<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] Region DCE recurses once per level of region nesting

On llvm main at 416f328b (the pin), `runRegionDCE`
(`mlir/lib/Transforms/Utils/RegionUtils.cpp`, *read*) propagates
liveness by recursion: `propagateLiveness(Operation *)` calls the region
form on each of the op's regions (`:374`), which calls the op form on
each op of each block (`:401`); and it deletes by recursion,
`deleteDeadness` calling itself on the regions of every live op (`:468`).
Each takes native frames per level of region nesting.

The tree reaches it through upstream's greedy pattern driver, whose
round ends in `simplifyRegions` (`GreedyPatternRewriteDriver.cpp:910`)
whenever region simplification is on, as it is by default
(`GreedyPatternRewriteDriver.h:167`, `Aggressive`), and `simplifyRegions`
runs `runRegionDCE` (*read*). Every function of a program meets it after
the lowering, in upstream passes the pipeline runs on each lowered
function while its control flow is still regions
(`compiler/spec/IdrisMLIR/Spec/Pipeline/Pipeline.idr`, the
`OnLoweredFunction` nest): `expand-strided-metadata`
(`ExpandStridedMetadata.cpp:1125`), `convert-vector-to-scf`
(`VectorToSCF.cpp:1756`, `:1761`) and `convert-linalg-to-loops`
(`Loops.cpp:306`) each run the driver on the function, and the
schedule's `transform.apply_patterns` does on each function it vectorizes
(`TransformOps.cpp:383`, the isolated target's path). Under the
compiler's one small, measured stack for every thread (proposals/0000
D33, C43, C99), a deeply nested function (a generated `else if` chain is
one match per branch, nested) would reach the guard: the tools' stack
limit would then be a limit on the programs the compiler accepts.

The other utilities `simplifyRegions` runs keep their own worklists at
the pin: `eraseUnreachableBlocks`, `mergeIdenticalBlocks` and
`dropRedundantArguments` (*read*). What erasing an op costs on the stack
is the destruction family's (upstream/83-destruction-iterative) and the
rewriter's own.

## Reproduce

`nested-dead.sh DEPTH` writes a function of `scf.execute_region` nested
DEPTH deep, a dead addition at each level, for `mlir-opt
-expand-strided-metadata`. On a small stack (`ulimit -s 256`) a few
thousand levels overflow it at the pin (*conjecture* on the depth: no
overflowing depth is measured). The textual parser and printer recurse on
the same depth through each operation's parse and print hooks, so through
`mlir-opt` region DCE is seen alone only on IR read from bytecode and not
printed back; a unit test that builds the nesting in memory and runs
`runRegionDCE` on a thread with a small stack isolates it.

## Patch

`llvm.patch`: both halves keep their position on an explicit stack.
Liveness changes no IR, so a region's steps (its blocks in post-order,
each block's ops in reverse and then, but for the entry block, its
arguments) are listed when its visit begins, and an op is processed once
its regions have been visited, as by recursion; the fixed point is the
same. The deletion keeps one frame per live op whose regions it is in:
the same regions, blocks (in post-order) and ops (in reverse, the next
taken before the current is erased) in the same order, successor
operands erased at each block's start and block arguments after each
region, so a listener sees the same notifications in the same order.
Upstream's region DCE tests (`mlir/test/Transforms/canonicalize-dce.mlir`,
`canonicalize-block-merge.mlir`) check that nothing else changed. Not
built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request, after an RFC on Discourse for the family of
  MLIR's recursions on input size (proposals/0000 C99: walks, the printer
  and parser, attributes, clone, destruction, region DCE, call graph
  construction, slices), each family its own pull request.
- Upstream test: a unit test in `mlir/unittests/Transforms` running
  `runRegionDCE` on regions nested a few thousand deep on a thread with a
  small stack, with `canonicalize-dce.mlir` unchanged.
- The patch goes when the pin runs region DCE without recursion on
  nesting depth.
