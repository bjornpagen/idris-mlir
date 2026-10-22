<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [AArch64] A function that pops its own stack arguments makes a sibling call, and returns with them still on the stack

On llvm main at 7208ba24 (the pin), and still on main on 2026-10-19, a
function whose calling convention makes it pop its incoming stack
arguments on return (`tailcc`, `swifttailcc`, `fastcc` under
`-tailcallopt`) lowers a call in tail position to a callee of another
convention, a C function, as a sibling call. The `TCRETURN` of a sibling
call adjusts the stack by `FPDiff`, which is 0 for one, and the epilogue of
a block that ends in a tail call pops what that operand says
(`AArch64FrameLowering::getArgumentStackToRestore`), not the function's
`ArgumentStackToRestore`. The callee returns straight to the caller's
caller with the argument area still on the stack: that caller re-adjusts
its stack pointer for a callee that popped and finds it the area's size
below where it left it, and its own epilogue reloads its frame record and
return address from the wrong slots.

`AArch64TargetLowering::isEligibleForTailCallOptimization`
(`llvm/lib/Target/AArch64/AArch64ISelLowering.cpp`) returns early for a
callee whose convention guarantees TCO, and otherwise looks for a sibling
call, checking that the callee's stack arguments fit the caller's area but
never that the caller has nothing to pop. GlobalISel's
`AArch64CallLowering::isEligibleForTailCallOptimization` has the same gap.
X86 refuses the case (`X86TargetLowering::IsEligibleForTailCallOptimization`:
when the caller has bytes to pop on return, the callee must pop the same).

## Reproduce

With the toolchain's llc, the test in `llvm.patch`
(`llvm/test/CodeGen/AArch64/tailcc-sibcall-callee-pop.ll`): `@pops`, a
`tailcc` function of ten i64 arguments whose last two come on the stack,
compiles to `ldr`s of them and `b c`, with no `add sp, sp, #16`, under
SelectionDAG and GlobalISel and for both arm64 Darwin and Linux; x86-64's
`@pops` calls `c` and pops its area with `retq $40`.

`stack-args-sibcall.mlir`, in the LLVM dialect alone: `@main`, a C
function, calls such a function and compares its stack pointer before and
after the call. Compiled by idris-mlir for arm64 macOS it exits on SIGBUS
(138) instead of 0.

In the compiler, every function of the program takes `tailcc` (idr-lower
gives it, `foreign/idr/lib/Conversion/Lower/Functions.cpp`); when the bug
was found, idr-tail-calls gave it to the functions on cycles of tail
calls. Such a function of more arguments than the
argument registers, whose last action is a runtime call (`idris_rt_dec` of
a string just printed), returned to its caller 16 bytes low: six programs
(tests directory-listing, files-roundtrip, array-of-arrays,
bounded-method-own, buffer-ops, io-loop-through-helper) printed everything
and then crashed after main returned, when `__idr$entry$body` reloaded its
frame record from 16 bytes below it, a cell's header and a heap address,
and returned into the heap. No store wrote the frame record: the stack
pointer was off.

## Expected

A function that must pop its incoming stack arguments makes no sibling
call; the call stays a call, and the function pops its argument area when
it returns.

## The fix

`llvm.patch`: both `isEligibleForTailCallOptimization`s refuse a sibling
call when the caller's `ArgumentStackToRestore` is not 0, after the early
return for a callee that guarantees TCO, so a tail call between two
`tailcc` functions, which adjusts the stack by `FPDiff` and lets the
callee pop the area, is unchanged. It adds
`llvm/test/CodeGen/AArch64/tailcc-sibcall-callee-pop.ll`: the call is a
`bl` followed by `add sp, sp, #16` and `ret`, and a `tailcc` function with
no stack arguments still makes the sibling call.

## Patch

`llvm.patch`, applied by tools/bootstrap.sh; checked by
tests/upstream-aarch64-sibcall-callee-pop (the program exits 0: the stack
pointer is where the caller left it).

## Upstreaming plan

An issue and a PR to llvm/llvm-project, `[AArch64]`, with the patch's
test, the commit message being the patch's header. The test's checks are
written by hand; upstream would regenerate them with
`update_llc_test_checks.py`. Status: not filed; carried; check-llvm not
run.
