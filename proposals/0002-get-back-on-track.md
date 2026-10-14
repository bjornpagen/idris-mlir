# 0002: get back on track — what remains

**Status:** decided 2026-10-12; the cutover it designed is built and
this file now keeps only what remains, trimmed 2026-10-14 at
b4713f66 and re-trimmed the same day at 552d682a. The cutover (the
deleted `0003-cutover-swarm/` packet, whose unfinished
qualification is §3 here) landed the design whole: an in-tree MLIR
dialect in upstream's layout, `idr.func` with inherent facts,
analyses under the pass manager, function passes in parallel, no
erased value emitted, profiling through the pass manager. On arm64
macOS at 552d682a the gate is green: `make check` 27/27 (0001's
licenses gate is the 27th), `make test-idr` 286/286, `make test`
415/415 (*measured* 2026-10-14 at `NCPU=6`). Licensing (0001) is
built; G0 is taken as 0004's F0. x86_64 Linux is NotRun.
Self-hosting (§2) is not done: stage 1 has never finished, and
step 3 is being executed in 0004 (F3's corpus verdict run in
flight, 0004 §2.2). Claims are marked: *read* (the path),
*measured* (the record), *conjecture*, *decision*.

**The one sentence.** What remains of the wall is in 0004 and 0006:
the whole program stays the unit of meaning and stops being the unit
of work. This proposal holds the gate that proves the cutover on both
targets and the road to a compiler that compiles itself.

## 1. Stages

| Stage | Status |
| --- | --- |
| C1 to C5, H1, H2 (the cutover) | done: built, arm64 gate green above |
| G0 (baseline record) | done, as 0004's F0 (`bench/profiles/2026-10-14-f0-stage0.md`) |
| G1 (both targets, §3) | remains: x86_64 Linux NotRun, bench unrun |
| S (self-hosting, §2) | remains: at step 3, executed in 0004 (§2.2 there is the live status) |

## 2. Self-hosting

Each step is measured before the next starts.

1. **Integrate.** Done; the tree is one tree and the gate above is its
   record.
2. **Green on the owner's machine.** Done on arm64 macOS (the gate
   above). G0's record is step 3.
3. **Break the wall by measurement.** The pipeline on the stage-0
   module (58,236 functions, ~300 MB of text; the frontend takes
   ~140 s of a stage-1 attempt) with `-mlir-timing` and a time trace:
   the first time the C++ side finishes on it. This is 0004's F0 and
   0006's S0, one record. The first compile-time round already landed
   against it (0004 §2): one Simplify round fell from 1,321 s to
   385 s (dev build), and stage 1 still did not finish in 4 h 23 min
   on the pre-round compiler, nor in the restarted attempt that
   followed. What dominates next is fixed first, in 0004's order.
   0006's S2 (units, split LLVM codegen, an ordered link) is taken as
   soon as the record shows codegen as the cost.
4. **The diet and the memory.** The stage-0 dump's functions,
   operations and bytes, and the peak resident memory of the frontend
   (9.1 GB at the 2026-10-10 measure) and of the pipeline. The stage
   that shrinks each is the one the measurement names.
5. **`make self`.** Stages 1 to 3 on the self-compiled frontend,
   stage 2 byte-identical to stage 3, and every stage's output
   byte-identical under one thread and under the pool
   (`tests/determinism`). When this is recorded in HANDOFF.md, this
   proposal is deleted.
6. **The test runner off Chez.** The runner compiled by the
   self-hosted compiler, so `make test` needs no Chez at all; Chez
   stays only as the host of stage 0.

Then, in queue order: 0003's stage 1 (the array purge as one hard
cutover; `make self` stays green across it, its fork users ported in
the same change), then sharding: 0006's stages with 0005's P1, P2
and P4.

## 3. G1: what the cutover still owes

A target that has not run an item is NotRun, never green.

**Not run.**

- **x86_64 Linux.** `tools/bootstrap.sh llvm`, then `make build`,
  `make check`, `make test`, `make test-idr` and
  `make test-mlir-tools`. It is also the first run of the runtime
  platform layer's Linux branches and the Linux check of the
  retirements PINS.md records, observed on arm64 only. A failure that
  reproduces with upstream dialects and tools is a patch in
  `upstream/`; any other is ours, fixed in the tree.
- **The bench.** `bench/run.sh` on each target against the one record
  kept, `bench/runs/2026-10-13-9a1b7b1-darwin-arm64`, by each
  program's ratio to its own C. Worse beyond the spread is a
  regression, bisected and fixed. The Linux records were purged
  (a00a0ec6), so Linux records a fresh baseline.
- **The other presets.** `release`, `hardened` and `profile`
  configure and build (the cutover packet's qualification, folded in
  here when the packet was deleted).
- **Peak live cells of `thunk-consumes-list`**: max RSS at 10^5 and
  10^6; bounded means the larger run's max RSS is under twice the
  smaller's.
- **`tests/upstream-idris/run`** with its pointer/environment skip
  removed, those functions being runtime handles now.

**Not proved.**

- **Compile times.** G0/F0 re-records the suite
  (`tests/compile-times.sh`) and the stage-0 module on this tree; a
  pass that grew against the 2026-10-13 record (429 compilations,
  167.9 s after the first compile-time round) is fixed or its cost
  stated.
- **The analyses, once each.** From the packet's qualification, now
  part of F0's record: no `(A)` row of an analysis appears twice
  between two steps that both preserve it; the verifier's share per
  round and after `idr-rc`; the serial residue per round; round
  counts per program and their ten highest.
- **Sensitivity.** The discriminator rows named by the packet
  (`tests/idr/func/*`, `tests/idr/asm/*`, the handoff and
  dialect-syntax compiler tests) fail at 25890d32 and pass now; run
  once at G1.

**The owner's decision not yet carried out.** `--demand in-place`
stays opt-in until the bench above passes with it on; then it is the
default.

**Seams to recheck at G1** (read before the cutover build; paths have
moved since, so each is re-read, not assumed): which memo labels are
`by_name` is a list in `Transforms/Defunctionalize/ByName.cpp` where a
trait would say it once; `closureLabel` does not see memo labels; an
`array.new` fill function that never returns is an internal error; a
partially applied `castPtr` is still rejected. (Rechecked and closed
2026-10-14: `--demand-in-place` with `--without idr-demand` or
`--without in-place` is a usage error naming both, tested in
`tests/idr/pipeline/steps.mlir`.)

## 4. Measures

- The suite's compile-time record, total and the ten slowest, against
  F0.
- The stage-0 dump: functions, operations, bytes.
- The pipeline on the stage-0 dump: wall and user time per pass and
  per analysis (F0's record).
- The bench on both targets by ratio to C.
- Determinism: one thread against the pool, byte for byte.

## 5. Decisions (the record)

- D1 (owner): this proposal first; self-hosting follows; then
  sharding. Amended 2026-10-13 (compile time inserted) and 2026-10-14
  (0003's stage 1 after `make self`, ahead of sharding; see the
  proposals index for the queue).
- D2: `foreign/idr` is an in-tree MLIR dialect in upstream's layout,
  no C++20 modules. Built.
- D3: every rewrite is a function pass under a nested pass manager;
  module passes only compute analyses or change symbols. Built; the
  Simplify round's remaining module members are 0004's to delete.
- D4: one representation per fact. Built; AGENTS.md carries it.
- D5: the frontend emits no erased value. Built.
- D6: the round ends on a change flag, bounded. Superseded in part:
  the round still fingerprints the module (`Simplify.cpp`), and 0004
  deletes the round structure itself.
- D7: a stage lands only with its proof; a stage that makes the
  compile-time record worse is not taken until it does not. Stands,
  as 0004's D1.
- D8 (owner): profiling is LLVM's time trace through the pass
  manager; Tracy is out of the tree. Built.
