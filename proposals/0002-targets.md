<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0002: four targets on the system's C library

**Status:** the cutover landed in 102183f4 (2026-10-18) and has been
built and run on arm64 macOS since (`make check` 34/34 at c4d38e9b). No
Linux target has built anything. What remains is the three Linux
builds and the facts written from memory that each must confirm. The
code is the specification of what landed: the target entries in
`CMakeLists.txt`, the bootstrap's target section, AGENTS.md's targets and
linking rules. Deleted when all three Linux targets are green; it is the
first Linux work, and 0001's S5 and G1's Linux legs (0006) run after it.

## Where the Linux targets run (*decision*)

- **x86_64 Linux:** a native x86_64 machine, since no cross run or
  emulation counts as green.
- **arm64 Linux, 4 KiB and 16 KiB:** two Fedora VMs on the arm64 Mac, one
  on Fedora's `kernel` (4 KiB pages) and one on `kernel-16k` (*recalled*:
  the package name). A VM on Apple Silicon runs arm64 code natively, so it
  counts; the 16 KiB VM is also the one place that runs
  `cortex-a76` code on an Apple CPU.

Each host needs glibc's development files and the kernel's headers
(Fedora: `glibc-devel`, `kernel-headers`), and no GMP of its own.

## What remains

1. **The three Linux builds,** in this order: x86_64 Linux, arm64 Linux at
   4 KiB, arm64 Linux at 16 KiB. On each, from a fresh clone of main:
   `make bootstrap` from the start, `make build`, `make check`,
   `make test`, `make test-idr`, `make test-unit`, `make test-mlir-tools`.
   - **Acceptance:** the bootstrap completes and refuses no executable;
     `tests/static-linking` passes; every suite's result matches arm64
     macOS's at the same commit, test for test, and each difference is a
     bug recorded in `audits/bugs.md` under the target lane, fixed in the
     tree or, when it reproduces with upstream's tools alone, as a patch
     under `upstream/`.
   - **Waits on:** the machines; nothing in the tree.
2. **What was written from memory** (*recalled*), each confirmed or
   corrected in the code that states it, on the first build that reaches
   it, with where the answer came from:
   - **arm64 Linux's user address bits**, 39 at 4 KiB (Raspberry Pi's
     kernels) and 47 at 16 KiB, in the two entries of `CMakeLists.txt`:
     read `CONFIG_ARM64_VA_BITS` from each VM's kernel configuration and
     write the number and its source in the entry. Whether the entry
     should hold a minimum or a maximum is a separate finding with its
     own home, "Each fact once"'s target section.
   - **compiler-rt's Linux start of the AArch64 features,**
     `__init_cpu_features` (`runtime/Platform/Aarch64/Cpu.cpp`):
     `tests/runtime-start`'s processor cases pass on both arm64 VMs.
   - **The clang driver finds glibc's start files with no GCC installed,**
     under `--rtlib=compiler-rt` (`tools/bootstrap.sh`): the bootstrap's
     clang links a program on a host with no GCC.
   - **glibc's libraries as the executable check names them**
     (`libc.so.6`, `libm.so.6`, the loader; glibc 2.34 and later satisfy
     `-lpthread`, `-ldl` and `-lrt` with empty archives, so no other
     appears): `tests/static-linking` passes with no other library named.
   - **`cortex-a76`'s features on every Apple CPU,** the 16 KiB entry's
     baseline: the runtime's start check passes in the 16 KiB VM on the
     M2 Max.
   - **The runtime's reservations under Linux's default overcommit:** the
     64 GiB stack (`runtime/Start/Runner.cpp`) and the 4 GiB-aligned heap
     region (`runtime/Alloc/Cells.cpp`) are mapped with `MAP_NORESERVE`,
     which the default heuristic mode does not count: the suites'
     programs start on every Linux host.
