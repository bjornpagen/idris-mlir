<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [clang][Driver] -fstack-clash-protection is ignored on Darwin

On llvm main at 416f328b (the pin), clang's driver passes
`-fstack-clash-protection` to the compiler only for Linux, FreeBSD and
Fuchsia (`RenderSCPOptions`, `clang/lib/Driver/ToolChains/Clang.cpp`,
*read*). On a Darwin target the flag is "argument unused during
compilation", an error in any configure check that adds `-Werror`, and
nothing is probed: a frame larger than a page is allocated by one
subtraction from the stack pointer and can step over the guard page
below the stack.

The runtime, GMP and the LLVM in our tools are code whose frames our
compiler does not size, so they take stack clash protection on every
target (proposals/0000 C59, C5). On arm64 macOS they could not.

## Reproduce

`large-frame.c`, compiled for `arm64-apple-macosx14.0` with
`-fstack-clash-protection -Werror -S`: at the pin the driver refuses the
unused flag; without `-Werror` the 64 KiB frame is one `sub sp` with no
probe (*read*: the driver never passes the flag to cc1, so no function
gets `"probe-stack"="inline-asm"`). No SDK is needed.

## Cause

Only the driver's list of systems. What the flag turns on is target code
with no run-time support, and none of it excludes Darwin (*read* at the
pin):
- clang's code generation gives every function `"probe-stack"="inline-asm"`
  when cc1 has the flag (`CodeGenModule.cpp`), for any target;
- AArch64 reads it on every target but Windows and UEFI
  (`AArch64FunctionInfo`'s constructor), and probes inline wherever it is
  not Windows (`AArch64TargetLowering::hasInlineStackProbe`); X86 the same
  (`X86TargetLowering::hasInlineStackProbe`);
- the probes are plain loads and stack pointer arithmetic in the prologue
  (`AArch64FrameLowering::inlineStackProbeFixed`). They add call frame
  information only to a function without a frame pointer, and Darwin's
  compact unwind encoder falls back to DWARF for any directive it cannot
  encode (`AArch64AsmBackend.cpp`, `generateCompactUnwindEncoding`), so
  unwinding stays correct either way;
- Darwin's stacks end in a guard page, the main thread's and each
  pthread's (one page, 16 KiB on arm64; *recalled*), larger than the
  4 KiB probe interval.

Upstream's review of the systems check said as much: on D92245 (2020),
reviewers asked how things go wrong on Darwin and found nothing specific
to it in the implementation; that change was reverted for an unrelated
regression, and the list was never revisited.

## Patch

`llvm.patch`: Darwin joins the systems `RenderSCPOptions` passes the flag
for. Upstream's driver test gains Darwin runs (macOS on arm64 and x86_64,
iOS, and off by default), and a codegen test checks the AArch64 probe
loop for a Mach-O target. Not built.

The bootstrap's stage 1 builds the patched tree too, since it compiles
stage 2's LLVM, whose frames take the protection on every target; so the
target section passes the flag on all four, with no case for Darwin.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request to llvm/llvm-project, `[clang][Driver]`, in the
  form of #119633 (Fuchsia's entry, 2024).
- Upstream test: `clang/test/Driver/stack-clash-protection.c`'s Darwin
  runs and `llvm/test/CodeGen/AArch64/stack-probing-darwin.ll`.
- The patch goes when the pin's driver passes the flag for Darwin.
