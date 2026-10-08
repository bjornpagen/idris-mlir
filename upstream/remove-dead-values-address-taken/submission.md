# Submission

Where: a comment on https://github.com/llvm/llvm-project/pull/208881
(open, approved, not merged as of trunk 7208ba24, 2026-10-08). No new
issue, no pull request of its own. Author is Bjorn, as an individual,
work done outside any employer. No @mentions.

If #208881 is merged before this is posted and the merged test file has
no case like `@address_taken_callee`, post the test instead as its own
pull request: title `[mlir][RemoveDeadValues] Test a kept callee's dead
operand` (58 characters), the first paragraph below reworded to say
#208881 fixed it, and the block appended to
`mlir/test/Transforms/remove-dead-values.mlir`.

Paste everything between the markers.

----- paste -----

This also fixes a second way to reach the null operand: the dropped use is
an operand of a call to a function whose signature the pass keeps. A
callee referenced by a non-call op (`func.constant` below), or a public
one, is skipped by `processFuncOp`, so its calls keep all their operands.
If it never reads a parameter, liveness marks the caller's argument passed
there dead, and the caller, private and only called, drops all uses of
that argument, including the operand of the call. Without this PR the
module below fails with `null operand found` at `func.call @ignores`
(checked at llvmorg-23.1.2; trunk has the same `dropAllUses`). With it
the call takes `ub.poison`.

A test for the end of `mlir/test/Transforms/remove-dead-values.mlir`. It
passes under both RUN lines with this PR's change to RemoveDeadValues.cpp.
The test hunk here no longer applies at trunk, since a test was appended
after `@func_with_non_call_users`; both can go at the end of the file.

```mlir
// -----

// Verify that a call of a function referenced by a non-call op (func.constant)
// keeps all its operands: the callee's signature is preserved, so an argument
// of the caller that the pass erases because the callee never reads it is
// passed as poison.
// CHECK-LABEL: module @address_taken_callee
// CHECK:         func.func private @ignores(%{{.*}}: i64) -> i64
// CHECK:         func.func private @caller() -> i64
// CHECK:           %[[P:.*]] = ub.poison : i64
// CHECK:           call @ignores(%[[P]]) : (i64) -> i64
// CHECK-CANONICALIZE-LABEL: module @address_taken_callee
// CHECK-CANONICALIZE:         func.func private @ignores(%{{.*}}: i64) -> i64
// CHECK-CANONICALIZE:         func.func private @caller() -> i64
// CHECK-CANONICALIZE:           %[[P:.*]] = ub.poison : i64
// CHECK-CANONICALIZE:           call @ignores(%[[P]]) : (i64) -> i64
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
