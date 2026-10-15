# 0006: a sharded whole-program compiler

**Status:** proposed 2026-10-10; reprioritized 2026-10-12; reconciled
2026-10-14 with 0004's pipeline cutover, which it consumes unchanged.
Design only. Built so far, by the 0002 cutover and 0004's first
compile-time round: MLIR threading on, every rewrite a function pass
under a nested pass manager (0002 D3), deduplication by content,
IntRange per function, RemoveDeadValues once at the fixpoint, labels in
one walk (0004 §3.1). The cutover 0002 designed is committed and builds
on arm64 macOS: `make check` 27/27, `make test-idr` 286/286,
`make test` 415/415 (*measured* 2026-10-14 at `NCPU=6`, at 7a27fd34
before the opt-in SCC pipeline and at 552d682a with it off by default;
0004 deletes that pipeline, §3.3 there). x86_64 Linux is NotRun
(0002 §3).

0004 is the pipeline this proposal shards. Its stages are this
proposal's stages, its ready-set nodes are this proposal's optimizer
units, its codegen bins are this proposal's codegen units, and its
determinism rules are D1 with the thread pool as the schedule (0004 §4,
§9). 0004's cutover takes three stages of this proposal: S0 (its F0
record), S1 (content names, its D18) and S2's first step (code
generation split after one whole-module O3, its lane L7). S2's second
step, the split before O3, follows the cutover in 0004's order (§10
there). What remains here is the sharded form of the same pipeline: the
whole-program parts sharded where the post-cutover record shows them
serial, the compiler's Idris half in parallel, and a persistent cache
with early cutoff. It follows 0003's stage 1, which follows `make self`
(proposals/README.md). S3 to S6, S9 and S10 are each taken by the
measurement rule §10 names; none waits on 0012 (D13). This is a
cutover: when a stage lands, the form it replaces is deleted in the
same change, never kept beside it (0004 D2).

**Sources.** `sources/notes/sharded-compilation/whole-program-at-scale.md`
(cited *wpas*: ThinLTO, GCC WHOPR, MLton, rustc, MLIR threading, build
systems, Zig, Swift, GHC) and
`sources/notes/sharded-compilation/deterministic-fixpoints.md` (cited
*dfp*: work stealing, LVars, deterministic algorithms, distributed
Datalog, parallel CFA and SCCs, parallel elaboration); the five reports
of `sources/notes/compile-pipeline/`, cited as 0004 cites them
(*codegen-partitioning §1*, *mojo §2*, *mlton §2*,
*upstream-mlir-llvm §3*, *casework-audit §3*);
`bench/profiles/2026-10-14-f0-stage0.md` (*F0*). Our code was read at
3de67510 on 2026-10-14; paths are under `foreign/idr/` unless named.
`M/` and `L/` are the pinned MLIR and LLVM trees under
`.toolchain/build/llvm-project/`.

**Claims** are marked: *read*, *measured*, *recalled*, *conjecture*,
*decision*.

## 1. The thesis

**Keep the whole program as the unit of meaning; stop making it the unit of work.**

Whole-program knowledge carries the compiler's guarantees: monomorphic
code with no dictionaries, closures as closed sums (total since 0004
§2), the in-place promise (a type fact, 0004 D19), the acyclic heap,
and 0011's closed sums. Those guarantees need **facts** about the whole
program. They do not need every pass to hold the whole program while it
runs. The facts are small (sets, edges, flags, sizes); the work
(translating bodies, MLIR passes, LLVM) is large and nearly all local
once the facts are known.

Three layers, never traded against each other (*decision*, 2026-10-14):

- **Guarantee facts:** the instance set and its bound, dictionary
  uniqueness, closure sums, exclusivity and borrows, layouts, the
  acyclic type graph. Whole-program forever, never softened for compile
  time. A refusal is decided here, in key order, so it names the same
  cause on every schedule (D5).
- **Decision facts:** inline decisions, the clone set, internalization,
  deduplication by content. Since 0004 made defunctionalization total
  by analysis, these are pure optimization: they change code quality,
  never acceptance (0004 D1, D17). Each is taken once, in dataflow
  order, as a function of content and frozen facts (D10, D11). So the
  sharded optimizer writes the serial optimizer's bytes and loses
  nothing to sharding (D1).
- **Pure work:** per-function rewrites, the lowering tail, LLVM O3,
  codegen. Per unit, full stop.

The one loss this design prices is LLVM's second interprocedural chance
across codegen units, which S2's second step gives up (0004 §5.4).
Cross-function inlining already happens at the `idr` level under
whole-program facts, so only the most diminishing part goes. ThinLTO's
record says such a loss is small: halving the import threshold cost 5%
on povray and 6.7% on milc, and internalization alone kept about 90% of
the gain on astar (*measured* by its authors, wpas §1). 0004 §10 holds
it to a bench runtime within 2%.

So the compiler becomes, at each of 0004 §4's stages:

1. **summaries**, per unit, in parallel;
2. **whole-program facts**, computed from summaries alone, decided once
   and read frozen: a deterministic fixpoint where the fact is one (§4),
   a bottom-up SCC summary where it is one (0004 §4.9);
3. **work**, per unit, given only that unit's slice of the facts, cached
   by content;
4. and once, at the end, a **link** in a fixed order.

ThinLTO and GCC's WHOPR prove this shape at Chromium scale for
optimization facts; this proposal applies it to guarantee-bearing facts
(wpas §1, §2, §9).

**The invariant (decision, D1):** for every shard count, worker count
and schedule, the output is byte-identical to the serial compile.
Whole-program semantics, sharded execution, one output. 0004's
determinism rules (byte-identical at 1, 2 and 8 threads, checked by
`tests/determinism`, 0004 §4) are D1 with MLIR's thread pool as the
schedule.

## 2. Where the pipeline is whole-program

*Read* at 3de67510, with what 0004's cutover makes of each:

- The pipeline is one `OpPassManager` (`lib/Transforms/Pipeline.cpp:92-172`)
  with MLIR threading on (`lib/Driver/Run.cpp:221-239`), and every
  rewrite is a function pass under a nested pass manager. What holds the
  whole module is Simplify's rounds and their serial members: SCCP 21 to
  43 s per round, one InlineCleanup instance at 211 s (*measured*, F0).
  0004 replaces them with one bottom-up ready set (0004 §4.6).
- LLVM sees one module: translate, link the runtime, internalize all but
  `main`, one O3 with MergeFunctions, one codegen, one object
  (`Run.cpp:143-201`; `lib/Target/Optimize.cpp:44-59`). 0004 splits code
  generation into size-balanced bins (0004 §5). That is S2.
- The frontend writes one text module, streamed as printed
  (`compiler/src/IdrisMLIR/Emit.idr:62`), which the driver parses as text
  (`Run.cpp:264`). 0004 makes the handoff bytecode (0004 §4 stage 1).
  Per-unit bytecode is S8's.
- A frontend symbol is its instance key printed, origin then arguments.
  Keys that print alike get repeats `p'n` in the program's order
  (`compiler/src/IdrisMLIR/Emit/Index.idr:32-49`), and derived functions
  are `<parent>.<kind><n>` (`lib/Transforms/Isolate/Isolate.cpp:124-125`;
  `lib/Transforms/Specialize/Clones.cpp:40-41`;
  `lib/Transforms/Defunctionalize/Decide.cpp:188-198`). Counts are stable
  under an edit elsewhere, not under an edit in the parent. 0004 derives
  every name from content (its D18): S1.
- Identical bodies are merged by content where the dialect sees them:
  `idr-deduplicate` merged 7,505 of 107,732 post-isolate functions on the
  self module in about 1 s (*measured*, 0004 §3.1). 0004 replaces it with
  Mojo's bottom-up design, transitive in one pass (0004 §4 stage 3).
- There is no persistent cache and no separate compilation.

*Measured* (F0): the frontend spends about 140 s (9.1 GB peak at the
2026-10-10 measure) emitting 58,236 functions. The C++ side has never
finished on that module: one Simplify round took 385 s after 0004's
first round of fixes, and sixteen rounds reached no fixpoint. The call
graph it must partition: the largest direct-call SCC is 174 at
emission, 93% singletons; 14 after isolate, deduplicate and contify; 24
of 28,276 after six rounds, with 99 functions in any SCC over 10. Only
17% of distinct origin-to-origin call pairs stay inside one Idris
module, 49% inside one top-level segment. That is why units follow SCCs
and namespaces only group them (§3.4). The cold cost after the cutover
is S0's second record.

### 2.1 Each stage, split into its whole-program and its per-unit part

In 0004 §4's order (*decision*: each row's split is 0004's, read there;
this table adds only where the sharded form puts each part):

| 0004 stage | Whole-program part (phase 2: decided once, read frozen) | Per-unit part (phase 3) |
| --- | --- | --- |
| 1, reachability and monomorphisation (`compiler/src/IdrisMLIR/Frontend/Translate/Instances.idr`) | the instance set from the root; the bound of 4096 instances per definition (`Instances.idr:38-39, 108-112`) and the growing-shape refusals, each in key order (D5) | translating each instance's body; emitting closures and suspensions in symbol form with names from content (0004 §4 stage 1) |
| 1, dictionary fields (`Translate/Dictionaries.idr`) | the one implementation per field over all construction sites: a monotone set, two after freeze a refusal | none: the late-site restart (`Translate/Programs.idr:126-136`) disappears, since facts only grow |
| 1, box or unboxed (`Translate/Programs.idr:138-157`) | SCCs of the data containment graph | none |
| 2, closed-world verification | no external `idr.func`, one public root (0004 D7); the type graph acyclic | every closure- or lazy-typed operand on an op with the flow interface (0004 D8); quantities, linearity and the stage read from types (0004 D19), re-checked per unit after every pass |
| 3, deduplication | classes by content, merged bottom-up so that merging is transitive, the lexicographically smallest member kept (0004 §4 stage 3; mojo §4) | hashing each body; renaming call sites to representatives |
| 4, defunctionalization | the label solve in MLton's representation, under 10 s on stage 0 (0004 §2.8); one sum per label set, constructors in label-name order (§5.2) | the conversion, per function (0004 §2.7) |
| 5, contification | MLton's dominator analysis over the call graph (0004 §4 stage 5) | the rewrite into the caller |
| 6 to 8, the optimizer | the call graph's SCCs; each callee's call sites outside its SCC (D11); nothing else is decided up front | the ready set: decisions at each callee's finality, `mlir::inlineCall`, the inner pipeline once, the bounded local loop, specialization nodes (0004 §4.6 to §4.8) |
| 9, constants, effects and identities | bottom-up SCC summaries, callee first, applied through upstream's `visitExternalCall` (0004 §4.9; upstream-mlir-llvm §4); the identities of `idr-identity` (`include/idr/Transforms/Passes.td:313-346`, today computed by idr-round-facts) are one more such summary, their greatest fixpoint taken inside each SCC (*decision*: RoundFacts goes, 0004 §6, and the ready set reads callee facts frozen) | each function's solve with interprocedural mode off |
| 10, dead values | RemoveDeadValues and SymbolDCE once (0004 §4.10) | none |
| 11, memory and loops (`idr-stack`, `idr-accumulate`, `idr-rc`, `idr-demand`, `idr-trmc`, `idr-tail-loops`, `idr-narrow`) | escape summaries; exclusivity as the complement of "shared somewhere" (§4.3) and borrow grades, each function's grade contexts as a key set (0004 §4 stage 11); `idr-demand`'s verdicts on the in-place type fact; ranges | placement and commit of counts (already nested, `lib/Transforms/Ownership/Rc.cpp:66, 101`); the rewrites |
| 12, lowering | layouts, every cell header once; the runtime's declarations from the decided set (0004 §4 stage 12) | the conversion, per function |
| 13, partitioning | the bins (§3.4); the tail-call cycle plan of `idr-tail-calls` (`Pipeline.cpp:172`), read on both sides of a unit boundary (0004 §5.3 item 4) | none |
| 14 and 15, per bin | cross-unit declarations carrying the whole-program facts as attributes, at S2's second step (0004 §5.4) | the lowering tail, translation, O3 (whole-module at S2's first step), codegen |

`idr-in-bounds` and `idr-vectorize` are gone before sharding starts:
0003's stage 1 deletes them (0003 §15), and what replaces them carries
its facts in types (0003 §2). This supersedes the earlier row that
computed in-bounds length relations in phase 2.

The global column is each stage's summaries and fixpoints; the local
column is work over one unit's bodies. That is GCC's IPA protocol made
explicit (generate summary, execute without bodies, transform; wpas
§2), applied to every stage of 0004.

## 3. The architecture

```text
Idris modules ─▶ [1 per module: elaborate, normalize statically, summarize TT]
                                   │ summaries keyed by content hash
                                   ▼
                 [2 frontend facts: instances, dictionaries, representations]
                                   │ frozen instance set, sliced
                                   ▼
                 [3 per unit: translate, emit]  ─▶ units as MLIR bytecode
                                   │
        for each of 0004 §4's stages 2 to 12:
          [summarize per unit] ─▶ [whole-program part, frozen] ─▶ [per-unit part]
        (stages 6 to 9 are one ready set over SCCs, final bodies flowing upward)
                                   │
                                   ▼
                 [13 partition into bins of SCCs, 0004 §5.3]
                                   ▼
                 [14, 15 per bin: lowering tail, translate, O3, codegen]
                                   ▼
                 [16 link in unit-name order]
```

### 3.1 Summaries

A summary is a set of flat, columnar relations (0009 D5: copied as a
buffer, with no detach walk), keyed by the content hash of what it
summarizes, so an unchanged input's summary is reused (§6). There are
two kinds (*decision*: the earlier single phase-1 summary listed facts,
such as sharing per call site, that exist only after the optimizer, so
it could not be computed from an elaborated module):

- **The frontend's, per Idris module** (phase 1): definitions with
  content hashes; call and reference edges in TT, for reachability;
  data containment edges; dictionary construction sites; and the results
  of static normalization, every closed call of total code in the
  module normalized on the type checker's interpreter (0007 §7), since a
  closed call needs only its callees, which the module's imports
  provide.
- **Each C++ stage's, per unit**: what that stage's global part reads:
  sizes, call edges with their multiplicity, closure constructions and
  applies (stage 4), per call site whether each argument is passed
  shared or exclusive at that site (stage 11), escape facts, ranges.
  Plain C++ data, never IR, merged in sorted order.

### 3.2 Phase 2: whole-program facts (the thin link)

Each stage's global part is computed from its summaries alone. The
frontend's facts are computed by the frontend: the instance set as a
semi-naive fixpoint over the instance table (0008 D3), on 0012's core
if 0008's O3 builds it there. The C++ facts are computed by C++ drivers
over plain summaries on MLIR's thread pool: bulk-synchronous rounds
where a fact is a fixpoint (§4, D2), callee first over the SCC order
where it is a summary (0004 §4.9) (D13). Its outputs:

- the frozen fact relations;
- the **units** (§3.4);
- for each unit, its **fact slice**: its instances, the sums its
  applies dispatch on, its layouts, its exclusivity and range facts, the
  in-edges and SCC facts its decisions read, and the slice's hash.

Each unit receives only its slice, as ThinLTO's distributed mode ships
each backend only its index subset (wpas §1).

### 3.3 Phase 3: work

A unit's work is a function of its bodies, its slice and, in the
optimizer, the final bodies of the callees its decisions inline. No pass
reads anything outside its unit, which is MLIR's threading rule (no
sibling inspection, no mutable state across runs;
`sources/docs/mlir/docs/PassManagement.md:29-51`, upstream-mlir-llvm
§3) applied at the unit level. The C++ side runs it in one process, in
one `MLIRContext`, on MLIR's thread pool (D7): units are functions and
nested `builtin.module`s under nested pass managers, and each codegen
unit gets its own `llvm::LLVMContext` and `TargetMachine` (0004 §4
stages 14 and 15; the pattern of `L/lib/LTO/LTOBackend.cpp:517-570`).

In the optimizer, units wait on one another only through final bodies,
in dataflow order: a node runs when every callee outside its SCC is
final, and a specialization request is a message to the node of its key
(D10). There is no outer delta loop: the earlier design's loop, in which
units asked phase 2 for new instances and clones until no delta, is
superseded by 0004's demand-driven nodes. The optimizer never asks for a
frontend instance: the instance set is closed when translation starts.

### 3.4 Units and partitioning

Two granularities, decoupled, both 0004's:

- **Optimizer units** are the ready set's nodes, call-graph SCCs (0004
  §4.6). An SCC is processed whole, its members never inlined into one
  another (0004 D14). Where a node runs changes speed, never bytes.
- **Codegen units** are 0004 §5.3's bins: top-level namespace groups;
  inside a group, SCCs ordered by content hash and cut where the hash
  meets a boundary condition, between a minimum and a maximum size; the
  bin count a function of size, never of threads; a function too large
  for a bin a unit of its own; an SCC never split. The bin size is
  0004's open question 2.

**Decision (D4):** partitioning is a pure function of content,
independent of the shard and thread counts, and stable under small
edits. A unit is named by the hash of its members' sorted content names,
as rustc names merged CGUs by a hash of sorted names (*recalled*,
codegen-partitioning §4). Because the partition does not depend on P,
the objects and the executable are identical for every P. This
supersedes the earlier "simplify units follow SCCs because loop breakers
need the SCC whole": 0004 deletes loop breakers, and the reason an SCC
stays whole is now that its members are never inlined into one another.

### 3.5 Phase 4: link

As 0004 §5.3 item 3 decides: each definition lives in exactly one unit;
a symbol another unit references gets external linkage, hidden
visibility, `dso_local` and its content-derived name under a reserved
prefix, which avoids the static-link collision `SplitModule`'s FIXME
warns of (`L/include/llvm/Transforms/Utils/SplitModule.h:32-38`); every
other symbol is internal; the runtime enters every unit as
`available_externally` (`Run.cpp:184-192`); objects are linked in
unit-name order. Whole-program internalization survives as a fact (one
public root, 0004 D7), applied per unit as hidden visibility.

Identical bodies are folded at three levels, each where they first
become visible: `idr` deduplication by content before
defunctionalization (stage 3), MergeFunctions inside each unit's O3
(`Optimize.cpp:50`), and `--icf=all` across objects at the link, already
on with function sections (`CMakeLists.txt:174, 213`;
`Optimize.cpp:30`). None holds a fact another holds: each folds what
the level before could not see. This supersedes the earlier "folded in
phase 2, replacing MergeFunctions across units".

## 4. Deterministic sharded fixpoints

The recipe (dfp §9). It applies to every whole-program fixpoint, on the
Idris side and on the C++ side alike; the ready set is not one of them
(§5.1).

### 4.1 Monotone sets, sharded by content

Every global relation only grows within a build, so it is an LVar-style
set: the order in which deltas arrive cannot change the fixpoint (dfp
§3). A tuple's owner shard is the hash of a canonical, content-derived
key: a definition's hash plus a normalized type-argument vector,
Merkle-hashed over hash-consed terms (0007 §3). Relations that join on
a column share a decomposition (Slog); recursion partitioned on its
pivot needs no shuffle (BigDatalog; dfp §4).

### 4.2 Bulk-synchronous semi-naive rounds

Each round: every shard joins its delta against the totals (0012 layer
2 on the Idris side, plain C++ joins on the C++ side), routes derived
tuples to their owner shards as messages, owners insert and dedupe, and
a global reduction asks whether anything is new. Only the frozen result
is read by the next phase. **Decision (D2):** propagation is
synchronous; asynchronous propagation reaches the same fixpoint but lets
round counts, and any bound counted per round, depend on the schedule
(dfp §9 item 2).

### 4.3 Non-monotone facts are complements read after freeze

"This argument is exclusive at every call site" is not monotone. Its
dual, "shared at some call site", is. Compute the dual to its fixpoint,
freeze, read the complement. The same applies to every greatest
fixpoint (the identities of `idr-identity`, §2.1 row 9): compute the
least fixpoint of the negation. This is the LVars "freeze after
writing" discipline (`sources/papers/kuper-2014-freeze-after-writing`,
dfp §3), and it removes the one place where reading early would make
the answer depend on timing.

### 4.4 Identifiers in two phases

During fixpoints everything is named by content hash. After freeze,
each shard sorts its keys, an exclusive prefix sum over shard counts in
shard order gives offsets, and each shard numbers its keys locally:
Blelloch et al.'s scan labeling, equal to a serial numbering by key
order (`sources/papers/blelloch-2012-internally-deterministic`, dfp §3).
Hash collisions are checked by full equality at the owner. **No id from
an allocation counter, a thread, a bump pointer or an arrival order
reaches output bytes, symbol names, partitions or cache keys (D3).**
Zig's `InternPool`, whose indices carry the creating thread's id in
their high bits, is the counterexample to avoid (wpas §7).

### 4.5 Symbol names

Every generated name is the owner's name and a short hash of the
structural key it denotes (0004 D18, §4 stage 1), so names are stable
under unrelated edits, which is also what makes the cache hit (§6).
What sharding adds (*decision*): the hash has one fixed width; a
collision between two keys, found at freeze by full equality at the
key's owner (§4.4), widens both by one rule, so the widening is a
function of the key set and never of arrival. The frontend's repeats
`p'n` (`Emit/Index.idr:32-49`) become hashes of their keys too. ThinLTO's
renaming of promoted locals by module hash is the precedent
(codegen-partitioning §3); GCC's `name.lto_priv.N`, a per-name counter
(codegen-partitioning §2), is the counterexample.

## 5. The hard parts

### 5.1 The optimizer is a ready set, not a global fixpoint

0004's cutover replaces `idr-simplify`'s whole-module rounds with one
bottom-up ready set over call-graph SCCs: each function processed once,
after its callees are final, and specialization requests as
content-keyed nodes in the same ready set (0004 §4.6 to §4.8).
Defunctionalization runs before it and is total by analysis (0004 §2),
so nothing the optimizer does decides acceptance. The ready set is a
schedule over a DAG of nodes, deterministic by dataflow order: a body is
a function of its own body and its callees' final bodies, a callee is
read only once final, calls are inlined in call-site order, and dead
functions are erased afterwards, serially, in module order (0004 §4
stage 6; mojo §2, §5). So its result does not depend on which worker ran
which node, and the sharded form is the same ready set with more
workers. Two of its quantities would read an arrival order if left as
counts, and D11 and D5 make them functions of content:

- **The call count in the inline formula** (`(calls - 1) * (size - 60)
  <= 320`, 0004 §4.7). *Decision (D11):* `calls(f)` is the number of call
  sites of `f` outside its SCC plus those left inside its SCC once the
  SCC is processed. The first term is a frozen phase-2 fact: no caller
  outside the SCC runs before `f` is final (0004 §4.6's readiness rule,
  *read*), and nothing else adds or removes a call of `f` before then
  (*conjecture*, checked by 0004 L3's determinism at 1, 2 and 8 threads).
  The second is local to `f`'s unit. A specialization node counts one
  call per request: its requesters wait on it, so their number is not
  known when it is final, and any count read then is an arrival count.
  A clone therefore inlines into each requester until that requester's
  cap is reached, which is today's rule for a clone made for one call
  site (0004 §3.2, *read*) bounded by the cap.
- **The clone budget.** `kClonesPerOwner = 1024`
  (`include/idr/Analysis/Specialize.h:59`, checked at
  `Specialize/Clones.cpp:30-33`) counts clones as they are made, so
  under any parallel schedule which request is the 1025th depends on
  timing. *Decision (D5):* no budget counts arrivals. Every bound is a
  function of what it bounds: a key's pattern size, a callee's final
  size, a caller's own size. A key over its bound is not requested and
  its argument stays a runtime leaf, as the binding-time rule already
  makes every argument it does not allow (`Specialize/Keys.cpp:6-15`,
  *read*). The bound on a key's pattern size is recorded in 0004's lane
  L3 beside the caller cap (0004 open question 1); until then its
  default is `kUnrollLimit`'s 32 (`Specialize/Keys.cpp:38`).

A spent bound stops optimizing and never refuses a program (0004 §2.5,
D17). The refusals that remain are the frontend's (the instance bound,
the growing shapes, a second dictionary implementation), decided in
phase 2 in key order (D5): the round in which a definition passes 4096
instances is fixed by D2, and the refusal names the least key over the
bound. A clone is a GCC-style virtual clone, a descriptor (owner,
pattern key) that the owner's unit materializes (wpas §2), now made on
demand when its node is first requested.

### 5.2 Defunctionalization's sums ripple

Adding one lambda changes the closure sum at every apply site it
reaches. Sum constructors are ordered by their labels' content-derived
names (0004 D18 deletes `fn$<n>` by first appearance), so an added
lambda inserts one case, and only the units holding those applies change
slice (§6's early cutoff stops the rest). MLton's 0CFA over all of
MLton takes under 2 s (*measured*, Weeks 2006, slide 14,
`sources/papers/weeks-2006-mlton-whole-program`; mlton §2), and 0004
holds ours under 10 s on stage 0 with MLton's representation (0004
§2.8, D12). The analysis is not the cost; the ripple is, and the cache
prices it (S9).

### 5.3 Static normalization lives in phase 1

Static normalization runs in the frontend, on the type checker's
interpreter (0007 §7). For this design that means:

- normalization is per module, in phase 1, cached under the module's
  content hash with the rest of its summary;
- its budget counts steps and bytes (0007 D8), so its results and its
  over-budget calls are the same on every schedule;
- phases 2 to 4 never run program code: no evaluation service, no
  scratch modules, no fork, and MLIR threading stays on (D6).

### 5.4 Two worlds: the Idris half and the C++ half

The frontend, the elaborator, Translate and the frontend's facts are
Idris. The `idr` passes and LLVM are C++ (AGENTS.md: the dialect and its
passes are C++ in `foreign/idr`), and so are their whole-program parts:
the label solve, the SCC summaries, the grades, the layouts (D13).

**The C++ half (decision, D7):** one process, one `MLIRContext`, MLIR's
thread pool, as 0004 builds it; units are nested modules and functions,
each codegen unit with its own `LLVMContext`. Per-worker contexts or
processes, with units as bytecode, are S6, built only by §10's rule.
This supersedes the earlier "one `MLIRContext` per worker" from the
start: it re-uniques every type per worker at a memory cost nobody has
measured, against a contention nobody has measured, and 0004's one
context already runs every nested pipeline in parallel.

**The Idris half (§12's open question; default taken):** parallel by
processes the C++ driver starts, over the child-process boundary that
exists today (`lib/Driver/Compile.cpp:1-4`, *read*: "the frontend and the
link as child processes, the pipeline and LLVM in process"): one process
per Idris module for phase 1 and one per translation unit at S8, the
same at every stage of `make self`. Summaries and units cross as files:
0009's packed buffers and MLIR bytecode. The boundary is one bytecode
module after 0004 (its stage 1) and per-unit bytecode from S8, never one
text module.

The driver stays C++ (*decision*): the C++ side links MLIR and LLVM in
process, and an Idris driver would reach them only through a foreign
world, while the one foreign world planned is Rust (AGENTS.md, 0013).
This closes the earlier question whether the Idris half should drive
the C++ half.

### 5.5 Large read-only facts across workers

A worker shares no heap with another: 0005's shards have none, and
processes have none. A large frozen table copied to every worker is
serial work on the sender, and 0005's `lent` waits on its measurement
rule (0005 D10: built when detach walks exceed 5% of wall).
**Decision (D8):** ship slices, not tables. Each unit carries only its
fact slice, so no worker needs the whole fact base, and the global tables
stay sharded where they were computed. A phase that still needs a
broadcast is a measurement, and it names its cost before anything is
built for it.

## 6. Incremental builds and the cache

A build is a constructive-trace build system with early cutoff
(`sources/papers/mokhov-2018-build-systems`, wpas §6) at three levels:

| Level | Key | Cut off when |
| --- | --- | --- |
| summary | hash of the module's elaborated content (TTC) | its summary hash is unchanged |
| fact slice | hash of the unit's slice | the slice hash is unchanged (a projection firewall: a global fact changes, most slices do not) |
| object | hash of (toolchain version, target entry, unit content, sorted hashes of the final bodies it inlined, slice hash), `computeLTOCacheKey`'s recipe of sorted lists (wpas §1) | the object exists |

No compiler option enters a key, because no option changes output: 0004
deletes every behaviour-selecting option (D2 there), and `--num-threads`
changes no byte (0004 §6, Kept). This supersedes the earlier "options"
column.

*Decision (D15):* the store is a directory of content-addressed blobs
under the build directory, named by their hash, and an index that is one
sorted table from key to blob, written by the C++ driver. It is Mojo's
`Cache/` design rebuilt on `llvm/Support/xxhash.h` in about 200 lines,
as 0004 §8 plans (mojo §4: content-addressed blobs behind a chain of
backends, keyed by a 128-bit xxhash, whole-module only there). Neither
0012's core nor bumbledb holds the index: 0012 is parked and Idris-side,
and a shared cache over S3 would need a network client, which only
0013's Rust world could bring (parked). This closes the earlier open
choice.

The object level needs S2's second step: under one whole-module O3,
LLVM's interprocedural passes can change any unit's code on an edit to
any other, so an object is a function of its unit only once O3 runs per
unit (*decision*: S9 follows S2's second step).

An edit to one definition re-summarizes one module, re-runs phase 2
semi-naively on its delta, re-slices the units whose slices changed, and
recompiles only those. ThinLTO's numbers set the expectation: an edit to
one rarely called function took 25 s under ThinLTO against 17 min 11 s
under full LTO, on Chromium (*measured*, wpas §1). GCC 15's lesson sets
the precondition: partitions must not drift under small edits (D4), or
nothing hits (wpas §2).

## 7. Using 0003 and 0005 inside the compiler

**0005's rules, applied to the compiler's workers** (processes by §12's
default; the same rules hold for in-language shards if the owner
chooses them):

- Pure work is deterministic and equal to the sequential run (0005 D2),
  which D1 needs: a worker's output is a function of its input files.
- Messages are columnar or packed values (0009 D5), so summaries,
  deltas and slices cross as buffer copies.
- Load balance without a shared heap: **over-decompose** (one message
  per unit or relation shard, many more units than workers), send
  **longest first** (sizes from summaries; earlier build timings from the
  cache may order placement but never decide output), place by queue
  depth (0005 §5.2), and let idle workers take unstarted messages,
  0005's D9 item, built when idle time at the last join exceeds a tenth
  of workers × wall. Message-based stealing in GLB's style (split and
  merge bags, lifelines; `sources/papers/zhang-2013-glb`, dfp §2) is the
  next step only if D9 is not enough.
- A started unit never migrates (0005 §5.2); units are small enough
  that it does not matter.
- On the C++ side the thread pool already balances:
  `failableParallelForEach` hands out elements by an atomic index, and a
  worker that waits takes work (`M/include/mlir/IR/Threading.h:35-79`,
  upstream-mlir-llvm §3); the ready set's waits lend the worker through
  `llvm::ThreadPoolTaskGroup` (0004 §4.6).

**0003's arrays.** With 0008's tables, the frontend's data is ids and
words, which is what 0003's parallel lowering accepts (elements that
count nothing). The Idris side's array work:

- sorting and grading keys for canonical order; scan labeling for ids
  (§4.4);
- segmented reductions for sizes, use counts and per-site sharing;
- `accumulate` histograms for partition sizes; size-change composition
  as products in the `SizeChange` semiring, encoded as `i8`, its closure
  a relational fixpoint over the checker's triples, not a sum (0003 §11;
  0010 §2.7);
- forward-backward SCC with trimming and canonical pivots (Fleischer et
  al., dfp §5) for the data containment graph. The call graph's SCCs are
  C++, our deterministic Tarjan (`include/idr/Support/Scc.h`, 0004 §4
  stage 6).

All are integer or finite-semiring reductions, which 0003's D15 lets
split across workers, so nothing here waits on float reassociation.

## 8. What limits the speedup (the performance ceiling)

By Brent's bound, time on P workers is at most T1/P + T∞ (Blumofe and
Leiserson, dfp §2). The terms that do not shrink with P:

| Serial term | What bounds it | Remedy |
| --- | --- | --- |
| phase 2's reductions and barriers | rounds × barrier cost | few rounds (semi-naive; facts only grow) |
| the longest chain of the ready set | the depth of the SCC DAG, and the largest node: 24 functions in one SCC after six rounds, and 152k ops in one function at round 6 (*measured*, F0) | 0004's per-caller cap bounds a function at the cap plus one inlined callee (0004 §4.7); both are reported per build |
| the label solve and the other serial global parts | each part's wall in the post-cutover record | S3 to S5, each by its rule (§10) |
| the link | linker parallelism | lld (*measured*: clang's debug link 104 s with GNU ld, 5.3 s with lld, wpas §5) |
| summary I/O | GCC's WPA was mostly type and declaration streaming (wpas §2) | flat columnar summaries, read as buffers |

This supersedes the earlier row "codegen units split the largest
simplify unit": 0004's bins never split an SCC.

Targets (*decision*; earlier conjectures, now thresholds the
post-cutover record is judged against):

- phase 2 at most **5% of one-worker wall**: by Amdahl that caps 8
  workers at 5.9×, the figure 0005 D10 uses for lending;
- cold self-compile at 8 workers at least **0.6 × 8** faster than at
  one;
- at one worker and one thread, **no slower** than 0004's pipeline
  beyond the run-to-run spread (0005's rule: single-thread performance
  wins the tie);
- a no-op rebuild compiles **zero** units; a one-definition edit
  recompiles only the units whose slices changed.

A target the record shows out of reach is reported with its measured
serial share; it is never lowered quietly.

## 9. Rules it keeps

- **Whole program, always** (AGENTS.md): every guarantee is still
  decided on the whole program; only the work is split.
- **Determinism:** byte-identical outputs for every shard count, worker
  count and schedule (D1). `tests/lib/determinism.sh`, which today
  compares two compilations and one thread against the pool, gains
  worker counts 1, 2 and 8 (0004 §4) and, at S8, process counts 1, 2 and
  8 for the Idris half. There is no schedule-perturbing mode: a mode is
  an option, and the compiler has none (0004 D2); schedules already vary
  from run to run, and `--num-threads` is the one knob (0004 §6, Kept).
  This supersedes the earlier "randomized placement and message delays".
- **Static linking, both targets, no new runtime library:** no OpenMP,
  TBB or async runtime; processes on the Idris side, LLVM's thread pool
  on the C++ side.
- **Reject with a named rule:** refusals are decided in phase 2 in key
  order, so a refusal names the same cause on every schedule (D5).
- **Single-thread performance wins the tie** (§8's third target). This
  replaces the earlier "Pi Zero" line, which named a machine that is no
  target of this compiler (the two target entries are x86_64 Linux and
  arm64 macOS, `CMakeLists.txt`); the rule it stood for is the
  one-worker target.
- **One representation:** no fact is held twice. The serial pipeline is
  the sharded one with one worker; there is no second path.

## 10. Staged plan, each stage with its proof

Every proof compares binaries: the commit before the stage against the
commit after, from a named saved module, as 0004 §10 measures (D12). No
stage keeps a differential mode or the replaced form in the binary.

| Stage | Content | When | Proof |
| --- | --- | --- | --- |
| S0 | measure, in two records: F0 (`bench/profiles/2026-10-14-f0-stage0.md`, before the cutover), and the post-cutover record of 0004 §10, which splits each stage's wall into its whole-program and per-unit parts and gives LLVM's share at stage-0 scale for the first time | F0 taken; the second with 0004's integration | both committed; the second fires the rules of S3 to S6 |
| S1 | content names (taken by 0004: D18, lanes L1 to L3) | the cutover | corpus outputs unchanged (0004 L1); names stable under an unrelated edit: a fixture that edits one definition and checks every other symbol unchanged, carried by 0004's L8 |
| S2 | split code generation in 0004 §5.4's two steps: first, whole-module O3, then codegen per bin (0004 L7); then O3 per bin, with the whole-program facts as attributes on cross-unit declarations | the first with the cutover; the second next after it (0004 §10) | executables byte-identical at 1, 2 and 8 threads, bench compile times recorded (0004 L7); at the second step also the bench runtime within 2% of the first step's (0004 §10), which prices whole-module LLVM optimization |
| S3 | the cheap global parts in parallel: closed world, constants, effects and identities, layouts, the type graph, contification's analysis, the tail-call plan | when the post-cutover record shows them together above 5% of one-worker wall | the compiled module byte-identical to the previous binary's on the corpus and stage 0 |
| S4 | the label solve sharded, in C++ by §4's recipe | when the post-cutover record shows it above 5% of wall; *conjecture*: never, since 0004 holds it under 10 s against an optimizer segment under 600 s | the sums and the module byte-identical to the previous binary's |
| S5 | exclusivity and borrow grades as monotone duals (§4.3) | by S3's rule, for these facts | `idr-demand`'s verdicts and the module byte-identical |
| S6 | the C++ half on per-worker contexts or processes, units as bytecode | when the post-cutover record shows the one context's shared state (the uniquer, the serial `am.nest` of each nested pipeline, `M/lib/Pass/Pass.cpp:950-977`) above 5% of wall | byte-identical at 1, 2 and 8 workers; memory per worker recorded |
| S7 | MLIR threading over nested pipelines (done by the 0002 cutover) and the ready set drained by the thread pool (taken by 0004's L3) | done and the cutover | `tests/determinism` across thread counts (0004 §4) |
| S8 | the Idris half in parallel: phase 1 one process per module, Translate per unit emitting per-unit bytecode, 0008's Translate fixpoint sharded by §4 | after 0003's stage 1 and 0008's O3 | determinism across process counts 1, 2 and 8; phase 1 and frontend-fact speedups recorded |
| S9 | the persistent cache and early cutoff at three levels (§6) | after S2's second step | a no-op rebuild compiles zero units; a one-definition edit recompiles only changed slices |
| S10 | balance: longest-first placement; D9's measurement on the compiler's own run; GLB-style stealing only if D9's rule fires and it is still not enough | with S8 | idle time at the last join below a tenth of workers × wall |

## 11. Rejected alternatives

- **Separate compilation with interface files** (GHC, Swift's
  primary-file mode): it loses the instance set, the closure sums and
  the every-caller fact, so it loses the guarantees.
- **One module, MLIR threading only, as the end state:** every rewrite
  already threads under nested pipelines (S7). The whole-program parts
  that 0004 leaves serial, LLVM's one module before S2 and the frontend
  stay serial on one module; S2, S3 to S6 and S8 are what spread them.
- **Work stealing over a shared heap:** 0005 rejects it ("every count
  becomes atomic, tagged or traced").
- **Asynchronous fixpoints:** same result, schedule-dependent round
  counts (D2).
- **An outer delta loop between phase 2 and the optimizer:**
  superseded by demand-driven nodes; it would process a requester before
  its clone exists and again after, against 0004's "each function
  processed once" (D10).
- **Budgets counted in arrival order,** including `kClonesPerOwner` as
  a count and a clone's requester count: schedule-dependent output (D5,
  D11).
- **Ids by allocation or arrival order,** including per-thread
  interning (Zig's), randomized partitioners (METIS unseeded, dfp §7),
  and timing-based heuristics in any decision.
- **Trusting hash equality:** collisions are checked by full equality
  at the owner.
- **Shipping whole fact tables to every unit:** slices instead (D8).
- **A partition that depends on the shard or thread count:** objects
  would differ per P (D4), as LTO's do with N = threads
  (codegen-partitioning §1).
- **LLVM's summary-based importer across units:** a second inlining
  analysis beside ours, which the one-representation rule forbids (0004
  D21).
- **The C++ facts on 0012's Idris core** (the earlier S4, "0CFA on
  0012"): it would move a dialect analysis out of `foreign/idr`, against
  AGENTS.md's division of the work, and hold the label flow in two
  languages (D13).
- **A differential mode, or the replaced module pass kept for
  comparison:** two paths in one binary (0004 D2, §3.3); a comparison is
  two binaries (D12).
- **Per-worker `MLIRContext`s before a measurement asks for them**
  (D7).
- **A schedule-perturbing mode in the compiler:** an option (0004 D2).

## 12. Open question, with the default taken

1. **The compiler's Idris half on 0005's shards.** `make self`'s stage 0
   runs the frontend on Chez (`tools/self.sh:13-14`). `libs/mlir-shard`'s
   operations are runtime primitives of the registry with no Idris body
   (0005 §7.1), as 0003 D19 makes `Linear.Array`'s, and AGENTS.md forbids
   shaping a feature so that Chez can run it. So the frontend's own
   source cannot call them while stage 0 runs it, and 0003's stage 1
   meets the same question for the fork's `Table` on `Linear.Vec`.
   **Default:** the Idris half is parallel by processes (§5.4), the same
   at every stage, and in-language shards serve user programs only. The
   owner may instead decide that registry primitives get a meaning on
   the Chez host for stage 0, which AGENTS.md would then have to allow;
   S8 would then use 0005's shards with the same rules (§7).

Closed since the earlier text: the hash (D16), memory per C++ worker
(D7 and S6's rule), the largest SCC (24 of 28,276 after six rounds, F0;
units follow SCCs), where the cache index lives (D15), and whether the
Idris half drives the C++ half (§5.4: no).

## 13. Decisions

- D1. Byte-identical output for every shard count, worker count and
  schedule; the serial pipeline is the sharded one with one worker.
- D2. Global fixpoints are bulk-synchronous semi-naive rounds; only
  frozen results are read.
- D3. No schedule-dependent id reaches output, names, partitions or
  keys; ids are content hashes, then scan labels after freeze.
- D4. Partitions are a pure, edit-stable function of content,
  independent of P: optimizer units are 0004's SCC nodes, codegen units
  0004's bins (its D20), each named by the hash of its members' sorted
  content names.
- D5. No budget counts arrivals: every bound is a function of what it
  bounds (a key's pattern size, a callee's final size, a caller's own
  size); a spent bound stops optimizing and never refuses (0004 D17).
  The frontend's refusals are decided in phase 2 in key order, naming
  the least key over the bound.
- D6. Static normalization (total code only, 0007 D1) runs in phase 1;
  phases 2 to 4 never run program code.
- D7. The C++ half runs in one process, one `MLIRContext` and MLIR's
  thread pool, each codegen unit with its own `LLVMContext`; per-worker
  contexts only by S6's rule.
- D8. Units carry fact slices, never whole tables.
- D9. Balance by over-decomposition, longest first and queue-depth
  placement; stealing only by 0005's measured rules.
- D10. Specialization requests are messages to their key's node in the
  ready set (0004 D15); there is no outer delta loop, and the optimizer
  never requests a frontend instance.
- D11. `calls(f)` in the inline formula is its call sites outside its
  SCC (frozen, from phase 2) plus those inside its SCC after the SCC is
  processed; a specialization node counts one call per request.
- D12. Every stage is proved binary against binary from a saved module;
  no differential mode, no kept module pass.
- D13. Whole-program facts are computed on the side that owns them: the
  frontend's in Idris, the dialect's in C++ in `foreign/idr`; 0012
  serves the Idris side only.
- D14. Determinism is checked across worker and process counts 1, 2 and
  8; there is no schedule-perturbing mode.
- D15. The cache is content-addressed blobs and one sorted index under
  the build directory, written by the C++ driver; the object level waits
  for S2's second step.
- D16. The C++ side hashes with LLVM's xxh3 at 128 bits
  (`L/include/llvm/Support/xxhash.h:58-70`); the Idris side's content
  hashes are the function 0004's lane L1 takes for content names, also
  128 bits. Their values never meet, so they need not be one function.
  Collisions are checked by full equality (§4.4), so no cryptographic
  hash is needed; BLAKE3 through 0013 is rejected with it.
