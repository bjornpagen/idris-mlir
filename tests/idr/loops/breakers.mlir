// RUN: idris-mlir-opt %s -split-input-file --idr-loop-breakers | FileCheck %s
// RUN: idris-mlir-opt %s -split-input-file --idr-loop-breakers --idr-expect=holds=every-cycle-has-breaker,breaks-last -o /dev/null
// idr-loop-breakers cuts every cycle of references among the functions that
// may be inlined, calls and closures alike, at the start of every round;
// Emit marks none, so its rule is the one rule.

// Two clones that call each other: the newest becomes the breaker.
// CHECK-LABEL: idr.func private @f(
// CHECK-NOT: no_inline
// CHECK-LABEL: idr.func private @f.spec1(
// CHECK-NOT: no_inline
// CHECK-LABEL: idr.func private @f.spec2(
// CHECK-SAME: no_inline
module attributes {idr.program} {
  idr.func private @f(%x: i64) -> i64 {
    %r = idr.call @f.spec1(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func private @f.spec1(%x: i64) -> i64 attributes {clone = #idr.clone<@f.spec1, #idr.spec_key<"f", [#idr.key_hole<0>]>>} {
    %r = idr.call @f.spec2(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func private @f.spec2(%x: i64) -> i64 attributes {clone = #idr.clone<@f.spec2, #idr.spec_key<"f", [#idr.key_hole<0>]>>} {
    %r = idr.call @f.spec1(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    %r = idr.call @f(%c) : (i64) -> i64
    return %r : i64
  }
}

// -----

// An IO loop whose action is a constant that closes over the loop's own
// lambda: once sccp has replaced the call of the breaker by that constant,
// the lambda refers to itself, and the inliner, which sees only calls, would
// unroll it once per round. It becomes a breaker.
// CHECK-LABEL: idr.func private @loop.lam1(
// CHECK-SAME: no_inline
module attributes {idr.program} {
  idr.func private @loop.lam1(%c: i64) -> !idr.fn<(i64) -> (i64)> {
    %k = idr.constant #idr.closure<@loop.lam1, []> : !idr.fn<(i64) -> (!idr.fn<(i64) -> (i64)>)>
    %f = idr.closure @step(%k) : (!idr.fn<(i64) -> (!idr.fn<(i64) -> (i64)>)>) -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  idr.func private @step(%k: !idr.fn<(i64) -> (!idr.fn<(i64) -> (i64)>)>, %x: i64) -> i64 {
    return %x : i64
  }
  idr.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    %f = idr.call @loop.lam1(%c) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %f(%c) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
}

// -----

// A cycle through a function that breaks last (the registry's column) and
// a function of the program: the breaker is the program's.
// CHECK-LABEL: idr.func private @Lib.go(
// CHECK-NOT: no_inline
// CHECK-LABEL: idr.func private @Main.back(
// CHECK-SAME: no_inline
module attributes {idr.program} {
  idr.func private @Lib.go(%x: i64) -> i64 attributes {break_last} {
    %r = idr.call @Main.back(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func private @Main.back(%x: i64) -> i64 {
    %r = idr.call @Lib.go(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    %r = idr.call @Lib.go(%c) : (i64) -> i64
    return %r : i64
  }
}

// -----

// The shape of a Show implementation for a rose tree: the user's show, the
// Prelude's show of a list, which does not break last, and a function of
// a library that does, first in module order. The cycle breaks at the
// first function that does not break last; a cycle of functions that all
// break last breaks at its first.
// CHECK-LABEL: idr.func private @Builtin.helper(
// CHECK-NOT: no_inline
// CHECK-LABEL: idr.func private @Prelude.showList(
// CHECK-SAME: no_inline
// CHECK-LABEL: idr.func private @Main.show(
// CHECK-NOT: no_inline
// CHECK-LABEL: idr.func private @Builtin.one(
// CHECK-SAME: no_inline
// CHECK-LABEL: idr.func private @Builtin.two(
// CHECK-NOT: no_inline
module attributes {idr.program} {
  idr.func private @Builtin.helper(%x: i64) -> i64 attributes {break_last} {
    %r = idr.call @Main.show(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func private @Prelude.showList(%x: i64) -> i64 {
    %r = idr.call @Builtin.helper(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func private @Main.show(%x: i64) -> i64 {
    %r = idr.call @Prelude.showList(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func private @Builtin.one(%x: i64) -> i64 attributes {break_last} {
    %r = idr.call @Builtin.two(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func private @Builtin.two(%x: i64) -> i64 attributes {break_last} {
    %r = idr.call @Builtin.one(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    %r = idr.call @Main.show(%c) : (i64) -> i64
    %s = idr.call @Builtin.one(%r) : (i64) -> i64
    return %s : i64
  }
}
