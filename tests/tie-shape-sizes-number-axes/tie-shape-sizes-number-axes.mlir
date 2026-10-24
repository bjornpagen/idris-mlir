// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// A tie names the axes something states, each a dynamic axis of its
// operand, with one size each, and its type is inferred only there: an
// axis nothing states stays untied, and a re-inference that makes a tied
// axis static, as a specialized copy makes its input, is refused at the
// tie, which keeps its type. A tie of the first of two dynamic axes, the
// second untied, verifies; a tie of an axis the array fixes is the error,
// which its inference reports.
idr.program @ties root(@main) stage(higher) {
  idr.func @main() {
    idr.return
  }
  idr.func @first(%x: tensor<?x?xi64>, %n: index) -> i64 {
    %y = idr.array.tie_shape %x axes [0] dims(%n) : tensor<?x?xi64> -> tensor<?x?xi64>
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
}

// -----

idr.program @ties root(@main) stage(higher) {
  idr.func @main() {
    idr.return
  }
  idr.func @fixed(%x: tensor<4x?xi64>, %n: index) -> i64 {
    // expected-error @below {{}}
    %y = idr.array.tie_shape %x axes [0] dims(%n) : tensor<4x?xi64> -> tensor<4x?xi64>
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
}
