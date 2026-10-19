<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Crash after main returns (exit 138/139): an LLVM AArch64 sibcall bug

Status (2026-10-19): root cause found and reduced to LLVM alone. An LLVM
patch was written and checked with a patched llc. It was not checked
end-to-end: idris-mlir was not rebuilt against the patched LLVM, and none of
the six tests was run with it. Work stopped there, as the owner asked.

## Symptom

directory-listing, files-roundtrip, array-of-arrays, bounded-method-own,
buffer-ops and io-loop-through-helper print all their output and then die
after main (SIGBUS or SIGSEGV). The program thread jumps into the heap
(`pc = lr = 0x7X00024000`, `fp = 1`).

## Root cause

No store corrupts anything. The **stack pointer** comes back 16 bytes
low from a `tailcc` function.

- On arm64, `tailcc` is callee-pops: a function pops its own incoming
  stack arguments when it returns (`ArgumentStackToRestore`). idr-tail-calls
  (foreign/idr/lib/Conversion/TailCallPlan.cpp, TailCalls.cpp) gives
  `tailcc` to the functions on cycles of tail calls. Some of them take more
  arguments than the eight registers hold.
- In directory-listing,
  `PrimIO.io_bind[Unit, Either FileError Directory].lam.93ee3dc4a8b9acc4`
  takes 11 arguments, 16 bytes of them on the stack on Darwin. On its path
  that prints a message (`putStrLn`), it ends in a call to the C function
  `idris_rt_dec`. LLVM lowers that call as a **sibling call**:
  `add sp, sp, #0x80; b _idris_rt_dec`. That pops the frame but not the 16
  bytes of arguments. `idris_rt_dec` returns straight to the tailcc
  function's caller, which then re-adjusts for a callee that popped, so
  `sp` ends 16 bytes too low. Every other return path of the same function
  ends in `add sp, sp, #0x90; ret`, which pops 16 more.
- From then on, every frame above reads its saved registers 16 bytes off.
  `__idr$entry$body` (`stp x29, x30, [sp, #-16]! ... ldp x29, x30, [sp], #16;
  ret`) reloads its frame record from a slot that a callee's frame used
  last, which happens to hold a cell header and a heap pointer
  (`{1, 0x7000024000}`). It then returns into the heap.
- The faulting "write" does not exist. lldb showed it: the stack pointer at
  `idris_rt_caf_release`'s entry (called from body) is 16 bytes below
  body's own stack pointer. Hardware watchpoints on body's real frame
  record never fired, and that record was intact. This explains why the
  earlier watchpoints "showed them intact". It also explains why removing
  any part of the program hid the crash: the slot's stale contents change.
  snmalloc, the frame cells, the handle table and the live-cell count are
  all unrelated.

The LLVM source of the bug is
`AArch64TargetLowering::isEligibleForTailCallOptimization`
(llvm/lib/Target/AArch64/AArch64ISelLowering.cpp, ~line 10114 at the pin
7208ba24). After the early return for callees that guarantee TCO, it looks
for a sibling call. It checks that the callee's stack arguments fit the
caller's area, but never that the caller has nothing of its own to pop. A
sibcall's `TCRETURN` carries `FPDiff = 0`, so
`AArch64FrameLowering::getArgumentStackToRestore` pops nothing. GlobalISel's
`AArch64CallLowering::isEligibleForTailCallOptimization` has the same gap.
X86 refuses this case. Upstream main still has it: I read main's function
on 2026-10-19 and found no such check.

## Reproducers

- LLVM alone (`llc -O2`, also `-O0`/GlobalISel, arm64 Darwin and Linux):

      declare void @c(ptr)
      define tailcc void @f(i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4,
                            i64 %a5, i64 %a6, i64 %a7, i64 %a8, ptr %p) {
        tail call void @c(ptr %p)
        ret void
      }

  At the pin this compiles to `ldr x0, [sp, #8]; b _c` with no `add sp`.
  x86-64 compiles it to `call c; ret $N` (correct).
- End to end, LLVM dialect only, through idris-mlir: a `tailcc @pops` of ten
  i64 arguments that tail-calls `@idris_rt_handle_is_null`. `@main` compares
  `llvm.intr.stacksave` before and after the call. Run it through
  `idris-mlir-opt --idr-target`, then `idris-mlir -o prog`, then `./prog`.
  At the pin it exits 138; with a correct LLVM it should exit 0. (The
  arguments must all be used and the result must decide the exit status.
  Otherwise whole-program optimization drops the stack arguments or the
  call.)
- directory-listing under lldb: break at `__idr$entry$body`, `stepi`, note
  `sp`, then break at `idris_rt_caf_release` and compare `sp`. It is 16
  lower.

## The fix (written, not committed)

The same check in both lowerings, placed after the guaranteed-TCO early
return (so tailcc-to-tailcc tail calls, which use FPDiff, are unchanged):

    // A sibling call leaves the stack as the caller found it, and its callee
    // returns straight to the caller's caller. A caller that must pop its own
    // incoming stack arguments on return (e.g. tailcc) would leave them on the
    // stack, so it cannot make one.
    if (MF.getInfo<AArch64FunctionInfo>()->getArgumentStackToRestore() != 0)
      return false;

The GlobalISel version adds an `LLVM_DEBUG` line. The upstream test is
`llvm/test/CodeGen/AArch64/tailcc-sibcall-callee-pop.ll`. In it, `@pops`
(ten i64, two on the stack) must become `bl c` ... `add sp, sp, #16` /
`ret`, under SelectionDAG and GlobalISel, on Linux and Darwin.
`@pops_nothing` (no stack arguments) must still be `b c`.

Checked: a stage 2 built with the patch (tools/bootstrap.sh runtimes
stage2, into this worktree's own .toolchain) passes all three RUN lines of
that test. The pinned llc fails its SelectionDAG and GlobalISel lines.

Prepared in this worktree, uncommitted (the owner paused fixing):
`upstream/30-aarch64-sibcall-callee-pop/` (README.md, llvm.patch,
stack-args-sibcall.mlir), `tests/upstream-aarch64-sibcall-callee-pop/`
(behavioural check: the program exits 0), a PINS.md entry
`aarch64-sibcall-callee-pop`, and an upstream/README.md row. This
worktree's `.toolchain` is a private directory, not the usual link. It
holds clones of the shared toolchain and its own patched llvm, with the
stamps of cmake, ninja and stage1 rewritten for this path. Do not copy it
elsewhere.

## Not done / next steps

1. In this worktree: `make build`, then run the six tests,
   `tests/upstream-aarch64-sibcall-callee-pop`, `make test-idr`,
   `make test-mlir-tools`, and a full `make test`. Confirm all six programs
   share this cause. That is expected but not verified for the other five.
   Each needs a tailcc function with stack arguments that ends in a C call.
2. Commit the patch, the check and the PINS entry. Then rebuild the shared
   toolchain (`tools/bootstrap.sh runtimes stage2`; with ccache it took
   about 25 minutes here). Until then, `make build` refuses (the stamp
   lacks patch 30).
3. Arm64 Linux has the same bug: the stack slots are 8 bytes there, so the
   area for 11 arguments is 32 bytes, not 16. x86-64 is unaffected.
4. No representation change on our side is called for. TailCallPlan is
   the one place that decides conventions, and its choice is valid IR. The
   bug is LLVM's alone (AGENTS.md: patch upstream, no workaround).
