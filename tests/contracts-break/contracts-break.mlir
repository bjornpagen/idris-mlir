// RUN: idris-mlir-opt %s --idr-contracts --pass-pipeline='builtin.module(idr.program(test-idr-break-contract{relation=effects-not-widened}))' -verify-diagnostics -o /dev/null
// RUN: idris-mlir-opt %s --idr-contracts=false --pass-pipeline='builtin.module(idr.program(test-idr-break-contract{relation=effects-not-widened}))' -o /dev/null
// RUN: idris-mlir-opt %s --idr-contracts --idr-effects -o /dev/null
// A pass may narrow what a function it keeps may do, never widen it. The
// test pass widens every function's effects on purpose, and every call's
// with its callee's, so the module verifies and what fails is the contract
// checked after it, which names the pass at each function: with the
// contracts off (the runner turns them on for every idris-mlir-opt, and an
// option's last occurrence is the one that counts) the run passes.
// idr-effects keeps it. linear-kept is broken in break-linear.mlir and
// crash-sites-not-added in crash-sites.mlir.
idr.program @contracts root(@main) stage(first) types #idr.types<> {
  // expected-error-re @below {{contract effects-not-widened broken by test-idr-break-contract{{.*}}@main}}
  idr.func effects<none> @main() -> i64 attributes {total} {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error-re @below {{contract effects-not-widened broken by test-idr-break-contract{{.*}}@lonely}}
  idr.func effects<none> @lonely(%x: !idr.lin<i64>) -> !idr.lin<i64> attributes {total} {
    return %x : !idr.lin<i64>
  }
}
