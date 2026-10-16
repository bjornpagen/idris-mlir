// NEEDS-ACCEPTANCE: that dims-known holds of the extent of an array a function is given and fails once at the memref.dim of the array @made made.
// RUN: idris-mlir-opt %s --idr-expect=holds=dims-known=@given -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=dims-known=@made -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 1
// A function asks the extent only of an array it was given (@given); the
// extent of one it made is the size it made it with, so asking it of the
// array (@made) is a read the fold of the question would have removed.
// CHECK-DAG: error: expected dims-known: {{.*}} in @made asks an extent of what {{.*}} made
idr.program @"dims-known" root(@root) stage(first) {
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
    %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
    %len = arith.index_cast %d : index to i64
    return %len, %w1 : i64, !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
