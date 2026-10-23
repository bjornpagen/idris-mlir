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
toolchain built with LLVM's and MLIR's assertions on in every stage our
code compiles against or links (D115): `print-local-aliases`
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
  (idr-constants, narrowing's copy analysis and Ranges, per function);
  remove-dead-values, if the qualification's trial brings it
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
- sites: foreign/idr/lib/Conversion/Lower/Functions.cpp (every function
  of the program takes `tailcc`) and TailCalls.cpp (its tail calls
  `musttail`); every arm64 target
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
  regions (upstream's region branch patterns, ours then on idr.match and
  idr.match_lit) read all of them, so an op of n regions costs n visits of
  size n: before the cutover, canonicalize in idr-optimize took 30, 120,
  223 s at n = 1k, 2k, 4k on a program of one `idr.match_lit` of n cases
  through the whole pipeline (the stress test that generated it is gone)
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
  ends in `ub.unreachable`, as Emit writes it and the e-graph's match
  rules leave it (foreign/idr/lib/Transforms/Joins/MatchRules.cpp).
  idr-optimize's leaf inlining calls upstream's `mlir::inlineCall`
  (foreign/idr/lib/Transforms/Inline/Inline.cpp) and idr-inline runs
  upstream's `Inliner` (Inline/InlinePass.cpp), both through the fast
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
- status (2026-10-21): carried; not filed; applies at 416f328b

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

## int-range-ne-either-view

- symptom: on llvm main at 416f328b (and on main on 2026-10-22),
  `isStaticallyTrue` decides `ne` only when both the signed and the
  unsigned ranges of the two sides are apart (`sne && une`), though a
  value lies within both its bounds, so either view proves it; through
  `evaluatePred`, neither `ne` nor `eq` folds where one view alone
  decides it, and a signed Int's zero test stays at run time when its
  range excludes 0 in one view only
- sites: none in our code; the patch. Every reader of `evaluatePred`:
  the numeric domain's interval instance (`Intervals::equal`,
  foreign/idr/lib/IR/Ops/Numeric.cpp), the bigs' comparisons
  (foreign/idr/lib/IR/OpsBigs.cpp), and upstream's `arith.cmpi` range
  under `IntegerRangeAnalysis`
- workaround: `upstream/102-int-range-ne-either-view/llvm.patch`:
  `sne || une`; checked by tests/upstream-int-range-ne-either-view, on
  the report's `ne-either-view.mlir`
- retire: drop the patch when the pin's `isStaticallyTrue` accepts either
  view
- upstream: upstream/102-int-range-ne-either-view; one pull request
- status (2026-10-22): carried; not filed

## fp-call-folding

- symptom: on llvm main at 416f328b, LLVM's constant folder computes a
  call of `llvm.exp`, `llvm.log`, `llvm.sin`, `llvm.cos`, `llvm.atan` or
  `llvm.pow` on constants with the compiling machine's libm
  (`ConstantFoldScalarCall1`, `ConstantFoldFP`, ConstantFolding.cpp), so
  a folded value could differ in its last digit from what the target
  computes (C198, C210). `llvm.tan`, `llvm.asin` and `llvm.acos` are not
  folded at the pin (*read*)
- sites: the driver's LLVM options (foreign/idr/lib/Driver/Main.cpp), the
  LLVM pipeline it runs (foreign/idr/lib/Target/Optimize.cpp); the
  lowering emits the nine math ops as upstream's MathToLLVM does, as
  those intrinsics, with neither `nobuiltin` nor `strictfp`
- workaround: upstream's own switch, no patch:
  `-disable-fp-call-folding` (ConstantFolding.cpp:68-71), which
  `canConstantFoldCallTo` and `ConstantFoldIntrinsic` read, set by the
  driver after the command line so that no argument unsets it. It is not
  narrowed: no call whose type holds a float folds in LLVM, `llvm.sqrt`,
  `llvm.floor` and `llvm.ceil`, which C198 keeps folding, among them;
  MLIR folds those before the lowering, and LLVM's lost folds are only
  optimizations (unmeasured). GlobalOpt's evaluator of static
  constructors folds calls without asking the switch (Evaluator.cpp:499);
  nothing of ours has one (the runtime's are refused,
  foreign/idr/lib/Driver/ReadRuntime.cpp), so nothing reaches it
- retire: never while LLVM folds with the compiling machine's libm
- upstream: none; the switch is upstream's

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
  other, share one timer. idr-optimize (its per-function pipeline),
  idr-narrow (idr-narrow-words on each function) and idr-inline
  (upstream's inliner, idr-simplify on each callable) run pipelines so:
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
  across `idr.data.match` and `idr.lit.match`, which carry
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
- sites: the generated `getSuccessorRegions` of `idr.data.match`,
  `idr.lit.match`, `idr.join` and `idr.loop`; `scf.index_switch` (71)
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
- sites: `idr.data.match` under `idr.join` whose cases all `idr.jump`; every
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
- sites: a known `idr.data.match` case ending in `idr.jump`; `scf.if` with a
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
  `scf.index_switch`, which `idr.data.match` lowers to, requires
  `scf.yield`, answers "the op" for every terminator and casts its
  terminators in its lowering; neither op accepts a terminator that never
  returns, so a case that only crashes needs a yield of poison values
- sites: the lowering of `idr.data.match` to `scf.index_switch`, nested jumps
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
- sites: every pool a tool hands MLIR, each worker on the stack the
  runtime's runner gave the tool's own thread, D33's measured bound with a
  margin, sized in one platform place (C43), through one strategy
  (`idr::driver::onToolStack`, foreign/idr/include/idr/Driver/Tool.h):
  the compiler's driver's pool (foreign/idr/lib/Driver/Compile.cpp),
  idris-mlir-reduce's, which it hands the context it makes
  (foreign/idr/tools/idris-mlir-reduce.cpp), and idris-mlir-opt's, which
  it hands `MlirOptMain` (mlir-opt-main-thread-pool)
- workaround: `upstream/75-thread-pool-stack-size/llvm.patch`:
  `ThreadPoolStrategy::StackSizeInBytes`; checked by
  tests/upstream-thread-pool-stack-size
- retire: when the pin's pool takes a stack size
- upstream: upstream/75-thread-pool-stack-size; one pull request
- status (2026-10-21): carried; not filed

## mlir-opt-main-thread-pool

- symptom: on llvm main at 416f328b, `MlirOptMain` runs its input on the
  pool of a temporary context it makes (`MlirOptMain.cpp:810-812`), and a
  caller cannot give it one, so idris-mlir-opt's workers run on the
  system's default stack with no signal stack, where the other tools'
  run on the tools' stack (thread-pool-stack-size,
  thread-pool-thread-start)
- sites: foreign/idr/tools/idris-mlir-opt.cpp, which builds its pool
  through `idr::driver::onToolStack` and sets it on the config it hands
  `MlirOptMain`
- workaround: `upstream/100-mlir-opt-main-thread-pool/llvm.patch`:
  `MlirOptMainConfig::setThreadPool(llvm::ThreadPoolInterface *)`, the
  pool every context `MlirOptMain` makes for its input shares when
  threading is enabled; `--mlir-disable-threading` still disables it.
  Its check, tests/upstream-mlir-opt-main-thread-pool, runs the report's
  `callers-pool.cpp`
- retire: when the pin's `MlirOptMain` takes a caller's pool
- upstream: upstream/100-mlir-opt-main-thread-pool; one pull request
- status (2026-10-22): carried; not filed

## thread-pool-thread-start

- symptom: on llvm main at 416f328b, `StdThreadPool` runs nothing of its
  client's on a worker before a task, and a new thread inherits no
  alternate signal stack, so a tool's worker that reaches its stack's
  guard dies of a bare SIGSEGV (SIGBUS or SIGSEGV on Darwin): the
  runtime's handler for the fault, which makes it the tool's internal
  error, has no stack to run on there
- sites: `idr::driver::onToolStack` (foreign/idr/include/idr/Driver/Tool.h),
  every tool pool's strategy, which names the runtime's function that
  installs the tools' signal stack on the calling thread
- workaround: `upstream/101-thread-pool-thread-start/llvm.patch`, applied
  after 75's: `ThreadPoolStrategy::OnThreadStart`, a `void (*)()` each
  thread a pool starts calls on itself before any task. Its check,
  tests/upstream-thread-pool-thread-start, runs the report's
  `signal-stack.cpp`, whose worker overflows into its guard and whose
  handler prints `ok` on the worker's signal stack
- retire: when the pin's pool runs a client's function on each thread it
  starts
- upstream: upstream/101-thread-pool-thread-start; one pull request, after
  75's
- status (2026-10-22): carried; not filed

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
  narrowing's copy analysis and Ranges, measured on it before any leaves
  it (C32, S3)
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
  (foreign/idr/lib/Analysis/Solver/TypeGraph.cpp),
  operation-equivalence-symbol-hook's
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
- sites: dead-code analysis's initialization (idr-constants'
  propagation, foreign/idr/lib/Transforms/Effects/Constants.cpp; the
  ranges analysis, foreign/idr/lib/Analysis/Ranges.cpp; idr-narrow's
  copies, foreign/idr/lib/Transforms/Narrow/Copy.cpp) and upstream's
  inliner in idr-inline (its use lists,
  foreign/idr/lib/Transforms/Inline/InlinePass.cpp), under the tools' one
  small stack (D33, C43, C99)
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

## sparse-region-successors-protected

- symptom: on llvm main at 416f328b (and on main on 2026-10-22),
  `AbstractSparseForwardDataFlowAnalysis::visitRegionSuccessors` is a
  documented override point declared `private:`, so an override cannot
  hand the successors it leaves back to upstream's propagation
- sites: foreign/idr/lib/Analysis/Ranges.cpp (`SummarizedRanges`, whose
  override refines a literal match's default region and hands every
  other successor to the base, C211)
- workaround: `upstream/103-sparse-region-successors-protected/llvm.patch`:
  the declaration moves into `protected:` beside `visitCallOperation`
  and `visitCallableOperation`; applies alone and after 89's. Checked by
  tests/upstream-sparse-region-successors-protected, on the report's
  `override.cpp`
- retire: when the pin declares it protected
- upstream: upstream/103-sparse-region-successors-protected; one pull
  request
- status (2026-10-22): carried; not filed

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
- sites: the bufferization of graded arrays, `!idr.graded<uses, hold, T>`
  tensor-like where `T` is (D43, L12)
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
- sites: `!idr.graded<uses, hold, T>` and every bridge of a graded tensor
  (D43, L12)
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
  patches applied in the order of their numbers, into
  .toolchain/<name>/src, stamped with them; the runtime compiles those
  copies
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

## effectful-argument-inline

- symptom: the stock Idris's inliner substitutes call by name, so a value
  a body never uses (an argument, a `let`, a pattern `let`'s scrutinee, a
  known constructor's field) is dropped with its effects, against eager
  evaluation: an `unsafePerformIO` write in an effectful `let` the body
  ignores never happens
- sites: everything the stock host compiles to run: stage 0, the test
  runner, the benchmarks' Chez baseline
- workaround: `upstream/96-effectful-argument-inline/idris.patch`: a
  value the body never uses that is a computation is kept, evaluated
  before the body by a `let` the inliner never inlines; a recursive call
  is an identity's only where its other arguments are no computations;
  checked by tests/upstream-effectful-argument-inline
- retire: when the Idris pin carries upstream's fix
- upstream: upstream/96-effectful-argument-inline; nothing sent (Idris
  takes no tool-written contribution)
- status (2026-10-22): carried

## coverage-repeated-split

- symptom: the stock Idris's coverage checker reports a covered case as
  missing, with a wildcard where a second split of the same variable
  (under a default) refines it, so a total definition is refused as not
  covering; an `impossible` clause for the named case does not help
- sites: everything the stock host checks under `%default total` or
  `covering`: stage 0 and the libraries
- workaround: `upstream/104-coverage-repeated-split/idris.patch`: the walk
  that proposes missing patterns names a re-split variable's arguments as
  the later split binds them; checked by
  tests/upstream-coverage-repeated-split
- retire: when the Idris pin carries upstream's fix (open issues #550 and
  #3710 report the symptom)
- upstream: upstream/104-coverage-repeated-split; nothing sent (Idris
  takes no tool-written contribution)
- status (2026-10-22): carried

## case-tree-fallthrough-copies

- symptom: the stock Idris builds a case tree exponential in the number
  of runs of constructor and wildcard patterns in the column it splits
  first, copying each run's fallthrough whole into every alternative: a
  definition of thirty such clauses ran 986 s to 18.7 GiB
- sites: everything the stock host checks: stage 0 and the libraries
- workaround: `upstream/105-case-tree-fallthrough-copies/idris.patch`:
  each copy of a fallthrough keeps, in its cases on the variable just
  matched, only the alternatives that variable can still take; checked by
  tests/upstream-case-tree-fallthrough-copies
- retire: when the Idris pin carries an upstream fix that keeps such
  trees small
- upstream: upstream/105-case-tree-fallthrough-copies; nothing sent (Idris
  takes no tool-written contribution)
- status (2026-10-22): carried

## size-change-call-paths

- symptom: the stock Idris's size-change closure appends both call paths
  of every graph it composes, kept only to report a loop, so the totality
  check of a mutual block takes time and memory exponential in its size
  (the checker's decoder in `Idris/Syntax/Tree.idr` passed 8 GiB in about
  115 s)
- sites: everything the stock host checks: stage 0 and the libraries
- workaround: `upstream/106-size-change-call-paths/idris.patch`: the path
  is lazy, built only where a loop is reported; checked by
  tests/upstream-size-change-call-paths
- retire: when the Idris pin carries upstream's fix
- upstream: upstream/106-size-change-call-paths; nothing sent (Idris
  takes no tool-written contribution)
- status (2026-10-22): carried

## delayed-case-expected-type

- symptom: the stock Idris elaborates a delayed case block at a fresh type
  of its own instead of the type its hole was given, so a
  pattern-matching lambda or `case` checked at a `Lazy` function type (as
  `maybe`'s second argument) is refused, "Can't solve constraint between:
  String and ?caseTy"
- sites: everything the stock host checks: stage 0 and the libraries;
  code of ours bent around it before the patch, to go once the toolchain
  carries it: harness/Fuzz.idr's two pattern lambdas written as cases
  (`checkOf`'s `OfFirst`, `checkerChecks`' `firstAgain`)
- workaround: `upstream/107-delayed-case-expected-type/idris.patch`:
  `delayElab` hands the delayed elaborator its hole's type, at which
  `checkCase` elaborates the block; checked by
  tests/upstream-delayed-case-expected-type
- retire: when the Idris pin carries upstream's fix for #3418
- upstream: upstream/107-delayed-case-expected-type; nothing sent (Idris
  takes no tool-written contribution)
- status (2026-10-22): carried

## case-split-pattern-fragment

- symptom: the stock Idris refuses a case (a record update) that splits a
  bound variable while an unsolved meta is applied to that variable: the
  clause's constraint leaves the pattern fragment, so an inferred lambda's
  type is never solved, or a `%defaulthint` fires first (upstream #62)
- sites: everything the stock host checks; code of ours bent around it
  before the patch, to go once the toolchain carries it: harness/Main.idr's
  `keep`, given a signature, and its `--threads` parse,
  `parsePositive {a = Nat}` with its comment naming this bug
- workaround: `upstream/108-case-split-pattern-fragment/idris.patch`:
  where an unsolved meta is applied to the variable a case splits and
  every clause splits it, the case function takes the variable twice,
  those metas applied to an unsplit copy at quantity 0; a case with a
  clause whose pattern there is a variable is left as the stock Idris
  builds it, since that clause solves the metas; checked by
  tests/upstream-case-split-pattern-fragment
- retire: when the Idris pin carries upstream's fix for #62
- upstream: upstream/108-case-split-pattern-fragment; nothing sent (Idris
  takes no tool-written contribution)
- status (2026-10-22): carried

## delayed-retry-doubling

- symptom: the stock Idris retries a failing delayed elaborator in a
  recoverable pass and an all-errors pass at every level of a nest, each
  running the levels inside again, so a type error under nested pattern
  binds takes time exponential in the nesting to report (eleven binds:
  about 50 s)
- sites: everything the stock host checks: stage 0 and the libraries;
  correct code is unaffected, an error in it is slow to report
- workaround: `upstream/109-delayed-retry-doubling/idris.patch`: an
  attempt that would begin with every metavariable unsolved that was
  unsolved when the last one failed is not run, its error kept; checked by
  tests/upstream-delayed-retry-doubling
- retire: when the Idris pin carries an upstream fix
- upstream: upstream/109-delayed-retry-doubling; nothing sent (Idris
  takes no tool-written contribution)
- status (2026-10-22): carried

## coverage-erased-index-first

- symptom: the stock Idris's coverage check of an erased function splits
  its erased indices before the arguments that determine them, so it
  reports impossible cases as missing, their explicit arguments all `_`
  (the checker's `Idris/Host.idr`: eleven proofs over `Mapped`; the
  frontend: 25 proofs and case blocks in `Proof/` and `Translate/`), and
  walks the tree under nested defaults an exponential number of times
  (`mappedContracts` past 300 s and 8 GiB)
- sites: everything the stock host checks under `%default total` or
  `covering`: stage 0 and the libraries
- workaround: `upstream/110-coverage-erased-index-first/idris.patch`: an
  erased function's coverage tree takes the arguments a run would keep,
  from the left, then the erased ones from the right; the tree a
  definition is evaluated by, and a kept function's coverage tree, are
  unchanged; checked by tests/upstream-coverage-erased-index-first
- retire: when the Idris pin carries an upstream fix
- upstream: upstream/110-coverage-erased-index-first; nothing sent (Idris
  takes no tool-written contribution)
- status (2026-10-22): carried

## coverage-nested-empty-type

- symptom: the stock Idris's coverage check refutes a missing case only
  by a pattern variable whose type no constructor's return type fits, so
  where a `Refl` matched inside a pair, or inside a case block's
  scrutinee, refines an argument, the tree splits that argument and
  reports its other values missing, with the argument that holds the
  equation unsplit (the frontend: `Held`'s `aloneWritten` and
  `lteSuccCases`, `Graph`'s `landsInto`, `joinedOver` and `intoClosed`,
  `Covers`' case blocks at 1252, 1733 and 1834, and `Covers`'
  `atNamedType`, whose case's pair is empty only by its equation and the
  part beside it together)
- sites: everything the stock host checks under `%default total` or
  `covering`: stage 0 and the libraries
- workaround: `upstream/111-coverage-nested-empty-type/idris.patch`: a
  type is empty also when each constructor that fits it takes an argument
  of an empty type, the arguments its return type determines replaced by
  what the type has there, or read under what the other arguments' types
  hold of the fresh names (a type with one constructor holds what its
  return type and its arguments' types hold, `Refl`'s two sides equal);
  an argument's type is looked into only while it is smaller than the
  type it is an argument of; checked by
  tests/upstream-coverage-nested-empty-type
- retire: when the Idris pin carries an upstream fix
- upstream: upstream/111-coverage-nested-empty-type; nothing sent (Idris
  takes no tool-written contribution)
- status (2026-10-23): carried; amended the same day for the equations
  across arguments

## do-local-definition-scope

- symptom: the stock Idris's desugaring of a `do` block leaves the names
  a bind, a let or a local block of the block binds out of the names a
  later local declaration's type must not bind as implicits, which a
  lambda, `let ... in` and a local block put there, so a typed local
  definition whose type names a local definition of the same block, `let
  v : Vect (length xs) Nat` after `let xs : List Nat`, binds that name as
  a fresh implicit and is refused (`length ?xs` ambiguous); a do-bound
  or let-bound name that is also a global's draws a false warning of an
  implicit binding (the frontend: `Growth/Graph`'s `build`, its
  `position` typed by `length slots`, and its warning for `entered`)
- sites: every do block the stock host checks: stage 0 and the libraries
- workaround: `upstream/112-do-local-definition-scope/idris.patch`:
  `expandDo` adds a bound name, a let-bound name and the names a local
  block defines to those names, as the lambda, `let ... in` and the local
  block it translates to do; checked by
  tests/upstream-do-local-definition-scope
- retire: when the Idris pin carries an upstream fix
- upstream: upstream/112-do-local-definition-scope; nothing sent (Idris
  takes no tool-written contribution)
- status (2026-10-23): carried

## type-implicit-binding-order

- symptom: the stock Idris binds an implicit argument still unsolved in a
  type as an argument of the type, outside the type's locals, before it
  retries the postponed constraints matching the arguments of two
  applications of one function, the step that solves it on a right-hand
  side, so a type naming `firstOf w`, `firstOf : P (xs ++ ys) n -> P xs
  n` and `w : P (as ++ bs) n`, is refused (`Can't solve constraint
  between: ?xs [no locals in scope] and as`) (the frontend:
  `Proof/Describes`' `firstPart`, `placedFirst w`)
- sites: every type the stock host checks: stage 0 and the libraries
- workaround: `upstream/113-type-implicit-binding-order/idris.patch`:
  `checkBindHere` retries a type's constraints in match mode before its
  defaults and before binding its unsolved implicits, the order a term's
  elaboration takes; checked by tests/upstream-type-implicit-binding-order
- retire: when the Idris pin carries an upstream fix
- upstream: upstream/113-type-implicit-binding-order; nothing sent (Idris
  takes no tool-written contribution)
- status (2026-10-23): carried

## let-delayed-elaborator-dropped

- symptom: the stock Idris retries the delayed case blocks of a let's
  value and drops its other delayed elaborators, so an ambiguous name in
  the value, waiting for its type, is never resolved, and its hole is left
  unsolved (`Unsolved holes: ... {delayed:N}`), in `let ... in` and in a do
  block's `let` (the frontend: `Growth/Graph`'s `build`, its three folds
  from `empty`)
- sites: every let the stock host checks: stage 0 and the libraries
- workaround: `upstream/114-let-delayed-elaborator-dropped/idris.patch`:
  `runDelays` keeps the delayed elaborators it does not retry and puts
  them back for the retries around it; checked by
  tests/upstream-let-delayed-elaborator-dropped
- retire: when the Idris pin carries an upstream fix
- upstream: upstream/114-let-delayed-elaborator-dropped; nothing sent
  (Idris takes no tool-written contribution)
- status (2026-10-23): carried

## size-change-as-pattern-doubling

- symptom: building a definition's size-change graph, which the stock
  Idris does for every definition whatever its totality, takes time
  doubling with each case block around a call: each case block wraps the
  definition's argument patterns in one more as pattern, and the
  comparison of an argument with an as pattern runs its inner part again
  whenever that part's result is known (`knownOr`), so a do block of
  thirty pattern binds checks in 118 s of user time, and linear
  continuations nested nine deep in 308 s (the e-graph prototype's slow
  elaboration of nested linear patterns,
  `audits/p0/design/idris-linear-check.md`)
- sites: every definition the stock host checks: stage 0 and the libraries
- workaround: `upstream/115-size-change-as-pattern-doubling/idris.patch`:
  `knownOr` returns the known result instead of the comparison that gave
  it; checked by tests/upstream-size-change-as-pattern-doubling
- retire: when the Idris pin carries an upstream fix
- upstream: upstream/115-size-change-as-pattern-doubling; nothing sent
  (Idris takes no tool-written contribution)
- status (2026-10-23): carried

## record-update-variable-type

- symptom: the stock Idris reads the record a record update names only
  off the type the update is expected to have, so an update of a variable
  in a let without a signature waits for the let's type, and is refused
  ("Can't infer type for this record update") where that type is never
  found, though the variable's own type names the record (the test
  runner: `harness/Covers.idr`'s `scanLine`, its update of `st` before a
  case with a catch-all)
- sites: every record update the stock host checks: stage 0 and the
  libraries
- workaround: `upstream/116-record-update-variable-type/idris.patch`:
  `checkUpdate` reads the record's name off the variable's type in the
  environment while the expected type is not yet a type constructor's,
  and checks the update against the expected type as before; checked by
  tests/upstream-record-update-variable-type
- retire: when the Idris pin carries an upstream fix
- upstream: upstream/116-record-update-variable-type; nothing sent (Idris
  takes no tool-written contribution)
- status (2026-10-23): carried

## case-scrutinee-postponed-constraints

- symptom: the stock Idris reads a case's scrutinee type straight after
  checking the scrutinee, before solving the constraints that check
  postponed, so a scrutinee whose type only such a constraint fixes is
  refused ("Can't infer type for case scrutinee"): `case given >>=
  parseInteger of`, where `Maybe String =?= ?m ?a` waits for the search
  for `Monad ?m` to make `m` invertible (the test runner:
  `harness/Determinism.idr`'s `determinismSeed`,
  `harness/Universal.idr`'s `actionsSeed`)
- sites: every case the stock host checks: stage 0 and the libraries
- workaround: `upstream/117-case-scrutinee-postponed-constraints/idris.patch`:
  `checkCase` solves the postponed constraints (no default applied) where
  the scrutinee's type is still headed by a metavariable, before it gives
  the type up; checked by tests/upstream-case-scrutinee-postponed-constraints
- retire: when the Idris pin carries an upstream fix
- upstream: upstream/117-case-scrutinee-postponed-constraints; nothing
  sent (Idris takes no tool-written contribution)
- status (2026-10-23): carried

## clause-metavariable-pruning

- symptom: a case's type, found from a clause whose result holds a
  metavariable the clause made (a string literal's type, fixed later by
  the body or the default), is a term over the variables outside the
  clause, and the stock Idris postpones it ("Can't shrink") because that
  metavariable stands applied to the clause's variables too, so a pattern
  let of such a case is refused ("Can't infer type for case scrutinee";
  the test runner: `harness/Verdict.idr`'s `editLines`, `let (mark, l) =
  case e of Keep x => (" ", x); ...`)
- sites: every unification the stock host solves in a term: stage 0 and
  the libraries
- workaround: `upstream/118-clause-metavariable-pruning/idris.patch`:
  where a solution does not shrink, `unifyHole` prunes each elaborator's
  metavariable in it of the clause's pattern variables it cannot depend
  on (solving it as a fresh one over those it keeps) and shrinks the
  solution again; checked by tests/upstream-clause-metavariable-pruning
- retire: when the Idris pin carries an upstream fix
- upstream: upstream/118-clause-metavariable-pruning; nothing sent (Idris
  takes no tool-written contribution)
- status (2026-10-23): carried
