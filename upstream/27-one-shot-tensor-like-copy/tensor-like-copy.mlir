// RUN: mlir-opt %s -test-one-shot-module-bufferize -split-input-file -verify-diagnostics

// An OpOperand of a tensor-like type that is not a builtin tensor bufferizes
// out-of-place: %arg is read after the op writes it. Such a value is copied
// by BufferizationOptions::tensorAllocationFn, which the test pass does not
// set, so the copy is an error. The OpOperand used to be given no copy, and
// the op wrote the buffer that is read after it.
func.func @custom_type_read_after_write(%arg: !test.test_tensor<[4], f64>)
    -> (!test.test_tensor<[4], f64>, !test.test_tensor<[4], f64>) {
  // expected-error @below {{allocating a tensor of type '!test.test_tensor<[4], f64>' is not supported}}
  %out = "test.dummy_tensor_op"(%arg) : (!test.test_tensor<[4], f64>)
    -> !test.test_tensor<[4], f64>
  return %out, %arg : !test.test_tensor<[4], f64>, !test.test_tensor<[4], f64>
}
