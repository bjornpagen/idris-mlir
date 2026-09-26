# PINS.md — the pinned-quirk registry

One entry per pinned workaround: code or build configuration that is
deliberately wrong by dialect law (docs/cpp-profile.md) because the pinned
toolchain, platform or dependency requires it, or a deliberate deviation from
bjornpagen/cpp-starter (docs/architecture/11-toolchain.md, TC-DEV-*). Each
`PIN(name)` site in the tree points at its entry here; the essay lives here,
once.

Tombstone ritual: on every toolchain bump, read this file top to bottom,
re-test every retire condition, and delete what upstream fixed — one file,
one sweep.

The accepted toolchain release series live only in `toolchain.lock.json`,
which the top-level CMake configure gate reads (TC-DEV-2).

## mlir-cxx-api

- symptom: MLIR's C++ API requires inheritance (`Dialect`, `Pass`,
  `OpRewritePattern`, `OpConversionPattern`), CRTP (`Op<...>`), headers and
  TableGen-generated `.inc` files included through the preprocessor; all of
  that is forbidden in dialect code
- sites: `foreign/idr/` — the whole dialect, its passes and both tools
- workaround: all MLIR-facing code is quarantine code in `foreign/idr/`
  (TC-ZONE-1); LLVM/MLIR headers and generated files are system includes, so
  the project's warnings apply to our code only; the targets never import std
- retire: when MLIR offers a module-based, inheritance-free API (not expected)
- upstream: none — MLIR's design

## platform-gate-x86_64

- symptom: cpp-starter's gate accepts arm64 only; this project runs on
  Linux x86_64 (the user's decision, TC-DEV-1)
- sites: CMakeLists.txt — the platform gate, and the Linux hardening block,
  which uses `-fcf-protection=full` (CET) on x86_64 where arm64 uses
  `-mbranch-protection=standard` (PAC/BTI; GCC rejects it on x86_64)
- workaround: accept Linux x86_64 in addition to cpp-starter's platforms;
  select the architecture's control-flow protection in CMake
- retire: never; this is a scope decision. Only Linux x86_64 is tested.
- upstream: none

## versions-in-lock-file

- symptom: cpp-starter keeps the accepted toolchain series only in the
  configure gate, but `tools/dev.py` must bootstrap the same pins
- sites: CMakeLists.txt reads `toolchain.lock.json` (`string(JSON ...)`)
- workaround: one source of truth, the lock file, read by both (TC-DEV-2)
- retire: never; deliberate
- upstream: none

## lint-graph-unbuilt

- symptom: the lint graph needs `clang` and `clang-tidy` from the pinned LLVM
  (TC-DEV-3), but building clang and clang-tools-extra alongside MLIR does not
  fit the build environment's 4 cores, 15 GB of RAM and 24 GB of disk in
  reasonable time
- sites: CMakeLists.txt (`IDRIS_MLIR_LINT_GRAPH` fails with this pin's name),
  CMakePresets.json (`lint`), tools/dev.py (`bootstrap-llvm` builds `mlir` only)
- workaround: the GCC graph with `-Werror` and the full warning set is the
  only enforcement for now
- retire: add `clang;clang-tools-extra` to `LLVM_ENABLE_PROJECTS` in
  `bootstrap-llvm` on a machine that can build them, and remove the fatal error
- upstream: none

## no-stdexec

- symptom: cpp-starter depends on stdexec and a wait backend; nothing here
  uses senders, receivers or an event loop yet (TC-DEV-4)
- sites: CMakeLists.txt (no `FetchContent_Declare(stdexec)`), no contracts
  runtime link (`stdc++exp`) either, since no code uses contracts
- workaround: omit both until a runtime needs them
- retire: when `src/` gains code that needs them; then adopt cpp-starter's
  declarations, `gcc-gmf-stdexec-ice` and `cmake-ld-link-order` verbatim
- upstream: none

## llvm-cxx17-headers

- symptom: LLVM/MLIR headers are C++17 and are compiled here in C++26 mode
  with `-freflection` (TC-DEV-5)
- sites: every translation unit in `foreign/idr/`
- workaround: none needed — verified in p0 that the pinned headers compile
  cleanly with the pinned GCC in the full profile (system includes)
- retire: delete this entry at the next toolchain bump if the check still
  passes without changes
- upstream: none

## idr-entry-public

- symptom: the contract keeps every `func.func` private (IDR-FN-2) and names
  the root in the `idr.entry` module attribute, which `symbol-dce` and the
  inliner do not count as a use, so they deleted the root (found in p0)
- sites: foreign/idr/lib/TailLoops.cpp (`idr-entry`), foreign/idr/lib/Lower.cpp
- workaround: the `idr-entry` pass makes the root public for the generic
  passes; `idr-lower` makes it private again when it creates the C entry
  point (OPT-PIPE-1)
- retire: never; it follows from the contract
- upstream: none

## darwin-inert-mitigations

- symptom: `_FORTIFY_SOURCE=3` is excluded from every C++ TU by Apple's SDK,
  and `-mbranch-protection=standard` executes as NOP in plain-arm64 Darwin
  processes, so both flags are byte-for-byte inert there
- sites: CMakeLists.txt — the Linux-only hardening block on
  `idris_mlir_language_profile`
- workaround: select the live mitigations in CMake, never behind a C++ `#ifdef`
- retire: as in cpp-starter
- upstream: none — platform ABI facts

## cmake-import-std-uuid

- symptom: `import std` is experimental in CMake, gated by
  `CMAKE_EXPERIMENTAL_CXX_IMPORT_STD`, and the accepted UUID value changes
  per CMake feature series — a stale UUID silently disables the feature
- sites: CMakeLists.txt — the configure gate on the pinned CMake series plus
  `set(CMAKE_EXPERIMENTAL_CXX_IMPORT_STD "d0edc3af-4c50-42ea-a356-e2862fe7a444")`
- workaround: pin the CMake series and the UUID together; on any CMake bump
  re-read `Help/dev/experimental.rst`, update the UUID, and move the lock's
  accepted series
- retire: when CMake ships `import std` as a stable feature
- upstream: none — CMake's deliberate experimental-feature mechanism

## cmake-ipo-probe-ordering

- symptom: CMake's `check_ipo_supported` probe inherits `CMAKE_CXX_FLAGS` but
  not `CMAKE_CXX_STANDARD`, and the pinned cc1plus rejects `-freflection`
  outside C++26, so a probe after the `-freflection` append fails
- sites: CMakeLists.txt — the probe precedes the `-freflection` append
- workaround: keep the IPO probe ahead of every standard-gated flag
- retire: as in cpp-starter
- upstream: none filed
