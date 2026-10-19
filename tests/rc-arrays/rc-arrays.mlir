// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o /dev/null
// An array a world orders is a counted value, memref<?xE, #idr.world>: a
// new one is owned (never exclusive: its elements are reached through
// it), and its fill moves in with its reference, exclusive or not. An
// element read takes a reference of its own, which its reader consumes or
// drops; a value set moves into the array. The array itself is only read
// by get and set, so a function that does only that borrows it (a plain
// parameter).

!Opt = !idr.data<"Opt", plain [@None(), @Some(!idr.str)]>
idr.program @arrays root(@root) stage(first) {
  idr.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 3 : i64
    %i = arith.constant 1 : i64
    %s = idr.constant !idr.str "s"
    %a, %w1 = idr.call @make(%n, %s, %w) : (i64, !idr.str, !idr.world) -> (memref<?x!Opt, #idr.world>, !idr.world)
    %v, %w2 = idr.call @read(%a, %i, %w1) : (memref<?x!Opt, #idr.world>, i64, !idr.world) -> (!Opt, !idr.world)
    %w3 = idr.call @write(%a, %s, %i, %w2) : (memref<?x!Opt, #idr.world>, !idr.str, i64, !idr.world) -> !idr.world
    %w4 = idr.call @unused(%a, %i, %w3) : (memref<?x!Opt, #idr.world>, i64, !idr.world) -> !idr.world
    return %w4 : !idr.world
  }
  idr.func @make(%n: i64, %s: !idr.str, %w: !idr.world) -> (memref<?x!Opt, #idr.world>, !idr.world) {
    %x = idr.con !Opt @Some(%s : !idr.str)
    %a, %w1 = idr.array.new [%n], %x, %w : !Opt -> memref<?x!Opt, #idr.world>
    return %a, %w1 : memref<?x!Opt, #idr.world>, !idr.world
  }
  idr.func @read(%a: memref<?x!Opt, #idr.world>, %i: i64, %w: !idr.world) -> (!Opt, !idr.world) {
    %v, %w1 = idr.array.get %a[%i], %w : memref<?x!Opt, #idr.world> -> !Opt
    return %v, %w1 : !Opt, !idr.world
  }
  idr.func @write(%a: memref<?x!Opt, #idr.world>, %s: !idr.str, %i: i64, %w: !idr.world) -> !idr.world {
    %y = idr.con !Opt @Some(%s : !idr.str)
    %w1 = idr.array.set %a[%i], %y, %w : memref<?x!Opt, #idr.world>, !Opt
    return %w1 : !idr.world
  }
  idr.func @unused(%a: memref<?x!Opt, #idr.world>, %i: i64, %w: !idr.world) -> !idr.world {
    %v, %w1 = idr.array.get %a[%i], %w : memref<?x!Opt, #idr.world> -> !Opt
    return %w1 : !idr.world
  }
}
