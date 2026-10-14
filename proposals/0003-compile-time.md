# 0003: compile time: one fast serial pipeline

**Status:** proposed 2026-10-13, inserted before sharding (0004, 0005)
by the owner on the day stage 1 of `make self` first translated the whole
frontend and then spent hours in IdrSimplify; updated 2026-10-14 at
b4713f66. F1 has partly landed (the record is §2): duplicate-function
elimination, the deletable symbol scans, scoped inline
canonicalization, IntRange nested, RemoveDeadValues once at the
fixpoint and region simplification off are built and measured. F0 (the
finished record), F2, F3, F4 and F5 are not. Its gate is self-hosting
(0001 §2 step 5: stages 2 and 3 byte-identical); F0 is 0005's S0, done
here because the numbers decide this proposal's thresholds, and it
runs on the stage-0 corpus that already exists — no finished stage 1
is needed for it. Stages are sized in AI hours: one stage is one
session's work, landed and measured before the next starts. This is a
cutover, not a tuning programme: every legacy mechanism §4 replaces
(the rounds, the fingerprints, the text handoff, per-round rebuilds)
is deleted in the stage that replaces it, with no compatibility owed.

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

**Sharding divides T1; this proposal cuts it.** 0005 §8 bounds sharded
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

## 2. Where the time goes, and what the first round took out

*Measured* (2026-10-13 to 2026-10-14, arm64 macOS, this machine; the
per-fix numbers are in the commits named):

- **The first F1 round is landed.** One explicit Simplify round on the
  stage-0 module: 1,321 s before, 385 s after (dev build). Its parts:
  reading a match field no longer scans 58k top-level symbols per
  field (0768bc9f; one canonicalizer sweep 65.1 → 19.1 user-s, output
  identical), and the inliner no longer fingerprints the module to
  notice its own work; `idr-deduplicate` erases 7,505 of 107,732
  post-isolate functions in ~1 s (234b81a0); two further scans deleted
  (4d207761); the inliner canonicalizes only the ops an iteration
  inserted instead of whole bodies — 70,252 whole-body runs over
  11.7M ops, the root alone 256 times, are gone (5088d7a8, which
  supersedes 0a8bf039's iteration bound); IntRange nested per
  function, 30 s → 3 s of wall per round with no check count changed
  (5d3318fb; SCCP measured and kept on the module); defunctionalize's
  labels in one walk, 66.6 → 54.0 s for that step (6a7841dc);
  RemoveDeadValues once at the fixpoint instead of per round
  (3b166aa3; ~40 s of the 385 s round was its serial analysis);
  region simplification disabled at every canonicalizer we build
  (`foreign/idr/include/idr/Transforms/Canonicalize.h`), landed by the
  owner's direction after its lane measured it round-neutral — F0's
  record re-prices it. The suite's compile-time record over 429
  compilations went 248.8 s → 167.9 s with nothing regressing, and
  the full gate is green (index, "Where the work stands").
- **What stands.** Stage 1 has still never finished: a 4 h 23 min
  attempt on the pre-round compiler and a restarted attempt after it
  were both stopped inside Simplify rounds. The multiplier that
  remains is the round structure itself — the subject of F3.
- **The SCC structure F3 needs exists.** Over the corpus's 146,824
  direct `idr.call` edges between 58,235 functions: 55,340 SCCs, 93%
  singletons, largest 174 (the TTImp elaborator), 1,219 functions in
  any SCC over 10 (*measured* 2026-10-14). Closure applies are not in
  that graph and inlining rewrites it, so F0 re-measures after
  inlining; as a lower bound on coupling it already answers §9's
  question unless inlining changes it qualitatively.

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

*Read* (this repository, at b4713f66): the round is the passes of
`Round.cpp` under a 64-round budget (`Passes.td` max-rounds), and the
loop still proves quiescence by fingerprinting the module
(`Simplify.cpp`, `OperationFingerPrint` before and after; the
inliner's cycle guard keeps one per cycle, `Inline.cpp`). The round's
nest still discards module analyses, so RoundFacts recomputes its
tables per round. Of the static symbol scans, the deletable ones are
deleted (above); what remains reads facts only a declaration holds —
`constructorOf`'s static call (`lib/IR/Symbols.cpp`) and `ApplyOp`'s
signature read (`lib/IR/OpsClosures.cpp`, the static
`SymbolTable::lookupNearestSymbolFrom`), F3's to serve by analysis.
The driver still parses the frontend's ~300 MB as text
(`lib/Driver/Run.cpp`, `parseSourceFile<ModuleOp>`): F4's.

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
  identical bodies after erasure; `idr-deduplicate` merges them since
  234b81a0 (§2).
- **Bytecode and content keys.** KGEN reads and writes MLIR bytecode
  (`KGENCompiler.cpp`, `Support/Compiler/BytecodeReaderWriter.h`), and
  `Cache/lib/CachedTransform.cpp` keys a transform's result by the
  bytecode of its input (locations stripped, so keys are relocatable)
  plus pipeline identity. In-process, that is a per-function memo of
  exactly the shape our per-function pipelines could use before 0005's
  persisted cache (its S9) exists.
- **Nested everything.** The pipeline files are walls of
  `addNestedPass<FuncOp>`; module passes are the exception (symbol and
  calling-convention changes), which is why their pool is not parked.

What does not transfer: separate compilation and `.mojoc` packages
(they stay unelaborated; our guarantees are whole-program by AGENTS.md —
that is 0005's design problem, already decided there); running with
verifiers off in production (our linearity verifier after every pass is
a rule, and its cost is to be measured and shrunk, not waived); their
fork-join runtime inside the compiler (our C++ side uses LLVM's pool,
0005 §9); and Bazel (our build is `make` and one recipe per AGENTS.md).

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
across compiles here; that is 0005 S9, which inherits the key design.

## 5. Staged plan, each stage with its proof

Sizes are AI hours (one working session each, including measurement);
they are ordering aids, not commitments. Every stage keeps D1.

| Stage | Content | Proof | Size |
| --- | --- | --- | --- |
| F0 | The record, on the existing stage-0 corpus (no finished stage 1 needed): one full Simplify fixpoint traced (`-mlir-timing`, time trace), round counts, per-pass global-vs-local wall, verifier and fingerprint shares, RSS, largest SCC after inlining, LLVM optimize/emit share; compile-times record refreshed; §6 thresholds fixed (this is 0005's S0 and 0001's G0, one record) | committed record under `bench/profiles/` and in HANDOFF.md | 1 h |
| F1 | **Partly landed 2026-10-13/14 (§2).** Remains: module fingerprints deleted from Simplify (changed flags instead; the inliner's cycle guard keeps its one per cycle, measured ~1% and kept); the two remaining static symbol scans served by analysis (with F3, where their callers live) | corpus byte-identical; stage-0 timing; determinism 1/2/8 | within F2/F3 |
| F2 | Analyses stay alive: RoundFacts as preserved analyses with explicit invalidation; the round nest no longer discards module analyses; symbol table built once per pipeline run and invalidated only by symbol-changing passes | analysis results differential-equal to recomputation on the corpus (assert pass in the determinism suite); stage-0 timing | 2 h |
| F3 | The SCC pipeline replaces the fixed-point rounds (§4 items 3-4): one bottom-up SCC pass owning inline+specialize decisions, bounded inner per-function pipeline, specialization deltas as worklist, dataflow members nested, RemoveDeadValues/SymbolDCE once at the end; `IdrSimplify`'s composite fixed point and the 64-round budget deleted (budgets on instances and requests stay, refusals identical) | corpus byte-identical or every changed byte explained in the stage record; simplify-idempotent property still holds (`tests/lib/properties.sh`); stage-0 Simplify-segment speedup by §6's factor; determinism 1/2/8 | 5-6 h |
| F4 | Bytecode handoff (Emit writes `.mlirbc` through the driver's own writer path or the frontend emits to the C++ side as bytecode directly — decided in-stage by which side already has the writer; dumps stay text) and the in-process per-function transform memo keyed by bytecode-without-locations plus pipeline identity | stage outputs byte-identical; parse+print share of stage-0 wall below F0's; second identical body in one compile demonstrably skipped (statistic in the record) | 3 h |
| F5 | The tail: whatever F0-F4's records say is next (verifier share, Defunctionalize, IdrRc, LLVM share) gets one stage each by the same rules, or is explicitly handed to 0005 with the number that says why | records; the §6 targets met or the remainder named in 0005 | as measured |

0002's stage 1 (the array purge) may land between any two F stages; it
deletes `idr-in-bounds` and its share with it, and no F stage may spend
effort speeding a pass 0002 deletes (F0's record names them).

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
  the tie (0004's rule), and the Pi Zero pays nothing.
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
  the same `unsupported` errors, decided in key order (0005 D5 holds
  already in the serial pipeline).
- **Upstream bugs fixed upstream** (AGENTS.md): if a stage's measurement
  convicts an upstream pass (region simplification's exponential case is
  the standing suspect), the fix is a patch under `upstream/` with its
  report and test, not a workaround here; sidestepping by config (F1)
  is allowed only while the report exists.

## 8. Rejected alternatives

- **Shard first** (0004/0005 before this): Brent's bound (0005 §8) —
  parallelizing a 10×-wasteful T1 buys at most the same 10× at 10 shards
  and keeps the serial terms; and 0005's own S6 (simplify per SCC unit)
  is this proposal's F3, done once here instead of twice.
- **Cached symbol tables in rewrite patterns**: measured — data race and
  use-after-erase under the inliner's workers; patterns are shared and
  stateless by upstream's contract (§2).
- **Verifiers off in production** (Mojo's production posture): the
  linearity verifier after every pass is a project rule, not a knob.
- **Separate compilation / package files** (`.mojoc`): loses the
  whole-program facts; rejected in 0005 §11 already.
- **An array-programming formulation of the MLIR rounds**: greedy
  rewriting and inlining mutate an operation graph; no whole-array form
  of them exists in MLIR or in Mojo (whose answer is the flat pipeline
  above). The array style's compile-time home is the frontend and the
  analyses (0006, 0007, 0011), not the rewrite rounds.
- **Keeping the rounds and tuning their knobs** (fewer rounds, cheaper
  fingerprint): leaves the multiplier structure — every new pass and
  every larger program pays it again. F1 takes the free wins on the way
  to deleting the structure in F3, not instead of it.
- **A persistent compile cache now**: that is 0005 S9 and needs its
  content names (S1); F4 builds the key in-process so S9 inherits a
  measured design instead of inventing one.

## 9. Open questions

- The finished stage-1 numbers (F0): verifier share, fingerprint share,
  Defunctionalize and IdrRc shares at 58k scale — each can reorder F1-F5.
- The largest call-graph SCC of the self-compile after inlining:
  before inlining it is 174 of 58,235 (§2, *measured*), so the
  question is only whether inlining grows a dominant one; F0 answers
  it (0005 §12 asks the same).
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
- D5. This proposal ends where 0005 begins: units, persisted cache and
  split codegen are sharding's, and F5 hands over by number, not by
  absorbing them.
- D6. Upstream MLIR mechanisms first (§1): Mojo is evidence for what
  works and what it costs, never the shape copied. A custom replacement
  for an upstream pass or utility needs a stage record showing upstream
  cannot express the need, and a PINS.md entry; a configuration of an
  upstream mechanism needs neither.
