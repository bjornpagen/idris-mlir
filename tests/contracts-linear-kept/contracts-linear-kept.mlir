// RUN: idris-mlir-opt %s --idr-contracts --test-idr-break-contract=relation=linear-kept -verify-diagnostics -o /dev/null
// A pass that gives a result used once by its grade back unrestricted
// breaks what Idris proved of the function's result, the one reference it
// hands its caller, and the contracts, which compare every function a pass
// kept with its record before the pass, name the pass: the test pass that
// breaks linear-kept on purpose, leaving a module that verifies, so that
// only the relation can catch it.
idr.program @contracts root(@main) stage(first) {
  idr.func @main() {
    return
  }
  // expected-error @+1 {{contract linear-kept broken by}}
  idr.func @give(%x: !idr.graded<once, i64>) -> !idr.graded<once, i64> {
    return %x : !idr.graded<once, i64>
  }
}
