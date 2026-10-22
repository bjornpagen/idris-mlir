<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] Slices recurse once per op of a use-def chain

On llvm main at 416f328b (the pin), `getBackwardSliceImpl`
(`mlir/lib/Analysis/SliceAnalysis.cpp`, *read*) calls itself for the
defining op of every value an op depends on (`:128`) and for the parent
of a block argument (`:145`), and `getForwardSliceImpl` for every op
nested in an op's regions (`:51`) and every user of its results (`:66`).
Each takes a native frame per op on the current path of the search, so
the native stack a slice needs grows with the length of a use-def chain:
straight-line code of N chained ops is N frames deep.

The tree reaches the backward slice through linalg's vectorizer, which
the schedule runs on every `linalg.generic` of a lowered function
(`foreign/idr/lib/Target/Schedules.cpp`: `transform.idr.vectorize_lanes`
calls `linalg::vectorizeOpPrecondition`, then `linalg::vectorize`). For a
reduction the precondition calls `reductionPreconditions`
(`Vectorization.cpp:2336`), which asks `matchLinalgReduction` (`:665`)
and so `matchReduction` whether the value the combiner adds depends on
the accumulator (`SliceAnalysis.cpp:313`): `dependsOnCarriedVals` takes
that value's backward slice outside the reduction (`:248`), through every
op of the function that computes it (*read*; the vectorization of a
reduction asks it again, `Vectorization.cpp:1393`). It reaches it too
through bufferization: the empty-tensor elimination the bufferizing pass
runs (`foreign/idr/lib/Transforms/Bufferize/Bufferize.cpp`,
`eliminateEmptyTensors`) moves the values a replacement needs with
`moveValueDefinitions` when no insertion point dominates them
(`EmptyTensorElimination.cpp:112`), which takes each value's backward
slice up to the ops that already dominate it (`RegionUtils.cpp:1478`;
*read*). No path through code the tree runs reaches the forward slice
(*read* at 7208ba24, the pin before: its callers are in passes and
transforms the pipeline does not run); it is in the patch as the other
half of the same search, one pull request for the file. Under the compiler's one small, measured stack for every thread
(proposals/0000 D33, C43, C99), a long chain in a function would reach
the guard: the tools' stack limit would then be a limit on the programs
the compiler accepts.

## Reproduce

`reduce-chain.sh LENGTH` writes a function whose reduction adds to its
accumulator a value computed by LENGTH chained additions, with a
transform script that vectorizes it, for `mlir-opt
-transform-interpreter`. On a small stack (`ulimit -s 256`) a long enough
chain overflows it at the pin (*conjecture* on the length: no
overflowing length is measured). The chain is straight-line code in one
block, which the textual parser and printer handle without recursion, so
the slice is seen alone.

## Patch

`llvm.patch`: both searches keep their path on an explicit stack, one
frame per op on it. Searching changes no IR, so the values (backward) or
ops (forward) an op leads to are listed when its visit begins, in the
order the recursion met them, and each is tested against the slice and
the path when its turn comes. The slices hold the same ops in the same
order (topological backward, reverse topological forward before the
callers reverse it), the filter is called on the same ops in the same
order, `visited` is added to and restored as the recursion did, a block
argument's parent is visited without entering the path as before, and a
value that fails (neither an op's result nor a block's argument, which
cannot occur) still ends the walk of the region it is used in.
`BackwardSliceOptions` and `ForwardSliceOptions` mean what they meant.
Upstream's slice tests (`mlir/test/IR/slice.mlir`,
`mlir/test/Dialect/Affine/slicing-utils.mlir`) and the vectorizer's
reduction tests check that nothing else changed. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request, after an RFC on Discourse for the family of
  MLIR's recursions on input size (proposals/0000 C99: walks, the printer
  and parser, attributes, clone, destruction, region DCE, call graph
  construction, slices), each family its own pull request.
- Upstream test: a unit test in `mlir/unittests/Analysis` taking the
  backward and forward slices of a chain a few thousand ops long on a
  thread with a small stack, with `slice.mlir` and `slicing-utils.mlir`
  unchanged.
- The patch goes when the pin computes slices without recursion on the
  length of a use-def chain.
