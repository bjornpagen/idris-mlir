// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns-argument=@back:0,returns-argument=@same:0 -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-structure-loops)),idr-expect{holds=structured-loops=@swap})' -o /dev/null
// A transpose permutes an array's dimensions: an array moved, no element
// made. The identity permutation is the array itself, and a permutation
// followed by its inverse is the array again, so both fold to their
// input; any other is lowered to one linalg op.
idr.program @transpose root(@root) stage(first) {
  idr.func @swap(%x: tensor<?x?xi64>) -> tensor<?x?xi64> {
    %t = idr.transpose %x permutation = [1, 0] : tensor<?x?xi64> -> tensor<?x?xi64>
    return %t : tensor<?x?xi64>
  }
  idr.func @back(%x: tensor<2x3x4xi64>) -> tensor<2x3x4xi64> {
    %t = idr.transpose %x permutation = [2, 0, 1] : tensor<2x3x4xi64> -> tensor<4x2x3xi64>
    %u = idr.transpose %t permutation = [1, 2, 0] : tensor<4x2x3xi64> -> tensor<2x3x4xi64>
    return %u : tensor<2x3x4xi64>
  }
  idr.func @same(%x: tensor<2x3xi64>) -> tensor<2x3xi64> {
    %t = idr.transpose %x permutation = [0, 1] : tensor<2x3xi64> -> tensor<2x3xi64>
    return %t : tensor<2x3xi64>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
