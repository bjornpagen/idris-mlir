<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][bufferization] An out-of-place OpOperand of a tensor-like type that is not a builtin tensor gets no copy

On llvm main at 416f328b (the pin, 2026-10-21), as at 7208ba24 and at
5eaa4e7e (main, 2026-10-23), One-Shot Bufferize handles a
`TensorLikeType` that is not a builtin tensor everywhere but where it
copies. Two places carry the same TODO, "Properly support with options, for
now it is hardcoded to builtin Tensor/MemRef types based approach":

- `BufferizableOpInterface::resolveTensorOpOperandConflicts`
  (`mlir/lib/Dialect/Bufferization/IR/BufferizableOpInterface.cpp:235-319`),
  which inserts the copy of every OpOperand the analysis decided
  out-of-place, skips an OpOperand whose type is not a builtin `TensorType`
  (`:250-251`). The analysis decided the copy because the op writes a buffer
  that is read after it; with no copy, the op writes that buffer. A silent
  miscompile.
- `allocateTensorForShapedValue` (`:164-233`), which makes the copy, handles
  a builtin ranked tensor, a memref and the unranked ones, and reaches
  `llvm_unreachable` for anything else (`:185`).

## Reproduce

`tensor-like-copy.mlir`, the test dialect's `!test.test_tensor`, which
implements `TensorLikeType` (`mlir/test/lib/Dialect/Test/TestTypeDefs.td:450`):
`test.dummy_tensor_op` reads and writes its operand, `%arg`, which the
return reads after it. With `-test-one-shot-module-bufferize` the analysis
decides the operand out-of-place, `resolveTensorOpOperandConflicts` skips it,
and the bufferized `test.dummy_memref_op` writes the argument's buffer, which
the function then returns as both results. No upstream dialect but the test
dialect has a tensor-like type of its own, so the reproducer needs it.

(Read from the source. The toolchain's `mlir-opt` builds no test dialect,
and no `mlir-opt` of the pin with it was at hand.)

## Expected

An OpOperand of any tensor-like type that bufferizes out-of-place is given a
copy, made by a hook its dialect sets, and without the hook bufferization
fails with an error that names the type, never with no copy and never in
`llvm_unreachable`. The ops the hook builds may read the value they copy,
and keep reading it: only the uses the value had before its copy read the
copy.

## Cause

The two functions test for the builtin types where they mean
`TensorLikeType`. `BufferizationOptions` has hooks for every other step that
depends on the types (`allocationFn`, `memCpyFn`, `castFn`, the type
converters, `reconcileBufferTypeMismatchFn`), but none to make a tensor-level
copy of a value of a dialect's own tensor-like type: `bufferization.alloc_tensor`
makes builtin ranked tensors alone.

## The copy of a result

Where the op does not write the out-of-place OpOperand and the operand has
one alias, an OpResult whose one aliasing OpOperand it is,
`resolveTensorOpOperandConflicts` copies the result instead (the result of
an `extract_slice` is usually the smaller), and gives the copy to the
result's uses (`:296-316`, the same at the pin and on main at 5eaa4e7e). It
takes those uses after the copy is made, so they include the ops that made
it, and it tells them apart by two exceptions: the op that defines the copy
and every `tensor.dim`. That covers what upstream's own copy builds of the
value: `alloc_tensor`, which reads it as its `copy` operand and defines the
copy, and the `tensor.dim` ops of its dynamic extents.

A hook's copy is not covered. An op the hook builds that reads the value
and does not define the copy (a cast to the builtin tensor a dialect copies
through, before an `alloc_tensor` and a cast back) is given the copy, which
its own result defines through the ops after it: a cycle, and the module no
longer verifies. Our hook builds exactly that for every graded array
(`foreign/idr/lib/Transforms/Bufferize/Bufferize.cpp`, the cast `heldAs`
makes of the value, then `alloc_tensor` and the cast back to the array's
uses), so every graded array copied at a result, the result of an
`idr.lin.cast` from a builtin tensor among them, would be a cycle. The
copy's readers are the uses the value had before the copy; taken first,
they need no exception at all.

## Patch

`llvm.patch` is a `git diff` against 416f328b, which applies after every
patch before it and to main at 5eaa4e7e:

- `BufferizationOptions::tensorAllocationFn` (`TensorAllocationFn`: builder,
  location, value, `copy`, options): a new value of the value's type, a copy
  of it if `copy` is set, otherwise one whose contents are undefined. Its
  default fails with "allocating a tensor of type T is not supported:
  BufferizationOptions::tensorAllocationFn is not set", at the location of
  the op that needed the copy. Its documentation says the ops it builds may
  read the value and that only the value's earlier uses are given the copy.
- `allocateTensorForShapedValue` calls it for a value of a tensor-like type
  that is not a builtin tensor, where it reached `llvm_unreachable`.
- `resolveTensorOpOperandConflicts` takes every tensor-like OpOperand, where
  it skipped every one that is not a builtin tensor. Builtin tensors are
  copied as before.
- Where it copies a result, `resolveTensorOpOperandConflicts` takes the
  result's uses before the copy is made and gives the copy to those alone.
  Both exceptions go, and with them the file's include of the tensor
  dialect, which only `tensor::DimOp` there needed. One thing changes for a
  builtin tensor: a `tensor.dim` of the result that stood before the copy now
  reads the copy, whose sizes are the same. No upstream test at the pin has
  one (*read*: every `tensor.dim` in the bufferization tests reads a block
  argument or the result of an op that is not copied this way).
- Both TODOs go.
- `one-shot-bufferize-tensor-like-copy.mlir`: the first reproducer under
  `-verify-diagnostics`, which expects the error.
- `tensor-copy-insertion-tensor-like.mlir`: the copy of a result, under
  `-test-tensor-copy-insertion=copy-test-tensors`. The test dialect gains
  `test.tensor_like_cast`, the same tensor at another tensor-like type, which
  neither reads nor writes and bufferizes to a `test.dummy_cast_op`; the
  copy-insertion test pass gains the option `copy-test-tensors`, which sets
  the hook to copy a test tensor as the builtin tensor of its shape, between
  two such casts. A cast whose argument is not writable and whose result
  `test.dummy_tensor_op` writes has its result copied, and the test checks
  that the hook's first cast reads the result, the `alloc_tensor` copies that
  cast, and the writer reads the cast back. Before the change the hook's
  first cast is given the copy, the module does not verify, and FileCheck
  sees no output.

## Why it is carried

A graded array, `!idr.graded<uses, hold, T>` over a tensor `T`, is
tensor-like wherever `T` is (`GradedTensorLike`,
`foreign/idr/lib/Transforms/Bufferize/Linear.cpp`), so One-Shot
bufferizes graded values and signatures itself, and an array field is
its buffer from the frontend on (proposals/0000 D43, C108). A graded
array that bufferizes out-of-place is then an OpOperand of a tensor-like
type that is not a builtin tensor, which the pin writes in place.
idr-bufferize sets this patch's hook to copy it at its grade
(`options.tensorAllocationFn`, `Bufferize/Bufferize.cpp`), so the
compiler does not build without the patch, and the hook reads the array
through a cast, so a graded array copied at a result needs the uses taken
first. The per-instance tensor-likeness is the other half,
`upstream/64-tensor-like-per-instance`, without which `!idr.graded`, one
class for every `T`, could not be tensor-like for some `T` alone.

## Testing at the pin

Not built. The diff applies to the pristine pin, 416f328b; in the
bootstrap's order among the carried patches, each applied in turn to a copy
of the pin's `mlir/` (its part under `mlir/`; this patch touches nothing
else), every one before and after it applying (`git apply --check`,
2026-10-23); and to main at 5eaa4e7e (the two test-dialect hunks at
offsets). At 7208ba24, `BufferizableOpInterface.cpp`
passed `-fsyntax-only` with the typecheck build's compile command, the
patched header first, before the result's uses were taken first; the
amended file and the test library's changes have not been compiled. The
bootstrap builds no MLIR tests, so neither upstream test has run.

Its check, `tests/upstream-one-shot-tensor-like-copy`, runs
`copied-result.mlir` through the pipeline to the end of the first stage
with the compiler's own tools: a graded array that One-Shot copies at the
cast that makes it, whose copy our hook makes through a cast of the array.
It holds when the module verifies and the output has the copy, which the
callee writes while the tensor the array was cast from is read after. It
has not run: no toolchain with this patch is built, on any target.

## Upstreaming plan

Status: carried (2026-10-21), amended 2026-10-23 for the copy of a result;
not filed; not built; no `submission.md` yet.

One issue (the miscompile, with `tensor-like-copy.mlir` and the bufferized
output that writes the argument) and one pull request, "[mlir][bufferization]
Copy an out-of-place OpOperand of any tensor-like type", against
llvm/llvm-project main, from `llvm.patch`. The body names the TODO it
resolves, and says why an option and not a `TensorLikeType` method: the copy
is an op of the type's dialect, and `BufferizationOptions` already holds the
hooks that build ops for the pass (`allocationFn`, `memCpyFn`, `castFn`).
It says why the copy of a result takes the result's uses first: a hook may
read the value through ops other than the one that defines the copy, and
the uses the value had before the copy are exactly its readers, with no
exception for `alloc_tensor` or `tensor.dim`; and that a `tensor.dim` of
the result standing before the copy now reads the copy. The hook's own
test, `tensor-copy-insertion-tensor-like.mlir`, goes with it, since only a
hook reaches the copy of a result whose own ops read it; the same option
tests the copy of an operand too, if reviewers want that case.

Before filing:
- search for an upstream fix since 5eaa4e7e (main still had both TODOs and
  the two exceptions on 2026-10-23);
- read the in-tree callers of `allocateTensorForShapedValue` for a value of
  a custom type they assume builtin;
- check that the diff applies to then-current main and is clang-format
  clean (Apple clang-format 21 asks to rewrap `defaultTensorAllocation`;
  the hunks added on 2026-10-23 are clean under it).

`check-mlir` is the pull request's pre-merge CI's (upstream/README.md,
**CI decides**). When the pin carries upstream's fix, `llvm.patch`, its
check and its `PINS.md` entry go.
