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
Retired when the LLVM pin moved from `llvmorg-23.1.2` to llvm main at
7208ba24: `uplift-final-counter` (`upstream/13-uplift-final-counter`, a
backport of main's 6e714c8d9) and `while-move-if-down-duplicates`
(`upstream/14-while-move-if-down-duplicates`, a backport of main's
a65eb8723), with their reports and checks (and idris-mlir-opt's copy of
upstream's uplift test pass, which only the first's check ran), and the
backported half of `int-range-narrowing-exactness` (main's 44a4dbf32).
Retired with the same bump, which rebuilt stage 2:
`llvm-force-enable-stats` (stage 2 is built with
`LLVM_FORCE_ENABLE_STATS`, so the installed `llvm-config.h` says
statistics count to every includer; `Statistics.cppm`'s `static_assert`
stays as the check) and `llvm-cxx17-headers` (the stage-2 clang of
7208ba24 compiled every unit of `foreign/idr`, C++26 against libc++ over
LLVM's C++17 headers, with no change for the headers). Retired because
main fixed it: `clang-module-predeclared-new`
(`upstream/12-clang-module-predeclared-new`, its check and its
workaround; main's clang compiles the report's unit, where 23.1.2's
crashed, so `Driver/Retarget.cppm` builds its feature string as
`std::string` again). These retirements were observed where the pin was
first built, arm64 macOS; `make build` and the suites on each target are
their check, as for any change. Retired with the one recipe
(2026-10-09): `stage2-thinlto`. Stage 2 is not LTO on any target: its
libraries are native code that every build of our tools links as it is,
a rebuild through the compiler cache relinks without optimizing LLVM
again, and the tools' few percent of speed is not worth the bootstrap's
hours. What programs gain from LTO is untouched: idris-mlir joins the
runtime's bitcode with each program's module, and our own code's Release
build is full LTO.

The LLVM pin is a commit of llvm main, not a release: the patch we carry
for a bug we send upstream is then its pull request, one diff, not two.
It moves when a patch of ours lands upstream, or about monthly otherwise.
Each bump is one commit: the lock, the toolchain rebuilt from it by the one
recipe (`tools/bootstrap.sh`) on both targets, the full suites green on
each, and this file's sweep.

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

## remove-dead-values-unreachable

- symptom: at llvmorg-23.1.2 and on main at 7208ba24, `remove-dead-values`
  finds a function or a block unreachable (dead-code analysis never visits
  it: a private function nothing live calls, or a match region a constant
  rules out), marks every value there dead and erases the function's
  arguments, but keeps the ops that still use them, and then crashes on
  the null operand (`mlir/lib/Transforms/RemoveDeadValues.cpp:661` on main,
  the region-branch canonicalization at `:862`, `Matchers.h:491`). It drops
  the uses of a dead block argument and of a dead result the same way
- sites: foreign/idr/lib/Simplify/Round.cppm (the simplify round runs
  `remove-dead-values{canonicalize=false}`); the patch itself has no other
  site
- workaround: `upstream/06-remove-dead-values-unreachable/llvm.patch`, the
  pull request: every value the pass erases (function argument, block
  argument, result, result of an erased op) gives its remaining uses a
  ub.poison at its definition, through one helper, `replaceUsesWithPoison`;
  the pass drops no use. A call the pass erases no result of is
  `remove-dead-values-unchanged-call`'s.
  Before the patch, idr-prune emptied the
  code the analyses prove unreachable right
  before `remove-dead-values`, and `symbol-dce` ran between them; with the
  patch the two left k-nucleotide's and every-types-export's objects byte
  for byte as they were, in as many rounds and as much time, so they went.
  Emptying also did one thing more: it ended the regions a constant rules
  out in ub.unreachable, so that the match canonicalization saw a match
  whose other regions crash never complete and cut the code after it. The
  canonicalization now asks which regions a match can take (the one its
  constant scrutinee selects), so it needs no emptied region
  (foreign/idr/lib/Canon/MatchPatterns.cppm, `EndAfterNoYield`)
- retire: drop the patch when the pin has our pull request (or #208881
  together with a fix for block arguments and results)
- upstream: upstream/06-remove-dead-values-unreachable (function arguments
  reported by others, #206920, #203226, open PR #208881); plan in its
  README: a new issue and a pull request against main for all four sites

## remove-dead-values-unchanged-call

- symptom: on main at 7208ba24, `remove-dead-values` replaces every call of
  a private function that returns a value with an identical new call, even
  when it erases none of its results: it lists each such call with the
  results to erase (`mlir/lib/Transforms/RemoveDeadValues.cpp:362-376`),
  and `RewriterBase::eraseOpResults` builds a new operation even for an
  empty set (`mlir/lib/IR/PatternMatch.cpp:278-314`). The module prints the
  same, but `OperationFingerPrint` changes, so a simplify round at its
  fixpoint would never keep the fingerprint, and every program with such a
  call would run to the round budget
- sites: none in our code; the patch. The simplify round runs
  `remove-dead-values{canonicalize=false}` itself
  (foreign/idr/lib/Simplify/Round.cppm)
- workaround: `upstream/16-remove-dead-values-unchanged-call/llvm.patch`, the
  pull request: `eraseOpResults` returns the operation unchanged when it
  erases no result, as `eraseOperands` does for operands. It replaces
  `idr-dead-values`, which ran the pass on a copy and kept the module when
  the copy hashed the same up to operation identity
- retire: drop the patch when the pin has the fix (in `eraseOpResults` or in
  the pass); the round keeps running `remove-dead-values` as it is
- upstream: upstream/16-remove-dead-values-unchanged-call (not filed;
  `check-mlir` not run on main); plan in its README: an issue and a pull
  request

## elaboration-primitive-folding

- symptom: at the pinned Idris, elaboration normalises every checked term
  with `normaliseArgHoles`, whose holes-only mode leaves definitions
  applied but reduces any primitive applied to constants
  (`src/Core/Normalise/Eval.idr:548`), with Idris's own implementation on
  Chez. The checked definition this compiler consumes then holds Chez's
  value instead of the call: `prim__cast_StringInt "12.7"` is 12 where the
  runtime reads 0, a Double's text is `+inf.0` or `5e-324|1`, a Char's
  string is its escape. A literal's conversion (`normalisePrims`) runs a
  user's `fromString` the same way. The fork inherited the bug with the
  code
- sites: the fork, compiler/idris/src/Core/Normalise/Eval.idr (`evalDef`
  of a `Builtin`), compiler/idris/src/Core/Normalise.idr
  (`normalisePrims`), compiler/idris/src/Core/Primitives.idr (`sharedOp`)
  and compiler/idris/src/Core/Value.idr (`sharedPrimsOnly`). The test
  generators write literals as they are (tests/Sem.idr,
  tests/TwoLevels.idr, tests/Fuzz.idr), where they hid each behind an
  identity that Idris does not reduce
- workaround: none; the fork carries the fix as its own code, the change
  of `upstream/18-elaboration-primitive-folding/pull-request.diff` (the
  pull request against the pin): a primitive reduces where a definition
  would, not in the holes-only modes, but for `believe_me`, which computes
  nothing (without it a `Fin` literal keeps base's forged proof, and
  tests/programs/data/vect is refused as an escape hatch), and a literal's
  conversion runs only the primitives every backend computes alike
  (Integer's arithmetic and comparisons, a wrapping cast from Integer, an
  exact cast to Double, `believe_me`).
  The frontend's prelude, base and the other packages Idris ships are
  built by the fork, so they keep their calls too. The stock Idris is not
  patched: it builds only stage 0 (the fork, the frontend and the test
  runner), which does not depend on what elaboration folds, and the
  benchmarks' Chez baseline, whose programs run on the Chez whose meaning
  the fold computes
- retire: when a re-sync of the fork brings upstream's fix, the fork's
  change is upstream's; then the report, its check and this entry go; the
  generators stay as they are
- upstream: upstream/18-elaboration-primitive-folding (not filed; upstream's
  own suite not run with the change); plan in its README: an issue and a
  pull request on idris-lang/Idris2

## remove-dead-values-address-taken

- symptom: at llvmorg-23.1.2 and on main at 7208ba24, `remove-dead-values`
  leaves alone the parameters of a function that is named other than as a
  callee (by an `idr.closure` or a closure constant, or because it is
  public), but still finds a value that a direct call passes to one of
  those parameters dead when the function never reads it: it erases the
  value (a parameter of the caller, or the op that made it) and the call
  keeps a null operand ("null operand found"). Arity raising and apply of
  a known closure make such direct calls
- sites: none in our code; the patch. The poison it passes is no value
  to evaluate at compile time (foreign/idr/lib/Facts/Evaluation.cppm), as
  any poison operand is not
- workaround: `upstream/06-remove-dead-values-unreachable/llvm.patch`, which
  gives such an operand `ub.poison` (this bug has no patch of its own)
- retire: drop the patch when the pin has #208881 or our
  remove-dead-values-unreachable pull request (neither on main at 7208ba24)
- upstream: upstream/01-remove-dead-values-address-taken; its test was
  posted as a comment on #208881 on 2026-10-08
  (https://github.com/llvm/llvm-project/pull/208881#issuecomment-6073061698);
  a test-only pull request follows if #208881 lands without it

## inline-unreachable

- symptom: the upstream inliner aborts on a single-block callee whose
  body ends in `ub.unreachable`: its fast path erases the terminator and
  continues the block with the operations after the call, the hook that
  declines it (`allowSingleBlockOptimization`) is asked of the caller's
  dialect, and the `ub` dialect declines nothing and implements no
  `handleTerminator`. The inliner's region patterns likewise skip a region
  that ends in `ub.unreachable`
- sites: none in our code; the patch. A body that never returns (a crash,
  a body Idris proved impossible, a match none of whose regions returns)
  ends in `ub.unreachable`, as Emit writes it and idr-tail-loops and the
  match canonicalization leave it. The match ops and the array
  loops declare `SingleBlock`, which the inliner reads: it inlines such a
  callee into a function body, and leaves a call of it in a match region a
  call, since the block after it would be a second block of the region
- workaround: `upstream/07-inline-unreachable-terminator/llvm.patch`, the
  pull request: the hook is asked of the terminator's dialect, the `ub`
  dialect declines the fast path for `ub.unreachable` and keeps it as the
  end of its block, and the inliner pass leaves a call of such a callee in
  a region that must stay one block
- retire: drop the patch when the pin has the merged fix (not on main at
  7208ba24)
- upstream: upstream/07-inline-unreachable-terminator (not yet filed);
  plan in its README: an issue and a pull request, #206083 named as a
  separate case

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
- workaround: idris-mlir runs the whole compilation, idris-mlir-opt
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
- upstream: upstream/10-recursive-attribute-parser (not yet filed; still
  reproduces on main at 7208ba24, run on arm64 macOS); plan in its README:
  an RFC on Discourse first

## bytecode-deferred-quadratic

- symptom: at llvmorg-23.1.2 and on main at 7208ba24, whose reader is the
  same file, MLIR's bytecode reader reads an attribute nested n deep in
  time quadratic in n (3.8 s for a builtin array 32,000 deep, 0.06 s
  from text), and never returns on a file whose attributes
  refer to each other in a cycle (`AttrTypeReader::resolveEntry`,
  `mlir/lib/Bytecode/Reader/BytecodeReader.cpp:1371-1459`). Compile-time
  evaluation's results are as deep as the program's values: a computed
  list of 20,000 elements took 45 s to read back
- sites: none in our code; the patch
- workaround: `upstream/03-bytecode-deferred-quadratic/llvm.patch`: the
  reader keeps the entries waiting on a deferred parse as a path, each
  waiting on the one above it, so a chain of n deferrals takes O(n) parses
  and a cycle fails with `cyclic reference to attribute index: N`
- retire: drop the patch when the pin's reader resolves deferred entries
  in linear time and rejects cycles (the patch's two tests pass unpatched)
- upstream: upstream/03-bytecode-deferred-quadratic (not yet filed); plan in
  its README: an issue and a pull request against main, where the reader
  is unchanged

## simplify-structural-fixpoint

- symptom: `composite-fixed-point-pass` decides its fixpoint by
  `OperationFingerPrint`, a hash of the addresses of the module's ops,
  blocks and values (`mlir/lib/Transforms/CompositePass.cpp:69-103`,
  `mlir/lib/IR/OperationSupport.cpp:986-1028`), and `sccp` erases every
  constant it meets and makes an equal one, since its fresh
  `OperationFolder` is never told about the constants the module has
  (`mlir/lib/Transforms/SCCP.cpp:42-62, 77, 84-99`). A pipeline with `sccp`
  in it never has the same fingerprint twice: on a module at its fixpoint
  the composite pass runs the pipeline past `max-iterations`.
  `-mlir-print-ir-after-change` prints after `sccp` for the same reason
- sites: foreign/idr/lib/Simplify/Pass.cc (`idr-simplify`, whose loop is a
  `composite-fixed-point-pass` over the round)
- workaround: `upstream/02-composite-fixed-point-sccp/llvm.patch` (the pull
  request): `sccp` hands each constant it reaches to its `OperationFolder`
  (`insertKnownConstant`) and leaves it, so a run that propagates nothing
  keeps the module's fingerprint. `idr-simplify` runs
  `composite-fixed-point-pass` over the round, with `max-iterations` its
  `max-rounds`. A round at the fixpoint keeps the fingerprint: `sccp` no
  longer remakes constants, and `remove-dead-values` keeps a call it erases
  no result of (`remove-dead-values-unchanged-call`)
  (`tests/idr/canon/upstream-passes`, `tests/idr/loops/tail-loop`). The
  upstream pass gives its caller no hook per iteration and, with
  `on-convergence-failure=error`, an error of its own, which is not the
  user error. So `idr-simplify` keeps what is its own around it: two passes
  that change nothing open and close each round (the round count, the
  per-round trace remark, the fixpoint remark), the round's statistics
  declared from the pipeline it gives the pass, and
  `on-convergence-failure=silent`. The pass runs the pipeline once more
  past `max-iterations` before it stops and does not look at that run (its
  own test expects `test.counter = 4` for `max-iterations=3`), so a loop
  that closed more than `max-rounds` rounds ran out of its budget, which
  is `unsupported (compile-time budget)` (`tests/idr/obs/budget`). A pass
  that fails in a round, that extra one included, reports its own error,
  and the loop adds none (`tests/idr/obs/round-failure`). The upstream
  pass refuses a budget of 0 (`CompositePass.cpp:57-63`), so with
  `max-rounds=0` `idr-simplify` runs no loop and reports the budget error.
  A fixpoint within `max-rounds` rounds passes, as before; a module over
  the budget costs a round more
- retire: drop the patch when the pin's `sccp` keeps existing constants.
  The two round passes and the count go when `composite-fixed-point-pass`
  tells its caller each iteration and lets it name its failure to converge
  (neither is on main at 7208ba24)
- upstream: upstream/02-composite-fixed-point-sccp (not yet filed; still
  broken on main at 7208ba24); plan in its README: an issue and a pull
  request

## vectorize-precondition-body

- symptom: at llvmorg-23.1.2 and on main at 7208ba24,
  `linalg::vectorizeOpPrecondition` ("Return success if the operation can
  be vectorized") checks the ops of an all-parallel generic's body
  (`isElementwise`), but of a reduction's only their types and the combiner
  (`mlir/lib/Dialect/Linalg/Transforms/Vectorization.cpp:2295-2333` on
  main, `:1881-1898`). It accepts a reduction whose body holds an op that
  is not elementwise-mappable (a crash check's `scf.if`, a call), which
  `linalg::vectorize` then refuses (`:1380-1382`), after building part of
  its vector code. idr-vectorize tiled such a loop before vectorizing it, and
  its scalar tiles ran the body column by column within each group of rows
- sites: none in our code; the patch. idr-vectorize decides with the
  precondition alone (foreign/idr/lib/Vectorize/Tiles.cppm, `vectorizable`),
  before it changes anything; a generic it refuses stays whole, and
  convert-linalg-to-loops runs its body in the program's order
- workaround: `upstream/04-vectorize-precondition-body/llvm.patch`, the
  pull request: the precondition and `vectorizeOneOp` share one rule for a
  body op no hook takes (a constant or an ElementwiseMappable op), and the
  precondition checks it for every body op of every linalg op, so
  `vectorize` fails before it creates any IR
- retire: drop the patch when the pin's precondition refuses such a body
  (the pull request landing on main)
- upstream: upstream/04-vectorize-precondition-body (not yet filed; still
  broken on main at 7208ba24); plan in its README: an issue and a pull
  request

## int-range-narrowing-exactness

- symptom: upstream's narrowing
  (`arith::populateIntRangeNarrowingPatterns`) makes an elementwise op an
  op on the narrow type whenever the ranges of its operands and results fit
  it. At llvmorg-23.1.2 three narrowed ops then computed something else: a
  shift whose amount can reach the narrow width (poison there), a `remsi`
  that can see INT_MIN % -1 of the narrow type (undefined behaviour once
  `llvm.srem`, where the wide op gives 0), and a `remui` of a word that may
  be negative, which the narrow op reads as another number. Main's
  44a4dbf32 (#218495) fixed the shift. Main at 7208ba24 still has neither
  remainder check: nothing stops a `remsi` whose dividend can be the narrow
  minimum while its divisor can be -1, and the ops that read their
  operands unsigned keep `CastKind::Both`
  (`mlir/lib/Dialect/Arith/Transforms/IntRangeOptimizations.cpp:396-402`
  there)
- sites: none in our code; the patch. idr-narrow-lanes versions a
  vectorized loop when its wide integer ops fit 32 bits, and the narrowing
  of its copy leaves wide an op whose 32-bit form would compute something
  else (tests/idr/vectorize/lanes-loops, lanes-x86-64)
- workaround: `upstream/09-int-range-narrowing-exactness/llvm.patch`, the
  remainders alone: `remsi` does not narrow when the dividend's range holds
  the narrow signed minimum and the divisor's holds -1, and the unsigned
  ops get `CastKind::Unsigned`
- retire: drop the patch when the pin's narrowing handles the remainders
- upstream: upstream/09-int-range-narrowing-exactness (remainders not yet
  filed; both still broken on main at 7208ba24); plan in its README: an
  issue and a pull request

## forward-dataflow-callee-lookup

- symptom: at llvmorg-23.1.2 and on main at 7208ba24, the sparse and dense
  forward data-flow analyses find the callee of every call they visit with
  `resolveCallable()`, a scan of the module's ops
  (`mlir/lib/Analysis/DataFlow/SparseAnalysis.cpp:237`,
  `DenseAnalysis.cpp:104`), so `sccp`, `int-range-optimizations`,
  `remove-dead-values` and our analyses take time quadratic in the number
  of functions: 8 to 9 percent of a compile of `k-nucleotide`
- sites: none in our code; the patch
- workaround: `upstream/05-forward-dataflow-callee-lookup/llvm.patch`: the
  solver builds one `SymbolTableCollection` per `initializeAndRun`, the
  span over which the IR does not change, and hands it to its analyses;
  the forward analyses resolve callees through it, and `DeadCodeAnalysis`
  uses it in place of the collection it kept across runs
- retire: drop the patch when the pin's forward analyses resolve callees
  from a symbol table (`tests/upstream/forward-dataflow-callee-lookup`
  then shows it with the pristine tools)
- upstream: upstream/05-forward-dataflow-callee-lookup (not yet filed; still
  present on main at 7208ba24); plan in its README: a pull request

## pass-timing-dynamic-pipeline

- symptom: on main at 7208ba24, MLIR's pass timing nests a pipeline that a
  pass runs through `Pass::runPipeline` under the root of the report, not
  under the pass: `PassTiming::runBeforePipeline` looks for its parent in
  `parentTimerIndices`, where `runBeforePass` records adaptors alone
  (`mlir/lib/Pass/PassTiming.cpp:63-67`, `:93-94`). The pipeline's time is
  counted twice, and two pipelines on one op name, one run inside the
  other, share one timer. idr-simplify, idr-eval, idr-inline, idr-target
  and idr-canonicalize run pipelines so: without the patch, in
  `idris-mlir --mlir-timing`, their pipelines are rows of the step beside
  the pass that runs them, and a step's rows add up to more than the step
- sites: none in our code; the patch. Each step of `idris-mlir` has a
  timer of its own (foreign/idr/lib/Driver/Run.cppm), which is the root of
  the step's pass timing, so the misplaced rows stay inside the step
- workaround: `upstream/19-pass-timing-dynamic-pipeline/llvm.patch`:
  #169615's change, under which every pass records its timer for the
  pipelines it runs, and a test of ours that fails without it
- retire: drop the patch when the pin has #169615 (or another fix the
  patch's test passes with)
- upstream: upstream/19-pass-timing-dynamic-pipeline (#169443; open pull
  request #169615, whose own test passes without its change); plan in its
  README: our test as a comment on #169615, not posted yet

## clang-module-layout-forward-declaration

- symptom: at llvmorg-23.1.2, the x86_64 Linux clang aborts ("Cannot get
  layout of forward declarations") generating
  `DenseMap<Operation *, DenseSetEmpty, ...>` (a `SetVector<Operation *>`'s
  set) in a module partition that imports a sibling partition holding a
  `DenseSet<Operation *>`. The clang of 7208ba24 compiles the unit on arm64
  macOS
- sites: foreign/idr/lib/Stack/Escape.cppm (the escape analysis's caller
  and worklist sets)
- workaround: the sets hold `func::FuncOp`, which is what they hold
- retire: tests/upstream/clang-module-layout-forward-declaration runs on
  every target and expects the pinned clang to compile the report's unit.
  When it passes on every target, this entry, the report and the check go;
  the sets may stay typed. Where it fails, the crash is reduced and patched
  (there is no patch yet)
- upstream: upstream/11-clang-module-layout-forward-declaration (not reduced
  yet); plan in its README: reduce, then file it, or move the pin past a
  fix on main

## platform-gate-x86_64

- symptom: cpp-starter's gate accepts Darwin arm64 only; this project's
  two first-class targets are x86_64 Linux and arm64 macOS (the user's
  decision), built by one recipe (`tools/bootstrap.sh`) and checked by the
  same suites on each
- sites: CMakeLists.txt — the platform gate, which accepts exactly those
  two hosts, and each target entry's tool flags (`-fcf-protection=full`,
  CET, in the x86_64 Linux entry)
- workaround: accept Linux x86_64 beside cpp-starter's Darwin arm64; each
  target entry names its own hardening
- retire: never; this is a scope decision
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

## darwin-inert-mitigations

- symptom: `_FORTIFY_SOURCE` does nothing with musl (it has no fortified
  functions) or with Apple's SDK for C++, and `-mbranch-protection=standard`
  executes as NOP in plain-arm64 Darwin processes
- sites: CMakeLists.txt — the target entries' tool flags, which the
  language profile applies: none define `_FORTIFY_SOURCE`, and the arm64
  macOS entry names no branch protection
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
  compiler is the stage-2 clang of the pinned llvm-project with the pinned
  libc++, statically linked, on both targets. GCC-only diagnostics
  of the profile (`-Wduplicated-cond`, `-Wlogical-op`, `-Wuseless-cast` and
  the like) and libstdc++'s `_GLIBCXX_ASSERTIONS` have no clang spelling
- sites: CMakeLists.txt — the compiler gate (Clang, the lock's LLVM series,
  libc++, a target with an entry), the warning set, and libc++'s extensive
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
  runtimes; the pinned toolchain builds only compiler-rt's builtins, on both
  targets, and on x86_64 Linux ASan does not support static executables
- sites: CMakePresets.json, which has no `asan-ubsan` preset;
  tests/spec/cpp-starter checks that it has none
- workaround: every build keeps trap-mode UBSan (`-fsanitize=undefined
  -fsanitize-trap=all`), which needs no runtime
- retire: when a sanitizer build is worth building compiler-rt's
  sanitizers for (and, on musl, dynamic executables); the preset comes
  back then, with what it builds
- upstream: none

## musl-thread-stacks

- symptom: musl's default thread stack is 128 KiB unless the executable's
  PT_GNU_STACK asks for more; LLVM and MLIR run deep recursions on threads
  of their own
- sites: CMakeLists.txt — the x86_64 Linux target entry's tool link flags,
  `-z stack-size=8388608`
- workaround: 8 MiB, glibc's default, recorded in PT_GNU_STACK
- retire: never while the tools link musl
- upstream: none — musl's documented behaviour

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
  idris-mlir raises every runtime function to the program's CPU
  (x86-64-v3, which has it)
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
- sites: tools/bootstrap.sh (step `libc`, on musl)
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
  refuse a SHA-256 that differs, or a file the release ships that the
  pinned commit lacks or holds otherwise; the files the commit has beyond
  the release (GMP's release leaves out its development tests, and one
  x86-64 assembly file, `mpn/x86_64/addaddmul_1msb0.asm`) are named in the
  stamp. The build is the commit's files either way. When they cannot
  fetch it, they say so and the stamp records `not verified`
- retire: when the official hosts are reachable and the check has passed
  once
- upstream: none

## idris-support-host-cc

- symptom: the pinned toolchain builds everything else with the stage-2
  clang, for the target, but Idris's C support library is a shared object
  loaded by Chez Scheme, a dynamically linked process of the host's C
  library (glibc on Linux, libSystem on macOS): a host program, which on
  Linux the target's C library, musl, is not
- sites: tools/bootstrap.sh (steps `chez` and `idris`)
- workaround: the pinned Chez Scheme and Idris 2 are built with the host's C
  compiler; they are host programs and never link into an executable
- retire: when Chez Scheme itself is built on the pinned toolchain for the
  host
- upstream: none

## idris-fork

- symptom: the frontend needs upstream Idris 2's elaborator, TTC and
  package code as its own source, so that this compiler can compile it,
  but third_party/Idris2 stays unmodified (it supplies prelude, base and
  stage 0). Three upstream bugs surfaced while forking: `--clean` looked
  for TTCs one `ttc` directory too deep and removed nothing
  (`src/Idris/Package.idr`); `Core.Unify.search` is defined in
  `Core.AutoSearch`, which only the REPL imported, so a driver without the
  REPL compiled it as a hole; and `Libraries.Text.Distance.Levenshtein.compute`
  crashes ("Badly initialised matrix") when either string is empty,
  because its loops over `[1..0]` count down (latent: the strings it
  compares are names, never empty in practice). Two more are fixed in it
  too: elaboration folds a primitive applied to constants with Idris's
  own implementation (elaboration-primitive-folding); and where the
  evaluator still computes a primitive (conversion checking, a type), it
  computes a Char's text as the escape `show` writes (`cast '\n'` is
  `"\\n"`), so the proof `cast '\n' = "\n"` is refused
  (evaluator-char-text)
- sites: compiler/idris (README.md lists every deviation;
  `tools/extract-idris.sh status` prints the files that differ from the
  gitlink), compiler/idris/src/Idris/Package.idr (the `clean` path),
  compiler/idris/src/Idris/ProcessIdr.idr (imports `Core.AutoSearch`),
  compiler/idris/src/Libraries/Text/Distance/Levenshtein.idr (filled a row
  at a time, with no matrix to miss),
  compiler/idris/src/Core/{Normalise,Normalise/Eval,Primitives,Value}.idr
  (elaboration-primitive-folding), compiler/idris/src/Core/Primitives.idr
  (every operation the evaluator computes calls the primitive of its
  name, which fixes the Char's text; tests/upstream/evaluator-char-text)
- workaround: none; the fork is our code. Its deviations from upstream are
  deliberate (the REPL, IDE mode, every other code generator and the CExp
  pipeline are out of scope) except the five bug fixes, which upstream
  should take
- retire: never as a whole. Each bug fix goes when an Idris bump brings
  upstream's fix (the re-sync merge in compiler/idris/README.md shows it)
- upstream: not filed; the `clean` path, the unimported
  `Core.AutoSearch` and Levenshtein's empty strings are each an issue and
  a pull request (with a test in its `tests/`) on
  idris-lang/Idris2; elaboration's folding is
  upstream/18-elaboration-primitive-folding, and the Char's text
  upstream/20-evaluator-char-text (the one-line fix; the fork's calls by
  name are its own)
