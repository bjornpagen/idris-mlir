<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][UB] ub.unreachable declares no memory effects, so every reader takes it for all of them

On llvm main at 416f328b (the pin), and on llvm main on 2026-10-21,
`ub.unreachable` is `UB_Op<"unreachable", [Terminator]>`
(`mlir/include/mlir/Dialect/UB/IR/UBOps.td:73`, *read*): it implements
no `MemoryEffectOpInterface`, and MLIR reads an op without one as having
every effect. Code past it never runs, so it has no effect anyone could
observe, but `wouldOpBeTriviallyDead` keeps a region op whose body ends
in it, and an analysis that sums a function's effects (the compiler's
derived effect row among them) counts a write to every resource at each
place control never goes on. The op came in with #169872 (2025); no
upstream change since gives it effects (main read 2026-10-21; #169873,
open, adds canonicalizations and leaves the traits as they are).

The compiler worked around it with an external model that gave the op
no effects (`NeverRuns`, `foreign/idr/lib/IR/FlowOps.cpp`), code standing
in for an upstream fix. That model is deleted: the patch below alone
gives the op its effects, and nothing in our code stands in for it.

## Reproduce

`unreachable-effects.mlir`, under `mlir-opt -canonicalize`: at the pin
the `scf.execute_region no_inline` whose body is only `ub.unreachable`
stays (*read*: the greedy driver erases an op only when
`isOpTriviallyDead` holds, and an op with no effect interface counts as
having effects); with the patch it is erased.

## Patch

`llvm.patch`: `ub.unreachable` declares `NoMemoryEffect`, and its
description says why; it stays unspeculatable, since executing it is
undefined behavior. A test in `mlir/test/Dialect/UB/canonicalize.mlir`
checks that the region op above is erased. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request to llvm/llvm-project, `[mlir][UB]`; the op's
  own description says executing it is undefined behavior, which is the
  whole argument.
- Upstream test: `mlir/test/Dialect/UB/canonicalize.mlir`'s
  `@dead_region_ending_in_unreachable`.
- The patch goes when the pin's `ub.unreachable` declares no memory
  effects.
