// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=counts-nothing=@growLeft,reuses-in-place=@growLeft,tests-nothing=@growLeft,counts-nothing=@growLeft2,reuses-in-place=@growLeft2 -o /dev/null
// NEEDS-ACCEPTANCE: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer.
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// A constructor rebuilt in the cell of the one taken apart, with one field
// changed: the fields given back as the take gave them are in the cell
// already, with the reference it held all along. In the owned stage they
// move out of the take and into the reuse, so nothing is counted for them
// (counts-nothing). Where the box may be shared, the take tests it
// and the token may be null.
!T = !idr.data<"T", plain [@Leaf(), @Node(!idr.box<!idr.data<"T">>, i64, !idr.box<!idr.data<"T">>)]>
!P = !idr.data<"P", plain [@None(), @Pair(!idr.box<!T>, !idr.box<!T>, i64)]>
idr.program @"kept-fields" root(@root) stage(first) {
  // A cell of @Pair is as large as one of @Node.
  idr.func @wrap(%x: !idr.box<!T>) -> !idr.box<!T> {
    %leaf = idr.constant #idr.con<!T, @Leaf, []> : !idr.box<!T>
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
      %none = idr.constant #idr.con<!P, @None, []> : !idr.box<!P>
      idr.yield %none : !idr.box<!P>
    }
    case @Node(%l: !idr.box<!T>, %k: i64, %rt: !idr.box<!T>) {
      %p = idr.con !idr.box<!P> @Pair(%l : !idr.box<!T>, %rt : !idr.box<!T>, %k : i64)
      idr.yield %p : !idr.box<!P>
    }
    }
    return %r : !idr.box<!P>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %x = arith.constant 7 : i64
    %leaf = idr.constant #idr.con<!T, @Leaf, []> : !idr.box<!T>
    %t = idr.con !idr.box<!T> @Node(%leaf : !idr.box<!T>, %x : i64, %leaf : !idr.box<!T>)
    %g = idr.call @growLeft(%t) : (!idr.box<!T>) -> !idr.box<!T>
    %m = idr.con !idr.box<!T> @Node(%leaf : !idr.box<!T>, %x : i64, %leaf : !idr.box<!T>)
    %h = idr.call @growLeft2(%m) : (!idr.box<!T>) -> !idr.box<!T>
    %a = idr.tag %m : !idr.box<!T>
    %s = idr.con !idr.box<!T> @Node(%leaf : !idr.box<!T>, %x : i64, %leaf : !idr.box<!T>)
    %p = idr.call @swap(%s) : (!idr.box<!T>) -> !idr.box<!P>
    %b = idr.tag %g : !idr.box<!T>
    %c = idr.tag %h : !idr.box<!T>
    %d = idr.tag %p : !idr.box<!P>
    %ab = arith.addi %a, %b : i64
    %cd = arith.addi %c, %d : i64
    %sum = arith.addi %ab, %cd : i64
    %w2 = idr.io.put_int signed %sum, %w : i64
    return %w2 : !idr.world
  }
}
