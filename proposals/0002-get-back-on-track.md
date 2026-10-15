<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0002: get back on track: what remains

**Status:** decided 2026-10-12. The cutover it designed is built on
arm64 macOS: an in-tree MLIR dialect in upstream's layout, `idr.func`
with inherent facts, analyses under the pass manager, function passes
in parallel, no erased value emitted, profiling through the pass
manager. Self-hosting's first three steps are done. What remains is
G1 (§3), the gate that proves the tree on both targets, and
self-hosting's steps 4 to 6 (§2).

The last built tree is the one before the pipeline cutover (c7aa7b62,
5d5f3312; its proposal at 484d6403), and its gate on arm64 macOS was
green: at 7a27fd34, before the opt-in SCC pipeline, `make check` 26/26,
`make test-idr` 286/286, `make test` 415/415; at 552d682a, which added
that opt-in (default off) and 0001's licenses gate, `make check` 27/27,
`make test-idr` 286/286, `make test` 415/415 (*measured* 2026-10-14 at
`NCPU=6`, HANDOFF.md). `make test-mlir-tools` was last recorded 17/17 on
2026-10-13. The cutover deleted the opt-in and the Simplify rounds, so
the suite it must reproduce is the rounds' 415/415. The cutover, the
representation wave on top of it (bfdcac70; its proposal at 484d6403)
and 0004 on top of both are integrated on the typecheck machine, which
builds no LLVM: there `make check` was 32/32 at bfdcac70 and, with 0004,
passes every spec but `licenses`, whose sweep is applied at integration;
nothing of them has been built, and 189 fixtures await acceptance
(`tests/ACCEPTANCE.md`). x86_64 Linux is NotRun: nothing of this tree
has been built there. G1's run is the qualification on the owner's
machine, after 0004's build and acceptance and the toolchain bump
(`0004-total/toolchain-bump.md`), and `make self` follows it
(proposals/README.md, the next chain). Claims are marked: *read* (the
path), *measured* (the record), *recalled*, *conjecture*, *decision*.

**The one sentence.** The wall was the rounds, which the cutover
deleted, and sharding (0006) comes after self-hosting: the whole
program stays the unit of meaning and stops being the unit of work.
This proposal holds the gate that proves the tree on both targets and
the road from there to a compiler that compiles itself.

## 1. Stages

| Stage | Status |
| --- | --- |
| G1 (both targets, §3) | remains: runs once, on the tree after the cutover, the representation wave and 0004, as their proof on both targets |
| S (self-hosting, §2) | remains: steps 4 to 6, after G1's run on the owner's machine |

## 2. Self-hosting

Each step is measured before the next starts, on the tree the
qualification proved. The wall's record is F0
(`bench/profiles/2026-10-14-f0-stage0.md`): the frontend emits the
stage-0 module, 58,236 functions and about 300 MB of text, in about
140 s, and the rounds the cutover deleted reached no fixpoint on it.
Stage 0's first run through the cutover's pipeline, to an executable,
is held to the cutover's §10 thresholds (the optimizer segment under
600 s of wall, the label solve under 10 s), recorded with
`-mlir-timing` and the time trace (`tools/profile.sh`), by binary from
the saved module.

4. **The diet and the memory.** Recorded from step 5's first run: the
   stage-0 handoff's functions, operations and bytes (MLIR bytecode
   since the cutover, so its bytes are not comparable with the text
   records below; functions, operations, time and memory are), and the
   peak resident memory of the frontend and of the pipeline. The
   records to beat: the frontend at 9.1 GB peak for a 405 MB text
   module in 137 s (arm64 macOS, 2026-10-10, HANDOFF.md); the rounds at
   5.27 GB peak in round 1 and about 5.8 GB steady, and the
   RemoveDeadValues tail at 7.65 GB (F0). *Decision:* this step is a
   record, not a gate. It holds `make self` back only if a stage does
   not fit the owner's machine; then the stage the record names is
   fixed first, in the proposal whose design it is (the frontend's
   memory is 0008's ground; the pipeline's next cost is on the
   cutover's §10 list). Reason: stage 0 already ran at 9.1 GB on that
   machine, and a reduction that blocks nothing belongs to the proposal
   that owns the design. Peak memory is one function of the host layer,
   `tools/host.sh`'s `peak_memory`, which `tools/self.sh` calls for each
   stage (`build/self/stageN/peak-kib`) and G1's bounded-memory check
   (§3) calls too.
5. **`make self`.** Stages 1 to 3 on the self-compiled frontend
   (`make self`, `tools/self.sh`, 1ce907d3): stage 2 byte-identical to
   stage 3 (the executable, the module, now the `.mlirbc` the frontend
   hands the pipeline, and the Core), recorded in HANDOFF.md on arm64
   macOS and on x86_64 Linux. *Decision:* `make self` checks stage 2
   against stage 3 at the default thread count, as it does today
   (`tools/self.sh:44`, `--num-threads="$ncpu"`); thread independence
   is checked once, in step 5's record, by stage 3's compile of itself
   at 1, 2 and 8 threads, byte for byte, and on every suite run by
   `tests/determinism` on its programs. Reason: the cutover's
   determinism rules make every output a function of its input alone
   (the cutover's §4), which the suite checks on every run; repeating
   the self-compile at three thread counts in every `make self` triples
   its cost for a property the suite already holds. `tests/determinism`
   compiles at 1, 2 and 8 threads (`tests/lib/determinism.sh:7`,
   *read*; not yet run).
6. **The test runner off Chez.** The runner compiled by the
   self-hosted compiler, so `make test` needs no Chez at all: its
   orchestration in sh, its generators compiled by idris-mlir, an
   `--exports` query in place of the stock REPL;
   `tests/toolchain/static-linking` covering `idris-mlir-front`; and
   AGENTS.md's Chez exception narrowed to stage 0 and the bench's
   baseline (HANDOFF.md, the 2026-10-12 state). *Decision:* this step
   follows step 5. The bench's Chez column is timing only: its output
   is never compared with the reference, which this compiler's output
   or clang's is (`bench/run.sh`'s `compared` columns). So the
   exception step 6 writes into AGENTS.md covers running stock Idris's
   Chez backend for a time, and never its meaning. Reason: a run that
   fails when Chez prints a value differently (`"+inf.0"` against the
   runtime's `inf`, `upstream/18-elaboration-primitive-folding`) makes
   Chez's meaning a gate, which AGENTS.md's no-oracle paragraph
   forbids; the C column is the comparison that matters (0003 §20 item
   3), and it stays, since the C program is a rebuild of ours whose
   output only shows that the two programs compute the same thing.

HANDOFF.md's list of what follows `make self` names one more item,
every rejection message made precise (what was found, where, why, and
what form compiles; the owner's request of 2026-10-10, HANDOFF.md's
2026-10-12 state). *Decision:* it is not a self-host step. The
cutover's D42 made a refusal's rule structured data on its diagnostic
(one `Rule` enum in ODS), its proof every reject test's expected text
unchanged. The four parts are fields added to that data in a change of
this proposal's own, after G1's run: the frontend's refusals and the
C++ side's each fill them where the refusal is decided, the driver
renders them in the one place that writes the phrase, and the reject
tests' expected files are rewritten in the same change. Reason: the
content of a refusal changes those expected files, which the
qualification holds fixed, so the two cannot be one change; the
representation came first because the fields need a place to live.

Then, in queue order (proposals/README.md, the next chain): x86_64
Linux, step 6, the split before O3 (0006's S2 second step), then
sharding, 0006's stages with 0005's P1, P2 and P4. 0011's features may
start any time after step 5.

## 3. G1: what the tree still owes on both targets

A target that has not run an item is NotRun, never green.

**When** (*decision*, D9). G1 runs once, on the tree after the
cutover, the representation wave and 0004, as their proof on both
targets: a change is done only when it builds and passes on both
(AGENTS.md). The run before the cutover, which was to give each target
an old binary for the cutover's §10 thresholds (no bench program's
compile time worse by more than 5%, nor its runtime by more than 2%),
was not taken: the waves ran on the typecheck machine before the
owner's machine ran anything. So the bench on arm64 is read against the
one record kept, `bench/runs/2026-10-13-9a1b7b1-darwin-arm64`, stage
0's optimizer against the cutover's §10 margin (under 600 s of wall),
and the Linux leg has no baseline but the one it records.

**Not run.**

- **x86_64 Linux.** `make bootstrap` (every step of
  `tools/bootstrap.sh`: `llvm` alone builds neither GMP, nor Chez, nor
  Idris), then `make build`, `make check`, `make test`, `make test-idr`
  and `make test-mlir-tools`. It is also the first run of the runtime
  platform layer's Linux branches and the Linux check of the
  retirements PINS.md records, observed on arm64 only. A failure that
  reproduces with upstream dialects and tools is a patch in
  `upstream/`; any other is ours, fixed in the tree.
- **The bench.** `bench/run.sh --record` on each target. On arm64 it
  is read against `bench/runs/2026-10-13-9a1b7b1-darwin-arm64` by each
  program's ratio to its own C, and a ratio worse by more than 2%, best
  of five, is a regression, bisected and fixed (the cutover's §10
  runtime margin; 0003 D35 and D36 measured the five-run spread at up
  to 97%, so the spread bounds nothing). Linux records a fresh
  baseline.
- **The other presets.** `release` and `hardened` configure and build,
  and `lint` runs its clang-tidy build (the presets beside `base`,
  `dev` and `typecheck`, `CMakePresets.json`).
- **Peak live cells of `tests/programs/eval/thunk-consumes-list`**: max
  RSS at 10^5 and 10^6, measured by §2 step 4's host function; bounded
  means the larger run's max RSS is under twice the smaller's.
- **`tests/upstream-idris/run` without its raw-pointer source scan.**
  The scan skips any test naming `prim__castPtr`, `prim__forgetPtr`,
  `prim__nullPtr`, `prim__nullAnyPtr`, `prim__getNullAnyPtr`,
  `prim__getString` or `getEnv` (`tests/upstream-idris/common.sh:94-98`),
  and every one of them is now admitted: the pointers as the runtime's
  handles (`compiler/src/IdrisMLIR/Registry/Libraries.idr:121-126`,
  `Recognized.idr:118-123`), `getEnv` and `getString` as primitives
  (`Registry/Primitives.idr:298, 376`). *Decision:* the scan goes, and
  a test that then fails is a failure, not a skip. The compiler's own
  refusal stays a skip through `rejection_skip`, which reads the
  refusal's rule and skips only one whose category is outside the
  language (`common.sh:117-127`; `tests/lib/rules.sh` reads the rule
  list the generator writes from ODS), never its message: System.FFI's
  `malloc` is still `unsupported (raw pointer)` (`Recognized.idr:205`),
  since raw pointers are outside the language.

**Not proved.**

- **Compile times.** *Decision:* G1's run takes `tests/compile-times.sh`
  on both targets and commits the record under `bench/profiles/`; that
  record is the first baseline, since none was committed before the
  cutover (`bench/profiles/` holds F0 alone). The 2026-10-13 figure
  (167.9 s over 429 compilations after the first compile-time round) is
  *recalled*: it is in no file and no commit message, and HANDOFF's
  2026-10-13 entry counts 490 compilations in a `/tmp` record since
  lost. Reason: a threshold needs a baseline anyone can read. A pass
  that later grows against that record is fixed or its cost stated.
- **The analyses, once each.** Taken once, on the tree after the
  cutover, from its first stage-0 record: no `(A)` row of an analysis
  appears twice between two steps that both preserve it; the
  verifier's share per stage and after `idr-rc`; the serial residue per
  stage.

## 4. Measures

- The suite's compile-time record, total and the ten slowest, first
  taken in G1's run (D19).
- The stage-0 handoff: functions, operations, bytes.
- The pipeline on the stage-0 module: wall and user time per pass and
  per analysis, and peak resident memory, by binary from the saved
  module (the cutover's §10).
- The bench on both targets by ratio to C.
- Determinism: byte for byte at 1, 2 and 8 threads.

## 5. Decisions (the record)

- D1 (owner): this proposal first; self-hosting follows; then
  sharding. Amended 2026-10-13 (compile time inserted) and 2026-10-14
  (the pipeline cutover before the remaining self-host steps, because
  stage 1 cannot finish without it; see the proposals index for the
  queue).
- D7: a stage lands only with its proof; a stage that makes the
  compile-time record worse is not taken until it does not. Stands, as
  the cutover's §10 thresholds and its rule that a stage missing its
  threshold is reworked or reverted whole, never kept beside the old
  form.
- D9: G1 runs once, on the tree after the cutover, the representation
  wave and 0004, as their proof on both targets (§3, "When").
- D10: §2's step 4 is a record, not a gate, unless a stage does not fit
  the owner's machine.
- D11: §2's step 6 follows step 5.
- D12: the upstream-Idris raw-pointer source scan goes; the compiler's
  own refusal stays a skip, by its rule's category (§3).
- D13: this proposal is deleted when G1 is green on both targets,
  §2's steps 5 and 6 are recorded in HANDOFF.md, and the precise
  rejection messages (D17) have landed.
- D16: `make self` compares stage 2 with stage 3 at the default thread
  count; thread independence is step 5's one record at 1, 2 and 8
  threads and `tests/determinism`'s on every suite run (§2 step 5).
- D17: precise rejection messages are fields added to the structured
  refusal of the cutover's D42, in a change of this proposal's after
  G1's run that rewrites the reject tests' expected files; not a
  self-host step (§2).
- D19: G1's compile-time baseline is the record its run commits under
  `bench/profiles/`; the 2026-10-13 figure is recalled, not a baseline
  (§3).

**Open, for the owner:** where G1's x86_64 Linux leg runs. Default: a
native x86_64 Linux machine of the owner's, since the bench needs the
target's hardware and no cross run or emulation counts as green. Until
one runs it, Linux stays NotRun and neither this proposal's cutover nor
the pipeline cutover is done on that target.
