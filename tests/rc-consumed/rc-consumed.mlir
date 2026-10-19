// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=resets-unshared -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=reuses-every-cell=@ins -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc -o %t.owned.mlir
// RUN: %differential %s %t.owned.mlir
// A box whose last use in a region consumes it dies in that use: no cell of
// it is left to reuse after the use. Here `ins` looks at the right subtree
// and then gives it to the recursive call. A take after the call would
// keep a second reference alive across it, and the callee would find the
// cell shared and copy it at every level. So every cell tested for reuse
// is one its function never gives a second reference, and the node taken
// apart is reused by the node built after the call. The input byte is how
// many keys go in, 0 to 5, from the byte itself up: from the third on the
// right subtree is a node, so each of ins's three paths is run, and each
// run prints the tree's sum, as it did before counting, and leaves no cell
// live.
!T = !idr.data<"T", plain [@L(), @N(!idr.box<!idr.data<"T">>, i64, !idr.box<!idr.data<"T">>)]>
idr.program @consumed root(@root) stage(first) {
  idr.func @ins(%t: !idr.box<!T>, %k: i64) -> !idr.box<!T> {
    %leaf = idr.constant !idr.box<!T> #idr.con<!T, @L, []>
    %r = idr.match %t : !idr.box<!T> -> (!idr.box<!T>) {
    case @L() {
      %n = idr.con !idr.box<!T> @N(%leaf : !idr.box<!T>, %k : i64, %leaf : !idr.box<!T>)
      idr.yield %n : !idr.box<!T>
    }
    case @N(%l: !idr.box<!T>, %x: i64, %rt: !idr.box<!T>) {
      %s = idr.match %rt : !idr.box<!T> -> (!idr.box<!T>) {
      case @L() {
        %r2 = idr.call @ins(%rt, %k) : (!idr.box<!T>, i64) -> !idr.box<!T>
        %n = idr.con !idr.box<!T> @N(%l : !idr.box<!T>, %x : i64, %r2 : !idr.box<!T>)
        idr.yield %n : !idr.box<!T>
      }
      case @N(%a: !idr.box<!T>, %y: i64, %b: !idr.box<!T>) {
        %r2 = idr.call @ins(%rt, %k) : (!idr.box<!T>, i64) -> !idr.box<!T>
        %n = idr.con !idr.box<!T> @N(%r2 : !idr.box<!T>, %y : i64, %l : !idr.box<!T>)
        idr.yield %n : !idr.box<!T>
      }
      }
      idr.yield %s : !idr.box<!T>
    }
    }
    return %r : !idr.box<!T>
  }
  // k keys, from key up, put in t one after another.
  idr.func @insMany(%t: !idr.box<!T>, %k: i64, %key: i64) -> !idr.box<!T> {
    %r = idr.match_lit %k : i64 -> (!idr.box<!T>) {
    case 0 {
      idr.yield %t : !idr.box<!T>
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %t1 = idr.call @ins(%t, %key) : (!idr.box<!T>, i64) -> !idr.box<!T>
      %k1 = arith.subi %k, %one : i64
      %key1 = arith.addi %key, %one : i64
      %t2 = idr.call @insMany(%t1, %k1, %key1) : (!idr.box<!T>, i64, i64) -> !idr.box<!T>
      idr.yield %t2 : !idr.box<!T>
    }
    }
    return %r : !idr.box<!T>
  }
  // The sum of the keys, each weighted by its depth plus one.
  idr.func @total(%t: !idr.box<!T>, %depth: i64) -> i64 {
    %r = idr.match %t : !idr.box<!T> -> (i64) {
    case @L() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @N(%l: !idr.box<!T>, %x: i64, %rt: !idr.box<!T>) {
      %one = arith.constant 1 : i64
      %d1 = arith.addi %depth, %one : i64
      %sl = idr.call @total(%l, %d1) : (!idr.box<!T>, i64) -> i64
      %sr = idr.call @total(%rt, %d1) : (!idr.box<!T>, i64) -> i64
      %xd = arith.muli %x, %d1 : i64
      %s1 = arith.addi %sl, %sr : i64
      %s = arith.addi %s1, %xd : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %key = arith.extui %c : i32 to i64
    %c6 = arith.constant 6 : i64
    %z = arith.constant 0 : i64
    %k = arith.remui %key, %c6 : i64
    %leaf = idr.constant !idr.box<!T> #idr.con<!T, @L, []>
    %t = idr.call @insMany(%leaf, %k, %key) : (!idr.box<!T>, i64, i64) -> !idr.box<!T>
    %s = idr.call @total(%t, %z) : (!idr.box<!T>, i64) -> i64
    %w2 = idr.io.put_sint %s, %w1 : i64
    return %w2 : !idr.world
  }
}
