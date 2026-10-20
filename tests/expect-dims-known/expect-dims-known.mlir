// RUN: idris-mlir-opt %s --idr-expect=holds=dims-known=@given,dims-known=@beside -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=dims-known=@made -verify-diagnostics -o /dev/null
// A function asks the extent only of an array it was given (@given); the
// extent of one it made is the size it made it with, so asking it of the
// array (@made) is a read the fold of the question would have removed. A
// function that makes an array and asks the extent of another it was given
// asks nothing it knows (@beside).
idr.program @"dims-known" root(@root) stage(first) types #idr.types<> {
  idr.func @given(%a: memref<?xi64, #idr.world>) -> i64 {
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
    %len = arith.index_cast %d : index to i64
    return %len : i64
  }
  idr.func @made(%n: i64, %w: !idr.world) -> (i64, !idr.world) {
    %fill = arith.constant 7 : i64
    %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
    %c0 = arith.constant 0 : index
    // expected-error @below {{expected dims-known: }}
    %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
    %len = arith.index_cast %d : index to i64
    return %len, %w1 : i64, !idr.world
  }
  idr.func @beside(%a: memref<?xi64, #idr.world>, %n: i64, %w: !idr.world) -> (i64, memref<?xi64, #idr.world>, !idr.world) {
    %fill = arith.constant 7 : i64
    %b, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
    %len = arith.index_cast %d : index to i64
    return %len, %b, %w1 : i64, memref<?xi64, #idr.world>, !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
