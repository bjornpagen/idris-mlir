# [mlir] `remove-dead-values` leaves a null operand in a call of a function whose signature it keeps

At `llvmorg-23.1.2`, `--remove-dead-values` leaves a `func.call` with a
null operand when a private function passes one of its own arguments to a
function the pass must leave alone (one named by `func.constant`, say)
and that function never reads the parameter.

## Reproduce

`address-taken.mlir`:

```mlir
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
```

```
$ mlir-opt address-taken.mlir --remove-dead-values
address-taken.mlir:7:8: error: null operand found
  %t = func.call @ignores(%b) : (i64) -> i64
       ^
note: see current operation: %0 = "func.call"(<<NULL VALUE>>) <{callee = @ignores}> : (<<NULL TYPE>>) -> i64
```

`mlir-opt` exits 1. Making `@ignores` public instead of naming it with
`func.constant` fails the same way. When the value passed is an op result
instead of a block argument, the pass already replaces it with `ub.poison`
and the module stays valid.

## Cause

The liveness is right: the backward analysis meets each call operand with
the callee's entry-block argument
(`mlir/lib/Analysis/DataFlow/SparseAnalysis.cpp:533`), whatever else names
the callee, and `@ignores` never reads `%x`, so `%b` is dead.

`processFuncOp` (`mlir/lib/Transforms/RemoveDeadValues.cpp:284`) returns
early for `@ignores`, because a non-call op uses its symbol (or, at
`:278`, because it is public): its signature stays and its calls keep all
their operands. The driver does nothing for a call op itself (`:807`).
For `@caller`, which is private and only called, `processFuncOp` marks
`%b` non-live (`:292`) and records it (`:355`). The cleanup drops every
use of `%b` (`:643-645`) and erases it (`:649`). The call of `@ignores`
is one of those uses, and nothing else touches it.

## Fix

[llvm/llvm-project#208881](https://github.com/llvm/llvm-project/pull/208881)
replaces the remaining uses of a dead function argument with `ub.poison`
instead of dropping them. That covers this call: the fix sits where the
use is lost, not in why the use survives, so the call of `@ignores` takes
`ub.poison : i64`. Checked with the pinned `RemoveDeadValues.cpp` plus
only #208881's source change, linked into an `mlir-opt`: the reproducer
and the public variant exit 0 and verify, and the test in `submission.md`
passes under both of the file's RUN lines.

The carried fix is `remove-dead-values-unreachable/llvm.patch`, which
includes #208881's function-argument change and this test.

## Why there is no patch

The fix is #208881's function-argument change, which
`remove-dead-values-unreachable/llvm.patch` already carries. This case adds
a test, not code, and the test goes in that patch: a second patch
appending to `mlir/test/Transforms/remove-dead-values.mlir` would not
apply after the first.

## Upstreaming plan

Status: file as a comment on
https://github.com/llvm/llvm-project/pull/208881 (open, approved, not
merged). No new issue. No second pull request. Author is Bjorn,
individual, work done outside any employer. No @mentions.

- Where: one comment on #208881; the text is `submission.md`.
- Upstream test: the `@address_taken_callee` module in `submission.md`,
  for `mlir/test/Transforms/remove-dead-values.mlir`.
- Dropped with `remove-dead-values-unreachable/llvm.patch`, when the pin
  includes #208881; `tests/upstream/remove-dead-values-address-taken`
  goes with it.
