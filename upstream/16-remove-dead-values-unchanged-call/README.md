# [mlir] `remove-dead-values` replaces a call it erases no result of with an identical one

On llvm main at 7208ba24 (the pin), `--remove-dead-values` replaces every
call of a private function that returns a value with a new, identical
call, whether or not it erases a result from it. The module prints the
same, but the call is a new operation, so `OperationFingerPrint` changes:
`composite-fixed-point-pass` with `remove-dead-values` in its pipeline never
sees a run that changes nothing on such a module, and
`-mlir-print-ir-after-change` prints after the pass.

## Reproduce

`unchanged-call.mlir` (a private function and its one call, which uses its
result):

```mlir
func.func private @inc(%x: i64) -> i64 {
  %c1 = arith.constant 1 : i64
  %y = arith.addi %x, %c1 : i64
  return %y : i64
}

func.func @main(%x: i64) -> i64 {
  %y = func.call @inc(%x) : (i64) -> i64
  return %y : i64
}
```

`mlir-opt unchanged-call.mlir --remove-dead-values` prints what
`mlir-opt unchanged-call.mlir` prints, with `canonicalize=false` too: the
pass has nothing to erase. It still changes the module:

```
$ mlir-opt unchanged-call.mlir --composite-fixed-point-pass='pipeline=remove-dead-values max-iterations=1 on-convergence-failure=error'
unchanged-call.mlir:0:0: error: Composite pass "CompositeFixedPointPass"+ didn't converge in 1 iterations
```

`mlir-opt` exits 1, and the same with `remove-dead-values{canonicalize=false}`.
`--remove-dead-values --mlir-print-ir-after-all --mlir-print-ir-after-change`
prints the module after the pass. With `@inc` public, or with a call that
has no result, the composite pass converges after one run.
`tests/upstream/remove-dead-values-unchanged-call` checks the reproducer.

Where it comes from: the module of `tests/idr/pipeline/fixpoint.mlir`, which
`idr-dead-values` keeps as it is while `remove-dead-values` does not (each
pass under the composite pass above, run through `idris-mlir-reduce
--opt-reduction-pass`). Its idr ops were replaced by upstream ones by hand
(the closure by `func.constant` and `func.call_indirect`, the literal match
by `scf.if`, the world by an argument and a result): idris-mlir-reduce
cannot replace an op whose result is used, and leaves null operands that
the idr verifier does not survive. On that module, `idris-mlir-reduce
--reduction-tree` with the test "the pinned `mlir-opt` parses it,
`remove-dead-values{canonicalize=false}` prints it as it was, and the
composite pass over that does not converge in one run" erases nothing,
since every op's result reaches a return, and `--opt-reduction-pass` with
`canonicalize` only hoists its constants. The last step was by hand: the
closure specialized away, as the simplify loop does, and the recursion
dropped, which leaves a direct call of `@inc`. The test holds of the
result, and idris-mlir-reduce erases nothing from it.

## Expected

A run of the pass that erases nothing leaves every operation as it is, so
the composite pass stops after one run, as it does with `canonicalize` or
`cse` on a module at their fixpoint.

## Cause

- `processFuncOp` (`mlir/lib/Transforms/RemoveDeadValues.cpp:272`) lists
  every call of a private function whose users are all calls, with the
  results to erase from it (`:362-376`, pushed at `:374`). The set is empty
  when every result of the function is live at some call; only a function
  without results is skipped (`:363`).
- The cleanup erases the listed results of each listed call through
  `dropUsesAndEraseResults` (`:201-209`, called at `:733`), which calls
  `RewriterBase::eraseOpResults`.
- `eraseOpResults` (`mlir/lib/IR/PatternMatch.cpp:278-314`) has no case
  for an empty set: it creates an operation with the same name, operands,
  result types, attributes and properties, moves the regions into it, and
  replaces the original with it (`:312`).
- `OperationFingerPrint` (`mlir/lib/IR/OperationSupport.cpp:986`) hashes
  the address of every operation, and `composite-fixed-point-pass` stops
  when the fingerprint after a run equals the one before it
  (`mlir/lib/Transforms/CompositePass.cpp:69-103`).
  `-mlir-print-ir-after-change` compares the same fingerprint.

Every other erasure the pass makes treats an empty set as nothing to do.
`RewriterBase::eraseOperands` returns early on one (`PatternMatch.cpp:250`),
and the pass's operand cleanup asks `nonLive.any()` first
(`RemoveDeadValues.cpp:711`). A function's `eraseArguments` and
`eraseResults` (`:661`, `:669`) keep the operation and, for an empty set,
set the type it already has. The two other callers of `eraseOpResults` in
the tree check for an empty set before they call it
(`mlir/lib/Interfaces/ControlFlowInterfaces.cpp:953`,
`mlir/lib/Dialect/SCF/IR/SCF.cpp:1583`).

## Patch

`llvm.patch` is the pull request, a `git diff` against 7208ba24, the pin.
`RewriterBase::eraseOpResults` returns `op` unchanged when `eraseIndices`
selects no result, as `eraseOperands` does for operands, and its comment
in `PatternMatch.h` says so. Nothing else in the tree asks it for an empty
set, so only `remove-dead-values` behaves differently: a call it erases no
result of stays the operation it was.

The check is in `eraseOpResults` rather than in the pass (listing a call
only when its set is not empty, at `RemoveDeadValues.cpp:363`) because the
pass relies on every other erasure treating an empty set as nothing to do,
and the other callers each guard against it themselves. Either fixes the
bug; if review prefers the pass, the one line moves there and the test
stays.

Test: a new file, `mlir/test/Transforms/remove-dead-values-fixed-point.mlir`,
modelled on the second `sccp.mlir` RUN line of
`upstream/02-composite-fixed-point-sccp`. Its two RUN lines, with the pass's
canonicalization and without, run each case under
`composite-fixed-point-pass{pipeline=remove-dead-values max-iterations=2}`
with `-verify-diagnostics`, so they fail on the non-convergence warning
unless the pass's output is its own fixed point, and FileCheck checks what
the pass leaves. The cases: a call none of whose results is dead
(`@call_with_live_result`, the reproducer), and a call one of whose results
the first run erases (`@call_with_one_dead_result`), which the second run
must leave as it is. The test is a file of its own because a RUN line
covers every case of its file, and those of `remove-dead-values.mlir` were
not written to be fixed points of the pass. It uses func and arith only.

The patch touches no file the other patches touch, so it applies to the
pinned source alone and after 02-07 and 09
(`tests/spec/upstream-patches`).

## Testing at the pin

On arm64 macOS, with a scratch `mlir-opt`: a main that registers every
upstream dialect, extension and pass (no test dialect), and
`PatternMatch.cpp` with this patch, compiled by Apple clang 21 with the
toolchain's flags (`-std=c++17 -fno-rtti -fno-exceptions`, assertions on)
and linked against the static `libMLIR*.a` and `libLLVM*.a` of
`.toolchain/llvm-macos` (7208ba24 with 02-07 and 09 among its patches).

- Both RUN lines of the new test pass (`mlir-opt | FileCheck` under
  `pipefail`, with the toolchain's `FileCheck`). With the toolchain's
  unpatched `mlir-opt` both fail, with an unexpected non-convergence
  warning on each case.
- `unchanged-call.mlir` converges after one run, and
  `-mlir-print-ir-after-change` prints nothing after the pass.
- `remove-dead-values.mlir` as 06's patch leaves it, under `canonicalize=0`
  and `canonicalize=1`, prints byte for byte what the toolchain's `mlir-opt`
  prints (its test-dialect cases fail to parse in both). So do the
  `remove-dead-values-*.mlir` files and `composite-pass.mlir`, and
  `Dialect/SCF/canonicalize.mlir` under `--canonicalize`. Under
  `--remove-dead-values=canonicalize=1` that last file's output varies from
  run to run with either binary (an `scf.while` case), which this patch
  does not touch.
- The changed lines of `PatternMatch.cpp` are clang-format clean under
  trunk's `.clang-format`.

`check-mlir` has not run with this patch.

## Our workaround, which this replaces

`idr-dead-values` ran `remove-dead-values` on a copy of the module and kept
the module when the copy hashed the same up to operation identity. With the
patch, the simplify round runs `remove-dead-values{canonicalize=false}`
itself, and the loop's fingerprint repeats at its fixpoint (`PINS.md`:
`remove-dead-values-unchanged-call`).

## Upstreaming plan

Status: not filed. `check-mlir` not run on main. Whether main past
7208ba24 fixes it is not known: it was read at the pin only, from a host
without network access.

- Where: a GitHub issue (the reproducer: `remove-dead-values` replaces a
  call it erases nothing from, and `composite-fixed-point-pass` over it does
  not converge) and a pull request against llvm main, one commit,
  `llvm.patch`. Before filing: search llvm/llvm-project for
  `eraseOpResults` and `remove-dead-values` fixed-point issues; check that
  the diff applies to then-current main and is clang-format clean, and that
  the new test fails with the `PatternMatch.cpp` change reverted (shown at
  the pin, against the toolchain's libraries); `check-mlir` is the pull
  request's pre-merge CI's (upstream/README.md, **CI decides**). There is
  no `submission.md` yet.
- Upstream test: `mlir/test/Transforms/remove-dead-values-fixed-point.mlir`.
- Independent of 06 (`remove-dead-values-unreachable`): neither changes a
  file the other changes, and either can land first.
- The patch is dropped when the pin includes the fix (or an equivalent one
  in the pass); then this directory, its check and its `PINS.md` entry go,
  and the simplify round keeps running `remove-dead-values` as it is.
