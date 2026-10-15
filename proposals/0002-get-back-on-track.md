# 0002: get back on track: what remains

**Status:** decided 2026-10-12. The cutover it designed is committed and
builds on arm64 macOS: an in-tree MLIR dialect in upstream's layout,
`idr.func` with inherent facts, analyses under the pass manager,
function passes in parallel, no erased value emitted, profiling through
the pass manager. This file keeps only what remains; trimmed 2026-10-14
at b4713f66 and 552d682a, against 0004's rewrite at 3de67510, and again
at ccaba89c.

The gate on arm64 macOS (*measured*, `NCPU=6`, HANDOFF.md): at
7a27fd34, before the opt-in SCC pipeline, `make check` 26/26,
`make test-idr` 286/286, `make test` 415/415; at 552d682a, which added
that opt-in (default off) and 0001's licenses gate, `make check` 27/27,
`make test-idr` 286/286, `make test` 415/415. `make test-mlir-tools`
was last recorded 17/17 on 2026-10-13. 0004's cutover deleted the
opt-in, so the gate the cutover must reproduce is the rounds' 415/415.
At ccaba89c `make check` is 27/27 (*measured* on the typecheck machine
2026-10-14): the one failure at 3de67510, `spec/time-trace` finding the
culled profiler's name in a verbatim research note, is fixed (§3).
At bfdcac70 `make check` is 32/32 on the typecheck machine.
x86_64 Linux is NotRun: nothing of this tree has been built there.

Licensing (0001) is built but for its L5 and L6, now ordinary work on
`main` (0001 D12). G0 is taken as 0004's F0. Self-hosting (§2) is not
done: stage 1 has never finished, and its remaining steps run after
the qualification of 0004's pipeline cutover with 0003's stage 1
(c7aa7b62, 5d5f3312) and of 0005 on top of it (bfdcac70), all coded and
integrated on the typecheck machine and none built; that proof is owed
on the owner's machine (HANDOFF.md; 0004 §0, §10; 0005 §10). G1's run
before the cutover was not taken (§3). Claims are marked: *read* (the
path), *measured* (the record), *recalled*, *conjecture*, *decision*.

**The one sentence.** The wall was the rounds, which 0004's cutover
deleted, and sharding (0007) comes after it: the whole program stays
the unit of meaning and stops being the unit of work. This proposal
holds the gate that proves the tree on both targets after that cutover
and 0005, and the road from there to a compiler that compiles itself.

## 1. Stages

| Stage | Status |
| --- | --- |
| C1 to C5, H1, H2 (the cutover) | done: committed, builds on arm64 macOS, gate above |
| G0 (baseline record) | done, as 0004's F0 (`bench/profiles/2026-10-14-f0-stage0.md`) |
| G1 (both targets, §3) | remains: the run before 0004's cutover, beside its lane L0, was not taken; G1 runs on the tree after the cutover and 0005, as their proof on both targets |
| S (self-hosting, §2) | remains: steps 1 and 2 done, step 3's record taken; the wall was the rounds, which 0004's cutover deleted (its §3 is the record, §10 the plan); step 3 is done at stage 0's first run through the new pipeline, and steps 4 to 6 follow; all wait on the qualification on the owner's machine |

## 2. Self-hosting

Each step is measured before the next starts. Steps 4 to 6 run on the
tree after 0004's cutover and 0005, once the owner's machine has
qualified it (proposals/README.md, the next chain).

1. **Integrate.** Done; the tree is one tree and the gate above is its
   record.
2. **Green on the owner's machine.** Done on arm64 macOS (the gate
   above).
3. **Break the wall.** The record is taken: 0004's F0, which is also
   0007's S0 (0004 §3.1). The frontend is not the wall: it emits the
   stage-0 module, 58,236 functions and about 300 MB of text (294 MB in
   F0's generic form), in about 140 s. Simplify's rounds are: round 1
   takes 447 s, sixteen rounds reach no fixpoint, and Simplify alone
   extrapolates past 2,000 s unfinished. The first compile-time round
   did not change that (one round fell from 1,321 s to 385 s, dev
   build), and stage 1 did not finish in 4 h 23 min on the pre-round
   compiler, nor in the restarted attempt that followed (*measured*
   then; 0004 §3.1, from the compile-time proposal at dcb087d2, the
   runs' own logs not kept). *Decision:* the wall
   is broken by 0004's cutover, not by further fixes to the rounds,
   because the round count is what remains and the cutover deletes the
   rounds (0004 §3.2, D13). The step is done when the stage-0 module
   runs through the whole post-cutover pipeline to an executable for
   the first time, within 0004 §10's thresholds (the optimizer segment
   under 600 s of wall, the label solve under 10 s), recorded with
   `-mlir-timing` and the time trace (`tools/profile.sh`), by binary
   from the saved module (0004 D22). 0007's S2's first step (code
   generation split after one whole-module O3) is taken inside that
   cutover, its lane L7; its second step, the split before O3, follows
   it (0004 §5.4, §10).
4. **The diet and the memory.** Recorded from step 3's run: the stage-0
   handoff's functions, operations and bytes (MLIR bytecode after the
   cutover, 0004 §4.1, so its bytes are not comparable with the text
   records below; functions, operations, time and memory are), and the
   peak resident memory of the frontend and of the pipeline. The
   records to beat: the frontend at 9.1 GB peak for a 405 MB text
   module in 137 s (arm64 macOS, 2026-10-10, HANDOFF.md); the rounds at
   5.27 GB peak in round 1 and about 5.8 GB steady, and the
   RemoveDeadValues tail at 7.65 GB (F0). *Decision:* this step is a
   record, not a gate. It holds `make self` back only if a stage does
   not fit the owner's machine; then the stage the record names is fixed
   first, in the proposal whose design it is (the frontend's memory is
   0009's ground; the pipeline's next cost is on 0004 §10's list after
   the cutover). Reason: stage 0 already ran at 9.1 GB on that machine,
   and a reduction that blocks nothing belongs to the proposal that
   owns the design. *Decision:* peak memory is measured by one function
   of the host layer, `tools/host.sh`, which `tools/self.sh` and G1's
   bounded-memory check (§3) both call. Built by 0005's lane R17:
   `tools/host.sh`'s `peak_memory` runs a command and records its peak
   resident set from `getrusage`, its unit decided there per host, and
   `tools/self.sh` calls it for each stage, writing
   `build/self/stageN/peak-kib` (*read*), in place of the
   `/usr/bin/time -l` it ran, macOS's flag alone. Reason: AGENTS.md's
   rule that per-target cases outside the target's one place are bugs,
   and step 5 is recorded on both targets.
5. **`make self`.** Stages 1 to 3 on the self-compiled frontend
   (`make self`, `tools/self.sh`, 1ce907d3): stage 2 byte-identical to
   stage 3 (the executable, the module, now the `.mlirbc` the frontend
   hands the pipeline, and the Core), recorded in
   HANDOFF.md on arm64 macOS and on x86_64 Linux. *Decision:* `make
   self` checks stage 2 against stage 3 at the default thread count, as
   it does today (`tools/self.sh:44`, `--num-threads="$ncpu"`); thread
   independence is checked once, in step 5's record, by stage 3's
   compile of itself at 1, 2 and 8 threads, byte for byte, and on every
   suite run by `tests/determinism` on its programs. Reason: 0004's
   determinism rules make every output a function of its input alone
   (0004 §4), which the suite checks on every run; repeating the
   self-compile at three thread counts in every `make self` triples its
   cost for a property the suite already holds. `tests/determinism`
   compiles at 1, 2 and 8 threads since 0004's lane L8
   (`tests/lib/determinism.sh:7`, *read*; not yet run).
6. **The test runner off Chez.** The runner compiled by the
   self-hosted compiler, so `make test` needs no Chez at all: its
   orchestration in sh, its generators compiled by idris-mlir, an
   `--exports` query in place of the stock REPL;
   `tests/toolchain/static-linking` covering `idris-mlir-front`; and
   AGENTS.md's Chez exception narrowed to stage 0 and the bench's
   baseline (HANDOFF.md, the 2026-10-12 state). *Decision:* this step
   follows step 5 and does not gate 0003's stage 1, which landed in
   0004's swarm wave, before it. Reason: the runner and the array
   stack are disjoint trees, and nothing in 0003 needs the runner off
   Chez. *Decision:* the bench's Chez column is timing only: its output
   is never compared with the reference, which this compiler's output or
   clang's is (`bench/run.sh:277-294` compares it today and dies on a
   difference; G1 removes that before its run, §3). So the exception
   step 6 writes into AGENTS.md covers running stock Idris's Chez
   backend for a time, and never its meaning. Reason: a run that fails
   when Chez prints a value differently (`"+inf.0"` against the
   runtime's `inf`, `upstream/18-elaboration-primitive-folding`) makes
   Chez's meaning a gate, which AGENTS.md's no-oracle paragraph forbids;
   the C column is the comparison that matters (0003 §21 item 4), and it
   stays, since the C program is a rebuild of ours whose output only
   shows that the two programs compute the same thing.

HANDOFF.md's list of what follows `make self` names one more item,
every rejection message made precise (what was found, where, why, and
what form compiles; the owner's request of 2026-10-10, HANDOFF.md's
2026-10-12 state). *Decision:* it is not a self-host step, and it is
not the cutover's. 0004 D42 makes a refusal's rule structured data on
its diagnostic, in lane L4, and is proved by every reject test's
expected text unchanged. The four parts are fields added to D42's data
in a change of this proposal's own, after G1's run after the cutover:
the frontend's refusals and the C++ side's each fill them where the
refusal is decided, the driver renders them in the one place D42 puts
the phrase, and the reject tests' expected files are rewritten in the
same change. Reason: the content of a refusal changes those expected
files, which the cutover's proof holds fixed, so the two cannot be one
change; the representation comes first because the fields need a place
to live.

Then, in queue order (proposals/README.md, the next chain): x86_64
Linux, step 6, 0004 §5.4's split before O3, then sharding, 0007's
stages with 0006's P1, P2 and P4. 0003's stage 1 (the array purge as one hard cutover, its fork
users ported in the same change) is not on this road any more: it
landed with 0004's cutover, before `make self` (c7aa7b62, 5d5f3312).
0012's features may start any time after step 5.

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
cutover's proof includes the run after it. *Decision:* the run before
the cutover is taken on the commit 0004's lane L0 records its baseline
on, so the bench, the compile-time suite and L0's stage-0 timings all
name one old binary. Reason: 0004 §10 measures old binary against new,
and two baselines from two commits would leave a threshold comparing
against a binary no record names.

*What happened:* the run before the cutover was not taken. 0004's
cutover and 0005 were coded and integrated on the typecheck machine,
which builds no LLVM, before the owner's machine ran anything, so G1
runs once, on the tree after both, as their proof. HANDOFF.md's list
reads the bench against the one record kept,
`bench/runs/2026-10-13-9a1b7b1-darwin-arm64`, and stage 0's optimizer
against 0004 §10's margin (under 600 s of wall). D14's commit was never recorded, so
this file names no old binary for a threshold that compares old against
new; the Linux leg has no baseline but the one it records.

**Closed since the last trim.**

- **`spec/time-trace`.** At 3de67510 it found the culled profiler's
  name in `sources/notes/compile-pipeline/mojo.md`, a verbatim research
  note (*measured*). The note stays verbatim; the test's mention search
  now leaves out `sources/` beside `third_party` and `proposals`
  (`tests/spec/time-trace/run:11`, ccaba89c), and `make check` is 27/27
  (*measured*, above).

**Not run.**

- **x86_64 Linux.** `make bootstrap` (every step of
  `tools/bootstrap.sh`: `llvm` alone builds neither GMP, nor Chez, nor
  Idris), then `make build`, `make check`, `make test`, `make test-idr`
  and `make test-mlir-tools`. It is also the first run of the runtime
  platform layer's Linux branches and the Linux check of the
  retirements PINS.md records, observed on arm64 only. A failure that
  reproduces with upstream dialects and tools is a patch in
  `upstream/`; any other is ours, fixed in the tree. `tools/self.sh`'s
  peak-memory measure is now `tools/host.sh`'s (§2 step 4), so step
  5's Linux record can be taken.
- **The bench.** `bench/run.sh --record` on each target. On arm64 it
  is read against the one record kept,
  `bench/runs/2026-10-13-9a1b7b1-darwin-arm64`, by each program's
  ratio to its own C, and a ratio worse by more than 2%, best of five,
  is a regression, bisected and fixed (0004 §10's runtime margin; 0003
  D35 and D36 measured the five-run spread at up to 97%, so the spread
  bounds nothing). Linux records a fresh baseline. The run before the
  cutover, which was to be each target's old binary for 0004 §10's
  thresholds, was not taken ("What happened", above). `bench/run.sh`
  no longer compares the Chez column's output with the reference: only
  this compiler's and clang's are held to it, and Chez is timed only
  (`bench/run.sh:11-17, 48-51`, *read*; D20).
- **The other presets.** `release` and `hardened` configure and build,
  and `lint` runs its clang-tidy build (the presets beside `base`,
  `dev` and `typecheck`, `CMakePresets.json`). The `profile` preset the
  packet named was deleted with Tracy (5677cd90, D8).
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
  refusal stays a skip through `rejection_skip`
  (`common.sh:115-127`): System.FFI's `malloc` is still
  `unsupported (raw pointer)` (`Recognized.idr:205`), since raw
  pointers are outside the language. The scan is still in the tree
  (`common.sh:94-97`, *read*). `rejection_skip` now reads the refusal's
  rule and skips only one whose category is outside the language
  (`common.sh:117-127`; `tests/lib/rules.sh` reads the rule list the
  generator writes from ODS; 0004 D42, 0005 D4), never its message.

**Not proved.**

- **Compile times.** *Decision:* G1's run before the cutover runs
  `tests/compile-times.sh` on both targets and commits the record under
  `bench/profiles/`; that record is the baseline. That run was not
  taken, so no baseline is committed; `bench/profiles/` holds F0 alone. The 2026-10-13 figure
  (167.9 s over 429 compilations after the first compile-time round) is
  *recalled*: it is in no file and no commit message, and HANDOFF's
  2026-10-13 entry counts 490 compilations in a `/tmp` record since lost
  (0004 §3.1). Reason: a threshold needs a baseline anyone can read. A
  pass that grew against that record is fixed or its cost stated. After
  the cutover the record is 0004 §10's, against the same binary.
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

**Seams** (re-read 2026-10-14 at ccaba89c, and their state checked
against bfdcac70 on 2026-10-15; nothing was run on this machine but
`make check`):

- **Which memo labels are `by_name`.** Closed in part: `markByName`
  reads the `ObservableIO` trait, so which op is an observable effect
  is said once, beside the op
  (`foreign/idr/lib/Transforms/Defunctionalize/ByName.cpp:26-28`). Its
  own reachability walk through direct calls (`:30-53`) is one of the
  three effects computations 0004 replaces with one summary, computed
  right after the label solve and before the conversion, which puts each
  memo sum's `by_name` labels in its body when the type is made;
  `markByName`'s walk goes (0004 §2.7, D34, D29; §4 stage 4, §6).
  Closed by the cutover: `ByName.cpp` is gone (*read*), unrun.
- **`closureLabel` and memo labels.** Closed: it returned a memo sum's
  label constructors (`foreign/idr/lib/Analysis/References.cpp:174-188`),
  and 0005 D21 deleted that file as dead code, a label now holding its
  function (0005 D1).
- **An `array.new` fill function that never returns** was an internal
  error, which refuses and does not miscompile (*recalled*: the
  qualification record of d8d23404, written against the tree before
  0002's cutover). Today `idr.array.new` takes a fill value, not a
  function, and a `generate` or `fold` body that never returns lowers
  to the program's crash (`tests/idr/lower/array-never-returns.mlir:2-5,
  35`, *read*), so the seam may no longer exist. *Decision:* it is not
  re-run here; it moved to 0003's stage 1, whose purge was to delete
  `idr.array.new` (0003 §15) but kept it as the world-ordered array's
  allocation (`foreign/idr/include/idr/IR/IdrArrayOps.td`); 0005's
  lane R10 decided it: `idr.array.new` stays, with its fill value,
  because an empty slot is a state an IOArray must not hold (0005 §11),
  so no fill function exists to diverge.
- **A partially applied `castPtr`.** The identity hook applies only at
  full arity (`compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr:364-370`);
  below it the call goes to the definition, `prim__castPtr = believe_me`
  (`:354`). The profile does not look into that body, because it holds
  that the identity hook answers for it (`Frontend/Profile.idr:65-70`),
  so the profile and the translation disagree below full arity. The
  translation of the body then reaches the `BelieveMe` primitive and
  refuses it as an escape hatch (`Terms.idr:868-871`), so the program is
  refused, not miscompiled (*read*, not run). *Decision:* one rule for
  every hook applied below its arity: emission eta-expands it, in
  symbol form, so that the partial application is an ordinary closure
  whose body is the saturated call, and the profile's assumption holds
  everywhere. It is emission's work, in 0004's lane L1, which owns
  `Frontend/Translate` and writes closures in symbol form (0004 §4.1,
  §10). Built (`Terms.idr`'s identity hook, below its arity a closure
  over its missing parameters; fixture
  `tests/programs/basic/partial-cast-pointer`, *read*), unrun.
- **`--demand-in-place` against `--without`.** Closed 2026-10-14 as a
  usage error (`tests/idr/pipeline/steps.mlir:18-21, 34-36`, 44495199);
  both options went in 0004's lane L4, and that test with them (0004 §6).

## 4. Measures

- The suite's compile-time record, total and the ten slowest: to be
  taken before the cutover as the baseline (D19), which was not done;
  it is first taken on the tree after the cutover and 0005.
- The stage-0 handoff: functions, operations, bytes.
- The pipeline on the stage-0 module: wall and user time per pass and
  per analysis, and peak resident memory, by binary from the saved
  module (0004 §10).
- The bench on both targets by ratio to C.
- Determinism: byte for byte at 1, 2 and 8 threads.

## 5. Decisions (the record)

- D1 (owner): this proposal first; self-hosting follows; then
  sharding. Amended 2026-10-13 (compile time inserted) and 2026-10-14
  (0004's cutover before the remaining self-host steps, because stage 1
  cannot finish without it, with 0003's stage 1 in the same swarm wave;
  see the proposals index for the queue).
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
- D9: G1 runs before 0004's cutover and after it (§3, "When"). The
  run before was not taken; G1 runs after the cutover and 0005 (§3,
  "What happened").
- D10: §2's step 4 is a record, not a gate, unless a stage does not fit
  the owner's machine.
- D11: §2's step 6 follows step 5 and does not gate 0003's stage 1.
- D12: the upstream-Idris raw-pointer source scan goes; the compiler's
  own refusal stays a skip (§3). The skip by rule is built; the scan is
  not yet removed.
- D13: this proposal is deleted when G1 is green on both targets after
  0004's cutover, §2's steps 5 and 6 are recorded in HANDOFF.md, and
  the precise rejection messages (D17) have landed.
- D14: G1's run before the cutover is on the commit 0004's L0 records,
  one old binary for every baseline (§3, "When"). Not taken: L0
  recorded no commit.
- D15: peak memory is one function of `tools/host.sh`, used by `make
  self` and G1 alike (§2 step 4). Built (0005's R17).
- D16: `make self` compares stage 2 with stage 3 at the default thread
  count; thread independence is step 5's one record at 1, 2 and 8
  threads and `tests/determinism`'s on every suite run (§2 step 5).
- D17: precise rejection messages are fields added to 0004 D42's
  structured refusal after the cutover, in a change of this proposal's
  that rewrites the reject tests' expected files; not a self-host step
  and not the cutover's, whose proof holds that text fixed (§2).
- D18: a hook applied below its arity is eta-expanded by emission, in
  0004's L1, with a fixture for a partially applied `castPtr` in its L8
  (§3, seams; 0004 §4 stage 1, §10). Built, unrun.
- D19: G1's compile-time baseline is the record its run before the
  cutover commits under `bench/profiles/`; the 2026-10-13 figure is
  recalled, not a baseline (§3).
- D20: the bench's Chez column is timing only; `bench/run.sh` compares
  only this compiler's and clang's outputs with the reference, from
  before G1's run (§2 step 6, §3). Reason: AGENTS.md's no-oracle rule.
  Built (`bench/run.sh`'s `compared` columns).

**Open, for the owner:** where G1's x86_64 Linux leg runs. Default: a
native x86_64 Linux machine of the owner's, since the bench needs the
target's hardware and no cross run or emulation counts as green. Until
one runs it, Linux stays NotRun and neither this cutover nor 0004's is
done on that target.
