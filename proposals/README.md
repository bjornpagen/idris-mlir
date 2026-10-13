# Proposals

Designs, numbered in the order the work starts: one file,
`NNNN-short-name.md`, or one directory, `NNNN-short-name/`, whose
`README.md` is the proposal and whose other files are what it is executed
from. A proposal states what it would change, which rules of AGENTS.md
it keeps, the staged plan, the alternatives it rejects, and each decision
it takes, with its reason or the measurement rule and threshold that
settles it. Claims are marked by their ground: read (the path given),
measured, recalled (from memory, to be checked), conjecture, or decision.

When the user decides, the decision is recorded in the proposal that owns
the topic, in its Decisions section, and the plan becomes work. There is
no separate record of decisions: once built, the code is the
specification. A proposal that is done is deleted, and the rest are not
renumbered again. One nearly done keeps only what remains. A proposal can
start before a later one it partly needs; the stages that wait are named
here.

The order of the work, decided by the owner on 2026-10-12: the cutover
(0015, executing 0014) is integrated; self-hosting (0014 §6.1) resumes
on it now; then 0007's stage 1 (the array purge and MLIR-first rebuild,
one cutover that ports the fork's array users); then sharding (0011's S0, S1, S2 and S8 with 0009's P1, P2 and P4). After
them the array style is the organizing principle: 0007's typed array
language, with 0016's interpreter, 0005's tables and 0008's layouts as
its consumers, and 0006's checker on 0016's machine; 0010's fixed-plan
joins are 0007's sparse half. 0004's features follow `make self`.
Parked, with the reason in each status line: 0010, 0011's S3 to S6 and
S9 to S10, 0013, and 0009's P3. Numbers are not reused: 0001, 0002 and
0003 were folded into 0014 and 0016, and 0012 was dropped.

- [0004](0004-self-host-features.md): the compiler features self-hosting
  asked for. A ledger of every rewrite self-hosting forced, and the
  features, each compiled away on the whole program (an erased match a
  runtime index forces, polymorphic recursion, dependent result and field
  types as specializations or closed sums, existentials and runtime types
  as defunctionalized sums, equality a primitive decides with its proof),
  no slower than the code they replace. The cutover settled part of the
  diet these touch (no quantity zero, no newtype, saturated methods).
  Not on the self-host path; starts when `make self` is green. A sketch.
- [0005](0005-data-oriented-frontend.md): a data-oriented, array-first
  frontend. The compiler's state as columnar tables keyed by typed ids,
  each pass as table operations, on 0016's arena. A consumer of 0007's
  array style. O2 waits on 0014's parse measurement; O3 and O7 are parked
  with 0010. Proposed.
- [0006](0006-typechecker.md): a state-of-the-art type checker for the
  fork, built on 0016's arena and machine: tabled search, shape
  arithmetic and a rewrite ladder, solvers that search while the kernel
  checks, and a separate small kernel, each stage measured against a
  baseline. T7 waits on 0009. Proposed.
- [0007](0007-typed-apl/README.md): a typed array language, MLIR first.
  Every fact Idris proves about an array has one image in MLIR, the one
  upstream optimizes on: shapes as ranked tensor types with static
  dimensions where the program fixes them, typed indices as accesses with
  no guard, linear threads as destination-passing chains One-Shot
  Bufferize puts in place, unordered combines as `linalg` reductions,
  formats as `#sparse_tensor.encoding`. Its sparse half carries relations
  and the compiler's semiring analyses (0005's multiplicity check,
  size-change composition). Purges today's array stack (about 6,300
  lines, `idr-in-bounds` among them) in one cutover, right after
  self-hosting. One file now: `compiler.md` and `types.md` are merged and
  deleted. Decided by the owner, 2026-10-12.
- [0008](0008-flattened-data.md): compiler-chosen flattened layouts of
  algebraic data. Packed preorder trees when the exclusive grade proves no
  sharing, columnar layouts for collections and arrays of records, one
  reference count per region, packed data as the shard message format. A
  consumer of 0007's array style; 0016's arena takes its layouts. Shard
  messages wait on 0009. Proposed.
- [0009](0009-shards.md): shards, the concurrency runtime. One copy of the
  single-threaded runtime per core, task frames for computations that
  wait, a reactor per shard, values crossing only inside messages. P1, P2
  and P4 are the second priority, with 0011; P3 is parked with 0013. Its
  decisions are taken.
- [0010](0010-relational-core.md): the relational core,
  `libs/mlir-relational`: worst-case optimal joins, semi-naive fixpoints,
  e-graphs with relational e-matching. Parked: nothing on the path to
  self-hosting or sharding needs it.
- [0011](0011-sharded-whole-program-compiler.md): a sharded whole-program
  compiler. The whole program stays the unit of meaning and stops being
  the unit of work. S0, S1, S2 and S8 are the second priority, and S2 is
  pulled into the self-host plan as the first lever on LLVM's single
  module. S7 is done by the cutover. S3 to S6 and S9 to S10 are parked.
  Proposed.
- [0013](0013-rust-interop.md): Rust as the one foreign world. Bindings
  are generated from rustdoc's JSON as runtime primitives, shims are
  linked as bitcode, Rust values live in counted cells, and ownership
  becomes the compiler's grades. Parked: nothing before the array work
  needs a foreign world.
- [0014](0014-get-back-on-track.md): get back on track. The self-host
  wall is representational: a handoff larger than the program, facts held
  in several places, and every pass a module pass verifying the whole
  program. The design the cutover executes, the self-host plan (§6.1),
  and what remained of the LLVM pin and of the representation cutover
  (§12), which is its gate G1. Executed by 0015.
- [0015](0015-cutover-swarm/README.md): the cutover swarm. 0014 as one
  cutover with no compatibility owed: the C++ side as an in-tree MLIR
  dialect in upstream's layout with `.cpp` and `.h`, `idr.func` with
  inherent facts, analyses under the pass manager, function passes in
  parallel with threading on, the frontend emitting no erased value and
  readable names with locations, and Tracy as a pinned profile preset.
  Committed and unbuilt; deleted once G1 qualifies it.
- [0016](0016-array-interpreter.md): the array interpreter. Static
  normalization and the type checker's evaluator as one array program:
  the hash-consed term arena as columns, and a wavefront machine that
  advances every live state at once, one kernel per kind of term per
  step, with array operations as whole-array runtime primitives. Takes
  over the former 0003 (its decisions D1 to D5 kept), 0005's arena and
  0006's evaluator. Its first stage after the arena is a measured gate
  against a plain loop. Starts after self-hosting. Proposed.

Contiguous runs (one run cell for strings, arrays and buffers) have no
proposal. A wasm32 target entry for bumbledb's TypeScript package is not
proposed; it is a target, and it is not the evaluator.
