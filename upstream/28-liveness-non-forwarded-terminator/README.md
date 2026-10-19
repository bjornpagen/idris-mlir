<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][dataflow] A terminator whose operands are all non-forwarded is never revisited, so remove-dead-values poisons them

On llvm main at 7208ba24 (the pin), `LivenessAnalysis::visitBranchOperand`
(`mlir/lib/Analysis/DataFlow/LivenessAnalysis.cpp:127-162`) gives a
non-forwarded operand of a `RegionBranchTerminatorOpInterface` op the
liveness of its parent's results. It reads them with `getLatticeElement`,
which subscribes nothing, and `visitOperation` then subscribes the parent
(`:120`, "Adding dependency for result ... after op: <the parent>"), not the
terminator. A terminator that also has a successor operand is subscribed
to the parent's results by that operand's meet
(`SparseAnalysis.cpp:672-675`), so it is visited again when one becomes
live. A terminator whose operands are all non-forwarded never is.

## Reproduce

`tabulate-across-call.mlir`, with idris-mlir-opt (the idr dialect's
`idr.tabulate`, whose region ends in `idr.array.yield`, which forwards
nothing: each element is stored at its index, not passed to a result):
`--remove-dead-values` turns `@squares`'s region into `%p = ub.poison : i64;
idr.array.yield %p`. The array is a result of a private function read by
the caller's callee, so its liveness arrives after the yield was first
visited. The same tabulation read in the function that makes it keeps its
elements. In the compiler this was a silent miscompile: idris-mlir runs
remove-dead-values before idr-structure-loops, and a program summing a
tabulated array in a loop printed 0 (tests/structure-tabulate's
differential).

Upstream's own dialects do not show it: each of their region terminators
with a non-forwarded operand (`scf.condition`) forwards another operand
too, whose meet subscribes it. The test dialect can: a region branch op
whose terminator has only non-forwarded operands.

## Expected

A non-forwarded terminator operand is live whenever the parent op's
results are live, whenever they become so.

## The fix

`llvm.patch`: `visitBranchOperand` reads the parent's results with
`getLatticeElementFor(getProgramPointAfter(op), result)`, `op` being the
operand's owner, which subscribes the terminator (or the branch op itself,
for a non-forwarded operand of its own), so the solver visits it again
when a result becomes live.

## Patch

`llvm.patch`, applied by tools/bootstrap.sh; checked by
tests/upstream-liveness-non-forwarded-terminator (the element is kept).

## Upstreaming plan

An issue and a PR to llvm/llvm-project, `[mlir][dataflow]`, with a test in
`mlir/test/Analysis/DataFlow/test-liveness-analysis.mlir` (or
`remove-dead-values.mlir`) on a test-dialect region branch op whose
terminator forwards nothing; the test is to be written against a build of
mlir-opt with the test dialect, which the toolchain's does not have.
Status: not filed; carried; the upstream test not written; check-mlir not
run.
