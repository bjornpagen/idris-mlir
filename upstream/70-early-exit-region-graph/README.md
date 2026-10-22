<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] The region-graph traversal reads another op's regions

With llvm/llvm-project#166688 carried (`upstream/65-early-exits`),
`traverseRegionGraph` (`mlir/lib/Interfaces/ControlFlowInterfaces.cpp`,
*read* at 416f328b), which serves `isRegionReachable`,
`isRepetitiveRegion` and `insideMutuallyExclusiveRegions`, sizes
`visited` by the op's region count and enqueues every region successor of
each terminator of its regions' blocks:

- A terminator that exits through the op has the regions of an enclosing
  op as successors, and the traversal then reads `visited` at that op's
  region numbers: out of bounds when the number is at least the op's
  region count (a jump from a match case to the third region of a join
  op, past a two-case match), a wrong answer otherwise.
- It reads only the terminators of each region's blocks, so a loop whose
  back exit is nested in an `scf.if` is reported not repetitive.

Two readers of ours meet it: the linearity verifier calls
`isRepetitiveRegion` on every match the pull request makes non-exclusive,
and bufferization's repetitive-region queries matter for arrays inside
loops (L09 §1.3.4 U4).

## Reproduce

`region-graph.mlir` (*read*: no tool of the pin parses `scf.loop`, and the
queries are reached through passes that ask them, bufferization's
analysis among them).

## Patch

`llvm.patch`, applying after 69: the traversal enqueues only the op's own
regions, and adds, for each region it visits, the exits nested deeper in
it that land on the op, with the successors the op reports for them, as
`getAllRegionBranchPoints` already enumerates them. Each visit walks the
region's subtree once more, as the pull request's verifier does. Not
built.

## Upstreaming plan

Status: carried (2026-10-21); not posted.

- Where: a review comment on llvm/llvm-project#166688 with the diff and a
  unit test.
- Upstream test: `isRepetitiveRegion` of `region-graph.mlir`'s loop region
  is true, and of a join op's region reached past a smaller op no read is
  out of bounds (a unit test over the test dialect's breakable loop).
- The patch goes when the pin carries the pull request with this covered;
  if upstream merges another form, D82 decides (65's README).
