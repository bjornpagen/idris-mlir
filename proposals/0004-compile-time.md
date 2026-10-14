# 0004: compile time: one fast serial pipeline

**Status:** current as of 2026-10-14 18:10 CDT. This file states
where compile time stands and the one refactor that remains; it
overwrites the earlier drafts and their decisions, which git
history holds. F0 (the measurement) is done and recorded in §2
and in `bench/profiles/2026-10-14-f0-stage0.md`. The first round
of fixes landed 2026-10-13/14 (§2). The owner approved the
proposals 2026-10-14 ("all approved. go forth."); licensing
(0001) is built and pushed, and F3's first serial form was built
and gated (§2.2). **That built form is now pinned as a problem
for re-evaluation (§2.3, the live status other agents should
read first): it landed as an opt-in second code path, which the
owner has called out as exactly the fallback/configuration slop
this compiler does not carry. The corpus verdict run was killed
by the owner at 18:10 without a verdict.** Two smaller
refactors were built, measured and reverted (§2.1). The gate is
self-hosting (0002 §2 step 5). Claims are marked: *read* (the
path), *measured* (the record), *conjecture*, *decision*.

**Sources.** The pinned MLIR tree (`.toolchain/llvm-project/mlir`);
the Mojo compiler in the owner's clone at `~/Documents/modular`
(4b0d20f); this repository's code and records; the investigation of
2026-10-14 (Mojo, MLIR upstream, our casework and serial dataflow,
read lane by lane; the InlineCleanup evidence is
`sources/`-cited in §2.1 from the research report of the same day).

## 1. The thesis

**Sharding divides T1; this proposal cuts it.** 0006 bounds sharded
time by T1/P + T-infinity and demands one shard be no slower than the
serial pipeline. Measured on the stage-0 self module, the serial
pipeline's cost is not the passes' necessary work; it is repetitions
of it: whole-module rounds that do not decay, per-iteration cleanup
on bodies that grow, analyses rebuilt per round, serial dataflow per
round (§2). The cure is a representation change, not tuning: **one
bottom-up pass over the call graph's SCCs, in which every decision
(inline, specialize, propagate) is taken once, against callees
already final, and every body is canonicalized a bounded number of
times.** That is the shape Mojo's pipeline proves out (§3) and the
serial rehearsal of 0006's phase-3 unit.

What is deleted, by name, with no compatibility owed: the Simplify
round structure and its composite fixed point; module fingerprints as
change detection; seed marks in discardable attributes and the walks
and sweeps that maintain them; per-round analysis rebuilds; the
per-iteration post-inline cleanup; unbounded inlining growth with no
size accounting. What never changes: every whole-program guarantee
fact (0006 §1), byte-identical output at any thread count, the
verifier after every pass, refusals as `unsupported`.

## 2. Where the time goes (F0, measured 2026-10-14)

The full record is `bench/profiles/2026-10-14-f0-stage0.md`; the
load-bearing numbers:

- The frontend is not the wall: 58,236 functions, ~300 MB, ~140 s.
  The prefix is not: parse 11.7 s, isolate 3.0, deduplicate 3.8,
  contify 3.5 (27.0 s total, 1.09 GB).
- Round 1 of Simplify: 447 s wall. IdrInline 330 s; one
  InlineCleanup instance 211 s, effectively serial (§2.1). SCCP
  43 s serial. Analyses rebuilt inside the round ~25 user-seconds
  (CallGraph 11.9, References twice, InlineDecisions, BindingTimes,
  RoundFacts). The per-function step is healthy (77 user-s in 10 s
  wall); IntRange nested is 48/6.
- Sixteen rounds do not reach a fixpoint: 99-142 s each, no decay,
  the module still changing at round 16. Operations grow ~471k ->
  ~1.25M while functions fall 100,198 -> 28,276: inlining
  concentrates the program into monsters
  (`IdrisMLIR.MLIR.statementText.spec1` ~152k ops, 14% of the module
  in one function; `Idris.ProcessIdr.processMod.lam4` ~76k). Peak
  RSS ~5.8 GB. Simplify alone is >2,000 s and unfinished.
- The SCC structure the cure needs exists: largest direct-call SCC
  174 at emission, 24 after six rounds of inlining; 93% singletons.
  Namespace locality is 17% same-module: namespaces group, SCCs work.
- RemoveDeadValues once: 65 s (liveness 51 s), 7.65 GB. The tail
  cannot start until Simplify converges: after 16 rounds
  defunctionalize still refuses an unresolved runtime closure.
- The first round of fixes (landed, each output-identical where it
  claims): the match-field symbol scan deleted (one canonicalizer
  sweep 65.1 -> 19.1 user-s); `idr-deduplicate` (7,505 of 107,732
  functions in ~1 s); scoped post-inline canonicalization (70,252
  whole-body runs deleted); IntRange nested (30 -> 3 s of wall per
  round); defunctionalize labels in one walk; RemoveDeadValues once
  at the fixpoint. One explicit round fell 1,321 -> 385 s (dev
  build); the suite record 248.8 -> 167.9 s over 429 compilations.
  Stage 1 still never finished: the round count is what remains.

## 2.1 Ground zero: the post-inline cleanup, and what did not work

`InlineCleanup` (`foreign/idr/lib/Transforms/Inline/Inline.cpp`) is
the component pipeline upstream's inliner runs on a function an
iteration inlined into: seeded canonicalization patterns, then
`simplifyRegions(..., mergeBlocks=false)` — a whole-body liveness
fixpoint (`mlir/lib/Transforms/Utils/RegionUtils.cpp`, `runRegionDCE`),
and an unconditional whole-body `eraseUnreachableBlocks` before the
patterns. Upstream's inliner optimizes an SCC before every inline
attempt until one inlines nothing
(`mlir/lib/Transforms/Utils/Inliner.cpp:471-490`), our iteration
bound is unlimited because a do block needs it, and its only
parallelism is across one SCC's nodes (`Inliner.cpp:527-567`) over
93%-singleton SCCs: the wall~user signature of the 211 s.

Two refactors were implemented, measured and **reverted** on
2026-10-14; both stay reverted until new evidence answers their
numbers:

- **Strict worklist confinement**
  (`GreedyRewriteStrictness::ExistingAndNewOps`): a do block took 19
  rounds against 3, and the corpus produced a linearity-invalid
  intermediate state. The apply a returned closure feeds sits more
  than one hop from any seed, through continuation block arguments.
  Recorded in the code at the config it rejected.
- **Deferring the structural half** (delete `simplifyRegions` from
  the hot cleanup; run it once per touched function after inlining,
  in parallel): 7% *slower* old-against-new under identical
  conditions on the round-6 module (462 s against 494 s; IdrInline
  user time 108 s -> 139 s; outputs same size, 18 lines of op order
  apart). Iterations carry the dead structure and the greedy work
  grows by more than the deferred fixpoints save.

The finding both leave: the dominant cost is the greedy pattern work
itself, spread from the seeds over enormous bodies, **repeated per
inlining iteration**. Mojo never pays it: their canonicalizer is
whole-function with region simplification disabled and no structural
pass (`Mojo/lib/Transforms/Canonicalizer.cpp:496-523`), and their
inliner runs a twelve-pass inner pipeline *once per function*, after
its callees are final, over a fork-join ready set
(`Mojo/lib/Transforms/AutomaticInline.cpp:380-410,439-491`;
`Mojo/lib/Compiler/Pipeline/Pipeline.cpp:206-231`). Semi-naive
evaluation joins deltas and never re-derives totals
(`sources/notes/sharded-compilation/deterministic-fixpoints.md`); our
cleanup is the delta step with the total re-derived around it, per
iteration, inside rounds that repeat it again.

## 2.2 F3 as built; the verdict run, killed without a verdict (2026-10-14)

**Built and pushed** (552d682a): `idr-simplify` gained an opt-in
`scc-pipeline` option (default off; the rounds stay the default).
Under it, `idr::runSimplifySCCPipeline`
(`foreign/idr/lib/Transforms/Simplify/Scc.cpp`) runs a pre part
once (effects, SCCP, loop breakers, RoundFacts, the per-function
step of identity/canonicalize/CSE/redirect), then a delta
(inline, specialize, RoundFacts, the per-function step) until one
delta changes nothing — termination by the module's structural
fingerprint, not by clone count, because a delta that makes no
clone can still expose inlining (*measured*: clone-count
termination left `@done` uninlined on do-block) — then a post
part once (SCCP, RoundFacts, the per-function step, IntRange,
SymbolDCE), then the existing RemoveDeadValues removal, resuming
the pipeline when a removal changed the module. `max-rounds`
bounds deltas; the instrumentation's round count counts deltas,
so remarks and the budget error read the same under either loop.
This is deliberately **not yet §4's full design**: there is no
ready-set engine, no size-budgeted inline decisions, no bottom-up
SCCP summaries, and no parallelism; the inliner's own bottom-up
SCC order plus counted deltas are the serial rehearsal whose only
question is whether deleting the round multiplier converges at
self scale. F2 has no separate commit: the investigation found
true analysis preservation mostly impossible under mutating
nested steps, so its recomputation cost is attacked by running
the facts once per part instead of once per round, here.

**Split for the file-size gate** (committed with §2.3's pin; the
split is pure movement and survives either re-evaluation
answer): the F3 addition took
`Simplify.cpp` to 463 lines against `tests/spec/file-size`'s 400.
The SCC driver loop moved into Scc.cpp beside its pipelines and
the census/remark reporting into `Simplify/Trace.cpp`, leaving
`Simplify.cpp` at 383 lines holding the loop and its
instrumentation. Pure movement: output byte-identical before and
after (*measured*, do-block, both pipelines).

**Gates on this tree** (*measured* 2026-10-14, arm64 macOS,
`NCPU=6` — half the 12 CPUs, the owner's standing override; tool
defaults stay maximalist per 7a27fd34): `make build` clean,
`make check` 27/27, `make test-idr` 286/286, `make test` 415/415.
On `tests/idr/pipeline/do-block.mlir` the SCC pipeline reaches
its fixpoint in 3 deltas with output byte-identical to the rounds
(*measured*, `cmp` clean, remark `fixpoint: round 3 changed
nothing`), and that test now runs `scc-pipeline=true` and diffs
against the rounds output as maintained coverage (2/2 under
`make test-idr only=idr/pipeline/do-block`). x86_64 Linux is
still NotRun (0002 §3).

**The verdict run, killed.** Started 2026-10-14 17:03 CDT on
the owner's machine; sampled inside `idr::runSimplifySCCPipeline`
at 36 and 86 CPU-minutes, ~1 GB RSS, output files empty (the
tool writes only at exit); **killed by the owner at 18:10 CDT
after ~66 wall-minutes and at least 90 observed CPU-minutes,
with no output and no verdict** — the owner's judgement being
that it was not ending soon enough to be the way this gets
decided. The exact command was (`/tmp/f3-corpus-verdict.sh`):

```
/usr/bin/time -l nice -n 10 taskpolicy -b \
  build/dev/foreign/idr/idris-mlir-opt /tmp/f0/post-contify.mlir \
  '--pass-pipeline=builtin.module(idr-simplify{scc-pipeline=true})' \
  -mlir-timing --mlir-pass-statistics \
  -o /tmp/f0/scc-out.mlir --remarks-filter-passed=idr-simplify
```

Input is the post-contify stage-0 module (158 MB; the raw
emission is `/tmp/idris-mlir-stage0.mlir`, and `/tmp/f0/round1`
to `round16.mlir` are the manual round trajectory §2 cites). The
throttling is deliberate (the opt tool has no thread cap, so
background QoS is how the half-CPU policy is honored), which
means **wall time from this run is not directly comparable** to
§2's unthrottled round walls; total CPU time, the delta count,
and whether it reaches a fixpoint at all are the comparable
facts. For scale: §2's 16 unthrottled rounds cost roughly
34 wall-minutes without converging, and the killed run passed
90 (efficiency-core) CPU-minutes without terminating, so
nothing shows the SCC pipeline faster — only that it was
progressing. An earlier throttled attempt the same day was
cancelled at 21 CPU-minutes still inside its first delta's
inlining. There is no verdict, and §2.3 pins what gets
re-evaluated before anyone reruns this.

## 2.3 Pinned problem: the optional path itself (owner, 2026-10-14)

**The problem, in the owner's terms:** F3 landed as an *opt-in*
— a behavior-selecting pass option, default off, with the old
rounds kept as the fallback. This compiler is free of
fallbacks and configuration: one thing, one representation, one
behavior (AGENTS.md; §1's deletion list). Two code paths for one
pass means every future change pays twice, every test proves
half, and the unexercised path rots while looking supported.
**This state is pinned for re-evaluation and no further work
builds on the option until it is resolved** — in particular, do
not rerun the corpus "to decide the flip"; the flip framing is
what is being re-evaluated.

How it got here, for the record: §6's landing rule (measure or
revert) was read as needing both pipelines in one binary to A/B
them; the A/B scaffolding was then checkpoint-committed to
`main` (552d682a, "corpus verdict pending") instead of staying a
local probe; the verdict run stalled, and the scaffolding froze
into the tree, acquiring a maintained test *for the flag* and
proposal prose describing "opt-in" as a steady state. None of
that was necessary: §2.1's experiments the same day were A/B'd
old-binary against new-binary under identical conditions, which
needs no option in the tree at all.

**The pointless casework this one option created** (every item
exists only to keep two behaviors alive; §3's inventory is the
older list this extends):

- The option itself (`Passes.td` `scc-pipeline`, default
  `false`), the `if (sccPipeline)` branch in
  `Simplify::runOnOperation`, and three extra `OpPassManager`
  members (`pre`/`delta`/`post`) beside `loop`/`removal`,
  copied in the pass's copy constructor and built in
  `initialize`/`getDependentDialects` whether or not they run.
- Naming lies to keep both loops' reporting identical: deltas
  increment the instrumentation's *round* count, so the remark
  says "fixpoint: round 3" for three deltas; `max-rounds`
  silently bounds deltas instead; the `rounds` statistic counts
  whichever loop ran. One counter, two meanings.
- Asymmetric observability: the instrumentation's per-round
  census/timing traces key on the composite's pipelines, so the
  rounds are traced and the deltas are not — the killed run
  could not even report how many deltas it had completed.
  Ninety CPU-minutes bought no progress signal.
- Test and doc casework: do-block RUN lines whose only purpose
  is diffing the two paths against each other; proposal and
  commit prose maintaining "pending" as a status; a budget test
  (`tests/idr/obs/budget.mlir`) whose semantics name rounds the
  other path does not have.
- Casework the SCC path *kept* despite §1 promising its
  deletion: a whole-module fingerprint taken around every delta
  and every removal as change detection; RoundFacts recomputed
  per delta; SCCP run twice (pre and post); the serial
  RemoveDeadValues resume loop unchanged. Deleting the round
  multiplier while keeping its change-detection and resumption
  machinery is half the refactor wearing the whole one's name.

**To re-evaluate (owner decision, then work):**

1. **One path, decided.** Either the SCC pipeline becomes
   `idr-simplify` — option, rounds, composite, `Round.cpp` and
   the round-shaped reporting deleted in the same change — or
   F3 is reverted whole and §4 is re-attacked. No third state,
   and no default-flip intermediate: a default is just an
   option with better PR.
2. **Measurement without options.** A/B by binary: two commits,
   two builds, identical conditions (the §2.1 method). A
   behavior-selecting pass option is not a measurement
   instrument and does not land on `main` again. (For scale:
   the tree today has five pass options total — `max-rounds` the
   budget, `scc-pipeline`, RC's `reuse`/`sink` toggles, and
   demand's `in-place`, whose opt-in status is itself an open
   owner decision in 0002 §3; `idr-expect`'s `holds` is a test
   API, a different thing. The re-evaluation says which of
   these survive as budgets/test APIs and which are the same
   slop in older clothes.)
3. **What either answer owes before it is called done:** the
   full suite run against the one remaining behavior (today's
   green suite proves the rounds; the SCC path has run exactly
   one lit test), determinism at 1/2/8 threads, and a bounded,
   observable corpus measurement — per-delta census remarks
   first, so a run reports progress instead of silence; a
   time-boxed identical-conditions A/B from a named starting
   module (e.g. `/tmp/f0/round16.mlir`) rather than an open-ended
   wait for a fixpoint. §6's thresholds still decide keep/revert;
   they just no longer license keeping both.

## 3. The casework, inventoried

Each mechanism exists only because cleanup runs per iteration inside
rounds. The refactor deletes the left column by changing the
representation on the right:

| Casework today | Representation that deletes it |
| --- | --- |
| Seed marks in a discardable attribute (`idr.inlined`), a pre-walk to find them, a module sweep to remove leftovers | Cleanup runs once per callable, when its callees are final: no marks, because "what changed" is the callable itself |
| Whole-module SHA1 fingerprints (Simplify loop, inliner cycle guard, composite) | Change as a returned flag from the one pass that knows; an emptying worklist is the fixed point |
| 64-round composite fixed point + RDV-resume loop | One bottom-up SCC pass; specialization requests return as content-keyed deltas against finished SCCs, counted |
| RoundFacts and module analyses rebuilt per round (nest discards them) | Preserved MLIR analyses, invalidated by the pass manager; later, 0006's summaries |
| Serial SCCP and SymbolDCE per round | Constants and reachability as bottom-up facts computed once; the passes that consume them stay per function |
| Unconditional unreachable sweeps before patterns | Patterns never see a body mid-inline: the callable is final-form when cleaned |
| Unbounded inlining growth (ops x2.6, one function at 152k ops) | Inline decisions as facts with a size budget, decided once per SCC (Mojo's heuristic shape), so growth is accounted, not emergent |
| `maxIterations=0` inlining iterations with fingerprint cycle-breaking | The bottom-up order itself: a chain unfolds in one pass because each callee is final before its caller is read |

What looks like casework but is semantics, and stays: unlimited
*exposure* of the next call in a do block (the bottom-up order
provides it by construction instead of by iteration), the linearity
verifier's rejection of invalid intermediate states (final-form
callables are always valid), and every `unsupported` refusal.

## 4. The refactor

One representation-first change in measured stages. §6's landing
rule governs every stage; a stage that misses its threshold is
reverted, as both attempts in §2.1 were.

**F2 — Analyses stay alive.** (No separate stage landed: the
2026-10-14 investigation found true preservation mostly
impossible under mutating nested steps, so F3's built form
attacks the same cost by computing the facts once per pipeline
part instead of once per round, §2.2. This stage revives only if
the post-F3 record still names rebuilds.) RoundFacts, the call
graph and the symbol tables become preserved analyses across the
nest (`markAnalysesPreserved` where true today by construction;
upstream's analysis manager already invalidates on change).
Delete the discard that forces rebuilds. Lands when at least
half the measured per-round rebuild (~25 user-s in round 1) is
gone at identical bytes.

**F3 — The SCC pipeline (the refactor).** (First serial form
built opt-in, corpus run killed without a verdict, and the
opt-in state itself pinned as a problem for re-evaluation,
§2.2–§2.3; what follows is the full design it rehearses.)
Delete `idr-simplify`'s
round structure. In its place, one module pass built as a ready-set
engine over the SCC DAG, specified once so serial and parallel
execution are two schedulers over the same work: a unit (one SCC)
is ready when its callees are final; serial drains the ready set in
canonical sorted order, parallel drains it with the pool and merges
in the same order — determinism by construction (scan labeling,
canonical SCC pivots;
`sources/notes/sharded-compilation/deterministic-fixpoints.md` §3,
§5, §9), tasks carrying ids and fact slices, never bodies
(Blumofe–Leiserson's bound, there §2). Weakly-connected components
are not the unit (one holds 99.7% of the stage-0 module, *measured*
2026-10-14) and neither are namespaces (17% locality, §2). Facts a
unit consumes are monotone sets read frozen, in hash-consed/sorted
representations — MLton's sub-2-second 0CFA is a representation
result first (`whole-program-at-scale.md` §3), and our 54 s label
walk says ours are not there yet. The pass:

1. computes the call graph once and its SCCs in bottom-up order
   (upstream `CallGraph` + `llvm::scc_iterator`, the traversal the
   inliner itself uses, `Inliner.cpp`'s `CGSCC` machinery read in the
   investigation);
2. per ready SCC, runs upstream's inliner with our decisions as its
   analysis input — decisions carrying a size budget, so growth is
   accounted per SCC and a 152k-op monster is refused at decision
   time, not discovered in a trace — then the bounded inner
   per-function pipeline (identity, canonicalize with the one config
   in `Canonicalize.h`, CSE, redirect, int-range) **once per
   callable**: Mojo's ready-set shape
   (`AutomaticInline.cpp:439-491`), ported outright under 0001's
   protocol where its structure beats upstream's inliner driver for
   this, upstream's where it does not, decided file by file in the
   stage record, never by taste. A callable is processed when its
   callees are final, so the do-block chain unfolds in the order
   itself;
3. takes specialization requests as content-keyed deltas (GCC's
   virtual clones, `whole-program-at-scale.md` §2): a request
   against a finished SCC re-queues exactly the affected SCCs,
   counted, each request decided once (0006 §3.5's virtual clones in
   serial form);
4. runs SCCP's interprocedural half as bottom-up constant summaries
   during the same pass (callee summaries first; the measured reason
   SCCP cannot nest per function is exactly these constants), and
   SymbolDCE + RemoveDeadValues once at the end.

With it go: the seed marks and every walk/sweep that maintains them,
`InlineCleanup` as a per-iteration pass (the inner pipeline is a
plain function pipeline again), the fingerprints, `max-rounds`, the
RDV-resume loop. Lands when the Simplify segment on the stage-0
corpus beats 600 s wall to the fixpoint the rounds reach (against
>2,000 s unfinished), corpus and suite byte-identical, determinism
1/2/8.

**F4 — The handoff in bytecode.** The frontend writes MLIR bytecode;
the driver reads it (`readBytecodeFile`); text stays a dump option.
Kills the ~12 s parse and the print side, and every text round-trip
in the corpus tooling. Lands on identical bytes everywhere.

**F5 — The named remainder.** Whatever F0-after-F3 names next, in
its order: today that list is the giant-function tail (a 152k-op
function bounds any per-function work; if it still dominates, an
outline splitting pass is designed then, from its trace), the
frontend's 140 s and 9.1 GB (0008's ground), and the LLVM tail once
it can run (0006 S2 measures it).

## 5. What this is not

Not separate compilation, not softened budgets, not threads as the
answer (parallelism divides what this cuts), not verifiers off, not
a second representation of any fact. Sharding (0006) consumes this
design unchanged: F3's SCC unit *is* 0006's phase-3 unit, its
summaries are 0006's, and nothing here is redone there.

## 6. The landing rule

Every stage lands with its measurement or not at all: the corpus
byte-identical (or the change in output named and intended), the
segment it claims faster by its threshold, no bench program's
compile regressing beyond 5% or its runtime beyond 2%, the suite
green, determinism 1/2/8. A cheaper round that needs more rounds
has bought nothing (§2.1, with the 19-round data point behind it).
