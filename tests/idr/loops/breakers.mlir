// RUN: idris-mlir-opt %s -split-input-file --idr-loop-breakers | FileCheck %s
// idr-loop-breakers cuts every cycle of references among the functions that
// may be inlined, calls and closures alike, at the start of every round.

// Two clones that call each other: the newest becomes the breaker.
// CHECK-LABEL: func.func private @f(
// CHECK-NOT: no_inline
// CHECK-LABEL: func.func private @f$spec$1(
// CHECK-NOT: no_inline
// CHECK-LABEL: func.func private @f$spec$2(
// CHECK-SAME: no_inline
module attributes {idr.program} {
  func.func private @f(%x: i64) -> i64 {
    %r = func.call @f$spec$1(%x) : (i64) -> i64
    return %r : i64
  }
  func.func private @f$spec$1(%x: i64) -> i64 attributes {idr.clone = #idr.clone<@f$spec$1, #idr.spec_key<"f", [#idr.key_hole<0>]>>} {
    %r = func.call @f$spec$2(%x) : (i64) -> i64
    return %r : i64
  }
  func.func private @f$spec$2(%x: i64) -> i64 attributes {idr.clone = #idr.clone<@f$spec$2, #idr.spec_key<"f", [#idr.key_hole<0>]>>} {
    %r = func.call @f$spec$1(%x) : (i64) -> i64
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    %r = func.call @f(%c) : (i64) -> i64
    return %r : i64
  }
}

// -----

// An IO loop whose action is a constant that closes over the loop's own
// lambda: once sccp has replaced the call of the breaker by that constant,
// the lambda refers to itself, and the inliner, which sees only calls, would
// unroll it once per round. It becomes a breaker.
// CHECK-LABEL: func.func private @loop$lam0(
// CHECK-SAME: no_inline
module attributes {idr.program} {
  func.func private @loop$lam0(%c: i64) -> !idr.fn<(i64) -> (i64)> {
    %k = idr.constant #idr.closure<@loop$lam0, []> : !idr.fn<(i64) -> (!idr.fn<(i64) -> (i64)>)>
    %f = idr.closure @step(%k) : (!idr.fn<(i64) -> (!idr.fn<(i64) -> (i64)>)>) -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  func.func private @step(%k: !idr.fn<(i64) -> (!idr.fn<(i64) -> (i64)>)>, %x: i64) -> i64 {
    return %x : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    %f = func.call @loop$lam0(%c) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %f(%c) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
}

// -----

// A cycle through a library function and a function of the program: the
// breaker is the program's, as Emit picks it (the library breaks last).
// CHECK-LABEL: func.func private @Lib.go(
// CHECK-NOT: no_inline
// CHECK-LABEL: func.func private @Main.back(
// CHECK-SAME: no_inline
module attributes {idr.program} {
  func.func private @Lib.go(%x: i64) -> i64 attributes {idr.library} {
    %r = func.call @Main.back(%x) : (i64) -> i64
    return %r : i64
  }
  func.func private @Main.back(%x: i64) -> i64 {
    %r = func.call @Lib.go(%x) : (i64) -> i64
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    %r = func.call @Lib.go(%c) : (i64) -> i64
    return %r : i64
  }
}
