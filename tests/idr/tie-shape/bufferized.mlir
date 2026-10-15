// RUN: idris-mlir-opt %s --idr-bufferize | FileCheck %s
// RUN: idris-mlir-opt %s --idr-bufferize --idr-lower | FileCheck %s --check-prefix=LOWERED
// A tie is the same statement on the buffer as on the tensor, so value
// bounds still relate the dimensions after bufferization; lowering drops
// it, since a buffer's sizes are its components already, and leaves no op.
// CHECK-LABEL: idr.func private @second(
// CHECK: idr.tie_shape %{{.*}} dims(%{{.*}}) : memref<?xi64>
// CHECK-NOT: tensor<
// CHECK: return
// LOWERED-NOT: idr.tie_shape
module {
  idr.func private @second(%x: tensor<?xi64>, %y: tensor<?xi64>) -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %n = tensor.dim %x, %c0 : tensor<?xi64>
    %y1 = idr.tie_shape %y dims(%n) : tensor<?xi64>
    %v = tensor.extract %y1[%c1] : tensor<?xi64>
    return %v : i64
  }
  idr.func @root() -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c4 = arith.constant 4 : index
    %e = tensor.empty(%c4) : tensor<?xi64>
    %t = scf.for %i = %c0 to %c4 step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %x = arith.index_cast %i : index to i64
      %a1 = tensor.insert %x into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    %v = idr.call @second(%t, %t) : (tensor<?xi64>, tensor<?xi64>) -> i64
    return %v : i64
  }
}
