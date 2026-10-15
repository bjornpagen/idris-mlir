// A recursive function that reads its argument after calling itself. The
// call never writes the argument, but the pinned driver does not analyze a
// function on a cycle of calls, so it assumes the call writes it and passes
// a copy.
func.func @foo(%t: tensor<5xf32>) -> tensor<5xf32> {
  %0 = func.call @foo(%t) : (tensor<5xf32>) -> tensor<5xf32>
  %c0 = arith.constant 0 : index
  %x = tensor.extract %t[%c0] : tensor<5xf32>
  vector.print %x : f32
  return %0 : tensor<5xf32>
}
