# [mlir][linalg] `vectorizeOpPrecondition` accepts a reduction whose body the vectorizer refuses

At `llvmorg-23.1.2`, `linalg::vectorizeOpPrecondition`, documented as
"Return success if the operation can be vectorized"
(`mlir/include/mlir/Dialect/Linalg/Transforms/Transforms.h:506-511`), says
yes to a `linalg.generic` with a reduction dimension whose body holds an op
that is not elementwise-mappable, such as an `scf.if` or a `func.call`.
`linalg::vectorize` then refuses that op, after it has built part of the
vector code, and returns failure with that code left in the function. The
same body in a generic without a reduction dimension is refused by the
precondition, before anything is built.

A client that asks the precondition first, then transforms the op (tiles
it, say) and vectorizes the result, is left with the transformed op and no
vectors: in our case a loop tiled four rows at a time whose tiles stay
scalar, which runs its body column by column within each group of rows.

## Reproduce

`body.mlir` holds one body, a crash check and a combiner, in two generics:
`@elementwise` has one parallel dimension, `@rows` a parallel and a
reduction dimension. The transform script vectorizes each, with failures
suppressed so that the IR is printed:

```mlir
func.func private @crash()

func.func @rows(%in: memref<?xi64>, %out: memref<?xi64>) {
  linalg.generic {indexing_maps = [affine_map<(d0, d1) -> (d1)>, affine_map<(d0, d1) -> (d0)>],
                  iterator_types = ["parallel", "reduction"]}
      ins(%in : memref<?xi64>) outs(%out : memref<?xi64>) {
  ^bb0(%x: i64, %acc: i64):
    %c0 = arith.constant 0 : i64
    %z = arith.cmpi eq, %x, %c0 : i64
    scf.if %z {
      func.call @crash() : () -> ()
    }
    %t = arith.addi %acc, %x : i64
    linalg.yield %t : i64
  }
  return
}
```

```
$ mlir-opt body.mlir --transform-interpreter -debug-only=linalg-vectorization
```

For `@elementwise` the trace ends in `Vectorization pre-conditions failed`,
and the function is printed as it was. For `@rows` the precondition passes,
and the trace goes on to `Vectorize generic by broadcasting to the canonical
vector shape`, then `failed to vectorize: scf.if`, then `Vectorization
failed`; the function is printed with the `linalg.generic` and, before it,
what the vectorizer built: `vector.create_mask`, two masked
`vector.transfer_read`s and an `arith.cmpi` on `vector<4x1xi64>`.

Expected: the precondition fails for `@rows` as it does for `@elementwise`,
and `vectorize` leaves the function as it was.

## Cause

`mlir/lib/Dialect/Linalg/Transforms/Vectorization.cpp`:

- `vectorizeLinalgOpPrecondition` (`:2224-2288`) checks every op of the body
  only for its operand and result types (`:2250-2268`). The ops themselves
  are checked only through `isElementwise` (`:2269`, which requires
  `hasOnlyScalarElementwiseOp`, `mlir/lib/Dialect/Linalg/Utils/Utils.cpp:203-229`),
  and only for an all-parallel generic. For a generic with a reduction
  dimension it returns `reductionPreconditions` (`:2283`, `:1879-1896`),
  which checks the combiner of each output and nothing else.
- `vectorizeOneOp` (`:1358-1449`) maps an op to vectors only when a hook
  takes it (`linalg.yield`, `linalg.index`, `tensor.extract`), it is a
  constant, or it is elementwise-mappable; any other op fails
  (`:1380-1382`).
- `vectorizeAsLinalgGeneric` (`:1473-1587`) builds the reads of every
  operand (`:1490-1546`) before it tries the body's ops one by one
  (`:1570-1584`), so a refused op leaves the reads and every op mapped
  before it.

## Proposed fix

The precondition and the vectorizer each hold their own idea of which body
ops can be vectorized, and they agree only for an all-parallel op. Make
them hold one: the rule `vectorizeOneOp` applies to an op no hook takes (a
constant, or an ElementwiseMappable op) becomes a predicate that
`vectorizeOneOp` and the precondition's per-op loop both call. That loop
already asks `tensor.extract` the precondition of its hook; it then admits
`linalg.yield` and `linalg.index` by kind (their hooks take every such
op) and `affine.apply` (`convertAffineApply` expands it into arith ops
first), and rejects every other op, for every linalg op, before
`vectorize` builds anything.

## Our workaround

None: the patch below is carried. `idr-vectorize`
(`foreign/idr/lib/Vectorize/Tiles.cppm`, `vectorizable`) asks the
precondition alone before it tiles anything; a generic it refuses stays
whole, and `convert-linalg-to-loops` runs its body in the program's order.
Before the patch it also asked `hasOnlyScalarElementwiseOp` of the body.

## Patch

`llvm.patch` implements the proposed fix: `isVectorizableWithoutHook` in
`Vectorization.cpp`, used by `vectorizeOneOp` step 3 and by the per-op
loop of `vectorizeLinalgOpPrecondition`, which now fails with
`precondition failed: cannot vectorize scf.if` for `@rows`. The
convolution and contraction paths do not walk the body with
`vectorizeOneOp`, but the bodies they accept are arith ops, so the check
leaves them as they were. An earlier version of the patch called
`hasOnlyScalarElementwiseOp` once more, for reductions only, which kept
the precondition's rule and the vectorizer's rule apart.

Test, added to the existing
`mlir/test/Dialect/Linalg/vectorization/unsupported.mlir`: a static
reduction whose body holds an `scf.if`, vectorized with
`vectorize_children_and_apply_patterns`. Without the patch
`VectorizationPattern` changes the IR and then reports failure, the greedy
driver does not converge, and the transform fails to apply; with it the
function is printed unchanged.

Verified against a `mlir-opt` linked from the pinned static libraries
with the patched `Vectorization.cpp`: the new test passes (and fails with
the unpatched `mlir-opt`), and the 23 other tests under `mlir/test` that
drive the Linalg vectorizer and run without test-only passes pass with
both. `tests/upstream/vectorize-precondition-body` checks `body.mlir`.

## Upstreaming plan

Status: file upstream.

- Where: an issue (title, body and a static reproducer in
  `submission.md`) and a pull request to llvm/llvm-project (Linalg
  vectorization). No existing report was found.
- Upstream test: the new case at the end of
  `mlir/test/Dialect/Linalg/vectorization/unsupported.mlir`; run
  `check-mlir` before sending (the four vectorizer tests that need
  test-only passes or `mlir-translate` were not run here).
