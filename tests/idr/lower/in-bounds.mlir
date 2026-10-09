// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// An access is tested by its guard alone. One whose guard a proof removed
// lowers with no comparison against the length and no crash; one that
// keeps its guard has both, once, before the access.
// CHECK-LABEL: func.func private @proven(
// CHECK-NOT: arith.cmpi
// CHECK-NOT: idris_rt_crash
// CHECK: return
// CHECK-LABEL: func.func private @checked(
// CHECK: arith.cmpi uge
// CHECK: llvm.call @idris_rt_crash(
// CHECK-NOT: idris_rt_crash
// CHECK: return
module attributes {idr.program} {
  func.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 3 : i64
    %i = arith.constant 0 : i64
    %o, %w0 = idr.array.new %n, %i, %w : i64 -> !idr.own<memref<?xi64>>
    %a = idr.borrow %o : !idr.own<memref<?xi64>>
    %w1 = func.call @proven(%a, %i, %w0) : (memref<?xi64>, i64, !idr.world) -> !idr.world
    %w2 = func.call @checked(%a, %i, %w1) : (memref<?xi64>, i64, !idr.world) -> !idr.world
    idr.drop %o : !idr.own<memref<?xi64>>
    return %w2 : !idr.world
  }
  func.func private @proven(%a: memref<?xi64>, %i: i64, %w: !idr.world) -> !idr.world {
    %v, %w1 = idr.array.get %a[%i], %w : memref<?xi64> -> i64
    %w2 = idr.array.set %a[%i], %v, %w1 : memref<?xi64>, i64
    return %w2 : !idr.world
  }
  func.func private @checked(%a: memref<?xi64>, %i: i64, %w: !idr.world) -> !idr.world {
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xi64>
    %n = arith.index_cast %d : index to i64
    %j = idr.check.in_bounds %i, %n, "array index out of bounds"
    %v, %w1 = idr.array.get %a[%j], %w : memref<?xi64> -> i64
    return %w1 : !idr.world
  }
}
