// NEEDS-ACCEPTANCE: that --idr-contracts names the pass that widens a function's effects or makes a linear result unrestricted, while the module stays valid, and lets a pass that keeps both pass.
// RUN: %status 1 idris-mlir-opt %s --idr-contracts --pass-pipeline='builtin.module(idr.program(test-idr-break-contract{relation=effects-not-widened}))' -o /dev/null 2> %t.effects.err
// RUN: FileCheck %s --check-prefix=EFFECTS < %t.effects.err
// RUN: %status 1 idris-mlir-opt %s --idr-contracts --pass-pipeline='builtin.module(idr.program(test-idr-break-contract{relation=linear-kept}))' -o /dev/null 2> %t.linear.err
// RUN: FileCheck %s --check-prefix=LINEAR < %t.linear.err
// RUN: idris-mlir-opt %s --idr-contracts=false --pass-pipeline='builtin.module(idr.program(test-idr-break-contract{relation=effects-not-widened}))' -o /dev/null
// RUN: idris-mlir-opt %s --idr-contracts=false --pass-pipeline='builtin.module(idr.program(test-idr-break-contract{relation=linear-kept}))' -o /dev/null
// RUN: idris-mlir-opt %s --idr-contracts --idr-effects -o /dev/null
// A pass may narrow what a function it keeps may do, never widen it, and
// never changes a quantity Idris proved. The test pass breaks one of the
// two on purpose and leaves a module that verifies, so what fails is the
// contract checked after it, which names it: with the contracts off (the
// runner turns them on for every idris-mlir-opt, and an option's last
// occurrence is the one that counts) both runs pass. idr-effects keeps
// both.
// EFFECTS: contract effects-not-widened broken by test-idr-break-contract
// LINEAR: contract linear-kept broken by test-idr-break-contract
idr.program @contracts root(@main) stage(first) {
  idr.func @main() -> i64 attributes {total, effects = #idr.effects<none>} {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @lonely(%x: !idr.lin<i64>) -> !idr.lin<i64> attributes {total, effects = #idr.effects<none>} {
    return %x : !idr.lin<i64>
  }
}
