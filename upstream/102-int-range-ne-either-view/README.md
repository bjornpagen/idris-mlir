<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] Integer range inference proves `ne` only when both views prove it

On llvm main at 416f328b (the pin), and on main on 2026-10-22 (*read*),
`isStaticallyTrue` (`mlir/lib/Interfaces/Utils/InferIntRangeCommon.cpp:710-720`)
decides `ne` as `sne && une`: the signed ranges of the two sides must be
apart and so must the unsigned ones. A `ConstantIntRanges` bounds one
value in both interpretations at once (`InferIntRangeInterface.h:21-26`):
the value lies within its signed bounds and within its unsigned bounds.
So two values are unequal as soon as either interpretation shows their
ranges apart: no bit pattern lies in both. `sne || une` is the test; the
comment above the code, which says neither interpretation may overlap,
reads the two views as alternatives rather than as one value bounded
twice.

`evaluatePred` asks `ne` both for itself and, inverted, for `eq`, so
neither comparison folds where one view alone proves it. A value known
to be -5 or 5 (signed [-5, 5], unsigned [5, 2^64 - 5]) is not known to
differ from 0, and the compiler's zero test of a signed Int, which reads
these ranges (`Intervals::equal`, foreign/idr/lib/IR/Ops/Numeric.cpp,
through `evaluatePred`), stays a test when the program runs although the
range excludes 0. Found by L13's eighth pass.

## Reproduce

`ne-either-view.mlir`: `mlir-opt --int-range-optimizations` leaves both
`arith.cmpi` of a `select` of -5 and 5 against 0 at the pin; with the
patch they fold to `true` (`ne`) and `false` (`eq`) (*read*; not run,
D56).

## Patch

`llvm.patch`: `sne || une`, and the comment says why. Tests in
`mlir/test/Dialect/Arith/int-range-opts.mlir`: `@ne_signed_apart`, where
only the signed bounds exclude 0, and `@ne_unsigned_apart`, where only
the unsigned bounds do; each folds `ne` to true and `eq` to false. The
upstream tests that keep an `ne` or `eq` comparison
(`int-range-interface.mlir`: `remui_restricted_fails`,
`remsi_restricted_fails`, `select_union`, `no_aggressive_eq`,
`select_undefined_union`, `ceil_divui`, `ceil_divsi`; the index
dialect's `index-canonicalize.mlir`) compare ranges that overlap in both
views, so they keep it (*read*). Applies to the pin alone and touches no
file another carried patch does; not built.

## Check

`tests/upstream-int-range-ne-either-view` (to write): the toolchain's
`mlir-opt --int-range-optimizations` on `ne-either-view.mlir` leaves no
`arith.cmpi` and returns `true` and `false`.

## Upstreaming plan

Status: carried (2026-10-22); not filed.

- Where: one pull request to llvm/llvm-project, `[mlir][intrange]`, on its
  own.
- Upstream test: the two lit tests above, with every existing
  `int-range-*` and `index-canonicalize` test unchanged.
- The patch goes when the pin's `isStaticallyTrue` accepts either view.
