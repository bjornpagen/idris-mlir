# 0003: compile time: one fast serial pipeline

**Status:** current as of 2026-10-14 at 7a27fd34. This file states
where compile time stands and the one refactor that remains; it
overwrites the earlier drafts and their decisions, which git history
holds. F0 (the measurement) is done and recorded in §2 and in
`bench/profiles/2026-10-14-f0-stage0.md`. The first round of fixes
landed 2026-10-13/14 (§2). The refactor in §4 is designed, not built;
two smaller refactors were built, measured and reverted (§2.1). Its
gate is self-hosting (0001 §2 step 5). Claims are marked: *read* (the
path), *measured* (the record), *conjecture*, *decision*.

**Sources.** The pinned MLIR tree (`.toolchain/llvm-project/mlir`);
the Mojo compiler in the owner's clone at `~/Documents/modular`
(4b0d20f); this repository's code and records; the investigation of
2026-10-14 (Mojo, MLIR upstream, our casework and serial dataflow,
read lane by lane; the InlineCleanup evidence is
`sources/`-cited in §2.1 from the research report of the same day).

## 1. The thesis

**Sharding divides T1; this proposal cuts it.** 0005 bounds sharded
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
serial rehearsal of 0005's phase-3 unit.

What is deleted, by name, with no compatibility owed: the Simplify
round structure and its composite fixed point; module fingerprints as
change detection; seed marks in discardable attributes and the walks
and sweeps that maintain them; per-round analysis rebuilds; the
per-iteration post-inline cleanup; unbounded inlining growth with no
size accounting. What never changes: every whole-program guarantee
fact (0005 §1), byte-identical output at any thread count, the
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

## 3. The casework, inventoried

Each mechanism exists only because cleanup runs per iteration inside
rounds. The refactor deletes the left column by changing the
representation on the right:

| Casework today | Representation that deletes it |
| --- | --- |
| Seed marks in a discardable attribute (`idr.inlined`), a pre-walk to find them, a module sweep to remove leftovers | Cleanup runs once per callable, when its callees are final: no marks, because "what changed" is the callable itself |
| Whole-module SHA1 fingerprints (Simplify loop, inliner cycle guard, composite) | Change as a returned flag from the one pass that knows; an emptying worklist is the fixed point |
| 64-round composite fixed point + RDV-resume loop | One bottom-up SCC pass; specialization requests return as content-keyed deltas against finished SCCs, counted |
| RoundFacts and module analyses rebuilt per round (nest discards them) | Preserved MLIR analyses, invalidated by the pass manager; later, 0005's summaries |
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

**F2 — Analyses stay alive.** RoundFacts, the call graph and the
symbol tables become preserved analyses across the nest
(`markAnalysesPreserved` where true today by construction; upstream's
analysis manager already invalidates on change). Delete the discard
that forces rebuilds. Lands when at least half the measured per-round
rebuild (~25 user-s in round 1) is gone at identical bytes.

**F3 — The SCC pipeline (the refactor).** Delete `idr-simplify`'s
round structure. In its place, one module pass that:

1. computes the call graph once and its SCCs in bottom-up order
   (upstream `CallGraph` + `llvm::scc_iterator`, the traversal the
   inliner itself uses, `Inliner.cpp`'s `CGSCC` machinery read in the
   investigation);
2. per SCC, runs upstream's inliner with our decisions as its
   analysis input, then the bounded inner per-function pipeline
   (identity, canonicalize with the one config in `Canonicalize.h`,
   CSE, redirect, int-range) **once per callable** — Mojo's ready-set
   shape (`AutomaticInline.cpp:439-491`): a callable is processed
   when its callees are final, so the do-block chain unfolds in the
   order itself;
3. takes specialization requests as content-keyed deltas: a request
   against a finished SCC re-queues exactly the affected SCCs,
   counted, each request decided once (0005 §3.5's virtual clones in
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
frontend's 140 s and 9.1 GB (0007's ground), and the LLVM tail once
it can run (0005 S2 measures it).

## 5. What this is not

Not separate compilation, not softened budgets, not threads as the
answer (parallelism divides what this cuts), not verifiers off, not
a second representation of any fact. Sharding (0005) consumes this
design unchanged: F3's SCC unit *is* 0005's phase-3 unit, its
summaries are 0005's, and nothing here is redone there.

## 6. The landing rule

Every stage lands with its measurement or not at all: the corpus
byte-identical (or the change in output named and intended), the
segment it claims faster by its threshold, no bench program's
compile regressing beyond 5% or its runtime beyond 2%, the suite
green, determinism 1/2/8. A cheaper round that needs more rounds
has bought nothing (§2.1, with the 19-round data point behind it).
