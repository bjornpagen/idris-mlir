<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane 21: perf-tracing (the other agent's self-hosting perf work)

Subject: the work of the agent the owner runs in parallel on proposal
0001's S3 (the release idris-mlir compiling stage 1), whose commits carry
the trailer `Co-Authored-By: Muse` / `Muse Code`. Audited at e96bb991
(the working tree) and origin/main as fetched on 2026-10-21, last at
51a4771b (11:04).

Status: written 2026-10-21, against origin/main at 51a4771b (fetched
four times: 101edbc5 at the first two, 51a4771b at the last two).

## 1. Reading notes

What in P0 (`proposals/0000-mlir-native.md` at the working tree, which
is e96bb991 plus the uncommitted P0 and audits) bears on the other
agent's work, written while reading.

**§1-§2 (the brief).**
- §2's last block, "The trait layer, as another agent read it today",
  is the other agent's report to the owner, *recalled*, with a
  correction (lane 07): no `Decides` trait existed at e96bb991. It now
  does, on origin/main, in 101edbc5 (section 2 below). §2's correction is
  therefore stale in the sense that the report described 101edbc5's work
  before it landed; the trait is not on the checkout P0 audits.
- §2 "Upstream patches": 06, 28 and 63 reach no pass of ours "since
  16005000 dropped `remove-dead-values`" — a consequence of the other
  agent's commit, already reflected in P0.
- §2 "Still on upstream's dataflow framework": `Analysis/Constants`,
  `Analysis/Ranges`, `Ownership/Borrows`, `Narrow/{Lanes,Copy}`,
  `Tail/Returned`, `Effects/Constants`. After ffa91113 exclusivity is
  off the list; these are the solves that remain, i.e. the next
  candidate walls.
- §2 "`lib/Support/Actions.cpp` and `Profile.cpp` the tracing": the
  other agent's measuring instruments (the action profiler).

**§3 (what history taught).** The wall table is almost entirely the
other agent's commits: ffa91113 (627 GB, exclusivity on
`DataFlowSolver`), 16005000 (52 GB, `remove-dead-values`; 43 GB
`idr-frames`), e96bb991 (graph build did not finish, quadratic in a
match's case count), b8301ebe (47 GB `idr-rc-stack`), 3a96c407 and
7987388b (75 million pattern attempts). 98c6315c and 73bba53f are not
its (Claude trailers). §3's conjectures to be confirmed or refuted from
its record: (a) upstream's framework failed on its state model, not its
algorithm; (b) the interface layer's costs scale with region and
successor counts; (c) the walls that were ours were fixed by
representation.

**§4 (the bar).** Order of preference: upstream as is, upstream
patched, our own solver in the solver layer with a header naming what
upstream lacks *and the measurement that shows it*. The other agent's
commit messages are exactly such measurements; P0 needs them as the
header text of each solver.

**§5.1 (mlir-analysis).**
- A4 (*measured* by wave 1, not on our IR): a 1-bit state costs about
  2.9 KB at the pin, >90 % two 64-bucket hash tables (the per-anchor
  inner `DenseMap<TypeID, ...>` and the dependents' `SetVector`). P1 (two
  declarations) cuts it about fifteenfold; P2 (flat map + bump arenas)
  eighteenfold; our own bit in a `BitVector` by value number: 0.13 B.
- A5: the solver's `StorageUniquer` takes a sharded lock per program
  point lookup though the solver is single-threaded; program points are
  never freed.
- A6: per-function scope is supported (`top` = a function); nothing
  between function and module; `eraseState` per anchor.
- A7: `DeadCodeAnalysis` + `SparseConstantPropagation` must be loaded
  beside every analysis; SCCP's `getPropertiesAsAttribute` grows the
  context.
- B2-B4: liveness creates a state for every value; `remove-dead-values`
  is whole-module only for its interprocedural part.
- C2-C4: `getPredecessors`, `getPredecessorValues`,
  `getSuccessorOperandInputMapping()`, `isRepetitiveRegion`,
  `insideMutuallyExclusiveRegions` are O(N) per call on an op of N
  regions, O(N²) when asked per region; C3: a sparse forward visit of a
  region branch's results joins all N terminators (no incremental join).
  5.1.2 item 5: "e96bb991's quadratic graph build is this lesson".
- D3: `RecursiveMemoryEffects` on a 30,000-case match walks the whole
  body on every `wouldOpBeTriviallyDead` query.
- G2: the action framework and debug counter as the upstream way to
  trace units of work — directly relevant to `Support/Actions.cpp`.
- H1 (arithmetic): upstream liveness ≈ 5 KB per value, so 52 GB ⇒
  V ≈ 10 million values; H2: 627 GB ≈ 200 million states at 2.9 KB.
  Both are *conjecture* that only the other agent's counts can test.
- Designs: 1 (patched framework per function + summary layer,
  recommended), 2 (patched, whole-program; "the measured baseline Design
  1 is compared against"), 3 (the solver layer: dense numbering,
  BitVectors, edge tables read once per op, concept-constrained
  lattices, actions per unit of work), 4 rejected (a general framework
  of our own).
- QA1-QA4 (owner) and W1-W7 (wave 2): W1 asks for V, B, P, F and the
  regions-per-op distribution on stage 1 at each solve point — the other
  agent's instrumentation is the only place such counts can come from.

**§5.2 (mlir-ods).**
- E1: a `MatchAnyOpTypeTag` pattern is merged into every op's list;
  "the 75 million attempts of 3a96c407 are what the any-op list does by
  design". M6 and Design 2 ("rooted rewriting", no `MatchAnyOpTypeTag`
  anywhere) are what 3a96c407 and 7987388b already did.
- E2: the greedy driver re-walks the region each iteration and re-queues
  every ancestor on a change (patch 62's quadratic on a match); E3 the
  walk driver terminates by construction.
- B2: a trait can supply an interface method (`AlwaysSpeculatableImplTrait`
  for `ConditionallySpeculatable`): the shape the other agent praises in
  `GuardedOp`. B4: `hasTrait` is a virtual call folding TypeID compares;
  on a typed op `constexpr`.
- M1: one effects model; "does IO" asked as `isa<IOResource>` over effect
  instances, `PerformsIO` deleted, world-operand rule as one trait
  supplying `getEffects` (row 3) — the other agent's "wave 3" (IO
  trait-supplied effects) in the same words.
- M4: traits stating a checkable fact get a `verifyTrait` (`SameValue`);
  marker traits nobody reads become a root or an interface, or go — the
  other agent's "wave 1" and gap 4.
- M5: `isa<ReturnOp, YieldOp>` → `ReturnLike` /
  `RegionBranchTerminatorOpInterface`; `Sink.cpp:114`, `Forms.cpp:132`
  → interface queries — the other agent's "wave 2" (ladder cull).
- M11, Q6, W7: verification after every pass at 70,000 functions; W7
  asks for a measured run with and without `--verify-each` — a
  measurement only the stage-1 runs can give.
- M10, W6: 98c6315c's context lock and 73bba53f's quadratic table.

**§5.3 (llvm).**
- B1: `isa<A, B>` over ops costs what `hasTrait` costs; the case against
  it is representational (a fact restated per use), not speed. So the
  other agent's "ladder cull" (its wave 2) buys no measured time; it is
  a representation item, to be argued as such.
- B7, M5: a non-empty `DenseMap`/`DenseSet` is ≥64 buckets, about 1 KB;
  "one per node" containers are the shape of §3's walls. LLVM's move is
  dense numbering (block numbers, `LazyValueInfo`'s vector by block id).
- C7, M6, M7: "Our recent fixes are the SCCP shape, found by hand":
  ffa91113 ("marks the program graph"), b8301ebe ("the flow graph,
  marked"), 16005000 ("a component's answer is data") are named; S1
  generalizes them (one graph, one state vector, `mark(graph, seeds)` as a
  BitVector BFS, frozen `Solution`). S1's cost note: "a graph build that
  must itself be linear (e96bb991's quadratic interface queries were in a
  graph build)".
- D1: `llvm::parallelFor` inside an MLIR pass puts a second pool beside
  the context's — relevant to any parallel loop the other agent adds.
- M8: 98c6315c's lock is "a fact kept in a uniqued mutable type rather
  than in frozen analysis data".
- Q-llvm-3 (numbering: per solve, cached analysis, or upstream patch),
  Q-llvm-6 (one thread vs many, compare solutions), Q-llvm-7 (the giant
  SCC): 101edbc5's per-function `Positions` numbering is a concrete
  data point for Q-llvm-3.

**§5.4 (modular).**
- F7, item 4, Design 4: Modular's `CFGAnalysis` — successors per
  terminator, predecessors inverted from them in one pass, cached — "the
  quadratic shape goes when predecessors are inverted from successors in
  one pass and cached". e96bb991 did exactly this for exclusivity's graph
  (section 2).
- F5, item 5, Design 3: Modular's SCCP copies its whole map into each
  nested region, "the copy-per-edge shape of our b8301ebe wall"; IPDF's
  rows-shared-until-written is the alternative representation.
- F16, Q-M2: Modular disables verification after every pass in
  production; verification's cost at 71 MB "is real".
- F19: tracing compiled out by a `constexpr` level in the type
  (`TimeTraceScope<Trace::kCompiler, ...::isEnabled()>`) — a model for
  the cost of our own tracing when off.

**§5.5 (cxx26).** Nothing on the perf runs directly; finding 18: trait-
and interface-rooted patterns are indexed per op at freeze (what
3a96c407 and 7987388b rely on). D3's `solveForward` sketch names
`ExclGraph` as an example graph.

**§5.6 (ecosystem).**
- B5: CIRCT's Arc moved one analysis off `DataFlowSolver` for 130 s →
  <200 ms (650×), "the move our ffa91113 made for exclusivity, made
  three years earlier".
- Item 1: a state exists only for what the problem is about; W-E2 asks
  each solver's domain counted at stage 1 against the values whose type
  leaves the question open — a measurement only the other agent's runs
  can make.
- Item 8: structured walks copying state per branch at a 30,000-case
  match is b8301ebe's wall; the fix is per-case deltas.
- Item 9: queries on a big region op once per op; "e96bb991 is this".
- W-E5 (budgets), W-E6 (every per-query walk of a match's regions),
  W-E9 (state copied per edge): checks the other agent's commits partly
  answer.

**§5.7 (library).** M1-M5 map each §3 wall to theory: M3 calls e96bb991
"validation repeated where a parse belongs" (query once per op, keep a
CSR edge array); M4 calls idr-rc-stack's 47 GB "a dense set per value
copied per edge" whose sparse form is one bit per value; M2 calls the
52 GB "a one-bit problem held as a lattice per value". M11: "a pattern
that matches any op is a full scan (the 75 million attempts of
3a96c407)".

**§5.8 (dialect-design).** DS4 rows bear on 101edbc5's trait work:
`SameValue`, `TakesReference`, `BuildsValue`, `CarriesOperand`,
`ResultCarriesOperand` → "one forwarding interface declared in ODS";
`PerformsIO`, `ObservableIO`, `IO` resource, world operands → effects on
`World`'s children; `ConsumesOperands`, `ConsumesOnly`, `Lin` →
`MemFree<Idr_Linear>`. The other agent's report keeps `SameValue` and
asks it be verified; DS4 deletes it into an interface. These disagree in
direction (section 3).

**§5.9 (mlton).**
- H's table maps every §3 wall (all but two are the other agent's
  commits) to the MLton mechanism that forbids it; M2: "the three fixes
  already made ... are each a step towards MLton's model, taken one
  analysis at a time".
- A3, G2.10, **Design 6**: MLton's driver prints, after every pass, the
  live heap and its state structures' statistics; Design 6 proposes "a
  Tracy plot per pass of the solver layer's arena bytes, cell counts and
  handler counts, and the process's footprint, so the next wall is a
  number in a trace, not a killed process". That is the other agent's
  own method made permanent.
- Q-W3 (what a 30,000-arm match costs), Q-W7 (the grade verifier's cost
  per pass on stage 1), Q-W9 (any-op patterns in idr-optimize): the
  other agent's records are the only measurements bearing on them.

**§5.10 (rc).** M6: "the commit messages of ffa91113 and e96bb991,
'marks the program graph', suggest it is already this shape [a monotone
two-point marking, O(V+E)]; wave 2 measures it". W4 asks for
idr-rc-exclusive's graph after e96bb991, its peak memory and time on
stage 1. R1's risk: "the graph's construction (e96bb991's quadratic
query)".

**§5.11 (oom).**
- O1 restates 0001's 43 GB (idr-frames, jetsam low-swap on 96 GB), 52 GB
  (stopped by hand), 47 GB (idr-rc-stack).
- K5: jetsam kills on `phys_footprint`, which counts compressed pages;
  an "RSS" figure under-reads it — every footprint number in the other
  agent's records must say which measure it is.
- C1-C3: MLIR has no memory column; LLVM's `-track-memory` reads the
  system malloc, blind under snmalloc; rustc's per-pass RSS is the
  pattern. A2 (a per-pass footprint `PassInstrumentation`), A3 (name the
  death on a pressure signal, flush the action profile), A4 (budgets in
  program units). W2-9: "whether the action profile is written
  incrementally, so a killed run keeps its tail".
- C7: a budget in bytes or seconds breaks stage 2 = stage 3.

**§6-§9.** §6 names this lane: "a twenty-first on the tracing and
performance work the owner's parallel agent pushes to origin/main". §8
groups the owner's questions; those this lane gives evidence for: Q2
(does S3 run alongside P0 as measurement), Q4 (who runs the release
idris-mlir on stage 1 for P0's measurements), QA1-QA4, Q-O2, Q-llvm-3,
Q-llvm-6, Q-llvm-7, ods-Q6/Q-M2/Q-O5 (verification), oom-2, oom-3,
drv-Q1 (assertions in measurements), drv-Q6 (profiling stage 1: a
buffered time trace or the streamed action profile, "about 1 GB a
minute in idr-optimize"), T-Q5 (measuring the verifier), hist-Q1
(measure before adopting, patch before dropping: "two removals (ffa91113,
16005000) that would each have failed it"), hist-Q2 (unbuilt landings),
hist-Q5 (reversals without a ruling: "595ed341 to ffa91113"). §9 holds
four decisions (D1-D4), none about the other agent's work.

## 2. The other agent's work

### 2.1 Which commits are its

*Measured*: `git log origin/main --format='%h %ad %(trailers:key=Co-Authored-By,valueonly)'`
after `git fetch origin` (twice, 2026-10-21). Twenty-three commits carry
a Muse trailer, in three generations:
- **Muse Spark** (`noreply@muse.dev`), 2026-10-12, eleven commits
  (1da82fe7 … 042608a4): test-idr fixtures, parsers, the quantities
  check, idr-isolate, Reuses' segfault. Not perf work; outside this
  lane except as history (lane 20's).
- **Muse Code** (`noreply@meta.com`), 2026-10-20, six commits: c4a046e0,
  31daec54, 276e8878, 3276be33 (expected files, two checks, an excl
  grade at the frame lifetime, the audit), then 3a96c407 and 7987388b,
  the first perf commits (the MatchAnyOp cutover).
- **Muse Code (muse-wonder-full-1.0)** / **Muse** (`noreply@muse.dev`),
  2026-10-20 to 21: 16005000, b8301ebe, 9db9813d, ffa91113, e96bb991
  (all in the working tree), and on origin/main only **101edbc5**
  (09:43) and **51a4771b** (11:04, found by this lane's last fetch: a
  measurement record and a bug entry, no code).

Every one of these is authored "Bjorn Pagen" with the trailer as the
only mark. The perf line is 3a96c407 → 51a4771b, nine commits in about
eighteen hours; twenty-four Muse commits in all.

### 2.2 Its instruments and method (*read*)

- `proposals/0001-self-host.md:101-112` (at e96bb991): "trace it, don't
  guess": the release `idris-mlir` with `--profile-actions-to=<file>`
  (MLIR's action profiler, a Chrome trace of every pass, every
  idr-optimize node, every pattern application and every tagged
  transform, `lib/Driver/Run.cpp:290-298`), `sample <pid>` when the trace
  stops growing, aggregation per action/pattern/node, reduction of a
  stuck node to a standalone module. The trace grows about 1 GB a minute
  in idr-optimize (`0001:107`).
- Our side of the instruments: `include/idr/Support/Actions.h`
  (`TaggedAction`, `perform`: a transform as an MLIR action, skippable
  by `-mlir-debug-counter`), `include/idr/Support/Profile.h` (LLVM's time
  trace behind `--time-trace`). None was changed by the other agent
  (*measured*: `git log` of both files ends at 1b2e31da, Claude).
- What each number below is: a jetsam kill's footprint (627 GB), an RSS
  at a jetsam kill (43 GB), a process stopped by hand while sampling
  (52 GB), a live sample (47 GB, "sampled live at 41 GB"), a sampler's
  share of a pass's samples (101edbc5), an action count and duration
  from the action profile (75 million, 336 s), a debug-build timing of a
  generated fixture (1.3 s), and verifier error counts. No commit
  records `-mlir-timing`, a footprint per pass, or V/B/P/F counts. **No
  S3 record exists under `bench/records/`** (*measured*: `ls
  bench/records` at origin/main: the last is `2026-10-17-self-growth.md`).
- 51a4771b adds a second instrument and the first written record:
  `audits/flamegraph-2026-10-21.md`, every compile of `make test-idr`
  (343 fixtures) and `make test` (480 programs) sampled with macOS
  `sample` at 1 ms on a hand-configured `RelWithDebInfo` build
  (`build/profile`, frame pointers, no LTO), swapped in for `build/dev`
  by a symlink for each run; wait-leaf stacks bucketed out; per-pid RSS
  every 2 s; method written out, raw traces kept out of git, scripts
  "throwaway". It measures the suites, **not stage 1** ("A stage-sized
  module … This is the missing measurement").

### 2.3 Commit by commit (each *read*: `git show <hash>`)

| commit | wall it met on stage 1 (whose measurement, how) | what it changed | measured / inferred in the message | tests and suites the message reports |
| --- | --- | --- | --- | --- |
| **3a96c407** (10-20 17:21) | idr-optimize: sinking, case-of-case, drop-empty-string-case were `MatchAnyOpTypeTag` patterns, "tried 75 million times in 31 traced minutes" (action profile) | the three patterns rooted at `MatchOpInterface` / `MatchLitOp`; the value-side and consumer-side scans deleted (`Canon/Sink.cpp` `holdingMatch`, `Canon/MatchPatterns.cpp` `emptyCaseAbove`); −86/+36 lines | measured: the attempt count; inferred: that a rooted pattern is re-tried "on any change under the match, whose ancestors it requeues", which is how the driver reaches it now | none named |
| **7987388b** (10-20 18:02) | none new: completes the cutover ("MatchAnyOpTypeTag occurs nowhere in the tree now") | `Narrow/Ops.cpp` NarrowWord rooted per op of the generated `IdrBigToWord.inc` list plus four named ops; defunctionalization's `RetypePattern` and the reducer's `PoisonResults` rooted at **every registered op** but a hand list of nine (`Defunctionalize/Patterns.cpp:277-284`); new trait `Idr_BuildsValue` on five ops, read by two expect properties (`Expect/Does.cpp:34`, `Expect/Placement.cpp:117`) | inferred only | none named |
| **16005000** (10-20 20:32) | idr-frames: "jetsam-killed at 43 GB", one action of 336 s on `bindGrammar`'s component (action profile); remove-dead-values: "the untraced run sampled there at 52 GB" | frames: one answer sum per component, one run per member, one resume per result type (`Tail/Frames.cpp`, new `FramesTypes.cpp`, `FramesPlan.cpp`; a component whose member result no constructor may hold keeps plain calls, `FramesPlan.cpp` `isFieldType`); **upstream `remove-dead-values` removed from the pipeline** (`Pipeline.cpp:96-106`); new fixture `tests/frames-answer-types` (differential) | measured: the two kills; **inferred, unmeasured**: that what remove-dead-values alone removed is decided "in the optimizer's specialization" and "counting drops like any other dead owned value" (its own bugs.md entry: "unmeasured there") | check 34/34, test-idr 341/341, test-unit, test-mlir-tools |
| **b8301ebe** (10-20 21:27) | idr-rc-stack "died … at 47 GB, sampled live in memmove inside BitVector unions" | `Transforms/Stack/Stack.cpp` `Inference`: a graph of candidate cells and values (`DenseMap<Value, unsigned>` ids, `SmallVector<SmallVector<unsigned, 2>>` out/in), three markings (`mark(seeds, backward)`), no per-value candidate set; the fixpoint loop of `keepFills` is one backward marking | measured: the death and the sample; inferred: "a bit per node however large the program" (no stage-1 number for the new form) | check 34/34; stack, expect, pipeline, e2e, frames tests |
| **9db9813d** (10-21 02:22) | counting: "On the stage-1 module that was 1088 take-on-borrow verifier errors" (the verifier's count) | `Analysis/Ownership/Reuses.cpp:178-191`: the decider erases uses an earlier site moved and skips a read with nothing left; fixture `tests/rc-reuse-read-field` (differential); bugs.md and 0001 updated; `make test` at b8301ebe 470/480 | measured: the error count; the fixture reproduces the stage-1 error | make test 470/480 at b8301ebe; test-idr rerunning |
| **ffa91113** (10-21 05:10) | idr-rc-exclusive on `DataFlowSolver`: "a 627 GB peak footprint when jetsam stopped it" | exclusivity's four solver analyses replaced by a `Graph` of `Item`s (op, call, region successor, block args, entry args) and a worklist marking over a `DenseMap<Value, Sharing>` (`ExclusivityDetail.h`, new `ExclusivityGraph.cpp`, `ExclusivityAnalyses.cpp` −500 lines net of rewrite); reachability is plain control reachability (`liveBlocksOf`); `Exclusivity::solve` cannot fail (FailureOr removed, `Transforms/Ownership/Exclusive.cpp`) | measured: the kill; inferred: "the questions are reachability and joins over a lattice of height two" | check 34/34, test-idr 342/342, test-unit, test-mlir-tools, make test 470/480 (same ten) |
| **e96bb991** (10-21 07:49) | exclusivity's graph build "did not finish" on stage 1: per branch op, every terminator asked per successor ("the square of the case count") | `Graph::scanBranch`: each point read once, each successor carries `SuccessorSources` (inputs, unforwarded, `from` pairs, `unknownFrom`); the marking asks the branch op nothing (`ExclusivityGraph.cpp:170-224`) | measured: "A generated match of 20000 cases now takes 1.3 s of IdrRcExclusive in the debug build" (a fixture outside the tree; not the stage-1 module) | all suites (sortedmap flaked once) |
| **101edbc5** (10-21 09:43, origin/main) | idr-rc-grades: "the sampler put half of IdrRcGrades in findAncestorOpInBlock and a quarter in block renumbering behind isBeforeInBlock" (sampler on stage 1); `decides` "re-derived per ask through RegionBranchOpInterface" | new `Positions` class (`Analysis/Ownership/Positions.cpp`, 335 lines): a pre-order numbering per function with a gap of 2^16 after each op, spans for ancestry, lazy numbering of inserted ops, `forget` before an erase or move, full renumber when a gap runs out; `usersIn`, `heldIn`, `usedAfter`, `usedIn`, `whereDies`, `onlyReads`, `decides` moved from free functions in `Uses.cpp` (−159 lines) and `Classes.cpp` into it; threaded by reference through Reuses, Grades, Reshape, Placement, Take, Reuse, Commit, Classes; **new trait `Idr_Decides`** (`IdrBase.td:295-303`, `Traits.h:126-149`, its `verifyTrait` at `:133-147`) with a `verifyTrait` holding the op's successor regions to it, on the two match ops, `memo.run`, `array.update`, `element.update`; fixture `tests/rc-numbering-past-a-match` (differential, a seventy-case match) | measured: the sampler shares; **not measured after the change** ("The program suite has not been rerun on this change") | check 34/34, test-idr 342/342 + the fixture, test-unit, test-mlir-tools |
| **51a4771b** (10-21 11:04, origin/main) | none on stage 1: both suites sampled at 1 ms on a profile build (`audits/flamegraph-2026-10-21.md`) | no code; `audits/bugs.md` (ownership): "Counting's op numbering corrupts under counting's own rewrites (`101edbc5`)" — `make test` at 101edbc5 is **403/480 against the standing 470/480**; `tests/chars` asserts in `placeOwned` because the kept `Positions` spans of one match's case blocks overlap; a fresh numbering at `place()` compiles it, one before `reshape` does not | measured (the agent's sampler): defunctionalize's per-function lambda 70 % of test-idr's on-CPU samples by total (half of them one stress fixture, `defunc-tag-limit`), its pattern set populated and frozen per function (populate 4.7 %, freeze 4.3 %, destroy about 1.9 % self); context-lock slow paths about a fifth of the reduced corpus; `toObjects` 34 % of `make test` by total; counting and idr-optimize a few percent; the verifier 1.6-1.7 % self; the 20,000-case probe under `--idr-rc` 0.31 s (profile build) against 3.83 s (dev) | test-idr 342/343 (one sampler-induced timeout); make test 403/480 |

Beside the perf line, the 10-20 Muse Code commits fixed what the first
full `make test` found (c4a046e0, 31daec54, 276e8878: `proves` refuses
an excl grade at `Lifetime::Frame`, `Exclusivity.cpp:163-165`) and
rewrote `audits/bugs.md` (3276be33).

### 2.4 Its report to the owner (2026-10-21), checked against the code

The report (quoted in full in the task, recalled in P0 §2) was written
against 101edbc5's tree, not e96bb991's: it cites `Traits.h:180` for
`GuardedOp`, which is line 154 at e96bb991 and 180 at 101edbc5
(*measured*: `grep -n "class GuardedOp"` on both), and it describes
`Decides` as built. Claim by claim (*read* at 101edbc5 unless noted):
- "GuardedOp … textbook MLIR": the trait supplies the interface method
  (`Traits.h:180`); holds (lane 02 §3.1 agrees).
- "`Idr_ConsumesOnly` and `Idr_ResultCarriesOperand` as TraitLists":
  holds (lane 02 §3.1).
- "New Decides … verifyTrait … hasTrait on the hot path. That is the
  template": built in 101edbc5. What the trait declares is also what
  `RegionBranchOpInterface` answers (`getSuccessorRegions` from the
  parent and from each region), and the `verifyTrait` re-asks the
  interface per region on every verification to hold the two together
  (`Traits.h:133-147`). The owned verifier still derives the same class
  through `verify::alternatives` (`IR/Verify/Linearity.cpp:27-33`,
  `Verify/OwnedRegions.cpp:128`), which also admits `scf.if`; counting's
  `decides` now admits only the five idr ops (section 4, P-3).
- Gap 1, `SameValue` with no `verifyTrait`: holds (`Traits.h`, lane 02
  E56).
- Gap 2, ladders: `Sink.cpp:114` `isa<ConOp, ClosureOp>` holds as read
  (`lib/IR/Canon/Sink.cpp:114`); lane 02 finds it restates no trait (two
  of five `BuildsValue` ops, met by shape) and assigns it to lane 04;
  `Forms.cpp:132` holds (`GeneratingOpInterface` misses `TransposeOp`,
  lane 02); "four copies of `isa<ReturnOp, YieldOp>`": lane 02 counts
  five and shows `ReturnLike` is not equivalent after structure loops.
- Gap 3, "three representations of does IO": lane 02 measures four, which
  disagree (`PerformsIO` = "has a world operand", 80 = 80; ten
  `PerformsIO` ops declare no `IOResource`).
- Gap 4, under-consumed traits: holds and is wider (lane 02: `PerformsIO`,
  `CallsRuntime`, `Primitive` have no C++ reader).
- "One honesty note: the Grades improvement is by construction, not yet
  measured": agrees with 101edbc5's message.

## 3. Reconciliation with P0 and wave 2

### 3.1 §3's table and its three conjectures

Six of §3's eight rows are the other agent's commits (2.3); 98c6315c and
73bba53f are Claude's. What its record adds to or takes from each
conjecture:

- **"Upstream's framework failed on its state model, not its
  algorithms."** *Confirmed in kind, open in amount.* Both framework
  walls are memory, never time: 627 GB (ffa91113, a jetsam footprint)
  and 52 GB (16005000). The agent's own diagnosis names the state, not
  the fixpoint ("a lattice per value, an Executable per program point
  and a predecessor state per function, each behind nested maps and
  uniqued program points", ffa91113). But nothing it recorded separates
  §5.1 A4's container cost (two 64-bucket tables per state, ≈ 2.9 KB,
  P1 cuts ≈ 15×) from the per-point state itself: it counted no values,
  states or anchors (§5.1 W1), and the 52 GB is a process **stopped by
  hand** while sampled, not a peak or a kill (0001:76-79; lane 20 row
  16005000: "a sample, not a peak"). So §5.1 H1's inference "52 GB ⇒
  V ≈ 10 million" and H2's "627 GB ≈ 200 million states" stay
  arithmetic; no measurement of the agent's confirms or refutes them.
- **"The interface layer has costs that scale with region and successor
  counts."** *Confirmed, and located in the client, as §5.1 C1/C4 say.*
  e96bb991's quadratic was our query pattern (`goesTo` per pair of
  terminator and successor, each building a fresh successor list), and
  its fix is C4's "enumerate edges once from the parent and from each
  terminator" (`ExclusivityGraph.cpp:170-224`). 101edbc5 found the same
  shape in counting (`decides` re-asking `getSuccessorRegions` per
  region per query, lanes 07 row 6 and 08 C-79 predicted it) and a new
  one §5.1 does not list: **IR navigation at scale** — upstream's
  `Block::findAncestorOpInBlock` (half of IdrRcGrades' samples) and the
  block order cache behind `Operation::isBeforeInBlock` (a quarter,
  renumbered after insertions). Neither is an interface; both are what
  a per-function numbering answers in O(1) (§5.7 M9, L2; lane 07 D5).
- **"Several walls were ours, and each was fixed by a representation."**
  *Confirmed for six of the eight fixes, refuted for two.* A
  representation replaced the state in 16005000/frames (clones per
  member × answer → one answer sum: §5.7 L5's "clones as keys"),
  b8301ebe (a candidate set per value → one graph, three markings),
  ffa91113 (solver state → a graph marked once), e96bb991 (a query per
  pair → a table per point), 3a96c407 (any-op dispatch → rooted
  patterns) and 101edbc5 (per-query walks → spans; a representation
  missing one coordinate, the block, and wrong on 67 programs, P-1). Two
  fixes added
  control flow instead: 9db9813d adds a guard (`erase_if` of uses an
  earlier site moved, and an early return, `Reuses.cpp:178-191`) while
  the state it guards against — a field read whose uses already moved
  but which stays in the IR — stays representable (lane 07's own-Q1
  and its D4: "the decision made as IR at once"); and 7987388b's
  `RetypePattern`/`PoisonResults` are rooted at *every registered op*
  less a hand list of nine (`Patterns.cpp:277-284`): `MatchAnyOpTypeTag`
  by enumeration, with a list restating which ops have patterns of
  their own (section 4, P-6).

### 3.2 §5.1's cost model and the agent's own structures

- **The DenseMap-per-anchor model (A4, B7, I7)**: *not tested* by any
  measurement of the agent's. Its replacements avoid the per-anchor map
  but none uses dense numbering of values: every new state is keyed by
  pointer through a hash map (*read*): exclusivity's
  `DenseMap<Value, Sharing>`, `DenseMap<Value, SmallVector<unsigned, 2>>
  dependents`, a `DenseSet<Block *>` per function in `liveOf`
  (`ExclusivityAnalyses.cpp`; one ≥64-bucket set per function, about
  70,000 of them: §5.3 B7's "one per node" shape at function grain,
  *conjecture* tens of MB); idr-rc-stack's `DenseMap<Value, unsigned>`
  ids with `SmallVector<SmallVector<unsigned, 2>>` adjacency
  (`Stack.cpp`, b8301ebe); `Positions`' `DenseMap<Operation *, Span>`
  and `DenseMap<Block *, SmallVector<Operation *>>` (101edbc5). The
  agent's states are sized by the program (values, ops), not by pairs,
  which is §5.11 A1's bar; whether they meet §5.3 I7 (a vector indexed
  by a dense number) is Q-llvm-3's question, and 101edbc5's per-function
  numbering is the closest thing to an answer the tree has (2.3).
- **§5.1 Designs 1-3.** The agent took Design 3's route (honest solvers
  of ours) wall by wall, without Design 1's per-function patched
  framework or Design 3's shared layer: three graph types with no shared
  code (lane 20 §3: "b8301ebe, ffa91113, e96bb991 … with no shared
  code"), two of them whole-program and serial (idr-rc-stack's inference,
  exclusivity's solve), the commit nested per function in parallel
  (`Exclusive.cpp`). Each solver's header states what upstream lacked
  and the wall that showed it, which §4 asks for, but only in commit
  messages and comments, not in measured numbers per header.
- **§5.1 G2 (actions, debug counter).** The agent's whole method rests
  on G2's mechanism (`--profile-actions-to`), and its measurements are
  per action; but the solves it wrote are not actions: `Stack.cpp`'s one
  action (`StackCellAction`, :83, :321) wraps each cell's rewrite, not
  the inference, and the exclusivity files and `Positions.cpp` have none
  (*measured*: `grep -c 'TaggedAction\|perform<'`), so the next trace
  shows each solve as one undivided pass.

### 3.3 The trait layer: its report and 101edbc5 against §5.2, §5.8 and lane 02

- **Direction.** The report's four waves (verifyTrait hardening; ladder
  cull; IO trait-supplied effects; verifier `alternatives` vs `Decides`)
  are §5.2's M4, M5, M1 and lane 07's D5 in the same order. They differ
  from P0 in one place: the report keeps each trait and verifies it
  (`SameValue` gets a `verifyTrait`); §5.8 DS4 and lane 02 (E56, E57,
  T6) **delete** `SameValue`, `CarriesOperand`, `ResultCarriesOperand`,
  `NoRuntimeForm` and the borrow's `ViewLikeOpInterface` into one
  forwarding declaration ("the result is the operand" held six ways).
  A `verifyTrait` on `SameValue` is work P0's cutover deletes.
- **`Idr_Decides` (101edbc5).** It meets §5.2 B2/B3 (a native trait with
  a `verifyTrait`, read by `hasTrait`) and deletes the per-query
  interface walk lanes 07 (O-06, U-05) and 08 (C-79) found. But it is a
  second declaration of a fact `RegionBranchOpInterface` already states
  (each region returns to the op; the entry goes into a region), kept in
  step by a verifier that re-asks the interface for every region of
  every such op on every verification (`Traits.h:133-147`): the
  representation-first skill's "one fact, one place" says to generate
  one from the other, and a `verifyTrait` that holds two copies together
  is a check that the second copy did not drift. The owned verifier
  still derives the same class from the interface (`verify::alternatives`,
  `Linearity.cpp:27-33`), now a second classifier beside the trait (the
  report's own wave 4). Upstream's `getRegionInvocationBounds` (which
  the match ops already override, `IdrMatchOps.td:29, 84`) is the
  interface's own statement of "each region at most once", which §5.2
  and lanes 02/03 have not weighed against a trait.
- **Lane 02 (§3.1) already checked the report as P0 §2 recalled it**;
  101edbc5 changes one of its answers (2.4, 3.5).

### 3.4 The next walls wave 2 predicts, against the agent's record

*Read*: sections 3, 5 and 8 of documents 01-20 (a reader dispatched by
this lane collected every predicted wall with the documents' own line
numbers; spot-checked here for lanes 05, 07, 08, 10, 11). No lane
measured anything on stage 1; every prediction is *read* or
*conjecture*. What the agent's runs say about each is only where a run
got to: in pipeline order, its runs passed deduplicate, defunctionalize,
knots, effects, contify, idr-optimize, columns, canonicalize and CSE,
structure loops, bufferize, accumulate, frames (after 16005000), idr-rc-cells,
idr-rc-stack (after b8301ebe), idr-rc-grades (after 9db9813d, slowly:
101edbc5's sampler) and reached idr-rc-exclusive (627 GB, then e96bb991's
graph build). Nothing after idr-rc-exclusive is recorded to have run on stage 1
(the report: "numbers come after gates and the wide-match probe"). Each
"passed" below is *conjecture* from the pipeline's order (a run that
died in a pass had run every pass before it); no record times them. So:

| predicted wall (lanes) | the agent's record | status |
| --- | --- | --- |
| counting's per-query walks: `decides`, `usedAfter`, `usedIn`, `findAncestorOpInBlock` in `readBetween`/`heldIn`, `Classes` per block (07 O-04…O-10, 08 C-06, C-22, C-27, C-37, C-79, 08 §8 1345) | 101edbc5's sampler: half of IdrRcGrades in `findAncestorOpInBlock`, a quarter in block renumbering; `decides` named as re-derived but given no share | **confirmed in part** (the ancestor and order walks, measured); the `decides` Θ(N) term not shown hot; `Classes` per block untouched and unmeasured |
| exclusivity: the op successor re-joins N predecessors (07 A-12), `unknownFrom` per successor and a live crash case sharing a match (07 X-09, G-09) | e96bb991: 1.3 s for a generated 20,000-case match in a debug build; the fixture's crash cases unknown | **open**; the one number is not stage 1 and says nothing of crash cases |
| exclusivity's outer loop re-solving per dropped memo label (07 E-01, A-01) | not separated in any record | **open** |
| Borrows, a whole-program `DataFlowSolver` user (05, 07 B-01, 20) | ran inside idr-rc-grades on every run past 9db9813d; never named by a sample | **survived, unmeasured** (lanes 05, 07 and 20 agree it ran and was not measured) |
| `isRepetitiveRegion` per terminator from idr-rc-stack (05 IQ1, 01 T44) | idr-rc-stack passed after b8301ebe | **survived**, time unrecorded |
| the program verifier after every pass, serial whole-program walks (01, 02, 03, 05, 06, 09, 10, 13, 19) | the verifier ran at every pass up to idr-rc-exclusive and found 9db9813d's 1088 errors; never timed | **survived, unmeasured** (ods-Q6, T-Q5) |
| `RecursiveMemoryEffects` on `idr.match`: every effect query walks N cases (02, 03, 05, 10) | canonicalize and CSE ran on stage 1 at every point up to counting | **survived, unmeasured** |
| canonicalize on wide matches: per-visit cost, ancestor requeue, no-op runs re-verified (04, 09, 13) | 3a96c407/7987388b removed the any-op dispatch; later runs passed idr-optimize | **survived after the cutover**, per-visit cost unmeasured (P-8) |
| defunctionalization's per-function pattern freeze, functions × registered ops (06 D-3), label-solve waves (06 L-10) | defunctionalize passed on every run since 73bba53f; 7987388b made the per-registered-op set (P-6) | **survived**, time unrecorded (843 s was 73bba53f's, before) |
| optimizer scheduling: giant SCC, `enable` rescans, node-table mutex (05, 09) | idr-optimize passed on the runs after 98c6315c and 3a96c407 | **survived**, time unrecorded |
| frames' residual product R·(F+1) + M·R (10 R-4) | frames passed after 16005000 | **survived**, the 336 s action not re-measured |
| Ranges / idr-narrow's whole-program interprocedural solve, re-solved after versioning (05 RA1, RA3, 11 R1, 20) | never reached | **open: the nearest unmeasured whole-program `DataFlowSolver` use downstream of the frontier** |
| Returned on the lowered module, whole-module, V largest there (05, 10 R-1, 20) | never reached | **open** |
| lowering: crash-site `StringAttr`s from workers, runs cut by count not cost (12 CV-16, CV-02) | never reached | **open** |
| bytecode text payload of the 71 MB handoff (01, 03, 13, 14) | the module is read at every run; read time never recorded | **open** |
| frontend memory and time, 6.5 GB, 450-528 s (14, 15, 16, 17) | not the agent's (0001: the frontend half, done) | outside this lane |

**At suite scale (51a4771b, *measured* by the agent's sampler, not
stage 1).** Two predictions are confirmed on the suites and one is
weighed: lane 06's D-3 (defunctionalization's pattern set populated and
frozen per function) is the largest named cost of test-idr after the
conversion itself (P-6); the uniquer and context-lock contention lanes
01, 06, 09 and 12 predicted from workers creating attributes is "roughly
a fifth of the reduced dialect corpus" (mutex slow paths, and
`ParallelDiagnosticHandler`'s per-thread order map at 3.8 %, an MLIR
threading cost §5.3 D1 does not list); and the verifier the nine lanes
fear is 1.6-1.7 % self (`verifyOpAndDominance`) on small modules, which
says nothing of a 71 MB one (the record: rankings "known to invert at
scale"). Counting and idr-optimize are "a few percent" of the suites.
The wide-match probe (a generated 20,000-case match through `--idr-rc`,
one thread) is 0.31 s on the profile build and 3.83 s on the dev build.

Two predictions bear on the agent's own fixes. Lane 10's proposed fix
for FP-2 (`madeInRest`) uses `findAncestorOpInBlock` with
`isBeforeInBlock`, the pair 101edbc5 measured as half and a quarter of
IdrRcGrades (`10-tail.md:767`); and lane 08 C-37's `readBetween` was the
same pair until 101edbc5 moved it onto `Positions` (`Reshape.cpp:184-186`
at 101edbc5). Lane 05 says Borrows ran on stage 1, lanes 07 and 20 say
it was not measured: both hold (*read*). The walls predicted by most
lanes (the verifier after every pass, nine lanes; no per-pass footprint
record, eight lanes) are the ones the agent's record says least about.

### 3.5 Wave-2 documents 101edbc5 and 51a4771b make stale

101edbc5 (origin/main, after the tree every wave-2 lane read) moves or
removes code eight documents cite. *Read*: `git diff e96bb991 101edbc5`;
the documents' lines by `grep -n`. No wave-2 document cites 101edbc5
(*measured*: `grep -l 101edbc5 audits/p0/*.md` finds only this one).

| lane | where in its document | what moved (file:line at e96bb991 → at 101edbc5) | stale how |
| --- | --- | --- | --- |
| 02 ods-effects | §3.1 (lines 585-589), the reconciliation of §2's trait layer | `Idr_Decides` added: `IdrBase.td:295-303`, `Traits.h:126-149` | "Refuted: no `Decides` exists … The one native trait with a `verifyTrait` is `ResultCarriesOperand`": both false at 101edbc5 |
| 02 ods-effects | §2 counts (native traits, `hasTrait` readers, the trait table F11-F15) and every `Traits.h` line above 123 and `IdrBase.td` line above 292 | `Traits.h` +26 lines after :123 (`GuardedOp` :154 → :180); `IdrBase.td` +10 after :292 | counts one trait short (and one `verifyTrait`, five ops, three `hasTrait<Decides>` readers); line drift |
| 07 ownership-analysis | §2 table rows for `Uses.cpp` (line 424: "207 lines: `heldIn`, `usersIn`, `decides`, `usedAfter`, `whereDies`, `fieldsOf`, `onlyReads`") and the vocabulary row (464) | `Uses.cpp` −159 lines; those functions are `Positions` members (`Analysis/Ownership/Positions.cpp`) | the file holds `pointBefore`, `definedAt`, `fieldsOf` only |
| 07 | §2 costs (546-564: `usedAfter` O(depth·uses·depth), `decides` O(regions), `findAncestorOpInBlock` per use) | spans and binary search (`Positions.cpp:155-275`) | the per-query costs stated are the old code's |
| 07 | §3 rows 6 and 7 (594-595: "`decides()` asks … on every call"; "`Decides` … refuted") | `Positions::decides` = `hasTrait<Decides>` (`Positions.cpp:211`) | both rows reverse |
| 07 | §4 O-04…O-07, O-10 (786-792), §4.8 U-01…U-09 (900-908), R-03, R-10 (934, 941), W3 (636), W-E6 (712) | as above | the issues are fixed or moved; their `Uses.cpp`/`Ownership.h` lines no longer exist |
| 07 | §5 D5 (1141-1163), "The vocabulary on a per-function scope" | `Positions` is a per-function pre-order numbering with spans and a `decides` bit by trait | D5 is half built, differently: not an analysis, not shared with the verifier's `Numbering`, maintained through rewrites by `forget`, uses sorted per query (3.6) |
| 08 counting | §3 rows "§5.1 W3 / §5.6 W-E6" (488), "§5.6 item 8" (493), "§5.11 A1" (510) | `decides`, `usedIn`, `usedAfter` now through `Positions` | the Θ(N) per-query terms cited are gone; the per-block `Classes` of `sinkConsumers` stays (`Reshape.cpp:162`) |
| 08 | §4 C-06, C-22, C-27, C-29, C-37 (`readBetween`'s `findAncestorOpInBlock`), C-79 (702-815) | `Classes.cpp:124-130` `usedIn` deleted; `Reshape.cpp:184-186` uses `topIn`/`before`; `Placement.cpp:193, 247` read the trait | the costs and some lines are stale; the ladders (`Class` switches) stand |
| 08 | §8 (1345-1357): "the quadratic shapes of §3.1 (`decides`, `usedIn`, per-block `Classes`)", "how often `decides` is asked" | as above | two of the three shapes changed under the measurement they asked for |
| 08 | §5 T3 (891-925): placement as one reverse walk, deleting `usedIn`, `usedAfter`, `decides` | `Positions` keeps the query vocabulary and makes it cheap | T3 now deletes 101edbc5's class, not the free functions |
| 03 ods-ops, 01 ods-types, 11 arrays, 16 frontend-checks, 19 tests-harness, 12, 13, 17, 18 | line references into `IdrBase.td` (>292), `Traits.h` (>123), `IdrMatchOps.td`, `IdrClosureOps.td`, `IdrArrayOps.td` | +10 / +26 lines; one trait added to five op definitions | line drift only (*measured*: 35, 46, 30, 12, 10 matching lines respectively; not checked one by one) |
| 20 history | §3 and §6 (252, 491, 949): "470/480 now", "the last recorded is 470/480 at ffa91113" | `make test` at 101edbc5 is 403/480 (51a4771b) | the standing count fell by 67 after the tree the lane read |
| 07, 08 | their bug lists' sources (`audits/bugs.md` at e96bb991) | 51a4771b adds the ownership entry "Counting's op numbering corrupts under counting's own rewrites" | a new open counting bug in the code they audit |

Lane 05 (analyses) cites the walls through e96bb991 correctly; nothing
after it contradicts lane 05.

### 3.6 Where the agent's changes and P0's plan touch the same code

- **Counting's vocabulary** (`Analysis/Ownership/Uses.cpp`, `Positions.cpp`,
  `Transforms/Ownership/{Classes,Placement,Reshape,Take,Reuse,Commit,Grades}.cpp`,
  `Analysis/Ownership/Reuses.cpp`): rewritten by 101edbc5; planned by lane
  07 D5 (a scope analysis) and lane 08 T3 (a reverse walk that deletes the
  queries). Three designs for one code path.
- **Exclusivity** (`Analysis/Ownership/Exclusivity*.cpp`): rewritten twice
  in three hours (ffa91113, e96bb991); lane 07 plans D1 (drop
  `unknownFrom`), D2 (call edges as handlers) and the solver layer (§5.3
  S1, §5.6 Design 1, §5.9 Design 1) over the same graph.
- **idr-rc-stack** (`Transforms/Stack/Stack.cpp`): b8301ebe's graph; lane 08
  and the solver-layer designs (§5.10 M6: "three markings, one honest solver
  layer").
- **The trait layer** (`IdrBase.td`, `Traits.h`, the op `.td` files): the
  agent added `Idr_BuildsValue` (7987388b) and `Idr_Decides` (101edbc5) and
  proposes four more waves (2.4); P0's ods lanes (01, 02, 03) redeclare
  every trait and lane 02 deletes `SameValue` and kin.
- **The pipeline** (`Transforms/Pipeline.cpp`): 16005000 removed
  `remove-dead-values`; QA3 and lane 20's hist-Q1/hist-Q3 ask whether it
  returns per function.
- **Canonicalization** (`IR/Canon/Sink.cpp`, `CaseOfCase.cpp`,
  `MatchPatterns.cpp`): 3a96c407's rooted patterns; lane 04 and §5.9
  Design 5 (a walk-driver normalizer).
- **Frames** (`Transforms/Tail/Frames*.cpp`): 16005000's answer sum; lane
  10 (tail-Q2, tail-Q3).

## 4. Issues

Issues the agent's work reveals or leaves, each with the commit. The
README's categories, plus one of this lane's own, *record* (a
measurement missing, unrepeatable, or kept only in prose). Where a
wave-2 lane already holds the issue, its ID is given and this table
only adds the commit's part.

| ID | commit; `file:line` | category | what | proposed disposition |
| --- | --- | --- | --- | --- |
| P-1 | 101edbc5, confirmed by 51a4771b; `Positions.cpp` `assign` (`lo = outer.pos, hi = outer.end`), `forget`; callers `Reuse.cpp:57`, `Take.cpp:64`, `Reshape.cpp:54, 207-210` | state | **a miscompile path, now measured**: `make test` at 101edbc5 is 403/480 against 470/480; `tests/chars` asserts in `placeOwned` because the kept spans of one match's case blocks overlap, and 65 outputs of the profile build assert "Malformed attribute storage object" through `place()` (51a4771b, `audits/bugs.md` ownership). Mechanism (*read*): an inserted op is bounded by its nearest numbered neighbours in its block, and where a side has none, by the parent op's whole span; a block has no coordinate of its own, so an op inserted after the last numbered op of a case block, or into a block with none numbered, takes room that belongs to the following cases (*conjecture* that this is the first overlapping `assign`, which the agent has not yet caught; it fits its "numbered … against the parent op's whole span rather than within their block's extent"). The missing coordinate is lane 07 D5's block-start sentinel (Insight 8). A second path, unconfirmed: a missed `forget` leaves a span under a freed pointer a new op may reuse. | the block as a coordinate of the numbering (a sentinel per block), and invalidation by a `RewriterBase::Listener` (§5.7 L6) or plan-then-rewrite (lane 07 D5); NQ-21-2 |
| P-2 | 101edbc5; `Reuses.cpp` (`Decider::positions`), `Grades.cpp:56`, `Commit.cpp:124`; `IR/Verify/Linearity.cpp:42-66` | rederivation | one function numbered three times across idr-rc-grades and idr-rc-exclusive, beside the owned verifier's own pre-order `Numbering`: one fact (where an op sits) held four ways | one numbering, an `AnalysisManager` analysis shared with the verifier (lane 07 D5; Q-llvm-3) |
| P-3 | 101edbc5; `Positions.cpp:211` vs old `Uses.cpp:96-104` (e96bb991) and `Verify/Linearity.cpp:27-33` | rederivation | `decides` was "any region branch whose regions return to it and whose entry enters one" (the old comment: "a match, an scf.if with both branches, an scf.index_switch", `Ownership.h` at e96bb991); it is now the five idr ops carrying `Idr_Decides`. An upstream region op reaching counting is now held across instead of moved into each region, and the owned verifier (`alternatives`) still calls its regions alternatives: the two classifiers differ on `scf.if`. Whether any `scf.if`/`scf.index_switch` reaches counting is not checked here (*conjecture*); the message does not mention the change. | one classification read by counting and the verifier (the report's own wave 4); a check of which upstream region ops reach idr-rc |
| P-4 | 101edbc5; `Positions.cpp` `assign` (`held.insert`), `forget` (`std::remove`), `usePositions` (sort per query) | state | inserting a numbered op into its block's op list and forgetting one are each linear in the block; a function body is one block, and counting inserts a dup, drop or take per value: *conjecture* inserts × block size in the largest function. Each `usedAfter`/`usedIn` sorts the value's uses again. | measure IdrRcGrades on stage 1 after 101edbc5 is fixed (the agent's own "not yet measured"); D5's uses sorted once |
| P-5 | 101edbc5; `IdrBase.td:295-303`, `Traits.h:133-147` | ods, rederivation | `Idr_Decides` restates what `RegionBranchOpInterface` answers, and its `verifyTrait` re-asks the interface for every region of every such op at every verification (after every pass, on matches of tens of thousands of cases) | one source: the interface's own statement (`getRegionInvocationBounds`, already overridden by the match ops) or a declaration that generates the interface's answer; lanes 02, 03 |
| P-6 | 7987388b; `Defunctionalize/Patterns.cpp:277-284`, called per function from `Defunctionalize/Pass.cpp:93-94`; `tools/idris-mlir-reduce.cpp` (`populateReductionPatterns`) | list, ladder, state | "rooted at each registered op but the ones with a pattern of their own": one `RetypePattern` per registered op name (every loaded dialect's), less a hand list of nine names restating which patterns exist; the attempts per op are unchanged from `MatchAnyOpTypeTag` except at those nine, and the set is populated and frozen **per function** (lane 06 D-3, "a candidate for §3's next wall"). 51a4771b measures the per-function rebuild at suite scale: `populateDefunctionalizePatterns` 4.7 %, `FrozenRewritePatternSet` construction 4.3 % and destruction about 1.9 % self of test-idr's on-CPU samples; whether 7987388b raised it (one pattern before, one per registered op after) is *conjecture* the audit does not test | one frozen set per run, the plan read through the converter at match time; legality from the `ConversionTarget`; a root the retyped ops share; lane 06 |
| P-7 | 7987388b; `IdrBase.td:290-293`, `Traits.h:119-123` | ods | `Idr_BuildsValue` added for two test properties (`Expect/Does.cpp:34`, `Expect/Placement.cpp:117`); lane 02 E45 | lane 02/19's decision (the flow's `Fresh` result, or keep it test-only) |
| P-8 | 3a96c407; `Canon/Sink.cpp:205-216` (`SinkIntoRegions`), `CaseOfCase.cpp:43-55` | state | rooted at the match, the patterns are retried on any change under it (the driver requeues ancestors: upstream patch 62's case) and `nearestSinkable` scans the match's whole block per attempt: attempts × block on a wide, busy match (*conjecture*; the 75 million any-op attempts are gone, the per-attempt cost is unmeasured) | lane 04; §5.9 Design 5 (a walk-driver normalizer, no fixpoint) |
| P-9 | 16005000; `Transforms/Pipeline.cpp:96-106` | upstream, record | `remove-dead-values` dropped on a run "stopped at 52 GB" by hand (0001:76-79), a sample, not a kill or a peak (lane 20); no patch of the state storage tried (lane 20); what it alone removed is "unmeasured there" (its own bugs.md text); patches 06, 28, 63 now reach nothing (hist-Q3) | QA3, hist-Q1, hist-Q3; a measured run of the per-function half (§5.1 5.1.2 item 4) |
| P-10 | 16005000; `Tail/FramesPlan.cpp:166-171` | budget | a component with a result type no field may hold keeps its plain calls and its stack growth, silently (lane 10 FP-11, R-3) | tail-Q2 |
| P-11 | ffa91113, e96bb991; `ExclusivityGraph.cpp:208-222`, `ExclusivityAnalyses.cpp:236-243` | state, rederivation | `unknownFrom` copied into every successor (successors × crash blocks), and a live crash case shares every input of every successor of its match (lane 07 X-09, G-09); e96bb991 removed the per-pair query but kept both | lane 07 D1: a terminator that transfers nowhere is no predecessor |
| P-12 | e96bb991; `ExclusivityAnalyses.cpp:244-251` | state | the op successor re-joins all N predecessors each time it runs (lane 07 §3 row 4, residue 2; §5.1 C3 in our code) | lane 07 D2; the solver layer's incremental join |
| P-13 | ffa91113; `Transforms/Ownership/Exclusive.cpp:39-46` | rederivation | the whole-program solve runs twice when grade copies exist, and is no analysis (0003 "Exclusivity solved twice", "Exclusivity is no analysis") — both unchanged by the rewrite | 0003's items; lane 07 |
| P-14 | b8301ebe, ffa91113, 101edbc5 | cpp, state | three graph or numbering types written in twelve hours with no shared code (lane 20), each keyed by pointer through hash maps, none an action, two whole-program and serial | the solver layer (§5.3 S1, §5.6 Design 1, §5.9 Design 1; QA4) with these three as its first clients |
| P-15 | 9db9813d; `Reuses.cpp:178-191` (the `erase_if` at :183) | rederivation | a guard where the state stays representable: a read whose uses an earlier site moved stays in the IR, and the decider filters it (lane 07 D4, own-Q1) | the decision made as IR when taken (lane 07 D4) |
| P-16 | 101edbc5; 51a4771b | record | landed on main with "The program suite has not been rerun on this change"; its first run (51a4771b) is 403/480 against 470/480, and main stays there (no fix pushed by this lane's last fetch) | hist-Q2; acceptance as `audits/bugs.md` states it: `make test` back to its standing count |
| P-17 | all; `bench/records/`, `proposals/0001-self-host.md:59-100` | record | no S3 record under `bench/records/` (0001's acceptance asks for one only when both halves exit 0, so the walls are kept nowhere but prose); 0001 §2 stops at 9db9813d's run, so the 627 GB exclusivity wall, e96bb991's graph build and 101edbc5's sampler shares are in commit messages only | a record per run (the frontier pass, its time, its footprint, what it was killed by), oom-3's per-pass footprint |
| P-18 | all | record | the numbers mix measures: a jetsam footprint (627 GB), an RSS at a kill (43 GB), a manual stop (52 GB), a live sample (41-47 GB), a debug-build fixture (1.3 s), sampler shares; §5.11 K5: RSS under-reads what jetsam kills on | oom-3; drv-Q1 (assertions) for timings |
| P-19 | 101edbc5; `Positions.cpp` `assign` (`std::function<void(Region &)> fill`) | cpp | a recursive walk through a type-erased `std::function` | a recursive lambda over deducing `this` (§5.5 D5) or a member function |
| P-20 | ffa91113; `ExclusivityAnalyses.cpp` (`liveOf`) | state | one `DenseSet<Block *>` per function (≥64 buckets once used, §5.3 B7), about 70,000 of them (*conjecture*: tens of MB, not a wall) | blocks numbered (`Block::getBlockID`, §5.3 B7) and one bit vector |

## 5. What P0's plan should take from it

### 5.1 Its method, made a standing part of the plan

The agent's loop (run stage 1 on the release build, profile the actions,
sample the process, reduce the stuck unit, fix the representation, rerun)
met eight walls in eighteen hours (§3's six, 9db9813d's verifier errors,
101edbc5's IdrRcGrades profile); the code reads that name any of them
(lanes 07 and 08 on counting's walks, lane 07 on `unknownFrom`) were
written the same day and say *conjecture*. P0's own bar asks for this: §4
("the measurement that shows it" in every solver's header), §5.9 Design
6 (a footprint report per pass), §5.11 A2/A3 (a per-pass footprint in a
`PassInstrumentation`; name the death on pressure), hist-Q1 (measure
before adopting). What the plan should take:
- **Every cutover step is measured on stage 1** before the next, at a
  recorded commit, with the release build, and the record goes under
  `bench/records/` whether or not the pipeline finishes: the frontier
  pass, `-mlir-timing` per pass, the footprint per pass in the measure
  jetsam kills on (§5.11 K5), and V/B/P/F at each solve point (§5.1 W1).
  Today none of this exists for S3 (P-17, P-18).
- **The solver layer's units are actions** (§5.1 G2): each function's
  or SCC's solve wrapped as a `TaggedAction`, so the action profile the
  agent reads names them and `-mlir-debug-counter` bisects them; none of
  its three new solvers is one (3.2).
- **A wall is fixed at the representation, never by a refusal**: the
  agent added no refusal and no count anywhere; its one limit (frames
  leaving a component unframed, P-10) leaves code less optimized, which
  AGENTS.md allows. That is §5.11's line.

### 5.2 Its measurements as P0's baseline

What the stage-1 pipeline half is known to cost, by pass, as of
origin/main (every number the agent's, from the commit named; the measure
in brackets):

| pass | before | after | the fix's own number |
| --- | --- | --- | --- |
| idr-optimize (patterns) | 75 million any-op attempts in 31 traced minutes [action profile] (3a96c407) | rooted | none on stage 1 |
| idr-frames | killed at 43 GB [RSS at jetsam]; one action 336 s (16005000) | answer sum | none on stage 1; later runs passed it (b8301ebe's run reached idr-rc-stack) |
| remove-dead-values | stopped by hand at 52 GB [manual stop, sampled] (16005000) | removed | none |
| idr-rc-stack | died at 47 GB, 41 GB live [sample] (b8301ebe) | graph markings | none on stage 1; the next run reached idr-rc-grades (9db9813d) |
| idr-rc-grades | 1088 verifier errors (9db9813d); half of the samples in `findAncestorOpInBlock`, a quarter in block renumbering [sampler] (101edbc5) | guard; `Positions` | not measured after 101edbc5; wrong on 67 programs of `make test` since (51a4771b) |
| idr-rc-exclusive | 627 GB [jetsam footprint] (ffa91113); graph build did not finish (e96bb991) | graph marking; per-point table | 1.3 s on a generated 20,000-case match [debug build, not stage 1] (e96bb991) |

The one written record (51a4771b's `audits/flamegraph-2026-10-21.md`)
measures the suites, where the ranking is startup, LLVM's backend,
defunctionalize's per-function pattern set and the context lock; it says
so, and that stage 1 is "the missing measurement". It also found that
main has been at 403/480 since 101edbc5 (P-1, P-16), so the next stage-1
run starts from a tree whose counting is wrong on 67 programs.

So P0's designs are compared against a pipeline whose **frontier is
unrecorded** after 101edbc5 (the report: "numbers come after gates and
the wide-match probe"), whose later passes (idr-demand, idr-trmc,
idr-tail-loops, idr-narrow, the lowering) stage 1 has never reached, and
for which no pass has a recorded stage-1 time. The baseline P0 needs
first is one complete record at a fixed commit (5.1); until then every
"measured" in P0 about stage 1 is a kill, a stop or a sample.

### 5.3 Its proposed trait waves against P0's ods lanes

| its wave (report) | P0's place | recommendation (*conjecture*, for the coordinator) |
| --- | --- | --- |
| 1. `verifyTrait` hardening (`SameValue`) and a dead-trait audit | §5.2 M4; lane 02 (reader counts done: §2, E45, E56); §5.8 DS4 and lane 02 T6 delete `SameValue` into one forwarding declaration | not as a separate wave: a `verifyTrait` on a trait the cutover deletes is a shim (hard cutover); the audit is lane 02's, done |
| 2. ladder cull with the Canon wave (Sink first) | §5.2 M5, §5.3 I1 (the case is representational, not speed: B1), lanes 02, 04, 10, 11 (`Sink.cpp:114` to lane 04, `Forms.cpp:132` to lane 11, the `ReturnLike` copies to lane 10) | inside P0's cutover, by the lanes that own the files |
| 3. IO trait-supplied effects, measured first | §5.2 M1 and row 3, §5.8 EF2/DS2, lane 02 (four representations of "does IO", which disagree) | waits on the owner: ods-Q2 and DD-Q3 decide whether the world stays a value; the measurement the report asks for (what generic passes then do to our ops) is §5.1 D2's table, on stage 1 |
| 4. verifier `alternatives()` vs `Decides` | lane 07 D5 (one scope, a `decides` bit), P-3, P-5 | one classifier; with lanes 01/03 deciding trait or interface |

### 5.4 Its solvers as the solver layer's first clients

- 101edbc5's `Positions` is lane 07's D5 "scope" half-built: the coordinate
  (pre-order spans) and `decides` by declaration, without the analysis,
  the sharing with the verifier, the stored use order or the block-start
  sentinel. P0 either makes it the per-function scope (§5.7 L2's `Scope`,
  §5.3 Q-llvm-3) or replaces it with lane 08's T3 reverse walk, which needs
  no position queries at all; not both.
- ffa91113/e96bb991's exclusivity `Graph` and b8301ebe's stack `Inference`
  are the two markings §5.10 M6 and §5.3 S1 (`mark(graph, seeds)`) name:
  the same two-point marking over two hand-built graphs. e96bb991's
  `SuccessorSources` is §5.4 Design 4's per-op edge table, written for one
  client.
- Each was written under a wall's pressure in hours (ffa91113 at 05:10
  introduced the quadratic e96bb991 removed at 07:49: lane 20), which is
  the case for building the shared graph and its linear build once (§5.3
  S1's cost note) rather than per wall.

### 5.5 What the coordinator should do about the collisions (3.6)

- **Rebase the plan on origin/main, by commit.** Wave 2 read e96bb991;
  main is 51a4771b and moving. Either fix one commit as P0's audited tree
  and list every later commit's delta (this document's 3.5 is the form),
  or re-run the affected lanes' staleness checks on each push.
- **Fence the parallel work.** Counting's vocabulary, exclusivity, the
  stack inference and the trait layer each now have the agent's design on
  main and one or two wave-2 designs on paper. Ask the owner (6.2, NQ-21-1)
  whether the agent's further changes are limited to measurement and to
  fixes that unblock a measurement, each with a record, and whether its
  trait waves are folded into P0's ods lanes rather than landed ahead of
  them.
- **Take its measurements into §3**, with their measures (P-18), and add
  101edbc5's row (IR navigation: `findAncestorOpInBlock`,
  `isBeforeInBlock`'s block renumbering).
- **Name the tree P0's gates start from.** Main has been 403/480 since
  101edbc5 (51a4771b); P0's T-Q1 invariant set and hist-Q2's "every step
  builds and passes" need a green starting commit, which today is
  e96bb991 (470/480, the standing ten), not origin/main. Whether
  101edbc5 is fixed forward or reverted is NQ-21-2's.

## 6. Evidence for the owner's questions

### 6.1 By ID (evidence only; the owner decides)

- **Q2 (does S3 stop for P0, or run alongside as measurement).** It ran
  alongside and did not stay measurement: nine commits in eighteen hours,
  seven of them changing code in the subsystems wave 2 audits (counting,
  exclusivity, idr-rc-stack, frames, canonicalization, defunctionalization's
  patterns, the trait layer), 101edbc5 and 51a4771b landing after the
  tree every lane read (3.5), and main red since 101edbc5 (P-16). D4 ("no
  code until the whole plan is approved") binds P0; whether it binds the
  parallel agent is not written anywhere (*read*: §9 D1-D4).
- **Q4 (who runs the release `idris-mlir` on stage 1).** Today only this
  agent; its instruments are MLIR's action profiler and `sample`
  (0001:101-112), its numbers are in commit messages, and no S3 record
  exists in `bench/records/` (P-17). Its first written record
  (51a4771b) is a sampling audit of the suites on a hand-made
  `RelWithDebInfo` build swapped in for `build/dev` by symlink, with
  throwaway scripts and raw traces outside git: repeatable from its
  method text, not from the tree.
- **QA1 (patch the state storage first).** No patch was tried before
  either drop (lane 20 rows ffa91113, 16005000). The agent's diagnosis
  is the state model, its numbers cannot apportion it between §5.1 A4's
  containers and per-point state (3.1).
- **QA2 (per-function solves vs whole-program).** Both of the agent's
  graph solves are whole-program and serial (idr-rc-stack, exclusivity);
  the one timing is 1.3 s for one 20,000-case match in a debug build
  (e96bb991); no per-function form was tried or measured.
- **QA3 (`remove-dead-values`).** Dropped whole by 16005000 on a run
  stopped by hand at 52 GB; the claim that specialization and counting
  cover what it removed is unmeasured (P-9); the per-function half was
  never run.
- **QA4, Q-O2, QL1, Q-llvm-3 (one state representation; numbering).** The
  tree now has three solver graphs with no shared code (P-14) and two
  per-function pre-order numberings (counting's `Positions`, the owned
  verifier's `Numbering`), built three plus one times per function per
  run of counting (P-2): evidence that a shared numbering has at least
  two clients, and that without a layer each wall makes its own.
- **Q-llvm-6, QL4 (determinism across thread counts).** The agent's
  solves are serial; nothing it added is tested at two thread counts.
- **ods-Q6, Q-M2, Q-O5, T-Q5 (verification at 70,000 functions).** On
  the suites the verifier is 1.6-1.7 % self (51a4771b); no measurement
  of it on stage 1 exists (0001:113-121 lists
  `verifyFlowEdges`, `Carriers::of`, `atLifetime` as risks). Two facts
  bear on it: the verifier after every pass is what caught 9db9813d's
  bug on stage 1 (1088 errors, named on the first), and 101edbc5 adds a
  per-region interface walk to every verification of every deciding op
  (P-5).
- **ods-Q2, DD-Q3 (effects that follow from types; the world).** The
  agent's wave 3 ("the trait should supply the effects") is one answer
  to both, proposed for landing after its other waves; lane 02 measures
  four disagreeing representations of "does IO".
- **canon-Q2, canon-Q5 (canonicalization's budget and place).** 3a96c407
  and 7987388b removed the any-op dispatch but kept the greedy driver;
  the rooted patterns are retried on every change under a match (P-8).
- **own-Q1, count-Q2 (reuse before or after counting).** 9db9813d's bug
  (1088 errors on stage 1) came from reuse decided before placement and
  simulated by moving uses that stay in the IR (P-15).
- **tail-Q2 (the constant-stack promise).** 16005000 leaves a component
  unframed when a result cannot be a field (P-10, lane 10 FP-11).
- **hist-Q1 (measure before adopting, patch before dropping).** The two
  drops lane 20 names are this agent's (16005000, ffa91113); both rest on
  a kill or a stop, neither on a measured alternative.
- **hist-Q2 (unbuilt or unverified landings).** 101edbc5 landed with "the
  program suite has not been rerun"; its first program-suite run, 78
  minutes later (51a4771b), is 403/480 against 470/480: the case the
  question describes, measured. The others report `make check`,
  test-idr, test-unit, test-mlir-tools, and 9db9813d and ffa91113 a full
  `make test` at 470/480.
- **hist-Q5 (reversals without a ruling).** ffa91113 reverses 595ed341's
  engine; 16005000 drops an adopted upstream pass; 101edbc5 changes what
  `decides` admits (P-3). None carries a dated ruling.
- **oom-2 (running out is a crash, not a refusal).** Every wall ended in
  a kill or a stop with no record of its own; the agent never answered a
  wall with a limit or a refusal.
- **oom-3 (a footprint record per pass; which measure).** The record
  mixes a jetsam footprint, an RSS at a kill, a manual stop and live
  samples (P-18).
- **drv-Q1 (assertions in measurements).** e96bb991's only timing is a
  debug build; the stage-1 runs are the release preset over the shared
  toolchain, which lane 13 says has LLVM assertions on.
- **drv-Q6 (profiling stage 1).** The agent used the streamed action
  profile (about 1 GB a minute in idr-optimize) plus `sample`; its later
  walls were found by sampling, not by the profile (b8301ebe's memmove,
  101edbc5's shares), and its first two by the profile's counts and
  durations (3a96c407, 16005000). For the suites it chose `sample` at
  1 ms on a frame-pointer build without LTO, because "the release
  preset's full LTO smears function attribution" (51a4771b): a third
  instrument beside the two drv-Q6 names.

### 6.2 New questions for the owner

- **NQ-21-1. The parallel agent and D4.** Does "no code until the whole
  plan is approved" bind the agent working S3, or may it keep changing
  counting, exclusivity, the stack inference and the trait layer on main
  while P0's lanes plan the same code? If it may, should its changes be
  limited to fixes that unblock a stage-1 measurement, each with a record,
  and its four trait waves be P0's ods lanes' work rather than landed
  ahead of them?
- **NQ-21-2. `Positions` (101edbc5): the scope, or an interim?** It is
  defective on main (403/480, P-1). Repair it toward the per-function
  scope P0 builds on (a coordinate per block, an analysis, one numbering
  shared with the owned verifier, invalidated by a rewriter listener:
  lane 07 D5), revert to e96bb991's queries until P0, or treat it as the
  interim that lane 08's T3 (placement as one reverse walk) deletes?
- **NQ-21-3. A record per S3 run.** Should every stage-1 run leave a
  record under `bench/records/` (frontier, per-pass time, footprint and
  its measure, V/B/P/F), wall or not, replacing 0001's "a record when both
  halves exit 0", so that P0's designs have a baseline (5.2)?

## 7. Deletion list

What goes if P0 takes the dispositions of section 4 (each *conjecture*
until the owning lane's plan is approved; the owning lane deletes it).

- `Analysis/Ownership/Positions.cpp`: `Positions::forget` and every call
  of it (`Reuse.cpp:57`, `Take.cpp:64`, `Reshape.cpp:54, 207-210` at
  101edbc5), replaced by a listener or by plan-then-rewrite (P-1); the
  per-pass constructions in `Reuses.cpp` (`Decider::positions`),
  `Grades.cpp:56`, `Commit.cpp:124` and the owned verifier's `Numbering`
  (`IR/Verify/Linearity.cpp:42-66`), for one numbering (P-2); or the
  whole class, if lane 08's T3 replaces the query vocabulary (NQ-21-2).
- `Positions::decides` and either `Idr_Decides` (`IdrBase.td:295-303`,
  `Traits.h:126-149`) or `verify::alternatives` (`Linearity.cpp:27-33`),
  for one classifier (P-3, P-5).
- `Positions::assign`'s `std::function<void(Region &)> fill` (P-19).
- `Defunctionalize/Patterns.cpp:277-284`'s `handled` list and the
  per-registered-op `RetypePattern` registration; the same in
  `tools/idris-mlir-reduce.cpp`'s `populateReductionPatterns` (P-6).
- `Idr_BuildsValue` (`IdrBase.td:290-293`, `Traits.h:119-123`) if lane
  19 reads "builds a value" off the flow's `Fresh` (P-7, lane 02 E45).
- `SuccessorSources::unknownFrom` (`ExclusivityDetail.h`,
  `ExclusivityGraph.cpp:208-222`, `ExclusivityAnalyses.cpp:236-243`)
  (P-11, lane 07 D1).
- `Reuses.cpp:178-191`'s moved-use filter once the decision is IR when
  taken (P-15, lane 07 D4).
- `liveOf`'s `DenseSet<Block *>` per function (P-20).
- Not to build: a `verifyTrait` for `Idr_SameValue`, which §5.8 DS4 and
  lane 02 T6 delete with the trait (the report's wave 1; 5.3).

## 8. Risks, unknowns, measurements needed

**Risks.**
- **This document goes stale at the agent's next push.** Fetched four
  times on 2026-10-21; the third found 51a4771b, folded in; the fourth
  found nothing newer. Its report
  announces four trait waves and a "wide-match probe".
- **Main is red** (P-1, P-16): 403/480 since 101edbc5, with an owned
  fix not yet made. Any stage-1 measurement or wave-2 check taken on
  main before the fix measures a counting that is wrong on 67 programs.
- **A second miscompile path in `Positions`**, unconfirmed: a missed
  `forget` leaves an order fact under a freed pointer (P-1).
- **The profile build's swap** (51a4771b's method): `build/dev` made a
  symlink to `build/profile` for each corpus run, "the dev tree moved
  aside and restored after"; any lane or agent building in the shared
  checkout meanwhile would have built or tested the wrong tree.
- **An unrecorded change of what counting moves into regions** (P-3),
  if any upstream region op reaches idr-rc.
- **Three designs for counting's vocabulary** (101edbc5, lane 07 D5,
  lane 08 T3) and two or three for exclusivity and the stack inference
  (the agent's graphs, lane 07 D1/D2, the solver layer): if the
  coordinator does not fence them (5.5), P0's cutover rewrites code that
  changed after its audit.
- **Baseline drift.** P0's §3 and its designs cite the walls; the
  pipeline that met them no longer exists in that form, and its current
  frontier is unrecorded (5.2).

**Unknowns.**
- Whether the 52 GB `remove-dead-values` run would have finished (stopped
  by hand on a 96 GB machine; 0001:76-79).
- What fraction of the 627 GB was §5.1 A4's container cost.
- Where the pipeline half stops after 101edbc5, and in what time.
- Whether e96bb991's 20,000-case fixture had crash cases (P-11).
- Which measure `peak_memory` and the agent's "RSS" read (lane 18:
  `ru_maxrss`, which misses compressed pages; §5.11 K5).

**Measurements needed** (all on stage 1, release build, one recorded
commit, beginning at origin/main):
1. The frontier and, per pass, `-mlir-timing` and the peak footprint in
   jetsam's measure (`phys_footprint`), as one `bench/records/` entry
   (P-17, oom-3; lanes 05, 07, 08, 10, 11, 13, 19, 20 ask the same).
2. IdrRcGrades after 101edbc5 (P-4), and idr-rc-exclusive on the module
   itself rather than a fixture (P-11, P-12; lane 07's 1470-1484).
3. V, B, P, F at each solve point, the largest matches' case counts and
   crash cases, SCC sizes (§5.1 W1; lanes 05, 07, 08, 15).
4. The verifier's share per pass (`--mlir-timing` rows; T-Q5) and with
   `-verify-each=0` if the owner allows it (lane 13 M2).
5. Ranges/idr-narrow and Returned in isolation, with footprints, before
   the pipeline reaches them (the open rows of 3.4).
6. For QA1 and QA3: the pre-ffa91113 exclusivity and `remove-dead-values`
   per function, on the U1-patched framework (lane 20 asks the first).

## 9. Sources read

- `.claude/skills/representation-first/SKILL.md` (whole); `AGENTS.md`.
- `proposals/0000-mlir-native.md` (whole, 11,583 lines at the time of
  reading: §0-§4, §5.1-§5.11, §6, §7, §8 including 8.12's wave-2
  questions, §9).
- `proposals/0001-self-host.md` and `proposals/0003-facts-once.md`
  (whole, at e96bb991; unchanged on origin/main).
- `audits/p0/README.md`; `audits/bugs.md` (as changed by 16005000,
  9db9813d; unchanged since on origin/main).
- Wave-2 documents: 02 §3.1 (565-640), §2 and §4 rows cited; 07 §2
  (424-470, 540-600), §3 rows 4, 6, 7, §4 (O-, U-, R-, X-, G- rows
  cited), §5 D5 (1136-1175); 08 §3 (479-530), §4 (C- rows cited), §5 T3
  headings, §8 (1318-1380); 10 (FP-11, R-1, line 767); 20 §3 rows and
  §5 tables (lines 200-470). Sections 3, 5 and 8 of all of 01-20 through
  a reader dispatched by this lane, its line citations spot-checked.
- Commits, read in full with `git show` (message and diff):
  c4a046e0, 31daec54, 276e8878, 3276be33 (stat), 3a96c407, 7987388b,
  16005000, b8301ebe, 9db9813d, ffa91113, e96bb991, 101edbc5, 51a4771b;
  `git diff e96bb991 101edbc5` for every file it touches; 51a4771b's
  `audits/flamegraph-2026-10-21.md` (whole) and its `audits/bugs.md`
  entry; `lib/Transforms/Defunctionalize/Pass.cpp` (80-105).
- Code at e96bb991: `lib/Transforms/Pipeline.cpp` (60-175),
  `lib/Analysis/Ownership/ExclusivityGraph.cpp` (15-60, 165-224),
  `ExclusivityAnalyses.cpp` (200-300), `Exclusivity.cpp` (160-180),
  `Uses.cpp` (85-130), `lib/IR/Verify/Linearity.cpp` (20-66),
  `lib/IR/Canon/Sink.cpp` (105-125, 195-236),
  `lib/Transforms/StructureLoops/Forms.cpp` (125-140),
  `include/idr/IR/IdrCheckOps.td` (15-60), `Traits.h` (GuardedOp),
  `include/idr/Support/Actions.h`, `Profile.h` (1-40),
  `lib/Driver/Run.cpp` (280-310).
- Code at 101edbc5 (`git show 101edbc5:<path>`):
  `lib/Analysis/Ownership/Positions.cpp` (whole),
  `lib/Transforms/Ownership/Commit.cpp` (30-160), `Traits.h` (120-150),
  `IdrBase.td` (285-305), `IdrMatchOps.td` (grep),
  `tests/rc-numbering-past-a-match` (head); 9db9813d's
  `tests/rc-reuse-read-field` (head).
- Commands: `git fetch origin` (four times); `git log origin/main` with the
  Co-Authored-By trailer; `grep -n`/`grep -c` over `audits/p0/*.md`;
  `ls bench/records`. Nothing built or run.
