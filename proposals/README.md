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
- [0004](0004-tensors.md): pure array programs as tensors until
  bufferization. A raise to `linalg` on tensors, fusion and tiling,
  One-Shot Bufferize with the linear grade kept, rank above 1, and SPMD
  through `shard-partition` on the runtime of 0005. Proposed.
- [0005](0005-shards.md): shards, the concurrency runtime. One copy of the
  single-threaded runtime per core, task frames for computations that
  wait, a reactor per shard, values crossing only inside messages, and
  Rust futures polled on the reactor. Its decisions are taken; the plan
  waits for launch.
