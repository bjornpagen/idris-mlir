// RUN: idris-mlir-opt %s --idr-isolate > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-isolate > %t.again.mlir
// RUN: diff %t.mlir %t.again.mlir
// A body that uses a linear value from above becomes a closure or a
// suspension holding that value, whose one use must apply or force it
// where it is made, or enter it into a linear type (the verifier of
// idr.closure and idr.suspend). Where the lambda was applied where it
// was made, the closure keeps that use. Where it was not -- returned,
// as PrimIO.io_bind returns the action it builds over its linear
// halves -- the closure is entered into a linear type and used back
// out of it: the pair is its one use, and what reads the use reads an
// ordinary value. A suspension whose body uses a linear value is the
// same, entered and used where it is not forced where it is made.
// CHECK-LABEL: idr.func private @returned(
// CHECK: %[[C:.*]] = {{(idr\.)?}}closure @returned.lam{{[0-9]+}}(%{{.*}}) : (!idr.lin<i64>) -> !idr.fn<(i64) -> i64>
// CHECK-NEXT: %[[E:.*]] = idr.lin.enter %[[C]] : !idr.lin<!idr.fn<(i64) -> i64>>
// CHECK-NEXT: %[[F:.*]] = idr.lin.use %[[E]] : !idr.lin<!idr.fn<(i64) -> i64>>
// CHECK-NEXT: return %[[F]] : !idr.fn<(i64) -> i64>
// CHECK-LABEL: idr.func private @applied(
// CHECK: %[[C:.*]] = {{(idr\.)?}}closure @applied.lam{{[0-9]+}}(%{{.*}}) : (!idr.lin<i64>) -> !idr.fn<(i64) -> i64>
// CHECK-NEXT: %[[R:.*]] = {{(idr\.)?}}apply %[[C]](%{{.*}}) : !idr.fn<(i64) -> i64>
// CHECK-LABEL: idr.func private @suspended(
// CHECK: %[[S:.*]] = {{(idr\.)?}}suspend @suspended.delay{{[0-9]+}}(%{{.*}}) : (!idr.lin<i64>) -> !idr.lazy<i64>
// CHECK-NEXT: %[[E:.*]] = idr.lin.enter %[[S]] : !idr.lin<!idr.lazy<i64>>
// CHECK-NEXT: %[[T:.*]] = idr.lin.use %[[E]] : !idr.lin<!idr.lazy<i64>>
// CHECK-NEXT: return %[[T]] : !idr.lazy<i64>
module {
  idr.func private @returned(%x: !idr.lin<i64>) -> !idr.fn<(i64) -> (i64)> {
    %f = idr.lambda : !idr.fn<(i64) -> (i64)> {
    ^bb0(%y: i64):
      %v = idr.lin.use %x : !idr.lin<i64>
      %s = arith.addi %v, %y : i64
      idr.yield %s : i64
    }
    return %f : !idr.fn<(i64) -> (i64)>
  }
  idr.func private @applied(%x: !idr.lin<i64>, %y: i64) -> i64 {
    %f = idr.lambda : !idr.fn<(i64) -> (i64)> {
    ^bb0(%z: i64):
      %v = idr.lin.use %x : !idr.lin<i64>
      %s = arith.addi %v, %z : i64
      idr.yield %s : i64
    }
    %r = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  idr.func private @suspended(%x: !idr.lin<i64>) -> !idr.lazy<i64> {
    %t = idr.delay : !idr.lazy<i64> {
      %v = idr.lin.use %x : !idr.lin<i64>
      idr.yield %v : i64
    }
    return %t : !idr.lazy<i64>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %w1 = idr.io.put_int signed %z, %w : i64
    return %w1 : !idr.world
  }
}
