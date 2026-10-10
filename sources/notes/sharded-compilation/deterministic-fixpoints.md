# Deterministic parallel fixpoints, scheduling and partitioning

Notes of the sharded-compilation cluster, 2026-10-10, for proposal 0011. Paths starting
`docs/`, `code/` or `papers/` are stored here; everything else was **read online on
2026-10-10 and is not stored**, except the items of §8, fetched the same day after the
owner's approval. Claims are marked
**measured**, **read** or **unverified**.

Contents: 1 what the library already held; 2 work stealing and its shared-nothing forms;
3 deterministic parallelism; 4 parallel and incremental Datalog; 5 parallel CFA and SCCs;
6 parallel elaboration; 7 partitioning; 8 snapshots fetched; 9 the recipe for 0011.

## 1. Already stored, and library findings

- `papers/jordan-2016-souffle/` (CAV 2016): **measured** OpenJDK 7 points-to in 35 s on an
  8-core desktop. `papers/jordan-2019-concurrent-btree/` (PPoPP 2019): optimistic
  read-write locks and access hints; **measured** "up to 6×" on membership tests and at least
  8.5× over TBB.
- `papers/newton-2016-parallel-type-checking/` is, by its content, **Fogg, Tobin-Hochstadt,
  Newton, "Parallel Type-checking with Saturating LVars"** (draft; venue unverified).
  **measured** "up to 8.46× parallel speedup" on HM inference and Typed Racket; futures over
  immutable data were "not a good fit". The folder name is misleading.
- `papers/sun-2025-gpu-datalog/` (ASPLOS 2025): hash-indexed sorted arrays; **measured** up
  to 45× over Soufflé on context-sensitive points-to.
- `papers/wenzel-2009-parallel-isabelle/`, `papers/barras-2015-async-coq/`,
  `papers/pacak-2020-incremental-type-checkers/`, `papers/filliatre-2006-hash-consing/`,
  `papers/michael-1996-concurrent-queues/`, `papers/kivity-2019-seastar/`,
  `docs/seastar/`, `docs/tokio/`, `docs/go-scheduler/`, `docs/rustc-parallel/`.
- **Index gaps**: no INDEX.md rows for `jordan-2016-souffle`, `jordan-2019-concurrent-btree`,
  `newton-2016-parallel-type-checking`, `sun-2025-gpu-datalog`; `kivity-2019-seastar` and
  `michael-1996-concurrent-queues` are in the not-yet-indexed list. All six were indexed on
  2026-10-10 under INDEX.md's "Sharded and incremental compilation".

## 2. Work stealing, and what it becomes without a shared heap

- **read** Blumofe, Leiserson, JACM 1999: expected time T1/P + O(T∞); space S1·P;
  communication O(P·T∞·(1+n_d)·S_max). Communication scales with P·T∞, not with total work,
  and with the size of what a steal moves: **tasks must carry handles, not bodies.**
- **read** Chase–Lev deque (SPAA 2005; read through Lê, Pop, Cohen, Zappa Nardelli, PPoPP
  2013): one CAS per steal, none on push. A shared-memory primitive.
- **read** Cilk-5 (PLDI 1998, abstract): the work-first principle; steals are assumed rare.
- **read** Zhang et al., "GLB: Lifeline-based Global Load Balancing" (arXiv 1312.5691; after
  Saraswat et al., PPoPP 2011): **stealing across distributed memory by message**. A failed
  thief tries w random victims, then registers on lifeline graphs; a victim with work later
  pushes it down a lifeline. Work is a user `TaskBag` with `split` and `merge`; results by
  `reduce`. **measured** nearly linear to 16K cores. The closest published model to stealing
  under 0009's runtime.
- **read** `docs/seastar/`, Glommio: thread per core, explicit cross-core messages, **no
  work stealing**. `docs/tokio/`: steals half a victim's queue, at most half the workers
  searching, a LIFO slot for locality.

## 3. Deterministic parallelism

- **read** Kuper, Newton, "LVars", FHPC 2013 (no open PDF found): writes are joins in a
  lattice, reads are threshold reads; determinism by construction.
- **read** Kuper, Turon, Krishnaswami, Newton, "Freeze After Writing", POPL 2014 (PDF 798 KB):
  handler pools and `quiesce` for fixpoints; `freeze` reads exact contents, a later
  conflicting write is an error ("quasi-determinism"); freezing as the last step gives full
  determinism. **measured** parallel k-CFA up to 202× total over the functional baseline.
- **read** Bocchino et al., "Deterministic Parallel Java", OOPSLA 2009 (via a course summary):
  regions partition the heap; effect summaries checked statically. Shard ownership is region
  disjointness by construction.
- **read** Blelloch, Fineman, Gibbons, Shun, "Internally Deterministic Parallel Algorithms
  Can Be Fast", PPoPP 2012 (PDF 375 KB): a unique dependence graph per input; **deterministic
  reservations** (reserve by priority write, then commit, in rounds); and **scan labeling**:
  distinct elements get labels by a prefix sum, equal to a serial numbering.
- **read** Shun, Blelloch, "Phase-Concurrent Hash Tables for Determinism", SPAA 2014 (PDF
  325 KB): inserts with inserts, finds with finds; the state at a quiescent point is
  independent of operation order (history-independent linear probing). **measured** up to 52×
  on 40 cores.
- **read** Slog (Gilray et al., arXiv 2211.11573): fact ids are bucket bits plus a per-bucket
  bump pointer — **schedule-dependent unless each bucket's input is sorted first**.

## 4. Parallel and incremental Datalog

- **read** Slog's backend, the concrete distributed semi-naive design: bulk-synchronous rounds
  of (relational kernels, all-to-all exchange, local insertion); delta and total per relation;
  tuples hash on join-key columns to a bucket and on the rest to a sub-bucket; joined
  relations share a bucket decomposition; heavy buckets split; round-robin sub-bucket
  placement beats hashing; termination by a global size check. Encodes CFAs and
  defunctionalization.
- **read** Kumar, Gilray, "Distributed Relational Algebra at Scale", HiPC 2019 (abstract):
  **measured** transitive closure producing 276 billion edges on 32,768 processes.
- **read** BigDatalog (SIGMOD 2016, abstract): with a generalized pivot, partition on that
  argument and recursion needs no shuffle (transitive closure on argument 1).
- **read** RecStep (PVLDB 2019): 4–6× over parallel engines; graph engines and
  program-analysis engines do not transfer performance to each other.
- **read** McSherry et al., "Differential Dataflow", CIDR 2013 (PDF 1.7 MB): collections over
  a partial order of versions, traces of differences, incrementally maintained iteration
  (SCC included), sharded by key; correctness independent of interleaving.
- **read** DRed (Gupta, Mumick, Subrahmanian, SIGMOD 1993, via secondary summary):
  over-delete, re-derive, insert. Not needed while facts only grow within one build.

## 5. Parallel CFA, points-to, SCCs

- **read** Doop (OOPSLA 2009): the whole points-to analysis in Datalog; **measured** over 15×
  faster than Paddle at equal precision, from join optimization, not parallelism.
- **read** MLton's closure conversion (`docs/mlton/`, ClosureConvert, Closure): 0CFA, then
  closures as sums with coercions — the serial baseline 0011's label relation reproduces.
- **read** Fleischer, Hendrickson, Pınar, IPDPS workshops 2000 (via secondary sources):
  forward-backward SCC — the intersection of forward and backward reachability from a pivot
  is one SCC; recurse on the rest in parallel. FB-Trim peels size-1 SCCs first, which suits
  call graphs. **The pivot must be canonical** (the least stable id); the SCC set is unique,
  but numbering and condensation order must be sorted after.

## 6. Parallel elaboration

- **read** `papers/wenzel-2009-parallel-isabelle/`: proofs as futures; Amdahl-limited by the
  join after each theory.
- **read** `papers/barras-2015-async-coq/`: worker processes; task requests and responses
  must be marshalable; marshalling the state was the main difficulty. **Task inputs must be
  small, closed, serializable values** — the same rule 0009 imposes on messages.
- **read** Lean 4 v4.19.0 release notes: theorem bodies elaborated in parallel with each other
  and with other elaboration.
- **measured** GHC `-jsem`: 22% on lens, 29% on pandoc; modules wait for all dependencies.

## 7. Partitioning

- **read** METIS (Karypis, Kumar 1998): coarsen, partition, refine, O(|E|) for k-way; its
  matching is randomized — seed it, or it breaks determinism.
- **read** GCC balanced partitioning and rustc CGU merging: §2 and §4 of
  `whole-program-at-scale.md`. Both sort, both bound partition size, rustc names merged units
  by hashing sorted names.

## 8. Snapshots (fetched 2026-10-10)

Approved by the owner and fetched on 2026-10-10; provenance in each folder's `README.md` and in
`sources/README.md` (access record, "Sharded-compilation pass").

| Folder | Source | Size | Status |
| --- | --- | --- | --- |
| `papers/blumofe-1999-work-stealing/` | https://klasses.cs.uchicago.edu/archive/2011/winter/32102-1/reading/steal.pdf | 390 KB | stored: PDF, `papers/blumofe-1999-work-stealing/paper.pdf` |
| `papers/le-2013-weak-memory-work-stealing/` | https://fzn.fr/readings/ppopp13.pdf | 989 KB | stored: PDF, `papers/le-2013-weak-memory-work-stealing/paper.pdf` |
| `papers/zhang-2013-glb/` | arXiv 1312.5691 (TeX e-print preferred) | about 2 MB PDF | stored: TeX (arXiv e-print), `papers/zhang-2013-glb/` |
| `papers/kuper-2014-freeze-after-writing/` | https://www.cl.cam.ac.uk/~nk480/lvish-popl.pdf | 798 KB | stored: PDF, `papers/kuper-2014-freeze-after-writing/paper.pdf` |
| `papers/blelloch-2012-internally-deterministic/` | https://jshun.csail.mit.edu/determ.pdf | 375 KB | stored: PDF, `papers/blelloch-2012-internally-deterministic/paper.pdf` |
| `papers/shun-2014-phase-concurrent-hash/` | https://jshun.csail.mit.edu/hash.pdf | 325 KB | stored: PDF, `papers/shun-2014-phase-concurrent-hash/paper.pdf` |
| `papers/gilray-2022-slog/` | arXiv 2211.11573 (TeX e-print preferred) | 945 KB PDF | stored: TeX (arXiv e-print), `papers/gilray-2022-slog/` |
| `papers/mcsherry-2013-differential-dataflow/` | http://www.cidrdb.org/cidr2013/Papers/CIDR13_Paper111.pdf | 1.7 MB | stored: PDF, `papers/mcsherry-2013-differential-dataflow/paper.pdf` |

## 9. The recipe this evidence supports

1. Every global relation is a **monotone set**, sharded by the hash of a canonical, content-
   derived key; relations that join on a column share a decomposition (Slog), and a pivot
   partition avoids shuffles in recursion (BigDatalog).
2. **Bulk-synchronous semi-naive rounds**: join deltas, route derived tuples to owners as
   messages, insert and dedupe, end on a global "anything new?" reduction; read only the
   **frozen** result (LVars). Round counts depend on the schedule only if propagation is
   asynchronous: keep it synchronous.
3. **Non-monotone facts** ("unique at every call site") are the complement of a monotone dual
   ("shared somewhere"), read after freeze.
4. **Identifiers in two phases**: content hashes during the fixpoint; after freeze, sort per
   shard and scan-label in shard order, which equals serial numbering; check hash collisions
   by full equality at the owner.
5. **Balance by over-decomposition and placement first**; message-based stealing (GLB's
   split/merge bags) only if measured idle time demands it; tasks carry ids, and frozen facts
   are replicated or sliced, never shipped per task.
