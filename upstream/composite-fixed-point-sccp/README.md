# [mlir] `composite-fixed-point-pass` never converges with `sccp` in its pipeline

At `llvmorg-23.1.2`, `composite-fixed-point-pass` runs a pipeline that has
`sccp` in it until `max-iterations`, and then warns, on a module that is
already at the pipeline's fixpoint. The pass decides convergence by
`OperationFingerPrint`, which hashes the addresses of the module's
operations, blocks and values, and `sccp` erases every constant it meets and
makes an equal one even when it propagates nothing, so the fingerprint is
new after every run although the module is the same.

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
`sccp` running six times; `--mlir-print-ir-after=sccp` prints the same
module after every run; `mlir-opt one.mlir --sccp` prints the same module,
and so does `--sccp` on that output. `pipeline=sccp,canonicalize` and the
default `max-iterations` warn the same way. On the same module,
`pipeline=canonicalize`, `pipeline=cse` and `pipeline=remove-dead-values`
each converge after one run, and so does `pipeline=sccp` on a module with
no constant in it.

Expected: `sccp` runs once and the pass converges, as it does whenever the
pipeline leaves the module as it is.

The same comparison makes `-mlir-print-ir-after-change` print after `sccp`:

```
$ mlir-opt one.mlir --sccp --mlir-print-ir-after-all --mlir-print-ir-after-change -o /dev/null
// -----// IR Dump After SCCPPass: sccp //----- //
module {
  ...
```

With `--canonicalize` or `--cse` in place of `--sccp` nothing is printed.

## Cause

Two things meet.

`CompositeFixedPointPass::runOnOperation`
(`mlir/lib/Transforms/CompositePass.cpp:68-91`) runs its pipeline, takes an
`OperationFingerPrint` of the operation and stops when it equals the one
taken before the run. `OperationFingerPrint`
(`mlir/lib/IR/OperationSupport.cpp:933-975`) hashes, for every operation in
the walk, its address, its parent's, its blocks' and their arguments', its
operands' (the `Value`s) and its successors', and the uniqued attributes,
properties, location and result types. It is a fingerprint of object
identity: two modules that print the same have different fingerprints
whenever an operation was erased and an equal one made. (The loop also
checks the count after each run, so `max-iterations=N` runs the pipeline
N + 1 times.)

`sccp`'s `rewrite` (`mlir/lib/Transforms/SCCP.cpp:67-110`) walks every
operation and, for each result whose lattice is a constant,
`replaceWithConstant` (`SCCP.cpp:42-62`) asks
`OperationFolder::getOrCreateConstant`
(`mlir/lib/Transforms/Utils/FoldUtils.cpp:207-220`) for a constant of that
value, replaces all uses of the result with it, and erases the operation if
that left it trivially dead (`SCCP.cpp:93-99`). A constant operation's own
result has a constant lattice: the analysis folds every operation with its
operands' constants (`mlir/lib/Analysis/DataFlow/ConstantPropagationAnalysis.cpp:75-100`),
and a constant folds to its value. The folder is made fresh for each run
(`SCCP.cpp:77`) and `rewrite` never tells it about the constants the module
already has (`OperationFolder::insertKnownConstant`, `FoldUtils.cpp:113-172`,
which the greedy driver calls for every constant it meets before it rewrites
anything, `mlir/lib/Transforms/Utils/GreedyPatternRewriteDriver.cpp:855-882`),
so `tryGetOrCreateConstant` (`FoldUtils.cpp:309-323`) finds nothing under the
key and materializes a new constant at the front of the entry block; the uses
move to it and the original is erased. The module prints the same, every
constant and every operation that used one has a new address, and the
fingerprint differs; the composite pass runs the pipeline again, which does
the same again, until `max-iterations`. `-mlir-print-ir-after-change`
(`mlir/lib/Pass/IRPrinting.cpp:107-115`) compares the same fingerprint.

## Proposed fix

Two parts, independent; either one ends this case. The first stops `sccp`
from remaking what it has; the second makes the composite pass right for
every pass that remakes an operation in place.

1. `sccp`: in `rewrite`, give the folder the constants the block already
   holds before replacing anything, as the greedy driver does: for an
   operation with the `ConstantLike` trait, `folder.insertKnownConstant(&op)`
   and move on. The folder then records it (or replaces it by an earlier
   equal constant it has recorded), and every later `getOrCreateConstant` of
   that value returns it. A run of `sccp` on a module at its fixpoint then
   touches nothing.
2. `composite-fixed-point-pass`: decide the fixpoint on the IR, not on
   addresses. A fingerprint that hashes each operation by its name,
   attributes, properties, result types and location, which
   `OperationEquivalence::computeHash` (`OperationSupport.cpp:678-714`)
   already does, with each operand hashed as the position of its defining
   value in a pre-order numbering of the block arguments and results, and an
   operand that is a constant hashed by its value. An operation remade in
   place, or a constant remade elsewhere in its block, then hashes the same.
   `OperationFingerPrint` keeps its use as an identity check, which the
   greedy driver's expensive pattern-API checks rely on.

## Our workaround

`PINS.md`: `simplify-structural-fixpoint`. `idr-simplify`
(`foreign/idr/lib/Passes/Simplify.cc`) is its own loop over the round and
decides the fixpoint with a structural hash of the module (`structural`):
constants by their value at each use, other values by their position in the
walk. Over its round budget it fails with a named error where the composite
pass warns and goes on.
