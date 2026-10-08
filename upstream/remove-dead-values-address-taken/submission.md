# Submission

Where: a comment on https://github.com/llvm/llvm-project/pull/208881.
No new issue, no pull request of its own. Author is Bjorn, as an
individual, work done outside any employer. No @mentions.

Paste everything between the markers.

----- paste -----

Another case this fixes, with a test for `mlir/test/Transforms/remove-dead-values.mlir`. A callee named by a non-call op keeps its signature (`processFuncOp` skips it), so its calls keep their operands; when it never reads a parameter, liveness marks the argument the private caller passes dead, and the caller's cleanup drops that use. At llvmorg-23.1.2 this fails with `null operand found` at `func.call @ignores`; with this PR the call takes `ub.poison`. A public callee in place of `func.constant` fails and is fixed the same way.

```mlir
// RUN: mlir-opt %s -remove-dead-values="canonicalize=0" -split-input-file | FileCheck %s
// RUN: mlir-opt %s -remove-dead-values="canonicalize=1" -split-input-file | FileCheck %s --check-prefix=CHECK-CANONICALIZE

// Verify that a function referenced by a non-call op (func.constant) keeps
// its signature, and that a call of it passes poison for an argument of the
// caller that the pass erases because the callee never reads it.
// CHECK-LABEL: module @address_taken_callee
// CHECK:         func.func private @ignores(%{{.*}}: i64) -> i64
// CHECK:         func.func private @caller() -> i64
// CHECK-NEXT:      %[[P:.*]] = ub.poison : i64
// CHECK-NEXT:      call @ignores(%[[P]]) : (i64) -> i64
// CHECK-CANONICALIZE-LABEL: module @address_taken_callee
// CHECK-CANONICALIZE:         func.func private @caller() -> i64
// CHECK-CANONICALIZE-NEXT:      %[[P:.*]] = ub.poison : i64
// CHECK-CANONICALIZE-NEXT:      call @ignores(%[[P]]) : (i64) -> i64
module @address_taken_callee {
  func.func private @ignores(%x: i64) -> i64 {
    %c = arith.constant 7 : i64
    return %c : i64
  }
  func.func private @caller(%b: i64) -> i64 {
    %t = func.call @ignores(%b) : (i64) -> i64
    return %t : i64
  }
  func.func @main(%a: i64) -> (i64, (i64) -> i64) {
    %f = func.constant @ignores : (i64) -> i64
    %t = func.call @caller(%a) : (i64) -> i64
    return %t, %f : i64, (i64) -> i64
  }
}
```

----- end -----
