# Proposals

Designs, numbered in the order they were written: one file,
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
specification. A proposal that is done is deleted, and one nearly done
keeps only what remains.

- [0001](0001-rust-interop.md): Rust as the one foreign world. Bindings
  are generated from rustdoc's JSON as runtime primitives, shims are
  linked as bitcode, Rust values live in counted cells, and ownership
  becomes the compiler's grades. Not started.
- [0002](0002-representation-cutover/README.md): the representation
  cutover, integrated. What remains is its qualification: the suites on
  both targets, the bench, peak live cells and `tests/upstream-idris`,
  never run since; two measurements not yet proved; the in-place promise
  made the default; and the seams the lanes left.
- [0003](0003-llvm-trunk.md): the LLVM pin on a trunk commit, done but
  for one step: the bootstrap and every suite on both targets with the
  patches the tree carries.
- [0004](0004-typed-apl/README.md): a typed APL. Arrays of any rank with
  shapes as erased types, rank polymorphism with frames and cells, index
  sets, the full operator vocabulary, and shape arithmetic in the
  elaborator. It lowers to tensor and linalg with fusion, tiling and
  One-Shot Bufferize meeting the grades, plus SPMD on the runtime of 0005.
  Two companion files go deeper on the compiler and on the type theory.
  Proposed.
- [0005](0005-shards.md): shards, the concurrency runtime. One copy of the
  single-threaded runtime per core, task frames for computations that
  wait, a reactor per shard, values crossing only inside messages, and
  Rust futures polled on the reactor. Its decisions are taken; the plan
  waits for launch.
- [0006](0006-flattened-data.md): compiler-chosen flattened layouts of
  algebraic data. Packed preorder trees (Gibbon) when the exclusive grade
  proves no sharing, and columnar layouts (Arrow-style) for collections and
  arrays of records, with one reference count per region and packed data
  as the shard message format. Proposed.
- [0007](0007-typechecker.md): a state-of-the-art type checker for the fork.
  Flat, hash-consed terms, glued evaluation, compiled reduction through
  idris-mlir, tabled search, shape arithmetic and a rewrite ladder, solvers
  that search while the kernel checks, a separate small kernel, and
  parallel elaboration, each stage measured against a baseline. Proposed.
- [0008](0008-otel.md): OpenTelemetry for Idris, after Mercury's
  hs-opentelemetry. Linear spans that must end exactly once, attributes
  typed by key and generated from the semantic-conventions registry,
  task-local context carried across fork/join and messages, a no-op
  provider removed at compile time, per-shard buffers and metrics with no
  atomics, and the compiler tracing its own phases. Proposed.
