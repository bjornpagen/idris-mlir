# 0012: a sharded whole-program compiler

**Status:** proposed (2026-10-10), for after 0004 and 0005. Nothing here is built.
It **assumes 0004 (typed APL) and 0005 (shards) are fully implemented**, and builds on 0006
(flattened data), 0007 (the type checker), 0010 (the data-oriented frontend) and 0011 (the
relational core).

**Sources.** `sources/notes/sharded-compilation/whole-program-at-scale.md` (ThinLTO, GCC
WHOPR, MLton, rustc, MLIR threading, build systems, Zig, Swift, GHC) and
`sources/notes/sharded-compilation/deterministic-fixpoints.md` (work stealing, LVars,
deterministic algorithms, distributed Datalog, parallel CFA and SCCs, parallel
elaboration). The pipeline facts below were read from this repository at c50d176d.

**Claims** are marked: *read*, *measured*, *recalled*, *conjecture*, *decision*.

## 1. The thesis

**Keep the whole program as the unit of meaning; stop making it the unit of work.**

Whole-program knowledge carries the compiler's guarantees: monomorphic code with no
dictionaries, closures as closed sums, the static in-place promise, the acyclic heap, and
0009's closed sums. Those guarantees need **facts** about the whole program. They do not need
every pass to hold the whole program while it runs. The facts are small (sets, edges, flags,
sizes); the work (translating bodies, MLIR passes, LLVM) is large and nearly all local once
the facts are known.

So the compiler becomes:

1. **summaries**, per module, in parallel;
2. **global facts**, computed from summaries alone by deterministic sharded fixpoints;
3. **work**, per unit, sharded, given only that unit's slice of the facts, cached by content;
4. **link**, in a fixed order.

ThinLTO and GCC's WHOPR prove this shape at Chromium scale for optimization facts; this
proposal applies it to guarantee-bearing facts (sources: §1, §2 and §9 of
`whole-program-at-scale.md`).

**The invariant (decision, D1):** for every shard count and every schedule, the output is
byte-identical to the serial compile. Whole-program semantics, sharded execution, one output.

## 2. Where the pipeline is whole-program today

*Read* (c50d176d):
- Every C++ pass in `foreign/idr` is a `ModuleOp` pass, except `idr-canonicalize`
  (`include/idr/Passes.td`). The pipeline is 25 steps
  (`lib/Dialect/Registration/PipelineSteps.cc:9-70`), each its own `PassManager`
  (`lib/Driver/Run.cppm:182-222`).
- MLIR threading is **off**: `context.disableMultithreading()` "so results do not depend on
  scheduling, and idr-eval may fork" (`Run.cppm:59-62`). `tests/lib/determinism.sh` already
  runs `idris-mlir-opt --idr-pipeline` under MLIR's thread pool and compares bytes. 0013
  replaces it with static normalization in the frontend, and the fork goes.
- LLVM sees one module: one O3 run with MergeFunctions, one single-threaded codegen, no
  module splitting (`Target/Optimize.cppm`, `Driver/Emit.cppm`).
- The frontend hands the C++ side one text file built as one `String`
  (`Emit.idr:41-52`, `Program.idr:177-180`).
- Names come from counters and walk order: `<f>$lam<n>`, `<owner>$spec$n`, `name[args]'k`
  in request order (`Isolate.cppm`, `Specialize/Clones.cppm:95-183`,
  `Translate/Types.idr:61-90`). Fixpoint detection uses `OperationFingerPrint`, which hashes
  addresses, not content.
- There is no persistent cache and no separate compilation; the fork removed upstream's
  incremental code generators (`compiler/idris/README.md:59-70`).

*Measured* (HANDOFF.md): the stage-0 self-compile spends 137 s and 9.1 GB in the frontend and
emits a 405 MB module of 58,305 functions. The C++ side has **never run on it**, so the
largest cost of a cold self-compile is unmeasured (§10, S0).

### 2.1 Each pass, split into its global and its local part

| Pass | Global part (facts, phase 2) | Local part (work, phase 3) |
| --- | --- | --- |
| reachability, monomorphisation (`Translate/Instances.idr`) | the instance set from `main`; the 4096 budget; growing-shape refusals | translating each instance's body |
| dictionary fields (`Translate/Dictionaries.idr`) | the one implementation per field over all construction sites (a monotone set; two → refusal after freeze) | — (the late-site *restart* disappears: facts only grow) |
| box or unboxed (`Programs.idr:107-120`) | SCCs of the data containment graph | — |
| `idr.program` verifier | type-graph acyclicity, the single root | linearity and owned stage per function, re-checked per unit after every pass |
| `idr-effects` | io/crash/diverge propagation over calls and closure labels | — |
| `idr-contify`, `idr-returned-arguments`, `idr-tail-calls` | exactly-one-caller, every-use-is-direct, call cycles | the rewrites |
| `idr-inline` (MLton size rule, `Inline/Decisions.cppm`) | decisions bottom-up over call-graph SCCs from summary sizes; per-unit import lists (ThinLTO) | inlining imported bodies |
| `idr-specialize` (`Specialize/Clones.cppm`) | the clone set: requests keyed by (owner, pattern key); the 1024 budget in key order | materializing a clone in its owner's unit (a GCC virtual clone) |
| `idr-defunctionalize` (`Defunctionalize/Analysis.cppm`) | label flow: which lambdas reach which apply sites (0CFA as Datalog); sums keyed by (closure type, label set) | rewriting applies and constructions |
| `idr-stack` | escape summaries per parameter over all calls | marking |
| `idr-rc` (`Ownership/Exclusive.cppm`, `Borrow.cppm`) | exclusivity as the complement of the monotone "shared somewhere" (§4.3); borrow inference's fixpoint | placing increments and decrements |
| `idr-demand` | verdicts of the in-place promise from exclusivity | — |
| `idr-narrow`, `idr-in-bounds` | interprocedural ranges and the length relation of private functions (a greatest fixpoint, computed as the complement of a least one) | the rewrites |
| `Layouts::of` | every cell header, once | — |
| `idr-lower`, `idr-entry`, conversions, `idr-vectorize`, `idr-narrow-lanes`, `idr-accumulate`, `idr-trmc`, `idr-tail-loops` | — | per function |
| LLVM O3, codegen | cross-unit decisions already made (imports, internalization) | per codegen unit |

The global column is a list of relations and fixpoints over summaries; the local column is
work over one unit's bodies. Every current module pass splits along this line, GCC's IPA
protocol made explicit (generate summary, execute without bodies, transform).

## 3. The architecture

```text
modules ─▶ [1 summarize, per module] ─▶ summary tables (columnar)
                                              │
                         ┌────────────────────▼────────────────────┐
                         │ [2 global facts] sharded semi-naive      │
                         │  rounds over mlir-relational, freeze,    │
                         │  scan-label ids, slice per unit          │
                         └────────────────────┬────────────────────┘
                                              │ unit = (bodies, imports, fact slice)
              ┌───────────────┬───────────────┼───────────────┬───────────────┐
              ▼               ▼               ▼               ▼               ▼
        [3 work: translate → idr passes → LLVM O3 → object], one unit per message
              │      ▲ specialization requests and new instances (outer rounds)
              └──────┴──────────────────────▶ back to 2 until no delta
                                              │
                                     [4 link, fixed order]
```

### 3.1 Phase 1: summaries

Each module, in parallel across shards, is elaborated (0007), translated into 0010's tables,
and summarized. A summary is a set of flat, columnar relations (0006: the shard message
format, copied as a buffer with no detach walk):

- definitions with content hashes, sizes and effect bits;
- call and reference edges; lambda construction sites and apply sites;
- data containment edges; dictionary construction sites;
- per call site, whether each argument is passed shared or exclusive *at that site*;
- the results of static normalization: every closed call of total code in the module,
  normalized here on the type checker's interpreter (0013), since a closed call needs only
  its callees, which the module's imports provide.

Summaries are keyed by the module's content hash, so an unchanged module's summary is reused
(§6).

### 3.2 Phase 2: global facts (the "thin link")

Every fact of §2.1's global column is a relation computed by 0011's `mlir-relational`
(layers 1 and 2) over the summaries, run **sharded and bulk-synchronous** (§4). Its outputs:

- the frozen fact relations;
- the **units**: SCCs of the call graph after inlining decisions, packed into balanced,
  edit-stable groups (§3.4);
- for each unit, its **fact slice**: its instances, its import list, the closure sums its
  applies dispatch on, its layouts, its exclusivity and range facts, its specialization
  descriptors — and the slice's hash.

Each unit receives only its slice, as ThinLTO's distributed mode ships each backend only its
index subset.

### 3.3 Phase 3: work

A unit is one closed message: its bodies (columnar), the read-only bodies it imports, and its
fact slice. A shard turns it into an object: translate, emit `idr` ops, run the local passes
with **its own `MLIRContext`**, lower, LLVM O3, codegen. No pass reads anything outside its
unit, which is exactly MLIR's threading rule (no sibling inspection, no global mutable state)
applied at the unit level.

Specialization and inlining inside simplify can *request* new instances or clones. A request
is a tuple keyed by content, sent back to phase 2 as a delta; the outer loop (§5.1) runs
until no unit requests anything new.

### 3.4 Units and partitioning

Two granularities, decoupled:
- **Simplify units** follow call-graph SCCs: mutual recursion, loop breakers and inlining
  need the SCC whole.
- **Codegen units** follow size: after simplify, functions are packed into balanced groups
  for LLVM (rustc's CGUs, GCC's balanced partitioner), so one huge SCC does not become one
  huge LLVM job.

**Decision (D4):** partitioning is a pure function of content, independent of the shard
count, and stable under small edits: units are named by the hash of their sorted member
hashes, grouping keeps a definition with its module neighbours (rustc's stable and volatile
CGUs, GCC's `cache` partitioner). Because the partition does not depend on P, the objects and
the executable are identical for every P.

### 3.5 Phase 4: link

Objects are linked in unit-name order. Cross-unit symbols are hidden in the final image.
Whole-program internalization survives as a fact (only `main` is public), applied per unit
as hidden visibility plus the import decisions. Identical post-erasure instance bodies are
folded **in phase 2 by content hash**, replacing LLVM's per-module MergeFunctions across
units.

## 4. Deterministic sharded fixpoints

The recipe (sources: `deterministic-fixpoints.md` §9).

### 4.1 Monotone sets, sharded by content

Every global relation only grows within a build, so it is an LVar-style set: the order in
which deltas arrive cannot change the fixpoint. A tuple's owner shard is the hash of a
canonical, content-derived key: a definition's hash plus a normalized type-argument vector,
Merkle-hashed over hash-consed terms (0007 §2.1). Relations that join on a column share a
decomposition (Slog); recursion partitioned on its pivot needs no shuffle (BigDatalog).

### 4.2 Bulk-synchronous semi-naive rounds

Each round: every shard joins its delta against the totals (0011 layer 2), routes derived
tuples to their owner shards **as messages** (0005), owners insert and dedupe, and a global
reduction asks whether anything is new. Only the frozen result is read by the next phase.
**Decision (D2):** propagation is synchronous; asynchronous propagation reaches the same
fixpoint but lets round counts and budgets depend on the schedule.

### 4.3 Non-monotone facts are complements read after freeze

"This argument is exclusive at every call site" is not monotone. Its dual, "shared at some
call site", is. Compute the dual to its fixpoint, freeze, read the complement. The same
applies to the greatest fixpoints (`idr-identity`, the in-bounds length relation): compute the
least fixpoint of the negation. This is the LVars "freeze after writing" discipline, and it
removes the one place where reading early would make the answer depend on timing.

### 4.4 Identifiers in two phases

During fixpoints everything is named by content hash. After freeze, each shard sorts its
keys, an exclusive prefix sum over shard counts in shard order gives offsets, and each shard
numbers its keys locally: Blelloch et al.'s scan labeling, equal to a serial numbering by key
order. Hash collisions are checked by full equality at the owner. **No id from an allocation
counter, a thread, a bump pointer or an arrival order reaches output bytes, symbol names,
partitions or cache keys (D3).** Zig's `InternPool` (thread id in an index's high bits) is
the counterexample to avoid.

### 4.5 Symbol names

Counters go: `$lam<n>` becomes `$lam<h>`, `$spec$n` becomes `$spec<h>`, collisions `'k`
disappear, where `<h>` is a short content hash of what the symbol denotes, widened only on a
collision found at freeze. ThinLTO's renaming by module hash is the precedent. Names become
stable under unrelated edits, which is also what makes the cache hit.

## 5. The hard parts

### 5.1 The simplify loop is a global fixpoint

Today `idr-simplify` iterates inline, specialize, sccp and canonicalize over the
whole module, up to 64 rounds (`Passes.td:579`), and specialization creates clones that
change the facts. Sharded, it is an **outer fixpoint**:

1. phase 2 freezes the facts; 2. every unit runs one local simplify round to its own
fixpoint; 3. units emit specialization requests and newly needed instances as content-keyed
tuples; 4. phase 2 takes them as a delta, re-runs only the affected fixpoints semi-naively,
re-slices only the affected units; 5. repeat until no delta.

Budgets (1024 clones per owner, 4096 instances per definition, 64 rounds) are spent **in phase
2, in key order** (D5), never in arrival order, so a budget's refusals are the same for every
schedule. A clone is a GCC-style virtual clone: a descriptor (owner, pattern key) that the
owner's unit materializes.

*Conjecture:* most units reach their fixpoint in one or two outer rounds, because
specialization requests cluster in a few hot owners. S6 measures the round count on the
self-compile and the corpus.

### 5.2 Defunctionalization's sums ripple

Adding one lambda changes the closure sum at every apply site it reaches. Sum constructors
are ordered by the lambda's content hash, so an added lambda inserts one case and only the
units holding those applies change slice (§6's early cutoff stops the rest). MLton's 0CFA
over all of MLton took under 2 s (*measured*, Weeks 2006, read online): the analysis is not
the cost; the ripple is.

### 5.3 Static normalization lives in phase 1

0013 replaces the C++ `idr-eval` with static normalization in the frontend, on the type
checker's interpreter. For this design that means:
- normalization is per module, in phase 1, cached under the module's content hash with the
  rest of its summary;
- its budget is counted steps, so its results and its over-budget calls are the same on
  every schedule;
- phases 2 to 4 never run program code: no evaluation service, no scratch modules, no
  fork, and MLIR threading can be on;
- outer simplify rounds are driven by specialization only (§5.1).

### 5.4 Two worlds: Idris shards and C++ passes

The frontend, the elaborator, Translate, the summaries and phase 2 are Idris and run on
0005's shards with 0004's arrays. The `idr` passes and LLVM are C++ (AGENTS.md: the dialect
and passes are C++ in `foreign/idr`). 0005's runtime does not reach into them.

**Decision (D7):** the C++ side follows the same discipline with its own threads: one worker
per core, one `MLIRContext` per worker (shared-nothing; types re-uniqued per worker at a
memory cost S0 measures), units as MLIR bytecode buffers, results merged by unit name. The
boundary between the worlds is per-unit bytecode, never one text module (0010 O2). The driver
keeps `idris-mlir` as the C++ orchestrator; the Idris side is a library of phases it calls
through the existing child-process boundary, then through 0001's Rust interop if that lands
first.

### 5.5 Large read-only facts across shards

0005 has no shared heap; a large frozen table copied to every shard is serial work on the
sender, and `lent` waits on its measurement rule (0005 D10: build it when detach walks exceed
5% of wall). **Decision (D8):** ship slices, not tables. Each unit message carries only its
fact slice, so no shard needs the whole fact base. The global tables stay sharded where they
were computed. If a phase still needs a broadcast, it is the measurement that triggers `lent`.

## 6. Incremental builds and the cache

A build is a constructive-trace build system (Mokhov et al.) with early cutoff at three
levels:

| Level | Key | Cut off when |
| --- | --- | --- |
| summary | hash of the module's elaborated content (TTC) | its summary hash is unchanged |
| fact slice | hash of the unit's slice | the slice hash is unchanged (a projection firewall: a global fact changes, most slices do not) |
| object | hash of (toolchain version, target, options, unit content, sorted import hashes, slice hash) — `computeLTOCacheKey`'s recipe | the object exists |

The store is content-addressed blobs plus a small relational index. 0011's core (or bumbledb
in hosted mode, as a shared cache over S3) can hold the index; that choice is open (§12). An
edit to one definition re-summarizes one module, re-runs phase 2 semi-naively on its delta,
re-slices the units whose slices changed, and recompiles only those.

ThinLTO's numbers set the expectation (*measured*, Chromium-scale): an edit to one rarely
called function took 25 s under ThinLTO against 17 min under full LTO. GCC 15's lesson sets
the precondition: partitions must not drift under small edits (D4), or nothing hits.

## 7. Using 0004 and 0005 inside the compiler

**0005 shards.**
- `runShards` hosts the compiler; phase 1 forks per module, phase 2 per relation shard, phase
  3 per unit (the Idris half), each with `fork`/`join`. Pure fork/join is "deterministic and
  equal to the sequential run" (0005 D2), which D1 needs.
- Messages are columnar or packed values (0006 D5), so summaries, deltas and slices cross
  shards as buffer copies.
- Load balance without a shared heap: **over-decompose** (one message per unit or relation
  shard, many more units than shards), send **longest first** (sizes from summaries; previous
  build timings from the cache may order placement but never decide output), place by queue
  depth (0005 §6), and let idle shards take unstarted messages, 0005's D9 item, which the
  compiler's own run is a natural case to measure (D9 builds it when idle time at the last
  join exceeds 1/10 of shards × wall). Message-based stealing in GLB's style (split and merge
  bags, lifelines) is the next step only if D9 is not enough.
- A started unit never migrates (0005); units are small enough that it does not matter.

**0004 arrays.** With 0010's tables, compiler data is ids and words, which is exactly what
0004's parallel lowering accepts (elements that count nothing). Phase 2's array work:
- sorting and grading keys for canonical order; scan labeling for ids (§4.4);
- segmented reductions for sizes, use counts and per-site sharing;
- `accumulate` histograms for partition sizes; size-change closure as Boolean matrix
  products (0007 §2.7);
- forward-backward SCC with trimming (Fleischer et al.) with canonical pivots, for call-graph
  and data-graph SCCs.
All integer: 0004's D15 lets integer reductions split across shards, so nothing here waits on
float reassociation.

## 8. What limits the speedup (the performance ceiling)

By Brent's bound, time on P shards is at most T1/P + T∞. The terms that do not shrink with P:

| Serial term | What bounds it | Remedy |
| --- | --- | --- |
| phase 2's global reductions and barriers | rounds × barrier cost | few rounds (semi-naive; facts only grow) |
| the largest simplify unit | the largest call-graph SCC after inlining | codegen units split it after simplify (§3.4); SCC size is reported per build |
| the outer simplify rounds | the specialization round count | measured in S6 |
| the link | linker parallelism | lld-style parallel linking (measured: clang's debug link 104 s with GNU ld, 5.3 s with lld) |
| summary I/O | GCC's WPA was mostly type and declaration streaming | flat columnar summaries, read as buffers |

Targets (*conjecture*, decided at S0 from the measured serial share):
- phase 2 at most **5% of one-shard wall**: by Amdahl that caps 8 shards at 5.9×, the same
  figure 0005 uses for lending;
- cold self-compile at 8 shards at least **0.6 × 8** faster than one shard;
- one shard **no slower** than today's serial pipeline (0005's rule: single-thread
  performance wins the tie);
- a no-op rebuild compiles **zero** units; a one-definition edit recompiles only the units
  whose slices changed.

## 9. Rules it keeps

- **Whole program, always** (AGENTS.md): every guarantee is still decided on the whole
  program; only the work is split.
- **Determinism**: byte-identical outputs for every shard count and schedule (D1).
  `tests/lib/determinism.sh` gains shard counts 1, 2, 8 and a schedule-perturbing mode
  (randomized placement and message delays) that must not change a byte.
- **Static linking, both targets, no new runtime library**: no OpenMP, TBB or async runtime;
  0005's runtime on the Idris side, LLVM's thread pool on the C++ side.
- **Reject with a named rule**: budgets and refusals are decided in phase 2 in key order, so
  a refusal names the same cause on every schedule.
- **Single-thread performance wins the tie.**
- **The Pi Zero**: one core is one shard; nothing here may cost it.

## 10. Staged plan, each stage with its proof

| Stage | Content | Proof |
| --- | --- | --- |
| S0 | measure: the C++ pipeline on the self-compile module (needs `make bootstrap`); per pass, the time in its global part against its local part; LLVM's share | committed record; the per-pass split decides §8's targets |
| S1 | content names: `$lam<h>`, `$spec<h>`, instance names by hash; sort at every hand-off | corpus outputs unchanged; names stable under an unrelated edit (a fixture) |
| S2 | units: per-unit bytecode from the frontend; split LLVM codegen; parallel local passes with one context per worker; ordered link | executables byte-identical across worker counts 1, 2, 8; compile-time speedup on bench |
| S3 | summaries and phase 2 for the cheap facts: reachability, effects, layouts, the type graph, contify, returned arguments, tail calls | differential: phase 2's facts equal the module passes' on the corpus and the self-compile |
| S4 | defunctionalization's label flow in phase 2 (0CFA on 0011) | differential against `idr-defunctionalize`'s analysis; sums identical |
| S5 | exclusivity, borrow and in-bounds facts as monotone duals | differential; `idr-demand` verdicts identical |
| S6 | inline and import decisions in phase 2; simplify per SCC unit; specialization requests as deltas; outer rounds; budgets in key order | corpus outputs unchanged; outer round counts recorded; self-compile speedup |
| S7 | MLIR's pass-manager threading on for nested pipelines, after 0013's V2 removes the fork | `determinism.sh` across thread counts; byte-identical outputs |
| S8 | the Idris half on 0005 shards: phase 1 per module, 0010's Translate fixpoint sharded, columnar summaries as messages | determinism across shard counts; phase 1 and 2 speedup |
| S9 | the persisted cache and early cutoff at three levels | no-op rebuild compiles zero units; a one-definition edit recompiles only changed slices |
| S10 | balance: longest-first placement; the D9 measurement on the compiler's run; GLB-style stealing only if D9's rule fires and it is still not enough | idle time at the last join below 1/10 of shards × wall |

## 11. Rejected alternatives

- **Separate compilation with interface files** (GHC, Swift's primary-file mode): it loses
  the instance set, the closure sums and the every-caller fact, so it loses the guarantees.
- **One module, MLIR threading only**: almost every pass is module-anchored; only the nested
  inline pipeline would thread.
- **Work stealing over a shared heap**: 0005 rejects it ("every count becomes atomic, tagged
  or traced").
- **Asynchronous fixpoints**: same result, schedule-dependent round counts and budgets (D2).
- **Ids by allocation or arrival order**, including per-thread interning (Zig's), randomized
  partitioners (METIS unseeded), and timing-based heuristics in any decision.
- **Trusting hash equality**: collisions are checked by full equality at the owner.
- **Shipping whole fact tables to every unit**: slices instead (D8); broadcasts are what
  `lent` exists for, if measured.
- **A partition that depends on the shard count**: objects would differ per P (D4).

## 12. Open questions

- The hash: BLAKE3 through Rust interop (0001) or a runtime primitive; width and collision
  policy.
- Memory per C++ worker with its own `MLIRContext` (re-uniqued types): S0 and S2 measure it.
- The largest SCC of the self-compile after inlining: if one SCC dominates, simplify within
  it needs its own split.
- Where the cache index lives: 0011's core in-process, or bumbledb as a shared cache over S3.
- Whether the Idris half should drive the C++ half (a self-hosted driver) once 0001 lands.

## 13. Decisions

- D1. Byte-identical output for every shard count and schedule.
- D2. Global fixpoints are bulk-synchronous semi-naive rounds; only frozen results are read.
- D3. No schedule-dependent id reaches output, names, partitions or keys; ids are content
  hashes, then scan labels after freeze.
- D4. Partitions are a pure, edit-stable function of content, independent of P; simplify
  units follow SCCs, codegen units follow size.
- D5. Budgets and refusals are decided in phase 2 in key order.
- D6. Static normalization (total code only, 0013) runs in phase 1; phases 2 to 4 never run
  program code.
- D7. The C++ side runs one `MLIRContext` per worker, units as bytecode, results merged by
  name.
- D8. Units carry fact slices, never whole tables.
- D9. Balance by over-decomposition, longest first and queue-depth placement; stealing only
  by 0005's measured rules.
