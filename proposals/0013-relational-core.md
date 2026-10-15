# 0013: the relational core, `mlir-relational`

## 0. Status

**Parked** since 2026-10-12, in the queue the owner approved on
2026-10-14 (`proposals/README.md`); reconciled the same day with 0004's
pipeline cutover and decided throughout: there is no open question.
Nothing here is built. It is parked because nothing on the path to the
cutover, self-hosting or sharding needs it. Its first consumer is
0009's O3, Translate's instance fixpoint, which starts after `make self`
and 0008's A0; R1 and R2 are built before O3, which is R3 here (0009's
status and D12). It is taken up then.

The tree it would build on (*measured*, 0002 and 0004 §0): the cutover
0002 designed is committed and builds on arm64 macOS, where `make test`
was 415/415 at 7a27fd34, before the opt-in SCC pipeline, and again at
552d682a with it off by default; both runs took the Simplify rounds,
which 0004's cutover deletes together with that pipeline. x86_64 Linux
is NotRun (0002 §3). `make self` has never finished; 0004's cutover is
what it waits on.

It is the library 0011 D6 names and 0009 D12 builds on. On this side it
takes over §4.5 of bumbledb's port proposal
(`../bumbledb/proposals/0003-idris-port.md`, read at bumbledb
c0e7708a6; earlier drafts here cited it under its old number, 0002);
that file keeps what is about the database. Since 2026-10-12 its
fixed-plan joins and aggregates are 0003's sparse half (0003 §10, D22);
this proposal keeps what that subset cannot express (D5).

**What 0004 changes here.** The library is Idris, compiled by this
compiler, so 0004 changes how it is compiled and never what it is
(*decision*, each point below):
- a prepared query is specialized by 0004's ready set, on the plan as a
  known constructor, not by `idr-specialize`'s rounds (§3, D7);
- every closure in the library (a fold's step, a rule's body) is
  defunctionalized by 0004's total analysis, so the library needs no
  rule of its own for closures and no program of it is refused for one
  (0004 §2.4);
- every budget that bounds specialization stops it and never rejects
  (0004 §2.5, D17, D39), so whether a query compiles never depends on
  its plan's size;
- the C++ side's own fixpoints (the label solve, the SCC summaries, the
  ready set) are not consumers: whole-program facts are computed on the
  side that owns them, and this library serves the Idris side only
  (0007 D13; D6 here).

**Sources.** Under `sources/`: `papers/zhang-2022-relational-ematching`,
`papers/zhang-2023-egglog`, `papers/willsey-2021-egg`,
`papers/wu-2026-slotted-egraphs`, `papers/jordan-2016-souffle`,
`papers/gilray-2022-slog`, `papers/bik-2022-sparse-mlir`,
`papers/kjolstad-2017-taco`, `papers/lattner-2020-mlir`,
`papers/sun-2025-gpu-datalog` (whose bibliography holds Free Join's
abstract), `notes/sharded-compilation/deterministic-fixpoints.md`
(cited *dfp*), `docs/rustc-dev-guide`, `code/mlir`, `docs/mlir`; the
pinned MLIR tree, `.toolchain/llvm-project/mlir`. bumbledb's Rust engine
at `../bumbledb/crates/bumbledb` (read at c0e7708a6) is the reference
implementation. Paths in this tree were read at ccaba89c. Literature
that is not stored is marked *recalled*.

**Claims** are marked: *read*, *measured*, *recalled*, *conjecture*,
*decision*.

## 1. Why one library: the convergence

bumbledb (a database) and idris-mlir (a compiler) were started
separately and converged. This section records why, because the reason
is what justifies sharing one library rather than two similar ones.

### 1.1 Both are implementations of logic
- **A database is model theory.** bumbledb's laws are first-order
  sentences (a containment is "for every account there is a holder"); its
  judge checks a finite structure against them; a query is a formula
  whose answers are its satisfying assignments (Codd's relational
  calculus).
- **A type checker is proof theory.** Types are propositions; elaboration
  produces equations between terms and solves them by unification.
- **They meet in Prolog,** which is exactly unification plus resolution
  over relations. Datalog is that without function symbols, and is what
  a database becomes once it recurses. Hindley-Milner inference is
  constraint generation plus unification.

### 1.2 Removing accidental complexity leaves few shapes
Both projects run under the same rule (AGENTS.md "one thing, one
representation"; bumbledb's `docs/design/representation-first.md`, read).
Applied long enough, it strips what is accidental, and what is essential
is a short list: sets and relations, terms and trees, arrays, fixpoints,
and equivalence (union-find, rewriting, e-graphs). Two systems under the
same pressure reach the same attractors.

The field shows the same convergence:
- program analysis moved to Datalog: Soufflé (*read*
  `papers/jordan-2016-souffle`), Doop (*read* through dfp §5), bddbddb
  and CodeQL (*recalled*);
- rustc became a demand-driven query system (*read*
  `docs/rustc-dev-guide/src/query.md:1-7`), and its borrow checker was
  rewritten as Datalog (Polonius, *recalled*);
- egglog merged e-graphs and Datalog (*read*
  `papers/zhang-2023-egglog/abstract.tex`), and relational e-matching
  showed that e-matching is a worst-case optimal join (*read*
  `papers/zhang-2022-relational-ematching/intro.tex:92`);
- Slog runs abstract-machine analyses (k-CFA) and equality saturation as
  distributed Datalog (*read* `papers/gilray-2022-slog`, `sec-apps-aam.tex`,
  `sec-apps-eqsat.tex`);
- databases became compilers (HyPer, Umbra, LingoDB on MLIR,
  *recalled*).

### 1.3 Each project had a hole shaped like the other
Greenspun's rule, both ways:
- **bumbledb grew half a compiler** (*read*, under
  `../bumbledb/crates/bumbledb/src`): sealed witnesses are proofs built
  by hand (`ValidatedPlan`, "the sealed plan witness execution trusts",
  `plan/fj.rs:224-232`; `DistinctWitness`,
  `plan/fj/provably_distinct.rs:43`); scalar twins plus NEON
  (`exec/kernel/neon.rs`) plus runtime dispatch (`exec/kernel.rs:1-19`)
  are a vectorizer written out; the executor is an interpreter that
  wants to be compiled (`exec/run.rs`).
- **idris-mlir was about to grow half a database:** the fork's unifier
  and rewrite machinery, the termination closure (`loopsFrom`, a
  breadth-first walk that keeps only the weakest graphs,
  `compiler/idris/src/Core/Termination/SizeChange.idr:413-453`), the
  reachability walk (`checkReachable`,
  `compiler/src/IdrisMLIR/Frontend/Profile.idr:211`) and Translate's
  instance queue (`Frontend/Translate/State.idr:108-114`) are each an
  ad hoc relational engine with its own worklist (*read*).

### 1.4 Code is data
A database runs programs (queries) over data; a compiler is a program
over programs. Specializing a database's interpreter to a query is
compilation (the first Futamura projection); a compiler reasoning about
a program is a query over facts about it. The same machinery serves
both.

**The test of the convergence** is not how it reads but whether the
shared library makes every consumer smaller and faster: the gates in §6.
If they fail, the analogy was only pretty.

## 2. What the engine is

From bumbledb, without storage, laws and the log (*read*: its README and
`crates/bumbledb/src`):
- **Relations are sets,** held as immutable columnar images (structure of
  arrays). No nulls.
- **Joins are worst-case optimal.** For the triangle `R(a,b), S(b,c),
  T(a,c)` with N rows each, a binary plan can build N² intermediate rows;
  binding one variable at a time across all relations is bounded by
  N^1.5, the AGM bound (*read*
  `papers/zhang-2022-relational-ematching/background.tex:484-562`).
  Free Join (Wang, Willsey and Suciu, SIGMOD 2023; its abstract *read*
  in `papers/sun-2025-gpu-datalog/main.bib:280-291`) spans binary hash
  join to generic join with one plan type and one structure that unifies
  hash tables and tries; the planner picks a point.
- **Lazy tries (COLT)** index an image only as far as a join probes it;
  nodes live in index-addressed pools; a singleton child pins an image
  row instead of allocating a node (`Cursor = Node | Row`, *read*
  `exec/colt.rs:34-40`).
- **Kernels** for scans, compaction, folds, gathers and Allen masks
  (*read* `exec/kernel/`; the Allen filters at `allen.rs:82-140`).
- **The executor is an interpreter** over a validated plan: plan nodes,
  cursors, sinks.

## 3. The library, by layer

Each layer is built on the one below. No storage and no IO: the library
is the functional and array core, and the shell belongs to consumers.

1. **Relations and joins:** typed relations as columnar arrays (0010's
   columns), COLT, Free Join and the generic-join end, selections,
   anti-probes, exact folds and aggregates, the interval kernels with
   their Allen masks (which 0009's name resolution joins on, 0009
   §4.4), the planner, and the executor as an interpreter.
2. **Fixpoints:** semi-naive Datalog over layer 1, with delta relations
   so each round joins only what is new. Transitive closure,
   reachability and strongly connected components are queries in it.
   *Decision* (D9): a relation may be lattice-valued, with a merge that
   keeps one value per key, egglog's `:merge` (*read*
   `papers/zhang-2023-egglog/herbie.tex:79-80`; Flix's lattices,
   *recalled*). Subsumption is that merge over antichains: the
   size-change closure keeps, per function reached, only the weakest
   graphs of the walks to it (0009 §4.7), which a plain set would
   merge. Sharded, layer 2 runs in 0007 §4's bulk-synchronous rounds
   (D8).
3. **Equality saturation:** egglog-style e-graphs over layers 1 and 2
   (union-find, congruence rebuilding); e-matching as worst-case optimal
   joins, i.e. layer 1 again; binders through slotted e-graphs.

**Prepared queries are specialized, not compiled by a query compiler**
(*decision*, D7). A query known at compile time is a closed call of the
planner on a constant query, then a call of the interpreter on the
plan:
- The planner is total, so 0008's static normalization computes the plan
  in the frontend (0008 §2, A3). Within 0008's counted budget the plan is
  a constant, an `#idr.con` in an `idr.constant` (0008 §2).
- The interpreter's call on that constant has an argument that is a
  known constructor, so 0004's ready set makes it a specialization
  request keyed by (interpreter, plan), named from its key (0004 §4
  stage 8); 0008 §2 assigns this rule to the ready set, not to the
  frontend. Case of known constructor, in the inner per-function
  pipeline, removes the dispatch on plan nodes (0004 §4 stage 6), and
  each call on a sub-plan becomes a request of its own.
- `linalg` fusion merges each pipeline into one loop nest (0003 §7.2):
  the first Futamura projection.

Each step is optimization. `kClonesPerOwner`, `kUnrollLimit` and the
per-caller cap stop it (0004 §2.5, D17, D25, D39), and a plan past
0008's budget is a first-demand constant (0008 §2) on which nothing is
specialized. Either way the query runs the interpreter, specialized or
not, and means the same. Ad-hoc queries run the interpreter, which is
batched and vectorized. There is no JIT in a program: it would link
LLVM into every program, and it would compile a query a second way
(D10).

**Decision (D1):** the interpreter is written to be specialized. Only the
plan is static; COLT forcing, exact-versus-estimated key counts and the
cover chosen per node depend on data, so they stay dynamic, and the
interpreter separates them from the plan by construction (binding-time
separation, the fact 0004's specialization of static structure reads,
0004 §4 stage 8). A prepared query compiles at most 4 plan variants, the
planner's covers under different cardinality assumptions, and a guard on
the image statistics picks one at run time, Umbra-style (*read* bumbledb
0003 §4.4). The 4 is the library's own constant, a bound on code size
as 0004's budgets are: no query is refused for wanting more. A query
whose statistics leave every variant's range plans at run time and runs
the interpreter on that plan, the same function unspecialized (D10;
bumbledb's text falls back to a JIT there, which a program does not
have).

## 4. Consumers

Every consumer is Idris (D6). Each names the layers it uses and the
stage of its own proposal that builds on them.
- **The frontend (0009),** whose O3 is the first consumer (0009 D12):
  - O3: Translate as semi-naive evaluation over the instance table
    (layer 2), reachability as its query, the refusals as filters on
    the delta (0009's O3 row);
  - O5: name resolution as an Allen "during" interval join with a
    max-depth fold (layer 1; 0009 §4.4);
  - O7: the elaborator's constraint store and postponement as
    semi-naive evaluation (layer 2), meta-to-meta unification on layer
    3's union-find (0009's O7 row; 0011 §2.7);
  - O8: the compiler's invariants as law queries on every compilation,
    under 5% of the frontend's wall (layer 1; 0009 §5, D13);
  - the size-change closure as a fixpoint with subsumption (layer 2,
    D9), whose composition kernel is 0003's sparse semiring product
    (0003 §11; 0009's O6 row keeps the fork's `loopsFrom` until then).

  Not here, by the proposals that own them: the multiplicity check is
  0003's sparse reduction (0003 §11), and tabled instance search is not
  on this library, since its answers are ordered and the ambiguity rule
  counts them, which a set-valued fixpoint does not express (0011 §2.3,
  D6).
- **The elaborator (0011):** e-graph saturation over equalities is
  offered to tactics and returns a proof term the kernel checks; it never
  extends conversion (0011 §2.0, §2.7). Shape arithmetic is 0003's
  library tactic (0003 D11; 0011 §2.4), not this library's. This
  supersedes the earlier "so `n * m = m * n` never blocks a user", which
  would need saturation inside conversion.
- **The sharded compiler (0007):** its S8 shards the frontend's instance
  fixpoint through 0009's O3, as layer 2 in bulk-synchronous rounds
  (0007 §3.2, §4.2). Its C++ facts are plain C++ over summaries and use
  nothing of this library (0007 D13; 0007 rejects the earlier S4, "0CFA
  on 0013").
- **bumbledb's port:** the core plus storage, laws, the log and shards
  (bumbledb 0003 §4.5). Its storage reaches LMDB through 0014's bindings
  (bumbledb 0003 §3), so that consumer also waits on 0014, which is
  parked.
- **User programs:** graph queries, rule engines and analyses, with a
  Datalog and e-graph engine specialized and fused into them.
- **The compiler's own optimizer: withdrawn** (*decision*). The earlier
  conjecture ran equality saturation over `idr` IR in place of, or
  beside, the greedy rewrite driver (prior work running egglog over
  MLIR: DialEgg, CGO 2025, *recalled*). 0004 fixes the optimizer (one
  ready set, one canonicalization configuration run once per function,
  no dual path: 0004 §4 stage 6, D2), and the dialect's passes are C++
  in `foreign/idr` (AGENTS.md; 0007 D13), which an Idris library cannot
  be. Saturation in the C++ optimizer, if it is ever wanted, is a
  proposal against 0004's stage 6 that replaces its canonicalization
  whole, measured old binary against new (0004 D22); it is not a
  consumer of this library.

**Decision (D2):** a consumer may not keep its own copy of a mechanism the
library provides (0009 §9 rejects the frontend's own Datalog or
union-find; 0011 D6). The rule binds Idris consumers; the C++ side is
none (D6).

## 5. What MLIR already provides

The convergence is cheap because MLIR is the third project under the same
rule: an open set of ops and types instead of a fixed instruction set,
each concept at one level (*recalled*: `papers/lattner-2020-mlir`).
Inventory, each with its limit:

| Mechanism | What it gives the core | Limit |
| --- | --- | --- |
| `sparse_tensor` | A relation is a sparse tensor of `i8` with `explicitVal = 1`, coordinates only, which is a trie (`i1` is not a valid sparse element: *read*, `isValidPrimaryType`, `mlir/lib/Dialect/SparseTensor/IR/SparseTensorDialect.cpp:922-926`); a conjunctive query is an einsum (`Q[a,b,c] = R[a,b]·S[b,c]·T[a,c]`). Level formats (dense, compressed, singleton) are trie levels: CSR is a two-level trie, and COLT's row-pinning singleton child is the singleton level's idea. Aggregates are semiring contractions in `reduce` regions. This fixed-plan part is 0003's sparse half (0003 §9, §10), and is not built twice (*read*: 0003). | Integer and float elements only; sorted coordinates, not hash maps; formats and variable order fixed at compile time where COLT forces lazily. Co-iteration merges sorted levels with two pointers, linear in the sum of their sizes (*read*: 0003 §10, from the sparsifier's loop emitter), while generic join needs each intersection in time of the smallest side (*read* `papers/zhang-2022-relational-ematching/background.tex:584-589`), so a sparse join is not worst-case optimal. A lowering target for plans that fit, not the engine. |
| `linalg`, `vector`, LLVM backends | The tail of a query compiler: fusion, tiling, vectorization to NEON, SVE, AVX-512 and wasm SIMD128. The scalar twin is the same source at width 1; hand NEON and runtime dispatch go. | Hash probes and data-dependent control are weak in `linalg`. |
| One-Shot Bufferize | Tensors have value semantics and bufferization decides in-place writes: Idris's "functional but in place" at the array level. 0003 keeps `!idr.lin` as the wrapper around the tensor, its entry a release One-Shot copies at only when the buffer is still read (*read*: 0003 §8). Images immutable, arenas and aggregation state in place, by one mechanism. | |
| Typed indices | A pool or table index typed by its pool's extent (`Index s`) is an access with no guard (*read*: 0003 §3.2, D4); `idr-in-bounds` is deleted by 0003's stage 1, so COLT's pools are written over typed indices. | An index the library cannot type goes through `Maybe`, the program's own test. |
| 0004's specialization nodes | A plan normalized to a constant is a known constructor, and the interpreter's call on it is a request keyed by (callee, the static pattern), named from its key (0004 §4 stage 8; §3 here). | Pure optimization: the budgets stop it and never reject (0004 §2.5). The planner must be total, since only total code is normalized (0008 §2); a plan past 0008's budget is a first-demand constant, and its query runs the interpreter unspecialized. |
| The verifier | Quantities and grades (`!idr.lin`, `!idr.excl`) survive lowering because they live in types and are re-checked after every pass (AGENTS.md). | An erased plan proof (`ValidatedPlan q` at quantity 0) is checked by Idris and is no value of the module: the frontend emits nothing for it, so nothing downstream re-checks it. This supersedes the earlier "erased plan proofs survive lowering". |
| `shard` | Hash-partitioned relations are a sharding annotation; where to reshuffle is propagation (*read*: 0003 §14; the pinned `mlir/include/mlir/Dialect/Shard`). | Upstream propagates over parallel array dimensions, not joins. A join whose atoms are not co-partitioned on a shared variable is 0007 §4's: derived tuples are routed to their owner shards (D8). |
| Greedy pattern rewriting | A fixpoint rewrite engine, destructive: the C++ optimizer's canonicalization, run once per function (0004 §4 stage 6). | Layer 3 is the non-destructive version, for Idris consumers only (§4, D6). |

**Decision (D5):** a plan whose formats, variable order and join order
are fixed at compile time, and which needs no hash level, lazy level or
worst-case optimal intersection, is emitted as a sparse array program of
0003 (§10 there) and compiled by its lowering. Every other plan runs the
interpreter, specialized as §3 says. What stays here is what the sparse
subset cannot express: COLT's lazy tries, hash tries, the Free Join
planner and its generic-join end, galloping intersection, indexes chosen
from statistics, plan variants, e-graphs, and the storage, laws and log
shared with bumbledb. Reason: one route per plan, the boundary 0003 D22
decides from its side in the same words; proposed here on 2026-10-12,
decided with 0003 D22.

**Decision (D3):** what upstream lacks (hash tables, strings, tries,
data-dependent control) becomes `idr` ops or runtime primitives, never
hand code in the library, by bumbledb 0003 §4.2's measurement rule
(*read*): a vectorized array program reaches at least 90% of the Rust
kernel's throughput on bumbledb's kernel benches
(`crates/bumbledb/src/exec/kernel/bench.rs`) on both targets, and where
it does not, the missing pattern becomes an `idr` op or a runtime
primitive, whose one meaning is the runtime's (AGENTS.md). The
hand-tuned NEON Allen kernel is the first test of the rule. A
LingoDB-style relational dialect is not the primary path (§9).

## 6. Gates

- semi-naive Datalog within 1.5× of Soufflé in compiled mode on its
  standard programs (transitive closure, points-to, same generation;
  *recalled* as Soufflé's set);
- e-matching and saturation within 1.5× of egglog on its benchmarks,
  its two case studies first: a unification-based points-to analysis and
  Herbie's floating-point rewriter (*read*
  `papers/zhang-2023-egglog/abstract.tex`);
- joins at ≥ 80% of bumbledb's Rust engine on its 32 read families;
  correctness is bumbledb's 2,879 cases (*read*
  `../bumbledb/docs/perf/results.md:1-10`,
  `docs/perf/runs/1.3.0/verify.log:34`), their answers committed once as
  expected files under `tests/` from bumbledb at the ported commit, with
  no run against SQLite, the Rust engine or a naive evaluator
  (*decision*: bumbledb checks those cases by randomized comparison with
  SQLite and a naive evaluator, `../bumbledb/docs/perf/measurement-plan.md:315`,
  and a test whose expected answer comes from another implementation at
  run time is the oracle AGENTS.md declines; the Rust engine stays a
  speed reference only). bumbledb 2.0 has not been
  re-measured (`results.md:3-4`), so R1 takes both against the Rust
  engine at the bumbledb commit it ports;
- for each consumer, its own proposal's gate: 0009's O3 (identical Core;
  translate ≥ 3× faster than O0), O5 (identical TTCs; parse and resolve
  no slower than 0008's A0), O7 (0008 A2's targets; identical TTCs) and
  O8 (a seeded violation of each law caught by name).

A caution on prepared-query speedups (*recalled*: Kersten et al., VLDB
2018): compiled and vectorized engines each win on different queries and
neither dominates. bumbledb's interpreter is already batched and SIMD,
so the larger win is expected from fusion across the library boundary
(a query's sink fused into the consumer, bumbledb 0003 §4.2), not from
compiling the core alone (*conjecture*).

## 7. Rules it keeps

- **No runtime library:** no `sparse_tensor` runtime, OpenMP or async
  runtime; everything static (AGENTS.md; 0003 §9, §16).
- **Both targets;** nothing per target outside the target entry.
- **One thing, one representation:** D2.
- **Facts in types:** a plan is `ValidatedPlan q`, an erased proof
  indexed by its query; erased, it is no value of the module (§5's
  verifier row).
- **No option and no mode** (0004 D2): the interpreter and its
  specializations are one function, and there is no JIT and no
  interpreted-or-compiled switch.
- **Deterministic outputs:** byte-identical at 1, 2 and 8 threads, as
  0004's determinism rule checks every program (`tests/determinism`);
  sharded fixpoints keep it by 0007 §4's synchronous rounds and
  content-derived owners (D8).

## 8. Staged plan

Each stage lands as a cutover: the form it replaces in a consumer is
deleted in the same change (0004 D2).

| Stage | Content | Proof |
| --- | --- | --- |
| R1 | layer 1: relations as 0010 columns, COLT, Free Join, the interval kernels, the planner, the interpreter | bumbledb's 2,879 read cases against their committed expected files (§6); its 32 read families at ≥ 80% of the Rust engine (§6) |
| R2 | layer 2: semi-naive fixpoints, lattice-valued relations (D9) | within 1.5× of Soufflé (compiled) |
| R3 | first consumer: 0009's O3, Translate's instance fixpoint | identical Core; translate ≥ 3× faster than 0009's O0 |
| R4 | layer 3: e-graphs, relational e-matching, slotted binders | within 1.5× of egglog |
| R5 | 0009's O7: the elaborator's constraint store and postponement on R2, meta-to-meta unification on R4's union-find; e-graph saturation offered to tactics (§4) | 0008 A2's targets; identical TTCs; a tactic's proof term checked by the kernel |
| R6 | prepared-query specialization and plan variants (D1, D7) | bumbledb's 34 scenario queries, prepared, at ≥ 1.5× the Rust engine (bumbledb 0003 §9, P5); byte-identical at 1, 2 and 8 threads |

0009's O5 and O8 need only R1 and run in 0009's own order after it.
This supersedes the earlier R5, "the elaborator on the library (0011
T4)": T4 is the rewrite ladder and uses nothing here (0011 §2.4), and
shape equalities are 0003's tactic.

## 9. Rejected alternatives

- **The engine inside bumbledb:** the compiler would need its own join
  engine, unifier and rewrite system, two copies that drift.
- **The library in bumbledb's repository:** the compiler builds only from
  its own tree, and it consumes the library. It lives in `libs/`.
- **A relational dialect with its own lowering (LingoDB's route) as the
  primary path:** it is a second semantics beside the interpreter. The
  interpreter, specialized, is the one meaning; dialect ops fill measured
  gaps only (D3).
- **`sparse_tensor` as the join engine:** its limits in §5; it stays a
  lowering target where a plan fits it.
- **Two routes for one plan:** a prepared query that fits the sparse
  subset is emitted as a 0003 sparse array program, and the interpreter
  is specialized only for one that does not (D5; 0003 D22). Specializing the
  interpreter for a plan that fits would be a second compilation of the
  same query.
- **A JIT for ad-hoc queries or for statistics outside every variant**
  (bumbledb 0003 §4.1, §4.4): it would link LLVM into every program, and
  it would be a second compilation of a query beside the specialized
  interpreter. The interpreter runs them (D10).
- **The library as the C++ optimizer's or the C++ analyses' engine**
  (§4): a dialect analysis moved out of `foreign/idr` would hold one
  fact in two languages (0007 D13), and an optimizer beside 0004's
  would be a dual path (0004 D2).
- **HyperCube-style partitioning for joins across shards** (*recalled*):
  no stored source measures it, and the stored evidence gives one
  design that is deterministic under 0007's rules (D8).
- **Trusting a solver for equalities:** 0011 §2.5; saturation finds, the
  kernel checks.

## 10. Decisions

There is no open question for the owner.

- D1. The interpreter is written to be specialized; at most 4 plan
  variants per prepared query, picked by a guard on image statistics,
  the 4 being the library's code-size bound, never a refusal.
- D2. No consumer keeps its own copy of a mechanism the library provides.
- D3. Upstream gaps become `idr` ops or runtime primitives, by
  bumbledb 0003 §4.2's measurement (≥ 90% of the Rust kernel on both
  targets); no hand code in the library.
- D4. The library lives in `libs/mlir-relational`; bumbledb depends on
  it as a package.
- D5. A plan that fits the sparse subset (fixed formats, variable order
  and join order; no hash or lazy level; no worst-case optimal
  intersection) is a 0003 sparse array program; every other plan runs
  the specialized interpreter (§5). Decided with 0003 D22.
- D6. Every consumer is Idris. The C++ side's fixpoints (the label
  solve, SCC summaries, the ready set, 0007's C++ phase 2) are C++ over
  MLIR's machinery and use nothing of this library. Reason: AGENTS.md
  puts the dialect's passes in `foreign/idr`, and 0007 D13 computes each
  whole-program fact on the side that owns it.
- D7. A prepared query is specialized by 0004's ready set: the plan,
  normalized by 0008's A3, is a known constructor, and the interpreter's
  call on it is a specialization request named from its key (0004 §4
  stage 8). Reason: one specializer for every sum (0008 §2), and its
  budgets stop it without rejecting (0004 §2.5).
- D8. Layer 2 across shards is 0007 §4's recipe: a tuple's owner shard
  is the hash of a content-derived key, relations that join on a column
  share a bucket decomposition (Slog), recursion is partitioned on its
  pivot so it needs no shuffle (BigDatalog), a join whose atoms are not
  co-partitioned routes its derived tuples to their owners as messages,
  heavy buckets split, and rounds are synchronous (*read* dfp §4, §9;
  0007 §4.1, §4.2, D2). Reason: the order of deltas cannot change the
  fixpoint, and round counts do not depend on the schedule.
- D9. A layer-2 relation may be lattice-valued, with a merge per key, so
  subsumption (the size-change closure's weakest graphs) is a merge, not
  a separate mechanism (egglog's `:merge`, *read*).
- D10. There is no JIT in a program. An ad-hoc query, and a prepared one
  whose statistics leave every variant's range, runs the interpreter on
  a plan made at run time. Reason: linking LLVM into programs is
  refused, and the interpreter is the one meaning (§3).
