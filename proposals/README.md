# Proposals

Designs, numbered in literally the order the work is done, low to high:
one file, `NNNN-short-name.md`, or one directory, `NNNN-short-name/`,
whose `README.md` is the proposal and whose other files are what it is
executed from. The number is the queue position, nothing else: when the
order changes, or a proposal is done and deleted, the rest are
renumbered in one commit that moves the files and every reference, so
the listing always reads as the plan. Numbers in earlier commits and
dated records name the numbering then in force; the renumbering
commit's message holds the map. A proposal states what it would change,
which rules of AGENTS.md it keeps, the staged plan, the alternatives it
rejects, and each decision it takes, with its reason or the measurement
rule and threshold that settles it. Claims are marked by their ground:
read (the path given), measured, recalled (from memory, to be checked),
conjecture, or decision.

When the user decides, the decision is recorded in the proposal that
owns the topic, in its Decisions section, and the plan becomes work.
There is no separate record of decisions: once built, the code is the
specification. A proposal that is done is deleted. One nearly done
keeps only what remains. A proposal can start before a later one it
partly needs; the stages that wait are named here.

The order of the work, decided by the owner on 2026-10-12 and amended
2026-10-13 to insert 0004: 0001 now (qualifying its packet 0002 is its
§6.1's first steps, self-hosting the rest); then 0003's stage 1 (the
array purge and MLIR-first rebuild, one cutover that ports the fork's
array users); then 0004 (compile time: the serial pipeline made fast,
its stages interleavable with 0003's stage 1, its F0 the stage-1
self-compile record 0006's S0 wants); then sharding (0005's P1, P2 and
P4 with 0006's S0, S1, S2 and S8). After them the array style is
the organizing principle: 0003's typed array language, with 0007's
interpreter, 0008's tables and 0009's layouts as its consumers, and
0010's checker on 0007's machine; 0012's fixed-plan joins are 0003's
sparse half. 0011's features may start any time after `make self`;
nothing waits on them. Parked, with the reason in each status line:
0012, 0013, 0006's S3 to S6 and S9 to S10, and 0005's P3.

- [0001](0001-get-back-on-track.md): get back on track. The self-host
  wall is representational: a handoff larger than the program, facts held
  in several places, and every pass a module pass verifying the whole
  program. The design the cutover executes, the self-host plan (§6.1),
  and what remained of the LLVM pin and of the representation cutover
  (§12), which is its gate G1. Executed by 0002.
- [0002](0002-cutover-swarm/README.md): the cutover swarm. 0001 as one
  cutover with no compatibility owed: the C++ side as an in-tree MLIR
  dialect in upstream's layout with `.cpp` and `.h`, `idr.func` with
  inherent facts, analyses under the pass manager, function passes in
  parallel with threading on, the frontend emitting no erased value and
  readable names with locations, and profiling through the pass
  manager (a time trace since D8, in 0001).
  Committed, and it builds; deleted once G1 qualifies it.
- [0003](0003-typed-apl/README.md): a typed array language, MLIR first.
  Every fact Idris proves about an array has one image in MLIR, the one
  upstream optimizes on: shapes as ranked tensor types with static
  dimensions where the program fixes them, typed indices as accesses with
  no guard, linear threads as destination-passing chains One-Shot
  Bufferize puts in place, unordered combines as `linalg` reductions,
  formats as `#sparse_tensor.encoding`. Its sparse half carries relations
  and the compiler's semiring analyses (0008's multiplicity check,
  size-change composition). Stage 1 purges today's array stack (about
  6,300 lines, `idr-in-bounds` among them) in one cutover, right after
  self-hosting; the language's later stages follow sharding, with 0007,
  0008 and 0009 as consumers. Decided by the owner, 2026-10-12.
- [0004](0004-compile-time.md): compile time: one fast serial pipeline.
  Sharding divides T1; this cuts it, before sharding: the whole-module
  Simplify fixed point (13 passes to 64 rounds, a SHA1 fingerprint of
  the module per round, analyses rebuilt per round, uncached symbol
  scans) replaced by one flat pass list in the shape Mojo's KGEN proves
  — duplicate functions merged first, one bottom-up SCC inline and
  specialize pass with a bounded inner per-function pipeline, region
  simplification off, serial dataflow nested per function, bytecode
  handoff and content-keyed per-function memos in-process. Measured in
  stages against the stage-0 self module (its F0 is 0006's S0), each
  landing only if faster, byte-identical and deterministic at 1/2/8
  threads; target at least 10x on the stage-1 pipeline. Inserted by the
  owner, 2026-10-13, renumbering 0004-0012 to 0005-0013. Proposed.
- [0005](0005-shards.md): shards, the concurrency runtime. One copy of
  the single-threaded runtime per core, task frames for computations
  that wait, a reactor per shard, values crossing only inside messages.
  P1, P2 and P4 are the sharding work, with 0006; P3 is parked with
  0013. Its decisions are taken.
- [0006](0006-sharded-whole-program-compiler.md): a sharded
  whole-program compiler. The whole program stays the unit of meaning
  and stops being the unit of work. S0, S1, S2 and S8 are the sharding
  work, with 0005, and S2 is pulled into 0001's self-host plan as the
  first lever on LLVM's single module. S7 is done by the cutover. S3 to
  S6 and S9 to S10 are parked. Proposed.
- [0007](0007-array-interpreter.md): the array interpreter. Static
  normalization and the type checker's evaluator as one array program:
  the hash-consed term arena as columns, and a wavefront machine that
  advances every live state at once, one kernel per kind of term per
  step, with array operations as whole-array runtime primitives. Takes
  over the former static-normalization proposal (its decisions D1 to D5
  kept), 0008's arena and 0010's evaluator. Its first stage after the
  arena is a measured gate against a plain loop. Starts after
  self-hosting. Proposed.
- [0008](0008-data-oriented-frontend.md): a data-oriented, array-first
  frontend. The compiler's state as columnar tables keyed by typed ids,
  each pass as table operations, on 0007's arena. A consumer of 0003's
  array style. O2 waits on 0001's parse measurement; O3 and O7 are
  parked with 0012. Proposed.
- [0009](0009-flattened-data.md): compiler-chosen flattened layouts of
  algebraic data. Packed preorder trees when the exclusive grade proves
  no sharing, columnar layouts for collections and arrays of records,
  one reference count per region, packed data as the shard message
  format. A consumer of 0003's array style; 0007's arena takes its
  layouts. Shard messages wait on 0005. Proposed.
- [0010](0010-typechecker.md): a state-of-the-art type checker for the
  fork, built on 0007's arena and machine: tabled search, shape
  arithmetic and a rewrite ladder, solvers that search while the kernel
  checks, and a separate small kernel, each stage measured against a
  baseline. T7 waits on 0005. Proposed.
- [0011](0011-self-host-features.md): the compiler features
  self-hosting asked for. A ledger of every rewrite self-hosting forced,
  and the features, each compiled away on the whole program (an erased
  match a runtime index forces, polymorphic recursion, dependent result
  and field types as specializations or closed sums, existentials and
  runtime types as defunctionalized sums, equality a primitive decides
  with its proof), no slower than the code they replace. The cutover
  settled part of the diet these touch (no quantity zero, no newtype,
  saturated methods). May start any time after `make self`; ordered
  here because nothing waits on it. A sketch.
- [0012](0012-relational-core.md): the relational core,
  `libs/mlir-relational`: worst-case optimal joins, semi-naive
  fixpoints, e-graphs with relational e-matching. Parked: nothing on
  the path to self-hosting or sharding needs it; it is taken up when
  its first consumer (0008's O3 and O7, 0006's S4, 0010's search)
  starts.
- [0013](0013-rust-interop.md): Rust as the one foreign world. Bindings
  are generated from rustdoc's JSON as runtime primitives, shims are
  linked as bitcode, Rust values live in counted cells, and ownership
  becomes the compiler's grades. Parked: nothing before the array work
  needs a foreign world.

Contiguous runs (one run cell for strings, arrays and buffers) have no
proposal. A wasm32 target entry for bumbledb's TypeScript package is not
proposed; it is a target, and it is not the evaluator.
