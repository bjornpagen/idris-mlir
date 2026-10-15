// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.func(affine-simplify-min-max))' | FileCheck %s
// Upstream's value bounds see a dimension through the op that made it, and
// a function's parameter has none: the tie is what states that two
// parameters indexed by one Idris size have one dimension. In @same the
// second array is tied to the first one's dimension, as the frontend
// writes a size variable that indexes two parameters, so the smaller of
// the two dimensions is either of them and the min goes. In @apart the
// sizes are two, and the min stays.
// CHECK-LABEL: idr.func private @same(
// CHECK-NOT: affine.min
// CHECK: return
// CHECK-LABEL: idr.func private @apart(
// CHECK: affine.min
// CHECK: return
module {
  idr.func private @same(%x: tensor<?xf64>, %y: tensor<?xf64>) -> index {
    %c0 = arith.constant 0 : index
    %n = tensor.dim %x, %c0 : tensor<?xf64>
    %y1 = idr.tie_shape %y dims(%n) : tensor<?xf64>
    %dx = tensor.dim %x, %c0 : tensor<?xf64>
    %dy = tensor.dim %y1, %c0 : tensor<?xf64>
    %m = affine.min affine_map<(d0, d1) -> (d0, d1)>(%dx, %dy)
    return %m : index
  }
  idr.func private @apart(%x: tensor<?xf64>, %y: tensor<?xf64>, %k: index) -> index {
    %c0 = arith.constant 0 : index
    %n = tensor.dim %x, %c0 : tensor<?xf64>
    %y1 = idr.tie_shape %y dims(%k) : tensor<?xf64>
    %dx = tensor.dim %x, %c0 : tensor<?xf64>
    %dy = tensor.dim %y1, %c0 : tensor<?xf64>
    %m = affine.min affine_map<(d0, d1) -> (d0, d1)>(%dx, %dy)
    return %m : index
  }
}
