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

In `vectorizeLinalgOpPrecondition`, check the body of every op that will be
vectorized as a generic (not a convolution, and not a contraction built as
`vector.contract`) the way `vectorizeOneOp` will: each op is one a hook
takes (with `tensorExtractVectorizationPrecondition` for `tensor.extract`),
a constant, an `affine.apply` (which `convertAffineApply` expands first) or
elementwise-mappable. `hasOnlyScalarElementwiseOp` is that check but for
its stricter result types. Then `vectorize` fails before it builds
anything, as it does for the all-parallel generic.

## Our workaround

`PINS.md`: `vectorize-precondition-body`. `idr-vectorize`
(`foreign/idr/lib/Vectorize/Tiles.cppm`, `vectorizable`) decides with the
precondition and `hasOnlyScalarElementwiseOp` of the body, the check
upstream makes of an all-parallel generic, before it tiles anything. A
generic it refuses stays whole, and `convert-linalg-to-loops` runs its body
in the program's order.

## Patch

`llvm.patch` implements the proposed fix: `vectorizeLinalgOpPrecondition`
checks, for a reduction, that every op of the body is one
`vectorizeOneOp` maps (a hook's op, a constant, an `affine.apply`, or an
elementwise-mappable op), so `vectorize` fails before it builds anything.
Test: `mlir/test/Dialect/Linalg/vectorization/reduction-body-unsupported.mlir`,
`@rows` left whole. Built into the pinned toolchain; the test passes with
its `mlir-opt`, and `tests/upstream/vectorize-precondition-body` checks
the reproducer.

## Upstreaming plan

- Where: an issue with this report and `body.mlir`, and a pull request to
  llvm/llvm-project (Linalg vectorization).
- Upstream test: `reduction-body-unsupported.mlir`; run `check-mlir` for
  the vectorization tests whose reductions hold ops the check now refuses.
- Status: not sent.
