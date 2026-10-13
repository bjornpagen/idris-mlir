// RUN: awk -f %s.awk %s > %t.mlir
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-simplify -o %t.out.mlir 2> %t.err
// RUN: FileCheck %s < %t.err
// A pass of a round that fails fails the simplify loop with its own error,
// and the loop adds none: its round budget did not run out. Here
// idr-specialize, in the first round, has no clone of @apply left: the
// module already holds as many as its budget allows, @apply.spec1 to
// @apply.spec1024, which the awk script beside this file writes where the
// comments below stand, each a clone of @apply at a closure of @add over its
// own constant, all of them called. @apply and its clones are no_inline, so
// that the inliner, which runs before it, leaves the call it would
// specialize and the clones it counts.
// CHECK-NOT: error:
// CHECK: error: unsupported (compile-time budget): specializing @apply made more than {{[0-9]+}} clones of it
// CHECK-NOT: error:
module attributes {idr.program} {
  idr.func private @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func private @apply(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {total, no_inline} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %y : i64
  }
  // clones
  idr.func private @use(%n: i64, %x: i64) -> i64 attributes {total} {
    %f = idr.closure @add(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.call @apply(%f, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %r0 = arith.extui %c : i32 to i64
    // calls
    %u = idr.call @use(%r0, %r1024) : (i64, i64) -> i64
    %w2 = idr.io.put_int signed %u, %w1 : i64
    return %w2 : !idr.world
  }
}
