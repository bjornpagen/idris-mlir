<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][bufferization] Tensor-likeness is a property of a type's class

On llvm main at 416f328b (the pin), `TensorLikeType` and `BufferLikeType`
(`mlir/include/mlir/Dialect/Bufferization/IR/BufferizationTypeInterfaces.td`,
*read*) are type interfaces with no `extraClassOf`, so a type class
either is tensor-like in every instance or in none. And
`bufferization.to_tensor` and `to_buffer` carry
`SameOperandsAndResultShape` and `SameOperandsAndResultElementType`
(`BufferizationOps.td`) beside `Bufferization_TensorAndBufferMatch`,
which already asks the tensor-like type whether the buffer is compatible
(`verifyCompatibleBufferType`; for builtins, the same shapes and element
types, `BufferizationDialect.cpp`).

The compiler's linear wrapper `!idr.lin<T>` is one class for every `T`:
a linear array, which One-Shot must bufferize itself, and a linear
handle, which is no tensor. Under proposals/0000 D43 and C108 it is
tensor-like exactly where `T` is, and an array field is its buffer from
the frontend on, through `to_buffer` and `to_tensor restrict`; with the
two shape traits, every bridge of a graded tensor fails to verify, since
a graded tensor is not a shaped type.

## Reproduce

Nothing upstream reaches it: no upstream type is tensor-like for some
instances alone. A type class implementing `TensorLikeType` makes every
instance a tensor to `isa`, and a `to_buffer` from a tensor-like type
that is not shaped fails `SameOperandsAndResultShape` (*read*).

## Patch

`llvm.patch`, applying after 62 (and before 65, which touches no file of
it): `isTensorLike()` and `isBufferLike()`, interface methods true by
default, with `extraClassOf` narrowing `isa` to the instances that
answer true; the two shape traits leave `to_tensor` and `to_buffer`,
whose `Bufferization_TensorAndBufferMatch` is the one rule (the
`invalid.mlir` cases keep their messages: that check fires first).
Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request to llvm/llvm-project, `[mlir][bufferization]`,
  beside 27's (`tensorAllocationFn`), naming `SymbolOpInterface`'s
  `extraClassOf` as the precedent.
- Upstream test: a test-dialect wrapper type tensor-like for one
  parameter alone, bufferized by One-Shot, and a `to_buffer` of it.
- The patch goes when the pin decides tensor-likeness per instance and
  checks bridges by the interface alone.
