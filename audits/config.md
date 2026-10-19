<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# The build configuration: every knob, who reads it, its verdict

The owner, 2026-10-19: "there was config hell. clean it all up." The rules:
one place per fact; no opt-in knob and no fallback; a deliberate test seam
stays, with why. One line per knob: where it is set, who reads it, and the
verdict: **deleted**, or **kept** with the one reason the problem has it.

## The target (CMakeLists.txt's entries)

- `IDRIS_MLIR_TARGET_CPU` (an LLVM CPU name, and a cached override of it):
  idr-target, `--print-target-cpu`, bench. **Deleted**: the program's CPU is
  `IDRIS_MLIR_PROGRAM_CPU`, and no configure names another CPU than its
  entry's.
- `IDRIS_MLIR_RUNTIME_BASELINE`: the runtime's compile. **Deleted**, as
  `IDRIS_MLIR_BASELINE_CPU`.
- `IDRIS_MLIR_PROGRAM_CPU`, `IDRIS_MLIR_BASELINE_CPU` (the pinned clang's
  flags for each CPU): the CPU derivation, the runtime's profile,
  `--print-cpu-flags`. **Kept**: the entry's facts, the one place a CPU is
  named.
- `IDRIS_MLIR_*_CPU_NAME`, `IDRIS_MLIR_*_CPU_FEATURES`: derived once at the
  configure from the flags, by the compiler that compiles the runtime;
  `idr/TargetEntry.h` carries them to idr-target, the machine, the driver
  and idr.os. **Kept**: a derivation, not a knob.
- getEnabledProcessorFeatures in idr-target (LLVM's MC table as a second
  description of the CPU): **deleted**.
- `IDRIS_MLIR_TARGET_TRIPLE` compile definition (IdrIR, IdrTarget,
  IdrDriver, three copies): **deleted**; the triple is `TargetEntry.h`'s.
- The idris-rt-cpu / idris-rt-features marks, `retarget`, `nativeRuns`
  (the runtime's own second description, and a runtime prepared for
  another CPU): **deleted**; runtime functions take the program's CPU.
- `IDRIS_MLIR_PAGE_SIZE` (the toolchain file, from the bootstrap's
  machine fact): the entry's selection, snmalloc, the runtime. **Kept**:
  the page size is the machine's, which only the bootstrap reads.
- Every other entry fact (`IDRIS_MLIR_RUNTIME_CPU_TEST` ...
  `IDRIS_MLIR_TOOL_RELEASE_LINK_FLAGS`): **kept**, each a fact of the
  target the comment above the entries lists, read where the build needs
  it.

## CMake cache and options

- `IDRIS_MLIR_TYPECHECK` (option, set FORCE by the typecheck toolchain
  file): the root, runtime/, foreign/idr. **Kept**: the typecheck build has
  a toolchain that cannot link (the host's clang, a TableGen-only LLVM); the
  file that names that toolchain sets it, no user does.
- `IDRIS_MLIR_PRESET_COMPILE_FLAGS`, `IDRIS_MLIR_PRESET_LINK_FLAGS` (the
  hardened preset's): the language profile. **Deleted** with the preset.
- `IDRIS_MLIR_IDRIS_PREFIX` (cache PATH): set by the presets' base and
  again by `make build` (`-D`, from tools/toolchain.sh's `checkout_prefix`).
  **Kept once**: the Makefile's, from toolchain.sh; the presets' copy is
  deleted.
- `IDRIS_MLIR_CCACHE` (find_program, optional): the compiler launcher.
  **Required** now: the bootstrap configures the cache every checkout
  shares, and a build without it was a second, slower behaviour.
- `IDRIS_MLIR_TYPECHECK_GMP_HEADER` (find_file, the sysroot's or else the
  host's): the typecheck build's runtime compile. **Deleted**: the header is
  the sysroot's, which `tools/bootstrap.sh gmp` builds; no host fallback.
- `CMAKE_MAKE_PROGRAM` found on PATH when the preset gave none: **deleted**
  (the fallback); the preset names the pinned ninja, and the gate checks
  its series.
- `MLIR_DIR`, `LLVM_DIR`, the compilers, their target and the binutils (the
  toolchain files): **kept**, where the toolchain is, written once by the
  bootstrap.
- `CMAKE_EXPORT_COMPILE_COMMANDS` (the presets' base): **kept**: clang-tidy
  and editors read the compile commands.
- `SNMALLOC_*` (runtime/CMakeLists.txt, FORCE): **kept**, fixed values
  snmalloc's own build reads, no knob of ours.

## Presets (CMakePresets.json)

- `dev`: **kept**, the build every command and test reads (Debug: the
  assertions are on).
- `release`: **kept**: the optimized compiler (full LTO), whose compile
  times are worth recording (tools/profile.sh); Debug's are not.
- `hardened`: **deleted**, an opt-in variant no test or command built. A
  sanitizer is a universal oracle, and its place is the build the tests
  run, not a preset nobody runs: putting UBSan's traps into `dev` is its
  own change (every test then runs under it), recorded here.
- `lint`: **kept**: clang-tidy is an analysis of every unit, run as a
  check is, and its preset is the one place its flags live.
- `typecheck`: **kept**: another toolchain (see `IDRIS_MLIR_TYPECHECK`).

## The Makefile's variables

- `PRESET`: **kept**, it selects `release` or `lint`.
- `NCPU` (`IDRIS_MLIR_NCPU`): **kept**, the one CPU budget; lanes that share
  a machine set it.
- `threads`: **deleted**: the runner's threads are the CPU budget, and each
  compilation a test makes then takes one thread; a second count of the
  same budget only let the two disagree.
- `only`, `except`, `SRC`, `OUT`, `ARGS`: **kept**, the arguments of a
  command (which tests, which program, which benchmarks).
- `IDRIS_PREFIX`, `IDRIS2`, `CMAKE`, `DEV_PRESET`, `COMPILER`,
  `CHECKOUT_PREFIX`, `HOST_PREFIX`, `TIMEOUT`: **kept**, each read from
  tools/toolchain.sh, the one place where the tools are.
- Exports `IDRIS2_PREFIX`, `PATH`, `IDRIS_MLIR_ROOT`,
  `IDRIS_MLIR_HOST_NAMES`, `CHEZ`: **kept**, each the value above handed to
  what the Makefile runs.

## Environment a tool reads

- `IDRIS_MLIR_TOOLCHAIN` (tools/toolchain.sh, bootstrap): **kept**, a test
  seam: the spec tests plant toolchains.
- `IDRIS_MLIR_IDRIS_SOURCE` (verify-pins, doctor, upstream-patches):
  **kept**, a test seam: doctor-without-idris-source plants a source.
- `IDRIS_MLIR_NCPU`: **kept** (above).
- `IDRIS_MLIR_ROOT`, `IDRIS_MLIR_HOST_NAMES` (the harness): **kept**, set
  by the Makefile.
- `IDRIS_MLIR_TEST_DEADLINE` (harness/testutils.sh): **kept**, the harness's
  own marker that a test runs under its deadline already.
- `IDRIS_MLIR_FUZZ_SEED`, `IDRIS_MLIR_DETERMINISM_SEED`,
  `IDRIS_MLIR_ACTIONS_SEED`: **kept**, replay seams: a failure prints the
  seed that reproduces it.
- `IDRIS_MLIR` (tools/profile.sh): **kept**, a seam: the compiler under
  measurement, a release build's for timings worth comparing.
- `IDRIS_RT_LIVE` (every program): **kept**, the live-cell protocol the
  tests read.

## The host's tools (tools/host.sh)

- `sha256`: coreutils', or else perl's `shasum`, or else macOS's own
  `sha256sum`. **One tool**: coreutils' (`sha256sum`, MacPorts'
  `gsha256sum` on macOS), which the host already provides for `timeout`.
- The nanosecond clock: GNU date's `%N`, or else perl's Time::HiRes.
  **One tool**: coreutils' date (`gdate` on macOS).
- `host_names` for an architecture or system outside the platform gate:
  **kept** as written, unreachable: the gate refuses such a machine first.

## The bootstrap (tools/bootstrap.sh)

- ccache "optional": **required**, as the CMake build requires it.
