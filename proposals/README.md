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

- [0001](0001-llvm-trunk.md): the LLVM pin on a trunk commit. Built on
  arm64 macOS, with `make build`, `make check`, `make test-idr` and
  `make test-mlir-tools` green at 8395d4f7, and `make self` showing stage
  2 identical to stage 3. What remains is the same suites on x86_64 Linux.
  Two `make test` programs, `every-interfaces-export` and
  `every-types-export`, hit their time limits and are set aside. Deleted
  when Linux is green.
- [0002](0002-representation-cutover/README.md): the representation
  cutover, integrated. What remains is its qualification: the program
  corpus and the Linux suites, the bench, peak live cells and
  `tests/upstream-idris`, two measurements not yet proved, the in-place
  promise made the default, and the seams the lanes left.
- [0003](0003-static-normalization.md): static normalization, and no
  compile-time evaluation feature. The compiler normalizes the static part
  of the program on the type checker's interpreter, with array operations
  as whole-array primitives: closed calls of total code become values or,
  past a counted budget, startup constants; partly static calls specialize
  on the arguments that steer control, of which monomorphisation is the
  type case; partial and covering code is never normalized. `idr-eval` is
  out of the simplify round; N2 deletes the pass. N3 waits on the term
  arena and on whole-array primitives. Decided (2026-10-10); not built.
- [0004](0004-self-host-features.md): the compiler features self-hosting
  asked for. A ledger of every rewrite self-hosting forced (improvements
  kept, regressions replaced when a feature lands), and the features, each
  compiled away on the whole program (an erased match a runtime index
  forces, polymorphic recursion, dependent result and field types as
  specializations or closed sums, existentials and runtime types as
  defunctionalized sums, equality a primitive decides with its proof),
  no slower than the code they replace. Stage 0 and `make self` are done.
  The six features are a sketch. Interned names (0005 O1) replace the
  name-equality traversal; the proofs stay here.
- [0005](0005-data-oriented-frontend.md): a data-oriented, array-first
  frontend. The compiler's state as columnar tables keyed by typed ids,
  and each pass as table operations. Owns the term arena. Early stages
  use today's arrays; the rank-polymorphic end state waits on 0007. O3
  and O7 wait on 0010. Staged by measured cost, each stage proved by
  identical TTCs. Proposed.
- [0006](0006-typechecker.md): a state-of-the-art type checker for the fork.
  Builds the interpreter on 0005's term arena. The three normalization
  rules are 0003's. Tabled search, shape arithmetic and a rewrite ladder,
  solvers that search while the kernel checks, and a separate small kernel,
  each stage measured against a baseline. T6 waits on 0007's arrays. T7
  waits on 0009. Proposed.
- [0007](0007-typed-apl/README.md): a typed APL. Arrays of any rank with
  shapes as erased types, rank polymorphism with frames and cells, index
  sets, the full operator vocabulary, and shape arithmetic in the
  elaborator. It lowers to tensor and linalg with fusion, tiling and
  One-Shot Bufferize meeting the grades. Multicore waits on 0009. The
  shape solver waits on 0006's rewrite ladder where a shape does not
  already reduce. Two companion files go deeper on the compiler and on
  the type theory. Proposed.
- [0008](0008-flattened-data.md): compiler-chosen flattened layouts of
  algebraic data. Packed preorder trees (Gibbon) when the exclusive grade
  proves no sharing, and columnar layouts for collections and arrays of
  records, with one reference count per region and packed data as the
  shard message format. The term arena is 0005's, not a stage here. Shard
  messages wait on 0009. Proposed.
- [0009](0009-shards.md): shards, the concurrency runtime. One copy of the
  single-threaded runtime per core, task frames for computations that
  wait, a reactor per shard, values crossing only inside messages.
  Per-shard startup constants are 0003's cost rule; this proposal says
  which shard computes one. The Rust-async stage waits on 0013. Its
  decisions are taken; the plan waits for launch.
- [0010](0010-relational-core.md): the relational core,
  `libs/mlir-relational`, shared by the frontend, the elaborator,
  bumbledb's port and user programs. Relations and worst-case optimal
  joins, semi-naive fixpoints, and e-graphs with relational e-matching;
  the executor an interpreter specialized per prepared query. Its columns
  are 0008's. Its first consumer is 0005's instance fixpoint. Proposed.
- [0011](0011-sharded-whole-program-compiler.md): a sharded whole-program
  compiler. The whole program stays the unit of meaning and stops being
  the unit of work. S0–S3 and S5–S7 need the bootstrap and 0003's N2; S4
  needs 0010; S8 needs 0009 and 0005. S0 can be recorded on the built
  arm64 toolchain. Proposed.
- [0012](0012-otel.md): OpenTelemetry for Idris, after Mercury's
  hs-opentelemetry. Linear spans that must end exactly once, attributes
  typed by key and generated from the semantic-conventions registry,
  task-local context carried across fork/join and messages, a no-op
  provider removed by static normalization, per-shard buffers and metrics
  with no atomics, and the compiler tracing its own phases. Per-shard
  buffers wait on 0009. Proposed.
- [0013](0013-rust-interop.md): Rust as the one foreign world. Bindings
  are generated from rustdoc's JSON as runtime primitives, shims are
  linked as bitcode, Rust values live in counted cells, and ownership
  becomes the compiler's grades. Off the compiler's critical path.
  bumbledb's storage stage waits on it. Not started.

Contiguous runs (one run cell for strings, arrays and buffers) have no
proposal. A wasm32 target entry for bumbledb's TypeScript package is not
proposed; it is a target, and it is not the evaluator.
