<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [simdutf] AVX512VPOPCNTDQ shares AVX512CD's instruction_set bit, so the icelake kernel can be chosen without VPOPCNTDQ

At simdutf v9.3.0 (bb77e7bb, the pin of third_party/simdutf) and on its
master branch (read 2026-10-15), `simdutf::internal::instruction_set` gives
two x86-64 features the same bit
(`include/simdutf/internal/isadetection.h`):

- `AVX512CD = 0x2000` (`:113`)
- `AVX512VPOPCNTDQ = 0x2000` (`:117`)

The x86-64 `detect_supported_architectures` sets that bit for either
feature: for CPUID leaf 7 EBX bit 28, AVX512CD (`:353-354`), and for ECX bit
14, AVX512VPOPCNTDQ (`:365-366`). So a mask that has the bit says nothing
about VPOPCNTDQ.

The icelake implementation requires `AVX512VPOPCNTDQ` among its instruction
sets (`src/simdutf/icelake/implementation.h:15-26`), and `detect_best_supported`
compares that requirement with the detected mask
(`src/implementation.cpp:1521-1534`). Its kernels are compiled in a target
region that includes `avx512vpopcntdq` (`src/simdutf/icelake.h:54-57`), and
`count_utf8` executes `_mm512_popcnt_epi64`, a VPOPCNTDQ instruction
(`src/icelake/implementation.cpp:1747`). On a processor that has AVX2, BMI1,
BMI2 and AVX-512 BW, CD, VL and VBMI2 but not VPOPCNTDQ, simdutf chooses
icelake, and the first count of a long enough string ends with an illegal
instruction.

No shipping processor is known to have VBMI2 without VPOPCNTDQ (Ice Lake and
later Intel cores, and AMD Zen 4 and later, have both), so the bug is latent
on hardware. A hypervisor can mask CPUID bits one by one, and a guest that
is shown AVX-512 without VPOPCNTDQ meets it.

`RVV = 0x4000` and `ZVBB = 0x8000` also reuse `AVX512BW`'s and `AVX512VL`'s
bits. That is harmless: each architecture's detection sets only its own
features, and a mask is never compared across architectures. The fix leaves
them alone.

## Reproduce

`distinct-bits.cpp`, a check the compiler runs: every x86-64 instruction set
is one bit of its own, and VPOPCNTDQ's is not CD's.

    c++ -std=c++17 -fsyntax-only -I third_party/simdutf/include \
        upstream/48-simdutf-avx512vpopcntdq-bit/distinct-bits.cpp

At the pin both static assertions fail; with `pull-request.diff` applied to
a copy of `include/`, both hold (host Apple clang 21, 2026-10-15).

## Expected

Each feature the detection reports has a bit of its own, so a kernel's
required set is tested feature by feature, and icelake is chosen only on a
processor with VPOPCNTDQ.

## Cause

`AVX512VPOPCNTDQ` was added after `AVX512VBMI2 = 0x10000` with a value that
was already taken, and nothing checks that the values are distinct.

## The fix

`pull-request.diff`, against simdutf's master (it applies to the pin with
`git apply --check`): `AVX512VPOPCNTDQ = 0x20000`, the free bit after
`AVX512VBMI2`. No other code names the value: the detection and the
icelake requirement both use the enumerator.

## Why there is no patch

Nothing in this repository reaches the bug. The runtime never asks
simdutf's detection to pick a kernel: it is built with the one
implementation its target's entry names, held as a constant of that
implementation's own class and called directly (`runtime/Strings/Simd.h`,
PINS.md `simdutf-constexpr-implementation`), and the startup check
refuses a machine without the features that implementation's kernels
use. `detect_best_supported`, `supported_by_runtime_system` and the free
functions that dispatch through `get_active_implementation` are never
called. simdutf is a patch project of `tools/patches.sh` since
`upstream/98-simdutf-constexpr-implementation`, but this diff stays a
submission, since nothing reaches the bug.

## Upstreaming plan

Status: not filed. simdutf's `AI_USAGE_POLICY.md` requires a human in the
loop who has read and reviewed the change and can answer for it in review,
and encourages disclosing tool assistance: Bjorn files it, in his own
words, if he chooses to.

- One issue, with simdutf's bug template: the two enumerators, the code
  path above, the processor feature combination that meets it, and
  `distinct-bits.cpp` as the steps to reproduce.
- One pull request, "Give AVX512VPOPCNTDQ an instruction_set bit of its
  own", from `pull-request.diff`, referencing the issue. CONTRIBUTING.md
  asks that every change be tested with `ctest --test-dir build`; that is
  not run here. If the maintainers want a guard, the pull request adds
  `distinct-bits.cpp`'s first assertion to `isadetection.h` itself, after
  the enum.
- When a simdutf release with the fix is pinned, this directory goes; until
  then it stays as the submission, whether or not it is sent.
