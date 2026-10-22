<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 synthesis F: the owner's decisions, as an agenda

This document turns the 158 questions of the proposal's §8 into decision
points, to be stepped through by the owner and the coordinator. It
decides nothing.

## 1. How to use this agenda

- The 158 questions become **84 decision points** (DP). Questions that
  are one decision asked from several sides share a DP. Every original
  ID is listed under exactly one DP; section 6 checks this.
- The owner's delegation of 2026-10-21 splits them in two.
  - **Owner** (DP-01 to DP-21): the language's meaning, promises to
    users, scope between proposals, other agents' work, and contested
    core shapes. Two of them (DP-04, DP-08) are already settled by the
    owner's rulings of 2026-10-21.
  - **Coordinator** (DP-22 to DP-84): what AGENTS.md, strong lane
    agreement or elegance settles, under "always a hard cutover, hard
    culling of the old code, maximally churning toward the most elegant
    representation". Section 4 gives the reason for each.
- The owner's DPs are numbered in the suggested order (section 3).
  DP-01 to DP-03 come first: they fix the effect tree's shape, which
  the centralized effect system (DP-04, ruled "extremely high
  priority") waits on. DP-05 to DP-07 are urgent (section 5) and should
  be taken in the same sitting. DP-08 needs only an approval of the
  skill's wording.
- Each DP gives: the decision in one sentence; the options, each with
  what it buys, what it costs and the evidence for it; what AGENTS.md
  says; what must be decided before it ("Before") and what waits on it
  ("Unblocks").
- Citations. "07 §6" means `audits/p0/07-ownership-analysis.md`,
  section 6 (and so for lanes 01 to 21). "21 P-1" is an issue ID in a
  lane's table. "§5.8 DS2" is a section of the proposal. "§9 D4" is one
  of the owner's recorded rulings.
- An answered DP becomes a dated entry in §9, and its IDs leave §8.

## 2. The decision points

### 2.1 The owner's (in the suggested order)

#### DP-01. A dead crash, a dead divergence, and `exit` [owner]

*Questions:* ods-Q1, DD-Q2, eff-Q2.

*Decision:* May the compiler delete an unused op that may crash or may
not end (upstream's model: only speculation is blocked), or are crash
and divergence effects kept in program order; and is `exit` a crash, a
divergence, or an effect of its own?

*Options:*
- **A. Both kept, as effects** (today). Buys: a program that would crash
  or hang still does; the test properties that assume it stay
  (computes-nothing, crash-sites, the contract crash-sites-not-added).
  Costs: two identical guards cannot be merged by CSE (a fold does it by
  hand, 04 §6); a `may_loop` op on every loop of a non-total function
  (10 §6).
- **B. Both deletable when dead** (upstream's model: no memory effect,
  not speculatable). Buys: upstream CSE and DCE do the work; the 11
  total ops a guard protects already use this model, and a guard is dead
  only when its op is (02 §6). Costs: a program Idris did not prove total
  may finish where it would have crashed or hung; test properties to
  restate.
- **C. Crash kept, divergence deletable only where Idris proved
  termination.** Total functions marked `mustprogress` at lowering (12
  §6), so LLVM may delete an effect-free endless loop only where Idris
  proved there is none. Buys: no behaviour change for unproved code.
  Costs: two models side by side.
- *`exit` (eff-Q2):* today the function summary says a function that
  always exits returns (02 §3.7); `exit` writes pending output and ends
  the process, the same order as a crash, though it is no `MayCrash` op
  (02 §6). Options: a crash, a divergence, or its own effect.

*Evidence:* 02 §6; 04 §6; 06 §6 (`diverge` is "not `total`"); 10 §6; 12
§6 (lowered, neither is deletable today); 16 §6 (termination is per
function and about its own loops); 18 §6 (the crash flushes output
first).

*AGENTS.md:* constrains: a trusted library's IO "effects happen where
the value is demanded, in program order with every other effect";
whether a crash is such an effect is the question. "Never miscompile
silently" applies once the meaning is fixed.

*Before:* none. *Unblocks:* DP-03, DP-04, DP-18, DP-50, DP-67.

#### DP-02. The world [owner]

*Questions:* DD-Q3.

*Decision:* After the frontend, is IO ordered by declared effects alone
(no world value), or does a world value stay, with its effects derived
from it? Under DP-04's ruling the IO effects live in the one effect
source either way; the question is whether a world value is kept too.

*Options:*
- **A. Effects only** (§5.8 DS2.1): IO ops declare effects on a resource
  tree; functions and calls carry effect sets; `unsafePerformIO` becomes
  a region op. Buys: deletes the world type, `world.new` and the world
  operands; the IO ops already conflict through `IOResource`, and a call
  already carries its callee's effects, verified (02 §6). (`PerformsIO`,
  which restates the world exactly, 80 = 80 ops, goes under DP-04 in
  either option.) Costs: MoveOut reads the world's
  def-use chain as the path to the next IO op; ten world-threaded memory
  ops are ordered by it; specialization keys, identities and consumers
  read it as a value (02 §6); the frontend threads it from TT (391 lines
  in 21 files) and the generated IO primitives are shaped by it (02, 14,
  15 §6); rank-0 `tabulate_io` has no dimension to carry the order (11
  §6).
- **B. The world kept, effects derived from it by one rule** (§5.8
  DS2.2). Buys: order visible in SSA; Idris's own representation; the
  frontend unchanged. Costs: the world threaded through every loop and
  region; under DP-04 its rule is one more row of the effect source.
- **C. The builtin `token`:** ruled out by every lane that looked (it
  cannot cross calls, branches or region results: 02 §6; §5.8 B11).

*Evidence:* 02 §6; 03 §6 (the world is the only difference between
`tabulate` and `tabulate_io`, and between `array.update` and
`element.update`); 06 §6; 11 §6; 12 §6 (seven special cases because the
world lowers to nothing); 14 §6; 15 §6; 20 §6 (the world and
`IOResource` coexisted from the first commit; no decision recorded); 21
§5.3 (the agent's wave 3 is one answer).

*AGENTS.md:* constrains A: a trusted library's IO must still happen
where the value is demanded, in program order.

*Before:* none. *Unblocks:* DP-03, DP-04, DP-38, DP-42, DP-50.

#### DP-03. The resource tree: what is ordered with what [owner]

*Questions:* ods-Q3, eff-Q1, eff-Q4.

*Decision:* Which states the resource tree names, and which are ordered
with which: a crash with IO and with heap writes; what a function's
`effects` summarize; and runtime-state reads.

*The parts, and their options:*
- *A crash and the heap (ods-Q3).* (a) Ordered with both IO and heap
  writes: a crash resource above both. (b) Ordered with IO only: the
  heap a sibling. Evidence: 02 §6 (the runtime's crash flushes output and
  exits; nothing reads program memory after it; today's heap order is an
  accident of every heap effect sitting on the root resource); 18 §6.
- *A function's summary (eff-Q1).* (a) Only {io, crash, diverge}, as
  today. (b) Every state a caller must order with, including memory its
  arguments reach and memo state. Evidence: 02 §3.7 (the summary can
  lose an op's effect: memory crosses a call by the root's accident,
  memo state not at all); lane 02's tree (T1) cannot land without the
  answer.
- *Runtime state (eff-Q4).* (a) `handle.string`'s read of the handle
  table and `io.strerror`'s read are IO, ordered with output (today).
  (b) A state ordered only with what changes it (`io.handle_free`, a
  failing call). Evidence: 02 §6 (`io.strerror` is deliberately not
  observable).

*AGENTS.md:* the trusted-IO line above; silent on the heap.

*Before:* DP-01, DP-02. *Unblocks:* DP-04, DP-31, DP-38, DP-50.

#### DP-04. The effect system's structure [owner: settled]

*Questions:* ods-Q2, ods-Q5.

*Decision:* Settled by the owner's ruling of 2026-10-21 ("extremely
high priority"): one centralized effect system, "defined and
monomorphized in a single place", so that no two readers ever disagree
about effects again. One TableGen source holds every effect fact (the
resource tree, each op's effects, the rules by which effects follow from
operand types, consumption, the function-summary bits, the mapping to
LLVM); every consumer is generated or monomorphized from it; one
concept-constrained query API answers every question; a verifier rule
checks that a function's summary equals the derivation from its ops;
every other reading is deleted. A design agent writes it in
`audits/p0/design/effects.md`. Nothing structural is left open; the
tree's shape waits on DP-01 to DP-03.

*What the ruling answers:*
- ods-Q2 (one trait computing effects from operand types, or ops split
  until every effect is static): the rules by which effects follow from
  types are declared in the one source, so a type-dependent effect no
  longer forces either a hand trait or a split. Evidence the design
  keeps: each distinction is already a type (`BoxType` against
  `DataType`, `isMemo`, the grade); a split by stage would double 11 ops;
  0004 judged `consumes`'s two modes essential (02 §6).
- ods-Q5 (effect stages and full-region effects that no pass reads):
  they are effect facts, so they are declared in the one source like
  every other, and what reads them is generated from it (today nothing
  does: 02 §6).
- Not §8 questions, but settled with them: lane 02's one classifier
  (02 §5 T5), the traits that restate effects (`PerformsIO`,
  `ObservableIO`, `MayCrash` beside the crash resource), the four
  disagreeing representations of "does IO" (02 §2; 21 §5.3), the summary
  that can lose an op's effect (02 §3.7), and the agent's trait wave 3
  (21 §5.3).

*AGENTS.md:* "One thing, one representation ... Generate the second
copy from the first, or delete it."

*Before:* DP-01, DP-02, DP-03 (the tree's shape). *Unblocks:* DP-31 (a
row of the source), DP-38 (the summary bits on the call), DP-50 (where
the summary is computed); lane 02's T1 to T8.

#### DP-05. The fence around P0's code [owner]

*Questions:* perf-Q1, Q2, hist-Q5.

*Decision:* Does §9 D4 ("no code until the whole plan is approved") bind
the agent working 0001's S3, and may any agent reverse a recorded
design without a dated ruling from the owner?

*Options:*
- **A. D4 binds everyone.** S3 stops changing code; stage-1 runs go on
  only as measurement, on a fixed binary.
  Buys: the tree the lanes audited stops moving; no design lands ahead
  of its lane.
  Costs: no new walls found by running stage 1 (every wall in §3 was
  found that way, none by a fixture: 20 §6 Q2); a fix for main (DP-06)
  needs an explicit exception.
  Evidence: 21 §6.1 Q2 (nine commits in eighteen hours, seven of them in
  code wave 2 audits; main red since 101edbc5).
- **B. S3 goes on inside a fence.** Only fixes that unblock a stage-1
  measurement, each with a record (DP-07); the agent's four trait waves
  become P0's ods lanes' work instead of landing first (its wave 3 is
  now the effect system's: DP-04).
  Buys: walls keep being found; the lanes' designs stay the plan.
  Costs: a judgement per commit; the plan must rebase on each push
  (21 §5.5).
  Evidence: 21 §5.3, §5.5, §6.2. A test case for the fence: lane 07's
  D1, a precision fix in the analysis the uniqueness refusal rests on,
  marked "fix first, alone" (07 §5 D1).
- **C. S3 goes on as today.**
  Buys: speed.
  Costs: main red (DP-06); three solver graphs written in twelve hours
  with no shared code (21 P-14; 20 §5.1 L4); reversals with no ruling
  (ffa91113, 16005000, and 101edbc5's change to what `decides` admits:
  21 §6.1).
- *hist-Q5, under any option:* a reversal of a recorded design (an
  engine, a type's representation) needs a dated ruling in §9, or it
  does not. Evidence: 20 §5.1 L8 (rules written on the day of a reversal
  held; agent reversals without one recurred within days).

*AGENTS.md:* silent on the parallel agent. §9 D1 (P0 first) and D4
apply, but D4 does not say whom it binds (21 §6.1). The owner's standing
instruction to be looped in on architectural decisions, which 20 L8
cites, bears on hist-Q5.

*Before:* none. *Unblocks:* DP-06, DP-07, DP-22; every lane design the
agent's code touches (counting, exclusivity, the stack inference, the
trait layer).

#### DP-06. Main is red: `Positions` [owner]

*Questions:* perf-Q2.

*Decision:* What happens to `Positions` (101edbc5), which left `make
test` at 403/480 against 470/480 at e96bb991?

*Options:*
- **A. Repair it forward** into the per-function scope P0 builds on: a
  coordinate per block (a sentinel), one numbering shared with the owned
  verifier as an analysis, kept valid by a rewriter listener.
  Buys: the shared numbering gets its first two clients now (21 P-1,
  P-2; 07 §5 D5).
  Costs: code now; it settles DP-53's numbering ahead of the plan.
- **B. Revert to e96bb991's queries until P0.**
  Buys: main back at its standing 470/480; e96bb991 is today's green
  start (21 §5.5); no design pre-empted.
  Costs: stage-1 runs lose 101edbc5's gain in idr-rc-grades (half of
  that pass's samples were in `findAncestorOpInBlock`: 21 §5.2).
- **C. Keep it as an interim** that counting's one reverse walk (08 §5
  T3) later deletes.
  Buys: no churn now.
  Costs: main stays red; every stage-1 run starts from counting that is
  wrong on 67 programs (21 §5.2); DP-22's gates have no green start.

*AGENTS.md:* constrains: "never miscompile silently", and 21 P-1 calls
this "a miscompile path, now measured". A and B are commits, so DP-05
must allow them.

*Before:* DP-05. *Unblocks:* DP-07 (the commit a baseline is taken at),
DP-22 (the green start), DP-53 (option A pre-empts it).

#### DP-07. The stage-1 record [owner]

*Questions:* Q4, perf-Q3, drv-Q1, oom-3, drv-Q6.

*Decision:* Who runs the release `idris-mlir` on the stage-1 module for
P0, on which build and with which instruments, and what must every run
leave behind?

*The parts, and their options:*
- *Who (Q4).* (a) The parallel agent, today the only one (21 §6.1).
  (b) A measurement lane of P0's on the build machine. This checkout has
  only a typecheck build (13 §6 Q4); local LLVM builds were ruled out on
  2026-10-09 (20 §6 QA1).
- *What a run leaves (perf-Q3).* (a) A record under `bench/records/` for
  every run, wall or not: how far it got, time per pass, footprint per
  pass and its measure, and the size counts (values, blocks, points,
  functions: §5.1 W1). This replaces 0001's "a record when both halves
  exit 0". (b) 0001's rule as it is. Evidence: 21 P-17, P-18, §5.1 (no
  S3 record exists; the numbers mix a jetsam footprint, an RSS at a kill,
  a manual stop and samples).
- *Footprint per pass (oom-3).* (a) Yes, in a `PassInstrumentation`,
  kept apart from the statistics that the determinism checks compare;
  the measure is `phys_footprint` on macOS (what jetsam kills on) and,
  on Linux, the cgroup's figure or resident plus swap. (b) No per-pass
  record. Evidence: 13 §6 oom-3 (none exists; `ru_maxrss` under-reads);
  §5.11 A2.
- *Assertions (drv-Q1).* (a) Measure on an LLVM without assertions (a
  second stage-2 build, or assertions off for the one toolchain, which
  the dev build then loses). (b) State every number as including them.
  Evidence: 13 §6 NQ1; 21 §6.1 (e96bb991's one timing was a debug
  build).
- *Profiler (drv-Q6).* (a) One buffered time trace, flushed on memory
  pressure (13 §5 T4, T5). (b) MLIR's streamed action profile (a lock
  and a flush per event; about 1 GB a minute in idr-optimize). Evidence:
  21 §6.1 (the later walls were found with `sample`, a third
  instrument).

*AGENTS.md:* silent on stage 1. It constrains the footprint measure:
the measure differs by OS, so it belongs in one platform place, not in
branches per target. Once "who" and "every run" are settled, the
measure, the assertions and the profiler are technical choices the
coordinator can make.

*Before:* DP-05, DP-06. *Unblocks:* DP-24, DP-51, DP-59, DP-60, DP-64,
DP-77; every "measured at stage 1" in §7.

#### DP-08. The line between MLIR interfaces and C++ concepts [owner: settled]

*Questions:* Q1, cxx-Q1, Q-M3, Q-llvm-1.

*Decision:* Settled by the owner's ruling of 2026-10-21 ("heavy use of
templates and concepts pls"): our own C++ is concept-constrained
templates by default; MLIR op interfaces stay where the op set is open;
a concept may read ODS facts (a trait, interface membership) but never
list ops. What remains is the owner's approval of the skill's new
wording: "never a ladder, and never a concept that lists ops".

*What the ruling answers:*
- Q1 and cxx-Q1: the line is cxx-Q1's (§5.5 D1).
- Q-M3: a concept-constrained problem type (§5.4 design 1's
  `SummaryProblem`), not Modular's concept-free CRTP (§5.4 F13).
- Q-llvm-1: monomorphized templates (§5.3 S1's one explicit
  instantiation of `solve` per analysis, each in its own translation
  unit), with compile time measured as part of P0, rather than clang's
  CRTP adapter over a core compiled once (§5.3 C2, C5).

*Evidence:* 05 §6 Q-llvm-1 (no virtual dispatch of our own; five
`function_ref`s with one caller each); 11 §6 Q1 (templates over op
classes instantiated from per-op lists where an interface root would
do); 12 §6 cxx-Q1 (the lowering already practises the line); 20 §5.1
L6 (settle this before the C++ is churned).

*AGENTS.md:* silent; the skill's wording is the owner's.

*Before:* none. *Unblocks:* DP-26, DP-53, DP-73; every C++ lane.

#### DP-09. P0 and proposals 0003 and 0011 [owner]

*Questions:* hist-Q4, ft-Q2.

*Decision:* Does P0 absorb 0003 (each fact once: 21 standing items) and
0011's O2 and O3 (Core as tables; the translation as semi-naive over an
interned instance table), or leave them for after self-hosting?

*Options:*
- **A. Absorb 0003 whole; take only 0011's small form** (the frontend
  lane's D-1, D-3, D-5) and leave O2 and O3 to 0011.
  Buys: P0's goal "no rederivation chains" becomes reachable (20 §5.2
  item 4: otherwise unmet by construction).
  Costs: a larger cutover; 0003's fork-side items (C1, C2, B1) join it
  (17 §6).
- **B. Absorb 0003 and 0011's O2 and O3.**
  Buys: the frontend refactored once.
  Costs: the largest scope; O2 and O3 are marked for after
  self-hosting.
- **C. Leave 0003 for later,** deferring each item explicitly.
  Buys: a smaller P0.
  Costs: rederivations the lanes keep meeting stay (Returned solved
  twice, exclusivity solved twice: 08 §6, 10 §6, 21 P-13).

*Evidence:* 20 §6 hist-Q4, §4.3, §5.2; 15 §6 NQ-2.

*AGENTS.md:* "do not erase facts before the passes that use them"
(0003's TTC items serve it). §9 D1 puts P0 before everything, while
0003 is queued after self-hosting.

*Before:* none. *Unblocks:* DP-36, DP-40, DP-76; the scope of most
lanes.

#### DP-10. P0 and proposal 0009 [owner]

*Questions:* arr-Q1, arr-Q5.

*Decision:* Does P0 take 0009's stage-2 decision (buffers in data-type
bodies, with `!idr.lin<T>` tensor-like per instance and two upstream
patches) and 0009's MLIR form for the generating ops (destination-style,
`TilingInterface`, the ordered form through upstream), or leave each to
0009's stages?

*Options:*
- **A. Both in P0.** Buys: deletes the retype after bufferization and
  the reason for the release and link models (11 §5 C5); the generating
  ops in upstream's form now (11 §5 C3). Costs: reverses 0009 §8's
  reason for keeping the grade off `TensorLikeType`; needs patch 27
  (uncarried) and a per-instance `extraClassOf`.
- **B. The MLIR form in P0, the buffers left to 0009.** Buys: P0's
  direction without the grade change. Costs: the retype stays one more
  cutover.
- **C. Both left to 0009.** Buys: P0 smaller. Costs: two cutovers of the
  array stage.

*Evidence:* 11 §6 N1, N5.

*AGENTS.md:* the upstream-patch procedure applies to the two patches.

*Before:* none. *Unblocks:* DP-39 (a tensor-like grade decided per
instance), DP-44, DP-45.

#### DP-11. Running out of memory is outside the language [owner]

*Questions:* oom-1.

*Decision:* Is running out of memory a named crash of the machine, as a
stack overflow is, never a value or an effect in the types?

*Options:*
- **A. Yes** (§5.11's reading). Evidence: the code already treats it so:
  no entry point returns a failed allocation, the process ends (18 §6);
  a box's allocation carries no crash (02 §6); no frontend fact names
  memory (16 §6).
- **B. Allocation failure as an effect** on every allocating op. Costs:
  no allocation could be deleted or moved; contrary to all of today's
  code.

*AGENTS.md:* silent; it already names things "outside the language"
(threads, collector finalizers, raw pointers).

*Before:* none. *Unblocks:* DP-18, DP-19, DP-33, DP-84.

#### DP-12. Acceptance: the in-place promise and the uniqueness refusal [owner]

*Questions:* count-Q1, own-Q2.

*Decision:* Is `unsupported (uniqueness)` defined by a rule stated where
the promise is made, before counting, with counting bound to honour it,
or by whatever the exclusivity analysis answers?

*Options:*
- **A. A rule at the promise.** The promise is the `in_place` type plus
  the function's own rebuild of a quantity-1 parameter, before counting;
  stack and reuse must honour it; a test checks the rule's boundary.
  Buys: acceptance stops depending on optimizations. Lane 08 reads a
  chain (by reading, no program run) where skipping one reuse action,
  idr-rc-stack making the parameter a frame value, or `sinkConsumers`
  placing a dup changes the verdict (08 §6.1 NQ1). Costs: a rule the
  analysis must decide exactly; programs may move between accepted and
  refused.
- **B. The analysis's answer, taken before any optimization can change
  it** (exclusivity on the program as the frontend wrote it). Buys: a
  more precise analysis admits more programs. Costs: every precision
  fix (07 §5 D1) still changes which programs pass.
- **C. The analysis's answer wherever it runs** (today). Costs: the
  chain above.

*Evidence:* 07 §6 rc-Q2, NQ2 (a live crash case shares a match's
results, a precision loss on exactly this path); 08 §6 rc-Q2 (an
in-place sum has no run-time fallback), §6.1 NQ1.

*AGENTS.md:* constrains strongly: "Acceptance is a property of the
program, never of the optimizer", and the in-place refusal must rest
"on a total analysis". If lane 08's chain holds, C breaks the first.

*Before:* none. *Unblocks:* DP-13, DP-55, DP-58.

#### DP-13. The space guarantee, and the order of reuse and borrowing [owner]

*Questions:* rc-Q3, rc-Q1, count-Q2, own-Q1.

*Decision:* Which space property do compiled programs carry
(garbage-free, frame-limited, or none stated), and so, in which order
are reuse, borrow inference and drop placement decided, and how far are
borrows inferred?

*Options (each a consistent bundle):*
- **A. Lean's order, as today, no stated property.** Reuse first (a take
  wins over a borrow); borrows inferred over the whole program with
  Lean's forced reasons; the reuse decision written as IR at once
  (07 §5 D4(a)), which removes the simulation behind 9db9813d's bug.
  Buys: least churn. Costs: neither garbage-free nor frame-limited
  (07 §6 rc-Q3); a borrowed parameter can hold memory no constant
  bounds (§5.10 A5).
- **B. Koka's order, frame-limited.** Drops placed first, reuse guided
  by drops after (a borrow wins); borrows inferred only where the caller
  uses the argument later or it has constant size; "frame-limited"
  stated, with a test. Buys: the simulation goes; a stated bound.
  Costs: the forced-owned reason must come from elsewhere (08 §6.1
  NQ2); Share's taint relies on a borrowed parameter never being dup'd
  (07 §6); the test compares two placements of one program, which the
  action tags can produce (19 §6).
- **C. Perceus, garbage-free.** Drops at last use; borrowing only on
  runtime primitives; "garbage-free" stated. Buys: the strongest
  property, the simplest rules. Costs: more counting at calls; the test
  must hold at every point of a run, which an exit-time count cannot
  check (19 §6).

*Evidence:* 07 §6 rc-Q1, rc-Q3, NQ1; 08 §6 rc-Q1, rc-Q3, §6.1 NQ2; 19
§6 rc-Q3; 21 §6.1 (9db9813d's 1088 verifier errors came from reuse
decided before placement and simulated); §5.10 A5, A6, B2, G5.

*AGENTS.md:* silent on space. "Linearity is a performance property,
never a correctness one" frames it; DP-12 constrains it (acceptance must
not depend on this order).

*Before:* DP-12; decide beside DP-14. *Unblocks:* DP-16, DP-55, DP-56,
DP-57.

#### DP-14. The constant-stack promise [owner]

*Questions:* tail-Q2.

*Decision:* Is "a mutual tail recursion and an IO loop run in constant
stack" (and left-nested binds) part of a program's meaning, or a
performance property?

*Options:*
- **A. Meaning.** A tail call on a cycle left as a call becomes an
  internal error (a broken contract between idr-rc-stack and
  idr-tail-calls); a frames component left without a plan must be fixed
  by a representation. Buys: a long-running IO loop cannot overflow;
  the `constant-stack` property already appears in 36 RUN lines (19
  §6). Costs: today's silent fallbacks (a call that may reach its
  caller's frame; a component unframed for a multi-result or unstorable
  result type) become work before P0 lands (10 §6; 21 P-10).
- **B. Performance.** A statistic (`numFrameBound`), as today.

*Evidence:* 10 §6 NQ-2; 21 §6.1 (16005000 left a component unframed);
19 §6.

*AGENTS.md:* silent. Under A, "acceptance is a property of the program"
means the promise cannot rest on an optimizer's budget.

*Before:* none; decide beside DP-13. *Unblocks:* DP-38, DP-46, DP-57.

#### DP-15. The match after defunctionalization: regions or blocks [owner]

*Questions:* Q-O1.

*Decision:* Keep the structured `match` (a region per case) past
defunctionalization, or switch to a first-order control-flow graph with
`case` as a terminator whose arms are blocks receiving the
constructor's fields; and if kept, for which passes?

*Options:*
- **A. Regions to the end** (today: idr-lower makes `scf.index_switch`;
  nothing of ours runs on a graph of blocks). Buys: 27 files outside the
  IR read the regions: every counting pass, TRMC, tail loops, frames,
  bufferization, columns, narrowing, inlining (03, 08, 10, 11 §6); tail
  loops end in upstream's structured tools; One-Shot bufferization on
  structured control. Costs: every effect query walks every case; the
  enclosing-match walks (which DP-37 removes); contification limited to
  one call site (10 §6).
- **B. Blocks from defunctionalization on** (MLton's form, §5.9 design
  2). Buys: e96bb991's quadratic query cannot arise; upstream's
  block-merging, dominance and liveness work as they are; full
  contification; one definition of tail position (10 §6). Costs: every
  region-reading pass rewritten onto blocks or moved before the switch;
  tail loops get `scf` back only through `lift-cf-to-scf`; One-Shot on
  unstructured control has limits (11 §6, recalled); a 30,000-arm case
  is 30,000 blocks in one region, with its dominator tree.
- **C. Regions through counting and the tail passes, blocks from a later
  point to the lowering.**

*Evidence:* 03 §6 (the op is already the region form of a case with
produced fields; e96bb991's quadratic was a client's); 04 §6 (ten
patterns read all N regions; three rebuild the match); 08 §6; 10 §6; 11
§6; 12 §6 (the region form's one artifact at lowering: a poison yield
after a crash).

*AGENTS.md:* silent. The skill: "upstream dialects before ours"
(`scf.index_switch` is a region per case).

*Before:* none. *Unblocks:* DP-37, DP-38, DP-46, DP-53, DP-67, DP-76.

#### DP-16. Borrows: regions, or lifetimes in types [owner]

*Questions:* DD-Q6.

*Decision:* Are borrows scoped by regions with no lifetime in the type,
or do types carry lifetimes as symbolic attributes (Mojo: kept until one
checking pass, then erased)?

*Options:*
- **A. Regions** (§5.8 T5): a local check stops a view escaping its
  region. Costs: a view read out of memory that may be written dies at
  that memory's next write, "a scope a region could not state" (01 §6);
  borrowed parameters are views the caller keeps alive across the call.
- **B. Symbolic lifetimes in types,** checked once, then erased.
- **C. Neither, as today:** a view is a grade, its scope checked by the
  owned rule's walk of the whole function; the lifetime parameter means
  heap or frame (0003 owes `static`).

*Evidence:* 01 §6; 07 §6; 08 §6 (borrows are views made per read; the
owner is never dropped before a view's last use); 17 §6 (Idris has no
borrows or lifetimes; the boundary is neutral).

*AGENTS.md:* silent ("a linear binder does not imply unique heap
ownership").

*Before:* DP-13 (whether borrows are inferred at all). *Unblocks:*
DP-39 (the lifetime parameter), DP-60 (where the owned rule runs).

#### DP-17. One meaning for ops without a runtime function [owner]

*Questions:* conv-Q1, ops-Q2, arr-Q3, ops-Q3.

*Decision:* Where is the one meaning of ops that have no runtime
function (Euclidean division, the total shifts, the scalar-value test,
`to_char_s/u`; `Array.Core`'s 21 externs), and may the frontend guard
an upstream `arith` op so `divu` and `modu` leave the dialect?

*Options:*
- **A. A runtime function for each,** which the folders call. Buys: one
  meaning in `runtime/`. Costs: a call where the vectorization schedule
  sees one (12 §6, conjecture); link-time inlining needed.
- **B. One C++ template, instantiated for folding and for lowering,**
  as the one meaning (12 §6 NQ1). Costs: the runtime's third copy of
  division goes or calls it.
- **C. The expansion into `arith`, with guards, is the meaning** (03 §6
  NQ2, NQ3; §5.8 DS4). A guard then `arith.divui`, paired by a
  generated record. Buys: upstream dialects before ours; `arith` folds
  them. Costs: every edge case `arith` leaves undefined (division by
  zero, shifts past the width) must be guarded exactly.
- **D. For the array externs, the dialect's op is the meaning** (11 §6
  N3), named so in AGENTS.md or 0009.

*Evidence:* 03 §6; 11 §6; 12 §6 (meaning written twice in C++, folder
and lowering, and division a third time in the runtime); 18 §6 (the
runtime has per-sign entries only where text or conversion differs).

*AGENTS.md:* constrains: "No primitive has an implementation in Idris:
its one meaning is the runtime's (`runtime/`), which folders call too",
and "a primitive of `libs/` ... means only what `runtime/` says". A is
what it says; B, C and D need it amended.

*Before:* none. *Unblocks:* DP-41, DP-42.

#### DP-18. Crash statuses and crash sites [owner]

*Questions:* oom-6, conv-Q4.

*Decision:* Does a program give distinct exit statuses for running out
of memory and for a stack overflow, and does a crash site reach the
runtime as data (cause, file, line, column) instead of one message
string per site?

*Options:*
- *Statuses (oom-6).* (a) One status each for out of memory and stack
  overflow, distinct from other crashes. (b) Status 1 for every crash,
  as today, the cause text telling them apart. Evidence: 18 §6 (ten
  runtime causes, all status 1; snmalloc's own errors abort; a libc++
  hardening trap is another status); 19 §6 (the harness requires exit 1
  and `idris-mlir: <cause>`; one test reaches out of memory, none a
  stack overflow).
- *Sites (conv-Q4).* (a) (cause, file, line, column) as data: an ABI
  change. (b) One string per site (today). Evidence: 12 §6 NQ4.

*AGENTS.md:* "Tests check behaviour: exit status ..."; silent on which
statuses. The ABI half is technical once the statuses are set.

*Before:* DP-01 (`exit`), DP-11. *Unblocks:* none.

#### DP-19. Strict hosts and a memory limit [owner]

*Questions:* oom-5, rt-Q3.

*Decision:* Must a program start under Linux overcommit mode 2 or a low
`ulimit -v`, and should programs have a memory limit (off, set by an
environment variable, or read from the cgroup), counted how?

*Options:*
- *Strict hosts (rt-Q3).* (a) Programs start there (reservations made
  lazily or sized). (b) Outside what a program promises; today a program
  reserves 64 GiB of stack, a 4 GiB heap region and snmalloc's pagemap,
  a constant chosen knowingly in 1445d894.
- *A limit (oom-5).* (a) Off by default. (b) An environment variable.
  (c) The cgroup's `memory.max` by default. Counted by a counter in the
  allocator's chain of ranges, or by the reservation's size.

*Evidence:* 18 §6 (the owner ruled once: 07aeb299 made the heap one
bounded region; 1445d894 reverted it the same day: "Memory is the
machine's ... no runtime setting or harness bound").

*AGENTS.md:* reading the cgroup is Linux-only, so it sits behind the
runtime's platform layer. The owner's earlier ruling in history points
one way for oom-5.

*Before:* DP-11. *Unblocks:* none.

#### DP-20. Idris's elaborator and its counts [owner]

*Questions:* Q-FB3.

*Decision:* Remove `%ambiguity_depth` (3) and `%auto_implicit_depth`
(50) from the fork, as `%totality_depth` was removed, or accept them as
Idris's own type checking, outside AGENTS.md's rule on counts?

*Options:*
- **A. Remove them.** Buys: no program refused because a count ran out.
  Costs: the elaborator's search needs another way to end.
- **B. Accept them** as how Idris decides what a program means.

*Evidence:* 17 §6 Q-FB3 (the counts at `Ambiguity.idr:326-334`,
`App.idr:272-274`; the precedent upstream/fork-totality-depth).

*AGENTS.md:* "A round count ... or any other count is never a reason to
refuse a program"; "a trust the frontend takes in Idris's compiler is
stated in the fork". Whether the rule reaches Idris's elaborator is the
question.

*Before:* read DP-33 (the budget line) first. *Unblocks:* none.

#### DP-21. The proof's model and the code [owner]

*Questions:* Q-fc-1.

*Decision:* Make the code's `Template` the model of Theorem 1 (the
frontend builds the derivation and the run-time witness goes), or accept
the witness as the bridge, recorded as a trust point?

*Options:*
- **A. The code is the model.** Buys: no internal-error path; the proof
  covers the code. Costs: proof work on the Idris side, inside the
  subset both hosts compile.
- **B. The witness accepted as a stated trust point.** Costs: an
  internal error that fires on a frontend bug (never on a user program)
  stays.

*Evidence:* 16 §6 Q-fc-1 (`Proof/Bound.idr`'s three-constructor model;
`Finite.heightWithin`, `sizedWithin`).

*AGENTS.md:* "a trust it takes in itself is `covering`, never asserted";
the skill keeps a trust point "only where the owner accepted one".

*Before:* none. *Unblocks:* lane 16's target design.

### 2.2 The coordinator's (grouped by area)

#### Process and records

##### DP-22. How each step lands [coordinator]

*Questions:* hist-Q2, T-Q1.

*Decision:* Must every cutover step build and pass the suites, and run
stage 1, on the build machine before the next; and which tests must
every step pass unchanged?

*Options:*
- **A.** Every step builds, passes the five suites and leaves a stage-1
  record before the next; no WIP on main. The invariant set: the program
  tests (234, 907 cases), the rejects with their neighbours, the
  semantics runs, the benchmarks' outputs, the fuzz seeds. Buys: no
  step's correctness rests on tests it rewrote. Costs: a green start
  (DP-06); a long stage-1 run per step. (20 §5.1 L2; 19 §6 T-Q1.)
- **B.** Build and suites per step; stage 1 at milestones. Cheaper;
  walls found later.
- **C.** Type-checked, unbuilt waves, as 10-14 to 10-18 were. The suite
  has not been green since (20 §6); 101edbc5 is the measured case
  (21 §6.1).

*AGENTS.md:* settles the build half: a change "is done when it builds
and passes on all four" targets, and the checks list. C is excluded.

*Before:* DP-05, DP-06. *Unblocks:* DP-23, DP-27, DP-28.

##### DP-23. The frontend's mirror moves with the `.td` [coordinator]

*Questions:* Q3.

*Decision:* Is the frontend cut over in the same change as the `.td`
files?

*Options:* **A.** The same commit. **B.** The frontend later, behind a
compatibility layer.

*Evidence:* 14 §6 (a change to an op, type or primitive the frontend
names breaks its build: 73 op call sites, 90 primitive constructors in
the registry; the 125 ops it never writes change by regeneration only);
15 §6 (Core insulates the translation, but 16 of its 24 files import
generated names); 17 §6 (a shim would be a second copy of the grade).

*AGENTS.md:* settles it: the Idris side "compiles under two hosts,
always", and §4's hard cutover forbids a shim.

*Before:* DP-22. *Unblocks:* DP-69.

##### DP-24. Measure before adopting, patch before dropping [coordinator]

*Questions:* hist-Q1.

*Decision:* Is an upstream mechanism adopted only with a measurement at
stage-1 scale, and removed only after the upstream patch was tried or a
measurement shows the state is essential; and is that rule written in
AGENTS.md or in P0's §4?

*Options:* **A.** In AGENTS.md. **B.** In §4 and in §7.3's gates.
**C.** No rule.

*Evidence:* 20 §5.1 L1, §6 NQ1 (595ed341's adoption, ffa91113's and
16005000's drops would each have failed it); 21 §6.1 (both drops rest on
a kill or a stop). Cost: a patch reaches the tool only through the
bootstrap on the build machine (20 §6 QA1).

*AGENTS.md:* constrains: an upstream bug is fixed upstream, never worked
around; §4 already asks each solver of ours to state "the measurement
that shows it". Writing a new rule into AGENTS.md is the owner's text.

*Before:* DP-07. *Unblocks:* DP-26, DP-51, DP-54.

##### DP-25. What P0 leaves out [coordinator]

*Questions:* QL5, cxx-Q5.

*Decision:* Are equality saturation and static reflection out of P0,
with nothing waiting for them?

*Options:* **A.** Both out. **B.** Plan a pin bump for reflection.
**C.** Study equality saturation in P0.

*Evidence:* 04 §6 QL5 (one phase-ordering cycle, c179ab2d, fixed by a
combined rewrite; no §3 wall came from phase ordering); §5.5 D9
(reflection at the pin is `^^` on builtin types behind a cc1 flag).

*AGENTS.md:* the LLVM projects track main, so reflection arrives with
the pin without a special bump.

*Before:* none. *Unblocks:* none.

##### DP-26. Ports from Modular, CIRCT and IREE [coordinator]

*Questions:* Q-M4, Q-E4, defunc-Q1.

*Decision:* Port more code (header kept, a `PINS.md` entry), or write
fresh code informed by it; and may deduplication merge functions inside
call-graph cycles?

*Options:*
- **A. Port where the code fits:** Modular's `SCCGraph` schedule,
  per-worker driver, dead-argument pass, `Shared<T>`; CIRCT's
  `InstanceGraph` shape and Dedup's hashing.
- **B. Fresh code informed by them.** Evidence: of the one port, little
  of the original remains and lane 06's T4 would retire it (06 §6);
  `SCCGraph` has neither the insertion nor the merge the optimizer
  needs (05 §6); what transfers from CIRCT Dedup is a shape of a few
  dozen lines (06 §6).
- **C. Port only self-contained passes with a property test** (20 §6:
  the port that succeeded was one; the engines that churned were
  framework adoptions).
- *Deduplication (defunc-Q1):* (a) partition refinement, which merges
  inside cycles and changes which functions survive and where their
  locations point; (b) keep the exclusion, with CIRCT's barrier-free
  hashing (06 §6 NQ-defunc-1).

*AGENTS.md:* licences and pins recorded; nothing loaded at run time.
DP-08: Modular writes CRTP without concepts (§5.4 F13), so ported code
is rewritten to the line or kept apart.

*Before:* DP-08, DP-24. *Unblocks:* DP-52.

##### DP-27. Renames [coordinator]

*Questions:* DD-Q8, T-Q3.

*Decision:* Is every name open, including `con`, `dup`, `drop`, the
`idr` namespace, and idr-expect's 82 property names?

*Options:* **A.** Every name open, the test API included. **B.** Op and
type names open; idr-expect's names frozen across P0, their
implementations restated over declared facts. **C.** Core names kept;
only the 46 unprefixed mnemonics renamed.

*Evidence:* 03 §6 (46 of 189 mnemonics unprefixed; 334 of 356 test files
name an `idr` op, 26,104 times); 14 §6 (the Idris side spells no op
name; the namespace is a few literals there); 19 §6 (b9d4d592 touched
322 test directories; a reject's directory starts with its rule's
phrase); 20 §6 (renames have been cheap and drifting).

*AGENTS.md:* silent. §1, the owner: "Redesign it whole, with every
rename it needs".

*Before:* DP-22. *Unblocks:* DP-28.

##### DP-28. Rewriting the fixtures [coordinator]

*Questions:* T-Q2.

*Decision:* How do the 339 fixtures holding 26,025 of today's names get
through the cutover?

*Options:* **A.** Rewritten by hand. **B.** Converted once by a script
that is not kept. **C.** Each fixture that can be a program test
replaced by one, whose emitted module no later dialect change touches.

*Evidence:* 19 §6 T-Q2.

*AGENTS.md:* "Tests check behaviour ... Not clone numbers, function
order or SSA names" bears toward C where it can.

*Before:* DP-22, DP-27. *Unblocks:* none.

##### DP-29. Snapshots for `sources/` [coordinator]

*Questions:* QL6.

*Decision:* Approve the list of documents in §5.7.6 for `sources/`.

*Options:* **A.** Approve. **B.** Amend. **C.** Defer.

*AGENTS.md:* `sources/` holds snapshots of papers and upstream docs.

*Before:* none. *Unblocks:* none.

##### DP-30. Two upstream RFCs [coordinator]

*Questions:* Q-E5.

*Decision:* Record as upstream work, sent separately, an RFC for a call
graph maintained in place with its SCCs, and one for a scope between
function and module in the dataflow framework?

*Options:* **A.** Record both; send separately. **B.** Do not record.

*Evidence:* 05 §6 (the call graph is rebuilt up to seven times per
pipeline; no solve of ours wants a per-SCC framework scope today); 20 §6
(nothing filed upstream yet; an RFC is a larger step than any sent).

*AGENTS.md:* "Every patch has a written plan to upstream it ...; sending
it is separate work."

*Before:* DP-52. *Unblocks:* none.

#### Effects and rules

##### DP-31. A closure's allocation [coordinator]

*Questions:* eff-Q3.

*Decision:* May CSE merge two equal closures, suspensions or evaluated
suspensions into one cell before counting, as it may today (they
declare no allocation), while a box's `con` may not?

*Options:* **A.** Yes, as today. **B.** No: they declare their
allocation, as `con` does (02 §5 T3). Either answer is one row of
the effect system's source (DP-04).

*Evidence:* 02 §6 NQ3.

*AGENTS.md:* silent.

*Before:* DP-03, DP-04. *Unblocks:* none.

##### DP-32. Quantity 1 at the boundary [coordinator]

*Questions:* DD-Q1, Q-FB2.

*Decision:* May a quantity-1 fact be dropped at the boundary: normalizing
`!idr.lin<i64>` to `i64` when it is built, and Emit holding a linear
binder plain when the translated body uses it twice?

*Options:*
- *Words (DD-Q1).* (a) Keep `!idr.lin<i64>`. (b) Normalize trivially
  copyable types when built (Swift's practice: §5.8 B5, D4).
- *Used twice (Q-FB2).* (a) A demotion the boundary makes and states.
  (b) An internal error: the translation must keep Idris's proof. (c) A
  refusal.

*Evidence:* 01 §6 (127 of 434 `lin` types in fixtures are words; the
verifier counts their uses; constants already exempt); 08 §6 (counting
never reads a word's quantity); 14 §6 and 15 §6 (the frontend grades
every linear binder but the world, whose bare type is already a
normalization by type); 17 §6 (on a word the fact detects passes that
duplicate a use; Q-FB2's site `Emit/Bodies.idr:131-138`).

*AGENTS.md:* settles it as written: "No pass may drop what Idris proved
... Quantity 1 is a type, `!idr.lin<T>`, which every transformation must
keep". DD-Q1 (b) and Q-FB2 (a) would need it amended, which is the
owner's.

*Before:* none. *Unblocks:* DP-39.

##### DP-33. Budgets, and the compiler running out [coordinator]

*Questions:* Q-llvm-2, Q-E3, oom-2, canon-Q2.

*Decision:* Confirm the line: an analysis a refusal rests on has no
budget (finite height or widening only); an optimizing analysis or
rewrite may stop at a budget counted in the program's units and keep
the pessimistic result, never an error; a compiler that runs out of
memory crashes with a named line, distinct from a refusal; and
canonicalization's `maxNumRewrites` is set per run to a multiple of the
function's op count.

*Options:* **A.** All of it. **B.** The line, but no rewrite budget for
canonicalization (a pattern cycle stays a hang, fixed in the patterns).
**C.** Budgets in time or bytes (they break stage 2 = stage 3: 09 §6).

*Evidence:* every lane that looked found the code already on the line:
04, 05, 06, 07, 08, 09, 10, 11, 13, 16, 19 §6 (no budget fails; none in
seconds; the stack budgets are bytes of the target's layout and only
leave cells on the heap: 08 §6). 04 §6 (`maxNumRewrites` unset, so a
cycle hangs: c179ab2d). 13 §6 oom-2 (today out of memory is LLVM's
handler and an abort; the verdict table has no row for it). 16 §6 (the
frontend's acceptance analyses have no budget at all; §5.6 and §5.11's
lists of analyses a refusal rests on omit its growth check and
reachability walk). 20 §6 (19fe1332 removed the one budget that
refused).

*AGENTS.md:* settles it: optimizing passes "may stop at a budget; a
spent budget leaves the program less optimized and never rejects it. A
round count ... or any other count is never a reason to refuse a
program", and every analysis a refusal rests on "is total".

*Before:* DP-11. *Unblocks:* DP-20 (read with it), DP-52, DP-53, DP-64,
DP-67, DP-77.

##### DP-34. Determinism across thread counts [coordinator]

*Questions:* QL4, Q-llvm-6.

*Decision:* Is byte-identical output at any thread count a requirement,
and is each solver also tested alone at one thread and at many, its
frozen answers compared?

*Options:* **A.** Required, plus a per-solver test in the unit-test
boxes. **B.** Required, whole-pipeline tests only (today). **C.** Not
required.

*Evidence:* 13 §6 (the code claims it in four places; the harness
compares 1, 3, 5, 13 and a drawn count); 19 §6 (`LabelsLeast` is already
an oracle's shape a solver box can reuse); 09 §6 (independent of the
schedule but for OPT-48); 16 §6 (the frontend is single-threaded, its
orders fixed); 20 §6 (3dbf0e2f required it); 21 §6.1 (nothing the agent
added is tested at two counts).

*AGENTS.md:* silent; the shipped tool already promises it.

*Before:* none. *Unblocks:* DP-52, DP-53.

##### DP-35. The `Faster` rule as a test [coordinator]

*Questions:* ids-Q6.

*Decision:* Check AGENTS.md's "removing the hook leaves the same result"
with a test that compiles each program with and without the `Faster`
hooks and compares exit, output and refusals, or keep it a review rule?

*Options:* **A.** A test. Cost: a mode that drops the hooks is a
behaviour option, which `Passes.td:4-5` and `Main.cpp:66-68` exclude by
principle (13 §6) and §5.4 lists as "not to take", so the test needs a
seam that is not a user-facing option. **B.** A review rule.

*Evidence:* 14 §6 NQ-14-6.

*AGENTS.md:* states the rule; "there is no oracle" concerns Chez and the
stock evaluator, not this comparison.

*Before:* none. *Unblocks:* none.

#### The dialect's representation

##### DP-36. Facts into types and the IR [coordinator]

*Questions:* Q-O3, Q-E2.

*Decision:* Is every fact a later pass reads written into a type or a
verified inherent property by the pass that proves it, with everything
else recomputed and nothing carried between passes as a side table; and
does a summary (a function's effects, its parameters' grades) live in
the IR, verified after every pass, or in a cached analysis?

*Options:*
- **A. Into the IR, verified** (§5.9 design 3; IREE's resource
  lifetimes). Today's code already does it for effects (on `idr.func`
  and each `idr.call`, verified) and grades (in function types), and the
  frontend writes quantity, erasure and termination (01, 06, 07, 08, 11,
  15, 17 §6). Buys: no rederivation chain; an immutable `!idr.data`
  naming its type in one table makes 98c6315c's lock and 73bba53f's
  rebuild impossible. Costs: every transformation keeps the facts right
  (06 §6); a type naming an entry of an ancestor's table leaves the ODS
  constraints and verifiers that read bodies without an op in hand (147
  calls in 57 files: 01 §6).
- **B. Summaries in cached analyses** (§5.6 design 1's default). Costs:
  recomputed per pipeline segment; if effects leave the call, upstream
  passes see unknown effects (03 §6).
- **C. By rule of the reader:** in the IR where passes rely on it across
  a pipeline segment; an analysis where one pass reads it.

*Evidence:* also 09 §6 (what a function gives back, binding times,
constants and inline facts die with the optimizer's run; what it gives
back is solved again on the lowered module); 10 §6; 12 §6.

*AGENTS.md:* constrains: never a discardable attribute; "one thing, one
representation"; do not erase facts before the passes that use them.

*Before:* DP-09. *Unblocks:* DP-38, DP-40, DP-48, DP-52, DP-65.

##### DP-37. Case regions bind the refined scrutinee [coordinator]

*Questions:* QL2, ops-Q1.

*Decision:* Make "one value per ownership state" a rule of the dialect,
with each case region binding its scrutinee at a type naming its
constructor (`!idr.ctor<T, @C>`), so `field`, `take` and `unpack` lose
their `tag` attribute and a read of the wrong constructor cannot be
written?

*Options:* **A.** Yes, with the new type. **B.** The ownership half only
(already true: every ownership op defines a new value). **C.** The
refined scrutinee bound as a block argument, with no new type.

*Evidence:* 01 §6 (no type says "this value is constructor C" but a
cell's); 03 §6; 04 §6 (three enclosing-match walks and `readField`'s scan
become a block-argument read); 07 §6; 08 §6 (counting undoes the
default region's rebinding, kept for nat-parity by c4d38e9b); 15 §6 (the
frontend knows the refined value and emits nothing of it).

*AGENTS.md:* silent.

*Before:* DP-15. *Unblocks:* DP-53.

##### DP-38. What `idr.func` and `idr.call` carry [coordinator]

*Questions:* DD-Q7, tail-Q1, count-Q4, Q-AN1.

*Decision:* Keep our own function and call ops as carriers of verified
facts (effects today; add "this call is a tail call", the callee's
parameter conventions, "gives back argument i"), or move to
`func.func`/`func.call` with those facts in analyses?

*Options:*
- **A. Keep them, and add the three facts,** written by the passes that
  prove them, checked by the call's verifier, tail position lowered into
  `llvm.call`'s `tail_call_kind`. Buys: deletes seven tail-position
  readers (`IR/Tail.cpp`'s climb, `TailPosition.cpp`'s path walk) and the
  whole-module Returned solve; grading can nest on functions (05, 08, 10
  §6). Costs: every pass that changes a body or a call keeps them right
  (06 §6); a call op between `idr.call` and `llvm.call` must hold tail
  position (10 §6).
- **B. `func.func` and `func.call`, facts in analyses.** Costs:
  `func.call` has no effects interface or property, so upstream CSE and
  DCE see every call as unknown (03 §6); `idr::FuncOp` is named 530
  times.
- **C. Effects on the call only, as today;** tail position a cached
  analysis per function, the LLVM walk kept.

*Evidence:* 03 §6; 05 §6 Q-AN1; 08 §6.1 NQ4; 10 §6 NQ-1; 12 §6 (the
lowering's phase 0 rebuilds `idr.func` as `func.func` and drops its
facts); 14 §6; 15 §6.

*AGENTS.md:* inherent properties are not discardable; silent otherwise.

*Before:* DP-02, DP-03, DP-04, DP-14, DP-15, DP-36. *Unblocks:* DP-54, DP-57,
DP-60, DP-61.

##### DP-39. The grade's form [coordinator]

*Questions:* types-Q4, types-Q3.

*Decision:* One closed grade attribute with methods, not an interface;
and is `Plain` two cases (nothing decided, before counting; holds no
reference, after) or one case read by the program's stage?

*Options:* *Grade (types-Q4):* (a) one attribute with methods (01 §5
C1); (b) §5.8 DS1.1's grade interface. *Plain (types-Q3):* (a) two
cases, one legal only before counting; (b) one case read by stage
(today).

*Evidence:* 01 §6 NQ3, NQ4 (six quantity and permission pairs occur);
11 §6 (a tensor-like grade per instance needs upstream's interface on
the one grade type, not a grade interface).

*AGENTS.md:* quantity 1 stays a type. The skill lists "an interface
where the type already fixes the implementation" among what to avoid.

*Before:* DP-10, DP-16, DP-32. *Unblocks:* DP-47.

##### DP-40. Who decides layout [coordinator]

*Questions:* ft-Q1, types-Q2.

*Decision:* Are representation choices (a one-field type collapsed to
its field, Nat-likes as `!idr.nat`, pointer-like words as `u64`, crash
alternatives enumerated, boxes for cyclic types) Idris facts the
frontend states, or the dialect's decision made once from the type
graph?

*Options:* **A.** The frontend decides and emits all of it, boxes
included: a table is never cyclic in place, `DataTableAttr::verify`
refuses a cycle once, and `layout::fit` with its whole-program remap
goes. **B.** The dialect decides layout (as `Term.idr:110-112` says),
the frontend emits types in place. **C.** Idris facts in the frontend,
layout in the dialect.

*Evidence:* 15 §6 NQ-1; 01 §6 NQ2.

*AGENTS.md:* points one way: the Idris side "checks what the compiler
accepts, monomorphises and decides representations". The comment in
`Term.idr` disagrees with it.

*Before:* DP-09, DP-36. *Unblocks:* DP-48.

##### DP-41. Signedness [coordinator]

*Questions:* DD-Q4.

*Decision:* arith's school (signless types, the sign on the op where the
computation differs) or CIR's (signed types, one op)?

*Options:* **A.** arith's. **B.** CIR's.

*Evidence:* the tree is arith's already, in ODS (03 §6), the folds (04
§6), the lowering (12 §6), the frontend's emitter (14, 15 §6) and the
runtime (18 §6). Left over: `shls`/`shlu` are one computation (§5.8 DS4:
one `shl`), and five pairs differ only in runtime function and ABI
extension (03 §6).

*AGENTS.md:* silent.

*Before:* DP-17. *Unblocks:* none.

##### DP-42. Ops, runtime functions and base primitives [coordinator]

*Questions:* DD-Q5, ids-Q5.

*Decision:* May one op with an enum (`io.clock <kind>`, `idr.check
<reason>`) map to runtime functions through a table generated from ODS;
and does an op's record name the base primitive it implements, so the
registry's IO rows are generated?

*Options:* *Enum ops (DD-Q5):* (a) one op, one function, the kind a
parameter of that function (the runtime already holds the enum:
`idris_rt_io_clock` reads `rt::platform::Clock`; 03, 12, 18 §6), which
needs the generator to admit an enum argument; (b) one op, several
functions, through a generated (op, case) table (a second dispatch
beside `Abi<Op>`: 12 §6); (c) separate ops, as today. The six stat
times as one op with several results need a multi-result ABI (12 §6),
and base calls them one by one (14 §6). *Primitive (ids-Q5):* (a) ODS
names it; (b) the registry stays the one place.

*AGENTS.md:* a primitive's one meaning is the runtime's; "one thing, one
representation".

*Before:* DP-02, DP-17, DP-69. *Unblocks:* DP-43.

##### DP-43. Output: fuse or compose [coordinator]

*Questions:* canon-Q3.

*Decision:* Is the canonical form fused (`put_str(show_sint x)` becomes
`put_sint x`, today) or composed (a pure `show` and one write, fused at
lowering, §5.8 DS4)?

*Options:* **A.** Fused. **B.** Composed: four effectful `put_*` ops go.

*Evidence:* 04 §6 NQ3.

*AGENTS.md:* silent. The skill: values and memory at different levels,
lowered progressively.

*Before:* DP-42. *Unblocks:* none.

##### DP-44. Is a link an op? [coordinator]

*Questions:* arr-Q2.

*Decision:* One op per kind (a link, in place always; a head, may copy),
the check then confirming the op, or one op with the fact computed once?

*Options:* **A.** One op per kind (the translation knows when it threads
one `LArray` across a boundary). **B.** One op, the fact computed once
(11 §5 C6).

*Evidence:* 11 §6 N2 (re-proved on every query today, `Linear.cpp:32-50`).

*AGENTS.md:* silent. The skill: one op per semantics.

*Before:* DP-10. *Unblocks:* none.

##### DP-45. Transposition as a tabulate [coordinator]

*Questions:* arr-Q4.

*Decision:* Delete `idr.transpose`, the frontend writing a transpose as a
tabulate of a permuted read that linalg names again?

*Options:* **A.** Delete it. **B.** Keep it.

*Evidence:* 11 §6 N4 (0009 §3.1's indexing map is kept in the
tabulate).

*AGENTS.md:* silent.

*Before:* DP-10. *Unblocks:* none.

##### DP-46. Frames' stack per result type [coordinator]

*Questions:* tail-Q3.

*Decision:* One stack data type per member result type (a mutually
recursive group), or one per component with the impossible cases in a
default region?

*Options:* **A.** Per result type: "a frame of another type on top"
cannot be built; the R·(F+1) impossible cases go. **B.** Per component.

*Evidence:* 10 §6 NQ-3 (D2).

*AGENTS.md:* silent.

*Before:* DP-14, DP-15. *Unblocks:* none.

##### DP-47. Stages declared in TableGen [coordinator]

*Questions:* ops-Q4, drv-Q2.

*Decision:* Does each op family declare the stages it is legal at (a
generated trait, replacing the program verifier's stage rule), and is
the pipeline one TableGen list (order, reasons, options) with its stage
chain asserted there and nesting computed from anchors, generating the
textual pipeline, the registrations and the tests' table?

*Options:* **A.** Both. **B.** Op stages only. **C.** Neither (today).

*Evidence:* 03 §6 NQ4; 13 §6 NQ2.

*AGENTS.md:* each refusal's rule already carries its category in ODS;
silent otherwise.

*Before:* DP-39, DP-60. *Unblocks:* none.

#### Defunctionalization

##### DP-48. Types first [coordinator]

*Questions:* defunc-Q3.

*Decision:* Replace the per-function dialect conversion by one walk that
writes the label solve's decision into the types, legality checked by
the stage verifier?

*Options:* **A.** One walk (deletes three maps per function and pattern
rollback). **B.** Keep the conversion (`TypeConverter` and
`ConversionTarget`, which the skill names for lowering); the types here
depend on a value's flow set, not its type.

*Evidence:* 06 §6 NQ-defunc-3, Q-O3; 21 P-6 (the per-function pattern
set costs about 11 % of test-idr's samples).

*AGENTS.md:* silent.

*Before:* DP-36, DP-40. *Unblocks:* none.

##### DP-49. One sink per operand [coordinator]

*Questions:* defunc-Q4.

*Decision:* A use that moves into two points unifies them, coarsening
both sets so the plan holds one key per use: keep, or coerce the operand
into each sink?

*Options:* **A.** Keep. **B.** Coerce into each (finer sets, more
coercions).

*Evidence:* 06 §6 NQ-defunc-4 (`LabelSites.cpp:106-110`).

*AGENTS.md:* silent.

*Before:* none. *Unblocks:* none.

##### DP-50. Effects before the conversion [coordinator]

*Questions:* defunc-Q2.

*Decision:* Fold idr-effects into defunctionalization's decision (one
summary over calls and label runs that also decides `by_name`, kept
current by idr-optimize), or keep a separate pass after the conversion?

*Options:* **A.** Fold it in (06 §5 T3). **B.** Separate, as today.

*Evidence:* 06 §6 NQ-defunc-2.

*AGENTS.md:* silent.

*Before:* DP-01, DP-02, DP-03, DP-04, DP-52. *Unblocks:* none.

#### The solver layer

##### DP-51. Upstream's dataflow framework: patch it, and what stays on it [coordinator]

*Questions:* QA1, QA2, Q-AN3.

*Decision:* Patch the framework's state storage first (P1: two
declarations; P2: a flat map and typed arenas), then decide per analysis
what returns to it; solve per function with summaries by default, or
whole-program where it measures small after the patch; and Ranges in
particular?

*Options:* **A.** P1 first, then measure the three whole-program users
(Ranges, Borrows, Returned) and keep those that fit (20 §5.2 item 3).
**B.** Per function by default: Ranges with callers-first argument
summaries, Returned as one bit per (result, argument), Borrows per SCC;
P1 for the per-function solves. **C.** P2.

*Evidence:* 05 §6 (P2's per-type freeing has no client: every solve
drops its whole solver at once; Ranges and Returned have never run at
stage 1; Ranges' readers are per function); 07 §6 (P1 cuts Borrows about
fifteenfold; exclusivity per function needs IFDS-style summaries or loses
precision; Borrows fits Lean's per-SCC shape); 10 §6 (Returned never
reached); 11 §6 (Ranges has the shape of the 52 GB wall; integer ranges
per function measured 3 s against 30 s module-wide); 20 §6 (no storage
patch was ever tried; none of about 25 patches has been filed); 21 §6.1.

*AGENTS.md:* an upstream problem is fixed upstream; §4's order (upstream
as is, then patched, then ours).

*Before:* DP-07, DP-24. *Unblocks:* DP-52, DP-53, DP-54.

##### DP-52. The spine: one program graph and one schedule [coordinator]

*Questions:* Q-E1, Q-M1, Q-AN2, Q-llvm-7.

*Decision:* One maintained program graph with three solve shapes
(summaries over SCCs, local solves per function, extract-solve-write
back) on one call-graph schedule; is the optimizer's dynamic schedule
(nodes inserted, SCCs merged) the spine's job or its one dynamic client;
`SCCGraph` ported or written fresh; and the giant SCC solved serially or
with lld's double-buffered rounds?

*Options:* **A.** A static spine, the optimizer its one dynamic client,
the giant SCC serial first and measured. **B.** A spine that supports
insertion and merge, serving every client. **C.** A or B, with lld's
rounds from the start. Port or fresh follows DP-26.

*Evidence:* 05 §6 (three schedules today; `SCCGraph` has neither
insertion nor merge; two problems do not fit the three shapes as stated:
the optimizer's growing graph, exclusivity's outer rounds; the stage-1
SCC sizes are recorded nowhere); 06 §6; 09 §6 (the optimizer is the
largest client and grows the graph mid-run; a giant component is one
worker's share).

*AGENTS.md:* optimizations "terminate by construction (a fixed sequence,
a bottom-up order)".

*Before:* DP-26, DP-33, DP-34, DP-36, DP-51. *Unblocks:* DP-30, DP-50,
DP-53, DP-54, DP-64.

##### DP-53. The solver layer's state and model [coordinator]

*Questions:* QA4, Q-O2, QL1, Q-llvm-3, QL3.

*Decision:* One state representation for all our solvers (dense
numbering per function, arrays and bit vectors, a read-only array view
built per solve); one model (MLton's constraint-generating interpreter
with cells, rules over relations, or transfer functions over one
engine); and where the numbering lives (per solve, a cached analysis, or
an upstream patch numbering ops or values)?

*Options:*
- *State:* (a) one shared representation; (b) each solver its own
  (today: at least six numberings minted separately, no two solvers
  sharing a graph type: 05 §6).
- *Model:* (a) MLton's interpreter as *the* layer, `DataFlowSolver` kept
  for intraprocedural solves whose state fits (it fits exclusivity, the
  stack inference, observable runs, effects and the label solve; not
  BindingTimes, which is relational: 05 §6); (b) rules over relations
  (the label solve already reads its rules as data: 06 §6); (c) transfer
  functions over one engine.
- *Input:* (a) a scoped array view per solve (Identities' `Record`
  exists: 05 §6); (b) MLIR values keyed by hash maps.
- *Numbering:* (a) per solve; (b) a cached analysis (`Positions` and the
  owned verifier's numbering are two clients already: 21 P-2); (c) an
  upstream patch (MLIR numbers blocks only, and we do not use it: 05 §6).

*Evidence:* 05 §6; 06 §6; 07 §6 (every state of the ownership analyses
maps onto a dense numbering per function); 21 P-14, P-20.

*AGENTS.md:* silent. §9 D2: our own solvers, named honestly, in code of
their own. DP-08 sets their C++.

*Before:* DP-08, DP-15, DP-33, DP-34, DP-37, DP-51, DP-52; DP-06 if it
takes option A. *Unblocks:* lane 07's D2 and D5, lane 08's T3.

##### DP-54. `remove-dead-values` [coordinator]

*Questions:* QA3, Q-opt-4, hist-Q3.

*Decision:* Bring the pass back split (upstream's per function, our
signature half over the call graph, perhaps in idr-optimize's summary),
whole-module on a patched framework, or leave it out as 16005000 did;
and retire patches 06, 28 and 63 now or hold them.

*Options:* **A.** Leave it out: the signature half is the optimizer's
specialization holes and counting's drops (16005000's message); retire
the three patches now. Cost: the claim is unmeasured (21 P-9); LLVM's
dead-argument pass cannot remove the dup and drop counting inserted (09
§6, conjecture). **B.** Split, our half in the optimizer's summary
(parameters bottom-up, results callers-first: 09 §5 T5); hold the
patches. **C.** Whole module, patched (eight patches over its life, two
silent miscompiles on our shapes, 52 GB sampled: 20 §6).

*Evidence:* 05 §6; 09 §6; 20 §6; 21 §6.1.

*AGENTS.md:* settles hist-Q3 once QA3 is answered: "A patch goes ...
when nothing in the tree reaches the bug any more".

*Before:* DP-24, DP-38, DP-51, DP-52, DP-64. *Unblocks:* none.

#### Counting

##### DP-55. How much exclusivity is static [coordinator]

*Questions:* rc-Q2, own-Q3.

*Decision:* Prove what one marking can and test the rest at run time
(R1), or also make copies of functions by grade (R2); and do grade copies
move into the one specializer or stay where exclusivity is solved?

*Options:* **A.** R1 and R2 as built: grade copies inside counting (one
per function, at most twice the functions), the run-time test as
fallback. **B.** R1 only: the copies go. **C.** The grade a key of the
one specializer; idr-optimize runs before grades exist (09 §6), so the
pipeline order changes.

*Evidence:* 07 §6; 08 §6; 12 §6 (both arms of the run-time test give the
same fields: speed, never meaning; the folding op is missing); 18 §6 (a
wide take-apart cost 4,472 increments and decrements in one function);
11 §6.

*AGENTS.md:* settles the fallback: "linearity is a performance property,
never a correctness one". An in-place sum has no fallback (DP-12).

*Before:* DP-12, DP-13. *Unblocks:* DP-58, DP-59, DP-64.

##### DP-56. Drops at last use [coordinator]

*Questions:* rc-Q5.

*Decision:* Confirm that drops go at last use everywhere (Idris has no
destructors, so nothing needs Swift's lexical lifetimes).

*Options:* **A.** Confirm. **B.** Lexical lifetimes somewhere.

*Evidence:* 08 §6: the rule today, with four exceptions each in the code
(a loop holds an outside value while it runs; a crash region places
nothing; a borrowed argument lives in the caller across the call; a tail
call in a cycle makes the parameter owned).

*AGENTS.md:* silent.

*Before:* DP-13. *Unblocks:* none.

##### DP-57. Counting before or after TRMC [coordinator]

*Questions:* count-Q3.

*Decision:* Counting before TRMC (today: Borrows predicts idr-trmc's
tail calls), or TRMC first, as Koka does?

*Options:* **A.** Counting first. **B.** TRMC first.

*Evidence:* 08 §6.1 NQ3; §5.10 M10.

*AGENTS.md:* silent.

*Before:* DP-13, DP-14, DP-38. *Unblocks:* none.

##### DP-58. The take's expansion [coordinator]

*Questions:* conv-Q3.

*Decision:* Is the take's expansion (the test, the moves, the counts)
counting's last step at the `idr` level, leaving the lowering only
primitive ops, or does it stay the lowering's?

*Options:* **A.** Counting's (fits a uniqueness test as a folding op).
**B.** The lowering's.

*Evidence:* 12 §6 NQ3.

*AGENTS.md:* silent.

*Before:* DP-12, DP-55. *Unblocks:* none.

##### DP-59. The count: threads, shards and encoding [coordinator]

*Questions:* rc-Q4, rt-Q1.

*Decision:* Confirm that no counted cell is ever shared between threads
(no atomic count, no mark-shared pass) and that shards pass cells by
detach; and adopt Koka's signed count without its atomic half, after a
measurement?

*Options:* *Threads (rc-Q4):* (a) confirm; (b) plan for sharing.
*Encoding (rt-Q1):* (a) Koka's (0 unique, negative sticky; "count 0 is
persistent" moves to the sticky constant); (b) today's (`count == 1 &&
!stack`).

*Evidence:* 08 §6 and 18 §6 (plain arithmetic, no atomics; folders
release their cells on the thread that made them; 0007 passes messages by
detach); 12 §6.

*AGENTS.md:* silent.

*Before:* DP-07, DP-55. *Unblocks:* none.

#### Verification and the pipeline

##### DP-60. Verification after every pass, at 70,000 functions [coordinator]

*Questions:* ods-Q6, Q-M2, Q-O5, types-Q1, drv-Q3, T-Q4, T-Q5.

*Decision:* Keep full verification after every pass in every build and
pay for it; make nesting on functions a rule of the pipeline (decide,
apply, restructure) so verification is per function and parallel; or
split release builds; and where the owned rule runs, how contracts
scale, and how the verifier is measured.

*Options:*
- **A. Everything after every pass,** its cost a measured budget. Costs:
  the program verifier walks every function three to six times on one
  thread after each program pass and group, up to 26 times a compilation
  (01, 13 §6).
- **B. Nesting as a rule:** a decide pass computes a whole-program fact
  and changes nothing; nested apply passes rewrite each function in
  parallel from it; only a restructure pass changes the program's
  shape. Full verification kept. Costs: about a dozen passes do
  per-function work by hand today; a pass that adds or erases functions
  cannot nest (§5.8 B9); 4c87dcc5's half-graded program is the collision
  to avoid (13 §6).
- **C. Split release:** the grade check after every pass, MLIR's
  structural verifier at phase boundaries (Modular's practice). Costs: a
  behaviour chosen by the build, which the driver excludes by principle
  (13 §6); release already links LLVM with assertions.
- *The owned rule (types-Q1):* (a) in `idr.func`'s region verifier
  (today, parallel); (b) a check pass the instrumentation runs after
  every pass, the region verifier keeping local rules.
- *Contracts (T-Q4):* test-only, per-function records under nesting
  instead of a module clone per pass.
- *Measuring (T-Q5):* (a) from `--mlir-timing`'s verifier rows, the
  rule kept whole; (b) a `--verify-each=0` run outside the tree.

*Evidence:* 01 §6; 04 §6 (upstream's canonicalizer never preserves
analyses, so the verifier runs after every canonicalize); 09 §6 (the
optimizer verifies after each of five inner passes, per round, per
member); 10 §6; 13 §6; 19 §6 (`tests/verifier-every-pass` forbids turning
it off anywhere); 20 §6 (it caught 4c87dcc5); 21 §6.1 (1.6-1.7 % of the
suites' time; it caught 9db9813d's bug on stage 1; 101edbc5 adds a walk
to every verification).

*AGENTS.md:* settles Q-O5's contract: quantity 1 is a type "the verifier
checks after every pass". Open: structural verification, nesting, where
the owned rule runs.

*Before:* DP-07, DP-16, DP-38. *Unblocks:* DP-47, DP-61, DP-67.

##### DP-61. `idr-lower` under the pass manager [coordinator]

*Questions:* conv-Q2.

*Decision:* Accept two program passes (declare every runtime function,
make every static datum) so the lowering runs as a function pass, or
keep the worker-and-merge scheduler as an honest scheduler of ours, said
so in its header?

*Options:* **A.** Two program passes, then a function pass. **B.** Keep
the scheduler, named.

*Evidence:* 12 §6 NQ2 (T6).

*AGENTS.md:* silent. §4: "MLIR's pass manager does the parallelism"; §9
D2 allows an honest solver of ours.

*Before:* DP-38, DP-60. *Unblocks:* none.

##### DP-62. Worker stacks [coordinator]

*Questions:* drv-Q4.

*Decision:* Run the context's workers on reserved stacks like the main
thread, through a pool of ours or upstream's `StdThreadPool` given a
stack size?

*Options:* **A.** A pool of ours. **B.** An upstream patch giving
`StdThreadPool` a stack size. **C.** As today (a pass's recursion limit
depends on its thread and the OS).

*Evidence:* 13 §6 NQ4.

*AGENTS.md:* upstream first; stack sizes per OS belong in one platform
place.

*Before:* none. *Unblocks:* none.

##### DP-63. The prepared runtime's bitcode in one home [coordinator]

*Questions:* drv-Q5.

*Decision:* Keep the prepared runtime's bitcode in one home on every
target (beside the object), removing a per-target fact branched on in
four places?

*Options:* **A.** One home. **B.** As today.

*Evidence:* 13 §6 NQ5.

*AGENTS.md:* settles it: "Per-target cases elsewhere are bugs."

*Before:* none. *Unblocks:* none.

#### Specialization

##### DP-64. Specialization: order and shape [coordinator]

*Questions:* Q-O4, Q-M5, Q-opt-1, ft-Q3, Q-opt-2.

*Decision:* Specialize higher-order functions before the label solve
(MLton's polyvariance, perhaps in the frontend) or only after
defunctionalization; keep the bottom-up hybrid or move to Mojo's
demand-driven shape; interleave inlining and specialization, or
specialize to completion and then inline once with true call counts; and
how a made node's calls are counted.

*Options:*
- **A. Today's shape,** fixing OPT-12 by counting a made node's
  requesters (Q-opt-2). It is already a hybrid: bottom-up over
  components, nodes made on first request and never duplicated, with
  suspension (09 §6).
- **B. MLton's order in the optimizer:** specialize to completion, then
  inline once, then normalize. OPT-12 and OPT-84 disappear; keys that
  only inlining exposes are lost unless specialization runs twice.
- **C. Polyvariance before the label solve, in the frontend** (it holds
  the lambdas, a keyed instance cache and the growth bound: 15 §6),
  placed between deduplication and defunctionalization (06 §6), decided
  by measuring the closure sums with and without it.

*Evidence:* 06 §6 Q-O4; 09 §6 (three of last week's fixes were closures
inside recursions after defunctionalization); 15 §6; 16 §6 (the
frontend's monomorphizer is demand-driven from the root already).

*AGENTS.md:* specialization terminates by construction and may stop at a
budget that never refuses.

*Before:* DP-07, DP-33, DP-52, DP-55. *Unblocks:* DP-54, DP-65, DP-68.

##### DP-65. Keys outside the context [coordinator]

*Questions:* Q-opt-3.

*Decision:* May specialization keys be the run's own interned data,
freed with the pass and taking no context lock, or must they stay
attributes so that tools can print them?

*Options:* **A.** The run's own data. **B.** Attributes (today; never
freed).

*Evidence:* 09 §6 (OPT-64; 98c6315c's lock in §3).

*AGENTS.md:* silent.

*Before:* DP-36, DP-64. *Unblocks:* none.

#### Rewrites and tools

##### DP-66. DRR allowed, PDLL refused [coordinator]

*Questions:* ods-Q4.

*Decision:* Allow DRR (native, rooted patterns) and refuse PDLL (no
production user at the pin, interpreted)?

*Options:* **A.** Yes. **B.** Both allowed. **C.** Neither.

*Evidence:* 04 §6 (five pattern classes are DRR-able, about 16 `Pat`s,
deleting `StrBuilderOpInterface`'s methods; the other fourteen read
regions or summaries, which PDLL would not change; CIRCT canonicalizes
with DRR); 12 §6 (the lowering's 1:N patterns are not DRR: allowed, not
required).

*AGENTS.md:* silent.

*Before:* none. *Unblocks:* none.

##### DP-67. Canonicalization's place [coordinator]

*Questions:* canon-Q5, canon-Q4.

*Decision:* Keep canonicalization a pass at four pipeline points and in
idr-optimize, on upstream's greedy driver, or move to MLton's shape (one
normalizer per function that each pass runs on what it rewrote, on the
walk driver); and name the dialects whose patterns it collects?

*Options:* **A.** Keep the pass, with `filter-dialects` naming idr,
arith, ub and what each point needs. **B.** The per-function normalizer;
the greedy driver kept for upstream's folds.

*Evidence:* 04 §6; 21 P-8 (rooted patterns retried on any change under a
match); §5.9 design 5.

*AGENTS.md:* silent.

*Before:* DP-01, DP-15, DP-33, DP-60. *Unblocks:* none.

##### DP-68. Canonical forms before defunctionalization [coordinator]

*Questions:* canon-Q1.

*Decision:* Add a canonicalization before defunctionalization, where
the force, suspension and closure patterns would shrink the closure sets
the label solve sees, or delete those patterns, folds and fixtures (they
are reached only by their fixtures today)?

*Options:* **A.** Add it. **B.** Delete them.

*Evidence:* 04 §6 NQ1.

*AGENTS.md:* silent.

*Before:* DP-64. *Unblocks:* none.

##### DP-69. One TableGen tool, and the handoff [coordinator]

*Questions:* Q-llvm-5, ids-Q3.

*Decision:* One tool on `MlirTblgenMain` generating the C++ and the
Idris mirror through `mlir::tblgen`'s wrappers (effects included); and
the frontend's handoff: every `idr` type and attribute encoded natively
in bytecode (the copied declarative-format parser and the Idris printers
deleted), or text kept and upstream patched to make the format parser a
library?

*Options:* **A.** Native bytecode; wrappers everywhere. **B.** Text, with
the upstream patch. **C.** As today: two tools over one record set, a
copied parser.

*Evidence:* 14 §6 (the generator is already `GenRegistration`s on
`MlirTblgenMain`; it reads no effects and bypasses the wrappers in
places; at the pin `MLIRTblgenLib` is the driver alone); 12 §6 (the ABI
backend reads marks as raw records and a C type's kind by spelling); 20
§5.3 (the owner: "we cannot have the binary format be read by hand").

*AGENTS.md:* an upstream gap is patched upstream; silent otherwise.

*Before:* DP-23. *Unblocks:* DP-42, DP-70, DP-71, DP-72.

##### DP-70. Properties the frontend writes [coordinator]

*Questions:* ids-Q2.

*Decision:* Accept that every op the frontend writes keeps inherent
attributes rather than properties, or generate each op's property
encoder for the Idris writer?

*Options:* **A.** Accept the constraint. **B.** Generate the encoders.

*Evidence:* 14 §6 NQ-14-2.

*AGENTS.md:* silent.

*Before:* DP-69. *Unblocks:* none.

##### DP-71. Generated Idris modules in git [coordinator]

*Questions:* ids-Q1.

*Decision:* Keep the fifteen generated modules checked in (fingerprinting
only the records and the output), or make them outputs of `make build`?

*Options:* **A.** Checked in. **B.** Build outputs.

*Evidence:* 14 §6 NQ-14-1 (16 of 29 commits touching `Syntax/Idr.idr`
only restamped one line).

*AGENTS.md:* both hosts must still build the Idris side; under B, the
generator is built first.

*Before:* DP-69. *Unblocks:* none.

##### DP-72. Generated binder names [coordinator]

*Questions:* ids-Q4.

*Decision:* Prime every generated parameter (`(lhs' : Value)`), so no
keyword list is kept, or keep the list copied from the fork's lexer?

*Options:* **A.** Prime. **B.** Keep the list.

*Evidence:* 14 §6 NQ-14-4.

*AGENTS.md:* "one thing, one representation" bears against a copied
list.

*Before:* DP-69. *Unblocks:* none.

#### C++

##### DP-73. Variants [coordinator]

*Questions:* Q-llvm-4, cxx-Q2.

*Decision:* Ban `get_if`/`holds_alternative` chains for one exhaustive
`std::visit`, or ban `std::visit` itself for one fold `match`, or allow
`std::visit` up to 11 alternatives?

*Options:* **A.** Exhaustive `std::visit` (or `PointerUnion` for
handles). **B.** One fold `match` everywhere. **C.** `std::visit` up to
11, `match` above. **D.** Case by case.

*Evidence:* §5.5 finding 12 (above 11 alternatives libc++ dispatches
through a table: 300 sites, 11.3 s and 3 MB against 2.0 s and 68 KB); 11
§6 (one variant, and an `optional` that is a sum in disguise); 20 §5.1
L6 (55 variants added by waves without lowering `isa<`).

*AGENTS.md:* silent. DP-08's ruling favours templates.

*Before:* DP-08. *Unblocks:* none.

##### DP-74. Precompiled headers [coordinator]

*Questions:* cxx-Q3.

*Decision:* Precompiled headers for `foreign/idr` now, and C++ modules
not in P0?

*Options:* **A.** Yes. **B.** Neither.

*Evidence:* 13 §6 (no PCH, on a premise §5.5 D6 refutes; 294 units
include MLIR's core; modules were tried and taken out: 4cfce768,
1e1a3827).

*AGENTS.md:* silent.

*Before:* none. *Unblocks:* none.

##### DP-75. libc++ hardening [coordinator]

*Questions:* cxx-Q4.

*Decision:* Which hardening mode for debug and test builds, and is
release measured or left unchecked?

*Options:* **A.** Extensive everywhere, as today. **B.** Extensive in
debug and test, release measured, then decided. **C.** Release
unchecked.

*Evidence:* 13 §6; 18 §6 (the runtime uses little of libc++; a failure
is a trap, not a named crash, unless an assertion handler is set).

*AGENTS.md:* static libc++ only; silent on modes.

*Before:* none. *Unblocks:* none.

#### Frontend and fork

##### DP-76. What the fork's TTC gives the frontend for case trees [coordinator]

*Questions:* Q-FB1, tail-Q4.

*Decision:* Keep an erasure-only run-time tree in the TTC and translate
it (deleting `Translate/Forced.idr`), or stop building it and keep 0003's
plan (`scTy`, the clause index); and, once the TTC keeps a block's
parent, emit a clause's case block in place as a match region of its
parent?

*Options:* *Q-FB1:* (a) keep and translate it; (b) stop building it (it
is computed and discarded today), 0003's plan. *tail-Q4:* (a) emit in
place, so idr-contify sees only what the compiler makes; (b) as today.

*Evidence:* 17 §6 Q-FB1; 10 §6 NQ-4.

*AGENTS.md:* points one way for Q-FB1: "Do not replace that input with
CExp or runtime case trees". Q-FB1 (a) would need it amended.

*Before:* DP-09, DP-15. *Unblocks:* none.

##### DP-77. Context-sensitive flow as a representation fix [coordinator]

*Questions:* Q-fc-2.

*Decision:* If stage 1 shows the node split's product to be large, is a
flow split by node (context-sensitive: acceptance unchanged, a larger
flow solve) the direction?

*Options:* **A.** Yes. **B.** Another representation, to be found.

*Evidence:* 16 §6 (that state is acceptance-critical, so no budget may
cut it; the growth phase went from 1,093 s to 67 s by four representation
fixes).

*AGENTS.md:* constrains: no budget on an analysis a refusal rests on, so
only a representation.

*Before:* DP-07, DP-33. *Unblocks:* none.

##### DP-78. The Core dump [coordinator]

*Questions:* ft-Q4.

*Decision:* Keep the Core dump (the whole program a second time, 79 MB on
the self compile), streamed, or make the module the one output and move
its readers onto it?

*Options:* **A.** Keep, streamed. **B.** The module only.

*Evidence:* 15 §6 NQ-4 (read by the harness's prelude coverage and one
test).

*AGENTS.md:* "one thing, one representation".

*Before:* none. *Unblocks:* none.

##### DP-79. A refusal in the fork's `Error` [coordinator]

*Questions:* ft-Q5.

*Decision:* Give the fork's `Error` a constructor for the frontend's
refusal, so `TS.inFlight` and the dedupe by printed text go?

*Options:* **A.** Yes. **B.** Keep the side channel.

*Evidence:* 15 §6 NQ-5.

*AGENTS.md:* the fork is ours; it never imports `IdrisMLIR.*`, so the
constructor carries a payload the fork defines.

*Before:* none. *Unblocks:* none.

#### The runtime

##### DP-80. Stack probes on all four targets [coordinator]

*Questions:* oom-4.

*Decision:* Probe the stack on all four targets, the probe size the
target's page, set by the lowering from the target's entry?

*Options:* **A.** Yes. **B.** Rely on bounded frames, with a test of the
claim.

*Evidence:* 12, 18, 19 §6 (no probes anywhere; the guard is 1 MiB; below
it lies the writable alternate signal stack, so a skipped guard corrupts
the handler's stack first; the tools have stack-clash protection on
Linux only, the runtime nowhere).

*AGENTS.md:* "never miscompile silently"; the page size lives only in
the target's entry.

*Before:* none. *Unblocks:* none.

##### DP-81. Test hooks in the shipped runtime [coordinator]

*Questions:* rt-Q2, rt-Q4.

*Decision:* Move the live-cell count to the checked runtime, so shipped
programs neither count every allocation nor read `IDRIS_RT_LIVE`; and
make the test work through the shipped IO buffer instead of a
compiled-in size?

*Options:* *rt-Q2:* (a) move it; (b) keep it. *rt-Q4:* (a) the shipped
buffer; (b) keep the seam.

*Evidence:* 18 §6 N2, N4; 19 §6 (every program run checks
`IDRIS_RT_LIVE`).

*AGENTS.md:* silent.

*Before:* none. *Unblocks:* none.

##### DP-82. snmalloc's config [coordinator]

*Questions:* rt-Q5.

*Decision:* Patch snmalloc upstream for a seed-range hook, or keep our
copy of its standard config with a test comparing it to the pinned one?

*Options:* **A.** The upstream patch. **B.** The copy and its test.

*Evidence:* 18 §6 N5; 20 §6 (snmalloc wants a CLA, so a patch stays a
submission).

*AGENTS.md:* snmalloc is pinned to its latest release.

*Before:* none. *Unblocks:* none.

##### DP-83. Mangling [coordinator]

*Questions:* conv-Q5.

*Decision:* Prefix every program symbol, so none can be a runtime
symbol or `main`?

*Options:* **A.** Yes. **B.** As today.

*Evidence:* 12 §6 NQ5.

*AGENTS.md:* silent.

*Before:* none. *Unblocks:* none.

##### DP-84. Runtime memory work that can wait [coordinator]

*Questions:* oom-7, oom-8, oom-9.

*Decision:* Defer returning the stack's pages after deep recursion, a
pressure signal in the runtime, and shards' limits (a process-wide limit
only; a reactor that drains remote frees before it blocks) until a
program or a shard needs them?

*Options:* **A.** Defer all three. **B.** Plan one now.

*Evidence:* §5.11 ranks them "can wait"; 18 §6 (nothing returns stack
pages; a program is one thread with no reactor; shards are not built,
and only a process-wide limit falls out of today's representation).

*AGENTS.md:* OS calls behind the runtime's platform layer.

*Before:* DP-11. *Unblocks:* none.

## 3. Suggested order (the owner's decision points)

The owner's twenty-one, in the order of section 2.1:

1. **DP-01** A dead crash, a dead divergence, and `exit`. Meaning.
2. **DP-02** The world. Meaning and a contested core shape.
3. **DP-03** The resource tree. Meaning; needs DP-01 and DP-02.
4. **DP-04** The effect system's structure. Settled by the owner's
   ruling; nothing to decide. It sits here because it waits on DP-01 to
   DP-03 and nothing else.
5. **DP-05** The fence around P0's code. Urgent; other agents' work.
6. **DP-06** Main is red: `Positions`. Urgent; needs DP-05.
7. **DP-07** The stage-1 record. Urgent; every measured design waits on
   it.
8. **DP-08** The C++ line. Settled by the owner's ruling; approve the
   skill's wording.
9. **DP-09** P0 and 0003, 0011. Scope; sets most lanes' reach.
10. **DP-10** P0 and 0009. Scope.
11. **DP-11** Out of memory is outside the language. Meaning; quick.
12. **DP-12** Acceptance and the in-place promise. Meaning.
13. **DP-13** The space guarantee, and the order of counting. Promise.
14. **DP-14** The constant-stack promise. Promise; beside DP-13.
15. **DP-15** The match: regions or blocks. Contested core shape.
16. **DP-16** Borrows: regions or lifetimes. Contested core shape;
    needs DP-13.
17. **DP-17** One meaning for ops without a runtime function. Meaning;
    an AGENTS.md amendment is on the table.
18. **DP-18** Crash statuses and sites. Promise.
19. **DP-19** Strict hosts and a memory limit. Promise.
20. **DP-20** Idris's elaborator and its counts. Acceptance.
21. **DP-21** The proof's model and the code. A trust point.

Why this order. The effect system was ruled "extremely high priority",
and its structure is settled (DP-04); only the tree's shape is open, and
that is DP-01 to DP-03, so they come first. The three urgent ones follow
in the same sitting: they block work happening now (section 5) and do
not depend on the effects decisions. DP-08 costs one approval. Then
scope (DP-09, DP-10), which every later answer assumes. Then the rest of
the language's meaning: acceptance and the promises of counting (DP-11
to DP-14), which counting's whole design waits on. Then the two
contested core shapes (DP-15, DP-16), which unblock the most
coordinator decisions after the effects. The last five each touch one
area.

**The dependency graph** (decision → the decisions it unblocks; owner
DPs in bold; generated from section 2's "Unblocks" lines, which agree
with every "Before" line):
- **DP-01** → DP-03, DP-04, DP-18, DP-50, DP-67
- **DP-02** → DP-03, DP-04, DP-38, DP-42, DP-50
- **DP-03** → DP-04, DP-31, DP-38, DP-50
- **DP-04** → DP-31, DP-38, DP-50; lane 02's T1 to T8
- **DP-05** → DP-06, DP-07, DP-22
- **DP-06** → DP-07, DP-22, DP-53
- **DP-07** → DP-24, DP-51, DP-59, DP-60, DP-64, DP-77
- **DP-08** → DP-26, DP-53, DP-73
- **DP-09** → DP-36, DP-40, DP-76
- **DP-10** → DP-39, DP-44, DP-45
- **DP-11** → DP-18, DP-19, DP-33, DP-84
- **DP-12** → DP-13, DP-55, DP-58
- **DP-13** → DP-16, DP-55, DP-56, DP-57
- **DP-14** → DP-38, DP-46, DP-57
- **DP-15** → DP-37, DP-38, DP-46, DP-53, DP-67, DP-76
- **DP-16** → DP-39, DP-60
- **DP-17** → DP-41, DP-42
- DP-22 → DP-23, DP-27, DP-28
- DP-23 → DP-69
- DP-24 → DP-26, DP-51, DP-54
- DP-26 → DP-52
- DP-27 → DP-28
- DP-32 → DP-39
- DP-33 → DP-20 (read with it), DP-52, DP-53, DP-64, DP-67, DP-77
- DP-34 → DP-52, DP-53
- DP-36 → DP-38, DP-40, DP-48, DP-52, DP-65
- DP-37 → DP-53
- DP-38 → DP-54, DP-57, DP-60, DP-61
- DP-39 → DP-47
- DP-40 → DP-48
- DP-42 → DP-43
- DP-51 → DP-52, DP-53, DP-54
- DP-52 → DP-30, DP-50, DP-53, DP-54, DP-64
- DP-55 → DP-58, DP-59, DP-64
- DP-60 → DP-47, DP-61, DP-67
- DP-64 → DP-54, DP-65, DP-68
- DP-69 → DP-42, DP-70, DP-71, DP-72
- DP-18 to DP-21 and every other coordinator DP unblock nothing on this
  agenda.

Pairs to decide side by side: DP-13 and DP-14 (the heap and the stack
halves of what space a program promises); DP-13 and DP-16 (whether
borrows are inferred bears on how they are scoped); DP-06 and DP-53
(DP-06's option A fixes the numbering early); DP-20 and DP-33 (one rule
on counts, inside and outside Idris's elaborator).

## 4. Who resolves what

The owner's delegation of 2026-10-21: the coordinator resolves what
AGENTS.md, strong lane agreement or elegance settles, under "always a
hard cutover, hard culling of the old code, maximally churning toward
the most elegant representation"; the owner keeps the language's
meaning, promises to users, scope between proposals, other agents' work,
and contested core shapes.

### 4.1 The owner's alone (21)

| DP | why it is the owner's | note |
| --- | --- | --- |
| DP-01 | the language's meaning | the effect system waits on it |
| DP-02 | meaning (how IO is ordered) and a contested core shape | the effect system waits on it |
| DP-03 | meaning (what is ordered with what) | the effect system waits on it |
| DP-04 | the owner's ruling | settled: nothing to decide |
| DP-05 | other agents' work | urgent; hist-Q5 has the owner's standing instruction behind it |
| DP-06 | other agents' work (the agent's commit) | urgent |
| DP-07 | other agents' work (who runs); scope (it replaces 0001's record rule) | urgent; the measure, the assertions and the profiler are then the coordinator's |
| DP-08 | the owner's ruling; the skill's wording | settled: approve the wording |
| DP-09 | scope between proposals (0003, 0011) | |
| DP-10 | scope between proposals (0009) | |
| DP-11 | meaning | quick: lanes 02, 16, 18 agree, and the code already does it |
| DP-12 | meaning (acceptance) | AGENTS.md constrains it strongly |
| DP-13 | a promise to users (space) | |
| DP-14 | a promise to users (stack) | |
| DP-15 | a contested core shape | §5.9's design and wave 2's 27 region-reading files pull apart |
| DP-16 | a contested core shape | no lane recommends one form |
| DP-17 | the meaning of primitives; an AGENTS.md amendment is on the table | AGENTS.md as written gives option A |
| DP-18 | a promise to users (exit statuses) | the ABI half is then the coordinator's |
| DP-19 | promises to users (strict hosts, a limit) | the owner's 1445d894 points one way for oom-5 |
| DP-20 | which programs Idris accepts | |
| DP-21 | a trust point, which only the owner accepts | |

### 4.2 The coordinator can resolve (63), with the reason

*Settled by AGENTS.md as written (13):*
- **DP-22** a change "is done when it builds and passes on all four"
  targets; the invariant set has lanes 19, 20 and 21 behind it.
- **DP-23** the Idris side "compiles under two hosts, always", and a
  hard cutover allows no shim (lanes 14, 15, 17).
- **DP-30** "Every patch has a written plan to upstream it ...; sending
  it is separate work."
- **DP-32** "Quantity 1 is a type ... which every transformation must
  keep"; an amendment would be the owner's.
- **DP-33** the budget paragraph; every lane that looked agrees; only
  canon-Q2's multiple is a number to choose.
- **DP-40** "the Idris side ... decides representations".
- **DP-54** the patch-retirement rule settles hist-Q3 once QA3 is
  chosen; lanes 05, 09, 20 hold the evidence for QA3.
- **DP-55** "linearity is a performance property" settles the run-time
  fallback; R1 against R2 is technical, after DP-12 and DP-13.
- **DP-60** the grade check after every pass is AGENTS.md's; a split by
  build is excluded by the driver's own principle (13 §6); nesting is
  the elegant remainder.
- **DP-63** "Per-target cases elsewhere are bugs."
- **DP-76** "Do not replace that input with CExp or runtime case trees"
  settles Q-FB1; tail-Q4 follows DP-09 and DP-15.
- **DP-77** no budget on an acceptance analysis leaves only a
  representation.
- **DP-80** "never miscompile silently"; the page size from the target's
  entry.

*Settled by strong lane agreement (18):*
- **DP-24** lanes 20 and 21; §4's order already asks for the
  measurement (wording in AGENTS.md, if wanted, is the owner's).
- **DP-25** lane 04's evidence; reflection arrives with the pin.
- **DP-26** lanes 05, 06, 20: what transfers is shape, not code.
- **DP-27** §1's "every rename it needs"; a hard cutover keeps the test
  API open too.
- **DP-34** the code already promises and tests it (lanes 13, 19).
- **DP-36** lanes 01, 06, 07, 08, 11, 15, 17: the IR already carries
  effects and grades, verified; P0's goal.
- **DP-37** lanes 01, 03, 04, 07, 08: half true already; the rest
  deletes walks.
- **DP-38** lanes 03, 05, 08, 10: `func.call` cannot carry the facts.
- **DP-41** six lanes: the tree is arith's already.
- **DP-42** lanes 03, 12, 18: the runtime already holds the enums.
- **DP-51** lanes 05, 07, 11, 20: P2 has no client; per function where
  the readers are; §4's order.
- **DP-52** lanes 05, 06, 09: one graph; the optimizer its one dynamic
  client.
- **DP-53** lanes 05, 06, 07, 21: one dense representation; §9 D2.
- **DP-56** the rule today, with four essential exceptions (08 §6).
- **DP-59** lanes 08 and 18 on threads; rt-Q1 waits on a measurement.
- **DP-64** lanes 06, 09, 15, 16; a measurement decides Q-O4.
- **DP-66** lane 04's evidence.
- **DP-74** lane 13; §5.5 D6.

*Settled by elegance under a hard cutover (32):*
- **DP-28** tests check behaviour: program tests over fixtures.
- **DP-29** housekeeping.
- **DP-31** a row of the effect source (DP-04); one allocation rule
  for every op that makes a cell.
- **DP-35** the rule exists; the test needs a seam that is not a
  user-facing option.
- **DP-39** the skill's "no interface where the type fixes the
  implementation"; a phase as a case of the data.
- **DP-43** values and memory at different levels.
- **DP-44** one op per semantics.
- **DP-45** one form for one thing (an indexing map in a tabulate).
- **DP-46** make the impossible frame unrepresentable.
- **DP-47** declare, don't write.
- **DP-48** the decision written into the types.
- **DP-49** precision against plan size, inside one pass.
- **DP-50** one summary computed once (its bits are DP-04's).
- **DP-57** an order inside counting.
- **DP-58** counting's facts end at the `idr` level.
- **DP-61** the pass manager does the parallelism; §9 D2 allows the
  alternative, named.
- **DP-62** upstream first.
- **DP-65** one fact, one place; no context lock.
- **DP-67** a bound per pass instead of a fixpoint driver.
- **DP-68** hard culling, or the stage that makes the patterns live.
- **DP-69** one tool, one record set.
- **DP-70** follows DP-69.
- **DP-71** no generated file restamped by hand.
- **DP-72** no copied list.
- **DP-73** DP-08's ruling and §5.5's measurement.
- **DP-75** a measured choice.
- **DP-78** one thing, one representation.
- **DP-79** a typed refusal, not a printed one.
- **DP-81** no test protocol in shipped programs.
- **DP-82** the CLA makes an upstream patch a submission at best.
- **DP-83** a total separation of names.
- **DP-84** the lane's own ranking; nothing needs them yet.

## 5. Urgent: what cannot wait for the rest

1. **DP-05, the fence.** The parallel agent is changing counting,
   exclusivity, the stack inference and the trait layer on main while
   wave 2's lanes plan the same code: nine commits in eighteen hours,
   seven of them in audited subsystems (21 §6.1). Nothing in §9 says
   whether D4 binds it. Until this is answered, every lane's design can
   be overtaken by a commit, and the plan must rebase on each push
   (21 §5.5).
2. **DP-06, main is red.** `make test` has been 403/480 since 101edbc5,
   against 470/480 at e96bb991 (51a4771b's record); lane 21 calls it a
   measured miscompile path (21 P-1). Every stage-1 run starts from
   counting that is wrong on 67 programs, and P0's gates (DP-22) need a
   green starting commit, which today is e96bb991 only (21 §5.5). It
   needs DP-05 first: every fix is a commit.
3. **DP-07, the stage-1 record.** No S3 run has left a record; the walls
   live in commit messages, measured four different ways (21 P-17,
   P-18). P0's designs need one complete baseline at a fixed commit
   before any of them can be compared (21 §5.2). If S3 goes on under
   DP-05's option B, each of its runs needs this record.

Urgent for the plan, by the owner's ruling: **DP-01 to DP-03.** The
centralized effect system is "extremely high priority" and its design
agent is already writing `audits/p0/design/effects.md`; the tree's
shape it must encode is exactly these three decisions, so the design
cannot finish without them.

Not blocking work now, but blocking the plan (§7): DP-08's wording
(lane 20 L6: the C++ rules before the C++ is churned); DP-09 (P0's
scope); DP-02 with the coordinator's DP-32 and DP-39 (lane 20 L3: the
world, the grade and the data table decided before any lane writes C++
against them). The coordinator should also rebase the plan on
origin/main, by commit, once DP-06 is answered (21 §5.5).

Lane 5.11 ranked oom-1 to oom-4 "urgent" because they shape P0's runtime
C++ and its instrumentation; none blocks work today. oom-1 is DP-11 (a
quick confirmation), oom-2 is in DP-33, oom-3 is in DP-07, and oom-4 is
DP-80.

## 6. The count check

A mechanical check, run on this file as written (*measured*):
- **Questions in §8:** every bullet of `proposals/0000-mlir-native.md`
  §8 (lines 10804 to 11614) whose bold text opens with an ID, less the
  one heading bullet "Variants: Q-llvm-4 and cxx-Q2 conflict" (its two
  questions are their own bullets): **158** IDs, all distinct.
- **Placed here:** every ID on a `*Questions:*` line of the 84 decision
  points: **158** IDs, all distinct.
- **The comparison:** no §8 ID is missing here; no ID is placed twice;
  no ID is placed that §8 does not hold. Every question in §8 is under
  exactly one decision point.
- **The split:** the owner's 21 decision points hold 46 of the IDs (two
  of those points, DP-04 and DP-08, settled by the owner's rulings of
  2026-10-21); the coordinator's 63 hold the other 112.
- **Dependencies:** every "Unblocks" entry has the matching "Before"
  entry and the reverse, except the side-by-side note between DP-13 and
  DP-14, which is a pairing, not an order.
