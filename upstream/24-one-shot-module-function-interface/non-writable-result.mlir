func.func private @constant() -> tensor<3xi64> {
  %c = arith.constant dense<[1, 2, 3]> : tensor<3xi64>
  return %c : tensor<3xi64>
}

func.func @writes_constant(%v: i64) -> tensor<3xi64> {
  %c0 = arith.constant 0 : index
  %0 = func.call @constant() : () -> tensor<3xi64>
  %1 = tensor.insert %v into %0[%c0] : tensor<3xi64>
  return %1 : tensor<3xi64>
}
