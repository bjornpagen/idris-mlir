// RUN: idris-mlir-opt %s -split-input-file --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir -split-input-file --idr-expect=holds=no-closures -o /dev/null
// NEEDS-ACCEPTANCE: the printed dispatches, as C06 makes them.
// An evaluated suspension holds its value in the forced state of its cell,
// which every cell of its lazy type shares: the value's labels flow into
// that anchor, and every force of the type reads them back. So a closure
// or a suspension an evaluated suspension holds converts like any other:
// the force gives a constructor of the closure's sum, and the apply of it
// is a dispatch that calls the label.
// CHECK-LABEL: idr.func @Main.main(
// CHECK: case @add(
// CHECK: call @add(
idr.program @"evaluated-keyed" root(@Main.main) stage(higher) {
  idr.func @add(%k: i64, %x: i64) -> i64 attributes {total} {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %f = idr.closure @add(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %t = idr.delay %f : !idr.fn<(i64) -> (i64)> -> !idr.lazy<!idr.fn<(i64) -> (i64)>>
    %g = idr.force %t : !idr.lazy<!idr.fn<(i64) -> (i64)>> -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %g(%n) : !idr.fn<(i64) -> (i64)>
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}

// -----

// A suspension held by an evaluated one: the inner cell's labels flow into
// the outer cell's forced state, and the force of the forced value is a
// force of a cell of the inner memo sum, whose suspension is @one.
// CHECK-LABEL: idr.func @Main.main(
// CHECK: force
// CHECK: force
idr.program @"evaluated-keyed" root(@Main.main) stage(higher) {
  idr.func @one() -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %s = idr.suspend @one() : () -> !idr.lazy<i64>
    %t = idr.delay %s : !idr.lazy<i64> -> !idr.lazy<!idr.lazy<i64>>
    %u = idr.force %t : !idr.lazy<!idr.lazy<i64>> -> !idr.lazy<i64>
    %v = idr.force %u : !idr.lazy<i64> -> i64
    %w1 = idr.io.put_int signed %v, %w : i64
    return %w1 : !idr.world
  }
}
