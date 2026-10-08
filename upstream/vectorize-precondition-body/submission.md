# Filing

Status: file (new issue and PR).

File a new GitHub issue and a new GitHub pull request on
https://github.com/llvm/llvm-project. LLVM's tracker and review are
GitHub. Do not file a Bugzilla bug.

The author is Bjorn, as an individual, outside any employer. The commit
and the pull request name no employer. No `Assisted-by` trailer. No
`@` mentions in the title, the body, or a comment.

## Issue

New issue: https://github.com/llvm/llvm-project/issues/new

Paste the title and the body. The body is the whole report, including
the reproducer.

### Title

```
[mlir][linalg] vectorizeOpPrecondition accepts a reduction whose body the vectorizer refuses
```

### Body

````
At llvmorg-23.1.2, `linalg::vectorizeOpPrecondition`, documented as
"Return success if the operation can be vectorized"
(`mlir/include/mlir/Dialect/Linalg/Transforms/Transforms.h`), returns
success for a `linalg.generic` with a reduction dimension whose body
holds an op that is not elementwise-mappable, such as an `scf.if` or a
`func.call`. `linalg::vectorize` then refuses that op, after it has
built part of the vector code, and returns failure with that code left
in the function. The same body in a generic with only parallel
dimensions fails the precondition, before anything is built.

A client that asks the precondition first, then transforms the op
(tiles it, for example) and vectorizes the result, is left with the
transformed op and no vectors.

On main, `vectorizeLinalgOpPrecondition` still returns success once
`reductionPreconditions` succeeds, without looking at the ops of the
body.

## Reproduce

One body, a crash check and a combiner, in two generics.
`@elementwise` has one parallel dimension. `@rows` has a parallel
dimension and a reduction dimension. The transform script vectorizes
each, with failures suppressed so the IR is printed.

```mlir
func.func private @crash()

func.func @elementwise(%in: memref<?xi64>, %out: memref<?xi64>) {
  linalg.generic {indexing_maps = [affine_map<(d0) -> (d0)>, affine_map<(d0) -> (d0)>],
                  iterator_types = ["parallel"]}
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

module attributes {transform.with_named_sequence} {
  transform.named_sequence @__transform_main(%root: !transform.any_op {transform.readonly}) {
    %generics = transform.structured.match ops{["linalg.generic"]} in %root : (!transform.any_op) -> !transform.any_op
    %elementwise, %rows = transform.split_handle %generics : (!transform.any_op) -> (!transform.any_op, !transform.any_op)
    transform.sequence %elementwise : !transform.any_op failures(suppress) {
    ^bb0(%g: !transform.any_op):
      transform.structured.vectorize %g vector_sizes [4] : !transform.any_op
    }
    transform.sequence %rows : !transform.any_op failures(suppress) {
    ^bb0(%g: !transform.any_op):
      transform.structured.vectorize %g vector_sizes [4, 1] : !transform.any_op
    }
    transform.yield
  }
}
```

```
mlir-opt body.mlir --transform-interpreter -debug-only=linalg-vectorization
```

For `@elementwise` the trace ends in `Vectorization pre-conditions
failed`, and the function is printed as it was. For `@rows` the
precondition passes, and the trace goes on to `Vectorize generic by
broadcasting to the canonical vector shape`, then `failed to vectorize:
scf.if`, then `Vectorization failed`. The function is printed with the
`linalg.generic` and, before it, what the vectorizer built:
`vector.create_mask`, two masked `vector.transfer_read`s, and an
`arith.cmpi` on `vector<4x1xi64>`.

Expected: the precondition fails for `@rows` as it does for
`@elementwise`, and `vectorize` leaves the function as it was.

## Cause

`mlir/lib/Dialect/Linalg/Transforms/Vectorization.cpp` at llvmorg-23.1.2:

- `vectorizeLinalgOpPrecondition` (lines 2224-2288) checks every op of
  the body only for its operand and result types (lines 2250-2268).
  The ops themselves are checked through `isElementwise` (line 2269),
  which requires `hasOnlyScalarElementwiseOp`
  (`mlir/lib/Dialect/Linalg/Utils/Utils.cpp`, lines 203-229), and that
  call is made for an all-parallel generic. For a generic with a
  reduction dimension the function returns the result of
  `reductionPreconditions` (line 2283; the function is at lines
  1879-1896), which checks the combiner of each output.
- `vectorizeOneOp` (lines 1358-1449) maps an op to vectors when a hook
  takes it (`linalg.yield`, `linalg.index`, `tensor.extract`), it is a
  constant, or it is elementwise-mappable. Any other op fails (lines
  1380-1382).
- `vectorizeAsLinalgGeneric` (lines 1473-1587) builds the reads of
  every operand (lines 1490-1546) before it tries the body's ops one
  by one (lines 1570-1584), so a refused op leaves the reads and every
  op mapped before it.

## Fix

`vectorizeLinalgOpPrecondition` should ask `hasOnlyScalarElementwiseOp`
of the body of every op that is vectorized as a generic, as
`isElementwise` already does for an all-parallel op. The custom
precondition registered above that check already covers the body's
`tensor.extract` ops. `vectorize` then fails before it builds anything.

The pull request does that and adds
`mlir/test/Dialect/Linalg/vectorization/reduction-body-unsupported.mlir`.
`@rows` is left whole, with no vector op built.
````

## Pull request

- Repository: https://github.com/llvm/llvm-project
- Base: `main`
- One commit. The diff is `llvm.patch` in this directory. Apply that
  file as the single commit of the branch:

  ```
  git am --keep-non-patch llvm.patch
  ```

  `--keep-non-patch` keeps the `[mlir][linalg]` prefix. Plain `git am`
  strips every leading bracketed word, including `[mlir]`. Do not
  rewrite `llvm.patch`. Do not add a sign-off.
- Upstream test the patch adds:
  `mlir/test/Dialect/Linalg/vectorization/reduction-body-unsupported.mlir`.
  `@rows`, a reduction whose body holds an `scf.if`, is left whole,
  with no vector op built.

GitHub squash-merges. The landed commit is the pull request title plus
the full pull request body. The message of the branch commit is not
what lands, and a contributor without write access cannot edit the
message at merge time, so set the title and the body to the text below
when opening the pull request. The title is the subject line, tagged
`[mlir]`. The body is why the precondition has to refuse this body
before `vectorize` builds anything.

After the issue exists, append `Fixes #<issue number>` as the last line
of the body, so the squash commit closes it.

### Title

```
[mlir][linalg] vectorizeOpPrecondition: check the body of a reduction
```

### Body

```
linalg::vectorizeOpPrecondition ("Return success if the operation can be
vectorized") accepts a linalg.generic with a reduction dimension whose
body holds an op the vectorizer cannot map, such as an scf.if or a
func.call. vectorizeLinalgOpPrecondition checks the body's ops with
hasOnlyScalarElementwiseOp only through isElementwise, for an
all-parallel op; for a reduction it checks the combiner alone
(reductionPreconditions). linalg::vectorize then builds the reads of
every operand and maps the body op by op, and fails on the first op
vectorizeOneOp refuses, leaving the vector code it built in the function.
A client that asks the precondition and transforms the op first (tiles
it, say) is left with the transformed op and no vectors.

vectorizeLinalgOpPrecondition now asks hasOnlyScalarElementwiseOp of the
body of every op that goes the generic way, as isElementwise does of an
all-parallel one, so vectorize fails before it builds anything. The
tensor.extract ops of the body are checked by the custom precondition
above it, as before.

Test: reduction-body-unsupported.mlir, a reduction with an scf.if in its
body is left whole, with no vector op built.
```
