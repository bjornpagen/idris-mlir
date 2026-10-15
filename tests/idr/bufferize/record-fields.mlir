// RUN: idris-mlir-opt %s --idr-bufferize | FileCheck %s
// NEEDS-ACCEPTANCE: which step makes an array of a record one tensor per field is not decided yet; this fixture states the two tensors' bufferization only.
// An array of a record is one array per field: here a record of an i64
// and an f64, whose tabulation fills both fields' arrays in one loop.
// Through bufferization each field's array is a buffer of its own, and no
// buffer of the record, whose elements nothing could vectorize, is made.
// CHECK-LABEL: idr.func @pairs(
// CHECK-SAME: -> (memref<?xi64>, memref<?xf64>)
// CHECK-NOT: tensor<
// CHECK-NOT: memref<?x!idr.data
// CHECK: return
!P = !idr.data<"P", plain [@MkP(i64, f64)]>
idr.program @"record-fields" root(@root) stage(first) {
  idr.func @pairs(%n: index) -> (tensor<?xi64>, tensor<?xf64>) {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %e1 = tensor.empty(%n) : tensor<?xi64>
    %e2 = tensor.empty(%n) : tensor<?xf64>
    %r:2 = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e1, %b = %e2) -> (tensor<?xi64>, tensor<?xf64>) {
      %x = arith.index_cast %i : index to i64
      %y = arith.sitofp %x : i64 to f64
      %a1 = tensor.insert %x into %a[%i] : tensor<?xi64>
      %b1 = tensor.insert %y into %b[%i] : tensor<?xf64>
      scf.yield %a1, %b1 : tensor<?xi64>, tensor<?xf64>
    }
    return %r#0, %r#1 : tensor<?xi64>, tensor<?xf64>
  }
  idr.func @root() -> i64 {
    %c0 = arith.constant 0 : index
    %c4 = arith.constant 4 : index
    %r:2 = idr.call @pairs(%c4) : (index) -> (tensor<?xi64>, tensor<?xf64>)
    %x = tensor.extract %r#0[%c0] : tensor<?xi64>
    %y = tensor.extract %r#1[%c0] : tensor<?xf64>
    %p = idr.con !P @MkP(%x : i64, %y : f64)
    %v = idr.field %p : !P @MkP[0] -> i64
    return %v : i64
  }
}
