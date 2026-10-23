// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// A tie states its array's dynamic sizes and gives the same array on, at
// its operand's type: a tie that changed the type would re-pack the
// array's words as a cast does, so a call whose result it ties would not
// stay the tail. A tie whose result has its operand's type verifies; one
// whose result moves a dynamic axis to another place, with as many sizes
// as either type has dynamic axes, is the error.
idr.program @ties root(@main) stage(higher) {
  idr.func @main() {
    idr.return
  }
  idr.func @same(%x: tensor<?x4xi64>, %n: index) -> i64 {
    %y = idr.array.tie_shape %x dims(%n) : tensor<?x4xi64> -> tensor<?x4xi64>
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
}

// -----

idr.program @ties root(@main) stage(higher) {
  idr.func @main() {
    idr.return
  }
  idr.func @other(%x: tensor<?x4xi64>, %n: index) -> i64 {
    // expected-error @below {{}}
    %y = idr.array.tie_shape %x dims(%n) : tensor<?x4xi64> -> tensor<4x?xi64>
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
}
