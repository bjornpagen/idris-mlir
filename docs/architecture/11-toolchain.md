# 11. Toolchain, C++ discipline, and layout

The toolchain is LLVM on musl, built from source in two stages
([plan](../plan.md), section 5.2): the host's C++ compiler builds a stage-1
`clang` and `lld`; stage 1 builds musl, the LLVM runtimes and the stage-2
LLVM/MLIR, `clang`, `lld` and `clang-tidy`, static on musl and libc++, with
LTO; stage 2 builds GMP, our C++ tools, the runtime and every program. GCC is
gone.

## Pins

- **TC-PIN-1 (p0).** Every external tool and library the build uses is
  pinned:
  - Idris 2, by the `third_party/Idris2` gitlink;
  - musl, GMP, simdutf, fast_float, snmalloc and, since the cutover, Ryu,
    by the gitlinks of their submodules under `third_party/`, which `toolchain.lock.json` records
    too, with their repository, tag or `git describe`, and version;
  - LLVM/MLIR, CMake and Ninja, in `toolchain.lock.json` (schema 4), each
    with the exact version, the source URL, the commit and the tag.

  No other file states a version number. The CMake configure gate,
  `tools/bootstrap.sh` and `tools/verify-pins.sh` read the lock file. This is
  cpp-starter's rule that versions live in one place, with the lock file as
  that place (`TC-DEV-2`). musl and GMP come from GitHub mirrors; the lock
  also records their official release tarballs' SHA-256 (`PINS.md`:
  `mirrored-sources`).
  - Test: `tests/spec/lock`, `tests/spec/idris-pin`
- **TC-PIN-2 (p0).** Everything is built from source into `.toolchain/`. A
  step's `provenance.json` stamp is written only after every part of the
  step, its checks included, succeeded; it records the digest of the step's
  inputs, and commands refuse stale or missing stamps. Nothing is installed
  globally, and no shell configuration is changed.
  - Test: `tests/spec/stale-stamps`, `tests/spec/failed-bootstrap`
- **TC-PIN-3 (p0).** Host packages are used only as prerequisites for
  building the pinned tools, never as the tools themselves: a C and C++
  compiler (for CMake, Ninja, stage 1 and Idris's C support library), make,
  git, python3 (LLVM's configure), m4 (GMP), Chez Scheme (Idris), and the
  Linux UAPI headers, which the musl step copies into the sysroot and records
  (`PINS.md`: `linux-uapi-from-host`, `idris-support-host-cc`).
  - Check: review (tools/bootstrap.sh)
- **TC-PIN-4 (v3). Upstream bugs.** A workaround in this repository for a
  bug of a pinned upstream (LLVM, MLIR, Idris) comes, in the same change,
  with:
  - the bug reduced to upstream dialects and tools, in its own directory
    under `upstream/`: a report written to be filed as it is, and its
    reproducer (`upstream/README.md`);
  - a `PINS.md` entry of the same name;
  - a test `tests/upstream/<name>/run` (`make test-mlir-tools`) that
    checks that the bug still reproduces with the pinned tools, so a
    toolchain bump that fixes it fails the test; then the workaround, the
    entry, the directory and the test are deleted in one change.

  If the reduced input does not reproduce upstream, the bug is ours, and
  is fixed instead.
  - Test: `tests/upstream/*`

- **TC-LIB-1 (v1 only; withdrawn in v3).** `idris-mlir-io` was a package
  installed into `.toolchain/`; programs use the Prelude now.

## Bootstrap (`tools/bootstrap.sh`)

- **TC-BOOT-1 (p0).** `tools/bootstrap.sh STEP...` builds the toolchain, with
  the steps `cmake`, `ninja`, `stage1`, `musl`, `runtimes`, `stage2`, `gmp`
  and `idris`, `llvm` (stage1 to stage2) and `all`; `make bootstrap` runs
  `all`, and `make doctor` reports what is built.
  - Test: `tests/spec/commands`, `tests/spec/doctor-without-idris-source`
- **TC-BOOT-2 (p0).** Stage 2 installs a complete tree into
  `.toolchain/llvm-musl`:
  - **Libraries** and the CMake packages for LLVM and MLIR.
  - **Tools:** `clang`, `lld`, `clang-tidy`, `mlir-tblgen`, `mlir-opt`,
    `mlir-translate`, `opt`, `llc`, `llvm-ar`, `llvm-nm`, `llvm-readelf`,
    `llvm-objdump`, `llvm-symbolizer`, `FileCheck`, `not` and `count`.
  - **Configuration:** projects `clang;lld;mlir;clang-tools-extra`; target
    X86; assertions on; RTTI and exceptions off; static PIE on musl and
    libc++, with no shared library and no plugin; LTO (`PINS.md`:
    `stage2-thinlto`) with fat objects, whose bitcode serves the Release
    build and whose native code every other build.
  - Test: `tests/spec/llvm-bootstrap`
- **TC-BOOT-3 (p0).** The tests run without lit or Python: the dialect tests'
  RUN lines find the pinned LLVM's `FileCheck`, `not` and `count` first on
  `PATH` (`tests/testutils.sh`).
  - Test: `tests/spec/pinned-test-tools`
- **TC-BOOT-4 (p0).** The two stages, in order: the host's C++ compiler
  builds stage 1 (`clang`, `lld` and the binary tools the next steps use,
  for X86 only); stage 1 builds musl, then compiler-rt's builtins, libunwind,
  libc++abi and libc++ (`LIBCXX_HAS_MUSL_LIBC`) into the sysroot, then stage
  2; stage 2 builds GMP (static, position-independent, every x86-64 kernel
  chosen at run time). Each step deletes its build tree once its install and
  checks succeeded; stage 1 and stage 2 resume an interrupted build.
  - Check: review (tools/bootstrap.sh)
- **TC-BOOT-5 (p0).** The pinned clangs are configured in one place: the
  file `x86_64-unknown-linux-musl.cfg` next to each, which names the sysroot,
  compiler-rt, libunwind, libc++, `lld` and static-PIE output. Both default
  to that target. Nothing else configures them.
  - Check: review (tools/bootstrap.sh, `config_file`)
- **TC-BOOT-6 (p0).** Resources: parallel jobs are the cores, at most one per
  5 GiB of memory, and one link at a time; the steps check free disk first.
  The stamps of stage 1 and stage 2 record the wall time, the peak memory in
  use, the build tree's size and the install's size (plan section 5.2: "states
  them").
  - Check: review (tools/bootstrap.sh)

## C++ discipline: cpp-starter, adopted fully

- **TC-CPP-1 (p0).** C++ in this repository follows bjornpagen/cpp-starter at
  revision `bdb6838`. Its `AGENTS.md` is copied verbatim to
  `docs/cpp-profile.md` and is normative for C++ here, except for the
  deviations below.
  - The repository adopts its `CMakeLists.txt` configure gate, its
    `CMakePresets.json` (`dev`, `release`, `asan-ubsan`, `lint`), its
    language-profile interface target, and its flags (C++26, modules, no
    exceptions, no RTTI, warnings as errors, hardening), with clang and
    libc++ in place of GCC and libstdc++ (`TC-DEV-6`).
  - It also adopts its `PINS.md` quirk registry, with the tombstone ritual on
    every toolchain bump.
  - Test: `tests/spec/cpp-starter`
- **TC-CPP-2 (p0).** CMake presets are the only interface for building C++.
  `make build` calls `cmake --preset` and `cmake --build --preset`; it never
  invokes Ninja or the compiler directly.
  - Test: `tests/spec/build-preset`

### Zones

- **TC-ZONE-1 (p0).** All MLIR-facing C++ lives in `foreign/idr/`: TableGen
  `.td` files, generated `.inc` files, headers, dialect and pass sources,
  and the tools (`idris-mlir-opt`, `idris-mlir-cc`, and since the cutover
  `idris-mlir-reduce`).
  - *Rationale:* MLIR's C++ API requires inheritance (`Dialect`, `Pass`,
    `OpRewritePattern`), CRTP (`Op<…>`), headers, and preprocessor-generated
    code. Under cpp-starter's rules that is quarantine code, "unavoidable
    foreign ABI adaptation". This is recorded as a `PINS.md` entry
    (`mlir-cxx-api`), not hidden.
  - LLVM and MLIR headers are included as system headers, so the project's
    warnings apply to our code, not to theirs.
  - Test: `tests/spec/zones`
- **TC-ZONE-2 (p0).** cpp-starter's `src/` (dialect code: named modules,
  no headers, no preprocessor) and `unsafe/` exist only once they hold code:
  C++ that touches neither the MLIR API nor a vendored C++ library goes to
  `src/`, which is then created with its `CMakeLists.txt` (`PINS.md`:
  `zones-on-demand`).
  - Test: `tests/spec/zones`
- **TC-ZONE-3 (p0).** `runtime/` holds the runtime (`TC-RT-1`): quarantine
  code, because it adapts vendored header libraries and exports a C ABI
  (`PINS.md`: `runtime-quarantine`). Its sources are `.cc`, its header
  `idris_rt.h`, its link check C.
  - Test: `tests/spec/zones` (C++ under `runtime/` and nowhere else outside
    `foreign/idr/`)

### Deviations from cpp-starter

Each deviation below has a `PINS.md` entry.

- **TC-DEV-1 (p0). Platform gate.** The gate also accepts Linux x86_64, as
  the user decided. Linux x86_64 is the only tested platform. The arm64
  platforms cpp-starter accepts stay accepted but untested.
- **TC-DEV-2 (p0). Version source.** The gate reads the accepted versions
  from `toolchain.lock.json` instead of containing them.
  - Test: `tests/spec/configure-gate`, `tests/spec/lock`
- **TC-DEV-3 (p0). Lint compiler.** The lint graph uses the `clang-tidy`
  built by stage 2, not cpp-starter's separately pinned Clang. The project
  then has one LLVM, not two.
- **TC-DEV-4 (p0). No stdexec.** cpp-starter's stdexec dependency and wait
  backend are not adopted, because nothing here uses them.
- **TC-DEV-5 (p0). C++17 headers.** LLVM's headers are C++17 and are compiled
  in C++26 mode. Any incompatibility found gets a `PINS.md` entry and the
  narrowest possible workaround.
  - Test: `tests/spec/deviations`
- **TC-DEV-6 (p0). clang and libc++.** The compiler is the stage-2 clang
  with libc++, for `x86_64-unknown-linux-musl`, and the gate refuses any
  other; without `-freflection`, which the pinned clang only stubs
  (`PINS.md`: `clang-libcxx`, `clang-no-reflection`).
  - Check: review (CMakeLists.txt, CMakePresets.json)
- **TC-DEV-7 (p0). No sanitizer runtimes.** The `asan-ubsan` preset fails at
  configure time: the static musl toolchain has no sanitizer runtimes. Every
  build keeps trap-mode UBSan (`PINS.md`: `no-sanitizer-runtimes`).
  - Check: review (CMakeLists.txt)
- **TC-DEV-8 (p0). LTO.** The Release build compiles our code with
  `-flto=full` and links it with the bitcode of LLVM's and MLIR's fat
  objects (`--fat-lto-objects`); other builds link their native code.
  Executables are static PIE (`TC-LINK-2`) with an 8 MiB main-thread stack
  (`PINS.md`: `musl-thread-stacks`, `stage2-thinlto`).
  - Check: review (CMakeLists.txt)

## The runtime and the link

- **TC-RT-1 (p0).** The runtime (`runtime/`, plan section 5.4) is C++ with
  no exceptions, no RTTI, no static constructors and no C++ library at link
  time. It is one archive of fat LTO objects, `libidris_rt.a`, compiled with
  `-O3` for the x86-64 baseline and without FP contraction; the vendored
  snmalloc, simdutf and fast_float are compiled into it.
  - *planned* (m3): `tests/toolchain/runtime-link`, `tests/toolchain/runtime-api`
- **TC-RT-2 (p0).** The build fails if the runtime references a symbol of
  the C++ runtime (mangled names, the C++ ABI, the unwinder, even weakly) or
  has a static constructor: every member is linked into one static-PIE
  executable with no C++ library and no unwinder, and `check-archive.sh`
  checks the archive's symbols and sections.
  - *planned* (m3): `tests/toolchain/runtime-link`
- **TC-RT-3 (p0).** Allocation: `idris_rt_alloc_N`/`idris_rt_free_N` for
  each size class N of `IDRIS_RT_SIZE_CLASSES`, over snmalloc with
  `SNMALLOC_MIN_ALLOC_STEP_SIZE=8`; each N is a size class of that
  configuration. GMP allocates through the same allocator
  (`idris_rt_gmp_init`), and exhausted memory ends the process with status 1.
  - *planned* (m3): `tests/toolchain/runtime-api`
- **TC-RT-4 (p0).** Strings and numbers: `idris_rt_utf8_valid`,
  `idris_rt_utf8_count` and `idris_rt_ascii` over simdutf's best
  implementation for the CPU (`PINS.md`: `simdutf-dispatch`);
  `idris_rt_parse_double` over fast_float with plan section 3's grammar.
  - *planned* (m3): `tests/toolchain/runtime-api`
- **TC-LINK-1 (p0).** A program is one LTO module: `idris-mlir-cc` links the
  program's LLVM IR with the runtime archive's bitcode (`--runtime`, by
  default the archive the build made), keeping only what the program reaches
  and refusing runtime constructors; raises runtime functions to the
  program's CPU; internalizes every symbol but `main`; runs LLVM's O3
  pipeline without FP contraction, and with `MergeFunctions` (*since the
  cutover*); and emits one object. `idris-mlir-cc` also links the runtime
  natively, so its folders and `idr-eval`'s JIT call the same functions
  (`LOW-RT-1`).
  - *planned* (m3): `tests/toolchain/driver`
- **TC-LINK-2 (p0).** Executables are static PIE for
  `x86_64-unknown-linux-musl`, linked by `lld` with `--gc-sections` and
  `--icf=all` against musl, GMP, compiler-rt and libunwind: an ELF of type
  DYN with no `INTERP` segment and no `DT_NEEDED` entry. (A static PIE keeps
  its dynamic section, which its start code reads to relocate itself.)
  musl's `libc.a` holds the `libm` functions of `LOW-EXT-1`.
  - *planned* (m3): `tests/toolchain/static-pie`

## Repository layout

- **TC-LAYOUT-1 (p0).**

  ```text
  CMakeLists.txt  CMakePresets.json  Makefile  PINS.md  toolchain.lock.json
  compiler/            Idris: frontend, middle end, emitter (idris-mlir)
  foreign/idr/         C++: idr dialect, passes, the JIT, idris-mlir-opt, -cc, -reduce
  runtime/             C++: the runtime, with a C interface (TC-ZONE-3, LOW-RT-1)
  tests/spec/          the spec's rules, the pins, the commands, the layout
  tests/toolchain/     the pinned toolchain and what it builds
  tests/compiler/      Idris-side unit tests and invalid-Core tests
  tests/profile/vN/    accept/ and reject/ fixtures per profile version
  tests/idr/           hand-written .mlir + FileCheck, per op/folder/pass
  tests/e2e/vN/        Idris source → executable, with oracles
  tests/mlir/          checks of the pinned upstream tools
  tools/bootstrap.sh   the toolchain; tools/*.sh the other commands' scripts
  docs/architecture/   this spec
  third_party/         Idris2, musl, gmp, simdutf, fast_float, snmalloc, ryu: pinned, unmodified
  ```
  - Test: `tests/spec/layout`
