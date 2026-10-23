// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// A function's result keeps every axis of its array `?`, whatever Idris
// knows of its size: a size it knows is a constant entry of its extents,
// and a static value is cast before the return, so the type a call gives
// is the type its slot takes and no cast follows a call. An input's axis
// may be static, as a specialized copy's is, and the program verifies; a
// result whose type holds an axis static is the error.
idr.program @results root(@main) stage(higher) {
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
  idr.func @known(%x: tensor<4xi64>) -> tensor<?xi64> attributes {extents = #idr.extents<[result 0 axis 0 = 4]>} {
    %y = tensor.cast %x : tensor<4xi64> to tensor<?xi64>
    idr.return %y : tensor<?xi64>
  }
}

// -----

idr.program @results root(@main) stage(higher) {
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
  // expected-error @below {{}}
  idr.func @static(%x: tensor<4xi64>) -> tensor<4xi64> {
    idr.return %x : tensor<4xi64>
  }
}
