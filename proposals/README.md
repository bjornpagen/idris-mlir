<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
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
keeps only what remains. A later text names a deleted proposal by what
it was ("the pipeline cutover") and the commit that holds its last text,
never by its old number, which the queue reuses. A proposal can start
before a later one it partly needs; the stages that wait are named
here.

## Where the work stands (2026-10-15)

**Integrated, typecheck only: 0004**, total by construction, every
known item, and upstream's TODOs ([0004-total/](0004-total/README.md),
decided and executed 2026-10-15, thirteen lanes on disjoint files, on
the typecheck machine, which builds no LLVM): the C++'s termination is
in its types, the frontend is `%default total`, instance finiteness is
proved, the fork is total on the frontend's paths, and every size
policy is a named constant in `tools/policies.txt`. It awaits the
owner's build. It runs on two waves that are done and deleted, both
coded and integrated and neither built: the pipeline cutover with
0003's stage 1 (c7aa7b62, 5d5f3312), and the representation wave on
top of it (bfdcac70, eighteen lanes), one representation for every
fact and no fuel. Their proposals' last texts are at 484d6403
(`proposals/0004-compile-time/README.md` and
`proposals/0005-representation/README.md` there, numbered before the
renumbering below), and every proposal here cites them by those names
and that commit. On the typecheck machine the whole C++ tree
typechecks, the host libraries and the fork build, and `make check`
passes every spec but `licenses`, whose sweep is applied at
integration (`make check` was 32/32 at bfdcac70). Nothing of the three
waves has been built or run anywhere: nothing has run on a build
machine since c7aa7b62, and x86_64 Linux is NotRun. 189 fixtures carry
`NEEDS-ACCEPTANCE:` (`tests/ACCEPTANCE.md`).

**Totality, as it stands.** "Acceptance never depends on an optimizer
count" holds by construction, by `tests/spec/totality`, which reads
structure, and by `tests/spec/no-fuel`, which holds the C++ to no
counted loop bound, budget or fixpoint loop outside
`tools/policies.txt` and the Idris to no `covering`, `partial` or
assertion. Every C++ worklist is an `idr::OnceWorklist` or an
`idr::MonotoneWorklist`, whose finiteness its type states, and every
other loop iterates a finite range. Every module of `compiler/src` and
`libs/` is `%default total`. Two trust points remain, each with its
theorem in `tools/policies.txt`: Idris's compiler behind
`IdrisMLIR.Frontend.Host` (the evaluator, the elaborator and the
termination check: irreducible while Idris's theory is not strongly
normalizing), and the dictionary passes in `Finite.translateFrom`, which
end over a set of known fields that only grows (0004 §4.4).

**The next chain**, in order: the owner's build and acceptance
(reconfigure, `make bootstrap`, `make build`, `make test`,
`make test-idr` and `make test-mlir-tools` on both targets, the 189
marked fixtures accepted; HANDOFF.md lists it); the toolchain bump
(`0004-total/toolchain-bump.md`: Idris 2 alone, then CMake and LLVM
together); then the queue: 0002's G1 (the qualification: determinism at
1, 2 and 8 threads, the bench, x86_64 Linux, 0002 §5 being the owner's
question of where it runs) and `make self` (0002 §2 step 5;
`tools/self.sh` compares the `.mlirbc` and records peak memory through
`tools/host.sh`, on both targets); 0002's step 6, the test runner off
Chez; the split before O3 (0006's S2 second step, the cutover's §5.4);
then 0005's P1.

Everything is on `main` in the one checkout: no branches, no
worktrees, locally or on the remote (*decision*, the owner's standing
rule, restated 2026-10-14). The caller decides the CPU count: tools
default to every CPU, and nothing assumes one machine (0004 §2).

The pipeline cutover answered its question first: defunctionalization
is total by analysis alone, as MLton's closure conversion is (a
verified closed world, one flow interface, a forced-state anchor per
lazy value type, no unknown element in the label set; the cutover's
§2), so inlining, specialization and every budget are pure
optimization and never reject a program. One bottom-up ready set over
the call graph's SCCs replaced the Simplify rounds: each function is
cleaned once, after its callees are final, under MLton's inline
formula applied once and a per-caller cap of 10,000 ops (the cutover's
§4 stage 7). Effects, constants and binding times are one summary per
function, read at each call from its callee (the representation wave's
D13), names come from content, facts live in types and inherent
properties, and code generation is split into size-balanced bins of
SCCs grouped by top-level namespace, 2^15 LLVM instructions each, so
their count follows the program's size and never the thread count (the
cutover's §5.3). No option, toggle, fallback or dual path survived (the
cutover's D2, §6). The research is stored verbatim in
`sources/notes/compile-pipeline/`, with the MLton
(`sources/code/mlton`, 43 files at aa2fd1ad) and Mojo
(`third_party/modular`, a reference submodule at 9211931) sources it cites.

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
and the rounds' C++ pipeline did not finish on it (the cutover's §3.1).
The cutover is what was to make it finish; nothing has measured that
yet.

The first compile-time round landed 2026-10-13 and 2026-10-14 and is
recorded in the cutover's §3.1: one explicit Simplify round on the
stage-0 module fell from 1,321 s to 385 s (dev build; *measured*,
5088d7a8), and the suite record from 248.8 s to 167.9 s over 429
compilations (*recalled*: the suite record was not kept, and G1's run
before the cutover, which was to re-record it, was not taken, 0002 §3).
Until the cutover deleted them, the rounds were the wall: sixteen of
them reached no fixpoint, and Simplify alone extrapolated past 2,000 s
unfinished (*measured*, `bench/profiles/2026-10-14-f0-stage0.md`, F0).
The cutover and 0006 are one architecture in two steps: **the whole
program stays the unit of meaning and stops being the unit of work.**
Every fact a guarantee rests on (the instance set, closure sums,
quantities, exclusivity, layouts) is decided once, on the whole
program, and read frozen; every body of work moves to the smallest
boundary its facts allow: call-graph SCCs for the `idr` passes,
size-balanced bins for LLVM. The structure is there: at emission the
largest direct-call SCC is 174 of 58,235 functions and 93% are
singletons, and after six rounds the largest is 24 of 28,276
(*measured*, F0; closure applies are not edges of that graph, and since
the cutover every apply is a dispatch of direct calls, its §2.7). Idris
modules are not that boundary: 17% of distinct origin-to-origin
direct-call pairs stay in one module and 49% in one top-level namespace
(*measured*, F0), which is why bins are grouped by namespace and cut by
content (the cutover's §5.3). 0006 shards the same pipeline: summaries
per module keep partitions stable under edits, and the ready set's
nodes and the bins are its units.

The order of the work, decided by the owner on 2026-10-12, amended
2026-10-13 to insert compile time, and re-cut 2026-10-14 as one
maximalist cutover with no compatibility owed to any legacy mechanism
the new shape replaces (0002 D1), and as it went: 0001 first (licensing,
its L5 and L6 built in 0004); the pipeline cutover, before 0002's
remaining self-host steps, because stage 1 cannot finish without it (it
took 0006's first S0 record, S1 and S2's first step), with 0003's stage
1 (the array purge) in the same swarm wave by the owner's decision of
2026-10-14, and the representation wave on top of it, decided and
dispatched on 2026-10-15; all three coded and integrated, none built;
then 0004, decided and integrated 2026-10-15, typecheck only. 0002's G1
run before the cutover was not taken: the waves ran on the typecheck
machine, so the qualification reads the bench against the 2026-10-13
record and stage 0's optimizer against the cutover's §10 margin of 600
s, as HANDOFF.md's list says. Then the chain above: the owner's build,
the toolchain bump, the qualification, `make self` (0002's step 5, with
step 4's diet and memory record taken from its run), x86_64 Linux, step
6, the split before O3; then sharding (0005's P1, P2 and P4 with 0006's
S-stages). After them the array style is the organizing principle:
0003's stages 2 to 8, with 0007's interpreter, 0008's tables and 0009's
layouts as its consumers, and 0010's checker on 0007's machine; 0012's
fixed-plan joins are 0003's sparse half. 0011's features may start any
time after `make self`; nothing waits on them.

Stages that wait on something besides the queue, each with its rule in
its proposal: 0006's S3 to S6, each taken when S0's second record (from
the qualification's first builds, on the owner's machine) shows its
part above 5% of one-worker wall; 0006's S9 (the cache) after S2's
second step; 0006's S8 and S10 (the Idris half in parallel, on 0005's
shards) after 0005's P4 and 0008's O3; 0005's P5, each item on its
measurement. Parked, with the reason in each status line: 0012, until
its first consumer starts, which is 0008's O3 (R1 and R2 are built
before it); 0013, which nothing before the array work needs, and with
it 0005's P3 and 0010's T8.

Questions only the owner can settle, each with its default taken in the
proposal that owns it: 0001 §3 (GMP's licence, with counsel) and 0001 §4
(whether a port's changes note names only what changed, which amends his
D1; default yes, path and revision in PINS.md alone), 0002 §5 (where
G1's x86_64 Linux leg runs), 0004 §5 item 3 (whether the request
relation refuses a chain that grows once and stops; default: the rule as
built, 0011's feature 2) and item 9 (the ryu pin, which has no release
since v2.0; default: stay), and 0007 §13 (the restated forms of the
owner's D3 and D5 for static normalization). Every other question in the
queue is decided.

Renumberings: on 2026-10-14, first the built cutover packet was
deleted and the queue closed up (dcb087d2 holds that map); then
licensing took 0001 and every other proposal moved up one (77994b30
holds that map). On 2026-10-15 (a) the representation wave took 0005
and the queue after it moved down by one, 0005-0013 becoming 0006-0014
(1f4170c0). On 2026-10-15 (b) the pipeline cutover's 0004
(`0004-compile-time/`) and the representation wave's 0005
(`0005-representation/`), both done, were deleted; this wave took 0004
(`0004-total/`); and 0006-0014 became 0005-0013 (0006 shards to 0005,
0007 the sharded compiler to 0006, 0008 the array interpreter to 0007,
0009 the data-oriented frontend to 0008, 0010 flattened data to 0009,
0011 the type checker to 0010, 0012 the self-host features to 0011,
0013 the relational core to 0012, 0014 Rust interop to 0013), the
commit that lands it holding the map. Dated records (`HANDOFF.md`
entries, `bench/runs/`, `sources/`) keep the numbering then in force.

- [0001](0001-licensing.md): licensing: every file says whose it is.
  The policy is built (3a275cf0, L1 to L4): SPDX provenance across the
  tree (ours 0BSD; Mojo and MLIR ports Apache-2.0 WITH LLVM-exception;
  the Idris fork BSD-3-Clause), `LICENSES/` with the third-party
  inventory, `tools/licenses.sh` and its gate. L5 (the dialect
  generator writes its own SPDX line) and L6 (the sweep's scope is
  every tracked file less one listed exclusion set, and the gate reads
  its facts from the data that holds them) were built in 0004, the
  sweep applied at integration. What remains is the owner's: accepting
  the built state; §3's GMP question, with counsel (default: LGPL-3.0
  §4(d)(0) through a relink kit, D7); and whether a port's changes note
  names only what changed (§4; default yes). Deleted when the owner
  accepts the built state.
- [0002](0002-get-back-on-track.md): get back on track. The cutover it
  designed is built, and self-hosting's first three steps are done;
  what remains is G1 (§3: x86_64 Linux, the bench on both targets,
  compile times), which runs once, as the qualification, after 0004's
  build and the toolchain bump, and self-hosting's steps 4 to 6 (§2),
  which follow it. One question is the owner's: where G1's Linux leg
  runs (default: a native x86_64 Linux machine of the owner's). Deleted
  when G1 is green on both targets and §2's steps 5 and 6 are recorded
  in HANDOFF.md (D13).
- [0003](0003-typed-apl/README.md): a typed array language, MLIR first.
  Every fact Idris proves about an array has one image in MLIR, the one
  upstream optimizes on. Stage 1 is done: it purged the array stack
  before it (about 6,300 lines, `idr-in-bounds` among them) and rebuilt
  it in one hard cutover, in the pipeline cutover's wave (c7aa7b62,
  5d5f3312), and the representation wave reshaped it (bfdcac70): arrays
  are ops end to end, lowered one to one (its D6, reversing 0003's D13),
  the generating set is declared once as bodiless `%extern`s (its D5),
  and record arrays split into columns in `idr-columns` (its D20); 0004
  extended patch 24 so a cycle of calls is analyzed to a fixpoint (its
  U4) and gave a vector's pop `idr.element.update`. §1 says what stage
  1 built, and its proof is the owner's build's. Stages 2 to 7 follow
  sharding, and stage 8 needs 0005's P4.
- [0004](0004-total/README.md): total by construction, every known
  item, and upstream's TODOs. No fuel anywhere: every C++ worklist an
  `idr::OnceWorklist` or `idr::MonotoneWorklist`, tail position without
  a budget, every frontend module `%default total`, instance finiteness
  proved (`compiler/src/IdrisMLIR/Proof/`), the fork total on the
  frontend's paths with four of Idris's bugs fixed as fork code, every
  size policy a named constant in `tools/policies.txt`, enforced by
  `tests/spec/no-fuel`; the C++ written as an Idris programmer would;
  the known small items; the runtime's cleanup and speed pass; the
  upstream TODOs on our paths (patch 24 extended, submissions 27, 48
  and 49); and 0001's L5 and L6. Decided and integrated 2026-10-15,
  typecheck only, with the bugs review found (older and introduced) in
  its §4.3. What remains (§5): the owner's build and acceptance, the
  toolchain bump ([toolchain-bump.md](0004-total/toolchain-bump.md)),
  the owner's two questions (the polymorphic-recursion whistle and the
  ryu pin), the dictionary passes' proof, the rest of Host's trust, the
  translation of applications made total, four deferred designs
  (data-type bodies that hold buffers first), typed identities in place
  of strings that stand for things (which the dictionary passes' proof
  waits on), the primitives cleaned up (dead, duplicated or badly shaped
  ones, across registry, ODS and runtime at once), a pass to trim the
  C++, and the submissions ready to file. Deleted when the
  owner's build is green and §5's items have their homes.
- [0005](0005-shards.md): shards, the concurrency runtime. One copy of
  the single-threaded runtime per core, task frames for computations
  that wait, a reactor per shard, values crossing only inside messages.
  Its decisions are taken (D1 the owner's, D2 to D12 on his
  delegation, D13 from AGENTS.md); nothing is built. P1, P2 and P4
  follow `make self`; P3 is parked with 0013; P5 waits on its
  measurements.
- [0006](0006-sharded-whole-program-compiler.md): a sharded
  whole-program compiler. Summaries per module, guarantee facts from
  summaries alone, work per ready-set node and codegen bin with fact
  slices, content-named partitions, an ordered link, and a persistent
  cache with early cutoff. It consumes the pipeline cutover and the
  representation wave unchanged: the cutover's ready set, drained by
  MLIR's thread pool in one process (S7, taken by the cutover's lane
  L3), is its phase-3 unit, and the cutover took its first S0 record
  (F0), S1 (content names) and S2's first step (split codegen after one
  whole-module O3), with four of its rules (D5, D11, D16, D20). S2's
  second step, the split before O3, is in the next chain above; S3 to
  S6, S8 to S10 wait as the paragraph above says. The owner closed
  §12: the compiler's Idris half is single-threaded until 0005's typed
  shards exist and then runs on them from stage 1; stage 0 on Chez
  stays single-threaded, and from 0007's A3 stage 0 is the native
  frontend of the last commit before A3.
- [0007](0007-array-interpreter.md): the array interpreter. Static
  normalization and the type checker's evaluator as one array program
  over a hash-consed term arena, which also holds the frontend's
  interned names. In the queue after sharding's first stages; A0 to A3
  need only `make self` (A3's dense array constants use the lowering
  0003's stage 1 brought, 0003 D40; 0007 stays the producer of closed
  array results), A4 needed 0003's stage 1, which is done, A5 waits on
  its stage 5, A6 on 0005's P4, and A7, the interactive loop, on A0.
  Its one question restates two of the owner's rulings (§13: D3 and
  D5; default: the restated forms); what A3's folds mean on the Chez
  host is 0006 §12's.
- [0008](0008-data-oriented-frontend.md): a data-oriented, array-first
  frontend: compiler state as columnar tables on 0007's arena. It
  consumes the emission the cutover's lane L1 and the representation
  wave's lanes R14 and R15 wrote (the program op, constructors by tag,
  arrays as ops), and its O2 writes the bytecode handoff from an ops
  table; O3, Translate's instance fixpoint, is 0012's first consumer.
  O0 is taken at `make self` with 0010's T0; O1 onward start after
  0007's A0, in the order O0's measured costs give.
- [0009](0009-flattened-data.md): compiler-chosen flattened layouts of
  algebraic data, packed and columnar, each a type over the one
  declaration, chosen per value by proof. It follows 0008, starts after
  `make self` and sharding's first stages, and builds on the data types
  that carry their constructors, which the cutover built (its D29).
- [0010](0010-typechecker.md): a state-of-the-art type checker for the
  fork, built on 0007's arena and machine: tabled instance search, the
  rewrite ladder, a separate kernel and parallel checking. T0 is
  recorded at `make self` with 0008's O0; T3 onward follows 0007's A2;
  T7 runs definitions on 0005's shards once they exist (0006 §12, the
  owner's decision); T8 is parked with 0013.
- [0011](0011-self-host-features.md): the compiler features self-hosting
  asked for, each compiled away on the whole program at no runtime
  price; only megamorphic constructs stay refused. Feature 2, the
  request-chain rule, landed with the pipeline cutover, which deleted
  the instance budget (its D40), and which 0004 proved finite
  (`Proof.Requests`), and the representation wave compiled a match on
  `Delay` as a force (its D4), one part of feature 1's stage; the other
  five may start after `make self`, and nothing waits on them. Its one
  question, when the budget goes, was the owner's and is decided: in the
  cutover. Whether the rule refuses a chain that grows once and stops is
  reopened for the owner (0004 §5).
- [0012](0012-relational-core.md): the relational core,
  `libs/mlir-relational`. Parked until its first consumer, 0008's O3,
  starts; R1 and R2 are built before it.
- [0013](0013-rust-interop.md): Rust as the one foreign world. Parked:
  nothing before the array work needs a foreign world; 0005's P3 and
  0010's T8 wait with it.

Contiguous runs (one run cell for strings, arrays and buffers) have no
proposal. A wasm32 target entry for bumbledb's TypeScript package is
not proposed; it is a target, and it is not the evaluator.
