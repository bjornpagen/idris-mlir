# PINS.md — the pinned-quirk registry

One entry per pinned workaround: code or build configuration that is
deliberately wrong by dialect law (docs/cpp-profile.md) because the pinned
toolchain, platform or dependency requires it, or a deliberate deviation from
bjornpagen/cpp-starter or from docs/plan.md (docs/architecture/11-toolchain.md,
TC-DEV-*). Each `PIN(name)` site in the tree points at its entry here; the
essay lives here, once.

Tombstone ritual: on every toolchain bump, read this file top to bottom,
re-test every retire condition, and delete what upstream fixed — one file,
one sweep. Retired with the LLVM-only toolchain (docs/plan.md section 5.2):
`lint-graph-unbuilt` (stage 2 builds clang and clang-tidy) and
`cmake-ipo-probe-ordering` (no IPO probe and no `-freflection` remain).

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

## orc-lljit

- symptom: docs/plan.md chose upstream's `mlir::ExecutionEngine` for
  compile-time evaluation, but it aborts in a static-musl process: creating
  it calls `cantFail(DynamicLibrarySearchGenerator::GetForCurrentProcess(...))`
  (`mlir/lib/ExecutionEngine/ExecutionEngine.cpp:393-395` at
  llvmorg-23.1.2), which needs `dlopen(NULL)`, and a static musl
  `idris-mlir-cc` has no dynamic loader; `LLJITBuilder` also links process
  symbols by default
- sites: foreign/idr/lib/Eval/Jit.cc (`idr-eval`, ELIM-EVAL-1, LOW-JIT-1)
- workaround: ORC's `LLJIT` directly, which `ExecutionEngine` wraps, with
  `setLinkProcessSymbolsByDefault(false)` (`LLJIT.h:415`) and an
  `absoluteSymbols` table that binds the runtime's functions, and the libm
  functions lowered code may call, to `idris-mlir-cc`'s own copies (LOW-RT-1)
- retire: never while `idris-mlir-cc` is static on musl; re-read at every
  LLVM bump, in case `ExecutionEngine` stops requiring process symbols
- upstream: none — a static process has no process-symbol generator by design

## symbol-dce-first

- symptom: at llvmorg-23.1.2, `remove-dead-values` on a private function
  that no one calls (or only itself) erases its arguments, while region ops
  that it keeps for their effects still use them, and then crashes
  (`mlir/lib/Transforms/RemoveDeadValues.cpp:649` and `:833`); the same
  happens with `scf.index_switch`
- sites: foreign/idr/lib/Passes/Simplify.cc (the round of the simplify loop,
  OPT-PIPE-5); tests/idr/canon/upstream-passes.mlir, which gives every
  private function a caller
- workaround: every round of the simplify loop runs `symbol-dce` before
  `remove-dead-values`, so no function without callers reaches it
- retire: when `remove-dead-values` handles such functions at a bump; then
  the order is free again
- upstream: none filed yet

## inline-unreachable

- symptom: the upstream inliner's default `handleTerminator`
  (`DialectInlinerInterface.td`) cannot handle a callee whose body ends in
  `ub.unreachable`, which is how a function whose body is a crash ends
  (`idr.crash`, then `ub.unreachable`, IDR-CRASH-1); the inliner's region
  patterns likewise skip a region that ends in `ub.unreachable`
- sites: foreign/idr/lib/Dialect/Dialect.cc (`IdrInliner`,
  IDR-IF-1)
- workaround: the dialect never inlines a function whose body is a
  top-level crash; a call of it stays a call, and a match region that
  crashes stays a region, which `idr-lower` lowers (LOW-MATCH-1). Nothing is
  lost but the inlining of a call that always crashes
- retire: when the inliner and region inlining handle `ub.unreachable` at a
  bump
- upstream: none filed yet

## platform-gate-x86_64

- symptom: cpp-starter's gate accepts arm64 only; this project runs on
  Linux x86_64 (the user's decision, TC-DEV-1)
- sites: CMakeLists.txt — the platform gate, and the Linux hardening block,
  which uses `-fcf-protection=full` (CET) on x86_64 where arm64 uses
  `-mbranch-protection=standard` (PAC/BTI, which x86_64 compilers reject)
- workaround: accept Linux x86_64 in addition to cpp-starter's platforms;
  select the architecture's control-flow protection in CMake
- retire: never; this is a scope decision. Only Linux x86_64 is tested.
- upstream: none

## versions-in-lock-file

- symptom: cpp-starter keeps the accepted toolchain series only in the
  configure gate, but `tools/bootstrap.sh` must build the same pins
- sites: CMakeLists.txt reads `toolchain.lock.json` (`string(JSON ...)`);
  tools/bootstrap.sh and tools/verify-pins.sh read it too
- workaround: one source of truth, the lock file, read by all (TC-DEV-2)
- retire: never; deliberate
- upstream: none

## no-stdexec

- symptom: cpp-starter depends on stdexec and a wait backend; nothing here
  uses senders, receivers or an event loop yet (TC-DEV-4)
- sites: CMakeLists.txt (no `FetchContent_Declare(stdexec)`), no contracts
  runtime link either, since no code uses contracts
- workaround: omit both until a runtime needs them
- retire: when code needs them; then adopt cpp-starter's declarations and
  its `cmake-ld-link-order` entry. Its `gcc-gmf-stdexec-ice` entry stays
  behind: GCC is gone (docs/plan.md section 5.2)
- upstream: none

## llvm-cxx17-headers

- symptom: LLVM/MLIR headers are C++17 and are compiled here in C++26 mode
  by the pinned clang with libc++ (TC-DEV-5)
- sites: every translation unit in `foreign/idr/`
- workaround: none needed so far — GCC compiled them cleanly in the full
  profile, and so did a host clang against the old headers; the pinned
  stage-2 clang has not compiled them yet (the first `make build` does)
- retire: delete this entry at the next toolchain bump if the check still
  passes without changes
- upstream: none


## darwin-inert-mitigations

- symptom: `_FORTIFY_SOURCE` does nothing with musl (it has no fortified
  functions) or with Apple's SDK for C++, and `-mbranch-protection=standard`
  executes as NOP in plain-arm64 Darwin processes
- sites: CMakeLists.txt — the Linux-only hardening block on
  `idris_mlir_language_profile`, which no longer defines `_FORTIFY_SOURCE`
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

## clang-libcxx

- symptom: cpp-starter's profile is GCC with libstdc++; this project's
  compiler is the stage-2 clang of the pinned llvm-project with libc++,
  static on musl (docs/plan.md section 5.2, TC-DEV-6). GCC-only diagnostics
  of the profile (`-Wduplicated-cond`, `-Wlogical-op`, `-Wuseless-cast` and
  the like) and libstdc++'s `_GLIBCXX_ASSERTIONS` have no clang spelling
- sites: CMakeLists.txt — the compiler gate (Clang, the lock's LLVM series,
  a `-linux-musl` target, libc++), the warning set, and libc++'s extensive
  hardening mode in place of `_GLIBCXX_ASSERTIONS`
- workaround: keep every warning clang has; the lint graph (clang-tidy,
  TC-DEV-3) covers what the GCC-only warnings did
- retire: never; GCC is gone
- upstream: none

## clang-no-reflection

- symptom: cpp-starter compiles with `-freflection`; the pinned clang's
  reflection is a stub (`^^` parses only for builtin types, no splices, no
  `<meta>`), and no code here uses reflection
- sites: CMakeLists.txt — the module-ABI flags have no `-freflection`
- workaround: concepts and templates
- retire: when a pin of llvm-project implements P2996; turn it on again
- upstream: llvm-project's P2996 work

## no-sanitizer-runtimes

- symptom: cpp-starter's `asan-ubsan` preset needs compiler-rt's sanitizer
  runtimes; the static musl toolchain builds only compiler-rt's builtins, and
  ASan does not support static executables
- sites: CMakeLists.txt (`IDRIS_MLIR_RUNTIME_SANITIZERS` fails with this
  pin's name), CMakePresets.json (`asan-ubsan`)
- workaround: every build keeps trap-mode UBSan (`-fsanitize=undefined
  -fsanitize-trap=all`), which needs no runtime; the preset fails at
  configure time instead of silently building something else
- retire: when a sanitizer build on musl is worth building compiler-rt's
  sanitizers (and dynamic executables) for
- upstream: none

## musl-thread-stacks

- symptom: musl's default thread stack is 128 KiB unless the executable's
  PT_GNU_STACK asks for more; LLVM and MLIR run deep recursions on threads
  of their own
- sites: CMakeLists.txt — `-z stack-size=8388608` for our tools
- workaround: 8 MiB, glibc's default, recorded in PT_GNU_STACK
- retire: never while the tools link musl
- upstream: none — musl's documented behaviour

## stage2-thinlto

- symptom: docs/plan.md section 5.7 builds stage 2 (LLVM, MLIR, clang,
  lld) with `LLVM_ENABLE_LTO=Full`. A full-LTO link is one single-threaded
  process over the whole program: for clang, clang-tidy or mlir-opt that is
  roughly 10 GB or more of memory and most of an hour each, on a machine
  with 4 cores and 15 GB that also runs compile jobs, and it has not been
  measured here
- sites: tools/bootstrap.sh (`IDRIS_MLIR_STAGE2_LTO`, default `Thin`; the
  ThinLTO backends are limited to two threads); CMakeLists.txt, where our
  own code is still `-flto=full`
- workaround: stage 2 is ThinLTO with fat objects. LLVM's tools are
  ThinLTO-optimized; our Release build links LLVM's ThinLTO bitcode with
  our full-LTO bitcode, so the two meet in one link but ThinLTO does not
  import across them. The stamp of stage 2 records the LTO kind, the time,
  the peak memory and the disk it took
- retire: run `IDRIS_MLIR_STAGE2_LTO=Full tools/bootstrap.sh stage2` on a
  machine where it fits, record the numbers here, and make Full the default
- upstream: none

## runtime-quarantine

- symptom: the runtime is C++ over vendored header libraries (snmalloc,
  simdutf, fast_float) and exports a C ABI (`idris_rt.h`), so it has headers
  and preprocessor code, which dialect law forbids
- sites: `runtime/` (TC-ZONE-3), every source there
- workaround: the runtime is quarantine code in its own zone, built with its
  own profile (no exceptions, no RTTI, no C++ library at link time, fat LTO
  objects) and checked by `check-archive.sh` (TC-RT-2)
- retire: never; the vendored libraries are C++ headers
- upstream: none

## runtime-cx16

- symptom: snmalloc requires CMPXCHG16B, which the x86-64 baseline lacks
- sites: runtime/CMakeLists.txt — `-march=x86-64 -mcx16`
- workaround: the runtime is compiled for the baseline plus CMPXCHG16B;
  idris-mlir-cc raises every runtime function to the program's CPU
  (x86-64-v3 by default, which has it)
- retire: never; every x86-64 CPU since 2006 has it
- upstream: none

## simdutf-dispatch

- symptom: simdutf picks its implementation from the environment variable
  `SIMDUTF_FORCE_IMPLEMENTATION` when it is set, so a program's string
  checks could depend on its environment
- sites: runtime/strings.cc
- workaround: the runtime selects `detect_best_supported()` once and calls
  that implementation directly
- retire: never; deliberate
- upstream: none


## linux-uapi-from-host

- symptom: musl ships no kernel headers, but libc++ (`<linux/futex.h>`) and
  snmalloc (`<linux/random.h>`, `<linux/futex.h>`) include them
- sites: tools/bootstrap.sh (step `musl`)
- workaround: the host's Linux UAPI headers (`linux/`, `asm/`,
  `asm-generic/`) are copied into the sysroot; the musl stamp records their
  package version and SHA-256 (TC-PIN-3). The UAPI is the kernel's stable ABI
- retire: when the kernel's headers are pinned and installed from source
- upstream: none

## mirrored-sources

- symptom: musl's and GMP's official hosts (git.musl-libc.org, gmplib.org)
  are unreachable here; the submodules are clones of GitHub mirrors
  (kraj/musl, arthenica/gmp)
- sites: .gitmodules, toolchain.lock.json (`release`, `release_sha256`),
  tools/bootstrap.sh (`verify_release`)
- workaround: each is pinned by commit to its release tag; the lock records
  the official release tarball and its SHA-256 (as buildroot and Homebrew
  publish it). The musl and gmp steps fetch the tarball when they can and
  refuse a SHA-256 or a set of files that differs from the pinned commit;
  when they cannot, they say so and the stamp records `not verified`
- retire: when the official hosts are reachable and the check has passed
  once
- upstream: none

## idris-support-host-cc

- symptom: docs/plan.md section 5.2 compiles Idris's C support library with
  the stage-2 clang; the library is a shared object loaded by the host's
  Chez Scheme, a glibc process, which the static musl toolchain cannot build
  for
- sites: tools/bootstrap.sh (step `idris`)
- workaround: Idris 2 is built as before, with the host's C compiler; it is
  a host program and never links into an executable (TC-PIN-3)
- retire: when Chez Scheme itself is built on the pinned toolchain
- upstream: none

## orc-lljit

- symptom: docs/plan.md section 6 runs compile-time evaluation through
  MLIR's `ExecutionEngine`; at the pinned llvmorg-23.1.2,
  `ExecutionEngine::create` calls
  `cantFail(DynamicLibrarySearchGenerator::GetForCurrentProcess(...))`
  (`mlir/lib/ExecutionEngine/ExecutionEngine.cpp:393-395`), which needs
  `dlopen(NULL)` and aborts in the static-musl `idris-mlir-cc`; `LLJITBuilder`
  also links the process's symbols by default
- sites: foreign/idr/lib/Eval/Jit.cc (idr-eval, docs/cutover.md 6.4 and
  decision 7.7)
- workaround: ORC's `LLJIT`, which `ExecutionEngine` wraps, with
  `setLinkProcessSymbolsByDefault(false)`, the inactive platform, and an
  `absoluteSymbols` table of the runtime's entry points, the libm functions
  of LOW-EXT-1 and the memory functions LLVM emits, all linked into
  `idris-mlir-cc`: the JITed code runs the same runtime and libc as
  executables
- retire: when `ExecutionEngine` can be created without a process-symbol
  generator (an option to skip it) and its other uses fit idr-eval's
  (one compile per round, a forked child); re-test on every LLVM bump
- upstream: none filed
