// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// The dimension of a new array is the size it was made with, clamped at 0
// (a negative size makes an empty array): memref.dim of idr.array.new
// folds, as upstream folds the dimension of memref.alloc, so a program's
// own test of the size meets the value the bounds check compares against.

// A size the program computes: the dimension is that size at least 0, and
// no memref.dim is left.
// CHECK-LABEL: func.func @of_size(
// CHECK-SAME: %[[N:.*]]: i64, %{{.*}}: !idr.world)
// CHECK-NOT: memref.dim
// CHECK: %[[L:.*]] = arith.maxsi %[[N]], %{{.*}} : i64
// CHECK-NOT: memref.dim
// CHECK: return %[[L]]
func.func @of_size(%n: i64, %w: !idr.world) -> i64 {
  %fill = arith.constant 7 : i64
  %a, %w1 = idr.array.new %n, %fill, %w : i64 -> memref<?xi64>
  %c0 = arith.constant 0 : index
  %d = memref.dim %a, %c0 : memref<?xi64>
  %len = arith.index_cast %d : index to i64
  return %len : i64
}

// A constant size: the dimension is a constant.
// CHECK-LABEL: func.func @of_constant(
// CHECK: %[[C:.*]] = arith.constant 5 : i64
// CHECK-NOT: memref.dim
// CHECK: return %[[C]]
func.func @of_constant(%w: !idr.world) -> i64 {
  %n = arith.constant 5 : i64
  %fill = arith.constant 7 : i64
  %a, %w1 = idr.array.new %n, %fill, %w : i64 -> memref<?xi64>
  %c0 = arith.constant 0 : index
  %d = memref.dim %a, %c0 : memref<?xi64>
  %len = arith.index_cast %d : index to i64
  return %len : i64
}

// A negative constant size: an empty array.
// CHECK-LABEL: func.func @of_negative(
// CHECK: %[[C:.*]] = arith.constant 0 : i64
// CHECK-NOT: memref.dim
// CHECK: return %[[C]]
func.func @of_negative(%w: !idr.world) -> i64 {
  %n = arith.constant -3 : i64
  %fill = arith.constant 7 : i64
  %a, %w1 = idr.array.new %n, %fill, %w : i64 -> memref<?xi64>
  %c0 = arith.constant 0 : index
  %d = memref.dim %a, %c0 : memref<?xi64>
  %len = arith.index_cast %d : index to i64
  return %len : i64
}

// An array from elsewhere has a dimension nothing here knows: the read
// stays for the lowering.
// CHECK-LABEL: func.func @of_argument(
// CHECK: memref.dim
func.func @of_argument(%a: memref<?xi64>) -> i64 {
  %c0 = arith.constant 0 : index
  %d = memref.dim %a, %c0 : memref<?xi64>
  %len = arith.index_cast %d : index to i64
  return %len : i64
}
