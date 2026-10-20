<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][linalg] linalg.index has no integer range

On llvm main at 7208ba24 (the pin), and still on main on 2026-10-19,
`linalg.index` implements no `InferIntRangeInterface`, so the integer
range analysis (`IntegerRangeAnalysis`) knows nothing of it: an
iteration index, which lies in [0, extent - 1], counts as any index.
An `scf.for` induction variable is bounded by its loop; the same index as
a `linalg.index` is not.

## Reproduce

`linalg-index-range.mlir`, with the toolchain's
`mlir-opt --int-range-optimizations`: `cmpi ult %i, 8` in a generic of
extent 8 and `cmpi sge (index_castui %i), 0` in a generic of dynamic
extent both stay; the same comparisons of an `scf.for` induction variable
fold to `true`. In the compiler, idr-narrow, which runs after
idr-structure-loops, could not prove the naturals an array's loop body
makes from its index (`at i = cast (finToNat i)`) small, so the bodies
stayed on bigs (`idris_rt_big_*` calls) and the vectorizer took none of
them: tests linarray-combinators, linarray-lanes-exact,
linarray-lanes-wide and determinism-threads-linarray-lanes
(the arrays-refused audit at 3c8a666a, §2 group B, item 2).

## Expected

`linalg.index d` has the range [0, extent - 1] of loop `d` of its
structured op where the shapes fix the extent, and [0, signed max - 1]
otherwise: a dimension is a non-negative index, so an index below it is
below the largest signed index.

## The fix

`llvm.patch`: an external model of `InferIntRangeInterface` for
`linalg.index` (`mlir/lib/Dialect/Linalg/IR/InferIntRangeInterfaceImpl.cpp`),
promised by the Linalg dialect and registered with its other interface
models (`registerAllDialectInterfaceImplementations`), beside the
external `ValueBoundsOpInterface` model the same op already has. The
extent is the parent's static loop range, as `IndexOp::fold` reads it; a
loop of extent 0 runs no iteration, and its index is given no range, as
the analysis gives none to an `scf.for` whose bounds are empty. The test
is `mlir/test/Dialect/Linalg/int-range-interface.mlir`.

The model is external rather than declared in `LinalgOps.td` so that it
touches no line upstream/56-cse-nested-linalg-index rewrites: both would
edit the one line that lists the op's traits. Upstream, declaring it in
ODS (`DeclareOpInterfaceMethods<InferIntRangeInterface,
["inferResultRanges"]>` with the same body in `LinalgOps.cpp`) is the
other form, and the review chooses.

The compiler registers the model with the others its passes read
(foreign/idr/lib/Driver/Register.cpp); idris-mlir-opt registers it
through `registerAllDialects`. The dialect promises the interface, so a
tool that runs the range analysis on linalg without the model fails
loudly instead of losing the ranges.

## Patch

`llvm.patch`, applied by tools/bootstrap.sh; checked by
tests/upstream-linalg-index-int-range (every comparison of an index
folds).

## Testing at the pin

Built into a private mlir-opt (Release, assertions, arm64 macOS) from the
pin with every carried patch and 56, 57 and 58's diff. The patch applies to
the pristine pin alone and after every carried patch. The reproducer is
fixed, the new test passes, and fails on the toolchain's mlir-opt (there the reproducer: its comparisons stay). check-mlir
on that build, with patch 24 as amended on 2026-10-19: 4100 passed, 639
unsupported, 1 skipped, 1 expectedly failed, none failed.

## Upstreaming plan

A PR to llvm/llvm-project, `[mlir][linalg] Infer the integer range of
linalg.index`, with the int-range-interface.mlir test and Bazel's overlay
(both in the patch); no issue needed. Status: not filed; carried; check-mlir passes on a private build.
