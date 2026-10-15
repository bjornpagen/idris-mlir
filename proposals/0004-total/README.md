<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0004: total by construction, every known item, and upstream's TODOs

**Status:** decided 2026-10-15 and executed the same day as one wave of
thirteen lanes on disjoint files, on the typecheck machine, which builds
no LLVM. It ran on top of the pipeline cutover (c7aa7b62, 5d5f3312) and
the representation wave (bfdcac70), whose proposals were deleted when
done (their last texts are at 484d6403). **Integrated, typecheck only:**
nothing of it has been built or run (§4.2), and nothing at all has run
on a build machine since c7aa7b62. The owner's build and the acceptance
of the marked fixtures come next, then the toolchain bump
([toolchain-bump.md](toolchain-bump.md)); §5 is what remains, each item
with where it goes next, and this file is deleted when the owner's build
is green and each item of §5 lives where it names. Claims are marked:
*read* (the path), *measured*, *recalled*, *conjecture*, *decision*.

## 1. Why

Fuel is a smell. A count that makes a computation stop, or decides
whether a program is accepted, means its termination has no argument the
code states. Three places still lacked that argument:
- **The C++.** Its loops ended "by structure", but that structure was
  only argued in comments.
- **The Idris half.** 18 frontend modules were `%default covering`,
  among them `Closed.idr`, whose reduction the representation wave made
  fuel-free. Its head-path argument was informal.
- **Upstream code we execute.** It carries about 60 TODOs on our paths,
  and we are happy to fix upstream.
The audits also left a list of known small items, our Idris fork carried
89 TODOs, and a few conventions were written for one particular machine.

The owner's representation-first guideline bound every lane
(`.claude/skills/compile-swarm-proposal`). Write the C++ as an Idris
programmer would:
- **Total by construction.** Every loop iterates a finite range, or a
  worklist whose finiteness is in its type.
- **Exhaustive.** Every closed enum is switched with no `default`, so
  `-Wswitch` checks it. A TypeSwitch over an open set ends in an internal
  error, never in a silent fallthrough.
- **Illegal states unrepresentable.** Use a strong type for a tag or an
  index. Use `FailureOr` or `std::optional` where a value may be absent,
  never a sentinel. Use a reference where null is impossible.
- **Linear handles where something must be consumed once.** For example,
  a move-only builder that must be finished.
- **Closed alternatives as sum types.** A `std::variant` with an
  exhaustive visit, not an enum with flags.
- **Pure analyses.** Immutable once built.
- **Constrained templates.** Use concepts.
- **One representation.** Generate the second copy from ODS, or delete it.

The runtime is the exception to this style. It is a cleanup and a speed
pass, as fast as it can be and open to inlining and optimization, in
musl's manner: small, flat code; hot paths visible to the inliner; no
abstraction that costs anything at run time. A type-safe sentinel is fine,
and so is `std::variant` where it is the fast representation. Where speed
and purity conflict, speed wins, and a comment says why.

## 2. Rules (in addition to AGENTS.md)

- **No fuel, anywhere.**
  - No recursion or loop is bounded by a count so that it stops. No
    greedy rewrite relies on an iteration limit to converge.
  - Termination is by structure: a finite range, a structurally smaller
    argument, or an insert-once or monotone worklist over a finite set.
  - In Idris, the totality checker must accept it (`%default total`;
    well-founded recursion through `Control.WellFounded`).
  - A size policy is a named constant: the inliner's caller cap, the
    sink's duplication limit, idr-stack's frame limit, the printer's alias
    cutoff. It only bounds growth or output, never termination or
    acceptance, and it is listed in `tools/policies.txt` with its reason.
    `tests/spec/no-fuel` allows exactly that file.
- **An optimization may stop at a budget** (*decision*, set during
  execution). A spent budget leaves the program less optimized and never
  refuses it, and the budget is a policy in `tools/policies.txt`.
  Whether a pattern set converges is a test's to state: `idr-canonicalize`
  counts the sweeps that end unconverged (its `not-converged` statistic),
  and its `test-convergence` option, which only fixtures set, makes one
  an error.
- **A linear value is used at most once on every path** (*decision*, set
  during execution). An unused one is released by counting, so a pure
  use of it may be dropped or sunk like any other. The verifier states
  the rule once (`foreign/idr/include/idr/IR/Verify.h:58-59`, *read*) and
  checks it after every pass.
- **The caller decides the CPU count.** `NCPU` / `IDRIS_MLIR_NCPU`
  defaults to every CPU (`tools/host.sh`), and nothing assumes one
  machine. The bootstrap's memory-per-job rule and the `NCPU=6`
  convention are gone.
- **The pin policy** (*decision*, the owner, 2026-10-15). The LLVM
  umbrella (llvm-project), modular and Idris 2 track main; every other
  dependency takes its latest release (Chez Scheme, CMake, Ninja, musl,
  GMP, simdutf, fast_float, snmalloc). ryu has made no release since
  v2.0 (2019) and stays 108 commits past it until the owner decides
  (AGENTS.md states the policy).
- **Upstream fixes are patches.** AGENTS.md's rule:
  `upstream/<NN>-<bug>/` with `llvm.patch`, a report, a reproducer, a
  `tests/upstream/<bug>/` check, an upstreaming plan and a PINS.md entry.
  Nothing is filed: sending is separate work. Nothing is ever sent to
  Idris. A fix to our fork is ours, recorded as
  `upstream/fork-<bug>/pull-request.diff` with its PINS.md entry.
- **Patch numbers per lane:** C5 took 26–29, U 30–39, C6 40–44, C3 45–47,
  C1/C2 48–49. As built: C5 used 26 and 27, and 26 was later folded into
  24 (§4.1); U, C6, C3, C1 and C2 needed none; 48 and 49 went to the
  runtime's submissions to simdutf and snmalloc.
- **Verification is typecheck-only.** C++ through
  `python3 tools/check-units.py <units>`; Idris through a private copy
  typechecked with `.toolchain/idris2`; never `make bootstrap`, `build` or
  `test`.

## 3. What was built

By area. Every item is coded and typechecked, and none is built or run
(§4.2). The C++ in `foreign/idr` and `runtime` grew by about 3,500 lines
net (*measured*: `git diff HEAD` and the new files).

### 3.1 Termination by construction in the C++

- **Two worklists, and every worklist one of them**
  (`foreign/idr/include/idr/Support/Worklist.h`). `idr::OnceWorklist<T>`:
  an element enters at most once, so it ends because the set is finite.
  `idr::MonotoneWorklist<T, Lattice>`: an element re-enters only when its
  lattice value strictly grew, and the lattice's height is in its type
  (`Lattice::kHeight`; debug builds assert at most `kHeight + 1` entries).
  Both are first in, first out. The label solve, binding times,
  identities, the specialization chain, the ready set, the scheduler and
  dead-code removal are OnceWorklists; every other loop iterates a finite
  range.
- **Tail position without a budget.** `TailPosition.cpp`'s 4096-step walk,
  which silently lost a tail call when it ran out, is an insert-once set
  keyed on a block and the known values of its arguments and live-ins
  (`TailPaths`, through MLIR's `Liveness`). It accepts tail calls the old
  walk refused, and it fixed an unsoundness: a path that loops back
  through the call's own block.
- **No greedy fixpoint where an ordered walk will do.** `Narrow/Copy`'s
  and `Narrow`'s greedy fixpoints are ordered walks with upstream's
  `OperationFolder`. idr-rc makes one context-sensitive solve; its third
  solve is gone. Borrows is event-driven, each function walked once.
- **Our canonicalizer is a pass of ours,** `idr-canonicalize`
  (`lib/Transforms/Canonicalize`), with the call-aware patterns bound per
  run, the `not-converged` statistic and the `test-convergence` option
  (§2). Patterns that move an effectful op re-notify the ops they unblock
  (`canon::CalleePattern::retryBetween`), so most consequences land in the
  same sweep.
- **The vector schedule.** Its required lowering runs unbudgeted; its
  unit-dimension cleanup is one named sequence,
  `@idr.vectorization.cleanup` (`lib/Target/Schedules.cpp`), budgeted by
  the `cleanupRounds` policy and suppressed when spent, which a fixture can
  run unsuppressed.
- **Upstream's own counts we execute** decide no acceptance: the 10-round
  cap of upstream's lowering passes (comments in `Pipeline.cpp`) and
  IntegerRangeAnalysis's widening, which only costs precision (comment in
  `Analysis/Ranges.h`).
- **The policies** are `tools/policies.txt`: the caller cap, the sink's
  duplication limit, idr-stack's three frame limits, NarrowLanes'
  `minExponent`, the schedule's `cleanupRounds`, the printer's
  `aliasFrom`, a folded constant's `constantBytes`, the runtime's three
  field widths, and the frontend's two trust points (§4.4).
  `tests/spec/no-fuel` holds the rest of the tree to none: no counted
  loop bound, budget constant or fixpoint loop in the C++, and no
  `covering`, `partial`, `assert_total` or `assert_smaller` in the Idris,
  per definition.

### 3.2 The frontend, total

Every module of `compiler/src` and `libs/` is `%default total`, with no
`partial` or `assert_smaller`; `assert_total` is left only at the two
trust points of §4.4. One part is not yet total, named in
tools/policies.txt and §5: the translation of applications (`covering` on
`Translate/Terms.idr`'s `term`, `suspend`, `delayed`, `letIn`,
`applyOver`, `bindHeld`, `application` and `headStep`, and on the
definitions of `Programs`, `Cases`, `Program` and `Driver` that reach
`term`) (*read*).
- **The reduction** (`Translate/Closed.idr`). `whnf`, `projected` and
  `implementationOf` end lexicographically on (the walk: definitions not
  yet unfolded, `Frontend/Walk.idr`; the phase; the term), and
  `cutRuntime` on (the walk, the term). A definition met a second time on
  a head path goes to Idris's normaliser (`host.normaliseAll`) under the
  guard that every definition it refers to ends, so the reduction has no
  trust point of its own. A projection is a record carrying the case
  tree's `IsVar` proof.
- **Dictionaries, instances, cases, the profile, the program, the driver,
  MLIR text and bytecode, and `Emit/**`.** The generated dialect printers
  take an abstract `Spelling` per payload, so printing recurses
  structurally (the text byte-identical by construction, *conjecture*:
  not compared on a build). Fixed on the way: `classify` looped on a
  binder that is not a Pi; `rootOf` cycled on stale indices.
- **The request chain is the worklist's** (`TS.chain`, `TS.requested`),
  with no parent pointers, and a request carries its site, owner and
  link. Keys, recursion (on `Walk`), types (Pi telescopes through
  `Translate/Given.idr`; a data instance's recursion on `chainsEnd`) are
  total. A nested data type (`data T a = L a | N (T (a, a))`), which hung,
  is refused as polymorphism (`tests/reject/polymorphism-nested-data`).
  `Holes.types` is a `List1`.
- **`Linear.Vec` is size-indexed** (`Vec n a`: a position is a `Fin n`,
  and `pop` takes a `Vec (S n) a`), so it has no crash path and its
  `assert_total` is gone; so are `libs/`'s `assert_smaller`s and
  `Ids.idr`'s `assert_total`.

### 3.3 Instance finiteness, proved

`compiler/src/IdrisMLIR/Proof/` holds the proofs, on base alone and free
of the fork:
- `AlmostFull.idr`: almost-full relations through ZT/SUP trees (Coquand,
  Vytiniotis and Wahlstedt), AF for `Nat`'s ≤, closure under weakening,
  union, inverse image and intersection, Dickson's lemma, finite fibres,
  and accessibility of an extension.
- `Generations.idr`: the first-in, first-out worklist as generations under
  a well-founded relation.
- `Requests.idr` and `Forms.idr`: one relation for a request (`Grows`,
  `Requested`, decided by `admit`). A request is a link: its definition by
  context index and its static arguments written as prefix tokens over
  finitely many forms, a literal weighing its magnitude. `afRequested` is
  proved outright.
- `Frontend/Finite.idr`: the worklist recurses on the erased
  accessibility proof, each request judged once; `chainsEnd` is proved and
  shared with the data-instance recursion. The link is the instance's
  identity (`Keys`), so identity and size agree; the old size ignored
  `DefImplicit` defaults, which was a soundness hole.

### 3.4 The fork

- **Total on the frontend's paths.** Fourteen fork operations the
  frontend calls are total (the context lookups, `toFullNames`,
  `substName`, `refsToLocals`, `getRefs`, `show` of a term and of an
  error, `hashArguments`, `mkdirAll`, `decode`, `loopsTerminate` and
  others), so their trusted fields could go; TTC decoders recurse on the
  bytes left, with TTC bytes and hashes unchanged.
- **Fuel removed:** `EvalOpts`' fuel and reduce limit, `computesType`'s
  depth of 8, `idempotentPower`'s 1024, and `%totality_depth`, which is now
  a parse error, `sizeCompare` memoised by subterm path (polynomial).
- **The size-change decision** works on dense graphs typed by their
  path's ends, `Dense n from to`, composed only by `andThen`, so a path
  composed in the wrong order does not typecheck; rows are a finite type
  (`Libraries.Data.List.Finite`: `NoDup`, pigeonhole). Check:
  `tests/compiler/fork-loops-terminate`.
- **Four upstream bugs fixed as fork code** (`upstream/fork-*`, PINS.md):
  a linear pattern `let` whose right side names an ambiguous function
  (`checkCaseDelayed` retried at linear only on a bare `LinearMisuse`;
  `fork-linear-ambiguous-let`), the totality depth
  (`fork-totality-depth`), an interface body that silently dropped what it
  cannot hold (`fork-interface-body`), and a with application inside a
  local definition or record update (`fork-with-application-scope`).
  Beside them, `fork-build-main` (`Idris.ModTree.buildMain`, the
  frontend's entry point) and `fork-total-frontend-paths`. Each has its
  `pull-request.diff` against the pin; nothing is sent to Idris.
- **The 89 TODOs:** six fixed (`WithClause.idr:258, 260`,
  `ProcessDecls.idr:152, 165`, `Local.idr:60`, `Interface.idr:73`); the
  other 83 triaged as not ours yet: upstream's refactors in progress,
  display and IDE details, language decisions refused or off our path,
  performance representations with no failure at hand. The triage is in
  the lane's report, not in the tree.

### 3.5 The IR core

- `enum class Tag` everywhere a tag is held; `isCellPointer()` on
  `Idr_ValueFactsTypeInterface` (true when every value is one non-null
  pointer to a live cell), which `Conversion/Facts.cpp` reads.
- About twenty null or sentinel states made unrepresentable: optional
  role tags, the `Held` bitmask, `SumLayout::tag`, the count word derived,
  one immutable `Layouts`, `DataRemap::create` returning `FailureOr`.
- The `Holds` analysis deleted, a twin of `holdsWorld`; `Symbols.cpp`
  split (`IR/DataRemap.cpp`); `definitionChain` (`IR/Grades.h`) for every
  walk along a value's chain of definitions.
- A call's `effects` is a `DefaultValuedAttr` (absent is any effect), and
  `effectsOf` is deleted.
- `GeneratingOpInterface` and `UpdateOpInterface` (`IdrInterfaces.td`);
  `idris-mlir-tblgen` maps `Idr_TagParameter` to `Nat`, so `KeyConAttr`
  is generated again.

### 3.6 Rewrites and effects

- `idr::CalleeEffects { const SymbolTable &symbols; }`
  (`IR/Flow.h`): with a table a call counts as its callee's effects,
  without one it may do anything; `ownEffects` is the one reading of a
  call's own effects. Sinking moves pure calls again.
- `canon::buildable` is the one leaf rule for constants, which
  `verifyConstant` calls.
- The flow vocabulary (`FlowAnchor`, `FlowPoint`, `FlowEdges::Edge`) is sum
  types with exhaustive visits.
- Exclusivity is context-sensitive, and split into its analyses;
  Escapes reads `RegionBranchOpInterface`, `isRepetitiveRegion` and
  `HasParallelRegion`.
- MoveOut fires from the read as well as the write.

### 3.7 The middle end

- Identities are a variant over an immutable record; a binding time is an
  `optional<BindingTime>`; specialization keys are typed.
- **Specialization keys generalize scalars** (*decision*). A key of an
  earlier one's shape that differs only in scalars (an integer, a big, a
  float, a string, any typed constant) is lifted: those scalars become
  parameters of one copy, and the call passes them. Only a key with more
  structure than an earlier one, the function's own or one on its request
  chain, is refused, and its call stays a call. `loop (Just n)` from a
  large literal ends with two copies. The argument is written once, at the
  head of `Transforms/Specialize/Specialize.cpp`.
- idr-optimize keeps a request record per function, judged by the grows
  rule, so a held function no longer restarts the chain.
- The passes that run only inside the inner pipeline are declared in
  `InnerPasses.td`, never registered, their constructors taking the run's
  state. `symbol-dce` replaces the hand-written reach of dead functions.
  PureCalls merges along the dominator tree and erases an unread pure call
  that takes a linear value (§2).

### 3.8 The memory passes

idr-rc's one solve (§3.1); Borrows walks each function once, with
`parameter()` only for entry-block arguments; about twenty-five states
made unrepresentable (Reuses' `Site` variants, `Point`, a `Width` enum, a
`Known` variant); analyses are plain values, not analysis-manager
entries; every chain walk goes through `definitionChain`.

### 3.9 Arrays and bufferization

- **Patch 24 extended** (`upstream/24-one-shot-module-function-interface`):
  cycles of calls analysed to a fixpoint over the call graph's strongly
  connected components (`FuncBoundaryFacts`), so a recursion's result is
  not copied at every level; the definite-alias writable rule, first
  carried as 26, folded in; a failure reported in a release build where it
  asserted.
- **Submission 27** (`tensorAllocationFn`) is a submission only: nothing in
  the tree reaches it.
- **`idr.element.update`**: `Vec.pop` moves the element out of the
  bufferized memref, with no increment and release around it; the two
  update ops lower through one `LowerUpdate`.
- `Record`/`recordOf` optional; the `Idr_ValueBuffer` constraint;
  permutation utilities from upstream.

### 3.10 Lowering, target and driver

- About twenty-five representation changes: the partition a variant,
  the runtime calls, a match's `Arm`, static members a variant, an
  `Action` enum; `--num-threads=0` refused.
- Big ops are plain runtime calls (`Bigs.cpp` keeps `nat.to_big`,
  `big.small` and `nat.to_extent`).
- A grouped sum's group word is encoded `group * 2 + 1`
  (`tests/idr/e2e/even-group.mlir`, §4.3).

### 3.11 The runtime

- The ASCII flag is gone (a string is ASCII exactly when its scalars equal
  its bytes); 46 dead size-class entries and other dead entries deleted.
- GMP's allocator is set once at start (`idris_rt_gmp_init`, which the
  tools call too).
- One `writeAll` in the platform layer, every OS call behind
  `rt::platform`; output by `memcpy`, a relaxed atomic length with fences,
  a flush that claims the buffer before it writes, `EINTR` retried.
- UTF-8 validated and counted in one pass (simdutf 9.3.0's
  `validate_utf8_with_counts`), malformed input decoded in one pass too.
- Big ops split into an always-inline small path and an out-of-line
  large one, the tagged arithmetic held once, in the runtime; allocation
  fast paths always-inline.
- simdutf's kernel is chosen by the target's startup check
  (`rt::platform::runsSimdutf`), so simdutf's own `cpuid` and its
  AVX512VPOPCNTDQ/CD bit collision are never reached (submission 48).
  snmalloc's arm64 yield asm is recorded (submission 49, PINS.md
  `snmalloc-arm-yield-asm`).
- `runtime/CMakeLists.txt` writes `<build>/runtime/c-flags`, so the nine
  toolchain tests that compile against `idris_rt.h` find the generated
  `idris_rt_ops.h`; they could not compile before.

### 3.12 Upstream, tests and tooling

- **Upstream.** 25, 02, 16 and 22 are prepared to file (their
  `submission.md`; nothing filed). About thirty TODO sites on our paths
  triaged, none affecting us; the folder's in-place loop is unreached.
  The toolchain bump is prepared, read-only:
  [toolchain-bump.md](toolchain-bump.md).
- **Tests.** `tests/spec/no-fuel`; `tools/policies.txt`; the specs scoped
  (the frontend-imports boundary, emit-dialects matching against
  building, no-behaviour-options' checks of tests); about sixty fixtures
  new or restated, the call-effects tests among them, restated under the
  rule that a call holds no effects; `tests/ACCEPTANCE.md`, the list of
  every marked file (§4.2). The fixtures that wrote a constant in the
  pre-cutover `#idr.con<@C, …>` form are swept to the form the parser
  has read since c7aa7b62.
- **Licensing.** 0001's L5 (the dialect generator writes the SPDX
  header) and L6 (`tools/licenses.sh`'s scope is every tracked file less
  one listed exclusion set; a fork file's holder read from the pin; the
  required texts derived from the identifiers in use; a port's attribution
  checked by its part). The sweep's `--apply` runs at integration.
- **Toolchain.** modular is a reference submodule (`third_party/modular`,
  `update = none`), and `sources/code/modular` is gone; simdutf v9.3.0 and
  fast_float v8.3.2, their latest releases; the bootstrap's jobs are the
  CPU budget; `tools/check-units.py` runs the typecheck build's compile
  commands, syntax only.

## 4. What execution decided, found and left on trust

### 4.1 Rulings

Each is in the code it governs; the rules of §2 are not repeated.
- **The reduction re-enters through Idris's normaliser.** A definition met
  twice on a head path goes to `host.normaliseAll` under the termination
  guard; the dictionary restart is `Finite`'s named trust point (§4.4).
  Head beta (ruling (b), shared by `Closed` and `Terms`): an environment
  binding for a syntactic redex, Idris's evaluator only for a lambda that
  arrives from the environment.
- **Instance finiteness is proved, not trusted** (§3.3), and the check
  and the proof are one relation, so they cannot drift.
- **A nested data type is polymorphism**, refused with its site, not
  hung on.
- **`%totality_depth` is gone**, its pragma a parse error, since a depth
  is fuel.
- **Scalars in specialization keys are lifted, never refused** (§3.7).
- **26 is part of 24.** Its bug does not reproduce on the pristine pin,
  only through 24's call model, so by AGENTS.md it is ours and belongs
  inside 24 (24's third pull request).
- **27 stays a submission**, not carried, since nothing reaches it.
- **simdutf's detection is never run**: the runtime's startup check picks
  the kernel.
- **modular is a submodule** read for reference, never fetched by a plain
  checkout.

### 4.2 Verification

Typecheck only, on the typecheck machine (*measured* there, 2026-10-15):
- **C++:** the whole tree typechecks with regenerated headers, 353 steps,
  0 errors (`make typecheck`'s C++ part).
- **Idris:** the host libraries and the fork build and install
  (`make typecheck-libs typecheck-fork`), and the frontend typechecks
  against that fork, every module through `Frontend/Driver.idr` (64 of
  64, no errors, no warnings), totality enforced (a deliberate non-total
  probe is rejected).
- **Specs:** `make check` passes, 33 of 33, after `tools/licenses.sh
  --apply`; `make typecheck` passes every part (configure, tblgen, C++,
  dialects, libraries, fork, frontend).
- **Nothing was built or run:** no `make build`, no `make test`, no
  `make test-idr`, no `make test-mlir-tools`, on either target. The
  exceptions are private probes: the runtime was compiled into a private
  archive and six runtime tests' programs (runtime-api, big-cell,
  stack-guard-page, double-print, page-size-mismatch, runtime-start) ran
  against it and matched their expected files; stock `idris2 --exec`
  probes exercised the size-change decision.
- **189 files carry `NEEDS-ACCEPTANCE:`** (`tests/ACCEPTANCE.md`, each with
  what to confirm): their expected output is what the code should do, not
  yet what a build showed.
- **Nothing has run on a build machine since c7aa7b62**, so this wave's
  build is also the first of the cutover's and the representation wave's;
  the stale constant syntax in about a hundred fixtures (§3.12) is what
  that gap had hidden.

Since no test could run, the lanes reviewed each other's diffs.

### 4.3 Bugs found

**Older than the wave** (each fixed):
- idr-optimize could run forever: a held function restarted its request
  chain (§3.7).
- A memo of Classes read a stale "borrowed" class after `sinkConsumers`
  moved a consumer past its root's last use: a use-after-free.
- Demand looped forever on an op that uses itself in an unreachable block.
- Freeing a cell of an even group crashed: the group word was stored raw
  (§3.10).
- TailPosition silently lost tail calls at its budget, and was unsound on
  a path back through the call's block (§3.1).
- Deduplication's hash was uninitialised, so copies could hash apart and
  merges be missed nondeterministically.
- Float and string keys never grew, so a loop stepping a `Double` made a
  copy per value (§3.7).
- The finiteness size ignored `DefImplicit` defaults (§3.3); `classify` and
  `rootOf` could loop (§3.2); a nested data type hung (§3.2).
- Four upstream Idris bugs (§3.4), and simdutf's AVX512VPOPCNTDQ bit,
  which shares AVX512CD's (submission 48).
- Nine toolchain tests could not compile (§3.11).
- About a hundred fixtures used a constant syntax the parser stopped
  reading at c7aa7b62.

**Introduced during the wave and caught by review** (each fixed, unless
noted):
- The size-change search composed walks in reverse, so a diverging
  3-cycle was judged total: unsound, since the verdict marks a function
  total. Fixed by `Dense` and `andThen` (§3.4).
- `implementationOf` stopped reducing a lambda field applied to arguments,
  so `show` on a dependent pair was refused as an implementation chosen at
  run time, and a higher-order dictionary came back unfolded into its
  constructor. A part cannot carry a function of its arguments (Idris's
  positivity check refuses it, and beta through an environment need not
  end: `(\x => x x) (\x => x x)`), so applying a part goes to the trusted
  evaluator's `normaliseHoles`, which applies lambdas and fills solved
  metavariables but unfolds no definition, and the phase gains a level
  (`Beta`, between as written and `Normal`). Left narrower than before
  the wave: a part applied again inside the `Beta` phase, and
  `cutRuntime` erasing a bound argument whose head is a lambda or an
  ordinary function when it is applied again
  (`tests/accept/show-dependent-pair`,
  `tests/accept/higher-order-dictionary`).
- The first trusted statement of the dictionary passes was false as
  typed (it asked a pass to learn a field, not to keep the ones known, so
  {a}, {b}, {a}, … descended): it is deleted, and the passes' trust is one
  call over a set that only grows (§4.4).
- MatchPatterns rebuilt a match before the string it reads (invalid IR);
  Exclusivity reported unreached copies live; a data race on a ready-set
  node's knowledge (now a worker-local `solved` and a `published` summary
  written between waves); a missed inlining; Borrows read past entry-block
  arguments; `element.update`'s formation had a hole; patch 24 asserted
  where it should fail; `mkdirAll` regressed on an execute-only ancestor;
  a range attribute made a `Bits8` of 128 or more a big's poison; the
  runtime's flush could write its bytes twice when the stack ran out
  inside it, and `writeAll` dropped output on `EINTR`; blind fixtures
  written against the wrong form.

### 4.4 What is left on trust

- **Idris's compiler, behind `IdrisMLIR.Frontend.Host`** (`host =
  assert_total`, listed in `tools/policies.txt`): the evaluator
  (`normalise`, `normaliseTypes`, `normaliseHoles`, `normaliseAll`), the
  elaborator (`buildMain`, `processPackageOpts`) and `checkTerminating`,
  which normalises as it goes. Irreducible while Idris's theory is not
  strongly normalizing and the elaborator runs what types compute.
  `loopsTerminate` is called directly, the fork's function being total.
- **The dictionary passes** (`Frontend/Finite.idr`, `translateFrom`: one
  `assert_total` on the call `passes (union known (keySet st.dicts))`):
  each pass learns a field the last took as never built, and the set of
  known fields only grows (a union), so the passes end exactly when
  finitely many fields are learnable, which rests on instance finiteness
  over every dictionary assignment and no type here states. Instance
  finiteness itself is proved; this is the one trust left in `Finite`.

## 5. What remains

Each item with where it goes next.

1. **The owner's build and acceptance** (HANDOFF.md): reconfigure first,
   so the runtime's `c-flags` exists; `make bootstrap`; `make build`,
   `make test`, `make test-idr` and `make test-mlir-tools` on both targets,
   the first run since c7aa7b62; accept the 189 marked files
   (`tests/ACCEPTANCE.md`). Then 0002's G1 (the qualification: determinism,
   the bench) and `make self`.
2. **The toolchain bump** ([toolchain-bump.md](toolchain-bump.md)): Idris 2
   to main 89ba32eb alone; then CMake 4.4.4 and LLVM main 7a83be39
   together, rebasing 06, refreshing 07 and retiring 01. Chez stays on
   v10.4.1 until 10.5.0 is tagged. Next after the owner's build.
3. **The polymorphic-recursion whistle** (the owner's decision): the
   relation refuses a chain that grows once and stops (`g Int` asks for
   `g (List Int)`, which asks for nothing), and its message then says the
   recursion builds deeper at each call. The option: refuse only on
   repeated growth, which is still almost full. Default: the rule as
   built. 0011's feature 2 owns the rule (its bounded case is reopened
   there), and taking the option changes it and `Proof.Requests`
   together.
4. **The dictionary passes, proved** (§4.4): the finite universe of
   learnable fields built from the request tree (König's lemma, the fan
   theorem), then a pigeonhole measure over the growing set replaces the
   `assert_total`. Goes with 0008's O3, Translate's instance fixpoint.
5. **The rest of Host** (§4.4): the evaluator, the elaborator and
   `checkTerminating` stay while Idris's theory is not strongly
   normalizing (`loopsTerminate` is called directly now that the fork's
   function is total). 0010's checker is where that changes, if anywhere.
6. **The translation of applications, total** (`Translate/Terms.idr`'s
   `term`, `application` and the functions they share, and the
   definitions of `Programs`, `Cases`, `Program` and `Driver` that reach
   them). Two changes make it so. (a) A structural spine: `term` walks an
   application's spine itself and builds one `Arg {written; translated;
   held}` per argument where the argument is a subterm, the translation
   and the closed-over values suspended there; every function that now
   calls `term` or `holed` on a list element (classify's values,
   arguments, finish, applyOver, identity, primitive, resolveMethod's
   rest) reads the thunks instead. (b) The head evaluation of the ruling
   in §4.1, shared with `Closed`: a syntactic redex `(\x => body) a` binds
   `x` in the environment (an alias for a variable, `TypeValue` for an
   erased argument, `Static` for a closed dictionary, a `Let` of the
   packed values with `Static shape (Just (FZ, hs))` for one that closes
   over runtime values) and translates `body` with no substitution; a
   value from the environment applied to arguments goes to
   `normalisedBy host.normaliseAll`, its runtime arguments stood for
   numbered hole markers mapped back to their thunks, and its normal form
   is translated in a phase that cannot evaluate again; metavariables are
   entered once on a path (`Walk`). Open for the owner: `normalisedBy`'s
   guard refuses an implementation that refers to a definition Idris does
   not prove total, which today is unfolded and translated as calls, so
   (b) keeps a structural path for that case or it would refuse programs
   that compile now. Next after the owner's build, before 0002's G1.
7. **Deferred designs:**
   - **Data-type bodies that hold buffers.** A constructor's field that
     holds an array is `tensor<…>` or `!idr.lin<tensor<…>>` in its data
     type's body, and a body is set once, so after One-Shot idr-bufferize
     remakes every data type whose body holds a tensor, and every type
     holding one of those, with the tensors' cell buffers (`DataRemap` of
     kind `buffers`), then retypes every function. The target: no body
     holds a tensor. From the frontend on, a field of array type is the
     array's cell buffer at its grade; `idr.con` takes the tensor and
     `idr.field` gives one, each the bufferization boundary that
     `to_buffer`/`to_tensor restrict` is (the store a release, the read
     not writable), and the data-type verifier refuses a tensor in a
     body. It changes what Emit writes for array fields, the verifier,
     `idr.con`/`idr.field`'s operand and result rules, and the store and
     heap-read models. Then `!idr.lin<T>` can be tensor-like where `T` is
     (submission 27's `tensorAllocationFn`, and a per-instance
     `extraClassOf` on `TensorLikeType`/`BufferLikeType`), and One-Shot
     bufferizes signatures and linear wrappers itself. It deletes the
     remap pass, its `toBuffer` leaf, `heldType`, the retyping loop, and
     the reason the release and link models exist. The world stays no
     tensor; a suspension's value follows the rule of a field. Goes with
     0003's next stage.
   - **Dependent rewrites.** Carrying a `rewrite`'s equality into MLIR,
     so that shape facts survive, comes with 0003's stage 2 (static
     extents through specialization); data-dependent shapes with its
     stage 5.
   - **A vectorizer gather from a memref**, an upstream feature; filed as
     upstream work when a program needs it.
   - **The canonicalizer cases a fold weakens** (a blocker a fold removes
     in place is seen on the driver's next sweep, by its design;
     `include/idr/Transforms/Canonicalize.h`); the next sweep is where
     they land.
8. **Strings that stand for things.** A string is a printed form, so
   inside the compiler a thing should have a typed identity and become text
   only where it is printed or handed to MLIR as a symbol. Today strings
   are identities in many places, each a fact the types cannot check and a
   comparison that can silently miss:
   - the frontend: `Request`'s `base`, `owner` and `chooser`; `TS.symbols`
     and the loops table keyed by `String`; `Recursion`'s Tarjan tables
     (`number`, `low`, `nodes`) keyed by a definition's printed name where
     its context index (a `Fin n`, as the proof's links use) is the
     identity; `ConId` holding its constructor's name;
   - Emit: the `keys` and `names` tables (`SortedMap String String`) and
     Bytecode's numbering by text;
   - the C++: the call-aware canonicalization patterns found by a debug
     label (`CalleePattern::kLabel`) rather than by their type; the
     runtime's callees and static data in `StringMap`s keyed by name where
     the ODS-generated runtime table could key them; `getName() == "main"`.
   The payoff is more than tidiness. A constructor's fields are strings,
   so any statement about "every field a translation can learn" is false in
   the type theory (a fresh field can always be spelt), which is exactly
   why the dictionary passes stay on trust (§4.4, item 4). With fields
   indexed by the data instances the requests reach, that universe is a
   type, and the passes' termination becomes a proof. Do it after the
   owner's build, area by area (the frontend's ids first, since item 4
   waits on them), each change keeping the printed text byte-identical.
9. **The primitives, cleaned up.** Audit the registry, the ODS ops and the
   runtime entries they call, as one list, for primitives that are dead,
   duplicated or badly shaped, and delete or reshape each across all three
   at once (one meaning, the runtime's). Known so far: `prim__scalarEnd`
   has no caller (its registry entry is gone), so the `idr.str.scalar_end`
   op and its folder, the runtime's `idris_rt_str_scalar_end` and its
   tests, Emit's `StrScalarEnd` and `tests/registry/string-iterator`'s
   case go; and `libs/mlir-linear`'s iterator computes a character's UTF-8
   width in Idris to make its steps structural, a second copy of a fact
   the runtime owns, which a primitive that returns the width (or the
   step) would make one. After the owner's build, with the string-typed
   identities (item 8).
10. **A pass to trim the C++'s verbosity** once the suites are green: it
   grew about 3,500 lines (§3).
11. **Upstream submissions ready for the owner to file:** 01 (test-only),
   02, 16, 22, 23 and 25 (`upstream/README.md`'s table); 48 and 49 need a
   human author (simdutf's and snmalloc's policies).
12. **The ryu pin** (the owner's): ryu has no release since v2.0 (§2).
