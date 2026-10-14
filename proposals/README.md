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

## Where the work stands (2026-10-14, at 2295e06b)

**Code bankruptcy is declared: no code changes land until the owner
approves these proposals.** First in the queue is licensing (0001):
SPDX provenance on every file, so that porting state of the art --
Mojo's where Mojo is structurally better, MLIR's everywhere else --
is mechanical and auditable. Then the compile-time refactor (0004),
whose measurement (F0) is taken and whose two attempted shortcuts
are measured, reverted and recorded in its §2.1.

The cutover is built and, on arm64 macOS, green: `make check` 26/26,
`make test-idr` 286/286, `make test` 415/415 (*measured* 2026-10-14).
x86_64 Linux has still not run the cutover tree: G1 (0002 §12) is
NotRun there, never green. Stage 1 of `make self` has still never
finished: the frontend emits the whole of itself (58,236 functions,
~300 MB of text, ~140 s) and the C++ pipeline does not finish on it.
That one fact orders the queue.

The first compile-time round (0004's F1, in part) landed 2026-10-13
and 2026-10-14 and is recorded in 0004 §2: one Simplify round on the
stage-0 module fell from 1,321 s to 385 s (dev build, *measured* in
the commits). The rounds themselves, the text handoff and LLVM's
single module remain. They are the wall, and 0004 and 0006 are written
as one architecture in two steps: **the whole program stays the unit
of meaning and stops being the unit of work.** Every fact a guarantee
rests on (the instance set, closure sums, exclusivity, layouts) stays
whole-program forever; every body of work (rewrites, LLVM, codegen)
moves to the smallest boundary its facts allow — call-graph SCCs for
`idr` passes, size-balanced units for LLVM. On the stage-0 module the
largest direct-call SCC is 174 of 58,235 functions and 93% are
singletons (*measured* 2026-10-14 over the corpus's `idr.call` edges;
closure applies are not in that graph, so it is a lower bound on
coupling, re-measured after inlining at F0). Namespaces are not that
boundary: 17% of distinct origin-to-origin direct-call pairs stay in
one module (*measured*, same probe). Modules produce summaries and
keep partitions stable under edits; SCCs do the work.

The order of the work, decided by the owner on 2026-10-12, amended
2026-10-13 to insert compile time, and re-cut 2026-10-14 as one
maximalist cutover with no compatibility owed to any legacy mechanism
the new shape replaces: 0001 first (licensing, so every port after it
is clean); then 0002 (G1, then self-hosting §2, whose step 3 is
0004's F0 record -- taken -- and takes 0006's split codegen as soon
as the record names codegen); 0004's remaining stages interleaved
with it, because stage 1 cannot finish without them; 0003's stage 1 (the
array purge) right after `make self`; then sharding (0005's P1, P2 and
P4 with 0006's S-stages). After them the array style is the organizing
principle: 0003's typed array language, with 0007's interpreter,
0008's tables and 0009's layouts as its consumers, and 0010's checker
on 0007's machine; 0012's fixed-plan joins are 0003's sparse half.
0011's features may start any time after `make self`; nothing waits on
them. Parked, with the reason in each status line: 0012, 0013, 0006's
S3 to S6 and S9 to S10 until the F0/S0 record calls for them, and
0005's P3.

Renumberings of 2026-10-14: first the built cutover packet was
deleted and the queue closed up (dcb087d2 holds that map); then
licensing took 0001 and every other proposal moved up one (this
commit's message holds the map). Dated records (`HANDOFF.md`
entries, `bench/runs/`, `sources/`) keep the numbering then in
force.

- [0001](0001-licensing.md): licensing: every file says whose it is.
  SPDX provenance across the tree -- ours (0BSD), Mojo/MLIR ports
  (Apache-2.0 WITH LLVM-exception), the Idris fork (BSD-3-Clause) --
  the porting protocol that takes state of the art fearlessly, and
  the third-party inventory. Done first; decided 2026-10-14.
- [0002](0002-get-back-on-track.md): get back on track. The design the
  cutover executed; what remains is G1 (§12: x86_64 Linux, the bench on
  both targets, compile times) and self-hosting (§6.1). Deleted when
  §6.1 step 5 (`make self`, stage 2 byte-identical to stage 3) is
  recorded in HANDOFF.md.
- [0003](0003-typed-apl/README.md): a typed array language, MLIR first.
  Every fact Idris proves about an array has one image in MLIR, the one
  upstream optimizes on. Stage 1 purges today's array stack (about
  6,300 lines, `idr-in-bounds` among them) in one cutover right after
  `make self`; the later stages follow sharding. Decided 2026-10-12.
- [0004](0004-compile-time.md): compile time: one fast serial pipeline.
  Deletes the whole-module Simplify fixed point and every multiplier
  under it (module fingerprints, per-round analysis rebuilds, uncached
  symbol scans, serial dataflow per round, the text handoff) for one
  bottom-up SCC pipeline with bounded inner per-function work. F0 is
  recorded and the first fixes landed (§2); two InlineCleanup
  refactors were measured and reverted (§2.1); F2 to F5 remain, F3
  being 0006's S6 done once, serially.
- [0005](0005-shards.md): shards, the concurrency runtime. One copy of
  the single-threaded runtime per core, task frames for computations
  that wait, a reactor per shard, values crossing only inside
  messages. Its decisions are taken.
- [0006](0006-sharded-whole-program-compiler.md): a sharded
  whole-program compiler. Summaries per module, guarantee facts from
  summaries alone, work per SCC/codegen unit with fact slices and
  import lists, content-named partitions, an ordered link. S2 (split
  LLVM codegen) is pulled into 0002 §6.1 step 3.
- [0007](0007-array-interpreter.md): the array interpreter. Static
  normalization and the type checker's evaluator as one array program
  over a hash-consed term arena. Starts after self-hosting.
- [0008](0008-data-oriented-frontend.md): a data-oriented, array-first
  frontend: compiler state as columnar tables on 0007's arena.
- [0009](0009-flattened-data.md): compiler-chosen flattened layouts of
  algebraic data, packed and columnar, chosen per value by proof.
- [0010](0010-typechecker.md): a state-of-the-art type checker for the
  fork, built on 0007's arena and machine.
- [0011](0011-self-host-features.md): the compiler features
  self-hosting asked for, each compiled away on the whole program at
  no runtime price. A sketch; may start after `make self`.
- [0012](0012-relational-core.md): the relational core,
  `libs/mlir-relational`. Parked until its first consumer starts.
- [0013](0013-rust-interop.md): Rust as the one foreign world. Parked:
  nothing before the array work needs a foreign world.

Contiguous runs (one run cell for strings, arrays and buffers) have no
proposal. A wasm32 target entry for bumbledb's TypeScript package is
not proposed; it is a target, and it is not the evaluator.
