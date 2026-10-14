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

## Where the work stands (2026-10-14, at b4713f66)

The cutover (former 0002, deleted in this renumbering; its remains are
0001's §12) is built and, on arm64 macOS, green: `make check` 26/26,
`make test-idr` 286/286, `make test` 415/415 (*measured* 2026-10-14).
x86_64 Linux has still not run the cutover tree: G1 (0001 §12) is
NotRun there, never green. Stage 1 of `make self` has still never
finished: the frontend emits the whole of itself (58,236 functions,
~300 MB of text, ~140 s) and the C++ pipeline does not finish on it.
That one fact orders the queue.

The first compile-time round (0003's F1, in part) landed 2026-10-13
and 2026-10-14 and is recorded in 0003 §2: one Simplify round on the
stage-0 module fell from 1,321 s to 385 s (dev build, *measured* in
the commits). The rounds themselves, the text handoff and LLVM's
single module remain. They are the wall, and 0003 and 0005 are written
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
the new shape replaces: 0001 now (G1, then self-hosting §6.1, whose
step 3 is 0003's F0 record and takes 0005's split codegen as soon as
the record names codegen); 0003's remaining stages interleaved with
§6.1, because stage 1 cannot finish without them; 0002's stage 1 (the
array purge) right after `make self`; then sharding (0004's P1, P2 and
P4 with 0005's S-stages). After them the array style is the organizing
principle: 0002's typed array language, with 0006's interpreter,
0007's tables and 0008's layouts as its consumers, and 0009's checker
on 0006's machine; 0011's fixed-plan joins are 0002's sparse half.
0010's features may start any time after `make self`; nothing waits on
them. Parked, with the reason in each status line: 0011, 0012, 0005's
S3 to S6 and S9 to S10 until the F0/S0 record calls for them, and
0004's P3.

Renumbering of 2026-10-14 (this commit): the cutover packet
`0002-cutover-swarm/` is deleted, its unfinished qualification folded
into 0001 §12; 0003→0002 (typed APL), 0004→0003 (compile time),
0005→0004 (shards), 0006→0005 (sharded compiler), 0007→0006 (array
interpreter), 0008→0007 (data-oriented frontend), 0009→0008
(flattened data), 0010→0009 (type checker), 0011→0010 (self-host
features), 0012→0011 (relational core), 0013→0012 (Rust interop).
Dated records (`HANDOFF.md` entries, `bench/runs/`, `sources/`) keep
the numbering then in force.

- [0001](0001-get-back-on-track.md): get back on track. The design the
  cutover executed; what remains is G1 (§12: x86_64 Linux, the bench on
  both targets, compile times) and self-hosting (§6.1). Deleted when
  §6.1 step 5 (`make self`, stage 2 byte-identical to stage 3) is
  recorded in HANDOFF.md.
- [0002](0002-typed-apl/README.md): a typed array language, MLIR first.
  Every fact Idris proves about an array has one image in MLIR, the one
  upstream optimizes on. Stage 1 purges today's array stack (about
  6,300 lines, `idr-in-bounds` among them) in one cutover right after
  `make self`; the later stages follow sharding. Decided 2026-10-12.
- [0003](0003-compile-time.md): compile time: one fast serial pipeline.
  Deletes the whole-module Simplify fixed point and every multiplier
  under it (module fingerprints, per-round analysis rebuilds, uncached
  symbol scans, serial dataflow per round, the text handoff) for one
  bottom-up SCC pipeline with bounded inner per-function work. F0 is
  recorded and the first fixes landed (§2); two InlineCleanup
  refactors were measured and reverted (§2.1); F2 to F5 remain, F3
  being 0005's S6 done once, serially.
- [0004](0004-shards.md): shards, the concurrency runtime. One copy of
  the single-threaded runtime per core, task frames for computations
  that wait, a reactor per shard, values crossing only inside
  messages. Its decisions are taken.
- [0005](0005-sharded-whole-program-compiler.md): a sharded
  whole-program compiler. Summaries per module, guarantee facts from
  summaries alone, work per SCC/codegen unit with fact slices and
  import lists, content-named partitions, an ordered link. S2 (split
  LLVM codegen) is pulled into 0001 §6.1 step 3.
- [0006](0006-array-interpreter.md): the array interpreter. Static
  normalization and the type checker's evaluator as one array program
  over a hash-consed term arena. Starts after self-hosting.
- [0007](0007-data-oriented-frontend.md): a data-oriented, array-first
  frontend: compiler state as columnar tables on 0006's arena.
- [0008](0008-flattened-data.md): compiler-chosen flattened layouts of
  algebraic data, packed and columnar, chosen per value by proof.
- [0009](0009-typechecker.md): a state-of-the-art type checker for the
  fork, built on 0006's arena and machine.
- [0010](0010-self-host-features.md): the compiler features
  self-hosting asked for, each compiled away on the whole program at
  no runtime price. A sketch; may start after `make self`.
- [0011](0011-relational-core.md): the relational core,
  `libs/mlir-relational`. Parked until its first consumer starts.
- [0012](0012-rust-interop.md): Rust as the one foreign world. Parked:
  nothing before the array work needs a foreign world.

Contiguous runs (one run cell for strings, arrays and buffers) have no
proposal. A wasm32 target entry for bumbledb's TypeScript package is
not proposed; it is a target, and it is not the evaluator.
