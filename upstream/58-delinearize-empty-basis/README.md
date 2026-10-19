<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][affine] affine.delinearize_index with no result asserts in its generated verifier

On llvm main at 7208ba24 (the pin), and still on main on 2026-10-19, an
`affine.delinearize_index` with an empty basis and no result crashes the
verifier instead of being reported. Its ODS (`AffineOps.td`) infers the
linear index's type from the results with
`TypesMatchWith<..., "multi_index", "linear_index", "$_self[0]">`, and the
generated `verifyInvariantsImpl` evaluates that on the result types before
the op's own `verify`: with no result it indexes an empty `TypeRange`
(`TypeRange.h`: "invalid index into type range"). `verify` would accept
the op anyway: its rule, a basis of N or N - 1 elements for N results,
holds for N = 0.

An op with no result cannot be meant: its custom form cannot spell it
(the parser wants a result type to infer the linear index's from), its
folder would return one result for none, and the canonicalizations take
care never to build one (`if (!newBasis.empty())`). The builders make
one, from an empty basis with an outer bound, and nothing reports it.

## Reproduce

`delinearize-empty-basis.mlir`, with the toolchain's `mlir-opt` (no pass):
the assertion, exit 134.

## Expected

The verifier reports the op: it has at least one result.

## The fix

`pull-request.diff` declares the rule in ODS, a `PredOpTrait` "has at
least one result" listed before the `TypesMatchWith`, so the generated
verifier checks it first and returns before reading a result type; the
op's description says N is at least one. The test is
`delinearize_no_result` in `mlir/test/Dialect/Affine/invalid.mlir`, in the
generic form.

## Why there is no patch

Nothing in this repository reaches the bug. idr-structure-loops built one
for an array domain of no dimension, where the loop over the cells after
the first has no index to delinearize; it now builds no loop there, since
such a domain has one cell, the first (`StructureLoops/Nests.cpp`, the
`rank == 0` case). That case is the problem's, not a workaround: with the
fix, an op with no result is still one the verifier refuses. So the fix is
kept as a submission, and tests/upstream-delinearize-empty-basis checks
that the pinned mlir-opt still has the bug: when it fails, upstream has
fixed it, and this directory and the check go.

## Testing at the pin

Built into a private mlir-opt with the carried patches and 56 and 57;
the diff applies to the pristine pin and after every carried patch.
`delinearize-empty-basis.mlir` is reported (exit 1, "failed to verify that
has at least one result"), the new test passes, and the lit tests of
Dialect/Affine pass. check-mlir as a whole was not run.

## Upstreaming plan

An issue and a PR to llvm/llvm-project, `[mlir][affine] Verify that
affine.delinearize_index has a result`, from `pull-request.diff`, with the
invalid.mlir test. Status: not filed; not carried.
