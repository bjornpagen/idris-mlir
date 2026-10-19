<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][bufferization] An out-of-place OpOperand of a tensor-like type that is not a builtin tensor gets no copy

On llvm main at 7208ba24 (the pin), One-Shot Bufferize handles a
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
`llvm_unreachable`.

## Cause

The two functions test for the builtin types where they mean
`TensorLikeType`. `BufferizationOptions` has hooks for every other step that
depends on the types (`allocationFn`, `memCpyFn`, `castFn`, the type
converters, `reconcileBufferTypeMismatchFn`), but none to make a tensor-level
copy of a value of a dialect's own tensor-like type: `bufferization.alloc_tensor`
makes builtin ranked tensors alone.

## The fix

`pull-request.diff` is a `git diff` against 7208ba24:

- `BufferizationOptions::tensorAllocationFn` (`TensorAllocationFn`: builder,
  location, value, `copy`, options): a new value of the value's type, a copy
  of it if `copy` is set, otherwise one whose contents are undefined. Its
  default fails with "allocating a tensor of type T is not supported:
  BufferizationOptions::tensorAllocationFn is not set", at the location of
  the op that needed the copy.
- `allocateTensorForShapedValue` calls it for a value of a tensor-like type
  that is not a builtin tensor, where it reached `llvm_unreachable`.
- `resolveTensorOpOperandConflicts` takes every tensor-like OpOperand, where
  it skipped every one that is not a builtin tensor. Builtin tensors are
  copied as before.
- Both TODOs go.
- `one-shot-bufferize-tensor-like-copy.mlir`: the reproducer under
  `-verify-diagnostics`, which expects the error.

## Why there is no patch

Nothing in this repository reaches the bug: every tensor idr-bufferize
bufferizes is a builtin ranked tensor. The type a fix would bring into
reach is `!idr.lin<T>`, a linear array, which is not tensor-like, and the
fix alone does not make it one:

- A type interface belongs to a type's class, and `!idr.lin<T>` is
  `!idr.q<one, plain, T>`, the class of every grade, the world's included.
  Upstream MLIR can decide an interface per instance: an interface's
  `extraClassOf` (`mlir/include/mlir/IR/Interfaces.td:128`, emitted for type
  interfaces by `mlir-tblgen`'s `OpInterfacesGen.cpp:658-668` with
  `$_type`) narrows `isa` to the instances an interface method accepts, as
  `SymbolOpInterface` does for ops. `TensorLikeType` and `BufferLikeType`
  have none, so a second patch would add one (a method that says whether
  the instance is tensor-like, true by default); then `!idr.lin<T>` is
  tensor-like exactly where `T` is, and the world is not.
- With both patches, `!idr.lin<T>` as tensor-like would still not delete the
  retyping idr-bufferize runs after One-Shot (`idr::DataRemap` with the
  `buffers` kind, `foreign/idr/lib/Transforms/Bufferize/Bufferize.cpp`). It
  would remove its wrapper and signature cases, which One-Shot would then
  bufferize itself, but a data type's body holds tensors too: a field of a
  constructor is `tensor<...>` or `!idr.lin<tensor<...>>` (a vector's cells,
  a record's array), and a body is set once, so a body that holds a buffer
  is a new data type, which only the remap makes. Making a data type that
  holds an array tensor-like would make every such data type a tensor to
  the analysis, which is the world made a tensor. The remap goes only when
  a body holds a buffer from the start, a change to what the frontend emits
  and to what a data type's verifier accepts.
- So the patch would carry no case of ours; it is kept as a submission.

## Testing at the pin

Not built. The diff applies to the pristine pin and after every carried
patch (`git apply --check`; its hunks are clear of patch 24's in the same
two files), and `BufferizableOpInterface.cpp` passes `-fsyntax-only` with
the typecheck build's compile command of the pin, the patched header first.
`tests/upstream-one-shot-tensor-like-copy` checked that the pinned source
still skips such an OpOperand.

## Upstreaming plan

Status: not filed; not built; no `submission.md` yet.

One issue (the miscompile, with `tensor-like-copy.mlir` and the bufferized
output that writes the argument) and one pull request, "[mlir][bufferization]
Copy an out-of-place OpOperand of any tensor-like type", against
llvm/llvm-project main, from `pull-request.diff`. The body names the TODO it
resolves, and says why an option and not a `TensorLikeType` method: the copy
is an op of the type's dialect, and `BufferizationOptions` already holds the
hooks that build ops for the pass (`allocationFn`, `memCpyFn`, `castFn`).
If reviewers want a test of the hook itself, the test pass sets it to a
`test.create_tensor_op` for an allocation without a copy, and the test
dialect gains a copy op for one with.

Before filing:
- search for an upstream fix since 7208ba24 (main still had both TODOs on
  2026-10-15);
- read the in-tree callers of `allocateTensorForShapedValue` for a value of
  a custom type they assume builtin;
- check that the diff applies to then-current main and is clang-format
  clean.

`check-mlir` is the pull request's pre-merge CI's (upstream/README.md,
**CI decides**). When the pin carries upstream's fix, this directory and its
check go. The per-instance `extraClassOf` for `TensorLikeType` and
`BufferLikeType` is written only with a consumer: the day `!idr.lin<T>` is
made tensor-like.
