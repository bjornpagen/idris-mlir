<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0005: four targets on the system's C library

**Status:** decided by the owner, 2026-10-18; nothing is built. It is the
first Linux work: 0003's S5 (`make self` on x86_64 Linux) and G1's Linux
build (0007) wait for it, so Linux runs once, on the platform it keeps.
arm64 macOS's S4 does not wait: this starts when S4 is done, so the
self-host runs on the bootstrap it started with.

Claims are marked *read* (the path given, in the 2026-10-18 tree),
*recalled* (to be checked), *decision* or *conjecture*.

## 1. The decisions

The owner's (*decision*, 2026-10-18):

- **Four first-class targets:** arm64 macOS; arm64 Linux with 16 KiB
  pages; arm64 Linux with 4 KiB pages, the kernel's default; and x86_64
  Linux. A change is done when it builds and passes on all four. Linux
  stays first-class.
- **One linking rule on every target:** a program and every tool link
  the operating system's own C library dynamically, and nothing else
  shared: libSystem on macOS, glibc on Linux. Everything of ours (the
  runtime, libc++, GMP, snmalloc, LLVM) stays static. musl goes.
- **glibc is pinned at 2.43, Fedora 44's.** Fedora 44 shipped on
  2026-04-28 with glibc 2.43; its stable package is 2.43-9.fc44
  (Fedora's package index, read 2026-10-18).

## 2. Why

Linux becomes what macOS already is: the system's C library, linked
dynamically, built against the host's headers, with everything of ours
static. The bootstrap's target section now forks once per C library,
`libc=musl` or `libc=sdk` (*read*: `tools/bootstrap.sh`), and every fork
below it collapses:

| Today: Linux / macOS | After |
|---|---|
| `libc=musl` / `libc=sdk` | the system's, on every target |
| `sysroot_is_host=no` / `yes`, and the Idris support library's case for it | gone: the sysroot's GMP is built against the host's C library everywhere |
| `config_file_musl` / `config_file_sdk` | one shape |
| the libc step builds musl and copies the host's kernel headers / records the SDK | it records the host's C library, on every target |
| libc++ with musl's flags | no musl flags |
| stage 2 static without PIC / dynamic with PIC | one setting |
| the executable check: a static PIE / only `/usr/lib` and `/System` | one rule, two readers (§4) |
| `CMakeLists.txt`: `-static-pie`, musl's thread-stack flag | gone |

What it adds besides deletions: Rust's `std` gets the program's
arguments from glibc as from libSystem, so 0021's one start item goes,
and Rust's glibc targets are its best-supported ones; glibc's `memcpy`
and string functions are chosen for the processor at run time;
`_FORTIFY_SOURCE` works on Linux; a sanitizer build becomes possible
there.

## 3. The target entries

| | arm64 macOS | arm64 Linux, 16 KiB | arm64 Linux, 4 KiB | x86_64 Linux |
|---|---|---|---|---|
| triple | `arm64-apple-macosx14.0` | `aarch64-unknown-linux-gnu` | `aarch64-unknown-linux-gnu` | `x86_64-unknown-linux-gnu` |
| page size | 16384 | 16384 | 4096 | 4096 |
| C library | libSystem, the host's SDK | glibc 2.43 | glibc 2.43 | glibc 2.43 |
| format, linker | Mach-O, `ld64.lld` | ELF, `ld.lld` | ELF, `ld.lld` | ELF, `ld.lld` |
| programs' CPU | `apple-m1` | `armv8.2-a` (*proposed*) | `armv8-a` (*decision*) | `x86-64-v3` |
| user address bits | 47 | read from the kernel at L2 | read from the kernel at L2 | 47 |
| runtime bitcode | beside the object | in the object | in the object | in the object |

- **An entry is a triple and a page size.** Both arm64 Linux entries
  have one triple; the page size the bootstrap reads from the machine
  (`getconf PAGESIZE`, as today) picks the entry. The toolchain file the
  bootstrap writes names it, and `CMakeLists.txt`'s entry for the triple
  admits the sizes it has, where it now writes the size itself. The
  runtime's start already refuses a page size that is not its entry's
  (*read*: `runtime/Start/Entry.cpp`, `checkPageSize`), so a 16 KiB build
  never runs on a 4 KiB kernel, and nothing runs on a 64 KiB one, which
  has no entry.
- **The programs' CPU on arm64 Linux** (*proposed*, §9). A 16 KiB Linux
  runs on Apple Silicon (Asahi Linux, Fedora's 16 KiB kernel in a VM on a
  Mac) and on the Raspberry Pi 5 family, whose Raspberry Pi OS kernel,
  `kernel_2712.img`, has 16 KiB pages by default (Raspberry Pi's
  documentation, read 2026-10-18). The Pi 5's Cortex-A76 is ARMv8.2-A, so
  the 16 KiB entry takes `armv8.2-a`, not `apple-m1`. A 4 KiB Linux runs
  on Graviton, Ampere, Snapdragon X, VMs on Macs, a Pi 5 booted with
  `kernel8.img`, and the older 64-bit Pis: the Zero 2 W and Pi 3
  (Cortex-A53) and the Pi 4 (Cortex-A72), which are ARMv8.0-A. They are
  supported (*decision*, the owner, 2026-10-18), on their 64-bit kernel
  (the Zero 2 W boots a 32-bit one unless told otherwise), so the 4 KiB
  target takes `armv8-a`; what a later processor adds, a program reaches
  through the CPU test, as on the other targets. The runtime already fits
  a 512 MiB board: its stack and its 4 GiB heap region are reservations
  Linux does not count against memory (`MAP_NORESERVE`), and a system
  that grants no heap region leaves the heap to grow without one (*read*:
  `runtime/Platform/Posix/Memory.cpp`, `runtime/Alloc/Cells.cpp`).
- **The CPU test on arm64 Linux.** Apple's compiler-rt reads the
  processor's features from sysctl when the test asks
  (`__init_cpu_features_resolver()`, *read*:
  `runtime/Platform/Aarch64/Cpu.cpp`); on Linux the resolver takes the
  kernel's hardware capabilities, `getauxval(AT_HWCAP)` (*recalled*).
  `Cpu.cpp` gains that form, inside the runtime's platform layer, where
  AGENTS.md puts an operating system's calls.
- **snmalloc on arm64 Linux** takes x86_64 Linux's definitions
  (`SNMALLOC_HAS_LINUX_RANDOM_H`, `SNMALLOC_HAS_LINUX_FUTEX_H`).
- **User address bits** on arm64 Linux depend on how the kernel was
  configured: 48 is usual with 4 KiB pages, and 47 or 48 with 16 KiB, and
  Raspberry Pi's own kernels may configure fewer (39, *recalled*). An
  entry's number is the smallest among the kernels it runs on, since the
  runtime places its stack and heap below it. L2 reads it from each
  machine's kernel and writes it in the entry, with where it came from,
  as the x86_64 and macOS entries do.

## 4. The C library

- **The libc step records the host's C library on every target**, and
  builds none: on macOS the SDK, as today; on Linux glibc's development
  files (its headers, start objects and `libc.so`'s link script) and the
  kernel's headers, from the host's packages (on Fedora, `glibc-devel`
  and `kernel-headers`). Its stamp names their versions, so a new one
  makes the steps built against it stale, as a new SDK does.
- **The pin.** `toolchain.lock.json`'s `musl` entry becomes
  `glibc: 2.43, Fedora 44`. The libc step reads the host's version
  (`getconf GNU_LIBC_VERSION`) and refuses any other: a newer glibc would
  raise every program's floor, and an older one is not the pin. So a
  Linux build host runs glibc 2.43 (Fedora 44, or any system on it), and
  a program runs on any Linux whose glibc is 2.43 or newer, as a macOS
  program runs on its deployment target or newer. Moving the pin is a pin
  move like any other (Fedora 45 has 2.44).
- **One clang configuration**, on every target: the system's C library;
  libc++, compiler-rt and lld beside the clang; GMP in the sysroot. No
  `-static-pie`, and no `--sysroot` pointing at a C library we built.
- **One linking rule, checked by one test.** An executable links only
  the system's C library: on ELF its interpreter and its needed
  libraries are glibc's (`libc.so.6`, `libm.so.6`, `ld-linux-*`); on
  Mach-O only `/usr/lib` and `/System/Library`, and never a libc++. Two
  readers (`llvm-readelf`, `llvm-objdump`), one rule, in
  `tools/bootstrap.sh`'s `check_executable` and
  `tests/toolchain/static-linking`.
- **Programs and tools** are PIE, bound at load (`-z relro -z now`, so no
  lazy binding) and called without the PLT (`-fno-plt`), with no
  executable stack.
- **libc++** is built static with its ABI library inside it on every
  target. The hermetic build stays macOS's alone: libSystem loads
  Apple's libc++ into every process, and glibc loads no C++ library.
- **GMP** is built from source and linked static, as today, against the
  host's C library on every target.

## 5. What is deleted

- `third_party/musl` (the submodule, its `.gitmodules` entry), the
  lock's `musl` entry and its check in `tools/verify-pins.sh`.
- In `tools/bootstrap.sh`: `libc_musl`, `config_file_musl`, `args_musl`,
  the musl branches of `recipe_libc` and of the runtimes' flags, the
  copy of the host's kernel headers and its `dpkg-query`, and
  `sysroot_is_host` with the support library's case for it.
- In `CMakeLists.txt`: the x86_64 Linux entry's `-static-pie` and
  `-z stack-size`.
- In `PINS.md`: `musl-thread-stacks` and `linux-uapi-from-host`; the
  musl half of `mirrored-sources`; the musl remarks in
  `no-sanitizer-runtimes` and `darwin-inert-mitigations`.
- The musl remarks in `runtime/check-archive.sh` (glibc defines
  `__cxa_atexit` and `__cxa_finalize` too), `runtime/Platform/Posix/Files.cpp`,
  `tools/toolchain.sh`, `bench/README.md`, `bench/run.sh`,
  `bench/c/regex-redux.c`, `README.md`, 0006's pin table and 0021.
- Tests: `tests/toolchain/runtime-prepared/linux/allowed` lists glibc's
  symbols; `tests/idr/lower/cpu-features-x86-64.mlir` takes the new
  triple.
- Possibly `upstream/08-execution-engine-process-symbols`: its bug shows
  in statically linked programs (*read*: its README). L1 checks whether
  any target still reaches it, and the patch goes if none does, its
  report kept as a submission.

## 6. What stays different

These are the machines, not choices:

- **Object format and linker:** ELF and `ld.lld`, Mach-O and `ld64.lld`;
  compiler-rt's files and flags; which reader the executable check uses.
- **CPU and page size:** x86-64 and arm64, 4 KiB and 16 KiB, and the
  processor test at a program's entry.
- **The oldest system a program runs on:** macOS's deployment target,
  Linux's glibc version.
- **The host's facts:** `sysctl` on macOS, `getconf` on Linux; Chez
  Scheme's machine type.
- **macOS's hermetic libc++** (§4).

## 7. The rules this keeps

- The target is decided in one place: the entry in `CMakeLists.txt`,
  and for the toolchain the bootstrap's target section. An operating
  system's calls stay behind the runtime's platform layer.
- Everything of ours is linked statically; nothing of ours is loaded at
  run time.
- Every dependency is pinned: glibc by its version, which the libc step
  checks, as the SDK is recorded by its own.
- Hard cutover: musl goes in L1, with nothing kept beside it.
- AGENTS.md's text changes in the stage that makes it true: L1 rewrites
  the linking rule and the x86_64 Linux entry, L2 the list of targets.
  Until L2, a change passes on the two targets that exist.

## 8. Plan

- **L1, x86_64 Linux on glibc** (after 0003's S4). Everything of §4 and
  §5, and AGENTS.md's linking rule. Exit: `make bootstrap`, `make build`
  and every suite AGENTS.md names green on x86_64 Linux (Fedora 44) and
  on arm64 macOS, since the bootstrap's shared code changes; the one
  linking rule holds on both; a program built there runs on glibc 2.43.
- **L2, arm64 Linux, both page sizes** (after L1). The bootstrap's
  `Linux:aarch64` host, the entry with its page size from the toolchain
  file, the CPU test's Linux form, snmalloc's definitions, the user
  address bits read from each kernel, and AGENTS.md's four targets.
  Exit: every suite green on all four targets, on Fedora 44 aarch64 with
  a 4 KiB kernel and with a 16 KiB one (Fedora ships both: `kernel` and
  `kernel-16k`, *recalled*).
- **Then** 0003's S5 runs on x86_64 Linux, and G1 (0007) qualifies all
  four targets.

## 9. Questions for the owner

1. **The programs' CPU on 16 KiB arm64 Linux.** Default: `armv8.2-a`,
   the Pi 5's (§3). The 4 KiB target's is decided: `armv8-a`, for the
   Pi Zero 2 W, Pi 3 and Pi 4.
2. **Where the Linux targets run.** Default: Fedora 44 VMs on the arm64
   Mac for both arm64 Linux targets, one per kernel, and a native
   x86_64 machine for x86_64 Linux, since emulation does not count as
   green (0007 §5).
3. **How glibc is pinned.** Default: the build host's glibc must be
   exactly 2.43 (§4). The alternative, if Linux builds must run on other
   hosts: a sysroot made of Fedora 44's own glibc packages, pinned by
   their hashes, on any host.
