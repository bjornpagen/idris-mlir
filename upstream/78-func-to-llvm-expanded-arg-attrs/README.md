<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][FuncToLLVM] A memref argument's attributes are dropped

On llvm main at 416f328b (the pin), `propagateFunctionArgResAttrs`
(`mlir/lib/Conversion/FuncToLLVM/FuncToLLVM.cpp`, *read*) attaches an
argument's attributes only where the argument converts to one LLVM
argument; for an argument that expands into several, a ranked memref's
descriptor among them, it attaches an empty dictionary to each, under
the pin's own TODO ("Implement custom handling for types that expand to
multiple function arguments"). `convert-argattrs.mlir` checks the drop.

So a quantity-1 buffer's `llvm.noalias`, which the compiler writes on
the memref argument of the function that owns it, never reaches LLVM,
and neither does D61's argument-memory fact, unless every memref is
lowered with the bare-pointer convention (*measured* on Homebrew's LLVM
22.1.8, proposals/0000 C149; the pin's code is the same).

## Reproduce

`memref-noalias.mlir`, under `-convert-func-to-llvm`: the lowered
function's seven arguments carry no attribute (*read* at the pin).

## Patch

`llvm.patch`, applying after 77: for a ranked memref, the pointer
attributes go where they hold. `llvm.noalias`, `llvm.nocapture`,
`llvm.nofree`, `llvm.nonnull`, `llvm.noundef`, `llvm.readonly`,
`llvm.writeonly` and `llvm.readnone` go to the allocated and the aligned
pointer; `llvm.align`, `llvm.dereferenceable` and
`llvm.dereferenceable_or_null`, which measure from the data, to the
aligned pointer alone; none to the offset, sizes or strides; an attribute
that is no pointer's is still dropped. The TODO goes, and the test checks
where the attributes go. An unranked memref is left as it was: its
pointer is the descriptor's, not the data's. Not built.

Both pointers address one buffer. LLVM reads two `noalias` arguments as
pointing to distinct objects, so a function that frees the buffer through
the allocated pointer after reading it through the aligned one lets LLVM
move the read past the free. Upstream's GPU lowering refuses `noalias`
on a non-bare memref for that reason (`GPUOpsLowering.cpp`, "Cannot copy
noalias with non-bare pointers"). The compiler's lowering therefore
frees a buffer whose argument is `noalias` through the aligned pointer,
which its allocator makes equal to the allocated one, or writes
`noalias` only on a function that does not free it (L21's lowering;
*conjecture* on LLVM's reordering, not reproduced).

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request to llvm/llvm-project, `[mlir][FuncToLLVM]`,
  resolving the TODO; the review will weigh the two-pointer `noalias`
  above, and the patch moves to what lands.
- Upstream test: `convert-argattrs.mlir`'s `check_memref` and
  `check_memref_pointer_attributes`.
- The patch goes when the pin keeps pointer attributes on an expanded
  memref.
