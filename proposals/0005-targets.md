<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0005: four targets on the system's C library

**Status:** landed 2026-10-18 as one cutover, unbuilt: nothing of it has
been compiled or run. The owner's builds qualify it, and it is deleted
when every target is green. It is the first Linux work: 0003's S5 and
G1's Linux legs (0007) run after it.

## Decisions

The owner's (*decision*, 2026-10-18):

- **Four first-class targets:** arm64 macOS; arm64 Linux with 16 KiB
  pages; arm64 Linux with 4 KiB pages, the kernel's default; x86_64
  Linux. Linux stays first-class: a change is done when it builds and
  passes on all four.
- **One linking rule:** every target links the operating system's own C
  library dynamically and nothing else shared, libSystem on macOS and
  glibc on Linux; everything of ours stays static. musl is gone.
- **The system's glibc, whichever the build machine has**, as the macOS
  SDK is: no pin and no check of its version. The libc step records it,
  so that another makes the steps built against it stale, and a program
  runs where the glibc is as new or newer, as a macOS program runs on its
  deployment target or newer.
- **The Raspberry Pi Zero 2 W, 3 and 4 are supported**, on their 64-bit
  kernels: the 4 KiB arm64 Linux target compiles programs for `armv8-a`
  (LLVM's `generic`).

Taken as the default, for the owner's review: the 16 KiB arm64 Linux
target compiles programs for `cortex-a76`, the Raspberry Pi 5's core
(ARMv8.2-A with crypto, dot product, RCpc, fp16 and SSBS), whose features
every Apple CPU has.

## What landed

- `tools/bootstrap.sh`: the Linux x86_64 and aarch64 hosts; the libc step
  records the system's C library and builds none; one clang configuration
  on every target; GMP in the sysroot serves Idris's support library
  everywhere; one executable check (`glibc_pie` on ELF, the dylib check on
  Mach-O); the page size in both toolchain files.
- `CMakeLists.txt`: the platform gate's three hosts; one Linux block and
  an entry per triple and page size; GMP's archive by path on every
  target; `_FORTIFY_SOURCE` (Release) and, on arm64 Linux,
  `-mbranch-protection=standard` for our tools, which glibc and Linux make
  live.
- `runtime/Platform/Aarch64/Cpu.cpp`: compiler-rt's Linux start of the
  processor's features.
- Deleted: `third_party/musl`, its lock entry, its licence row, its
  check in `tools/verify-pins.sh`, every musl branch of the bootstrap,
  `sysroot_is_host`, and the PINS entries `musl-thread-stacks` and
  `linux-uapi-from-host`, with the musl halves of three more.
- AGENTS.md, README.md, PINS.md, `bench/`, the tests that named musl, and
  `tests/toolchain/static-linking`, whose expected file is owed
  acceptance.

## What remains

1. **The owner's builds.** On each target, `make bootstrap` from the
   start, `make build` and every suite AGENTS.md names. arm64 macOS
   first, since the bootstrap's shared code changed under it too; then
   x86_64 Linux; then arm64 Linux on a 4 KiB and on a 16 KiB kernel.
2. **What was written from memory**, each where the code says it, to
   confirm or correct on the first build that reaches it (*recalled*):
   - the user address bits of arm64 Linux: 39 at 4 KiB, Raspberry Pi's
     kernels' setting, and 47 at 16 KiB, the fewer of three and four
     levels of tables. Read `CONFIG_ARM64_VA_BITS` from each machine's
     kernel and write the number in its entry with where it came from;
   - compiler-rt's Linux start of the AArch64 features,
     `__init_cpu_features`;
   - the clang driver finding glibc's start files with no GCC installed,
     under `--rtlib=compiler-rt`;
   - glibc's libraries as the executable check names them (`libc.so.6`,
     `libm.so.6`, the loader): glibc 2.34 and later satisfy LLVM's
     `-lpthread`, `-ldl` and `-lrt` with empty archives, so no other
     appears;
   - `cortex-a76`'s features on every Apple CPU, for Linux on Apple
     Silicon at 16 KiB.
3. **`upstream/08-execution-engine-process-symbols`**: its bug shows in
   statically linked programs. If no target reaches it now, the patch
   goes and its report stays as a submission.

## Questions for the owner

1. **Where the Linux targets run.** Default: Fedora 44 VMs on the arm64
   Mac for both arm64 Linux targets, one on Fedora's `kernel` (4 KiB) and
   one on `kernel-16k`, and a native x86_64 machine for x86_64 Linux,
   since emulation does not count as green (0007 §5).
