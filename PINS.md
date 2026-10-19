<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# PINS.md — the pinned-quirk registry

One entry per pinned workaround: code or build configuration that is
deliberately other than the profile the C++ follows (upstream MLIR's
layout and conventions for foreign/idr, an in-tree dialect of headers and
.cpp; the language profile and configure gate of CMakeLists.txt, adopted
from bjornpagen/cpp-starter, for the build and the runtime) because the
pinned toolchain, platform or dependency requires it, a deliberate
deviation from that profile, or a pinned source the build takes beside
the toolchain. Each `PIN(name)` site
in the tree points at its entry here; the essay lives here, once.

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
statistics count to every includer; a `static_assert(LLVM_ENABLE_STATS)` in
idr-optimize's unit, foreign/idr/lib/Transforms/Optimize, stays as the
check) and
`llvm-cxx17-headers` (the stage-2 clang of 7208ba24 compiled every unit
of `foreign/idr`, C++26 against libc++ over LLVM's C++17 headers, with no
change for the headers). Retired because main fixed it:
`clang-module-predeclared-new` (`upstream/12-clang-module-predeclared-new`,
its check and its workaround; main's clang compiles the report's unit,
where 23.1.2's crashed, so the driver builds its feature string as a
`std::string` again). These retirements were observed where the pin was
first built, arm64 macOS; `make build` and the suites on each target are
their check, as for any change. Retired with the cutover to MLIR's layout
(2026-10-12): `mlir-cxx-api` (foreign/idr follows upstream MLIR's layout,
headers, TableGen and inheritance, as its profile, so they are no
deviation; no module wraps MLIR's headers), `zones-on-demand`
(cpp-starter's `src/` and `unsafe/` zones are no rule of that layout),
`clang-module-layout-forward-declaration` (no module partition is left in
foreign/idr, so the unit that crashed the x86_64 clang is gone),
`cmake-module-restat` (the runtime is headers and .cpp too, so no C++
module is left in the tree and no BMI is written anew),
`cmake-import-std-uuid` (no unit imports `std`, so the experimental gate
and its UUID went), `no-stdexec`
(nothing here would use senders, so there is no omission to record) and
`versions-in-lock-file` (the lock as the one source of the accepted
series is the configure gate's design, said below, not a workaround).
Retired with the pipeline cutover (2026-10-14), because nothing in the
tree reaches their bugs once the simplify rounds and their composite fixed
point are gone: `simplify-structural-fixpoint`
(`upstream/02-composite-fixed-point-sccp`),
`remove-dead-values-unchanged-call`
(`upstream/16-remove-dead-values-unchanged-call`) and
`remove-dead-values-poison-operand`
(`upstream/22-remove-dead-values-poison-operand`). Their reports stay as
submissions, each with its pull request as `pull-request.diff`, which the
bootstrap does not apply, and a check that the pin still has the bug
(upstream/README.md, **When nothing reaches the bug**).
Never carried: `bytecode-unregistered-properties`
(`upstream/25-bytecode-unregistered-properties`, found 2026-10-15). The
pinned reader reads an op written unregistered as if its properties were
a properties index; the frontend writes each op's inherent attributes in
its attribute dictionary, which the reader moves into properties, so
nothing in the tree reaches the bug. Its report, reproducer and pull
request are kept as a submission, with `tests/upstream-bytecode-unregistered-properties`
checking that the pin still has it.
Retired with the one recipe (2026-10-09): `stage2-thinlto`. Stage 2 is
not LTO on any target: its libraries are native code that every build of
our tools links as it is, a rebuild through the compiler cache relinks
without optimizing LLVM again, and the tools' few percent of speed is not
worth the bootstrap's hours. What programs gain from LTO is untouched: idris-mlir joins the
runtime's bitcode with each program's module, and our own code's Release
build is full LTO.

The LLVM pin is a commit of llvm main, not a release: the patch we carry
for a bug we send upstream is then its pull request, one diff, not two.
It moves when a patch of ours lands upstream, or about monthly otherwise.
Each bump is one commit: the lock, the toolchain rebuilt from it by the one
recipe (`tools/bootstrap.sh`) on every target, the full suites green on
each, and this file's sweep.

The accepted toolchain release series live only in `toolchain.lock.json`,
which the top-level CMake configure gate reads.

## liveness-non-forwarded-terminator

- symptom: on main at 7208ba24, liveness never revisits a region
  terminator whose operands are all non-forwarded, so they keep the
  liveness its parent's results had when it was first visited;
  `remove-dead-values` then erases the ops that define them and leaves
  ub.poison. `idr.array.yield` is such a terminator (each element is stored
  at its index): an array tabulated in a private function and read only
  through a call had every element poisoned, a silent miscompile
- sites: foreign/idr/lib/Transforms/Pipeline.cpp (remove-dead-values runs
  before idr-structure-loops); the idr ops whose regions end in
  idr.array.yield (idr.tabulate, idr.fold_last, idr.scan_last)
- workaround: `upstream/28-liveness-non-forwarded-terminator/llvm.patch`:
  `visitBranchOperand` reads the parent's results with a dependency on the
  operand's owner; checked by tests/upstream-liveness-non-forwarded-terminator
- retire: drop the patch when the pin has the fix
- upstream: upstream/28-liveness-non-forwarded-terminator; plan in its
  README: an issue and a PR with a test-dialect test
- status (2026-10-18): carried; not filed

## dead-code-nested-symbol-use

- symptom: on main at 7208ba24 (and on main on 2026-10-19), dead-code
  analysis resolves a non-call symbol use against the analysis' top, not
  the symbol table being walked, so a use in a nested table finds nothing
  and its function's callers count as all known; liveness then finds what
  the function returns dead, and `remove-dead-values` makes it return
  ub.poison. Every idr program is a symbol table nested in the module, and
  a label reached only through an idr.closure returned poison, a silent
  miscompile
- sites: foreign/idr/lib/Transforms/Pipeline.cpp (remove-dead-values on the
  program); every analysis on MLIR's solver that loads DeadCodeAnalysis
- workaround: `upstream/29-dead-code-nested-symbol-use/llvm.patch`: the use
  is resolved in the table being walked; checked by
  tests/upstream-dead-code-nested-symbol-use
- retire: drop the patch when the pin has the fix
- upstream: upstream/29-dead-code-nested-symbol-use; plan in its README: an
  issue and a PR with a remove-dead-values test
- status (2026-10-19): carried; not filed

## aarch64-sibcall-callee-pop

- symptom: on main at 7208ba24 (and on main on 2026-10-19), AArch64 lowers a
  call in tail position from a function that pops its own stack arguments
  (`tailcc`) to a C function as a sibling call, which pops nothing, so the
  caller's caller gets its stack pointer back the argument area's size too
  low. A `tailcc` function of idr-tail-calls with more arguments than the
  argument registers, ending in a runtime call, made six programs crash
  after main returned: `__idr$entry$body` reloaded its frame record 16
  bytes low and returned into the heap
- sites: foreign/idr/lib/Conversion/TailCalls.cpp and TailCallPlan.cpp
  (which functions take `tailcc`); every arm64 target
- workaround: `upstream/30-aarch64-sibcall-callee-pop/llvm.patch`: a
  function with stack arguments to pop makes no sibling call, under
  SelectionDAG and GlobalISel; checked by
  tests/upstream-aarch64-sibcall-callee-pop
- retire: drop the patch when the pin has the fix
- upstream: upstream/30-aarch64-sibcall-callee-pop; plan in its README: an
  issue and a PR with an llc test
- status (2026-10-19): carried; not filed

## cse-nested-linalg-index

- symptom: on main at 7208ba24 (and on main on 2026-10-19), cse replaces
  the `linalg.index` of a structured op nested in another's body by the
  enclosing op's index of the same dimension: `linalg.index` is `Pure` with
  no operand, and cse shares its known values across nested regions that
  are not isolated from above. An array tabulated in a tabulate's body read
  its row index for its column index after the cse that follows
  idr-bufferize, a silent miscompile (tests/linarray-rows-crash-order)
- sites: foreign/idr/lib/Transforms/StructureLoops (a tabulate in a
  tabulate's body is a linalg.generic in another's body);
  foreign/idr/lib/Transforms/Pipeline.cpp (cse after idr-bufferize)
- workaround: `upstream/56-cse-nested-linalg-index/llvm.patch`: the trait
  `DependsOnParent` on `linalg.index`, and cse's key for such an op holds
  its parent; checked by tests/upstream-cse-nested-linalg-index
- retire: drop the patch when the pin has the fix
- upstream: upstream/56-cse-nested-linalg-index; plan in its README: a PR
  that fixes issue #62644, perhaps after an RFC for the trait
- status (2026-10-19): carried; not filed

## linalg-index-int-range

- symptom: on main at 7208ba24 (and on main on 2026-10-19), `linalg.index`
  has no integer range, so the range analysis cannot bound a value computed
  from a loop's index as it bounds an `scf.for` induction variable.
  idr-narrow could not prove the naturals an array's loop body makes from
  its index small, the bodies stayed on bigs, and the vectorizer took none
  of them (tests linarray-combinators, linarray-lanes-exact,
  linarray-lanes-wide, determinism-threads-linarray-lanes)
- sites: foreign/idr/lib/Transforms/Narrow (the range analysis after
  idr-structure-loops); foreign/idr/lib/Driver/Register.cpp, which
  registers the model
- workaround: `upstream/57-linalg-index-int-range/llvm.patch`: an external
  model of `InferIntRangeInterface` for `linalg.index`, [0, extent - 1],
  promised by the Linalg dialect; checked by
  tests/upstream-linalg-index-int-range
- retire: drop the patch, and the registration in Register.cpp, when the
  pin has the fix (in ODS, the registration goes with it)
- upstream: upstream/57-linalg-index-int-range; plan in its README: a PR
  with a Linalg int-range test
- status (2026-10-19): carried; not filed

## remove-dead-values-unreachable

- symptom: at llvmorg-23.1.2 and on main at 7208ba24, `remove-dead-values`
  finds a function or a block unreachable (dead-code analysis never visits
  it: a private function nothing live calls, or a match region a constant
  rules out), marks every value there dead and erases the function's
  arguments, but keeps the ops that still use them, and then crashes on
  the null operand (`mlir/lib/Transforms/RemoveDeadValues.cpp:661` on main,
  the region-branch canonicalization at `:862`, `Matchers.h:491`). It drops
  the uses of a dead block argument and of a dead result the same way
- sites: foreign/idr/lib/Transforms/Pipeline.cpp (the pipeline runs
  `remove-dead-values{canonicalize=false}` once, after idr-optimize); the
  patch itself has no other site
- workaround: `upstream/06-remove-dead-values-unreachable/llvm.patch`, the
  pull request: every value the pass erases (function argument, block
  argument, result, result of an erased op) gives its remaining uses a
  ub.poison at its definition, through one helper, `replaceUsesWithPoison`;
  the pass drops no use. Nothing of ours empties the code
  the analyses prove unreachable: the match canonicalization asks which
  regions a match can take (the one its constant scrutinee selects), so it
  cuts the code after a match whose other regions never complete without
  an emptied region (foreign/idr/lib/IR/Canon/MatchPatterns.cpp,
  `EndAfterNoYield`)
- retire: drop the patch when the pin has our pull request (or #208881
  together with a fix for block arguments and results)
- upstream: upstream/06-remove-dead-values-unreachable (function arguments
  reported by others, #206920, #203226, open PR #208881); plan in its
  README: a new issue and a pull request against main for all four sites
- status (2026-10-15): #208881 merged on main 2026-10-12 (0edf6243); the
  PR is to be rebased onto main for the block-argument, result and
  erased-op cases. Retire when the pin is past 0edf6243 and has the
  rebased PR.

## cse-statistic-assignment

- symptom: on main at 7208ba24, `CSE::runOnOperation`
  (`mlir/lib/Transforms/CSE.cpp:46-47`) assigns each run's counts to its
  `num-cse'd`/`num-dce'd` statistics instead of accumulating them, so a
  nested CSE's reported total is the last function's count of each
  clone: `tests/determinism-threads-*` compare one module's statistics
  under one thread and under many and fail (234 under many, 0 under one,
  on rbtree), the module itself identical
- sites: none in our code; the patch. CSE runs nested in idr-optimize's
  per-function pipeline (foreign/idr/lib/Transforms/Optimize) and in the
  pipeline's cleans (foreign/idr/lib/Transforms/Pipeline.cpp)
- workaround: `upstream/23-cse-statistic-assignment/llvm.patch`: CSE
  accumulates, with a test of the total under one thread and many
- retire: drop the patch when the pin has the fix
- upstream: upstream/23-cse-statistic-assignment (not filed); plan in
  its README: one pull request, no issue

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
  generators write literals as they are (harness/Sem.idr,
  harness/TwoLevels.idr, harness/Fuzz.idr), where they hid each behind an
  identity that Idris does not reduce
- workaround: none; the fork carries the fix as its own code, the change
  of `upstream/18-elaboration-primitive-folding/pull-request.diff` (the
  pull request against the pin): a primitive reduces where a definition
  would, not in the holes-only modes, but for `believe_me`, which computes
  nothing (without it a `Fin` literal keeps base's forged proof, and
  tests/vect is refused as an escape hatch), and a literal's
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
- upstream: upstream/18-elaboration-primitive-folding; nothing is sent,
  since Idris takes no tool-written contribution (upstream/README.md,
  **Idris**); its diff records the change for re-syncs

## termination-closure

- symptom: at the pinned Idris, a termination check (`calcTerminating`,
  `src/Core/Termination/SizeChange.idr`) closes the size-change graphs over
  every path between every pair of the unchecked functions the checked one
  reaches, and records only that one's verdict. A `total` function calling
  into a large `covering` part of a program pays for all of it, and every
  other caller pays again: `Reach.idr` (a chain of 160) takes 33.8 s. The
  translator asks for the termination of each definition it translates,
  and the fork's own sources are `covering`, so the self-compile stalled
  at `Core.Context.prettyName`. The fork inherited the bug with the code
- sites: the fork, compiler/idris/src/Core/Termination/SizeChange.idr
  (`insideComponents`, `settle`, `addCases`, `calcTerminating`)
- workaround: none; the fork carries the fix as its own code, the change
  of `upstream/21-termination-closure/pull-request.diff` (the pull request
  against the pin): the closure runs over the calls inside strongly
  connected components, which gives the same graphs from each function to
  its own component in the same order, so every verdict and message is
  unchanged; and a successful search records as terminating every function
  it visited whose verdict no later check could change. The stock Idris is
  not patched: it builds only stage 0 and the benchmarks' Chez baseline.
  The translator itself no longer asks this check (it decides whether every
  loop through a definition terminates per component, `Recursion`); the
  elaborator's checks of `total` code still do
- retire: when a re-sync of the fork brings upstream's fix, the fork's
  change is upstream's; then the report, `tests/upstream-termination-closure`
  and this entry go
- upstream: upstream/21-termination-closure; nothing is sent, since Idris
  takes no tool-written contribution (upstream/README.md, **Idris**); its
  diff records the change for re-syncs

## erased-coverage-nested-match

- symptom: at the pinned Idris, the compile-time tree of a quantity-0
  definition splits an argument its clauses leave to unification before
  the patterns that fix it; `0 fp : All IsF ws -> All Pr ws` is reported
  not covering. The fork inherited it
- sites: the fork, Core/Context/Context.idr (`Clause`), TTImp/ProcessDef.idr
  (`unifiedArgs`), TTImp/ProcessTransform.idr (its clause's marks); the case
  builder's order is relevant-implicit-split's
- workaround: none; the fork carries the change of
  upstream/50-erased-coverage-nested-match/pull-request.diff, the first of
  the series 50, 52, 53. The stock Idris is not patched: nothing it builds
  meets the bug
- retire: when a re-sync brings upstream's fix; then the report,
  tests/upstream-erased-coverage-nested-match and this entry go
- upstream: nothing is sent (upstream/README.md, **Idris**)

## totality-unimported-callee

- symptom: at the pinned Idris a `total` function reaching a looping
  `covering` function through a module its module does not import is
  accepted: the module's context holds only what its imports make visible,
  and `resolveCall` (`src/Core/Termination/SizeChange.idr`) drops a callee
  it does not hold. The fork inherited it (its `--check` accepted the
  reproducer's LC)
- sites: the fork, compiler/idris/src/Core/Termination/{References,SizeChange,Positivity}.idr,
  Core/Context.idr (`Unimported`), Core/Binary.idr (extra data as a blob,
  `readDefinitions`, `ttcVersion`), Idris/ProcessIdr.idr (`readModule`)
- workaround: none; the fork carries the fix as its own code, the change of
  `upstream/51-totality-unimported-callee/pull-request.diff`: the check
  reads a callee the context does not hold from the modules its imports
  reach, into a table the elaborator never sees, and refuses one no loaded
  module defines. The stock Idris is not patched (stage 0 only) and still
  accepts the reproducer
- retire: when a re-sync of the fork brings upstream's fix; then the report,
  `tests/upstream-totality-unimported-callee` and this entry go
- upstream: upstream/51-totality-unimported-callee; nothing is sent
  (upstream/README.md, **Idris**); its diff records the change for re-syncs

## relevant-implicit-split

- symptom: at the pinned Idris, the coverage tree of a definition splits an
  argument its clauses leave to unification before the patterns that fix
  it, at every quantity; `fp4 : {ws : List W} -> All IsF ws -> All Pr ws`
  is reported not covering. The fork inherited it, and
  erased-coverage-nested-match's first change, which took such an argument
  as a variable, refused `0 liftedBad0`, whose later argument's type needs
  the split
- sites: the fork, Core/Case/CaseBuilder.idr (`Origin`, `Use`, `arrange`:
  at every step of the match an argument no clause tests and some clause
  leaves to unification is split last, and `Source`: every part of a
  pattern unification found keeps that origin when the tree splits it),
  TTImp/ProcessDef.idr (`saved`: the
  tree a running definition keeps is built without the marks)
- workaround: none; the fork carries the change of
  upstream/52-relevant-implicit-split/pull-request.diff, applied after
  50's. The stock Idris is not patched: nothing it builds meets the bug
- retire: with erased-coverage-nested-match, when a re-sync brings
  upstream's fix; then the report, tests/upstream-relevant-implicit-split
  and this entry go
- upstream: nothing is sent (upstream/README.md, **Idris**)

## constructor-implicit-mark

- symptom: at the pinned Idris, a constructor's implicit a pattern leaves
  out, solved by unification, keeps no mark in the checked clause, so the
  case tree splits it before the field that fixes it; `v1 (C1 (ItIsF ::
  [])) = ()` is reported not covering. The fork inherited it
- sites: the fork, TTImp/Elab/{App,As,Check}.idr, TTImp/Elab.idr,
  TTImp/ProcessDef.idr (`unifiedArgs`): a left-out implicit is bound as an as-pattern over its hole, the one mark
  erased-coverage-nested-match reads, and the mark is dropped where the
  hole is a variable
- workaround: none; the fork carries the change of
  upstream/53-constructor-implicit-mark/pull-request.diff, applied after
  52's; it also carries erased-constant-pattern. The stock Idris is not
  patched: nothing it builds meets the bug
- retire: when a re-sync brings upstream's fix; then the report,
  tests/upstream-constructor-implicit-mark and this entry go
- upstream: nothing is sent (upstream/README.md, **Idris**)

## erased-constant-pattern

- symptom: at the pinned Idris, the case tree of a quantity-0 definition
  takes a constant or type a clause writes on an erased argument as a
  variable: `0 h : (0 n : Integer) -> Integer; h 0 = 1; h _ = 2` reports
  `h _` unreachable and proves `h 5 = 1`. The fork inherited it
- sites: the fork, Core/Case/CaseBuilder.idr (`getClauseType`: at quantity
  0 a pattern the clause writes splits)
- workaround: none; the fork carries it in
  upstream/53-constructor-implicit-mark/pull-request.diff. The stock Idris
  is not patched: nothing it builds meets the bug
- retire: when a re-sync brings upstream's fix; then the report,
  tests/upstream-erased-constant-pattern and this entry go
- upstream: nothing is sent (upstream/README.md, **Idris**)

## lazy-case-scrutinee

- symptom: at the pinned Idris, a case block or an if where a `Lazy t` is
  expected delays each alternative and not the block, so its scrutinee is
  computed where the argument is built: `pick (case boom 1 of ...)` with
  `pick : Lazy Int -> Int` that never forces it runs `boom 1`. The fork
  inherited it
- sites: the fork, TTImp/Elab/Case.idr (`checkCaseExpected`: a block at a
  delayed type is elaborated as a delay of the block) and
  TTImp/Elab/Lazy.idr (`checkDelayAt`, the one elaborator of a delay)
- workaround: none; the fork carries the change of
  upstream/55-lazy-case-scrutinee/pull-request.diff. The stock Idris is
  not patched: nothing it builds meets the bug
- retire: when a re-sync brings upstream's fix; then the report,
  tests/upstream-lazy-case-scrutinee and this entry go
- upstream: nothing is sent (upstream/README.md, **Idris**)

## remove-dead-values-address-taken

- symptom: at llvmorg-23.1.2 and on main at 7208ba24, `remove-dead-values`
  leaves alone the parameters of a function that is named other than as a
  callee (by an `idr.closure` or a closure constant, or because it is
  public), but still finds a value that a direct call passes to one of
  those parameters dead when the function never reads it: it erases the
  value (a parameter of the caller, or the op that made it) and the call
  keeps a null operand ("null operand found"). Arity raising and apply of
  a known closure make such direct calls
- sites: none in our code; the patch
- workaround: `upstream/06-remove-dead-values-unreachable/llvm.patch`, which
  gives such an operand `ub.poison` (this bug has no patch of its own)
- retire: drop the patch when the pin has #208881 or our
  remove-dead-values-unreachable pull request (neither on main at 7208ba24)
- upstream: upstream/01-remove-dead-values-address-taken; its test was
  posted as a comment on #208881 on 2026-10-08
  (https://github.com/llvm/llvm-project/pull/208881#issuecomment-6073061698);
  a test-only pull request follows if #208881 lands without it
- status (2026-10-15): retire when the pin is past 0edf6243, which fixed
  01's test as #208881 stood on 2026-10-08; the test-only PR is due.

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
  match canonicalization leave it. idr-optimize inlines with upstream's
  `mlir::inlineCall` (foreign/idr/lib/Transforms/Optimize), whose fast
  path the patch fixes. The match ops declare `SingleBlock`, which the
  inliner reads: such a callee is inlined into a function body, and a call
  of it in a match region stays a call, since the block after it would be
  a second block of the region
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
  array in `mlir-opt`)
- sites: foreign/idr/include/idr/Support/Stack.h (the tools' stack, its
  guard and `runTool`); foreign/idr/lib/Driver/Main.cpp,
  foreign/idr/tools/idris-mlir-opt.cpp, foreign/idr/tools/idris-mlir-reduce.cpp
  (each through `runTool`); runtime/Start/Runner.cpp (`idris_rt_run_on_stack`)
- workaround: idris-mlir runs the whole compilation, and idris-mlir-opt and
  idris-mlir-reduce their runs, on the runtime's reserved-stack runner: 2^40
  bytes of address space,
  committed as touched, above a guard, so the depth is bounded by memory
  (2^40 bytes is more than a compiling machine has; reserving costs time
  in proportion to the size, at start and exit). Running out of it is a
  named error
- retire: when MLIR parses, prints and walks nested attributes from a
  worklist; `tests/upstream-recursive-attribute-parser` fails then. There is
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
  `mlir/lib/Bytecode/Reader/BytecodeReader.cpp:1371-1459`). A list
  constant of 20,000 elements took 45 s to read back
- sites: none in our code; the patch. The frontend hands idris-mlir its
  module as bytecode, which the driver reads as it reads text
- workaround: `upstream/03-bytecode-deferred-quadratic/llvm.patch`: the
  reader keeps the entries waiting on a deferred parse as a path, each
  waiting on the one above it, so a chain of n deferrals takes O(n) parses
  and a cycle fails with `cyclic reference to attribute index: N`
- retire: drop the patch when the pin's reader resolves deferred entries
  in linear time and rejects cycles (the patch's two tests pass unpatched)
- upstream: upstream/03-bytecode-deferred-quadratic (not yet filed); plan in
  its README: an issue and a pull request against main, where the reader
  is unchanged

## vectorize-precondition-body

- symptom: at llvmorg-23.1.2 and on main at 7208ba24,
  `linalg::vectorizeOpPrecondition` ("Return success if the operation can
  be vectorized") checks the ops of an all-parallel generic's body
  (`isElementwise`), but of a reduction's only their types and the combiner
  (`mlir/lib/Dialect/Linalg/Transforms/Vectorization.cpp:2295-2333` on
  main, `:1881-1898`). It accepts a reduction whose body holds an op that
  is not elementwise-mappable (a crash check's `scf.if`, a call), which
  `linalg::vectorize` then refuses (`:1380-1382`), after building part of
  its vector code. A schedule that tiles such a loop before vectorizing it
  leaves scalar tiles that run the body column by column within each group
  of rows
- sites: none in our code; the patch. The vectorization schedule's
  `transform.idr.vectorize_lanes` decides with the precondition alone
  (foreign/idr/lib/Target/Schedules.cpp), before it changes anything; a
  generic it refuses stays whole, and convert-linalg-to-loops runs its
  body in the program's order. A tile the precondition accepts and
  `linalg::vectorize` then refuses would be an internal error there
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
  else (tests/linarray-lanes-exact)
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
  from a symbol table (`tests/upstream-forward-dataflow-callee-lookup`
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
  other, share one timer. idr-optimize (its per-function pipeline), idr-rc,
  idr-narrow, idr-returned-arguments and idr-tail-calls run pipelines so:
  without the patch, in `idris-mlir --mlir-timing`, their pipelines are
  rows beside the pass that runs them, and the rows add up to more than
  the pass
- sites: none in our code; the patch. idris-mlir runs one pass manager
  (foreign/idr/lib/Driver/Run.cpp), whose timing is the report
- workaround: `upstream/19-pass-timing-dynamic-pipeline/llvm.patch`:
  #169615's change, under which every pass records its timer for the
  pipelines it runs, and a test of ours that fails without it
- retire: drop the patch when the pin has #169615 (or another fix the
  patch's test passes with)
- upstream: upstream/19-pass-timing-dynamic-pipeline (#169443; open pull
  request #169615, whose own test passes without its change); plan in its
  README: our test as a comment on #169615, not posted yet

## one-shot-module-function-interface

- symptom: on main at 7208ba24, One-Shot Module Bufferize knows only the
  func dialect: it collects `func::FuncOp` and walks `func::CallOp`
  (`mlir/lib/Dialect/Bufferization/Transforms/OneShotModuleBufferize.cpp:315-378`),
  keys `FuncAnalysisState` by `func::FuncOp` (`FuncBufferizableOpInterfaceImpl.h:57-70`),
  writes its boundary models on func's ops (`FuncBufferizableOpInterfaceImpl.cpp:162-535`)
  with their queries `static`, and its function-argument type converter
  takes a `func::FuncOp` (`BufferizableOpInterface.h:271-273`). It refuses a
  function none of whose blocks returns (`:139-145`), which every function
  that only crashes is. A call result is writable whatever its callee
  returns (`BufferizableOpInterface.td:460-466`), so a caller writes in place
  a constant's global or a heap array a callee returns. Empty tensor
  elimination sees function boundaries only on a `ModuleOp`
  (`EmptyTensorElimination.cpp:210`), and `getGlobalFor` puts a constant's
  global in the enclosing `ModuleOp` (`BufferUtils.cpp:105`), outside
  idr.program, where its `memref.get_global` does not find it and a pass on
  the program may not write. Functions on a cycle of calls are not analyzed
  (`OneShotModuleBufferize.cpp:515-529`), so a call into the cycle reads,
  writes and aliases every operand, and with the non-writable results each
  level of a recursion copies its callee's result
- sites: none in our code; the patch. idr-bufferize (foreign/idr/lib/Transforms/Bufferize)
  runs the module driver on idr.program, attaches upstream's
  `func_ext::FuncOpBufferizableModel`, `CallOpBufferizableModel` and
  `ReturnOpBufferizableModel` to idr.func, idr.call and idr.return, and runs
  empty tensor elimination on a module analysis of its own
- workaround: `upstream/24-one-shot-module-function-interface/llvm.patch`, four
  pull requests in one diff: a reland of upstream's reverted #110322 (the
  driver, its state, the models and the type converter on
  `FunctionOpInterface`, `CallOpInterface` and `ReturnLike`; the functions
  limited to function ops with a `BufferizableOpInterface` implementation,
  so a `transform.named_sequence`, the revert's cause, stays an other op;
  the models public templates and their queries exported; a function that
  never returns analyzed with no aliasing result); the strongly connected
  components of the call graph, with each cycle's boundaries iterated to a
  fixpoint (`analyzeCallCycle`, one `FuncBoundaryFacts` per function); the
  return values that
  may not be writable recorded per function and read by the call model's
  `isWritable`, with a value that definitely aliases one of its op's
  operands writable on its own (`OneShotAnalysisState::isWritable` asked
  the op even then, so a call result equivalent to an argument was copied
  before a write); and the nearest symbol table for empty tensor elimination's
  module analysis and for a constant's global
- retire: drop each part when the pin carries upstream's fix for it; the
  patch goes when all have (`tests/upstream-one-shot-module-function-interface`
  then passes with the pristine tools); the models stay upstream's templates
- upstream: upstream/24-one-shot-module-function-interface (not filed; not
  built; upstream main is the pin's at 2026-10-14); plan in its README:
  four pull requests, the reland of #110322 first, cycles second

## eliminate-duplicate-functions

- symptom: upstream's `duplicate-function-elimination` works on
  `func::FuncOp` alone and merges in one round, so callers that differ
  only in which copy they call stay apart
  (`mlir/lib/Dialect/Func/Transforms/DuplicateFunctionElimination.cpp:23-48`)
- sites: foreign/idr/lib/Transforms/Deduplicate/EliminateDuplicateFunctions.cpp,
  a port; foreign/idr/lib/Transforms/Deduplicate/Equivalence.cpp, ours, its
  comparison
- workaround: the port of Modular's
  `Mojo/lib/Transforms/EliminateDuplicateFunctions.cpp`, taken at revision
  `9211931` (`third_party/modular`, a reference submodule: shallow, `update = none`, so a plain checkout does not fetch it; `git submodule update --init third_party/modular` does), Apache-2.0 WITH LLVM-exception, its
  header kept. What changed: it runs on idr.func; KGEN's call graph
  (Mojo's `CallGraphUtils.h`) is a graph of every symbol reference, and
  AsyncRT's dependency chains are waves by height over the graph's
  components (`llvm::scc_iterator`, as Modular's), renamed and hashed in
  parallel on MLIR's thread pool, classes formed serially in module
  order; its comparison is ours (the facts but the name and `instance`,
  the body op for op, locations aside, a function that refers to itself
  matched with one that does too); a function is merged only when every
  use of it may be renamed, every use is renamed and the copies are
  erased; the kept function takes every member's location. The
  lexicographically smallest member kept and the external node that
  reaches every function are Modular's
- retire: when the pin carries upstream's `duplicate-function-elimination`
  generalized to `FunctionOpInterface`, merging transitively in one pass,
  with a hook for the facts that must match: then the port goes and the
  pass runs upstream's. Re-read against Modular when the submodule moves
- upstream: the generalization is planned (the pipeline cutover's proposal
  at 484d6403, §7 item 1), not written

## platform-gate

- symptom: the adopted profile's gate accepts Darwin arm64 only; this
  project's first-class targets are arm64 macOS, arm64 Linux at 16 KiB and
  at 4 KiB pages, and x86_64 Linux (the owner's decision), built by one
  recipe (`tools/bootstrap.sh`) and checked by the same suites on each
- sites: CMakeLists.txt — the platform gate, which accepts exactly their
  hosts, Linux x86_64 and aarch64 and Darwin arm64, and each target
  entry's tool flags (`-fcf-protection=full`, CET, in the x86_64 Linux
  entry; `-mbranch-protection=standard` in the arm64 Linux entries)
- workaround: accept those hosts; each target entry names its own
  hardening
- retire: never; this is a scope decision
- upstream: none

## darwin-inert-mitigations

- symptom: `_FORTIFY_SOURCE` does nothing with Apple's SDK for C++, and
  `-mbranch-protection=standard` executes as NOP in plain-arm64 Darwin
  processes
- sites: CMakeLists.txt — the target entries' tool flags, which the
  language profile applies: the arm64 macOS entry defines no
  `_FORTIFY_SOURCE` and names no branch protection, which the Linux
  entries, where both are live, do
- workaround: select the live mitigations in CMake, never behind a C++ `#ifdef`
- retire: never; platform ABI facts
- upstream: none

## clang-libcxx

- symptom: the adopted profile is GCC with libstdc++; this project's
  compiler is the stage-2 clang of the pinned llvm-project with the pinned
  libc++, statically linked, on every target. GCC-only diagnostics
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
  runtimes; the pinned toolchain builds only compiler-rt's builtins, on
  every target
- sites: CMakePresets.json, which has no `asan-ubsan` preset;
  tests/mlir-layout checks that it has none
- workaround: the hardened preset builds our tools with trap-mode UBSan
  (`-fsanitize=undefined -fsanitize-trap=all`), which needs no runtime
- retire: when a sanitizer build is worth building compiler-rt's
  sanitizers for; the preset comes back then, with what it builds
- upstream: none

## runtime-quarantine

- symptom: the runtime links into every program and into idris-mlir, whose
  folders call it, so it cannot take the tools' profile: a program links no
  C++ library, and idris-mlir joins the runtime's bitcode with each
  program's module. It is C++ over vendored header libraries (snmalloc,
  simdutf, fast_float) and exports a C ABI (`idris_rt.h`)
- sites: `runtime/`, every source there
- workaround: the runtime is built with its own profile (no exceptions, no
  RTTI, no C++ library at link time, its bitcode carried as the target
  entry says: fat LTO objects on ELF, the vendored headers as system
  headers) and checked by `check-archive.sh`
- retire: never; every program links it
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

- symptom: simdutf picks its implementation itself on first use: from the
  environment variable `SIMDUTF_FORCE_IMPLEMENTATION` when it is set, so a
  program's string checks could depend on its environment, and otherwise by
  its own processor detection, cpuid and xgetbv in inline assembly
  (`include/simdutf/internal/isadetection.h:281,296`) over a feature mask in
  which AVX512VPOPCNTDQ and AVX512CD share a bit (`:113,117`), so it can
  choose the icelake kernel on a processor without VPOPCNTDQ, which that
  kernel executes
- sites: runtime/Strings/Simd.cpp; `runsSimdutf` in the target entry's
  processor file (runtime/Platform/X86_64/Cpu.cpp,
  runtime/Platform/Aarch64/Cpu.cpp)
- workaround: the runtime takes the first implementation of
  `get_available_implementations()`, simdutf's priority order, for which the
  target's processor file says the processor has every feature of the
  target region its kernels are compiled in, tested with
  `__builtin_cpu_supports` as the startup check tests a program's features,
  and calls that implementation's methods directly. Reading the list and the
  names runs no detection; `detect_best_supported`,
  `supported_by_runtime_system` and the free functions that dispatch through
  `get_active_implementation` are never called, so nothing in the tree
  reaches simdutf's cpuid or the shared bit. On arm64 the one implementation
  is arm64 (NEON, the baseline)
- retire: never; deliberate: the feature decision has one owner, the
  target's startup check
- upstream: upstream/48-simdutf-avx512vpopcntdq-bit (the shared bit; a
  submission, not carried)

## snmalloc-arm-yield-asm

- symptom: snmalloc's Arm AAL spins with inline assembly,
  `__asm__ volatile("yield")` in `AAL_arm::pause()`
  (third_party/snmalloc/src/snmalloc/aal/aal_arm.h:53-60), where the runtime
  reaches the processor through intrinsics only; every snmalloc spin loop
  the runtime meets on arm64 runs it. No configuration macro or AAL the
  build can select replaces it: aal.h takes aal_arm.h for every Arm target,
  and `pause()` takes `__yield()` only under MSVC
- sites: third_party/snmalloc, compiled by runtime/Alloc/Cells.cpp
- workaround: none; the assembly is carried as snmalloc writes it, since
  snmalloc is no patch project of tools/patches.sh. The fix, one
  `#elif __has_builtin(__builtin_arm_yield)` branch that emits the same
  instruction as an intrinsic, is a submission
- retire: when the snmalloc pin moves past upstream's change
- upstream: upstream/49-snmalloc-arm-yield-intrinsic (not filed)
## mirrored-sources

- symptom: GMP's official host (gmplib.org) is unreachable here; the
  submodule is a clone of a GitHub mirror (arthenica/gmp)
- sites: .gitmodules, toolchain.lock.json (`release`, `release_sha256`),
  tools/bootstrap.sh (`verify_release`)
- workaround: it is pinned by commit to its release tag; the lock records
  the official release tarball and its SHA-256 (as buildroot and Homebrew
  publish it). The gmp step fetches the tarball when it can and
  refuse a SHA-256 that differs, or a file the release ships that the
  pinned commit lacks or holds otherwise; the files the commit has beyond
  the release (GMP's release leaves out its development tests, and one
  x86-64 assembly file, `mpn/x86_64/addaddmul_1msb0.asm`) are named in the
  stamp. The build is the commit's files either way. When it cannot
  fetch it, it says so and the stamp records `not verified`
- retire: when the official host is reachable and the check has passed
  once
- upstream: none

## idris-support-host-cc

- symptom: the pinned toolchain builds everything else with the stage-2
  clang, for the target, but Idris's C support library is a shared object
  loaded by Chez Scheme, a dynamically linked process of the host's C
  library (glibc on Linux, libSystem on macOS): a host program
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
  name, which fixes the Char's text; tests/upstream-evaluator-char-text)
- workaround: none; the fork is our code. Its deviations from upstream are
  deliberate (the REPL, IDE mode, every other code generator and the CExp
  pipeline are out of scope) except the five bug fixes, which upstream
  should take
- retire: never as a whole. Each bug fix goes when an Idris bump brings
  upstream's fix (the re-sync merge in compiler/idris/README.md shows it)
- upstream: nothing is sent, since Idris takes no tool-written
  contribution (upstream/README.md, **Idris**); the `clean` path, the
  unimported `Core.AutoSearch` and Levenshtein's empty strings are the
  fork's own fixes, which a re-sync checks against upstream's code;
  elaboration's folding is upstream/18-elaboration-primitive-folding, and
  the Char's text upstream/20-evaluator-char-text (the one-line fix; the
  fork's calls by name are its own)
- totality: the fork's own code bounds no recursion by a count.
  `normaliseTypes` follows each name once (it stopped at a depth of 8). The
  size-change decision (`loopsTerminate`) works on dense graphs typed by
  their path's ends (`Dense n from to`), joined only in path order by
  `andThen`, so a path cannot be composed backwards; the graphs' rows are a
  finite type (`Libraries.Data.List.Finite`: `Finite`, `NoDup`, the
  pigeonhole principle); it keeps each graph and each function-and-graph
  pair once, and collects a loop graph's powers until one repeats, finding
  the idempotent power among them (it searched at most 1024 and counted one
  not found as failing); each search's measure is the room left, so
  `loopsTerminate` is total. Sites:
  compiler/idris/src/Core/Normalise/Eval.idr (`computesType`),
  compiler/idris/src/Core/Termination/SizeChange.idr (`Dense`, `andThen`,
  `Calls`, `Kept`, `powers`, `nonDescending`, `loopsBack`, `search`,
  `loopsTerminate`), compiler/idris/src/Libraries/Data/List/Finite.idr; its
  check is tests/fork-loops-terminate

## linear-ambiguous-let

- symptom: at the pinned Idris, a `let` (pattern or plain) whose value
  applies a name with several candidates to a linear variable is refused
  ("can't find any elaboration which works ... Trying to use linear name h
  in non-linear context") although exactly one candidate fits at
  multiplicity one: the retry at one recognised a bare `LinearMisuse`
  (`checkCase`) or one seen through `InType`/`InCon`/`InLHS`/`InRHS`
  (`checkLet`), never the `AllFailed` of an ambiguous name. libs/mlir-array
  wrote `LArray.shape` qualified because of it. The fork inherited the bug
  with the code
- sites: compiler/idris/src/TTImp/Elab/{Delayed (`misusesLinear`), Case
  (`checkCaseDelayed`), Binders (`checkLet`)}.idr
- workaround: none; the fork carries the fix as its own code, the change of
  `upstream/fork-linear-ambiguous-let/pull-request.diff` (against the pin,
  with upstream test `linear021`). The stock Idris is not patched: it builds
  only stage 0 and the benchmarks' Chez baseline
- retire: when a re-sync brings upstream's fix; then the report and this
  entry go
- upstream: upstream/fork-linear-ambiguous-let; nothing is sent
  (upstream/README.md, **Idris**)

## totality-depth

- symptom: at the pinned Idris, whether a recursion is total depends on
  `%totality_depth` (default 5): `sizeCompare` looks under matching
  constructors on both sides only that deep, a count bounding a search that
  is exponential without it, so `deep` in
  `upstream/fork-totality-depth/Depth.idr` is refused and accepted after
  `%totality_depth 7`; and an as pattern's sides kept the first known
  answer, so an answer could weaken with depth. The fork inherited it; the
  frontend reaches it through `checkTerminating`
- sites: compiler/idris/src/Core/Termination/CallGraph.idr (`Step`,
  `SizeMemo`, `sizeCompare`, `compareNew`, `compareRoot`),
  compiler/idris/src/Core/{Options,Context}.idr,
  compiler/idris/src/Idris/{Syntax,Desugar,Parser}.idr
- workaround: none; the fork carries the change of
  `upstream/fork-totality-depth/pull-request.diff`: each pair of subterms,
  named by its two paths of `Step`s, is compared once (one memo per
  comparison of an argument with a parameter), which bounds the work by the
  product of the terms' sizes with no count; an as pattern's sides are
  joined with `|+|`. `%totality_depth` and `totalLimit` are gone and the
  parser refuses the pragma. Everything the pin accepts is accepted
- retire: when a re-sync brings upstream's own removal of the count
- upstream: upstream/fork-totality-depth; nothing is sent (**Idris**)

## interface-body-dropped

- symptom: at the pinned Idris, an interface body keeps its method
  signatures, abstract types and defaults and silently drops every other
  declaration (data with constructors, records, namespaces, `parameters`,
  `failing`, `%runElab`, directives, nested interfaces or implementations):
  `upstream/fork-interface-body/Dropped.idr` reports `Undefined name
  Colour` at the use and nothing at the declaration. The fork inherited it
- sites: compiler/idris/src/Idris/Elab/Interface.idr (`BodyPart`,
  `bodyPart`, `splitParts`; `getSig` and `getDefault` are gone)
- workaround: none; the fork carries the change of
  `upstream/fork-interface-body/pull-request.diff` (upstream test
  `interface037`). Nothing the packages Idris ships or libs/ declare is
  refused
- retire: when a re-sync brings upstream's fix
- upstream: upstream/fork-interface-body; nothing is sent (**Idris**)

## with-application-scope

- symptom: at the pinned Idris, a with application (`f pats | w`) on a with
  clause's right-hand side is rewritten except inside a local block's
  definitions or a record update's fields, where it is refused (`with
  application not implemented yet`):
  `upstream/fork-with-application-scope/WithScope.idr`. The fork inherited
  it
- sites: compiler/idris/src/TTImp/WithClause.idr (`wrhsD`, `wrhsU`)
- workaround: none; the fork carries the change of
  `upstream/fork-with-application-scope/pull-request.diff` (upstream test
  `with013`)
- retire: when a re-sync brings upstream's fix
- upstream: upstream/fork-with-application-scope; nothing is sent
  (**Idris**)

## build-main

- symptom: none of Idris's. The frontend, which is total, must build a
  program, and building needs the elaborator's session state; `UState`
  holds the evaluator's values (`NF`, not strictly positive), which no
  total definition may name
- sites: compiler/idris/src/Idris/ModTree.idr (`buildMain`)
- workaround: the fork provides `buildMain mainFile`: it makes UST, DLY and
  MD, resets the context to the main module's origin and runs `buildDeps`.
  It is the one elaborating operation the frontend trusts, beside the
  evaluator's. `upstream/fork-build-main/pull-request.diff` records it
  against the pin
- retire: when the frontend no longer builds through it
- upstream: nothing; upstream's drivers hold the session

## total-frontend-paths

- symptom: none of Idris's. Upstream code the total frontend calls is
  `covering` and beyond Idris's checker, though it terminates: it traverses
  binders, metavariable arguments and case alternatives through `map`,
  `traverse` or the method being defined; it decodes a TTC by re-entering
  `fromBuf` with the same buffer reference; decoding resolves through
  `HasNames` instances whose `full` looks up and so may decode another
  definition; `lookupCtxtExactI` calls itself on the index it found;
  weakening uses `assert_total`; and some code says nothing (dead evaluator
  fuel, two copies of each name traversal, an always-True Bool from
  `processDecls`)
- sites: compiler/idris/src/Core/TT/Term.idr (`insertNames`, `thinTerm`,
  `shrinkTerm`, `onRefs`, `showTerm`), compiler/idris/src/Core/TT.idr
  (`mkLocals`, `substName`, `addMetas`, `addRefs`),
  compiler/idris/src/Core/Case/CaseTree.idr (`showCT`, `onTreeTerms`,
  `getRefs`, `getMetas`), compiler/idris/src/Core/Hash.idr (`hashTerm`),
  compiler/idris/src/Core/Core.idr (`showError`),
  compiler/idris/src/Core/Context.idr (`OnNames`, `onNamesTerm`,
  `onNamesTree`, `indexedName`, `resolveGlobalDef` and the `resolve…`
  functions of its parts, `lookupContextEntry`, `lookupCtxtExactI`,
  `lookupCtxtExact`; `decode` declared `total`),
  compiler/idris/src/Core/Binary/Prims.idr (`remaining`, `fewer`),
  compiler/idris/src/Core/TTC.idr (`decodeName`, `decodeTerm` and
  `decodeTree` with their parts, `encodeTerm` and `encodeTree` with
  theirs), compiler/idris/src/Core/Directory.idr (`mkdirAll`: done at once when the
  directory exists; otherwise creates each prefix of the path, outermost
  first, passing one that exists already),
  compiler/idris/src/Core/{Value,Normalise/Eval}.idr,
  compiler/idris/src/Algebra/SizeChange.idr (`DecEq`),
  compiler/idris/src/Libraries/Utils/Binary.idr (`%default total`; `dumpBin`
  gone), compiler/idris/src/TTImp/{ProcessDecls,Elab/Local}.idr
- workaround: none; the fork's code there is total by structural or
  well-founded recursion Idris's checker accepts, with upstream's output
  (the same TTC bytes, shown text and hashes). A TTC's decoders recurse on
  the bytes left to read (`Control.WellFounded`).
  `upstream/fork-total-frontend-paths/pull-request.diff` records the change
  against the pin
- retire: never as a whole; each part goes when a re-sync brings upstream's
  own total version
- upstream: nothing is sent (**Idris**)

## bytecode-data-table
- symptom: the pinned writer asks no dialect to encode a mutable type and
  writes its text (`mlir/lib/Bytecode/Writer/BytecodeWriter.cpp:894-899`,
  `IRNumbering.cpp:524-525`); a data type's text holds the body of every
  data type it reaches, once per path: over 300 M bodies for one instance
  of the self module
- sites: foreign/idr/lib/IR/Bytecode.cpp, the readers of the module's
  table (`DataType::readTable`) and of a data type's entry
  (`DataType::member`); foreign/idr/include/idr/IR/IdrBytecode.td, whose
  `DataType` and `DataTable` never print (`DialectTypeNoPrint`, a false
  predicate, constant getters)
- workaround: the frontend writes each data type once, its body in the
  module's one table entry (an idr attribute), and every other occurrence
  as a custom entry naming its member; `idris-mlir-opt --emit-bytecode`
  still writes data types as text, which the parser reads as before
- retire: when the pin's writer encodes mutable types through a dialect
  (pull request #229910, open): give both records printers, so the C++
  writer writes the table too
- upstream: none to send; the deviation is ours
