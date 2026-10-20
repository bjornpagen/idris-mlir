<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][math] math.sqrt of a negative constant is not folded

On llvm main at 7208ba24 (the pin), and still on main on 2026-10-19,
`math::SqrtOp::fold` (`mlir/lib/Dialect/Math/IR/MathOps.cpp`) declines
every operand whose sign bit is set: `if (a.isNegative()) return {};`.
That leaves two constants unfolded whose square root is fixed. Of a
number below zero it is a NaN: IEEE 754 says so, and so does `llvm.sqrt`,
which `math.sqrt` lowers to (LangRef: the result matches a conforming
libm's, without errno). LangRef's rules for NaN values leave the sign and
payload of a NaN an operation makes unspecified, so a quiet NaN is a
correct fold whatever the target computes. Of -0 it is -0, which the
folder declines as well, since `isNegative` holds of it. (LLVM's own
constant folder declines the first too, but for another reason: it runs
the host's `sqrt` and gives up when that raises FE_INVALID.)

In this repository the fuzzer (tests/fuzz-seeds, seed 1, static part)
writes `sqrt (-2.5)` as a closed expression and requires every such line
folded: idr-optimize leaves the `math.sqrt` in place, and the check
fails. The program's output is right either way: the runtime prints a NaN
as `nan` whatever its sign (runtime/Doubles/Printing.cpp).

## Reproduce

`sqrt-negative.mlir`, with the toolchain's `mlir-opt --canonicalize`: the
`math.sqrt` of `-2.5` stays.

## Expected

The square root of a negative non-zero constant folds to a quiet NaN, of
-0 to -0; a NaN operand stays as it is (its payload is the target's).

## Patch

`llvm.patch`: the folder returns `APFloat::getQNaN` for a negative
non-zero operand, declines a NaN, and lets -0 reach the host `sqrt`,
which gives -0. Tests `sqrt_fold_negative` and `sqrt_fold_negative_zero`
in `mlir/test/Dialect/Math/canonicalize.mlir`.

## Carried

`llvm.patch`, which tools/bootstrap.sh applies to the pin it builds, since
tests/fuzz-seeds reaches the bug. tests/upstream-sqrt-negative-fold checks
that the toolchain's mlir-opt folds the reproducer.

## Upstreaming plan

A pull request to llvm/llvm-project, `[mlir][math] Fold sqrt of negative
constants to NaN`, with the two canonicalize.mlir tests. Status:
carried from the toolchain build of 2026-10-19; not filed.
