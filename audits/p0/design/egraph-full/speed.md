<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: the speed of full equality saturation

Status: written 2026-10-21 for D85 (`proposals/0000-mlir-native.md:1218-1231`),
which binds this file: the full research form of equality saturation, one
engine, because eggcc's "11× slower than LLVM -O3" is "one
implementation's measurement (an interpreted Datalog engine), not a bound"
and "after the sparse arrays lowering in mlir, it becomes dense". D86 and
D87 (`:1232-1259`) then chose the route: the engine written once in Idris,
printed as MLIR "sparse tensors where the relations are, loops elsewhere",
compiled by the pinned toolchain's sparsifier. This file answers one part:
where the time of full saturation goes, and how fast it can be made. It
reverses nothing; where a finding bears on D86's route it is stated as a
cost, for the owner and for `one-engine.md` and `sparse-library.md`
beside it.

Grounds: *measured* (a command I ran, named with its build, input and
machine), *measured (agent)* (a run by this task's measurement agent,
scripts and outputs in `/tmp/egraph-full-speed/{scripts,out}`), *read*
(a path:line or section I read), *read (agent)* (read in the primary
source by one of this task's reading agents; the location is theirs, not
re-checked by me), *summary* (an abstract, README or pull request text
only), *recalled*, *conjecture*, *decision* (a ruling Dn). Ours at HEAD
e96bb991 with the working tree's proposal; MLIR at the pin 7208ba24.

Machine for every measurement: Apple M2 Max (virtual), 8 cores, 32 GB,
macOS; rustc 1.101.0-nightly (2026-10-08) release builds; Apple clang
21.0.0 `-O2 -march=native`. The machine was shared (load average 5 to 24
over the session, from processes not of this task); single-threaded
headline numbers were rerun at load 5-6 and agree with the loaded runs
within 20%. Outside code, cloned with `--depth 1` under
`/tmp/egraph-full-speed/`: egglog 6b42f908 (2026-10-21), egg 73975c98,
eggcc 8337bb0d (pins egglog 90635860), egglog-experimental 61e68719,
extraction-gym 903ba0f8, egglog-benchmarks 4e9061a2, herbie 5c056bd8;
wasmtime aceb6b0f from the earlier research. Nothing was built or run in
the repository.

## 0. In plain words

- **Where the time goes depends on size, and it is mostly not the
  join.** On small e-graphs with many iterations, an interpreted engine
  spends its time in per-step overhead and in rebuilding indexes
  (eggcc: 13-47% of egglog's time outside every phase, rebuild 20-40%,
  thousands of steps over 16k-191k tuples; *measured (agent)*). On large
  ones, it spends it maintaining tables: in egglog at 16M tuples,
  merge plus rebuild is 76%, and one function, `SortedWritesTable::merge`,
  is 58% of the CPU samples (*measured (agent)*). The join itself, the
  part a relational compiler compiles, is a minority wherever it was
  separated out.
- **How fast it can be made: about 5-16× over egglog, measured on one
  workload.** I wrote the e-graph a generator would print for one fixed
  signature and rule set (dense ids, one open-addressing hash-cons per
  op, an array union-find, rules as nested loops over per-op tables and
  counting-sort indexes, semi-naive by timestamps) and ran it against
  egglog on the same rules and term. Both build the identical e-graph
  (633,739 `Add` and 7,363,672 `Mul` nodes after 7 iterations; 47.9M
  matches in each). egglog: 26.4-31.8 s on one thread, 10.4 s on 8,
  9.4 GB. The dense engine: 3.5-3.7 s on one thread, 3.1 GB: 7.2-9.0×
  single-threaded, 2.9× against egglog's 8 threads. At per-function sizes
  (190 to 19,000 nodes) the gap is 4.1-20× (*measured*, §2).
- **Of the dense engine's own time, the join is 9-20%.** Building the
  right-hand sides (a hash-cons probe or insert per node, and a union) is
  35-65%; re-canonicalizing after merges is 24-30%; rebuilding indexes is
  3-48%, the large share at small sizes, where an index over every class
  id is a fixed cost per iteration (*measured*). Compiled relational
  engines report the same: compiling the plan buys 1.3-6× over an
  interpreter with the same data structures; the data structures and
  algorithms buy 10× to 10⁵× (Soufflé, compiled Free Join, eqrel, egg's
  rebuilding; *read (agent)*, §3).
- **What "dense" buys, measured.** A per-function e-graph has dense ids
  and stays in cache: the dense engine costs 75-230 ns per node at up to
  20,000 nodes and 440-510 ns per node at 8M (*measured*). That is the
  sense in which per-function saturation becomes dense: arrays indexed by
  class id, held in one arena per function.
- **What the sparsifier can and cannot carry (bears on D86/D87).** At the
  pin, `sparse_tensor` has no hash level, accepts a sparse output only if
  its structure is fixed or it is fresh and filled in lexicographic order,
  and has no deletion (*read*, §3.5). An e-graph's tables grow inside an
  iteration and are rewritten by every rebuild, so the sparsifier can
  compile the join over a frozen snapshot (the 9-20%), while the
  hash-cons, union-find, rebuild and index maintenance (the 80-90%) are
  D86's "loops elsewhere". Repacking the relations into sparse tensors
  every iteration costs O(table) per iteration: in the dense engine an
  idle iteration over 100k nodes costs 1.4 ms (*measured*), which over
  eggcc's 4,312-8,256 steps on 16k-191k tuples would be 1-22 s of
  repacking per benchmark (*conjecture*, arithmetic), more than egglog's
  whole run on them (0.8-9.2 s, *measured (agent)*).
- **Termination: count nodes, not iterations or seconds.** Saturation
  need not terminate (undecidable in general; associativity alone
  diverges; *read (agent)*). In the measured run one iteration multiplied
  the e-graph 422× (18,943 to 7,997,421 nodes) and the next did not finish
  in 100 s; one rule (associativity of `Mul`) produced 91% of all matches
  (*measured*). Time is linear in nodes made, so a node budget per op is a
  time budget in program units, deterministic, and only ever leaves code
  less optimized (AGENTS.md); a per-rule match cap with back-off keeps one
  rule from spending it.
- **The estimate (*conjecture*, §5).** At stage-1 scale (about 0.76M ops
  in 114,110 functions at emit, *read*; 1-3M ops at the e-graph's points,
  *conjecture*), a compiled, dense engine with a budget of 16-64 nodes per
  op costs on the order of 3-70 s of CPU, which 8 cores spread to 0.4-9 s,
  except the largest function (a match of tens of thousands of cases,
  1.6M-13M nodes), which runs on one core for 0.7-19 s and sets the wall.
  Node creation and canonicalization dominate it. An interpreted engine at
  the same budget would cost the 5-16× above.
- **Genuinely research** (§6): a generated engine that keeps the measured
  factor while carrying typed classes, analyses, conditions and the
  region skeleton (no compiled e-graph engine has been measured against an
  interpreted one; my point is hand-written, one rule set); dynamic
  relations in MLIR's sparse pipeline; schedules that find the good
  programs within a budget; effects inside the graph; parallelism inside
  one e-graph.

## 1. Where the time goes, engine by engine

### 1.1 egglog

- **Its engine** (*read (agent)*, egglog 6b42f908): since 1.0.0
  (2025-10-18) the backend is `core-relations` (tables, joins, union-find)
  under `egglog-bridge` (semi-naive evaluation, merge functions),
  `CHANGELOG.md:102-104`, `egglog-bridge/src/lib.rs:1-9`. A rule's query
  is split by tree decomposition (min-fill variable elimination,
  `core-relations/src/free_join/plan.rs:1-45, 537`) and each bag is joined
  by Generic Join, the default (`plan.rs:509-526`), with dynamic variable
  ordering at run time (`free_join/join_tail.rs:399-421`); a vectorized
  plan interpreter, no code generation (`execute.rs:1-17`). Semi-naive: a
  rule with N atoms runs as N variants of one cached plan by timestamp
  (`egglog-bridge/src/rule.rs:767-833`). Rebuild is skipped when no union
  happened (`lib.rs:785-797`) and otherwise loops containers, tables and
  re-timestamping to a fixpoint (`:810-866`); per table it picks an
  incremental or a full scan by a cost model, tables of at most 100 rows
  always scanned (`core-relations/src/table/rebuild.rs:309-350`). The
  union-find is union by minimum id with path halving, no rank
  (`union-find/src/lib.rs:1-12, 87-120`). Indexes are built lazily per
  (table, columns), refreshed from appended rows, rebuilt in full when the
  table rehashes (`free_join/mod.rs:1076-1118`, `hash_index/mod.rs:118-152`,
  `table/mod.rs:1125-1135`). Parallel cutoffs: 400k rows for index
  building and rebuild (`parallel_heuristics.rs:8-16`).
- **Its timers** (*read (agent)*): search and apply are one timer, since
  matches feed actions that stage writes (`execute.rs:199-529`); merge is
  `merge_all` applying the staged writes (`:531-533`); rebuild is
  `egglog-bridge/src/lib.rs:799-801`.
- **Splits** (*measured (agent)*, `egglog -j N --save-report`):

  | input | size | search+apply / merge / rebuild | threads |
  | --- | --- | --- | --- |
  | all 101 `tests/*.egg` | small | 91 / 4 / 5% of 7.9 s; phases are 69% of wall | |
  | math-microbenchmark, 11 iterations | 1,047,896 tuples | 52 / 15 / 33%, 0.31 s | j8 no faster |
  | the same, 12 iterations | 15,987,528 tuples, 3.6 GB | 24 / 24 / 52%, 11.0 s (10.7 s in the last iteration) | j8 3.5 s in-process |
  | gemma4_moe | 111k tuples, 227 iterations | 98 / 0 / 2%, 3.08 s | j8 2.39 s |
  | eggcc-2mm | 2,466 iterations | 81 / 2 / 17%, 0.64 s | j8 slower, 0.95 s |

  A CPU sample of the 12-iteration math run's last iteration
  (`sample`, 8 s, one thread; *measured (agent)*): self time
  `SortedWritesTable::merge` 58%, `memmove` 9.8%, `RowBuffer::add_row`
  6.5%, hashbrown `reserve_rehash` 5.6%, the merge callback 4.6%,
  `Canonicalizer::rebuild_buf` 3.7%: by call tree 75% in `merge_all` and
  25% in rebuild. Table maintenance, not matching. On the many-rule
  workloads, one rule dominates search (paged_llama 89%, eggcc-extraction
  86%, herbie-vanilla 85%; *measured (agent)*), and "search" there includes
  building tries per run and staging writes (*read (agent)*).
- **Schedules and limits** (*read (agent)*): `(run R N :until F)` is
  `Repeat(N, Run)` (`src/ast/parse.rs:668-699`); `saturate` loops until an
  iteration changes nothing (`src/lib.rs:1024-1069`); core egglog has no
  node or time limit. egglog-experimental's back-off scheduler: match
  limit 1000, ban 5, threshold `limit << times_banned`, optional
  `:node-limit` (`src/scheduling.rs:516-524, 640-660`).

### 1.2 egg

- **Matching and runner** (*read (agent)*, egg 73975c98): patterns compile
  to a four-instruction virtual machine, Bind, Compare, Lookup, Scan
  (`src/machine.rs:24-29`). Runner defaults: 30 iterations, 10,000 nodes,
  5 s (`src/run.rs:341-347`); the default scheduler is back-off, match
  limit 1000, ban 5 (`:354, 869-877`). The paper calls search "the bulk of
  running time" (`sources/papers/willsey-2021-egg/05-impl.tex:201`) and
  measures deferred rebuilding 88× faster on congruence and 21× end to end
  (`03-rebuilding.tex:538-551`, *read (agent)*).
- **Splits** (*measured (agent)*, `cargo test --release`): the bundled math
  and lambda tests, 34 runner reports, 0.59 s: search 79%, apply 13%,
  rebuild 9%. egglog's math benchmark ported to egg (23 rules, 7 seed
  terms, a scheduler that runs every rule every iteration): 11 iterations,
  1,047,904 nodes, 0.70 s, search 18 / apply 59 / rebuild 24%; 12
  iterations, 15,987,536 nodes, 28.3 s, 29 / 50 / 21%, 4.1 GB. The node
  counts equal egglog's tuples plus the 8 literal leaves: the same
  e-graph, on which one-threaded egglog is 2.3-2.6× faster than egg.

### 1.3 eggcc

- **Its schedule** (*read (agent)*, eggcc 8337bb0d): three passes, each an
  egglog run then extraction (`dag_in_context/src/schedule.rs:213-275`);
  rulesets bounded by `repeat` counts (3, 2, 3, 2, 4) and a helper loop of
  `repeat 5`, because "substitution doesn't necessarily saturate"
  (`:52-57`); no node or time cap on saturation; the only timeout is ILP's
  300 s per region (`lib.rs:413-414, 516`). egglog-experimental expands it
  into thousands of single `(run X)` steps.
- **The paper's breakdown** (*read*, through `design/egraph.md` §1.4, and
  *read (agent)*, `10-eval.tex:86-91, 221-240`): per benchmark, 7.93 s
  outside extraction and 1.54 s in it against LLVM -O3's 0.83 s, which is
  the 11×. Raytracer: 171.6 s saturation, 22.6 s extraction. The context
  treatment (`WITHCTX`) spends 20.66 s outside extraction against 7.11 s
  without, 2.9×; it is disabled in `infra/profile.py:130`, so the figure
  may be stale.
- **Measured** (*measured (agent)*; stock eggcc needs an installed LLVM 18
  and Cbc, so a copy had its LLVM backend call removed, the ILP extractor
  stubbed, and per-pass timers added; `eggcc --run-mode optimize`, one
  thread):

  | benchmark | total | egglog's share | search+apply / merge / rebuild / outside phases | extraction | steps | max tuples |
  | --- | --- | --- | --- | --- | --- | --- |
  | palindrome | 0.80 s | 88% | 31 / 3 / 20 / 47% | 3% | 4,312 | 16k |
  | mat-mul | 1.19 s | 95% | 31 / 1 / 26 / 42% | 2% | 5,113 | 29k |
  | bicg | 2.40 s | 94% | 41 / 2 / 34 / 23% | 4% | 6,867 | 74k |
  | 2mm | 9.15 s | 96% | 45 / 1 / 40 / 13% | 3% | 8,256 | 191k |
  | csrmv | 3.74 s | 91% | 33 / 1 / 39 / 27% | 7% | 6,154 | 62k |
  | cholesky_decomp | 4.65 s | 89% | 33 / 1 / 36 / 30% | 4% | 5,956 | 63k |

  "Outside phases" is parsing, typechecking, rule compilation and per-step
  overhead. A sample of 2mm's main thread: `Canonicalizer::rebuild_buf`
  33%, `radix_sort_slice_by_value` (index building) 10%, `memmove` 8%,
  rule compilation about 5%.
- **What this says** (*conjecture*): eggcc's e-graphs are small; its time
  is thousands of steps, each paying a rebuild, index refreshes and a
  fixed overhead in proportion to the tables rather than to the step's
  delta. That is the regime where specialized code and delta-proportional
  maintenance pay most, and where per-iteration repacking pays worst
  (§3.5).

### 1.4 Extraction

- **Cost relative to saturation.** In every system with numbers,
  saturation outweighs extraction: eggcc 2-7% of total (*measured
  (agent)*) and 1.54 s of 9.46 s in the paper (*read*);
  greedy tree-cost extraction in the dense engine of §2 is 39 ms on 8M
  nodes (1%) and 63 µs on 18,943 nodes (2.7%) (*measured*). extraction-gym
  (*measured (agent)*, without ILP, extraction time only): eggcc-bril, 36
  files, 0.27-0.86 s per extractor in total; tensat, 10 files, 0.42-17.3 s;
  herbie, 18 files, 0.61-1.84 s; faster-greedy-dag finds the best DAG cost
  on eggcc and tensat files, the others within 3%.
- **Where it gets hard** (*read (agent)*): optimal extraction with sharing
  is NP-hard; effect-safe extraction is NP-complete even to find any
  solution (eggcc `07-np.tex:29-34`). Statewalk DP is O(k·n²) for
  statewalk width k ≤ 2ⁿ (`06-tiger.tex:441-491`); 94.7% of eggcc's
  regions have width 1 and 98.4% at most 5; rewriting pure terms cannot
  increase it (`:500`). ILP (Gurobi) times out on 234 of 9,610 regions and
  on all 30 PolyBench benchmarks, and still times out with the cost
  dropped: finding a valid extraction is the hard part (`10-eval.tex:11-16,
  112-201`). Tensat's ILP exceeds 3,600 s at k_multi=2. e-boost reports
  558× over ILP at a 0.21% gap (arXiv 2508.13020, `5_experiment.tex:45`);
  SmoothE 8-37× over ILP at comparable quality.
- **For us** (*conjecture*, from `design/egraph.md` §2.1, §2.3): with
  effects held in the region skeleton, not threaded through the graph,
  extraction stays greedy and is a few percent of saturation; it becomes
  research the day the skeleton becomes a partial order per resource
  (egraph.md §9 E11), when statewalk-like widths appear.

## 2. A dense, specialized engine, measured

### 2.1 What was built, and why

The question D85 raises is the constant factor of an engine whose
relations and rule joins are compiled to dense specialized code. No
published measurement compares a compiled e-graph engine with an
interpreted one (*read (agent)*: none found among Soufflé, Ascent, Free
Join, relational e-matching, egglog, Metatheory.jl, ISLE). So I wrote, in
C++ outside the repository, the engine a generator would print for one
signature and one rule set, and ran it against egglog on the same input.

- Signature: `Num(i64) | Var(i) | Add(a, b) | Mul(a, b)`.
- Rules, all rewrites: commutativity of `Add` and `Mul`; associativity
  `x + (y + z) → (x + y) + z` and the same for `Mul`; distribution
  `a·(b + c) → a·b + a·c`; factoring `a·b + a·c → a·(b + c)`; `a + 0 → a`;
  `a·1 → a`; `a·0 → 0`. The egglog file is the same nine `rewrite`s
  (`/tmp/egraph-full-speed/dense/rules.egg`).
- Input: one random 12-leaf term (seed 1), the same s-expression for both
  (`p-12-7.egg`).
- Engine (`/tmp/egraph-full-speed/dense/eg.cpp`, 353 lines, sha256
  9a2e8744bb856c07…): dense `uint32_t` ids; a union-find array, smaller id
  the representative, path halving; per op one row vector
  `(a, b, out, timestamp)` and one open-addressing hash map from
  `(a, b)` to its row; each rule a nested loop, one loop nest per
  semi-naive variant, over rows and counting-sort (CSR) indexes by class
  id; search all rules, then apply all (insert-or-find each right-hand
  node, union with the match's class), then rebuild (re-canonicalize
  every row, dedupe by hash, union on a conflict, repeat to a fixpoint),
  then rebuild the indexes; greedy tree-cost extraction after the last
  iteration.
- Check of equivalence: after 5, 6 and 7 iterations both engines hold the
  same node counts per op (772/810, 4,161/14,772, 633,739/7,363,672), and
  47,935,503 matches against egglog's 47,922,277 (*measured*); the e-graph
  after an iteration is fixed by the matches on the previous one, so
  equal counts are the semantic check.

### 2.2 Results

All *measured*, release builds, one thread unless named.

The headline (7 iterations, 7,997,421 nodes, 3,969,355 classes):

| engine | wall | split | ns per match | peak footprint |
| --- | --- | --- | --- | --- |
| egglog, `-j 1` | 26.4-31.8 s | search+apply 16-28%, merge 18-21%, rebuild 54-63% | 573-659 | 9.37 GB |
| egglog, `-j 8` | 10.3-10.4 s (user 29.8 s) | search+apply 39%, merge 6%, rebuild 56% | 211 | 8.67 GB |
| dense | 3.53-3.66 s | search 9-10%, apply 58-64%, rebuild 24-30%, index 2.5-2.7%, extraction 1% | 74-85 | 3.07 GB |

(egglog walls with `/usr/bin/time -p`, splits from `--save-report` runs;
the dense engine's from its own timers. The two egglog `-j 1` walls are
from the loaded and the lighter session.) In egglog's per-rule report,
associativity of `Mul` made 43,467,795 of the 47,922,277 matches (91%) and
took 89% of search and apply.

Per-function sizes (dense: best warm run of 3,000; egglog: three runs of
one 6-iteration program, cumulative phase time per iteration from
`--save-report`):

| iterations | nodes | dense | egglog | ratio |
| --- | --- | --- | --- | --- |
| 3 | 188 | 14 µs | 229-274 µs | 16-20× |
| 4 | 549 | 48 µs | 437-580 µs | 9-12× |
| 5 | 1,592 | 249 µs | 1,243-1,598 µs | 5.0-6.4× |
| 6 | 18,943 | 2.2-2.4 ms | 9.7-13.0 ms | 4.1-5.8× |

Dense engine, its own split and cost per node (*measured*, seeds 1 and
7): 19-188 nodes: 4-14 µs, index 26-48%; 549-1,592 nodes: 86-230
ns/node, search 9-18%, apply 36-53%, rebuild 23-39%, index 9-21%;
18,943 nodes: 118-124 ns/node; 8M nodes: 443-512 ns/node. The index
share at small sizes is a fixed O(class ids) counting sort per index per
iteration.

egglog's floor (*measured*, three small programs, 20 iterations): a
program whose one rule changes the e-graph every iteration costs 39-85 µs
in all (2-4 µs per iteration); 100 or 1,000 added rules that never match
add 1-6 ns per rule per iteration, even when their tables have new rows.
So egglog's small-size gap is not a per-rule floor; it is per-match and
per-tuple cost while matches exist.

The cost of iterating without change (*measured*, identity rules only,
200,000-leaf term, 101,637 nodes): 5 iterations 32 ms; 105 iterations
174 ms; 1,005 iterations 1.53 s. An idle iteration costs 1.4 ms, about 14
ns per node, all of it the full re-scan rebuild (59-61%) and the full
index rebuild (35-37%). That is what a non-incremental dense engine, or
one that repacks its relations each iteration, pays per step.

### 2.3 What the measurement shows, and what it does not

- Specialization (fixed arity, one table per op, keys packed into one
  word, rules as loops, no dynamic values, no merge functions) buys
  7-9× at 8M nodes and 4-20× at per-function sizes over egglog's
  interpreted backend on this workload. This sits inside what the
  compiled-Datalog record shows: Soufflé's interpreter with the same data
  structures is 1.32-5.67× slower than its generated C++, and its older
  interpreter with a run-time tuple comparator 9.8-43× slower (§3.1).
- Inside the specialized engine, the join is 9-20%; making nodes and
  canonicalizing them is 80-90%. Of the 3.5 s, about 2.2 s is apply,
  dominated by about 96M hash-cons probes into tables of 8M rows, which
  miss cache; 0.9 s is rebuild.
- It is one hand-written engine, one rule set, one term family, nine
  rules: no analyses, no conditions, no typed classes, no regions, no
  merge functions, no parallelism. The factor is an upper estimate of what
  specialization alone buys on pure rewriting; a generated engine that
  carries those features gives some of it back (*conjecture*: 1.5-3×). Its
  rebuild and indexes are full scans each iteration, which is cheap on
  this exploding workload and expensive on long schedules (the idle
  iteration above); a production engine needs egglog's incremental paths.
- Both engines are single-machine, one function's e-graph; neither
  measures what our IR adds (the region skeleton, effect classification,
  elaboration).

## 3. What compiled relational engines report, and what transfers

### 3.1 Soufflé

*read (agent)*: Scholz et al., CC 2016, Table 4 (OpenJDK7 points-to, about
840M tuples): an SQL engine with semi-naive evaluation 22,800 s; compiled
to C++ 850 s (26.8×); index consolidation 650 s; data-structure tuning
75 s (8.7×); parallel 35 s. Table 3: over 99% of run time is set
operations: inserts about 45%, membership about 35%, range queries about
15%, scans about 5%. Hu et al., PLDI 2021, §5.1, Fig. 15: the interpreter
with the same templated data structures is 1.32-5.67× slower than the
generated C++ (DOOP 1.59-2.2×); its older interpreter with a run-time
tuple comparator was 9.8-43× slower, so most of the gap was the
specialized data structures, not the plan; counting C++ compilation the
interpreter wins a first run by 6.46× (Table 1). The specialized B-tree
(PPoPP 2019) is insert-only and never frees nodes. `eqrel` (Nappa et al.,
PACT 2019): dense ids and a wait-free union-find in a growable array;
pairs are never stored, per-class lists are built on demand and dropped
on any insert; up to 5.4 orders of magnitude faster on real programs.

### 3.2 Ascent and BYODS

*read (agent)*: Ascent (CC 2022), Datalog compiled through Rust macros
with hash indexes, is 0.8-1.6× of Soufflé (Table 3) and 56-172× faster
than Flix (Table 2). BYODS (OOPSLA 2023): a union-find relation answers
eqrel at N=1600 in 0.0047 s against 191 s (Table 1); Steensgaard 120 ms
against Soufflé eqrel's 170 ms (§5.2).

### 3.3 Joins: Free Join, relational e-matching, compiled plans

- *read (agent)*: Free Join (Wang, Willsey, Suciu, SIGMOD 2023; arXiv
  2301.10841, `05-eval.tex:179-231`): JOB geomean 2.94× over DuckDB's
  binary join and 9.61× over Generic Join; the lazy column trie is 8.47×
  over eager tries; it is a plan interpreter in Rust. Kaboli et al.,
  arXiv 2505.19918: the same plans compiled through SDQL to C++ are
  1.42-1.49× faster by geomean, and "trie construction dominates the
  overall run time for most of the queries" (`5_experiments.tex:124`).
- *read (agent)*: relational e-matching (Zhang, Wang, Willsey, Tatlock,
  POPL 2022, `sources/papers/zhang-2022-relational-ematching/eval.tex:110-155`):
  one matching pass, worst-case optimal by Generic Join
  (`algorithm.tex:463-467`); total speedup over egg's matcher 1.66-2.6× on
  lambda and up to 119.8× on math at 217k nodes; best single pattern
  8.6M× without index building; worst 0.03× with it. Index building is
  about 56-60% of Generic Join's time; the gain is in large non-linear
  patterns with small outputs, while totals are dominated by linear
  patterns with many matches, such as associativity (`eval.tex:160-201`);
  hash tries are "difficult to update efficiently" (`discussion.tex:120-127`).
- *read (agent)*: egglog (PLDI 2023, `implementation.tex:252-261`): 3.34×
  over egg without semi-naive, 9.27× with it, at iteration 100; it beats
  compiled Soufflé on Steensgaard by 4.96× because it keeps a canonical
  representation, not by compilation (`pointer-analysis.tex:223`).

### 3.4 GPUs and parallelism

*read (agent)*: GDlog (`sources/papers/sun-2025-gpu-datalog`, H100 against
32-core Soufflé): 14.3 s against 233 s on 1.91B tuples; join 39% of run
time, merging the delta into the full relation 42% (§6.4); Soufflé spends
77.8% in serialized deduplication and insertion (§1); the GPU loses on
allocation at 1M-10M tuples (Table 7). SRDatalog (2026, arXiv 2604.20073):
rules compiled ahead of time to CUDA, 26× Soufflé by geomean, 5.4× at
1,542 iterations and 214× at 24; kernel launches bound the long tail of
tiny deltas (§6.1). No GPU e-graph engine found. Inside one e-graph,
parallel saturation plateaus at 1.7-2.6× on 8 threads, with merging
e-classes 30% of total time (Foresight, CC 2026, §7.3.2, read from the
PDF's text); matching scales, applying and rebuilding do not (ICCS 2026).
egglog: 8 threads help only large e-graphs (math, 12 iterations: 3.1× in
process) and slow down many small iterations (eggcc-2mm 0.64 s to 0.95 s)
(*measured (agent)*); parallel e-matching 1.0-1.28× (PR #954, *summary*).

### 3.5 Sparse tensor compilers, and MLIR's sparsifier

- *read (agent)*: Etch (PLDI 2023): at least 24× SQLite and 1.6× DuckDB on
  TPC-H Q5 and Q9, 0.75-1.2× of TACO (§8, Figs. 17, 19), over "static data
  structures ... data sets at rest" (§8.2). Finch: a tensor is read-only or
  update-only, switched by freeze and thaw (§3.1); freezing a hash level
  costs time proportional to all its entries, "not incremental
  construction" (§3.3.2). Galley: 5-20× median over DuckDB on subgraph
  counting, no outer loop around several inner ones. SDQL: hash
  dictionaries updated destructively inside one query, no recursion, no
  deletion; 1.4-23× TACO. STOREL: up to 16.4× TACO, read-only storage.
  TACO: inputs built by insert then pack; Chou's dynamic formats add
  insertion at 2.0-3.5× slower computation than CSR, no deletion. MLIR's
  sparsifier: 1.06-1.44× TACO (Bik et al. 2022, §7). None supports
  deletion or re-canonicalization.
- *read*, at the pin: the level formats are dense, batch, compressed,
  loose-compressed, singleton and n:m
  (`mlir/include/mlir/Dialect/SparseTensor/IR/SparseTensorAttrDefs.td:163-171`;
  `Enums.h:154-162`: no hash level). A sparse output is admissible only
  when its nonzero structure does not change ("simply dynamic") or when it
  "materializes uninitialized into the computation and insertions occur in
  lexicographic index order" (`lib/Dialect/SparseTensor/Transforms/Utils/CodegenEnv.cpp:155-179`,
  the materializing test at `:25-28`); the sparsifier's store is "direct
  insertion in lexicographic coordinate order" or the expanded access
  pattern of one innermost level (`Transforms/Sparsification.cpp:424-470`).
  There is no delete op in `SparseTensorOps.td`.
- **What follows for D86's route** (*conjecture*, from the above): a
  conjunctive query over a frozen snapshot is a sum of products over the
  Boolean semiring, which a `linalg.generic` over sparse operands
  expresses, and the sparsifier co-iterates it into specialized loops
  over positions and coordinates: that is the search, 9-20% of the dense
  engine. Inserting the right-hand sides into the hash-cons while
  searching, re-canonicalizing rows after unions, deduplicating, and
  keeping indexes current are mutations of a growing relation in an order
  no output format admits; they are D86's "loops elsewhere", 80-90% of
  the time. If the relations are packed into sparse tensors each
  iteration, every step pays O(table): 14 ns per node per step measured in
  §2.2, against egglog's incremental paths. The speed D85 asks for is
  then in those loops, the data structures under them, and their
  delta-proportional maintenance; the sparsifier compiles the minority
  part. D87's library is where a dynamic level would have to come from,
  as a design or an upstream change (§6).

### 3.6 What transfers to an e-graph

*conjecture*, drawn from §1-§3.5:
- Compiling the plan: 1.3-6× on the join (Soufflé 1.32-5.67×, compiled
  Free Join 1.42-1.49×), on the 9-20% (dense) or the trie-building and
  staging share of "search" (interpreted). End to end, compiling joins
  alone gives roughly 1.2-1.6×.
- Specializing the data structures: the larger part of the measured
  7-9× (fixed arity, packed keys, one table per op, no dynamic values),
  as Soufflé's history shows (9.8-43× before specialized structures).
- Algorithms and representation: the largest factors in the record
  (deferred rebuilding 21-88×, semi-naive 2.8×, eqrel 10⁵·⁴×, Soufflé's
  tuning 8.7×). For us, the representation's share is fewer nodes made:
  directional rules and Cranelift's `subsume` (egraph.md §1.2, §3.1),
  conditions checked before a right side is built, a per-rule match cap.
- What compilation does not remove: hashing, probing and random memory
  traffic of hash-cons inserts, union-find and re-canonicalization. They
  scale with nodes made, and they are what parallel engines fail to
  scale (Foresight's 30% in merging).

## 4. Termination and budgets

- **The theory** (*read (agent)*): termination of saturation is
  R.E.-complete for one instance and Π₂-complete for all terms; weak term
  acyclicity is a sufficient syntactic criterion (Suciu, Wang, Zhang, ICDT
  2025, arXiv 2501.02413, `intro.tex:414-473`). Associativity alone does
  not terminate, and a canonical rewriting system can diverge under
  saturation because its equalities run both ways; depth-bounded and
  merge-only saturation always terminate, and a rule whose right-side
  variables occur only at depth 1 terminates (Zhang and Flatt, EGRAPHS
  2023, §3-§6).
- **The measurement** (*measured*, §2.2): iterations do not bound time.
  The e-graph grew 2.9×, 2.9×, 11.9× and then 422× per iteration (188,
  549, 1,592, 18,943, 7,997,421 nodes); the eighth iteration did not
  finish in 100 s. Time is linear in nodes made (74-85 ns per match, 75-510 ns per
  node), so nodes are the unit that bounds it.
- **Bounds in program units** (*read (agent)*): nodes per class
  (Cranelift 5, `codegen/src/egraph/mod.rs:131`), matches per rule per
  iteration with an exponential ban (egg and egglog-experimental: 1000,
  ban 5; egg `run.rs:869-877`), a node cap relative to the input (Herbie:
  4,000 nodes, 50 iterations, the initial size subtracted,
  `src/config.rkt:130, 154`, `egg-herbie.rkt:1125-1128`), iteration counts
  per ruleset and multi-pattern rules for one iteration only (Tensat:
  50,000 nodes, 15 iterations, k_multi=1, because multi-patterns grow the
  e-graph O(N²) then O(N⁴), `main.tex:567-576, 750-755`; eggcc's `repeat`
  counts), term depth, merge-only rounds that cannot add nodes. Guided
  search reaches what unguided saturation cannot: sketch guidance applies
  all seven matrix-multiplication optimizations in seconds under 1 GB,
  where unguided saturation fails five of them at 1 h and 60 GB (Koehler
  et al., `conclusion.tex:7-8`); Ruler's Enumo finishes only by
  alternating growth with compression (`05-rulelifting.tex:175-214`).
- **What keeps full saturation practical here** (*conjecture*, within
  AGENTS.md and D57): a node budget per function, `B × ops(f)` (the
  arena's capacity, egraph.md §4.5), as the one bound that stops; a
  per-rule match cap with back-off, in matches, so that one rule cannot
  spend the budget (the measured run gave 91% of its matches to one
  rule); ruleset phases with iteration counts only as a schedule, never as
  a stop condition; merge-only rounds after the budget is spent, which
  cannot grow the graph and finish the congruence closure; and no wall
  time anywhere, since a time limit makes the output depend on the machine
  and breaks byte-identical output at any thread count (egraph.md §4.4). A
  spent budget leaves the program less optimized and refuses nothing.

## 5. The estimate at stage-1 scale

Everything here is *conjecture* built on the measured constants of §2 and
the scale *read* in `bench/records/2026-10-16-self-emit.md:30-31`: the S2.1
module holds 63,464 Core functions, 114,110 `idr.func` and 756,678 ops at
emit, about 6.6 ops per function, with matches of tens of thousands of
cases (e96bb991's 20,000-case fixture).

| input | value | ground |
| --- | --- | --- |
| ops at the e-graph's points | 1-3M (specialization and inlining grow the module) | conjecture from 0.76M at emit |
| node budget B | 16-64 nodes per op (for scale: Herbie caps an expression at 4,000 nodes; Tensat at 50,000; Cranelift's aegraph averages 1.13 nodes per class) | conjecture; the caps read (§4) |
| nodes made | 16M-190M over the module | B × ops |
| cost per node, function in cache (≤ 20k nodes) | 75-230 ns, dense engine; 0.2-0.5 µs once typed classes, analyses, conditions and the skeleton are carried | measured; the generality tax conjecture (1.5-3×) |
| cost per node, largest function (millions of nodes) | 0.45-1.5 µs | measured 443-512 ns; tax conjecture |
| extraction | 1-7% of saturation while effects stay in the skeleton | measured (§1.4) |
| parallelism | across functions, near-linear on 8 cores; none inside one function | conjecture; inside-one-graph parallelism plateaus (§3.4) |

- **CPU**: 16M nodes at 0.2 µs is about 3 s; 190M nodes at 0.35 µs about
  67 s.
- **Wall on 8 cores**: 0.4-9 s for everything but the largest function,
  which is linear in its own size and runs on one core: a match of 20,000
  cases is perhaps 100k-200k pure ops, at B=16-64 1.6M to 13M nodes, at
  0.45-1.5 µs per node 0.7-19 s. That tail sets the wall; its budget is
  the same rule (nodes per op), so a smaller B is the lever if it is too
  long, and it costs that one function some optimization, nothing else.
- **An interpreted engine at the same budget**: the 5-16× of §2.2 (egglog
  is the best interpreted engine measured, 2.3-2.6× faster than egg), so
  roughly 15 s to 20 min of CPU.
- **What dominates**: node creation (hash-cons probe and insert per
  right-side node, and its union), then canonicalization after merges,
  then index maintenance; the join is a tenth to a fifth. So the levers,
  in order: fewer nodes made (directional rules, conditions before
  construction, back-off), maintenance proportional to the delta, arenas
  small enough to stay in cache, and only then compiled joins.
- **What would move it**: a rule set whose matches per node differ from
  the arithmetic set's six; eggcc-style context or state rules (2.9× in
  eggcc, which egraph.md §2.2 avoids by refined values instead of
  contexts); schedules of thousands of small steps, where the fixed cost
  per step and per-step repacking dominate (§1.3, §2.2).

## 6. What is genuinely research

- **A generated engine at the measured factor.** No compiled e-graph
  engine has been measured against an interpreted one (§2.1). Whether an
  engine generated from the Idris specification keeps a 5-9× factor
  while carrying typed classes, analyses with `make`, `join` and
  `modify`, side conditions, the region skeleton and elaboration is open;
  §2 is one hand-written point.
- **Dynamic relations in MLIR's sparse pipeline.** A level that grows by
  hashed or unordered insertion, with deletion and re-canonicalization,
  exists in no sparse-tensor system found (§3.5), and the pinned
  sparsifier rejects it. Without it, D86's printed engine compiles its
  joins sparsely and its maintenance as plain loops; with it, the design
  and the upstream work are new.
- **Delta-proportional maintenance in compiled form.** egglog chooses
  between incremental and full rebuilds by a cost model per table; egg
  keeps parent lists. Both are known; doing it in printed loops over
  caller-owned tables, without a general allocator, is design work, not
  research, but no system has measured it.
- **Schedules that reach the good programs within a budget.** Beyond the
  termination results there is no theory of which nodes should fill a
  budget; back-off, phases, guidance and merge-only rounds are empirical.
- **Effects and regions inside the graph at full saturation.** Contexts
  cost eggcc 2.9×; effect-safe extraction is NP-complete; statewalk DP is
  polynomial only in bounded width.
- **Parallelism inside one e-graph**: plateaus at 1.7-2.6×; across
  functions it is free, and the largest function stays serial.
- **Optimal extraction with sharing** (NP-hard): e-boost and SmoothE close
  most of the gap to ILP on published benchmarks, none of them ours.

## 7. Sources

- Ours: `AGENTS.md`; `.claude/skills/representation-first/SKILL.md`;
  `proposals/0000-mlir-native.md` (D57, D69, D84-D87);
  `audits/p0/design/egraph.md` (whole), `perf-sources.md` (§0, §1),
  `egraph-full/one-engine.md` (§0, skimmed for the route);
  `bench/records/2026-10-16-self-emit.md:20-35`,
  `2026-10-17-self-growth.md`.
- MLIR at the pin 7208ba24: `include/mlir/Dialect/SparseTensor/IR/{SparseTensorAttrDefs.td:130-260,SparseTensorOps.td,Enums.h:150-165}`;
  `lib/Dialect/SparseTensor/Transforms/Sparsification.cpp:395-470`,
  `Transforms/Utils/CodegenEnv.cpp:20-30, 150-182`.
- Outside code (commits in the status line), read by me or this task's
  agents at the lines named: egglog (`core-relations`, `egglog-bridge`,
  `union-find`, `src/{lib,extract,scheduler}.rs`, `cli.rs`), egg
  (`src/{machine,run}.rs`), eggcc (`dag_in_context/src/{lib,schedule}.rs`,
  `infra/`), egglog-experimental (`src/scheduling.rs`), extraction-gym,
  herbie (`src/config.rkt`, `src/core/egglog-herbie.rkt`,
  `egg-herbie.rkt`), wasmtime (`cranelift/codegen/src/egraph/mod.rs`).
- Papers in `sources/papers/`: `willsey-2021-egg`, `zhang-2023-egglog`,
  `zhang-2022-relational-ematching`, `yang-2021-tensat`,
  `koehler-2021-sketch-eqsat`, `pal-2023-ruler`, `jordan-2016-souffle`,
  `sun-2025-gpu-datalog`, `kjolstad-2017-taco`, `bik-2022-sparse-mlir`.
  Fetched: Flatt et al., OOPSLA 2026, arXiv 2609.31887 (eggcc, the TeX in
  `/tmp/eqsat-research/eggcc`); Scholz et al., CC 2016; Hu et al., PLDI
  2021; Jordan et al., PPoPP 2019; Nappa et al., PACT 2019; Sahebolamri et
  al., CC 2022 and OOPSLA 2023; Wang, Willsey, Suciu, SIGMOD 2023 (arXiv
  2301.10841); Kaboli et al., arXiv 2505.19918; Kovach et al., PLDI 2023
  (Etch); Ahrens et al. (Looplets, Finch); Deeds et al. (Galley); Shaikhha
  et al., OOPSLA 2022 (SDQL); STOREL, SIGMOD 2023; Chou et al. 2022;
  Suciu, Wang, Zhang, ICDT 2025 (arXiv 2501.02413); Zhang and Flatt,
  EGRAPHS 2023; Foresight, CC 2026; ICCS 2026; SRDatalog, arXiv
  2604.20073; e-boost, arXiv 2508.13020; SmoothE, ASPLOS 2025.
- Weaker ground (*summary* only): egglog PR #954 (parallel speedups),
  herbie PRs #1646 and #1676, Goharshady et al. OOPSLA 2024 (treewidth
  extraction), MCTS-GEB, Metatheory.jl's README.
- Scaffolding outside the repository, not committed:
  `/tmp/egraph-full-speed/dense/{eg.cpp,rules.egg,p-12-*.egg,rep.py,cum.py}`
  (the dense engine and the comparison), `/tmp/egraph-full-speed/{scripts,out}`
  (the measurement agent's runs), `/tmp/egraph-full-speed/{lit,read}` (the
  reading agents' downloads).
