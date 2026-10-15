# 0006: a sharded whole-program compiler

**Status:** proposed 2026-10-10; reprioritized 2026-10-12; reconciled
2026-10-14 with 0004's pipeline cutover, which it consumes unchanged,
and with 0005. Design only: every question is decided but one, which
needs the owner (§12). Built so far, by the 0002 cutover and 0004's
first compile-time round: MLIR threading on, every rewrite a function
pass under a nested pass manager (0002 D3), deduplication by content,
IntRange per function, RemoveDeadValues once at the fixpoint, labels in
one walk (0004 §3.1). The cutover 0002 designed is committed and builds
on arm64 macOS: `make build` clean, `make check` 27/27, `make test-idr`
286/286, `make test` 415/415 (*measured* 2026-10-14 at `NCPU=6`, at
552d682a and its file-size split df5d8742, on the rounds, the default).
The opt-in SCC pipeline of 552d682a ran in one lit test only, and 0004
deletes it (§3.3 there). x86_64 Linux has not run this tree: 0002's G1
is NotRun there.

0004 is the pipeline this proposal shards. Its stages are this
proposal's stages, its per-function passes and ready-set nodes are this
proposal's units of work, its codegen bins are this proposal's codegen
units, and its determinism rules are D1 with the thread pool as the
schedule (0004 §4, §9). 0004's cutover takes three stages of this
proposal: S0's first record (F0), S1 (content names, 0004 D18) and S2's
first step (code generation split after one whole-module O3, 0004 lane
L7). S2's second step, the split before O3, follows the cutover in
0004's order (§10 there). What remains here is the sharded form of the
same pipeline: the whole-program parts sharded where the post-cutover
record shows them serial, the compiler's Idris half in parallel, and a
persistent cache with early cutoff. It follows 0003's stage 1, which
follows `make self` (proposals/README.md). S3 to S6 are each taken by
the measurement rule §10 names, judged on S0's second record; S9
follows S2's second step; S8 and S10 wait on 0008's O3, which takes
0012 out of parking and needs its R1 and R2 first (0008's status and
D12; 0012 §0). No C++ stage waits on 0012 (D13). Four rules this
proposal decided are run by 0004's cutover itself, so 0004 states them
and they are recorded here as taken: D5 (0004 D39), D11 (0004 §4 stage
7, D14), D16 (0004 §4 stage 1, D18) and D20 (0004 §4 stage 6, D47).
This is a cutover: when a stage lands, the form it
replaces is deleted in the same change, never kept beside it (0004 D2).

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
3de67510 on 2026-10-14 and re-read at ccaba89c, where it is unchanged;
paths are under `foreign/idr/` unless named.
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

- **Guarantee facts:** the instance set and the refusal of an unbounded
  one, dictionary uniqueness, closure sums, exclusivity and borrows, layouts, the
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
it to a bench runtime within 2%. Coroutine elision across units is one
instance of the loss, and 0005 D11 records its count beside the bench.

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
  (`compiler/src/IdrisMLIR/Emit.idr:61-62`), which the driver reads with
  `parseSourceFile` (`Run.cpp:264`), which already takes bytecode too.
  0004 makes the handoff bytecode; the work is the frontend's writer
  (0004 §4 stage 1). Per-unit bytecode is S8's.
- A frontend symbol is its instance key printed, origin then arguments.
  Keys that print alike get repeats `p'n` in the program's order
  (`compiler/src/IdrisMLIR/Emit/Index.idr:32-49`), and derived functions
  are `<parent>.<kind><n>` (`lib/Transforms/Isolate/Isolate.cpp:124-125`;
  `lib/Transforms/Specialize/Clones.cpp:40-41`), with closure and memo
  sums `fn$<n>` and `lazy$<n>` by first appearance
  (`lib/Transforms/Defunctionalize/Decide.cpp:186-198`). Counts are
  stable under an edit elsewhere, not under an edit in the parent. 0004
  derives every generated name from content (its D18), and the repeats
  go with the counters: an instance's symbol is its key printed,
  followed by the low 64 bits of its identity hash where the print
  drops part of the identity, a rule of the key alone, so no key's
  symbol depends on another key (0008 §4.10, D7). That is S1.
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
this table adds where the sharded form puts each part, and a home for
the facts 0004 leaves without one, D19 and D20):

| 0004 stage | Whole-program part (phase 2: decided once, read frozen) | Per-unit part (phase 3) |
| --- | --- | --- |
| 1, reachability and monomorphisation (`compiler/src/IdrisMLIR/Frontend/Translate/Instances.idr`) | the instance set from the root; the refusals of a megamorphic construct, today `checkRecursion` (`Translate/Recursion.idr:130-165`) and `growing` (`Instances.idr:68-93`), with the instance budget until 0011's feature 2 replaces all three with its request-chain rule (0011 D4; 0004 D40), as filters on each round's delta (0008 §4.8, D3), the least rejected key reported (D5) | translating each instance's body; emitting closures and suspensions in symbol form with names from content (0004 §4 stage 1) |
| 1, dictionary fields (`Translate/Dictionaries.idr`) | the one implementation per field over all construction sites: a monotone set, two after freeze a refusal (`Dictionaries.idr:136-154`) | none: the late-site restart (`Translate/Programs.idr:126-136`) disappears, since facts only grow (0011 D6) |
| 1, box or unboxed (`Translate/Programs.idr:138-157`) | SCCs of the data containment graph | none |
| 2, closed-world verification | one public root of the two root types (`lib/IR/Verify/Program.cpp:25-40`), no external `idr.func` (0004 D7); the type graph without a knot or an unboxed cycle (`Verify/Program.cpp:92-100`, `Verify/Knots.cpp:3-10`) | every closure- or lazy-typed operand on an op with the flow interface (0004 D8); quantities, linearity and the stage read from types (0004 D19), each op's own verifier, re-run per unit after every pass |
| 3, deduplication | classes by content, merged bottom-up so that merging is transitive, the lexicographically smallest member kept (0004 §4 stage 3; mojo §4) | hashing each body; renaming call sites to representatives |
| 4, defunctionalization | the label solve in MLton's representation, under 10 s on stage 0 (0004 §2.8); one sum per label set, constructors in label-name order (§5.2); the first effects summary, over the call graph in which an apply calls every label of its key (0004 D34); at 0005's P4, the send check over the decided sums (0005 §7.3) | the conversion, per function (0004 §2.7) |
| 5, contification | MLton's dominator analysis over the call graph (0004 §4 stage 5) | the rewrite into the caller |
| 6 to 8, the optimizer | the call graph's SCCs; each function's call count, frozen when the optimizer starts (D11); nothing else is decided up front, and each SCC's binding times are computed from its own bodies when it is ready (D20) | the ready set: decisions at each callee's finality, `mlir::inlineCall`, the inner pipeline once, the bounded local loop, specialization nodes (0004 §4.6 to §4.8) |
| 9, constants, effects and identities | bottom-up SCC summaries, callee first, applied through upstream's `visitExternalCall` (0004 §4.9; upstream-mlir-llvm §4) | each function's solve with interprocedural mode off |
| 10, dead values | RemoveDeadValues and SymbolDCE once (0004 §4.10); their liveness a least fixpoint, sharded by §4 only by S3's rule (D19) | none |
| 10a, the arrays stage, from 0003's stage 1 (0003 §7, D26) | One-Shot's module analysis, whole-program and serial upstream (0003 §7); the columns choice for collections that are not arrays, right before the stage (0009 D12) | structuring, fusion, the schedules and the clean, per function |
| 11, memory and loops (`idr-stack`, `idr-accumulate`, `idr-rc`, `idr-demand`, `idr-trmc`, `idr-tail-loops`, `idr-narrow`) | escape summaries; exclusivity as the complement of "shared somewhere" (§4.3) and borrow grades, each function's grade contexts as a key set (0004 §4 stage 11); `idr-demand`'s verdicts on the in-place type fact; ranges | placement and commit of counts (already nested, `lib/Transforms/Ownership/Rc.cpp:66, 101`); the rewrites |
| 12, lowering | layouts, every cell header once; the runtime's declarations from the decided set; the tail-call cycle plan of `idr-tail-calls` (`Pipeline.cpp:172`, `include/idr/Conversion/TailCallPlan.h`), one module plan (0004 §4 stage 12) | the conversion, per function |
| 13, LLVM | at S2's first step: translation, the runtime linked in, internalization and one O3, whole (0004 §4 stage 13); at its second, the facts LLVM would lose across units, written as attributes on cross-unit declarations (0004 §5.4) | at the second step: the lowering tail, translation and O3, per codegen unit, each in its own `MLIRContext` and `LLVMContext` (0004 D30) |
| 14, partitioning | the bins (§3.4), every `musttail` caller joined to its callee (0004 §5.3 item 4, D33) | none |
| 15, code generation | none | each bin in its own `LLVMContext` and `TargetMachine` (0004 §5.4) |
| 16, link | the order: bin names (D4) | none |

Every per-unit part not named above runs per function, the unit of
MLIR's nested pass managers (0004 §4). What idr-round-facts computes
today for the round's function step (`Simplify/RoundFacts.cpp:39-43`:
the symbol table, `Holds`, `Identities`, `CloneTable`, `BindingTimes`)
gets one home each (*decision*, D20, taken by 0004's cutover as its
§4 stage 6 and D47): `Holds`, two bits per declaration
over the type graph (`include/idr/Analysis/Holds.h:3-6`), is a type fact
frozen in phase 2; `Identities`, a greatest fixpoint over the module
today (`include/idr/Analysis/Identities.h:3-12`), is a stage-9 summary
whose greatest fixpoint is taken inside each SCC; `BindingTimes`, a
property of each parameter over the references from its cycles
(`include/idr/Analysis/Specialize.h:106-120`), is computed per SCC from
that SCC's own bodies when it is ready; `CloneTable` goes with the
key-named nodes (0004 §6); the symbol table is the ready set's driver's,
a module pass (0004 §4.6). Reason: RoundFacts exists only because a
nested pass manager drops module analyses (upstream-mlir-llvm §3), and
each fact then has exactly the scope it quantifies over.

`idr-in-bounds` and `idr-vectorize` are gone before sharding starts:
0003's stage 1 deletes them (0003 §15), and what replaces them carries
its facts in types (0003 §2). This supersedes the earlier row that
computed in-bounds length relations in phase 2. The 4096-instance count
(`Instances.idr:33-39, 110-112`), which reports `unsupported
(compile-time budget)` (`IdrisMLIR/Rule.idr:37, 69`), survives 0004's
cutover (0004 D40) and is gone once 0011's feature 2 lands (0011 D4);
if 0008's O3 lands first it carries the count unchanged as a check on
the delta (0008 D3), and S8 shards it with the other refusals. This
supersedes the earlier row that decided that count in phase 2.

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
                 [13 LLVM, whole: translate, link the runtime, O3]
                                   ▼
                 [14 partition into bins of SCCs, 0004 §5.3]
                                   ▼
                 [15 per bin: codegen]
                                   ▼
                 [16 link in bin-name order]
```

That is S2's first step. At its second, stage 14 moves before stage 13:
the bins are cut on the lowered MLIR module, and each bin's lowering
tail, translation, O3 and codegen run in contexts of its own (0004
§5.4, D30).

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
semi-naive fixpoint over the instance table (0008 D3), on 0012's core,
where 0008's O3 builds it (0008's status). The C++ facts are computed
by C++ drivers over plain summaries on MLIR's thread pool: bulk-synchronous rounds
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
§3) applied at the unit level. The C++ side runs it in one process, on
MLIR's thread pool (D7). Every stage up to lowering runs in one
`MLIRContext`, its units functions under nested pass managers and the
ready set's nodes. Each codegen unit gets contexts of its own: at S2's
first step an `llvm::LLVMContext` and `TargetMachine` into which its
definitions are read lazily from the optimized module's bitcode (0004
§5.4; the pattern of `L/lib/LTO/LTOBackend.cpp:517-570`); at the second
step a nested `builtin.module` whose lowering tail runs under
`pm.nest<ModuleOp>()`, written as bytecode and translated and optimized
in an `MLIRContext` and `LLVMContext` of its own (0004 D30).

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
  meets a boundary condition, between B/4 and 2B; the bin count a
  function of size, never of threads; a function too large for a bin a
  unit of its own; an SCC never split, and a `musttail` caller never
  apart from its callee. B is 2^15 = 32,768 LLVM instructions counted
  on the optimized module at S2's first step, and the same constant
  counted in ops of the lowered MLIR module at its second (0004 §5.3
  item 1, D26). The runtime's definitions, whose names are C
  identifiers with no dot, their own mangling
  (`include/idr/Conversion/Mangle.h:15-20`), fall into one namespace
  group by the same rule, so they need no rule of their own.

**Decision (D4):** partitioning is a pure function of content,
independent of the shard and thread counts, and stable under small
edits. A bin is named by the hash of its members' sorted content names,
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
other symbol is internal; objects are linked in bin-name order.
Whole-program internalization survives as a fact (one public root, 0004
D7), applied per unit as hidden visibility.

The runtime is linked as today at S2's first step, into the one module
before O3 (`Run.cpp:184-192`; 0004 §5.3 item 3): when the prepared
runtime's native half runs on the program's CPU its bodies join as
`available_externally`, so O3 inlines what pays and the rest resolves
to the native half at the link, where every piece of runtime state has
its one definition (`include/idr/Driver/Runtime.h:67-76`); otherwise
each body the program reaches becomes a definition compiled with it.
The partition places definitions only, so an `available_externally`
body left after O3, which code generation drops, is a declaration to
every bin. At the second step each unit links the same
`available_externally` bodies before its own O3, by the same
`LinkOnlyNeeded` link (`lib/Driver/LinkRuntime.cpp:130-145`), and in the
definitions case the reached bodies are also defined once, in the
runtime's namespace group of §3.4 (*decision*: the second step keeps
today's two cases and adds no third).

Identical bodies are folded at three levels, each where they first
become visible: `idr` deduplication by content before
defunctionalization (stage 3), MergeFunctions in O3 (`Optimize.cpp:50`;
whole-module at S2's first step, per unit at its second), and
`--icf=all` across objects at the link, already on with function
sections (`CMakeLists.txt:174, 213`; `Optimize.cpp:30`), which matters
from the second step (0004 §5.3 item 3). None holds a fact another
holds: each folds what the level before could not see. This supersedes
the earlier "folded in phase 2, replacing MergeFunctions across units".

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
fixpoint that stays global: compute the least fixpoint of the negation.
The identities of `idr-identity`, a greatest fixpoint over the module
today, do not stay global: each SCC takes its own inside its node,
callees' identities read frozen (D20). This is the LVars "freeze after
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

Every generated name is the owner's name and a hash of the structural
key it denotes (0004 D18, §4 stage 1), so names are stable under
unrelated edits, which is also what makes the cache hit (§6). An
instance's symbol is its key printed, followed by its identity hash
where the print drops part of the identity, so the frontend's repeats
`p'n` (`Emit/Index.idr:21-60`) go and no symbol depends on another key
(0008 §4.10, D7). What sharding needs (*decision*, D16, taken by 0004's
cutover as its §4 stage 1 and D18): the hash has one fixed width, the low 64 bits
of the key's 128-bit content hash, written as 16 hex digits; two keys
whose names collide are caught where the name is interned, by full
equality of the keys (§4.4), and the collision is an internal error,
never a merge and never a widened name (0008 §4.10). Reason: names
collide only among one owner's generated functions, and if all of the
stage-0 module's 107,732 functions had one owner the chance of any
collision would be about n²/2^65 = 3·10^-10 (computed); a widening rule
would be a branch kept for that case, and it would make one key's name
depend on another key. This supersedes the earlier widening rule.
ThinLTO's renaming of promoted locals by a 64-bit module hash is the
precedent (codegen-partitioning §3); GCC's `name.lto_priv.N`, a
per-name counter (codegen-partitioning §2), is the counterexample.

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
  <= 320`, 0004 §4.7). *Decision (D11, taken by 0004's cutover as its
  §4 stage 7 and D14):* `calls(f)` is the number of
  `f`'s call sites when the optimizer starts, a frozen phase-2 fact. No
  count inside an SCC is ever read: a function on a cycle, the only kind
  with a call site inside its own SCC, is never inlined (0004 §4.7). The
  frozen count is the count at `f`'s finality: no caller of `f` runs
  before `f` is final (0004 §4.6's readiness rule, *read*), and a node
  the optimizer creates before then is a clone of a function below `f`
  or in its SCC, so it calls `f` only if `f` is on a cycle
  (*conjecture*, checked by 0004 L3's determinism at 1, 2 and 8 threads).
  A specialization node counts one call per request: its requesters wait
  on it, so their number is not known when it is final, and any count
  read then is an arrival count. A clone therefore inlines into each
  requester until that requester's cap is reached, unless it is on a
  cycle, which is today's rule for a clone made for one call site (0004
  §3.2, *read*) bounded by the cap. This supersedes the earlier two-term
  count, whose second term only a function on a cycle could have.
- **The clone budget.** `kClonesPerOwner = 1024`
  (`include/idr/Analysis/Specialize.h:56-59`, spent at
  `Specialize/Clones.cpp:30-33`) is a budget that stops specializing and
  never refuses (0004 D39, §2.5): a finite set of static patterns can
  pass 1,024 in a large program, and specialization's termination rests
  on the binding-time rule (`Specialize/Keys.cpp:6-15`) and each key's
  node being made once. Counted per owner as requests arrive, which
  request is the 1,025th, and so which call stays unspecialized, would
  depend on which caller a worker ran first. *Decision (D5, taken by
  0004's cutover as its §4 stage 8 and D39):* no budget
  counts arrivals; every bound is a function of what it bounds. So the
  clone budget is counted per requesting node: the distinct keys one
  node requests of one owner, in its call-site order, an already-made
  key counted like a new one; a request past the 1,024th is not made,
  and its argument stays a runtime leaf, as the binding-time rule makes
  every argument it does not allow. A node's requests are a function of
  its own final body, so the budget is spent the same way on every
  schedule. It still bounds code size, with the per-caller cap (0004
  D25), and it still never refuses. This supersedes two earlier forms:
  a separate bound on a key's pattern size in place of the count, which
  would have held the binding-time rule twice and lost the bound 0004
  keeps; and the count read owner-wide, which 0004's earlier text
  implied and which a parallel ready set would read in arrival order.

A spent bound stops optimizing and never refuses a program (0004 §2.5,
D17). The refusals that remain are the frontend's: a megamorphic
recursion (`checkRecursion`, `growing`), a second dictionary
implementation, and, until 0011 D4 lands, the instance budget (0004
D40). Decided in phase 2 by D2's rounds, each names the least
key its round rejects, so it names the same site on every schedule
(D5). A clone is a GCC-style virtual clone, a descriptor (owner,
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

**The C++ half (decision, D7):** one process and MLIR's thread pool, as
0004 builds it. Every stage up to lowering runs in one `MLIRContext`,
its units functions and the ready set's nodes; each codegen unit has
contexts of its own, an `LLVMContext` at S2's first step and an
`MLIRContext` and `LLVMContext` at its second (0004 D30, §3.3). The
second step's per-unit `MLIRContext` exists because concurrent
translation of sibling modules on one context is neither documented nor
tested upstream (upstream-mlir-llvm §5), and a unit written as bytecode
and read into a context of its own needs no such promise. Per-worker
contexts or processes for the stages before lowering, with units as
bytecode, are S6, built only by §10's rule. This supersedes the earlier
"one `MLIRContext` per worker" from the start: it re-uniques every type
per worker at a memory cost nobody has measured, against a contention
nobody has measured, and 0004's one context already runs every nested
pipeline in parallel.

**The Idris half (§12's open question; default taken):** parallel by
processes the C++ driver starts, over the child-process boundary that
exists today (`lib/Driver/Compile.cpp:3-4`, *read*: "the frontend and the
link as child processes, the pipeline and LLVM in process"): one process
per Idris module for phase 1 and, at S8, worker processes that take
Translate's ranges longest first (§7, D18), the same at every stage of
`make self`. Summaries and units cross as files: 0009's columnar
relations, whose id columns the reader checks once against their
tables' extents (0009 D11), and MLIR bytecode; never packed buffers,
whose offsets would need a checking walk. The boundary is one bytecode
module after 0004 (its stage 1) and per-unit bytecode from S8, never one
text module.

**Translation units at S8** (*decision*, D18). The frozen instance set,
sorted by key, is cut into contiguous ranges of about 2^15 Core nodes
each, sized by the subtree sizes 0008's tables store (0008 D8), so the
count follows size and never the process count (D4). Each process
writes one bytecode file per range. The driver reads every file into
the one `MLIRContext` without verifying it alone
(`ParserConfig(context, verifyAfterParse = false)`,
`M/include/mlir/IR/AsmState.h:472-486`, since a unit names symbols other
units define), moves the top-level ops into one module, orders them by
symbol name and verifies the module once. So the module, and everything
after it, is the same for every cut and every process count, and the
cut needs no edit stability: no cache keys on it. A data type a unit
uses is written in that unit with its body, as 0004's identified types
carry it (0004 D29); identified types are uniqued by name in the
context, so the module holds each once, and two bodies under one name
fail, as they do for LLVM's identified structs, whose parser sets a body
only when it is the same (`M/lib/Dialect/LLVMIR/IR/LLVMTypeSyntax.cpp:
117-135`); for ours that failure is an internal error. The ranges are
Translate's, not the C++ side's units, which exist only after
defunctionalization (§3.4). The 2^15 is a *conjecture* (tens to hundreds
of ranges at stage 0); S8 records the ranges and each one's fixed cost,
and a miss changes the constant in one commit, as 0004 D26 does for
bins.

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
(`sources/papers/mokhov-2018-build-systems`, wpas §6) at four levels
(*decision*, D15):

| Level | Key | Cut off when |
| --- | --- | --- |
| summary | hash of the module's elaborated content (TTC) | its summary hash is unchanged |
| fact slice | hash of the unit's slice | the slice hash is unchanged (a projection firewall: a global fact changes, most slices do not) |
| node | hash of (the node's bodies as the whole-program stages left them, its slice hash, the sorted hashes of the final body and summary of every callee it reads) | its final body's hash is unchanged, so its callers' keys do not change |
| object | hash of (toolchain version, target entry, the bin's lowered members, the cross-unit declarations it reads, with their attributes), `computeLTOCacheKey`'s recipe of sorted lists (wpas §1) | the object exists |

The node level caches the optimizer, and its key is what a node's work
reads by 0004's rule: its own body and its callees' final bodies and
summaries (0004 §4.6, stage 9). The object level caches LLVM. This
supersedes the earlier object key, which mixed the two: it keyed a bin
on the final bodies its SCCs inlined, which a bin, cut after the
optimizer, already holds.

No compiler option enters a key, because no option changes output: 0004
deletes every behaviour-selecting option (D2 there), and `--num-threads`
changes no byte (0004 §6, Kept). This supersedes the earlier "options"
column.

**Locations stay outside every key** (*decision*, D17). Each level's
content is hashed with its source locations stripped, and the locations
are kept beside it, read only to name a refusal's site. Mojo keys its
cached transforms the same way, on bytecode with locations stripped "to
ensure determinism across different builds" (mojo §4). Reason: a line
added at the top of an Idris module moves every location after it, and
without the rule that one edit would miss every level below the
module's summary. It rests on a property of today's output that S9's
proof checks: no location reaches a program byte. Locations are only
builder locations in the lowering (`lib/Conversion/Checks.cpp:31-99`,
*read*), a missing case crashes with "unhandled input for" its owner's
name and no position (`compiler/src/IdrisMLIR/Frontend/Translate/
Cases.idr:95-96`, *read*), and the driver writes no debug information
(*conjecture*: `Run.cpp:143-202` sets none).

*Decision (D15):* the store is a directory of content-addressed blobs
under the build directory, named by their hash, and an index that is one
sorted table from key to blob, written by the C++ driver; the frontend's
summaries are blobs of the same store, which the driver hands to its
child processes by path. It is Mojo's
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
unit. The node level does not, but alone it would save the optimizer
while the whole-module O3 still ran on every edit (*decision*: S9
follows S2's second step and lands its four levels as one stage, with
one proof).

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
- Messages between the compiler's workers are columnar values (0009
  D5, D11), so summaries, deltas and slices cross as buffer copies, each
  id column checked once by the reader.
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
  a relational fixpoint with subsumption over the walks `loopsFrom`
  keeps, not a sum (0003 §11; 0010 §2.6, §2.7; 0012 D9);
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
| the longest chain of the ready set | the depth of the SCC DAG, and the largest node: 24 functions in one SCC after six rounds, and 152k ops in one function at round 6, both under the rounds (*measured*, F0) | 0004's per-caller cap keeps every function the optimizer inlines into at or under 10,000 ops, or at its emitted size when that is larger (0004 §4.7, D25); the depth and the largest node are reported per build |
| the label solve and the other serial global parts | each part's wall in S0's second record | S3 to S5, each by its rule (§10) |
| the link | linker parallelism | lld (*measured*: clang's debug link 104 s with GNU ld, 5.3 s with lld, wpas §5) |
| summary I/O | GCC's WPA was mostly type and declaration streaming (wpas §2) | flat columnar summaries, read as buffers |

This supersedes the earlier row "codegen units split the largest
simplify unit": 0004's bins never split an SCC.

Targets (*decision*; earlier conjectures, now thresholds S0's second
record and each later stage's record are judged against):

- phase 2 at most **5% of one-worker wall**: by Amdahl that caps 8
  workers at 5.9×, the figure 0005 D10 uses for lending;
- cold self-compile at 8 workers at least **0.6 × 8** faster than at
  one;
- at one worker and one thread, **no slower** than 0004's pipeline by
  more than 0004 §10's 5% compile-time margin, best of five, binary
  against binary (0005's rule: single-thread performance wins the tie;
  0003 D35 on why a run-to-run spread bounds nothing);
- a no-op rebuild compiles **zero** units; a one-definition edit
  recompiles only the nodes and bins whose keys changed (§6).

A target the record shows out of reach is reported with its measured
serial share; it is never lowered quietly.

## 9. Rules it keeps

- **Whole program, always** (AGENTS.md): every guarantee is still
  decided on the whole program; only the work is split.
- **Determinism:** byte-identical outputs for every shard count, worker
  count and schedule (D1). `tests/lib/determinism.sh`, which today
  compares two compilations and one thread against the pool, gains
  worker counts 1, 2 and 8 (0004 §4) and, at S8, process counts 1, 2 and
  8 for the Idris half. Its per-step dumps, taken today with
  `--dump-dir` (`tests/lib/determinism.sh:19`), move to upstream's
  `-mlir-print-ir-tree-dir` when 0004 deletes the option (0004 §6, lane
  L8). There is no schedule-perturbing mode: a mode is
  an option, and the compiler has none (0004 D2); schedules already vary
  from run to run, and `--num-threads` is the one knob (0004 §6, Kept).
  This supersedes the earlier "randomized placement and message delays".
- **Static linking, both targets, no new runtime library:** no OpenMP,
  TBB or async runtime; processes on the Idris side, LLVM's thread pool
  on the C++ side.
- **Reject with a named rule:** refusals are decided in phase 2 by D2's
  rounds, each naming the least key its round rejects, so a refusal
  names the same cause on every schedule (D5).
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
| S0 | measure, in two records: F0 (`bench/profiles/2026-10-14-f0-stage0.md`, before the cutover), and a record taken from the binary 0004's integration builds, on the post-contify stage-0 module and the bench, under 0004 §10's conditions: `-mlir-timing` per pass and LLVM's scopes (`translate`, `link runtime`, `optimize`, `codegen`, `Run.cpp:143-202`), each stage's wall split into its module-level steps and its per-unit work, the ready set's depth and largest node, and LLVM's share at stage-0 scale for the first time | F0 taken; the second with 0004's integration | both committed under `bench/profiles/`; the second fires the rules of S3 to S6 |
| S1 | content names (taken by 0004: D18, lanes L1 to L3 and L9): generated names from the key's hash at D16's width, instance symbols made injective by 0008 D7's suffix, a rule of the key alone (0008 §4.10) | the cutover | corpus outputs unchanged (0004 L1); names stable under an unrelated edit: a fixture that edits one definition and checks every other symbol unchanged, carried by 0004's L8 |
| S2 | split code generation in 0004 §5.4's two steps: first, the whole-module O3 kept and codegen split per bin, each bin materialized lazily from the optimized module's bitcode (0004 L7, D21); then the bins cut on the lowered MLIR module, each lowered, translated and optimized in contexts of its own, with the whole-program facts as attributes on cross-unit declarations (0004 D30) | the first with the cutover; the second next after it (0004 §10) | executables byte-identical at 1, 2 and 8 threads, bench compile times recorded (0004 L7); an edit fixture whose unrelated bins keep their members, and from the second step their bytes, since before it the whole-module O3 may change any bin (§6; 0004 D41); at the second step also the bench runtime within 2% of the first step's (0004 §10), which prices whole-module LLVM optimization |
| S3 | the cheap global parts in parallel: the closed-world module rule, the type graph and `Holds`, layouts, deduplication's classes, contification's analysis, the tail-call plan; liveness, a least fixpoint, sharded by §4's recipe in place of the one serial solve (D19); and One-Shot's module analysis in the arrays stage, judged on 0003 stage 1's record of that stage's wall (0003 §17) with the columns choice beside it (0009 D12). The summaries of 0004 stage 9 are not here: the ready set runs them in parallel from the cutover (S7) | for each part, when S0's second record shows it above 5% of one-worker wall, or the parts together above it | the compiled module byte-identical to the previous binary's on the corpus and stage 0 |
| S4 | the label solve sharded, in C++ by §4's recipe | when S0's second record shows it above 5% of one-worker wall; *conjecture*: never, since 0004 holds it under 10 s against an optimizer segment under 600 s | the sums and the module byte-identical to the previous binary's |
| S5 | exclusivity and borrow grades as monotone duals (§4.3) | by S3's rule, for these facts | `idr-demand`'s verdicts and the module byte-identical |
| S6 | the stages before lowering on per-worker contexts or processes, units as bytecode (codegen units have their own contexts from S2's second step, D7) | when S0's second record shows the one context's shared state (the uniquer, the serial `am.nest` of each nested pipeline, `M/lib/Pass/Pass.cpp:950-977`) above 5% of one-worker wall | byte-identical at 1, 2 and 8 workers; memory per worker recorded |
| S7 | MLIR threading over nested pipelines (done by the 0002 cutover) and the ready set drained by the thread pool (taken by 0004's L3) | done and the cutover | `tests/determinism` across thread counts (0004 §4) |
| S8 | the Idris half in parallel: phase 1 one process per module (elaboration is 0010's T7, processes first), 0008's Translate fixpoint sharded by §4, Translate per range writing per-unit bytecode that the driver merges in symbol order (D18) | after 0003's stage 1 and 0008's O3 (which needs 0012's R1 and R2) | determinism across process counts 1, 2 and 8; phase 1 and frontend-fact speedups recorded; the ranges' count and fixed cost recorded |
| S9 | the persistent cache and early cutoff at four levels, locations outside every key (§6, D15, D17) | after S2's second step | a no-op rebuild compiles zero units; a one-definition edit recompiles only the nodes and bins whose keys changed; a line added at the top of a module recompiles nothing below its summary and leaves every object byte unchanged |
| S10 | balance of the Idris half's processes: longest-first placement; D9's measurement on the compiler's own run; GLB-style stealing only if D9's rule fires and it is still not enough (the C++ side's pool already balances, §7) | with S8 | idle time at the last join below a tenth of workers × wall |

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
- **Budgets counted in arrival order,** including `kClonesPerOwner`
  read owner-wide as requests arrive and a clone's requester count:
  schedule-dependent output (D5, D11).
- **`kClonesPerOwner` as an assertion:** a large program can pass 1,024
  keys of one owner with a finite key set, and refusing it would make
  acceptance depend on program size (0004 D39).
- **A widening rule for colliding names:** a branch kept for a case of
  probability about 3·10^-10 on the stage-0 module, which would make one
  key's name depend on another key (§4.5, D16).
- **Source locations inside a cache key:** one added line would miss
  every level below the module's summary (D17).
- **Liveness per SCC:** argument liveness flows from callees and result
  liveness from callers, so a per-SCC order would need both directions
  and would be weaker than the one solve; liveness is a least fixpoint,
  sharded by §4's recipe instead (D19).
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
- **Per-worker `MLIRContext`s for the stages before lowering,** until a
  measurement asks for them (D7).
- **A Translate partition that reaches output:** the driver merges the
  units in symbol order, so the cut needs no edit stability and shares
  no rule with 0004's bins (D18).
- **A schedule-perturbing mode in the compiler:** an option (0004 D2).

## 12. Open question, with the defaults taken

1. **What a registry primitive means on the Chez host that runs stage
   0.** `make self`'s stage 0 runs the frontend on Chez
   (`tools/self.sh:13-14`), where a runtime primitive of ours has no
   meaning, and AGENTS.md forbids shaping a feature so that Chez can run
   it. The one fact has two consequences, so they are one question.
   - *The compiler's Idris half on 0005's shards.* `libs/mlir-shard`'s
     operations are runtime primitives of the registry with no Idris
     body (0005 §7.1, D13), so the frontend's own source cannot call
     them while stage 0 runs it. 0003's stage 1 does not meet the
     question: `LArray` has no primitive of its own, and the fork's
     `Table` moves onto base's `Data.IOArray` (0003 D37, D38).
     **Default:** the Idris half is parallel by processes (§5.4), the
     same at every stage, and in-language shards serve user programs
     only.
   - *0007's A3 folds.* From A3 the frontend's normalizer folds a
     primitive by calling `runtime/` (0007 §5), which stage 0 on Chez
     cannot do, and a fold computed with Chez's meaning (upstream/18
     records `"+inf.0"` against the runtime's `inf`) would land in
     stage 1, against AGENTS.md's rule that a primitive's one meaning is
     the runtime's. **Default:** from A3 on, `make self`'s stage 0 is
     the native frontend built from the last commit before A3; stock
     Idris on Chez builds only that commit's frontend, which then
     compiles the current source natively, so no fold ever runs on Chez
     and no host test enters the interpreter (0007 §7). Under this
     default, stage 0 no longer runs the current source on Chez after
     A3, so the first item's reason falls with it then; S8 may then use
     0005's shards by the same rules (§7), in a change that records it.
   The owner may instead decide that registry primitives get a meaning
   on the Chez host for stage 0, which AGENTS.md would then have to
   allow; S8 would then use 0005's shards with the same rules (§7), and
   A3 would fold on the host's meaning.

Closed since the earlier text: the hash and its width (D16, §4.5),
memory per C++ worker (D7 and S6's rule), the largest SCC (24 of 28,276
after six rounds, F0; units follow SCCs), where the cache index lives
and what it keys (D15, D17), whether the Idris half drives the C++ half
(§5.4: no), the bin size (0004 D26), the order the clone budget is
counted in (D5, under 0004 D39), Translate's units (D18), where 0004's
per-SCC liveness lives (D19), and where RoundFacts' facts go (D20).

## 13. Decisions

- D1. Byte-identical output for every shard count, worker count and
  schedule; the serial pipeline is the sharded one with one worker.
- D2. Global fixpoints are bulk-synchronous semi-naive rounds; only
  frozen results are read.
- D3. No schedule-dependent id reaches output, names, partitions or
  keys; ids are content hashes, then scan labels after freeze.
- D4. Partitions are a pure, edit-stable function of content,
  independent of P: optimizer units are 0004's SCC nodes, codegen units
  0004's bins (its D20, D26), each bin named by the hash of its members'
  sorted content names; objects link in bin-name order.
- D5. Taken by 0004's cutover (0004 D39, §4 stage 8): no budget counts
  arrivals; every bound is a function of what it
  bounds (a key's pattern under the binding-time rule, a callee's final
  size, a caller's own size, a node's own requests); a spent bound stops
  optimizing and never refuses (0004 D17). `kClonesPerOwner` (0004 D39)
  is counted per requesting node, over the distinct keys it requests of
  one owner in call-site order. The frontend's refusals are decided in
  phase 2 by D2's rounds, each naming the least key its round rejects.
- D6. Static normalization (total code only, 0007 D1) runs in phase 1;
  phases 2 to 4 never run program code.
- D7. The C++ half runs in one process on MLIR's thread pool. The
  stages up to lowering run in one `MLIRContext`; each codegen unit has
  an `LLVMContext` of its own at S2's first step and an `MLIRContext`
  and `LLVMContext` at its second (0004 D30). Per-worker contexts for
  the stages before lowering only by S6's rule.
- D8. Units carry fact slices, never whole tables.
- D9. Balance by over-decomposition, longest first and queue-depth
  placement; stealing only by 0005's measured rules.
- D10. Specialization requests are messages to their key's node in the
  ready set (0004 D15); there is no outer delta loop, and the optimizer
  never requests a frontend instance.
- D11. Taken by 0004's cutover (0004 §4 stage 7, D14): `calls(f)` in
  the inline formula is `f`'s call sites when the
  optimizer starts, frozen from phase 2; a function on a cycle is never
  inlined, so no count inside an SCC is read; a specialization node
  counts one call per request.
- D12. Every stage is proved binary against binary from a saved module;
  no differential mode, no kept module pass.
- D13. Whole-program facts are computed on the side that owns them: the
  frontend's in Idris, the dialect's in C++ in `foreign/idr`; 0012
  serves the Idris side only.
- D14. Determinism is checked across worker and process counts 1, 2 and
  8; there is no schedule-perturbing mode.
- D15. The cache is content-addressed blobs and one sorted index under
  the build directory, written by the C++ driver, at four levels:
  summary, fact slice, node and object (§6). It lands as one stage after
  S2's second step, which the object level needs.
- D16. Taken by 0004's cutover (0004 §4 stage 1, D18): one content
  hash, XXH3's 128-bit variant: LLVM's on the C++ side
  (`L/include/llvm/Support/xxhash.h:58-70`), and the same algorithm in
  plain Idris over `Bits64` on the frontend, which runs on Chez at stage
  0, where a runtime primitive has no meaning (§12). Reason: the two
  sides' values never meet, since each names and keys what it made, so
  the choice is one algorithm to specify and test rather than interop,
  and a published algorithm brings its test values, which the frontend's
  copy is checked against as committed expected values. A generated name
  carries the low 64 bits and a collision is an internal error (§4.5); a
  key carries all 128. Collisions are checked by full equality (§4.4),
  so no cryptographic hash is needed; BLAKE3 through 0013 is rejected
  with it. The frontend's hashing time on Chez is recorded at S1
  (*conjecture*: small, since it hashes keys, not bodies).
- D17. Every cache level hashes its content with source locations
  stripped and keeps the locations beside it, read only to name a
  refusal; no location reaches a program byte, which S9's proof checks.
- D18. At S8, Translate's units are the frozen instance set sorted by
  key and cut into ranges of about 2^15 Core nodes; the driver reads
  each unit's bytecode unverified, merges the top-level ops in symbol
  order and verifies the module once, so the cut never reaches output;
  its count follows size, as D4 asks, and D4's edit stability, which is
  for partitions that reach output, does not bind it.
- D19. Liveness, which 0004 runs once at the end of its optimizer, is a
  least fixpoint, so when S3's rule fires for it, it is sharded by §4's
  recipe (per-function transfer in parallel, cross-function edges as
  messages, bulk-synchronous rounds) and its frozen set equals the
  serial solve's; never a per-SCC approximation.
- D20. Taken by 0004's cutover (0004 §4 stage 6, §6, D47): what
  idr-round-facts computes gets one home each: `Holds` a type
  fact frozen in phase 2, `Identities` a stage-9 summary with its
  greatest fixpoint inside each SCC, `BindingTimes` per SCC from its own
  bodies when it is ready, `CloneTable` gone with the key-named nodes,
  the symbol table the ready set's driver's.
