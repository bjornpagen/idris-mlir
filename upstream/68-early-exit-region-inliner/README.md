<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] The region inliner follows an early exit into another op

With llvm/llvm-project#166688 carried (`upstream/65-early-exits`),
`InlineRegionBranchOp` (`mlir/lib/Interfaces/ControlFlowInterfaces.cpp`,
*read* at 416f328b) inlines a region branch op when
`computeSingleAcyclicRegionBranchPath` finds one path through it from
"parent" back to its results. For a region that ends in an exit crossing
the op, the region's one successor is a region, or the results, of the
exit's target, an enclosing op. The path follows it there. The pattern
then inlines the region, erases the exit, and asks the op for the
target's inputs, which asserts in a build with assertions, and returns
"path ends after a different operation" after it has changed the IR.
`scf.if` registers the pattern, so `scf.if %true { scf.break ... }`
reaches it; so does `idr.data.match` with a known case ending in `idr.jump`
(L09 §1.3.4 U2).

## Reproduce

`region-inliner.mlir`, under `-canonicalize` (*conjecture* from the
reading: not run, since no tool of the pin parses `scf.loop`).

## Patch

`llvm.patch`, applying after 67: the path ends, unmatched, at a
successor the op does not own (`getRegionBranchSuccessorOwner(successor)
!= op`), before anything is changed. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not posted.

- Where: a review comment on llvm/llvm-project#166688 with the diff and
  the reproducer as a test.
- Upstream test: `region-inliner.mlir`'s function in
  `mlir/test/Dialect/SCF/loop_canonicalize.mlir`, checking the `scf.if`
  folds to its break and nothing else changes.
- The patch goes when the pin carries the pull request with this case
  covered; if upstream merges another form, D82 decides (65's README).
