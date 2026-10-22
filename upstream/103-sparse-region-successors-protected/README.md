<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] A sparse forward analysis cannot call the base visitRegionSuccessors

On llvm main at 416f328b (the pin), and on main on 2026-10-22 (*read*),
`AbstractSparseForwardDataFlowAnalysis::visitRegionSuccessors`
(`mlir/include/mlir/Analysis/DataFlow/SparseAnalysis.h:276-288`) is
`virtual` and documented as one an analysis may override, but declared
under `private:`. C++ lets a subclass override a private virtual and not
call it, so an override that refines the successors of one op must
re-implement the propagation of every other, which is upstream's code
written again. No pull request or issue on it was found (2026-10-22).

The compiler's range analysis (`SummarizedRanges`,
foreign/idr/lib/Analysis/Ranges.cpp, L14) gives the default region of a
literal match the scrutinee's range with its keys excluded and hands
every other region successor to upstream's: it needs the base callable.

## Reproduce

`override.cpp`: an `IntegerRangeAnalysis` whose override of
`visitRegionSuccessors` counts its calls and hands each to the base.
At the pin it does not compile (the base is private); with the patch it
prints `ok` once the override ran and the `scf.if`'s result has the
range [1, 2] (*conjecture*: not built or run, D56).

## Patch

`llvm.patch`: the declaration moves from `private:` into `protected:`,
beside the other overridable hooks (`visitCallOperation`,
`visitCallableOperation`), and its comment says an override may call it
for the successors it leaves. Nothing else changes. The backward
analysis's `visitRegionSuccessors` is a different, non-virtual helper
and stays private. Applies to the pin alone and after
`upstream/89-dataflow-iterative-initialization`, whose lines in the
same header it does not touch (checked with `git apply` on the pin's
file); not built.

## Check

`tests/upstream-sparse-region-successors-protected` (to write):
`mlir_check` of `override.cpp`, which prints `ok`.

## Upstreaming plan

Status: carried (2026-10-22); not filed.

- Where: one pull request to llvm/llvm-project, `[mlir][dataflow]`, on
  its own.
- Upstream test: none needed for an access change; the existing
  `mlir/test/Analysis/DataFlow` tests unchanged, and the reproducer as a
  unit test if a reviewer asks for one.
- The patch goes when the pin declares the method protected.
