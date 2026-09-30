// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=resets-unshared -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=reuses-every-cell=@ins -o /dev/null
// A box whose last use in a region consumes it dies in that use: no cell of
// it is left to reuse after the use. Here `ins` looks at the right subtree
// and then gives it to the recursive call. A take after the call would
// keep a second reference alive across it, and the callee would find the
// cell shared and copy it at every level. So every cell tested for reuse
// is one its function never gives a second reference, and the node taken
// apart is reused by the node built after the call.
module attributes {idr.program} {
  idr.data @T box {
    idr.ctor @L ()
    idr.ctor @N (!idr.box<@T>, i64, !idr.box<@T>)
  }
  func.func private @ins(%t: !idr.box<@T>, %k: i64) -> !idr.box<@T> {
    %leaf = idr.constant #idr.con<@T::@L, []> : !idr.box<@T>
    %r = idr.match %t : !idr.box<@T> -> (!idr.box<@T>) {
    case @L() {
      %n = idr.con @T::@N(%leaf, %k, %leaf) : (!idr.box<@T>, i64, !idr.box<@T>) -> !idr.box<@T>
      idr.yield %n : !idr.box<@T>
    }
    case @N(%l: !idr.box<@T>, %x: i64, %rt: !idr.box<@T>) {
      %s = idr.match %rt : !idr.box<@T> -> (!idr.box<@T>) {
      case @L() {
        %r2 = func.call @ins(%rt, %k) : (!idr.box<@T>, i64) -> !idr.box<@T>
        %n = idr.con @T::@N(%l, %x, %r2) : (!idr.box<@T>, i64, !idr.box<@T>) -> !idr.box<@T>
        idr.yield %n : !idr.box<@T>
      }
      case @N(%a: !idr.box<@T>, %y: i64, %b: !idr.box<@T>) {
        %r2 = func.call @ins(%rt, %k) : (!idr.box<@T>, i64) -> !idr.box<@T>
        %n = idr.con @T::@N(%r2, %y, %l) : (!idr.box<@T>, i64, !idr.box<@T>) -> !idr.box<@T>
        idr.yield %n : !idr.box<@T>
      }
      }
      idr.yield %s : !idr.box<@T>
    }
    }
    return %r : !idr.box<@T>
  }
  func.func @root(%w: !idr.world) -> !idr.world {
    %leaf = idr.constant #idr.con<@T::@L, []> : !idr.box<@T>
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %t1 = func.call @ins(%leaf, %c1) : (!idr.box<@T>, i64) -> !idr.box<@T>
    %t2 = func.call @ins(%t1, %c2) : (!idr.box<@T>, i64) -> !idr.box<@T>
    %s = idr.match %t2 : !idr.box<@T> -> (i64) {
    case @L() {
      idr.yield %c1 : i64
    }
    case @N(%l: !idr.box<@T>, %x: i64, %rt: !idr.box<@T>) {
      idr.yield %x : i64
    }
    }
    %w2 = idr.io.put_int signed %s, %w : i64
    return %w2 : !idr.world
  }
}
