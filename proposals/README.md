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

## Where the work stands (2026-10-19)

The goal is self-hosting: `make self`, stage 2 = stage 3, on the four
targets (0001). Everything else waits for it unless it says otherwise.

- **Built and running on arm64 macOS:** the total wave, the sound wave and
  the representation wave (their last texts at 77eaa5b1; the code is
  their specification), and the four-targets cutover (0002). Main at
  c4d38e9b: `make check` 34/34; the last full counts, before the ownership
  lane's static-lifetime cutover was taken out, were `make test` 446-449
  of 478, `make test-idr` 331-332 of 333 and `make test-mlir-tools` 30 of
  30. The known failures are `audits/bugs.md`'s, by lane.
- **Blocked on one toolchain rebuild:** upstream 62 and 63 (4dde6b7f) are
  written and tested on a private build, not yet in the shared toolchain,
  so the pin check refuses the full suites and `make self` until it is
  rebuilt.
- **Self-hosting:** the frontend, on Chez, compiled itself and the fork
  with no refusal on 2026-10-17 (345 s, 5.64 GB, an 82 MB module), before
  the representation wave. Since then nothing of it has run: the wave's
  frontend has not compiled itself, the pipeline has never run on the
  self module, and `make self` has never finished.
- **Linux:** no Linux target has built anything.

## What comes next, in order

1. **Rebuild the shared toolchain with upstream 62 and 63** (the
   coordinator). Acceptance: `tools/verify-pins.sh built llvm sysroot`
   passes, and so do `tests/upstream-greedy-multi-region-ancestors` and
   `tests/upstream-liveness-trivially-dead`.
2. **One full suite run on main** (`make test`, `test-idr`,
   `test-mlir-tools`, under the lanes' lock). It confirms or strikes every
   `audits/bugs.md` entry marked *not rerun*, and gives 2a02891f
   (control: a member call granted a node) its first run.
3. **0001 S3: stage 1 on arm64 macOS** (`make self-fork`, then
   `tools/self.sh 1`). The census: every refusal, internal error and
   superlinear pass it finds goes to `audits/bugs.md` under the lane that
   owns it, and the lanes fix them. S3 does not wait for green suites
   (0001 D9), and its pipeline half runs without a time limit (0001 D10).
4. **The lanes make the suites green** on arm64 macOS: `audits/bugs.md`,
   and what S3 adds to it.
5. **0001 S4: `make self` on arm64 macOS,** stage 2 = stage 3, on a green
   tree.
6. **0002: the three Linux builds** (x86_64, arm64 at 4 KiB, arm64 at
   16 KiB pages), then **0001 S5** on each. The Linux builds wait only on
   the machines and may start any time.
7. **After `make self` on arm64 macOS,** in parallel with the Linux work:
   0003 (each fact once: every location kept first, then the TTC's facts,
   then the rest) and 0004 (the
   test suite the audit planned, the runner under both hosts first).
8. **After `make self` on the four targets:** 0005 (the toolchain bump),
   0006 (G1, the qualification), then the queue from 0007 on.

Off that path, and not started while self-hosting is the focus, though
nothing blocks them: 0016's three small edits and its measurement, 0017's
P0 (the native DMP measurement on this machine) and P1, 0019's N1.

## The queue

- [0001](0001-self-host.md): **self-hosting, `make self` finishes,** and
  nothing else. S1 and S2 are done; S3 is next (above, steps 1 to 3),
  then S4 and S5.
- [0002](0002-targets.md): four first-class targets on the system's C
  library. Landed (102183f4) and running on arm64 macOS; what remains is
  the three Linux builds and the facts written from memory each confirms.
- [0003](0003-facts-once.md): each fact once. The facts the compiler
  knew, threw away and derives again or guesses, from the 2026-10-19
  sweeps, the representation wave's leftovers and the static lifetime;
  each kept or derived from a tighter representation by §1's rules. The
  After `make self` on arm64 macOS.
- [0004](0004-tests.md): the test suite the 2026-10-18 audit planned: the
  harness's lies first, then the typed runner, the vocabulary, the
  universal checks, the relations and the search. After `make self` on
  arm64 macOS.
- [0005](0005-toolchain-bump.md): the toolchain bump, its survey redone
  (18 carried LLVM patches now, 9 when surveyed). After `make self` holds
  on the four targets.
- [0006](0006-qualification.md): the qualification, G1: bench, compile
  times, bounded memory, the upstream-Idris scan, on every target; then
  "what form compiles" on every refusal.
- [0007](0007-shards.md): shards, the concurrency runtime. Nothing
  built; P1 first.
- [0008](0008-sharded-whole-program-compiler.md): a sharded
  whole-program compiler. S1, S2's first step and S7 are built; S0's
  second record comes from 0001's S3.
- [0009](0009-typed-apl/README.md): a typed array language, MLIR first.
  Stage 1 is built; stage 2 next.
- [0010](0010-array-interpreter.md): the array interpreter. Nothing
  built; A0 after `make self` and 0013's T0.
- [0011](0011-data-oriented-frontend.md): a data-oriented frontend. O0 is
  recorded at `make self`; one contingency is self-hosting's (a frontend
  stage that does not fit the machine).
- [0012](0012-flattened-data.md): compiler-chosen flattened layouts.
  Nothing built; F2 needs only built work.
- [0013](0013-typechecker.md): a type checker for the fork. T0 and the
  dead clock's deletion after `make self`.
- [0014](0014-self-host-features.md): bounded features self-hosting once
  asked for, and the growth check's known limits. Feature 1's erased-match
  check first.
- [0015](0015-relational-core.md): the relational core. R1 when 0011's O3
  is next.
- [0016](0016-licensing.md): licensing. Built; three small edits and one
  measurement remain, then it is deleted.
- [0017](0017-apple-dmp.md): the heap as Apple's DMP reads it. The region
  is built; P0 and P1 can run on this machine now.
- [0018](0018-fin-words.md): `Fin n` as a machine word. F0 from 0001's
  S3; F1 needs nothing.
- [0019](0019-niche-sums.md): niche layouts of sums. N1 needs nothing.
- [0020](0020-rust-interop.md): Rust as the one foreign world. Parked
  until a consumer starts.

Every question the owner was asked has its decision in the proposal that
owns it; none is open.

## Explorations (not queued)

Questions recorded so they are not lost. None is a proposal, none has a
position in the queue, and each may turn out wrong for this language.

- **A smaller custom op set** (*conjecture*, 2026-10-15). Tinygrad's
  simplification was a small, closed op set as data, with everything else
  rewrite rules over it. The question is whether part of the `idr`
  dialect would read better that way: many of our ops are "call this
  runtime function" (lane P's primitive audit in 0003), and some could be
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
(`bench/`, `sources/`) keep the numbering then in force. Earlier maps:
dcb087d2, 77994b30, 1f4170c0, 787744f3, 419c4ee7, e5b05658, 102183f4.

On 2026-10-19 the total wave (last text d346040c), the sound wave (2d9290b5)
and the representation wave (77eaa5b1) were deleted as done, the
self-host plan moved to the head of the queue, and two proposals came in
from the audits: each fact once and the test suite. The map, old to new:
0003 self-host -> 0001; 0005 targets -> 0002; new, each fact once -> 0003;
new, the test suite -> 0004; 0006 toolchain bump -> 0005; 0007
qualification -> 0006; 0008 shards -> 0007; 0009 sharded compiler ->
0008; 0010 typed APL -> 0009; 0011 array interpreter -> 0010; 0012
data-oriented frontend -> 0011; 0013 flattened data -> 0012; 0014
typechecker -> 0013; 0015 self-host features -> 0014; 0016 relational
core -> 0015; 0017 licensing -> 0016; 0018 Apple DMP -> 0017; 0019 Fin
words -> 0018; 0020 niche sums -> 0019; 0021 Rust interop -> 0020.
