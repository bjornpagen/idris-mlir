<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Where the compiler's CPU goes: a sampling audit of both suites (2026-10-21)

Measured on main at `101edbc5`, arm64 macOS, `IDRIS_MLIR_NCPU=2`
throughout. This is a measurement record, not a fix: every number below
came out of the sampler described next, and the one bug it found is
registered in `bugs.md` (ownership, the `Positions` renumbering).

## Method

- A dedicated profile build in `build/profile`: `RelWithDebInfo`
  (`-O2 -g`), `-fno-omit-frame-pointer`, no LTO (the release preset's
  full LTO smears function attribution). Configured by hand with the
  pinned toolchain file; no preset was added. The harness resolves its
  tools through `build/dev`, so for each corpus run `build/dev` was a
  symlink to `build/profile` (the dev tree moved aside and restored
  after; no build ran while swapped). A front link
  (`idris-mlir-front`) was made inside the profile tree.
- Capture is macOS `sample` at 1 ms. dtrace is unavailable (SIP, no
  passwordless sudo). Two `sample -wait <name>` waiters per binary
  (`idris-mlir`, `idris-mlir-opt`) attach at process birth and respawn;
  one pid-polling slot (50 ms) attaches to long-lived processes the
  birth grabs already left. Per-grab symbolication overhead measured
  at 0.02–0.03 s, negligible. The sampler also recorded per-pid RSS
  every 2 s. Scripts (sampler, call-graph collapser, flamegraph SVG
  generator) are throwaway Python described under "Reproducing";
  raw traces are not committed.
- A sample is one thread-millisecond. Stacks whose leaf is a wait
  primitive (`__ulock_wait`, `__wait4`, `__psynch_*`, `mach_msg`,
  `_pthread_cond_wait`, blocking read/write, …) are bucketed
  "blocked" and excluded from the on-CPU tables. Every tool's main
  thread sits in `pthread_join` for its worker, and the driver waits
  in `wait4` for its Chez-hosted frontend child; both are blocked by
  this rule, which is why blocked counts are large.
- `sample` does not expand inlines: a "self" attribution names the
  out-of-line frame the PC was in, with inlined callees folded into
  it. Read "self" as "self plus everything inlined into it", and use
  the total (subtree) column and the flamegraphs for structure.
- Interference is real and was measured, not hidden: one test in
  corpus A (`defunc-tag-limit`) hit its 60 s step limit only under
  the sampler. The suites otherwise behave as they do unsampled,
  with one exception that is the bug below.
- The profile build runs the 20 000-case wide-match probe
  (`--idr-rc`, one thread) in 0.31 s against the dev build's 3.83 s.
  Absolute suite walls under the profile build therefore say little
  about the dev build; the rankings carry over, exact percentages
  shift.

## Corpus A: `make test-idr`, 343 fixtures

751 s wall, 995 sample files, 1 122 compiler pids seen, peak sampled
RSS 968 MB. 1 461 421 samples, of which 673 331 on-CPU and the rest
blocked. The suite itself: 342/343, the one failure the sampler
timeout above.

One fixture is the corpus's center of mass. The 16 largest grabs —
consecutive, all from `defunc-tag-limit`, whose defunctionalize step
ran to the 60 s step limit — hold 52 % of all on-CPU samples. Both
readings matter, so corpus A is reported whole and with those grabs
removed (964 files, 216 254 on-CPU samples).

On-CPU self time by owner, whole corpus: upstream MLIR/LLVM 54 %,
anonymous-namespace (ours and MLIR's pass structs, inseparable by
name) 20 %, other/system 20 %, `idr::` 6 %. With the one fixture
removed: upstream 54 %, other/system 32 % (mostly the mutex slow
paths below), anonymous-namespace 9 %, `idr::` 4 %.

Hottest by self, whole corpus (template arguments elided):

| % | function |
| --- | --- |
| 25.3 | conversion driver callback (`applyConversion`'s thread lambda) |
| 17.9 | `Defunctionalize::runOnProgram`'s per-function lambda |
| 8.0 | `applyConversion` |
| 4.7 | `idr::defunctionalize::populateDefunctionalizePatterns` |
| 4.6 | `_pthread_mutex_firstfit_lock_slow` |
| 4.3 | `mlir::FrozenRewritePatternSet` constructor |
| 4.3 | `mlir::Operation::print` |
| 1.7 | `mlir::ParallelDiagnosticHandler::eraseOrderIDForThread` |
| 1.6 | `mlir::applyFullConversion` |
| 1.2 | `FrozenRewritePatternSet::Impl` destructor |

By total, `Defunctionalize`'s per-function lambda alone covers 70 %
of on-CPU samples (`applyFullConversion` 38 % under it). With the
`defunc-tag-limit` grabs removed, that lambda is still 4.9 % self,
and the table is led by `_pthread_mutex_firstfit_lock_slow` at
11.1 %: parallel conversion and verification threads queue on the
context lock. The lock-adjacent leaves sum to roughly a fifth of the
reduced corpus (`firstfit_lock_slow` 11.1 %, `unlock_slow` 2.5 %,
`recursive_mutex::lock` 2.2 %, `firstfit_lock_wait` 1.9 %,
`__psynch_mutexdrop` 1.9 %, `ParallelDiagnosticHandler`'s order-ID
map set/erase 3.8 % combined).

Two costs are the harness's, not a user compile's, and are named so
nobody optimizes them by mistake: printing is 9 % of the reduced
corpus (`Operation::print` 7.8 % + 1.3 %, the lit round-trip check
`--verify-roundtrip` reprints every fixture), and parsing about
4 % (`parseAsmSourceFile`, `OperationParser::parseOperation`).

## Corpus C: `make test`, 480 programs

748 s wall, 969 sample files, 760 pids, peak sampled RSS 331 MB.
2 346 086 samples, 390 288 on-CPU. Blocked is 83 % of all samples:
the dominant leaf of the raw corpus is `__wait4_nocancel` at 63 % —
wall time in this corpus is mostly the Chez-hosted frontend running
while the driver waits, plus each tool's join thread. That is a
statement about the suite's shape (480 small programs, each paying a
frontend), not about the pipeline.

On-CPU self by owner: anonymous-namespace 46 %, upstream 40 %,
other/system 7 %, `idr::` 7 %. Hottest by self:

| % | function |
| --- | --- |
| 29.9 | driver `toObjects` (lowering + LLVM to objects) |
| 16.6 | `mlir::PassManager::run` |
| 9.1 | `Defunctionalize`'s per-function lambda |
| 5.0 | driver `run`'s `std::visit` over handoff/lowered |
| 3.3 + 3.0 | `OpToOpPassAdaptor::runPipeline` / `::run` |
| 2.9 + 2.8 | `Optimize::runOnProgram`, `idr::optimize::Scheduler::turn` |
| 2.4 + 2.0 + 1.6 | LLVM backend pass managers (`FPPassManager`, legacy PM, inliner) |
| 2.0 | `idr::driver::writeObjects` |
| 1.7 + 1.6 | Grades' per-function lambda and `Grades::runOnProgram` |
| 1.6 | `OperationVerifier::verifyOpAndDominance` |

By total: `toObjects` covers 34 % of on-CPU samples, the pass
manager 24 %, defunctionalize's lambda 9.5 %. In small whole-program
compiles the backend and pass-manager machinery outweigh the idr
passes; counting (Grades and everything under it) is a few percent.

Corpus C also has a validity caveat that outranks its numbers: the
suite ran 403/480 under this build, against a standing 470/480. That
is the bug below, found by this run. Compiles that abort early burn
less and different CPU, so read corpus C's ranking as sound at the
top (backend, pass manager, defunctionalize) and approximate below
it. 65 test outputs carry the same MLIR assertion signature
("Malformed attribute storage object", through Grades' `place()`),
which is the optimized manifestation; the dev build asserts earlier
and legibly (below).

## The bug this audit found: counting's numbering corrupts under counting's own rewrites

`101edbc5` replaced counting's per-query block walks with
`Positions` (`foreign/idr/lib/Analysis/Ownership/Positions.cpp`):
one gap-interval numbering of a function, maintained incrementally
as rewrites insert ops (`assign`) and told about erasures and moves
(`forget`). `make test` had not run on that commit when it landed;
corpus C is its first program-suite run.

What is established:

- `tests/chars` reproduces standalone (`tools/compile.sh` on a copy
  of its `Main.idr`), on both builds, deterministically. The dev
  build asserts in `placeOwned` (Placement.cpp): the last use of an
  owned value is a terminator that does not take it over. The
  pre-grades module is small (875 lines) and the assert reproduces
  with `idris-mlir-opt -mlir-disable-threading --idr-rc-grades` on it.
- At the assert, `usersIn` for the match-scrutinee value in one case
  block returns *every op of the block* (unpack, io call, con,
  yield), though only the unpack uses the value. The kept numbering
  at that point has case blocks of one match interleaved: the four
  cases' first ops sit at 14 565 376 / 14 663 680 / 14 761 984 /
  14 893 056 with span widths of 16 384 / 114 688 / 212 992 /
  344 064 — the spans overlap across cases, so ancestry-by-containment
  and the binary search in `topIn` answer with ops of the wrong case.
- A freshly constructed `Positions` at `place()` time compiles the
  repro cleanly; a fresh one before `reshape` does not. The
  corruption is therefore introduced by the incremental maintenance
  during the reshape phase (selects, take-apart, consumer sinking,
  field owning), not by the numbering's semantics and not by the
  reuse rewrite before it. The individual `assign` that first
  overlaps was not yet caught; overlapping widths are consistent
  with ops being numbered one at a time against the parent op's
  whole span rather than within their block's extent.
- The profile build's "Malformed attribute storage object" crashes
  (65 outputs in corpus C) share the `place()` stack and are taken
  to be this same corruption reaching op creation under `NDEBUG`-off
  MLIR assertions at `-O2`; not yet proven identical. 5 outputs are
  `mlir.expect` failures at `idr-rc-exclusive` (counting placed
  differently), also consistent with wrong death answers.

What is owed (registered in `bugs.md`): catch the first overlapping
`assign` (log allocations whose step exceeds the fresh numbering's
gap, with the op and bounds), then fix at the representation — the
candidates are numbering whole blocks when their parent is numbered,
bounding an insert by its block's own extent, or renumbering at
phase boundaries inside Grades (measured clean on the repro if done
before placement, still corrupt if only done before reshape — so a
boundary-only fix must also hold within reshape). Add the smallest
fixture: the pre-grades module of `tests/chars` reduced to the one
function, as an `--idr-rc-grades` lit test, or the shape that makes
it: a match whose cases each unpack the scrutinee while counting
inserts takes/dups in the cases during reshape. Then rerun
`make test` to the standing count before trusting corpus C below
its top ranks.

## Findings, ranked by measured share

1. **Defunctionalize's conversion is the dialect corpus's centre of
   mass**, and still 9.5 % by total in whole-program compiles. Two
   separable costs: the conversion itself (`applyConversion` and its
   thread callback, 33 % self combined in corpus A), and rebuilding
   its pattern set per function — `populateDefunctionalizePatterns`
   4.7 % self plus `FrozenRewritePatternSet` construction 4.3 % and
   destruction ~1.9 %, paid inside the per-function parallel lambda,
   once per function, for a set that only the type converter
   distinguishes. Whatever is done about the pass, that rebuild is a
   computed-once fact being recomputed.
2. **Context-lock contention under parallel passes** is roughly a
   fifth of the reduced dialect corpus (mutex slow paths and the
   diagnostic handler's per-thread order map). This is CPU burned
   queueing, and it grows with thread count, so the two-core budget
   understates it relative to a wide machine.
3. **In small whole-program compiles the backend dominates**:
   `toObjects` 34 % by total, LLVM pass managers and the inliner the
   bulk of its leaves. Nothing upstream of lowering competes except
   pass-manager overhead itself (`PassManager::run` 16.6 % self —
   mostly inlined children; read with the flamegraph).
4. **Optimize and counting are not where suite CPU goes**:
   `Optimize` ≈ 3 % self, Grades ≈ 3 % combined in corpus C, and in
   the reduced corpus A no counting function reaches the top 25. The
   standing suspicion (Canon re-walks, verifier walks) is not what
   these corpora burn on; `OperationVerifier::verifyOpAndDominance`
   is 1.6–1.7 % self in both.
5. **Process startup is a visible per-invocation tax** across ~1 900
   sampled compiler launches: `_dyld_start` 1.2–2.2 % self. It
   bounds how much any per-compile improvement can move suite wall
   time, and it argues for measuring stage-sized modules (below)
   before optimizing for the suite's shape.
6. **The frontend is the program suite's wall clock**: 63 % of all
   samples are the driver in `wait4` for its Chez child. Any
   compile-time work aimed at suite wall time that ignores process
   count and frontend time is optimizing the smaller term.

## Not measured yet

- The benchmark suite's compiles (`bench/run.sh`, 30 programs) —
  corpus B was not run; the sampler and swap procedure above apply
  unchanged.
- A stage-sized module (the 71 MB stage-1 frontend module in
  `build/self/stage1`): the corpora here are thousands of small
  compiles, whose ranking (startup, backend, pattern-set rebuilds)
  is known to invert at scale. This is the missing measurement, and
  the one the self-host proposal's traced run would give.
- Inline-aware attribution (Instruments/`xctrace` Time Profiler
  expands inlines from DWARF) on one large workload, to split the
  pass-manager and conversion "self" buckets into the inlined
  helpers actually burning cycles.
- Corpus C rerun after the `Positions` fix, to replace its
  approximate lower ranks.

## Reproducing

Raw sample files, folded stacks, RSS series and the flamegraphs
(`test-idr.svg` 673 331 samples, `test.svg` 390 288 samples) were
kept out of git per the owner's rule and lived under `/tmp/flame` on
the measuring machine. The three throwaway scripts are small and
rebuildable from the method above: a runner that holds two
`sample -wait` waiters per binary name plus one pid-polling tail
slot around a workload command; a collapser that parses `sample`'s
call-graph text into an op tree per thread (depth from the count's
column), emits folded stacks from subtree self counts, buckets
wait-leaf stacks as blocked, and ranks by self and total; and a
folder-to-SVG renderer. The one non-obvious step is the profile
build and the `build/dev` swap; both are described under Method.
