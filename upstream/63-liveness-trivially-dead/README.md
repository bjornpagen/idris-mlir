<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] Liveness walks an op of many regions once per region

On llvm main at 7208ba24 (the pin), `LivenessAnalysis::visitOperation`
(`mlir/lib/Analysis/DataFlow/LivenessAnalysis.cpp`) asks
`wouldOpBeTriviallyDead(op)`, which walks every region of `op`. The
backward sparse analysis (`AbstractSparseBackwardDataFlowAnalysis::visitRegionSuccessors`)
calls `visitNonControlFlowArguments` once for each region successor of a
region branch op, and liveness's override visits the parent op there
while none of its results is live: an op of n regions walks them n times.
remove-dead-values over defunc-tag-limit's program (a `match_lit` of n
cases in a private function) took 10.9, 30.9 and 87 s at n = 1k, 2k, 4k
(Debug, loaded machine).

## Reproduce

A private function returning an `scf.index_switch` of n cases, each adding
its constant to an argument, called from a public one (the awk program in
tests/upstream-liveness-trivially-dead). remove-dead-values takes 0.12,
0.44 and 1.62 s at n = 1000, 2000, 4000 with the pinned mlir-opt.

## Patch

`llvm.patch`, against 7208ba24 with the carried patches (28 among them):
`LivenessAnalysis` keeps whether each op would be trivially dead, asked
once per op: the IR does not change while the analysis runs. NFC, so no
test of its own: the liveness and remove-dead-values tests hold it.

Tested on a private build of the pinned source with every carried patch
(Release, assertions, AArch64, Apple clang): check-mlir passes 4101, 0
failed; the reproducer takes 0.02, 0.03, 0.05 s at n = 1000, 2000, 4000,
its output byte-identical to the unpatched tool's.
tests/upstream-liveness-trivially-dead checks the pinned mlir-opt by the
growth of the time from n = 2000 to n = 8000.

## Upstreaming plan

Status: not sent. Send as one pull request to llvm/llvm-project,
`[mlir] Ask once per op whether liveness would find it trivially dead`,
with `llvm.patch`'s diff and message, tagged NFC; no issue is needed. The
patch goes when the pin carries the change.
