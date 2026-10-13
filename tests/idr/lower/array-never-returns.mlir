// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// A loop over an array whose body never returns ends in ub.unreachable,
// as a match region that crashes does: lowering keeps the crash at its
// index, in order, and yields poison after it, which no path reaches. It
// is the program's crash, never the compiler's error.
// CHECK-LABEL: func.func private @gen(
// CHECK: linalg.generic
// CHECK: llvm.call @idris_rt_crash
// CHECK: linalg.yield
// CHECK-NOT: idr.
// CHECK: return
// CHECK-LABEL: func.func private @rows(
// CHECK: linalg.generic
// CHECK: llvm.call @idris_rt_crash
// CHECK: linalg.yield
// CHECK-NOT: idr.
// CHECK: return
module attributes {idr.program} {
  idr.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 4 : i64
    %a, %w1 = idr.call @gen(%n, %w) : (i64, !idr.world) -> (memref<?xi64>, !idr.world)
    %b, %w2 = idr.call @rows(%n, %w1) : (i64, !idr.world) -> (memref<?xf64>, !idr.world)
    return %w2 : !idr.world
  }
  idr.func private @gen(%n: i64, %w: !idr.world) -> (memref<?xi64>, !idr.world) {
    %zero = arith.constant 0 : i64
    %a, %w1 = idr.array.generate %n, %zero, %w : i64 -> memref<?xi64> (%i: i64) {
      idr.crash "boom"
      ub.unreachable
    }
    return %a, %w1 : memref<?xi64>, !idr.world
  }
  idr.func private @rows(%n: i64, %w: !idr.world) -> (memref<?xf64>, !idr.world) {
    %zero = arith.constant 0.0 : f64
    %v, %w0 = idr.array.new [%n], %zero, %w : f64 -> memref<?xf64>
    %r, %w1 = idr.array.generate %n, %zero, %w0 : f64 -> memref<?xf64> (%i: i64) {
      %wf = idr.world.new
      %s, %w2 = idr.array.fold %v, %zero, %wf : memref<?xf64>, f64 -> f64 (%acc: f64, %x: f64, %j: i64) {
        idr.crash "boom"
        ub.unreachable
      }
      idr.yield %s : f64
    }
    return %r, %w1 : memref<?xf64>, !idr.world
  }
}
