Approach changed: the old patch added one more elementwise check after reductionPreconditions; now the precondition and vectorizeOneOp call one predicate, isVectorizableWithoutHook, so every body op that passes is one the vectorizer can map.

# Filing

Status: file (new issue and PR).

File a new GitHub issue and a new GitHub pull request on
https://github.com/llvm/llvm-project. LLVM's tracker and review are
GitHub. Do not file a Bugzilla bug. A search of the tracker (October
2026) found no existing report.

The author is Bjorn, as an individual, outside any employer. The commit
and the pull request name no employer. No `Assisted-by` trailer. No
`@` mentions in the title, the body, or a comment.

## Issue

New issue: https://github.com/llvm/llvm-project/issues/new

### Title

```
[mlir][linalg] vectorize leaves IR behind for a reduction with an scf.if in its body
```

### Body

````
`linalg::vectorizeOpPrecondition` accepts a `linalg.generic` with a
reduction iterator whose body holds an op the vectorizer cannot map, such
as an `scf.if`. `linalg::vectorize` then creates the `transfer_read`s and
the vector form of the ops before the `scf.if`, fails on it, and returns
failure with that IR left in the function. The same body in an
all-parallel generic is rejected by the precondition before anything is
created.

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
    %1 = transform.get_parent_op %0 {isolated_from_above} : (!transform.any_op) -> !transform.any_op
    %2 = transform.structured.vectorize_children_and_apply_patterns %1 : (!transform.any_op) -> !transform.any_op
    transform.yield
  }
}
```

`mlir-opt repro.mlir --transform-interpreter` fails with
`error: failed to apply` on `vectorize_children_and_apply_patterns`:
`VectorizationPattern` changes the IR and then returns failure, so the
greedy driver does not converge. Applying `transform.structured.vectorize`
to the generic inside `failures(suppress)` instead prints the function
with two `vector.transfer_read`s and an `arith.cmpi` on
`vector<8x16xi64>` in front of the untouched `linalg.generic`. Expected:
the precondition fails and the IR is left as it was.

Cause, in `mlir/lib/Dialect/Linalg/Transforms/Vectorization.cpp` (as of
llvmorg-23.1.2 and main): `vectorizeLinalgOpPrecondition` checks the
kinds of the body ops only through `isElementwise`
(`hasOnlyScalarElementwiseOp`), that is, only for an all-parallel op; for
an op with a reduction iterator it returns `reductionPreconditions`,
which checks the combiner of each output. `vectorizeOneOp` maps an op
only if a hook takes it, it is a constant, or it is ElementwiseMappable,
and `vectorizeAsLinalgGeneric` builds the reads of every operand before
it tries the first op.
````

## Pull request

- Repository: https://github.com/llvm/llvm-project
- Base: `main`
- One commit. The diff is `llvm.patch` in this directory. Apply that
  file as the single commit of the branch:

  ```
  git am --keep-non-patch llvm.patch
  ```

  `--keep-non-patch` keeps the `[mlir][linalg]` prefix. Do not add a
  sign-off.

GitHub squash-merges, and the landed commit is the pull request title
plus body, so set them to the text below. After the issue exists, append
`Fixes #<issue number>` as the last line of the body.

### Title

```
[mlir][linalg] Check every body op in the vectorization precondition
```

### Body

```
vectorizeLinalgOpPrecondition checks the ops of the body against what
the vectorizer can map only through isElementwise, that is, only for an
all-parallel op. For an op with a reduction iterator it checks the
combiner and nothing else, so a body that holds, say, an scf.if passes.
vectorizeAsLinalgGeneric then creates the transfer_reads and maps the
body op by op until vectorizeOneOp refuses the scf.if, and
linalg::vectorize returns failure with that IR left behind.
VectorizationPattern therefore returns failure after changing the IR,
and vectorize_children_and_apply_patterns fails to converge.

Which ops vectorizeOneOp maps without a hook (a constant, or an
ElementwiseMappable op) is now one predicate, isVectorizableWithoutHook,
used by vectorizeOneOp and by the per-op loop of the precondition, which
already asks tensor.extract the precondition of its hook. The loop
admits linalg.yield and linalg.index by kind, since their hooks take
every such op, and affine.apply, which is expanded into arith ops before
the body is vectorized; it rejects every other op, for every linalg op,
before anything is created. Convolution and contraction bodies are arith
ops, so they pass as before.

Test: unsupported.mlir, vectorize_children_and_apply_patterns leaves a
reduction whose body holds an scf.if unchanged; before this change the
transform failed to apply.
```
