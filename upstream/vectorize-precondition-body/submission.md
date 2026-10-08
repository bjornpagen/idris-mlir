# Filing

Status: file (new issue and pull request).

File a new issue and a new pull request on
https://github.com/llvm/llvm-project, issue first. A search of the
tracker and of open pull requests (October 2026) found no report and no
fix; the code involved is unchanged on main at 7208ba24.

The author is Bjorn, as an individual, outside any employer. No
`Assisted-by` trailer, no sign-off, no `@` mentions.

## Issue

New issue: https://github.com/llvm/llvm-project/issues/new

### Title

```
[mlir][linalg] Vectorizer leaves partial IR for a reduction with scf.if
```

### Body

````
`linalg::vectorizeOpPrecondition` accepts a `linalg.generic` with a
reduction iterator whose body holds an op the vectorizer cannot map,
such as an `scf.if`. `linalg::vectorize` then creates the
`transfer_read`s and the vector form of the ops before the `scf.if`,
fails on it, and returns failure with that IR left in the function. The
same body in an all-parallel generic is rejected by the precondition
before anything is created.

repro.mlir:

```mlir
func.func private @side_effect()

func.func @f(%in: memref<8x16xi64>, %out: memref<8xi64>) {
  linalg.generic {indexing_maps = [affine_map<(d0, d1) -> (d0, d1)>, affine_map<(d0, d1) -> (d0)>],
                  iterator_types = ["parallel", "reduction"]}
      ins(%in : memref<8x16xi64>) outs(%out : memref<8xi64>) {
  ^bb0(%x: i64, %acc: i64):
    %c0 = arith.constant 0 : i64
    %z = arith.cmpi eq, %x, %c0 : i64
    scf.if %z {
      func.call @side_effect() : () -> ()
    }
    %t = arith.addi %acc, %x : i64
    linalg.yield %t : i64
  }
  return
}

module attributes {transform.with_named_sequence} {
  transform.named_sequence @__transform_main(%arg1: !transform.any_op {transform.readonly}) {
    %0 = transform.structured.match ops{["linalg.generic"]} in %arg1 : (!transform.any_op) -> !transform.any_op
    %1 = transform.get_parent_op %0 <isolated_from_above> : (!transform.any_op) -> !transform.any_op
    %2 = transform.structured.vectorize_children_and_apply_patterns %1 : (!transform.any_op) -> !transform.any_op
    transform.yield
  }
}
```

`mlir-opt repro.mlir --transform-interpreter` fails with `error: failed
to apply` on `vectorize_children_and_apply_patterns`:
`VectorizationPattern` changes the IR and then returns failure, so the
greedy driver does not converge. Applying `transform.structured.vectorize`
to the generic inside a `failures(suppress)` sequence instead prints the
function with two `vector.transfer_read`s and an `arith.cmpi` on
`vector<8x16xi64>` in front of the untouched `linalg.generic`.

Expected: the precondition fails, and the function is left as it was.

Cause, in `mlir/lib/Dialect/Linalg/Transforms/Vectorization.cpp`:
`vectorizeLinalgOpPrecondition` checks the kinds of the body ops only
through `isElementwise` (`hasOnlyScalarElementwiseOp`), that is, only
for an all-parallel op; for an op with a reduction iterator it returns
`reductionPreconditions`, which checks the combiner of each output.
`vectorizeOneOp` maps an op only if a hook takes it, it is a constant,
or it is ElementwiseMappable, and `vectorizeAsLinalgGeneric` creates the
reads of every operand before it maps the first body op.

Reproduced with llvmorg-23.1.2 (with `{isolated_from_above}`, the
spelling there); the code involved is the same on main at 7208ba24.
````

## Pull request

- Repository: https://github.com/llvm/llvm-project, base `main`.
- One commit; its diff is `pull-request.diff` in this directory, which
  applies to main at 7208ba24 (`git apply pull-request.diff`).
  `llvm.patch` is the same change for llvmorg-23.1.2, which this
  repository builds; it differs only in the test's
  `transform.get_parent_op` spelling, `{isolated_from_above}` there.
- Set the title and body below; GitHub squash-merges them as the commit
  message. Replace `<issue>` with the issue's number once it is filed.

### Title

```
[mlir][linalg] Check every body op in the vectorization precondition
```

### Body

```
vectorizeLinalgOpPrecondition checks the kinds of the body ops only
through isElementwise, that is, only for an all-parallel op. For an op
with a reduction iterator it checks the combiner and the types of the
body ops, so a body that holds an op the vectorizer cannot map, such as
an scf.if, passes. vectorizeAsLinalgGeneric then creates the
transfer_reads and maps the body op by op until vectorizeOneOp refuses
the scf.if, and linalg::vectorize returns failure with that IR left
behind. VectorizationPattern therefore fails after changing the IR, and
vectorize_children_and_apply_patterns fails to apply.

The rule vectorizeOneOp applies to an op that no hook takes (a
constant, or an ElementwiseMappable op) is now one predicate,
isVectorizableWithoutHook, which the per-op loop of the precondition
calls too. The ops that hooks take are admitted as before:
tensor.extract through its own precondition, linalg.yield and
linalg.index, whose hooks take every such op, and affine.apply, which
convertAffineApply expands before the body is vectorized. A hook added
later without being listed there makes the precondition reject its op,
never accept one that the vectorizer refuses.

The precondition now fails for such ops, for every linalg op, so
linalg::vectorize fails without rewriting anything. Convolution and
contraction bodies are arith ops and pass as before.

Test: unsupported.mlir, a reduction whose body holds an scf.if is left
unchanged by vectorize_children_and_apply_patterns; before this change
the transform failed to apply.

Fixes #<issue>
```
