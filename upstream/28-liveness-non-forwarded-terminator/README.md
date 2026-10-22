<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][dataflow] A terminator whose operands are all non-forwarded is never revisited, so remove-dead-values poisons them

On llvm main at 7208ba24 (the pin then) and at 416f328b (the pin since 2026-10-21, where the pull request still applies), `LivenessAnalysis::visitBranchOperand`
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

The file is in the idr dialect as it stood when the compiler met the
bug (`idr.tabulate`, the data-type table `#idr.types`), before the
cutover renamed and retyped it, and is kept as that record: it runs
under no idris-mlir-opt after the cutover, and what goes upstream is the
test dialect's case below.

Upstream's own dialects do not show it: each of their region terminators
with a non-forwarded operand (`scf.condition`) forwards another operand
too, whose meet subscribes it. The test dialect can: a region branch op
whose terminator has only non-forwarded operands.

## Expected

A non-forwarded terminator operand is live whenever the parent op's
results are live, whenever they become so.

## The fix

`pull-request.diff`: `visitBranchOperand` reads the parent's results with
`getLatticeElementFor(getProgramPointAfter(op), result)`, `op` being the
operand's owner, which subscribes the terminator (or the branch op itself,
for a non-forwarded operand of its own), so the solver visits it again
when a result becomes live.

## Why there is no patch

There is no `llvm.patch`, and there is no `PINS.md` entry. The compiler
met this bug through one pass, `remove-dead-values`, the one reader of
liveness in the tree, which the pipeline ran once after the optimizer. The cutover retires it (proposals/0000
C35): dead parameters are a demand bit in the optimizer's summary and
dead results one callers-first pass, so the pipeline runs no
`remove-dead-values`, and nothing in the tree reaches the bug. The pass
returns, nested on each function, only if the cutover's measured trial
shows it erases what the rest leave; then its patches are carried again,
rebased, and that measurement is recorded here either way. The report
stays a submission, with the pull request as `pull-request.diff`, which
the bootstrap does not apply.

## The pull request

`pull-request.diff`, applied by tools/bootstrap.sh; checked by
tests/upstream-liveness-non-forwarded-terminator (the element is kept).

## Upstreaming plan

An issue and a PR to llvm/llvm-project, `[mlir][dataflow]`, with a test in
`mlir/test/Analysis/DataFlow/test-liveness-analysis.mlir` (or
`remove-dead-values.mlir`) on a test-dialect region branch op whose
terminator forwards nothing; the test is to be written against a build of
mlir-opt with the test dialect, which the toolchain's does not have.
Status: not filed; not carried since 2026-10-21 (Why there is no patch);
the upstream test not written; check-mlir not run.
