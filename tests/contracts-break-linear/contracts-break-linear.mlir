// RUN: idris-mlir-opt %s --idr-contracts --pass-pipeline='builtin.module(idr.program(test-idr-break-contract{relation=linear-kept}))' -verify-diagnostics -o /dev/null
// RUN: idris-mlir-opt %s --idr-contracts=false --pass-pipeline='builtin.module(idr.program(test-idr-break-contract{relation=linear-kept}))' -o /dev/null
// No pass changes a quantity Idris proved. The test pass gives @lonely's
// linear result back unrestricted on purpose, @lonely being named by no
// call, so the module verifies and what fails is the contract checked
// after it, which names the pass: with the contracts off the run passes.
idr.program @contracts root(@main) stage(first) {
  idr.func effects<none> @main() -> i64 attributes {total} {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error-re @below {{contract linear-kept broken by test-idr-break-contract{{.*}}@lonely}}
  idr.func effects<none> @lonely(%x: !idr.lin<i64>) -> !idr.lin<i64> attributes {total} {
    return %x : !idr.lin<i64>
  }
}
