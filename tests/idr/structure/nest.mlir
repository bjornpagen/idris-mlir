// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.func(idr-structure-loops))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=structured-loops=@table,structured-loops=@rowSums,structured-loops=@rowSumsF -o /dev/null
// RUN: FileCheck %s < %t.mlir
// NEEDS-ACCEPTANCE: the forms of the folds over a frame (C11 section 7, forms C and D), as idr-structure-loops writes them.
// A tabulation of rank 2 is a nest of two loops, the inner carrying what
// the outer carries, and it is one structured op of two parallel
// dimensions. A fold over each row whose combiner is one integer op, its
// read of the matrix at the row and the fold's index, is one op of a
// parallel and a reduction dimension. A float fold over each row keeps
// its combine in index order: a loop over the fold's index around one
// parallel op over the rows, which is what computes on lanes.
// CHECK-LABEL: idr.func private @table(
// CHECK: linalg.generic
// CHECK-SAME: iterator_types = ["parallel", "parallel"]
// CHECK: return
// CHECK-LABEL: idr.func private @rowSums(
// CHECK: linalg.generic
// CHECK-SAME: iterator_types = ["parallel", "reduction"]
// CHECK-NOT: tensor.extract
// CHECK: return
// CHECK-LABEL: idr.func private @rowSumsF(
// CHECK: scf.for
// CHECK: linalg.generic
// CHECK-SAME: iterator_types = ["parallel"]
// CHECK: return
module {
  idr.func private @table(%n: index, %m: index) -> tensor<?x?xi64> {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %e = tensor.empty(%n, %m) : tensor<?x?xi64>
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?x?xi64>) {
      %row = scf.for %j = %c0 to %m step %c1 iter_args(%b = %a) -> (tensor<?x?xi64>) {
        %x = arith.index_cast %i : index to i64
        %y = arith.index_cast %j : index to i64
        %p = arith.muli %x, %y : i64
        %b1 = tensor.insert %p into %b[%i, %j] : tensor<?x?xi64>
        scf.yield %b1 : tensor<?x?xi64>
      }
      scf.yield %row : tensor<?x?xi64>
    }
    return %r : tensor<?x?xi64>
  }
  idr.func private @rowSums(%t: tensor<?x?xi64>) -> tensor<?xi64> {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %zero = arith.constant 0 : i64
    %n = tensor.dim %t, %c0 : tensor<?x?xi64>
    %m = tensor.dim %t, %c1 : tensor<?x?xi64>
    %e = tensor.empty(%n) : tensor<?xi64>
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %s = scf.for %j = %c0 to %m step %c1 iter_args(%acc = %zero) -> (i64) {
        %x = tensor.extract %t[%i, %j] : tensor<?x?xi64>
        %u = arith.addi %acc, %x : i64
        scf.yield %u : i64
      }
      %a1 = tensor.insert %s into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    return %r : tensor<?xi64>
  }
  idr.func private @rowSumsF(%t: tensor<?x?xf64>) -> tensor<?xf64> {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %zero = arith.constant 0.0 : f64
    %n = tensor.dim %t, %c0 : tensor<?x?xf64>
    %m = tensor.dim %t, %c1 : tensor<?x?xf64>
    %e = tensor.empty(%n) : tensor<?xf64>
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?xf64>) {
      %s = scf.for %j = %c0 to %m step %c1 iter_args(%acc = %zero) -> (f64) {
        %x = tensor.extract %t[%i, %j] : tensor<?x?xf64>
        %u = arith.addf %acc, %x : f64
        scf.yield %u : f64
      }
      %a1 = tensor.insert %s into %a[%i] : tensor<?xf64>
      scf.yield %a1 : tensor<?xf64>
    }
    return %r : tensor<?xf64>
  }
}
