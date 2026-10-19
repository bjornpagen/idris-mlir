// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// An array yield moves its leading values into the arrays its parent holds
// for them, so its parent is an op that holds such arrays; under any other
// op the verifier refuses it.

idr.program @"yield-parent" root(@root) stage(first) {
  idr.func @f(%x: i64) -> i64 {
    %r = scf.execute_region -> i64 {
      // expected-error @+1 {{failed to verify that its parent holds the arrays it yields into}}
      idr.array.yield %x : i64
    }
    return %r : i64
  }
  // The program's root, which the function above is no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
