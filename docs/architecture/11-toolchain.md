# 11. Toolchain, C++ discipline, and layout

## Pins

- **TC-PIN-1 (p0).** Every external tool the build uses is pinned:
  - Idris 2, by the `third_party/Idris2` gitlink;
  - LLVM/MLIR, GCC, CMake and Ninja, in `toolchain.lock.json`, which moves to
    schema 3. Each entry records the exact version, the source URL, and the
    commit or SHA-256.

  No other file states a version number. The CMake configure gate and
  `tools/dev.py` read the lock file. This is cpp-starter's rule that versions
  live in one place, with the lock file as that place (`TC-DEV-2`).
  - Check: `tests/tooling`, which checks that the gate and `dev.py` read
    their versions from the lock file
- **TC-PIN-2 (p0).** Everything is built from source into `.toolchain/`. A
  `provenance.json` stamp is written only after every step succeeds, and
  commands refuse stale or missing stamps. This is the existing mechanism,
  extended to the new tools. Nothing is installed globally, and no shell
  configuration is changed.
- **TC-PIN-3 (p0).** Distribution packages are used only as prerequisites for
  building the pinned tools, never as the tools themselves:
  - Chez Scheme and GMP, for Idris;
  - a host C/C++ compiler, to build the pinned GCC;
  - GCC's own prerequisites (GMP, MPFR, MPC), as its documentation requires.

- **TC-LIB-1 (v1).** `dev.py build` builds and installs the `idris-mlir-io`
  package with the pinned Idris into `.toolchain/`, where both `idris-mlir`
  and stock `idris2` find it with `-p idris-mlir-io`. It is built with stock
  Idris, and its TTC format matches, because `idris-mlir` is built from the
  same pinned Idris.

## Bootstrap (`tools/dev.py`)

- **TC-BOOT-1 (p0).** `dev.py` gains `bootstrap-gcc`, `bootstrap-cmake` and
  `bootstrap-ninja`, and `doctor` reports them.
- **TC-BOOT-2 (p0).** `bootstrap-llvm` builds the pinned LLVM with the pinned
  GCC, CMake and Ninja (D10), and installs a complete tree into
  `.toolchain/llvm`:
  - **Libraries** and the CMake packages for LLVM, MLIR and Clang.
  - **Tools:** `mlir-tblgen`, `mlir-opt`, `mlir-translate`, `opt`, `llc`,
    `llvm-nm`, `FileCheck`, `not`, `count`, `clang` and `clang-tidy`. The
    last two serve the lint graph (`TC-DEV-3`).
  - **Configuration:**
    - projects `mlir;clang;clang-tools-extra`;
    - targets `Native`;
    - assertions on;
    - RTTI and exceptions off (LLVM's defaults, matching cpp-starter);
    - `LLVM_INSTALL_UTILS=ON`.
  - The existing memory cap on parallel compile jobs stays.
- **TC-BOOT-3 (p0).** `lit` is used from the pinned source tree
  (`llvm/utils/lit`), not from PyPI.

## C++ discipline: cpp-starter, adopted fully

- **TC-CPP-1 (p0).** C++ in this repository follows bjornpagen/cpp-starter at
  revision `bdb6838`. Its `AGENTS.md` is copied verbatim to
  `docs/cpp-profile.md` and is normative for C++ here, except for the
  deviations below.
  - The repository adopts its `CMakeLists.txt` configure gate, its
    `CMakePresets.json` (`dev`, `release`, `asan-ubsan`, `lint`), its
    language-profile interface target, and its flags (C++26, reflection,
    modules, no exceptions, no RTTI, warnings as errors, hardening).
  - It also adopts its `PINS.md` quirk registry, with the tombstone ritual on
    every toolchain bump.
- **TC-CPP-2 (p0).** CMake presets are the only interface for building C++.
  `dev.py build` calls `cmake --preset` and `cmake --build --preset`; it
  never invokes Ninja or the compiler directly.

### Zones

- **TC-ZONE-1 (p0).** All MLIR-facing C++ lives in `foreign/idr/`: TableGen
  `.td` files, generated `.inc` files, headers, dialect and pass sources,
  and the two tools.
  - *Rationale:* MLIR's C++ API requires inheritance (`Dialect`, `Pass`,
    `OpRewritePattern`), CRTP (`Op<…>`), headers, and preprocessor-generated
    code. Under cpp-starter's rules that is quarantine code, "unavoidable
    foreign ABI adaptation". This is recorded as a `PINS.md` entry
    (`mlir-cxx-api`), not hidden.
  - LLVM and MLIR headers are included as system headers, so the project's
    warnings apply to our code, not to theirs.
- **TC-ZONE-2 (p0).** `src/` holds cpp-starter dialect code (named modules,
  no headers, no preprocessor). It stays empty until code exists that does
  not touch the MLIR API, such as a future runtime. `unsafe/` stays empty
  until needed.

### Deviations from cpp-starter

Each deviation below has a `PINS.md` entry.

- **TC-DEV-1 (p0). Platform gate.** The gate also accepts Linux x86_64, as
  the user decided. Linux x86_64 is the only tested platform. The arm64
  platforms cpp-starter accepts stay accepted but untested.
- **TC-DEV-2 (p0). Version source.** The gate reads the accepted versions
  from `toolchain.lock.json` instead of containing them.
- **TC-DEV-3 (p0). Lint compiler.** The lint graph uses the `clang` and
  `clang-tidy` built from the pinned LLVM, not cpp-starter's separately pinned
  Clang. The project then has one LLVM, not two.
- **TC-DEV-4 (p0). No stdexec.** cpp-starter's stdexec dependency and wait
  backend are not adopted, because nothing here uses them.
- **TC-DEV-5 (p0). C++17 headers.** LLVM's headers are C++17 and are compiled
  in C++26 mode with reflection enabled. Any incompatibility found gets a
  `PINS.md` entry and the narrowest possible workaround.

## Repository layout

- **TC-LAYOUT-1 (p0).**

  ```text
  CMakeLists.txt  CMakePresets.json  PINS.md  toolchain.lock.json
  compiler/            Idris: frontend, middle end, emitter (idris-mlir)
  lib/idris-mlir-io/   Idris: the trusted IdrisMLIR.IO module (PROF-IO-*)
  foreign/idr/         C++: idr dialect, passes, idris-mlir-opt, idris-mlir-cc
  src/  unsafe/        cpp-starter zones (empty at first)
  tests/tooling/       dev.py and repository rules
  tests/compiler/      Idris-side unit tests and invalid-Core tests
  tests/profile/vN/    accept/ and reject/ fixtures per profile version
  tests/idr/           hand-written .mlir + FileCheck, per op/folder/pass
  tests/e2e/vN/        Idris source → executable, with oracles
  tests/mlir/          checks of the pinned upstream tools
  tools/dev.py         bootstrap, build, test entry point
  docs/architecture/   this spec
  third_party/Idris2   pinned, unmodified
  ```
