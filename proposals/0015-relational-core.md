<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0015: the relational core, `mlir-relational`

**Amended by P0 (2026-10-21, `0000-mlir-native.md`).** R1 and R2 are
absorbed into the cutover in `libs/mlir-relational` (D44). R4's part in
P0 is the union-find the elaborator's O7 consumes, kept in the checker,
`compiler/checker` (D107, C233); the shared e-graph engine written once
in Idris over a sparse tensor library (D85 to D87) was reversed by D107,
and the optimizer's e-graph is a C++ pass over MLIR's ops (C153).

## 0. Status

**In P0 in part; nothing is built** (*read* at e3b93a77, 2026-10-22:
`libs/mlir-relational` holds the lanes' first modules, joins, intervals
and the fixpoint, unbuilt, as no step of the cutover is built until the
whole is, P0's D56). R1 and R2 are P0's (D44), written by its lanes in
plain Idris for both hosts, before their consumers 0011's O3 (R3 here)
and O8, which are P0's too (P0 §7's F9). Their bars, bumbledb's Rust
engine and Soufflé, are ratios measured once `make self` holds, on
engines outside the toolchain (C136). R4 comes into P0 only as far as
0011's O7 consumes it, a union-find, which is the checker's own and not
this library's (D69, D107). The rest (layer 3 here, R5's saturation
offered to tactics, R6) is not P0's and stays **AFTER-SELF**. 0011's O5
and O8 need only R1 (0011 §8, D12), and whether O5's resolution is
layer 1's join is P0 §4's open question (C216). Every decision is
taken.

The library is Idris in `libs/` (D4), compiled by this compiler. It takes
over §4.5 of bumbledb's port proposal
(`../bumbledb/proposals/0003-idris-port.md`, read at 93540b7b6), which
keeps what is about the database. Why one library for a database and a
compiler: both implement logic over sets, relations, fixpoints and
equivalence, and each grew an ad hoc copy of the other's machinery.
bumbledb has hand-built plan witnesses, a vectorizer written out as NEON
twins, and an interpreter that wants compiling. The frontend has
Translate's worklist, `checkReachable`
(`compiler/src/IdrisMLIR/Frontend/Profile.idr`) and the checker's
size-change closure. The test is §5's gates: if the shared library does
not make every consumer smaller and faster, the analogy was only pretty.

Mechanisms of the pipeline cutover (built at c7aa7b62 and 5d5f3312; its
last text at 484d6403) are named "the cutover's".

## 1. Rules it keeps

- **No runtime library** (no `sparse_tensor` runtime, OpenMP or async
  runtime); every target; nothing per target outside the target entry.
- **One thing, one representation** (D2). **Facts in types:** a plan is
  `ValidatedPlan q`, an erased proof indexed by its query; Idris checks
  it, and it is no value of the module.
- **No option and no mode** (the cutover's D2): the interpreter and its
  specializations are one function, with no JIT and no
  interpreted-or-compiled switch.
- **Deterministic:** byte-identical across the thread counts and
  processes the determinism check (`harness/lib/determinism.sh`) uses. Sharded fixpoints keep this by
  D8.
- **Total, no fuel** (AGENTS.md; `tests/no-fuel` searches `libs/`).
  Every module is `%default total`, with no `covering`, `partial` or
  assertion. Layer 2 ends by an argument its type carries, never by a
  round count. The argument is one of: a finite universe (typed indices),
  a lattice of finite height for D9's merge, or a well-founded relation
  the consumer supplies. Translate's worklist today descends within the
  bounds the growth check gives (`Proof/Requests.idr`, `Universe` and
  `Bounds`; `Frontend/Growth.idr`). The checker's size-change subsumption is
  already total over `Fin m`
  (`compiler/checker/src/Core/Termination/SizeChange.idr`), and its
  replacement keeps that proof. Layer 3's saturation does not end in
  general. What it offers a tactic is bounded by the program, never by a
  library budget or a depth, as the elaborator's automatic search now
  ends by the path rule with no count and `%auto_implicit_depth` is
  refused by the parser (P0's D53), because a spent budget would fail a
  proof by a count (*decision*, from AGENTS.md).
- **Size policies:** D1's 4 plan variants is a named constant with its
  line in `tools/policies.txt`.
- **Two hosts** (AGENTS.md). The frontend compiles
  and runs under the stock Idris on Chez as well as under idris-mlir,
  forever: which compiler a bootstrap uses as stage 0 is a build choice,
  never a reason to stop building on Chez. Code the stock host runs
  reaches no `libs/` `%extern`. So the layers that O3, O5, O7 and O8 use
  are plain-Idris definitions over base, with bodies, linear where that
  helps. idris-mlir may replace one with a runtime op through the
  registry's `Faster` hook (`compiler/src/IdrisMLIR/Registry/Entry.idr`,
  `Kind`),
  as it does `Linear.String.Iterator.scalarBytes`. The body stays the one
  meaning, and removing the hook leaves the same result. Columns over
  `mlir-array`'s `%extern` generating set, and D3's ops and primitives,
  serve programs only (user programs, bumbledb's port), never the
  frontend's own code. D2's one implementation holds, because a `Faster`
  hook is no second meaning.

## 2. The library, by layer

No storage and no IO: this is the functional and array core, and the
shell is the consumers'. Each layer is built on the one below. The
reference implementation is bumbledb's engine
(`../bumbledb/crates/bumbledb/src`, read at c0e7708a6), taken without
storage, laws or the log.

1. **Relations and joins.** Relations are sets, held as columnar images
   with no nulls. Programs hold them as 0009 §4.5's columns, one tensor
   per field (not 0012's, which follows 0011), and the frontend holds
   them in plain Idris (§1). The layer has: COLT lazy tries in index-addressed
   pools, where a singleton child pins an image row (`exec/colt.rs:34-40`);
   Free Join, from binary hash join to worst-case optimal generic join
   (the AGM bound, *read*
   `sources/papers/zhang-2022-relational-ematching/background.tex:484-562`);
   selections, anti-probes, exact folds and aggregates; the interval
   kernels with their Allen masks; the planner; and the executor, an
   interpreter over a validated plan.
2. **Fixpoints.** Semi-naive Datalog over layer 1: delta relations, so
   each round joins only what is new. Transitive closure, reachability
   and SCCs are queries in it. A relation may be lattice-valued (D9).
   Across shards, rounds follow D8.
3. **Equality saturation.** egglog-style e-graphs over layers 1 and 2
   (union-find, congruence rebuilding). E-matching is a worst-case
   optimal join (layer 1), and binders go through slotted e-graphs.

**Prepared queries are specialized, not compiled by a query compiler**
(D1, D7, D10). The planner is total, so 0010's A3 normalizes a known
query's plan to a constant. The interpreter's call on that known
constructor is then a request of the cutover's ready set, keyed by
(interpreter, plan). Case of known constructor removes the dispatch on
plan nodes, and `linalg` fusion merges each pipeline into one loop nest
(0009 §7.2). Each step is optimization. Specialization stops at the
request-chain rule (`foreign/idr/include/idr/Transforms/Specialize.h`)
or at the caller cap (`kCallerCap`, `tools/policies.txt`). A plan past
0010's budget is a first-demand constant. Either way the query runs the
interpreter and means the same.

## 3. Consumers

Every consumer is Idris (D6).
- **0011's frontend:**
  - O3, the first consumer: Translate as semi-naive evaluation over the
    instance table, reachability as its query, within the growth check's
    bounds (layer 2; 0011 §4.8).
  - O5: name resolution as an Allen "during" join with a max-depth fold
    (layer 1; 0011 §4.4), whose form is P0 §4's open question (C216).
  - O7: the elaborator's constraint store and postponement (layer 2),
    with meta-to-meta unification on the checker's own union-find, not
    layer 3's (P0's D107).
  - O8: the compiler's invariants as law queries on every compilation
    (layer 1; 0011 §5, D13).
  - The size-change closure as a fixpoint with subsumption (layer 2, D9).
    Its composition kernel is 0009 §11's sparse semiring product.
- **0013's elaborator:** e-graph saturation offered to tactics. It returns
  a proof term the kernel checks and never extends conversion (0013 §2.0).
- **0008's S8:** the instance fixpoint sharded through O3, as layer 2 in
  bulk-synchronous rounds (0008 §4.2).
- **bumbledb's port:** the core plus storage, laws, the log and shards.
  Its storage reaches LMDB through 0020, so it waits on 0020 too.
- **User programs:** graph queries, rule engines and analyses.

Not consumers, by the proposals that own them:
- the multiplicity check (0009 §11);
- tabled instance search, whose answers are ordered and counted by the
  ambiguity rule (0013 §2.3, D6);
- shape arithmetic (0009 D11);
- every C++ fixpoint, and the C++ optimizer (D6; 0008 D13 rejects "0CFA
  on 0015"). Saturation over `idr` IR is P0's, not this library's: an
  e-graph takes the place of greedy rewriting at every point of the
  pipeline that holds our ops (P0's D98), built in C++ from MLIR's own
  mechanisms, its rules and laws data of the dialect's specification
  (D107, D109), and a true e-graph, whose fired rules keep both forms in
  one class, classes merged by a union-find, congruence restored after
  each round, each class's member chosen by cost (D123).

## 4. What MLIR provides, and the boundary

`sparse_tensor` can hold a relation as a tensor of `i8` with
`explicitVal = 1` (`i1` is no valid sparse element: *read*,
`.toolchain/llvm-project/mlir/lib/Dialect/SparseTensor/IR/SparseTensorDialect.cpp:922-926`),
and a conjunctive query is then an einsum. Two limits keep it from being
the engine:
- its co-iteration is linear in the sum of the levels' sizes, where
  generic join needs time in the smallest side;
- its formats and variable order are fixed at compile time, where COLT
  forces lazily.

So it is a lowering target for the plans that fit (0009 §9 and §10 hold
the inventory, with `linalg`, One-Shot Bufferize and typed indices), and
D5 draws the line. `shard` propagates over array dimensions, not joins,
so a join whose atoms are not co-partitioned is D8's.

## 5. Gates

- Semi-naive Datalog within 1.5× of Soufflé in compiled mode on
  transitive closure, points-to and same generation (*recalled* as
  Soufflé's set).
- E-matching and saturation within 1.5× of egglog, its two case studies
  first: unification-based points-to and Herbie's rewriter (*read*
  `sources/papers/zhang-2023-egglog/abstract.tex`).
- Joins at ≥ 80% of bumbledb's Rust engine on its 32 read families, and
  correctness on its 2,879 oracle cases. Both figures are bumbledb
  2.0.0's (*read* `../bumbledb/docs/perf/results.md:3-5` and
  `docs/perf/runs/2.0.0/verify.log:34`, measured 2026-10-10 at
  7135a9a18). The answers are committed once as expected files under
  `tests/`, from the ported commit, with no run against SQLite, the Rust
  engine or a naive evaluator (*decision*: bumbledb's oracle compares
  with them at run time, which is the oracle AGENTS.md declines; the Rust
  engine is a speed reference only).
- Each consumer's own gate, held in its proposal (0011 §8).

Compiled and vectorized engines each win on different queries
(*recalled*: Kersten et al., VLDB 2018). bumbledb's interpreter is
already batched and SIMD, so the larger win is expected from fusing a
query's sink into its consumer, not from compiling the core alone
(*conjecture*).

## 6. Staged plan

Each stage lands as a cutover: the form it replaces in a consumer is
deleted in the same change. R1, R2 and R3 are P0's (D44), with R5's half
that is 0011's O7 (D69), on the checker's own union-find, which is all
of R4 that P0 takes (D107). R4, R5's tactics and R6 stay
**AFTER-SELF**.

| Stage | Content | Needs | Proof |
| --- | --- | --- | --- |
| R1 | layer 1, its frontend paths in plain Idris (§1) | nothing; P0's, before O3 (D44; §0) | bumbledb's 2,879 cases against committed expected files; its 32 read families at ≥ 80% of the Rust engine |
| R2 | layer 2, lattice-valued relations (D9), termination in the type (§1) | R1 | within 1.5× of Soufflé (compiled) |
| R3 | 0011's O3 | R2; 0011's O0 (at `make self`); 0010's A0 | identical Core; translate ≥ 3× faster than O0 |
| R4 | layer 3: e-graphs, relational e-matching, slotted binders | R2 | within 1.5× of egglog |
| R5 | 0011's O7, P0's (D69): the constraint store and postponement on layer 2, meta-to-meta unification on the checker's own union-find (D107); saturation offered to tactics | O7: R2 and that union-find, no e-graph (D69, D107); the tactics: R4; 0010's A2 | 0010 A2's targets; identical TTCs; a tactic's proof term checked by the kernel |
| R6 | prepared-query specialization and plan variants (D1, D7) | R1; 0010's A3 | bumbledb's 34 scenario queries, prepared, at ≥ 1.5× the Rust engine; byte-identical across thread counts |

## 7. Rejected alternatives

- **The engine inside bumbledb, or the library in bumbledb's repository:**
  the first gives the compiler a second copy that drifts; the second
  fails because the compiler builds only from its own tree (D4).
- **A relational dialect with its own lowering (LingoDB's route) as the
  primary path:** a second semantics beside the interpreter. Dialect ops
  fill only measured gaps (D3).
- **`sparse_tensor` as the engine, a JIT, the library as the C++ side's
  engine:** §4 with D5, D10, D6.
- **HyperCube partitioning across shards:** no stored source measures
  it, while D8 is deterministic under 0008's rules (*recalled*).
- **Trusting a solver for equalities:** saturation finds and the kernel
  checks (0013 §2.5).

## 8. Decisions

- D1. The interpreter is written to be specialized: only the plan is
  static. COLT forcing, key counts and the cover per node depend on data
  and are separated from the plan by construction. A prepared query
  compiles at most 4 plan variants, the planner's covers under different
  cardinality assumptions, and a guard on image statistics picks one
  (Umbra-style, bumbledb 0010 §4.4). The 4 bounds code size and never
  refuses.
- D2. No consumer keeps its own copy of a mechanism the library provides
  (0011 §9; 0013 D6).
- D3. What upstream lacks (hash tables, strings, tries, data-dependent
  control) becomes `idr` ops or runtime primitives, never hand code in
  the library. The rule is bumbledb 0010 §4.2's measurement: at least
  90% of the Rust kernel's throughput on
  `crates/bumbledb/src/exec/kernel/bench.rs`, on every target, and the
  hand-tuned NEON Allen kernel is the first test. On a path the frontend
  reaches, the gap is closed by a `Faster` hook over a plain-Idris body
  (§1).
- D4. The library lives in `libs/mlir-relational`; bumbledb depends on
  it as a package.
- D5. A plan with fixed formats, variable order and join order, and no
  hash level, lazy level or worst-case optimal intersection, is a 0009
  sparse array program. Every other plan runs the specialized
  interpreter. Decided with 0009 D22: one route per plan.
- D6. Every consumer is Idris. The C++ side's fixpoints are C++ over
  MLIR's machinery: AGENTS.md puts the dialect's passes in `foreign/idr`,
  and 0008 D13 computes each whole-program fact on the side that owns it.
- D7. A prepared query is specialized by the cutover's ready set, on the
  plan normalized by 0010's A3 as a known constructor. Reason: one
  specializer for every sum (0010 §2), whose budgets stop it without
  rejecting.
- D8. Layer 2 across shards follows 0008 §4. A tuple's owner is the hash
  of a content-derived key; relations that join on a column share a
  bucket decomposition; recursion is partitioned on its pivot. A join
  whose atoms are not co-partitioned routes its derived tuples to their
  owners. Heavy buckets split, and rounds are synchronous (*read*
  `sources/notes/sharded-compilation/deterministic-fixpoints.md` §4, §9).
  Reason: the order of deltas cannot change the fixpoint.
- D9. A layer-2 relation may be lattice-valued, with a merge per key
  (egglog's `:merge`, *read* `sources/papers/zhang-2023-egglog/herbie.tex:79-80`).
  Subsumption, such as the size-change closure keeping only the weakest
  graphs, is then a merge and not a separate mechanism. The lattice has
  finite height (§1).
- D10. There is no JIT in a program. An ad-hoc query, or a prepared one
  whose statistics fall outside every variant, runs the interpreter on a
  plan made at run time. Reason: linking LLVM into programs is refused,
  and the interpreter is the one meaning.

## The MLIR form owed

From the representation wave's audit of the proposals' MLIR forms (its
last text at 77eaa5b1), checked against the code there; none of it is
built unless it says so.

- D3's ops: one op per meaning, its effects in ODS on the structure it
  touches; a hash table is memory (`MemRead` and `MemWrite` on the table,
  never on IO); its guard an `Idr_Guarded` mark; data-dependent control
  `scf.while` and `scf.if` over those ops, never an op of ours.
