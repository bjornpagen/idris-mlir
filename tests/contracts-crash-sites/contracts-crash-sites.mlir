// RUN: idris-mlir-opt %s --idr-contracts --pass-pipeline='builtin.module(idr.program(idr-effects, test-idr-break-contract{relation=crash-sites-not-added}))' -verify-diagnostics -o /dev/null
// RUN: idris-mlir-opt %s --idr-contracts=false --pass-pipeline='builtin.module(idr.program(idr-effects, test-idr-break-contract{relation=crash-sites-not-added}))' -o /dev/null
// A function a pass keeps that could not crash before it has no place that
// may crash after it, counted of that function alone, whatever other
// function answers to its name. idr-effects solves what each function may
// do: @f nothing, @lam and the root crash. The test pass then makes every
// function that could not crash, @f alone, crash instead of returning, and
// lets every function and call crash, so the module verifies; @f gains a
// place that may crash, and may crash, so both contracts name the pass
// there.
idr.program @"crash-sites" root(@root) stage(first) {
  // expected-error-re @below {{contract effects-not-widened broken by test-idr-break-contract{{.*}}@f}}
  // expected-error-re @below {{contract crash-sites-not-added broken by test-idr-break-contract{{.*}}: @f}}
  idr.func @f(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  // A lambda of f's definition, as Emit locates one: a function of another
  // symbol that answers to f all the same.
  idr.func @lam(%x: i64) -> i64 attributes {total} {
    %y = idr.check.nonzero %x, "division by zero" : i64
    %r = idr.divs %x, %y : i64
    return %r : i64
  } loc("f")
  idr.func @root() -> i64 attributes {total} {
    %c = arith.constant 7 : i64
    %a = idr.call @f(%c) : (i64) -> i64
    %b = idr.call @lam(%a) : (i64) -> i64
    return %b : i64
  }
}
