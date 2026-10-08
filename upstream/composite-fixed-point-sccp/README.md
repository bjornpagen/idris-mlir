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
IR, which no change to the composite pass can hide. Part 2 makes the
composite pass right for any pass that remakes an operation in place.

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
(`foreign/idr/lib/Simplify/Pass.cc`) is its own loop over the round and
decides the fixpoint by `OperationFingerPrint`. The patch stops `sccp`
remaking constants. `idr-dead-values` leaves a call `remove-dead-values`
would rebuild without erasing a result, so a round at the fixpoint keeps
the fingerprint (`tests/idr/canon/upstream-passes`,
`tests/idr/loops/tail-loop`). The loop stays: this pass warns and goes on
at its budget, and the round's statistics and remarks are the loop's. Over
its round budget the loop fails with a named error.

## Patch

`llvm.patch` is part 1: in `rewrite` (`SCCP.cpp`), an operation that
matches `m_Constant` is given to the folder with `insertKnownConstant` and
skipped. The skip is the one branch, and it is honest: a constant is the
form the rewrite produces, and routing it through the folder would erase
its location. Seeding the folder up front with a walk, as the greedy driver
does, was tried and rejected: it hoists the constants out of a loop `sccp`
then erases and leaves them dead (`@loop_inner_control_flow` in
`sccp-structured.mlir`).

Test: a second RUN line in `mlir/test/Transforms/sccp.mlir` runs every
case under `composite-fixed-point-pass{pipeline=sccp max-iterations=2}`
with `-verify-diagnostics` and the same CHECK lines: one run of `sccp`
reaches its fixed point. `sccp.mlir`, `sccp-structured.mlir` and
`sccp-callgraph.mlir` are the only tests in the tree that run `sccp`.

Verified with an `mlir-opt` linked from the pinned static libraries and the
patched `SCCP.cpp`: all three `sccp` test files pass as they are; the new
RUN line passes, and fails with the unpatched `mlir-opt` (a warning per
function); the same RUN line added to `sccp-structured.mlir` and
`sccp-callgraph.mlir` passes too. The three `sccp.mlir` cases that use the
test dialect (`@simple_produced_operand`, `@inplace_fold`,
`@op_with_region`) could not be run here, since the installed `mlir-opt`
has no test dialect; they were removed from the local copy. `one.mlir`
converges with `max-iterations=1`, keeps the constant's location, and
`-mlir-print-ir-after-change` prints nothing after `sccp`.
`tests/upstream/composite-fixed-point-sccp` checks the reproducer.

## Upstreaming plan

Status: file upstream.

- Where: a GitHub issue and a pull request to llvm/llvm-project. Not
  Bugzilla. The text to paste is `submission.md`: the issue carries the
  report and both parts, part 2 as a proposal; the pull request is one
  commit, `llvm.patch`, which is part 1, and its body is the squash commit
  message. It refers to the issue as "Part of", since part 2 stays open.
- Upstream test: the second RUN line in `mlir/test/Transforms/sccp.mlir`;
  run `check-mlir`, which runs the test-dialect cases that could not be
  run here.
- Dropped when the pin includes the fix to `sccp`; part 2 is separate work
  and does not hold the patch.
