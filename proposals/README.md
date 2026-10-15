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

## Where the work stands (2026-10-15)

**Coded and integrated, not built.** 0004's cutover with 0003's stage 1
(c7aa7b62, 5d5f3312) and, on top of it, 0005 (bfdcac70, one swarm wave
of eighteen lanes): on the typecheck machine, which builds no LLVM,
`make typecheck` passes every part and `make check` is 32/32. Nothing of
either has been built or run anywhere. The owner's machine owes, before
anything else (HANDOFF.md): `make bootstrap` (patch 24 changed), `make
build`, `make test`, `make test-idr` and `make test-mlir-tools` with the
`NEEDS-ACCEPTANCE` files accepted (134 by HANDOFF.md's count; `git grep
-l NEEDS-ACCEPTANCE -- tests` lists 145 at bfdcac70), determinism at 1,
2 and 8 threads,
the bench, and `make self`. x86_64 Linux is NotRun. 0005's audit of the
cutover's tree found facts held by convention, concepts held two to four
times, refusals by fuel and count, and 35 bugs by reading; 0005 §4 is
what the tree now is and its §11 what execution decided.

**Totality, as it stands.** "Acceptance never depends on an optimizer
count" holds by construction and by `tests/spec/totality`, which reads
structure; it is not machine-proven. The C++ terminates by structure,
argued in its comments. Idris proves termination in 38 of compiler/src's
57 modules (`%default total`) and in all of `libs/`. The 18
Frontend/Translate and driver modules are `%default covering`,
`Translate/Closed.idr`, the fuel-free reduction, among them: its
head-path argument is informal. One `assert_total` remains in
`compiler/src/IdrisMLIR/Ids.idr:311` and one in
`libs/mlir-array/Linear/Vec.idr`, the crash path. The next step (0005
§12): the frontend's modules made `%default total`, the head-path rule
written as well-founded recursion over the unvisited definitions (as
`Emit/Index.idr` already does with `Accessible`), and `Ids.idr`'s
`assert_total` replaced by structural recursion.

**The next chain**, in order: qualify on the owner's machine (bootstrap,
build, the three suites with acceptance, determinism, the bench); `make
self` (0002 §2 step 5; `tools/self.sh` now compares the `.mlirbc` and
records peak memory through `tools/host.sh`, on both targets); x86_64
Linux (0002 §5, the owner's question of where it runs); 0002's step 6,
the test runner off Chez; 0004 §5.4's second step, the split before O3;
then 0006's P1. Two small items are owed beside it, neither waiting on
the chain: the frontend's totality proof above; and the fork's
elaborator bug, `checkCaseDelayed`
(`compiler/idris/src/TTImp/Elab/Case.idr:394-404`) retrying a
scrutinee at linear only on a bare `LinearMisuse`, so that an ambiguous
name on the right of a linear pattern `let` fails, fixed in the fork as
our own code, recorded in PINS.md with its change against the pin in
`upstream/<bug>/pull-request.diff` (AGENTS.md).

Everything is on `main` in the one checkout: no branches,
no worktrees, locally or on the remote (*decision*, the owner's
standing rule, restated 2026-10-14). Agent-run heavy work on the
owner's 12-CPU machine uses `NCPU=6`; tool defaults stay maximalist
(7a27fd34).

0004 answers its question first: defunctionalization becomes total by
analysis alone, as MLton's closure conversion is (a verified closed
world, one flow interface, a forced-state anchor per lazy value type,
no unknown element in the label set; 0004 §2), so inlining,
specialization and every budget are pure optimization and never
reject a program. Then one bottom-up ready set over the call graph's
SCCs replaces the Simplify rounds: each function is cleaned once, after
its callees are final, under MLton's inline formula applied once and a
per-caller cap of 10,000 ops (0004 §4 stage 7). Effects, constants and
binding times are one summary per function, read at each call from its
callee (0005 D13), names come from content, facts live in types and
inherent properties, and code generation is split into size-balanced
bins of SCCs grouped by top-level namespace, 2^15 LLVM instructions
each, so their count follows the program's size and never the thread
count (0004 §5.3). No option, toggle, fallback or dual path survives
(0004 D2, §6). The research is stored verbatim in
`sources/notes/compile-pipeline/`, with the MLton
(`sources/code/mlton`, 43 files at aa2fd1ad) and Mojo
(`sources/code/modular`, at 9211931) sources it cites. The opt-in
`scc-pipeline` of 552d682a, whose corpus run was killed without a
verdict, was deleted by the cutover (0004 §3.3, §6).

The last built tree, on arm64 macOS, is the one before the cutover: the
cutover 0002 designed, committed and building. Its gate was green at
7a27fd34, before the opt-in SCC pipeline (`make check` 26/26, `make
test-idr` 286/286, `make test` 415/415), and at 552d682a and its
file-size split df5d8742, which added that opt-in, default off, with
0001's licenses gate (`make build` clean, `make check` 27/27, 286/286,
415/415); *measured* 2026-10-14 at `NCPU=6`, both runs on the Simplify
rounds. The cutover deleted the opt-in and the rounds together, and its
proof must reproduce the rounds' 415/415. `make check` was 27/27 at
ccaba89c and is 32/32 at bfdcac70 (*measured* on the typecheck machine).
x86_64 Linux has not run any of it: 0002's G1 is NotRun there, never
green. Stage 1 of `make self` has never finished: the frontend emits the
whole of itself (58,236 functions, about 300 MB of text, about 140 s)
and the rounds' C++ pipeline did not finish on it (0004 §3.1). The
cutover is what was to make it finish; nothing has measured that yet.

The first compile-time round landed 2026-10-13 and 2026-10-14 and is
recorded in 0004 §3.1: one explicit Simplify round on the stage-0
module fell from 1,321 s to 385 s (dev build; *measured*, 5088d7a8),
and the suite record from 248.8 s to 167.9 s over 429 compilations
(*recalled*: the suite record was not kept, and G1's run before the
cutover, which was to re-record it, was not taken, 0002 §3). Until the
cutover deleted them, the rounds were the wall: sixteen of them reached
no fixpoint, and
Simplify alone extrapolated past 2,000 s unfinished (*measured*,
`bench/profiles/2026-10-14-f0-stage0.md`, F0). 0004 and 0007 are one
architecture in two steps: **the whole program stays the unit of
meaning and stops being the unit of work.** Every fact a guarantee
rests on (the instance set, closure sums, quantities, exclusivity,
layouts) is decided once, on the whole program, and read frozen;
every body of work moves to the smallest boundary its facts allow:
call-graph SCCs for the `idr` passes, size-balanced bins for LLVM.
The structure is there: at emission the largest direct-call SCC is 174
of 58,235 functions and 93% are singletons, and after six rounds the
largest is 24 of 28,276 (*measured*, F0; closure applies are not edges
of that graph, and after the cutover every apply is a dispatch of
direct calls, 0004 §2.7). Idris modules are not that boundary: 17% of
distinct origin-to-origin direct-call pairs stay in one module and 49%
in one top-level namespace (*measured*, F0), which is why bins are
grouped by namespace and cut by content (0004 §5.3). 0007 shards the
same pipeline: summaries per module keep partitions stable under
edits, and the ready set's nodes and the bins are its units.

The order of the work, decided by the owner on 2026-10-12, amended
2026-10-13 to insert compile time, and re-cut 2026-10-14 as one
maximalist cutover with no compatibility owed to any legacy mechanism
the new shape replaces (0002 D1), and as it went: 0001 first
(licensing, built but for its L5 and L6); 0004's cutover, before
0002's remaining self-host steps, because stage 1 cannot finish without
it (it takes 0007's first S0 record, S1 and S2's first step), with
0003's stage 1 (the array purge) in the same swarm wave by the owner's
decision of 2026-10-14, and 0005 on top of it, decided and dispatched
on 2026-10-15; all three coded and integrated, none built. 0002's G1
run before the cutover, beside 0004's lane L0 (0002 §3, D14), was not
taken: the waves ran on the typecheck machine, so the qualification
reads the bench against the 2026-10-13 record and stage 0's optimizer
against 0004 §10's 600 s margin, as HANDOFF.md's list says. Then the chain above: the qualification,
`make self` (0002's step 5, with step 4's diet and memory record taken
from its run), x86_64 Linux, step 6, 0004 §5.4's split before O3; then
sharding (0006's P1, P2 and P4 with 0007's S-stages). After them
the array style is the organizing principle: 0003's stages 2 to 8,
with 0008's interpreter, 0009's tables and 0010's layouts as its
consumers, and 0011's checker on 0008's machine; 0013's fixed-plan
joins are 0003's sparse half. 0012's features may start any time after
`make self`; nothing waits on them.

Stages that wait on something besides the queue, each with its rule in
its proposal: 0007's S3 to S6, each taken when S0's second record (from
the cutover's first builds, on the owner's machine) shows its part above 5% of
one-worker wall; 0007's S9 (the cache) after S2's second step; 0007's
S8 and S10 (the Idris half in parallel, on 0006's shards) after
0006's P4 and 0009's O3; 0006's P5,
each item on its measurement. Parked, with the reason in each status
line: 0013, until its first consumer starts, which is 0009's O3 (R1
and R2 are built before it); 0014, which nothing before the array work
needs, and with it 0006's P3 and 0011's T8.

Questions only the owner can settle, each with its default taken in
the proposal that owns it: 0001 §5 (GMP's licence, with counsel) and
0001 §9 (whether a port's changes note names only what changed, which
amends his D1; default yes, path and revision in PINS.md alone), 0002
§5 (where G1's x86_64 Linux leg runs), and 0008 §13 (the restated forms
of the owner's D3 and D5 for static normalization). Every other
question in the queue is decided.

Renumberings: on 2026-10-14, first the built cutover packet was
deleted and the queue closed up (dcb087d2 holds that map); then
licensing took 0001 and every other proposal moved up one (77994b30
holds that map). On 2026-10-15 the representation wave took 0005 and
the queue after it moved down by one, 0005-0013 becoming 0006-0014
(1f4170c0). Dated records (`HANDOFF.md` entries, `bench/runs/`,
`sources/`) keep the numbering then in force.

- [0001](0001-licensing.md): licensing: every file says whose it is.
  SPDX provenance across the tree (ours 0BSD; Mojo and MLIR ports
  Apache-2.0 WITH LLVM-exception; the Idris fork BSD-3-Clause), the
  porting protocol that takes the state of the art fearlessly, and the
  third-party inventory. **Built and pushed 2026-10-14** (3a275cf0,
  L1 to L4). What remains is L5 (the dialect generator writes its own
  SPDX line) and L6 (the sweep's scope is every tracked file less one
  listed exclusion set, and the gate reads its facts from the data that
  holds them), both proved by `make check` on the typecheck machine.
  §5's GMP question is the owner's, with counsel; its default is
  LGPL-3.0 §4(d)(0) through a relink kit (D7). Whether a port's changes
  note names only what changed is his too (§9; default yes). The
  `foreign/idr/` rename is decided against (D8). L5 and L6 were to land
  before 0004's packet (D12); both waves ran without them, so they are
  ordinary work on `main`, any time. Deleted when L5 and L6 are built
  and the owner accepts the built state.
- [0002](0002-get-back-on-track.md): get back on track. The design the
  cutover executed; what remains is G1 (§3: x86_64 Linux, the bench on
  both targets, compile times), whose run before 0004's cutover was not
  taken and which now runs once, on the tree after the cutover and 0005,
  and self-hosting (§2), whose steps 4 to 6 follow that qualification.
  One question is the owner's: where G1's Linux leg runs
  (default: a native x86_64 Linux machine of the owner's). Deleted when
  G1 is green on both targets after 0004's cutover and §2's steps 5 and
  6 are recorded in HANDOFF.md (D13).
- [0003](0003-typed-apl/README.md): a typed array language, MLIR first.
  Every fact Idris proves about an array has one image in MLIR, the one
  upstream optimizes on. Stage 1, which purged the array stack before
  it (about 6,300 lines, `idr-in-bounds` among them) and rebuilt it in
  one hard cutover, is coded and integrated with 0004's (c7aa7b62,
  5d5f3312), its proof owed on the owner's machine. 0005, integrated on
  top of it, reversed its D13 (arrays are ops end to end, lowered one to
  one, 0005 D6), declared the generating set once as bodiless `%extern`s
  (D5) and split record arrays into columns in `idr-columns` (D20).
  Stages 2 to 7 follow sharding, and stage 8 needs 0006's P4.
  Decided 2026-10-12, reconciled with 0004 on 2026-10-14.
- [0004](0004-compile-time/README.md): whole-program facts, a fixed optimizer,
  parallel code generation. The pipeline cutover, coded and integrated
  with 0003's stage 1 (c7aa7b62, 5d5f3312), its proof owed on the owner's
  machine: defunctionalization total by analysis, one bottom-up ready set
  over call-graph SCCs, specialization as content-keyed nodes, effects and
  constants as SCC summaries, names from content, facts in types,
  partitioned code generation, and the deletion of every option, toggle,
  fingerprint, seed mark and budget-as-refusal. 0005 changed several of
  its mechanisms (the root and stage, constructors, forces, call effects,
  the specialization budget, the flow interface, boxing, the layout
  limit); its §0 lists them and §11 marks each decision 0005 superseded.
  What remains of it after the qualification is §5.4's split before O3.
- [0005](0005-representation/README.md): one representation for every
  fact, and no fuel. A constructor is its tag and a label holds its
  function, a force is a call, the program and its stage are an op, the
  array generating set is declared once and lowered from its own ops, one
  account of how a value moves, one type interface for what a value holds,
  the runtime ABI and guards generated from ODS, one summary per function,
  bufferization through upstream's models, and every refusal by fuel or
  count removed; with the 35 bugs found by reading the cutover's tree.
  Coded and integrated (bfdcac70; one wave of eighteen lanes,
  `ownership.json`), its proof owed on the owner's machine with the
  cutover's; §11 records what execution decided and §12 what totality
  rests on.
- [0006](0006-shards.md): shards, the concurrency runtime. One copy of
  the single-threaded runtime per core, task frames for computations
  that wait, a reactor per shard, values crossing only inside messages.
  Its decisions are taken (D1 the owner's, D2 to D12 on his
  delegation, D13 from AGENTS.md); nothing is built. P1, P2 and P4
  follow `make self`; P3 is parked with 0014; P5 waits on its
  measurements.
- [0007](0007-sharded-whole-program-compiler.md): a sharded
  whole-program compiler. Summaries per module, guarantee facts from
  summaries alone, work per ready-set node and codegen bin with fact
  slices, content-named partitions, an ordered link, and a persistent
  cache with early cutoff. It consumes 0004's cutover and 0005 unchanged: 0004's
  ready set, drained by MLIR's thread pool in one process (0007 S7,
  taken by 0004's L3), is its phase-3 unit, and the cutover takes its
  first S0 record (F0), S1 (content names) and S2's first step (split
  codegen after one whole-module O3), with four of its rules (D5, D11,
  D16, D20), which 0004 now states. S2's second step, the split before
  O3, follows the cutover; S3 to S6, S8 to S10 wait as the paragraph
  above says. The owner closed §12: the compiler's Idris half is
  single-threaded until 0006's typed shards exist and then runs on
  them from stage 1; stage 0 on Chez stays single-threaded, and from
  0008's A3 stage 0 is the native frontend of the last commit before
  A3.
- [0008](0008-array-interpreter.md): the array interpreter. Static
  normalization and the type checker's evaluator as one array program
  over a hash-consed term arena, which also holds the frontend's
  interned names. In the queue after sharding's first stages; A0 to A3
  need only `make self` (A3's dense array constants use the lowering
  0003's stage 1 brought, 0003 D40; 0008 stays the producer of closed
  array results), A4 waits on 0003's stage 1, which has landed, A5 on
  its stage 5, A6 on 0006's
  P4, and A7, the interactive loop, on A0. Its one question restates
  two of the owner's rulings (§13: D3 and D5; default: the restated
  forms); what A3's folds mean on the Chez host is 0007 §12's.
- [0009](0009-data-oriented-frontend.md): a data-oriented, array-first
  frontend: compiler state as columnar tables on 0008's arena. It
  consumes the emission 0004's lane L1 and 0005's R14 and R15 wrote
  (the program op, constructors by tag, arrays as ops), and its O2 writes 0004's
  bytecode from an ops table; O3, Translate's instance fixpoint, is
  0013's first consumer. O0 is taken at `make self` with 0011's T0;
  O1 onward start after 0008's A0, in the order O0's measured costs
  give.
- [0010](0010-flattened-data.md): compiler-chosen flattened layouts of
  algebraic data, packed and columnar, each a type over the one
  declaration, chosen per value by proof. It follows 0009, starts after
  `make self` and sharding's first stages, and builds on 0004's data
  types that carry their constructors (0004 D29).
- [0011](0011-typechecker.md): a state-of-the-art type checker for the
  fork, built on 0008's arena and machine: tabled instance search, the
  rewrite ladder, a separate kernel and parallel checking. T0 is
  recorded at `make self` with 0009's O0; T3 onward follows 0008's A2;
  T7 runs definitions on 0006's shards once they exist (0007 §12, the
  owner's decision); T8 is parked with 0014.
- [0012](0012-self-host-features.md): the compiler features
  self-hosting asked for, each compiled away on the whole program at
  no runtime price; only megamorphic constructs stay refused. Feature
  2, the request-chain rule, landed with 0004's cutover, which deleted
  the instance budget (0004 D40), and 0005 compiled a match on `Delay`
  as a force (0005 D4), one part of feature 1's stage; the other five
  may start after `make self`, and nothing waits on them. Its one question, when the budget
  goes, was the owner's and is decided: in the cutover.
- [0013](0013-relational-core.md): the relational core,
  `libs/mlir-relational`. Parked until its first consumer, 0009's O3,
  starts; R1 and R2 are built before it.
- [0014](0014-rust-interop.md): Rust as the one foreign world. Parked:
  nothing before the array work needs a foreign world; 0006's P3 and
  0011's T8 wait with it.

Contiguous runs (one run cell for strings, arrays and buffers) have no
proposal. A wasm32 target entry for bumbledb's TypeScript package is
not proposed; it is a target, and it is not the evaluator.
