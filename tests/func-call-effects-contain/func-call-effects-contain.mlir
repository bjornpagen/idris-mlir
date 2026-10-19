// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// What a call may do contains what its callee may: its symbol-use verifier
// holds it, as it holds the call's types to the callee's signature, so a
// pass that reads a call alone never reads too little. A call may hold
// more, as one no solve has written holds everything.

idr.program @"call-effects-contain" root(@root) stage(first) {
  idr.func effects<crash> @crashes(%x: i64) -> i64 attributes {total} {
    %y = idr.check.nonzero %x, "division by zero" : i64
    return %y : i64
  }
  idr.func @root() -> i64 {
    %c = arith.constant 3 : i64
    // expected-error @+1 {{holds the effects none, which do not contain those of @crashes: crash}}
    %r = idr.call @crashes(%c) effects<none> : (i64) -> i64
    return %r : i64
  }
}

// -----

// Two effects or more are written bare, comma-separated, and read back so.
idr.program @"call-effects-contain" root(@root) stage(first) {
  idr.func effects<crash, diverge> @crashes(%x: i64) -> i64 {
    %y = idr.check.nonzero %x, "division by zero" : i64
    return %y : i64
  }
  idr.func @root() -> i64 {
    %c = arith.constant 3 : i64
    %a = idr.call @crashes(%c) effects<crash, diverge> : (i64) -> i64
    %b = idr.call @crashes(%a) : (i64) -> i64
    return %b : i64
  }
}
