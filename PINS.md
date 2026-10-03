# PINS.md — the pinned-quirk registry

One entry per pinned workaround: code or build configuration that is
deliberately wrong by the C++ profile we follow (bjornpagen/cpp-starter)
because the pinned toolchain, platform or dependency requires it, or a
deliberate deviation from cpp-starter. Each `PIN(name)` site in the tree
points at its entry here; the essay lives here, once.

Tombstone ritual: on every toolchain bump, read this file top to bottom,
re-test every retire condition, and delete what upstream fixed — one file,
one sweep. Retired with the LLVM-only toolchain: `lint-graph-unbuilt`
(stage 2 builds clang and clang-tidy) and
`cmake-ipo-probe-ordering` (no IPO probe and no `-freflection` remain).

The accepted toolchain release series live only in `toolchain.lock.json`,
which the top-level CMake configure gate reads.

## mlir-cxx-api

- symptom: MLIR's C++ API requires inheritance (`Dialect`, `Pass`,
  `OpRewritePattern`, `OpConversionPattern`), CRTP (`Op<...>`), headers and
  TableGen-generated `.inc` files included through the preprocessor; all of
  that is forbidden by the C++ profile
- sites: `foreign/idr/` — the whole dialect, its passes and its tools
  (`foreign/idr/tools/`), idris-mlir-tblgen among them: a TableGen backend
  that reads ODS through `mlir::tblgen` and registers itself with
  `mlir::GenRegistration`
- workaround: all MLIR-facing code is quarantine code in `foreign/idr/`;
  LLVM/MLIR headers and generated files are system includes, so
  the project's warnings apply to our code only; the targets never import std.
  The headers are parsed once, by the module `idr.mlir`
  (`foreign/idr/lib/Mlir.cppm`), which re-exports the names the code uses;
  what TableGen declares (the dialect, op hooks, pass bases, DRR patterns)
  stays in plain translation units in the global module
- retire: when MLIR offers a module-based, inheritance-free API (not expected)
- upstream: none — MLIR's design

## cmake-module-restat

- symptom: the Ninja rule CMake 4.2 writes for a scanned C++ compile has no
  `restat`, and clang writes a module interface's BMI anew on every compile
  of it; so touching an interface unit, even a comment in it, recompiles
  every unit that imports it, and every unit that imports those. Touching
  `idr/Idr.h`, TableGen's output or `lib/Mlir.cppm` recompiles every unit
  that imports anything
- sites: `foreign/idr/CMakeLists.txt` and `foreign/idr/lib/*/CMakeLists.txt`
  (the `CXX_MODULES` file sets of `idr_dialect`)
- workaround: interface units declare and never define, so that an edit to
  code recompiles its one implementation unit and nothing else; `idr.mlir`
  already exports every name the code uses, so it rarely changes
- retire: when CMake's Ninja generator restats a BMI and clang leaves an
  unchanged BMI untouched; then a definition may sit in an interface again
- upstream: none filed — a CMake and clang feature, not a bug

## zones-on-demand

- symptom: cpp-starter's layout has `src/` and `unsafe/` zones, but this
  project has no C++ outside `foreign/idr/` and `runtime/`; empty zone
  directories with placeholder `CMakeLists.txt` files are dead weight
- sites: `CMakeLists.txt` (no `add_subdirectory` for them)
- workaround: the zones do not exist until their first code does; that
  change adds the directory, its `CMakeLists.txt` and the `add_subdirectory`
- retire: when either zone gets code
- upstream: none — a deviation from cpp-starter

## orc-lljit

- symptom: upstream's `mlir::ExecutionEngine`, the natural engine for
  compile-time evaluation, aborts in a static-musl process: creating
  it calls `cantFail(DynamicLibrarySearchGenerator::GetForCurrentProcess(...))`
  (`mlir/lib/ExecutionEngine/ExecutionEngine.cpp:393-395` at
  llvmorg-23.1.2), which needs `dlopen(NULL)`, and a static musl
  `idris-mlir-cc` has no dynamic loader; `LLJITBuilder` also links process
  symbols by default
- sites: foreign/idr/lib/Eval/Jit.cc (`idr-eval`)
- workaround: ORC's `LLJIT` directly, which `ExecutionEngine` wraps, with
  `setLinkProcessSymbolsByDefault(false)` (`LLJIT.h:415`) and an
  `absoluteSymbols` table that binds the runtime's functions, and the libm
  functions lowered code may call, to `idris-mlir-cc`'s own copies; the
  library functions LLVM calls only on some targets (Darwin's `bzero`,
  `__exp10`, ...) are the target entry's `IDRIS_MLIR_JIT_LIBRARY_CALLS`,
  bound from the process by a `DynamicLibrarySearchGenerator` that allows
  those names alone, which only a target with a dynamic loader names
- retire: when `ExecutionEngine` can be created without the process's
  symbols (upstream/execution-engine-process-symbols); re-read at every LLVM
  bump
- upstream: upstream/execution-engine-process-symbols (not yet filed): an
  option to create the engine without the process's symbols

## prune-before-remove-dead-values

- symptom: at llvmorg-23.1.2, `remove-dead-values` finds a function or a
  block unreachable (dead-code analysis never visits it: a private function
  nothing live calls, or a match region a constant rules out), marks every
  value there dead and erases the function's arguments, but keeps the ops
  that still use them, and then crashes on the null operand
  (`mlir/lib/Transforms/RemoveDeadValues.cpp:649`, the region-branch
  canonicalization at `:833`, `Matchers.h:491`). The constants that make a
  region unreachable can appear after `sccp` in the same round (from
  `canonicalize` or `idr-eval`), so running `sccp` first is not enough
- sites: foreign/idr/lib/Passes/Prune.cc (`idr-prune`),
  foreign/idr/lib/Passes/Simplify.cc (the round of the simplify loop)
- workaround: `idr-prune` runs before `remove-dead-values` and empties,
  with the same analyses, every block they prove unreachable: a match
  region ends in `ub.unreachable`, a function returns poison. `symbol-dce`
  runs between them, since emptying code can leave a function nothing
  refers to, which the analysis would find unreachable in turn
- retire: when `remove-dead-values` leaves unreachable code alone or erases
  it at a bump; `tests/upstream/remove-dead-values-unreachable` fails then
- upstream: upstream/remove-dead-values-unreachable (not yet filed)

## remove-dead-values-address-taken

- symptom: at llvmorg-23.1.2, `remove-dead-values` leaves alone the
  parameters of a function that is named other than as a callee (by an
  `idr.closure` or a closure constant), but still finds a value that a
  direct call passes to one of those parameters dead when the function
  never reads it: it erases the value (a parameter of the caller, or the op
  that made it) and the call keeps a null operand ("null operand found").
  Arity raising and apply of a known closure make such direct calls
- sites: foreign/idr/lib/Passes/Prune.cc (`idr-prune`),
  foreign/idr/lib/Eval/Eval.cc (a poison operand is no value to evaluate)
- workaround: `idr-prune`, right before `remove-dead-values`, makes each
  call of such a function pass `ub.poison` for every parameter the
  function never reads
- retire: when `remove-dead-values` keeps the operands of calls whose
  callee's signature it keeps (`tests/upstream/remove-dead-values-address-taken`
  fails)
- upstream: upstream/remove-dead-values-address-taken (not yet filed)

## uplift-final-counter

- symptom: at llvmorg-23.1.2, `scf::upliftWhileToForLoop`
  (`populateUpliftWhileToForPatterns`) replaces the `scf.while` result of
  the counter with its value in the last iteration, one step short of the
  value the loop ends with, and below the lower bound when the loop runs
  no iteration
- sites: foreign/idr/lib/Passes/TailLoops.cc (`counterUsedAfter`);
  foreign/idr/tools/idris-mlir-opt.cc registers upstream's test pass
  `test-scf-uplift-while-to-for`, which the pinned mlir-opt lacks, for the
  reproducer
- workaround: `idr-tail-loops` uplifts a counted loop only when nothing
  uses the value its counter ends with; any other stays an `scf.while`
- retire: when the uplift gives the value the loop ends with
  (`tests/upstream/uplift-final-counter` fails)
- upstream: upstream/uplift-final-counter (not yet filed)

## inline-unreachable

- symptom: the upstream inliner's default `handleTerminator`
  (`DialectInlinerInterface.td`) aborts on a callee whose body ends in
  `ub.unreachable`: the `ub` dialect's inliner interface does not implement
  it, and no hook of ours sees that terminator. The inliner's region
  patterns likewise skip a region that ends in `ub.unreachable`
- sites: compiler/src/IdrisMLIR/Emit/Bodies.idr (`epilogue`),
  foreign/idr/lib/Passes/Prune.cc (`idr::returnNever`, which
  foreign/idr/lib/Passes/TailLoops.cc uses too),
  foreign/idr/lib/Dialect/Dialect.cc (the program's verifier)
- workaround: no function body ends in `ub.unreachable`: one that never
  returns (a crash, a body Idris proved impossible, a match none of whose
  regions returns) returns `ub.poison` instead, which is never reached; the
  program's verifier refuses a body that ends in `ub.unreachable`, after
  every pass. A match region that crashes still ends in `ub.unreachable`
  and stays a region, which the lowering lowers
- retire: when the inliner handles `ub.unreachable` at a bump;
  `tests/upstream/inline-unreachable-terminator` fails then
- upstream: upstream/inline-unreachable-terminator (not yet filed)

## mlir-recursion

- symptom: MLIR's textual parser and printer, and many walks, recurse once
  per level of attribute nesting, so a constant nested a few thousand deep
  overflows an 8 MiB stack with a bare SIGSEGV (6,000 levels of builtin
  array in `mlir-opt`). Compile-time evaluation builds constants as deep as
  the program's own values: a computed list of 10,000 elements is a
  constant nested 10,000 deep
- sites: foreign/idr/tools/idris-mlir-cc.cc (`runOnLargeStack`),
  foreign/idr/tools/idris-mlir-opt.cc, foreign/idr/lib/Eval/Child.cc,
  runtime/start.cc (`idris_rt_run_on_stack`)
- workaround: idris-mlir-cc runs the whole compilation, idris-mlir-opt
  its run, and the evaluation child its calls, on the runtime's
  reserved-stack runner: up to 2^44, 2^44 and 2^46 bytes of address space,
  committed as touched, above a guard, so the depth is bounded by memory.
  Running out of it is a named error in the tools and exhaustion in the
  child. idris-mlir-reduce does not have it
- retire: when MLIR parses and prints nested attributes from a worklist;
  `tests/upstream/recursive-attribute-parser` fails then
- upstream: upstream/recursive-attribute-parser (not yet filed)

## bytecode-deferred-quadratic

- symptom: MLIR's bytecode reader reads an attribute nested n deep in time
  quadratic in n (4.5 s for a builtin array 32,000 deep, 0.18 s from
  text). Compile-time evaluation's results are as deep as the program's
  values: a computed list of 20,000 elements took 45 s to read back
- sites: foreign/idr/lib/Eval/Reify.cc (`encodeResults`, `decodeResults`)
- workaround: the evaluation child sends a call's results as bytecode of
  a flat table of their distinct parts, each after the parts it holds,
  which it names by position; the compiler rebuilds the constants from the
  table in order. No attribute in the table is nested more than a few
  levels, and a shared part is in it once
- retire: when the bytecode reader resolves deferred entries in linear
  time; `tests/upstream/bytecode-deferred-quadratic` fails then. The table
  may stay regardless, as it keeps sharing without the reader's help
- upstream: upstream/bytecode-deferred-quadratic (not yet filed)

## simplify-structural-fixpoint

- symptom: at llvmorg-23.1.2, `composite-fixed-point-pass` decides its
  fixpoint by `OperationFingerPrint`, a hash of the addresses of the
  module's ops, blocks and values (`mlir/lib/Transforms/CompositePass.cpp:68-91`,
  `mlir/lib/IR/OperationSupport.cpp:933-975`), and `sccp` erases every
  constant it meets and makes an equal one, since its fresh `OperationFolder`
  is never told about the constants the module has
  (`mlir/lib/Transforms/SCCP.cpp:42-62, 84-99`). A pipeline with `sccp` in
  it never has the same fingerprint twice: on a module at its fixpoint the
  composite pass runs the pipeline `max-iterations` times and warns.
  `-mlir-print-ir-after-change` prints after `sccp` for the same reason
- sites: foreign/idr/lib/Passes/Simplify.cc (`structural`, and the loop in
  `runOnOperation`)
- workaround: `idr-simplify` is its own loop over the round and decides the
  fixpoint by a structural hash of the module: constants by their value at
  each use, other values by their position in the walk, so a constant
  remade at another address hashes the same. Over its round budget it fails
  with `unsupported (compile-time budget)`, where the composite pass would
  warn and go on
- retire: when `composite-fixed-point-pass{pipeline=sccp}` converges on a
  module `sccp` leaves as it is (`tests/upstream/composite-fixed-point-sccp`
  fails). Then measure whether a round at its fixpoint keeps its
  `OperationFingerPrint`; if it does, `structural` goes, and the loop may be
  a `composite-fixed-point-pass` over the round once its budget can be an
  error and its statistics ours
- upstream: upstream/composite-fixed-point-sccp (not yet filed)

## vectorize-precondition-body

- symptom: at llvmorg-23.1.2, `linalg::vectorizeOpPrecondition` ("Return
  success if the operation can be vectorized") checks the ops of an
  all-parallel generic's body (`isElementwise`), but of a reduction's only
  their types and the combiner
  (`mlir/lib/Dialect/Linalg/Transforms/Vectorization.cpp:2250-2288`,
  `:1879-1896`). It accepts a reduction whose body holds an op that is not
  elementwise-mappable (a crash check's `scf.if`, a call), which
  `linalg::vectorize` then refuses (`:1380-1382`), after building part of
  its vector code. idr-vectorize tiled such a loop before vectorizing it, and
  its scalar tiles ran the body column by column within each group of rows
- sites: foreign/idr/lib/Passes/Vectorize.cc (`vectorizable`)
- workaround: idr-vectorize decides with the precondition and
  `linalg::hasOnlyScalarElementwiseOp` of the body, the check upstream
  makes of an all-parallel generic, before it changes anything; a generic it
  refuses stays whole, and convert-linalg-to-loops runs its body in the
  program's order. A tile of a generic it took that the vectorizer refuses
  is its error, and fails the pass
- retire: when the precondition refuses such a body
  (`tests/upstream/vectorize-precondition-body` fails); `vectorizable` then
  asks the precondition alone
- upstream: upstream/vectorize-precondition-body (not yet filed)

## int-range-narrowing-exactness

- symptom: at llvmorg-23.1.2, upstream's narrowing
  (`arith::populateIntRangeNarrowingPatterns`) makes an elementwise op an
  op on the narrow type whenever the ranges of its operands and results fit
  it (`mlir/lib/Dialect/Arith/Transforms/IntRangeOptimizations.cpp:378-397`).
  Three narrowed ops then compute something else: a shift whose amount can
  reach the narrow width (poison there), a `remsi` that can see INT_MIN %
  -1 of the narrow type (undefined behaviour once `llvm.srem`, where the
  wide op gives 0), and a `remui` of a word that may be negative, which
  the narrow op reads as another number
- sites: foreign/idr/lib/Passes/NarrowLanes.cc (`exact`)
- workaround: idr-narrow-lanes versions a vectorized loop only when every
  integer op in it wider than 32 bits is an arith op whose 32-bit form
  computes the same: a shift's amount stays below 32, a signed remainder
  never sees INT32_MIN % -1, an op that reads its operands unsigned sees
  no negative word; any other loop keeps its 64-bit lanes
- retire: when the narrowing asks this itself
  (`tests/upstream/int-range-narrowing-exactness` fails); `exact` goes then
- upstream: upstream/int-range-narrowing-exactness (not yet filed)

## llvm-force-enable-stats

- symptom: `llvm/ADT/Statistic.h` makes `llvm::Statistic` a no-op when
  `NDEBUG` is defined (the release preset) and `LLVM_FORCE_ENABLE_STATS` is
  0, but the pinned MLIR library is built with assertions, where it counts:
  `Pass::Statistic`'s out-of-line constructor would write a counter into a
  one-byte member, over what follows it in the pass. A plain
  `-DLLVM_FORCE_ENABLE_STATS=1` does not help: `llvm/Config/llvm-config.h`
  defines it to 0 unconditionally, after the command line
- sites: foreign/idr/CMakeLists.txt (the compile options of idr_dialect and
  of idris-mlir-tblgen, which links no idr_dialect),
  foreign/idr/lib/Support/EnableStatistics.h,
  foreign/idr/lib/Support/PipelineStatistics.cc (the static_assert)
- workaround: every translation unit of idr_dialect and the tools starts
  with `lib/Support/EnableStatistics.h` (`-include`), which includes
  `llvm-config.h` first and redefines `LLVM_FORCE_ENABLE_STATS` to 1, so
  statistics count in every build type; a static_assert fails the build
  where they would not
- retire: when the pinned LLVM is built with `LLVM_FORCE_ENABLE_STATS`, or
  a pass statistic's layout no longer depends on the includer's `NDEBUG`
- upstream: none

## platform-gate-x86_64

- symptom: cpp-starter's gate accepts arm64 only; this project runs on
  Linux x86_64 (the user's decision)
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
- workaround: one source of truth, the lock file, read by all
- retire: never; deliberate
- upstream: none

## no-stdexec

- symptom: cpp-starter depends on stdexec and a wait backend; nothing here
  uses senders, receivers or an event loop yet
- sites: CMakeLists.txt (no `FetchContent_Declare(stdexec)`), no contracts
  runtime link either, since no code uses contracts
- workaround: omit both until a runtime needs them
- retire: when code needs them; then adopt cpp-starter's declarations and
  its `cmake-ld-link-order` entry. Its `gcc-gmf-stdexec-ice` entry stays
  behind: GCC is gone
- upstream: none

## llvm-cxx17-headers

- symptom: LLVM/MLIR headers are C++17 and are compiled here in C++26 mode
  by the pinned clang with libc++
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
  static on musl. GCC-only diagnostics
  of the profile (`-Wduplicated-cond`, `-Wlogical-op`, `-Wuseless-cast` and
  the like) and libstdc++'s `_GLIBCXX_ASSERTIONS` have no clang spelling
- sites: CMakeLists.txt — the compiler gate (Clang, the lock's LLVM series,
  a `-linux-musl` target, libc++), the warning set, and libc++'s extensive
  hardening mode in place of `_GLIBCXX_ASSERTIONS`
- workaround: keep every warning clang has; the lint graph (clang-tidy)
  covers what the GCC-only warnings did
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

- symptom: stage 2 (LLVM, MLIR, clang, lld) was meant to be built with
  `LLVM_ENABLE_LTO=Full`. A full-LTO link is one single-threaded
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
  and preprocessor code, which the C++ profile forbids
- sites: `runtime/`, every source there
- workaround: the runtime is quarantine code in its own zone, built with its
  own profile (no exceptions, no RTTI, no C++ library at link time, its
  bitcode carried as the target entry says: fat LTO objects on ELF) and
  checked by `check-archive.sh`
- retire: never; the vendored libraries are C++ headers
- upstream: none

## runtime-cx16

- symptom: snmalloc requires CMPXCHG16B, which the x86-64 baseline lacks
- sites: CMakeLists.txt, the x86_64 target entry — `-march=x86-64 -mcx16`
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
  package version and SHA-256. The UAPI is the kernel's stable ABI
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

- symptom: the pinned toolchain builds everything else with the stage-2
  clang, but Idris's C support library is a shared object loaded by the host's
  Chez Scheme, a glibc process, which the static musl toolchain cannot build
  for
- sites: tools/bootstrap.sh (step `idris`)
- workaround: Idris 2 is built as before, with the host's C compiler; it is
  a host program and never links into an executable
- retire: when Chez Scheme itself is built on the pinned toolchain
- upstream: none
