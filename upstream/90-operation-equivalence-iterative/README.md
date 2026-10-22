<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] OperationEquivalence recurses once per level of region nesting

On llvm main at 416f328b (the pin), and on main at 1204f6b4
(2026-10-21), whose `OperationSupport.cpp` is the same file,
`OperationEquivalence::isRegionEquivalentTo`
(`mlir/lib/IR/OperationSupport.cpp:769`) compares each pair of operations
of each pair of blocks by calling `isEquivalentTo` (`:803`), which
compares each pair of their regions by calling `isRegionEquivalentTo`
(`:950`) (*read*). Two native frames, with their lambdas and a block map,
per level of region nesting, so comparing two operations or regions nested
N deep needs a native stack that grows with N. No pull request or issue
upstream changes it (searched 2026-10-21).

What reaches it in this repository: the e-graph's identical-regions rule,
which compares a match's case bodies operation by operation
(`foreign/idr/lib/Transforms/Joins/IdenticalRegions.cpp`), and the
deduplication of functions by partition refinement, which compares
function bodies (`foreign/idr/lib/Transforms/Deduplicate/Deduplicate.cpp`).
Both compare program-sized bodies, and a deeply nested function (a
generated `else if` chain is one match per branch, nested) reaches the
guard of the compiler's one small, measured stack for every thread
(proposals/0000 D33, C43, C99): the tools' stack limit would then be a
limit on the programs the compiler accepts. Upstream, the same holds for
CSE (`mlir/lib/Transforms/Utils/CSE.cpp:41`) and
`duplicate-function-elimination`
(`mlir/lib/Dialect/Func/Transforms/DuplicateFunctionElimination.cpp:76`).

## Reproduce

`nested-functions.sh DEPTH` writes a module of two private functions
alike, each nesting `scf.execute_region` DEPTH deep;
`mlir-opt -duplicate-function-elimination` compares their bodies with
`isRegionEquivalentTo`. On a small stack (`ulimit -s 256`) a few thousand
levels overflow it at the pin (*conjecture* on the depth: no overflowing
depth is measured). The textual parser and printer recurse on the same
depth through each operation's parse and print hooks (PINS.md
`mlir-recursion`), so through `mlir-opt` the comparison is seen alone only
on IR read from bytecode and not printed back; the patch's unit test
builds the nest in memory.

## Patch

`llvm.patch`, applying after 79, whose symbol-reference hook it keeps:
`isEquivalentTo` and `isRegionEquivalentTo` run one comparison,
`EquivalenceComparison`, that keeps its place on an explicit stack, one
frame per pair of operations whose regions are being compared (or for the
pair of regions the caller gave): the pairs of regions left, the map of
the current pair's blocks, and the pair of blocks and of operations
reached. An operation is compared without its regions as before
(attributes, properties, location, operands, results, the results marked
equivalent), then its regions are pushed; its successors are mapped in
the enclosing region once everything nested in it is compared, as the
recursion did on its return. So `checkEquivalent`, `markEquivalent` and
`checkCommutativeEquivalent` are called in the same order, the same
first difference stops the comparison, an operation compared with itself
is still equivalent without its regions being compared, each pair of
regions still maps its blocks apart, and a region pair of different
lengths still fails after its common prefix. One change: one
`SymbolRefMapper` serves the whole comparison, where 79 made one per
operation, so the hook is asked once per reference a comparison meets,
not once per operation (the same answers for a hook that is a function).
The unit test, `OperationEquivalenceTest.DeepNestingOnASmallStack` in
`mlir/unittests/IR/OperationSupportTest.cpp`, compares two chains nested
10,000 deep, each level a result and a block argument and, after the next
level, a use, on a 256 KiB thread: they are equivalent, by both entry
points, with every value marked once in the recursion's order; a chain
whose innermost branch maps a block to another block is not. It
destroys its chains innermost first, so that it needs no other patch (83
makes destruction iterative too). `tools/bootstrap.sh` applies it with
every `upstream/*/llvm.patch`, in name order. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request, `[mlir]`, after the RFC on Discourse for the
  family of MLIR's recursions on input size
  (upstream/10-recursive-attribute-parser's plan), and after 79's pull
  request, on whose hook it is written; if 79 is not taken, the same
  change without the mapper.
- Upstream test: the unit test above, with `HashWorksWithFlags`, 79's
  tests and the lit tests of CSE (`mlir/test/Transforms/cse.mlir`) and
  `duplicate-function-elimination` unchanged.
- The patch goes when the pin compares operations and regions without
  recursion on nesting depth.
