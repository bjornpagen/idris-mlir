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

The order of the work, decided by the owner on 2026-10-12: 0001 now
(qualifying its packet 0002 is its §6.1's first steps, self-hosting the
rest); then 0003's stage 1 (the array purge and MLIR-first rebuild, one
cutover that ports the fork's array users); then sharding (0004's P1,
P2 and P4 with 0005's S0, S1, S2 and S8). After them the array style is
the organizing principle: 0003's typed array language, with 0006's
interpreter, 0007's tables and 0008's layouts as its consumers, and
0009's checker on 0006's machine; 0011's fixed-plan joins are 0003's
sparse half. 0010's features may start any time after `make self`;
nothing waits on them. Parked, with the reason in each status line:
0011, 0012, 0005's S3 to S6 and S9 to S10, and 0004's P3.

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
  readable names with locations, and Tracy as a pinned profile preset.
  Committed and unbuilt; deleted once G1 qualifies it.
- [0003](0003-typed-apl/README.md): a typed array language, MLIR first.
  Every fact Idris proves about an array has one image in MLIR, the one
  upstream optimizes on: shapes as ranked tensor types with static
  dimensions where the program fixes them, typed indices as accesses with
  no guard, linear threads as destination-passing chains One-Shot
  Bufferize puts in place, unordered combines as `linalg` reductions,
  formats as `#sparse_tensor.encoding`. Its sparse half carries relations
  and the compiler's semiring analyses (0007's multiplicity check,
  size-change composition). Stage 1 purges today's array stack (about
  6,300 lines, `idr-in-bounds` among them) in one cutover, right after
  self-hosting; the language's later stages follow sharding, with 0006,
  0007 and 0008 as consumers. Decided by the owner, 2026-10-12.
- [0004](0004-shards.md): shards, the concurrency runtime. One copy of
  the single-threaded runtime per core, task frames for computations
  that wait, a reactor per shard, values crossing only inside messages.
  P1, P2 and P4 are the sharding work, with 0005; P3 is parked with
  0012. Its decisions are taken.
- [0005](0005-sharded-whole-program-compiler.md): a sharded
  whole-program compiler. The whole program stays the unit of meaning
  and stops being the unit of work. S0, S1, S2 and S8 are the sharding
  work, with 0004, and S2 is pulled into 0001's self-host plan as the
  first lever on LLVM's single module. S7 is done by the cutover. S3 to
  S6 and S9 to S10 are parked. Proposed.
- [0006](0006-array-interpreter.md): the array interpreter. Static
  normalization and the type checker's evaluator as one array program:
  the hash-consed term arena as columns, and a wavefront machine that
  advances every live state at once, one kernel per kind of term per
  step, with array operations as whole-array runtime primitives. Takes
  over the former static-normalization proposal (its decisions D1 to D5
  kept), 0007's arena and 0009's evaluator. Its first stage after the
  arena is a measured gate against a plain loop. Starts after
  self-hosting. Proposed.
- [0007](0007-data-oriented-frontend.md): a data-oriented, array-first
  frontend. The compiler's state as columnar tables keyed by typed ids,
  each pass as table operations, on 0006's arena. A consumer of 0003's
  array style. O2 waits on 0001's parse measurement; O3 and O7 are
  parked with 0011. Proposed.
- [0008](0008-flattened-data.md): compiler-chosen flattened layouts of
  algebraic data. Packed preorder trees when the exclusive grade proves
  no sharing, columnar layouts for collections and arrays of records,
  one reference count per region, packed data as the shard message
  format. A consumer of 0003's array style; 0006's arena takes its
  layouts. Shard messages wait on 0004. Proposed.
- [0009](0009-typechecker.md): a state-of-the-art type checker for the
  fork, built on 0006's arena and machine: tabled search, shape
  arithmetic and a rewrite ladder, solvers that search while the kernel
  checks, and a separate small kernel, each stage measured against a
  baseline. T7 waits on 0004. Proposed.
- [0010](0010-self-host-features.md): the compiler features
  self-hosting asked for. A ledger of every rewrite self-hosting forced,
  and the features, each compiled away on the whole program (an erased
  match a runtime index forces, polymorphic recursion, dependent result
  and field types as specializations or closed sums, existentials and
  runtime types as defunctionalized sums, equality a primitive decides
  with its proof), no slower than the code they replace. The cutover
  settled part of the diet these touch (no quantity zero, no newtype,
  saturated methods). May start any time after `make self`; ordered
  here because nothing waits on it. A sketch.
- [0011](0011-relational-core.md): the relational core,
  `libs/mlir-relational`: worst-case optimal joins, semi-naive
  fixpoints, e-graphs with relational e-matching. Parked: nothing on
  the path to self-hosting or sharding needs it; it is taken up when
  its first consumer (0007's O3 and O7, 0005's S4, 0009's search)
  starts.
- [0012](0012-rust-interop.md): Rust as the one foreign world. Bindings
  are generated from rustdoc's JSON as runtime primitives, shims are
  linked as bitcode, Rust values live in counted cells, and ownership
  becomes the compiler's grades. Parked: nothing before the array work
  needs a foreign world.

Contiguous runs (one run cell for strings, arrays and buffers) have no
proposal. A wasm32 target entry for bumbledb's TypeScript package is not
proposed; it is a target, and it is not the evaluator.
