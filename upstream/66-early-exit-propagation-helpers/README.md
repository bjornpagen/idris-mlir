<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] The early-exit propagation helpers are private to SCF

With llvm/llvm-project#166688 carried (`upstream/65-early-exits`), an op
that an early exit crosses (`PropagateControlFlowBreak`) must answer
`getSuccessorRegions` for that exit with its target's successors, never
with itself. The pull request computes that answer with two helpers,
`terminatorPropagatesThrough` and `appendPropagatedTerminatorSuccessors`,
written `static` in `mlir/lib/Dialect/SCF/IR/SCF.cpp` (*read*, the
patched tree at 416f328b) and called by `scf.loop` and `scf.if`. Every
other propagating op needs the same answer: `scf.index_switch`
(`upstream/71-early-exit-index-switch`), and our `idr.data.match`,
`idr.lit.match`, `idr.join` and `idr.loop`, whose generated
`getSuccessorRegions` must forward an exit whose target is an ancestor.
With the helpers private, each dialect writes its own copy of them.

## Reproduce

Nothing to run: the defect is that the code cannot be reached from
outside SCF.cpp (*read*).

## Patch

`llvm.patch`, applying after 65: the two functions move, unchanged, from
SCF.cpp to `mlir/lib/Interfaces/ControlFlowInterfaces.cpp`, declared in
`ControlFlowInterfaces.h` beside the pull request's
`getRegionBranchSuccessorOwner`, with a comment saying what a
propagating op's `getSuccessorRegions` returns for an exit. SCF.cpp calls
them as before. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not posted.

- Where: a review comment on llvm/llvm-project#166688 carrying this diff,
  as L09's review found (every propagating `RegionBranchOpInterface` op
  needs them).
- Upstream test: none of its own; the pull request's tests cover the
  callers.
- The patch goes when the pin carries the pull request with the helpers
  exported, or another way to answer for a propagated exit; if upstream
  merges another form, D82 decides (65's README).
