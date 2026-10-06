# PINS.md — the pinned-quirk registry

One entry per pinned workaround: code or build configuration that is
deliberately wrong by the C++ profile we follow (bjornpagen/cpp-starter)
because the pinned toolchain, platform or dependency requires it, or a
deliberate deviation from cpp-starter. Each `PIN(name)` site in the tree
points at its entry here; the essay lives here, once.

A bug in a pinned upstream is fixed by a patch to its source, carried in
`upstream/<bug>/` and applied by `tools/bootstrap.sh` (upstream/README.md);
its entry's workaround is that patch, and the entry goes when the pin moves
past upstream's fix. Where code of ours still stands in for a patch, because
the toolchain has not been rebuilt with it or because the bug has no patch
yet, the entry says what that code is and when it goes.

Tombstone ritual: on every toolchain bump, read this file top to bottom,
re-test every retire condition, and delete what upstream fixed, with the
patches the new pin has upstream's fix for — one file, one sweep. Retired
with the LLVM-only toolchain: `lint-graph-unbuilt` (stage 2 builds clang
and clang-tidy) and
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
  The headers are parsed once, by the modules `idr.mlir`
  (`foreign/idr/lib/Mlir.cppm`) and `idr.dialect`
  (`foreign/idr/lib/Dialect/Dialect.cppm`), which re-export the names the
  code uses; what TableGen declares (the dialect, op hooks, pass bases, DRR
  patterns) stays in plain translation units in the global module
- retire: when MLIR offers a module-based, inheritance-free API (not expected)
- upstream: none — MLIR's design

## cmake-module-restat

- symptom: the Ninja rule CMake 4.2 writes for a scanned C++ compile has no
  `restat`, and clang writes a module interface's BMI anew on every compile
  of it; so touching an interface unit, even a comment in it, recompiles
  every unit that imports it, and every unit that imports those. Touching
  `idr/Idr.h`, TableGen's output or `lib/Mlir.cppm` recompiles every unit
  that imports anything
- sites: `foreign/idr/cmake/IdrLibrary.cmake` (the `CXX_MODULES` file set of
  every module's library) and `runtime/CMakeLists.txt` (`rt.platform`'s)
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
- sites: foreign/idr/lib/Eval/Jit.cppm (`idr-eval`)
- workaround: none: `idr-eval` builds ORC's `LLJIT`, which
  `ExecutionEngine` wraps, because it needs what the engine does not give
  (JITLink's memory manager, the session's error reports, no wrapper per
  function; upstream/execution-engine-process-symbols/README.md says
  which). It links no process symbol by default and binds the runtime's
  functions, the libm functions lowered code calls and the target entry's
  `IDRIS_MLIR_JIT_LIBRARY_CALLS` itself. The upstream fix is drafted as
  that directory's `pull-request.diff`, not carried
- retire: this entry goes once `Jit.cppm` says so in its own words: the
  `LLJIT` is the design, not a stand-in
- upstream: upstream/execution-engine-process-symbols (not yet filed); plan
  in its README: a pull request

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
- sites: foreign/idr/lib/Simplify/Prune.cppm (`idr-prune`),
  foreign/idr/lib/Simplify/Round.cppm (the round of the simplify loop)
- workaround: `upstream/remove-dead-values-unreachable/llvm.patch` (open
  pull request #208881): the pass gives the remaining uses of a dead
  argument `ub.poison`. Until the toolchain is rebuilt with it, `idr-prune`
  runs before `remove-dead-values` and empties,
  with the same analyses, every block they prove unreachable: a match
  region ends in `ub.unreachable`, a function returns poison. `symbol-dce`
  runs between them, since emptying code can leave a function nothing
  refers to, which the analysis would find unreachable in turn. Whether
  `idr-prune` stays as an optimization once it is no longer needed is
  measured then
- retire: drop the patch when the pin has #208881
- upstream: upstream/remove-dead-values-unreachable (reported by others,
  #206920, #203226); plan in its README: our reproducers to #208881

## remove-dead-values-address-taken

- symptom: at llvmorg-23.1.2, `remove-dead-values` leaves alone the
  parameters of a function that is named other than as a callee (by an
  `idr.closure` or a closure constant), but still finds a value that a
  direct call passes to one of those parameters dead when the function
  never reads it: it erases the value (a parameter of the caller, or the op
  that made it) and the call keeps a null operand ("null operand found").
  Arity raising and apply of a known closure make such direct calls
- sites: foreign/idr/lib/Simplify/Prune.cppm (`idr-prune`),
  foreign/idr/lib/Facts/Evaluation.cppm (a poison operand is no value to evaluate)
- workaround: `upstream/remove-dead-values-unreachable/llvm.patch`, which
  gives such an operand `ub.poison` (this bug has no patch of its own).
  Until the toolchain is rebuilt with it, `idr-prune`, right before
  `remove-dead-values`, makes each call of such a function pass `ub.poison`
  for every parameter the function never reads
- retire: drop the patch when the pin has #208881
- upstream: upstream/remove-dead-values-address-taken (not yet filed);
  plan in its README: its reproducer as a test of #208881

## uplift-final-counter

- symptom: at llvmorg-23.1.2, `scf::upliftWhileToForLoop`
  (`populateUpliftWhileToForPatterns`) replaces the `scf.while` result of
  the counter with its value in the last iteration, one step short of the
  value the loop ends with, and below the lower bound when the loop runs
  no iteration
- sites: foreign/idr/lib/Tail/Loops.cppm (`counterUsedAfter`);
  foreign/idr/tools/idris-mlir-opt.cc registers upstream's test pass
  `test-scf-uplift-while-to-for`, which the pinned mlir-opt lacks, for the
  reproducer
- workaround: `upstream/uplift-final-counter/llvm.patch`, main's 6e714c8d9
  (#225476) backported. Until the toolchain is rebuilt with it,
  `idr-tail-loops` uplifts a counted loop only when nothing uses the value
  its counter ends with; any other stays an `scf.while`
- retire: drop the patch when the pin has 6e714c8d9 (not on release/23.x);
  idris-mlir-opt's copy of the test pass stays while the pinned mlir-opt
  has no test passes
- upstream: upstream/uplift-final-counter (fixed on main); nothing to send

## inline-unreachable

- symptom: the upstream inliner's default `handleTerminator`
  (`DialectInlinerInterface.td`) aborts on a callee whose body ends in
  `ub.unreachable`: the `ub` dialect's inliner interface does not implement
  it, and no hook of ours sees that terminator. The inliner's region
  patterns likewise skip a region that ends in `ub.unreachable`
- sites: compiler/src/IdrisMLIR/Emit/Bodies.idr (`epilogue`),
  foreign/idr/lib/Simplify/ReturnNever.cppm (`idr::simplify::returnNever`,
  which foreign/idr/lib/Simplify/Prune.cppm and
  foreign/idr/lib/Tail/WhileDo.cppm use),
  foreign/idr/lib/Verify/Program.cppm (the program's verifier)
- workaround: `upstream/inline-unreachable-terminator/llvm.patch`
  (drafted): the inliner inlines a block that ends in a terminator that
  does not return as a block of its own, and the `ub` dialect keeps
  `ub.unreachable` as its end. Until the toolchain is rebuilt with it, no
  function body ends in `ub.unreachable`: one that never
  returns (a crash, a body Idris proved impossible, a match none of whose
  regions returns) returns `ub.poison` instead, which is never reached; the
  program's verifier refuses a body that ends in `ub.unreachable`, after
  every pass. A match region that crashes still ends in `ub.unreachable`
  and stays a region, which the lowering lowers
- retire: drop the patch when the pin's inliner handles `ub.unreachable`
- upstream: upstream/inline-unreachable-terminator (not yet filed); plan in
  its README: an issue and a pull request citing #206083

## mlir-recursion

- symptom: MLIR's textual parser and printer, and many walks, recurse once
  per level of attribute nesting, so a constant nested a few thousand deep
  overflows an 8 MiB stack with a bare SIGSEGV (6,000 levels of builtin
  array in `mlir-opt`). Compile-time evaluation builds constants as deep as
  the program's own values: a computed list of 10,000 elements is a
  constant nested 10,000 deep
- sites: foreign/idr/lib/Driver/RunOnLargeStack.cppm (`runOnLargeStack`),
  foreign/idr/tools/idris-mlir-opt.cc, foreign/idr/lib/Eval/Child.cppm,
  runtime/start.cc (`idris_rt_run_on_stack`)
- workaround: idris-mlir-cc runs the whole compilation, idris-mlir-opt
  its run, and the evaluation child its calls, on the runtime's
  reserved-stack runner: up to 2^40, 2^40 and (the child, whose calls have
  stack budgets) twice its calls' largest stack budget of address space,
  committed as touched, above a guard, so the depth is bounded by memory
  (2^40 bytes is more than a compiling machine has; reserving costs time
  in proportion to the size, at start, exit and every fork).
  Running out of it is a named error in the tools and exhaustion in the
  child. idris-mlir-reduce does not have it
- retire: when MLIR parses, prints and walks nested attributes from a
  worklist; `tests/upstream/recursive-attribute-parser` fails then. There is
  no patch: the fix is a design change across the parser, the printer and
  the sub-element walks (its README says why), so this code stays until
  upstream has it
- upstream: upstream/recursive-attribute-parser (not yet filed); plan in its
  README: an issue, then an RFC

## bytecode-deferred-quadratic

- symptom: MLIR's bytecode reader reads an attribute nested n deep in time
  quadratic in n (4.5 s for a builtin array 32,000 deep, 0.18 s from
  text). Compile-time evaluation's results are as deep as the program's
  values: a computed list of 20,000 elements took 45 s to read back
- sites: foreign/idr/lib/Eval/Encoding.cppm (`encodeResults`, `decodeResults`)
- workaround: `upstream/bytecode-deferred-quadratic/llvm.patch` (drafted):
  the reader resolves deferred entries from a stack, in linear time. Until
  the toolchain is rebuilt with it, the evaluation child sends a call's
  results as bytecode of
  a flat table of their distinct parts, each after the parts it holds,
  which it names by position; the compiler rebuilds the constants from the
  table in order. No attribute in the table is nested more than a few
  levels, and a shared part is in it once. The table may stay after the
  rebuild, as it keeps sharing without the reader's help: measure then
- retire: drop the patch when the pin's reader resolves deferred entries in
  linear time
- upstream: upstream/bytecode-deferred-quadratic (not yet filed); plan in
  its README: an issue and a pull request

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
- sites: foreign/idr/lib/Simplify/Structural.cppm (`structural`), and
  foreign/idr/lib/Simplify/Pass.cc (the loop in `runOnOperation`)
- workaround: `upstream/composite-fixed-point-sccp/llvm.patch` (drafted,
  part 1 of the report's fix): `sccp` keeps the constants the module holds.
  Until the toolchain is rebuilt with it, and for as long as the measure
  below says so, `idr-simplify` is its own loop over the round and decides the
  fixpoint by a structural hash of the module: constants by their value at
  each use, other values by their position in the walk, so a constant
  remade at another address hashes the same. Over its round budget it fails
  with `unsupported (compile-time budget)`, where the composite pass would
  warn and go on
- retire: with the patch, `composite-fixed-point-pass{pipeline=sccp}`
  converges on a module `sccp` leaves as it is. Then measure whether a
  round at its fixpoint keeps its `OperationFingerPrint`; if it does,
  `structural` goes, and the loop may be a `composite-fixed-point-pass` over
  the round once its budget can be an error and its statistics ours. Drop
  the patch when the pin's `sccp` keeps existing constants
- upstream: upstream/composite-fixed-point-sccp (not yet filed); plan in
  its README: an issue and a pull request

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
- sites: foreign/idr/lib/Vectorize/Tiles.cppm (`vectorizable`)
- workaround: `upstream/vectorize-precondition-body/llvm.patch` (drafted):
  the precondition checks a reduction's body too. Until the toolchain is
  rebuilt with it, idr-vectorize decides with the precondition and
  `linalg::hasOnlyScalarElementwiseOp` of the body, the check upstream
  makes of an all-parallel generic, before it changes anything; a generic it
  refuses stays whole, and convert-linalg-to-loops runs its body in the
  program's order. A tile of a generic it took that the vectorizer refuses
  is its error, and fails the pass
- retire: with the patch, `vectorizable` asks the precondition alone; drop
  the patch when the pin's precondition refuses such a body
- upstream: upstream/vectorize-precondition-body (not yet filed); plan in
  its README: an issue and a pull request

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
- sites: foreign/idr/lib/Narrow/Widths.cppm (`exact`)
- workaround: `upstream/int-range-narrowing-exactness/llvm.patch`: main's
  44a4dbf32 (#218495, the shift) backported, and the remainders drafted.
  Until the toolchain is rebuilt with it, idr-narrow-lanes versions a
  vectorized loop only when every
  integer op in it wider than 32 bits is an arith op whose 32-bit form
  computes the same: a shift's amount stays below 32, a signed remainder
  never sees INT32_MIN % -1, an op that reads its operands unsigned sees
  no negative word; any other loop keeps its 64-bit lanes. With the patch
  the narrowing asks this itself, and `exact` goes
- retire: when the pin has 44a4dbf32 the backported part leaves the patch;
  drop the rest when the pin's narrowing handles the remainders
- upstream: upstream/int-range-narrowing-exactness (remainders not yet
  filed); plan in its README: an issue and a pull request for them

## while-move-if-down-duplicates

- symptom: at llvmorg-23.1.2, the `scf.while` canonicalization
  `WhileMoveIfDown` replaces every use of an `scf.if` result in the
  `scf.condition` with the if's else value at the first position that
  forwards it (`mlir/lib/Dialect/SCF/IR/SCF.cpp:3464-3476`). When the
  condition forwards that result at several positions, the after-region
  arguments of the later ones keep the else value where the loop needs the
  then value: the loop computes something else
- sites: none in our code; the patch
- workaround: `upstream/while-move-if-down-duplicates/llvm.patch`, main's
  a65eb8723 (#219458) backported
- retire: drop the patch when the pin has a65eb8723 (in 24.1.0)
- upstream: upstream/while-move-if-down-duplicates (fixed on main); nothing
  to send

## forward-dataflow-callee-lookup

- symptom: at llvmorg-23.1.2, the sparse and dense forward data-flow
  analyses find the callee of every call they visit with
  `resolveCallable()`, a scan of the module's ops
  (`mlir/lib/Analysis/DataFlow/SparseAnalysis.cpp:237`,
  `DenseAnalysis.cpp:104`), so `sccp`, `int-range-optimizations`,
  `remove-dead-values` and our analyses take time quadratic in the number
  of functions: 8 to 9 percent of a compile of `k-nucleotide`
- sites: none in our code; the patch
- workaround: `upstream/forward-dataflow-callee-lookup/llvm.patch`: the
  forward analyses own a `SymbolTableCollection`, as `DeadCodeAnalysis`
  does, and resolve callees through it
- retire: drop the patch when the pin's forward analyses resolve callees
  from a symbol table (`tests/upstream/forward-dataflow-callee-lookup`
  then shows it with the pristine tools)
- upstream: upstream/forward-dataflow-callee-lookup (not yet filed); plan
  in its README: a pull request

## clang-module-layout-forward-declaration

- symptom: at llvmorg-23.1.2, clang aborts ("Cannot get layout of forward
  declarations") generating `DenseMap<Operation *, DenseSetEmpty, ...>` (a
  `SetVector<Operation *>`'s set) in a module partition that imports a
  sibling partition holding a `DenseSet<Operation *>`
- sites: foreign/idr/lib/Stack/Escape.cppm (the escape analysis's caller
  and worklist sets)
- workaround: the sets hold `func::FuncOp`, which is what they hold
- retire: when a patch or the pin lets the pinned clang compile the
  report's unit (tests/upstream/clang-module-layout-forward-declaration);
  the sets may stay typed. There is no patch yet: the crash is not reduced
- upstream: upstream/clang-module-layout-forward-declaration (not reduced
  yet); plan in its README: reduce, then file or backport

## clang-module-predeclared-new

- symptom: at llvmorg-23.1.2, clang reaches an UNREACHABLE ("predeclared
  global operator new/delete is missing") generating libc++'s
  `__libcpp_allocate` in a module unit without a global module fragment that
  builds `std::string`s from an imported wrapper of libc++
- sites: foreign/idr/lib/Driver/Retarget.cppm (`retarget`)
- workaround: the feature string is an `llvm::SmallString`
- retire: when a patch or the pin lets the pinned clang compile the
  report's unit (tests/upstream/clang-module-predeclared-new). There is no
  patch yet: the crash is not reduced
- upstream: upstream/clang-module-predeclared-new (not reduced yet; likely
  #189252); plan in its README: reduce, then add to #189252

## llvm-force-enable-stats

- symptom: `llvm/ADT/Statistic.h` makes `llvm::Statistic` a no-op when
  `NDEBUG` is defined (the release preset) and `LLVM_FORCE_ENABLE_STATS` is
  0, but the pinned MLIR library is built with assertions, where it counts:
  `Pass::Statistic`'s out-of-line constructor would write a counter into a
  one-byte member, over what follows it in the pass. A plain
  `-DLLVM_FORCE_ENABLE_STATS=1` does not help: `llvm/Config/llvm-config.h`
  defines it to 0 unconditionally, after the command line
- sites: foreign/idr/CMakeLists.txt (the compile options of idr_build, which
  every library of foreign/idr and the tools are compiled with, and of
  idris-mlir-tblgen, which links none of them),
  foreign/idr/lib/Support/EnableStatistics.h,
  foreign/idr/lib/Support/Statistics.cppm (the static_assert)
- workaround: every translation unit of foreign/idr and the tools starts
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

## darwin-ld64-tapi

- symptom: the pinned `ld64.lld` (LLVM 23.1.2) cannot read a `.tbd` whose
  `targets` list names a target it does not know. The macOS 27 SDK's
  `libSystem.tbd` names `arm64e.x1-macos` and `arm64e.x1-maccatalyst`, so
  every Darwin link against `libSystem` — the runtime's, GMP's, and every
  program's — fails with `could not load TAPI file ...: unknown target`.
  The `TextAPIReader` has a `SkipUnknownTriples` option
  (`llvm/lib/TextAPI/TextStub.cpp:402`), but `ld64.lld` never sets it
- sites: tools/bootstrap.sh — `config_file_darwin`, whose `-fuse-ld=lld`
  makes every Darwin link the pinned `ld64.lld`'s, as CMakeLists.txt's
  `arm64-apple-macosx14.0` entry does for programs (with `--icf=all`). The
  report, reproducer and check are `upstream/ld64-lld-unknown-tapi-target/`
  and `tests/upstream/ld64-lld-unknown-tapi-target/`
- workaround: `upstream/ld64-lld-unknown-tapi-target/llvm.patch`:
  release/23.x's 532fa5afb (`arm64e.x1`) backported, and
  `SkipUnknownTriples = true` in `macho::loadDylib`, so the pinned
  `ld64.lld` reads the macOS 27 SDK and the next one's. No code of ours
  stands in for it
- retire: when the pin has 532fa5afb the backported part leaves the patch;
  drop the rest when the pin's `ld64.lld` reads a stub with an unknown
  target
- upstream: `upstream/ld64-lld-unknown-tapi-target/` (not yet filed); plan
  in its README: an issue and a pull request for `SkipUnknownTriples`

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
  clang, but Idris's C support library is a shared object loaded by Chez
  Scheme, a dynamically linked process of the host's C library (glibc here,
  libSystem on macOS), which the static musl toolchain cannot build for
- sites: tools/bootstrap.sh (steps `chez` and `idris`)
- workaround: the pinned Chez Scheme and Idris 2 are built with the host's C
  compiler; they are host programs and never link into an executable
- retire: when Chez Scheme itself is built on the pinned toolchain for the
  host
- upstream: none
