// @pick returns its argument. The argument's alias set also holds a
// constant, through the scf.if that may yield either, so the function's
// result may alias a buffer that is not writable; but it is definitely the
// argument's buffer, which a call result is equivalent to. A caller that
// writes the result writes the buffer of its own operand, its argument,
// which is writable and not read after the call: no copy is needed.
func.func private @pick(%t: tensor<4xf32>, %c: i1, %i: index) -> (tensor<4xf32>, f32) {
  %cst = arith.constant dense<0.0> : tensor<4xf32>
  %s = scf.if %c -> tensor<4xf32> {
    scf.yield %t : tensor<4xf32>
  } else {
    scf.yield %cst : tensor<4xf32>
  }
  %x = tensor.extract %s[%i] : tensor<4xf32>
  return %t, %x : tensor<4xf32>, f32
}

func.func @writes_picked(%t: tensor<4xf32>, %c: i1, %v: f32) -> tensor<4xf32> {
  %c0 = arith.constant 0 : index
  %r:2 = func.call @pick(%t, %c, %c0) : (tensor<4xf32>, i1, index) -> (tensor<4xf32>, f32)
  %w = tensor.insert %v into %r#0[%c0] : tensor<4xf32>
  return %w : tensor<4xf32>
}
