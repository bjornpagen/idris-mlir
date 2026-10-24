<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][dataflow] The sparse and dense analyses initialize by recursion on nesting depth

On llvm main at 416f328b (the pin), and on main on 2026-10-21, every
analysis base of upstream's data-flow framework initializes by calling
itself once for every operation of every block it visits (*read*):
`AbstractSparseForwardDataFlowAnalysis::initializeRecursively`
(`mlir/lib/Analysis/DataFlow/SparseAnalysis.cpp:69`, recursing at
`:93`), `AbstractSparseBackwardDataFlowAnalysis::initializeRecursively`
(`:394`, at `:406`), and the dense forward and backward analyses'
`initialize` itself (`DenseAnalysis.cpp:50` and `:377`, at `:69` and
`:396`). One native frame per level of nesting: SCCP, the integer range
analysis, liveness and every dense analysis need a native stack that
grows with the depth of the IR. Under the compiler's one small, measured
stack for every thread (proposals/0000 D33, C43, C99), a deeply nested
function (a generated `else if` chain is one match per branch, nested)
reaches the guard: the tools' stack limit would then be a limit on the
programs the compiler accepts. Dead-code analysis's own initialization is
upstream/92-dead-code-iterative-initialization, and the symbol-table walk
it starts with is upstream/88-symbol-table-walk-iterative.

What reaches it in this repository: the sparse forward initialization
in the integer range solves (the ranges analysis, idr-narrow's copies). Nothing of ours runs a sparse
backward or dense analysis; their initializations are the same family
and the same traversal, so the patch takes them too.

## Reproduce

`nested-regions.sh DEPTH` writes a function nesting `scf.execute_region`
DEPTH deep; its comment names a pass of each kind. Under a small stack
(`ulimit -s 256`) a few thousand levels overflow the initialization at
the pin (*conjecture* on the depth: no overflowing depth is measured).
Through `mlir-opt` the textual parser recurses on the same depth first
(PINS.md `mlir-recursion`); the patch's unit test builds the nest in
memory.

## Patch

`llvm.patch`, applying after 05, 65 and 77 (the same files):
`DataFlowAnalysis::initializeNested` visits an operation and every
operation and block nested in it in the order the recursions took, an
operation before its regions, the regions and their blocks in order, each
block before its operations, and the operations of a block forward or,
for a backward analysis, last first, each with everything nested in it
before the next, keeping its position in an explicit worklist. The four
initializations call it with what they did per operation and per block
(the sparse ones subscribe to each block's liveness, and all but the
sparse backward one visit each block), so every state is created,
subscribed and visited in the same order and the results are unchanged;
only the debug log's messages change. The sparse analyses' private
`initializeRecursively`
goes. One change of behaviour: a dense analysis's nested operations were
initialized through the virtual `initialize`, so an override of it was
called on each of them; it is now called on the top operation alone, as
the sparse analyses' always was. No analysis in llvm-project overrides a
dense analysis's `initialize` (at the pin), and nothing of ours does. The
unit test, `DataFlowTest.DeepNestingOnASmallStack` in a new
`mlir/unittests/Analysis/DataFlowTest.cpp` (the target
`MLIRAnalysisTests`), runs dead-code analysis, constant propagation,
liveness and a dense forward and a dense backward analysis over a chain
nested 10,000 deep on a 256 KiB thread, and each of them reaches the
innermost operation. `tools/bootstrap.sh` applies it with every
`upstream/*/llvm.patch`, in name order. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request, `[mlir][dataflow]`, after the RFC on
  Discourse for the family of MLIR's recursions on input size
  (upstream/10-recursive-attribute-parser's plan), and after the pull
  requests of 80 (the dense analyses' anchor equivalence walks), 88 and
  92, which the unit test's solve reaches first. The review will weigh
  the protected `initializeNested` and the dense `initialize` override's
  narrower reach.
- Upstream test: the unit test above, with the lit tests of the
  framework unchanged (`mlir/test/Analysis/DataFlow`: last-modified,
  next-access, written-to, liveness, dead-code analysis; SCCP and the
  integer range optimizations).
- The patch goes when the pin initializes the sparse and dense analyses
  without recursion on nesting depth.
