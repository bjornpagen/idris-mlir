<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] The greedy rewrite driver revisits an op of many regions after each change in each

On llvm main at 7208ba24 (the pin), `GreedyPatternRewriteDriver::addToWorklist`
(`mlir/lib/Transforms/Utils/GreedyPatternRewriteDriver.cpp`) adds an op
and every ancestor up to the scope to the worklist, which is last in,
first out: the ancestors are visited before anything else that is
pending, after every change below them. The patterns of an op with
several regions read all of them: upstream's region branch patterns
(`populateRegionBranchOpInterfaceCanonicalizationPatterns`) build the
mapping of every region's successor operands, and ours on `idr.match`
and `idr.match_lit` (IR/Canon's SinkConsumer, EndAfterNoYield,
`getTakenRegion`), until the cutover deleted every greedy rewrite of
ours, read every region too. So an op of n regions in which every region
changes costs n visits of size n.

defunc-tag-limit's program, a `match_lit` of n cases, through the whole
pipeline: canonicalize in idr-optimize took 30, 120 and 223 s at n = 1k,
2k, 4k (Debug, loaded machine).

## Reproduce

`greedy-multi-region-ancestors.mlir`: an `scf.index_switch` of 8 cases,
each folding an addition of two constants. With `-debug-only=greedy-rewriter`
(an assertions build) the switch is processed 18 times. With n cases the
time grows as n^2: canonicalize takes 0.13, 0.51 and 2.11 s at n = 500,
1000, 2000 with the pinned mlir-opt.

## Patch

`llvm.patch`, against 7208ba24 with the carried patches: an ancestor with
more than one region goes on a second worklist, moved to the worklist when
the worklist is empty, so it is revisited once for all the changes inside
it; an ancestor with one region is revisited at once, as before. The order
of visits is unchanged wherever no op has several regions. Deferring every
ancestor instead changes the outcome of two non-confluent pattern sets in
check-mlir (a broadcast left unfolded in
`Dialect/Linalg/vectorization/extract-with-patterns.mlir`, `in_bounds` not
inferred in `Dialect/Vector/vector-warp-distribute.mlir`); deferring only
those with several regions changes none. Its test is the reproducer, with
`CHECK-COUNT-4`.

Tested on a private build of the pinned source with every carried patch
(Release, assertions, AArch64, Apple clang): check-mlir passes 4101, 0
failed. The switch at n = 1000 and 2000 canonicalizes in 0.01 and 0.03 s,
with output byte-identical to the unpatched tool. Linked into
idris-mlir-opt with upstream 63, defunc-tag-limit's program through
`--idr-pipeline` takes 1.1, 1.9, 3.4 and 9.8 s at n = 1k, 2k, 4k, 16k
(against 17, 56 and 234 s at 1k, 2k, 4k), idr-optimize 0.4 to 3.7 s.
tests/upstream-greedy-multi-region-ancestors checks the pinned mlir-opt.

## Upstreaming plan

Status: not sent. Send as one pull request to llvm/llvm-project,
`[mlir] Revisit a multi-region ancestor once the worklist is empty`, with
`llvm.patch`'s diff and message; no issue is needed. Reviewers may prefer
a different rule for which ancestors wait (every ancestor, with the two
tests' expectations updated, or a config option); follow them. The patch
goes when the pin carries the change.
