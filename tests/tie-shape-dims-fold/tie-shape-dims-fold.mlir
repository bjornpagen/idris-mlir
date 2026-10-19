// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns-argument=@dynamic:1,returns=@static:4,returns-argument=@tied:1,returns-argument=@buffer:1 -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --canonicalize --idr-expect=holds=returns-argument=@untied:1 -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=UNTIED < %t.err
// An array tied to sizes has those sizes as its dimensions: the dimension
// of a tied tensor or buffer at a dynamic dimension folds to the size it
// was tied to, and at a static one to the constant of its type, through
// the dialect's canonicalization of shaped results. So a size Idris proved
// equal across a call is the same value on both sides, and no dimension is
// read at run time. An array tied to nothing keeps its dimension a read
// (@untied). The patterns converge (the first RUN line).
// UNTIED: expected returns-argument: {{.*}}@untied
idr.program @"dims-fold" root(@root) stage(first) {
  idr.func @dynamic(%x: tensor<?xi64>, %n: index) -> index {
    %y = idr.tie_shape %x dims(%n) : tensor<?xi64>
    %c0 = arith.constant 0 : index
    %d = tensor.dim %y, %c0 : tensor<?xi64>
    return %d : index
  }
  idr.func @static(%x: tensor<4x?xi64>, %m: index) -> index {
    %y = idr.tie_shape %x dims(%m) : tensor<4x?xi64>
    %c0 = arith.constant 0 : index
    %d0 = tensor.dim %y, %c0 : tensor<4x?xi64>
    return %d0 : index
  }
  idr.func @tied(%x: tensor<4x?xi64>, %m: index) -> index {
    %y = idr.tie_shape %x dims(%m) : tensor<4x?xi64>
    %c1 = arith.constant 1 : index
    %d1 = tensor.dim %y, %c1 : tensor<4x?xi64>
    return %d1 : index
  }
  idr.func @untied(%x: tensor<?xi64>, %n: index) -> index {
    %c0 = arith.constant 0 : index
    %d = tensor.dim %x, %c0 : tensor<?xi64>
    return %d : index
  }
  idr.func @buffer(%b: memref<?xf64>, %k: index) -> index {
    %y = idr.tie_shape %b dims(%k) : memref<?xf64>
    %c0 = arith.constant 0 : index
    %d = memref.dim %y, %c0 : memref<?xf64>
    return %d : index
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
