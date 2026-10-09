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

Trunk (7208ba24, 2026-10-08) is the same: `processFuncOp` now also skips a
function with uses it cannot see (`RemoveDeadValues.cpp:280-292`), which
keeps more signatures, and the cleanup still drops the dead argument's
uses (`:657`). See Testing on main.

## Fix

[llvm/llvm-project#208881](https://github.com/llvm/llvm-project/pull/208881)
replaces the remaining uses of a dead function argument with `ub.poison`
instead of dropping them. That covers this call: the fix sits where the
use is lost, not in why the use survives, so the call of `@ignores` takes
`ub.poison : i64`. Checked with llvmorg-23.1.2's `RemoveDeadValues.cpp`
(the pin then) plus only #208881's source change, linked into an
`mlir-opt`: the reproducer and the public variant exit 0 and verify, and
the test in `submission.md` passes under both of the file's RUN lines as a
standalone file. As a diff appending it to trunk's
`remove-dead-values.mlir`, it passes `git apply --check`.

The carried fix is `upstream/06-remove-dead-values-unreachable/llvm.patch`,
whose one helper poisons the uses of a dead function argument as #208881
does. It does not carry this test: it is 06's pull request, which leaves
the test to #208881. `tests/upstream/remove-dead-values-address-taken`
checks the reproducer against the pinned tools.

## Testing on main

On llvm main at 7208ba24 (2026-10-08), with the seven code diffs of
01-08 applied together (02-07's `llvm.patch` and 08's
`pull-request.diff`), a Release build with assertions
(`-DLLVM_ENABLE_PROJECTS=mlir -DLLVM_TARGETS_TO_BUILD=Native
-DBUILD_SHARED_LIBS=ON -DLLVM_ENABLE_ASSERTIONS=ON`, clang 18, x86_64
Linux) builds without errors and passes `ninja check-mlir`: 4102 passed,
630 unsupported, 1 expectedly failed, none failed.

This bug's test is not in that build (it is a comment on #208881, not a
diff). Run on main at 7208ba24 as its own file with
`remove-dead-values.mlir`'s two RUN lines: it fails under both without a
fix, passes under both with only #208881's source change, and passes
under both with 06's change.

## Why there is no patch

The fix is #208881's function-argument change, which
`remove-dead-values-unreachable/llvm.patch` makes too. This case adds a
test, not code, and the test is not carried: that patch is 06's pull
request, which does not include it, and a second patch appending to
`mlir/test/Transforms/remove-dead-values.mlir` would not apply after it.
`tests/upstream/remove-dead-values-address-taken` checks the
reproducer.

## Upstreaming plan

Status: posted 2026-10-08 as a comment on
https://github.com/llvm/llvm-project/pull/208881
(https://github.com/llvm/llvm-project/pull/208881#issuecomment-6073061698), with its prose unwrapped
so GitHub does not render the hard line breaks. #208881 was open,
approved and not merged then (its source change applies to trunk at
7208ba24, its test hunk no longer does). Next: wait for #208881's author
or reviewers; if it lands without the test, send the test-only pull
request `submission.md` describes. Trunk's `remove-dead-values.mlir` has no case like
this one. No new issue. No second pull request unless #208881 lands
without such a test; `submission.md` says what to send then. Author is
Bjorn, individual, work done outside any employer. No @mentions.

- Where: one comment on #208881; the text is `submission.md`.
- Upstream test: the `@address_taken_callee` module in `submission.md`,
  for `mlir/test/Transforms/remove-dead-values.mlir`.
- Dropped with `remove-dead-values-unreachable/llvm.patch`, when the pin
  includes #208881; `tests/upstream/remove-dead-values-address-taken`
  goes with it.
