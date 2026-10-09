# [mlir] `composite-fixed-point-pass` never converges with `sccp` in its pipeline

At `llvmorg-23.1.2`, `composite-fixed-point-pass` runs a pipeline that has
`sccp` in it until `max-iterations`, and then warns, on a module that is
already at the pipeline's fixpoint. The pass decides convergence by
`OperationFingerPrint`, which hashes the identity of the module's
operations, blocks and values, and `sccp` replaces every constant it meets
by an equal one it makes, even when it propagates nothing, so the
fingerprint is new after every run although the module prints the same.

## Reproduce

`one.mlir` (one constant, used by an operation that cannot fold it):

```mlir
func.func @one() -> i32 {
  %c = arith.constant 1 : i32
  return %c : i32
}
```

```
$ mlir-opt one.mlir --composite-fixed-point-pass='pipeline=sccp max-iterations=5'
one.mlir:0:0: warning: Composite pass "CompositeFixedPointPass"+ didn't converge in 5 iterations
one.mlir:0:0: note: see current operation:
module {
  func.func @one() -> i32 {
    %c1_i32 = arith.constant 1 : i32
    return %c1_i32 : i32
  }
}
```

`mlir-opt` exits 0 with the module unchanged. `--log-actions-to=-` shows
`sccp` running six times; `mlir-opt one.mlir --sccp` prints the same
module, and so does `--sccp` on that output. `pipeline=canonicalize`,
`pipeline=cse` and `pipeline=remove-dead-values` each converge after one
run on the same module, and so does `pipeline=sccp` on a module with no
constant in it. With `-mlir-print-debuginfo`, the constant `sccp` prints
has lost its location (`loc(unknown)`), and
`--sccp --mlir-print-ir-after-all --mlir-print-ir-after-change` prints
after `sccp`; with `--canonicalize` or `--cse` it prints nothing.

For a constant that is not trivially dead the IR grows: with
`%0 = "emitc.constant"() {value = 1 : ui32} : () -> ui32` used by
`emitc.switch`, `--sccp --sccp --sccp` leaves four `emitc.constant`
operations.

## Cause

`CompositeFixedPointPass::runOnOperation`
(`mlir/lib/Transforms/CompositePass.cpp:68`) runs its pipeline, takes an
`OperationFingerPrint` of the operation and stops when it equals the one
taken before the run. `OperationFingerPrint`
(`mlir/lib/IR/OperationSupport.cpp:933`) hashes the address of every
operation, block, argument, operand and successor along with the uniqued
attributes, properties, location and result types: two modules that print
the same differ whenever an operation was erased and an equal one made.

`sccp`'s `rewrite` (`mlir/lib/Transforms/SCCP.cpp:67-110`) walks every
operation and, for each result whose lattice is a constant,
`replaceWithConstant` (`SCCP.cpp:42-62`) asks
`OperationFolder::getOrCreateConstant`
(`mlir/lib/Transforms/Utils/FoldUtils.cpp:207`) for the constant of that
value, replaces all uses of the result with it, and erases the operation if
it is trivially dead (`SCCP.cpp:93-99`). A constant operation's own result
has a constant lattice: `SparseConstantPropagation` folds it to its value
(`mlir/lib/Analysis/DataFlow/ConstantPropagationAnalysis.cpp:75-100`). The
folder is made fresh for each run (`SCCP.cpp:77`) and is never told about
the constants the IR already holds, which the greedy driver does with
`OperationFolder::insertKnownConstant` before it rewrites anything
(`mlir/lib/Transforms/Utils/GreedyPatternRewriteDriver.cpp:858`). So
`tryGetOrCreateConstant` (`FoldUtils.cpp:309`) materializes a new constant,
with the folder's erased location, at the front of the entry block; the
uses move to it and the original is erased, or, when it is not trivially
dead (`emitc.constant` has no memory-effect trait), kept beside it.
`-mlir-print-ir-after-change` (`mlir/lib/Pass/IRPrinting.cpp:107-116`)
compares the same fingerprint.

## Proposed fix

Two parts. Part 1 is an `sccp` bug on its own: a run that propagates
nothing must leave the IR as it is, and the `emitc.constant` case grows the
IR, which no change to the composite pass can hide. Part 2 would make
the composite pass right for any pass that remakes an operation in place;
it is a note here, not sent (see the plan).

1. `sccp`: `rewrite` gives each constant it reaches to the folder
   (`insertKnownConstant`) and does not replace it. The folder then hands
   that constant out for its value, and may hoist it or merge it into an
   equal one it already holds. The constant is not looked up through the
   folder for itself, because a lookup erases the location of the constant
   it returns. Constants are given as the walk reaches them, not up front
   as the greedy driver does, so a constant nested in an operation that
   `sccp` erases (a loop whose results all fold) goes with it instead of
   being hoisted out and left dead.
2. `composite-fixed-point-pass`: decide the fixpoint on the IR, not on
   identity. A fingerprint that hashes each operation by its name,
   attributes, properties, result types and location, as
   `OperationEquivalence::computeHash` (`OperationSupport.cpp:678`) does,
   with each operand hashed as the position of its defining value in a
   pre-order numbering of the block arguments and results. An operation
   remade in place then hashes the same. `OperationFingerPrint` keeps its
   use as an identity check, which the greedy driver's and the dialect
   conversion's expensive checks rely on.

## Our workaround

`PINS.md`: `simplify-structural-fixpoint`. `idr-simplify`
(`foreign/idr/lib/Simplify/Pass.cc`) runs `composite-fixed-point-pass` over
its round, so the fixpoint is that pass's `OperationFingerPrint`. The patch
stops `sccp` remaking constants. `idr-dead-values` leaves a call
`remove-dead-values` would rebuild without erasing a result, so a round at
the fixpoint keeps the fingerprint (`tests/idr/canon/upstream-passes`,
`tests/idr/loops/tail-loop`). Without the patch every module would run to
the round budget and fail.

## Patch

`llvm.patch` is part 1: in `rewrite` (`SCCP.cpp`), an operation that
matches `m_Constant` is given to the folder with `insertKnownConstant` and
skipped. The same diff applies to llvm main, so there is no separate
`pull-request.diff`. The skip is the one branch, and it is honest: a
constant is the form the rewrite produces, and routing it through
`getOrCreateConstant` would erase its location. The fix stays in `sccp`
rather than in `OperationFolder`: the folder uniques the constants its
client tells it about, and the greedy driver, its other client, already
tells it; making `getOrCreateConstant` search the IR for an equal
constant would change that contract for every client and still miss a
constant outside the insertion block. Seeding the folder up front with a
walk, as the greedy driver does, was tried and rejected: it hoists the
constants out of a loop `sccp` then erases and leaves them dead
(`@loop_inner_control_flow` in `sccp-structured.mlir`).

One behaviour change beyond the fix, stated in the pull request: a
constant in a block the analysis found dead is now hoisted to the entry
block and uniqued, as `canonicalize` does, where `sccp` used to leave it.

Test: a second RUN line in `mlir/test/Transforms/sccp.mlir` runs every
case under `composite-fixed-point-pass{pipeline=sccp max-iterations=2}`
with `-verify-diagnostics` and the same CHECK lines. `-verify-diagnostics`
turns the non-convergence warning into a failure, so the line checks the
property (a second run of `sccp` keeps the fingerprint), and the CHECK
lines check that wrapping `sccp` does not change its output.
`max-iterations=2` because the first run legitimately changes the input.
`sccp.mlir`, `sccp-structured.mlir` and `sccp-callgraph.mlir` are the
only tests in the tree that run `sccp`.

Verified while the pin was llvmorg-23.1.2, with an `mlir-opt` linked from
its static libraries and its patched `SCCP.cpp`: `sccp-structured.mlir`
and `sccp-callgraph.mlir` pass as they are; the patched 23.1.2 `sccp.mlir`
and the patched main `sccp.mlir` pass both RUN lines, and the new line
fails with the unpatched `mlir-opt` (a warning on 11 of 16 functions).
Cases the 23.1.2 `mlir-opt` cannot run were removed from the local copies:
the three test-dialect cases (`@simple_produced_operand`, `@inplace_fold`,
`@op_with_region`), and from the main copy
`@no_crash_acc_kernel_environment` (newer syntax) and
`@no_inplace_extract_fold_of_speculative_constant` (needs #213933). The
patched `SCCP.cpp` from main passes `clang-format` and `-fsyntax-only`
against main's headers. `one.mlir` converges with `max-iterations=1`,
keeps the constant's location, and `-mlir-print-ir-after-change` prints
nothing after `sccp`. `tests/upstream/composite-fixed-point-sccp` checks
the reproducer.

## Testing on main

On llvm main at 7208ba24 (2026-10-08), with the seven code diffs of
01-08 applied together (02-07's `llvm.patch` and 08's
`pull-request.diff`), a Release build with assertions
(`-DLLVM_ENABLE_PROJECTS=mlir -DLLVM_TARGETS_TO_BUILD=Native
-DBUILD_SHARED_LIBS=ON -DLLVM_ENABLE_ASSERTIONS=ON`, clang 18, x86_64
Linux) builds without errors and passes `ninja check-mlir`: 4102 passed,
630 unsupported, 1 expectedly failed, none failed.

Then, on the same build, with this patch's `SCCP.cpp` change alone
reverted and `mlir-opt` rebuilt: `Transforms/sccp.mlir` fails (the new
RUN line warns that the composite pass did not converge); with the
change back, it passes. Every case of `sccp.mlir` ran, the test-dialect
ones included.

## Upstreaming plan

Status: file upstream. Still broken on llvm main at 7208ba24 (2026-10-08):
`SCCP.cpp`, `FoldUtils.cpp` and the composite pass's fingerprint check are
unchanged from llvmorg-23.1.2, and no issue or pull request addresses it
(searched llvm/llvm-project for sccp, insertKnownConstant and
composite-fixed-point-pass; the nearest are #213933, which reverts
in-place folds during the analysis, and #218394, which makes the composite
pass's convergence failure configurable).

- Where: a GitHub issue and a pull request to llvm/llvm-project. Not
  Bugzilla. The text to paste is `submission.md`. The issue is the `sccp`
  bug only; the pull request is one commit, `llvm.patch`, which applies
  unchanged to main (the pin), and its body is the squash commit
  message, ending `Fixes #<issue>`. Part 2 is not in the issue: with
  `sccp` fixed, nothing in the tree is known to need it, and it changes
  what a public utility promises; it would be its own RFC if a pass is
  found that remakes an operation in place.
- Upstream test: the second RUN line in `mlir/test/Transforms/sccp.mlir`
  (see Testing on main).
- Dropped when the pin includes the fix to `sccp`.
