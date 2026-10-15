module attributes {transform.with_named_sequence} {
  func.func @payload(%t: tensor<4xf32>) -> tensor<4xf32> {
    return %t : tensor<4xf32>
  }

  transform.named_sequence @schedule(%arg0: !transform.any_op {transform.readonly}) {
    transform.yield
  }
}
