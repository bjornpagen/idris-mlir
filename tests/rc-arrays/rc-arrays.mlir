// RUN: idris-mlir-opt %s --idr-rc -o %t.owned.mlir
// RUN: %differential %s %t.owned.mlir
// An array a world orders is a counted value, memref<?xE, #idr.world>: a
// new one is owned (never exclusive: its elements are reached through
// it), and its fill moves in with its reference, exclusive or not. An
// element read takes a reference of its own, which its reader consumes or
// drops; a value set moves into the array. The array itself is only read
// by get and set, so a function that does only that borrows it (a plain
// parameter). Each index is checked, as the frontend checks one, before
// the op it guards. The input byte sets the array's length, 0 to 3, and the
// index read and written, 0 to 4, so the empty array, the last element and
// the indices past the end (the bounds crash) are all run, and on every
// one the program means what it meant before counting and leaves no cell
// live when it returns.

!Opt = !idr.data<"Opt">
#types = #idr.types<
  "Opt" = plain [@None(), @Some(!idr.str)]
>
idr.program @arrays root(@root) stage(first) types #types {
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c, %w0 = idr.io.get_byte %w
    %b = arith.extui %c : i32 to i64
    %c4 = arith.constant 4 : i64
    %c5 = arith.constant 5 : i64
    %n = arith.remui %b, %c4 : i64
    %q = arith.divui %b, %c4 : i64
    %i = arith.remui %q, %c5 : i64
    %s = idr.constant !idr.str "s"
    %t = idr.constant !idr.str "two"
    %a, %w1 = idr.call @make(%n, %s, %w0) : (i64, !idr.str, !idr.world) -> (memref<?x!Opt, #idr.world>, !idr.world)
    %v, %w2 = idr.call @fetch(%a, %i, %w1) : (memref<?x!Opt, #idr.world>, i64, !idr.world) -> (!Opt, !idr.world)
    %w3 = idr.call @store(%a, %t, %i, %w2) : (memref<?x!Opt, #idr.world>, !idr.str, i64, !idr.world) -> !idr.world
    %w4 = idr.call @unused(%a, %i, %w3) : (memref<?x!Opt, #idr.world>, i64, !idr.world) -> !idr.world
    %u, %w5 = idr.call @fetch(%a, %i, %w4) : (memref<?x!Opt, #idr.world>, i64, !idr.world) -> (!Opt, !idr.world)
    %lv = idr.call @len(%v) : (!Opt) -> i64
    %lu = idr.call @len(%u) : (!Opt) -> i64
    %w6 = idr.io.put_sint %lv, %w5 : i64
    %w7 = idr.io.put_sint %lu, %w6 : i64
    return %w7 : !idr.world
  }
  idr.func @len(%v: !Opt) -> i64 {
    %r = idr.match %v : !Opt -> (i64) {
    case @None() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @Some(%x: !idr.str) {
      %l = idr.str.length %x
      idr.yield %l : i64
    }
    }
    return %r : i64
  }
  idr.func @make(%n: i64, %s: !idr.str, %w: !idr.world) -> (memref<?x!Opt, #idr.world>, !idr.world) {
    %x = idr.con !Opt @Some(%s : !idr.str)
    %a, %w1 = idr.array.new [%n], %x, %w : !Opt -> memref<?x!Opt, #idr.world>
    return %a, %w1 : memref<?x!Opt, #idr.world>, !idr.world
  }
  idr.func @fetch(%a: memref<?x!Opt, #idr.world>, %i: i64, %w: !idr.world) -> (!Opt, !idr.world) {
    %j = idr.check.in_bounds %i, %a, "array index out of bounds" : memref<?x!Opt, #idr.world>
    %v, %w1 = idr.array.get %a[%j], %w : memref<?x!Opt, #idr.world> -> !Opt
    return %v, %w1 : !Opt, !idr.world
  }
  idr.func @store(%a: memref<?x!Opt, #idr.world>, %s: !idr.str, %i: i64, %w: !idr.world) -> !idr.world {
    %y = idr.con !Opt @Some(%s : !idr.str)
    %j = idr.check.in_bounds %i, %a, "array index out of bounds" : memref<?x!Opt, #idr.world>
    %w1 = idr.array.set %a[%j], %y, %w : memref<?x!Opt, #idr.world>, !Opt
    return %w1 : !idr.world
  }
  idr.func @unused(%a: memref<?x!Opt, #idr.world>, %i: i64, %w: !idr.world) -> !idr.world {
    %j = idr.check.in_bounds %i, %a, "array index out of bounds" : memref<?x!Opt, #idr.world>
    %v, %w1 = idr.array.get %a[%j], %w : memref<?x!Opt, #idr.world> -> !Opt
    return %w1 : !idr.world
  }
}
