<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][bufferization] An out-of-place OpOperand of a tensor-like type that is not a builtin tensor gets no copy

On llvm main at 416f328b (the pin, 2026-10-21), as at 7208ba24, One-Shot Bufferize handles a
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

## Patch

`llvm.patch` is a `git diff` against 7208ba24, which applies unchanged to
416f328b and after every patch before it:

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

## Why it is carried

A graded array, `!idr.graded<uses, hold, T>` over a tensor `T`, is
tensor-like wherever `T` is, so One-Shot bufferizes graded values and
signatures itself, and an array
field is its buffer from the frontend on (proposals/0000 D43, C108). The
cutover deleted the retyping idr-bufferize used to run after One-Shot
(the old `idr::DataRemap`'s `buffers` kind), which this replaces; no code
of it is left. A graded array that bufferizes out-of-place is
then an OpOperand of a tensor-like type that is not a builtin tensor,
which this patch copies through the dialect's hook where the pin wrote it
in place. The per-instance tensor-likeness is the other half,
`upstream/64-tensor-like-per-instance`, without which `!idr.graded`, one
class for every `T`, could not be tensor-like for some `T` alone.

## Testing at the pin

Not built. The diff applies to the pristine pin, 416f328b, and after every
patch before it (`git apply --check`; its hunks are clear of patch 24's in
the same two files). At 7208ba24, `BufferizableOpInterface.cpp` passed
`-fsyntax-only` with the typecheck build's compile command, the patched
header first. Its check, `tests/upstream-one-shot-tensor-like-copy`, is
written with this change: the toolchain's `mlir-opt` builds no test
dialect, so the check bufferizes an out-of-place linear array, a
tensor-like type that is not a builtin tensor, with the compiler's own
tools, and asserts that the operand is copied, never written in place.

## Upstreaming plan

Status: carried (2026-10-21); not filed; not built; no `submission.md` yet.

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
- search for an upstream fix since 416f328b (main still had both TODOs on
  2026-10-21);
- read the in-tree callers of `allocateTensorForShapedValue` for a value of
  a custom type they assume builtin;
- check that the diff applies to then-current main and is clang-format
  clean.

`check-mlir` is the pull request's pre-merge CI's (upstream/README.md,
**CI decides**). When the pin carries upstream's fix, `llvm.patch`, its
check and its `PINS.md` entry go.
