// RUN: idris-mlir-opt %s --idr-target=cpu=apple-m1 --idr-lower --idr-vectorize --idr-expect=holds=vectorized -o /dev/null
// RUN: idris-mlir-opt %s --idr-target=cpu=apple-m1 --idr-lower --idr-vectorize --canonicalize --cse | FileCheck %s
// RUN: idris-mlir-opt %s --idr-target=cpu=apple-m1 --idr-pipeline | FileCheck %s --check-prefix=LLVM
// The arm64 counterpart of rows-x86-64: the same loop over an array with a
// parallel dimension, on the CPU this arm64 test names (apple-m1), whose
// cache line and vector width are one 128-bit NEON register: four lanes of
// a 32-bit element, two of a 64-bit one, so the f64 row loop steps by two
// lanes. A row reduction keeps its reduction dimension at one lane and
// still adds each lane's row in index order. The whole pipeline reaches
// the LLVM dialect with vector loads and stores and no vector or affine op
// left.
// CHECK-LABEL: func.func private @squares(
// CHECK: scf.for %{{.*}} = %{{.*}} to %{{.*}} step %[[C2:.*]] {
// CHECK: vector.transfer_write %{{.*}} : vector<2xi64>
// CHECK-NOT: linalg.generic
// CHECK: return
// CHECK-LABEL: func.func private @total(
// CHECK-NOT: vector.
// CHECK: linalg.generic
// CHECK-SAME: iterator_types = ["reduction"]
// CHECK: return
// CHECK-LABEL: func.func private @rows(
// CHECK-NOT: vector.multi_reduction
// CHECK-NOT: vector.reduction
// CHECK-NOT: vector<2x1x
// CHECK: scf.for
// CHECK: scf.for
// CHECK: vector.transfer_read {{.*}} : memref<{{.*}}f64{{.*}}>, vector<2xf64>
// CHECK: arith.divf %{{.*}} : vector<2xf64>
// CHECK: arith.addf %{{.*}} : vector<2xf64>
// CHECK: vector.transfer_write %{{.*}} : vector<2xf64>
// CHECK-NOT: vector.multi_reduction
// CHECK-NOT: vector.reduction
// CHECK-NOT: vector<2x1x
// CHECK: return
// LLVM-NOT: vector.
// LLVM-NOT: affine.
// LLVM-NOT: linalg.
// LLVM: llvm.store %{{.*}} : vector<2xf64>, !llvm.ptr
// LLVM-NOT: vector.
// LLVM-NOT: affine.
// LLVM-NOT: linalg.
module attributes {idr.program} {
  func.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 7 : i64
    %a, %w1 = func.call @squares(%n, %w) : (i64, !idr.world) -> (memref<?xi64>, !idr.world)
    %s, %w2 = func.call @total(%a, %w1) : (memref<?xi64>, !idr.world) -> (i64, !idr.world)
    %v, %w3 = func.call @ones(%n, %w2) : (i64, !idr.world) -> (memref<?xf64>, !idr.world)
    %r, %w4 = func.call @rows(%n, %v, %w3) : (i64, memref<?xf64>, !idr.world) -> (memref<?xf64>, !idr.world)
    return %w4 : !idr.world
  }
  func.func private @squares(%n: i64, %w: !idr.world) -> (memref<?xi64>, !idr.world) {
    %zero = arith.constant 0 : i64
    %a, %w1 = idr.array.generate %n, %zero, %w : i64 -> memref<?xi64> (%i: i64) {
      %sq = arith.muli %i, %i : i64
      idr.yield %sq : i64
    }
    return %a, %w1 : memref<?xi64>, !idr.world
  }
  func.func private @total(%a: memref<?xi64>, %w: !idr.world) -> (i64, !idr.world) {
    %zero = arith.constant 0 : i64
    %s, %w1 = idr.array.fold %a, %zero, %w : memref<?xi64>, i64 -> i64 (%acc: i64, %x: i64, %i: i64) {
      %t = arith.addi %acc, %x : i64
      idr.yield %t : i64
    }
    return %s, %w1 : i64, !idr.world
  }
  func.func private @ones(%n: i64, %w: !idr.world) -> (memref<?xf64>, !idr.world) {
    %one = arith.constant 1.0 : f64
    %a, %w1 = idr.array.new %n, %one, %w : f64 -> memref<?xf64>
    return %a, %w1 : memref<?xf64>, !idr.world
  }
  func.func private @rows(%n: i64, %v: memref<?xf64>, %w: !idr.world) -> (memref<?xf64>, !idr.world) {
    %zero = arith.constant 0.0 : f64
    %one = arith.constant 1 : i64
    %r, %w1 = idr.array.generate %n, %zero, %w : f64 -> memref<?xf64> (%i: i64) {
      %w0 = idr.world.new
      %i1 = arith.addi %i, %one : i64
      %s, %w2 = idr.array.fold %v, %zero, %w0 : memref<?xf64>, f64 -> f64 (%acc: f64, %x: f64, %j: i64) {
        %ij = arith.addi %i1, %j : i64
        %d = arith.sitofp %ij : i64 to f64
        %m = arith.divf %x, %d : f64
        %t = arith.addf %acc, %m : f64
        idr.yield %t : f64
      }
      idr.yield %s : f64
    }
    return %r, %w1 : memref<?xf64>, !idr.world
  }
}
