<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][Pass] A group of nested passes invalidates every analysis of its parent

On llvm main at 416f328b (the pin), `OpToOpPassAdaptor` never says what
it preserves, so when it returns, `OpToOpPassAdaptor::run` invalidates
every analysis of the parent op (`mlir/lib/Pass/Pass.cpp`,
`am.invalidate(pass->passState->preservedAnalyses)`, *read*), though each
nested pass declared what it kept. LLVM's pass manager intersects the
preserved sets of the passes it runs (`llvm/lib/IR/PassManager.cpp`).
A group of `idr.func` passes that all keep the program's call graph
drops it, and the next program pass rebuilds it (proposals/0000 C114).

## Reproduce

The patch's unit test, run at the pin: a module pass computes an
analysis; a nested group of two function passes that both preserve it
runs; a second module pass finds it no longer cached.

## Patch

`llvm.patch`, applying after 73: `PreservedAnalyses::intersect`; each
nested pipeline intersects what its passes preserved on its op; the
adaptor's preserved set is the intersection over every op it ran on,
gathered per op during the parallel run and intersected after it. An
adaptor that ran no pipeline preserves everything. Unit test
`PassManagerTest.AdaptorPreservesWhatNestedPassesPreserve`, with and
without threading. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request to llvm/llvm-project, `[mlir][Pass]`, naming
  LLVM's pass manager as the model.
- Upstream test: the unit test above.
- The patch goes when the pin's adaptor preserves the intersection.
