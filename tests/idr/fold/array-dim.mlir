// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=dims-known=@of_size,returns=@of_size:_,returns=@of_constant:5,returns=@of_negative:0,returns=@of_argument:_ -o /dev/null
// The dimension of a new array is the size it was made with, clamped at 0
// (a negative size makes an empty array): memref.dim of idr.array.new
// folds, as upstream folds the dimension of memref.alloc, so a program's
// own test of the size meets the value the bounds check compares against.

// A size the program computes: the dimension is that size at least 0, and
// no memref.dim is left.
idr.program @"array-dim" root(@of_constant) stage(first) {
  idr.func @of_size(%n: i64, %w: !idr.world) -> i64 {
    %fill = arith.constant 7 : i64
    %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
    %len = arith.index_cast %d : index to i64
    return %len : i64
  }

  // A constant size: the dimension is a constant.
  idr.func @of_constant(%w: !idr.world) -> i64 {
    %n = arith.constant 5 : i64
    %fill = arith.constant 7 : i64
    %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
    %len = arith.index_cast %d : index to i64
    return %len : i64
  }

  // A negative constant size: an empty array.
  idr.func @of_negative(%w: !idr.world) -> i64 {
    %n = arith.constant -3 : i64
    %fill = arith.constant 7 : i64
    %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
    %len = arith.index_cast %d : index to i64
    return %len : i64
  }

  // An array from elsewhere has a dimension nothing here knows: the read
  // stays for the lowering.
  idr.func @of_argument(%a: memref<?xi64, #idr.world>) -> i64 {
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
    %len = arith.index_cast %d : index to i64
    return %len : i64
  }
}
