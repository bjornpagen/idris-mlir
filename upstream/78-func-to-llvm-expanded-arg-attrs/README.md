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

## The fix

`pull-request.diff`, against the pin: for a ranked memref, the attributes of
the pointer the memref stands for (`llvm.noalias`, `llvm.nocapture`,
`llvm.nofree`, `llvm.nonnull`, `llvm.noundef`, `llvm.readonly`,
`llvm.writeonly`, `llvm.readnone`, `llvm.align`, `llvm.dereferenceable`
and `llvm.dereferenceable_or_null`) go to the descriptor's aligned
pointer alone; none to the allocated pointer, the offset, sizes or
strides; an attribute that is no pointer's is still dropped. The TODO
goes, and the test checks where the attributes go. An unranked memref is
left as it was: its pointer is the descriptor's, not the data's. Never
built.

Every access goes through the aligned pointer, so nothing the attributes
buy is lost there. The allocated pointer is the one a deallocation frees
(`memref.dealloc` lowers to a free of it), and the attributes claim
nothing of it: `noalias` on both pointers would make LLVM read two
arguments addressing one buffer as distinct objects (proposals/0000
C163). Upstream's GPU lowering refuses `noalias` on a non-bare memref for
the same two pointers (`GPUOpsLowering.cpp`, "Cannot copy noalias with
non-bare pointers").

What the diff does not settle, and whatever writes `noalias` on a
descriptor must: LLVM's alias analysis also reads a plain argument as distinct from a `noalias`
one (`BasicAliasAnalysis.cpp`, `aliasCheck`: an argument against an
identified function-local object, a `noalias` argument among them, is
`NoAlias`; *read* at the pin). So a function that reads the buffer
through the aligned pointer and frees it through the allocated one still
lets LLVM move the read past the free, whichever pointer carries
`noalias`. A lowering that writes it therefore frees such a buffer
through the aligned pointer, which its allocator makes equal to the
allocated one, or writes `noalias` only on a function that does not free
it (L21's lowering, which writes these attributes itself; *conjecture*
on LLVM's reordering, not reproduced).

## Why there is no patch

It was carried for the lowering of a function that owns a quantity-1
buffer, whose `noalias` FuncToLLVM dropped. The compiler's lowering now
builds every program function as an `llvm.func` itself and attaches
`noalias`, argument memory and the rest there (proposals/0000 C165,
L21), so no function of ours passes through FuncToLLVM and nothing in
the tree reaches the bug. The report stays as a submission, its pull
request as `pull-request.diff`, which the bootstrap does not apply.

## Upstreaming plan

Status: not carried since 2026-10-21 (C165); not filed.

- Where: one pull request to llvm/llvm-project, `[mlir][FuncToLLVM]`,
  resolving the TODO; the review will weigh the aligned pointer alone
  against both, and the diff moves to what lands.
- Upstream test: `convert-argattrs.mlir`'s `check_memref` and
  `check_memref_pointer_attributes`.
- The report goes when the pin keeps pointer attributes on an expanded
  memref.
