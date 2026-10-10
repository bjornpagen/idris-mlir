# 0010: the relational core, `mlir-relational`

**Status:** proposed (2026-10-10). Nothing here is built. It is the
proposal 0006 D6 promised, written now because 0005 names its first
consumer. It takes over §4.5 of `../bumbledb/proposals/0001-idris-port.md`
on this side; that file keeps what is about the database.

**Sources.** Under `sources/`: `papers/zhang-2022-relational-ematching`,
`papers/zhang-2023-egglog`, `papers/willsey-2021-egg`,
`papers/wu-2026-slotted-egraphs`, `papers/jordan-2016-souffle`,
`papers/bik-2022-sparse-mlir`, `papers/kjolstad-2017-taco`,
`papers/lattner-2020-mlir`, `code/mlir`, `docs/mlir`. bumbledb's Rust
engine at `../bumbledb/crates/bumbledb` is the reference implementation.
Literature not re-read for this draft is marked *recalled*.

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
representation"; bumbledb's `docs/design/representation-first.md`). Applied
long enough, it strips what is accidental, and what is essential is a
short list: sets and relations, terms and trees, arrays, fixpoints, and
equivalence (union-find, rewriting, e-graphs). Two systems under the same
pressure reach the same attractors.

The field shows the same convergence (*recalled*): program analysis moved
to Datalog (bddbddb, Doop, Soufflé, CodeQL); rustc became a demand-driven
query system and its borrow checker was rewritten as Datalog (Polonius);
egglog merged e-graphs and Datalog; relational e-matching showed
e-matching is a worst-case optimal join; and databases became compilers
(HyPer, Umbra, LingoDB on MLIR).

### 1.3 Each project had a hole shaped like the other
Greenspun's rule, both ways:
- **bumbledb grew half a compiler:** sealed witnesses (`ValidatedPlan`,
  `DistinctWitness`) are proofs built by hand; scalar twins plus NEON plus
  runtime dispatch are a vectorizer written out; the executor is an
  interpreter that wants to be compiled (*read*:
  `../bumbledb/crates/bumbledb/src/plan/fj.rs`, `exec/kernel/`,
  `exec/run.rs`).
- **idris-mlir was about to grow half a database:** a unifier, a rewrite
  system, the termination closure, the reachability worklist and
  instance resolution are each an ad hoc relational engine with its own
  worklist and union-find.

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
  N^1.5 (the AGM bound, *recalled*). Free Join (Wang et al., SIGMOD 2023)
  spans binary hash join to generic join; the planner picks a point.
- **Lazy tries (COLT)** index an image only as far as a join probes it;
  nodes live in index-addressed pools; a singleton child pins an image
  row instead of allocating a node (`Cursor = Node | Row`).
- **Kernels** for scans, compaction, folds, gathers and Allen masks.
- **The executor is an interpreter** over a validated plan: plan nodes,
  cursors, sinks.

## 3. The library, by layer

Each layer is built on the one below. No storage and no IO: the library
is the functional and array core, and the shell belongs to consumers.

1. **Relations and joins:** typed relations as columnar arrays (0008's
   columns), COLT, Free Join and the generic-join end, selections,
   anti-probes, exact folds and aggregates, the planner, and the executor
   as an interpreter.
2. **Fixpoints:** semi-naive Datalog over layer 1, with delta relations
   so each round joins only what is new. Transitive closure,
   reachability and strongly connected components are queries in it.
3. **Equality saturation:** egglog-style e-graphs over layers 1 and 2
   (union-find, congruence rebuilding); e-matching as worst-case optimal
   joins, i.e. layer 1 again; binders through slotted e-graphs.

**Prepared queries are specialized, not compiled by a query compiler.** A
query known at compile time is a closed call of the interpreter on a
constant query. The planner is total, so static normalization (0003)
computes the plan in the frontend; `idr-specialize` clones the
executor for it, defunctionalization and inlining remove dispatch, and
`linalg` fusion merges each pipeline into one loop nest: the first Futamura
projection. Ad-hoc queries run the interpreter, which is batched and
vectorized; there is no JIT in a program (it would link LLVM into every
program).

**Decision (D1):** the interpreter is written to be specialized. Only the
plan is static; COLT forcing, exact-versus-estimated key counts and the
cover chosen per node depend on data, so they stay dynamic, and the
interpreter separates them from the plan by construction (binding-time
separation). A prepared query compiles at most 4 plan variants and a
guard on image statistics picks one (bumbledb 0001 §4.4).

## 4. Consumers

- **The frontend (0005):** the instance fixpoint, reachability, name
  resolution's interval join, multiplicity and size-change folds,
  postponement as semi-naive evaluation.
- **The elaborator (0006):** constraints as relations, meta unification
  as union-find, shape and rewrite equalities as e-graph saturation, so
  `n * m = m * n` never blocks a user.
- **bumbledb's port:** the core plus storage, laws, the log and shards.
- **User programs:** graph queries, rule engines and analyses, with a
  Datalog and e-graph engine specialized and fused into them.
- **Later, the compiler's own optimizer** (*conjecture*): equality
  saturation over `idr` IR in place of, or beside, the greedy rewrite
  driver (there is prior work running egglog over MLIR, DialEgg, CGO
  2025, *recalled*). The engine would then type-check the compiler's
  input, optimize its IR, and be compiled by it.

**Decision (D2):** a consumer may not keep its own copy of a mechanism the
library provides.

## 5. What MLIR already provides

The convergence is cheap because MLIR is the third project under the same
rule: an open set of ops and types instead of a fixed instruction set,
each concept at one level (*recalled*: `papers/lattner-2020-mlir`).
Inventory, each with its limit:

| Mechanism | What it gives the core | Limit |
| --- | --- | --- |
| `sparse_tensor` | A relation is a sparse Boolean tensor; a conjunctive query is an einsum (`Q[a,b,c] = R[a,b]·S[b,c]·T[a,c]`). Level formats (dense, compressed, singleton) are trie levels: CSR is a two-level trie, and COLT's row-pinning singleton child is the singleton level's idea. Co-iteration by merge lattices is generic join's intersection; variable order is loop order (*recalled*: bik-2022, kjolstad-2017; Ahrens's Finch, Deeds et al.'s Galley). 0007 §13 already plans `SArray fmt s a` on `#sparse_tensor.encoding` without the runtime library (*read*). | Numeric elements only (*read*: 0007 §13); sorted coordinates, not hash maps; formats fixed at compile time where COLT forces lazily; no worst-case optimal variable ordering. A lowering target for some plans, not the engine. |
| `linalg`, `vector`, LLVM backends | The tail of a query compiler: fusion, tiling, vectorization to NEON, SVE, AVX-512 and wasm SIMD128. The scalar twin is the same source at width 1; hand NEON and runtime dispatch go. | Hash probes and data-dependent control are weak in `linalg`. |
| One-Shot Bufferize | Tensors have value semantics and bufferization decides in-place writes: Idris's "functional but in place" at the array level. 0007 carries `!idr.lin` into the tensor encoding (*read*: 0007 `compiler.md` §9). Images immutable, arenas and aggregation state in place, by one mechanism. | |
| `IntegerRangeAnalysis` | `idr-in-bounds` proves pool and table indices in range, so COLT's pools need no `unsafe` and no per-access check (*read*: 0007 `compiler.md` names it). | Indices it cannot prove keep a guard. |
| `idr-specialize` on constant arguments | A plan computed by static normalization specializes the executor. | The planner must be total: only total code is normalized (0003). |
| The verifier | Erased plan proofs and grades survive lowering because they are re-checked after every pass. | |
| `shard` | Hash-partitioned relations are a sharding annotation; where to reshuffle is propagation (*read*: 0007 `compiler.md`'s SPMD row). | Upstream propagates over parallel array dimensions, not joins. A join whose atoms are not co-partitioned on a shared variable needs a shuffle or HyperCube-style partitioning (*recalled*); this is open. |
| Greedy pattern rewriting | A fixpoint rewrite engine, destructive. | Layer 3 is the non-destructive version. |

**Decision (D3):** what upstream lacks (hash tables, strings, tries,
data-dependent control) becomes `idr` ops or runtime primitives, never
hand code in the library, as bumbledb 0001 §4.2's measurement rule says.
A LingoDB-style relational dialect is not the primary path (§8).

## 6. Gates

- semi-naive Datalog within 1.5× of Soufflé in compiled mode on its
  standard programs (transitive closure, points-to, same generation);
- e-matching and saturation within 1.5× of egglog on its benchmarks;
- joins at ≥ 80% of bumbledb's Rust engine on its read families, with its
  oracle (2,879 cases in its 1.3.0 suite) as the correctness gate;
- for each consumer, its own proposal's gate (0005's stages, 0006's T2
  and T4).

A caution on prepared-query speedups (*recalled*: Kersten et al., VLDB
2018): compiled and vectorized engines each win on different queries and
neither dominates. bumbledb's interpreter is already batched and SIMD,
so the larger win is expected from fusion across the library boundary
(a query's sink fused into the consumer), not from compiling the core
alone (*conjecture*).

## 7. Rules it keeps

- **No runtime library:** no `sparse_tensor` runtime, OpenMP or async
  runtime; everything static (AGENTS.md; 0007 §13).
- **Both targets;** nothing per target outside the target entry.
- **One thing, one representation:** D2.
- **Facts in types:** a plan is `ValidatedPlan q`, an erased proof
  indexed by its query.
- **Deterministic outputs.**

## 8. Staged plan

| Stage | Content | Proof |
| --- | --- | --- |
| R1 | layer 1: relations as 0008 columns, COLT, Free Join, the planner, the interpreter | bumbledb's oracle cases for reads; read families ≥ 80% of the Rust engine |
| R2 | layer 2: semi-naive fixpoints | within 1.5× of Soufflé (compiled) |
| R3 | first consumer: 0005 O3, Translate's instance fixpoint | identical Core; O3's threshold |
| R4 | layer 3: e-graphs, relational e-matching, slotted binders | within 1.5× of egglog |
| R5 | the elaborator on the library (0006 T4) | 0007's shape-equality corpus never blocks; base elaborates no slower |
| R6 | prepared-query specialization and plan variants (D1) | bumbledb's scenario queries, prepared, against the Rust engine |

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
- **Trusting a solver for equalities:** 0006 §2.5; saturation finds, the
  kernel checks.

## 10. Decisions

- D1. The interpreter is written to be specialized; at most 4 plan
  variants per prepared query, picked by a guard.
- D2. No consumer keeps its own copy of a mechanism the library provides.
- D3. Upstream gaps become `idr` ops or runtime primitives, by
  measurement; no hand code in the library.
- D4. The library lives in `libs/mlir-relational`; bumbledb depends on
  it as a package.
