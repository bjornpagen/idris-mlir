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

## Where the work stands (2026-10-17)

Two waves are integrated on the typecheck machine and wait for the
owner's build: 0001, total by construction (d06ed15c), and 0002 on top of
it, sound passes, typed identities, good tests or none (1cd1193a). Under
them are two earlier waves, the pipeline cutover with 0009's stage 1
(c7aa7b62, 5d5f3312) and the first representation wave (bfdcac70), whose
last texts are at 484d6403. `make typecheck` passes every part (C++ 0 errors)
and `make check` is 35/35 (*measured*, 1cd1193a). Nothing of these waves
has been built or run on a build machine: the last build was c7aa7b62,
arm64 macOS only, and x86_64 Linux has run none of it. What ran without
LLVM is recorded in 0002 §11: the runtime's property programs, two
googletest boxes, and the Idris machinery and frontend on Chez.
`tests/ACCEPTANCE.md` lists the files owed acceptance.

**Self-hosting comes first** (the owner, 2026-10-15). `make self` has
never finished: the frontend on Chez emitted the whole of itself and the
fork (58,236 functions) with no refusal, and the C++ pipeline of the time,
its Simplify rounds, did not finish on that module (F0,
`bench/profiles/2026-10-14-f0-stage0.md`). The cutover deleted the rounds;
nothing has measured the new pipeline on the self module. 0003 is the
plan. Its S1, the frontend's refusal sweep, runs here; S3 to S5 are the
owner's machines.

**The polymorphism rule is built** (the owner's ruling, 2026-10-16;
integrated 2026-10-17): option C of 0003 §7, a growth graph over the
program's finite type flow that refuses only a type grown without bound,
with its proof in Idris. The self compile's frontend step passes it with
no patch (0003's S2.2, `bench/profiles/2026-10-17-self-growth.md`).

**The chain, in order:** the owner's build of 0001 and 0002 (HANDOFF.md
lists it); 0003, self-hosting, S1 and S2 here, then S3 to S5; 0004, the
representation wave onto MLIR's grain, here and now, its acceptance joining
the owner's build; 0005, the toolchain bump, whose strongest check is
stage 2 = stage 3 on the new pins; 0006, the qualification (G1); then the
queue below.

Everything is on `main` in the one checkout: no branches, no worktrees
(*decision*, the owner's standing rule). The caller decides the CPU count.

The rules every proposal holds to, each stated in AGENTS.md or here:
- **Representation first.** The owner's lens, carried verbatim in every
  dispatch: `0002-sound/parts/representation.md`.
- **Hard cutover.** No backwards compatibility.
- **Upstream MLIR first.** Our C++ at its minimum; the smaller C++ wins over
  a nicety.
- **Two hosts, forever.** The Idris side compiles and runs under the
  stock Idris on Chez and under idris-mlir. What the stock host runs uses
  only definitions with bodies, which idris-mlir may replace with a
  runtime op through the registry's `Faster` hook. A `%extern` primitive
  serves programs only. A bootstrap may use either host, and neither is
  dropped.
- **The totality rule.** A definition Idris does not prove ends is refused
  only where a normaliser would run it (the owner, 2026-10-15). A total
  compiler compiles a partial program without running it.

## The queue

- [0001](0001-total/README.md): total by construction. Integrated
  (d06ed15c), its record culled to what it built (the full text is at
  b843d8b5). It remains until the owner's build is green, which
  self-hosting needs (SELF-HOST); §3 says where each remaining item went.
- [0002](0002-sound/README.md): sound passes, typed identities, good tests
  or none. Integrated (1cd1193a). What remains is the owner's build of it
  and the findings recorded in its §9 for the next wave. Deleted when the
  build is green and §9's items have homes.
- [0003](0003-self-host/README.md): **self-hosting: `make self` finishes.** The
  stages:
  - S0: integration fixes, done in 0002.
  - S1: the refusal sweep, here.
  - S2: fix each refusal in the code, never by loosening a rule. S2.1
    (each data type written once) and S2.2 (the polymorphism checker) are
    done; the fork's `SyntaxInfo` knot (D3) runs in 0004's wave.
  - S3: the pipeline on the self module (owner's machine).
  - S4 and S5: `make self` on arm64 macOS, then x86_64 Linux, with stage
    2 = stage 3.

  `tools/self.sh` re-copies the sources per stage (D6), and the test
  machinery comes under both hosts after it (D7).
- [0004](0004-representation/README.md): representation first, onto
  MLIR's grain. A swarm packet of 24 lanes over the C++ and the Idris side
  (197 findings, contracts S0 to S44), its decisions the owner's (§9).
  Landed 2026-10-18 (2c042728 and after): the C++ typechecks, nothing is
  built; the owner's build qualifies it with the self-host (HANDOFF.md).
- [0005](0005-toolchain-bump.md): the toolchain bump. Idris 2 alone, then
  CMake and LLVM together, then a fresh survey. Right after `make self`,
  whose stage 2 = stage 3 check is the bump's strongest. It holds the
  ryu pin.
- [0006](0006-qualification.md): the qualification, G1. Determinism (as
  `tests/lib/determinism.sh` states it), the bench, x86_64 Linux and
  compile times, run once after `make self`. Only the Linux build and
  suite come before self-hosting's S5.
- [0007](0007-shards.md): shards, the concurrency runtime. Nothing is
  built. D14 gives the frontend a plain-Idris layer that idris-mlir runs
  on shards through `Faster`. AFTER-SELF.
- [0008](0008-sharded-whole-program-compiler.md): a sharded whole-program
  compiler. S1, S2's first step and S7 are built (records). S0's second
  record is taken from self-hosting's stage-1 run. The rest is AFTER-SELF.
- [0009](0009-typed-apl/README.md): a typed array language, MLIR first.
  Stage 1 is built (record). Stages 2 to 8 follow sharding. D45 gives the
  frontend a plain-Idris array layer, declared once.
- [0010](0010-array-interpreter.md): the array interpreter. Nothing is
  built. A0 needs `make self` green. AFTER-SELF.
- [0011](0011-data-oriented-frontend.md): a data-oriented frontend over
  plain-Idris tables. It takes typed SSA names. O0 is recorded after
  `make self`. AFTER-SELF.
- [0012](0012-flattened-data.md): compiler-chosen flattened layouts.
  Nothing is built. F2 depends only on built work. AFTER-SELF.
- [0013](0013-typechecker.md): a state-of-the-art type checker for the
  fork. T0 is recorded after `make self`. AFTER-SELF.
- [0014](0014-self-host-features.md): features self-hosting once asked
  for. None is needed for `make self`: the frontend emitted itself with no
  refusal, and the regimented subset rewrites code rather than widening
  the language. Kept as designs. AFTER-SELF.
- [0015](0015-relational-core.md): the relational core. Parked until
  0011's O3 starts; R1 and R2 come first.
- [0016](0016-licensing.md): licensing. Built (L1 to L6). What remains is
  the owner's acceptance, the two questions below, and three small edits
  (the port's changes note, the porting rules into `foreign/README.md`,
  the LLVM row of `LICENSES/THIRD-PARTY.md`).
- [0017](0017-apple-dmp.md): the heap as Apple's data memory-dependent
  prefetcher reads it. The heap region is built (efe0ad36). P0, the native
  measurement that can withdraw every claim, and P1, the stack in the
  heap's region, can run now. P2 to P4 are AFTER-SELF, with 0009's gathers,
  0012's gates and G1.
- [0018](0018-fin-words.md): `Fin n` as a machine word where its bound is
  static. Nothing is built. F0 measures on the owner's build; F1 is
  frontend-only; F2 waits on F0. AFTER-SELF.
- [0019](0019-niche-sums.md): niche layouts of sums. A sum with one
  constructor that has fields holds the others in values that field never
  holds, so `Maybe String` is one word. Then thin sums out of `fit`'s boxes,
  several constructors with fields, and a list's `Nil` as NULL (gated).
  Nothing is built. N1 needs only the owner's build. AFTER-SELF.
- [0020](0020-rust-interop.md): Rust as the one foreign world. The
  manifest names crates and nothing else; the generator binds them whole.
  Parked; revised 2026-10-18.

## Questions only the owner can settle

Each has its default taken in the proposal that owns it:
- **0016 §3:** GMP's licence, with counsel. *Default:* LGPL-3.0 §4(d)(0)
  through a relink kit.
- **0016 §4:** whether a port's changes note names only what changed.
  *Default:* yes.
- **0006 §5:** where G1's x86_64 Linux leg runs. *Default:* a native
  machine of the owner's.
- **0005:** the ryu pin. *Default:* stay.
- **0010 §13:** what the normaliser may fold of a primitive. *Default:*
  none, on either host.
- **0013 §2.3:** `%auto_implicit_depth` and `%ambiguity_depth`, counts
  that decide acceptance. *Default:* keep.
- **0020 §19.1:** the Rust toolchain pin. *Default:* the latest stable
  with `RUSTC_BOOTSTRAP=1`.
- **0020 §19.2:** whether the target rules bind a program's crates.
  *Default:* our tree only.
- **0020 §19.3:** the 2026-10-18 model beyond the owner's rulings (every
  Rust call is `IO`, `std` named like any crate): one handle with a
  run-time borrow state, data and objects, whole named crates, one process
  kept by the runtime, traits as interfaces, generics decided by rustc,
  the names. *Default:* as written.
- **0007 D14:** a crash in forked work held until its join. Taken; for
  review.

## Explorations (not queued)

Questions recorded so they are not lost. None is a proposal, none has a
position in the queue, and each may turn out wrong for this language.

- **A smaller custom op set** (*conjecture*, 2026-10-15). Tinygrad's
  simplification was a small, closed op set as data, with everything else
  rewrite rules over it. The question is whether part of the `idr`
  dialect would read better that way: many of our ops are "call this
  runtime function" (lane P's primitive audit in 0015), and some could be
  upstream `arith`/`math` ops plus one generic runtime call. Reasons it
  may not fit:
  - Idris's primitive set is fixed by Idris, not chosen by us.
  - Analyses need to see some ops by name: effects, ranges, exclusivity
    and folding all read the op, not the call.
  - Tinygrad's domain is dense tensor kernels, and ours is a strict,
    counted functional language.

  If it is ever taken up, it starts as a measurement: which ops no
  analysis reads.

## Renumberings

Each renumbering commit's message holds its map; dated records
(`HANDOFF.md` entries, `bench/`, `sources/`) keep the numbering
then in force. Earlier maps: dcb087d2, 77994b30, 1f4170c0, 787744f3,
419c4ee7.

On 2026-10-17, strict order of the work: the in-flight work in the
order it ran (total integrated before sound, which is built on it;
self-hosting; the representation wave, dispatched now), then the
queue in its recorded order, the parked Rust interop last (the owner:
a proposal parked with no trigger runs after every one that has one).

| Old | New | Proposal |
|---|---|---|
| 0002 | 0001 | total |
| 0001 | 0002 | sound |
| 0003 | 0003 | self-host |
| 0020 | 0004 | representation |
| 0004 | 0005 | toolchain bump |
| 0005 | 0006 | qualification |
| 0006 | 0007 | shards |
| 0007 | 0008 | sharded compiler |
| 0008 | 0009 | typed APL |
| 0009 | 0010 | array interpreter |
| 0010 | 0011 | data-oriented frontend |
| 0011 | 0012 | flattened data |
| 0012 | 0013 | typechecker |
| 0013 | 0014 | self-host features |
| 0014 | 0015 | relational core |
| 0016 | 0016 | licensing |
| 0017 | 0017 | Apple DMP |
| 0018 | 0018 | Fin words |
| 0019 | 0019 | niche sums |
| 0015 | 0020 | Rust interop |
