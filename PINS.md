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
Retired when the LLVM pin moved from 7208ba24 to llvm main at 416f328b
(2026-10-21), with every other dependency fast-forwarded to its latest
(CMake 4.4.4, simdutf 9.3.2; the rest were already their latest) and the
toolchain built without assertions in every stage our code compiles
against or links (D91): `print-local-aliases`
(`upstream/60-print-local-aliases`, its check and its report: main's
8bcccd8b6576, #232518, gives the same printing as
`-mlir-print-always-use-aliases`, which the harness's dumps take); and,
because nothing in the tree reaches their bugs once the cutover runs no
`remove-dead-values` (C35) and no upstream `cse` (D98, D100):
`remove-dead-values-unreachable`, `remove-dead-values-address-taken`,
`liveness-non-forwarded-terminator`, `liveness-trivially-dead` and
`cse-statistic-assignment` (`upstream/06`, `01`, `28`, `63` and `23`),
whose reports stay as submissions with their pull requests as
`pull-request.diff`. Retired with the deduplicator's port (C10):
`eliminate-duplicate-functions`, its port replaced by partition
refinement over upstream's `OperationEquivalence`
(operation-equivalence-symbol-hook). Retired when the lowering came to
build every program function as an `llvm.func` itself (C165):
`func-to-llvm-expanded-arg-attrs` (`upstream/78`), since no function of
ours passes through FuncToLLVM; its report stays as a submission, its
pull request as `pull-request.diff`. Never carried: dead-argument
elimination's always-true `tailcc` test (proposals/0000 C141), fixed on
main by 3d88cd257637 (#233919) before the pin. Retired with the
runtime's one simdutf implementation (C169): `simdutf-dispatch`, the
runtime's choice among simdutf's implementations at startup; the runtime
holds the one its target's entry names as a constant of that
implementation's class and calls it directly
(simdutf-constexpr-implementation).
Retired with the one recipe (2026-10-09): `stage2-thinlto`. Stage 2 is
not LTO on any target: its libraries are native code that every build of
our tools links as it is, a rebuild through the compiler cache relinks
without optimizing LLVM again, and the tools' few percent of speed is not
worth the bootstrap's hours. What programs gain from LTO is untouched: idris-mlir joins the
runtime's bitcode with each program's module, and our own code's Release
build is full LTO.

The LLVM pin is a commit of llvm main, not a release: the patch we carry
for a bug we send upstream is then its pull request, one diff, not two.
Every dependency is fast-forwarded to its latest about weekly (the LLVM
umbrella projects, modular and Idris 2 at main, the rest at their latest
release), and when a patch of ours lands upstream. Each bump is one
commit: the lock, the gitlinks, the carried patches rebased or dropped,
the toolchain rebuilt from it by the one recipe (`tools/bootstrap.sh`) on
every target, the full suites green on each, and this file's sweep.

The accepted toolchain release series live only in `toolchain.lock.json`,
which the top-level CMake configure gate reads.

## dead-code-nested-symbol-use

- symptom: on main at 7208ba24 (and on main on 2026-10-19), dead-code
  analysis resolves a non-call symbol use against the analysis' top, not
  the symbol table being walked, so a use in a nested table finds nothing
  and its function's callers count as all known; liveness then finds what
  the function returns dead, and `remove-dead-values` makes it return
  ub.poison. Every idr program is a symbol table nested in the module, and
  a label reached only through an idr.closure returned poison, a silent
  miscompile
- sites: every analysis on MLIR's solver that loads DeadCodeAnalysis
  (idr-constants, narrowing's copy analysis, Ranges and Borrows, per
  function); remove-dead-values, if the qualification's trial brings it
  back (C35)
- workaround: `upstream/29-dead-code-nested-symbol-use/llvm.patch`: the use
  is resolved in the table being walked; checked by
  tests/upstream-dead-code-nested-symbol-use
- retire: drop the patch when the pin has the fix
- upstream: upstream/29-dead-code-nested-symbol-use; plan in its README: an
  issue and a PR with a remove-dead-values test
- status (2026-10-21): carried; not filed; applies at 416f328b

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
- status (2026-10-21): carried; not filed; applies at 416f328b

## greedy-multi-region-ancestors

- symptom: on main at 7208ba24, the greedy rewrite driver adds an op's
  ancestors to its last-in-first-out worklist with the op, so an ancestor is
  revisited after each change below it; the patterns of an op with several
  regions (upstream's region branch patterns, ours on idr.match and
  idr.match_lit) read all of them, so an op of n regions costs n visits of
  size n: canonicalize in idr-optimize took 30, 120, 223 s at n = 1k, 2k, 4k
  on defunc-tag-limit's program through the whole pipeline
- sites: the greedy driver inside the upstream passes the pipeline runs
  over a module that still holds multi-region ops (`convert-linalg-to-loops`,
  `convert-vector-to-scf`, `expand-strided-metadata`,
  `convert-vector-to-llvm`'s pre-lowering, D99), whose every visit of such
  an op asks whether it is dead across all its regions; our own greedy
  rewrites are gone (D98)
- workaround: `upstream/62-greedy-multi-region-ancestors/llvm.patch`: an
  ancestor with several regions is revisited once the worklist is empty;
  checked by tests/upstream-greedy-multi-region-ancestors
- retire: drop the patch when the pin has the change
- upstream: upstream/62-greedy-multi-region-ancestors; plan in its README:
  one PR
- status (2026-10-21): tested on a private build of the earlier pin,
  7208ba24 (check-mlir 4101 passed, 0 failed); applies at 416f328b; not
  filed

## sqrt-negative-fold

- symptom: on main at 7208ba24 (and on main on 2026-10-19),
  `math::SqrtOp::fold` declines a negative constant, so the square root of
  a negative constant stays a `math.sqrt` that a run computes: the
  fuzzer's static form of a program, whose every line must fold, fails on
  it (tests/fuzz-seeds)
- sites: the e-graph pass, which reads every op's fold (D98), and
  `createOrFold` in the conversions
- workaround: `upstream/61-sqrt-negative-fold/llvm.patch`: a quiet NaN for
  a negative non-zero operand, -0 for -0; checked by
  tests/upstream-sqrt-negative-fold
- retire: drop the patch when the pin folds it
- upstream: upstream/61-sqrt-negative-fold; plan in its README: one PR
- status (2026-10-21): carried; not filed; applies at 416f328b

## cse-nested-linalg-index

- symptom: on main at 7208ba24 (and on main on 2026-10-19), cse replaces
  the `linalg.index` of a structured op nested in another's body by the
  enclosing op's index of the same dimension: `linalg.index` is `Pure` with
  no operand, and cse shares its known values across nested regions that
  are not isolated from above. An array tabulated in a tabulate's body read
  its row index for its column index after the cse that follows
  idr-bufferize, a silent miscompile (tests/linarray-rows-crash-order)
- sites: a tabulate in a tabulate's body, a linalg.generic in another's
  body; the e-graph pass, which takes cse's place and must key an op with
  `DependsOnParent` by its parent as cse's key does (D98; L14's seam).
  Upstream's cse itself runs nowhere now (D98, D100)
- workaround: `upstream/56-cse-nested-linalg-index/llvm.patch`: the trait
  `DependsOnParent` on `linalg.index`, and cse's key for such an op holds
  its parent; checked by tests/upstream-cse-nested-linalg-index
- retire: drop the patch when the pin has the fix
- upstream: upstream/56-cse-nested-linalg-index; plan in its README: a PR
  that fixes issue #62644, perhaps after an RFC for the trait
- status (2026-10-21): carried; not filed; applies at 416f328b

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
- status (2026-10-21): carried; not filed; applies at 416f328b

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

## literal-partial-fold

- symptom: at the pinned Idris, a literal elaborated while its type still
  holds a hole (`index 2 v` in a lambda checked before the vector that
  fixes `Fin ?n`) is folded by `normalisePrims` to a stuck partial normal
  form: base's Fin `fromInteger` unfolds into the caller, the erased
  `believe_me` of its where block's `lemma` with it, so the profile
  refused the caller as an escape hatch. The fork inherited it
- sites: the fork, Core/Normalise.idr (`normalisePrims`: in an
  expression the fold is kept only when it reaches a value, else the call
  stays); and the compiler's profile, compiler/src/IdrisMLIR/Frontend/
  Profile.idr (`proofOnly`: a trusted library's definitions of quantity 0
  are not walked)
- workaround: none; the fork carries the change of
  upstream/59-literal-partial-fold/pull-request.diff, after 18's. The
  stock Idris is not patched: nothing it builds meets the bug
- retire: when a re-sync brings upstream's fix; then the report,
  tests/upstream-literal-partial-fold and this entry go
- upstream: nothing is sent (upstream/README.md, **Idris**)

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
  416f328b)
- upstream: upstream/07-inline-unreachable-terminator (not yet filed);
  plan in its README: an issue and a pull request, #206083 named as a
  separate case

## ub-unreachable-effects

- symptom: on llvm main at 416f328b (and on main on 2026-10-21),
  `ub.unreachable` declares no memory effects, so every reader of effects
  takes it for all of them: a region that ends in it keeps its parent
  alive, and a summed effect row counts a write to every resource where
  control never goes on
- sites: none in our code; the patch. Every body that never returns ends
  in `ub.unreachable`, and the derived effect row and every effect query
  over it read the op's own declaration: the external model that gave it
  no effects in our code (`NeverRuns`) is deleted, so the patch alone
  carries the fact
- workaround: `upstream/87-ub-unreachable-effects/llvm.patch`:
  `NoMemoryEffect` on the op, unspeculatable still; checked by
  tests/upstream-ub-unreachable-effects, which runs the report's
  `unreachable-effects.mlir` under `-canonicalize` and finds the region
  op gone
- retire: when the pin's `ub.unreachable` declares no memory effects
- upstream: upstream/87-ub-unreachable-effects; one pull request
- status (2026-10-21): carried; not filed

## mlir-recursion

- symptom: MLIR recurses on the depth of its input in many places, each
  needing a native stack that grows with the IR it reads: a constant
  nested a few thousand deep overflowed an 8 MiB stack with a bare SIGSEGV
  (6,000 levels of builtin array in `mlir-opt`)
- sites: foreign/idr/include/idr/Driver/Tool.h (`runTool`: the tools run
  on the runtime's runner, runtime/Start/Runner.cpp, on a small stack the
  target entry measures, `IDRIS_MLIR_TOOL_STACK_BYTES`, behind a one-page
  guard that stack-clash probes make enough; darwin-stack-clash)
- workaround: one carried patch per family of MLIR's recursion on input
  size (C99), each with its PINS entry and tests/upstream-<bug> check: the
  textual parse, print and alias collection of nested builtin arrays and
  dictionaries (10), the walks (80), the attribute walker and replacer
  (81), clone (82), destruction (83), region DCE (84), slices (85),
  the symbol-table walk (88), the sparse and dense analyses'
  initialization (89), the comparison of operations and regions (90),
  bufferization's buffer types along chains of values (91), dead-code
  initialization (92), call graph construction (93) and the bytecode
  writer's numbering of nested attributes and types (97)
- left, for the stage-1 stack painting to measure (D33, S1), each
  recursing through code no explicit stack inside MLIR's own reaches: the
  op parser and printer, which reach a nested region through the op's own
  parse and print hooks (the alias collection's dummy printer with them);
  a dialect attribute's parameters, through its parser and printer; and
  the rewriter's `eraseOp`, which recurses through a `std::function` when
  a listener is attached (`PatternMatch.cpp`), with
  `Operation::dropAllDefinedValueUses`
- retire: when the pin has every family's fix, or the painting shows the
  ones left within the measured stack
- upstream: one RFC on Discourse for the family set, then one pull
  request per family (upstream/10-recursive-attribute-parser's plan)

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
  is unchanged (it applies at 416f328b)

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
- upstream: upstream/04-vectorize-precondition-body (not yet filed; applies
  at 416f328b); plan in its README: an issue and a pull request

## int-range-narrowing-exactness

- symptom: upstream's narrowing
  (`arith::populateIntRangeNarrowingPatterns`) makes an elementwise op an
  op on the narrow type whenever the ranges of its operands and results fit
  it. At llvmorg-23.1.2 three narrowed ops then computed something else: a
  shift whose amount can reach the narrow width (poison there), a `remsi`
  that can see INT_MIN % -1 of the narrow type (undefined behaviour once
  `llvm.srem`, where the wide op gives 0), and a `remui` of a word that may
  be negative, which the narrow op reads as another number. Main's
  44a4dbf32 (#218495) fixed the shift, and 28db2071a69c (#233323) the
  unsigned ops. Main at 416f328b still lets a `remsi` narrow whose dividend
  can be the narrow minimum while its divisor can be -1
- sites: none in our code; the patch. idr-narrow-lanes versions a
  vectorized loop when its wide integer ops fit 32 bits, and the narrowing
  of its copy leaves wide an op whose 32-bit form would compute something
  else (tests/linarray-lanes-exact)
- workaround: `upstream/09-int-range-narrowing-exactness/llvm.patch`, the
  `remsi` half alone: it does not narrow when the dividend's range holds
  the narrow signed minimum and the divisor's holds -1
- retire: drop the patch when the pin's narrowing handles `remsi`
- upstream: upstream/09-int-range-narrowing-exactness (the `remsi` half
  not yet filed); plan in its README: an issue and a pull request

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
  present on main at 416f328b); plan in its README: a pull request

## pass-timing-dynamic-pipeline

- symptom: on main at 416f328b, MLIR's pass timing nests a pipeline that a
  pass runs through `Pass::runPipeline` under the root of the report, not
  under the pass: `PassTiming::runBeforePipeline` looks for its parent in
  `parentScopes`, where `runBeforePass` records adaptors alone (main's
  #232948 rewrote the file for thread safety and kept that). The pipeline's time is
  counted twice, and two pipelines on one op name, one run inside the
  other, share one timer. idr-optimize (its per-function pipeline), idr-rc,
  idr-narrow, idr-returned-arguments and idr-tail-calls run pipelines so:
  without the patch, in `idris-mlir --mlir-timing`, their pipelines are
  rows beside the pass that runs them, and the rows add up to more than
  the pass
- sites: none in our code; the patch. idris-mlir runs one pass manager
  (foreign/idr/lib/Driver/Run.cpp), whose timing is the report
- workaround: `upstream/19-pass-timing-dynamic-pipeline/llvm.patch`:
  #169615's change as the rewritten file spells it, under which every
  pass records its scope for the pipelines it runs, and a test of ours
  that fails without it
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
  built; applies at 416f328b); plan in its README: four pull requests, the
  reland of #110322 first, cycles second

## early-exits

- symptom: on llvm main at 416f328b, a region terminator hands control to
  its immediate parent op alone: a jump from a match case to a join point
  two levels up, or a loop's back edge nested in a match, has no form but
  a flag yielded outward or blocks, which drop the scopes counting reads
- sites: the join points of the control-flow lane (`idr.join` and
  `idr.loop` define a builtin `token` per target; `idr.jump` exits to it
  across `idr.match` and `idr.match_lit`, which carry
  `PropagateControlFlowBreak`); every upstream analysis that reads the
  edge (dead code, SCCP, the sparse and dense analyses, post-dominance,
  the inliner's refusal of an escaping region); the lowering through
  `scf.if` and `scf.index_switch`
- workaround: `upstream/65-early-exits/llvm.patch`, llvm/llvm-project
  #166688 (head 968e49b1) rebased by hand onto the pin, five hunks placed
  where the pin's text moved; its own gaps are 66 to 71 below; checked by
  tests/upstream-early-exits
- retire: when the pin passes the merge of #166688; if upstream merges
  another form, ours moves to it only when it keeps every fact this one
  keeps (D82), and a rejection of the pull request is a new ruling
- upstream: upstream/65-early-exits; the pull request itself
- status (2026-10-21): carried; #166688 open, no approving review

## early-exit-propagation-helpers

- symptom: with early exits carried, the helpers that answer a
  propagating op's `getSuccessorRegions` for an exit through it
  (`terminatorPropagatesThrough`, `appendPropagatedTerminatorSuccessors`)
  are `static` in SCF.cpp, so every dialect writes its own copy
- sites: the generated `getSuccessorRegions` of `idr.match`,
  `idr.match_lit`, `idr.join` and `idr.loop`; `scf.index_switch` (71)
- workaround: `upstream/66-early-exit-propagation-helpers/llvm.patch`: the
  two exported from ControlFlowInterfaces, unchanged; checked by
  tests/upstream-early-exit-propagation-helpers
- retire: with early-exits, or when #166688 exports them
- upstream: upstream/66-early-exit-propagation-helpers; a review comment
  on #166688
- status (2026-10-21): carried; not posted

## early-exit-dead-match

- symptom: with early exits carried, a resultless op whose regions all
  exit to an enclosing target is found trivially dead when the exit
  declares its (empty) effects, and is erased: the code after it runs in
  place of the exit, a miscompile
- sites: `idr.match` under `idr.join` whose cases all `idr.jump`; every
  erasure of dead ops (the e-graph pass's cleanup, dead-code elimination)
- workaround: `upstream/67-early-exit-dead-match/llvm.patch`:
  `wouldOpBeTriviallyDead` keeps a root an exit leaves; checked by
  tests/upstream-early-exit-dead-match
- retire: with early-exits, or when #166688 covers it
- upstream: upstream/67-early-exit-dead-match; a review comment on
  #166688
- status (2026-10-21): carried; not posted

## early-exit-region-inliner

- symptom: with early exits carried, `InlineRegionBranchOp` follows a
  region's exit into its target, which it does not own, changes the IR,
  then fails (an assertion in a build with assertions)
- sites: a known `idr.match` case ending in `idr.jump`; `scf.if` with a
  constant condition around an exit
- workaround: `upstream/68-early-exit-region-inliner/llvm.patch`: the path
  stops at a successor the op does not own; checked by
  tests/upstream-early-exit-region-inliner
- retire: with early-exits, or when #166688 covers it
- upstream: upstream/68-early-exit-region-inliner; a review comment on
  #166688
- status (2026-10-21): carried; not posted

## early-exit-successor-inputs

- symptom: with early exits carried, `RemoveDeadRegionBranchOpSuccessorInputs`
  and `RemoveDuplicateSuccessorInputUses` edit the inputs of an exit's
  target from an op that holds only some of the exits to it: the target's
  other exits keep their operands (refused by the verifier), or two of its
  inputs are merged on a partial view
- sites: a dead or duplicate join-point parameter seen from a match that
  holds only some of the jumps to it
- workaround: `upstream/69-early-exit-successor-inputs/llvm.patch`: both
  skip an input the op does not own; checked by
  tests/upstream-early-exit-successor-inputs
- retire: with early-exits, or when #166688 covers them
- upstream: upstream/69-early-exit-successor-inputs; a review comment on
  #166688
- status (2026-10-21): carried; not posted

## early-exit-region-graph

- symptom: with early exits carried, `traverseRegionGraph` indexes its op's
  `visited` by another op's region numbers (out of bounds past the op's
  region count) and misses an exit nested below a region's terminator (a
  loop whose back edge sits in a match reads not repetitive)
- sites: the linearity verifier's `isRepetitiveRegion` on matches;
  bufferization's repetitive-region queries for arrays in loops
- workaround: `upstream/70-early-exit-region-graph/llvm.patch`: only the
  op's regions are nodes, and nested exits landing on it are edges;
  checked by tests/upstream-early-exit-region-graph
- retire: with early-exits, or when #166688 covers it
- upstream: upstream/70-early-exit-region-graph; a review comment on
  #166688
- status (2026-10-21): carried; not posted

## early-exit-index-switch

- symptom: with early exits carried, only `scf.if` carries exits:
  `scf.index_switch`, which `idr.match` lowers to, requires `scf.yield`,
  answers "the op" for every terminator and casts its terminators in its
  lowering; neither op accepts a terminator that never returns, so a case
  that only crashes needs a yield of poison values
- sites: the lowering of `idr.match` to `scf.index_switch`, nested jumps
  lowered by upstream's `convert-scf-to-cf`; a crash case ending in
  `ub.unreachable` or a crash terminator of ours
- workaround: `upstream/71-early-exit-index-switch/llvm.patch`: the
  switch propagates exits as `scf.if` does, and both accept any
  terminator that never returns (`scf::op_impl::isNoReturnTerminator`);
  checked by tests/upstream-early-exit-index-switch
- retire: with early-exits, or when #166688 covers it
- upstream: upstream/71-early-exit-index-switch; a review comment on
  #166688
- status (2026-10-21): carried; not posted

## scc-iterator-node-numbers

- symptom: on llvm main at 416f328b, `scc_iterator` hashes every node of a
  graph into a `DenseMap` for its visit numbers, where `po_iterator`
  indexes a vector by `GraphTraits::getNumber`
- sites: the solver layer's components (the program graph over
  `mlir::CallGraph`, 73); the inliner's component walk
- workaround: `upstream/72-scc-iterator-node-numbers/llvm.patch`: visit
  numbers by node number when the graph numbers its nodes; checked by
  tests/upstream-scc-iterator-node-numbers
- retire: when the pin's `scc_iterator` reads node numbers
- upstream: upstream/72-scc-iterator-node-numbers; one pull request
- status (2026-10-21): carried; not filed

## call-graph-dense-ids

- symptom: on llvm main at 416f328b, `mlir::CallGraph` names its nodes by
  pointer and keeps no components, so a client keeps per-node state in a
  pointer-keyed map and runs `scc_iterator` itself
- sites: the solver layer's program graph (L14), which reads
  `CallGraphNode::getIndex()` and `CallGraph::getSCCs()` and keeps what
  upstream cannot hold (tail kinds, sites, the editor); upstream's inliner
- workaround: `upstream/73-call-graph-dense-ids/llvm.patch`: dense ids
  minted by the graph, stable for its life, and its bottom-up components
  as ranges of one kept permutation; checked by
  tests/upstream-call-graph-dense-ids
- retire: when the pin's `CallGraph` holds dense ids and kept components
  in a form that keeps every fact this one gives
- upstream: upstream/73-call-graph-dense-ids; an RFC on Discourse, then
  the pull request with 72
- status (2026-10-21): carried; not filed

## pass-adaptor-preserved-analyses

- symptom: on llvm main at 416f328b, `OpToOpPassAdaptor` preserves no
  analysis, so every group of nested passes invalidates every analysis of
  its parent, though each nested pass declared what it kept
- sites: the nested `idr.func` groups of the pipeline, after which the
  program graph and the solver layer's cached analyses survive
- workaround: `upstream/74-pass-adaptor-preserved-analyses/llvm.patch`:
  the adaptor preserves the intersection of what its nested passes
  preserved, as LLVM's pass manager does; checked by
  tests/upstream-pass-adaptor-preserved-analyses
- retire: when the pin's adaptor preserves the intersection
- upstream: upstream/74-pass-adaptor-preserved-analyses; one pull request
- status (2026-10-21): carried; not filed

## thread-pool-stack-size

- symptom: on llvm main at 416f328b, `StdThreadPool` starts its workers
  with `llvm::thread`'s default stack size (8 MiB on Darwin, the system's
  elsewhere), which no strategy changes
- sites: the compiler's driver, which builds MLIR's thread pool with every
  thread on one stack size, D33's measured bound with a margin, sized in
  one platform place (C43)
- workaround: `upstream/75-thread-pool-stack-size/llvm.patch`:
  `ThreadPoolStrategy::StackSizeInBytes`; checked by
  tests/upstream-thread-pool-stack-size
- retire: when the pin's pool takes a stack size
- upstream: upstream/75-thread-pool-stack-size; one pull request
- status (2026-10-21): carried; not filed

## pass-base-derived-class

- symptom: on llvm main at 416f328b, a pass's `baseClass` is spliced into
  the generated template over `DerivedT`, so a CRTP base class works, but
  nothing documents it
- sites: `StagedPass`, CRTP over the derived pass, which deletes the last
  virtual of ours (C120)
- workaround: `upstream/76-pass-base-derived-class/llvm.patch`,
  documentation only; checked by tests/upstream-pass-base-derived-class
- retire: when the pin documents it
- upstream: upstream/76-pass-base-derived-class; one NFC pull request
- status (2026-10-21): carried; not filed

## dataflow-state-storage

- symptom: on llvm main at 416f328b, `DataFlowSolver` keeps behind every
  anchor a `DenseMap` and in every state with a dependent a `SetVector`
  with no inline size, two 64-bucket hash tables from the first entry:
  about 2.9 KB for one bit of liveness (measured, arm64 macOS)
- sites: the per-function solves on upstream's framework: idr-constants,
  narrowing's copy analysis, Ranges and Borrows, measured on it before any
  leaves it (C32, S3)
- workaround: `upstream/77-dataflow-state-storage/llvm.patch`: small maps
  and sets inline, the solver's uniquer single-threaded; about fifteenfold
  less per state; checked by tests/upstream-dataflow-state-storage
- retire: when the pin's solver keeps small states inline
- upstream: upstream/77-dataflow-state-storage; one pull request with
  massif numbers
- status (2026-10-21): carried; not filed; the qualification records its
  bytes per anchor on all four targets

## operation-equivalence-symbol-hook

- symptom: on llvm main at 416f328b, `OperationEquivalence` compares and
  hashes symbol references by identity, in attributes and properties and
  in the types of operands, results and block arguments, so two functions
  that differ only in which of two equal callees they name are never
  equivalent
- sites: the deduplication of functions by partition refinement over
  upstream's `OperationEquivalence` (L18), which retires the port of
  Modular's `EliminateDuplicateFunctions` (C10)
- workaround: `upstream/79-operation-equivalence-symbol-hook/llvm.patch`:
  an optional `MapSymbolRefFn` through which symbol references are
  compared and hashed, in attributes, properties and those types; checked
  by tests/upstream-operation-equivalence-symbol-hook, which should cover
  a type naming a symbol as well as an attribute
- retire: when the pin's `OperationEquivalence` takes such a hook
- upstream: upstream/79-operation-equivalence-symbol-hook; one pull
  request
- status (2026-10-21): carried; not filed

## walk-iterative

- symptom: on llvm main at 416f328b, every walk in `Visitors.h` and the
  two stage-aware walks in `Visitors.cpp` recurse once per level of
  operation nesting (the pin's own TODO says they should not)
- sites: every pass, under the tools' one small stack (D33, C43, C99)
- workaround: `upstream/80-walk-iterative/llvm.patch`: the eight walks on
  one explicit-stack engine, with the same order and the same erasure,
  skip and interrupt behaviour for every iterator kind; checked by
  tests/upstream-walk-iterative
- retire: when the pin walks without recursion on nesting depth
- upstream: upstream/80-walk-iterative; one pull request after the RFC
  for MLIR's recursions on input size
- status (2026-10-21): carried; not filed

## attr-type-walker-iterative

- symptom: on llvm main at 416f328b, `AttrTypeWalker`, `AttrTypeReplacer`
  and `CyclicAttrTypeReplacer` recurse once per level of attribute or type
  nesting
- sites: the substitution of family index terms
  (foreign/idr/lib/IR/Families/Substitute.cpp), the type graph
  (foreign/idr/lib/IR/TypeGraph.cpp), operation-equivalence-symbol-hook's
  mapping, and upstream's symbol-use walks and renames, under the tools'
  one small stack (D33, C43, C99)
- workaround: `upstream/81-attr-type-walker-iterative/llvm.patch`: an
  explicit stack with the same order, caches and cycle handling; checked
  by tests/upstream-attr-type-walker-iterative
- retire: when the pin walks and replaces without recursion on depth
- upstream: upstream/81-attr-type-walker-iterative; one pull request
  after the RFC for MLIR's recursions on input size
- status (2026-10-21): carried; not filed

## clone-iterative

- symptom: on llvm main at 416f328b, `Region::cloneInto` recurses once per
  level of region nesting
- sites: upstream's inliner and every clone of an operation with regions
  (the e-graph's elaboration, idr-narrow's copies, bufferization), under
  the tools' one small stack (D33, C43, C99)
- workaround: `upstream/82-clone-iterative/llvm.patch`: the same two
  steps, the second from an explicit stack, in the same order; checked by
  tests/upstream-clone-iterative
- retire: when the pin clones without recursion on nesting depth
- upstream: upstream/82-clone-iterative; one pull request after the RFC
  for MLIR's recursions on input size
- status (2026-10-21): carried; not filed

## destruction-iterative

- symptom: on llvm main at 416f328b, destroying an operation and dropping
  its references recurse once per level of nesting, and destruction
  visits a chain nested N deep about N²/2 times
- sites: every erase and every module freed, under the tools' one small
  stack (D33, C43, C99)
- workaround: `upstream/83-destruction-iterative/llvm.patch`, applying
  after 82: teardown from an explicit stack, every reference dropped
  before anything is freed, references dropped through parent links;
  checked by tests/upstream-destruction-iterative
- retire: when the pin destroys without recursion on nesting depth
- upstream: upstream/83-destruction-iterative; one pull request after the
  RFC for MLIR's recursions on input size
- status (2026-10-21): carried; not filed

## region-dce-iterative

- symptom: on llvm main at 416f328b, `runRegionDCE`'s liveness
  propagation and deletion recurse once per level of region nesting
- sites: every greedy rewrite the upstream passes run on lowered functions
  end each round in `simplifyRegions` (expand-strided-metadata,
  convert-vector-to-scf, convert-linalg-to-loops, the schedule's
  `transform.apply_patterns`), under the tools' one small stack (D33,
  C43, C99)
- workaround: `upstream/84-region-dce-iterative/llvm.patch`: explicit
  stacks with the same order and the same erasures; checked by
  tests/upstream-region-dce-iterative
- retire: when the pin's region DCE runs without recursion on depth
- upstream: upstream/84-region-dce-iterative; one pull request after the
  RFC for MLIR's recursions on input size
- status (2026-10-21): carried; not filed

## slice-iterative

- symptom: on llvm main at 416f328b, the backward and forward slices
  recurse once per operation of a use-def chain
- sites: the vectorizer's reduction matching
  (foreign/idr/lib/Target/Schedules.cpp, through
  `vectorizeLinalgOpPrecondition`) and bufferization's empty-tensor
  elimination (`moveValueDefinitions`), under the tools' one small stack
  (D33, C43, C99)
- workaround: `upstream/85-slice-iterative/llvm.patch`: explicit stacks
  with the same slices in the same order; checked by
  tests/upstream-slice-iterative
- retire: when the pin slices without recursion on chain length
- upstream: upstream/85-slice-iterative; one pull request after the RFC
  for MLIR's recursions on input size
- status (2026-10-21): carried; not filed

## symbol-table-walk-iterative

- symptom: on llvm main at 416f328b, `SymbolTable::walkSymbolTables`
  recurses once for every operation of every block it visits, so its
  native depth is the IR's nesting depth whatever symbols it holds
- sites: dead-code analysis's initialization (idr-optimize's constant
  propagation, the ranges analysis, idr-narrow's copies), upstream's
  inliner in idr-inline (its use lists) and the continuations check's
  `SymbolUserMap` (foreign/idr/lib/Transforms/Expect/Continuations.cpp),
  under the tools' one small stack (D33, C43, C99)
- workaround: `upstream/88-symbol-table-walk-iterative/llvm.patch`,
  applying after 80: a stage-aware walk with a stack of each open
  operation's visibility, the same tables passed in the same post-order
  with the same visibility; checked by
  tests/upstream-symbol-table-walk-iterative
- retire: when the pin walks symbol tables without recursion on depth
- upstream: upstream/88-symbol-table-walk-iterative; one pull request
  after the RFC for MLIR's recursions on input size and after 80's
- status (2026-10-21): carried; not filed

## dataflow-iterative-initialization

- symptom: on llvm main at 416f328b, the sparse forward and backward
  analyses (`initializeRecursively`) and the dense forward and backward
  analyses (`initialize`) initialize by recursion, once per operation of
  every block, so every analysis on upstream's framework needs a native
  stack that grows with the IR's depth
- sites: the sparse forward initialization of idr-optimize's constant
  propagation and of the integer range solves (the ranges analysis,
  idr-narrow's copies), under the tools' one small stack (D33, C43, C99);
  nothing of ours runs a sparse backward or dense analysis, whose
  initializations are the same traversal
- workaround: `upstream/89-dataflow-iterative-initialization/llvm.patch`:
  one traversal from an explicit worklist in the recursions' order
  (`DataFlowAnalysis::initializeNested`), so every state is created and
  visited as before; a dense analysis's `initialize` override is now
  called on the top operation alone, and none overrides it; checked by
  tests/upstream-dataflow-iterative-initialization
- retire: when the pin initializes the sparse and dense analyses without
  recursion on depth
- upstream: upstream/89-dataflow-iterative-initialization; one pull
  request after the RFC for MLIR's recursions on input size and after
  80's, 88's and 92's
- status (2026-10-21): carried; not filed

## operation-equivalence-iterative

- symptom: on llvm main at 416f328b, `OperationEquivalence::isEquivalentTo`
  and `isRegionEquivalentTo` call each other once per level of region
  nesting
- sites: the e-graph's identical-regions rule
  (foreign/idr/lib/Transforms/Joins/IdenticalRegions.cpp) and the
  deduplication of functions by partition refinement
  (foreign/idr/lib/Transforms/Deduplicate/Deduplicate.cpp), on
  program-sized bodies, under the tools' one small stack (D33, C43, C99)
- workaround: `upstream/90-operation-equivalence-iterative/llvm.patch`,
  applying after 79, whose symbol hook it keeps: one comparison from an
  explicit stack of the pairs of regions being compared, in the
  recursion's order, so the callbacks are called in the same order and
  the same first difference stops it; one symbol mapper per comparison;
  checked by tests/upstream-operation-equivalence-iterative
- retire: when the pin compares operations and regions without recursion
  on nesting depth
- upstream: upstream/90-operation-equivalence-iterative; one pull request
  after the RFC for MLIR's recursions on input size and after 79's
- status (2026-10-21): carried; not filed

## buffer-type-iterative

- symptom: on llvm main at 416f328b, `bufferization::getBufferType` and
  the `getBufferType` implementations call each other once per value of a
  chain of values whose buffer types depend on each other (an aliased
  operand, a cast's source, a loop's init_arg and yielded value)
- sites: the bufferization of arrays, One-Shot Bufferize over the
  compiler's models (foreign/idr/lib/Transforms/Bufferize/), on
  program-sized chains, under the tools' one small stack (D33, C43, C99)
- workaround: `upstream/91-buffer-type-iterative/llvm.patch`: the
  computation from an explicit stack of the values in progress, held in
  `BufferizationState`; an implementation's question with no answer yet
  fails, the value is computed by a frame of its own, and the
  implementation runs again, so every one is asked the same values in the
  same order with the same invocation stack and answers. It holds for an
  implementation that asks the same values when run again and acts on a
  failed question only by failing, as upstream's and the compiler's
  models do (the interface's documentation states it); checked by
  tests/upstream-buffer-type-iterative
- retire: when the pin computes buffer types without recursion on the
  length of a chain
- upstream: upstream/91-buffer-type-iterative; one pull request after the
  RFC for MLIR's recursions on input size
- status (2026-10-21): carried; not filed

## dead-code-iterative-initialization

- symptom: on llvm main at 416f328b, `DeadCodeAnalysis::initializeRecursively`
  recurses once per level of region nesting, so every sparse forward
  analysis needs a native stack that grows with the IR's depth
- sites: every solve on upstream's framework, under the tools' one small
  stack (D33, C43)
- workaround: `upstream/92-dead-code-iterative-initialization/llvm.patch`:
  the same pre-order from a worklist; checked by
  tests/upstream-dead-code-iterative-initialization
- retire: when the pin initializes it without recursion on depth
- upstream: upstream/92-dead-code-iterative-initialization; one pull
  request after the RFC for MLIR's recursions on input size
- status (2026-10-21): carried; not filed

## call-graph-iterative-construction

- symptom: on llvm main at 416f328b, `computeCallGraph` recurses once per
  level of region nesting
- sites: every build of `mlir::CallGraph` (the program graph, the
  inliner), under the tools' one small stack (D33, C43)
- workaround: `upstream/93-call-graph-iterative-construction/llvm.patch`:
  the same pre-order from a worklist; checked by
  tests/upstream-call-graph-iterative-construction
- retire: when the pin builds it without recursion on depth
- upstream: upstream/93-call-graph-iterative-construction; one pull
  request after the RFC for MLIR's recursions on input size
- status (2026-10-21): carried; not filed

## bytecode-numbering-iterative

- symptom: on llvm main at 416f328b, the bytecode writer numbers a nested
  attribute or type by a dummy writing that numbers each component as it
  reaches it (`IRNumberingState::number`), recursing once per level of
  nesting
- sites: none in our code; the patch. The toolchain's `mlir-opt` writing
  bytecode reaches it: tests/upstream-bytecode-deferred-quadratic writes
  an array nested 32,000 deep on a small stack, with no raised limit
- workaround: `upstream/97-bytecode-numbering-iterative/llvm.patch`: the
  dummy writer records the components it reaches, numbered afterwards
  from an explicit stack in the recursion's order, so the bytecode is
  unchanged; checked by tests/upstream-bytecode-numbering-iterative
- retire: when the pin numbers nested attributes and types without
  recursion on their depth
- upstream: upstream/97-bytecode-numbering-iterative; one pull request
  after the RFC for MLIR's recursions on input size
- status (2026-10-21): carried; not filed

## function-interface-edits

- symptom: on llvm main at 416f328b, `FunctionOpInterface`'s
  `insertArguments`, `insertResults`, `eraseArguments` and `eraseResults`
  are shared class declarations, so a caller holding the interface runs
  the interface's copy and never an operation's own, and none of the hooks
  they call is given the indices
- sites: `idr.func`'s positional facts (where each scoped value lives and
  the bounds between lifetimes, what it gives back, its untouched and
  bounded parameters), kept by its own edits
  (foreign/idr/lib/IR/Func/Edits.cpp) under every caller, upstream's
  passes among them (C187)
- workaround: `upstream/99-function-interface-edits/llvm.patch`: the four
  edits are interface methods with the present bodies as their defaults,
  and the single-item forms reach them through the operation; checked by
  tests/upstream-function-interface-edits
- retire: when the pin's `FunctionOpInterface` dispatches the four edits
  to an operation's own
- upstream: upstream/99-function-interface-edits; one pull request
- status (2026-10-21): carried; not filed

## one-shot-tensor-like-copy

- symptom: on llvm main at 416f328b, One-Shot Bufferize gives an
  out-of-place operand of a tensor-like type that is not a builtin tensor
  no copy, so the op writes a buffer read after it, and its allocation
  reaches `llvm_unreachable`
- sites: the bufferization of linear arrays, `!idr.lin<T>` tensor-like
  where `T` is (D43, L12)
- workaround: `upstream/27-one-shot-tensor-like-copy/llvm.patch`:
  `BufferizationOptions::tensorAllocationFn` and a copy of every
  tensor-like out-of-place operand; checked by
  tests/upstream-one-shot-tensor-like-copy
- retire: when the pin copies such an operand
- upstream: upstream/27-one-shot-tensor-like-copy; an issue and a pull
  request
- status (2026-10-21): carried; not filed

## tensor-like-per-instance

- symptom: on llvm main at 416f328b, tensor-likeness is a property of a
  type's class, and `to_tensor`/`to_buffer` require shaped types beside
  the interface's own check, so no graded tensor can be tensor-like for
  some payloads alone or bridged
- sites: `!idr.lin<T>` and every bridge of a graded tensor (D43, L12)
- workaround: `upstream/64-tensor-like-per-instance/llvm.patch`:
  `isTensorLike`/`isBufferLike` through `extraClassOf`, and the shape
  traits gone; checked by tests/upstream-tensor-like-per-instance
- retire: when the pin decides tensor-likeness per instance
- upstream: upstream/64-tensor-like-per-instance; one pull request
- status (2026-10-21): carried; not filed

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
- workaround: none: no build runs a sanitizer. Trap-mode UBSan
  (`-fsanitize=undefined -fsanitize-trap=all`) needs no runtime, and its
  place is the build every test runs, not an opt-in preset
- retire: when a sanitizer build is worth building compiler-rt's
  sanitizers for
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
- workaround: the runtime is compiled for the baseline plus CMPXCHG16B,
  which the program's CPU then has too (its features are its flags' and
  the baseline's)
- retire: never; every x86-64 CPU since 2006 has it
- upstream: none

## simdutf-constexpr-implementation

- symptom: at simdutf 9.3.2 (and on its master, read 2026-10-21), no
  implementation's constructor is `constexpr`, so a program cannot hold
  an implementation as a constant object of its own `final` class: the
  object needs a dynamic initializer, and the only constant way to reach
  the kernels is through the virtual table and
  `get_active_implementation()`, simdutf's run-time choice
- sites: runtime/Strings/Simd.h (`rt::strings::utf8`, a constant of the
  class the target's entry names, IDRIS_RT_SIMDUTF_CLASS), and every call
  of the runtime into simdutf through it, each direct, so the stack bound
  sees its callee; the runtime compiles simdutf from the bootstrap's
  export (runtime-library-export)
- workaround: `upstream/98-simdutf-constexpr-implementation/simdutf.patch`:
  `constexpr` on the base constructor and on every architecture's but
  rvv's, which asks the processor for Zvbb; checked by
  tests/upstream-simdutf-constexpr-implementation
- retire: when a pinned simdutf release has constexpr constructors
- upstream: upstream/98-simdutf-constexpr-implementation; a pull request
  to simdutf/simdutf
- status (2026-10-21): carried; not filed

## snmalloc-arm-yield-asm

- symptom: snmalloc's Arm AAL spins with inline assembly,
  `__asm__ volatile("yield")` in `AAL_arm::pause()`
  (third_party/snmalloc/src/snmalloc/aal/aal_arm.h:53-60), where the runtime
  reaches the processor through intrinsics only; every snmalloc spin loop
  the runtime meets on arm64 runs it
- sites: the runtime's snmalloc, compiled by runtime/Alloc/Cells.cpp from
  the bootstrap's export (runtime-library-export)
- workaround: `upstream/49-snmalloc-arm-yield-intrinsic/snmalloc.patch`:
  one `#elif __has_builtin(__builtin_arm_yield)` branch that emits the
  same instruction as an intrinsic, applied to the export since snmalloc
  became a patch project (2026-10-21); checked by
  tests/upstream-snmalloc-arm-yield-intrinsic
- retire: when the snmalloc pin moves past upstream's change
- upstream: upstream/49-snmalloc-arm-yield-intrinsic (not filed)

## runtime-library-export

- symptom: the fixes of the libraries the runtime compiles are patches to
  their source, snmalloc's (94, 95, 49) and simdutf's (98), which the
  runtime's build cannot apply to the submodules it would compile
- sites: tools/bootstrap.sh (steps `snmalloc` and `simdutf`, one
  `step_export`), tools/patches.sh (projects `snmalloc` and `simdutf`),
  tools/verify-pins.sh (`sysroot`); the toolchain files, which name the
  exports as `IDRIS_MLIR_SNMALLOC` and `IDRIS_MLIR_SIMDUTF`;
  runtime/CMakeLists.txt, which compiles both from them
- workaround: the bootstrap exports third_party/snmalloc and
  third_party/simdutf, each at its gitlink, the lock's revision, with its
  patches applied in name order, into .toolchain/<name>/src, stamped with
  them; the runtime compiles those copies
- retire: a library's export goes when it carries no patch
- upstream: none
- status (2026-10-21): snmalloc's new with this bump; simdutf's with C169

## snmalloc-pagemap-sanity-checks

- symptom: at snmalloc 0.7.6, a bounded pagemap tests every in-range lookup
  and every write against its range, a check of the client paid on every
  free
- sites: the runtime's heap (runtime/Alloc), snmalloc's bounded flat map
  over the heap's one span (C5, C100); its frees are of cells its types
  prove are heap cells
- workaround: `upstream/94-snmalloc-pagemap-sanity-checks/snmalloc.patch`:
  the tests run only under `sanity_checks`; null still reads the default
  entry; checked by tests/upstream-snmalloc-pagemap-sanity-checks
- retire: when a pinned snmalloc release gates them
- upstream: upstream/94-snmalloc-pagemap-sanity-checks; a pull request to
  microsoft/snmalloc
- status (2026-10-21): carried; not filed

## snmalloc-notify-using-result

- symptom: at snmalloc 0.7.6, with `pal_enforce_access`, the POSIX and
  Apple PALs ignore `notify_using`'s `mprotect` result, so a refused commit
  hands out `PROT_NONE` pages and the program dies by SIGSEGV, unnamed
- sites: the runtime's heap under a strict host (overcommit mode 2,
  `ulimit -v`), which must end with status 111 (D35, D37)
- workaround: `upstream/95-snmalloc-notify-using-result/snmalloc.patch`:
  `notify_using` and `notify_using_readonly` return false when `mprotect`
  fails; every caller already handles it; checked by
  tests/upstream-snmalloc-notify-using-result
- retire: when a pinned snmalloc release reports the failure
- upstream: upstream/95-snmalloc-notify-using-result; a pull request to
  microsoft/snmalloc
- status (2026-10-21): carried; not filed

## darwin-stack-clash

- symptom: on llvm main at 416f328b, clang's driver passes
  `-fstack-clash-protection` to the compiler for Linux, FreeBSD and Fuchsia
  alone (`RenderSCPOptions`), so on arm64 macOS the flag is an unused
  argument, an error in a configure check that adds `-Werror`, and no frame
  is probed; the backends' inline probing has no Darwin restriction
- sites: tools/bootstrap.sh (stage 2's and GMP's flags, the same on every
  target; stage 1 built from the patched tree, since it compiles stage 2's
  LLVM); CMakeLists.txt's target entries and the runtime's probe flags,
  which give our tools and the runtime the flag (C5, C59)
- workaround: `upstream/86-darwin-stack-clash/llvm.patch`: Darwin joins the
  systems the driver passes the flag for; checked by
  tests/upstream-darwin-stack-clash, which compiles the report's
  `large-frame.c` for arm64-apple-macosx14.0 with the flag and `-Werror`
  and finds the probe loop
- retire: when the pin's driver passes the flag for Darwin
- upstream: upstream/86-darwin-stack-clash; one pull request
- status (2026-10-21): carried; not filed

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
- stored terms: a stored definition's terms are frozen preorder columns,
  their locations beside them, read purely, so the fork states no new
  trust for them (C183; interned-identifiers). The fork's evaluator reads
  those columns, not upstream's trees, so it is no longer upstream's
  evaluator with changes that a three-way merge carries forward: a
  re-sync re-implements upstream's changes to the evaluator against the
  columns. That is D44's accepted cost of taking 0010's A0 whole
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

## ttc-term-locations

- symptom: none of Idris's. At the pin a term read back from a TTC has no
  location at any node (`emptyFC`), and a main file is read back from its
  TTC once built, so every op the frontend emitted took its definition's
  location
- sites: compiler/idris/src/Core/TTC.idr (`within`, `encodeFC`,
  `decodeFC`, the term, binder and case-tree leaf encoders and decoders),
  compiler/idris/src/Core/Binary.idr (`ttcVersion`)
- workaround: none; the fork writes each node's location, relative to the
  location it is part of, as `upstream/fork-ttc-term-locations/pull-request.diff`
  records
- retire: when a re-sync brings a TTC that keeps term locations
- upstream: upstream/fork-ttc-term-locations; nothing is sent (**Idris**)

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
  (the same shown text and hashes, and the same TTC bytes but for the
  locations of ttc-term-locations). A TTC's decoders recurse on
  the bytes left to read (`Control.WellFounded`).
  `upstream/fork-total-frontend-paths/pull-request.diff` records the change
  against the pin
- retire: never as a whole; each part goes when a re-sync brings upstream's
  own total version
- upstream: nothing is sent (**Idris**)

## search-depth

- symptom: at the pinned Idris, the automatic search stops at
  `%auto_implicit_depth` (default 50) and a goal it cannot solve within
  it fails the program: acceptance is a count. The fork inherited it
- sites: compiler/idris/src/Core/AutoSearch.idr (the embedding check),
  Core/Core.idr (`Growth`), the depth fields of `ISearch`, `PSearch` and
  `BySearch`, the pragma's parser, Core/Normalise/Quote.idr
  (`quoteWithin`, `TooDeep`)
- workaround: none; the fork carries the change of
  `upstream/fork-search-depth/pull-request.diff` (a386fe4d), and the
  growth sum (search-growth, e5b39cb2): a goal that embeds an earlier goal
  of its path waits, and at the last chance refuses the program; the
  pragma is refused; the depths that remain decide a stored term's form,
  never acceptance (D53, C66, C127)
- retire: when a re-sync brings upstream's own removal of the count
- upstream: nothing is sent (**Idris**)

## ambiguity-depth

- symptom: at the pinned Idris, nested resolution of overloaded names
  stops at `%ambiguity_depth` (default 3) and only refuses programs
  (`printLn (1, 2, 3, 4, 5, 6)`). The fork inherited it
- sites: compiler/idris/src/TTImp/Elab/Ambiguity.idr, TTImp/Elab/Check.idr
  (`ambigTries`), the pragma's parser and option
- workaround: none; the fork carries the change of
  `upstream/fork-ambiguity-depth/pull-request.diff` (a386fe4d): the count
  and everything serving it go, and the pragma is refused (D55)
- retire: when a re-sync brings upstream's own removal of the count
- upstream: nothing is sent (**Idris**)

## posix-paths

- symptom: at the pinned Idris, `Libraries.Utils.Path` reads every path
  with Windows's grammar and tests the host's operating system at run
  time (`"/tmp/a:b" </> "Main.idr"` is `/tmp/a/Main.idr`). The fork
  inherited it
- sites: compiler/idris/src/Libraries/Utils/Path.idr, its users
- workaround: none; the fork carries the change of
  `upstream/fork-posix-paths/pull-request.diff` (a386fe4d): a path is an
  optional root and the names after it, split at `/` alone; `Volume`,
  `isWindows` and the separators go (C125)
- retire: never as a whole: the compiler's targets are all POSIX
- upstream: nothing is sent (**Idris**)

## no-runtime-tree

- symptom: at the pinned Idris, every definition gets a second, run-time
  case tree, built with `%transform`s, `%spec` and partial evaluation,
  that the TTC drops and the frontend never reads. The fork inherited it
- sites: compiler/idris/src/Core/Case/CaseBuilder.idr,
  Core/Context/Context.idr (`PMDef`'s `clausePats`), TTImp/ProcessDef.idr;
  `TTImp.PartialEval` and `Core.Transform`'s use gone
- workaround: none; the fork carries the change of
  `upstream/fork-no-runtime-tree/pull-request.diff` (a386fe4d): none is
  built; a `PMDef` holds the compile-time tree and each clause's patterns
  (C55)
- retire: never as a whole; the frontend reads checked TT (AGENTS.md)
- upstream: nothing is sent (**Idris**)

## ttc-facts

- symptom: at the pinned Idris, the TTC drops a `let`'s, `PLet`'s and
  `PVTy`'s binder type, why a term is erased, a case tree's scrutinee type
  and clause indices, and a block's typed parent, which the frontend
  guessed back (one guess refused valid programs, 17 FB-01)
- sites: compiler/idris/src/Core/TTC.idr, Core/Binary.idr (`ttcVersion`)
- workaround: none; the fork carries the change of
  `upstream/fork-ttc-facts/pull-request.diff` (a386fe4d): the TTC keeps
  them (D44's F1, C129)
- retire: when a re-sync brings a TTC that keeps them
- upstream: nothing is sent (**Idris**)

## block-parent

- symptom: at the pinned Idris, a case or with block's name holds its
  parent's printed text and the session's machine-name counter (17
  FB-10). The fork inherited it
- sites: compiler/idris/src/Core/Name.idr (`CaseBlock`, `WithBlock`),
  Core/UnifyState.idr (`blockOrdinals`), TTImp/Elab/Case.idr,
  Core/Reflect.idr
- workaround: none; the fork carries the change of
  `upstream/fork-block-parent/pull-request.diff` (a386fe4d): the parent's
  full name and the block's ordinal among its parent's blocks (C129)
- retire: when a re-sync brings upstream's own typed parent
- upstream: nothing is sent (**Idris**)

## param-pos

- symptom: at the pinned Idris, a type's parameters are read off its
  constructors' types as written, so a constructor whose binders come
  through a definition has none (17 FB-18). The fork inherited it
- sites: compiler/idris/src/Core/Context/Data.idr
- workaround: none; the fork carries the change of
  `upstream/fork-param-pos/pull-request.diff` (a386fe4d): read off the
  types in normal form
- retire: when a re-sync brings upstream's fix
- upstream: nothing is sent (**Idris**)

## erase-args

- symptom: at the pinned Idris, a definition's erased positions are fixed
  where its type is declared, too few when the type reaches its binders
  through a definition declared before and defined after. The fork
  inherited it
- sites: compiler/idris/src/TTImp/ProcessDef.idr (`updateErasable`),
  Algebra/ZeroOneOmega.idr
- workaround: none; the fork carries the change of
  `upstream/fork-erase-args/pull-request.diff` (a386fe4d): found again
  once the clauses are checked against the whole spine; the frontend
  reads them once (C122)
- retire: when a re-sync brings upstream's fix
- upstream: nothing is sent (**Idris**)

## parser-bounds

- symptom: at the pinned Idris, `WithBounds` keeps `isIrrelevant : Bool`
  beside bounds that are junk when it is set, so the functor and monad
  identities fail (measured, payoffs.md §1.5). The fork inherited it
- sites: compiler/idris/src/Libraries/Text/Bounded.idr, the lexers, the
  parser core and their users
- workaround: none; the fork carries the change of
  `upstream/fork-parser-bounds/pull-request.diff` (a386fe4d): a sum,
  `Irrelevant val | Relevant val bounds`, and `Located` tokens (D101)
- retire: when a re-sync brings upstream's own sum
- upstream: nothing is sent (**Idris**)

## dead-options

- symptom: at the pinned Idris, the elaborator carries a never-started
  search timer, `%search_timeout`, `%foreign_impl`, `--debug-elab-check`,
  `delayDepth` and the raw TTImp parser, none of which a reader needs. The
  fork inherited them
- sites: compiler/idris/src/Core/Options.idr, Idris/Syntax/Pragmas.idr,
  Idris/CommandLine.idr, Core/Context.idr, TTImp/Elab/Delayed.idr,
  Idris/Desugar.idr (`collectDefs`)
- workaround: none; the fork carries the change of
  `upstream/fork-dead-options/pull-request.diff` (a386fe4d): they go, and
  the parser refuses a removed pragma where it is written (C128)
- retire: never as a whole
- upstream: nothing is sent (**Idris**)

## search-growth

- symptom: the fork's first form of the search's growth (a386fe4d) was an
  error, which every combinator that catches a failed branch had to
  recognize and rethrow, or a sibling answered in its place
- sites: compiler/idris/src/Core/AutoSearch.idr (`Searched`: `Found` or
  `Grows`), Core/Unify.idr, Core/Core.idr and Idris/Error.idr
  (`GrowingSearch`), TTImp/Elab/Check.idr, TTImp/Elab/Delayed.idr
- workaround: none; the fork's own code (e5b39cb2): a growth is a case of
  the search's result beside its failures, so no combinator can catch it;
  one through unknowns waits for a later round, and at the last chance
  refuses the program (`GrowingSearch`) (C127)
- retire: never; the fork's representation
- upstream: nothing is sent (**Idris**)

## tuple-node

- symptom: at the pinned Idris, `(l, r)`, `()` and `(x ** p)` desugar to
  an alternative of two candidates, the type and the value, each
  elaborated in full and nested at each level of a tuple, so elaborating a
  tuple costs more than its size. The fork inherited it
- sites: compiler/idris/src/TTImp/TTImp.idr (`ITypeOrValue`, its functor,
  traversals and TTC), Idris/Desugar.idr, Idris/Resugar.idr,
  TTImp/Elab/Ambiguity.idr, TTImp/Elab/Term.idr, TTImp/Elab/App.idr,
  TTImp/Elab/Case.idr, TTImp/Elab/Quote.idr, TTImp/BindImplicits.idr,
  TTImp/Impossible.idr, TTImp/Reflect.idr, TTImp/Utils.idr,
  TTImp/WithClause.idr
- workaround: none; the fork's own code (e5b39cb2): one node holding its
  parts once, read by the expected type's sort (`Universe`, `Known`,
  `Unknown`); under an unknown sort the site waits, and at the last chance
  takes upstream's rule; the three alternatives go, so a tuple elaborates
  in time linear in its size (C126). Where the two readings are different
  terms (a dependent pair whose name is bound implicitly, an idiom
  bracket), it is still the alternative of the two
- retire: when a re-sync brings upstream's own single node
- upstream: nothing is sent (**Idris**)

## reducts

- symptom: the frontend reads the evaluator's normal forms with no
  statement of what they are, so every reading it proves sound rests on a
  check, when it runs, that the evaluator agreed with it
- sites: compiler/idris/src/Idris/Host.idr (`Reduces`, `Reduct`,
  `Defines`, `definition`, `definedOnce`; the four normalisers return a
  `Reduct`, its steps at quantity 0)
- workaround: none; the fork's own code (e5b39cb2): the one stated trust
  of the frontend in the evaluator, that a closed term's normal form is a
  reduct of it under `Reduces`, a relation that declares every step the
  evaluator takes, private to the trusted library (D68)
- retire: never; the fork's statement of its own evaluator
- upstream: nothing is sent (**Idris**)

## union-find

- symptom: at the pinned Idris, the solver retries every guess and every
  delayed search after each round until none progresses, and an unknown
  solved as another's application is a solution the store follows one at
  a time. The fork inherited it
- sites: compiler/idris/src/Libraries/Data/UnionFind.idr (persistent,
  every member naming its root, the smaller class renamed on a merge),
  Core/UnifyState.idr and Core/Unify.idr (`mergeUnknowns`, `wake`)
- workaround: none; the fork's own code (e5b39cb2): meta-to-meta
  unification merges two unknowns' classes, and each class holds the
  searches waiting on it; a failed search that changed nothing waits until
  an unknown its goal reaches is solved or made invertible; the first
  round retries every guess as upstream's did, each later round only the
  searches woken (D69, D107)
- retire: never; the fork's representation
- upstream: nothing is sent (**Idris**)

## ttc-delays

- symptom: at the pinned Idris, a `Delay` the elaborator inserts for a
  `Lazy` or `Inf` expected type and one the program writes are the same
  term in the TTC, though an inserted one stands for the whole expression
  the type delays, the `let`s placed around it included, which a reader
  with eager evaluation must tell apart. The fork inherited it
- sites: compiler/idris/src/Core/TT/Term.idr (`Delaying` on `TDelay`,
  `NDelay` and `PDelay`), Core/TTC.idr, Core/Value.idr, Core/Hash.idr,
  Core/Unify.idr and Core/Normalise/Convert.idr (laziness alone compared),
  TTImp/Elab/Lazy.idr, Core/Case/CaseTree.idr, Core/Coverage.idr
- workaround: none; the fork's own code (e5b39cb2): the origin is kept in
  the TTC beside the facts of ttc-facts (C124); conversion and
  unification compare a delay's laziness only
- retire: when a re-sync brings a TTC that keeps it
- upstream: nothing is sent (**Idris**)

## ttc-imports-pragmas

- symptom: at the pinned Idris, the TTC keeps no module's imports with
  their locations and no pragma the module writes, so a reader scanned the
  source for them; the parser took a pragma's kind as text
- sites: compiler/idris/src/Core/Context.idr (`Import`, moved from
  `Idris.Syntax`), Idris/Syntax/Pragmas.idr (`KwPragma`, one constructor
  per spelling the parser accepts; `PragmaUse`), Idris/Parser.idr,
  Parser/Rule/Source.idr (each use recorded in the parse's state, which a
  failing branch drops), Core/TTC.idr, Core/Binary.idr (`ModuleFile`),
  Idris/ProcessIdr.idr, Idris/Host.idr (`readDefinitions`)
- workaround: none; the fork's own code (e5b39cb2): imports and pragma
  uses, each with its location, kept in the TTC and given by
  `readDefinitions` with the definitions (U9)
- retire: when a re-sync brings a TTC that keeps them
- upstream: nothing is sent (**Idris**)

## typed-packages

- symptom: at the pinned Idris, the package directories a build adds are
  text, and a reader took a TTC's path apart to learn its package
- sites: compiler/idris/src/Core/Options.idr and Core/Context.idr
  (`PackageDir`), Idris/Package.idr and Idris/SetOptions.idr
  (`addPkgDir`), Core/Directory.idr (`Found`: the build directory, a
  package, an import directory), Core/Binary.idr (`Loaded`)
- workaround: none; the fork's own code (e5b39cb2): a package is recorded
  with its name and version as its directory names them, and each TTC the
  session reads with where the search found it
- retire: never; the fork's representation
- upstream: nothing is sent (**Idris**)

## interned-identifiers

- symptom: at the pinned Idris, a name's leaves (`Basic`, `Field`, `MN`,
  `DN`, a namespace's parts) are strings, so every equality of names and
  every lookup keyed by a name compares text character by character, and
  a builtin name the compiler recognizes or makes is found by its
  spelling. The fork inherited it
- sites: compiler/idris/src/Core/Name/Ident.idr (`Ident`, `Idents`,
  `internIn`), Core/Name/Known.idr (`Known`: the identifiers the
  compiler's own code spells, each at its ordinal; `roundTrip` and
  `below` checked when the compiler is built), Core/Name.idr and
  Core/Name/Namespace.idr (the leaves), Core/Context/Context.idr
  (`idents`: the session's one table, kept across resets and
  backtracking), Core/Context.idr (`intern`), Parser/Lexer/Source.idr and
  Parser/Source.idr (`RawToken` becomes `Token`: text becomes an
  identifier between lexing and parsing), Core/Binary/Prims.idr
  (`TTC Ident`)
- workaround: none; the fork's own code, the interned names of 0010's A0
  (D44): one table per session holds each text once, at its own id, so two
  identifiers are equal exactly when their ids are; a known identifier is
  a constant at its ordinal, never looked up; text becomes an identifier
  only at the lexer, the TTC's reader and `intern`; identifiers order by
  their text, so what is written from a map or a sort keyed by names is in
  the same order in every session, and a TTC writes an identifier's text,
  never its id
- stored terms (C183, A0's other half, the term arena as columns): a term
  being elaborated stays an unshared, located tree, as the elaborator's
  reads of locations need; when a definition is stored, its terms become
  columns in preorder, shared within the definition, with their locations
  as one more preorder column. The columns are frozen with the definition
  (an immutable array of `mlir-array`, on both hosts), so every read is a
  pure read of an immutable value and the fork states no new trust.
  Definitions refer to one another by interned name, never by a position
  in an arena, so no table grows under a read. The cost: nothing is shared
  across definitions, which one append-only arena would give only at the
  price of that trust; and the evaluator that reads the columns is
  re-implemented, not merged, at each re-sync (idris-fork), D44's
  accepted cost
- retire: never; the fork's representation
- upstream: nothing is sent (**Idris**)
