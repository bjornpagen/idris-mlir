// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// A tie gives one size per dynamic axis of its operand, and its type is
// inferred only where they number them: a re-inference that makes the
// operand more static, as a specialized copy makes its input, is refused
// at the tie, which keeps its type. A tie of an array with no dynamic axis
// and no size verifies; the same tie given one size is the error, which
// its inference reports.
idr.program @ties root(@main) stage(higher) {
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
  idr.func @none(%x: tensor<4xi64>, %n: index) -> i64 {
    %y = idr.array.tie_shape %x dims() : tensor<4xi64> -> tensor<4xi64>
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
}

// -----

idr.program @ties root(@main) stage(higher) {
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
  idr.func @stale(%x: tensor<4xi64>, %n: index) -> i64 {
    // expected-error @below {{}}
    %y = idr.array.tie_shape %x dims(%n) : tensor<4xi64> -> tensor<4xi64>
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
}
