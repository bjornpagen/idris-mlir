// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns-argument=@back:0,returns-argument=@same:0 -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-structure-loops)),idr-expect{holds=structured-loops=@swap})' -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-structure-loops)))' -o %t.loops.mlir
// RUN: %differential %s %t.loops.mlir
// RUN: idris-mlir-opt %s --canonicalize -o %t.folded.mlir
// RUN: %differential %s %t.folded.mlir
// A transpose permutes an array's dimensions: an array moved, no element
// made. The identity permutation is the array itself, and a permutation
// followed by its inverse is the array again, so both fold to their
// input; any other is lowered to one linalg op. The root transposes
// arrays whose elements and, for @swap, sizes (1 to 3 by 1 to 3) the input
// byte sets, and prints elements read at their transposed places, the
// corners and an inner one: the lowered and the folded programs print what
// the module as written prints, on every byte.
idr.program @transpose root(@root) stage(first) types #idr.types<> {
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
  // The array whose element at (i, j, ...) is b + 100i + 10j + k.
  idr.func @grid2(%m: index, %n: index, %b: i64) -> tensor<?x?xi64> {
    %t = idr.tabulate [%m, %n] {
    ^bb0(%i: index, %j: index):
      %x = arith.index_cast %i : index to i64
      %y = arith.index_cast %j : index to i64
      %c100 = arith.constant 100 : i64
      %c10 = arith.constant 10 : i64
      %x1 = arith.muli %x, %c100 : i64
      %y1 = arith.muli %y, %c10 : i64
      %s = arith.addi %x1, %y1 : i64
      %e = arith.addi %s, %b : i64
      idr.array.yield %e : i64
    } : tensor<?x?xi64>
    return %t : tensor<?x?xi64>
  }
  idr.func @grid3(%b: i64) -> tensor<2x3x4xi64> {
    %t = idr.tabulate [] {
    ^bb0(%i: index, %j: index, %k: index):
      %x = arith.index_cast %i : index to i64
      %y = arith.index_cast %j : index to i64
      %z = arith.index_cast %k : index to i64
      %c100 = arith.constant 100 : i64
      %c10 = arith.constant 10 : i64
      %x1 = arith.muli %x, %c100 : i64
      %y1 = arith.muli %y, %c10 : i64
      %s = arith.addi %x1, %y1 : i64
      %s2 = arith.addi %s, %z : i64
      %e = arith.addi %s2, %b : i64
      idr.array.yield %e : i64
    } : tensor<2x3x4xi64>
    return %t : tensor<2x3x4xi64>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %b = arith.extui %ch : i32 to i64
    %c3 = arith.constant 3 : i64
    %one = arith.constant 1 : i64
    %mr = arith.remui %b, %c3 : i64
    %q = arith.divui %b, %c3 : i64
    %nr = arith.remui %q, %c3 : i64
    %m1 = arith.addi %mr, %one : i64
    %n1 = arith.addi %nr, %one : i64
    %m = arith.index_cast %m1 : i64 to index
    %n = arith.index_cast %n1 : i64 to index
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c2 = arith.constant 2 : index
    %ml = arith.subi %m, %c1 : index
    %nl = arith.subi %n, %c1 : index
    %g = idr.call @grid2(%m, %n, %b) : (index, index, i64) -> tensor<?x?xi64>
    %s = idr.call @swap(%g) : (tensor<?x?xi64>) -> tensor<?x?xi64>
    %e0 = tensor.extract %s[%c0, %c0] : tensor<?x?xi64>
    %e1 = tensor.extract %s[%nl, %ml] : tensor<?x?xi64>
    %e2 = tensor.extract %s[%nl, %c0] : tensor<?x?xi64>
    %e3 = tensor.extract %s[%c0, %ml] : tensor<?x?xi64>
    %w1 = idr.io.put_sint %e0, %w0 : i64
    %w2 = idr.io.put_sint %e1, %w1 : i64
    %w3 = idr.io.put_sint %e2, %w2 : i64
    %w4 = idr.io.put_sint %e3, %w3 : i64
    %t3 = idr.call @grid3(%b) : (i64) -> tensor<2x3x4xi64>
    %bk = idr.call @back(%t3) : (tensor<2x3x4xi64>) -> tensor<2x3x4xi64>
    %c3i = arith.constant 3 : index
    %f0 = tensor.extract %bk[%c1, %c2, %c3i] : tensor<2x3x4xi64>
    %f1 = tensor.extract %bk[%c0, %c1, %c2] : tensor<2x3x4xi64>
    %w5 = idr.io.put_sint %f0, %w4 : i64
    %w6 = idr.io.put_sint %f1, %w5 : i64
    %t2 = idr.tabulate [] {
    ^bb0(%i: index, %j: index):
      %x = arith.index_cast %i : index to i64
      %y = arith.index_cast %j : index to i64
      %c10 = arith.constant 10 : i64
      %x1 = arith.muli %x, %c10 : i64
      %s2 = arith.addi %x1, %y : i64
      %e = arith.addi %s2, %b : i64
      idr.array.yield %e : i64
    } : tensor<2x3xi64>
    %sm = idr.call @same(%t2) : (tensor<2x3xi64>) -> tensor<2x3xi64>
    %h0 = tensor.extract %sm[%c1, %c2] : tensor<2x3xi64>
    %w7 = idr.io.put_sint %h0, %w6 : i64
    return %w7 : !idr.world
  }
}
