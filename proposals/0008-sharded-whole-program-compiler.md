<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0008: a sharded whole-program compiler

**Status (2026-10-19, read at 77eaa5b1):** open; S1, S2's first step
and S7 are built (§2) and have run on arm64 macOS in every suite since
2026-10-18. Nothing else is built, and `make self` needs nothing more
from here. **First step: S0's second record**, taken from a stage-1 self
run once two pass statistics are written (§10); self-hosting does not
wait for them.
From that record: S2's second step comes after `make self`, unless the
record shows the whole-module O3 does not fit the owner's machine; S3 to
S6 are each taken by §10's measurement rule. S8 and S10 wait on 0007's
P4 and on 0011's O3, which needs 0015's R1 and R2 first. S9 follows S2's
second step. A stage that lands deletes the form it replaces in the same
change. Claims are marked *read*, *measured*, *recalled*, *conjecture*
or *decision*. Paths are under `foreign/idr/` unless named. The sources
are `sources/notes/sharded-compilation/` (*wpas*, *dfp*),
`sources/notes/compile-pipeline/` and F0
(`bench/records/2026-10-14-f0-stage0.md`).

## 1. The thesis

Keep the whole program as the unit of meaning; stop making it the unit of
work. There are three layers, never traded against each other
(*decision*):

- **Guarantee facts:** the instance set and the refusal of an unbounded
  one, dictionary uniqueness, closure sums, exclusivity and borrows,
  layouts, and the acyclic type graph. They stay whole-program forever.
  Each is decided in key order, so a refusal names the same cause on
  every schedule (D5).
- **Decision facts:** inlining, the clone set and deduplication by
  content. These are pure optimization, since defunctionalization is
  total by analysis. Each is taken once, in dataflow order, from content
  and frozen facts (D10, D11).
- **Pure work:** per-function rewrites, the lowering tail, LLVM's O3 and
  code generation, all per unit.

Every stage is then four steps: summaries per unit; whole-program facts
computed from the summaries alone and read frozen; work per unit, each
unit given only its slice of the facts; and one link in a fixed order.
This is the shape of GCC's WHOPR and of ThinLTO (wpas §1, §2).

**The invariant (D1):** for every shard count, worker count and schedule,
the output is byte-identical to the serial compile.

The one loss this design prices is LLVM's interprocedural pass across
codegen units, which S2's second step gives up. It is held to a bench
runtime within 2% (ThinLTO's record, wpas §1).

## 2. Built, and what it still owes

Built by the pipeline cutover (c7aa7b62, 5d5f3312; its last text at
484d6403), with the code as the record:

- S1, names from content, XXH3-128 (D16): `lib/IR/ContentNames.cpp`,
  `include/idr/IR/Symbols.h`, `compiler/src/IdrisMLIR/Ids.idr`,
  `compiler/src/IdrisMLIR/Frontend/Translate/Keys.idr`;
  `tests/determinism-name-stability`, `tests/content-hash`.
- S2's first step, one whole-module O3 then bins of SCCs (D4):
  `lib/Target/Partition.cpp`, `lib/Target/Extract.cpp`,
  `include/idr/Target/Target.h` (`binInstructions`),
  `lib/Driver/Artifacts.cpp` (`writeObjects`), `lib/Driver/Run.cpp`.
- S7, MLIR threading and the ready set's waves on the context's pool:
  `lib/Transforms/Pipeline.cpp`, `lib/Transforms/Optimize/Waves.cpp`.
- D5, D10, D11 and D20: `include/idr/Transforms/Specialize.h`,
  `include/idr/Analysis/Inline.h`, `include/idr/Analysis/Identities.h`.

F0 keeps three numbers that still hold: the frontend's 58,236 functions
in about 140 s at 9.1 GB on Chez, the largest SCC (24 of 28,276
functions after inlining), and namespace locality (17% of direct-call
pairs inside one module, 49% inside one top-level namespace).

Owed by S2's first step, held by no test:

- the cutover's D33: a program whose tail-call cycle spans two namespace
  groups, which would overflow the stack without its tail calls
  (acceptance: it runs in constant stack; with 0006's G1);
- the cutover's D41: an edit fixture in which every bin the edit does not
  touch keeps its members (with S9).

## 3. The architecture

### 3.1 Summaries

A summary is a set of flat columnar relations (0012 D5), keyed by the
content hash of what it summarizes, so an unchanged input's summary is
reused (§6). There are two kinds:

- **The frontend's, one per Idris module (phase 1).** It holds:
  - definitions with their content hashes;
  - TT call and reference edges;
  - data containment edges;
  - dictionary construction sites;
  - the results of static normalization (0010 §7).
- **Each C++ stage's, one per unit.** It holds what that stage's global
  part reads: sizes, call edges with their multiplicity, closure
  constructions and applies, whether each argument is passed shared or
  exclusive at each call site, escape facts and ranges. These are plain
  C++ data, never IR, and are merged in sorted order.

### 3.2 Phase 2: whole-program facts

Each stage's global part is computed from its summaries alone. The
frontend computes its own facts in Idris: the instance set is 0011 D3's
semi-naive fixpoint, on 0015's core. The C++ facts are computed in
`foreign/idr` on MLIR's pool (D13). A fact that is a fixpoint is computed
in bulk-synchronous rounds (§4). A fact that is a summary is computed
callee first, over the SCC order. Phase 2 outputs:

- the frozen relations;
- the units (§3.4);
- each unit's fact slice, with the slice's hash (D8).

### 3.3 Phase 3: work

A unit's work reads its own bodies, its slice and, in the optimizer, its
callees' final bodies. No pass reads anything outside its unit. Every
stage up to lowering runs in one `MLIRContext` (D7). There is no outer
delta loop, and the instance set is closed before translation starts
(D10).

### 3.4 Units and partitioning

- **Optimizer units** are the ready set's components, whose members are
  never inlined into one another.
- **Codegen units** are §2's bins (D4).

At S2's second step the bins are cut on the lowered module. Its
LLVM-dialect ops are counted against the same `binInstructions`, so the
bin size stays one constant in one unit. The dialect's ops are the
instructions to be (*conjecture*: the two counts agree within the slack
between B/4 and 2B, which S2's second step records). The runtime's
definitions have C names with no dot, so they fall into one group by the
same rule.

### 3.5 Phase 4: link

At S2's first step this is built:

- a symbol another bin reads is external, hidden and `dso_local`, under
  `__idr.` (`lib/Target/Partition.cpp`);
- the root is the one public symbol.

At S2's second step each unit links the runtime's `available_externally`
bodies before its own O3, through the same `LinkOnlyNeeded` link
(`lib/Driver/LinkRuntime.cpp`). Where the runtime's bodies are
definitions, they are defined once, in the runtime's group (*decision*:
today's two cases, and no third).

Identical bodies are folded at three levels, each folding what the level
before it could not see:

1. idr-deduplicate;
2. MergeFunctions in O3, per unit from the second step;
3. `--icf=all` at the link (`CMakeLists.txt`, each target entry's
   program link flags).

## 4. Deterministic sharded fixpoints

This is the recipe of dfp §9, for every whole-program fixpoint on either
side. The ready set is not such a fixpoint (§5.1).

### 4.1 Monotone sets, sharded by content

Every global relation only grows within a build, which makes it an
LVar-style set. A tuple's owner shard is the hash of a canonical key
derived from its content. Relations joined on a column share one
decomposition (Slog). A recursion partitioned on its pivot needs no
shuffle (BigDatalog; dfp §4).

### 4.2 Bulk-synchronous semi-naive rounds

In each round:

1. every shard joins its delta against the totals;
2. it routes the tuples it derives to their owner shards;
3. the owners insert them and remove duplicates;
4. a global reduction asks whether anything is new.

Only frozen results are read. The rounds are synchronous so that no round
count, and no bound counted per round, depends on the schedule (D2).

### 4.3 Non-monotone facts are complements read after freeze

"Exclusive at every call site" is not monotone, so it is computed as the
complement of "shared at some call site", which is. That dual is a least
fixpoint, frozen and then read (LVars' freeze after writing, dfp §3).
Identities are not global: each component takes its own greatest fixpoint
(§2).

### 4.4 Identifiers in two phases

While fixpoints run, everything is named by its content hash. After the
freeze, ids come from Blelloch's scan labeling, which equals a serial
numbering in key order. A hash collision is checked by full equality at
the owner. No id from a counter, a thread or an arrival order reaches
output bytes, names, partitions or cache keys (D3).

### 4.5 Symbol names

Built as S1 (§2). A name never widens on a collision (D16), so no key's
name depends on another key's.

## 5. The hard parts

### 5.1 The optimizer is a ready set

The ready set is built (§2). A body is a function of its own body and its
callees' final bodies, so the sharded form is the same ready set with
more workers. D5 and D11 removed the two quantities that would have read
an arrival order.

### 5.2 Defunctionalization's sums ripple

A sum's constructors are ordered by their labels' content names, so a
new lambda inserts one case. The analysis is cheap: MLton's takes under
2 s (Weeks 2006), and ours is held under 10 s on stage 0 by the cutover's
§10. The cost is the ripple to every apply site, and S9's early cutoff
prices it.

### 5.3 Static normalization lives in phase 1

Static normalization runs per module, cached with the module's summary.
Its budget counts steps and bytes (0010 D8), so its results are the same
on every schedule. Phases 2 to 4 never run program code (D6).

### 5.4 Two worlds

**The C++ half (D7).** It runs in one process on MLIR's pool, with one
`MLIRContext` up to lowering. Each codegen unit has its own
`LLVMContext` (built). From S2's second step each unit also has
its own `MLIRContext`, because concurrent translation of sibling modules
on one context is neither documented nor tested upstream
(upstream-mlir-llvm §5). Per-worker contexts before lowering come only by
S6's rule.

**The Idris half (the owner, §12).** It is single-threaded until 0007's
typed shards exist. After that it runs on them under idris-mlir, and on
Chez it runs the same code sequentially, through the plain-Idris layer
§12 names. Summaries and units cross to the C++
driver at the frontend's child-process boundary
(`lib/Driver/Compile.cpp`) as files:

- 0012's columns, whose id columns the reader checks once (0012 D11);
- MLIR bytecode: one module today, and one per unit from S8.

**Translation units at S8 (D18).** The frozen instance set, sorted by
key, is cut into ranges of about 2^15 Core nodes, sized by 0011 D8's
subtree sizes (*conjecture*: tens to hundreds of ranges at stage 0). Each
shard writes one bytecode file per range. The driver then:

1. reads each file unverified (`ParserConfig(..., verifyAfterParse =
   false)`);
2. merges the top-level ops in symbol order;
3. verifies the module once.

So the cut never reaches output. Identified types are uniqued by name, so
a type written in several units is held once, and two different bodies
under one name are an internal error.

The driver stays C++, because MLIR and LLVM link into it in process.

### 5.5 Slices, not tables

Each unit carries only its fact slice, so no worker needs the whole fact
base (D8). A phase that still needs a broadcast states its measured cost
before anything is built for it.

## 6. The cache (S9)

The build is a constructive-trace build system with early cutoff, at four
levels (`sources/papers/mokhov-2018-build-systems`; D15):

| Level | Key | Cut off when |
| --- | --- | --- |
| summary | hash of the module's elaborated content (TTC) | the summary's hash is unchanged |
| fact slice | hash of the unit's slice | the slice's hash is unchanged |
| node | hash of the node's bodies as the whole-program stages left them, its slice hash, and the sorted hashes of the final body and summary of every callee it reads | the final body's hash is unchanged |
| object | hash of the toolchain version, the target entry, the bin's lowered members, and the cross-unit declarations it reads with their attributes (`computeLTOCacheKey`'s recipe) | the object exists |

- No option enters a key, because no option changes output.
- Each key hashes content with its locations stripped. The locations are
  kept beside it and read only to name a refusal (D17). S9's proof checks
  that no location reaches a program byte (*conjecture* until then).
- The store is a directory of content-addressed blobs under the build
  directory, plus one sorted index, written by the C++ driver over
  `llvm/Support/xxhash.h`. This is Mojo's `Cache/` design.
- The object level needs S2's second step: under one whole-module O3, an
  edit anywhere can change any bin.
- The precondition is that partitions do not drift under small edits
  (D4; wpas §2).

## 7. 0007's and 0009's mechanisms inside the compiler

- **Workers follow 0007's rules:**
  - pure work is equal to the sequential run (0007 D2);
  - messages are columnar values;
  - work is balanced by over-decomposition, longest first (as
    `writeObjects` already orders its bins, `lib/Driver/Artifacts.cpp`),
    and by queue-depth placement;
  - stealing comes only by 0007's D9;
  - a started unit never migrates.
- **The C++ side's pool balances already:** `failableParallelForEach`
  hands out elements by an atomic index.
- **The Idris side's array work is integer and semiring reductions**,
  which 0009 D15 lets split:
  - sorting keys, and scan labeling;
  - segmented reductions for sizes and per-site sharing;
  - histograms for partition sizes;
  - size-change closure in the `i8` semiring;
  - forward-backward SCC with trimming over the data containment graph.

## 8. The ceiling and the targets

By Brent's bound, time on P workers is at most T1/P + T∞. These serial
terms do not shrink with P:

- phase 2's barriers;
- the ready set's depth and its largest component;
- the label solve;
- the whole-module O3, until S2's second step;
- the link, which is lld;
- summary I/O.

The targets (*decision*):

- phase 2 takes at most 5% of one-worker wall;
- a cold self-compile at 8 workers is at least 0.6 × 8 faster than at
  one;
- at one worker, no slower than the cutover's pipeline by more than 5%,
  best of five, binary against binary;
- a no-op rebuild compiles zero units;
- a one-definition edit recompiles only the nodes and bins whose keys
  changed.

A target the record shows is out of reach is reported with its measured
serial share, never lowered quietly.

## 9. Rules it keeps

- Every guarantee is decided on the whole program.
- Output is byte-identical across workers, shards and schedules (D1,
  D14).
- Everything is linked statically: no OpenMP, TBB or async runtime.
- Every refusal names its rule (D5).
- Single-thread performance wins the tie.
- The serial pipeline is the sharded one with one worker. There is no
  second path and no differential mode (D12).

## 10. Staged plan

Every proof compares two binaries, the commit before against the commit
after, run on a named saved module (D12). Stage 1's
`build/self/stage1/idris-mlir-front.mlirbc` is that module.

**The measurement rule, stated once:** a stage is taken when S0's second
record shows the wall it would split above 5% of one-worker wall.

| Stage | Content | When | Proof | Mark |
| --- | --- | --- | --- | --- |
| S0, second record | `make self`'s stage-1 run. `tools/self.sh` already writes `-mlir-timing` (every pass, and LLVM's translate, link runtime, optimize and codegen; `lib/Driver/Run.cpp`) and peak memory to `build/self/stage1/`. It is also 0006's record of the self-compile: one run, read by both proposals. It adds three things nothing records yet: idr-optimize's wave count, its largest component (as pass statistics; `Passes.td` has neither), and the frontend's hashing time on Chez (D16). It is judged against the cutover's §10 thresholds: the optimizer under 600 s and the label solve under 10 s | the first stage-1 run, after the two statistics are added to `IdrOptimize` in `Passes.td` | committed under `bench/records/` | the first step; taken from a stage-1 run after the statistics land, not on self-hosting's path |
| S2, second step | The bins are cut on the lowered module (§3.4). Each bin's lowering tail, translation, O3 and codegen run in an `MLIRContext` and an `LLVMContext` of its own. The facts LLVM would lose across units are written as attributes on cross-unit declarations | after `make self` and 0006's step 6 | byte-identical at every thread count; D41's fixture keeps the bytes of the bins an edit does not touch; bench runtime within 2% of the first step's | **AFTER-SELF**. It becomes **SELF-HOST** only if S0's second record shows LLVM's segment does not fit the owner's machine (0006 D10's rule). LLVM is measured only at test scale (3.8%, F0), and codegen is already split (*conjecture*: whole-module O3 fits) |
| S2's owed fixtures | D33's two-group tail-call cycle; D41's edit fixture (§2) | D33 with 0006's G1; D41 with S9 | they run | **AFTER-SELF** |
| S3 | The cheap global parts in parallel: the closed-world rule, the type graph and its value facts, layouts, deduplication's classes, contification's analysis, the tail-call plan, liveness sharded by §4 (D19), One-Shot's module analysis with 0012 D12's columns choice | by the rule, part by part or together | the module byte-identical on the corpus and stage 1's module | **AFTER-SELF** |
| S4 | The label solve, sharded in C++ by §4 | by the rule (*conjecture*: never, being under 10 s) | the sums and the module byte-identical | **AFTER-SELF** |
| S5 | Exclusivity and borrow grades as monotone duals (§4.3) | by the rule | `idr-demand`'s verdicts and the module byte-identical | **AFTER-SELF** |
| S6 | Per-worker contexts or processes before lowering, with units as bytecode | by the rule, on the one context's shared state (the uniquer, and the serial nesting between waves) | byte-identical across workers; memory per worker recorded | **AFTER-SELF** |
| S8 | The Idris half on 0007's shards, reached through §12's plain-Idris layer: phase 1 one module per task (0013's T7), 0011's Translate fixpoint sharded by §4, and per-unit bytecode (D18), from stage 1 on | after 0007's P4, that layer, and 0011's O3 | byte-identical across shard counts; the ranges' count and fixed cost recorded | **AFTER-SELF** |
| S9 | The cache at four levels (§6; D15, D17) | after S2's second step | a no-op rebuild compiles nothing; a one-definition edit recompiles only the nodes and bins whose keys changed; a line added at the top of a module leaves every object byte unchanged | **AFTER-SELF** |
| S10 | The Idris half balanced across shards: longest-first placement, then 0007's D9, then GLB-style stealing only if D9 is not enough | with S8 | idle time at the last join below a tenth of workers × wall | **AFTER-SELF** |

## 11. Rejected alternatives

- **Separate compilation with interface files:** it loses the instance
  set, the closure sums and the every-caller facts.
- **One module with MLIR threading as the end state:** LLVM's single
  module and the frontend stay serial.
- **Work stealing over a shared heap:** 0007 rejects it.
- **Asynchronous fixpoints:** their round counts depend on the schedule
  (D2).
- **An outer delta loop between phase 2 and the optimizer** (D10).
- **Any budget counted in arrival order** (D5, D11).
- **A widening rule for colliding names** (D16).
- **Locations inside a cache key** (D17).
- **Liveness computed per SCC:** it flows in both directions (D19).
- **Ids by allocation or arrival order, per-thread interning, an
  unseeded partitioner, or a timing heuristic in any decision** (D3).
- **Trusting hash equality** (§4.4).
- **Shipping whole tables to every unit** (D8).
- **A partition that depends on P** (D4).
- **LLVM's summary-based importer across units:** a second inlining
  analysis beside ours.
- **The C++ facts on 0015's Idris core** (D13).
- **A differential mode, a kept module pass or a schedule-perturbing
  mode:** each is an option, and the compiler has none (D12).
- **Per-worker `MLIRContext`s before a measurement asks for them** (D7).
- **A Translate partition that reaches output** (D18).

## 12. Questions closed by the owner (2026-10-14)

1. A primitive of ours has no meaning on Chez, and nothing is shaped so
   that Chez can run it. Two things follow:
   - The compiler's Idris half is single-threaded until 0007's shards
     exist, and then runs on them under idris-mlir. Code the stock host
     runs reaches no `libs/` `%extern` (the coordinator's two-hosts
     ruling of 2026-10-15, now AGENTS.md's two hosts). So the frontend reaches the shards
     only through a plain-Idris layer with bodies, whose meaning is
     sequential and is what Chez runs. idris-mlir replaces that layer
     with 0007's runtime through the registry's `Faster` hook, which
     changes no byte (D1). That layer is 0007's `Shard.Pure` (its
     D14).
   - From 0010's A3 the bootstrap's default stage 0 is the native
     frontend built from the last commit before A3 (0010 D19). That is
     only a build default: the frontend still compiles and runs under
     stock Idris on Chez, and is tested there.

## 13. Decisions

- D1. Output is byte-identical for every shard count, worker count and
  schedule. The serial pipeline is the sharded one with one worker.
- D2. Global fixpoints are bulk-synchronous semi-naive rounds, and only
  frozen results are read.
- D3. No schedule-dependent id reaches output, names, partitions or keys.
  Ids are content hashes during fixpoints and scan labels after the
  freeze.
- D4. Partitions are a pure function of content, independent of P and
  stable under small edits. Bins are named by the hash of their members'
  sorted names, and objects link in name order. Built for S2's first
  step (§2).
- D5. No bound counts arrivals. Every bound is a function of what it
  bounds, and a spent bound never refuses. Built (§2). The frontend's
  refusals are the growth check's, made on the whole program before
  translation (`compiler/src/IdrisMLIR/Frontend/Growth.idr`, 3fc4d2e4),
  so S8's sharded rounds refuse nothing.
- D6. Static normalization runs in phase 1 (0010 D1). Phases 2 to 4
  never run program code.
- D7. The C++ half runs in one process on MLIR's pool. Each codegen unit
  has its own `LLVMContext` (built), and from S2's second step its own
  `MLIRContext` too. Per-worker contexts before lowering come only by
  S6's rule.
- D8. Units carry fact slices, never whole tables.
- D9. Work is balanced by over-decomposition, longest first and
  queue-depth placement. Stealing comes only by 0007's measured rules.
- D10. A specialization request is a message to its key's node, and
  there is no outer delta loop. Built (§2).
- D11. `calls(f)` is frozen when the optimizer starts, a function on a
  cycle is never inlined, and a specialization node counts one call per
  request. Built (§2).
- D12. Every stage is proved binary against binary from a saved module,
  with no differential mode and no kept module pass.
- D13. Whole-program facts are computed on the side that owns them: the
  frontend's in Idris, the dialect's in C++. 0015 serves the Idris side
  only.
- D14. Determinism is checked across the thread counts
  `harness/lib/determinism.sh` names, and from S8 across as many shard
  counts. There is no schedule-perturbing mode.
- D15. The cache is content-addressed blobs and one sorted index, at
  four levels (§6). It lands as one stage, after S2's second step.
- D16. The one content hash is XXH3-128: LLVM's in C++, and the same
  algorithm in plain Idris over `Bits64`, checked against the published
  vectors (`tests/content-hash`). A name carries the low 64
  bits, a cache key all 128. A collision is an internal error. Built
  (§2).
- D17. Every cache key strips locations, and no location reaches a
  program byte.
- D18. At S8, Translate's units are key-sorted ranges of about 2^15 Core
  nodes, merged in symbol order and verified once, so the cut never
  reaches output.
- D19. Liveness is a least fixpoint. When S3's rule fires for it, it is
  sharded by §4 and equals the serial solve, never a per-SCC
  approximation.
- D20. RoundFacts' facts each got one home: `Holds` is the value-facts
  interface, and identities and binding times are per component in the
  one per-function summary. Built (§2).

## The MLIR form owed

From the representation wave's audit of the proposals' MLIR forms (its
last text at 77eaa5b1), checked against the code there; none of it is
built unless it says so.

- Whole-program facts are managed analyses read with
  `getCachedParentAnalysis`, as idr-narrow reads Ranges (`Narrow.cpp`);
  §3.1's "plain C++ data" changes with it. Still handed by constructor: the
  Exclusivity solve to idr-rc's commit (`Ownership/Exclusive.cpp`) and the
  ready set to idr-optimize's inner passes (`Optimize.cpp`).
- S6's units are the one module loaded lazily
  (`BytecodeReader(..., lazyLoad=true)` and `materialize`): no unit format
  and no merge. The writer already puts each isolated function in a
  section of its own.
- D19's liveness is upstream's `remove-dead-values` (`Pipeline.cpp`);
  sharding it is a patch to upstream's solver with its plan, never a
  liveness of ours.
- The ready set is recorded as a gap beside `mlir::Inliner`
  (`setOpPipelines`), with its upstream plan, in the list 0005's bumps
  check.
