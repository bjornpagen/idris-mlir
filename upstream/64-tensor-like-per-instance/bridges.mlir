// mlir-opt bridges.mlir -split-input-file -verify-diagnostics
//
// With the shape traits gone, the tensor-like type's own check is the one
// rule for a bridge: builtin bridges of matching shape and element type
// verify, and a mismatch is refused by `verifyCompatibleBufferType`, with
// its message. (A graded tensor, tensor-like where its payload is and not
// shaped, verifies only with the patch: the compiler's tools show it.)

func.func @matching(%m: memref<4x?xf32>) -> memref<4x?xf32> {
  %t = bufferization.to_tensor %m : memref<4x?xf32> to tensor<4x?xf32>
  %b = bufferization.to_buffer %t : tensor<4x?xf32> to memref<4x?xf32>
  return %b : memref<4x?xf32>
}

// -----

func.func @shape_mismatch(%m: memref<4x3xf32>) {
  // expected-error @below{{'bufferization.to_tensor' op failed to verify that specified tensor and buffer types match}}
  // expected-error @below{{shapes do not match}}
  %t = bufferization.to_tensor %m : memref<4x3xf32> to tensor<3x4xf32>
  return
}
