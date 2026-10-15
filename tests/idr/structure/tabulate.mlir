// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=structured-loops=@squares -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.func(idr-structure-loops))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=structured-loops=@squares,structured-loops=@scaled -o /dev/null
// RUN: FileCheck %s < %t.mlir
// A tabulation, as the frontend writes it (tensor.empty, then a loop that
// inserts each element at its induction variable), whose body only
// computes is one structured op, whose dimension is parallel: the order of
// its elements is unobservable. A read of another array at the induction
// variable is an input of that op with the identity map, not a read in
// its body. Before the pass the property fails, so it is the pass's.
// CHECK-LABEL: idr.func private @scaled(
// CHECK: linalg.generic
// CHECK-SAME: ins(
// CHECK-NOT: tensor.extract
// CHECK: return
module {
  idr.func private @squares(%n: index) -> tensor<?xi64> {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %e = tensor.empty(%n) : tensor<?xi64>
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %x = arith.index_cast %i : index to i64
      %sq = arith.muli %x, %x : i64
      %a1 = tensor.insert %sq into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    return %r : tensor<?xi64>
  }
  idr.func private @scaled(%x: tensor<?xi64>, %k: i64) -> tensor<?xi64> {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %n = tensor.dim %x, %c0 : tensor<?xi64>
    %e = tensor.empty(%n) : tensor<?xi64>
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %v = tensor.extract %x[%i] : tensor<?xi64>
      %s = arith.muli %v, %k : i64
      %a1 = tensor.insert %s into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    return %r : tensor<?xi64>
  }
}
