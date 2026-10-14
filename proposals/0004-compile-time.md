# 0004: compile time: one fast serial pipeline

**Status:** proposed (2026-10-13), inserted before sharding (0005, 0006)
by the owner on the day stage 1 of `make self` first translated the whole
frontend and then spent hours in IdrSimplify. Nothing here is built. Its
gate is self-hosting (0001 §6.1: stages 2 and 3 byte-identical), whose
stage-1 run is its baseline measurement (F0 is 0006's S0, done here because
the numbers decide this proposal's thresholds). It follows 0003's stage 1
in the queue only where a stage says so; F1 needs nothing but the gate.
Stages are sized in AI hours: one stage is one session's work, landed and
measured before the next starts.

**Sources.** The pinned MLIR tree (`.toolchain/llvm-project/mlir`); the
Mojo compiler, read in the owner's clone at `~/Documents/modular`
(4b0d20f, Mojo 1.2.0.dev2026101305): `Mojo/lib/Compiler/Pipeline/Pipeline.cpp`,
`Mojo/lib/Transforms/{Canonicalizer,AutomaticInline,EliminateDuplicateFunctions}.cpp`,
`Mojo/lib/Compiler/ObjectCompiler/KGENToLLVMPipeline.cpp`,
`Mojo/lib/Compiler/KGENCompiler.cpp`, `Cache/lib/CachedTransform.cpp`;
this repository's records: `bench/profiles/` time traces, `tests/compile-times.sh`'s
record, `bench/runs/2026-10-13-9a1b7b1-darwin-arm64/`, and process samples
of the stage-1 run (2026-10-13, in the session that wrote this).

**Claims** are marked: *read*, *measured*, *recalled*, *conjecture*, *decision*.

## 1. The thesis

**Sharding divides T1; this proposal cuts it.** 0006 §8 bounds sharded
time by T1/P + T∞ and already demands one shard be no slower than today's
serial pipeline. Today that serial pipeline's cost on a large program is
not the passes' necessary work; it is a multiplier stack of our own
making, applied to upstream's per-operation costs:

- a whole-module fixed point (IdrSimplify: up to 64 rounds of 13 passes,
  each round visiting every function, `foreign/idr/lib/Transforms/Simplify/Round.cpp`);
- inside it, an inliner that iterates to quiescence, re-canonicalizing
  callables per iteration, and upstream's greedy driver at its defaults
  (aggressive region simplification, 10 full-reseed iterations);
- serial module passes (SCCP, IntRange, RemoveDeadValues, SymbolDCE)
  re-run per round while the thread pool parks;
- change detection by SHA1 fingerprint of the whole module per round and
  per inline cycle (`OperationFingerPrint`);
- analyses (RoundFacts: symbol table, holds, identities, clone table,
  binding times) rebuilt from scratch every round;
- uncached symbol lookups, each a linear scan of the module's top level,
  in canonicalization and verification paths (`lib/IR/Symbols.cpp`).

Mojo's KGEN is the existence proof of the other shape (*read*, sources
above): a flat pass list with no whole-module rounds; nearly every pass
nested per function (`addNestedPass<FuncOp>`), hence parallel; one custom
SCC inliner whose decisions are taken once, bottom-up, with a small fixed
inner per-function pipeline; a canonicalizer with region simplification
*disabled* ("the MLIR region simplifier has exponential behaviour",
FIXME(#25742) in their LLVM pipeline, and the same setting in their own
canonicalizer); duplicate functions merged before anything expensive;
bytecode as the handoff format; and whole transforms cached by content
key (bytecode of the input with locations stripped, plus pipeline
identity), so a hit skips the passes entirely.

Mojo is evidence here, not a template (*decision*, D6): where upstream
MLIR has the mechanism — the inliner's own SCC order and async callable
pipelines, `GreedyRewriteConfig`, analyses and their preservation,
bytecode — this proposal uses upstream's, configured, and stays an
in-tree dialect in upstream's conventions (AGENTS.md), because that is
what survives LLVM pins. A Mojo-shaped custom replacement (their own
canonicalizer, their own inliner) is taken only where a stage's record
shows upstream cannot express the need, and then as the smallest
upstream-shaped pass of our own, with the deviation recorded in PINS.md.

The maximal version of this proposal is therefore not knob-tuning. It
deletes the fixed-point round structure and replaces it with that shape,
adapted to the facts only this compiler has: instances and specialization
requests are known up front from the frontend, linearity lives in types
and is verified after every pass, and output bytes are identical at any
thread count. What cannot be deleted is measured and bounded instead.

**The invariant (decision, D1):** every stage lands only if the corpus
(`make test`, `make test-idr`, bench expected outputs) is byte-unchanged
or changes only where the stage's own record says why, determinism holds
at 1/2/8 threads, and the stage's threshold (§6) is met on the stage-0
module. A stage that is not faster by its own measurement is reverted,
not kept for its elegance.

## 2. Where the time goes today

*Measured* (2026-10-13, arm64 macOS, this machine):

- The frontend is not the wall: stage 1 emits 58,236 `idr.func` in a
  308 MB text module (65 MB Core beside it) in about 140 s.
- On the largest finished profile (every-interfaces-export, 15.2 s total
  in `bench/profiles/`): IdrSimplify 9.85 s (64.7%), of which IdrInline
  6.35 s over 5 rounds (first round 5.56 s) and the canonicalizer 4.83 s
  over 7,062 runs; CSE 1.48 s; the whole LLVM backend 3.8%.
- On stage 1 itself: past two hours at the time of writing, 100% of
  samples inside Simplify's composite fixed point, cycling Inline, SCCP,
  IntRange, RemoveDeadValues across rounds; one thread busy in the serial
  members, the pool parked; RSS about 10 GB. No finished total exists
  yet: F0 records it.
- Bench programs compile in 0.8 to 5.4 s (`bench/runs/2026-10-13-9a1b7b1-darwin-arm64/results.md`),
  so the multiplier is invisible at bench scale and total at self scale.
  That gap — superlinear in module size — is the thing to kill, not the
  constant factor.

*Read* (this repository): 23 of the dialect's 28 passes are `ModuleOp`
passes (`foreign/idr/include/idr/Transforms/Passes.td`); the round is 13
passes (`Round.cpp:23-63`) under a 64-round budget (`Passes.td` max-rounds,
with one extra round past budget spent proving quiescence); the round's
nest discards module analyses, so RoundFacts recomputes its five tables
per round; `declarationOf`/`constructorOf` (`lib/IR/Symbols.cpp:49-61`)
and `ApplyOp::canonicalize` (`lib/IR/OpsClosures.cpp`) call the static,
uncached `SymbolTable::lookupNearestSymbolFrom`, a linear scan of 58k
top-level operations per call; the driver parses the frontend's 308 MB
as text (`lib/Driver/Run.cpp`, `parseSourceFile<ModuleOp>`).

*Read* (upstream, pinned tree): parallelism exists only under nested
pass managers and in the inliner's async SCC optimization; SCCP,
RemoveDeadValues and SymbolDCE are op-agnostic module passes, serial by
construction; `GreedyRewriteConfig` defaults to aggressive region
simplification; rewrite patterns are shared across cloned passes and
threads and must not hold mutable caches — a `SymbolTableCollection`
held by a canonicalization pattern is raced on and goes stale as the
inliner erases functions (measured the hard way, 2026-10-13: segfault
in the inliner's workers; reverted, with the reason recorded in
`OpsClosures.cpp`).

## 3. What Mojo does that transfers

*Read* in the clone named in Sources; paths are inside it.

- **No rounds.** `Mojo/lib/Compiler/Pipeline/Pipeline.cpp` builds
  first-opt, then late-opt, each pass once. The inliner's inner pipeline
  repeats a fixed short sequence a fixed number of times; nothing waits
  for a whole-module fingerprint to stop changing.
- **Decisions bottom-up over SCCs, once.** `AutomaticInline.cpp` walks
  call-graph SCCs with `SymbolTableAnalysis` in hand (an analysis, owned
  by the pass — the legal place for a cached table), and inlines by
  level and size decided per SCC, instead of iterating the module until
  nothing inlines anywhere.
- **A hobbled canonicalizer.** Their own `Canonicalizer.cpp` runs
  `GreedySimplifyRegionLevel::Disabled`; the stock canonicalizer in
  their LLVM pipeline gets the same config, with the exponential-behaviour
  FIXME. Region simplification (block merging, dead-region erasure) is
  work our own patterns and SimplifyCF-style passes already do where it
  pays.
- **Duplicates die first.** `EliminateDuplicateFunctions` runs before
  DCE, before inlining: elaboration emits structurally identical
  specializations at scale, and every later pass pays per copy. Our
  frontend emits one instance per key, but distinct keys routinely have
  identical bodies after erasure; nothing merges them today.
- **Bytecode and content keys.** KGEN reads and writes MLIR bytecode
  (`KGENCompiler.cpp`, `Support/Compiler/BytecodeReaderWriter.h`), and
  `Cache/lib/CachedTransform.cpp` keys a transform's result by the
  bytecode of its input (locations stripped, so keys are relocatable)
  plus pipeline identity. In-process, that is a per-function memo of
  exactly the shape our per-function pipelines could use before 0006's
  persisted cache (its S9) exists.
- **Nested everything.** The pipeline files are walls of
  `addNestedPass<FuncOp>`; module passes are the exception (symbol and
  calling-convention changes), which is why their pool is not parked.

What does not transfer: separate compilation and `.mojoc` packages
(they stay unelaborated; our guarantees are whole-program by AGENTS.md —
that is 0006's design problem, already decided there); running with
verifiers off in production (our linearity verifier after every pass is
a rule, and its cost is to be measured and shrunk, not waived); their
fork-join runtime inside the compiler (our C++ side uses LLVM's pool,
0006 §9); and Bazel (our build is `make` and one recipe per AGENTS.md).

## 4. The architecture after this proposal

One pipeline, run once, in pipeline order — the shape §3 evidences,
built from upstream mechanisms first (D6), with our facts kept where
they live today (types, inherent attributes, analyses):

1. Isolate, Contify as today (already cheap at self scale; *measured*
   in F0, else they join the list).
2. Duplicate-function elimination, then dead-symbol elimination: the
   module that enters optimization is the deduplicated one.
3. One SCC pass over the call graph, bottom-up — upstream's inliner
   first (its SCC order, async callable pipelines and iteration control,
   with our decisions in its interface and preparation passes, where
   they already live), a pass of our own only if F3's record shows the
   interface cannot carry a decision we need: per SCC, inline and
   specialize decisions taken once from analyses (sizes, effects, holds —
   the facts RoundFacts computes today, computed once and preserved as
   analyses), with a fixed inner per-function pipeline (our Identity
   patterns, canonicalize with region simplification disabled, CSE,
   Redirect) run a fixed small number of times per callable, in
   parallel. Specialization requests discovered while inlining are
   deltas appended to the SCC worklist, bounded by the same budgets and
   refusals as today, in key order — not a new whole-module round.
4. The dataflow members (SCCP, IntRange) nested per function where
   their semantics are per-function (upstream's are op-agnostic; nesting
   is a pipeline change, proven by differential output), RemoveDeadValues
   and SymbolDCE once each at the end, not per round.
5. Defunctionalize and after, as today, on the smaller module.

Change detection is by the passes' own changed flags and the SCC
worklist emptying; no operation in the pipeline hashes the module.
Symbol lookups go through pass-owned analyses (`SymbolTableAnalysis`
or our own), never through a pattern and never through the static scan:
the two remaining static-scan sites are deleted, and `ApplyOp`'s
signature read is served by making the closure constant carry what
materialization needs or by an analysis the *pass* (not the pattern)
consults — decided in F3 by which keeps one representation (AGENTS.md:
generate the second copy or delete it; a type list duplicated into the
attribute is a second copy, so the analysis is the favourite).

The frontend-to-driver handoff becomes bytecode (text remains the dump
and test format, `--dump-dir` unchanged), and per-function transform
results inside one compile are memoized by content key in-process:
the same body under two keys is simplified once. Nothing is persisted
across compiles here; that is 0006 S9, which inherits the key design.

## 5. Staged plan, each stage with its proof

Sizes are AI hours (one working session each, including measurement);
they are ordering aids, not commitments. Every stage keeps D1.

| Stage | Content | Proof | Size |
| --- | --- | --- | --- |
| F0 | The record: stage 1 finished with `-mlir-timing`, round counts from the simplify remark, per-pass wall and RSS, largest SCC after inlining; `tests/compile-times.sh` record refreshed; thresholds in §6 fixed from these numbers (this is 0006's S0, pulled here) | committed record under `bench/profiles/` and in HANDOFF.md | 1 h after stage 1 lands |
| F1 | The multipliers that need no restructure: canonicalizer region simplification off (or bounded) everywhere we build a canonicalizer; module fingerprints deleted from Simplify and Inline (changed flags instead); the two static symbol scans deleted (analysis-served or restructured callers); duplicate-function elimination after Contify | corpus byte-identical; stage-0 module through Simplify alone (dump-step timing) faster by F0's threshold; determinism 1/2/8 | 2-3 h |
| F2 | Analyses stay alive: RoundFacts as preserved analyses with explicit invalidation; the round nest no longer discards module analyses; symbol table built once per pipeline run and invalidated only by symbol-changing passes | analysis results differential-equal to recomputation on the corpus (assert pass in the determinism suite); stage-0 timing | 2 h |
| F3 | The SCC pipeline replaces the fixed-point rounds (§4 items 3-4): one bottom-up SCC pass owning inline+specialize decisions, bounded inner per-function pipeline, specialization deltas as worklist, dataflow members nested, RemoveDeadValues/SymbolDCE once at the end; `IdrSimplify`'s composite fixed point and the 64-round budget deleted (budgets on instances and requests stay, refusals identical) | corpus byte-identical or every changed byte explained in the stage record; simplify-idempotent property still holds (`tests/lib/properties.sh`); stage-0 Simplify-segment speedup by §6's factor; determinism 1/2/8 | 5-6 h |
| F4 | Bytecode handoff (Emit writes `.mlirbc` through the driver's own writer path or the frontend emits to the C++ side as bytecode directly — decided in-stage by which side already has the writer; dumps stay text) and the in-process per-function transform memo keyed by bytecode-without-locations plus pipeline identity | stage outputs byte-identical; parse+print share of stage-0 wall below F0's; second identical body in one compile demonstrably skipped (statistic in the record) | 3 h |
| F5 | The tail: whatever F0-F4's records say is next (verifier share, Defunctionalize, IdrRc, LLVM share) gets one stage each by the same rules, or is explicitly handed to 0006 with the number that says why | records; the §6 targets met or the remainder named in 0006 | as measured |

0003's stage 1 (the array purge) may land between any two F stages; it
deletes `idr-in-bounds` and its share with it, and no F stage may spend
effort speeding a pass 0003 deletes (F0's record names them).

## 6. Targets and measurement rules

Fixed now as ratios against F0's record, so no target moves after the
measurement exists (*decision*; the absolute numbers land in F0's record):

- Stage-1 pipeline wall (frontend excluded) improves by **at least 10×**
  against F0, at the default thread count, same machine.
- No bench program's compile regresses by more than **5%**, and none of
  their runtimes by more than 2% (bench record rules as today).
- Peak RSS on stage 1 does not grow.
- One thread (`--mlir-disable-threading`) is no slower than today's
  one-thread compile of the same corpus: single-thread performance wins
  the tie (0005's rule), and the Pi Zero pays nothing.
- Every stage's A/B is `tests/compile-times.sh` plus stage-0 dump-step
  timing on the same module bytes F0 recorded; a claim without both is
  *conjecture* and does not land.

## 7. Rules it keeps

- **Determinism**: byte-identical output at 1, 2 and 8 threads
  (`tests/lib/determinism.sh`); no schedule-dependent name, key or
  decision is introduced — SCC order and worklist order are by key.
- **Facts in types, verified after every pass** (AGENTS.md): `!idr.lin<T>`
  and inherent facts unchanged; the verifier stays on after every pass.
  Its cost is shrunk by serving it cached analyses, never by skipping it.
- **One thing, one representation**: no fact is duplicated into a cache
  key, an attribute or a side table that can drift from the IR; content
  keys hash the IR itself and are checked by full equality on a hit.
- **Both targets, one recipe; nothing target-specific** outside the one
  place the target is decided. Nothing here is target work at all.
- **Refusals unchanged**: instance and specialization budgets refuse with
  the same `unsupported` errors, decided in key order (0006 D5 holds
  already in the serial pipeline).
- **Upstream bugs fixed upstream** (AGENTS.md): if a stage's measurement
  convicts an upstream pass (region simplification's exponential case is
  the standing suspect), the fix is a patch under `upstream/` with its
  report and test, not a workaround here; sidestepping by config (F1)
  is allowed only while the report exists.

## 8. Rejected alternatives

- **Shard first** (0005/0006 before this): Brent's bound (0006 §8) —
  parallelizing a 10×-wasteful T1 buys at most the same 10× at 10 shards
  and keeps the serial terms; and 0006's own S6 (simplify per SCC unit)
  is this proposal's F3, done once here instead of twice.
- **Cached symbol tables in rewrite patterns**: measured — data race and
  use-after-erase under the inliner's workers; patterns are shared and
  stateless by upstream's contract (§2).
- **Verifiers off in production** (Mojo's production posture): the
  linearity verifier after every pass is a project rule, not a knob.
- **Separate compilation / package files** (`.mojoc`): loses the
  whole-program facts; rejected in 0006 §11 already.
- **An array-programming formulation of the MLIR rounds**: greedy
  rewriting and inlining mutate an operation graph; no whole-array form
  of them exists in MLIR or in Mojo (whose answer is the flat pipeline
  above). The array style's compile-time home is the frontend and the
  analyses (0007, 0008, 0012), not the rewrite rounds.
- **Keeping the rounds and tuning their knobs** (fewer rounds, cheaper
  fingerprint): leaves the multiplier structure — every new pass and
  every larger program pays it again. F1 takes the free wins on the way
  to deleting the structure in F3, not instead of it.
- **A persistent compile cache now**: that is 0006 S9 and needs its
  content names (S1); F4 builds the key in-process so S9 inherits a
  measured design instead of inventing one.

## 9. Open questions

- The finished stage-1 numbers (F0): verifier share, fingerprint share,
  Defunctionalize and IdrRc shares at 58k scale — each can reorder F1-F5.
- The largest call-graph SCC of the self-compile after inlining: if one
  SCC dominates, F3's per-SCC parallelism starves the same way the
  inliner's does today (0006 §12 asks the same question; F0 answers it).
- Whether Specialize's requests have SCC structure as clean as calls do,
  or whether request deltas can revisit an SCC enough times to re-grow
  rounds inside F3 — bounded by recording delta counts in F3's proof.
- Whether upstream's CompositeFixedPointPass can end rounds on a changed
  flag without fingerprints, or F1 replaces it with our own loop (an
  upstream-shaped change, in-tree, either way).

## 10. Decisions

- D1. The landing rule of §1: measured, byte-identical-or-explained,
  deterministic at 1/2/8 threads, or reverted.
- D2. The baseline corpus is the stage-0 module bytes F0 records, plus
  `tests/compile-times.sh`'s 490 compilations; no other corpus decides
  a stage.
- D3. No whole-module hash, scan or rebuild per round survives F3:
  change is tracked by flags and worklists, symbols by analyses,
  duplicates by content — each checkable by grep in the stage record.
- D4. Speed never buys a second representation of a fact, a skipped
  verifier, or a schedule-dependent output byte.
- D5. This proposal ends where 0006 begins: units, persisted cache and
  split codegen are sharding's, and F5 hands over by number, not by
  absorbing them.
- D6. Upstream MLIR mechanisms first (§1): Mojo is evidence for what
  works and what it costs, never the shape copied. A custom replacement
  for an upstream pass or utility needs a stage record showing upstream
  cannot express the need, and a PINS.md entry; a configuration of an
  upstream mechanism needs neither.
