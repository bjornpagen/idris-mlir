func.func private @never_returns(%t: tensor<4xf32>) -> tensor<4xf32> {
  ub.unreachable
}

func.func @caller(%t: tensor<4xf32>, %c: i1) -> f32 {
  %c0 = arith.constant 0 : index
  scf.if %c {
    %0 = func.call @never_returns(%t) : (tensor<4xf32>) -> tensor<4xf32>
  }
  %1 = tensor.extract %t[%c0] : tensor<4xf32>
  return %1 : f32
}
