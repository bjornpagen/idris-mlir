<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 synthesis E: how P0 is carried out

Reader E of P0 (`proposals/0000-mlir-native.md`). The cluster is
process: the pipeline and the build, the tests, the history's lessons,
and the parallel agent doing tracing and performance work on main.

Sources: lanes 13, 19, 20 and 21 in full; §7 and §8 of lanes 01–12 and
14–18; P0 §0–§4, §6, §8, §9 and parts of §5.1, §5.2, §5.5 and §5.11;
proposals 0001 and README; `tools/lanes/README.md`; and `git log
e96bb991..origin/main` (the local ref, not fetched: 101edbc5, 51a4771b).

Citations: "20 §5" is `audits/p0/20-history.md` §5; "P0 §5.11 A2" is
the proposal. Nothing here is a decision: the owner decides.

**Owner ruling received during this synthesis** (2026-10-21, through the
coordinator; not yet in P0 §9):
- "Heavy use of templates and concepts pls." Our own C++ is
  concept-constrained templates by default. §8 Q1, Q-M3 and Q-llvm-1
  are settled in that direction.
- Template compile time is therefore a cost P0 has to measure and
  manage: precompiled headers, and one explicit instantiation per
  translation unit (P0 §5.5 D3, D6; 13 DP-55, DP-59).
- Every change is a hard cutover that culls the old code, churning as
  far as the most elegant representation needs.

## 1. In plain words

**What this cluster is about.** P0 rewrites almost everything at once:
the dialect, the effects, the analyses, the C++, part of the Idris side.
This cluster asks how to do that without losing a working compiler on
the way: the pipeline and build every change passes through, the tests
that say a change is right, what the history says went wrong, and the
other agent changing the same code on main right now.

**What went wrong before** (20 §4.2, §5.1):
- **Upstream code adopted untested, then dropped unpatched.**
  Exclusivity went onto `DataFlowSolver` after one 0.84 s test
  (595ed341). Twenty-one days later it hit 627 GB and was dropped with
  no storage patch tried (ffa91113). Our own dead-values pass was deleted
  for upstream's `remove-dead-values`; four patches followed, and the
  pass left the next day (16005000; 20 §3.1, L1).
- **Waves landed type-checked, never built or run.** There were four in
  five days (10-14 to 10-18). `make test` was 415/415 on 10-14 and has
  not been green since (20 §2.3, L2).
- **Walls were fixed one at a time, under pressure.** "Build a graph
  once, mark it" was written three times in two days with no shared
  code; one version had a quadratic build, fixed three hours later
  (20 L4; 21 P-14).
- **Records drifted.** PINS.md and `upstream/` describe a pass that no
  longer runs (20 L5, H2, H3).
- **Agents reversed designs without a ruling.** The reversals that held
  were owner rulings written down that day (20 §4.1, L8).
- **Memory was known only from kills and samples**, never from a record
  (20 L7; 21 P-18).

**How P0 must be carried out differently** (the lanes' shared answer;
the owner decides each point in §5):
- **Measure first.** Add a per-pass footprint and time record, and take
  one complete stage-1 record at a fixed commit before the first
  refactor (13 §5 order 1; 20 §5.2 item 3; 21 §5.2).
- **Build, pass and measure every step before the next.** No unbuilt
  landing. Each step is a hard cutover that deletes what it replaces in
  the same commit (20 L2; the ruling above).
- **Freeze a set of tests the cutover cannot rewrite**, and pass it
  unchanged at every step (19 C3, T-Q1).
- **Move every name P0 changes out of the tests first**, into one
  generated pass table (19 C2; 13 T2).
- **Adopt or drop upstream code only with a stage-1-scale
  measurement** (20 L1).
- **Fix the starting tree and fence the parallel agent.** Main has been
  red since 101edbc5 (21 §5.5).

## 2. Where the lanes agree

**2.1 Measure before adopting or dropping upstream code.** This is the
history's main lesson (20 L1): every adoption, keep or removal carries a
stage-1-scale measurement, and a removal also carries the upstream patch
it tried or proof that the state is essential. The lanes owning the next
likely walls ask the same: Ranges and Returned (05 §8; 10 R-1; 11 R1),
the defunctionalization freeze (06 risk 1), exclusivity and Borrows (07
§8). P0 asks it of our own solvers too (P0 §4). The parallel agent's
loop (run, profile, sample, fix the representation) becomes a standing
method (21 §5.1).

**2.2 Every step builds and passes:** the five suites and a stage-1 run,
no WIP on main, no option selecting an old path (20 L2, H6–H8). 101edbc5
is the measured counter-example: it landed with "the program suite has
not been rerun", and its first run was 403/480 against 470/480 (21
P-16). Lanes 07 and 08 add a before-and-after on the corpus wherever
acceptance or counts could move (07 §8; 08 §8).

**2.3 An invariant test oracle.** The 234 program tests (907 cases), the
47 rejects with their `near/` neighbours, the 144 `semantics@` runs, the
30 benchmarks' outputs against clang's, and the fuzz seeds (19 C3).
Their inputs are Idris sources and bytes and they check behaviour, so P0
cannot rewrite them to agree with itself. It is an oracle of our own,
which testing-by-search names (SKILL §7) and AGENTS.md allows.

**2.4 The pipeline's shape.**
- **Facts once, read nested.** A module pass computes whole-program
  facts, and function-nested passes read them in parallel (P0 §5.1 F1,
  F2). A function pass reads its ancestors, never its siblings (P0 §5.8
  B9).
- **Lane 13 makes it one rule** (13 T1): every pass is exactly one kind.
  *Decide* computes a fact and changes nothing; *apply* rewrites each
  function from it, nested and parallel; *restructure* adds or erases
  functions and stays a program pass. Lane 08's nested grading needs the
  same shape (08 T6).
- **The order is data**, with a reason per step (13 T2; 19 C2; P0 §5.9
  A2; 0004 §3.6).
- **No fixpoint loop, and no round count that refuses** (P0 §5.6 D2;
  13 §3.1).

**2.5 Verification's cost.** Nine lanes fear the verifier after every
pass (21 §3.4); none measured it on stage 1. By reading, one compilation
runs three single-threaded whole-program walks up to 26 times (13 §2.3),
and symbol-dce and the canonicalizer re-verify even when they changed
nothing (13 DP-05, DP-06). Every lane cheapens it by mechanism, never by
a flag: nesting, upstream patches U-a and U-b, and each check moved to
where its fact changes (13 T3; 01 C7; 02 T2). On the suites it is
1.6–1.7 % of self time (51a4771b), which says nothing about 71 MB.

**2.6 A record per run.** Every stage-1 run leaves one, finished or not:
the frontier, time and footprint per pass with the measure named, and
V/B/P/F (21 perf-Q3, §5.1; 13 T5; 20 L7; P0 §5.11 A2). Records are part
of each change: PINS.md and `upstream/` change in the same commit, and
the upstream table is generated (20 L5).

**2.7 Budgets in the program's units only.** No budget refuses (13
W-E5; 19 §3.2; 04 T3; P0 §5.11 A4). A budget in bytes or seconds would
break stage 2 = stage 3 (P0 §5.11 C7).

**2.8 Determinism stays a property.** The code claims byte-identical
output at any thread count in four places, and tests it on a few
programs (13 §6 QL4; 19 §6 QL4). Footprint and trace data stay out of
every compared output (13 T5), and names never depend on order (09 R3;
15 §8).

**2.9 Solver units are actions.** Every solve, per function or per SCC,
is an MLIR action, so the trace names it and the debug counter can
bisect it (P0 §5.1 G2; 13 §3.1; 21 §5.1). None of the three new solvers
is one today (21 §3.2).

**2.10 Templates and concepts, and compile time managed.**
- The ruling settles the style. The lanes say how to pay for it: one
  explicit instantiation per solver in its own unit with `extern
  template` elsewhere (P0 §5.5 D3, D6.3), a `-ftime-trace` baseline
  before the churn (D6.2; 13 DP-59), and a precompiled header (D6.1; 13
  DP-55).
- Headers dominate, not templates (P0 §5.5 findings 11–13). By
  arithmetic, our 294 units spend about 7.5 CPU-minutes on headers per
  clean build, and about 2.1 with a PCH (13 DP-55).

## 3. Where they disagree, and what each turns on

**3.1 Verification in release.**
- Q-M2 offers Modular's split: the grade check after every pass, the
  structural verifier only at phase boundaries in release (P0 §5.4
  F16).
- Against it: AGENTS.md verifies grades after every pass;
  `tests/verifier-every-pass` refuses any way to turn the verifier off
  (19 §3.1); and a split by build type is a behaviour chosen by the
  build, which `Passes.td:4-5` excludes (13 §6 Q-M2).
- Lane 01 and P0 §5.8 B10 would move the def-use part of the grade check
  into a check pass run by instrumentation (types-Q1).
- **Turns on:** a cost nobody has measured, and whether the contract
  covers MLIR's structural verifier or only the grades.

**3.2 How to measure the verifier.**
- Lane 13: `idris-mlir-opt -verify-each=0` against the default (13 M2),
  or a pass's timing row minus its action span (13 §2.3, M1).
- Lane 19: read `--mlir-timing`'s `Verifier` rows, so the rule is never
  broken (19 T-Q5).
- **Turns on:** whether a run outside the tree counts as turning the
  verifier off.

**3.3 The order of the first steps.** All four lanes measure first.
Then lane 20 wants scale fixtures, U1 measured on Ranges, Borrows and
Returned, the solver layer with the three markings ported, and only then
the dialect's passes (20 §5.2 item 3). Lane 19 wants stage-named steps
(C2) and the ending record (C4) before any dialect change. Lane 13 wants
U-a and U-b, the pipeline as a record list, then decide/apply/restructure
lane by lane. Lane 21 wants one complete stage-1 record at a fixed
commit before anything. Lane 20 also wants DS1–DS3 (data table, grade,
world) decided on paper before any C++ against them (20 L3; 01 R3).
- **Turns on:** whether the solver layer precedes the dialect redesign,
  and how many owner answers come before any code.

**3.4 Hard cutover against old-versus-new comparison.**
- The history's best-run change rebuilt the label solve and compared old
  against new over 314 solves before deleting the old one (7adc6095;
  20 §5.3).
- Other lanes ask for the same kind of check: the analyses compared on
  the corpus before the old goes (07 §8); statistics and live cells per
  test, before and after (08 §8); memoized against recomputed (15 §8);
  BindingTimes reproducing today's remarks (05 §8); a byte-identical
  module (14 §8).
- The ruling: every change is a hard cutover that culls the old code.
- The two fit only if the old form lives inside one step, never ships,
  and goes in that commit, as "a second implementation we own" (SKILL
  §7). The alternative is a recorded artifact: statistics or outputs
  captured before the step, compared after.
- **Turns on:** whether a comparison inside one commit is a "dual path".

**3.5 WIP on main.**
- The lanes README, the owner's binding rules, allows WIP commits that
  build.
- Lane 20 asks for none during the cutover (20 H7), and hist-Q2 asks
  whether any unbuilt landing is allowed.
- **Turns on:** whether a P0 step may span commits.

**3.6 Is a stage-1 run a record or a gate?**
- 0001 D4 calls time and memory "a record, not a gate", and 0001 D9 runs
  S3 before green suites.
- Lane 20 puts a stage-1 run in every step's gate (20 L2, §5.2 item 2).
- Lane 21 wants a record every step, "whether or not the pipeline
  finishes".
- **Turns on:** whether a step may make the frontier or a footprint
  worse.

**3.7 P0 first, or S3 alongside?**
- P0 D1 puts P0 before everything, and D4 forbids code before the plan.
- `proposals/README` agrees in "Where the work stands", but its "What
  comes next" still lists 0001 S3 as step 2.
- The parallel agent pushed nine commits in eighteen hours, two after
  the audit base, all in audited code (21 §6.1 Q2).
- Nothing written says whether D4 binds it.

**3.8 Three designs for one code path.**
- Counting's queries: 101edbc5's `Positions` (a numbering with spans, on
  main), lane 07 D5 (a scope analysis shared with the verifier), and
  lane 08 T3 (a reverse walk with no position queries) (21 §3.6, §5.4).
- The trait layer: the agent's waves keep `SameValue` and give it a
  `verifyTrait`; P0 §5.8 DS4 and lane 02 delete it into one forwarding
  declaration (21 §3.3). `Idr_Decides` restates what
  `RegionBranchOpInterface` answers (21 P-5).

**3.9 Wave 1 against our code** (lane 13 unless marked).
- **Refuted by our code:** "ccache cannot cache a PCH" (by P0 §5.5 D6;
  13 §3.1); two thread pools (we have one: 13 §2.5 vs P0 §5.3 D1);
  snmalloc as the tools' malloc (13 §2.6 vs P0 §5.11 C1); "4 pass
  definitions" (there are 29: 13 §3.1 vs P0 §2); the verifier off in
  release (ours always verifies: 13 §3.1 vs P0 §5.4 F16).
- **Hardening:** extensive in every configuration, release and the
  inlined runtime included (13 DP-56). P0 §5.5 D8 assumed debug and test
  only.
- **"The framework failed on containers":** confirmed in kind, open in
  amount. No record separates the container cost from per-point state
  (21 §3.1; 20 §3.1).

**3.10 With AGENTS.md.**
- **Four targets.** A change "is done when it builds and passes on all
  four", but no Linux target has built anything (proposals README). The
  gate has to name its targets.
- **Two hosts for test machinery.** The runner depends on `contrib` and
  `test`, so it builds under the stock host only (19 H1).
- **Per-target cases outside the entry.** The runtime bitcode's home is
  branched on in four places (13 DP-35), and the runtime has `__APPLE__`
  branches (18 §7).
- **Never miscompile silently.** No stack probes exist, so a frame
  larger than the guard skips it (18 §8; P0 §5.11 B2; 20 §4.3).

## 4. Problems found, consolidated

1. **Main is red.** `make test` at 101edbc5 is 403/480 against 470/480
   at e96bb991 (*measured* by the agent, 51a4771b; 21 P-1, P-16).
   `tests/chars` asserts in `placeOwned`. *Read:* a block has no
   coordinate in `Positions`, so the case blocks' spans overlap.
   101edbc5 also changed, unrecorded, which ops count as deciding
   (`scf.if` dropped out; 21 P-3). e96bb991 has ten standing failures
   too, and nothing has been green since 10-14 (20 §2.3).
2. **No stage-1 baseline.** There is no S3 record in `bench/records/`
   and no frontier recorded after 101edbc5; no pass after
   idr-rc-exclusive has ever run on stage 1 (21 P-17, §3.4, §5.2). The
   numbers mix measures (21 P-18): a jetsam footprint (627 GB), an RSS at
   a kill (43 GB), a manual stop (52 GB), live samples (41–47 GB), and a
   debug-build fixture (1.3 s).
3. **The parallel agent collides with P0.** It changed counting,
   exclusivity, the stack inference, canonicalization,
   defunctionalization's patterns and the traits (21 §3.6). Two commits
   came after the audit base, leaving lanes 02, 07 and 08 partly stale
   (21 §3.5). Three reversals carry no ruling (21 §6.1 hist-Q5), and four
   trait waves are announced (21 §2.4).
4. **Worker threads have small stacks.** The main thread runs on a 2^36
   reserved stack; pool workers get LLVM's default, 8 MiB on Darwin, so
   PIN(mlir-recursion) holds only on the main thread (*read*, 13 DP-39).
   Recursion depth depends on thread and OS, unmeasured on stage 1 (13
   M7). `PINS.md:595` says 2^40 where the code reserves 2^36.
5. **Assertions in release measurements.** Stage 2, which every
   idris-mlir links, has `LLVM_ENABLE_ASSERTIONS=ON` and forced
   statistics (*read*, 13 DP-57). Release also verifies after every pass
   and runs extensive hardening (13 §6 Q4).
6. **Tests name what P0 renames** (*measured*, 19 T1–T3, S5–S17): 41
   `mlir.expect` files name steps by pass; 644 RUN lines name 24
   `--idr-*` passes and 86 spell pipeline nests; dumps are named by op
   (`idr_program_*`); action tags, a remarks filter and reject
   directories carry names; 339 fixtures hold 26,025 `idr.` names and
   1,024 lines of reference IR. It has happened before: 28274bd3 "named
   the step idr-rc, which no pass is any more".
7. **Verification's cost is unknown and multiplied** (*read*, 13 §2.3,
   DP-03–07): up to 26 runs of three serial whole-program walks, and
   no-op symbol-dce and canonicalize runs re-verify. `--idr-contracts`
   clones the module before every program pass, so a measurement under
   it measures the clones too (19 E25, §8).
8. **No footprint record; a killed run leaves nothing.** No `task_info`
   anywhere (13 §2.6). The time trace is written at exit (13 DP-52).
   `peak_memory` is `ru_maxrss`, which misses compressed pages (13
   DP-63; 19 §3.2).
9. **The pipeline order is held twice, and the copies disagree.**
   `Passes.td` swaps two pairs against `Pipeline.cpp`, and the harness
   re-parses the order with awk (13 DP-01). The dead
   `remove-dead-values` is registered and the canonicalizer is not (13
   DP-16).
10. **Stale records.** Patches 06, 28 and 63 reach nothing but are
    carried. PINS.md names a dropped pass. The upstream table lacks 62
    and 63. None of about 25 LLVM patches is filed (20 H2–H4).
11. **Parallel paths barely tested.** Every test compiles on one thread;
    only fuzz seeds and four determinism tests use others. No solver is
    compared across thread counts (19 S16, M2, §6).
12. **The runner builds under one host** (19 H1), which AGENTS.md
    forbids.
13. **Checkout leftovers.** `tests/spec` (untracked) and `tests/build`
    make the runner's `discover` refuse to start (19 §8, T20; `git
    status`).
14. **Stack overflow is untestable.** The stack is one 64 GiB
    reservation with no setting; the 1 MiB guard claim is untested; no
    probes exist; every crash shares status 1 (19 §6 oom-6, §8; 18 §8).
15. **0003 is unscheduled.** 21 of its 24 probed rederivations stand (20
    §4.3).
16. **Hand-built serial solvers.** Three graph types share no code, are
    pointer-keyed, and none is an action; two are whole-program and
    serial (21 P-14; 20 H17).
17. **Defunctionalization's per-function freeze.** `RetypePattern` is
    rooted at every registered op except a hand list, and frozen per
    function (21 P-6; 06 risk 1). At suite scale that costs 4.7 %, 4.3 %
    and 1.9 % of self time (51a4771b).
18. **The profile build was swapped in by symlink**, `build/dev` to
    `build/profile`, for each corpus run. Anything built meanwhile in the
    shared checkout used the wrong tree (21 §8).
19. **No compile-time baseline.** There is no PCH and no `-ftime-trace`;
    the one record is a stale ninja log, 7.26 s mean per unit (13 §2.7,
    DP-59). Under the template ruling, P0 needs this baseline.

## 5. The decisions this cluster hinges on

The §8 IDs, grouped into decision points. Q1, Q-M3 and Q-llvm-1 are
settled by the ruling.

**E1. The parallel agent and the starting tree** (Q2, perf-Q1, perf-Q2,
hist-Q5).
- *The agent:* (a) stops changing code and only measures; (b) changes
  only what unblocks a measurement, each change with a record, its trait
  waves folded into P0's ods lanes (21 §5.5); or (c) continues freely,
  and P0 re-checks staleness on every push.
- *The tree:* e96bb991 (470/480), or origin/main with 101edbc5 fixed
  forward, or reverted.
- *`Positions`:* repaired toward lane 07's D5 scope, reverted, or kept
  as an interim that lane 08's T3 deletes.
- *Evidence:* eight walls met in eighteen hours (21 §5.1); main red
  (§4.1); its waves overlap lanes 01–03 (21 §5.3).
- *What depends on it:* which tree the audits describe, every gate's
  baseline, and the counting and trait designs.

**E2. The gate each step passes** (hist-Q1, hist-Q2, T-Q1; the WIP rule,
3.5; the four targets, 3.10).
- *Options:* (a) build, five suites, the invariant set unchanged, a
  stage-1 run, the step's measurement, no WIP (20 L2); (b) suites every
  step, stage 1 at milestones; (c) type-checked landings, as in 10-14 to
  10-18, which the history argues against (20 §8).
- *Sub-questions:* is "green" 470/480 with ten named failures, or
  480/480? Does a stage-1 regression fail the step, or only get recorded
  (3.6)? Is it arm64 macOS only until Linux builds?
- *Evidence:* the gate's time is unmeasured (19 §8). One full suite runs
  at a time across lanes (lanes README). Stage 1's frontend half alone
  takes 450–528 s (0001).
- *What depends on it:* step size, and so the whole shape in §6.

**E3. Who measures, on what build, recorded how** (Q4, perf-Q3, oom-3,
drv-Q1, drv-Q6, oom-2).
- *Runner:* the owner's machine (no LLVM is built in this checkout, and
  local LLVM builds were ruled out on 10-09: 20 §6 QA1; 13 §6 Q4); the
  parallel agent, today the only one running stage 1 (21 §6.1 Q4); or a
  coordinator step.
- *Build:* release with assertions, stated every time, or a second
  stage-2 build without them (13 drv-Q1).
- *Measure:* `phys_footprint` (what jetsam kills on), not RSS (P0 §5.11
  K5).
- *Instrument:* a buffered time trace flushed on pressure; the streamed
  action profile (about 1 GB a minute); or 51a4771b's no-LTO sampler
  (21 §6.1 drv-Q6).
- *Record:* every run, replacing 0001's "when both halves exit 0"
  (perf-Q3). oom-2: a named crash, never a refusal, with one line on
  pressure.
- *What depends on it:* every "measured" in P0, hist-Q1's gate, and E4.

**E4. Verification after every pass** (ods-Q6, Q-M2, Q-O5, types-Q1,
T-Q4, T-Q5).
- *Options:* (a) keep it whole, its cost a measured budget; (b) keep it
  whole and cheapen it by nesting (13 T1), U-a and U-b, and moved checks
  (13 T3); (c) Modular's split.
- *Contracts:* per-function records instead of a module clone per pass
  (19 C7).
- *Evidence:* it caught 4c87dcc5 and 9db9813d's 1,088 errors on stage 1
  (13 §6; 21 §6.1). It turned 73bba53f's quadratic into 843 s (20 §3.1).
  It is 1.6–1.7 % on the suites.
- *What depends on it:* nesting (E5), lanes 01 and 03's verifier
  content, and `tests/verifier-every-pass`.

**E5. The pipeline's representation** (drv-Q2, drv-Q3, canon-Q5,
ops-Q4; Q-llvm-5 as a dependency).
- *Options:* one TableGen list of steps, with the stage chain asserted at
  build time and nesting from anchors (13 T2); decide/apply/restructure
  as a rule (13 T1); or today's C++.
- *Evidence:* the order is held twice and the copies disagree (§4.9).
  About a dozen passes already nest by hand: 13 parallel loops and three
  `runPipeline` nests (13 §3.2). 4c87dcc5 is the one collision between
  nesting and verification (13 §6).
- *What depends on it:* lane 19's C2, lane 14's generator, and every
  lane's pass split.

**E6. The tests through the cutover** (T-Q1, T-Q2, T-Q3, DD-Q8 for rule
names, ids-Q6).
- Is the invariant set named and frozen (19 C3)?
- Are the 339 fixtures rewritten by hand, by a script that is not kept,
  or replaced by program tests (T-Q2)?
- Are idr-expect's 82 names frozen as the test API (T-Q3)?
- Are rule names a stable API? Reject directories carry them (19 S17).
- Kept either way: a REF stays a meaning stated by hand, never output
  copied back (19 §8). The 260 prose `expected-error`s are deleted, not
  restated (19 T4).

**E7. What P0 absorbs** (hist-Q4 for 0003; ft-Q2 for 0011 O2/O3; arr-Q1
and arr-Q5 for 0009; Q3, the mirror; QL5; 0004's C2 and C4).
- P0's goal "no rederivation chains" is unmet unless 0003's 21 items are
  taken or named (20 §4.3).
- Under the ruling, the mirror moves with the `.td` it mirrors.

**E8. Upstream during P0** (hist-Q1 as a rule; hist-Q3, retire 06, 28,
63; QA1 and QA3, their process side; Q-E5; U-a, U-b, U-d, U-e).
- Only the coordinator builds LLVM patches (lanes README), so patches
  batch into toolchain rebuilds at stage boundaries.
- Each patch P0 needs gets a sending step (20 H4).
- 62 and 63 sat "tested on a private build ... not yet built into the
  toolchain" (20 §6).

**E9. The build under heavy templates** (cxx-Q3, cxx-Q4, drv-Q4,
drv-Q5; Q-llvm-1 settled).
- *PCH:* now, with `-fno-pch-timestamp` and ccache sloppiness (13
  DP-55), or after a `-ftime-trace` baseline (13 M5).
- *Hardening:* the release mode chosen after measuring (13 DP-56, M6).
- *Workers:* our own pool on reserved stacks, or upstream's
  `StdThreadPool` given a stack size (U-d; 13 DP-39).
- *Bitcode:* one home on every target (13 DP-35).
- *What depends on it:* every gate's time (E2), and which passes may run
  on workers.

**E10. Runtime correctness the gate would expose** (oom-4, oom-6,
rt-Q3). A missing probe is silent corruption (18 §8), and a 64 GiB stack
makes an overflow test impractical (19 §8). Both need a design before
any test.

## 6. A proposed shape for executing P0

These are options for the owner, built from the lanes' orders (13 §5, 19
§5, 20 §5.2, 21 §5). Every stage culls what it replaces (the ruling).

Clusters, as I read them: A ≈ lanes 01–04; B ≈ 05–07 and 09; C ≈ 08,
10–12 and 18; D ≈ 14–17.

**S0. Settle and fix the tree** (no code). Answer E1–E3, the 8.1 effects
group and DS1–DS3 (20 L3); pick the starting commit; correct PINS.md,
the upstream table and P0 §3 (20 §3.1; 21 §5.2). *Gate:* dated §9
rulings; main at a named standing count. *Needs:* A drafts DS1–DS3 and
the resource tree.

**S1. Instruments** (additive, no behaviour change).
- The footprint `PassInstrumentation` and the verifier span (13 T4, T5);
  the census pass (13 M3); a flush on pressure with a line naming the
  death (P0 §5.11 A3); solves as actions (21 §5.1).
- Scale fixtures (a 20,000-case match, 65,536 labels: 20 L1), and the
  `-ftime-trace` baseline (13 DP-59).
- Then one full stage-1 record.
- *Gate:* output byte-identical, suites unchanged, the record written.
- *Needs:* C, lane 18's footprint function; B, actions in exclusivity
  and the stack inference.

**S2. Tests that survive the cutover.**
- The pipeline as a generated list, with stage-named dumps and
  `--idr-pipeline=from:/to:` (13 T2; 19 C2); the ending as one record
  (19 C4); idr-expect generated from records (19 C1); U-a and U-b.
- *Gate:* the generated pipeline equals today's `--dump-pass-pipeline`
  (13 §5 order 3), and the invariant set is unchanged.
- *Needs:* D, lane 14's generator (Q-llvm-5); C, lane 18's ending; A,
  per-op stage legality if ops-Q4.

**S3. Upstream trials, each measured.** U1 on Ranges, Borrows and
Returned; `remove-dead-values` per function, or 06, 28 and 63 retired
(QA3, hist-Q3); optionally exclusivity on the patched framework, to
learn whether ffa91113 was forced (20 §8; 21 §8 item 6). *Gate:* a record
per adoption or removal (hist-Q1). *Needs:* B mostly; C for the
toolchain rebuild.

**S4. The solver layer's spine.**
- One program graph, numbering and marking, with the three markings
  ported (20 L4; 21 §5.4); `Positions` resolved one way; per-solver
  determinism boxes (19 C5).
- Concept-constrained templates, instantiated once per unit (the ruling;
  P0 §5.5 D3).
- *Gate:* E2's gate, plus each solver's footprint no worse than its S1
  record.
- *Needs:* B the solvers; C counting's readers; A the match ops'
  per-op interface answers (P0 §5.1 C4).

**S5. The dialect redesign, with its mirror.** One cutover per op
family, or one for all (owner's option). The Idris mirror and the
fixtures move in the same commit (Q3, T-Q2). *Gate:* the invariant set
unchanged, REFs not regenerated, the module byte-identical where the
representation is unchanged (14 §8). *Needs:* A the surface; D the
generator and Emit (14, 15); C the lowering patterns; B readers of
renamed facts.

**S6. Pass redesigns, as decide/apply/restructure,** in lane 13's order:
08, 11, 10, 09, 06 (13 §5 order 4). Each has a before-and-after on the
corpus wherever acceptance or counts can move (07 §8; 08 §8), done as
3.4 decides. *Gate:* E2's gate plus statistics and live cells per test.
*Needs:* C (counting, tail, lowering, arrays); B (exclusivity, borrows,
optimize).

**S7. Verification re-priced, the build, a hard cleanup:** 13 T3 with
lanes 01 and 03, PCH and hardening (E9), then a full cleanup. *Gate:*
the stage-1 pipeline finishes; then 0001 S4.

**Three alternatives.**
- **(i) Infrastructure first:** the order above. Lanes 13, 19, 20 and 21
  converge on it.
- **(ii) Representation first:** S5 straight after S1. This is the
  literal "one total cutover" (P0 goal), and it risks the 10-14 to 10-18
  failure (20 §8).
- **(iii) Wall-driven:** S3 continues, and each wall becomes a P0 step.
  This is the parallel agent's mode, and it fits D4 only if E1 allows it.

## 7. Risks, and the measurements that must exist

**Risks.**
- **Landing before running:** P0 is larger than the four unbuilt waves
  together (20 §8). **Re-adopting upstream unmeasured:** the adopt, run
  out, drop cycle can repeat for each analysis §5.1 sends back (20 §8).
- **The cutover rewrites its own oracle** (19 §8). **Acceptance moves:**
  exclusivity, the uniqueness promise and inlining change what passes or
  how fast it compiles (07 §8; 08 NQ1; 09 R1).
- **The next walls are unmeasured:** Ranges and idr-narrow, Returned,
  the defunctionalization freeze, the serial program verifier (05 §8; 10
  R-1; 11 R1; 06 risk 1; 13 §2.3).
- **The instruments' own memory:** the time trace at granularity 0 (13
  DP-52), the action profile at 1 GB a minute, the contracts' clones (19
  §8). **Worker stacks:** a deep recursion on a worker dies with a bare
  SIGSEGV (13 §8).
- **Template compile time** grows under the ruling; a PCH hides missing
  includes and fixes the hardening mode per target (P0 §5.5 D6; 13 §8).
- **Two hosts:** every Idris-side change builds under both, and each TTC
  bump rebuilds prelude, base and `libs/` (14–17 §8).
- **The gate's own cost:** one suite at a time, and no recorded time for
  stage 1's pipeline half (lanes README; 21 §5.2). **Staleness** at every
  push of the parallel agent (21 §8).

**Measurements needed before or during P0** (on stage 1 at a recorded
commit unless marked):
1. The frontier, with time and peak `phys_footprint` per pass, as one
   record (21 §8 item 1; 13 M1, M4).
2. The verifier's share per pass, from timing rows and action spans (13
   M1; 19 T-Q5). M2 only if E4 allows it.
3. V/B/P/F per solve, the largest matches, SCC sizes (13 M3; 05 §8; 15
   M-1).
4. Ranges, Returned and Borrows alone, with footprint (05 §8; 10 R-1; 21
   §8 item 5).
5. IdrRcGrades once 101edbc5 is fixed, and idr-rc-exclusive on the module
   itself (21 §8 item 2).
6. The defunctionalization freeze per function (06 risk 1).
7. Worker stacks: the PIN reproducer, threaded and unthreaded (13 M7).
8. Build time per unit and per template, with and without a PCH (13 M5).
   Required by the template ruling.
9. Hardening's cost in release, on the bench (13 M6).
10. The suites' wall time per kind, and the contracts' share (19 §8).
11. Counting statistics as S6's baseline: `numDups`, `numDrops`,
    `numTakes`, `numReuses`, `numExclusive` (08 §8).
12. The largest frame against the 1 MiB guard (18 §8).

## 8. What is stale or left unverified by wave 2

- **No lane built or ran the compiler.** Every cost in lanes 01–20 is
  read or conjecture (13 §8; 19 §8; 03 §8); the only runs are the
  parallel agent's.
- **Every lane read e96bb991.** 101edbc5 and 51a4771b make some of it
  stale (21 §3.5): lane 02's "no `Decides`", lane 07's `Uses.cpp` rows
  and D5 premise, lane 08's query costs and T3 target, and lane 20's
  "470/480 now".
- **Not fetched.** Anything pushed after 51a4771b is unknown here.
- **P0 §5.1 H1–H2 is arithmetic** (52 GB as about 10 million values, 627
  GB as about 200 million states), resting on no count (21 §3.1). **52 GB
  is a manual stop** (20 §3.1); **1.3 s is a debug fixture** (21 §2.3);
  **51a4771b measures the suites**, whose rankings "invert at scale".
- **Lane 19's counts** describe this checkout, leftovers included (19
  §8). **Lane 13's build timings** come from a stale log, its ccache-PCH
  flags recalled (13 §2.7). **Lane 12's ABI table** dates from 10-18.
- **Conversation-only owner decisions** are invisible to the history (20
  §8). **P0 §2's trait reading** describes work since built on
  origin/main (21 §1). **P0 §9 lacks the template ruling** received
  here; it belongs there, dated.
