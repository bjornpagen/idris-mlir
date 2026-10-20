// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// What a call may do contains what its callee may: its symbol-use verifier
// holds it, as it holds the call's types to the callee's signature, so a
// pass that reads a call alone never reads too little. A call may hold
// more, as one no solve has written holds everything. The error names
// what the call's set lacks: one of two (diverge, of crash and diverge),
// or another than the one held (crash, where io is).

idr.program @"call-effects-contain" root(@root) stage(first) types #idr.types<> {
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

idr.program @"call-effects-contain" root(@root) stage(first) types #idr.types<> {
  idr.func effects<crash, diverge> @crashes(%x: i64) -> i64 {
    %y = idr.check.nonzero %x, "division by zero" : i64
    return %y : i64
  }
  idr.func @root() -> i64 {
    %c = arith.constant 3 : i64
    // expected-error @+1 {{holds the effects crash, which do not contain those of @crashes: diverge}}
    %r = idr.call @crashes(%c) effects<crash> : (i64) -> i64
    return %r : i64
  }
}

// -----

idr.program @"call-effects-contain" root(@root) stage(first) types #idr.types<> {
  idr.func effects<crash> @crashes(%x: i64) -> i64 attributes {total} {
    %y = idr.check.nonzero %x, "division by zero" : i64
    return %y : i64
  }
  idr.func @root() -> i64 {
    %c = arith.constant 3 : i64
    // expected-error @+1 {{holds the effects io, which do not contain those of @crashes: crash}}
    %r = idr.call @crashes(%c) effects<io> : (i64) -> i64
    return %r : i64
  }
}

// -----

// Two effects or more are written bare, comma-separated, and read back so.
// Any set that contains the callee's holds: its own, more, everything.
idr.program @"call-effects-contain" root(@root) stage(first) types #idr.types<> {
  idr.func effects<crash, diverge> @crashes(%x: i64) -> i64 {
    %y = idr.check.nonzero %x, "division by zero" : i64
    return %y : i64
  }
  idr.func effects<crash> @guards(%x: i64) -> i64 attributes {total} {
    %y = idr.check.nonzero %x, "division by zero" : i64
    return %y : i64
  }
  idr.func effects<none> @pure(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  idr.func @root() -> i64 {
    %c = arith.constant 3 : i64
    %a = idr.call @crashes(%c) effects<crash, diverge> : (i64) -> i64
    %b = idr.call @crashes(%a) : (i64) -> i64
    %d = idr.call @guards(%b) effects<io, crash> : (i64) -> i64
    %e = idr.call @pure(%d) effects<none> : (i64) -> i64
    %f = idr.call @pure(%e) effects<io> : (i64) -> i64
    %g = idr.call @pure(%f) effects<diverge> : (i64) -> i64
    return %g : i64
  }
}
