<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [snmalloc] The Arm AAL's pause() is inline assembly where the compiler has the yield intrinsic

At snmalloc 0.7.6 (f126f1c, the pin of third_party/snmalloc) and on its
main branch (read 2026-10-15), `AAL_arm::pause()`
(`src/snmalloc/aal/aal_arm.h:53-60`), which every spin loop calls through
`Aal::pause()` (`ds/combininglock.h`, `ds_aal/flaglock.h`,
`ds_aal/singleton.h`, `ds/aba.h`, `ds_aal/prevent_fork.h`), is

    #ifdef _MSC_VER
          __yield();
    #else
          __asm__ volatile("yield");
    #endif

so with clang and GCC it is an inline-assembly statement. The same file's
`prefetch()` (`:62-72`) already takes the compiler's builtin first,
`__builtin_prefetch` under `__has_builtin` and unless
`SNMALLOC_NO_AAL_BUILTINS`, and keeps the assembly for a compiler without
it. Clang has the ACLE hint as a builtin on Arm and AArch64,
`__builtin_arm_yield` (with `__yield` from `<arm_acle.h>`), which lowers to
`llvm.aarch64.hint(1)` (`clang/lib/CodeGen/TargetBuiltins/ARM.cpp:4460`
in the LLVM this repository pins): the same instruction, which the
optimizer then sees as an intrinsic rather than an opaque asm string.

This repository's rule is that runtime code reaches the processor through
intrinsics only, with no inline assembly, so that a new target is a new
entry and not a port of assembly strings. snmalloc is the only code on the
runtime's path that breaks it: `pause()` runs in every snmalloc spin loop
the runtime meets, on arm64 macOS. (`AAL_arm::tick()`'s `mrs cntvct_el0`,
`:76-87`, is never instantiated: the ticker reads `PAL::time_in_ms`, and
nothing calls `Pal::tick`.)

## Reproduce

    printf '#include <snmalloc/aal/aal.h>\nvoid spin() { snmalloc::Aal::pause(); }\n' > t.cpp
    clang++ --target=arm64-apple-macosx14.0 -std=c++20 -O2 -fno-exceptions \
        -fno-rtti -DSNMALLOC_USE_SELF_VENDORED_STL \
        -I third_party/snmalloc/src -emit-llvm -S -o - t.cpp | grep yield

At the pin the IR holds `call void asm sideeffect "yield"`; with
`pull-request.diff` applied to a copy of `src/`, `llvm.aarch64.hint` and no
asm (host Apple clang 21, 2026-10-15). Both assemble to `yield`.

## Expected

`pause()` uses the compiler's intrinsic where the compiler has it, as
`prefetch()` does, and inline assembly only for a compiler without it.

## Cause

`pause()` predates the builtin-first pattern the file later took for
`prefetch()`.

## The fix

`pull-request.diff`, against snmalloc's main (it applies to the pin with
`git apply --check`): one `#elif __has_builtin(__builtin_arm_yield) &&
!defined(SNMALLOC_NO_AAL_BUILTINS)` branch before the assembly, which calls
`__builtin_arm_yield()`. MSVC keeps `__yield()`, and a compiler without the
builtin (GCC has none by that name) keeps the assembly, so no build changes
behaviour; `SNMALLOC_NO_AAL_BUILTINS` turns it off as it does for prefetch.

## Why there is no patch

snmalloc is no patch project of `tools/patches.sh`: the build compiles
third_party/snmalloc as its submodule pins it, and adding a project to the
bootstrap cannot be verified on the machine this was written on. Until
upstream takes the change and the pin moves past it, the inline assembly
stays in the runtime, recorded as a deviation (PINS.md
`snmalloc-arm-yield-asm`).

## Upstreaming plan

Status: not filed. Bjorn files it, if he chooses to, as a contribution he
has reviewed and answers for: snmalloc is a Microsoft project whose README
asks every contributor to sign the Microsoft CLA, which its bot checks on
the pull request.

- One pull request against microsoft/snmalloc main, "Use
  __builtin_arm_yield in the Arm AAL's pause where available", from
  `pull-request.diff`. The body says it mirrors `prefetch()`, emits the
  same instruction, and changes nothing for MSVC or for a compiler without
  the builtin. snmalloc's CI builds arm64 Linux and macOS with clang and
  GCC, which covers both branches; no new test, since the instruction is
  unchanged.
- When a snmalloc release with the change is pinned, the PINS.md entry and
  this directory go.
