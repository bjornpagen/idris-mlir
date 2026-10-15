# 0002: get back on track: what remains

**Status:** decided 2026-10-12. The cutover it designed is committed and
builds on arm64 macOS: an in-tree MLIR dialect in upstream's layout,
`idr.func` with inherent facts, analyses under the pass manager,
function passes in parallel, no erased value emitted, profiling through
the pass manager. This file keeps only what remains; trimmed 2026-10-14
at b4713f66 and 552d682a, and again at 3de67510 against 0004's rewrite.

The gate on arm64 macOS (*measured*, `NCPU=6`, HANDOFF.md): at
7a27fd34, before the opt-in SCC pipeline, `make check` 26/26,
`make test-idr` 286/286, `make test` 415/415; at 552d682a, which added
that opt-in (default off) and 0001's licenses gate, `make check` 27/27,
`make test-idr` 286/286, `make test` 415/415. `make test-mlir-tools`
was last recorded 17/17 on 2026-10-13. 0004's cutover deletes the
opt-in, so the gate the cutover must reproduce is the rounds' 415/415.
At 3de67510 `make check` is 26/27 (*measured* on the typecheck machine
2026-10-14): `spec/time-trace`, D8's check, finds the culled profiler's
name in the verbatim research note
`sources/notes/compile-pipeline/mojo.md` (§3). x86_64 Linux is NotRun:
nothing of this tree has been built there.

Licensing (0001) is built. G0 is taken as 0004's F0. Self-hosting (§2)
is not done: stage 1 has never finished, and its remaining steps run
after 0004's pipeline cutover, which is designed and awaits the
owner's approval (0004 §0, §10). Claims are marked: *read* (the path),
*measured* (the record), *recalled*, *conjecture*, *decision*.

**The one sentence.** The wall is 0004's cutover, and sharding (0006)
comes after it: the whole program stays the unit of meaning and stops
being the unit of work. This proposal holds the gate that proves the
tree on both targets, before that cutover and after it, and the road
from the cutover to a compiler that compiles itself.

## 1. Stages

| Stage | Status |
| --- | --- |
| C1 to C5, H1, H2 (the cutover) | done: committed, builds on arm64 macOS, gate above |
| G0 (baseline record) | done, as 0004's F0 (`bench/profiles/2026-10-14-f0-stage0.md`) |
| G1 (both targets, §3) | remains, run twice: on the tree before 0004's cutover (the baseline on both targets) and after it (the cutover's proof on both) |
| S (self-hosting, §2) | remains: steps 1 and 2 done, step 3's record taken; the wall is 0004's cutover (its §3 is the record, §10 the plan); steps 4 to 6 follow it |

## 2. Self-hosting

Each step is measured before the next starts. Steps 4 to 6 run on the
tree after 0004's cutover.

1. **Integrate.** Done; the tree is one tree and the gate above is its
   record.
2. **Green on the owner's machine.** Done on arm64 macOS (the gate
   above).
3. **Break the wall.** The record is taken: 0004's F0, which is also
   0006's S0 (0004 §3.1). The frontend is not the wall: it emits the
   stage-0 module, 58,236 functions and about 300 MB of text, in about
   140 s. Simplify's rounds are: round 1 takes 447 s, sixteen rounds
   reach no fixpoint, and Simplify alone extrapolates past 2,000 s
   unfinished. The first compile-time round did not change that (one
   round fell from 1,321 s to 385 s, dev build), and stage 1 did not
   finish in 4 h 23 min on the pre-round compiler, nor in the restarted
   attempt that followed (*measured*, the record carried in 0004's
   earlier drafts). *Decision:* the wall is broken by 0004's cutover,
   not by further fixes to the rounds, because the round count is what
   remains and the cutover deletes the rounds (0004 §3.2, D13). The step
   is done when the stage-0 module runs through the whole post-cutover
   pipeline to an executable for the first time, within 0004 §10's
   thresholds (the optimizer segment under 600 s of wall, the label
   solve under 10 s), recorded with `-mlir-timing` and the time trace
   (`tools/profile.sh`), by binary from the saved module (0004 D22).
   0006's S2 (split LLVM codegen) is taken inside that cutover, its lane
   L7 (0004 §5.4), not after it.
4. **The diet and the memory.** Recorded from step 3's run: the stage-0
   handoff's functions, operations and bytes (bytecode once 0004 §4.1
   lands), and the peak resident memory of the frontend and of the
   pipeline. The records to beat: the frontend at 9.1 GB peak for a
   405 MB text module in 137 s (arm64 macOS, 2026-10-10, HANDOFF.md);
   the rounds at 5.27 GB peak in round 1 and about 5.8 GB steady, and
   the RemoveDeadValues tail at 7.65 GB (F0). *Decision:* this step is a
   record, not a gate. It holds `make self` back only if a stage does
   not fit the owner's machine; then the stage the record names is fixed
   first, in the proposal whose design it is (the frontend's memory is
   0008's ground; the pipeline's next cost is on 0004 §10's list after
   the cutover). Reason: stage 0 already ran at 9.1 GB on that machine,
   and a reduction that blocks nothing belongs to the proposal that
   owns the design.
5. **`make self`.** Stages 1 to 3 on the self-compiled frontend
   (`make self`, `tools/self.sh`, 1ce907d3): stage 2 byte-identical to
   stage 3 (the executable, the module and the Core), and every stage's
   output byte-identical at 1, 2 and 8 threads (`tests/determinism`,
   0004 §4's determinism rules, 0006's S7). Recorded in HANDOFF.md on
   arm64 macOS and on x86_64 Linux.
6. **The test runner off Chez.** The runner compiled by the
   self-hosted compiler, so `make test` needs no Chez at all: its
   orchestration in sh, its generators compiled by idris-mlir, an
   `--exports` query in place of the stock REPL;
   `tests/toolchain/static-linking` covering `idris-mlir-front`; and
   AGENTS.md's Chez exception narrowed to stage 0 and the bench's
   baseline (HANDOFF.md, the 2026-10-12 state). *Decision:* this step
   follows step 5 and does not gate 0003's stage 1, which starts right
   after `make self` as the queue says. Reason: the runner and the array
   stack are disjoint trees, and nothing in 0003 needs the runner off
   Chez.

Then, in queue order: 0003's stage 1 (the array purge as one hard
cutover; `make self` stays green across it, its fork users ported in
the same change), then sharding: 0006's stages with 0005's P1, P2 and
P4. 0011's features may start any time after step 5.

## 3. G1: what the tree still owes on both targets

A target that has not run an item is NotRun, never green.

**When** (*decision*). G1 runs once on the tree before 0004's cutover
and again after it. Reasons: 0004 §10's thresholds (no bench program's
compile time worse by more than 5%, nor its runtime by more than 2%)
compare against the old binary, and x86_64 Linux has no record at all
(its records were purged, a00a0ec6), so only a run before the cutover
gives that target a baseline; a Linux failure found before the cutover
is a platform failure, not a cutover failure; and a change is done
only when it builds and passes on both targets (AGENTS.md), so the
cutover's proof includes the run after it.

**Not green.**

- **`spec/time-trace`.** At 3de67510 it finds the culled profiler's
  name in `sources/notes/compile-pipeline/mojo.md`, a verbatim research
  note (*measured*). The note is right to stay verbatim; the test's
  exclusions (`tests/spec/time-trace/run:9`, which leaves out only
  `third_party` and `proposals`) gain `sources/`, which keeps its own
  rules.

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
  is read against the one record kept,
  `bench/runs/2026-10-13-9a1b7b1-darwin-arm64`, by each program's
  ratio to its own C; worse beyond the spread is a regression,
  bisected and fixed. Linux records a fresh baseline. The run before
  the cutover is, on each target, the old binary 0004 §10's thresholds
  compare against.
- **The other presets.** `release` and `hardened` configure and build,
  and `lint` runs its clang-tidy build (the presets beside `dev` and
  `typecheck`, `CMakePresets.json`). The `profile` preset the packet
  named was deleted with Tracy (5677cd90, D8).
- **Peak live cells of `tests/programs/eval/thunk-consumes-list`**: max
  RSS at 10^5 and 10^6; bounded means the larger run's max RSS is under
  twice the smaller's.
- **`tests/upstream-idris/run` without its raw-pointer source scan.**
  The scan skips any test naming `prim__castPtr`, `prim__forgetPtr`,
  `prim__nullPtr`, `prim__nullAnyPtr`, `prim__getNullAnyPtr`,
  `prim__getString` or `getEnv` (`tests/upstream-idris/common.sh:94-98`),
  and every one of them is now admitted: the pointers as the runtime's
  handles (`compiler/src/IdrisMLIR/Registry/Libraries.idr:121-126`,
  `Recognized.idr:118-123`), `getEnv` and `getString` as primitives
  (`Registry/Primitives.idr:298, 376`). *Decision:* the scan goes, and
  a test that then fails is a failure, not a skip. The compiler's own
  refusal stays a skip through `rejection_skip`
  (`common.sh:115-127`): System.FFI's `malloc` is still
  `unsupported (raw pointer)` (`Recognized.idr:205`), since raw
  pointers are outside the language.

**Not proved.**

- **Compile times.** Before the cutover: the suite
  (`tests/compile-times.sh`) re-recorded on this tree against the
  2026-10-13 record (429 compilations, 167.9 s after the first
  compile-time round); a pass that grew is fixed or its cost stated.
  After the cutover the record is 0004 §10's.
- **The analyses, once each.** Taken once, on the tree after the
  cutover, from its first stage-0 record: no `(A)` row of an analysis
  appears twice between two steps that both preserve it; the
  verifier's share per stage and after `idr-rc`; the serial residue per
  stage. *Decision:* the tree before the cutover is not measured for
  it, and the packet's "round counts per program and their ten highest"
  is deleted with the rounds (0004 §6). Reason: a structure about to be
  deleted informs nothing that 0004 §3 does not already hold.
- **Sensitivity.** The discriminator rows the packet named
  (`tests/idr/func/*`, `tests/idr/asm/*`, the handoff and
  dialect-syntax compiler tests) fail at 25890d32 and pass on the
  cutover; run once in G1's run before 0004's cutover, since they test
  the cutover this proposal built. After 0004's cutover they are what
  its lane L8 leaves of them.

**Superseded: the owner's in-place decision.** "`--demand in-place`
stays opt-in until the bench passes with it on; then it is the default"
is superseded by 0004 (its D2 and §6): the option is deleted, the
in-place promise becomes a fact of `mlir-linear`'s types that the
frontend emits and `idr-demand` checks every time (0004 §4.1, lanes L1
and L4), and the bench condition is 0004 §10's runtime threshold.

**Seams** (re-read 2026-10-14 at 3de67510; nothing was run on this
machine):

- **Which memo labels are `by_name`.** Closed in part: `markByName`
  reads the `ObservableIO` trait, so which op is an observable effect
  is said once, beside the op
  (`foreign/idr/lib/Transforms/Defunctionalize/ByName.cpp:25-27`). Its
  own reachability walk (`:29-52`) is one of the effects computations
  0004 replaces with one summary (0004 §4.9, §6), so what remains is
  0004's lane L3, not G1's.
- **`closureLabel` and memo labels.** Closed: it returns a memo sum's
  label constructors (`foreign/idr/lib/Analysis/References.cpp:174-188`).
- **An `array.new` fill function that never returns** is an internal
  error, which refuses and does not miscompile. It moves to 0003's
  stage 1, whose purge deletes `idr.array.new`
  (`proposals/0003-typed-apl/README.md:1126`); the fixture goes with
  the purge's tests.
- **A partially applied `castPtr`.** The identity hook applies only at
  full arity (`compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr:364-370`);
  below it the call goes to the definition, `prim__castPtr = believe_me`.
  That it is still rejected is *recalled* from the packet, not re-run.
  It belongs to emission: one rule for every hook applied below its
  arity, its eta-expansion written in symbol form so that the partial
  application is an ordinary closure, in 0004's lane L1 (0004 §4.1).
- **`--demand-in-place` against `--without`.** Closed 2026-10-14 as a
  usage error (`tests/idr/pipeline/steps.mlir:18-34`); both options go
  in 0004's lane L4, and that test with them (0004 §6).

## 4. Measures

- The suite's compile-time record, total and the ten slowest: before
  the cutover against 2026-10-13, after it against the old binary.
- The stage-0 handoff: functions, operations, bytes.
- The pipeline on the stage-0 module: wall and user time per pass and
  per analysis, and peak resident memory, by binary from the saved
  module (0004 §10).
- The bench on both targets by ratio to C.
- Determinism: byte for byte at 1, 2 and 8 threads.

## 5. Decisions (the record)

- D1 (owner): this proposal first; self-hosting follows; then
  sharding. Amended 2026-10-13 (compile time inserted) and 2026-10-14
  (0003's stage 1 after `make self`, ahead of sharding; 0004's cutover
  before the remaining self-host steps, because stage 1 cannot finish
  without it; see the proposals index for the queue).
- D2: `foreign/idr` is an in-tree MLIR dialect in upstream's layout,
  no C++20 modules. Built.
- D3: every rewrite is a function pass under a nested pass manager;
  module passes only compute analyses or change symbols. Built. 0004
  keeps it: its ready set is a module-level scheduler whose units run
  one per-function pipeline through `Pass::runPipeline` (0004 §4.6),
  and the Simplify round's remaining module members go with the rounds
  (0004 §6).
- D4: one representation per fact. Built; AGENTS.md carries it.
- D5: the frontend emits no erased value. Built.
- D6: the round ends on a change flag, bounded. Superseded whole by
  0004 (D13, §6): there are no rounds, change is the returned fact of
  the pass that made it, and the round's module fingerprint goes.
- D7: a stage lands only with its proof; a stage that makes the
  compile-time record worse is not taken until it does not. Stands, as
  0004 §10's thresholds and its rule that a stage missing its threshold
  is reworked or reverted whole, never kept beside the old form.
- D8 (owner): profiling is LLVM's time trace through the pass
  manager; Tracy is out of the tree. Built (the `profile` preset went
  at 5677cd90); `tests/spec/time-trace` checks it.
- D9: G1 runs before 0004's cutover and after it (§3, "When").
- D10: §2's step 4 is a record, not a gate, unless a stage does not fit
  the owner's machine.
- D11: §2's step 6 follows step 5 and does not gate 0003's stage 1.
- D12: the upstream-Idris raw-pointer source scan goes; the compiler's
  own refusal stays a skip (§3).
- D13: this proposal is deleted when G1 is green on both targets after
  0004's cutover and §2's steps 5 and 6 are recorded in HANDOFF.md.

**Open, for the owner:** where G1's x86_64 Linux leg runs. Default: a
native x86_64 Linux machine of the owner's, since the bench needs the
target's hardware and no cross run or emulation counts as green. Until
one runs it, Linux stays NotRun and neither this cutover nor 0004's is
done on that target.
