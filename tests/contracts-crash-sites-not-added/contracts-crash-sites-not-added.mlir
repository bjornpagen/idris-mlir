// RUN: idris-mlir-opt %s --idr-contracts --test-idr-break-contract=relation=crash-sites-not-added -verify-diagnostics -o /dev/null
// A pass that makes a function whose row could not crash crash breaks
// what the function's row said of it, and the contracts name the pass:
// the test pass that breaks crash-sites-not-added on purpose, writing the
// rows again so the module verifies, so that only the relation catches it.
idr.program @contracts root(@main) stage(first) {
  // expected-error @+1 {{contract crash-sites-not-added broken by}}
  idr.func @main() -> i64 {
    %c = arith.constant 7 : i64
    return %c : i64
  }
}
