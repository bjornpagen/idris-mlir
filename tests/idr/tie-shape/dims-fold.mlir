// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// An array tied to sizes has those sizes as its dimensions: the dimension
// of a tied tensor or buffer at a dynamic dimension folds to the size it
// was tied to, and at a static one to the constant of its type, through
// the dialect's canonicalization of shaped results. So a size Idris proved
// equal across a call is the same value on both sides, and no dimension is
// read at run time.
// CHECK-LABEL: idr.func private @dynamic(
// CHECK-SAME: %{{[^:]*}}: tensor<?xi64>, %[[N:[^:]*]]: index)
// CHECK-NOT: tensor.dim
// CHECK: return %[[N]] : index
// CHECK-LABEL: idr.func private @static(
// CHECK-SAME: %{{[^:]*}}: tensor<4x?xi64>, %[[M:[^:]*]]: index)
// CHECK-NOT: tensor.dim
// CHECK-DAG: %[[C4:.*]] = arith.constant 4 : index
// CHECK: return %[[C4]], %[[M]] : index, index
// CHECK-LABEL: idr.func private @buffer(
// CHECK-SAME: %{{[^:]*}}: memref<?xf64>, %[[K:[^:]*]]: index)
// CHECK-NOT: memref.dim
// CHECK: return %[[K]] : index
module {
  idr.func private @dynamic(%x: tensor<?xi64>, %n: index) -> index {
    %y = idr.tie_shape %x dims(%n) : tensor<?xi64>
    %c0 = arith.constant 0 : index
    %d = tensor.dim %y, %c0 : tensor<?xi64>
    return %d : index
  }
  idr.func private @static(%x: tensor<4x?xi64>, %m: index) -> (index, index) {
    %y = idr.tie_shape %x dims(%m) : tensor<4x?xi64>
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %d0 = tensor.dim %y, %c0 : tensor<4x?xi64>
    %d1 = tensor.dim %y, %c1 : tensor<4x?xi64>
    return %d0, %d1 : index, index
  }
  idr.func private @buffer(%b: memref<?xf64>, %k: index) -> index {
    %y = idr.tie_shape %b dims(%k) : memref<?xf64>
    %c0 = arith.constant 0 : index
    %d = memref.dim %y, %c0 : memref<?xf64>
    return %d : index
  }
}
