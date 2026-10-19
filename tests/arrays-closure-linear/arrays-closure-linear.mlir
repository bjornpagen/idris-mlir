// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A closure holds its captures, so it is used as often as they may be: one
// that captures a linear value is itself at quantity one, which its type
// says, and the linearity verifier counts its one use as any linear
// value's. It is applied as it is: the apply reads its carrier.

idr.program @"closure-linear" root(@root) stage(higher) {
  idr.func @g(%s: !idr.lin<!idr.str>, %n: i64) -> i64 {
    idr.crash "no body"
    ub.unreachable
  }
  idr.func @f(%s: !idr.lin<!idr.str>) {
    // expected-error @+1 {{failed to verify that its result is at quantity one exactly when a capture is}}
    %c = idr.closure @g(%s) : (!idr.lin<!idr.str>) -> !idr.fn<(i64) -> (i64)>
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"closure-linear" root(@root) stage(higher) {
  idr.func @g(%s: !idr.lin<!idr.str>, %n: i64) -> i64 {
    idr.crash "no body"
    ub.unreachable
  }
  idr.func @f(%s: !idr.lin<!idr.str>, %n: i64) -> i64 {
    %c = idr.closure @g(%s) : (!idr.lin<!idr.str>) -> !idr.lin<!idr.fn<(i64) -> (i64)>>
    %r = idr.apply %c(%n) : !idr.lin<!idr.fn<(i64) -> (i64)>>
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
