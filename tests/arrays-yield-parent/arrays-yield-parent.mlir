// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// An array yield moves its leading values into the arrays its parent holds
// for them, so its parent is an op that holds such arrays; under any other
// op the verifier refuses it. Under an idr.tabulate, which holds the array
// it builds, it verifies (the second split).

idr.program @"yield-parent" root(@root) stage(first) types #idr.types<> {
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

// -----

idr.program @"yield-parent" root(@root) stage(first) types #idr.types<> {
  idr.func @f(%n: index) -> tensor<?xi64> {
    %t = idr.tabulate [%n] {
    ^bb0(%i: index):
      %x = arith.index_cast %i : index to i64
      idr.array.yield %x : i64
    } : tensor<?xi64>
    return %t : tensor<?xi64>
  }
  // The program's root, which the function above is no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
