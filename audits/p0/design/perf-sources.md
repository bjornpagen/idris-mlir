<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design input: what made the compiler slow, measured, and the C++ that makes each cause unrepresentable

Status: written 2026-10-21 against the working tree (e96bb991) and
origin/main as fetched that day, last at 1e1907ab (11:55). Sources: the
commits carrying the `Co-Authored-By: Muse` / `Muse Code` trailer (the
owner's parallel agent, "the agent" below), the Claude-trailered stage-1
commits the task names beside them, `audits/flamegraph-2026-10-21.md`
(51a4771b, "the flamegraph record"), `audits/bugs.md` at 51a4771b and
1e1907ab, `proposals/0001-self-host.md` §2 at origin/main, and the code
each names, ours and upstream's (`.toolchain/llvm-project`, unpatched
source). Lanes 20 and 21 (`audits/p0/20-history.md`,
`audits/p0/21-perf-tracing.md`) read some of this first; this document
goes down to the data structure and the call. The brief and the walls
are `audits/p0/wave1/00-brief.md` §2-§3.

Grounds: *measured (agent, hash)* or *measured (Claude, hash)*, the
commit or record that holds the number; *measured (wave 1)*, a wave-1
lane's own measurement; *read*, a path:line I read (ours at e96bb991
unless marked `main:`, which is origin/main at 1e1907ab; upstream as
`mlir/…` or `llvm/…` under `.toolchain/llvm-project`); *conjecture*.

The scale every rule below is judged at (*measured*, bench records by
Claude, d346040c): the stage-1 module is 75-82 MB, 63,464-69,773 Core
functions (114,110 `idr.func` at S2.1), 5,932-6,743 data types
(`bench/records/2026-10-16-self-emit.md`, `2026-10-17-self-growth.md`);
6,988 types entering defunctionalization (73bba53f); matches of tens of
thousands of cases (e96bb991).

## 1. The measured record

Every number the agent (and the Claude stage-1 commits the task names)
recorded, with its measure. No Muse commit added a `bench/records/` entry
(*measured*: the last is `2026-10-17-self-growth.md`); every stage-1
number below lives in a commit message or in 0001 §2 prose.

| # | commit (who) | pass / unit | the number | measure | build | corpus | caveat |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M1 | 3a96c407 (agent) | idr-optimize, three canon patterns | about 75 million attempts each in 31 traced minutes | action-profile count | release (full LTO) | stage 1 | a window, not the pass; no time per attempt |
| M2 | 16005000 (agent) | idr-frames, `bindGrammar`'s component | 336 s in one action; killed at 43 GB | action duration; RSS at a jetsam low-swap kill on 96 GB | release | stage 1 | RSS under-reads `phys_footprint` (wave 1 §5.11 K5) |
| M3 | 16005000 (agent) | upstream `remove-dead-values` | 52 GB | an untraced run stopped by hand while sampled | release | stage 1 | not a peak, not a kill: whether it would have finished is unknown |
| M4 | b8301ebe (agent) | idr-rc-stack | died at 47 GB; sampled live at 41 GB in `memmove` inside `BitVector` unions | live sample, then death | release | stage 1 | no number for the new form |
| M5 | 9db9813d (agent) | idr-rc-grades | 1088 take-on-borrow verifier errors | verifier count | release | stage 1 | correctness, one bug; `make test` 470/480 at b8301ebe |
| M6 | ffa91113 (agent) | idr-rc-exclusive on `DataFlowSolver` | 627 GB peak footprint when jetsam stopped it | jetsam footprint | release | stage 1 | no V/B/P/F counts: the split between container cost and state count is arithmetic only |
| M7 | e96bb991 (agent) | exclusivity's graph build | did not finish; after the fix 1.3 s of IdrRcExclusive on a generated 20,000-case match | wall, one pass | stage 1: release; fixture: **debug** | stage 1; fixture outside the tree | the after-number is not stage 1; the fixture's crash cases unknown |
| M8 | 101edbc5 (agent) | idr-rc-grades | half the samples in `findAncestorOpInBlock`, a quarter in block renumbering behind `isBeforeInBlock` | `sample` shares | release | stage 1 | not re-measured after; "the program suite has not been rerun" |
| M9 | 51a4771b (agent) | `make test-idr`, 343 fixtures | 673,331 on-CPU thread-ms; Defunctionalize's per-function lambda 70 % by total (17.9 % self), `applyConversion` and its thread callback 33 % self, `populateDefunctionalizePatterns` 4.7 %, `FrozenRewritePatternSet` ctor 4.3 %, its `Impl` dtor about 1.9 %, `Operation::print` 4.3 %, `ParallelDiagnosticHandler::eraseOrderIDForThread` 1.7 % self | 1 ms `sample`, inlines folded into "self", wait-leaf stacks excluded | profile: RelWithDebInfo, frame pointers, no LTO, hand-configured, swapped in for `build/dev` | suites, `IDRIS_MLIR_NCPU=2` | 52 % of on-CPU samples are one fixture (`defunc-tag-limit`, 65,538 functions), which hit its 60 s limit only under the sampler (flamegraph §Corpus A, lines 52-93) |
| M10 | 51a4771b (agent) | the same, `defunc-tag-limit` removed | `_pthread_mutex_firstfit_lock_slow` 11.1 %, `unlock_slow` 2.5 %, `recursive_mutex::lock` 2.2 %, `firstfit_lock_wait` 1.9 %, `__psynch_mutexdrop` 1.9 %, the diagnostic handler's order-ID map set/erase 3.8 %: "roughly a fifth"; printing 9 %, parsing about 4 % (the harness's round trip) | as M9 | as M9 | 964 files, 216,254 on-CPU samples | "it grows with thread count, so the two-core budget understates it" (§Findings 2) |
| M11 | 51a4771b (agent) | `make test`, 480 programs | 390,288 on-CPU; `toObjects` 34 % by total (29.9 % self), `PassManager::run` 16.6 % self, Defunctionalize lambda 9.1 % self, Optimize ≈ 3 %, Grades ≈ 3 %, `verifyOpAndDominance` 1.6 %, `_dyld_start` 1.2-2.2 %; 63 % of all samples the driver in `wait4` on its Chez frontend | as M9 | as M9 | suites | run at 403/480 (the `Positions` bug): lower ranks approximate (§Corpus C, lines 101-140) |
| M12 | 51a4771b (agent) | `--idr-rc` on the 20,000-case probe, one thread | 0.31 s profile build, 3.83 s dev build | wall | both | fixture | the dev build is 12× slower on the same work: no dev-build timing transfers |
| M13 | 51a4771b, 0be4e660, 1e1907ab (agent) | counting's `Positions` | `make test` 403/480 at 101edbc5 against 470/480; back to 470/480 at 0be4e660 | suite count | dev | suites | correctness of a perf change; 65 outputs "Malformed attribute storage object" through `place()` in the profile build |
| M14 | 98c6315c / 017f5374 (Claude) | idr-optimize's workers | queued on the uniquer's write lock, "about half the samples of a ten-minute window" | `sample` | release | stage 1 | recorded in 0001 §2 (main: lines 64-67), not in the commit |
| M15 | 73bba53f (Claude) | idr-defunctionalize | 843 s rebuilding the data-type table; 6,988 types to start | wall | release | stage 1 | "the dev build verifies every member of each remake" |
| M16 | b9d4d592 (Claude) | idr-defunctionalize | first half hour digesting types by printing | wall | release | stage 1 | |
| M17 | 1b2e31da, c179ab2d (Claude) | idr-optimize | six hours in one call of the sink pattern; a rewrite cycle in one lambda | hangs | release | stage 1 | correctness (non-termination), not cost |
| M18 | 4dde6b7f (Claude) | `defunc-tag-limit`'s match through the pipeline | 17, 56, 234 s at 1k, 2k, 4k cases; with patches 62 and 63, 1.1, 1.9, 3.4, 9.8 s at 1k, 2k, 4k, 16k | wall | private Release+assertions build of the pinned source | fixture | the patched toolchain was not yet built when measured |

Earlier stage-0/1 walls, kept for the patterns of §3 (*read*, lane 20
§3.2, not re-measured): the label solve's ~4.3·10⁹ (node, label) items,
~300 GB projected at 65,536 labels, each union-find class owning a copy
of its set (7adc6095); SCCP 8.8 s at 16,000 functions from
`resolveCallable` scanning the module per call visit, 0.7 s patched
(upstream/05); one function's InlineCleanup 211 s of a 447 s round, the
round's analyses serial (`bench/records/2026-10-14-f0-stage0.md`); the
simplify loop comparing printed text because `OperationFingerPrint`
hashes pointers (2ab5adf9).

General caveats (*read*): the release preset is full LTO
(`CMakePresets.json:24-28`), which "smears function attribution"
(flamegraph §Method, lines 12-14), so stage-1 samples name inlined
roots; the toolchain's MLIR is built with `LLVM_ENABLE_ASSERTIONS=ON`
(`tools/bootstrap.sh:1028`), so MLIR's own asserts run in the release
compiler, and with ABI-breaking checks on
(`.toolchain/build/*/include/llvm/Config/abi-breaking.h:19`), so every
`DenseMap` iterator in our code carries epoch checks; the suites run at
two cores; "rankings … known to invert at scale" (§Not measured, lines
241-245).

## 2. The causes

Each: the mechanism at the data structure and the call, the code, how it
scales, and whether and how it was fixed. C1-C12 are measured walls or
measured shares; C13-C14 are causes the record implies and the code
shows, not yet a measured share.

### C1. Patterns that match any op (M1)

- **Mechanism.** A pattern built with `MatchAnyOpTypeTag` has no root;
  freezing puts it in `nativeAnyOpPatterns`
  (`mlir/lib/Rewrite/FrozenRewritePatternSet.cpp:141`), and the
  applicator merges that list into the candidate list of **every op it
  visits** (`mlir/lib/Rewrite/PatternApplicator.cpp:77-84, 154-170`).
  Sinking, case-of-case and the empty-string case were such patterns,
  and each, at a non-match op, asked its question from the other end:
  `holdingMatch` ran `findAncestorOpInBlock` per user and
  `isBeforeInBlock`, `emptyCaseAbove` a worklist up every append chain
  (3a96c407's deleted code, `Canon/Sink.cpp`, `Canon/MatchPatterns.cpp`).
- **Scale.** Attempts = ops visited × any-op patterns; each attempt's
  scan per users or appends. 75 million each in 31 minutes (M1).
- **Fixed** (3a96c407, 7987388b): rooted at `MatchOpInterface` /
  `MatchLitOp` (an interface root is expanded to op names at freeze,
  `FrozenRewritePatternSet.cpp:129-134`), and NarrowWord at each op of
  the generated `IdrBigToWord` list by a parameter pack
  (`Narrow/Ops.cpp:217-228`). **Residue** (*read*): a rooted match
  pattern runs again on any change under the match, because the greedy
  driver pushes every ancestor of a changed op
  (`mlir/lib/Transforms/Utils/GreedyPatternRewriteDriver.cpp:641-657`;
  patch 62 defers multi-region ancestors), and `nearestSinkable` costs
  min(ops before the match, ops inside it) calls of `sinkable` per
  attempt (`IR/Canon/Sink.cpp:170-197`), each walking users with
  `isAncestor` (`:103-130`): attempts × block, unmeasured (lane 21 P-8).
  7987388b replaced the other any-op patterns by enumerating
  `getRegisteredOperations()` at run time: C2.

### C2. A static pattern set built, frozen and legalized per function (M9)

- **Mechanism** (*read*). `convert` (`Transforms/Defunctionalize/Pass.cpp:87-104`),
  called for every function in parallel (`:138-140`), builds a
  `SlotTypeConverter`, a `ConversionTarget`, a `RewritePatternSet` and
  then, per function:
  1. `populateDefunctionalizePatterns` (`Defunctionalize/Patterns.cpp:269-285`)
     adds one heap-allocated `RetypePattern` per **registered op** of
     every loaded dialect less a hand list of nine names (`:282`), each
     rooted by a `StringRef` that `OperationName`'s constructor hashes
     into the context's `StringMap` (`mlir/lib/IR/MLIRContext.cpp:910-922`);
  2. `applyFullConversion` freezes it: a `std::make_shared<Impl>` and a
     `DenseMap<OperationName, std::vector<RewritePattern *>>` with one
     vector per root (`FrozenRewritePatternSet.cpp:63-126`);
  3. the `OperationLegalizer` walks every pattern again and builds
     `invalidPatterns`, `parentOps`, `legalizerPatterns` and
     `minOpPatternDepth`, four hash maps keyed by `OperationName`, plus a
     `SetVector` worklist (`mlir/lib/Transforms/Utils/DialectConversion.cpp:2522-2533, 2927-3030`);
  4. the applicator copies every list into its own map and sorts each
     (`PatternApplicator.cpp:58-117`);
  5. all of it is destroyed at the function's end;
  6. the converter's cache of type conversions starts cold per function.
- **Scale.** F functions × R registered ops (×4-5 allocations each),
  whatever the function's size. R is every op of every dialect loaded
  when the pass runs, idr's 191 among them (*conjecture*: several
  hundred; the pass manager loads every pass's dependent dialects before
  the first pass). Before 7987388b the retype was one any-op pattern,
  which takes the legalizer's early return (`DialectConversion.cpp`
  `buildLegalizationGraph`, the `anyOpLegalizerPatterns` branch); after,
  the per-function setup is O(R): 7987388b's fix of C1 multiplied C2 by R
  (*conjecture*; lane 21 P-6 says the same, untested).
- **Measured** (M9): populate 4.7 %, freeze 4.3 %, destroy about 1.9 %
  self of test-idr's on-CPU samples, "a computed-once fact being
  recomputed" (flamegraph §Findings 1). `defunc-tag-limit` is a
  function-count stress (65,538 functions) of exactly stage 1's shape
  (~70,000), and it alone is 52 % of the corpus. **Not fixed.**

### C3. Global locks taken per work item, per pass, per op (M10)

- **Mechanism** (*read*). MLIR's parallel loops take one process-wide
  `std::recursive_mutex` twice per element:
  `failableParallelForEach` sets and erases the element's order id in a
  `ParallelDiagnosticHandler` (`mlir/include/mlir/IR/Threading.h:53, 61, 64`),
  each a `DenseMap` insert or erase under `SmartScopedLock`
  (`mlir/lib/IR/Diagnostics.cpp:1052-1062`; `SmartMutex` is a
  `std::recursive_mutex`, `llvm/include/llvm/Support/Mutex.h:28-29`).
  The verifier runs every isolated op through the same loop
  (`mlir/lib/IR/Verifier.cpp:367`) after every pass, and the pipeline
  has a dozen loops of ours (`grep parallelFor` over `lib/`: Effects,
  Recursion, Reuses, Grades ×2, Deduplicate ×2, Defunctionalize,
  TailCalls, TailCallPlan, Lower, Optimize's waves and ready set). Second,
  `PassInstrumentor` holds one recursive mutex across **every**
  instrumentation callback (`mlir/lib/Pass/Pass.cpp:1224-1293`), and
  idr-optimize runs a five-pass inner pipeline per node through
  `runPipeline` (`Transforms/Optimize/Component.cpp:84-97`), each pass
  calling before/after hooks on the driver's always-on timing
  (`Driver/Run.cpp:146-149`; `mlir/lib/Pass/PassTiming.cpp:46-134`, a
  `DenseMap` by thread id, and `mlir/lib/Support/Timing.cpp:247-252`, an
  `asyncMutex` per nesting from another thread), our Tracy zones
  (`Support/Profile.cpp:105-175`, a `std::mutex` and a map by thread),
  and the statistics fold.
- **Attribution** (*read*, against the record's label). The agent calls
  it "the context lock". On Apple the context's uniquer shards are
  `pthread_rwlock`s (`llvm/include/llvm/Support/RWMutex.h:22-23`,
  `llvm/lib/Support/RWMutex.cpp:41-56`), whose slow paths are
  `_pthread_rwlock_*`/`__psynch_rw_*` frames, none of which M10 lists;
  every leaf M10 lists is a pthread **mutex** (firstfit, mutexdrop,
  `recursive_mutex::lock`), and 3.8 % is the diagnostic handler's own
  map. So the contended locks are the per-element and per-hook mutexes
  above, not uniquing (*conjecture* which of them dominates: the record
  has no callers view).
- **Scale.** Elements × loops × passes: with F ≈ 70,000 and a
  verification per pass, millions of acquisitions of one lock per compile
  (*conjecture*, arithmetic); the critical section is a hash-map update,
  so contention grows with threads (M10's own caveat). **Not fixed.**

### C4. A mutable type's facts read through the uniquer's write path (M14)

- **Mechanism** (*read*, 98c6315c's diff of `IR/Types.cpp`). MLIR gives
  mutable storage one synchronized entry, `mutate`, which takes a shard
  **writer** lock chosen by the storage pointer's hash
  (`mlir/lib/Support/StorageUniquer.cpp:195-206`; 8 shards, `:139-141`).
  `holdsReferences`/`holdsWorld` of a data type read their facts through
  it (`ReadFacts`, `KeptFacts`, a lazy fixpoint with a "not yet" state),
  so every read of one popular type's facts, asked of every value by the
  flow-edge, carrier and lifetime verifiers in every optimizer worker,
  queued on one writer lock.
- **Fixed** (98c6315c, Claude): a group of types is sealed at once,
  body and facts solved and written in one `mutate`
  (`IR/Types.cpp:199-224`); every read after is a plain field. **Residue**
  (*read*): `Carriers::of(type)` recomputes `isClosureType`,
  `isLazyType` and `holdsReferences` per call (`IR/FlowEdges.cpp:26-38`),
  called per edge of every op the verifier checks: lock-free now, still a
  per-query computation of a constant of the type.

### C5. A growing table held as one immutable attribute, remade per insert (M15)

- **Mechanism** (*read*). The program's data types are one uniqued
  `DataTableAttr` of N members (`IR/IdrAttrs.td:318`). Declaring one
  type copied the member list, inserted by name, and called
  `get`: N hashed, N compared, N pointers allocated in the context's
  arena, never freed (`IR/DataBody.cpp` `with`, before 73bba53f), and,
  where our `NDEBUG` is off, `verify` ran: a name-ordered scan and an
  `AttrTypeWalker` over every field of every member with a
  `lower_bound` by name string per data type met (`DataBody.cpp:266-297`).
- **Scale.** O(N²) time, and O(N²) words of immortal arena (*conjecture*
  for the memory: about N²/2 × 8 B, ~200 MB at N = 7,000). 843 s.
- **Fixed** (73bba53f, Claude): `Declarations` collects and declares
  once per scope (`IR/Types.cpp:228-268`, `DataBody.cpp:327-335`,
  `IR/Func/Func.cpp:47`). **Residue**: each scope still remakes the
  table whole (scopes × N), and members are ordered and found by name
  string.

### C6. Identity by printed text (M16)

- **Mechanism** (*read*, b9d4d592's message): a data type's text held
  the body of every data type it reached, once per path, and types were
  digested by printing; a digest unfolded the type graph into a tree.
- **Fixed** (b9d4d592, Claude): a data type is nominal, `!idr.data<"T">`,
  its body once in the table. The same pattern earlier: the simplify
  loop's fixpoint test compared printed modules (2ab5adf9).

### C7. Upstream's dataflow state model, per value, whole program (M3, M6)

- **Mechanism** (*read*). `DataFlowSolver` keeps
  `DenseMap<LatticeAnchor, DenseMap<TypeID, std::unique_ptr<AnalysisState>>>`
  (`mlir/include/mlir/Analysis/DataFlowFramework.h:481-482`), so every
  anchor owns an inner hash map, ≥ 64 buckets once it holds one entry
  (`llvm/include/llvm/ADT/DenseMap.h:273, 282`), every state a heap
  object with a `SetVector` of dependents, itself a 64-bucket set from
  its first insert (`DataFlowFramework.h:559`); program points are
  uniqued in a `StorageUniquer` whose lookups take a thread-local cache
  and a shard lock even in a single-threaded solve, and are never freed
  (`:329, 376-404`; `StorageUniquer.cpp:160-191`). Exclusivity loaded four
  analyses (ffa91113^ `ExclusivityAnalyses.cpp:369-373`):
  `DeadCodeAnalysis` (an `Executable` per block point, a
  `PredecessorState` per callable), `NoConstants` (a
  `Lattice<ConstantValue>` per value, there only because dead-code
  analysis needs a constant lattice), `Running` (per function) and
  `ExclusiveAnalysis` (a `CellsLattice` per value). Upstream
  `remove-dead-values` keeps a liveness state per value beside the same
  two.
- **Scale.** ≥ two states per value, each about 2.9 KB, more than 90 %
  of it the two minimum-size tables (*measured (wave 1)*, §5.1 A4:
  1,460-2,916 B per anchor; a bit in a `BitVector` by value number is
  0.13 B). 627 GB, 52 GB.
- **Fixed by leaving the framework** (ffa91113: exclusivity's own graph
  and marking; 16005000: `remove-dead-values` out of the pipeline). No
  patch of the state storage was tried (lane 20 §3.1). **Residue**: Constants,
  Ranges, Borrows (run inside idr-rc-grades, `main:` `Grades.cpp`
  `getAnalysis<idr::Borrows>`), Narrow/{Lanes,Copy}, Tail/Returned and
  Effects/Constants are still on it (brief §2), and none of them has met
  stage 1's frontier yet but Borrows.

### C8. A fact per pair of value and cell, copied along every edge (M4)

- **Mechanism** (*read*, b8301ebe's diff of `Transforms/Stack/Stack.cpp`).
  The inference kept `llvm::MapVector<Value, llvm::BitVector> reach`, a
  candidate-width vector per value; `reached()` returned the vector **by
  value**, so every edge followed copied C bits, and `add` copied again
  before the union (`grown = it->second`); `keepFills` re-ran over all
  fills until nothing changed.
- **Scale.** V × C bits held, and edges × C/64 words copied per round
  (*conjecture*: V ≈ 10⁷ and C ≈ 4·10⁴ give the 47 GB order).
- **Fixed** (b8301ebe): one graph over cells and values, three
  markings, a bit per node (`Stack.cpp:116-268`, `mark` at `:197`).
  **Residue** (*read*): node ids are a pointer-keyed
  `DenseMap<Value, unsigned>` (`:265`), adjacency two
  `SmallVector<SmallVector<unsigned, 2>>` (`:267`, a header plus inline
  room per node per direction), edges found by `std::visit` over the
  edge variant through a callback per op (`:132`); whole program and
  serial; no stage-1 number.

### C9. IR cloned per pair of member and answer (M2)

- **Mechanism** (*read*, 16005000's diff of `Tail/Frames.cpp`
  `perform`). For every answer type and every member, a clone of the
  member's body (`fn->clone(mapping)`, one `IRMapping`, three hash maps,
  per pair) and a resume filled with every frame's rest.
- **Scale.** M × A × (|body| + F × |rest|) ops.
- **Fixed** (16005000): one answer sum per component, one run per
  member, one resume per result type (`include/idr/Transforms/Tail.h:171-220`).
  **Residue**: R·(F+1) + M·R (lane 10 R-4); a component whose result
  type no field may hold keeps plain calls (lane 21 P-10); the 336 s
  action not re-measured.

### C10. An interface query per pair of successor and terminator (M7)

- **Mechanism** (*read*, e96bb991's diff). For each successor of a
  region branch (N+1 for an N-case match) the graph build asked
  `goesTo` of the parent point and of every terminator; `goesTo` called
  `getSuccessorRegions` into a fresh `SmallVector`, which for the parent
  point pushes all N regions (`include/idr/IR/IdrMatchOps.td:63-72`).
  The marking re-asked the same per run of each successor item.
- **Scale.** (N+1)·(N+1) interface calls, (N+1)·N of them O(N) each:
  cubic in the worst term, "the square of the case count" in lookups.
- **Fixed** (e96bb991): each point read once, each successor carries
  its sources (`Analysis/Ownership/ExclusivityGraph.cpp:170-224`).
  **Residue** (*read*): `unknownFrom` appended to every successor
  (`:222`, N × crash blocks); the op successor re-joins all N
  predecessors on every run (`ExclusivityAnalyses.cpp:228-271`); every
  execution of an op item rebuilds its `FlowEdges` (`:148-154`); the
  state is `DenseMap<Value, Sharing>`, dependents
  `DenseMap<Value, SmallVector<unsigned, 2>>` and a `DenseSet<Block *>`
  per function (`ExclusivityAnalyses.cpp:315-316`,
  `ExclusivityDetail.h:155`), all pointer-keyed.

### C11. IR navigation recomputed per query (M8, M13)

- **Mechanism** (*read*). Counting's queries (`Analysis/Ownership/Uses.cpp`
  at e96bb991): `usedAfter` climbs the ancestors of `op` and, at each
  level, collects the value's users in that block (`:113-128`), each by
  `findAncestorOpInBlock` (`:75-82`) and `isBeforeInBlock`, sorted with
  `isBeforeInBlock` as comparator (`:29-39`); `decides` asked
  `getSuccessorRegions` into a fresh vector of N successors per call
  (`:96-104`). Upstream: `findAncestorOpInBlock` walks the parent chain
  (`mlir/lib/IR/Block.cpp:74-84`), each step an out-of-line
  `Block::getParentOp` (`:31-33`) of three dependent loads;
  `isBeforeInBlock` keeps an order index with a stride of 5
  (`mlir/include/mlir/IR/Operation.h:1009`), so the third insertion into
  one gap renumbers the whole block (`mlir/lib/IR/Operation.cpp:398-451`,
  `Block.cpp:136-142`), and any splice or move invalidates the block's
  whole order (`Operation.cpp:507-516`); with the toolchain's assertions
  on, that invalidation also runs `assert(!verifyOpOrder())`, a walk of
  the whole block, per move (`Block.cpp:107-111`).
- **Scale.** usedAfter O(depth × uses × depth) plus a sort per level;
  counting inserts a dup, drop or take per value and moves consumers in
  bodies that are mostly one block: renumberings × block size.
- **Fixed** (101edbc5, repaired 0be4e660): `Positions`, a pre-order
  numbering per function with a 2¹⁶ gap after each op, spans for
  ancestry, lazy numbering of inserted ops, `forget` before erase or
  move. It shipped without the block as a coordinate: an op written at a
  case's start was numbered against the match's whole span, the cases'
  spans overlapped, `usersIn` returned whole case blocks, and 67 programs
  failed (M13); 0be4e660 gives each block its own extent. **Residue**
  (*read*, `main:` `Analysis/Ownership/Positions.cpp`): three
  pointer-keyed maps per op and block (`main:` `Ownership.h:164-170`);
  `assign` scans the block for numbered neighbours, walks the inserted
  op to count, and inserts into a sorted vector (`:96-116, 153-158`),
  and `forget` erases from it (`:161-176`), each O(block); any block
  the numbering does not know renumbers the whole function (`:88-91,
  186-195, 275, 300`); `usePositions` re-collects and re-sorts a value's
  use positions per query (`:245-255`); the recursion goes through a
  `std::function` (`:120`); the class is built three times per function
  per run of counting, beside the owned verifier's own numbering (lane
  21 P-2). Not measured on stage 1 since.

### C12. Revisiting a many-region op after every change inside it (M18)

- **Mechanism** (*read*, 4dde6b7f; upstream as pinned). The greedy
  driver's `addToWorklist` pushes the changed op and every ancestor to
  the scope (`GreedyPatternRewriteDriver.cpp:641-657`), so an N-region
  match is revisited after each change in any region, and the
  region-branch patterns read all N regions per visit: O(N²); liveness
  asked `wouldOpBeTriviallyDead`, a walk of every region, once per
  region successor.
- **Fixed upstream-first** (patches 62, 63, carried; 63 reaches nothing
  since 16005000).

### C13. A question answered by mutating or cloning IR (M17)

- **Mechanism** (*read*). To ask whether a consumer folds with a
  constant, `canon::feeds` folded the consumer itself with the constant
  swapped in and put it back; a commutative fold relinked a use list a
  caller was walking, which never ended (1b2e31da). Now `foldsWith`
  clones the op without regions per probe (`IR/Canon/Feeds.cpp:75-93`):
  an allocation, a use inserted into and removed from every operand's
  use list, and an erase, per probe, on the sink pattern's path.
- **Status.** Correct; the per-probe allocation and use-list mutation
  stand, unmeasured.

### C14. Costs outside the passes the suites show (M11)

The LLVM backend (`toObjects` 34 % by total), the pass-manager's own
machinery (16.6 % self, inlined children unresolved), process start
(`_dyld_start` 1.2-2.2 % over ~1,900 launches), the harness's print and
parse round trip (13 %), and the frontend the driver waits on (63 % of
samples). These bound the suites' wall clock and say nothing of stage
1, where the record expects the ranking to invert (§Findings 3-6).

## 3. Patterns across the causes

| pattern | instances | what it costs |
| --- | --- | --- |
| **Dispatch tried on every op.** A rewrite or check whose root is "any op", or a run-time enumeration of every registered op standing in for one. | C1 (three canon patterns, NarrowWord, RetypePattern, PoisonResults before 7987388b); C2 (`getRegisteredOperations()` in `Patterns.cpp:282` and `tools/idris-mlir-reduce.cpp:61`) | attempts × ops; R patterns per set |
| **Per-unit construction of what is static.** Built per function (or per node, per pass run) though nothing in it depends on the function. | C2 (pattern set, freeze, legalizer, cold converter cache); C11 (`Positions` three times per function); C3 (instrumentation hooks per pass per node) | F × R allocations; F × hooks |
| **Shared mutable state touched from workers, and global locks per work item.** | C3 (diagnostic order map, instrumentor, timing, zones); C4 (reads through `mutate`); predicted: lowering's crash-site `StringAttr`s from workers (lane 12 CV-16), types made per value by `setType` (`Stack.cpp:346`, counting's grades) | a fifth of a corpus at two threads, more at more |
| **A fact recomputed per query that could be numbered or computed once.** | C11 (ancestry, order, `decides`, use positions), C10 (`goesTo`), C4 residue (`Carriers::of`), C10 residue (`FlowEdges` per item run), C12 (trivially-dead per successor) | queries × depth or × N |
| **Pointer-keyed hash maps per node.** A ≥ 64-bucket `DenseMap`/`DenseSet` per anchor, per function, or keyed by `Value`/`Operation *`/`Block *` where a dense id would index an array. | C7 (inner map and dependents per anchor); C8, C10, C11 residues (`ids`, `sharing`, `dependents`, `liveOf`, `spans`, `blockSpans`, `opsInBlock`) | ~1 KB per non-empty map; a hash and a miss per query |
| **Whole-program state per value in a general framework.** | C7 (exclusivity, `remove-dead-values`); C8 before b8301ebe | V × states × 2.9 KB |
| **Products where the problem is a sum.** A fact, a clone or a query per pair. | C8 (value × cell), C9 (member × answer), C10 (successor × terminator), C5 (declaration × table), label solve (node × label, 7adc6095) | quadratic memory or time |
| **Identity or order by text.** | C6 (digest by printing); 2ab5adf9 (fixpoint by printed module); C5 (table ordered and searched by name string); C2 (patterns rooted by name lookups, `handled` as a list of names) | unfolding; string hashes and compares on hot paths |
| **Asking by mutating or copying.** | C13 (fold probe in place, then a clone per probe); C9 (clones per pair) | allocation per query; hazards |
| **Immortal allocations from transient work.** The context's arena grows with every intermediate table, point, type or string a pass makes and drops. | C5 (a table per declaration); C7 (program points never freed); types made per value (`setType` in counting and stack) | arena growth with no free (*conjecture*, unmeasured) |
| **A derived index maintained by hand through rewrites.** | C11 (`Positions`, `forget` called by each rewrite; the missing block coordinate miscompiled 67 programs) | correctness, M13 |
| **Fixes each wrote their own graph.** | C8, C10, C11: three graph or numbering types in twelve hours, no shared code, none an action (lane 21 P-14) | each new wall rebuilds the layer |

## 4. Rules for P0's C++

Each rule names the representation that makes its causes unrepresentable,
what it ties to, and where the C++ type system (templates, concepts,
`consteval`) can enforce it. They are design inputs for the owner, not
settled.

**R1. Every pattern's root set is a compile-time list.** A rewrite is
rooted at an op type, a trait or an interface named in its template
arguments; a set over several ops is a parameter pack generated from ODS
(the shape `addNarrowWords<Ops...>` already has, `Narrow/Ops.cpp:217-228`,
from `IdrBigToWord.inc`). `MatchAnyOpTypeTag`, `getRegisteredOperations()`
in a populate function, roots spelled as strings and hand lists of
"handled" names do not exist. A retype that applies to "every op whose
types change" is not a pattern: it is a walk over the ops the plan names.
Ties: C1, C2; M1, M9.

**R2. What does not depend on the unit is frozen once per process, and
units receive only data.** Pattern sets, conversion targets, legalizer
graphs and type converters are built in a pass's `initialize` (or once
per run, before the parallel loop) and shared read-only; a per-function
plan is data the shared object reads through a reference passed at match
time, never a reason to rebuild it. A concept for "unit work" takes
`(const Frozen &, const Plan &, Unit)` and nothing constructible.
idr-optimize's pool of pipelines (`Component.cpp:84-97`) is the existing
good form. Ties: C2 (F × R), C11 (three builds per function); M9.

**R3. No context mutation, and no synchronized read, on a worker.** A
parallel phase sees the context through a `const` view; every type,
attribute, location and string it needs is made in a serial prologue
from a plan, or its result is data materialized serially after the loop.
Make it a type: creation goes through a `Materializer &` that only the
serial phase can construct, so a worker cannot name a creating call.
Mutable storage is sealed before any reader exists (98c6315c's shape)
and is read as plain fields. Ties: C3, C4; M10, M14.

**R4. Parallelism is chunked, and per-element machinery stays off the
hot path.** One parallel loop per phase over chunks balanced by op count
(not one task per function at F ≈ 70,000); diagnostics are collected as
data per chunk and emitted in order once, so `ParallelDiagnosticHandler`
is not entered per element; no per-node `OpPassManager` runs under
instrumentation (timing, zones, statistics hooks per pass per node);
verification of 70,000 functions is one chunked loop. Ties: C3; M10.

**R5. Dense ids, computed once per scope, are the coordinates.** Every
function, block, op and value a solver or query touches gets a dense
`uint32_t` per scope (function or program), in one pre-order walk that
also records block begin/end as coordinates (0be4e660's lesson: a block
is a coordinate, not a gap between ops) and parent and depth per op.
Order is an integer compare, ancestry an interval test, "users in block
B after p" a range over a use list sorted once. The numbering is one
cached analysis shared by every client and the verifier, invalidated by
a `RewriterBase::Listener` or by planning before rewriting, never by a
hand `forget`. `findAncestorOpInBlock`, `isBeforeInBlock` and
`getParentOp` chains do not appear in a loop. Upstream already offers a
stable O(1) `Block::getBlockID` (`mlir/include/mlir/IR/Block.h:62-65`).
Ties: C7, C8, C10, C11; M6, M8, M13.

**R6. State is sized by the problem, as arrays indexed by dense id;
pairs exist only as an explicit sparse edge list.** A solver's state is
a `BitVector` or a `std::vector<Lattice>` indexed by node id; its graph
is CSR (`offsets`, `targets`, both `uint32_t`), built in one linear pass
that reads each op, each region-branch point and each terminator once
(e96bb991's form); a marking is a BFS over it. No map keyed by `Value`,
`Operation *` or `Block *` holds per-node state; no fact is held per pair
of nodes; no state is copied along an edge. Ties: C7, C8, C9, C10, the
label solve; M3, M4, M6, M7.

**R7. A fact of a type or an op kind is a constant, read by a load.**
Per-type facts (carriers, `Held`, closure, lazy, reference-holding) are
a bitset in the type's storage, computed when the type is made or
sealed. Per-op-kind facts (decides, builds a value, the operand roles a
flow model reads, the runtime symbol) are `constexpr` tables generated
from ODS and indexed at compile time by the op class (a
`consteval`-built table per op type, read through a template parameter),
not an interface walk per query and not a `verifyTrait` that re-derives
an interface's answer per verification. Ties: C4 residue, C10, C11's
`decides`; M8, M14.

**R8. A table that grows is built once per phase.** Members are
collected into a builder and uniqued once (73bba53f's `Declarations`,
generalized to every phase that adds types); identity and order are
dense ids, names are for printing only. No immutable uniqued attribute
holding a set is remade per element. Ties: C5, C6; M15, M16.

**R9. Identity is never text.** No digest, fingerprint, sort key or
lookup by printed form or by op name string on a hot path: op kinds by
`TypeID` or a generated enum, data types by id, fixpoints by explicit
change bits. Ties: C2, C5, C6, 2ab5adf9.

**R10. Answering a question allocates nothing and mutates nothing.** A
probe folds attributes, not an op: constant folders as functions over
operand attributes generated per op kind, or one scratch op per thread
reused; no clone per probe, no relinking of use lists to ask.
Ties: C13; M17.

**R11. Whole-program solves are one shared layer, and each unit is an
action.** Where a question is essential over the whole program
(exclusivity, frame lifetimes), it is one graph type, one linear build,
one marking, in the solver layer, with each function's or SCC's work a
`TaggedAction`, so the profile names it and `-mlir-debug-counter`
bisects it. Where a per-function or per-SCC solve with summaries
answers, that is the form. Ties: C7, C8, C10, the three ad hoc graphs.

**R12. No type erasure on a hot path where the set is closed at compile
time.** Recursion is a member function or a deducing-`this` lambda, not
a `std::function` (`Positions.cpp:120`); edge enumeration is a template
over the op's flow model, not a `function_ref` per edge with a
`std::visit` per edge (`Stack.cpp:132`, `ExclusivityAnalyses.cpp:170-185`).
Ground: the owner's directive and the sampler's undivided "self"
buckets; no measurement isolates this cost yet (*conjecture* for its
size).

**R13. The production build and every measured build state their
assertions, and the production compiler links an MLIR without them.**
The release compiler today runs MLIR's asserts, among them a whole-block
walk per op move (`Block.cpp:107-111`), and DenseMap epoch checks in our
own code (§1 caveats); the profile build is 12× faster than dev on the
same probe (M12). Whether the shared toolchain splits into an
assertions build for tests and an assertions-off build for production
is the owner's and lane 13's (drv-Q1); the cost is unmeasured (U8).

## 5. What is still unmeasured, and must be

Each on stage 1 unless said, at one recorded commit (origin/main is
1e1907ab, 470/480), release build, a `bench/records/` entry per run
whether or not it finishes.

| # | what | why it matters | instrument |
| --- | --- | --- | --- |
| U1 | The frontier after 1e1907ab, and per pass `-mlir-timing` and peak footprint in jetsam's measure (`phys_footprint`), with V, B, P, F at each solve point and the largest matches' case and crash-case counts | no pass has a recorded stage-1 time; every stage-1 number in §1 is a kill, a stop, a window or a share | a per-pass `PassInstrumentation` writing footprint (wave 1 §5.11 A2), `-mlir-timing`, counts |
| U2 | idr-rc-grades after 101edbc5 and 0be4e660 | the fix of M8 is unmeasured; `assign`/`forget` are O(block) and unknown blocks renumber the function (C11 residue) | the action profile with a `TaggedAction` per function; `sample` |
| U3 | idr-rc-exclusive on the module itself | M7's after-number is a debug fixture; `unknownFrom` × crash blocks and the op successor's re-join are open | as U2 |
| U4 | idr-defunctionalize's per-function setup at F ≈ 70,000: R, and the shares of populate, freeze, legalizer and destroy | C2's scaling is F × R; M9 measured it only on suites | `sample` on a profile build at stage-1 scale; count R |
| U5 | Which mutex M10's slow paths are, at NCPU 2, 8 and the machine's width | C3's attribution is by reading; the fix differs per lock | a callers view (`xctrace` Time Profiler expands inlines, flamegraph §Not measured) |
| U6 | The verifier after every pass: total, and our op verifiers' parts | nine lanes predict it; suites show 1.6-1.7 %; `verifyFlowEdges` tests each edge's value with `llvm::is_contained` over the op's operands (`IR/Flow.cpp:164-170`), quadratic in an op's operand count; `Carriers::of` per edge; `Decides`' `verifyTrait` asks the interface per region (`main:` `Traits.h:133-147`) | `-mlir-timing` with and without `-verify-each` |
| U7 | The framework solves still ahead of the frontier: Ranges in idr-narrow, Tail/Returned on the lowered module, Constants, Borrows inside grades | the next C7 walls, by the same state model | each in isolation with footprint |
| U8 | Assertions in the toolchain's MLIR and ABI-breaking checks | C11's per-move block walk, DenseMap epochs in our code | stage 1 with an assertions-off MLIR, same commit |
| U9 | Canonicalization's per-attempt cost after rooting | C1 residue: `nearestSinkable` min(B, M) per attempt, attempts per change under a match | the action profile's per-pattern totals |
| U10 | idr-frames after 16005000 | the 336 s action was not re-measured; residue R·(F+1) + M·R | the action profile |
| U11 | The arena: bytes the context holds at each pass end | C5, C7 and per-value `setType` allocate forever | a per-pass instrumentation reading the allocator's totals |
| U12 | Whether 7987388b raised C2 | one any-op pattern became R rooted patterns per function | populate+freeze+legalizer time per function before and after, on `defunc-tag-limit` |
| U13 | The lowering's context writes from workers and the 71 MB bytecode read | predicted by lanes 12 and 13, never reached or timed | as U1 |

## 6. Sources read

- `.claude/skills/representation-first/SKILL.md` (whole); `AGENTS.md`;
  `audits/p0/wave1/00-brief.md` §2-§3 (identical to the proposal's §2-§3
  as first read); `audits/p0/21-perf-tracing.md` and
  `audits/p0/20-history.md` §3-§4 (whole where cited);
  `audits/p0/wave1/5.1-mlir-analysis.md` A4-A5.
- `git show origin/main:audits/flamegraph-2026-10-21.md` (all 266 lines);
  `audits/bugs.md` diffs of 51a4771b and 1e1907ab;
  `git show origin/main:proposals/0001-self-host.md` §1-§2;
  `bench/records/` listing and the 10-14, 10-15, 10-16, 10-17 records'
  heads.
- Commits, message and diff: 3a96c407, 7987388b, 16005000 (Frames,
  Pipeline, Tail.h, bugs.md, 0001), b8301ebe, 9db9813d (message, stat),
  ffa91113 (message, stat, the old solver's analyses), e96bb991,
  101edbc5 (message, stat), 51a4771b, 0be4e660, 1e1907ab, 98c6315c
  (message, `Types.cpp`), 73bba53f, b9d4d592, 1b2e31da, c179ab2d,
  196d3c6f, 4dde6b7f, 276e8878 (messages). The Muse Spark commits of
  10-12 and c4a046e0, 31daec54, 3276be33 are not perf work.
- Ours at e96bb991: `Transforms/Defunctionalize/{Pass,Patterns}.cpp`,
  `Driver/{Register,Run}.cpp`, `Support/Profile.cpp`,
  `Transforms/Optimize/{Component,Optimize}.cpp`,
  `Transforms/Stack/Stack.cpp`, `Analysis/Ownership/{ExclusivityGraph,ExclusivityAnalyses,Uses}.cpp`,
  `ExclusivityDetail.h`, `IR/{Types,DataBody,FlowEdges,Flow,Regions}.cpp`,
  `IR/Canon/{Sink,Feeds}.cpp`, `Narrow/Ops.cpp`, `IdrMatchOps.td`,
  `tools/idris-mlir-{opt,reduce}.cpp`, `Transforms/Contracts/Contracts.cpp`
  (hooks). At origin/main: `Positions.cpp`, `Ownership.h`, `Grades.cpp`,
  `Traits.h` (Decides).
- Upstream at the pin: `FrozenRewritePatternSet.cpp`,
  `PatternApplicator.cpp`, `DialectConversion.cpp` (legalizer),
  `GreedyPatternRewriteDriver.cpp` (`addToWorklist`), `MLIRContext.cpp`
  (op names, string-attr dialect refs), `StorageUniquer.cpp`,
  `Threading.h`, `Diagnostics.cpp` (parallel handler), `Pass.cpp`
  (instrumentor, `run`, verification), `PassTiming.cpp`, `Timing.cpp`,
  `Verifier.cpp`, `Block.cpp`, `Operation.cpp`/`.h` (order),
  `DataFlowFramework.h`, `llvm/ADT/DenseMap.h`, `llvm/Support/{Mutex,RWMutex}.h`,
  `RWMutex.cpp`; `tools/bootstrap.sh` (toolchain flags);
  `CMakePresets.json`.
- Commands: `git fetch origin`; `git log`/`git show`/`git diff` only.
  Nothing built or run.
