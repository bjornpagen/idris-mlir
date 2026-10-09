# [mlir][SCCP] sccp keeps a property that an in-place fold sets on an op that had none

On llvm main at 7208ba24 (the pin), sccp simulates each operation's fold
and then reverts what the fold changed in place. That revert cannot undo a
property the fold set where the operation had none. The `arith.extui`
folder shows it: folding an `extui` of an `extui` in place, it takes the
inner one's `nneg` flag, and sccp keeps it.

## Reproduce

`unset-property.mlir`:

```mlir
func.func @unset_property(%x: i3) -> i16 {
  %a = arith.extui %x nneg : i3 to i8
  %b = arith.extui %a : i8 to i16
  return %b : i16
}
```

`mlir-opt unset-property.mlir --sccp` prints `%b` as
`%1 = arith.extui %0 nneg : i8 to i16`; `mlir-opt unset-property.mlir`
prints it without `nneg`, and that is the only line that differs.
`tests/upstream/sccp-revert-unset-property` checks the reproducer.

Where it comes from: `foldsWith` (`foreign/idr/lib/Canon/Feeds.cppm`)
copies sccp's fold simulation. Making it restore whatever the fold returned,
as #213933 made sccp do, showed that sccp's revert of properties, from their
attribute form, cannot clear one; `foldsWith` copies the properties storage
instead (d426e24a).

## Expected

sccp leaves the module as it was: it propagates nothing here, and an
analysis's simulated fold must not change the IR.

## Cause

- `SparseConstantPropagation::visitOperation`
  (`mlir/lib/Analysis/DataFlow/ConstantPropagationAnalysis.cpp:69-90`)
  saves the operands, the discardable attributes and
  `getPropertiesAsAttribute()` before the fold (`:72-74`). After it, it
  restores the operands if they changed, the discardable attributes, and
  the properties with `setPropertiesFromAttribute` when the saved attribute
  is not null (`:85-90`). The revert is unconditional since #213933, and the
  properties are restored from their attribute form since #218878.
- The attribute form lists only the attribute-backed properties that are
  set: `appendAttributeProperty` skips a null one
  (`mlir/lib/IR/OperationSupport.cpp:26-31`), and an operation with none
  set has no attribute form at all (`return {}`,
  `mlir/tools/mlir-tblgen/OpDefinitionsGen.cpp:1448-1450`). So sccp
  restores nothing for such an operation.
- Restoring from a form that lacks the property does not clear it either.
  The generated setter reads each attribute-backed property with
  `dict.get` (`OpDefinitionsGen.cpp:1388`, `:1403`), and
  `detail::setAttributeProperty` returns success and leaves the property as
  it was when the attribute is null
  (`mlir/include/mlir/IR/OperationSupport.h:82-96`, `:86`).
- `arith::ExtUIOp::fold` (`mlir/lib/Dialect/Arith/IR/ArithOps.cpp:1809-1825`)
  folds an `extui` of an `extui` in place: `setNonNeg(lhs.getNonNeg())`
  (`:1813`), then the operand. sccp puts the operand back, and the flag
  stays.

The flag is true in this case, since `%b`'s operand is a zero extension and
so never negative. But any fold that sets an unset attribute-backed property
in place would leave it after sccp, true or not.

## The fix

`pull-request.diff` copies the properties storage before the fold and
copies it back after it, as the conversion driver's `ModifyOperationRewrite`
rolls back an in-place modification
(`mlir/lib/Transforms/Utils/DialectConversion.cpp:681-745`, `rollback` at
`:723`). It uses `OperationName::initOpProperties` to copy, then
`Operation::copyProperties` and `destroyOpProperties`. That restores every
property exactly, set or not. The operands and the discardable attributes
are restored as before.

Test: a new case at the end of `mlir/test/Transforms/sccp.mlir`, after
#213933's regression test, which is the reproducer with CHECK lines for
the unchanged `%b`.

## Why there is no patch

There is no `llvm.patch`, and there is no `PINS.md` entry. The bug
cannot change what the compiler computes, so carrying the patch would only
make every checkout rebuild the toolchain.

- The bug needs a fold that sets an unset property in place. No folder of
  ours sets a property in place (findings/llvm-trunk-mechanisms.md). In the
  fold bodies of the upstream dialects the compiler's IR holds where
  constant propagation runs (arith, math, ub, index, scf, vector, memref,
  affine, llvm; read at the pin), the properties set in place are required
  ones, which the attribute form always lists: `arith.cmpi`'s predicate,
  `memref.transpose`'s permutation, the affine delinearize and linearize
  ops' static basis, `llvm.extractvalue`'s position, and
  `llvm.getelementptr`'s constant indices. The one exception is
  `arith.extui`'s `nneg`. The helpers those bodies call were not all read.
- Before `idr-narrow`, no operation has `nneg`: Emit makes none. So
  `sccp` in the simplify round (`foreign/idr/lib/Simplify/Round.cppm`),
  whose fixpoint is an `OperationFingerPrint`, and the solver of
  `idr-defunctionalize` (`foreign/idr/lib/Defunctionalize/Sums.cppm`)
  never meet the bug.
- `idr-narrow` and `idr-narrow-lanes` set `nneg` on an `arith.extui`
  whose range is non-negative and fits 32 bits
  (`foreign/idr/lib/Narrow/Copy.cppm`). Constant propagation runs after
  that, in their solvers and in `idr-in-bounds`'s (`narrow::runSolver` in
  `Narrow/Naturals.cppm`, `Copy::analyse` in `Narrow/Copy.cppm`). There
  the fold can only add a flag that is true: the `extui` it folds takes a
  zero extension, which is never negative. So the IR may change, but not
  its meaning, and none of those passes compares fingerprints.

The pull request is still one we intend to send, drafted as
`pull-request.diff`, which the bootstrap does not apply.

## Testing at the pin

On arm64 macOS, with `.toolchain/llvm-macos` (7208ba24 with 02-07, 09 and
15 applied; none of them touches `ConstantPropagationAnalysis.cpp`):

- `pull-request.diff` applies to 7208ba24 (`git apply --check` in
  `.toolchain/llvm-project`), and after 02's change to `sccp.mlir`.
- The patched `ConstantPropagationAnalysis.cpp` passes `-fsyntax-only`
  (`-std=c++17 -fno-rtti -fno-exceptions -Wall -Wextra`) with the
  toolchain's clang against its headers. The changed lines are
  clang-format clean under trunk's `.clang-format` (Xcode's clang-format 21).
- The new case, run alone with `sccp.mlir`'s RUN line
  (`-pass-pipeline="builtin.module(func.func(sccp))" -split-input-file`),
  fails with the toolchain's unpatched `mlir-opt`: `%b` prints with
  `nneg`. Its CHECK lines pass on the same file run without sccp. The whole
  `sccp.mlir` does not run here: it uses the test dialect, which the
  toolchain's `mlir-opt` does not register.

Not run with the change: no `mlir-opt` with it has been built, so the new
case has not been seen to pass, and `check-mlir` has not run.

## Upstreaming plan

Status: not filed, not ready. llvm main still has the bug: on 2026-10-09
`ConstantPropagationAnalysis.cpp` on GitHub's main was byte for byte the
pin's. No issue or pull request covers it: searched llvm/llvm-project for
sccp, in-place folds and properties. The nearest are #213933 and #218878,
both merged, which this follows.

- Where: one pull request to llvm/llvm-project (MLIR, dataflow), as
  `submission.md` says. There is no issue: the pull request carries the
  reproducer. Its title and body are the squash commit message.
- Upstream test: the new case at the end of
  `mlir/test/Transforms/sccp.mlir`.
- Before sending: build `mlir-opt` with the diff on then-current main. The
  new case must pass, and fail with the `ConstantPropagationAnalysis.cpp`
  change reverted. `check-mlir` must pass.
- Independent of 02 (`composite-fixed-point-sccp`): 02 changes `SCCP.cpp`
  and `sccp.mlir`'s RUN lines, this the analysis and the end of
  `sccp.mlir`. Either can land first; this diff applies after 02's.
- Nothing in this repository depends on it. When the pin includes the fix,
  `tests/upstream/sccp-revert-unset-property` fails, and this directory and
  that check go.
