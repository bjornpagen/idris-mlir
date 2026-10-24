// RUN: idris-mlir-opt %s --idr-contracts --test-idr-break-contract=relation=linear-kept -verify-diagnostics -o /dev/null
// A pass that gives a linear result back unrestricted breaks what Idris
// proved of the function's result, and the contracts, which compare every
// function a pass kept with its record before the pass, name the pass:
// the test pass that breaks linear-kept on purpose, leaving a module that
// verifies, so that only the relation can catch it. It drops each result
// used many times as well, as a pass may drop a dead one: @give keeps its
// shape, and @split's two results become one, which the contracts compare
// with what its record gives once a result used many times is dropped, so
// dropping one result hides no weakening of another.
idr.program @contracts root(@main) stage(first) {
  idr.func @main() {
    return
  }
  // expected-error @+1 {{contract linear-kept broken by}}
  idr.func @give(%x: !idr.graded<once, i64>) -> !idr.graded<once, i64> {
    return %x : !idr.graded<once, i64>
  }
  // expected-error @+1 {{contract linear-kept broken by}}
  idr.func @split(%x: !idr.graded<once, i64>, %n: i64) -> (!idr.graded<once, i64>, i64) {
    return %x, %n : !idr.graded<once, i64>, i64
  }
}
