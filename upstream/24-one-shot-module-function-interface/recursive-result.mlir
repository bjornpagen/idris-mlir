// A recursive function whose every level writes the array the level below
// returns, a buffer of its own allocation. Once a call result of a callee
// that is not analyzed is not writable, a callee on a cycle of calls is
// one, so each level copies the array before writing it, unless the cycle
// is analyzed.
func.func @build(%n: index) -> tensor<8xf32> {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %f = arith.constant 1.0 : f32
  %done = arith.cmpi eq, %n, %c0 : index
  %r = scf.if %done -> tensor<8xf32> {
    %e = tensor.empty() : tensor<8xf32>
    %z = linalg.fill ins(%f : f32) outs(%e : tensor<8xf32>) -> tensor<8xf32>
    scf.yield %z : tensor<8xf32>
  } else {
    %m = arith.subi %n, %c1 : index
    %t = func.call @build(%m) : (index) -> tensor<8xf32>
    %t1 = tensor.insert %f into %t[%m] : tensor<8xf32>
    scf.yield %t1 : tensor<8xf32>
  }
  return %r : tensor<8xf32>
}
