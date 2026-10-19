// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=counts-nothing=@growLeft,reuses-in-place=@growLeft,tests-nothing=@growLeft,counts-nothing=@growLeft2,reuses-in-place=@growLeft2 -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc -o %t.owned.mlir
// RUN: %differential %s %t.owned.mlir
// A constructor rebuilt in the cell of the one taken apart, with one field
// changed: the fields given back as the take gave them are in the cell
// already, with the reference it held all along. In the owned stage they
// move out of the take and into the reuse, so nothing is counted for them
// (counts-nothing). Where the box may be shared, the take tests it
// and the token may be null. The input byte is the key and says which of
// the three trees are leaves, so each function runs on a leaf and on a
// node, and every run prints what it printed before counting and leaves no
// cell live.
!T = !idr.data<"T", plain [@Leaf(), @Node(!idr.box<!idr.data<"T">>, i64, !idr.box<!idr.data<"T">>)]>
!P = !idr.data<"P", plain [@None(), @Pair(!idr.box<!T>, !idr.box<!T>, i64)]>
idr.program @"kept-fields" root(@root) stage(first) {
  // A cell of @Pair is as large as one of @Node.
  idr.func @wrap(%x: !idr.box<!T>) -> !idr.box<!T> {
    %leaf = idr.constant !idr.box<!T> #idr.con<!T, @Leaf, []>
    %z = arith.constant 0 : i64
    %n = idr.con !idr.box<!T> @Node(%x : !idr.box<!T>, %z : i64, %leaf : !idr.box<!T>)
    return %n : !idr.box<!T>
  }
  // The left subtree changes; the key and the right subtree are kept.
  idr.func @growLeft(%t: !idr.box<!T>) -> !idr.box<!T> {
    %r = idr.match %t : !idr.box<!T> -> (!idr.box<!T>) {
    case @Leaf() {
      idr.yield %t : !idr.box<!T>
    }
    case @Node(%l: !idr.box<!T>, %k: i64, %rt: !idr.box<!T>) {
      %l2 = idr.call @wrap(%l) : (!idr.box<!T>) -> !idr.box<!T>
      %n = idr.con !idr.box<!T> @Node(%l2 : !idr.box<!T>, %k : i64, %rt : !idr.box<!T>)
      idr.yield %n : !idr.box<!T>
    }
    }
    return %r : !idr.box<!T>
  }
  // The same, on a tree its caller keeps a reference to.
  idr.func @growLeft2(%t: !idr.box<!T>) -> !idr.box<!T> {
    %r = idr.match %t : !idr.box<!T> -> (!idr.box<!T>) {
    case @Leaf() {
      idr.yield %t : !idr.box<!T>
    }
    case @Node(%l: !idr.box<!T>, %k: i64, %rt: !idr.box<!T>) {
      %l2 = idr.call @wrap(%l) : (!idr.box<!T>) -> !idr.box<!T>
      %n = idr.con !idr.box<!T> @Node(%l2 : !idr.box<!T>, %k : i64, %rt : !idr.box<!T>)
      idr.yield %n : !idr.box<!T>
    }
    }
    return %r : !idr.box<!T>
  }
  // Another constructor, of another type, in the node's cell.
  idr.func @swap(%t: !idr.box<!T>) -> !idr.box<!P> {
    %r = idr.match %t : !idr.box<!T> -> (!idr.box<!P>) {
    case @Leaf() {
      %none = idr.constant !idr.box<!P> #idr.con<!P, @None, []>
      idr.yield %none : !idr.box<!P>
    }
    case @Node(%l: !idr.box<!T>, %k: i64, %rt: !idr.box<!T>) {
      %p = idr.con !idr.box<!P> @Pair(%l : !idr.box<!T>, %rt : !idr.box<!T>, %k : i64)
      idr.yield %p : !idr.box<!P>
    }
    }
    return %r : !idr.box<!P>
  }
  // A leaf when which is 0, else a node of key x.
  idr.func @tree(%which: i64, %x: i64) -> !idr.box<!T> {
    %leaf = idr.constant !idr.box<!T> #idr.con<!T, @Leaf, []>
    %r = idr.match_lit %which : i64 -> (!idr.box<!T>) {
    case 0 {
      idr.yield %leaf : !idr.box<!T>
    }
    default(%d: i64) {
      %n = idr.con !idr.box<!T> @Node(%leaf : !idr.box<!T>, %x : i64, %leaf : !idr.box<!T>)
      idr.yield %n : !idr.box<!T>
    }
    }
    return %r : !idr.box<!T>
  }
  // The keys, each times its depth.
  idr.func @keys(%t: !idr.box<!T>, %depth: i64) -> i64 {
    %r = idr.match %t : !idr.box<!T> -> (i64) {
    case @Leaf() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @Node(%l: !idr.box<!T>, %k: i64, %rt: !idr.box<!T>) {
      %one = arith.constant 1 : i64
      %d1 = arith.addi %depth, %one : i64
      %sl = idr.call @keys(%l, %d1) : (!idr.box<!T>, i64) -> i64
      %sr = idr.call @keys(%rt, %d1) : (!idr.box<!T>, i64) -> i64
      %kd = arith.muli %k, %depth : i64
      %s1 = arith.addi %sl, %sr : i64
      %s = arith.addi %s1, %kd : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %x = arith.extui %ch : i32 to i64
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %c4 = arith.constant 4 : i64
    %one = arith.andi %x, %c1 : i64
    %two = arith.andi %x, %c2 : i64
    %four = arith.andi %x, %c4 : i64
    %t = idr.call @tree(%one, %x) : (i64, i64) -> !idr.box<!T>
    %g = idr.call @growLeft(%t) : (!idr.box<!T>) -> !idr.box<!T>
    %m = idr.call @tree(%two, %x) : (i64, i64) -> !idr.box<!T>
    %h = idr.call @growLeft2(%m) : (!idr.box<!T>) -> !idr.box<!T>
    %a = idr.tag %m : !idr.box<!T>
    %s = idr.call @tree(%four, %x) : (i64, i64) -> !idr.box<!T>
    %p = idr.call @swap(%s) : (!idr.box<!T>) -> !idr.box<!P>
    %b = idr.call @keys(%g, %c1) : (!idr.box<!T>, i64) -> i64
    %c = idr.call @keys(%h, %c2) : (!idr.box<!T>, i64) -> i64
    %d = idr.tag %p : !idr.box<!P>
    %w1 = idr.io.put_sint %a, %w0 : i64
    %w2 = idr.io.put_sint %b, %w1 : i64
    %w3 = idr.io.put_sint %c, %w2 : i64
    %w4 = idr.io.put_sint %d, %w3 : i64
    return %w4 : !idr.world
  }
}
