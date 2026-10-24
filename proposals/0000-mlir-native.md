<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0: MLIR-native, modern C++, the cutover before everything

**Status (2026-10-23):** being cut over, on main. The owner approved the
plan on 2026-10-21 (D4) and the cutover started that night from
28ef777e. The research is done and archived (§0). The owner's rulings
are §2; the coordinator's decisions, each listed for the owner's review,
are §3; what is left for the owner is §4. Recheck 5
(`audits/p0/verify/recheck5/`) measures what remains.

**Goal.** One total, hard-cutover refactor of the compiler's C++ and
MLIR side and of the Idris side it feeds, so that every fact is held
once, in the representation that makes its misuse unwritable:
- **Upstream first**: upstream MLIR as it is; then upstream patched
  (`upstream/<bug>/`, AGENTS.md); then our own solver, named as such, in
  one honest solver layer whose composition and threading are explicit.
- **One source, compile-time C++**: every static fact (ops, types,
  grades, effects, each op's rules and laws, the runtime ABI, the
  pipeline, refusal rules) is
  declared once, in the dialect's Idris specification, whose invariants
  Idris's types prove; our TableGen is generated from it, 100% (D15,
  D16), and every consumer is generated as compile-time constants,
  checked when the compiler is built, dispatched by templates and
  concepts, monomorphized (D7).
- **One effect system**, defined and monomorphized in one place, so no
  two readers of an effect can disagree (D9).
- **Idris does types, MLIR does programs**: the Idris side is
  representation (checking, elaboration, representation decisions, the
  specification, the libraries), and every optimization is C++ over
  MLIR (D107, D109).
- **The `idr` dialect redesigned whole**: every op, type, attribute,
  effect and name, merged where two ops are one op, split where one op
  is two (D9, §5.3).
- **No rederivation chains**: a fact is computed once, kept in a type or
  a verified property or a cached analysis, and read after that.
- **Hard cutover and hard culling** in every step: no shim, alias, dual
  path or "remove later".

## 0. How this document works

- **It is the one decision point.** Everything settled is one of: an
  owner's ruling (§2, dated), a coordinator decision made under the
  owner's delegation (§3, with its reason, open to the owner's review),
  or an open decision for the owner (§4). The rest of the document (the
  target, the deletions, the stages) follows from those, and changes
  when they do.
- **The evidence lives in `audits/p0/`**, and this document cites it:
  - `wave1/`: the eleven research lanes (`5.1-mlir-analysis.md` to
    `5.11-oom.md`), the codebase brief and the walls history
    (`00-brief.md`), and the register of all 158 questions
    (`questions.md`). In every other document, "§5.N" means
    `wave1/5.N-*.md`, "P0 §2" and "P0 §3" mean `wave1/00-brief.md`, and
    a question ID (QA1, ods-Q1, hist-Q3, ...) resolves in
    `wave1/questions.md`.
  - `01-*.md` to `21-*.md`: wave 2, each subsystem of our code read
    against the research (`README.md` lists them).
  - `synthesis/`: one synthesis per cluster (A the dialect's surface, B
    the analyses and the solver layer, C memory and the back end, D the
    Idris side, E how P0 is carried out), F the decision agenda (the 158
    questions as 84 decision points, DP-01 to DP-84), G the
    coordinator's drafted decisions.
  - `verify/`: the verification swarm, twenty lanes (`L01-*.md` to
    `L20-*.md`) that read every ruling against the code, the adversarial
    review (`review.md`), and the coordinator's queue of the owner's
    questions with the ruling that settled each (`status.md`). A lane
    cited as "L05 §2.3" is `verify/L05-*.md`.
  - `design/`: the effect system (`effects.md`, its machinery;
    `effect-vocabulary.md`, its tree, names and lowering;
    `typed-effects.md`, rows on ops), the specification and its generator
    (`one-source.md`), matches, join points and counting
    (`match-and-counting.md`), the elaborator's counts
    (`elaborator-counts.md`), lifetimes (`lifetimes/`: `constraints.md`,
    `static-handles.md`, `prior-art.md`, and `lowering.md`, D93's design),
    the e-graph (`egraph.md`, whose two tiers D85 reversed;
    `egraph-full/`: `workloads.md`, `unknowns.md`, `payoffs.md` and
    `speed.md`, the evidence D98 to D108 rest on; `effects.md` (D103 on
    real IR, C150 to C152), `synthesis.md` (C155) and
    `machine-prototype.md` (C149); `mlir-form.md`, the narrow e-graph's
    MLIR form under D106 and D107, settled by C153; `one-engine.md`,
    `sparse-library.md` and `machine.md`, kept by D107 as the record of
    the route not taken), the measured causes of every slowdown
    (`perf-sources.md`), and the compile-time C++ architecture
    (`compile-time-cpp.md`, re-based by C121).
- **Claims are marked by their ground** (proposals/README.md): *read*,
  *measured*, *recalled*, *conjecture*, *decision*.
- **AGENTS.md is kept whole.** In particular: grades in types, verified
  after every pass, never in a discardable attribute; a budget never
  rejects a program; acceptance is a property of the program, never of
  the optimizer; four targets and nothing per-target outside the
  target's entry; static linking; an upstream bug fixed upstream; the
  Idris side compiles under both hosts; tests check behaviour.

## 1. What the research found

Wave 1 read MLIR, LLVM, Modular, the C++26 draft at our pin, CIRCT,
IREE, MLton, Koka, Lean and the library; wave 2 read every subsystem of
ours against it; six syntheses and a decision agenda distilled it.
Nothing in waves 1 and 2 was built or run: every cost below is read or
conjecture unless it names the parallel agent's measurement.

**One fact, held many times, the copies disagreeing.** "Does IO" is held
four ways that do not match (a trait, a world operand, an effect, the
function summary's own reading; synthesis A §1). "The result is the
operand" six ways. Erasure is decided by five readers with different
defaults (D §2.2). An instance's identity lives in five structures (D
§1). Tail position is decided in four places (C §1). Whether an operand
is consumed is read five ways, and where a value dies three (C §1). A
function's effect summary ignores its ops' effects, so `exit` claims to
return (A §4 B1, B2).

**Facts thrown away, then rebuilt.** The fork computes facts and drops
them at the TTC; the frontend guesses seven of them back, and one guess
refuses valid programs (D §2.1, §4 #1). The call graph is rebuilt up to
seven times per compile (B §1). "Gives back an argument" is solved by
the optimizer, dropped, and solved again on the lowered module (B §1).

**Whole-program state per value is the shape of every memory wall.**
The 627 GB was mostly two container choices paid twice per state in
upstream's solver, about 2.9 KB for a one-bit fact, cut about 15× by a
small upstream patch (§5.1 A4). What left upstream's framework was never
per-value dataflow: exclusivity is a gated marking, Borrows a marking,
frames' plan no solve at all (B §1). The next walls are the same shape:
Ranges in idr-narrow, Returned on the lowered module, Borrows (B §4).

**Static facts paid for at run time.** Uniqueness is a C++ branch in
two lowering patterns, not an op that folds; an exclusive drop still
reads the count; every `inc`/`dec` tests for NULL and the odd bit though
the type says what the word is; every crash exits with status 1 (C §1,
§4).

**Static things built per function; the context mutated on workers.**
The parallel agent's sampling of both suites (*measured*,
`audits/flamegraph-2026-10-21.md` on origin, 51a4771b): defunctionalization
builds and freezes a pattern set per function, about 11% of the dialect
suite's sampled CPU, inside a per-function conversion step that took 70%
(`design/perf-sources.md` C2); lock slow paths are about a fifth of the
reduced corpus (by symbol, MLIR's per-item diagnostic and
pass-instrumentation mutexes rather than the context's type locks:
perf-sources, unconfirmed).
Its stage-1 samples found half of idr-rc-grades in ancestor walks and a
quarter in block renumbering (101edbc5), workers queued on the context's
write lock (98c6315c), 75 million attempts of patterns rooted at any op
(3a96c407), and a table rebuilt per declaration (73bba53f).

**Acceptance leaks into the optimizer.** The in-place promise binds only
where reuse happened to recycle a cell, so skipping an optimization can
remove a refusal or add one (C §4 #1), against AGENTS.md.

**What "undo the damage of replacing upstream" became.** Four jobs, not
a revert (B §1): patch upstream's state storage and measure it, the step
history skipped; keep upstream's framework where a fact is per value
inside one function (idr-constants already is, at stage-1 scale); use
far more of upstream's non-solver machinery (the analysis manager's
caching, `CallOpInterface` and `scc_iterator`, actions, SCCP's rewrite,
`OperationEquivalence`); put what upstream has no mechanism for into one
solver layer of shared, concept-constrained types.

**How it went wrong before** (E §1, lane 20). Upstream code was adopted
with no stage-1 test (595ed341) and dropped with no patch tried
(ffa91113, 16005000). Four waves landed type-checked but never run
(10-14 to 10-18); the full suite has not been green since 10-14. There
is no stage-1 baseline: the walls live in commit messages, measured four
different ways (E §4 #2).

**State of main.** The parallel agent's 101edbc5 broke 67 programs;
its 0be4e660 and 1e1907ab fixed them (*measured* by the agent: `make
test` back at its standing 470/480). It has stopped committing, and
none of its work binds P0; its tracing is the evidence for P0's
performance design (D17).

## 2. The owner's rulings

Dated, in the owner's words where quoted. Each binds every section
below.

- **D1** (2026-10-21). P0 comes before everything else in the queue.
- **D2** (2026-10-21). Our own solvers are allowed where upstream cannot
  do the job: "let's just be honest, and refactor it out into its own
  code where we can better understand how they compose and are
  threaded."
- **D3** (2026-10-21). Research before code: wave 1 outside our code,
  then wave 2 over it, each lane reading the representation-first skill
  and AGENTS.md in full. Done.
- **D4** (2026-10-21). No code until the whole plan is approved.
  *Met* (2026-10-21, 19:56 CDT): "i want you to personally update the
  entire verificatino swarm to BE the swarm cutover. then we'll start it
  tonight." The packet was rewritten as the cutover's, and the cutover
  started from 28ef777e (20:10 CDT); C153 was approved with the plan.
- **D5** (2026-10-21). The lens: representation first. "This document
  outlines the philosophy and it's extremely important": the skill's
  source document is the bar every finding and design is judged by.
- **D6** (2026-10-21). Delegation: "try to resolve as many questions of
  your own, it should always be a hard cutover, hard culling of the old
  code, maximally churning it to get the maximally elegant
  representation." The coordinator resolves what AGENTS.md, strong lane
  agreement or elegance settles (§3); the owner keeps the language's
  meaning, promises to users, scope between proposals, other agents'
  work, and contested core shapes (§4).
- **D7** (2026-10-21). Templates and concepts, and maximal compile-time
  C++: "I'm serious about modernizing our C++ this time, and culling all
  the polymorphic ladders"; "i cannot stress this enough, heavy use of
  templates and concepts pls"; "we should push on this maximally insane
  compile time c++ requirement. i will not accept any plan that does
  anything less than this." Our own C++ is concept-constrained templates
  by default: callbacks are template parameters, a ladder over our own
  types is a concept-constrained overload set or one fold over a closed
  sum, MLIR op interfaces stay only where the op set is open, and a
  concept may read ODS facts (trait or interface membership) but never
  list ops. Every fact knowable when the compiler is built is a
  compile-time constant, generated from the one source (since D16, the
  dialect's Idris specification, through the TableGen it generates) and
  checked by `static_assert`/`consteval`; runtime dispatch, runtime-built tables,
  string compares and hash lookups of static facts survive only where
  MLIR's open op set forces them, each one listed and justified (§5.2).
  Settles Q1, Q-M3, Q-llvm-1, cxx-Q1 (DP-08). The skill's new wording,
  "never a ladder, and never a concept that lists ops", was approved by
  D47 (corrected 2026-10-21, L06).
- **D8** (2026-10-21). The Idris side is in scope: "if we need to
  heavily refactor our idris code, representation first, so be it",
  type-driven, within the subset both hosts compile.
- **D9** (2026-10-21). One centralized effect system, "extremely high
  priority ... so there's never downstream disagreement about this ever
  again ... so it can all be defined and monomorphized in a single
  place" (§5.1). Settles the effect system's structure (DP-04); its
  tree's shape waits on DP-01 to DP-03. And the dialect redesigned
  whole: "if two ops are secretly the same with slightly different
  effects, let's take advantage of pushing hard on the representation."
- **D10** (2026-10-21). A hard ban, now in AGENTS.md: "NO FACT KNOWN
  STATICALLY, RIGHT NOW OR IN PRINCIPLE, MAY EVER BE PAID FOR AT
  RUNTIME", at the compiler's run time or a compiled program's; a fact an
  earlier stage knew or could have kept counts as known. AGENTS.md lists
  this audit's evidence of what never to do. Every section below is held
  to it.
- **D11** (2026-10-21). Decisions are settled one at a time, each with
  its full context, before the next is raised: "i cannot handle multiple
  issues at once, human must have full context for each issue before
  continuing."
- **D12** (2026-10-21). A strict subset, never a contradiction: "we
  already decided that we should support a strict SUBSET of upstream
  idris. but that doesn't mean we should ever support CONTRADICTORY flags
  or default pragma behaviors." The compiler may refuse a program upstream
  accepts (`unsupported`); a program it accepts means what upstream's
  language says, and every flag, pragma and default (`partial`,
  `covering`, `total`, `%default`, `--total`) means what it means
  upstream. What upstream's optimizer happens to do is not its language
  (AGENTS.md: there is no oracle). Refined the same day: "just because
  upstream may miscompile it, doesn't mean that we should. upstream is not
  the ORACLE, it's the philosophy ... we are still an idris 2 compiler. we
  may even be MORE CORRECT than upstream. but we must never change the
  meaning of upstream concepts." Where upstream's compiler departs from
  its own language, we keep the language.
- **D13** (2026-10-21; DP-01's first part: ods-Q1, DD-Q2). Eager
  evaluation is the meaning: upstream documents it ("arguments to
  functions are evaluated before the function itself",
  `docs/source/tutorial/typesfuns.rst:704-705`; the reason,
  `docs/source/faq/faq.rst:134-150`). An unused computation in partial
  code is evaluated, so its crash or endless loop happens; deleting it
  would give unused values a lazy meaning the language lacks (upstream's
  inliner does delete an unused pure `let`, `src/Compiler/Inline.idr:200-206`,
  an optimizer behaviour, not a promise). Only totality, as upstream
  defines it, licenses deletion: a function proved `total` carries no
  divergence effect, may be deleted when unused, and is lowered with
  `mustprogress`. A statically certain crash (a constant zero divisor) is
  compiled as a plain crash where evaluation reaches it, with no run-time
  test (D10). Making totality mandatory would be a narrower subset, not a
  contradiction, and is not taken: it would refuse most real programs.
- **D14** (2026-10-21; DP-01's second part: eff-Q2). `exit` is its own
  effect: an IO action that ends the process normally and never returns,
  as upstream's `exitWith : HasIO io => ExitCode -> io a` says ("Exit the
  program normally", `libs/base/System.idr:307-310`). Not a crash (a
  crash is partial code failing) and not a divergence (exit finishes, and
  a `total` `main` may call it). The effect system names "ends the
  process" under the IO resource, in its one source; `idr.io.exit` becomes
  a terminator with no world result; a function's summary carries a "may
  end the process" bit derived from its ops, so a function that may exit
  is never lowered `willreturn` and the call to exit is `noreturn` (the
  summary that today says an exiting function returns, lane 02 §3.7, goes
  by construction). Its status stays distinct from a crash's (DP-18).
- **D15** (2026-10-21). Any higher-level specification of ours is Idris:
  "our higher level spec should not be in a python dsl, opdsl, etc... it
  should just be idris. obviously. we have chez so we can always
  bootstrap. always idris." A spec above TableGen, or a generator or DSL
  of ours, is written in Idris (in the subset both hosts compile), never
  in Python, YAML, OpDSL or a language of its own; stock Idris on Chez
  builds it first, so the build always starts.
- **D16** (2026-10-21). Our TableGen is 100% generated by Idris: "tablegen
  FULLY 100% generated by idris is the right move. i approve. it must be
  an extremely hard cull and cutover." The dialect's one source is a typed
  Idris specification (its ops, types, attributes, effects, rules and
  tables, invariants proven by Idris's types); every `.td` file under
  `foreign/idr` becomes its output, none written or edited by hand, none
  kept beside it. Upstream's own `.td` files stay upstream's. How the
  specification is shaped and built is `audits/p0/design/one-source.md`'s
  (written; corrected 2026-10-21, L03).
- **D17** (2026-10-21; DP-05: perf-Q1, Q2). No fence around the parallel
  agent: it has stopped committing, and P0 may undo any of its work. Its
  commits were tactical fixes for speed and type-checking with no
  architectural design, so none binds P0: `Positions` and `Idr_Decides`
  (101edbc5, 0be4e660), exclusivity's graph (ffa91113, e96bb991), the
  stack marking (b8301ebe), frames' answer sum (16005000) and the rest are
  kept, rewritten or deleted on P0's merits alone. Its tracing is the
  evidence base for P0's performance and monomorphization design ("deeply
  inspire all your performance monomorphization work from his tracing
  work"): `audits/flamegraph-2026-10-21.md` and the samples in its commit
  messages, distilled in `audits/p0/design/perf-sources.md`. DP-06
  (`Positions`) leaves the owner's list: counting's redesign decides it.
  hist-Q5 (reversals) is AGENTS.md's: a recorded design is reversed only by
  a dated ruling of the owner.
- **D18** (2026-10-21; bears on DP-15). The lossless representation at
  every point: "we always always want to choose the data structure that
  prevents the loss of information we already had statically ... we
  should be using the lossless representation at any point. but maybe
  there may be real performance reasons we want to use blocks between
  them." A representation that loses a fact already known is used only
  for a stated performance reason, and only after that fact is carried
  elsewhere. The match's form after defunctionalization stays open:
  "linearity and reference counting copy optimizations are going to steer
  most of our decision making here ... because this is the new thing that
  we bring against mlton and koka." And foundational: "mlton has a gc, we
  have rc with proved rc copy optimizations, which i want to exploit more
  heavily. this needs to be foundational in making this decision." MLton's
  flat CFG was chosen under a collector, where no ownership, scope or
  uniqueness fact matters at run time; ours is chosen for how much it lets
  the compiler prove about counting (exclusive values, in-place updates,
  reuse, dups and drops elided), now and as those proofs grow. Join points (a third shape, between
  regions and blocks) and the parser-combinator blowup (bindGrammar,
  16005000) are being investigated in `audits/p0/design/match-and-counting.md`.
- **D19** (2026-10-21; DP-15: Q-O1). Regions, join points, blocks only at
  the lowering, a hard cutover, never reversed until something strictly
  better exists: "approved. push hard on this, this is a hard hard
  cutover. and we should document this in a way such that this is never
  reversed until we come up with something strictly better."
  - *Regions are the base*: a match is a region per case, each a
    single-entry, single-exit scope rejoining at the op's results, from
    the frontend to the lowering (upstream's `scf` shape).
  - *Join points*: a linear, non-escaping continuation called in tail
    position, and a local tail call contification finds, is a join point:
    a named continuation local to its function, jumped to with typed
    arguments (grades and reuse tokens among them), never an allocated
    closure; a recursive join point is a loop. Their encoding in MLIR,
    keeping upstream's interfaces, is `design/match-and-counting.md`'s.
  - *Blocks only at the lowering*, through upstream's `convert-scf-to-cf`;
    LLVM does the block-level work.
  - *Why*: the representation is chosen for what it lets the compiler
    prove about counting (D18). Regions keep the scopes placement, reuse
    within a case, the in-place promise and stack cells read; join points
    add what regions alone cannot (a shared continuation without copying
    it, a linear tail continuation never allocated, reuse across a rejoin
    through a token argument); blocks would drop facts our proofs read,
    which MLton, under a collector, could afford to drop.
  - *Strictly better*, the only ground for reversal: a form that keeps
    every fact this one keeps, proves at least every counting decision
    this one proves and proves more, shown on evidence and accepted by a
    dated ruling of the owner.
- **D20** (2026-10-21; DP-02: DD-Q3). After the frontend, IO is ordered
  by declared effects alone, and the world value is gone: "we have to do
  it. obviously A", a total, full cutover. The frontend may keep Idris's
  world inside Core and drops it at Emit; no world type, `world.new`, or
  world operand survives in the IR. The derived effect row's `io` atom is
  IO's typed carrier: it is exact where the world was an upper bound, and
  it covers a trusted library's forged world (`audits/p0/design/typed-effects.md`
  §4, §5). Effects live in our types, the Idris specification's (D16); in
  the IR a computation's row lives on its op (`idr.func`, `idr.call`),
  never in an MLIR value type, since none of our effects changes a calling
  convention. Deleted by the cutover: the world type, `world.new`, world
  operands on 44 op definitions, the seven lowering special cases; the
  `tabulate`/`tabulate_io` and `array.update`/`element.update` pairs
  merge; MoveOut and the ten world-ordered memory ops read effects.
- **D21** (2026-10-21; DP-03's first part: ods-Q3). A crash is ordered with
  IO only: the heap is a sibling of the crash in the resource tree, so
  heap reads and writes may move across a crash or a guard, while
  crashes, `exit` and output stay ordered among themselves (the runtime
  flushes output before a crash's message, `runtime/Io/Ending.cpp:64-71`).
  After a crash nothing observes the heap; a heap write reaches output
  only through an IO op, itself ordered. The hazard of an access hoisted
  above the check that makes it valid is held by data dependence, not by
  effects: a guard returns its operand refined and the total op reads
  that value (lane 03 §3).
- **D22** (2026-10-21; DP-03's second part: eff-Q1). A function's effect
  summary covers every state a caller must order with (memory its
  arguments reach, reference counts, memo state, IO, crashes, divergence,
  ending the process), derived from its ops, never written by hand,
  checked per function. Forced by soundness under D21: with the heap a
  sibling of the crash, a summary of only {io, crash, diverge} would hide
  a callee's heap and memo effects (lane 02 §3.7; `typed-effects.md` §4).
  The effect system's vocabulary, every resource, effect and atom, is
  being designed and named whole before it is settled (D23 below fixes
  how failure enters it) ("now that we have
  a proper effect system, we need to think about it and deeply think about
  and rename all the effects properly"): `audits/p0/design/effect-vocabulary.md`.
- **D23** (2026-10-21; DP-11: oom-1). Running out of memory is outside
  the language, a named crash of the machine as a stack overflow is
  (since D32 compiled code cannot exhaust the stack),
  never a value or an effect in the types. The program ends with a named
  out-of-memory ending, output flushed, nothing allocated on the way
  down; the language promises nothing about which allocation it happens
  at. Allocations are not ordered with IO or with each other for the sake
  of failing, so they may be deleted, sunk, turned into reuse or stack
  cells. Where new memory enters the arena is still marked: an "acquires
  memory" effect (MLIR's `Allocate` on the arena), the owner's point that
  limits and out-of-memory need it ("any new allocation of new memory
  into the snmalloc arena"), deletable when unused, carrying no crash.
  Memory limits stay a runtime policy at those places (DP-19).
- **D24** (2026-10-21; DP-12: count-Q1, own-Q2). The in-place promise is
  a rule read off the program before counting, and counting is bound to
  honour it: "A." A type of kind `in_place` (today `Linear.List.LList`,
  `Linear.Nat.LNat`, by the registry's `InPlaceType`) promises its values
  are rebuilt in place with no run-time test. A function that takes apart
  a quantity-1 parameter of such a type and builds a value of that type
  from it rebuilds it; that is decided from the program as the frontend
  wrote it, never from what an optimization did.
  - *The three quantities*: an erased index or proof (quantity 0) is no
    value and never a cell, so the rule never reads it; linearity
    (quantity 1) is what makes a parameter subject to the rule, a fact
    about the callee; exclusivity (`!idr.excl<T>`, proved) is the
    obligation at every call, a fact about the caller's program, since a
    linear binder does not imply unique ownership.
  - *Counting honours it*: reuse must recycle the rebuilt cell, the stack
    inference may not take that parameter, and no placement may add a dup
    of it; a pass that would break the promise is a bug, not a refusal.
  - *The refusal*: a call the exclusivity analysis cannot prove exclusive
    is `unsupported (uniqueness)` at the call, the analysis exact against
    the rule, and a test pins the rule's boundary
    (`tests/uniqueness-shared-rebuild` and its `near/`).
  - *Deleted*: `idr-demand` deriving the promise from `idr.cell.recycle`
    and the take's token (`Demand.cpp`'s `rebuilt`), the chain where
    skipping a reuse action, a frame value or `sinkConsumers`' dup changed
    the verdict (08 §6.1 NQ1).
- **D25** (2026-10-21; `design/match-and-counting.md` §5.3, §12). Nested
  jumps to a join point go through upstream's early exit, carried as a
  patch now: "obviously carry the PR as a patch." Upstream's PR #166688
  ("[MLIR] Introduce support for early exits", open, last updated
  2026-07-22; 3,965 lines added over 44 files, about 1,700 outside tests
  (corrected 2026-10-21, L09), in `Dominance.cpp`, the control-flow
  interfaces, the dataflow analyses, the inliner and `scf`) is backported
  as `upstream/<NN>-early-exits/llvm.patch` (corrected 2026-10-21, L09)
  with its tests, a PINS.md entry and its plan, and goes when the pin
  passes the merge.
  - *The encoding*: the PR's is ours, a token defined by the target op.
    `idr.join` implements `HasBreakingControlFlowOpInterface` and receives
    jumps; `idr.match` and `idr.match_lit` carry the trait
    `PropagateControlFlowBreak` (a trait, not an interface: corrected
    2026-10-21, L09) and let them through; `idr.jump %tok(...)`
    terminates with its target in its `!idr.cont<...>` token. Upstream's
    SCCP and dead code read nested jumps as edges, post-dominance changes
    and the inliner refuses a region an exit escapes (corrected
    2026-10-21, L09);
    no control-flow reading of ours stands beside them, and the
    conservative modelling of §5.4 and idr-lower's own lowering of
    nested jumps are never built.
  - *Always carry the patch*: "we always always carry the patch,
    ESPECIALLY if it's meant to be upstreamed or coming for free in a
    future release." A change upstream we need, a fix or a feature, is
    carried, upstream's own form first; AGENTS.md's patch rule says so.
  - *Fast-forward every dependency*: "as part of this change, we should
    fast forward ALL of our deps to latest as well, llvm AND MLIR. good
    to do this every week or so." Main for llvm-project, modular and
    Idris 2, the latest release for the rest (CMake, Ninja, GMP,
    simdutf, fast_float, snmalloc, Chez), every carried patch rebased or
    dropped where upstream now has it, the backport applied to the new
    pin; then again about weekly.
  - *If upstream merges another form*, ours moves to it; if it rejects
    the PR, which encoding stands is a new ruling, on evidence.
- **D26** (2026-10-21; DP-13's first part: rc-Q3). Compiled programs are
  frame-limited, stated as a property of every compiled program: "yes.
  let's do B." Garbage-free is out because no reuse can keep it
  (Lorenzen and Leijen, ICFP 2022, §4), and none-stated bounds nothing.
  Stated for this compiler, not copied from the paper: "we DON'T use a
  gc, and we DON'T allow mutation of cyclic data structures. we use an
  RC. i don't want to cargo cult any properties from that paper that
  only exist to address those edge cases." The statement, approved
  ("yes"):
  - *The promise*: at every allocation, each heap cell is either still
    reachable from what the program will use, or held by an active call
    (a native frame or a heap continuation frame of `idr-frames`), and
    each call holds at most a fixed number of bytes it no longer needs,
    computed by the compiler for each function from its types.
  - *A call may hold*: reuse tokens of statically sized cells awaiting
    their construction; the shells of its stack cells, whose fields are
    released at count 0; values borrowed past their last use whose type
    bounds everything they reach (a pair of words, not a list).
  - *Never*: a dead dynamically sized cell (array, string, bignum) held
    past an allocation; a borrowed argument no active call needs after
    the call (D73), unless its type bounds everything it reaches (so an
    argument whose binder in the caller is linear is passed owned, read
    off its type); any structure held past its last use.
  - *Outside it*: the allocator's overhead and spare room inside a live
    cell; persistent static data, which is live; a saturated count, as
    running out of memory is (D23).
  - *Not carried over from the paper*, each absent here: its cycle-free
    qualifier (`idr-knots` refuses every cycle, so every cell is freed),
    thread-shared counts, the run-time uniqueness test as part of space,
    the lambda rule (closures are constructors after
    defunctionalization), an uncomputed constant (sizes are static),
    safety for space, an abstract evaluation context.
  The order of counting and the extent of borrowing (DP-13's other
  parts) follow from it.
- **D27** (2026-10-21; the effect vocabulary's tree, D22's open part).
  The resource tree, "approved", after the whole design was laid out
  from the top (`design/effect-vocabulary.md` §1 to §4, §8.3):
  ```
  root (upstream)
  ├── frame (upstream)       stack cells
  ├── heap                   Allocate, Free: the memory any cell lives in
  │   ├── contents           Read, Write: memory written in place
  │   ├── count              Read, Write, Free: reference counts
  │   └── memo_state         Read, Write: memo cells
  ├── identity               Allocate: a fresh linear or owned value
  └── io                     Read, Write: the outside, one ordered state
      ├── runtime_state      Read: the handle table, the saved errno
      ├── exit               Write: the run ending normally
      └── crash              Write: the run ending by a crash
          └── divergence     Write: the run never ending
  ```
  Immutable memory, static data and what is fixed for the run have no
  resource. Forced by rulings: IO unsplit, crash under IO and the heap
  beside it (D21), divergence under crash (D13), exit under IO (D14).
  Chosen with it: the heap carries only acquiring and freeing, its
  children the rest; identity apart from the heap; runtime state a
  read-only child of IO (eff-Q4 (b)). Its names are D28's.
- **D28** (2026-10-21). The resources' names, "all approved. this must
  be a very hard cutover. zero backwards compat.": printed `idr.heap`,
  `idr.contents`, `idr.count`, `idr.memo_state`, `idr.identity`,
  `idr.io`, `idr.runtime_state`, `idr.exit`, `idr.crash`,
  `idr.divergence`; upstream's root and frame keep upstream's names; C++
  `idr::effects::Heap` and kin, the enum `ResourceId`; Idris
  `Spec.Effects.Resource`'s constructors `Heap`, `Contents`, `Count`,
  `MemoState`, `Identity`, `IO`, `RuntimeState`, `Exit`, `Crash`,
  `Divergence`. Named for the state each is, never for a reader's
  question or a mechanism. `IOResource`, `CrashResource`,
  `DivergenceResource`, `LinResource`, `ReferenceResource` and
  `MemoStateResource` are deleted in the change that brings the new
  names, with no alias, shim or dual spelling in any reader, test or
  printed form.
- **D29** (2026-10-21). The atoms' names, one name per concept: "B."
  An atom on a resource with one atom is that resource's name; a
  resource with two is named by kind. The row prints
  `effects<io, runtime_state, exit, crash, divergence, count,
  memo_state, read, write, alloc, free>`: `read` and `write` on
  `contents`, `alloc` and `free` on `heap` (LLVM's `allockind` words),
  the last two reporting only. Generated from `Spec.Effects.Atom`, so the
  printed spelling, the C++ enum and the Idris constructor are one.
  `runtime`, `memo` and `diverge` as atoms are gone, with no alias.
- **D30** (2026-10-21; DP-14: tail-Q2). Proper tail calls are part of a
  compiled program's meaning: "a call in tail position MUST NEVER grow
  the stack. proper tail calls, locked in." As ML and Scheme guarantee
  them (Clinger's space property), and as upstream Idris on Chez has
  them.
  - *Every call of the program in tail position*, on a cycle or not, is a
    jump: a loop, a join point (D19), or `musttail` with `tailcc`. Every
    call is direct (megamorphic code is refused; defunctionalization
    makes every application a dispatch), so nothing stands between a
    tail call and its guarantee. A runtime op is a primitive, not a call
    of the program.
  - *One fact per call*: whether a call is in tail position is decided
    once, held on the call, verified, and lowered to `llvm.call`'s tail
    kind; every pass obeys it (lane 10 NQ-1). The stack inference puts
    no cell in a frame a tail call may reach (it goes to the heap); a
    result returned through memory forwards the caller's own slot.
  - *A failure is a compiler bug*, an internal error, never a silent
    call and never a refusal; it never rests on a budget.
  - *Non-tail recursion* stays legal and uses the stack as written.
  - *Deleted*: the two definitions of tail position (`IR/Tail.cpp`'s
    climb, `TailPosition.cpp`'s walk) and the four deciders of a tail call
    on its caller's cycle (`Borrows.cpp`, `Stack.cpp`, `Recursion.cpp`,
    `TailCallPlan.cpp`), read across 19 files (corrected 2026-10-21,
    L10), idr-tail-calls' cycle condition and its silent fallback
    (`frameBound`, `lib/Conversion/TailCallPlan.cpp:108-112`, summed by
    the statistic `numFrameBound`; corrected 2026-10-21, L06, L19).
  - *Cost to measure, never a reason to weaken*: `tailcc` on every
    function of the program that only the module's calls reach.
  - *For 0020*: nothing; Rust never calls back into Idris (D92).
- **D31** (2026-10-21; lane 10 NQ-2's frames half). Running an action
  never grows the native stack, however its binds nest: "B. of course B.
  need to optimize it like fuck ... if it's bleeding edge pl research and
  it can be done, we should do it. and be proud of it." The research
  answer was that it can be done: CPS and defunctionalization of the
  continuation are textbook (Danvy and Nielsen 2001 §3, read) and in
  production in Scala's effect runtimes (recalled); our form is new.
  - *The design*: idr-frames rebuilt as a typed, linear, uncounted,
    contiguous stack of frames: one stack per result type (lane 10 D2),
    so a frame of the wrong type is unrepresentable and the per-pair
    clone (the 43 GB wall, 16005000) has nothing to do; each frame
    pushed once and popped by one resume, so never counted (D10); a push
    a bump and stores, a pop a bump, chunks given back as it shrinks; a
    frame an escaped join point (D19), reuse tokens carried in it. It
    transforms the call's continuation, never the monad's binds, so it
    needs no monad law.
  - *Its silent gaps close by representation* (seven at HEAD, not three:
    the third is dead under D22, and four more close by framing every
    non-tail call of a component, as D32 extends it; corrected
    2026-10-21, L10): frames hold several results and values of any
    type; a component's members share one row.
    A failure is an internal error, as for D30.
  - *Not promised*: constant memory for the nesting (a zipper derived
    automatically is research). Extended by D32 from binds to every
    recursion on a call cycle.
- **D32** (2026-10-21). The native stack is small and statically
  bounded: "B is way better. stack should be kept small, i'm in the musl
  camp on this." Replaces 1445d894's 64 GiB reservation, chosen so that
  deep recursion would never overflow, which let a runaway recursion take
  the machine down (that commit's own defunc-cycle), keeps strict hosts
  from starting a program (18 R-STK-3) and multiplies per shard.
  - *Every recursion on a call cycle keeps its depth on D31's typed frame
    stacks*, which grow until memory runs out (D23): a non-tail call on a
    cycle pushes its rest as a frame, as a bind's does. The native stack
    then holds only the program's acyclic call depth.
  - *Its size is a static fact* (D10): the longest acyclic path of the
    call graph, weighted by each function's frame size as code generation
    reports it, with a margin for the C library's and other outside
    code's frames (the runtime's own are computed, its bitcode being in
    the module; corrected 2026-10-21, L10); computed when the program is
    built, small, and the runner
    reserves that. No frame is larger than the guard, checked when built.
  - *Reaching the guard is an internal error*, never a property of the
    program: compiled code cannot exhaust the stack.
  - *Costs, measured as it is built*: recursion over data (a tree's
    height) pays a frame's dispatch instead of a native return.
  - *For 0020*: a foreign call runs in Rust's own runtime (D92), whose
    frames this bound does not cover and need not.
- **D33** (2026-10-21). The compiler's own tools keep a small stack too:
  "A." Our C++ is iterative (worklists, never recursion on the input's
  size); MLIR's deepest recursion is measured on the stage-1 module and
  on deep-nesting fixtures (S1), and a recursion that scales with the
  input (`walk`, the printer and parser, region utilities on nesting
  depth: under D19 a generated `else if` ladder nests one match per
  branch; the verifier is already iterative at the pin, corrected
  2026-10-21, L15) is fixed upstream by patch, as
  `upstream/10-recursive-attribute-parser` reports (a report and
  reproducer, its patch owed; corrected 2026-10-21, L15, L10). The tools' 64 GiB
  stack goes with the programs'.
- **D34** (2026-10-21). Tail recursion modulo context is a promise: "as
  a promise!" A self call whose result the value a tail returns holds, in
  cells and parts of values built for it that nothing else reaches
  (`f x :: map f xs`, several constructors deep, across a rejoin, an IO
  action inside the actions that run it), is compiled as a loop that
  builds each such cell first and passes the pending field as a
  destination (`!idr.dest`). Read off the program as the frontend wrote
  it, as D24's rule is; counting honours it, and on an exclusive value
  reuse rebuilds the cells in place (D24, C1). A failure is an internal
  error. Under D32 a missed one would only cost a frame per level; the
  promise is that it never does.
- **D35** (2026-10-21; DP-19's first part: rt-Q3, 18 N3). Programs
  start on strict hosts (Linux overcommit mode 2, a low `ulimit -v`,
  both Linux's: macOS refuses an address-space limit, corrected
  2026-10-21, L19):
  "yes, we should start on strict hosts, obviously. A." A program
  commits no memory before it uses it, and reserves no address space
  beyond what the host allows. The owner's point with it: "our stack is
  way too huge, and the heap region seems a bit large too. its aligned
  to 4gib for dmp but it doesn't have to be 4 off of the bat. let's
  choose better values" (C5).
- **D36** (2026-10-21; DP-19's second part: oom-5). A program reads
  its host's memory limit and keeps to it, with no setting: "B." At
  start the runtime reads the cgroup's `memory.max` on Linux, behind the
  platform layer (macOS has none to read); when committed memory would
  cross it, the program ends with D23's named out-of-memory ending,
  output flushed, before the kernel's killer would end it unnamed.
  Committed bytes are counted in snmalloc's chain of ranges, by
  snmalloc's own `StatsRange` in the `StandardLocalState` chain that
  `Cells.cpp:69` selects (`snmalloc/backend/standard_range.h:41`; not a
  type the runtime owns, corrected 2026-10-21, L06, L11). Hard only: no program can
  react to a soft one (D23). No environment variable (1445d894).
- **D37** (2026-10-21; DP-18's first part: oom-6). One exit status per
  ending, in skarnet's style: "yep. sounds good. let's do that."
  | ending | status |
  | --- | --- |
  | returned | 0 |
  | `exit n` | n; a status no parent can read (outside 0 to 255) is a crash at the exit's site (D64) |
  | crashed (a partial function, `idris_crash`, a failed guard) | 1 |
  | out of memory (D23, D36) | 111 |
  | cannot run on this machine (a CPU feature, the page size) | 126 |
  | internal error (the compiler's or the runtime's bug: D30, D32, counting) | `SIGABRT` after the message |
  Messages go to standard error as `<program>: fatal: <cause>`, the
  program's own name. One generated table, the runtime's ending sum
  (replacing `Ending { mainReturned, exited }`, 18 R-STK-4), read by the
  runtime, the harness and the documentation; tests read the status and
  the committed standard error, never parsed text. Upstream is no guide
  here: its Chez backend writes `ERROR: <msg>` to standard output and
  exits 1, its RefC backend exits 255, and `exitWith (ExitFailure 256)`
  reads as success there.
- **D38** (2026-10-21; DP-18's second part: conv-Q4, 12 T9). A crash
  site reaches the runtime as data: "A." One entry,
  `idris_rt_crash_at(cause, file, line, column)`: one global per cause
  and one per file, shared, the line and column immediates; the runtime
  writes `<program>: fatal: file:line:col: cause` (D37) on its cold
  path. `idris_crash` with a run-time string keeps its site. Deletes the
  per-site message global, its digest and the attribute made on a worker
  for each (12 CV-16), and the generic call that lost the site (CV-17).
- **D39** (2026-10-21; DP-16: DD-Q6, absorbing DP-39). Scopes are named
  in types, Tofte and Talpin's way on D19's regions: "YES! NOW WE SNAP
  RIGHT ONTO MLIR for free. let's do it. hard cutover to B."
  - *The grade's fourth parameter is a lifetime* (D40): today's two
    constants, `heap < frame`, with the `static` that 467fa2f5 added and
    c4d38e9b removed (corrected 2026-10-21, L05), become three
    particular scopes (forever, counted, this call), and scope variables
    add the rest. A variable is bound by an op whose MLIR region is its
    extent (Tofte and Talpin's `letregion`), or by a function's scope
    parameter. Lexical, so its checking is local and linear given the
    signatures; never Rust's non-lexical lifetimes, which a CFG needs and
    D19's regions with SSA do not.
  - *Signatures carry scope parameters*, inferred bottom-up over the call
    graph's SCCs as the effect rows are (D22): a result can live in its
    argument's scope (a recursive `lookup` returns a view of the tree,
    counted nothing), and a callee can build its result in the caller's
    scope. A scope parameter is a handle at run time, so it is part of the
    function's type (C2 R3).
  - *Views first*: borrowed parameters and results; an array element a
    view where D27's effects show no write to the array.
  - *Then allocation*: cells bump-allocated into a scope, freed together
    at its end, with no count word; each scope proven within D26 (its
    cells live until its end, or a fixed amount per frame), counting the
    fallback for any cell not proven, so a scope is an optimization over
    counting, never a replacement (MLKit's leaks, which led it to add a
    collector, Hallenberg, Elsman and Tofte 2002, recalled). A scope's
    cells holding owned references into the counted heap drop them at its
    end; one holding only views of older data and of each other frees in
    O(1). A scope moves whole between shards (0007 §5.1).
  - *Static is graded from what a value holds*, never from where it came
    (the bug that removed 467fa2f5's attempt, c4d38e9b); 0003's owed
    static lifetime is this.
  - *Deleted*: the owned verifier's whole-function def-use walk (a view's
    scope is now its type and its region), `isStatic`'s search along the
    definition chain, the `dup` of every counted element read from an
    array (stated at `Analysis/Ownership.h:23-24`, made at
    `Transforms/Ownership/Reshape.cpp:109-112`; corrected 2026-10-21,
    L06, L12) where no write intervenes.
- **D40** (2026-10-21). The name: "we should maximally churn the names
  to be maximally correct. let's just pick the best name." The concept
  is a **lifetime** (the code's word already, `IdrTypes.td:277-299`,
  `IR/Lifetimes.h`; "region" is MLIR's `Region`, "scope" upstream's
  `AutomaticAllocationScope`, "arena" snmalloc's, "extent" an array's,
  "origin" borrow-only). Its constants are `static` (the whole run),
  `counted` (until its count reaches zero) and `frame` (this call);
  today's `heap` constant becomes `counted`, since `heap` is the
  resource of D28, the memory any cell lives in, which a cell of a
  lifetime variable lives in too. A variable is bound by the op
  `idr.lifetime`, whose region is its extent, or by a function's
  lifetime parameter. A value may hold references only to values whose
  lifetime outlives its own: `static`, then `counted`, then lexical
  lifetimes from outer to inner, `frame` the outermost of a function's.
  The grade prints `!idr.q<1, own, T, ρ>`, `counted` left unwritten.
  Synthesis A's "locality" and every other spelling of the concept go.
- **D41** (2026-10-21; DP-17's first part: conv-Q1, ops-Q2, ops-Q3).
  An op of inline arithmetic has one meaning, a C++ template: "B seems
  better, we're going for the pinnacle of optimization." Euclidean
  division, the total shifts, and the char conversions with their
  scalar-value test (corrected 2026-10-21, L13) are each one function
  generic over a numeric domain (a
  concept), instantiated over integers as the folder (its edge cases
  `static_assert`ed when the compiler is built), over intervals as
  upstream's `InferIntRangeInterface`, and over an IR builder as its
  expansion into `arith`, emitted at the stage that needs `arith`
  (vectorization, 0009; the lowering); the runtime includes the same
  header. The op stays until then (D18): it keeps the fact of what it
  is, as upstream's `arith.floordivsi` stays an op until `arith-expand`.
  Deletes the meaning written three times, in the folder, the lowering
  and the runtime (03 O-47, 12 §6; three times for division, twice for
  the shifts and the char conversions, corrected 2026-10-21, L13, L15).
  Strings, big integers and IO stay
  runtime functions.
- **D42** (2026-10-21; DP-17's second part: arr-Q3, 11 I-LI2, N3). The
  array library's generating set means the dialect's ops: "the whole
  point of the mlir array library is to take advantage and to lower
  directly to mlir." `Array.Core`'s 22 bodiless externs (`tabulate`,
  `!!`, `foldLast`, `scanLast`, `nest`, `merge`, `reshape`, `transpose`,
  `take` and the rest) mean the op the Idris specification declares for
  each, with upstream's tensor and linalg semantics, as the library's
  header already says. Not a design change: AGENTS.md's rule that an
  extern of `libs/` means only what `runtime/` says contradicted it, and
  is amended.
- **D43** (2026-10-21; DP-10: arr-Q1, arr-Q5, 11 N1, N5). P0 takes
  0009's array cutover whole: "A." The array stage is cut over once.
  - *The generating ops in upstream's form* (11 C3): `tabulate`,
    `fold_last` and `scan_last` take destinations, implement
    `DestinationStyleOpInterface` and `TilingInterface`, bufferize
    through upstream's model, and an ordered one becomes loops through
    `lowerToLoopsUsingSCFForOp`; `idr-structure-loops` only turns the
    pure word ops into linalg. Deletes `Nests.cpp` whole,
    `GeneratingOpInterface` and `Idr_Iteration`'s translation.
  - *An array field is its buffer from the frontend on* (11 C5): `idr.con`
    takes a tensor through `bufferization.to_buffer`, `idr.field` gives
    one through `to_tensor restrict`, the data-type verifier (since D48,
    the family attribute's; corrected 2026-10-21, L12) refuses a
    tensor in a body, and `!idr.lin<T>` is tensor-like where `T` is, so
    One-Shot bufferizes linear wrappers and signatures itself. Two
    upstream patches, carried (D25): submission 27 (`tensorAllocationFn`)
    and a per-instance `extraClassOf` on `TensorLikeType` and
    `BufferLikeType`. Deletes the "buffers" retype (`DataRemap`),
    `heldType`, `StoreModel`, `HeapReadModel`, and the reason
    `EnterModel` and `UseModel` exist. Reverses 0009 §8's reason for
    keeping the grade off `TensorLikeType`; 0009 is amended in the same
    change.
- **D44** (2026-10-21; DP-09: hist-Q4, ft-Q2). P0 absorbs every fact
  once and the data-oriented frontend whole: "no more postponing. when
  we're rewriting the whole darn thing we're gonna redo everything
  right. we should do the big one." It reverses the owner's 2026-10-19
  deferral of 0003 to after self-hosting.
  - *0003 whole*: its 62 items in six sections (21 was lane 20's probe
    of them; corrected 2026-10-21, L16), the fork's among them (17 §6),
    so that "no rederivation chains" holds (20 §5.2).
  - *0011 whole*: the small form (one dense instance identity minted
    once, classification and types memoized by key, locations as
    interned coordinates; 15 D-1, D-3, D-5) and the large one, Core as
    tables (O2) and the translation as semi-naive evaluation over an
    interned instance table (O3).
  - *And what 0011's large form stands on*: 0010's A0 (interned names,
    the term arena as columns) and 0015's R1 and R2 (the relational core,
    in plain Idris, both hosts). Their stages keep their order and
    their measured bars; each comes into P0's execution (§7) with its
    proposal amended in the same change.
- **D45** (2026-10-21; DP-20: Q-FB3, 17 §6). The fork's elaborator
  refuses no program because a count ran out: "A." As
  `upstream/fork-totality-depth` did for `%totality_depth`, each count
  is replaced by a search that ends by construction, and its pragma is
  refused by the parser.
  - *Finding implementations automatically* (`%auto_implicit_depth`,
    50; `App.idr:272-274`): an implementation whose requirements are not
    smaller than what it implements is refused (a size rule in the
    manner of Haskell's Paterson conditions), so the search ends; a few
    programs upstream accepts are refused, which a strict subset allows
    (D12).
  - *Overloaded names* (`%ambiguity_depth`, 3; `Ambiguity.idr:326-334`):
    a search bounded by what it has already tried, as the totality fix
    is; its mechanism is confirmed by reading the code
    (`audits/p0/design/elaborator-counts.md`).
  - Each change lives in the fork as its own code, recorded in PINS.md,
    with its diff against the pin in `upstream/<bug>/pull-request.diff`.
  - *Under the evidence of `design/elaborator-counts.md`* (2026-10-21,
    measured on the stock pinned Idris), both mechanisms recorded above
    fail and go back to the owner (§4): the size rule refuses upstream's
    own prelude (`Uninhabited (a, b)` from `Either (Uninhabited a)
    (Uninhabited b)`, `Prelude/Types.idr:301`) and does not reach every
    hint (constructors, parent projections, `%hint` functions); the
    ambiguity count never ended anything (deleting it ends every search,
    at a measured cost: 433 s for a 22-tuple under `printLn`).
- **D46** (2026-10-21; DP-21: 16 Q-fc-1). The frontend's growth proof
  covers the code: "A." Theorem 1 is stated over the code's own
  `Template`, not a three-constructor model (`Proof/Bound.idr`), and the
  frontend builds the derivation as it works, at quantity 0. The run-time
  re-check of the conclusion on every request (`Finite.heightWithin`,
  `sizedWithin`, `Frontend/Finite.idr:187-202`; `boundsHold`,
  `Translate/Types.idr:847-853`; corrected 2026-10-21, L16) and its internal error go: a
  proven fact is not checked again when the compiler runs (D10). The
  proof is written in the subset both hosts compile.
- **D47** (2026-10-21; DP-08). The representation-first skill's line,
  approved ("yes"): shared shape over ops is an interface, "never an
  `isa<A, B>` ladder, and never a concept that lists ops", replacing
  "never an `isa<A, B>` ladder or a C++ concept", which contradicted D7.
  A concept may read an op's declared facts (a trait, interface
  membership, a generated constant).
- **D48** (2026-10-21; DS3, returned by G within DP-36). A data type is
  the inductive family Idris checked, carried whole into MLIR: "hot.
  lock it in." Pushed past the three options put (a name sealed once,
  an index into the program's table, a structural type) by the owner:
  "we need to push hard on the best possible representation, and start
  to dogfood qtt too. what is the maximally precise type?"
  - *A family is an attribute holding the declaration*: its erased
    indices; per constructor the index variables it binds, the index
    equation it satisfies, and its fields, each with its quantity (one
    or many: an erased field does not exist); recursion as `self[...]`,
    a back-reference carrying an index; a mutually recursive group as
    `#idr.families<...>` with back-references by position.
    ```mlir
    #Vect = #idr.family<"Vect" [n : nat] {
      @Nil  where n = 0
      @Cons where n = m + 1, m : nat  (x : i64, xs : self[m])
    }>
    ```
  - *A data type is a family applied to index terms*:
    `!idr.data<#Vect[n]>`, `!idr.data<#Vect[3]>`. Identity is content,
    shared by MLIR's uniquing; labels are for readers and nothing looks
    them up, so there is no table and no name without a body. Every type
    comes from a declaration (Idris's, or one a pass declares), so equal
    declarations are equal types and no canonicalizing step exists.
  - *Erased parameters share one binder*: index variables and lifetime
    variables (D39, D40) are quantity-0 parameters of a function or a
    region (`idr.func @map<n : nat, ρ : lifetime>`), passed at calls at
    compile time only (`idr.call @map<k, frame>`), checked by substitution.
  - *What follows, none of it paid at run time*: a match refines the
    index, and a case whose equation is false does not exist (the
    verifier knows `head`'s `@Nil` is impossible at `n + 1`); a known
    index fixes the shape (`#Vect[3]` is three words inline, no tag, no
    cell, no count); `Fin n` is one word below `n` (0018); a typed
    expression's impossible arms vanish under specialization.
  - *Inline or in a cell is layout*, a function of the type and its
    lifetime computed once: a recursive field at an unknown index is a
    cell, a value of a known index has a fixed size. `!idr.box` is no
    longer a type.
  - *The index language*: constants, variables, successor and
    constructor applications, `Nat` as a number; anything richer is an
    opaque term, sound and refining nothing, until static normalization
    (0010) grows it.
  - *The specification is written the same way* (D16): index terms
    well-scoped by `Fin s`, one equation per family index by
    `Vect s`, a field's quantity a type with no erased case.
  - *Deleted*: the `#idr.types` table (`Idr_DataTableAttr`,
    `DataBody.cpp`), `MutableType` and sealing, the content-named remakes
    (`DataRemap`, `Symbols.h:139-236`), the name-alone state and the
    program verifier's walk for it (01 T59), `!idr.box` as a type. The
    149 readers of a body (measured at HEAD, corrected 2026-10-21, L04)
    read it from the type.
- **D49** (2026-10-21; one-source 11.3 item 1: ids-Q1, DP-71). The
  specification's generated files are committed: "A." Each is stamped
  with the fingerprint of the specification and of its own text;
  `make check` regenerates into a temporary tree and fails on any
  difference, so a hand edit fails. A C++ build never waits on Idris, a
  reviewer sees the `.td` and C++ a specification change produces, and
  bisecting C++ needs no generator. They are output, never a second
  source; AGENTS.md says so beside its rule that a copy kept in step by a
  verifier is still a copy.
- **D50** (2026-10-21; one-source 11.3 item 2). The frontend imports the
  specification's closed sets: "A." The refusal categories, the ending
  table (D37), the clock kinds, the grade's parts and the pipeline's
  stages are the specification's modules, imported; their generated Idris
  copies and `IdrRules.txt`, `IdrPassRoles.txt`, `IdrPassStages.txt` go.
  Builders and encoders stay printed, each a plain function typed by its
  op's operand count (`Vect n Value`): a generic builder's type would
  depend on a run-time value of varying representation, which the subset
  refuses (one-source §6.2).
- **D51** (2026-10-21; one-source 11.3 item 3). Upstream's records are
  read by one slim C++ TableGen backend: "A." It prints the Idris
  builders and encoders of the upstream ops the frontend writes (`arith`,
  `math`, `memref`, `tensor`, `ub`, `builtin`) through MLIR's own
  TableGen API, for the ops the specification admits alone (a generated
  `IdrAdmitted.td`, one record per op naming upstream's def, a wrong name
  TableGen's own error). The one generator of ours not in Idris: C++
  reading upstream's records, nothing of upstream restated. Every other
  backend of `idris-mlir-tblgen` goes (one-source §6.5).
- **D52** (2026-10-21; one-source 11.3 item 4). Under idris-mlir the
  generator reproduces the committed files byte for byte: "A." The
  committed files are the specification of what it writes, as a test's
  expected files are, so neither host is the reference and this is no
  oracle; it sits beside `make self`'s stage 2 equal to stage 3. Its
  output is a pure function of the specification: declaration order, no
  map iteration or directory listing, only strings and integers printed
  (never a `Double`, 14 X01), no time, environment or path read.
- **D53** (2026-10-21; amends D45 on `design/elaborator-counts.md`'s
  evidence). The automatic search ends by the path rule, not the size
  rule: "A." Before the search takes up a goal, it compares the goal with
  every goal on its own path (unknowns as one symbol, the search's locals
  as one, constants by their type); if an earlier one embeds in it
  (homeomorphic embedding), the search is growing: convertible, that step
  fails, as upstream's cycle check does; otherwise the program is
  refused, naming the two goals and the hints between them, never
  dropped as a failed branch so a sibling wins. Kruskal's tree theorem
  makes every endless path meet such a pair, so every search ends with no
  count. Every program the stock Idris elaborates with a large enough
  depth is elaborated the same, except where upstream's answer was its
  depth running out. Goes with it: the size rule (it refuses upstream's
  prelude, `Uninhabited (a, b)` at `Prelude/Types.idr:301`, and misses
  constructor, parent and `%hint` hints), `%auto_implicit_depth`,
  `%search`'s 50, the two fixed depths of 500 and the parser's 1000, each
  pragma refused by the parser.
- **D54** (2026-10-21; `design/elaborator-counts.md` §2.6 case 2). A
  growing search that holds an unknown is postponed, not refused: "A."
  It is set aside as a determining-argument failure is
  (`Core/Unify.idr:1449-1455`, corrected 2026-10-21, L17), retried after a round of elaboration makes
  progress (progress solves a hole for good, so retries end), and the
  program is refused only at the last chance, if the path still grows.
- **D55** (2026-10-21; `design/elaborator-counts.md` §1). Overloaded
  names: the count goes, and the tuple's two meanings are settled by
  representation: "B." `%ambiguity_depth` and everything that serves it
  are deleted (§1.7 there lists them); the count never ended a
  resolution, every attempt elaborating a smaller part of the source, and
  only refused programs (`printLn (1, 2, 3, 4, 5, 6)`). The measured cost
  without it is the tuple's (433 s for a 22-tuple under `printLn`; 48
  nested two-way overloads of another name take 0.37 s), an artefact of
  one syntax for the pair type and the pair value: `(a, b)` is settled
  by the sort of its expected type when that is known, and by its
  components when not, which gives upstream's elaboration without trying
  both readings at every level. Its design in the fork is owed (a
  conjecture in the evidence), recorded in PINS.md with its
  `upstream/fork-*/pull-request.diff`. "Bounded by what it has already
  tried" (D45) is withdrawn: an attempt reads and writes the elaborator's
  state, so a memo of tries is unsound, and none is needed to end.
- **D56** (2026-10-21). The cutover is built only when it is whole: "we
  will only build when this entire cutover is fully done." No step of P0
  is built, typechecked or run on its own; the whole cutover is written,
  then built and qualified on all four targets as one change, in a final
  phase of repairs and reruns, and lands only built and passing
  (AGENTS.md: a change is done when it is built, run and passes). So the
  execution's shape (§7) is not a sequence of gated steps: every area is
  written at once by owned lanes, against contracts this document fixes,
  with checks written as part of each area, and the build is the end.
  Suspected bugs (§8, C8) are folded into the cutover and reproduced in
  its qualification; none is built or fixed on main before it.
- **D57** (2026-10-21; reopens G's DP-25). Optimization by search over
  the legal choices the representation exposes, equality saturation
  among them: "we want to wring as much perf as possible and nasty,
  ridiculous unintuitive optimizations ... once we have the
  representation, the search could be trivial"; "yes, egraph good." The
  types decide what is legal (a token's exclusivity, a family's known
  index, an effect row, a quantity, a lifetime, a tail fact); the
  optimizer chooses among legal candidates by a cost model, each search
  finite and ending by construction, a budget leaving code less
  optimized and never refusing. DP-25's exclusion of equality
  saturation goes. Its form and place (an e-graph over our ops and
  upstream's, its rules from the Idris specification, effects and
  regions, extraction) are `audits/p0/design/egraph.md`'s, researched
  before they are settled.
- **D58** (2026-10-21; L04 Q1, the reviewer's claim 1). A known index
  meets code compiled for every index by specialization by layout class:
  "A." An application's class is closed (every index term known, its
  unfolding within a shape budget) or unknown; a call whose callee's
  layout changes under the call's indices targets a copy of the callee
  at that class, a refined recursive call specialized in turn, an index
  that climbs past the budget reaching the general copy. The class set is
  finite, so the copies are, and the specialization ends by construction;
  the budget, written once in the specification and measured before it
  is fixed, only ever leaves code less optimized. A bounded conversion
  (`idr.reindex`) remains only where an index becomes known inside a
  function. `#Vect[3]` is inline wherever its index is known, `Vect
  100000` stays cells (no quadratic code, no frame past the guard), and
  `Fin 256` is a byte through calls, one mechanism with 0018's.
- **D59** (2026-10-21; L04 Q2, L20 I4 and its correction to D48). A
  run-time value in an index position keeps its link to the index, the
  singleton of Dependent ML (Xi and Pfenning 1999, recalled): "b." A
  quantity-ω binder that occurs in an index position is also an index
  binder, and its run-time value's type carries the term (a natural
  indexed by `n`, a literal closed); a call passes the argument's term
  when it is known (a literal, or the caller's own linked binder) and
  `opaque` otherwise. `replicate 3 x` is `#Vect[3]`, specialized and
  inline (D58); a dependent pair keeps the length its vector has;
  `replicate`'s and `Linear.Vec`'s run-time lengths have their binder.
  Costs: the natural type gains an index parameter, every op producing a
  natural states its result's term or `opaque`, the frontend's binder
  translation gains one case.
- **D60** (2026-10-21; L12 OQ1). An array's size a call fixes has one
  key, the index term: "A." Where a function's signature names a dynamic
  dimension of an array argument or result by an index variable, that
  variable is the key; D58's specialization substitutes it, and the
  copy's tensor types become static where the term is a constant.
  Inside a function, equalities stay run-time ties (`idr.tie_shape`):
  MLIR's tensor type has no symbolic dimension, and an array's extent is
  a run-time value linked to its index by D59. 0009 stage 2's refined
  tensor type as a second specialization key is never built; 0009 is
  amended in the same change.
- **D61** (2026-10-21; L02 Q2). A function's effect row gains a part per
  parameter, for writes through an exclusive owned parameter: "B." Only a
  parameter whose grade is exclusive and owned has one; the call declares
  the write on that operand, a caller passing memory it acquired itself
  loses the effect, and LLVM is told the write is argument memory only.
  In-place rebuilding (D24) and array building (D43) become movable,
  mergeable and deletable where the caller owns the memory. The row keeps
  D29's eleven atoms beside it; the writer joins the per-parameter part.
- **D62** (2026-10-21; L20 Q4). No grade richer than Idris's: "a." The
  grade is Idris's quantity (one or many; zero is absence) × the
  compiler's permission × the lifetime, written once in the Idris
  specification as one algebra (the quantity semiring, the permission
  lattice, the lifetime order) with its laws proven there and generated
  as compile-time tables (D16). No affine source quantity (Idris has
  none, D12; the IR's linearity check is affine by design, stated so), no
  borrow quantity (the permission and lifetime carry it), no fractional
  permission (lending is a lifetime region), no semiring of lifetimes.
  How the parts combine (L05's quantity × hold) waits on the lifetime
  research.
- **D63** (2026-10-21; amends D39, D40, D48; settles the lifetime
  question). A lifetime is an SSA value, a hard cutover: "lifetime as an
  ssa value seems by far the best way to do this, can we hard cutover to
  it pls?" Chosen over a lifetime as a type parameter with binders (D39,
  D40, D48 as written) and over MLIR regions alone, weighed against what
  MLIR does for free.
  - *The value*: `idr.lifetime` opens a region and yields a token for it;
    a function takes a lifetime as an argument, a call passes it as an
    operand. MLIR's region scoping and dominance check that nothing of a
    lifetime outlives it, and upstream's inliner, CSE and dead code
    handle it as any SSA value, with no substitution or inliner of ours.
  - *One value, both jobs*: where a function allocates into the lifetime,
    the token is the run-time arena handle; everywhere else it is erased
    at the lowering. D39's "a handle at run time" and the lanes' split of
    an erased lifetime from a separate handle are both met by one value.
  - *What changes*: lifetime variables leave the type: D48's binder
    holds index variables alone, and the grade's lifetime parameter keeps
    only what is not a lexical lifetime. How a value's lifetime is known
    (the op that makes a view or allocates takes the token), how a
    signature relates a result to an argument's lifetime, and how the
    verifier checks it without following def-use chains (AGENTS.md) are
    designed in `audits/p0/design/lifetimes/` under this ruling.
  - *Deleted*: lifetime variables in types, their binders and
    substitution, the outlives order over type-level variables, D40's
    `!idr.q<1, own, T, ρ>` printing.
- **D64** (2026-10-21; L11 Q1; amends D37's `exit n` row). An `exit`
  status no parent can read (outside 0 to 255) is a crash at the exit's
  site, not an internal error: "B." Status 1, the message naming the
  site (D38): `<program>: fatal: file:line:col: exit status 300 cannot be
  reported`. `SIGABRT` stays for the compiler's or the runtime's own bugs
  alone.
- **D65** (2026-10-21; L11 Q2; amends D36). The host's memory limit is
  the kernel's real kill point: "B." The lowest limit up the cgroup tree,
  less what that cgroup already holds, plus its swap allowance where the
  cgroup may swap (`memory.swap.max`); the program runs as far as the
  machine lets it, then ends with D23's named out-of-memory ending,
  output flushed, before the kernel's killer would end it unnamed.
- **D66** (2026-10-21; L10 Q1; reads D35 by its purpose). The small
  computed stack (D32) is charged in full when its thread starts: "A." It
  is a few hundred KiB at most, the program's own need, so a strict host
  still starts it; D35's rule is against claiming what may never be used
  (the old 64 GiB), not against the bounded stack a program needs.
  Committing it page by page from a fault handler buys nothing and is not
  built.
- **D67** (2026-10-21; L03 Q2, L19's D49 correction; amends D49's
  stamps). The generated files' fingerprints live in one committed
  manifest: "B." It lists every generated file with its content hash, and
  the hashes of the specification and of the generator; no generated
  file carries a stamp, and one is rewritten only when its bytes change,
  so an edit recompiles only what it changed (a spec-wide stamp in each
  header would recompile all 316 includers on any edit). `make check`
  regenerates and compares the files and the manifest: a hand edit fails,
  and so does a generator changed without its outputs.
- **D68** (2026-10-21; L16 Q1; completes D46). D46's one link no proof
  of ours can reach, that the fork's normaliser returns at a call the
  value the site's template reduces to, is one stated trust in the fork:
  "A." `Idris.Host` states, at quantity 0, that property over a
  reduction relation the fork declares for the static fragment (heads,
  beta of families, a stuck definition's leaf, projection); the
  frontend's readers are proved sound against it, and the run-time
  witness goes in the change that lands the proof. It sits where
  AGENTS.md puts the frontend's trusts in Idris's compiler, beside the
  termination trust the fork already states; it is the trust Idris's own
  type checker rests on. No second evaluator (0010 D3: one evaluator).
- **D69** (2026-10-21; L16 Q3; extends D44). "0011 whole" includes O6
  and O7, with what they stand on: "A." O6 (multiplicity checking as a
  semiring fold, size-change composition as a semiring product) brings
  0009's plain-Idris layer (its stage 7); O7 (the elaborator's constraint
  store and postponement on 0015's relational core, meta-to-meta
  unification on its union-find) brings 0015's R4, its e-graphs, which
  are also the machinery of D57's optimizer search, built once. Their
  proposals are amended in the same change.
- **D70** (2026-10-21; L08 Q1; amends D24's obligation). The in-place
  promise obliges exclusivity of the family's own cells only, not of
  everything the value reaches: "B." A new permission between `own` and
  `excl` says the spine is the holder's alone while its contents may be
  shared; it is part of D62's one grade algebra, and its name follows the
  naming scheme. `reverse (rep n (Just k))` rebuilds in place though every
  element is one shared cell; an element's sharing never reaches the
  promise, and every rebuild that can be kept is accepted.
- **D71** (2026-10-21; L12 OQ2). `LArray` and `Linear.Vec` keep D24's
  promise, one mechanism for "written in place": "A." Both are `in_place`
  types (two more `InPlaceType` entries); their values carry the
  exclusive linear grade by construction, so exclusivity holds for them
  at every call; bufferization reads the grade, never searching for
  links; the vector's cell is rebuilt in place by D24's rule. A program
  that defeats the library's construction meets `unsupported
  (uniqueness)`, not an internal error. One-Shot's link check as a second
  statement of the promise goes, and an array read out of a cell is
  writable only where its grade is exclusive (L12's suspected
  miscompile, `Linear.cpp:91`).
- **D72** (2026-10-21; L08 Q3; reads D24 by its first sentence). The
  in-place promise reaches every value of an `in_place` type bound at
  quantity 1, a parameter or a field a linear match binds: "B." A linear
  record holding a linear list keeps the promise for the list; the
  obligation reaches the enclosing value, so callers pass the record with
  its own cells exclusive (D70), through the specialization by grade.
- **D73** (2026-10-21; L08 Q2, L07; rewords D26's "never" line). D26
  forbids "a borrowed argument no active call needs after the call",
  not "a borrowed argument whose last use is the call": "B." Borrowing a
  part of a value the caller still holds is allowed (Lean's derived
  borrows): a read-only recursion over a borrowed tree (`depth`, two
  calls under `max`) counts nothing, since the caller keeps the tree
  alive and the lent parts cost no extra memory. The borrow's validity
  rests on its lifetime (D63). D26's promise, bytes a call no longer
  needs, is unchanged.
- **D74** (2026-10-21; L07 Q1). D26 holds on a path that ends the
  process too: "A." Dead values are freed before any allocation on a
  path ending in a crash or `exit`, so a program never runs out of memory
  on its way to its own ending; frees after that path's last allocation
  are not emitted, since nothing follows them but the end.
- **D75** (2026-10-21; L09 Q1; amends D19's "never an allocated
  closure"). A join point is promised where the program as written
  makes one, and found beyond that by optimization: "C." A linear
  continuation the source defines and applies only in tail position
  within one function is a join point by construction, guaranteed, and
  a miss is an internal error (as D30, D34); one that becomes a join
  point only after inlining is an optimization, never a promise resting
  on the inliner's budget (AGENTS.md). Linearity alone does not make a
  continuation non-escaping.
- **D76** (2026-10-21; L09; amends D25's encoding). A join point's
  target is upstream's builtin `token`, a hard cutover to MLIR's own
  pattern: "B ... hard cutover to the mlir upstream pattern pls."
  `idr.join` defines a token per target; `idr.jump` takes it; the pinned
  verifier already refuses any token that escapes, for every op, so
  "non-escaping" costs us nothing to enforce (a custom `!idr.cont<...>`
  would have leaked through every operand of ours that accepts any
  type). The join op holds each target's argument types, and the jump's
  verifier checks against them. `!idr.cont` is never built.
- **D77** (2026-10-21; L10, L11, C59; keeps D32). No stack probes in
  compiled code: "A." The compiler knows every compiled function's frame
  size, so it proves at build time that none exceeds the guard (D32,
  D10); only the runtime's own C++ and what it links, whose frames may
  be sized at run time, take stack-clash protection.
- **D78** (2026-10-21; L05 Q1). The counted cell in lexical memory goes:
  "B." Every cell of a lexical lifetime, the frame's included, is
  uncounted and freed when its lifetime ends; a cell whose D26 proof
  fails is a counted heap cell. The stack bit in every header and each
  run-time test of it (in uniqueness tests, a static fact; in frees of a
  value of either kind) are deleted, and so is the state of an owned
  value at a lexical lifetime. Today's stack cells and cells placed in a
  lifetime are compared in the cutover's qualification (D56); a cell
  that moved to the heap is brought back by a tighter lifetime, never by
  the counted stack cell.
- **D79** (2026-10-21; C90's offered extent). In the in-place check, a
  use counts only if it may still hold the value at the rebuild: "B." A
  borrowed read whose lifetime has ended (D63) does not count, so `let n
  = countW xs in bump xs` with a read-only `countW` rebuilds in place.
  Decided by borrow inference on the program as written, inside the
  in-place check before any optimization, so acceptance stays a property
  of the program; a callee that keeps the value is no borrow, and the
  call is refused. The boundary is pinned by tests (B10 and its near
  neighbours).
- **D80** (2026-10-21; L19, L11; extends D38). A crash cause that names a
  function carries the name as data: "b." `idris_rt_crash_at(cause,
  function, file, line, column)`, one shared global per function name
  (cold-path data); the message reads `<program>: fatal: Main.idr:10:1:
  no clause matched in Main.name`. The name is a static fact the
  compiler holds, never baked into text per site.
- **D81** (2026-10-21; L02, the integration; extends D37). The reader of
  a pipe going away ends the program by `SIGPIPE`, honestly and with no
  data lost: "b." The runtime ignores the signal, sees the failed write
  (`EPIPE`), flushes every other open file, restores the default action
  and raises `SIGPIPE`, so the process dies by that signal: status 141 to
  a shell, no message, as Unix tools do. It joins D37's table as the one
  ending caused from outside the program.
- **D82** (2026-10-21; the integration; reconciles D25 with D19). Ours
  moves to upstream's merged form of early exits only when that form
  keeps every fact ours keeps (D19's bar, at least equal): "b."
  Otherwise ours stays, its patch carried, and the difference goes to
  the owner with its evidence. "Upstream first" adopts upstream's
  mechanisms, never a loss of facts; D76 (upstream's builtin `token`) is
  the case that keeps everything and enforces more.
- **D83** (2026-10-21; C67, L18 Q1). AGENTS.md's megamorphic example
  reads with its definition: "a." The example "an implementation chosen
  by a runtime value" becomes "an implementation chosen from a set no
  analysis bounds"; a run-time choice among implementations the program
  fixes is a closed sum and compiles, and the seven tests that refused it
  under `Megamorphic` become program tests.
- **D84** (2026-10-21; `design/egraph.md`; reads D69's "built once").
  The e-graphs are built once in everything that carries meaning, with
  one small engine per side: "A." The rule language and its proven laws
  (in the Idris specification), the rules, the extraction model, the
  termination argument and the test fixtures are shared; the Idris
  frontend's elaborator and the C++ optimizer each keep one small core
  that reads them. One engine across the boundary would need a C export
  or a foreign call (AGENTS.md forbids both) and would break the two
  hosts; sharing its state would be unsound (the elaborator must be
  complete, the optimizer may stop at a budget).
- **D85** (2026-10-21; reverses D84 and egraph.md's two tiers). The full
  research form of equality saturation, one engine, written once: "let's
  go full retard, full research level retard, and extract out extremely
  dense fast code to be shared with c++ ... why our crazy blazingly fast
  egraph stuff needs to be in both idris and c++? why in two places? i
  want to reverse my old decision. we want the full research version
  that 'is too slow' ... after the sparse arrays lowering in mlir, it
  becomes dense." eggcc's 11× is one implementation's measurement (an
  interpreted Datalog engine), not a bound: the e-graph's relations and
  rule joins compiled to dense specialized code, through MLIR's sparse
  pipeline or a compiled-Datalog generator, change its constant factors.
  How it is written once and shared with the C++ under AGENTS.md (no C
  interop, two hosts, committed generated outputs) is researched before
  it is settled: `audits/p0/design/egraph-full/`.
- **D86** (2026-10-21; under D85). The one e-graph engine is written once
  in Idris and reaches the C++ as compiled MLIR: "I like the second row.
  we can link in bitcode or something." The specification generator
  (stock Idris on Chez) prints the engine and its rules as MLIR (sparse
  tensors where the relations are, loops elsewhere); the pinned
  toolchain's own MLIR and LLVM passes, the sparsifier among them,
  compile it to bitcode before idris-mlir is built, and it is linked
  statically into the C++ tools, as the runtime's bitcode is joined
  today (`LinkRuntime.cpp`), its entry points declared by a header
  generated from the same source. The frontend's elaborator (D69) takes
  an Idris form generated from the same source, so both hosts build it.
  Not C interop: no user code reaches C, and nothing is loaded at run
  time; the generated MLIR is committed under D67. Its design is
  `audits/p0/design/egraph-full/`'s.
- **D87** (2026-10-21; under D85, D86). A sparse tensor library comes
  before the engine: "if this depends on a new idris type that is
  specially optimized for sparse tensors, we clearly need to add that
  first ... the linear arrays philosophy, exact mapping to mlir
  concepts, but this time for sparse tensors." Idris types whose shape
  (D60) and storage format are in their types and whose operations mean
  MLIR's `sparse_tensor` concepts exactly, as `mlir-array`'s generating
  set means the dialect's ops (D42); since the frontend's elaborator uses
  the engine and must build on the stock host, each operation has a plain
  Idris body as its one meaning, replaced under idris-mlir by its dialect
  op through the registry's `Faster` hook (AGENTS.md). Its design, and
  whether the engine written over it reaches the C++ through idris-mlir
  (a bootstrap stage) or through the generator (D86 as recorded), are
  `audits/p0/design/egraph-full/sparse-library.md` and `one-engine.md`.
- **D88** (2026-10-21; L05's quantity × hold, rethought on the
  representation-first source; supersedes D62's "quantity × permission ×
  lifetime"). The grade's coordinates: "bingo. this is good." Today's
  three fields split one question across two of them (who frees the
  memory: `own`/`borrow` and `counted`/`frame`) and crowd two into one
  (`permission` mixes who frees it with what is known about sharing).
  The axes, each deciding different code:
  ```
  hold  = static
        | freed-by { count | lifetime } × sharing { maybe-shared | spine | exclusive }
  grade = uses { once | many } × hold     (only on types that hold references)
  ```
  - *Lifetime leaves the grade*: freed by its lifetime is the old borrow
    and frame states, which lifetime named by the op that made the value
    (D63, C140); freed by the count is the old `counted`.
  - *A view and a cell allocated into a lifetime are one hold*: a
    reference owning nothing, valid inside its lifetime; sharing being
    its own axis, a fresh arena cell can be exclusive and rebuilt in
    place, a view of another's value cannot.
  - *No hold on a reference-free type*: a word carries its bare type;
    "an owned `i64`" cannot be written.
  - *The one illegal state is unwritable*: static data is shared by
    definition, so `static` is its own case, with no sharing level.
  - Every combination it can express is meaningful; every verifier rule
    that hunted a bad combination of the old fields is deleted. Written
    once as D62's algebra in the Idris specification. Names follow the
    naming scheme, separately.
- **D89** (2026-10-21; D88's one essential case). Static data reaching
  code that counts is met by specialization by hold, the runtime's
  static marker its fallback: "c." A call passing a static value where
  the callee would count targets a copy specialized for it, which counts
  nothing (one more axis of D58's finite, budgeted specialization, D57's
  search over legal choices); where every caller passes counted values,
  nothing is tested; only a function that genuinely receives both,
  beyond the budget, keeps the count-0 marker test, a fact unknown at
  that point (AGENTS.md). Static data stays read-only and shared by every
  shard (0007); a sentinel count, which would write it, is rejected.
- **D90** (2026-10-21; names D88, D63, D70, C140; corrects D88's scope).
  The grade and lifetime vocabulary, a hard cutover: "approved all. go."
  *Uses* applies to every type (a linear word is linear); *hold* only to
  types that hold references.
  | concept | name |
  | --- | --- |
  | the wrapper type | `!idr.graded<…>` |
  | uses | `once`, `many` (the IR checks at most once) |
  | freed by its count | `counted` |
  | freed when its lifetime ends | `scoped` |
  | never freed | `static` |
  | sharing, no claim | nothing printed |
  | sharing, its own family's cells unshared (D70) | `unique self` (through every `self[…]` field, D48) |
  | sharing, nothing reachable shared | `unique deep` |
  | the axes in the specification and C++ | `Uses`; `Release` (`Counted`, `Scoped`, `Static`); `Unique` (`None`, `Self`, `Deep`) |
  | a lifetime's type | `!idr.lifetime` |
  | opening a lifetime | `idr.lifetime`, an op whose region is the lifetime |
  | this call's own lifetime | `idr.activation` |
  | lending a counted value for a region | `idr.lend` |
  Printed: `!idr.graded<once, counted unique deep, !List>`,
  `!idr.graded<many, scoped, !Tree>`, `!idr.graded<many, static,
  !String>`, `!idr.graded<once, i64>`. `Static` has no sharing field, so
  `static unique …` cannot be written. Deleted with no alias: `!idr.q`,
  `!idr.lin`, `own`, `borrow`, `plain`, `excl`, `heap`, `frame` as a
  lifetime constant, and the `idr.borrow` and `idr.frame` op names.
- **D91** (2026-10-21; L15 OQ-1, under D10). No assertions, anywhere:
  "a". The toolchain's LLVM and MLIR are built with
  `LLVM_ENABLE_ASSERTIONS=OFF` in every stage our code compiles against
  or links (today ON at `tools/bootstrap.sh:1028` and `:1131`, read), so
  there is one toolchain and the compiler shipped is the one the tests
  ran. Our C++ has no `assert`: each invariant one re-tests becomes a
  type, a verifier rule, or nothing. The price is measured before the
  cutover lands (perf-sources U8: stage 1 against an assertions-off MLIR
  at the same commit), so the record says what the ruling buys. The cost,
  paid by whoever writes passes: a misuse of MLIR's API that an upstream
  assertion would stop at the call shows up later, as a verifier failure
  or as corruption. Not covered: MLIR's verifier between passes, which
  AGENTS.md's quantity rule keeps, and `LLVM_FORCE_ENABLE_STATS`, a
  separate setting.
- **D92** (2026-10-21; L20 Q1 to Q3, set aside). Rust is its own foreign
  runtime: "i think rust should just have it's foreign runtime. it's just
  IO, no special compiler optimizations here. i don't think rust should
  be able to call back into idris." A Rust call is an IO action into that
  runtime; the compiler has no optimization special to Rust, and Rust
  never calls Idris. D30's and D32's promises are about compiled Idris
  and have nothing to cover past the call. Stale in 0020 until it is
  taken: §8.8's callbacks and the cycle check they feed (0020:89, 118,
  148, 537, 578-604), and its Rust-specific counting (the run-time move
  test, 0020:415-417, 684-688). L20 Q2 (when a destructor runs) and Q3
  (moves decided at compile time) wait for 0020, not for P0.
- **D93** (2026-10-21; status.md Q31; amends C140's parameterless type).
  A lifetime's lowering is two facts in two places, a hard cutover: "yes,
  we should hard cutover to your new better representation for
  lifetimes." What the value is at run time is its type's kind,
  `!idr.lifetime<view | room | cursor | home k>` (`view`: nothing
  allocates into it, no value; `room`: a block of static size, a pointer
  in; `cursor`: an unbounded bump, a pointer in and out; `home k`: the
  per-shard home of site k, no value), read in zero steps by every
  allocation, callee, frame, copy and the lowering. Where its memory
  comes from is the op that opens it, one op per source: `idr.lifetime`
  (none, binds `view`), `idr.lifetime.home`, `.block`, `.stack`, `.chain`,
  each fixing its binder's kind. A `view` parameter accepts a lifetime of
  any kind (upstream's generic address space), so a function that only
  reads a lifetime has one body; every other kind is passed only to
  itself, which is the call's type check; a mode copy's function type is
  its key. Every lifetime is born decided: one decide step writes every
  opener, kind, signature and copy, so no undecided lifetime exists in
  the IR. The kind is not an identity (D63: identity is the SSA value).
  Upstream model: the GPU dialect's address spaces, beside
  `memref.alloc` against `memref.alloca`. Unwritable: an allocation into
  a `view` lifetime, a callee given a kind it was not compiled for, a
  lifetime reaching the lowering undecided. Costs: the kind parameter,
  the pure cast `idr.lifetime.forget` (its result the `view` of its
  operand, the one op whose result is a lifetime), and the call rule.
  Rejected: the kinds as a per-parameter property of the function
  (static-handles §4.8), a fact beside the type it describes. Design:
  `audits/p0/design/lifetimes/lowering.md`.
- **D94** (2026-10-21; status.md Q32; under D93, beside D61). How much a
  function puts into a lifetime parameter is a per-parameter part of
  `idr.func`, in the same record as D61's write part: "i agree with a."
  Whether it puts at all is the parameter's kind (D93); the amount is
  `Finite n | Unbounded`, a part only a put-kind lifetime parameter has
  (`room` only `Finite`), as D61's part exists only for an exclusive
  owned parameter, so no part can sit on a parameter it does not
  describe. It is a summary of the body, derived callees first, held on
  the function and checked per function as covering its body (its direct
  allocations plus each callee's amount), re-derived as rows are (C64).
  It is no effect and is not copied onto calls; the caller's lowering
  reads the callee once. Its readers: the caller's layout of a `room`
  block, the decide step, D26's proof. Rejected: the amount in the
  lifetime's type (a fact of the callee's body, not of the value) and a
  copy on every call.
- **D95** (2026-10-21; status.md Q35; reverses C84's cycle clause, keeps
  its tail clause). A lifetime may span a call on its function's cycle,
  one lifetime per recursion level: "a." Where idr-frames turns such a
  call into a push and a jump (D31, D32), it splits the region lexically:
  before the push the region ends by packing its lifetime into a linear
  value (for `.stack` the mark, one word; for `.chain` the chain), the
  frame holds the package, and the resume opens a region binding a fresh
  lifetime value from it, its held values restated by the pop. Every
  region stays lexical in its function, the jump stays `musttail`, and
  the frame stack's linearity makes a second unpack unwritable. A
  per-level lifetime is `.stack` or `.chain`, never `.block` (a block's
  cells cannot move into a frame). D26 holds: each level's instance is
  held by an active call, and keeps its count or spine proof (C84). The
  pack and unpack pair is built once, for this and for 0007's moves
  between shards. Why: the code that most wants lifetimes (a parser, an
  evaluator, a tree builder) is on call cycles (review.md §3, read at
  `audits/p0/verify/review.md:223-238`); the gain is measured as it is
  built (static-handles M6). Design: `design/lifetimes/lowering.md` §6.
- **D96** (2026-10-21; status.md Q33). No lifetime is handed over at a
  tail call; every lifetime ends in the function that opened it: "A."
  C84's tail clause and C97 stand. An outer lifetime passed through a
  tail call as a parameter already serves a loop building its result
  (constraints V8), and in-place reuse (D24) gives constant space to a
  loop whose state points into the last; a handed-over lifetime would
  chain arenas that D26 refuses unless every cell stays live. D95's pack
  and unpack pair allows it later as one rule if a measurement asks
  (prior-art M5: sites kept counted because of a tail call).
- **D97** (2026-10-21; reaffirms D85 and D86 with their reasons; settles
  status.md item 38). The e-graph is for one shared representation,
  elegance, and QTT pushed hard enough to make bugs unwritable, never for
  speed: "i like egraph not for speed, it's for shared representation,
  elegance, and pushing qtt extremely hard to remove bugs. obviously
  idris over c++ is preferable"; "let's push very very hard." The engine
  and its library layer (`design/egraph-full/machine.md`, under research)
  are written once in Idris in QTT's style: every table quantity 1 and
  updated in place, bounds and capacities erased proofs, the engine's
  phase an erased index, so a misuse is unwritable and no check is
  printed. Speed is measured, never the reason. It stays in P0, so R4 in
  P0 is the whole engine, not only the union-find O7 consumes. Weighed
  and not reopening D85, whose reason was never speed: speed.md (the
  speed comes from compiling a specialized engine, which C++ would give
  too), sparse-mlir.md (sparse tensors cover matching only),
  one-engine.md §8 (three strains on AGENTS.md, still to settle).
- **D98** (2026-10-21; supersedes C47 and C48; under D97). The greedy
  rewriter is cut over at the earliest moment, in P0, with no interim
  form: "cutover the greedy rewriter ASAP. wipe it off the face of the
  earth, cutover at the earliest moment." At every point of the pipeline
  that holds our ops (today upstream's `canonicalize` and `cse` at
  `foreign/idr/lib/Transforms/Pipeline.cpp:93-94` and `:116-117`, read)
  and as upstream `Inliner`'s simplification pipeline, the e-graph pass
  takes their place. Our own three calls of the greedy driver go
  (`Optimize/Optimize.cpp:65`, `Narrow/Copy.cpp:128`,
  `Narrow/Narrow.cpp:128`, read), each becoming e-graph rules, one walk or
  a dialect conversion. Our ops carry no canonicalization pattern and no
  DRR (C47 withdrawn), and C48's configuration of upstream's canonicalizer
  with its two carried patches is never built. An op's fold stays its
  meaning, read by the e-graph and by `createOrFold`. The e-graph's chain
  (the rule language in the specification, the sparse library, its
  library layer, the engine) is the first work of S6, since every other
  pass redesign meets its output. Open, to the owner next: the points
  that hold upstream's ops only (`Pipeline.cpp:167-168`, `:181-182`) and
  the upstream passes that run the driver inside (`Pipeline.cpp:153-164`).
- **D99** (2026-10-21; D98's upstream half). Upstream's passes are never
  duplicated: "let's not duplicate upstream's passes." The greedy driver
  inside an upstream pass we run (`convert-linalg-to-loops`,
  `convert-vector-to-scf`, `expand-strided-metadata`,
  `convert-vector-to-llvm`'s pre-lowering; `Pipeline.cpp:153-164`) stays
  upstream's; we neither re-implement such a pass nor configure its
  driver. D98 covers our code and the points that hold our ops.
- **D100** (2026-10-21; D98's open points). Nothing runs at the points
  that hold upstream's ops only: "b." The canonicalize and CSE pairs at
  `Pipeline.cpp:167-168` and `:181-182` are deleted; LLVM's optimizer
  cleans the lowered code, and upstream folds still apply inside each
  conversion through `createOrFold`. The pipeline's own comment says the
  conversions lower everything in their first round (read,
  `Pipeline.cpp:153-164`); a loss in the built output is measured in the
  qualification and recorded, for the owner to rule on.
- **D101** (2026-10-21; `design/egraph-full/payoffs.md` §1.5, §1.6). Our
  libraries change with the compiler's use case, by hard cutover: "if we
  need to tune our idris-mlir libraries and hard cutover linear arrays or
  sparse tensors, we should do it. it should change according to our use
  case. if you don't like the bool, we can fix it." `mlir-array`,
  `mlir-linear` and the sparse tensor library (D87) are reshaped wherever
  the engine, the parser case or a representation calls for it, with no
  compatibility. The fork's `WithBounds` (`compiler/idris/src/Libraries/Text/Bounded.idr:48-53`),
  whose `isIrrelevant : Bool` sits beside bounds that are junk when it is
  set so that the functor and monad identities fail (measured,
  payoffs.md §1.5), becomes a sum (`Irrelevant val | Relevant val
  bounds`), fixed in the fork as its own code and recorded in `PINS.md`.
- **D102** (2026-10-21; `unknowns.md` U1, owner question 3; amends D13's
  licence and D14's aside). Only the derived effect row licenses deleting
  or moving a call: "A." A call may be deleted when unused, or float in
  the e-graph, only if its row carries neither `crash` nor `divergence`.
  Totality, as upstream defines it, removes divergence (no divergence
  effect, `mustprogress`), never a crash: stock Idris reports
  `g x = div x 0` total and it crashes (measured: the prelude's `div` is
  `case y == 0 of False => ...` with no zero arm, accepted in the prelude
  and refused in user code, `third_party/Idris2/libs/prelude/Prelude/Num.idr:127-133`),
  and base uses `assert_total`. A crash is an effect of any code that can
  reach a failing check; where a divisor or index is proved safe (a
  constant, an interval, a type) the check folds and the row is clean.
  The rule language's `Total` condition (`egraph.md` §3.1, E6) becomes a
  row condition. D14's "a crash is partial code failing" reads "a crash
  is a failing check". Not decided here: whether the fork's checker is
  fixed to report the prelude's `div` as not total.
- **D103** (2026-10-21; `unknowns.md` U13, owner question 1; under D57,
  D85, D97). Effectful ops stay outside the e-graph, in a skeleton that is
  a partial order per resource subtree of the effect tree, with one-way
  rules on it: "c." Pure values (reads of immutable memory among them,
  which have no resource) are saturated in full; an op whose row orders
  it has no alternatives in the graph, so extraction stays polynomial and
  deterministic and effect order cannot be broken by the engine. Each
  resource keeps only its own order: a read of mutable memory may be
  placed across a crash check (D21) or out of a loop that writes no
  memory it reads; forwarding a written value and deleting an overwritten
  write are one-way skeleton rules. Two quantity-1 values are distinct by
  type and D61 gives each exclusive parameter its own effect part, so
  their effects order independently with no alias analysis. Rejected:
  a one-line skeleton (gives up those moves) and effects inside with a
  state token per resource (effect-safe extraction NP-complete; no real
  case needs cost-chosen order on one resource). Rests on reasoning;
  `design/egraph-full/effects.md` (under research) checks it on real IR,
  and a contradiction returns it to the owner.
- **D104** (2026-10-21; `unknowns.md` U28, owner question 4; under D101,
  D103). A linear parser's input is a quantity-1 handle to immutable
  bytes: "a." A read has no resource, so every peek is a pure value that
  floats in the e-graph (shared across `<|>`'s alternatives, hoisted for
  first-byte dispatch, deleted when unused); tokens are views scoped by
  a lifetime (D93); releasing the handle is the one ordered op. A unique
  mutable buffer is frozen into such a handle in place and thawed back in
  place once every view's lifetime has ended, which the lifetime rules
  check, so reusing a buffer copies nothing (a proposal for the
  libraries under D101; `Linear.String.Iterator` already has this shape
  for strings). The library's failure result hands the handle back
  unconsumed, so `<|>` may retry and un-factoring stays linear-safe
  (`unknowns.md` U28). Rejected: a mutable buffer, whose reads are
  ordered skeleton ops that never merge.
- **D105** (2026-10-21; `design/egraph-full/workloads.md` §3.2, §5; "ok,
  let's add the two bug fixes too"). Two representation bugs the
  real-workload run found are fixed in the cutover:
  - *A `Nat` literal is one constant.* The frontend emits a literal of
    64 as 64 chained `idr.big.add(_, #idr.big<1>)`
    (`IdrisMLIR.Ids.len17to128`, measured: 5,211 e-graph nodes for one
    constant); it reads the literal once at the boundary and emits its
    value as one constant of its representation.
  - *A case binds its scrutinee refined.* Each case of a match binds the
    scrutinee refined to that case's constructor (its family at the
    refined index, D48), and the fields are reads of that refined value
    (total, since its type fixes the constructor), as a guard returns
    its operand refined (D21). Today a case binds its fields alone, so a
    rule that rebuilds the constructor from them equated it with the
    unrefined scrutinee and decided 1,347 matches in the frontend and 17
    in the benchmarks wrongly (measured, workloads.md §5). Corrects
    `egraph.md` §2.2's claim that a case already binds its refined value.
- **D106** (2026-10-21; narrows D85 to D87 and D97). The e-graph stays
  narrow and the bulk of the work is MLIR: "let's keep the egraph stuff
  narrow but the bulk of the focus should be using mlir. the frontend
  stays the frontend, mlir stays mlir." Narrow: it replaces greedy
  rewriting on our ops (D98) and nothing else; its rules are today's
  local patterns with the choice per arm; algebra and theorem rules
  only one-way and narrowly triggered (workloads.md: they found nothing
  extraction kept and caused every budget stop); no e-graph research
  beyond what is running. How "the frontend stays the frontend, mlir
  stays mlir" bears on D85 to D87's one engine shared across the
  boundary is the owner's next question.
- **D107** (2026-10-21; reverses D86, D87's place in P0, D85's and D97's
  one engine written once across the boundary, and D97's settling of
  status.md item 38). Each side keeps its own, and only the rules are
  shared: "a." The optimizer's e-graph is built from MLIR's own
  mechanisms, upstream first and patched where they fall short (the
  hash-consing CSE uses, the pattern machinery, the fold hooks, the
  effect interfaces, the rewriter), in C++ as the dialect's passes are,
  concept-constrained templates; its exact MLIR form (the research
  `eqsat` dialect's classes as ops, or a pass holding its own tables over
  MLIR's ops) is a design step under D106's narrow scope. The frontend's
  elaborator keeps its own union-find in Idris, which is all its
  unification and constraint store need (it merges, never searches), so
  R4 in P0 is what O7 consumes (item 38). The rules and their laws are
  written once, in the dialect's Idris specification, and generated to
  each side as the TableGen is. Gone from P0: the Idris engine printed as
  MLIR and linked as bitcode (D86), the sparse tensor library as its
  prerequisite (D87; it may come later as a library on its own merits),
  the engine's library layer, the route question, and the strains on the
  C-interop rule (`one-engine.md` §8). D97's "shared representation"
  narrows to shared rules and laws; D103's skeleton, D104 and D105 stand.
  Why: "the frontend stays the frontend, mlir stays mlir" (D106), as
  AGENTS.md's "Idris does types; MLIR does programs"; the measured value
  is the local rules (`workloads.md`), which are shared without sharing
  an engine. `one-engine.md`, `sparse-library.md` and `machine.md` are
  kept as the record of the route not taken.
- **D108** (2026-10-21; `unknowns.md` U17, owner question 2; under C15,
  C16). The e-graph's budget counts nodes, from the program alone: "a."
  A function's budget is B nodes per op, so its arena (B × its ops × the
  bytes per node) is known before its search starts; the worker pool
  admits functions only while their arenas fit the host's memory, so a
  small host compiles more slowly and never differently, and output is
  byte-identical on every machine and at every thread count (C16). A
  function whose arena alone exceeds the host's memory ends the compiler
  through C15's one out-of-memory handler with its named line, a crash of
  the machine, never a refusal. Measured scale: median 3 ops, largest
  4,287 on the frontend's own IR before defunctionalization
  (`workloads.md`), about 105 MB at B = 64 and 384 bytes per node
  (`speed.md`; arithmetic). Rejected: a budget read from the host's
  memory (output varies by machine) and a fixed cap for the smallest
  host (a round constant).
- **D109** (2026-10-21; reaffirms D107 and AGENTS.md's "Idris does
  types; MLIR does programs"). Idris is representation and every
  optimization is C++: "can we keep it all c++ only? idris should be pure
  representation, none of the optimization stuff. within reason. don't
  take that too literally." The e-graph and every pass that makes code
  faster or smaller run in C++ over MLIR. The Idris side holds what
  represents: the frontend's checking, elaboration (its own union-find,
  D107) and representation decisions; the dialect's specification, whose
  declarations include each op's rules and laws as data, generated into
  the C++ as the TableGen is, never run in Idris; and the libraries
  (`mlir-array`, `mlir-linear`). Within reason: the specification states
  a law, the C++ uses it.

## 3. The coordinator's decisions (for the owner's review)

Made under D6, each with its reason, its evidence and the questions it
closes; the owner may overturn any of them. Drafted in
`audits/p0/synthesis/G-coordinator-decisions.md` for decision points
DP-22 to DP-84 and folded in here after the coordinator's review.

- **D110** (2026-10-21; L08's finding; amends D90's `unique self`).
  `unique self` reaches into in-place fields: "whatever you prefer for
  the first." It means the value's own family's cells unshared and,
  recursively, the own cells of every field whose type is an `in_place`
  family, read once from the family declaration. So D72's obligation on
  a linear record holding a linear list is `unique self`: the record's
  cell and the list's spine, never the list's elements (D70), and a
  record whose list holds shared elements is rebuilt in place as D70
  promises. No new grade case.
- **D111** (2026-10-21; the integration's build, this cutover). The
  integration lane does the Idris half on this machine and stops at the
  LLVM build: "i feel like a the second." It wires the build files, runs
  the specification's generator on the stock host, builds the
  specification, the frontend, the fork and the libraries on stock Idris,
  and routes each error to its lane overnight; the toolchain's bootstrap
  and the C++ build on the four targets run on the owner's machines, and
  their failures are routed the same way.
  *Widened* (2026-10-22, the owner): "you can build everythinrg except
  for llvm proper. everything else is deferred to my other machine." So
  this machine builds the whole Idris half (the specification and its
  generators, the checker, the frontend, the libraries, the harness, the
  frontend's runs over the fixtures, `make check`) and our C++ against
  the TableGen-only typecheck toolchain, each lane on its own export;
  the LLVM build and everything that needs it (our C++ against the
  assertions-on MLIR, the suites that run our tools) are the owner's
  other machine's.
- **D112** (2026-10-22; the owner, on the assertions). "why are we doing
  so many assertions? can we fix a lot of the assertions pls? especially
  for our own compiler. we should strive to prove things rather than
  assert them, or refactor the represnetations such that invalid states
  are unrepresentable." Every check our code makes of its own invariant
  at run time (an `internal` error in the frontend, an internal error or
  `llvm_unreachable` in the C++, an `assert_total`, `assert_smaller` or
  `believe_me` in the fork) is removed by changing the representation so
  the state it rules out cannot be built, or by carrying the proof. One
  stays only where the fact is not known until run time (the program's
  input, the machine, which registered op an `Operation *` is), and the
  code that keeps it says so. The host's declared trusts are reviewed by
  the same rule: each one Idris can prove is proved.
- **D113** (2026-10-22; the owner, on the code rewritten for the
  compiler). "we should undo the damage from rewriting our parser in a
  simpler form taht our compiler can handle, our codebase should be great
  as fuck. our compiler is better now and we should be doing the
  maximally good thing for our code." Code of ours that was rewritten
  into a worse form so that an earlier compiler could compile it is
  rewritten back into its best form: the fork's parser returns to
  upstream's deep embedding, and every rewrite the fork's README lists
  under "Rewritten so that this compiler can compile it" returns to
  upstream's form or a better one. The code is never kept worse to spare
  the compiler. *Corrected* by D116: the coordinator read into this that
  the compiler gains whatever construct the restored code uses (C230,
  C232). The owner never said that, and it would have widened the strict
  subset; that clause is struck.
- **D114** (2026-10-22; the owner, on the C++; amends D91 and D112).
  "c++ assertions are totally fine! the more the merrier! c++ has a
  totally different policy from the idris. in fact, we should probably be
  using c++26 contracts too for correctness!" D112 binds the Idris side
  alone. Our C++ checks its own invariants at run time freely, and more
  of them is better: an internal error stays and new ones are welcome.
  D91's toolchain half stands (LLVM and MLIR built without their
  assertions, one toolchain the tests run and the compiler ships with);
  its "our C++ has no `assert`" is reversed. C++26 contracts (`pre`,
  `post`, `contract_assert`) are the form once the pinned clang has
  them; see C226.
- **C226** (2026-10-22; under D114). How our C++ asserts until clang has
  contracts. An invariant check is always on: it reports a fatal
  internal error, the ending table's `SIGABRT`, never `<cassert>`'s
  `assert`, which `NDEBUG` removes in the one build we ship, and which,
  if `NDEBUG` were dropped for our sources, would also switch on LLVM's
  and MLIR's own header checks against a toolchain built without them.
  Contracts are not in mainline clang (read 2026-10-22: three separate
  implementations and a design document, llvm-project #229978; the
  pinned tree has none, and WG21's P4334 still contests the feature), so
  there is no upstream form to carry yet. When mainline has one, the
  weekly toolchain bump brings it and the checks become `pre`, `post` and
  `contract_assert`, the contract semantic chosen to enforce.
- **D115** (2026-10-22; the owner; reverses D91's toolchain half). "we
  should turn on llvm and mlir assertions to help us debug too. i don't
  know why we're not enabling them either." The toolchain's LLVM and MLIR
  are built with `LLVM_ENABLE_ASSERTIONS=ON` in every stage our code
  compiles against or links, still one toolchain the tests run and the
  compiler ships with. Our C++ is compiled to match, without `NDEBUG`, so
  the headers it shares with LLVM and MLIR agree, and `assert` is live in
  our code too. The qualification still records the price, now of having
  them on.
  C226 is amended by it: our C++ may use `assert` beside the always-on
  fatal internal error, since nothing removes it any more; the runtime
  compiled programs link keeps its own profile, where a check is a fatal
  error and `NDEBUG` stays, so a program's speed does not pay for the
  compiler's debugging.
- **D120** (2026-10-22; the owner; on the typecheck build). "you should
  just build it without assertions to move past it then. lol." The
  typecheck build (`IDRIS_MLIR_TYPECHECK`: the host's clang against the
  TableGen-only LLVM, nothing linked but `idris-mlir-tblgen`, nothing
  shipped or tested) compiles our C++ against whatever toolchain it has,
  with our units matching that toolchain's `NDEBUG`, so this machine,
  which builds no LLVM, checks the C++ against the toolchain it already
  holds. The builds that link, ship and run the tests (dev, release)
  still refuse an LLVM built without assertions (D115).
- **D121** (2026-10-22; the owner; on upstream bugs). "remember, if
  upstream ever miscompiles sometihng, we patch."; "yes, never dance
  around upstream again. we fix upstream and save the patches." Where a
  pinned upstream (stock Idris above all, the bootstrap host, and LLVM,
  MLIR, Chez) gets correct code of ours wrong, it is patched, the patch
  saved as `upstream/<bug>/<project>.patch` with its report, reproducer,
  check and PINS entry and applied by the bootstrap, and our code is not
  bent around it. The stock-host hazards the lanes were told to avoid
  are bugs to patch.
- **D116** (2026-10-22; the owner; binding). "to be crystal clear, i
  only care that upstrmea compiles our idris-mlir, and i don't care about
  idris-mlir compiling upsteram." Then, the same hour: "idris-mlir must
  self host idris-mlir, that is obviously a goal. it must be compisable
  BOTH from upstream idris and our idris-mlir." Our code (the frontend,
  the specification, the libraries, the test machinery and whatever
  checks types for us) compiles under both: stock upstream Idris on Chez,
  the bootstrap, and idris-mlir itself, which self-hosts. idris-mlir
  compiling upstream's own code is no goal. The language idris-mlir
  accepts stays the strict subset AGENTS.md defines, and is never widened
  past that definition. *Corrected* the same hour: the first text of this
  ruling made upstream the only host and so dropped self-hosting, which
  reversed the two-hosts decision; the owner's second message restores
  it. C230 and C232 stay withdrawn pending D117.
- **D117** (2026-10-22; the owner; the fork). "why do we maintain an
  upstrema fork? lol. we should purge the fork entirely. there should be
  only raw upstream, and idris-mlir. if upstream idris miscompiles it for
  some reason, we should PATCH upstream, not maintain a fork."; "why the
  fuck are we maintaining a fork of the upstrteam idris compiler? i don't
  care about upstream at all. our code is gonna be way better. edwin
  brady's code is just a slop bootstrap." There is no fork of Idris's
  compiler: `compiler/idris` goes. Raw upstream Idris, pinned and
  unmodified, is the bootstrap host only, and a bug in it that our code
  meets is patched in upstream (`upstream/<bug>/`), never forked. What
  checks the types of the programs idris-mlir compiles, once the fork is
  gone, is §4's open question (raised 2026-10-22). *Answered* by D118.
- **D118** (2026-10-22; the owner; answers D117's question). "the fork
  shouldn't be a "fork", it's just copying over code into our own tree
  with no arbitrary boundaries, and stamping it with the spdx identifier.
  we could keep it clean, but no compiler/idris, we call it something
  else. compiler/idris is just too vague. see, i think a lot of this fork
  discussion is actually just confusing about terminology because of bad
  naming. this clearly isn't a fork, it's like how openbsd/freebsd are
  copying code from each other with proper attribution and fusing it into
  their own tree." The type checker idris-mlir uses is our code: Idris's
  checker, copied into our tree with its attribution (each file's SPDX
  line and copyright kept), and ours to change freely from then on. It
  tracks no upstream: no re-sync, no pin it follows, no list of files
  kept against upstream's, no diff kept for a merge, no rule that
  upstream's form or interface be preserved. It sits behind no arbitrary
  boundary: no import rule fences it from the rest of our code. It lives
  in a directory named for what it is (C233), compiles under both hosts
  (D116), and its best form is ours, written in the strict subset.
- **C233** (2026-10-22; under D118). The checker's name. `compiler/idris`
  becomes `compiler/checker`, its package `idris-mlir-checker`: it parses,
  elaborates and type-checks Idris and holds the checked definitions the
  translation reads. Its modules keep their names (`Core.*`, `TTImp.*`,
  `Idris.*`, `Parser.*`, `Libraries.*`). Deleted with the fork's
  framing: `tools/extract-idris.sh` and `compiler/idris/MODULES` (the
  re-sync), the README's re-syncing and upstream-bug sections, every
  `upstream/fork-*` record and `pull-request.diff` (a bug in our checker
  is fixed in it like any of our code), the PINS entries that describe
  the checker as a fork, and AGENTS.md's import fence.
- **D119** (2026-10-22; the owner; the checker's code). "yes, obivously
  we should improve the paser code. upsteram code sucks. it should be
  using fully goated parser combinators that porperly leverage qtt. that
  type passing bullshit is really bad. that's just called bad code." The
  checker's parser is ours, written fresh: parser combinators that use
  quantities, the token stream and the parse state threaded linearly so
  idris-mlir updates them in place and counts nothing, termination proved
  by the types (a consuming parser's evidence that it advances), and no
  type passing: no constructor field whose type the constructor hides,
  no `Type` held at run time, no type computed from a run-time value.
  The same holds across the checker: where Idris's code passes types
  around (the extensible metadata records, `TokenKind`'s `TokType`,
  `CommandLine`'s `ActType`, the tokenizer's hidden tag), ours states the
  types it means. Upstream's form is never the target (D118); L17r's and
  L17s's restorations of it are replaced by this.
- **D122** (2026-10-22; the owner; §4's question on L08's finding E2
  against C185; amends D90 and D110, reverses C185's claim level). "i
  take your rec": A. `unique self` also covers the storage of a buffer
  an own cell holds, never its elements, as D110 extended it to
  `in_place` fields; a buffer-holding `in_place` type (`LArray`,
  `Linear.Vec`) obliges `unique self` as every other `in_place` type
  does. A linear array or vector whose elements are shared values, or
  whose size may be a big, claims it, and the eight programs C185 refused
  (linarray-fill-sum, -bubble, -push-pop, -reserve, -read-past-size,
  -write-past-size, -records, vec-pop-then-push) compile. The field read
  gains a reach, a buffer an own cell holds, through which a claim on
  own cells reaches the buffer's storage alone; a constructor's cell
  claims `unique self` only where each buffer it holds does; the
  family's promised claim is `unique self` for every `in_place` type; and
  bufferization writes a held buffer in place where the cell claims
  `unique self`. The exclusivity check reads the promise and does not
  change. *Corrected* (recheck 4, the coordinator's record of the
  ruling's consequences, not the ruling): whether an own cell holds a
  buffer keeps one reader and stays, the boundary grading of a
  quantity-1 parameter (`InPlace/Rule.cpp`'s `boundaryAsks`), where it
  says when the promise binds, never how much it claims.
- **D123** (2026-10-22; the owner; §4's question on L14's evidence;
  under D97, D98 and D106; settles D57's union). "A": the e-graph is a
  true one. A fired rule adds its right side to its left side's class
  and both forms stay; classes merge through a union-find, and
  congruence is restored after each round of merges; a class keeps what
  every member's facts say of its one value, met, so `mod x 8`'s [0, 7]
  stays with `andi x 7`; extraction chooses each class's member by
  cost, the engine's own (an op one, a constant none) until a measured
  model replaces it. The interim that carried a replaced node's facts to its
  replacement goes, with the replacement. Rules run in a fixed order of
  rounds and stop at the specification's budget (D108's `nodesPerOp`),
  a spent budget leaving the program less optimized, never refused.
  Costs: a union-find, merges with their rebuild, and an extraction that
  works, in L14's engine, within D108's admission. Whether the e-graph
  calls folds stays §4's question, apart.
- **D124** (2026-10-22; the owner; §4's question on lending an array to
  upstream's ops, L08's and L05's evidence). "B": a loan is a projection
  under a lifetime token, `idr.carrier %v in %l`, with no region of its
  own. Its result is the bare carrier an upstream op takes; `%v` stays
  its holder's, no count changes, and `%v` outlives `%l`. A scoped
  parameter is projected under its own lifetime; a counted value is lent
  under a lifetime opened around the uses, as D63 puts the lifetime on
  the op that makes the value. A bare alias names no lifetime, so the
  three escapes are refused by one check over upstream's own alias
  interfaces (`ViewLikeOpInterface` for memrefs, bufferization's
  `getAliasingValues` for tensors), run as a verifier after every pass:
  an alias of a loan never leaves the region that defines its lifetime
  or returns from the function, is never the value a write stores, and
  is never adopted by an op of ours. `shareIntoCarriers`, the `readBare`
  exclusion and borrows' rule counting every parameter an upstream op
  reads go. The grade keeps its shape (D88, D90); C's scoped memory
  space is not built, and is open to a later ruling on evidence that the
  check is where escapes are missed.
- **D125** (2026-10-22; the owner; §4's question on 0011's O5, L17's
  evidence). "B": O5 is the flat parse tree and its decoder to `PTerm`
  (C216's first half), and nothing more. Names are resolved where Idris
  resolves them, during elaboration against the typed environment, and
  Desugar keeps its bound-name set as it reads it now. Resolution as R1's
  interval join comes with a later stage, not P0's, that moves Desugar
  onto the parse tree's tables, so the join has a reader when it is
  built (0011 §4.5 records it). O5's bar is parse alone: identical TTCs,
  parsing no slower than 0010's A0. So O5 needs no part of 0015's
  library, and P0 builds neither the join, nor a row per clause for its
  pattern variables, nor fields carrying binders into Desugar.
- **D126** (2026-10-23; the owner; L06c's measurement of the C++'s type
  dispatch). "i agree on this principle. let's do it and push hard":
  every question a ladder asks becomes one interface method declared in
  the Idris specification, with its `.td` regenerated; the C++ then
  dispatches through that interface, a typed signature or a typed walk,
  and no `isa` chain remains over our own ops, attributes or types. A
  ladder over upstream's types uses upstream's own kind enums or
  interfaces; a function that takes a bare `Operation *` and casts takes
  the op's type; a walk that tests each op is a typed walk. A templated
  visitor in C++ is not the form, since it keeps a second copy of what the
  specification declares. Measured at HEAD by L06c: 94,405 lines of C++
  in `foreign/idr`, 1,011 `isa`/`dyn_cast`/`cast` sites, 27 ladders of
  three or more tests of one subject.
- **D127** (2026-10-23; the owner; §4's question on folds, recheck 3's
  finding). "yes. the compiler MUST compute constant strings, doubles,
  and big integers at compile time. obviously." Option C: the e-graph
  holds a string, a `Double` and a big integer as values of its own
  (bytes, an `APFloat`, the runtime's limbs), computed by the runtime's
  own functions through `Fold.h`'s conversions made generic over the
  domain, as the numeric template already is, the op's fold its
  attribute instance; no attribute is made until the write-back
  materializes the extracted winner. A fold the specification marks
  `NeverFolded` (a C library function whose last digit is each
  library's) stays unfolded, and so does a result IEEE does not fix (a
  NaN). D98's "an op's fold is its meaning, which the e-graph reads"
  holds as written; C205 and C218 are amended so the graph reads that
  meaning without making attributes. The lowering's comment that the
  optimizer folded what folds becomes true.
- **D128** (2026-10-23; the owner; §4's question on C257's stop,
  L16da's evidence). "i recommend A": the translation walks a settled
  implementation (a dictionary or a polymorphic function applied to
  closed arguments) as written, its arguments bound once, as the growth
  model's site walk does (`Sites.applyHead`), never by the host's
  normaliser (`Terms.lambdasApplied`, `normaliseHoles`), so the two walks
  visit one structure and every request is tied to its site by walking
  (C257). A closure argument is bound once by a `let` and called where it
  is used, not inlined at each use; inlining is the C++ pipeline's
  (specialization, defunctionalization, the inliner), measured at
  qualification. Keys still read through the host's normaliser (D68). The
  growth proof stays over the code (D46), and with C257's site walk the
  run-time re-check is deleted.
- **D129** (2026-10-23; the owner; §4's question on a tail call's data
  result, L16dv's evidence and the research lane's reading of upstream
  and prior art). "b star is good": B*. A tail call whose result layout
  differs from its caller's targets a copy of its callee keyed to the
  open layout: the result's closed indices are `opaque` in the key, so
  the copy returns what an index unknown at compile time would (a
  `Vect 4 Int` in a cell, a `Fin 256` as a natural), and the copy's own
  tail calls ask for the open layout in turn. It is one more axis of
  D58's key (closed or open, per result), beside D89's hold, so the key
  alphabet at most doubles and the copies end by construction, with no
  budget and no fixpoint; it never refuses a program. Every non-tail
  call keeps D58's in-place result. The call verifier checks that every
  tail call's result layout is its caller's, beside the given-back
  results, and a residual mismatch is an internal error (D30); a
  re-packing reindex never carries a tail. LLVM's `musttail` rule
  (identical return types) stays the last check, below ours. Rejected:
  A (every result in the open layout, undoing D58 at every function
  result, paid at run time by every program), D2 (one layout per group
  tied by tail calls, which takes the in-place result from every non-tail
  caller in a mixed group and rewrites signatures after Emit) and C (the
  lost tail call, against D30). C262's array result is the same rule's
  array case, unchanged.
- **D130** (2026-10-23; the owner; L18y's evidence on D129's open
  copy). "1 is good": a data type carries a layout mark,
  `!idr.data<#Vect[4] open>`: the indices Idris proved stay, and the
  value is laid out as at an unknown index (a cell where its indices
  would put it inline). D129's open copy returns its result marked open,
  so nothing it knew is dropped: a match on it still knows its indices
  and prunes the cases they rule out, and the reindex after a redirected
  tail call is refined by the scope rule as any other, unchanged. The
  mark is part of the type, so layout is still computed from the type;
  refinement and identity of indices ignore it, substitution keeps it,
  and the layout classes and layout comparison read it. It follows
  upstream's own form for one shape in another layout (a tensor's
  `encoding`, a memref's `layout`). Rejected: a data index's known value
  kept in the function's extents beside an opaque type (C262's form,
  which arrays keep only because the tensor type is upstream's), and a
  stated trust in the redirected reindex.
- **D131** (2026-10-23; the owner; L18y's evidence on `tests/vect`, the
  converse of D129). "A": the index language gains addition. A term of
  sort `Nat` may be a sum of levels plus a count, in normal form (each
  level once with its multiplicity, then the count; `n + 0` is `n`, a
  level plus a count stays the successor form it is), read off base's
  `plus` on `Nat` by identity, as `IO` is recognised. So a copy D58 keys
  at closed inputs has a closed result where its type sums them
  (`reverseOnto` at 0 and 3 returns `Vect 3`), its tail calls key copies
  that return the same closed layout, and the copies end by construction;
  vect's tail call is made with no mechanism of its own, and every length
  computed from known lengths is known (append, concat, reverse). A match
  on a sum learns nothing of its parts, which is sound. Rejected: keying a
  callee to its caller's closed layout with nothing proving the sum (B),
  and opening every such caller (C). What a sum cannot express stays
  `opaque`: C267.
- **C236** (2026-10-22; recheck 3, L14's finding on §5.2). `IdrSolver`,
  the solver layer, is built over MLIR's own analyses and call graph
  (C33, C114), so it names MLIR; what it keeps is keyed by dense ids,
  never by an IR handle. §5.2 is corrected to say so, in place.
- **C237** (2026-10-22; L17y's finding, under D119 and D112). A grammar's
  type carries an erased bound on the tokens it may read, and recursion
  between grammars goes through a box: a grammar indexed by n may call a
  boxed grammar only at a bound below n, which it reaches by consuming a
  token, and one fixpoint combinator ties a grammar to its boxed self.
  So every grammar of the checker is total by its types, mutual
  recursion included (an expression inside brackets is an expression
  again), and `Idris.Parser` sheds its `%default covering`. This is the
  sized-parser discipline of total parser combinators (Danielsson's;
  Allais's agdarsec), on L17w's linear shallow embedding, with the bound
  at quantity 0 so it costs nothing at run time.
- **C227** (2026-10-22; L16's growth passes; under D68, extends C221).
  An eta-redex around a stuck call reads as both forms. A site's
  `\x => F m x`, with `F` stuck on a marker, contracts to `F m`; at an
  instance where `F` unfolds, the lambda stays around its unfolding, one
  level taller, and no rule wrote that. The reading is the choice of the
  contracted call and the walk under one lambda per argument the call
  lacks, as a stuck call is already read beside its unfolding, so the
  template covers what each instance reaches. A program this newly
  refuses is one whose instance the old reading under-counted, which the
  run-time re-check would have stopped; an instance that contracts a
  lambda the site keeps gets its rule too. `believe_me` reads as the
  argument it returns.
- **C228** (2026-10-22; the Emit pass under D112). The frontend's core
  term carries what Emit reads off it. Emit re-derives facts the
  translation knew and checks them as internal errors: a call's arity,
  the result type of a lambda or a suspension, the type of what a case,
  an application, a resume or a tensor op takes, a tensor axis within
  its operand's rank, a literal case's key kind, a word load's width.
  The term holds each: a call holds its callee's signature with its
  arguments as a vector of that length, a lambda and a suspension their
  result type, a case, application, resume and tensor op their operand's
  type, an axis is a `Fin` of the rank, a literal case is keyed by one
  literal kind, and a word load or store names a closed word type. The
  translation builds each where it already knows it; Emit reads it and
  checks nothing. An operand nothing in scope defines and a family the
  table lacks become unrepresentable the same way, by scoped values and
  a family identity that indexes its table.
- **C229** (2026-10-22; recheck 3). Two rules the tree left unapplied.
  The upstream dialects' Idris modules that `idris-mlir-tblgen` writes
  (D51, through `tools/dialects.sh`) are generated files like the
  specification's: committed, no stamp in any file, and regenerated and
  compared by `make test-mlir-tools`, where the C++ generator is built;
  they take no entry in `generated.manifest`, which keeps one writer
  (C199 amended). And `tools/check-units.py`, a Python program of ours,
  goes: anything of ours above the C++ is Idris, and shell only as
  glue, so the typecheck build's per-unit syntax check is written in
  Idris or done by the build's own compile of each unit.
- **C230** (2026-10-22; *withdrawn* by D116 the same day: the language is
  never widened to compile the fork). (2026-10-22; under D113, with C174
  and C213). What the
  frontend gains for the fork's restored code. A constructor field whose
  type the constructor hides (upstream's `SeqEat`, `SeqEmpty`, holding a
  grammar and a continuation at a first result type the constructor's
  own type does not show) is a closed sum at each instance of the
  family: one alternative per hidden type the whole program puts there,
  each with its fields at that type, so a match on it dispatches and
  calls the code monomorphized at that type, as C213 does for a
  polymorphic value. A constructor that fixes its family's index
  (`NextIs`, `EOF`, `Bounds`, `Position`) is D48's equation. A recursion
  at the hidden type, or from `WithBounds ty` to `ty`, is a recursion at
  a type the program fixes, which the growth graph bounds. Only a hidden
  type set no analysis bounds is refused, as `runtime closure` refuses
  today, naming the site.
- **C231** (2026-10-22; the translation's D112 pass). Two of its
  judgement calls settled. A registry row that a library's definition
  contradicts is the boundary's to refuse, once: the validation that
  already refuses it with `hook shape` hands the translation a validated
  row carrying that evidence, so the twenty-two places that re-tested it
  (now refusals, before that internal errors) cannot meet a bad row and
  go. And a type whose binders a runtime value decides is refused once,
  as `value type`, where the program's types are first read; the growth
  check's reading (`staticsOver`) and the instance table's take a type
  already admitted, so neither aborts nor refuses on its own.
  (C232's narrowing of this refusal is withdrawn with C232, by D116.)
  *Sharpened* (L16bk's finding): the admission is per instance, not per
  definition. A member at a use (`{0 t} -> (f : t) -> t`) and the growth
  walk's readings meet types whose binders only the static arguments
  show, which no definition-level walk with free markers can admit. So a
  type is admitted where it is first instantiated, at the request, with
  its static arguments put in: every binder then shows or the program is
  refused as `value type`, naming the request. `staticsOver` and
  `classifyAt` take the instance's admitted telescope and have no
  missing-binder branch.
  *Corrected* (L16cd's handoff): only `classifyAt` takes the admitted
  telescope. `staticsOver` runs in the growth walk over markers, before
  any instance exists, and its missing-binder case (`PastBinders`) is a
  real one: requiring an admitted telescope there would refuse
  `(t : Type) -> F t` as `value type`, a change of acceptance.
- **C234** (2026-10-22; L16bh's question, under C228 and C123). An
  instance's signature is read once, when the instance is requested, and
  the request holds it: the instance's own step and every call to it read
  that one value, and the step's second classification goes. A result
  type the frontend refuses is then refused once, at the request that
  first meets it, which the refusal names; it was refused either way,
  so acceptance does not change.
  *Sharpened* (L16bj): the request returns the signature indexed by the
  kinds it was requested with, so a caller holds a signature tied to its
  own arguments' kinds by type and re-checks nothing at the call.
  *Corrected* (L16cd's handoff): a cached signature is keyed by the
  static kinds alone, so tying it to a caller's other kinds would mean
  classifying again. What a caller needs of it, which parameters exist at
  run time, is read off the callee's own signature, where it is fixed.
- **C235** (2026-10-22; recheck 3, L04's question). A fold over the
  dialect's types is C52's one `match`: `Support/Match.h` gains the
  overload that folds an `mlir::Type` over the dialect's type list, which
  the specification generates, exhaustively, and `foldDialect`'s chain of
  `isa` and its `optional` go. Our types are a closed set the
  specification fixes, and AGENTS.md takes a fold over a closed sum there.
  A type interface is MLIR's answer for an open set, which this is not.
- **C238** (2026-10-22; the make-check fixes). Two settlements. The
  solver layer's schedule runs in waves through MLIR's `parallelForEach`,
  a component's wave one past the latest it reads, with no atomics, its
  diagnostics in a fixed order and each component's work counted in its
  own slot and summed once (L14); a wave waits for its slowest member,
  the price of no shared counter. And the footprint ledger stays
  per-thread, as C178 says (each pass's footprint counted per thread by
  its one allocator): `tests/mlir-layout` admits that ledger beside the
  three kinds of state it already allows, rather than every footprint
  container carrying a ledger of its own.
- **C239** (2026-10-22; recheck 3, the seam between L16 and L18, under
  D60 and D58). The function op holds the link D60 keys on. `idr.func`
  gains a property, its extents: for each argument and result, and each
  dynamic dimension of its ranked tensor type that an index term names,
  that term over the function's `index_binders`, in the vocabulary
  `index_args` already holds. The tensor type stays upstream's, `?`
  where the size is no constant, as D60 has it ("MLIR's tensor type has
  no symbolic dimension"); the property says which term a `?` is and
  nothing the type says, so its verifier refuses an entry on a static
  dimension or a term over a level the function does not bind. The
  frontend writes it from the source each dimension already records
  (`Shapes.witnesses`), where `extentDim` wrote `Dynamic` and dropped
  the variable; `extentDim`'s second walk of `indexTerm` goes, a
  dimension's term being `indexTerm`'s and static where that term is a
  literal. D58's specialization substitutes a call's `index_args` into
  the callee's extents as into its family types, and a copy whose term
  becomes a constant has that dimension static in its signature, the
  call casting its operand by `tensor.cast`, whose agreement the Idris
  type proves; inside a function, ties stay `idr.tie_shape`. Not a tensor
  encoding: that makes the tensor type symbolic, which D60 declines, and
  every upstream op that infers a result type would have to carry it.
  Not an argument attribute: signature rewrites drop `arg_attrs`, and
  AGENTS.md keeps facts out of what can be dropped.
  *Amended* (L18x's handoff, the same day). Three limits, each with its
  reason. Only an input's axis becomes static in a copy; a result keeps
  the callee's type, since a cast after the call would take a tail call
  out of tail position (D30), and the caller learns no more from a
  result than its own types say. Only an axis of a bare tensor becomes
  static; a graded array (quantity 1, static or scoped) keeps its axis
  dynamic, since no cast keeps a grade, until §4's question on lending
  arrays to upstream's ops is ruled, which leaves the program less
  optimized and refuses nothing. And the static type reaches the copy's
  body through the one substitution, in one walk in program order: each
  op whose result types follow from its operands (upstream's
  `InferTypeOpInterface`) has them inferred again from the refined
  operands, and a `tensor.cast` back to the old type stays only where a
  use's type is fixed elsewhere (a block argument, a yield to its
  parent's result, a return). The walk runs once and needs no fixpoint;
  a cast left where nothing refines past it is the less optimized form,
  never wrong.
- **C240** (2026-10-22; recheck 3, the seam between L16 and L18, under
  D75 and D76). The op that holds D75's promise is the join itself: Emit
  writes `idr.join`, or `idr.loop` for a recursive one, for each
  continuation the program as written makes, so no later pass meets the
  promise as a function it might fail to contify. The program as written
  makes one where a binder the function defines (a `let` of a lambda, or
  a definition local to the function, which Idris lifts under a name
  nested in it) occurs only as the head of a saturated application in
  tail position, of the function or of the binder's own body. Emit reads
  that off the checked term: a syntactic test, total, with no budget.
  A binder that passes it and is emitted as anything else cannot be
  stated: the test and the rewrite are one (C261, amended here). Contify stays what D75 calls optimization, finding the rest
  after inlining, and stops calling itself a promise; the audit's worry
  that idr-deduplicate merges two source continuations before contify
  sees them goes, since a join is local to its function and no pass
  makes it a function again. Not a promise flag on `idr.func`: a
  function marked as secretly a join point holds the join point twice.
- **C241** (2026-10-22; L04x's handoff, under C239, D58 and AGENTS.md's
  termination by construction). Four settlements. A size keys a copy
  only from a call outside the callee's call cycle, or from one inside it
  whose term for that axis is its caller's own: a recursive call that
  changes the term (`go (S n)` called at 0) reaches the copy with that
  axis dynamic, so the keys come from the finite set of calls into each
  cycle and specialization ends by construction, with no budget and no
  number. An entry may hold a constant where the type keeps the axis
  dynamic on purpose (a result, a graded input), so a known size is
  never dropped; only a bare input's constant makes its axis static.
  A call's operands meet its view of the callee by MLIR's shape
  compatibility (`?` meets any size), not equality, so a call at a
  constant size to the general function needs no cast, and the
  specializer casts only where it retargets to a copy. And a refined
  hold reaching a return or a yield takes no cast, the use accepting a
  value whose hold fits its own (`holdFits`). The callers of the
  two-argument `substitute` (L02, L13, L18) pass the callee's extents.
  *Sharpened* (L02y's handoff, the same day): shape compatibility holds
  only at an axis the callee's extents name, where its declared type is
  `?` and a term says which size; everywhere else, a copy's static axis
  among them, a call's operand equals its view exactly. So a call
  retargeted to a copy carries its `tensor.cast` by construction, and a
  missing one is the verifier's error, never the lowering's. One
  function, beside `staticSizeAt` in `Func.h`, holds the rule, and closure
  constants read it too. The one substitution's walk refines no graded
  type's shape, keeping a graded result's old shape wherever the op
  accepts it, since no cast keeps a grade.
- **C242** (2026-10-22; L16bq's handoff, under D68 and C234). An
  instance is classified and translated at its key's forms (normal, then
  eta-contracted), the forms that name it, never at the normalised
  arguments alone: one instance, one reading of its arguments. The value
  put in for a requested parameter is then its argument reading's form
  by construction (`ArgumentFrom`), and `staticReading` keeps the
  `InstanceReading` it computed with the key it caches, rather than
  reading it again. The emitted code may change where an argument held an
  eta-redex; its meaning does not, since Idris's conversion is up to eta.
- **C243** (2026-10-22; recheck 3's sweep, §5.2). `IdrSupport` names
  nothing of the dialect, over MLIR's core (IR and Pass), and §5.2's "naming no MLIR" is
  corrected to that: every library that links it links MLIR
  (measured: its eleven link sites in the CMake files), so an MLIR-free
  `IdrSupport` would buy no link it enables, and its MLIR headers
  (`Actions.h`, `Match.h`'s fold over `mlir::Type`, `Profile.h`,
  `Remake.h`) are the support every pass shares. What must name no LLVM
  or MLIR stays D41's numeric header alone, which the runtime includes.
- **C244** (2026-10-22; recheck 3, L10's seam on C206). Whether an op
  gives its operand on with no run-time work is one op interface,
  `CarriesOnOpInterface`, declared in `Spec/Tail/Declarations.idr`, its
  one method answering with an enum (`Carry`: `Free`, `Works`), as
  upstream's speculatability answers. `ResultCarriesOperand`'s class
  derives from the interface's trait, so every op with the trait answers
  `Free` from one place; `data.reindex` implements it from its types
  (`isFree`), as C206 says. The tail decider and its three other readers
  (`Tail/Context.cpp`, `TrmcRewrite.cpp`, `AccumulatorPlan.cpp`) ask the
  interface, and the `dyn_cast<DataReindexOp>` goes.
- **C245** (2026-10-22; recheck 3's sweep, under C229). Two lines of
  Python in the tools stay, each a host primitive POSIX shell lacks and
  the bootstrap's host provides (LLVM's build needs Python): the
  bootstrap's advisory lock (`flock`, which macOS's shell has no command
  for) and a child's peak memory (`wait4`'s rusage, where hosts' `time`
  differ or are absent). They hold no logic of ours; any that grows past
  a primitive is ported.
- **C246** (2026-10-22; recheck 3's sweep, under C229 and AGENTS.md's
  "anything of ours above the C++ is Idris"). The harness's shell and
  awk (3,768 lines: `harness/lib/*.sh` and `tests/runtime-effects/*.awk`,
  measured) are programs, not glue, and are ported into the harness's
  Idris, which both hosts compile; what stays shell is the glue that
  starts a tool with its arguments.
- **C247** (2026-10-22; recheck 3's sweep, the ladder in
  `Analysis/IdentitiesRecord.cpp:165-190`). How an op's result is built
  of its operands, a constructor of its fields or a natural's successor
  or predecessor of another, is one op interface,
  `StructureOpInterface`, declared in `Spec/Core/Interfaces.idr`, its one
  method answering a closed sum (`Structure`: `Built` with a tag and its
  fields, `Successor` and `Predecessor` with the value, `Unbuilt`).
  `data.con`, `nat.pred` and `big.add` implement it (`big.add` answers
  `Successor` only where one operand is a constant one, from its own
  operands); the identities record asks it where it named the three, and
  its calls, matches and constants keep their own dispatch, each already
  MLIR's (`CallOp`, `MatchOpInterface`, `m_Constant`).
- **C248** (2026-10-22; L16bs's handoff, under C240, D75 and D30).
  Three settlements. An IO action's tail call is a tail call: a call
  whose result the function applies to its world in tail position is the
  action's call saturated with the world, so C240's test reads it so,
  and a local IO loop is a join like any other, since running an action
  never grows the stack however its binds nest. `idr.array.tie_shape`
  gives its array on with no run-time work, so it answers `Free` to
  `CarriesOnOpInterface` (C244), the tail decider looks through it, and
  C240's test reads tail position through the core term's tie, Emit
  tying the join's result where the tie wrapped a jump. And the
  frontend declares no copy of base's `All`: a clash of names is settled
  by qualification or `hiding`, never by a second definition. Accepted
  as written: a `let`-join's tail position measured from its `let`;
  `case` and `with` blocks counted as local definitions, since Idris
  lifts them so; one join op per function, a loop where a member calls
  another; a lambda's or a delay's body joining nothing, each its own
  function after lifting.
- **C249** (2026-10-22; L16bu's handoff, under C242 and C234). The
  readings an instance is keyed by live below the state that caches
  them: `InstanceReading` and the relations it is built of (`FormFrom`,
  `ReadAs`, `Mode`, `Root`, `Keys.Run`) move out of `Growth/Template.idr`
  into a module both `Translate/State.idr` and `Template.idr` import, so
  the readings cache and a request hold `0 reading : InstanceReading ctx
  k t` beside the key, and `ArgumentFrom` is whole. A request's kinds
  are a `Vect` of its callee's applied arity, so a request keying an
  instance by more arguments than it has parameters is unrepresentable.
  *Amended* (L16cb's handoff, the same day): the readings cannot sit
  below `State` while `Closed` and `Keys`, which they read (`markerOf`,
  `EtaNormal`, `MaximalReading`, `writeConstant`), import `State`. So
  `State` splits: what `Closed` and `Keys` read of it moves into a module
  below them, the readings module sits above `Closed` and `Keys` and
  below what is left of `State` (the cache and `Request`), which imports
  it, and `Template` imports the readings. One layering, no cycle, and
  `State` holds nothing the modules below it need.
  *Sharpened* (L16cd, as built): `Errors`, `Closed` and `Keys` hold the
  translation state, so the readings sit below `State` rather than above
  `Closed`: `Definitions`, `Contraction` (the eta contraction, with
  `EtaNormal` and `MaximalReading`), `Literals` (`Run`, `writeConstant`)
  and `Readings` (`InstanceReading` and its relations) come down out of
  `State`, `Closed` and `Keys`, and nothing imports upward.
- **C250** (2026-10-22; recheck 3's sweep and the §6 check, under C39
  and C107). A boxed element's take is counting's, as every take is:
  where an array's element is boxed (`layout::element(type).boxed`, the
  one decision, from the element's type and the target's sizes, which
  counting asks as the lowering does), counting expands the element's
  take into `idr.match_unique`, folded by grade (`unique deep` to the
  unique region, a scoped value to the shared one) and lowered to
  `scf.if` on "count is 1" only where it stays unfolded, as C39 has it.
  `Elements.cpp`'s own test in `takeOut` and its shared path (increment,
  decrement, a new box) go, as C107 deletes them; a known claim pays no
  test at run time, and an unknown one pays it once, in the one form.
  *Corrected* (L07's handoff, the same day). The box has no value at the
  `idr` level: boxing is layout, decided at the lowering from the
  element's type and the target's sizes, so counting has nothing to
  split on, and `idr.match_unique` takes only a value with a cell of its
  own. So the lowering keeps its one test where it first knows the
  fact: whether a copy of the array shares the box is known only at run
  time, and where the array's claim covers its storage (D122's `unique
  self`) no test is made. L12's removal of that test, which left a
  shared box taken from untested, is reverted. C107's deletion stands
  for the wholly placed arrays' test, which is gone; for a shared box,
  copying on write is the program's meaning, not a test of a static
  fact.
- **C253** (2026-10-22; L07's handoff, under C39 and D76). The reuse
  token is `!idr.reuse_token<…>`, C++ `ReuseTokenType`, C39's
  `!idr.token` renamed: join points take upstream's builtin `token`
  (D76), and one name for two types made every unit that saw both
  ambiguous. Its readers (L04, L05, L15, L16, L19, L21) take the new name.
- **C254** (2026-10-22; L16ce's handoff, under D68). Two settlements
  of the growth graph. It draws the arc it now misses: a field read of a
  rank-2 dictionary parameter, applied, landing open with computing
  arguments, inside a field's record, which the graph read as computing
  and so rooted nothing. The analysis models every path the program has,
  so a program growing through that path is refused by the graph, as the
  language's bound requires, rather than met by the re-check; a program
  that does not grow through it is unchanged. And positions are numbered
  before landings are read, so the proof reads a numbered table where it
  needed lookup-after-insert facts base's `SortedMap` does not state; the
  ids change and no verdict does.
- **C255** (2026-10-22; L16ck's question, under C240 and C228). A
  nested block no walk reaches is no part of the compiled program: a
  local definition is a function, not a computation, so eager evaluation
  runs nothing of one no call reaches, and nothing translates it. So
  `Defined` holds its nested-block name only for a block a walk names,
  the split of `Defined` parametrises it by the whole program's facts
  (`Read = Reading Nature`), and no reading meets a block it cannot place.
- **C256** (2026-10-22; L16ct's blockers, the design reader's evidence;
  under C222, C249, D68). A request carries what it was keyed from, by
  type, and nothing is computed and thrown away. `WholeKind`, `NeededCut`
  and `HeldAs` move down into `Readings`, and the cut lemmas beside
  `Closed.cutShape`, so `State.Request` holds, at quantity 0 per keyed
  position, its site's membership and its `HeldAs`, and `TS` the model
  and its site table, written once by the growth check; nothing imports
  upward (`Program` passes the finished lemma down as an erased
  argument). A dictionary's static reading runs `Closed.fixing` once on
  the reading's form and keeps the reduct (`FixedValue` moved down), from
  which classification decides static or choice and the whole
  parameter's entry is matched, in place of the reductions Instances and
  Cases compute and drop; the key stays the reading's form, since keying
  by the frontend's own reduct would make a second evaluator part of an
  instance's identity, against D68, and part from the growth check's key
  at a marker. A call's per-position data is tied to the callee by an
  index on its signature: `NoKey` carries evidence its kind keys nothing,
  the instance cache keeps the `SignedAt` and returns it on both paths
  with each link's holes, and classification returns the values it read,
  so the held values and runtime variables the translation reads twice
  are read once. No verdict and no emitted name changes, which the
  cutover's `make test` confirms; a type computed from a dictionary that
  changed a later binder's quantity, if a program has one, is refused as
  `unsupported`.
- **C257** (2026-10-22; the same evidence; under C222, D68). A request's
  site is found by walking, never by a lookup that can miss. One
  structural `Place`, a step per constructor of the term or case tree
  with the walk's mode a field of its own and a default's expansion a
  step named by its constructor, is moved below `State` from
  `Growth/Sites.idr`, which emits a tree in the writer's shape that the
  growth graph numbers once, as C254 numbers positions; the translation
  threads the place down that tree beside its term, both walks made to
  visit the same alternatives in the same order. Each keyed argument is
  computed from its site's term: the instance's values put in by a
  run-time copy of `Host.putIn` equal to it by `Refl`, then solved,
  skeleton and cut, each step returning its piece of `HeldAs`, so the
  request's equation holds by construction rather than by a simulation
  between two environments; code generation keeps `closeNormalise`. With
  the induction's facts this deletes `Finite.unsound`, `heightWithin`
  and `sizedWithin`. If the translation's reduction of a settled
  implementation does not keep its members' structure as written, the
  site walk cannot follow it and this stops for a ruling; and if the
  proof needs the normaliser idempotent beyond D68's statement, that new
  trust is the owner's.
- **C258** (2026-10-22; L16cv's finding, under C256). An instance's link
  is keyed by everything the instance's code depends on. A held
  dictionary's holes (the types of the runtime values it closes over and
  the binder that holds them) are part of its written argument wherever
  its written form does not already fix them, so two requests that differ
  only in their holes are two links, never one cache entry whose
  signature belongs to whichever came first; the cache keeps the
  `SignedAt` and gives it back on both paths, and a call's per-position
  data is tied to it by type (C256's E). The holes count toward the
  argument's size, and the growth model reads them as the translation
  does (`Sites`' `holedAt`), so the run-time re-check never sees a key
  the model did not bound. Symbol text follows the link; tests check
  behaviour, not symbols. A program whose holes grow without bound along
  a chain needs unboundedly many instances and is refused as
  megamorphic, where today it would share one.
  *Sharpened* (L16cz's evidence): the premise holds, since a hole type
  names the caller's index levels where the form erases them
  (`Terms.argValueIn`), so a cache hit gives a second request the first's
  signature today. The holes are written in the callee's telescope, in
  the link and in the binder the callee reads, never as the caller's
  levels; the universe heights count held positions as parameter
  positions are counted; and the hole key is computed by one function the
  translation and the model both reach through C257's site walk, so it
  lands with that walk and not before.
- **C259** (2026-10-22; L16cv's finding, under C256). A choice's member is
  registered with its dictionary reading, the reduct the one
  classification found, so a dispatch arm's member, a held member and
  `heldHere`'s rebuilt form are fixed by type, matched on that kept
  reduct, and never reduced again; a member whose form does not reduce
  cannot be registered, so no arm meets one, and Cases' whole-parameter
  internal error and its second reduction go.
- **C260** (2026-10-23; the design reader on L16di's stop; under D112,
  D68). A metavariable's solution is read once, at the boundary, by its
  entry. `Reading` holds a table of solutions, filled by `readProgram`
  after the freeze from every metavariable a reached term names, each
  `SolvedAs` its term with its placement and, at quantity 0, Host's
  `Solve` premises for a definition with no arguments and one leaf, or
  `Open`; a metavariable at no entry or of any other shape is refused
  there as `CompiledModule`, as the boundary refuses other malformed
  checked input, which no program reaches (the checker writes a solution
  only in that shape). `Closed.solution` reads the table by the term's
  entry, so its two internal errors and the placement checks in Terms and
  Sites go; no trust is added, the substitution of a solution's `let`s
  stated against the normaliser that runs them. The builtin pair is read
  the same way, into `Reading.pair` (L16's queue).
- **C261** (2026-10-23; the same reader; under C240, C248, D112). Which
  local functions are a body's join points is decided once per body, and
  the body rewritten once: one view of a tail's head (a call, or one
  applied to the world, through ties) feeds a fold that gives each body
  its callees at tail heads and elsewhere, `jumpedBy` and `fitsRuns`
  become membership in those sets, and `joinsIn` turns each member's tail
  head into its jump with every inner slot left as it is, total by
  construction, so `throughAll`, the rewrite run on its own outputs, and
  Programs' internal error go, with `Continuation`'s call arms. That no
  dropped member is still called stays held by the one decision and
  checked by MLIR's symbol table, not by an Idris type, until calls are
  typed by their functions. *C240 amended in place*: a passing binder
  emitted as anything else is unrepresentable, not an internal error.
  *Sharpened* (L16dk's evidence, 2026-10-23): the decision reads each
  local in every region it is rewritten in, a run region included, so a
  world-applied local called inside another local's run region becomes a
  join only where that region calls it only as a run's head; otherwise it
  stays a function, its call a proper tail call and contify free to find
  it, where it would have named a function the program no longer defines.
- **C262** (2026-10-23; L18x's finding, under C239 and D30). No cast
  follows a call. A function's result axes are `?` whatever their term,
  a literal included, its size kept in `#idr.extents` (a constant entry
  where it is known), and the function verifier refuses a static result
  axis, so the type a call gives is the type its slot takes and Emit's
  `fit` never puts a `tensor.cast` or a re-packing reindex after one: a
  cast between ranked types is not free here (an array's words are its
  cell and one word per dynamic size, `memref.cast` lowering re-packs
  them), so a cast after a tail call would take it out of tail position
  silently. A caller reads a callee's known result size from its
  extents; a return of a static value casts before the return. C239's
  "static where that term is a literal" holds for inputs only, amended
  here. And `idr.array.tie_shape`, which carries a tail freely, keeps its
  operand's type by its definition.
  *Sharpened* (L13y's evidence, 2026-10-23): `tie_shape`'s result type is
  inferred, and its inference refuses operands whose `?` axes its sizes do
  not number, so where a specialized copy makes a tie's input static the
  re-inference fails at that op and the substitution's refusal path keeps
  the tie's old type with a cast back (C239's amendment), rather than a
  tie whose sizes no longer match its type; the size count is the
  inference's, with no second verifier. Every C++ place that makes a
  function's signature (the specializer's consumers and requests among
  them) gives dynamic result axes and casts before the return.
  *Sharpened* (L16dv's evidence): "no cast follows a call" binds a call
  whose result its function gives (a tail); a call whose value Idris
  types statically elsewhere (a `let`, a static input, a field) may be
  cast to that type after it, never between it and a return, since binding
  at `?` everywhere would lose the size the value's type states. Emit
  writes a result's constant extent entries (C239's "the frontend writes
  extents" covers Emit). A tie states what it ties before the call, an
  axis nothing states computed from the index terms the call is given.
- **C263** (2026-10-23; L16dy's and L16eb's evidence, under C217 and
  AGENTS.md's monomorphic rule). A parameter whose type's result is a
  universe (`Type`, `Type -> Type`, any `... -> Type`) is a type parameter,
  keyed at compile time as `Type` is, whatever its quantity: never a
  function choice and never a run-time value, so an interface over a
  higher-kinded parameter Idris binds at ω compiles. A type case on such
  a parameter at ω compiles too: in every instance the type is known, so
  the tree's choice is fixed, and the alternative is selected from the
  type's head as a fixed implementation's is (the matching constructor's,
  else the default, else the missing case's crash). This widens what
  compiles toward the language, where a type at ω was refused as a
  run-time type; it changes no program's meaning.
- **C264** (2026-10-23; L14x's handoff, under D127, D108 and C205).
  Three settlements of the e-graph's computed constants. (a) The bytes
  the strings and bigs it computes may take are the graph's own budget,
  beside its nodes and their operands (`Engine.h`'s arena bound, derived
  from D108's `nodesPerOp`): a constant past it is not kept and its op
  stays applied, so a doubling chain stops; a spent budget leaves the
  function less optimized and refuses nothing, as every budget of an
  optimizing pass. (b) Upstream's float ops whose result IEEE 754 fixes
  (`arith`'s add, sub, mul, div, rem, neg and compare, `math.sqrt`,
  `floor`, `ceil`, and the conversions a range guard admits) are computed
  on the graph's Double values by `APFloat` at round-to-nearest-even,
  the operation each op's upstream fold applies (read there, cited per
  op), so the op's meaning is upstream's documented one and no second
  meaning is written; a NaN result stays applied (Fold.h's refusal), and
  a function IEEE leaves to the library (`exp`, `log`, `pow`, the
  trigonometric ones) stays applied, as the checker folds only what IEEE
  fixes. Which upstream ops the graph computes is a list in the
  specification, beside `NeverFolded`. (c) Whether a computed string or
  big may stand at a counted hold is read before it is decided: how the
  Graded stage strengthens holds, and whether a value's hold may change
  under its users before it, decide whether the graph places the
  constant at a static hold or leaves it (the queue's L14y).
  *Settled* (2026-10-23, L14y's reading): (ii). No pass makes a hold
  static (the Graded strengthening moves counted to scoped and adds
  sharing claims), primitive ops take any hold and constructor fields
  accept static, but calls and returns need equal grades and the graph
  unites only classes of one type. So the graph places a computed string
  or big as static data and re-grades, at write-back, the values within
  the function that flow from it to ops admitting any hold; an argument
  of a call becomes static and idr-optimize's next round keys the callee
  by hold (D89's specialization, already the specializer's); a value the
  function returns at a counted hold stays applied, since its signature
  is the specializer's, not the graph's.
- **C265** (2026-10-23; L18y's handoff, under D129 and D30). A tail
  call's result layouts agree from the Graded stage on, a stage fact of
  the specification's table (`StageTailLayouts = LayoutsPending |
  LayoutsAgree`, pending at Higher and First, agreeing from Graded), and
  L10z's re-pack check holds where they agree. Within First the decider
  still stops at a re-pack (the call is `nontail` there), and idr-optimize's
  specializer redirects it to the copy D129 keys, which makes it a tail;
  a pass after it that loses a tail to a re-pack is caught at Graded's
  first verification, an internal error. Checking from First, where
  defunctionalization decides the facts, refused every program with such
  a tail before the specializer ran.
- **C266** (2026-10-23; L05x's handoff, under D124). A loan's stretch is
  cut at every op no loan region may hold (a call that runs on a frame, a
  tail call, a jump out, the terminator), the reads on each side lent
  under their own view lifetimes, and an alias a read needs past a cut is
  made again on the far side from that side's loan, as frames re-lend
  static data (one helper for both). So no loan changes a count. The two
  residual shares go: an upstream op whose own region holds a call that
  runs on a frame cannot reach lending (idr-structure-loops keeps every
  region that calls as our op, and frames stop at such an op), and an
  alias read across a cut whose op cannot be made again has no frontend
  shape; each is an internal error naming its op, never a count change
  D124 rules out. An op of ours adopts an alias when its flow edges move,
  release or pass it by value, whatever its uses count.
- **C267** (2026-10-23; under D131, D129 and AGENTS.md's acceptance
  rule; for the owner's review). Where a caller compiled at a closed
  layout tail-calls a callee whose result index the language still
  cannot express (`Vect (n * m)`, `Vect (length xs)`), the specializer
  does not make that closed copy: its non-tail callers take the open
  result and convert it after their call, so the program is less
  optimized, never refused, and its tail call is kept. D129's "every
  non-tail call keeps D58's in-place result" holds wherever the closed
  copy can be made. An internal error there would refuse a valid
  program, which acceptance as a property of the program rules out.
  *Sharpened* (2026-10-23, L04x's evidence; under D130): a function
  closed by its own type (declared `Vect 3`), which no copy can decline,
  meets the same tail: its result is marked open (D130), so the tail call
  agrees and its non-tail callers convert after their call, as a declined
  copy's do. One rule for both: where a caller's closed result cannot
  agree with its tail callee's, the caller's result is marked open. It is
  decided once per function, beside the optimizer's schedule of
  per-function facts, not per request.
- **C268** (2026-10-23; L16ef's handoff, under C262 and D30; amends
  C262's second sharpening; for the owner's review). `idr.array.tie_shape`
  names the axes it ties, and its sizes cover those alone: a tie states
  what something states of an array, and an axis nothing states stays
  untied, never read off the array. So nothing but the tie follows a
  call, a tail stays a tail, and Emit reads no size from an array to tie
  it (the reads on values that already exist go too). C262's "an axis
  nothing states computed from the index terms the call is given" is no
  obligation of Emit, which turns no index term into a run-time size: the
  frontend may state more axes before the call (successors, and sums
  under D131), which shrinks what stays untied but never empties it.
  Rejected: no tie on a call's result with an axis unstated, which drops
  the stated axes' facts.
- **C269** (2026-10-23; L07x's handoff, under C87 and AGENTS.md's "a
  linear binder does not imply unique heap ownership"; for the owner's
  review). The uniqueness test's shared region takes its value at `many`
  uses: the runtime shares the cell there, so each field read is of a
  value others reach too and its count rises by `count.dup`, which C87
  admits only of a value used many. The unique region keeps `once`. The
  program's quantity is kept: the test consumes the once owner once, and
  its shared region's argument is a new value whose sharing the test
  established. Declared in the specification (the op's region argument
  and its type compatibility); a cast by `lin.cast`, which declares no
  consumption, is rejected.
- **C270** (2026-10-23; L07y's evidence, under C87 and C88). C87 holds
  for `count.drop` as for `count.dup`: a drop takes only a value used
  many, by its declaration. A once owner is consumed by `count.take`,
  which moves its cell into a token and its fields out, never by field
  reads and a drop; placement takes it where it would have dropped it.
  The ops that end an owner (drop, take, take_into, match_unique,
  unpack) carry one trait in the specification, which linearity reads to
  count such a use as the cell's alone.
- **C271** (2026-10-23; L17bb's stop, under C55 and D12; for the owner's
  review). A `%transform` in a trusted library (prelude and base write 16)
  is elaborated as upstream elaborates it, both sides checked against
  each other, and kept nowhere: its meaning is an equality the optimizer
  may use, which changes no program, and this compiler's optimizer is the
  C++ pipeline over MLIR. So a wrong rule is refused as upstream refuses
  it, and nothing reads a rule: `addTransform`, the `transforms` field, its
  TTC section and `%transform`'s rounds go. A user module's `%transform`
  stays refused as `unsupported` (`tests/pragma-transform`). The rules an
  implementation's methods generate are not pragmas and go with what
  reads them.
- **C272** (2026-10-23; L16ei's F-F2, under AGENTS.md's lossless rule
  and D48). An index the instance key erases is an index parameter of the
  instance, and each call passes its term, so a closure's type keeps the
  index its caller names (`summed = sum . toList` at `Vect n`: `(.)`'s
  instance takes `n` as an index parameter, and the call passes `v0`).
  Rejected: erasing a closure type's indices, which loses what the type
  states, lays closure arguments out as at unknown indices, and needs
  opaque-to-level reindexes inside lambdas the scope rule refuses.
- **C275** (2026-10-23; L12w's stop, under AGENTS.md's "nothing static
  built on a worker's hot path"). Whether a reindex or a field read builds
  a cell is one function, decided from what the types already store and
  their index terms, as the layout classes decide a class, making no type
  or attribute (`families::builds` and `fieldReadBuilds` today build field
  types through `determinedFields` where words differ). The reindex's
  verifier, its flow, the field read's flow and the lowering's repack ask
  it. Rejected: storing the answer on the op (a second copy of a fact the
  types hold) and splitting the reindex by whether it builds (the
  distinction is derived from its types, not chosen).
- **C276** (2026-10-23; L18w's evidence, under D48 and AGENTS.md's
  "acceptance is a property of the program, never of the optimizer"; for
  the owner's review). A cast from an opaque index is admitted to any
  term, as it is to a level: the operand's index is one Idris proved and
  the language cannot write (`Vect (length xs)` returned where `Vect n` is
  owed), and the scope rule takes the program's word for it whatever the
  target. So substitution never changes whether a function verifies: a
  copy that closes `v0` to 3 turns `#Vect[_]` to `#Vect[v0]` into
  `#Vect[_]` to `#Vect[3]`, admitted as the generic cast was. Today a
  level target admits an opaque operand (a level pattern matches anything)
  and a closed one refuses it, so a class copy of a valid function failed
  verification. A cast between two terms the language writes is checked
  against the refinements as before. Rejected: opening every binder such
  a cast targets, with conversions before calls, which keeps the
  inconsistency and pays at every call.
- **C277** (2026-10-23; L18v's open items, under C267 and the grade's
  rule that a claim is an optimization; for the owner's review). Holds
  only go down, by one order. A copy keyed to a weaker parameter hold
  whose parameter its result gives back (the gives-back facts the
  analyses already keep, read, not recomputed) has its result keyed to
  that hold too, so its callers read the key's results as the copy will
  give them. A lowered operand at a call of a member of the caller's own
  component lowers the member's parameter hold by the same rule as a
  result, rather than keying a copy inside a component the redirect has
  not finished; the order is finite, so it ends.
- **C278** (2026-10-23; L18t's open items, under C277). A copy's result
  is keyed by what may give a lowered parameter back, not only what gives
  it back on every path: where the parameter reaches the result on some
  path (a reverse accumulator), the result takes the weaker hold, a sound
  bound, read from the same analysis's may facts beside its must facts.
  A copy inside its caller's component lowers its parameter by C277's
  member rule, as a member does, its key's signature then restated. The
  re-inference of results after a grade changes is one function
  (`families::takenTypes`), which `Ownership/Exclusive.cpp` and
  `InPlace/UniqueResults.cpp` ask too.
- **C279** (2026-10-23; L19w's and L19n's stops, under AGENTS.md's one
  place the target is decided and "a test that names a pass"). Every
  module is given the build's target where it enters the pipeline,
  by `idr-target`'s one rule: a module that names no target takes the
  build's, one that names another is refused `OtherTarget`. Every slice
  `buildPipeline` makes runs `idr-target` first, whatever stage it starts
  at, so `--idr-pipeline` and its slices are what the driver runs, and
  the driver's own `addPass` goes. The driver runs the same rule on a
  lowered module, so `moduleKindOf`'s second target check (a lowered
  module naming none refused) goes: a module the pipeline lowered always
  names its target, and a hand-written one is the build's, as a handoff
  module is. No test names `--idr-target` or writes a target into its
  module, and no option prints the whole target.
- **C280** (2026-10-23; L12v's stop, under the resource tree of
  2026-10-21 and AGENTS.md's "nothing else names a resource"; for the
  owner's review). The heap's contents gain one child, `Filling`: a
  cell's fields while it is filled, between its allocation or reuse and
  its first use as a value, which `cell.init` writes. Every ordering the
  tree gives stays (an effect on the contents still conflicts with its
  child). An update's region may not read or write the contents or a
  state above them, the rule read off the tree through the one effect
  query, so counting's own work in the region (a drop or a token freed
  on the heap, a cell filled) passes and no op is listed. Narrowing by
  the type of the value an effect names is unsound there: a call writing
  through a cell that holds the array reaches the emptied place.
- **C281** (2026-10-23; L16em's stop, under AGENTS.md's "one thing, one
  representation ... generate the second copy from the first" and D112;
  amends C257's threading; for the owner's review). The growth model's
  walk decides every request once and records it in the tree it grows:
  at each place, the request the translation will make there (its
  callee, its keyed arguments computed from the site's term as C257
  says, its `DrawnFrom` and `HeldAs`), so the tree is the program's
  terms annotated with their decided requests. The translation folds
  that tree: it reads each request at its node and computes none, so no
  request can miss its site, which no walk beside the term could prove
  in `Front` (two effectful walks admit no quantity-0 proof that they
  agree, and a miss could only be an internal error, a fallback or an
  asserted trust, each refused). Every request the translation makes is
  such a node: a member's body translated at a use is walked by the
  model at that use; a dispatch's arms are nodes under its site; a
  capped position carries its cap as its evidence in place of a
  `DrawnFrom`; a data family's registration is a `Builds` node. With the
  lemma's induction over the model's walk alone, this deletes
  `Finite.unsound`, `heightWithin`, `sizedWithin`, `Types.boundsHold` and
  the translation's own request computation.
- **C282** (2026-10-23; L16en's finding, under C277: a weaker claim is
  always sound). A value built of fields takes from a field the claim
  that field's value holds only where that value is used once, its
  reference moving into the new value; a field whose value is used many
  times gives no claim (`None`), since its cell is reached by its other
  uses as well (`(xs, xs)` claimed `unique deep` over a list both fields
  reach). The rule is the specification's `freshClaim`, its proof reading
  the field at its uses, which the frontend and the dialect's builder
  both ask; a claim lost here is raised later only where exclusivity
  proves it (`idr-unique-results`).
- **C251** (2026-10-22; the §6 check). §6's "grep finds no remaining
  reference" counts code, tests' expected behaviour, generated files and
  current documentation. It does not count history kept on purpose:
  AGENTS.md's "Never:" lines, which name what the tree once did; dated
  records under `bench/records/`; a test's planted witness, an input
  holding the forbidden form so the check that refuses it is seen to
  refuse it; and a document's account of a deletion as done. A stale
  sentence that describes a deleted thing as present is a remaining
  reference and goes.
- **C252** (2026-10-22; L13's handoff on INT-10). A constant closure,
  `#idr.closure<@callee, [captures]>` (C++ `ClosureAttr`), is declared in
  `Spec/Closures/Declarations.idr` beside the closure type, which no
  specification declared after the TableGen cutover though four readers
  name it. It holds the callee and its captures and no index terms: a
  closure at terms stays `idr.fn.closure`, as its fold already says, so
  a constant's check asks that the callee binds no index variables and
  reads no terms.
- **C232** (2026-10-22; *withdrawn* by D116 the same day: the language is
  never widened to compile the fork; 0014's features stay parked). (2026-10-22;
  under D113, extends C230). What the frontend
  gains so the fork's code compiles in upstream's form (L17r, L17s). Each
  is a construct whose runtime choices the whole program fixes, so it
  compiles by specialization or as a closed sum, and only the unbounded
  case is refused, naming its site:
  - a `Type` passed or held at run time (a record's field list
    `{fs : _}`, `KeyVal.type`, `TokenKind`'s `TokType`): specialized at
    each site where it is static, and a closed sum of the types the
    program uses where it is chosen at run time;
  - a type computed from such a value (`LabelledValue.value : kv.type`,
    `tokValue`'s result, `ActType argdescs`): computed per
    specialization or per alternative of that sum;
  - a constructor field whose type the constructor hides (`Compose`,
    `SeqEat`): C230;
  - dictionaries held in an `All` over such a list, and mutually
    recursive instances: dictionaries of the closed sum C174 makes;
  - a match on an erased proof whose constructor a runtime index fixes
    (0014's first feature, the forced index): the index's runtime value
    selects the alternative;
  - a polymorphic function in a recursive group used at types the program
    fixes: the growth graph's bound (D68).
  0014's features 1, 3, 4 and 5 come into the cutover with these.
- **C1** (2026-10-21; DP-13's other parts: count-Q2, own-Q1, rc-Q1)
  (names per D90). Counting's order and borrows follow from D26 and D24.
  - *Drops first, then reuse guided by them*: the reverse walk places
    drops at last use; a forward walk per function, with a map from
    layout to the tokens available, intersected at rejoins, turns a drop
    whose cell a later construction on the path fits into
    `cell.recycle`, the token passed on as a join argument across a
    rejoin (D19). The in-place promise (D24) is read before placement
    and makes its rebuild an obligation of this walk. A token of a
    dynamically sized cell is used before the next allocation or freed
    (D26).
  - *Borrows inferred over the closed program, within D26*: a parameter
    is borrowed only when at every call the caller uses the argument
    afterwards or its type bounds everything it reaches, and the callee
    neither consumes nor stores it; a parameter D24 rebuilds is owned. A
    runtime function's conventions come from the Idris specification.
    Users declare nothing: Idris has no borrow annotation.
  - *Reason*: D26 states the bounds; Lorenzen and Leijen prove this
    order frame-limited (ICFP 2022 §5.4) and Lean's order not (§3.1,
    example B); ours is Lean's, with reuse sites predicted before
    placement by guessing that any call takes its arguments over
    (`Reuses.cpp:193-195`) and simulated, the simulation 9db9813d's 1088
    verifier errors came from (21 §6.1).
  - *Deleted*: the predicted death points, the guess, the simulation,
    Borrows' forced-owned reason taken from reuse sites
    (`Borrows.cpp:179-181`).
  - *Amended* (2026-10-21, the verification swarm: L05 §1, L07 §1.2 and
    I1, I2, L08 §1.2 and I-2, L09 §2.10, L10 I-3, L14 §3, review §4.1).
    The borrow rule as first written would own `length`'s list (`length
    (_ :: t) = 1 + length t` passes a field of a borrowed list at its
    last use) and borrow at a tail call that a drop then follows; and the
    walk cannot honour a rebuild it does not see. Corrected:
    - *Borrows*: a parameter, or a join parameter, is borrowed only when
      the callee neither consumes nor stores it nor takes it apart into a
      rebuild site, and at every call or jump the argument is used after
      it, or is static, or is a view at a lifetime that outlives the call
      (a view of the caller's borrowed parameter or a part read from
      one; this clause rests on D26's never-line read as "no active call
      needs it after the call", §4's queue), or is dead after it with a
      type that bounds everything it reaches, where that call is neither
      in tail position (D30) nor a D34 site. "Bounds everything it
      reaches" is a layout fact computed once when the type is made (no
      cycle of containment, no dynamically sized cell). One backward
      two-point marking writes the answer into the signature, `counted`
      or a `scoped` view tied to a lifetime the caller passes as a value
      (D39, D63). An argument whose binder in the caller has quantity 1
      makes the parameter `counted` with no query
      (D26); the callee's own quantity 1, or returning the parameter, no
      longer does.
    - *Rejoins and jumps*: a token reaches the code after a match only as
      a match result, the least count per layout over the regions that
      yield (one that ends the process or jumps takes no part), and a
      join region only as a jump argument, a quantity-1 argument being a
      move. Tokens of one layout are taken in a total order: the one a D24
      obligation names, then `counted unique deep` before `counted`,
      then the sink's own source, then the earlier source.
    - *Order*: placement, exclusivity, reuse, the take's expansion; the
      walk reads `unique deep` off the token's type.
    - *The promise's pairing is data before the walk* (C90): a rebuild is
      a linear token consumed by `idr.rebuild`, so the walk never pairs a
      promised cell; "an obligation of this walk" is withdrawn.
    - *No token of a dynamically sized cell exists* (D48 makes every
      token's layout static): that clause is withdrawn; such a cell is
      reused only as the destination of the op that consumes it.
    - *Deleted besides*: `Uses.cpp` whole; the cycle restriction at
      `Borrows.cpp:236-237`; the quantity-1 and returned rules
      (`Borrows.cpp:83-84, 215-217`); Borrows on the dataflow framework,
      its prediction of idr-trmc and its two never-patterns
      (`Borrows.cpp:272-288, 303-304`). The forced-owned reason becomes a
      fact of the program: a parameter the callee takes apart into a
      rebuild site is `counted`.

- **C2** (2026-10-21; the stress test of D27's tree,
  `design/effect-vocabulary.md` §8.3: a sharded io_uring server, async
  Rust, proposals 0007 and 0020) (names per D90) (amended by D92: R5's
  open point, when a Rust destructor runs relative to output, waits for
  0020, not for §4). The tree holds per
  shard, unchanged; five rules follow.
  - *R1*: memory the kernel touches is held by ownership: a completion
    read consumes an exclusive buffer into the operation in flight and
    its completion returns it; a zero-copy send holds a `counted`
    reference to immutable bytes; a cancelled task's in-flight buffer is dropped by
    the reactor at the completion.
  - *R2*: `heap` is the memory any cell lives in (snmalloc's arena, a
    kernel buffer ring, a foreign allocation); giving a buffer back to
    the kernel is a `Free`.
  - *R3*: an effect that changes a calling convention lives in the
    function's type; 0007's `wait` is the first, and its ordering is
    `RunsUnknown`, as `apply`'s.
  - *R4*: a foreign call's effects come from its operands' types and
    grades (`IO`; contents read through `&`, written through `&mut`;
    consumption; acquisition; no callbacks, D92), since after D20 and
    D21 IO orders no heap memory.
  - *R5*: a drop of a value whose type may reach a foreign cell writes
    `IO`, since a destructor may flush or close.
  - *Stale, for when 0007 and 0020 are taken*: the world in 0007 (D1,
    `Here`, task frames) and in 0020 §9, §11.2; 0007's `idr.wait` as a
    two-successor terminator (a region op under D19).
  - *Amended* (2026-10-21; L01 §1.7, L02 §1.1, F13, F14, L11 §1, L20
    §1.7 to §1.9):
    - *R1*: a buffer the kernel writes is `!idr.graded<once, counted
      unique deep, …>`, never `scoped`, neither to this call's lifetime
      (`idr.activation`) nor to any other (D63), so neither the stack
      inference nor allocation into a lifetime can take it and a cancel
      cannot free it under the kernel; the completion's result is the
      consumed buffer, exclusive, in the op's signature; a zero-copy send
      takes a `counted` reference or a `static` view; a registered buffer
      slot is a linear token of the ring's lifetime.
    - *R2*: a ring buffer's cell needs its own header kind, since the
      type-blind free dispatches on the header (`Rc/Freeing.cpp:98,
      127-135`).
    - *R3*: inside P0 the first convention-changing fact is allocation
      into a caller's lifetime (D39), which D63 makes an operand, the
      lifetime's token, rather than an effect; nothing is handed to Rust
      to call back, since Rust never calls Idris (D92).
    - *R4*: a foreign call also writes `exit`, `crash` and `divergence`
      and may `free`, and is never `nosync`, `willreturn` or
      `mustprogress`; it takes no callback operand (D92).
    - *R5*: "may reach a foreign cell" is a fact of the type, computed
      when it is made (D48) and read by the typed rule `ReleasesForeign`,
      never found by a walk at the drop; where the drop lands relative to
      output is §4's queue (Rust's destructor timing).
    - *Stale besides*: 0007's "every fork is joined" and "lending cannot
      dangle" (a monadic result is unrestricted, so a dropped join is a
      use after free), its `lent` permission (an `idr.lend` region under
      D63, D90),
      its task frame "linear because it holds the world"; 0020's run-time
      borrow state for constants and statics, and "every call takes and
      gives the world" (D20).

- **C3** (2026-10-21; DP-31, eff-Q3; revised the same day under the
  owner's word: "my human word always takes precedence over automated
  decisions ... if the vibe says i would have overruled them, trust the
  instinct"). Building a value acquires nothing before counting: `con`,
  `closure`, `suspend` and `delay` of an unrestricted value are pure (two
  equal ones merge, an unused one goes, one may be hoisted: compile-time
  hash-consing of immutable values), a linear or owned result takes a
  fresh identity (`Allocate` on `identity`, never merged), and memory is
  acquired where counting materializes a cell (`cell.new`, `Allocate` on
  `heap`), which is where the `alloc` atom comes from. The first version
  (every constructor acquires, so CSE merges none) traded an
  optimization for an exact count before counting, where no reader needs
  one. Deletes the hand list in `Expect/Allocation.cpp:28-33` and fixes
  the allocation test missing `delay` (02 B5).
  *Amended* (2026-10-21; L01 §1.8, I1, I2, I6; L08 §1.9; L13 I4; L18
  §1.1, I2; review §7). Construction is pure only where nothing reads
  identity. An unforced memo cell, the one cell that changes while
  references to it live, keeps its construction op after
  defunctionalization, `Allocate` on `identity`, never merged, hoisted
  or folded (deletable when unused): today `SuspendOp::fold` and the
  memo case of `ConOp::fold` make every capture-free suspension one
  static cell whose forced value lives until exit. A value of an
  `in_place` family takes a fresh identity where it is produced, as a
  linear result does: two equal `LCons 1 LNil` merged by CSE turn two
  exclusive arguments into one shared one, so D24 would refuse after an
  optimization; its `#idr.con` cannot be written and record eta does not
  replace it. The same rule covers runtime builders of immutable values
  (`big.*`, `str.*`): they acquire `heap` only once counting makes the
  result owned, so `(x + y) * (x + y)` builds one `big.add`; the `alloc`
  atom also comes from every runtime function that builds an owned
  result. idr-expect's `no-heap-allocation` and `builds` read the counted
  program (they break before counting today, 15 fixtures). Deletes besides
  `SuspendOp::fold`, the memo case of `ConOp::fold`, the statics walk
  (`Defunctionalize/Pass.cpp:116-127`), the static `MemAlloc` on 33
  builders and `Idr_BuildsValue`; the hand list is at
  `Expect/Allocation.cpp:24-30`. D27's gloss of `identity` ("a fresh
  linear or owned value") is read to include these.

- **C4** (2026-10-21; with D34) (amended by D102: where an operand or
  `f` must be `total` for a call to be skipped or moved, read a row
  carrying neither `crash` nor `divergence`, since totality removes
  divergence only). Accumulators are an optimization,
  widened: `idr-accumulate` makes an accumulating loop of a self call
  combined in a tail by any operation the runtime defines as exactly
  associative, with its identity (`Integer` and `Int` `+` and `*`, the
  bitwise and, or and xor, `&&` and `||` with their short circuit kept),
  only where eager evaluation's order of effects, crashes and divergence
  is unchanged. Never a floating-point operation, never a user's
  `Semigroup` or `Monoid` (Idris proves no law). Today only `idr.big.add`.
  *Amended* (2026-10-21; L10 §1 C4, §2.6, I-13). Exact associativity and
  an identity suffice, no commutativity: the clone combines on the side
  the call was on (`acc ⊕ g` for `g ⊕ f(…)`), so string concatenation
  qualifies, and `Int` and fixed-width `+` and `*` qualify because they
  wrap. `&&` and `||` need nothing with the call on the right; on the
  left the other operand must be pure and total, and the loop runs to the
  base case unless `f` is `total`. The other operand is computed before
  the call, or is pure, total and speculatable, so a crash's site (D38)
  is unchanged; every self call of `f` is such a site or a tail call. The
  countdown recognizer (`AccumulatorPlan.cpp:165-210`) goes: it is the
  closed form of an accumulated loop.

- **C5** (2026-10-21; the values D35 asked for). Every size is the
  program's or the host's, never a round constant, and nothing is
  committed before it is used (lane 18 T-AL3: reserved `PROT_NONE`,
  made writable as used, address space and commitment two states):
  - *The stack*: D32's computed bound and a margin for the runtime's and
    the C library's frames, rounded to pages; tens to hundreds of KiB
    expected, the musl camp. The runtime's own units take
    `-fstack-clash-protection`, since GMP's temporaries use `alloca`.
  - *The guard*: one page, or the largest frame rounded up if larger,
    checked when the program is built (D32).
  - *The signal stack*: the target's `SIGSTKSZ` for programs (today 1
    MiB); the tools' measured with LLVM's crash report on it.
  - *The heap*: a window aligned to 4 GiB, which is what Apple's
    prefetcher reads (bits 32 to 55 of a word equal to its address's,
    0017 §1); reserved as address space only, nothing committed at
    start, snmalloc committing chunk by chunk as it uses them; under a
    `ulimit -v` the window shrinks to what the limit leaves. Only the
    alignment matters to the prefetcher, never the size.
  - *snmalloc's page map*: its flat map reserves on the order of 256 GiB
    of address space (2^34 entries of 16 bytes over 48 bits, *conjecture*
    from `ds/pagemap.h:102-108`); harmless under strict overcommit once
    `PROT_NONE`, fatal under `ulimit -v`. Its replacement (a map bounded
    by the heap's window, or grown with it) is designed from snmalloc's
    source and measured.
  - *Amended* (2026-10-21; L10 §1 C5, I-10; L11 §1 C5, I1, I7, I8; L19
    §1.9; review §4.3):
    - *The stack*: the runtime's frames are computed (its bitcode is in
      the module); the margin covers outside code (the C library, GMP,
      compiler-rt) and the host's thread overhead read at start, measured
      per target and checked when built; the whole is committed when its
      thread starts (D66). "Tens to hundreds of KiB" is *conjecture* (the
      arm64 glibc floor is 128 KiB, *recalled*).
    - *GMP*: the bootstrap's separate library, which the runtime's flags
      never reach (`tools/bootstrap.sh:1060-1066`); it is configured
      `--enable-alloca=malloc-reentrant`, so its temporaries come from
      the allocator, and built with `-fstack-clash-protection`, as are
      the runtime and the tools.
    - *The signal stack*: the host's minimum (`sysconf(_SC_SIGSTKSZ)` or
      `AT_MINSIGSTKSZ` on Linux, the constant on macOS) plus the handler
      path's frames, rounded to pages, with its own guard: the layout is
      `[guard | stack | guard | signal stack]`.
    - *The heap*: no window is reserved; every chunk is reserved at a
      fixed address from a span whose start is aligned to 4 GiB, so a
      `ulimit -v` (Linux only: macOS refuses one) needs no shrinking rule
      (C100).
    - *The page map*: now *read*, 2^34 entries of 16 bytes, 256 GiB on
      all four targets (`ds/pagemap.h:101-109`, `aal/aal.h:122-125`),
      half the user space of arm64 Linux with 4 KiB pages. Its
      replacement is snmalloc's bounded flat map over the span, committed
      per page, with one carried patch (C100); a grown two-level map is
      rejected, as it adds a dependent load to every free.

- **C6** (2026-10-21; one-source §9, NQ-14-5 reopened). An op's
  specification names the base primitive it implements, and the
  registry's rows for those primitives are generated from it: both are
  Idris now, so the old objection (coupling ODS to base's spelling, 14
  TD10) no longer holds, and the mapping is held once.
  *Withdrawn and replaced* (2026-10-21; L03 §1.9, Q1 option B; L12
  I12). The objection was never the language but the coupling: a
  specification that spells base's names couples the dialect to base's
  spelling (14 TD10), and that stands. A primitive op has no attributes,
  so one generic builder over the specification's op value is inside the
  subset, D50's own reason for printing builders not reaching it
  (`pureOp` already is one, `compiler/src/IdrisMLIR/Dialect/Idr.idr:1355`).
  So the registry's rows, the array externs' among them, name the
  specification's op they mean, and base's names stay in the registry;
  the specification carries no Idris spelling; adding a primitive is two
  edits, its op and its row; no primitive sums are printed. Deletes the
  per-primitive printed builders and the `Primitive` trait no C++ reads
  (`IR/Traits.h:72-79`).
- **C7** (2026-10-21; one-source §4.1). The specification lives in
  `compiler/spec/`, package `idris-mlir-spec`, modules `IdrisMLIR.Spec.*`,
  depending on `base` alone; the generator in `compiler/specgen/`.
  *Corrected* (recheck 3): the generator is the package's own
  executable, `specgen`, its modules `IdrisMLIR.Spec.Generator.*`
  beside the specification's, as the tree builds it and `ownership.json`
  gives L03; no `compiler/specgen/` exists.
  *Amended* (2026-10-21; L03 §1.10, §2.2). Base suffices (`Vect`,
  `Fin`, `So`, `Elem`, `List1`, `Decidable.Equality`). The pinned Idris
  builds it into `HOST_PREFIX` for the frontend, the runner, specgen and
  the syntax samples, and the frontend builds it into `CHECKOUT_PREFIX`
  for `make self` and D52, as the fork is; the harness and
  `syntax-samples.ipkg` depend on it. Its modules add `Format`,
  `Admitted`, `Families`, `Bytecode`, `Constraints`, `Interfaces` and
  `Traits`; `tests/registry-only` gains `compiler/spec/` as a second home.
- **C8** (2026-10-21; §8's suspected bugs; revised under the owner's
  word and their standing "fix bugs aggressively") (amended by D98,
  D100: the canonicalize passes `maxNumRewrites` configures go, so C48's
  per-op patch is never built). A suspected bug
  inside what P0 replaces is deleted with its cause, under the ruling or
  stage that replaces it (D22 and C3 the effects rows, D24 the in-place
  promise, D32 and C5 the stack, D41 the primitives, D44 the Idris
  side's, D16 the pipeline held twice). One outside it (`maxNumRewrites`
  unset, 04 C60; `OsOp::fold` and the build machine's triple, 03 O-81;
  the fork's Windows branches, 17 FB-48; snmalloc's errors without the
  flush, 18 R-AL-3; the optimizer's nondeterminism, 09 OPT-48, OPT-14) is
  fixed inside the cutover too, since nothing is built before it is whole
  (D56), and reproduced in its qualification, recorded in
  `audits/bugs.md` once reproduced. L06 finds four of these five inside
  code P0 replaces anyway.
  *Amended* (2026-10-21; L06 §1.1, L11 §1 D23, L13 §1.2, L17 §1.4, L18
  §1.2). Four of the five are inside P0's rewrite, not outside:
  `maxNumRewrites` in the pipeline specgen prints, `OsOp::fold` in the
  dialect redesigned whole, snmalloc's failure path in the runtime's,
  the optimizer's in C45 and C46; only the fork's path module is
  outside, and under D56 it is fixed inside the cutover too, not on main
  first. Corrected items: `maxNumRewrites` counts rewrites per run
  (`GreedyPatternRewriteDriver.h:84-90`), so a per-op bound is a carried
  upstream patch (C48); snmalloc's `PAL::error` aborts unflushed in
  another format at the first allocation on exactly D35's strict hosts
  (the 256 GiB page map's reservation fails, `pagemap.h:213, 221-224`),
  and our PAL's `error` ends as the runtime's internal error; the fork's
  path module reads every path with Windows's grammar on every target
  (`"/tmp/a:b" </> "Main.idr"` is `/tmp/a/Main.idr`,
  `Libraries/Utils/Path.idr:150-194`) and tests the host's `os` at run
  time (C125); OPT-14's stale dominance is refuted, since the pass
  manager clears nested analyses after every run (`Pass.cpp:673-679`),
  while OPT-48 holds.

C9 to C63 are synthesis G's drafts as L06 dispositioned them against the
rulings (`audits/p0/verify/L06-dispositions.md` §1.4, its appendix),
each corrected where a lane's evidence bears on it; the six that
conflicted with a ruling (DP-27, 28, 40, 52, 74, 80) are rewritten to it
and say so, and DP-68 is withdrawn. C64 on are the verification swarm's
improvements (`audits/p0/verify/`), each citing its lane and section.

*Process and scope*
- **C9** (DP-25: QL5, cxx-Q5; corrected, L15 §2.11; its first half
  superseded by D57) (amended by D106, D107, D109: the form is narrow,
  built from MLIR's mechanisms in C++, its rules data of the
  specification never run in Idris; its exact MLIR form is §4's, not
  `egraph.md`'s). Equality saturation is D57's, its form and place
  `design/egraph.md`'s. A C++ feature joins the design only when both the
  pinned clang and the host compiler `make typecheck` uses have it
  (`tools/bootstrap.sh:117, 1126-1160`); static reflection and expansion
  statements are in neither today, so P0 waits for neither and takes
  them when a weekly fast-forward (D25) brings them to both. The
  specification is our reflection.
- **C10** (DP-26: Q-M4, Q-E4, defunc-Q1; corrected, L18 §1.1, I1). No
  more ports: fresh code from Modular's, CIRCT's and IREE's shapes, to
  D7's line. The deduplicator port is retired by partition refinement
  over upstream's `OperationEquivalence`, its symbol hook a carried patch
  (D25), merging duplicates inside call-graph cycles, each class keeping
  its first in symbol order; it runs once, after idr-knots, on the
  first-order program, labels compared as class slots (C68). Deletes
  heights, waves, the cycle exclusion, `Reading`, `BodyHash`,
  `BodyEqual`, per-op dictionaries, deduplication's first slot
  (`Pipeline.cpp:62-71`), the port's PINS.md entry.
- **C11** (DP-27: DD-Q8, T-Q3; rewritten under D28, L06 I5; L13 §6).
  Every name is open (D28, D29, D40): mnemonics, `con`, `dup`, `drop`, the
  namespace, pass names, idr-expect's property names. Every mnemonic
  takes its family prefix: 46 of today's 189 have none (`con`, `field`,
  `match`, `divs`, `take`, `dup`, ...; 9,647 uses in 334 fixtures). A name
  lands in the change that makes or remakes its concept, never in a later
  rename step (G's "renames land last" would print old names inside the
  new design, against D28); a rule's phrase changes in the step that
  changes the rule.
- **C12** (DP-28: T-Q2; rewritten under the owner's test rule, L06 I6;
  L19 §2.1, §2.9). A fixture stating behaviour becomes a program test;
  one stating a pass's guarantee, an idr-expect property over a program
  test; one whose subject is a shape a pass must handle that no program
  test reaches, a stage slice (`--idr-pipeline=from:<stage>,to:<stage>`)
  in the new dialect with a property or `%differential`. Every other
  fixture is deleted, none renamed by script: op sequences, SSA names (53
  lines), op names (13), orders, the 260 prose `expected-error`s, 84
  `facts:` remarks, reference IR copied from output, fixtures of states
  the specification cannot construct; the 104 files naming `!idr.box<` and
  the 332 naming `#idr.types<` are restated by behaviour or deleted.
- **C13** (DP-29: QL6; corrected by D57). 5.7's items 1 to 17 are
  fetched, verified and recorded with licences in `sources/INDEX.md`;
  item 16, dropped with equality saturation, returns with D57.

*Effects, quantities and budgets*
- **C14** (DP-32: DD-Q1, Q-FB2; corrected, L16 I4, L20 I1) (names per
  D90). `!idr.graded<once, i64>` stays a type on words. The translation's substitution respects
  quantities: a quantity-1 variable substituted for a binder of quantity
  many, or aliased, is let-bound once through `lin.use`, so no binder of
  quantity 1 is used twice; a parameter keeps its Pi binder's quantity,
  and a binder the translation makes takes its quantity where it is made.
  Emit reads quantities and never counts uses; a quantity-1 binder used
  twice reaching Emit is an internal error, now unreachable. D24's subject
  is the match on the linear parameter itself. Deletes `mostUses`,
  `heldAs`, `holdFor` and Emit's `Lazy Nat` counts
  (`Emit/Bodies.idr:48-146`), the demotion at `Emit/Declarations.idr:45`,
  `madeAt`'s two `Bool`s (`Emit/Monad.idr:134-136`); `coerce`'s pair of
  `Bool`s becomes a `Held` sum.
- **C15** (DP-33: Q-llvm-2, Q-E3, oom-2, canon-Q2; corrected, L08 §2.1,
  L13 §2.4, L14 §1.3, L15 I-8, L17 §2.1, L18 §1.1) (amended by D98,
  D108: no canonicalization runs where our ops are, so its per-op bound
  and C48's patch go; the e-graph's budget is B nodes per op, from the
  program alone). No budget in an
  analysis a refusal rests on, nor in what it reads: the frontend's
  profile, growth check and reachability walk (its derivation built at
  quantity 0, D46); the label solve on the program as written and
  defunctionalization (C68); idr-knots; idr-in-place, which decides D24's
  rule (C90); the effect rows. A refusal analysis's units are never
  skippable (C115). The fork's searches end by construction (D45, D53 to
  D55); its counts that change only a stored term's form stay, named
  (C128). Every other analysis may stop at a budget in program units: a
  budgeted solve is its own type and writes top for every unfinished
  function, never an error. Canonicalization is bounded per op by a
  carried upstream patch (C48), k a constant of the specification
  measured on the stage-1 module, the tests keeping
  `test-convergence=true`. The compiler running out of memory ends through
  one handler with a named line, never a refusal. Deletes `kNoLimit`
  (`Pipeline.cpp:28-32`, `Optimize.cpp:64-66`) and LLVM's default abort.
- **C16** (DP-34: QL4, Q-llvm-6; L14 §2.5, L19 §2.5). Output is
  byte-identical at any thread count, tested whole (a `threads` scale
  fixture at one thread and on the pool) and per solver (frozen answers
  at one thread and many). Deletes OPT-48's lock-ordered request chain
  (C46).
- **C17** (DP-35: ids-Q6). Each program is compiled by the shipped
  frontend and by a test-only build whose registry omits the `Faster`
  rows (each naming its specification op, C6); exit, output and refusals
  are compared. Hooks are indexed by kind (`Contract | Faster |
  Stricter`), so a `Faster` hook on a bodiless definition cannot be
  written. Deletes `Faster` on bodiless primitives.

*The dialect's representation*
- **C18** (DP-36: Q-O3, Q-E2; corrected, L14 §1.3, I12, I13, L18 §1.1,
  I8, L20 I3). Every fact a later pass reads is written by the pass that
  proves it into a type or a verified property; no side table crosses
  passes (forced besides: the pass manager clears per-function analyses
  after each nested run, `Pass.cpp:673-678`). Rows live on `idr.func` and
  `idr.call` (D20, D22); grades and families in types (D40, D48), a
  lexical lifetime an SSA token (D63). "Gives back argument i" is held once, on `idr.func`, per
  result field path (a result and a field path of an inline value to an
  argument and a field path), never copied to the call: a parallel reader
  reads it from its decide step, and idr-identity's rewrite is done where
  it is decided. A result's exclusivity is a fact of the function type
  (C92). Binding times and inline verdicts are the optimizer's alone and
  die with its run. Deletes the facts that cross passes outside the IR,
  the call copy of "gives back" and its verifier arm,
  `Transforms/Identity/` whole, the residue solve on lowered code.
- **C19** (DP-37: QL2, ops-Q1; corrected, L04 §2.5, L09 §2.4, I6). Each
  case region binds its scrutinee refined to a constructor set, a case
  the singleton and the default the complement (none when it is empty).
  The refined type names the family application and the constructor by
  its position (its label printed, never looked up, D48); it binds the
  constructor's index variables as levels of the scope's telescope (C79)
  under its equation, the refinement found by one first-order unifier
  that restates Idris's `conflict` (`Core/Coverage.idr:22-135`), and its
  fields at the scrutinee's quantity times the field's; a case whose
  refinement clashes does not exist. Values whose types mention the
  refined index are forwarded into the case at the refined type;
  `idr.match_lit` replaces its scrutinee by the constant in each case.
  `field`, `take` and `unpack` take an operand refined to one
  constructor, so a read of the wrong one cannot be written. Deletes the
  `tag` attributes and their printers, the three enclosing-match walks
  with their three identity rules (`OpsMatch.cpp:78-94`,
  `OpsConReads.cpp:123-138`, `Eta.cpp:39-47`), `readField`'s scan,
  counting's undo of the default's rebinding.
- **C20** (DP-38: DD-Q7, tail-Q1, count-Q4, Q-AN1; corrected, L02 §2.3,
  L09 §1.4, L10 §2.1, I-1, I-2, L13 §2.1, L14 I12). `idr.func` and
  `idr.call` stay, and `idr.call` reaches the LLVM conversion as itself,
  never as `func.call`, which cannot carry the tail fact. A function
  carries its row (an inherent property; a clone copies its source's),
  its signature (grades, index parameters, lifetime tokens as arguments,
  D63) and "gives back" (C18); it loses `no_inline`. A call carries its
  callee's row, its quantity-0 index arguments (D48), its lifetime
  tokens as operands (D63) and its `TailKind`
  (`nontail | tail | modulo_context`), with no builder default: written
  by the frontend and by each pass that makes a call, checked by the
  function's region verifier in one walk, lowered as `musttail` under
  `tailcc` on every internal function. Contification alone rewrites it,
  when it places a function at a non-tail continuation; a jump carries
  none, tail position being a precondition for forming one. Its types are
  its callee's conventions after substitution, so no convention attribute
  exists. A result is given back in every function joined by tail calls
  or in none (§8's bug in idr-returned-arguments). Deletes `IR/Tail.cpp`'s
  climb, `TailPosition.{cpp,h}`, `TailCallPlan.{cpp,h}`, `forTails`,
  `reachesTailCall`, the four cycle deciders, `Recursion.cpp`, the
  whole-module Returned solve.
- **C21** (DP-39: types-Q4, types-Q3; corrected, L04 F2, F5, L05 §1 D40,
  §2.2, L20 §2.1; rewritten under D62, D63) (names per D90) (amended by
  D93: a lifetime's type carries its kind, `!idr.lifetime<view | room |
  cursor | home k>`, and one opener per source of its memory binds it).
  One closed
  `#idr.grade` attribute with constexpr methods and no interface, one
  algebra with its laws proven in the specification (D62): uses (`once`,
  `many`) on every type, and on a type that holds references a hold,
  `static`, or `counted` or `scoped` with what is known of its sharing
  (nothing printed, `unique self`, `unique deep`). The hold is settled by
  D88 and D90: who frees a value and what is known of its sharing are
  its two axes, and a lifetime is not part of the grade. A lifetime is a
  value of type `!idr.lifetime`, opened by `idr.lifetime`, this call's
  own `idr.activation`, passed as an operand (D63); how a value's
  lifetime is known and how a signature relates a result to an
  argument's lifetime are `design/lifetimes/`'s, under D63. No hold
  is ever undecided (C144); a value of a type that holds no reference
  carries no hold (D88, C143).
  `!idr.graded<once, counted unique self, T>` is legal: D24's
  obligation, as D70 amends it, writes it. A lifetime is never an index
  of a data type, and a declaration's field grade carries uses alone,
  no hold. The frontend imports the grade's parts (D50). L05's partial
  outlives order over type-level lifetime variables and D40's printing
  of a lifetime as the grade's fourth parameter are deleted by D63.
  Deletes the grade's free functions,
  the stage reads (`Grades.cpp:80-91`, `Program.cpp:222-228`),
  `holdsOwn`, `QType::verify`'s frame rules, the hand enum
  `IdrBase.td:96-108`, and on the Idris side `data Lifetime = Heap |
  Frame` and the `Maybe Lifetime` whose `Nothing` is the heap.
- **C22** (DP-40: ft-Q1, types-Q2; rewritten under D48, L06 I7; L04
  §1.3, I7, I8, L16 I8) (names per D90). The frontend states only
  Idris's facts: `Nat`
  itself as a number, pointer-like word types as `u64`, the enumerated
  crash alternatives. Layout is not the frontend's: each family is
  carried whole as the instance's (keyed parameters substituted,
  dictionary fields fixed per program), a field's quantity 1 the uses
  `once` of its type's grade (`!idr.graded<once, …>`); inline or in a
  cell, a one-field collapse
  included, is one function of the type and its lifetime computed once
  (C81), byte layout the lowering's from the data layout. Families of
  numeral shape (`Fin`, `Elem`, `LNat`, a user's Peano type) have a
  number layout, a fixed width at a closed bound and `natural` otherwise,
  converted by `idr.numeral.to_nat` and `of_nat` with no range check;
  0018's D1 is amended in the same change. G's half that had the
  frontend emit boxes conflicts with D48 and goes. Deletes `Layout/Fit.cpp`
  and its whole-program remap, the second `TypeGraph` walks, the
  frontend's box emission, `Registered.Newtype` and the newtype case in
  `Cases.idr`, the Numeral-to-`NatT` mapping with its `FZ`/`FS`
  arithmetic.
- **C23** (DP-41: DD-Q4; corrected, L13 §1.1, I6). arith's school:
  signless types, the sign on the op where the computation differs. The
  four shifts stay four (`shift<Dir, S>`): a shift amount's signedness is
  part of the computation (`shls 4, -1 : i8` is 2, `shlu 4, 255 : i8` is
  0, `Ops.cpp:260-264`), so G's one `shl` is withdrawn. Family constants
  are enums (`Signedness`), never `bool`. Deletes `signed : IntTy ->
  Bool`.
- **C24** (DP-42: DD-Q5, ids-Q5; corrected, L01 I3, L13 §2.1, I5). One op
  per operation, its variant an enum of the specification: `io.clock
  <kind>` over the four real clocks (monotonic, utc, process, thread),
  `ClockKind` imported (D50); the six file-time readers and
  `io.file_time` one op with seven results (a status and six fields), as
  the one OS call is. The GC clocks are the constant -1, written by the
  frontend; `clock_valid`, `clock_second`, `clock_nanosecond` and
  `handle.is_null` are `arith` over encodings held in `Spec.Clocks` and
  `Spec.Handles`. The generated ABI row is keyed by op and case, and the
  runtime's entries are explicit instantiations of one template over the
  case. Crash sites follow D38 and C102; base primitives, C6. Deletes the
  per-clock and per-time ops, six runtime entries
  (`idris_rt_io_clock_valid` and kin, `idris_rt_handle_is_null`), the
  generator's refusal of an enum, hand arities.
- **C25** (DP-43: canon-Q3; corrected, L13 I10). Output composes a pure
  `show_*` and one `put_str`, a list as `put_str (str.pack l)`; the
  lowering emits the allocation-free entry for the composition (put and
  show already share one formatter each). Deletes the four `put_*` ops,
  `io.put_list`, `Canon/PutList.cpp`, canon's fusion
  (`Output.cpp:107-133`), the lowering's choice by element type.
- **C26** (DP-44: arr-Q2; corrected, L12 §2.8, I9, L13 §1.1, L20 §3.5)
  (names per D90). `lin.enter` and `lin.use` are one op, `lin.cast`, between types equal up
  to quantity, its direction one generated accessor (`QuantityChange {
  Enter, Leave }`), `Allocate` on `identity` both ways; one fold states the
  QTT rule (an inner cast of many to one folds only with one use). An
  array's cast is an equivalent alias of its operand, and a link (in
  place, always) is the grade, not a search: in place where the operand is
  the buffer of a value graded `unique deep` (`LArray` is unique by
  construction,
  every producer handing it to a quantity-1 binder, so `to_tensor
  restrict` is proved, not trusted, and a conflict is One-Shot's internal
  error); should §4's queue not make that promise D24's, in place where
  its equivalence chain reaches a cast out of a linear value, computed
  once. Deletes `UseModel`, `EnterModel`'s release, `isLink`
  (`Linear.cpp:32-50`) and `sharers` per query.
- **C27** (DP-45: arr-Q4; L06 I9 and L12 I10 reconciled, L12 §2.8).
  `idr.transpose` goes and nothing recovers a permutation: the frontend
  writes upstream's `linalg.transpose` (D42) where the elements are words,
  its permutation once, and a tabulation reading at the swapped indices
  where they are counted, since no linalg body holds a reference while
  counting runs (`Forms.cpp:78-97`); a transposing read inside a tabulate
  stays its indexing map. Deletes `TransposeOp` and its arms in `Forms`,
  `Linalg`, `Nests`, `TransposeColumns`.
- **C28** (DP-47: ops-Q4, drv-Q2; corrected, L03 §2.4, L12 §2.2, L13
  §2.4, L14 §2.5) (amended by D98, D100: no canonicalize pass remains,
  so no canonicalization dialects follow from the pipeline). Each op
  family declares in the specification the
  stages it is legal at (`stages = Any | From s t`, so "runs at any stage
  but sets one" cannot be written), checked by one generated trait. The
  pipeline is one list in the specification (order, reasons, options,
  each pass's kind, decide, apply or restructure, and what it keeps,
  edits or invalidates of the program graph), its stage chain proved
  there, printed into `Passes.td` and the pipeline's body, and imported by
  the frontend and the harness (D16, D50); nesting and canonicalization's
  dialects follow from it. `idr.array.yield` ends a generating op's region
  only. Deletes the role and stage records in `.td` (only `baseClass`
  printed), the TableGen `assert` at `Passes.td:66-67`, the verifier's
  stage rule, the hand order and its copy, the harness's awk, the dead
  `remove-dead-values` registration.

*Defunctionalization*
- **C29** (DP-48: defunc-Q3; corrected, L04 §2.11, I13, L18 §2.1, I5, L20
  §3) (names per D90). One walk writes the label solve's decision into the types, every
  family made in the serial decision and none on a worker: each closure
  sum is a family the pass declares (D48), indexed by its carrier's free
  index variables, each label binding its lifted function's other index
  parameters as constructor binders with no equation (a capture `xs :
  #Vect[n]` otherwise names an `n` no binder holds); a memo family is a
  cell by its kind; a linear closure's sum stays graded `once`; `byName` a
  two-case `mode` (`Memoized | ByName`); values retyped to the
  applications, legality checked by the stage verifier, with no
  per-function conversion. Deletes `Plan`, `SlotTypeConverter`,
  `RetypePattern`, the rollback, `PatternsCalls.cpp`.
- **C30** (DP-49: defunc-Q4). A use moving into two sinks unifies them;
  the plan holds one key per use; what the knot rule refuses follows from
  it (C68).
- **C31** (DP-50: defunc-Q2; corrected, L02 §2.3, L14 §1.3, L18 §1.1). No
  idr-effects pass: the one derivation of rows (D22, C64) first runs in
  defunctionalization's decision, over the program graph born there with
  no walk, once the label solve's firings have completed it; `by_name` is
  read off a label row's `io` atom (which excludes `exit`, `crash` and
  `divergence`) in the label solve, never in an op's declaration.
  Deletes `Analysis/Effects.cpp` (`solveEffects`, `observableRuns` and
  its private graph, `LabelsRun`) and the body rule
  (`Func.cpp:189-202`).

*The solver layer*
- **C32** (DP-51: QA1, QA2, Q-AN3; corrected, L14 §1.2, §2.6). Upstream's
  dataflow framework's storage is patched first (P1, carried), and Ranges
  and Borrows are measured on it (bytes per anchor on all four targets,
  the scale fixtures, stage 1); it keeps the per-value solves inside one
  function: idr-constants, narrowing's Copy, Ranges per function with
  callees-first return and callers-first argument summaries (without them
  it loses today's interprocedural precision, `Ranges.cpp:67`). Returned
  needs no measurement: it is deleted as a re-derivation (C18). Borrows
  leaves the framework for C1's marking only on the patched framework's
  number, taken first (L05's and L08's designs do not skip it). No P2.
- **C33** (DP-52, with DP-30: Q-E1, Q-M1, Q-AN2, Q-llvm-7, Q-E5;
  rewritten under AGENTS.md's order and D25, L06 I4; L14 §1.2, I6, I7).
  One call graph, written first as a carried patch to `mlir::CallGraph`,
  its upstream plan the RFC; ours in the solver layer only for what the
  patch's plan states upstream cannot hold (D2); G's own graph with an RFC
  to send later skipped the middle step. Its shape, on either carrier:
  dense ids minted by the graph and fixed for the analysis's life, born
  in defunctionalization's decision (C31); rows of `(callee, tail kind,
  sites)`, never call-op pointers; SCCs bottom-up as ranges of one
  permutation; frozen and read-only, edited only through one
  restructuring pass's editor and refrozen; preserved across nested
  groups (C114); no instance on the lowered module, where D32's bound
  reads LLVM's own. Three solve shapes on one static schedule; the
  optimizer its one dynamic client, its component merges an overlay over
  SCC ids; the giant SCC serial first. The dataflow-scope RFC is not
  wanted. Deletes `CallCycles`, `Recursion`, caller-only
  `SymbolUserMap`s, every name- or pointer-keyed function map,
  `Scc.cpp`'s copies, the ready set's private graph
  (`ReadySet.cpp:27-75`), `TailCallPlan.cpp:72-88`'s user map, the
  optimizer's second walk.
- **C34** (DP-53: QA4, Q-O2, QL1, Q-llvm-3, QL3; corrected, L08 §1.7,
  §2.4, L14 §2.2, I11, L15 I-3, I-9). Shared concept-constrained types
  (`Id<Tag>`, `IndexVector` with raw index deleted, `Graph` modelled by
  `Csr<Tag>` with a sentinel root row and `GraphTraits` whose `NodeRef`
  carries its graph, `GatedCsr`, `Lattice`, `Summary`, direction the
  graph view's type) and three algorithms: the marking, with four clients
  (exclusivity, allocation into a lifetime, borrows, the obligation
  closure), ordinary functions compiled once behind an inline wrapper,
  its gates data propagated as Horn clauses, never a callback (a
  non-monotone gate would compile and change a verdict with the
  schedule); `summarize<Order, Problem>`, explicitly instantiated once per
  problem behind `extern template`; extract-solve-link. Each solver runs
  over a read-only view. A function's numbering is cached within one pass
  or one nested pipeline (blocks numbered per region, plus an offset),
  never maintained across rewrites. An analysis declares the analyses it
  reads as a type, its `isInvalidated` generated from the list. The label
  solve keeps its rules as data; the frontend's translation is relational
  (D44). Deletes six numberings, pointer-keyed solver maps, dead
  worklists, `MonotoneWorklist`, `FiniteLattice`, `bool backward`, the
  solvers' `function_ref`s and every gate callback, the hand
  `isInvalidated`s.
- **C35** (DP-54: QA3, Q-opt-4, hist-Q3; corrected, L06 I11, L14 I4, L18
  §1.1). Patches 06, 28 and 63 reach nothing in the tree and are retired
  (AGENTS.md). The per-function `remove-dead-values` is measured in the
  cutover's qualification with upstream fixes U1 and U2 (M3d) and returns
  nested on `idr.func`, its patches carried again, only if it erases what
  the rest leave and fits; otherwise that measurement goes into the
  patches' `upstream/` record, never a removal on a run stopped by hand.
  Dead parameters are a demand bit in the optimizer's summary, the callee
  narrowed before its callers run; dead results, one callers-first pass;
  only many-quantity parameters can be dead. A function a closure label
  names has an unknown caller only before defunctionalization; after it
  every caller is in the graph, and an unread capture is narrowed by
  dropping its constructor's field, the family redeclared after knots.

*Counting*
- **C36** (DP-55: rc-Q2, own-Q3; corrected, L07 §2.5, L08 I-5, L18 I6,
  L20 I7). One solve proves what it can, by context: its nodes are (value,
  mask) pairs created as calls reach them, a call's mask only losing bits,
  re-marked with targets fixed until none moves; one grade copy per
  reached (function, mask) whose answer differs, named from its key, with
  no budget (the key space is finite). Copies are made by the one
  clone-and-key template, generic over a key alphabet with an order and a
  lift (grade copies: a finite alphabet, equality, no lift), which copies
  each parameter's grade from the original by construction; join regions
  take the same keys. The run-time test stays only as `idr.match_unique`'s
  unfolded form (C39), where exclusivity is unknown until run time, and
  its code says so. No promise rests on a copy (D24). To measure on stage
  1: reached pairs, copies, code size, the solve's time and footprint.
  Deletes counting's own cloning code, `givesExclusive`, `copyable` and
  the key closure (`Specialize.cpp:51-69, 92-117`), the second solve and
  its hand pass manager (`Exclusive.cpp:39-54`), the grade restatements in
  `Declare.cpp:39-42`, `Patterns.cpp:43-45`, `Keys.cpp:218-222`.
- **C37** (DP-56: rc-Q5; corrected, L07 §1.2). Drops go at last use, over
  quantity-many values only (a quantity-1 value's last use is its one
  use), with the problem's exceptions: a loop holding an outside value; an
  array held across its update; a crash region, only on paths that
  allocate and call nothing before ending (D26 on such a path is §4's
  queue); every call in tail position and every D34 site, whose
  parameter is owned (D30, D34); a borrowed argument only where C1 allows
  one, join parameters included. No lexical lifetimes for drops: Idris
  has no destructors.
- **C38** (DP-57: count-Q3; corrected, L04 §2.16, L07 §2.13, L10 §2.5,
  I-11, review §4.4) (amended by C203: the one decider writes
  `modulo_context` at the first-order stage, still before counting). Tail recursion modulo context is read off the
  program before counting (D34): the frontend writes `modulo_context` on
  the call, which needs case blocks emitted in place (C55). Its source
  condition states the evaluation order: the self call is the last
  evaluated component of every context cell on its path, so building the
  cell first moves no crash across a divergence (D13), and an effect
  moves only where D21 allows. Counting runs first and honours it:
  placement puts nothing between the self call and its context's
  constructors, the walk holds the scrutinee's token across the call and
  recycles it at the context's `cell.init`, where idr-trmc executes it.
  `!idr.dest` stays linear by its type, typed by a family application
  whose layout is a cell with its constructor and field positions (D48).
  Mutual recursion modulo context is not promised. Deletes Borrows'
  prediction of idr-trmc, finding the context after counting and TRMC's
  second `contextAt` (`IR/Tail.cpp:134-195`), `BoxType` as the
  destination's parameter.
- **C39** (DP-58: conv-Q3; corrected, L01 I4, L04 §3, L05 §2.3, L07 §2.5
  to §2.7, I3, I4, I7, L08 §2.2) (names per D90) (amended by D98: our
  ops carry no canonicalization pattern, so the fold by grade is not
  one; which of D98's forms takes it is not ruled). The take's expansion
  is counting's last step at the `idr` level. Uniqueness is a two-region
  match, `idr.match_unique %x` (`RegionBranchOpInterface`): `unique`
  receives the token, `counted unique deep` and never null, and the
  fields `counted`; `shared` receives views, dups the living fields and
  drops `%x`. Canonicalization folds it by grade, `unique deep` to the
  unique region and a value `scoped` to this call's lifetime
  (`idr.activation`) to the shared one; an unfolded one lowers to
  `scf.if` on "count is 1", for `counted` values only. A reuse token is
  `!idr.reuse_token<{#F[i] @C, ...}>` (C253), a non-empty set of one layout, linear,
  `counted unique deep` or `counted`, with no lifetime parameter; `idr.token.null`, written only past the copy budget, is the
  one source of a null token, `idr.token.free` frees one (an exclusive one
  with no test, a maybe-null one testing null only), and `idr.take_into`
  fuses where every path recycles. Counting's ops take only values whose
  layout is a cell; `take` and `drop` take `counted` values and declare
  `CountsIfShared`; `cell.recycle` is counted only and declares
  `Recycles`. Moves and counts are IR; the lowering lowers primitive ops
  only. Deletes the lowering's uniqueness branches (`Counting.cpp:47-49,
  91-107`, `Cells.cpp:123-140`, `Elements.cpp:64-82`), `LowerTake`, two of
  `idris_rt_free_cell`'s three tests, the exclusive drop's count read, the
  `Fields` table, the token's null where none can be, and the runtime's
  stack-bit test if the counted stack cell goes (L05's question to the
  owner).
- **C40** (DP-59: rc-Q4, rt-Q1; corrected, L11 §2) (names per D90). No
  counted cell is ever shared between threads (no atomic count, no
  mark-shared pass); shards pass cells by detach (C2). The count takes
  Koka's signed encoding without atomics (0 unique, negative sticky),
  "count 0 is persistent" moving to the sticky constant; with `static`
  in the type (D88, D90) a `dup`
  or `drop` of a static value cannot be written, and the sticky test
  serves only run-time facts. The kinds of word form an ABI lattice
  (`Cell` below `MaybeCell` and `Big`, their join `Any`), one `inc` and
  `dec` instantiation per kind, `layout::Component`'s `bool counted` the
  kind; the type-blind free keeps its test, which is essential. Deletes
  `count == 1 && !stack`.

*Verification and the pipeline*
- **C41** (DP-60: ods-Q6, Q-M2, Q-O5, types-Q1, drv-Q3, T-Q4, T-Q5;
  corrected, L02 §2.5, L04 V2, L05 §1 D39, L07 §2.14, L09 I9, L14 §2.5,
  L15 I-5, L19 §2.2). Full verification after every pass in every build,
  cheapened by nesting as a rule: a decide step changes no op and
  preserves everything, so the verifier skips it; apply groups rewrite
  functions in parallel, reading their decision through a const view; only
  restructure passes change the program's shape. The owned rule's walk
  splits: its views half goes (D39); its exactly-once half joins the one
  linearity verifier, which checks owned references exactly once and
  quantity-1 values at most once (the max over a match's alternatives,
  the sum over a join's sequential regions, a repeated region counting
  twice), on its success path summing uses unordered and numbering only
  past one, and asking region exclusivity once per op class. The owned
  stage adds: each token consumed exactly once per path, none at
  quantity many, no `dup` or `drop` of a quantity-1 value, a recycle's
  layouts equal. Each function's verifier checks its row (C64) and its
  cases' refinements in one fused walk. A pass that changed nothing
  preserves all analyses (patches U-a, U-b, carried). Contracts are
  per-function test records checked per stage (C130); the verifier's
  cost is read from `--mlir-timing`. Deletes the program verifier's serial
  walks (`effectsCovered`; the name-alone walk, `Func.cpp:56-90`),
  `Owned*.cpp` whole, the contracts' module clone (`Contracts.cpp:306`),
  hand nests, the linearity verifier's `Numbering`, `holders`, `byBlock`.
- **C42** (DP-61: conv-Q2). Two program passes (declare every runtime
  function, make every static datum, once), then the lowering as a
  function pass. Deletes the worker-and-merge scheduler. *Corrected*
  (recheck 3, L21): the lowering is anchored on the program and lowers
  each function inside it, since a pass cannot replace its own anchor
  `idr.func`; the contract `parts/contracts/spec-core.md` and
  `Pipeline.idr` say so, and no worker-and-merge scheduler is left.
- **C43** (DP-62: drv-Q4; L10 §1 D33, L15 §1.3). Every thread of the
  compiler runs on one stack size, D33's measured bound with a margin,
  set through a carried patch giving `StdThreadPool` a stack size and
  sized in one platform place; the tools' reservation (2^36 bytes,
  `runtime/Start/Runner.cpp:44`) shrinks in the change that lands the last
  upstream recursion patch (C99), not "until". Deletes OS-default worker
  stacks and `PINS.md:595`'s stale 2^40.
- **C44** (DP-63: drv-Q5). The prepared runtime's bitcode lives beside the
  object on every target. Deletes `BitcodeHome`, its switch, both CMake
  branches, the section path.

*Specialization*
- **C45** (DP-64: Q-O4, Q-M5, Q-opt-1, ft-Q3, Q-opt-2; corrected, L04
  §2.7, L05 §2.4.4, L09 §2.5, L18 §1.1, I7). The bottom-up schedule
  stays, what a call reaches one sum decided at the grant, in MLton's
  order after acceptance (C68): specialize to completion with leaf
  inlining (no call, at most 40 ops) inside it; inline once on the final
  graph with true call counts on upstream's `mlir::Inliner`, the verdict
  its callback (an upstream patch for parallel components only if the
  serial walk measures as the wall); contify again, a fixed sequence and
  never a fixpoint; normalize. Keys include known index terms by layout
  class (D58, C81) with a run-time value's linked term (D59) and an
  array's size key (D60), allocation modes and `static`; a callee that
  puts into a caller's lifetime, taking its token as the arena handle
  (D63), gets a counted copy for callers that pass none. No
  polyvariance before the acceptance solve; after it, only if the closure
  sums shrink, a C++ pass under a budget, never the frontend's. Deletes
  OPT-84's five rules, `inlineCalls`, `inlineStep` and the inline step
  outside a pass, `betaReduces`, `callsOnlyBeside`, `dispatched`,
  `no_inline`, the per-round interleaving.
- **C46** (DP-65: Q-opt-3; corrected, L18 §2.2, I6). Keys are the run's
  own interned data (a closed sum in an arena), freed with the pass,
  taking no context lock, printed on demand. A key gains index patterns; a
  node's name is a digest of the key's canonical bytes, owners spelled by
  symbol, never printed text; the lift is anti-unification over every
  same-shape earlier key at once, so the order workers take a lock cannot
  reach a node. Deletes `Idr_SpecKeyAttr`, `Idr_KeyRaiseAttr`,
  `Idr_KeyHoleAttr`, `Idr_KeyConAttr`, `chainOf`'s dependence on order
  (`Requests.cpp:91-104, 153-155`), the global node-table mutex.

*Rewrites and tools*
- **C47** (DP-66: ods-Q4; L03 §1.1, L13 §2.5) (superseded by D98). DRR for rooted local
  patterns, each a record of `IdrisMLIR.Spec.Rewrites` printed one to one
  as `Pat<>` (D16); today's `.td` has none, so DRR enters with its first
  pattern (L13 lists six output and head patterns). PDLL refused;
  region-reading patterns stay C++. Deletes five C++ pattern classes,
  `StrBuilderOpInterface`'s partial methods (`writesInPieces`,
  `writePieces`, `knowsFirstChar`, `firstChar`, the five `unasked`
  stubs) and `Output.cpp`'s fusion.
- **C48** (DP-67: canon-Q5, canon-Q4; corrected, L09 §2.3, L13 §2.4, I9) (superseded by D98).
  Upstream's canonicalizer on the greedy driver, one configuration
  generated from the pipeline's specification: top-down, region
  simplification off, `maxIterations` 10, no CSE between iterations,
  `testConvergence` on in canon tests only, `filter-dialects` derived from
  each point's stage-admitted ops, never listed. Two carried patches: a
  per-op rewrite bound (`setMaxNumRewritesPerOp(k)`, pass option
  `max-num-rewrites-per-op`; C15), since today's bound counts per run;
  and preservation when nothing changed (the pass reporting `&changed`, as
  CSE does). The join ops register upstream's dead and duplicate
  successor-input patterns, correct only with C93's fixes; one match view
  per visit. Deletes the second configuration (`Optimize.cpp:64-66`), the
  hand dialect list, `kNoLimit`, the per-visit rescans and string roots.
- **C49** (DP-68: canon-Q1; withdrawn, L18 §1.1, I1, I2b). No
  canonicalization runs before defunctionalization: it would change the
  label sets idr-knots reads, under a budget, and fold a suspension into a
  static memo cell memoized even where its runs are observed (against
  AGENTS.md: a trusted IO action's effects happen where its value is
  demanded). Acceptance comes first (C68).
- **C50** (DP-69: Q-llvm-5, ids-Q3; corrected, L03 §1.7, I-3, L04 §2.3,
  §2.8, L16 §1.1). Every `idr` type and attribute, D48's family
  attributes included (a group one record `Families = (Array<Member>)`,
  terms `Array<TermNode>`, acyclic), is native in bytecode, its layout
  derived from the type's parameters (`Bytecode = Derived | Custom hook`,
  `Custom` only for a checked builder), its encoding printed from the
  specification for the C++ and the Idris writer (D16). No `idr` text
  crosses the handoff, and a double crosses as its 64 bits. The copied
  format parser stays only in D51's backend, for `arith`'s and `ub`'s
  attributes printed as text. Deletes the parser's `idr` use, the Idris
  printers (`Syntax/Idr.idr`), the hand record switch, the restated
  member lists (`IdrBytecode.td:38-65`: `BoxType`, `TableCtor`,
  `TableMember`, `DataTable`), raw record reads and string compares,
  decimal doubles.
- **C51** (DP-72: ids-Q4; corrected, L03 §1.6). Every binder specgen
  prints in an Idris builder is primed, so no keyword list is copied. A
  builder takes one argument per operand group (a `Value`, a `List Value`
  for a variadic group, a `Maybe Value` for an optional one; 32 ops have
  variadic groups), the op indexed by its group counts; "operands are a
  `Vect n Value`" is withdrawn.

*C++*
- **C52** (DP-73: Q-llvm-4, cxx-Q2; corrected, L15 §1.5, §1.6). One
  exhaustive fold, `match`, over every closed sum of ours, coverage
  checked at compile time. `get_if`, `holds_alternative`, `std::visit`
  (libc++'s dispatch cliff at 11 alternatives,
  `libcxx/include/variant:1596-1607`) and `TypeSwitch`, a ladder by another
  name (05 ID10 and synthesis B §2.9 still allow it, against D47), are
  banned: 189 accessor uses and 4 `TypeSwitch`es go. `PointerUnion` for
  pointer-sized handles, read by the same fold.
- **C53** (DP-74: cxx-Q3; rewritten, L15 I-11, replacing G's "none of
  ours" and L06's compile-time-cpp §7.2 contents). One precompiled header
  on `IdrIR`, reused by every target of ours, after the `-ftime-trace`
  baseline: libc++, LLVM's ADT, MLIR's `pch.h` set and `IdrDialect.h`
  (with `IdrOps.h.inc`, 38,361 lines included by 263 files); our
  vocabulary headers stay out, so an edit of `Support/Id.h` rebuilds no
  header and a missing include stays an error. `-fno-pch-timestamp` and
  ccache sloppiness; no C++ modules in P0; measured as built.
- **C54** (DP-75: cxx-Q4; L11 §2.9, L15 §2.2). Extensive libc++ hardening
  in every configuration; a failure is a bug of the runtime or the
  compiler, routed by a handler to D37's internal-error ending; release's
  cost measured and reported. `IndexVector`'s bound check is that
  hardening, kept because two scopes numbered under one tag share a type;
  its code says so. Deletes the bare trap.

*Frontend and fork*
- **C55** (DP-76: Q-FB1, tail-Q4; corrected, L16 §1.2, §2.2, I5, L17
  §1.2, I6). The fork stops building the run-time case tree; the TTC
  keeps 0003's `scTy`, the clause index and each clause's builder
  patterns (D44), so the alias map is a per-clause column of the
  definition table; once it keeps a block's typed parent (C129), a case
  block is emitted in place as a region of its parent (D19). The profile
  and keys read `refersTo` from the compile-time tree. Deletes
  `mkRunTime`, `compileRunTime`, `toCompileCase`, `canInlineCaseBlock`,
  `canInlineDef`, `inlineSafe`, the elaboration-time use of
  `Core/Transform.idr`, `TTImp/PartialEval.idr` whole (with
  `%transform`'s rounds and `%spec`'s limits), `PMDef`'s run-time tree
  field, `refersToRuntimeM` and `calcRefs`'s `Bool`, the case builder's
  `RunTime` phase and `-Xcase-tree-opt`, `Forced.idr`, `host.argToPat`,
  `Cases`' guesses.
- **C56** (DP-77: Q-fc-2; corrected, L16 §2.10). If stage 1 shows the
  node split's products large, the growth check's flow splits by node,
  acceptance unchanged, and D46's derivation covers the split form; the
  derivation concludes sizes and breadth as well as heights, since the
  worklist recurses on `InUniverse`.
- **C57** (DP-78: ft-Q4; L16 §2.5). The module is the one output; the
  Core dump (79 MB on the self compile) goes, its two readers reading the
  module.
- **C58** (DP-79: ft-Q5; corrected, L16 §2.5, I7, L17 §2.7). A refusal is
  an op of the module, one per refusal, its site the op's location and its
  rule an enum property from `Spec.Rules`, which is indexed by category
  and carries its scope (`reject : Rule c -> ...`); never the fork's
  `Error` or a side channel. A removed pragma reaches the frontend as
  Idris's parse error, category `elaboration`. Deletes `idr.refusals`
  (`Emit.idr:104`, `IdrBase.td:68-70`, `Verify/Attributes.cpp:21-28`,
  `Driver/Run.cpp:231-237`), `Profile.outsideLanguage`, `TS.inFlight` and
  the dedupe by printed text.

*The runtime*
- **C59** (DP-80: oom-4; rewritten under D32, C5 and D10, L06 I3).
  Compiled code takes no stack probes: its frames are static and the
  guard is at least the largest, checked when the program is built (D32,
  C5), so a probe would test at run time what the build proved. The
  runtime, GMP and the tools, whose frames the compiler does not size,
  take `-fstack-clash-protection` on every target; the signal stack has
  its own guard (C5). L10 and L11 keep probes on every function with a
  one-page guard, and L11 would delete D32's build-time check (L11 I11):
  that changes D32, so it is the owner's. Deletes `Runner.cpp:35-37`'s
  unchecked claim and the planned probe plumbing from the target's entry
  into the lowering.
- **C60** (DP-81: rt-Q2, rt-Q4; corrected, L01 I7, L11 I5, L19 I5).
  Shipped programs neither count cells nor read an environment variable;
  the count lives in the checked runtime, which every program case links,
  and a run whose main returns with cells live ends as D37's internal
  error naming the count; the shipped binary is checked to hold no count
  symbol. The counter goes no later than the effect tree, since under D23
  its output would change with the optimizer. The IO test writes past the
  shipped buffer; the compiler's folders count no cells either. Deletes
  the `thread_local` count, `liveCells`, `forgetCell`,
  `idris_rt_live_cells`, `reportLiveCells`, `IDRIS_RT_LIVE`,
  `IDRIS_RT_IO_BUFFER_SIZE`, the harness's count parsing, `countFoldLeak`
  (`IR/Fold/Scope.cpp:21-31`).
- **C61** (DP-82: rt-Q5; corrected, L11 I1, I2). snmalloc becomes a
  patch project (`tools/patches.sh:22`, PINS.md), carrying three patches,
  each with its report, test and plan (a submission: snmalloc wants a
  CLA): the seed-range hook, commit failures reported, the bounded page
  map's range checks (C100). Our copy of its config goes.
- **C62** (DP-83: conv-Q5). One prefix on every program symbol, so none
  is a runtime symbol or `main`. Deletes three collision checks.
- **C63** (DP-84: oom-7, oom-8, oom-9). Returning stack memory is D31's
  (frame stacks give chunks back, one spare kept) and D32's (the native
  stack is small); a pressure signal and shards' limits wait until a
  program or a shard needs them (C2, D36); the backend, and so the span
  and the limit, is process-wide.

*Settled by rulings, not restated:* DP-22 and DP-24 (AGENTS.md; their
gates struck as meta-work), DP-23 (D16, D50), DP-30 (D25, inside C33),
DP-31 (C3), DP-46 (D31), DP-70 (D16, D50), DP-71 (D49).

*From the verification swarm* (2026-10-21). Each is a lane's
improvement the lane or the coordinator marks the coordinator's (the
evidence, AGENTS.md or elegance settles it); the six the coordinator
named in `audits/p0/verify/status.md` are C11 (family prefixes) and C64
to C68, and its two answers to L03's questions are C6's replacement and
C137.

*The coordinator's six*
- **C64** (L14 §1.1, I2; L02 §2.3, F4, F17, I3, I8, I9) (amended by D98:
  where our ops are, the e-graph pass, not the canonicalizer and CSE, is
  what shrinks a row between derivations; "covers" stands). A function's row
  covers its derivation after every pass and equals it right after each
  re-derivation; a call's row equals its callee's. D22's own word is
  "covers": the canonicalizer folds a match and deletes crash and IO ops
  with no hook of ours, and CSE erases dead reads, so equality after every
  nested pass would need a program-level writer after each. The
  derivation is one fold over each op's declaration form, a call
  contributing its row and D61's per-parameter part; an effect on memory
  the function acquired itself (`Allocate`d on `heap` or the frame in the
  same function) projects to nothing. Its writer joins over the program
  graph's components callees first, with no iteration, as an incremental
  decide step seeded by the functions whose row shrank: after
  defunctionalization, after each optimizer component, at the end of
  every program pass that adds effects (bufferization, frames, each
  counting pass, TRMC) and last before the lowering. `idr.func`'s region
  verifier checks containment; `idr.call`'s symbol-use verifier,
  equality. Deletes §5.1's equality as an after-every-pass check, the
  verifier rule V0, `effectsCovered`'s serial walk
  (`Verify/Program.cpp:53-72, 260`).
- **C65** (L09 §1.6, §2.1, §2.7, I2) (amended by D98: our ops carry no
  canonicalization pattern, so a loop with no back jump becoming
  `idr.join` is not one; which of D98's forms takes it is not ruled).
  `idr.join` and `idr.loop` are split,
  one family. `idr.join` is non-recursive, its continuations' tokens
  defined in its body, so its join regions cannot name them; `idr.loop`
  is a recursive group whose every region begins with the tokens,
  implements `LoopLikeOpInterface`, and carries `idr.may_loop` at each
  join region's entry in code of partial origin; an `idr.loop` with no
  back jump canonicalizes to `idr.join`. One op per semantics: repetition
  and divergence are the difference, and tokens in every region would put
  10,100 of them on a 100-case consumer. Deletes `Tail/Loop.cpp`,
  `Tail/WhileDo.cpp`, `TailLoops.cpp:13-23, 128-169`, the `i1`
  "continue" flag and its poison halves.
- **C66** (L17 §1, I1; review §1 item 3, §9.2; within D53). The path rule
  compares a goal only with earlier goals of the same type constructor,
  argument by argument, with constants ordered by value; a numeral of a
  unary type enters as its tree `S (S … Z)`, so `LTE 4 10` does not
  embed in `LTE 3 9` and upstream's own `natToFinLT`
  (`libs/base/Data/Fin.idr:186-187`) elaborates; universe levels, which
  carry fresh names, are one symbol, or Kruskal's premise fails
  (`Check.idr:410-416`). D53's meaning, a search that ends by
  construction with no count, is kept, and it refuses fewer finite
  searches (`Rose Nat`, an `Integer` countdown). Discriminated by
  `natToFinLT 3 {n = 10}` elaborating while `Cons2.idr` is still refused.
- **C67** (L18 §1.1, Q1, I4; AGENTS.md's definition). A run-time choice
  among implementations the program fixes is a closed sum, compiled like
  any other, not megamorphic: AGENTS.md defines megamorphic as a set no
  compile-time analysis bounds, and the program bounds this one; where no
  static dictionary exists it is a run-time record of closures,
  defunctionalized. Seven tests that refuse such a choice under
  `Megamorphic` (`IdrBase.td:192-202`) become program tests. AGENTS.md's
  example, "an implementation chosen by a runtime value", reads against
  its definition here; its wording is the owner's.
- **C68** (L18 §1.1, §2.3, Q2, I1). Acceptance comes before optimization:
  the label solve runs on the frontend's program, total and with no
  budget, and idr-knots right after defunctionalization; every
  optimization runs after knots. The knot rule is stated over the label
  solve's least solution of the program as written, so a change of its
  precision is a change of the language, made in a commit that says so
  with a test at its boundary. Today deduplication before the solve
  unions merged functions' parameter sets
  (`EliminateDuplicateFunctions.cpp:23-26, 202-212`) and can add
  `unsupported (cycle)`. Deletes deduplication's first slot
  (`Pipeline.cpp:62-71`), DP-68's pass (C49), polyvariance before the
  solve.

*Effects*
- **C69** (L01 §1.9, §1.10, I3; L02 F7, I4; L13 I5). Every declaration
  states what its runtime function does, held to it by
  `tests/runtime-effects` on the four targets: `handle.string` writes
  `crash` until `getString` of a non-string handle is a guard at the call
  (C101); `array.set` declares its count write and free, `array.new` its
  fill's count write; `array.yield` consumes and `own.adopt` takes a
  fresh identity, neither `Pure`; `nat.from_big` writes a count and
  acquires nothing; `memo.run` writes counts; `io.exit` writes `crash`
  as well as `exit`, since a status outside 0 to 255 crashes at its site
  (D64; L01 §1.4 D14); `io.file_errno` reads
  `runtime_state`; `io.pid` and `io.arg_count` declare nothing; a runtime
  edge case that returns its argument shared (`str.append`,
  `str.reverse`, `str.drop_bytes`, `big.shl`, `big.shr`) copies instead.
  Consumption is `Free` on `count` alone: a `Read` beside it put `count`
  in every row passing an owned value and bought nothing. `Scratch`
  becomes `RuntimeMemory`, memory no value names, which reports `alloc`
  and `free` and is never an MLIR effect. The one query API compares
  `ResourceId` exactly, never upstream's `isa`, whose `classof` makes a
  crash's resource an IO one (`SideEffectInterfaces.h:108-115`). Deletes
  `io.term_setup`, the `Pure` on `array.yield` and `own.adopt`, the
  consuming ops' `Read`.
- **C70** (L15 §2.7, I-2; L01 §1.11, §2.2; L02 F9, F15). An op's
  declaration is two independent facts: its own effects, static or by
  typed rules each reading one value's own type, operand or result
  (`Consumes`, `NewIdentity`, `Acquires`, `ReadsMemo`, `CountsIfShared`,
  `Recycles`, `Summarized`, `ReleasesForeign`); and its bodies' effects,
  its own or recursive. `idr.match` needs a typed own part and recursive
  bodies, which "five forms, exactly one per op" cannot hold. "Runs
  unknown code" is a static row; a definition declares nothing. At HEAD:
  112 static, 57 typed, 7 recursive, 2 running unknown code, 2
  definitions, 9 deleted or merged. Region-op sets are folded by each
  reader's walk through the function's numbering, never a pointer-keyed
  map; "declares nothing" is `EffectSet::everything()`, no `bool`; the
  dynamic facts gain one, which resource an upstream effect names (a
  `TypeID` compare forced by MLIR's open set). Deletes `AcquiresCell`,
  `effects.md`'s `Node`, `Nodes`, `exact`, `recursive`, `unknown`,
  `allocOther`, the nullable `Cache *` and `Cache::of(Operation *)`.
- **C71** (L01 §1.1, I5). A fresh identity is not fresh memory: upstream's
  `LocalAliasAnalysis` reads any `Allocate` on a value as fresh memory
  (`LocalAliasAnalysis.cpp:240-292, 403-421`), so `%l = idr.lin.enter
  %arg` would not alias `%arg`. The first pass of ours that adopts it
  carries an upstream patch, a `Resource` hook (default true, false for
  `identity`); until then it is not run on `idr` ops.
- **C72** (L02 §2.6, I1, I2, I5, I6, I10, F6; L10 §2.1; L20 I6; D61). What
  LLVM is told, by one generated function from a row. `memory(...)` has a
  `read` floor, never `none`: reuse rebuilds a cell under the same pointer
  (`Conversion/Counting.cpp:86`), and LLVM merging two `memory(none)`
  calls across that store prints 2, not 3; `write` joins to readwrite
  (LLVM's `write` alone makes a first read poison); `free` adds `argmem`;
  acquisition, release and `crash` add `inaccessiblemem` and `errnomem`;
  D61's per-parameter write is `argmem` only. `willreturn` only for a row
  with none of `io`, `exit`, `crash`, `divergence` (an IO action may block
  or end by `SIGPIPE`; LLVM's own table gives `read` and `write` none);
  `mustprogress` not with `divergence`; `nofree` not with `free` or
  `exit`; `nounwind` always; `nosync` per atom, withheld from `io`,
  `alloc`, `free` once 0007's shards land. The step that leaves `idr.func`
  builds `llvm.func`, `llvm.call` and `llvm.return` directly, the
  post-lowering passes nesting on `llvm.func`. Every exclusive owned
  pointer parameter is `noalias`; contents loads carry `invariant.group`,
  in-place writes go through a laundered pointer. `idr.call` is
  `ConditionallySpeculatable` from its row (no `io`, `exit`, `crash`,
  `divergence`), so LICM can hoist it. Deletes the `memory(none)` outcome,
  `FuncToFunc.cpp`'s `LowerFunc`, `LowerCall`, `LowerReturn` and the
  `func.func` stage, `Runtime::mayLoop`.
- **C73** (review §7) (amended by D98, D103: where our ops are, CSE gives
  way to the e-graph pass; D103's order lets a heap read move across a
  crash check or out of a loop that writes no memory it reads, and C151
  carries the LICM patch for the loop only if a measurement asks for it).
  Upstream reads the tree's disjointness only in CSE
  (`Transforms/Utils/CSE.cpp:222`), which treats only writes as
  conflicts; LICM moves only pure ops
  (`LoopInvariantCodeMotionUtils.cpp:117`). D21's freedom to move a heap
  read across a crash is cashed in hoisting and sinking only by a
  resource-aware LICM, written first as a carried upstream patch
  (AGENTS.md's order). An op whose only effect is `Allocate` on its own
  result is trivially dead, which the law "an acquisition names its
  result" already requires.
- **C74** (L16 §1.1 D13, I1; L02 I12; L18 I3) (amended by D102: a row
  with neither `divergence` nor `crash` is not what `total` gives, since
  totality removes divergence only; the deletion rule stands). Divergence
  follows Idris's
  components: `Termination = Terminates ComponentId | MayDiverge (List1
  Name)`, decided per Idris component; Emit writes the component on
  `idr.func`, a lifted lambda taking its owner's, and a component of ours
  is marked non-diverging only when every member terminates in one and
  the same Idris component, since specialization and defunctionalization
  make cycles Idris's graph never had (`data D = MkD (D -> Nat)` reads
  "terminates" today, so an unused looping call is deleted, against D13).
  The attribute is `terminates`, written exactly when Idris's checker says
  so (`Translate/Closed.idr:459-472`; today's `total` means only this); a
  call is deletable when its row has neither `divergence` nor `crash`,
  which is D13's `total`. Nobody clears it: a made function's is its
  origin's, or true when its final component has no cycle. Deletes
  `Facts.terminating : Bool`, `TS.loops`, `fromMaybe False`, the blanket
  `total' = True` on lifted functions, `FuncOp::absorb` and its two calls
  (`Inline.cpp:156`, `Contify.cpp:109`).

*The specification*
- **C75** (L03 §1.11, §3, I-2, I-4, I-6, I-7). Inside the specification
  every reference within an op is a position: `Op` is indexed by its group
  counts (`Vect i Operand`, `Vect o Result`, `Vect a Attr`, `Vect r
  Region`), and the format, guards, effect rules and type relations name
  `Fin`s, names living only in the operand records (a lookup that can miss
  is a missing index, and `auto` search depth differs between the hosts).
  A primitive's binding is checked against its op through quantities: its
  arguments at a non-zero quantity, the world aside, number the op's
  operand groups, literals filling the rest. Grade rules are typed data
  (`Graded`, `ResultQuantity = MaxOfOperands [positions]`, linear by type
  a fact of each type), printed to the C++ and imported by Emit. specgen's
  C++ printer has no `if`, `switch`, `isa` or concept body: a per-op fact
  is a table or a specialization (D47 for generated code). Deletes the
  three erased searches (`named`, `ruled`, `guarded`), `Guard.operand :
  Nat`, Emit's internal errors at `Emit/Operations.idr:67, 82`, the
  closure-quantity rule at `Emit/Bodies.idr:331-344`, `linear One WorldT
  = False`, the three `CPred` strings per read class.
- **C76** (L03 §1.3, I-9; L15 §1.1; review §6). A law the specification
  proves reaches C++ as its table, never as a second proof: C++ asserts
  only that a hand function equals a printed table, and
  `static_assert`/`consteval` check facts whose subject is C++ (for a law
  the specification states, D7's check when the compiler is built is
  Idris's). Idris's types prove the specification's internal laws (the
  tree, the grade algebra, index arity), not the hand C++ the printed
  `.td` names (183 code blocks of about 1,590 lines, 36 `CPred`s, 37
  `extraClassDeclaration`s): each becomes a named hook whose declaration
  is printed and whose definition is written by hand, a missing one a
  link error. Deletes compile-time-cpp's `semilattice()`-style re-proofs.
- **C77** (L03 §1.6, I-5). The dialect list and the admitted upstream set
  are one fact of the specification (`Spec.Core.Dialect`,
  `Spec.Admitted`, one `IdrAdmitted<D>.td` per upstream dialect). The
  frontend and the harness import nine closed sets, today's nine
  namespaces of `Syntax/Idr.idr` (`CtorRole` and `SumKind` going with
  D48). `IdrRules.txt`, `IdrPassRoles.txt` and `IdrPassStages.txt` go once
  their shell readers move into the Idris harness (`harness/lib/rules.sh:17-18`,
  `profile.sh:56`, `differential.sh:16`, `tests/rules-covered/run:23`).
  Deletes `tools/dialects.sh:83-93`, `MLIR.idr`'s per-dialect
  constructors and string dialect names, the writer's "text before the
  dot", the unused upstream builders.
- **C78** (L03 §1.1, §1.8, I-8; L19 I9; review §6). specgen reads no file
  and sorts nothing: its core is `generate : List (Path, Doc)` with no IO,
  `Doc`'s leaves `String` and `Integer`, every identifier ASCII (no
  code-point operation, or every `Doc` checked ASCII), so its output is
  the same on both hosts and all four targets; a wrapper writes a fresh
  tree and compares it. The fingerprint covers the generator's own
  sources and hashes the specification's printed value, in D67's one
  committed manifest. specgen's first output prints exactly what today's `.td`
  and generator produce (today's def names, since mlir-tblgen emits ops in
  def-name order, `OpGenHelpers.cpp:55`; the order of types, attributes
  and interfaces; the explicit values of `Quantity`, `Rule` and
  `CheckKind`), held by byte identity in the cutover's qualification
  (D56), never as a step built on its own; each later change deletes its
  construct's constructor and printer branch with it. Deletes
  `tests/dialects-current`.

*Data types and lifetimes*
- **C79** (L04 §2.2, I1, I14; L05 §1 D48, I8; narrowed by D63). Index
  variables are de Bruijn levels of one telescope per scope, a
  declaration a scope of its own: types print and unique with no context,
  values flow inward by dominance, and names are for readers. Lifetimes
  are SSA values (D63), so the telescope holds index variables alone and
  upstream's inliner, CSE and dead code handle lifetimes with no
  substitution of ours. One interface, `ErasedBinderOpInterface`, over
  the ops that bind index variables (`idr.func`, `idr.match` per case,
  `idr.join`), and one substitution utility for the verifier, the
  specializer, folds that
  inline a case and the inliner: an index-polymorphic callee, which
  upstream's inliner rejects (`InliningUtils.cpp:395, 532`), is cloned
  under the substitution, its impossible cases pruned, then inlined by
  upstream's `inlineCall`, with no upstream patch.
- **C80** (L04 I4, I5, I6; review §2.1). A group is a strongly connected
  component of the monomorphic instance graph, not an Idris `mutual`
  block (`Rose`'s `List (Rose a)` is a member), in a deterministic order;
  one `regroup` utility forms new groups where defunctionalization makes a
  cycle, `AttrTypeReplacer` remaking content elsewhere. Labels are part of
  a family's identity, or MLIR keeps the first creator's labels for every
  equal declaration; still never looked up. Member kinds are a closed sum
  (data, closure, memo); list and numeral are derived shapes, `in_place` a
  `Promise { None, InPlace }` on the data member. Deletes `DataRemap`'s
  names, keys, `describe`, `remake`, `shapeAt`, `leaf` and per-kind
  remaps, `Idr_SumKind`, `Idr_CtorRole`, `KindRule`, `RoleOnce`, `ruleOf`,
  `roleTags`, the role variant's 18 `get_if` sites, `Idr_BaseListOf`,
  `ListType` as a kind source.
- **C81** (L04 §2.6, I2, I10, I11; D58). A type's facts are computed in
  its storage when it is made, with no MLIR storage made: its possible
  constructors, its class, its layout and what it holds. An application's
  class is `Closed` (every index closed, its unfolding within the shape
  budget) or `Unknown`; its layout is `Number` for a numeral, `Cell` for a
  memo member and for a recursive member at `Unknown`, `InPlace`
  otherwise; a call whose layout changes under its indices targets the
  copy D58 makes. `idr.field` is speculatable exactly when the type fixes
  the constructor; `idr.tag` folds on a single possible constructor. Byte
  offsets stay in `Layouts`, built by one walk and cached. Deletes
  `!idr.box`, `layout::fit` (`Fit.cpp`, `Layout.h:224-233`),
  `graph.boxed`, `solveHeld` at sealing, `holdsNoComponent`'s walk,
  `TypeGraph` in verifiers, `Layouts.cpp:41-104`'s graph build, the box
  test (`OpsConReads.cpp:24-28`).
- **C82** (L04 V5, I3, I9, I12; review §2.3). Refinement is scoped: per
  case (C19), and in `idr.assume <lhs = rhs>`, a region for an erased
  equality (`replace`, `rewrite`, an erased `Refl`); a yield of a refined
  type into an enclosing one passes `idr.reindex`, a pure cast checked
  against the enclosing refinements, since MLIR's `areTypesCompatible`
  has no region context (`ControlFlowInterfaces.td:100`). The empty
  default keeps Idris's coverage; an arm Idris proved impossible stays as
  an `unreachable` carrying its justification, an essential branch; a
  dead non-empty default is erased; a region binding a value of an
  uninhabited application is `ub.unreachable` (Idris's `isEmpty`); the
  frontend writes one crash default. Deletes the registry's identity hooks
  for `replace`-shaped definitions and the per-constructor crash arms
  (`Cases.idr:298-306`).
- **C83** (L05 §1 D39, §2.3, I4; under D63) (names per D90). Lending is
  a region op that threads its owner: `idr.lend %o` opens a region whose
  views are tied to the lifetime token it yields (D63) and gives the
  owner back as its first result, placement outlining the smallest run
  of ops that holds every use of the views (its exact form
  `design/lifetimes/`'s); so a view read after its owner is dropped,
  refused today only by the walk D39 deletes, cannot be written. Deletes
  today's pure view op (`IdrOwnershipOps.td:98-107`), `Viewing`, `places`, the write epochs,
  `deadness`, `ownersAcross`, `backEdges`.
- **C84** (L05 §2.6.3, I5, rule 8; review §3, §4.1, §8) (amended by D95:
  its cycle clause is reversed, a lifetime spanning a call on its
  function's cycle as one lifetime per level, packed before the push and
  unpacked at the resume; its tail clause stands, D96). Each lifetime
  carries its D26 proof as a local verifier rule, a "count" proof (its
  cells bounded until its end) or a "spine" proof (each cell reachable
  from its parent); a site with neither stays `cell.new`, since escape
  alone bounds nothing (a loop building a pair per element into an
  enclosing lifetime holds a million dead pairs). This is D26's clause
  for a lifetime's cells. No lifetime region holds a call in tail position
  or a call on its function's cycle, or the call is no jump (D30):
  recursive code allocates into a lifetime only outside the call, a cost
  to measure. Whatever infers how a result relates to an argument's
  lifetime (`design/lifetimes/`, under D63) ends by construction, as
  AGENTS.md requires of a fixpoint. Deletes the byte budgets as the
  only bound (`Stack.cpp:78-80`), which stay a performance policy.
- **C85** (L05 §1 D39, I7) (amended by C208: "exclusive" alone, never
  "linear"). D39's element view reads the borrow scope's
  row: an element read inside a scope whose row has no `write`, or from an
  exclusive or linear array, is a view; otherwise it takes a reference.
  MLIR's effects name values, and distinct values may alias (`readIORef
  r; writeIORef r' y` with `r'` an alias of `r`). Deletes `Classes.cpp:74`'s
  blanket owned element, `isCountedElement` (`Values.cpp:37-40`),
  Borrows' element cases.
- **C86** (L05 §1 D39, §2.6.2, I9) (amended by D88, D90: `static` is a
  hold, never freed, not a lifetime). `static` comes from a constant's type,
  the frontend's literal types and the field-read rule, never from
  purity; a static memo label's function is specialized to put its forced
  value into `static`, a never-freed lifetime. Deletes `madeStatic` and
  `isStatic` (`Verify/Uses.cpp:74-84`) with their nine callers,
  counting's `Phantom`, `Constant` and `StaticRead` classes,
  `persistHeld` and `idris_rt_persist_held`.

*Counting, exclusivity and the in-place promise*
- **C87** (L07 §3, I6; L20 I2). Counting's types carry the quantities:
  placement's live set holds quantity-many values only; `dup` and `drop`
  take quantity-many operands, `idr.dup` a counted view and never a
  quantity-1 one (today `(1, borrow)` can be built and dup'd, two linear
  owners of one cell); a token at quantity many is refused; an argument
  made by `lin.use` is dead at the call with no liveness query. Deletes
  placement's work on linear values and the liveness query for `lin.use`
  arguments.
- **C88** (L07 §2.8, §2.10, §2.11, I10, I11). Run decrements combine only
  drops placed at one point; coalescing may move an increment earlier,
  never a decrement later past an allocation or a call (D26). The
  per-function bound `B(f) = S(f) + max_p (T(p) + W(p))` is kept as a
  running maximum and reported as a pass statistic nothing reads to
  decide, checked by two differential tests (reuse, borrows); its proof
  sketch follows Lorenzen and Leijen, Def. 3 and Thms 4 and 5.
- **C89** (L07 §1.3, I13). `in_place` is admitted only on a family with
  exactly one constructor that has a cell, checked when the registry's
  table is built.
- **C90** (L08 §1.1, §2.1 to §2.3, I-1 to I-3; L05 §1 D24; L19 I3) (names
  per D90). The in-place rule is decided by a check pass, `idr-in-place`, right after
  defunctionalization and idr-knots, before any optimization, on the
  program as the frontend wrote it (D24's own words). Today the refusal
  reads exclusivity after contify, the optimizer, canonicalization, CSE,
  frames and placement, so acceptance moves with the inliner's cap,
  borrow inference and dead-code deletion, and the stack inference runs
  before exclusivity, ignoring the promise (`Pipeline.cpp:38-41`,
  `Stack.cpp:116-269`). It covers rebuild sites (the same family at equal
  layout, inside the taken cell's case region), obligations closed back
  over every parameter that forwards the value (`Linear.List.reverse`),
  and exclusivity, a crash case giving nothing (C91); it refuses once per
  cause at the user's call, naming the cause. Its verdict is grades:
  `!idr.graded<once, counted unique self, T>` on an obligation parameter
  (the family's own cells exclusive, D70; counted memory, so no cell of a
  lexical lifetime can receive it), and each rebuild an `idr.take` at the
  case's entry whose linear token `idr.rebuild %token @C(fields)` consumes
  (a fresh identity, never merged or folded), carried as a jump argument
  or a frame field like any token; later passes keep them or fail the
  verifier, and counting lowers a rebuild to `cell.recycle` and
  `cell.init`. A use counts only if it may still hold the value at the
  rebuild; a borrowed read whose lifetime has ended does not (D79). Acceptance holds under every optimization skip (C132). Deletes
  `Demand.cpp` and `Demand.h`, `IdrDemand`, `createIdrDemand`, the
  name-keyed map, the reporting heuristic (`Demand.cpp:127-135`),
  exclusivity's part in acceptance.
- **C91** (L08 §1.6, I-4). A dead end gives nothing: in exclusivity's
  extractor a block whose terminator has no successor and is neither a
  region-branch terminator nor a breaking jump (D25) contributes no
  predecessor; any other terminator is an internal error naming the op.
  `bump1 (bump1 …)` with a partial `bump1`, refused today, is accepted.
  Deletes `SuccessorSources::unknownFrom`, `ExclusivityGraph.cpp:208-216,
  222`, `ExclusivityAnalyses.cpp:234-243`.
- **C92** (L20 §3, I3) (names per D90). Where QTT proves exclusivity it
  is a local type rule the verifier checks: a value is `unique deep` when
  it is fresh (a constructor, a recycled cell, a call result whose
  signature says exclusive) or taken from a `unique deep` value at a
  linear position, and flows only through linear positions; the marking
  covers only the rest. A result's exclusivity is a fact of the function
  type, derived bottom-up over SCCs as rows are: every returning path
  returns a fresh value or a `unique deep` argument it consumed, a crash path contributing nothing. Deletes
  the marking's nodes for linear chains and the second "gives back" solve
  where it holds.

*Control flow*
- **C93** (L09 §1.3, I3, I4, I9, I10; review §5). D25's carried patch is
  the PR's interfaces with our token as the target's encoding, our variant
  (upstream still argues its encoding, and the pin has none of it);
  `match-and-counting.md` §5.4's second tier (our passes reading jump
  edges, idr-lower lowering nested jumps) is superseded and never built,
  and the patch lands in the cutover before the first pass that reads a
  nested jump. Beside it, five upstream fixes, each its own
  `upstream/<NN>-<name>/llvm.patch` with an `scf` reproducer, a
  `tests/upstream-<name>` check, a PINS.md entry and a review comment on
  PR #166688 as its plan: a resultless match whose cases all jump erased
  as dead; the region inliner changing IR and then failing; the dead- and
  duplicate-input patterns editing inputs another op owns;
  `traverseRegionGraph` reading out of bounds; `scf.index_switch` unable
  to carry exits; and the PR's propagation helpers moved to
  `ControlFlowInterfaces`. The backport is rebased by hand (five hunks
  fail `git apply` at the pin, two even with fuzz). Two of our readers
  adapt in the same change (`Flow.cpp:44-62` reads the owner's inputs;
  `Linearity.cpp:27-33` tests "no region successor owned by this op").
  `idr.jump` declares no effects. The PR's per-op subtree walk is measured
  first; if it is a wall, the target enumerates its exits, upstream.
- **C94** (L09 §2.8, I5). The join ops lower in one conversion with
  upstream's `populateSCFToControlFlowConversionPatterns`, nested jumps
  lowered by upstream through C93's `scf.index_switch` fix, so irreducible
  groups lower with no run-time selector and blocks appear only there.
  Deletes `createSCFToControlFlowPass()` at `Pipeline.cpp:186` and the
  poison yields (`Conversion/Matches.cpp:30-37`).
- **C95** (L09 §2.5, §2.6, I7, I8). Contification follows Fluet and Weeks
  on regions, through return points: one dominator tree over functions,
  continuation nodes and a root, with no budget (a size cap may only
  decline); it runs at today's slot and again after inlining (C45). Join
  points also come from self-tail loops and from case-of-case, which
  copies only the dispatch: the consumer's cases become join regions of
  one flat `idr.join`, one jump per case per yielding region, ending by
  construction. Deletes the single-site rule, its reason and the root
  found by name (`Contify.cpp:10-13, 95-101`), the second-block workaround
  (`:34-42, 119-121`), the per-run `SymbolUserMap` and `CallCycles`
  rebuild, the whole-consumer copy (`CaseOfCase.cpp:141-176`), TRMC's
  `runningRegions` recount.

*Tail calls, frames and the stack*
- **C96** (L10 §1 D31, §2.3, I-5 to I-8; L07 I9; L20 I10). Frames are a
  D48 family indexed by the awaited result, with a third layout, the frame
  stack: linear, uncounted, contiguous, one stack type per awaited result
  over one physical stack (D31). A push is an `idr.con` of a frame, a pop
  an `idr.match` consuming its handle, so a linear value keeps its
  quantity in a frame; the top is a linear value threaded through the
  functions on the cycle, chunks per task, so two interleaved waits on
  one shard cannot pop each other's frames. Every non-tail call of a
  member is framed (D32's CPS of every component). The answer is written
  through the base frame's destination, so runs and resumes return
  nothing. Frames run after counting and TRMC and before the tail loops,
  so reuse tokens ride in frames and D24 holds across a cycle (a tree map
  would otherwise free and reallocate every node). Deletes the answer sum,
  `answerTypeOf`, `asAnswer`, `fromAnswer`, the `ub.unreachable` cases and
  `heldAs` re-entries (`Frames.cpp:244`, `FramesTypes.cpp:91`), the gaps
  at `FramesPlan.cpp:61, 64, 87-99, 108-118, 151-171`, any thread-local
  top.
- **C97** (L10 I-4) (names per D90). No operand of a call in tail
  position has a lifetime that ends with the call (`scoped` to this
  call's lifetime, `idr.activation`, or to a lifetime whose region
  encloses the call, D63), checked locally at the call (`q n
  = sum [n, n]` would read a torn-down frame). Deletes `Frame.{cpp,h}`
  and the cycle test in `Stack.cpp`.
- **C98** (L10 §2.4, I-9; L19 I6; review §4.3). D32's bound is computed on
  the final LLVM module from code generation's per-function stack sizes,
  read in process as `DiagnosticInfoStackSize` (`.stack_sizes` is ELF
  only), plus each frame's local-area offset, the incoming and outgoing
  argument areas and the x86-64 red zone; a build-time check makes any
  non-`musttail` edge inside an SCC of the final module an internal error;
  the bound reaches the runner as one object compiled after the bins
  (`idris_rt_program_stack`). The margin is measured per target and
  checked when built (C5). A `musttail` fixture matrix runs on all four
  targets (patch 30's AArch64 history), and deep test programs run on the
  computed bound, re-derived by a test. Deletes `Runner.cpp:27-44`'s
  sizes, the shared size in `Support/Stack.h`, the bench's raised `ulimit
  -s` (`bench/run.sh:95-96, 201-207`).
- **C99** (L10 §1 D33, I-12; L15 §2.9, I-1). No recursion on input size
  in our C++: about 55 functions recurse today, and a 20,000-branch `else
  if` kills `rewriteTail` and `framesFrom`. The tail fact is read off the
  call, a type's recursive facts are bits computed when it is made, ids
  in pre-order give a topological order, and `depthFirst`
  (`Support/Nest.h`) serves the rest. Upstream's recursions get one patch
  per family (`walk`, the printer, the parser, attributes' parse, print,
  alias walk, walker and replacer, the bytecode writer, clone, drop and
  destruction, region DCE, dead-code initialization, call graph
  construction, slices), after painting the deepest stack. Deletes those
  recursions, compile-time-cpp's deducing-`this` recursion and `depth`
  lambda, the recursion through `std::function` (`IR/ValueFacts.cpp:241`,
  `idris-mlir-tblgen.cpp:261`).

*The runtime*
- **C100** (L11 §1 D35, §2.1, I1, I2, I13). The heap is one span aligned
  to 4 GiB, every chunk reserved at a fixed address from it as snmalloc
  asks; the page map is snmalloc's bounded flat map over the span (a
  1/1024 of it, `PROT_NONE`, committed per page), one carried patch gating
  its fast-path range tests behind `sanity_checks`. snmalloc's commit
  reports failure: a carried patch makes `notify_using` return
  `mprotect`'s result in both PALs (`pal_posix.h:244-253`,
  `pal_apple.h:214-228`), compiled with `pal_enforce_access` only (today a
  refused commit hands out `PROT_NONE` memory and the program dies by
  `SIGSEGV`, unnamed). The runner initializes the heap once, and one
  allocation on its thread before the body moves snmalloc's own failure
  before the program runs. About 324 GiB is reserved today. Deletes
  `heapRegion`, `addRegion` (`Cells.cpp:39, 93-105`), the writable
  `reserve` and `#ifdef MAP_NORESERVE` (`Posix/Memory.cpp:65-85`),
  `ensure_init` and its two flags, `idris_rt_gmp_init` as an ABI entry.
- **C101** (L11 §2.2, §2.4, I3, I6, I10; L19 §2.1, I2). One generated
  ending: `Spec.Endings` (`Cause`, `Site`, `Ending` with `Exited : Fin
  256`, `Crashed : Site -> Cause`, `OutOfMemory` with no site; `status`
  total; an `exit` status outside 0 to 255 a crash at its site, D64) and
  one `end`, read by the runtime, the harness and the tests
  (`expected-ending` and `expected-stderr`, so an exit beside a crash
  cannot be written). Every ending but an internal error closes the handle
  table and writes the program's files (a crash today loses file output
  D21 ordered before it). `getString` of a non-string handle becomes a
  guard at the call; a size check found before an allocation becomes the
  out-of-memory ending. The program's static facts reach a noreturn
  `idris_rt_start` as one record (body, CPU features, stack bytes, name),
  the name the executable's as the driver builds it, never `argv[0]`
  (today every program prints `idris-mlir:`). Deletes `IDRIS_RT_CRASHED`,
  `rt::start::Ending`, `checkStatus`, `idris_rt_crash`,
  `idris_rt_crash_str`, `idris_rt_main_return`, `idris_rt_io_exit` (now
  `idris_rt_exit(uint8_t)`), `RootKind::Status`, the hard prefix
  (`Posix/Files.cpp:103-109`), the ten texts, `outOfMemory`, `tooLarge`,
  the harness's three protocols.
- **C102** (L13 §1, I3; L11 §2.5, I4). A crash site is an inherent
  property, `#idr.site<file, line, column>`, of `idr.crash` and of each
  guard, written by the frontend and never read from a `Location`
  (`MergeIdenticalRegions` ignores locations, so two `idris_crash "bad"`
  arms at lines 3 and 4 merge and print line 3). Within D38 the cause is a
  value of the specification's enum, passed as an immediate with its
  message table generated into the runtime, where D38 wrote a shared
  global per cause (a kind spelt as text); the per-file text and the line
  and column immediates stay. Deletes `crashMessage`'s location search
  (`Runtime.cpp:41-50`), the per-program cause strings, the cause
  `StrAttr` (`IdrCheckOps.td:22-26`, `IdrBase.td:304-308`).
- **C103** (L11 §1 D36, I9). The limit kept to is the smallest `memory.max`
  on the path from the program's cgroup to the mount root (cgroup v1:
  `hierarchical_memory_limit`), less the working set at start, held in a
  limit range after `StatsRange` in snmalloc's pipe; today a leaf with no
  `max` under a limited ancestor reads no limit. Where the cgroup may swap,
  its swap allowance is added (D65).
- **C104** (L11 I12). 0017's D9 comes free: D31's frame-stack chunks come
  from the runtime's allocator and the native stack is small, so its
  1 GiB budget, its 64 GiB text and P1 go, 0017 amended in the same
  change.

*Arrays*
- **C105** (L12 §1.3, I1) (names per D90). A field's buffer is writable
  only when its cell is exclusive: its root is the frontend's `to_tensor
  restrict`, marked writable only when the scrutinee is `unique deep`,
  and `lin.use` and
  `lin.enter` stop being roots, since quantity 1 is a fact of the binder,
  not of who owns the cell. Fixes §8's suspected miscompile. Deletes
  `UseModel`, `EnterModel`'s release, the argument at `Data.cpp:14-16`.
- **C106** (L12 §1.5, §3.1, I2, I3). `merge e x` keeps its extents
  (`tensor.collapse_shape`, then `tensor.expand_shape` to the frame's and
  `e`'s; `nest` stays the identity), so an empty frame's shape is `[<0,
  k]`. A linear `read` or `shape` is one linear use of a value graded
  `once` (D43: no `lin.use` or `lin.enter` exists, the grade carries
  linearity on the tensor itself), so Emit never demotes it
  (`Terms.idr:1570-1589`). Deletes `merge`'s identity entry
  (`Recognized.idr:147`) and those sites' reliance on Emit's demotion.
- **C107** (L12 §1.6, §3.4, I4, I6, I7; L07 I8; D60). The generating ops
  stand until the lowering: counting runs on their buffer forms through
  their flow and effects, and `lowerToLoopsUsingSCFForOp`, which takes
  ops without results, runs per function right before `idr-lower`. A
  tabulation of cells whose extents only a cell knows computes the
  zero-index cell once, sizes the destination from the frame and its
  extents and yields it at index 0. A generating op over counted elements
  writes a fresh destination (`tensor.empty`, verified), places elements
  and never decrements, its allocation not zero-filled; an element update
  reuses its cell at the `idr` level. Iterator types answer `parallel`
  only where the region only computes, else `reduction`; tiling methods
  stay at their failing default. Deletes `Nests.cpp:94-153`, the NULL fill
  and the decrement at stores for wholly placed arrays (`Arrays.cpp:91-112`,
  `Elements.cpp:52-62`, `Memrefs.cpp:97-109`), the element take's test
  and free-then-allocate (`Elements.cpp:64-82`, `Arrays.cpp:253, 263`),
  `Idr_Iteration`, `getIterations`, `Linalg.cpp:139-141, 200`.
- **C108** (L12 §1.6, I5). D43's two patches: 27
  (`upstream/27-one-shot-tensor-like-copy/`) becomes a carried
  `llvm.patch`, its claimed test, which does not exist, written in that
  change; a new 64 (`upstream/64-tensor-like-per-instance/`) holds
  per-instance `isTensorLike` and `isBufferLike` through `extraClassOf`,
  and drops `SameOperandsAndResultShape` and
  `SameOperandsAndResultElementType` from `to_tensor` and `to_buffer`,
  without which every bridge of a graded tensor fails to verify. Both
  type converters keep the grade, and every buffer-type path goes through
  ours.
- **C109** (L12 §1.2, I11). IO arrays' memory space `#idr.world` is
  renamed `#idr.mutable` (memory written while shared), with one
  coordinate type, `index`; the merged `idr.array.update`'s region is
  verified to touch no `contents`, read from the one effect query, the
  guarantee the world gave. Deletes the name, the casts at
  `Bufferize.cpp:236-239`, the `I64` operands, `ElementUpdateOp`.

*Ops and primitives*
- **C110** (L13 I1; L15 §2, I-4). D41's template can neither branch nor
  build poison: a `Domain` concept whose `Truth` no `bool` is
  constructible from (`mlir::Value` converts to `bool`, so a branch would
  lower `idr.divs -7, 2` to -3), `divide`, `shift` and `toChar` written
  over `select`; partial operations take evidence only the domain makes
  (`SafeDivisor<D>`, `BelowWidth<D>`), so no instance builds `arith.divsi`
  at MIN / -1 or a shift by the width. Domains: a `constexpr` fixed-width
  word (no `APInt`) in a freestanding header (*corrected*, recheck 3: it
  lives in `foreign/idr/include/idr/IR/Numeric/`, which the runtime
  includes, one template shared by both), intervals
  over upstream's `intrange`, the `arith` expansion; the 8-bit law is
  checked exhaustively per row; the runtime's small path reads a `wraps`
  fact. Deletes `IR/Ops.cpp:205-294`, `Conversion/Scalars.cpp:57-190`,
  `runtime/Big/Arithmetic.cpp:20-33`, `IR/OpsScalars.cpp:20-33`.
- **C111** (L13 I2, I8). A guard's condition is a D41 function
  (`Nonzero`, `InBounds`, `InRange`), and ranges decide guards: one that
  holds folds away, one that fails becomes `idr.crash` with its cause and
  site. The ranges domain seeds a `Fin n` operand with [0, n-1], so a
  bounds check on a `Fin n` index is never built. Deletes the conditions
  written three times (`OpsChecks.cpp:22-61, 130-168`,
  `Conversion/Checks.cpp:43-97`).
- **C112** (L13 §1.8, I7). `closure`, `suspend` and `delay` are one
  capture family, all `Idr_LinearWhenACaptureIs`: today `delay` lacks it,
  so `idr.delay %x : !idr.lin<..> -> !idr.lazy<..>` verifies and drops a
  quantity. Deletes the separate `delay` definition.
- **C113** (L13 §1.3, §1.5, §2.1, §2.2) (amended by C204: integer,
  char and double keys stay on `idr.lit.match`) (amended by D98: no
  canonicalization runs on our ops, so the region-end sum's reader named
  here goes; its reader under D98 is not ruled). The op surface: defs
  printed flat
  from the specification, one per op, a family's constants enum members
  (`static constexpr bool quotient`, `isSigned`, `left` go); each op's
  meaning one sum, `Runtime Symbol | Inline InlineFn | HandFolder |
  NoFold`, pure runtime ops folding through one `foldByRuntime` read off
  the generated ABI row, which no IO or buffer op can take; `ToIntOp::fold`
  is a 38th hand folder; folds declare what they meet per op instead of
  cloning per query; `match_lit`'s integer and `i1` keys go to
  `scf.index_switch` and `scf.if`; canonicalization's region ends a closed
  sum `Yields | Stops | Jumps`; `big.pred` is `nat.pred`;
  `io.unsafe_run` a region op (D20); `os` is `target.os`, folded from the
  target's entry; `buffer.*` are memory ops, not IO. 189 ops become 166
  by L13's count (14 deleted, 14 merged, four new), before the ops other
  entries add (C39, C65, C82, C83, C90).

*Analyses and the C++*
- **C114** (L14 §1.2, I1, I5). Two carried upstream patches: an
  `OpToOpPassAdaptor` returns the intersection of its nested passes'
  preserved sets, as LLVM's does (`PassManager.cpp:137-169`), so a group
  of `idr.func` passes no longer drops the program graph
  (`Pass.cpp:618-619, 1172-1186`); `scc_iterator` reads node numbers as
  `po_iterator` does (`SCCIterator.h:73-75`). Deletes the graph's rebuild
  after every group, `Scc.cpp`'s `Vertex` copy and root vertex,
  `stronglyConnected`'s map.
- **C115** (L14 §1.2, I3). Transform units are MLIR actions; solve units
  are trace zones, never skippable: a debug counter can skip an action
  (`Actions.h:4-9, 51-62`), a skipped exclusivity unit leaves its SCC
  "exclusive", a miscompile, and a skipped refusal unit acts as a budget
  of zero.
- **C116** (L14 §2.5, I8). A decide step makes every type and attribute
  its answer needs, serially in id order; each apply group is paired with
  its decide step in the pipeline's record and reads the decision through
  a const view, a missing decision an internal error. Deletes context
  writes on workers in every apply step (98c6315c's class).
- **C117** (L14 I9). BindingTimes is sized by the program: one monovariant
  solve per root over (member, parameter) with a flat lattice, adopted
  only if its remarks equal today's on the corpus (today (P+1)^arity
  states per member, `BindingTimes.cpp:83-116`). Deletes the tuple map and
  the per-visit walks.
- **C118** (L14 §2.7). A fact decidable from Idris's checked TT is
  computed in Idris (on 0015's core where it is a fixpoint) and crosses
  Emit as a type or a property; a fact about the IR after Emit is C++; no
  fact is computed on both sides.
- **C119** (L15 §3, I-7) (amended by C195: the `Exclusive` handle
  goes; a value's exclusivity is its grade). Quantity handles in C++: `Exclusive`, made only
  by `asExclusive`, and a move-only `Token` (copy deleted, `consume() &&`
  leaving counting's walk by a recycle, a join argument or a drop;
  `rejoin` taking both sides by value), in `include/idr/IR/Quantities.h`,
  so the walk cannot recycle one cell twice; the verifier after every pass
  stays the complete check, since MLIR's machinery builds ops without our
  builders. Deletes the `isExclusive`-then-build validators
  (`Grades.h:91`).
- **C120** (L15 §2, I-10, I-12). Every choice of ours is a sum, never a
  `bool`: `StageFacts` (16 representable states, 5 valid),
  `role::Label::byName`, `Component::counted`, `factsOf(…, bool shared)`,
  `placeOwned(…, bool keep)`, `give(…, bool self)`, `foldCheck(…, bool
  holds)`, `byNameIs`, `performs`, `provedIs`, `forEachNamed`'s `inPlace`;
  stored callbacks (`DataRemap::Leaf`, `Scheduler::RunPipeline`) become
  template parameters; `Loop.cpp:48`'s flag, the program's own boolean,
  stays. `StagedPass` becomes CRTP through a small carried patch
  documenting `DerivedT` in `PassBase.td`'s `baseClass`, deleting the last
  virtual of ours (`Pipeline.h:44`).
- **C121** (L15 §1.1, I-6; L03 §1.3, I-10). `compile-time-cpp.md` is
  re-based: its T0 is the specification (D16, D51), not hand TableGen and
  a rebuilt `idris-mlir-tblgen`; `static_assert` only on facts whose
  subject is C++ (C76); no feature unless the pin and the typecheck host
  both have it (C9); sealing restated on D48, and the grade's laws on
  D88's axes (uses × hold, hold = `static` | `Release` × `Unique`) as the
  laws the grade algebra proves in the specification, reaching the C++
  as its tables (C76). Synthesis D §2.6 is amended the same way. Deletes CTC §2.2's
  generator model, `matchPin`, the re-proofs.

*The frontend and the fork*
- **C122** (L16 §1.2, I3; L17 §1.2, I4; D59). Erasure is decided once,
  from one source: each position's quantity from the binders of the
  definition's one normal form, aligned to its case-tree arguments. L16
  drafted the fork's `eraseArgs` for the prefix; it is frozen at
  declaration (`TTImp/ProcessType.idr:178-186`), so no reader of ours
  reads it, and the fork reruns it per module if the reproducer confirms
  the bug. A position is `Absent | Index Sort | Runtime Quantity
  ClosedTerm`, a quantity-many binder in an index position also an index
  binder (D59); the prefix is per definition, the rest per instance where
  a type is computed (`printf`'s shape). Deletes the five readers
  (`Closed.idr:291`, `Forced.idr:153`, `Growth/Sites.idr:481`,
  `Terms.idr:75`, `Types.idr:170`), the past-the-type default, 40 `use`
  sites.
- **C123** (L16 I2, I10). A static argument has one representation, a
  `Template Admitted 0` whose leaves keep their closed content; its key,
  print, height, arity and heaviest token are functions of it. Where only
  proofs read the evidence, a decision is `Decided p = Yes (0 _ : p) | No
  (0 _ : Not p)`. Deletes `render` as a traversal, `TS.readings`,
  `closedHeight` on requests, the second dictionary take-apart, the unary
  `LTE` built per request and thrown away (`Proof/Requests.idr:692-709`,
  `Proof/Growth.idr:42-56`).
  *Sharpened* (2026-10-23, recheck 5): the one representation as built
  is `StaticReading` (`Translate/State.idr`), which holds the reading at
  quantity 0 with its form, height and head tied to it by type; that,
  not a `Template Admitted 0`, is C123's form.
- **C124** (L16 §1.1 D13, I6). A `let` around a `Delay` keeps the
  language: the fork keeps "this `Delay` was inserted for a `Lazy`
  expected type", and only an inserted `Delay` moves a `let`; `f (let x =
  loop 0 in Delay 3)` loops under eager evaluation (D13), where today it
  prints 0 (`Translate/Closed.idr:184-197`). Deletes `delayedLets`'
  blanket move.
- **C125** (L17 §2.4, I2). One POSIX path model in the fork: a path is an
  optional root and names split at `/`; `:`, `?` and `\` are ordinary
  characters; no volume, no `isWindows`, no `System.Info` (AGENTS.md's
  four targets; D10). Recorded as `upstream/fork-posix-paths/` with its
  PINS.md entry and test. Deletes the `isWindows` branches, `Volume`,
  `pathLookup`, `dirSeparator`, `pathSeparator`.
- **C126** (L17 I3; review §9.4; D55's owed design). The desugarer builds
  one node, `ITypeOrValue : FC -> Overlaid -> RawImp` (`Overlaid = PairOf
  l r | UnitOf | DPairOf n r`), in place of the three tuple alternatives
  (`Desugar.idr:529-560`); elaboration classifies the expected type's head
  as `Universe | Other | Unknown`, and under `Unknown` elaborates the
  components once and postpones the site, retrying with no new
  elaboration, as D54 postpones; at the last chance upstream's rule
  applies, its default the value (`UniqueDefault (MkPair a b)`, D12).
  Linear in the tuple. Checked by comparing each definition's checked
  term with stock Idris's at `%ambiguity_depth 1000` over prelude, base,
  `libs/`, the fork, the frontend and `tests/`. Deletes
  `elaborator-counts.md` §1.7's list and the three tuple alternatives.
  *Amended* (2026-10-23, recheck 5): the comparison with stock Idris's
  checked terms is withdrawn. There is no oracle (AGENTS.md), and the
  checker tracks no upstream (D118): the tuple forms' meaning is
  upstream's language, stated by tests whose expected files are the
  specification (each of `(a, b)`, `()` and `(x ** p)` as a type, as a
  value and under an unknown expected type, with upstream's default),
  and linearity in the tuple is a measurement.
- **C127** (L17 I5, I8; review §9.3; within D54). A growth's case in
  `retryGuess` postpones in every mode but `LastChance`, where it throws
  its own refusal: the handler D54 cites postpones even at the last chance
  (`Core/Unify.idr:1449-1462`), so copied as cited a growth would never be
  refused. The last chance is the end of the declaration's elaboration,
  and the refusal names the two goals and the hints between them. A
  search's result is one sum, `Found | Repeated | Grown`; the size-limited
  quote returns `Quoted | TooDeep`. Deletes `InternalError "Cycle in
  search"` (`AutoSearch.idr:516`), which the driver reads as a compiler
  bug.
- **C128** (L17 §2.1, §2.3, I7). Every count of the fork is classified:
  those deciding acceptance are gone (D53, D55); those changing only a
  stored term's form stay, named, with typed signals
  (`%nf_metavar_threshold` 25, the quote depths, the "simple" test's 6 and
  3). Dead counts, state and options go: `delayDepth` and `deeper`, the
  never-started timer checked at every unfolding (`Eval.idr:302`),
  `%search_timeout` and `%foreign_impl` (refused by the parser),
  `--debug-elab-check`, `processTTImpFile` with its `%search` 1000; reify
  drops a script's search depth.
- **C129** (L17 §1.2, I9, I10). A case block's parent is typed:
  `CaseBlock : Name -> Nat -> Name`, the parent's name and the block's
  ordinal from a per-parent counter, where today's `Int` is the
  session-wide machine-name counter (`Core/UnifyState.idr:193-209`);
  base's reflected form stays upstream's. `tests/upstream-patches` applies
  every carried Idris `pull-request.diff` to a copy of the pin with `git
  apply --check`. Deletes `outermost`, `rootOf`'s textual climb,
  `keyOrigin`'s search.

*Tests and the execution*
- **C130** (L19 §2.2, §3.3, I1, I4). Properties are stage-scoped:
  `--idr-expect-at=<stage>:<props>` checks after every pass of a stage, in
  process, and D24's, D26's, D30's and D31's and D32's properties are on
  for every compilation the suite makes, so no test names a pass. Quantity
  checks key a binder by a typed location (`#idr.binder<def, index>`),
  never a printed key. Deletes `harness/lib/mlir.sh:5-116`
  (`checked_steps`, `step_dumps`, `step_of`, `step_module`), the 27
  per-test promise lines, every `after:<pass>` step, `Quantities.cpp`'s
  `keyOf` and its colliding-key drop.
- **C131** (L19 §2.1, §2.4, I2). The invariant set is typed behaviour, not
  a step gate: `Case { stdin; stdout; ending : Spec.Ending; stderr; libm
  }` and `Reject { rule : Spec.Rule; line; message }`; it changes only in
  the change of a ruling that changes what a run shows, the ruling named
  (D13, D37, D38 change it), and `tests/endings` alone pins the status
  table. Deletes the expected-exit and expected-crash pair and the three
  protocol copies (`run.sh:26-39`, `e2e.sh:108, 161-178`,
  `differential.sh:155-170`).
- **C132** (L19 §1.2, I3). Acceptance is invariant under every
  optimization skip: the compiler writes `--emitted=<path>` whatever the
  verdict, and every reject and every invariant-set program keeps its
  verdict under a drawn skip set, its seed printed; D24's rebuild and
  D34's destination are lowering-role obligations, never skippable
  actions. `uniqueness-shared-rebuild` passes before and after D24 today,
  so it does not discriminate the rule; this does. Deletes
  `actions.sh:22-27`'s hand tags and `tests/actions-skip-programs`.
- **C133** (L19 §1.15, §2.5, I7). Scale fixtures are Idris generators
  over the specification's builders, each asserting a scaling relation
  (work and footprint at 2N within 2.2 times those at N, the factor
  *conjecture*, to calibrate): eight fixtures, a `threads` one among
  them. Deletes `tests/defunc-tag-limit`'s awk generator and pass flag.
- **C134** (L19 §1.1, §2.1, I8). The test runner builds under both hosts
  and imports the specification's closed sets (stages, endings, rules,
  crash causes, primitives): today it depends on `contrib` and `test`
  (`harness.ipkg:7`, `Test.Golden`, `Language.JSON`) and shells out
  through `system`, against AGENTS.md's two-host rule. Deletes
  `harness/Prims.idr:3-10` and its guard comments, `lit.sh:100-101`'s
  spelled statuses, `profile.sh:63-67`'s directory-prefix rule.
- **C135** (L19 I10, I11, I13). `%differential` compares the whole ending,
  its BEFORE lowered with every optimization skipped; semantics cases also
  run on stdin values, so D41's `arith` expansion is tested and not only
  its folder, with a unit box for the interval instance; a
  linear-program generator checks D24 against each program's
  de-linearized twin and the harness's own statement of exclusivity.
  Deletes `differential.sh:15-48, 58, 166`, `Sem.maxCases` and its
  self-check.
- **C136** (review §9.1; L16 §2.9, I9) (amended by D69, D107: O6 and O7
  come in, O7 with only the union-find of 0015's R4). D44's absorbed work
  has its place
  in §7 under D56: each absorbed stage is written by an owned lane against
  §5's contracts and built with the rest at the end, keeping its bars as
  its proposal states them, ratios measured natively once `make self`
  holds. 0011's O2 is the Emit of the new dialect, written once over the
  Core table. R1's bar (bumbledb's Rust engine) and R2's (Soufflé) depend
  on engines outside the toolchain, and O3 needs only R2's semi-naive
  fixpoint. Whether 0011's O6 and O7 come in is §4's queue.
- **C137** (L03 §1.7, Q3 option A). D51's one backend also prints, from
  the same upstream records, the C++ table of the admitted upstream ops,
  so stage legality and `BigToWord` read an op's class from its def and
  the specification never restates a class name. Deletes the admitted
  set's hand C++ side, which no generator wrote.

- **C138** (2026-10-21; L19 Q1). D26 is discriminated at run time by a
  typed record from the checked runtime (the runtime tests link, never
  shipped programs): its peak of held-but-dead bytes per active call
  against the bound the compiler computed for each function, compared by
  the harness as data, never parsed text. Static checks state the bound;
  this record shows a program keeps it.

- **C139** (2026-10-21; L09, L10; reads D30's "decided once" as one
  decider). Whether a call is in tail position has one definition, used
  by the frontend and by every pass that moves a call (contification,
  inlining, the specializer), which rewrites the call's tail fact through
  it; the fact is verified after every pass. A call contification moves
  out of a tail position grows no stack its source did not (Clinger's
  property is the bound), so D30's promise is unchanged. A jump to a
  join point is a tail transfer by construction.

- **C140** (2026-10-21; `design/lifetimes/constraints.md`, under D63)
  (names per D90) (amended by D93: the type carries its kind,
  `!idr.lifetime<view | room | cursor | home k>`, one opener per source
  fixes it, and the pure cast `idr.lifetime.forget` is the one op whose
  result is a lifetime). D63's form: one parameterless type `!idr.lifetime`,
  whose values come from an `idr.lifetime` region's entry, an `idr.lend`
  region's entry, `idr.activation` (this activation) and function
  parameters, and are never a result, a yield, a store or a join
  parameter; a lifetime value has the type `!idr.lifetime`, a value that
  lives in a lifetime is graded `scoped`, and its producer or binder
  names the lifetime operand, so a lifetime is found in one step and no
  check follows a def-use chain; outlives is dominance, checked by the
  verifier's walk with a stack of open binders; a function's property
  says which lifetime each value parameter and result lives in, with
  declared bounds between lifetime parameters. This call's lifetime
  leaves the grade for `idr.activation`'s value; `static` stays. `idr.lifetime` is not an `AutomaticAllocationScope` (a slot
  inside one would lower to a dynamic alloca and break D32). The
  builtin `token` stays the join point's (D76), local to a function; a
  lifetime crosses calls, so it is our own type.
- **C141** (2026-10-21; constraints.md). Upstream LLVM bug: dead-argument
  elimination's exemption for `tailcc` tests a condition that is always
  true (`DeadArgumentElimination.cpp:640-641`), so with every internal
  function `tailcc` (D30) LLVM removes no dead argument. Carried as an
  upstream patch with its report and test (D25, AGENTS.md). Erased
  lifetimes never reach LLVM in any case: D63 erases them at our
  lowering, by design, not as a workaround.

  Fixed upstream on main by 3d88cd257637 (#233919), which the cutover's
  fast-forward to main 416f328b reaches, so no patch is carried (L06,
  2026-10-21).
- **C142** (2026-10-21; the integration's cross-proposal amendments;
  the owner asked the coordinator's preference). P0 amends 0018 (numeral
  families' number layouts, its D1; C22), 0017 (its 1 GiB budget, 64 GiB
  text and P1; C104) and 0011 (its rule skipping a stage under 5%, against
  D44 and D69's "whole") in the same change that makes each stale, as
  AGENTS.md's hard cutover requires: a record changes with what it
  describes.

- **C143** (2026-10-21; D90's gap, found folding §5.3). A value of a type that holds no reference and may be used many times is the bare type (`i64`, `f64`, `i1`), the form upstream's ops take; `!idr.graded<many, T>` with no hold cannot be built (for such a type the grade's builder takes `once` alone), so the one fact has one spelling and no upstream op needs a conversion. Reason: one fact, one representation (AGENTS.md), and upstream first. Open to the owner's review.
- **C144** (2026-10-21; C21's undecided hold; L05 at
  `audits/p0/verify/L05-lifetimes.md:294`). No hold is ever undecided:
  before counting, a value that holds references is `counted` with no
  sharing claim, or `static` for a constant (C86), and the passes that
  learn more strengthen it on D88's axes (the lifetime decide step to
  `scoped`, exclusivity to `unique self` or `unique deep`), each a
  verified refinement. So the grade has no undecided case and no meaning
  that depends on the stage. Reason: L05's "plain counted" before
  counting, in D90's names; a grade sound from birth, as D93's lifetimes
  are born decided. Open to the owner's review.
- **C145** (2026-10-21; D93; `design/lifetimes/lowering.md` §4.2). The
  lifetimes of `idr.lend` and `idr.activation` are `view`: a temporary
  that dies with a loan goes into an `idr.lifetime` nested in the lend's
  region, so a loan has one meaning, and the activation takes slots
  only. Reason: one op per semantics.
- **C146** (2026-10-21; D93; lowering.md §4.4). A caller holding a
  `cursor` that calls a `room` copy writes `idr.lifetime.reserve %l, n`
  (one check of n bytes and a bump, `Allocate` on `heap` when it takes a
  chunk), its own op, never an implicit conversion at the call. Reason:
  a conversion at a call would hide an effect.
- **C147** (2026-10-21; D93; lowering.md §4.6). `.stack` and `.chain`
  give one kind, `cursor`, and the difference stays in the opener. The
  discipline check (K5) treats a cursor parameter as possibly
  stack-sourced: inside a `.stack` region a put targets only that
  region's lifetime or one opened inside it, else the region is
  `.chain`. Conservative where a parameter is always chain-sourced,
  counted by static-handles M3. Reason: splitting the kind would make an
  identical copy per source.
- **C148** (2026-10-21; D93; lowering.md §4.1). `home k`'s k is a dense
  number the decide step mints per home site, never a symbol, since
  symbol walks do not see types; the lowering sizes the thread-local
  array by one walk of the `.home` openers.
- **C149** (2026-10-21; `design/egraph-full/machine-prototype.md`; under
  D61 and AGENTS.md's "what the compiler knows of effects reaches LLVM").
  Upstream's FuncToLLVM drops every argument attribute of an argument
  that expands into several (a memref's descriptor), leaving its own
  `TODO` (read at the pin,
  `mlir/lib/Conversion/FuncToLLVM/FuncToLLVM.cpp:408-420`), so a
  quantity-1 buffer's `noalias` and D61's argument-memory fact never
  reach LLVM (measured on Homebrew's LLVM 22.1.8). Fixed upstream's way,
  by a carried patch implementing that `TODO` (each pointer attribute
  attached to the descriptor's allocated and aligned pointers), with its
  report, reproducer, `tests/upstream-` check, `PINS.md` entry and plan to
  upstream it. Reason: AGENTS.md carries a change we need as a patch, and
  the gap is upstream's own stated one.
- **C150** (2026-10-21; `design/egraph-full/effects.md` §1.3; restores
  D103's premise). A linear array's read gives back a new array value, as
  Idris's type says (`read : (1 _ : LArray s a) -> Index s -> Res a
  (const (LArray s a))`, `libs/mlir-array/Array/Core.idr:211`): the
  frontend today returns the same value it read from
  (`compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr:1570-1578`,
  read), so only the order of ops in the block put the read before the
  in-place write that consumes the array, an order the e-graph could
  break (217 such reads in the inlined benchmarks, measured), after which
  the read would see the overwritten element (D71). With the array
  threaded, the order is data dependence, as a total op stays below its
  guard (D21), and the engine again cannot break it. Reason: no pass may
  drop what Idris proved (AGENTS.md), and the frontend dropped linearity.
- **C151** (2026-10-21; `effects.md` §2; under D103). Measured on the
  frontend's inlined IR: 7.1% of 5.25M ops are fixed, 92.6% of them both
  writing memory and crashing (IORef calls in partial code); the partial
  order frees 21 of 224,572 ordered pairs over a single line (210 with
  C152), 13 of 7,193 in the benchmarks, since 98% of regions hold at most
  one fixed op and a call carries its callee's whole row; no real case
  needs a cost-chosen order on one resource. D103 stands and costs
  little. Its reason against effects inside reads more exactly: an
  effectful rule that keeps both forms makes extraction NP-complete; one
  that replaces the node it rewrites keeps it polynomial, which is what
  D103's one-way skeleton rules do. Merging a repeated read across a
  crash check, which upstream CSE does through the resource tree, is a
  skeleton rule of the e-graph pass where our ops are (D98); upstream
  LICM hoists only pure ops, so lifting a read out of a loop, should a
  measurement ask for it, is a carried patch to upstream's LICM (D99),
  never a pass of ours.
- **C152** (2026-10-21; `effects.md` §1.2). Before counting, `array.get`
  is a borrowing read with `Read` on contents only; counting places the
  element's dup. Today it declares a `Write` on count
  (`foreign/idr/include/idr/IR/IdrArrayOps.td:309-311`;
  `effect-vocabulary.md:297`), a counting decision carried early that
  pins every read: two reads conflict, an unused read stays, a repeated
  read cannot be the first's value. `field` already declares no count
  write for the same reason (`effect-vocabulary.md:281`).
- **C153** (2026-10-21; D107's open form; `design/egraph-full/mlir-form.md`;
  for the owner's review in the plan's approval). The optimizer's
  e-graph is a C++ pass with its own typed tables over MLIR's ops,
  `egraph.md` §4's Tier 1 narrowed to D106, in the solver layer as our
  own solver: rules applied at insertion, no rebuild until a measurement
  asks, the choice per arm a skeleton rule, folds called with constant
  operands only (an MLIR fold may rewrite its own op,
  `mlir/lib/IR/Operation.cpp:862-878`, read), D41's templates as its
  analyses, and `mlir-form.md` §3.4's typed ids, phases and ownership as
  its review list (46 of 77 real engine bugs read in egg, egglog and
  Cranelift fall in classes they make unwritable, `machine.md` §2.1).
  Rejected: the research `eqsat` dialect, whose authors limit it to pure
  straight-line code, whose e-matching lowering exists only in Python
  (xDSL), whose C++ keeps per-node state in pointer-keyed maps, repairs
  its classes by an unbounded greedy rewrite (D98) and leaves stale and
  non-canonical classes writable. Reason: AGENTS.md (no greedy driver,
  no pointer-keyed per-node state, typed choices) and the evidence agree;
  upstream first does not reach research code that is not upstream.
  *Amended* by D123 (L14x, 2026-10-22): rules run in rounds, a rebuild
  restoring congruence after each, in place of rules at insertion with no
  rebuild; each class records the outermost region a member is
  computable in, so no union puts a block argument where a use cannot
  see it, and extraction writes back only a member computable at each
  use.
- **C154** (2026-10-21; `machine.md`, measured on the stock host). A
  library body run by the stock host decides with evidence at quantity 0
  (a decision type whose proof is erased), never a proof built at run
  time: a body that builds a `Dec` pays its proof in steps on Chez (one
  run 0.37 s against 24.9 s). Evidence over `Bool` (AGENTS.md) holds, at
  no cost on either host.
- **C155** (2026-10-21; `design/egraph-full/synthesis.md`; under D106,
  D109). No rule synthesizer is kept in the tree in P0. Of the rules
  Ruler and Enumo found from our ops' meaning (checked against the
  folders on 808,192 cases), the dozen one-way families triggered by a
  constant (Euclidean `div` and `mod` by a power of two to a shift or a
  mask, a shift by a negative constant to the other shift, the
  scalar-value test under a mask below 2^11) enter as cases of D41's one
  template (its folder, ranges and expansion), checked as that template
  is. Sampling alone admits nothing: at 64 bits it accepted 508 rules of
  which z3 refutes 60. How rules beyond these would be proved (SMT
  generated from the template, or exhaustive at small widths) waits for
  a rule that needs it.
- **C156** (2026-10-21; D108's open number). The e-graph's B (nodes per
  op) is a constant of the dialect's specification, measured on the
  stage-1 module before it is fixed, as every budget is (C15); a spent B
  leaves code less optimized.
- **C157** (2026-10-21; D98's reach over C39, C65, C113). The rewrites
  those decisions placed in canonicalization become rules of the e-graph
  pass (a one-way skeleton rule where an effectful op is rewritten, a
  rule over pure values otherwise), or a fold where they rewrite one op
  from its operands alone; none survives as a pattern on the greedy
  driver.
- **C158** (2026-10-21; settles C11 against D90; for the owner's review).
  Op names: every op takes the prefix of the family it acts on (C11), the
  type or resource its operands are, except names a ruling fixes
  (`idr.func`, `idr.call`, `idr.lifetime`, `idr.activation`, `idr.lend`)
  and the ops that shape the IR and act on no type or resource
  (`idr.program`, `idr.return`, `idr.yield`, `idr.join`, `idr.loop`,
  `idr.jump`, `idr.constant`, and `idr.refusal`, which sits in the module
  and acts on no type, by C218), which stay bare as upstream's `func` and
  `scf` structure ops do. The table is
  `audits/p0/verify/parts/contracts/mnemonics.md` (`data.con`,
  `data.match`, `lit.match`, `fn.closure`, `lazy.force`, `count.dup`,
  `int.div_s`, `nat.pred`, `array.tabulate` and kin). Reason: C11's rule,
  D28's "named for what a thing is", and the names the owner fixed in D90.
- **C159** (2026-10-21; D61's reach, L02's question). D61's write part
  exists on a parameter that is `counted unique self` as well as `unique
  deep`: an in-place rebuild writes only the family's own cells, which
  `unique self` makes the parameter's alone (D70), so the write is to
  memory only that parameter reaches. Reason: D70's "every rebuild that
  can be kept is accepted", and D61's in-place rebuilding made movable,
  mergeable and deletable where the caller owns the memory.
- **C160** (2026-10-21; L05's question on D93's wording). A lifetime
  value comes from a region's entry (an opener's binder, a lend's), a
  parameter, `idr.activation` (this call's own, as C140 lists it), or one
  of two derived results: `idr.lifetime.forget` (the view of its operand)
  and `idr.lifetime.reserve` (a room carved from a cursor, C146). Each
  derived result is defined inside its operand's region, so none can
  outlive what it came from. D93's "the one op whose result is a
  lifetime" reads as "the one op whose result is its operand's view".
- **C161** (2026-10-21; L05's finding on D88). `count.dup` and
  `count.drop` take a `counted` operand only, by a generated constraint:
  a `scoped` value is a view of counted memory or a cell of an arena,
  which D88's hold does not tell apart, and neither may be duplicated or
  dropped. A lent value that must outlive its loan is duplicated from its
  counted original, which dominates the lend, so nothing is lost. Reason:
  the illegal state is unwritable, and D88 needs no fourth case.
- **C162** (2026-10-21; amends C21's "attribute"). The grade is a value
  class held as `!idr.graded`'s parameters, with no attribute of its own
  beside the type, so it lives in one place (D90's printed form). Reason:
  one fact, one representation.
- **C163** (2026-10-21; amends C149, L06's finding). The FuncToLLVM patch
  attaches `noalias` and the other pointer attributes to a memref
  descriptor's aligned pointer only, never to its allocated pointer: a
  function may free through the allocated pointer, and `noalias` there
  would let LLVM move a read past the free. Every access goes through the
  aligned pointer, so nothing the attribute buys is lost.
- **C164** (2026-10-21; amends C78, L03's finding). specgen's output is
  not compared with today's hand `.td`: the cutover redesigns every op,
  type and name in one change (D56, C158), so today's text describes a
  dialect that no longer exists. Byte identity is held instead between a
  fresh generation and the committed outputs, on both hosts and all four
  targets (D67), which C78's pure `generate` makes possible.
- **C165** (2026-10-21; L21's finding; retires C149's and C163's patch).
  Program functions are built as `llvm.func` by our lowering and never
  pass through FuncToLLVM, which attaches `noalias`, argument memory and
  the rest itself (L21). So patch 78 reaches nothing and goes, its report
  kept as a submission (AGENTS.md: a patch goes when nothing in the tree
  reaches the bug).
- **C166** (2026-10-21; L14's seam between L16's Emit and L09's
  specification; extends C19 and D105 to `idr.lit.match`). A literal
  match's default region binds the scrutinee refined to the complement of
  its keys, at the scrutinee's type; a literal case binds nothing, since
  its value is its key, a constant. The refinement is read off the
  binding's place (the op's keys), never held again. The natural `0`
  versus successor match needs it: the predecessor is computed from the
  value proved non-zero, so `nat.pred` is total and ranges see `≥ 1`
  there; a default that binds nothing loses that fact, as an unrefined
  case did before D105. L09's specification takes Emit's form; L05's
  `sourceOf` maps the binding to its scrutinee.
  *Amended* (2026-10-23, L07v's evidence under the one rule of when a
  reference moves on, 74f9a18f): a literal case binds the scrutinee too,
  its value equal to its key (`getRegionScrutinee` keeps `Equals{key}`),
  as a data match's case binds its refined scrutinee. The match forwards
  its operand into every region's binding, so the rule moves it at the op
  and each binding dies in its region, with no per-edge path in the rule,
  placement or linearity; a counted scrutinee no longer leaks on a case
  path, and a case that reads the scrutinee reads its binding, moved in
  with no dup. A word or Double case binds a word, which holds no
  reference. Rejected: keeping a case unbound with a per-edge move, a
  dup and a drop on each case path that reads the scrutinee, a special
  case in three readers.
- **C167** (2026-10-21; L10's finding that C38 and C96 disagree;
  amends C38's last sentence). `!idr.dest<T>` is a place a value of type
  `T` goes, linear by its own type, where `T` is any carrier that is not
  graded, not linear by type (no destination of a destination, a cell or
  a frame stack) and not a lifetime. Where the place is (a hole of a
  fresh cell, a frame's answer slot) is fixed by the op that makes it,
  never by the type: a binary-tree insert's two holes (`Node` fields 0
  and 2) must be one loop-carried type, which C38's cell-constructor-field
  typing made two; and frames write an answer of any row type through the
  base frame's destination (C96), which C38 could not hold for an `i64`
  or an inline pair. It lowers to one address per run-time component of
  `T`. What a hole may be is stated once, in the type's verifier; L04's
  `destOf` asks it.
- **C168** (2026-10-21; L11's finding; C40's encoding yields to D89). The
  count keeps "1 is unique, 0 is static", not Koka's signed encoding:
  D89, the owner's ruling, keeps the count-0 marker test for the one
  essential case and rejects a sentinel count, which would write static
  data that every shard shares read-only. C40's other parts (no atomic
  count, the word-kind lattice, one `inc` and `dec` per kind) stand.
- **C169** (2026-10-21; L11's risk). simdutf runs the one implementation
  the target's entry fixes, called directly through that implementation's
  `final` class, never chosen at run time: the target's features are a
  static fact (AGENTS.md: no CPU query outside the target's startup
  check, which refuses a machine without them, status 126), and run-time
  selection through a virtual table is an indirect call the stack bound
  must treat as reaching every function of its type, so simdutf's
  dispatch would read as a cycle and `--prepare-runtime` would refuse.
  `Strings/Simd.cpp`'s selection goes; if simdutf offers no direct path,
  the path is an upstream patch.
- **C170** (2026-10-21; L09's choice, reviewed). A control op that makes
  a scoped value (`data.match`, `lit.match`, `join`, `loop`) states its
  lifetime by one optional `outer` operand, present exactly when one of
  its results is scoped, through the same `StatesLifetimeOpInterface`
  as `idr.func` and `idr.call`: a lifetime is an SSA value whose
  dominance MLIR checks (D93), not a field of a type or an attribute, and
  one interface states it for every op that makes scoped values.
- **C171** (2026-10-21; L10's finding of a bug in frames' wrapper; C96's
  answer slot). Where a function waits for an answer written through a
  destination, the slot is one op, `idr.dest.answer`: a single region
  that receives a `!idr.dest<R>` and the op's result, of type `R`, is
  the value written through it, read out when the region ends. The
  destination is used exactly once on every path (it is linear by its
  type), cannot leave the region (dominance), and no call inside the
  region is in tail position, since the op reads its slot after the
  region; so C97 holds for it with no reading of where a destination
  points. It lowers to a stack slot of `R`'s components, which the
  destination's addresses name and the result loads. It replaces the
  wrapper's `cell.stack` cell with a counted init, which refused an
  answers member laid out in place, returned views of its own
  activation, and had no way to move an owned value out of the slot.
- **C172** (2026-10-21; L06's finding on patch 86). Stage 1 of the
  toolchain builds from the patched tree on every target, not the pinned
  tree as checked out: it is the compiler that builds stage 2's LLVM and
  every program's runtime, so it must carry clang's stack-clash fix for
  Darwin (patch 86) to emit the probes AGENTS.md requires on a small
  stack. One recipe on all four targets, nothing per target. Its cost:
  any change to a carried LLVM patch rebuilds stage 1 as well as stage 2,
  on each weekly bump that touches a patch.
- **C173** (2026-10-21; L08's finding; where D71's "by construction"
  and C92's local rule run). Bufferization reads the grade (D71), but
  `unique deep` was written only by the exclusivity marking, which runs
  after bufferization, and D110's `unique self` covers cells, not
  buffers; so at bufferization no buffer held in a cell was provably
  writable, `LArray`'s inside `Array` included. C92's local rule runs
  before bufferization: a value is `unique deep` when it is fresh (a
  constructor's, a recycled cell's, or a call's result whose signature
  says so) or taken or read at a linear position from a `unique deep`
  value, and flows only through linear positions. The ops' own result-type
  inference states the local part, and a result's exclusivity in a
  function type is derived bottom-up over call-graph components as rows
  are, before bufferization. The verifier checks the rule after every
  pass; the marking after bufferization adds claims only where it proves
  more. No ruling changes: D71 already says "by construction", and C92
  says how.
- **C174** (2026-10-21; L16's blocker on D83). D83's closed sum is a
  sum of which implementation, not a record of method values: a
  dictionary chosen at run time is a value of a closed sum whose
  constructors are the instances the program fixes, each carrying the
  choices its own constraints made (an instance `Show a => Show (List
  a)` holds its element's choice as a field); each use of a method
  matches on it and calls that instance's method monomorphized at the
  use's own types. A polymorphic method then needs no polymorphic value,
  since every use site fixes its types, and defunctionalization treats the
  sum as any other. A choice whose set no analysis bounds (an instance
  built deeper at each recursive call) stays megamorphic and refused.
- **C175** (2026-10-21; L16's blocker on 0011's O3). The translation
  runs as semi-naive evaluation (R2's fixpoint) over the instance table
  with no effect in the step: the definitions it reads are read once at
  the boundary into typed tables (AGENTS.md), and an instance's identity
  is its content (definition and index terms), so minting an instance
  is deriving a tuple whose key is that content. The universe grows with
  each round's new keys, which semi-naive evaluation handles as its
  delta; the growth check, which decides the megamorphic refusal as a
  property of the program, bounds it, and no count refuses.
- **C176** (2026-10-21; L10's finding; amends C167's "not graded"). A
  destination's type carries the grade its write must meet:
  `!idr.dest<T>` where `T` may be a graded type, and `dest.write`
  accepts a value whose claim is at least `T`'s, while `idr.dest.answer`
  gives back exactly `T`. A carrier-only destination lost a framed
  result's `unique` claim, which frames could only meet with an internal
  error, and the lossless form keeps it. A `T` that is `scoped` makes
  `idr.dest.answer` a control op making a scoped value, which states its
  lifetime by C170's `outer` operand, checked to enclose the op. Still
  excluded: a `T` linear by its type, and a lifetime.
- **C177** (2026-10-21; L11's route for C138; amends C138's record).
  The checked runtime holds each active call to the bound the compiler
  computed for its function, instead of recording peaks for the harness
  to compare: the compiled program tells it where a call begins, what it
  holds dead and where it ends, and an allocation made while a call holds
  more dead bytes than its bound ends the run with its own ending,
  `FrameBoundExceeded`, an internal error from the one ending table. The
  harness compares the ending as data, as it does for every ending, and
  parses no text; a planted program whose only possible internal error
  is the bound shows the check catches it. The shipped runtime's entries
  are empty, and `check-archive` refuses an account in a shipped
  archive. Enforcing the bound at the allocation where it would break is
  the stronger statement of D26, and it needs no file or channel of its
  own.
- **C178** (2026-10-21; L15's measure for C133's scale relations). A
  pass's footprint is the peak, less the start, of the bytes held in the
  compiler's shared containers (`IndexVector`, `BitSet`, `Ragged`, and
  every solver's program-sized state, moved into them), counted per
  thread by their one allocator and reported per pass run. It gives the
  same number on every target, at any thread count and on every run,
  which a scale relation at N and 2N needs; a process's resident size
  differs by target, allocator and page size, and stays the qualification
  measurement of peak memory, not the scale relation's.
- **C179** (2026-10-21; L10's finding; amends C171 and C170). A row of
  any width keeps every result at its whole grade, and each scoped
  result states its own lifetime:
  - `idr.dest.answer` is the slot of a row: results `R1..Rk` and one
    region binding one `!idr.dest<Ri>` per result, each result exactly
    its destination's `T` (C176); `k = 1` is C171's op. Rows of no
    result and of several exist (dead results are dropped, columns
    rewrite result lists), and an answers record read back at its
    fields' read type lost a static, scoped or claimed result, which
    frames met only with an internal error. Frames' base frame holds one
    destination per result; the answers group, the resume's construction
    of it, the wrapper's unpack and the internal error go.
  - C170's one `outer` operand becomes `outers`, one per scoped result
    in result order, the pairing read off the results' types: one
    operand could not state two results scoped in two lifetimes without
    narrowing one of them to the other's span, which refuses a later
    yield the program is entitled to. The same holds for `data.match`,
    `lit.match`, `join` and `loop`.
- **C180** (2026-10-21; L12's fresh-buffer invariant, and its seam with
  L16). A write into a buffer bufferization has just allocated releases
  nothing, so it is its own op, `idr.array.place_copy`, decided in
  One-Shot's copy hook where the fact is known; and every buffer of
  elements that hold references is written whole by its first user, a
  destination-style op that does not read it (`place_copy`, a
  tabulation or a scan), so no store, copy or release at death reads an
  unwritten slot and no allocation is zero-filled. The frontend
  therefore writes a counted join and a rank-0 counted fold init as
  tabulations, as C107 already writes a counted transpose; joins of
  words keep their slices, since the invariant concerns only
  reference-holding elements. No upstream hook is carried: a
  tabulation is the representation that states the fact.
- **C181** (2026-10-21; L05's open question; reads C170's "one interface
  states it for every op that makes scoped values"). Every op that can
  make a scoped value states its lifetime through `outers` (C179),
  `data.field`, `data.con`, `data.reindex` and `lin.cast` among them,
  not only control ops: a value's lifetime is then read off its defining
  op in one step, never found by walking its definitions back to an
  opener, and nothing read through these ops stays counted for want of
  a stated lifetime. An op that passes a scoped operand through states
  that operand's lifetime or one it encloses, which the verifier checks
  locally; a constructor states one its scoped fields all outlive. The
  decide step sets them all.
- **C182** (2026-10-21; L09's finding; completes C179 and C181). The
  values an op makes include those its regions bind: a control op's
  `outers` holds one lifetime per scoped value it makes, paired off the
  types, in this order: its scoped results, in result order; for
  `data.match`, each scoped entering position (the scrutinee, then each
  forwarded value), one entry covering every region, since each region
  binds position k at the same hold, refined only in its family; for
  `lit.match`, the scrutinee's position its default binds; for `join`
  and `loop`, each scoped parameter of each region, in region and
  parameter order. The count is checked equal to the number of scoped
  values. Deriving a bound value's lifetime from what entered it would
  walk through nested matches, which C181 rules out, and one entry for
  several values would narrow them, which C179 rules out.
- **C183** (2026-10-21; L17's question on 0010's A0 in the fork). A term
  being elaborated stays an unshared, located tree, as the elaborator's
  59 location reads need; when a definition is stored, its terms become
  columns in preorder, shared within the definition, with their
  locations as one more preorder column, so no location is lost and no
  shared node needs one. The stored columns are frozen with the
  definition (an immutable array of `mlir-array`, both hosts), so every
  read is a pure read of an immutable value and the fork states no new
  trust: a run-time read hidden as pure is what AGENTS.md allows only a
  trusted library, and a frozen array needs none. Definitions refer to
  one another by interned name, not by arena position, so no table
  grows under a read. Its cost: no sharing across definitions, which a
  global append-only arena would give at the price of that trust.
- **C184** (2026-10-21; L19's finding against `no-local-headers` and
  `zones`). No header sits beside a `.cpp`: each of the ten under `lib/`
  moves into `include/idr` under its owner, folded into the owner's
  existing header where it is that unit's interface, or in a directory
  granted for it (`Transforms/EGraph/` to L14, `Conversion/Lower/` to
  L21, `Transforms/InPlace/` to L08, `Transforms/Tail/` to L10,
  `Transforms/Counting/` to L07, `Transforms/ExpectProperties.inc` to
  L19). The rule stands as written: a declaration two units share has
  one home.
- **C185** (2026-10-21; L08's question on D71; reads D71 with D70 and
  D110). An `in_place` type whose own cells hold a buffer (`LArray`,
  `Linear.Vec`) obliges `unique deep`, not D70's `unique self`: D71 gives
  their values "the exclusive linear grade by construction", and only
  exclusivity of the buffer lets bufferization write it in place; for
  every other `in_place` type, D70 and D110's `unique self` stand. Which
  types those are is read off the family declaration (an own cell holds
  a buffer), never listed. A quantity-1 parameter of such a type is
  graded `unique deep` from its type and quantity at the boundary, and
  the exclusivity check holds every call to it: a call it cannot prove
  exclusive meets `unsupported (uniqueness)`, as D71 says. A buffer an
  upstream op makes enters our grades through `own.adopt`, so a cell
  holding it can claim `unique deep`.
  *Reversed* in its claim level by D122: such a type obliges `unique
  self`, which covers the buffer's storage and never its elements.
- **C186** (2026-10-21; L21's question on C177). The lowering emits the
  frame-bound account's calls in every build, and which runtime the
  program links decides what they do: the runtime's bitcode is linked
  into the module before code generation (C44, `LinkRuntime`), and the
  shipped runtime's entries are empty, so they inline away before any
  instruction is chosen and a shipped program pays nothing. A second
  lowering mode chosen by an option would be configuration the compiler
  does not carry. The claim is checked, not assumed: a shipped program's
  object references no account entry, a test of L19's beside
  `check-archive`'s refusal of an account in a shipped archive.
- **C187** (2026-10-21; L02's finding). `idr.func`'s positional facts
  (`lives_in`, `given_back`, the bounds) stay consistent under every
  insert or erase of an argument or result, by whoever calls it, through
  an upstream patch: `FunctionOpInterface`'s four edits become interface
  methods with upstream's present behaviour as their defaults, so a
  generic caller reaches `idr.func`'s own edits, which keep the facts.
  Today they are shared class declarations that a generic handle never
  dispatches, and none of the hooks they call receives the index map. A
  refusal through `cloneTypeWith` returning null would leave a generic
  caller holding a null type, which without assertions is undefined
  behaviour, not a refusal. It is carried as an `upstream/` patch with
  its check and PINS entry (AGENTS.md: the change we need is carried),
  and lets upstream passes edit `idr.func` safely.
- **C188** (2026-10-21; L08's finding E1; amends C185's "at the
  boundary"). The frontend writes no sharing claim on a parameter: a
  call's argument must equal its parameter's type, grade included, and
  the frontend's own output is verified when it is parsed, so a claim
  the frontend writes but cannot already prove at every call makes its
  module fail verification, an internal error, before any analysis
  could refuse the program. `idr-in-place`, the first pass that can
  prove calls, writes the boundary grade, reading the promise off the
  type, and refuses a call it cannot prove with `unsupported
  (uniqueness)` (D71).
- **C189** (2026-10-21; L10's findings; reads AGENTS.md's "a lifetime is
  an optimization over counting, never a replacement"). Frames carry no
  lifetime: every function a call cycle runs on its stack takes the
  cycle's lifetimes as parameters, in one arrangement, and passes them
  on at every tail (L10, 6905a004). No lifetime or loan is ever placed
  in a shape frames cannot split: where a cycle's functions do not share
  their lifetimes in one arrangement, where a loan would wrap a call on
  its own cycle, or where a framed call sits inside a match inside a
  per-level region, the decide step and borrows leave those values
  counted, as they would with no lifetime at all. Copies per arrangement
  of lifetimes are an optimization the decide step may make within its
  budget; a spent budget leaves the values counted and refuses nothing.
  Frames' internal error then marks only a broken invariant, never a
  program it was handed by the passes before it.
- **C190** (2026-10-21; L08's choice, reviewed; follows C173 and C188).
  `idr-in-place` runs C92's local rule (`unique::raiseClaims`, shared
  with `idr-unique-results`) after it writes the boundary grade and
  before it meets positions: a graded parameter's claim otherwise falls
  to shared at the first match that takes it apart, and bufferization
  never sees it. One rule, run where the grade it reads has just been
  written.
- **C191** (2026-10-21; L14's seam against `mlir-form.md` §3.2). A node
  a rule builds gets its facts without materializing an op: its range
  from upstream's own range functions (`InferIntRangeCommon.h`,
  `inferAnd`, `inferSub` and kin) for an admitted upstream op, and from
  D41's templates (`InlineArith<F>`, exposing `F`) for ours, chosen by
  the rule table's generated op kind through a generated table, so no
  op is created on a worker and no attribute made there; its constant
  comes only from the meet with what it replaced, since a node whose
  operands are all constant is folded when it is inserted. The admitted
  op's record names its range function in the specification. §3.2's
  line ("a rule-made node is never folded through an `Operation`")
  stands, and L14's detached-op route goes.
- **C192** (2026-10-22; L16's seam with L07 and L12; refines C185's
  adoption). A buffer enters our grades by `own.adopt` where it is
  allocated, and only there: bufferization places it at each
  `memref.alloc` it makes for elements that hold references, since only
  it knows which buffer is an allocation. The frontend writes none: the
  buffer behind a tensor it stores may be a slice, a parameter's or one
  read back out of a cell, and adopting it there would count one memory
  twice.
- **C193** (2026-10-22; L16's finding; carries out D71 as ruled). `LArray`
  reaches the dialect as its family, a cell holding its buffer, as
  `Linear.Vec` does, not as a bare tensor: the Faster hook that maps it to
  a value array is what kept D71's `InPlaceType` row from ever being
  read, and a bare tensor carries no grade for bufferization to read
  (D71: "bufferization reads the grade"; C105: a field's buffer is
  writable only when its cell is exclusive). Its operations read the
  buffer out of the cell, run on it, and rebuild the cell in place by
  D24's rule. The claim its buffer needs is the open question in §4.
- **C194** (2026-10-22; L10's finding; completes C189). Every op whose
  region can hold a call on its function's own cycle is one frames can
  split: `io.unsafe_run`, at whose end nothing runs, propagates
  control-flow breaks; `memo.run` gets a split form whose store into the
  cell is a continuation step; and a generating op (`array.tabulate`,
  `array.update`) whose body holds such a call is lowered to a join-point
  loop (`idr.loop`) before frames, which splits join regions already.
  No valid program then reaches frames' internal error.
- **C195** (2026-10-22; L07's finding; amends C119). C119's `Exclusive`
  handle goes: a value's exclusivity is its grade, in its type, which the
  lowering reads for a free with no count and the dup verifier reads to
  refuse a claimed value; a handle beside the type would hold the same
  claim twice. `Token` stays, and gains a branch into each region of an
  op that runs exactly one of them and an N-arm rejoin, since a match has
  N regions and its result tokens exist only once it is rebuilt with
  their merged types.
- **C196** (2026-10-22; the decisions audit; amends C24 and records
  C1's reach). File times follow base's own API: `io.file_time` takes a
  file handle and gives a file-time handle, and one op,
  `handle.file_time <field>`, reads each of base's six fields, where C24
  had one op with seven results that no base function matches (L13,
  989f2be5). And C189 supersedes C1 where they meet: borrow inference
  lends nothing around a call on its caller's own cycle, so frames can
  split every region it is handed; C1's derived borrows stand
  elsewhere.
- **C197** (2026-10-22; L19's sixth pass; amends C134's "primitives").
  The harness's table of builtins keeps what is the test's own: each
  builtin's spelling as a program writes it, and its meaning, the
  oracle's, written from upstream's language and `runtime/`'s
  documentation. The harness imports neither the fork nor the frontend,
  and C6 keeps base's names out of the specification, so nothing else
  could hold the spelling. What a builtin is in the dialect comes from
  the specification's op value its entry names: the op, its family and
  host dependence, its operand and result types, and the guard where it
  crashes. The table's own operation sum and parameter domains go (19
  G6). The oracle's meaning includes each crash the runtime documents,
  so a generated program that reaches one is checked, not avoided.
  *Sharpened* (2026-10-22; L19's finding): each builtin's Idris-level
  signature, its operand and result types as a program writes them
  (Int8 apart from Bits8, Char apart from Int32), is the table's own,
  beside its spelling, since it is base's language, which C6 keeps out
  of the specification, and the dialect's signless types and family ops
  drop it. The op, its family, host dependence and guard still come
  from the specification's op.
  *Shape* (2026-10-22; recheck 3's sweep, the harness finding a guard's
  reading by its mnemonic): a guard names its check by a closed sum,
  `GuardKind` (`NonZero`, `InBounds`, `NonEmpty`, `Finite`, `Range`,
  `HoldsString`), declared with `Guard` in `Spec/Core/Op.idr`, whose
  `given` has `S (guardOthers kind)` positions; `Spec/Ops/Checks.idr`
  maps each kind to its op by one total function (`guardOpOf`), which
  the generator reads where it read the op, and the harness reads each
  kind's condition by a total match, with no lookup and no `Left`.
- **C198** (2026-10-22; L13's seventh pass). No fold whose answer
  depends on the compiling machine. Upstream's folds of `math.exp`,
  `log`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan` and `powf` call the
  compiling machine's libm, whose results IEEE does not pin, so a
  folded constant could differ in its last digit from what the target
  computes, and removing an optimization would change a result. The
  specification marks those admitted records as never folded, and
  every reader of folds (the e-graph's generated table among them)
  omits them, so they run on the target as written. `sqrt`, `floor` and
  `ceil` are exact under IEEE, so their folds stay.
- **C199** (2026-10-22; L17's third pass). The fork's known identifiers
  are held once. `Core.Name.Known` spells each of its 824 identifiers
  four times, as a constructor, its text, its ordinal and the inverse,
  kept in step by a proof run when the compiler is built; a copy kept
  in step by a check is still a copy. One Idris list of pairs, a
  constructor and its text, is the source, in the fork; a generator in
  the fork's tree, written in the subset both hosts compile, prints the
  module from it. The output is committed with its fingerprint in
  `generated.manifest`, and `make check` regenerates it, as for the
  dialect's TableGen. *Amended* (INT-4's question): the output is
  committed and `make check` regenerates it and fails on any byte of
  difference (`knowngen check`), but it takes no entry in
  `generated.manifest`. The manifest is the dialect specification's,
  written by one generator from one list of outputs; an entry for
  knowngen's files would give it a second writer or make the spec's
  generator hold a copy of the fork's output list.
- **C200** (2026-10-22; L09's C52 sweep; sharpens C52). No case of a
  `match` takes every type. A generic case beside named ones is a
  default, and a sum that gains an alternative then goes to it silently,
  which is the coverage C52 exists to keep. A case for several
  alternatives names them, by a list or by the concept they share. The
  fold refuses an unconstrained case when the compiler is built, by
  probing the cases with a type no sum holds.
- **C201** (2026-10-22; L11's sixth pass; settles C43's margin). The
  tools' threads run on D33's measured mark plus the target's
  outside-code margin, the same one value the programs' stack takes
  (C98, C5): the deepest stack the C library's entries the tools reach
  use, painted and measured per target and recorded in the target's
  entry with its build and input. Our C++ and MLIR's, patched, never
  recurse on the input, so the mark over the stage-1 module and the
  nesting fixtures covers our own frames; only outside code needs the
  margin, and a round factor would be a size that is neither the
  program's nor the host's.
- **C202** (2026-10-22; L08's fifth pass). No pass of ours rewrites the
  type of a value an upstream op produces. An element that
  `tensor.extract` or `memref.load` reads has its type's grade, from the
  array's element type: the in-place rule never raises it and never
  follows it into the array, so a requirement the element's type does
  not meet ends at the shared value's cause, as the in-place promise
  asks. `ub.poison` is graded as any value of ours: it holds no value,
  so its type is ours to choose, and a dead arm yielding it costs a
  match no claim.
- **C203** (2026-10-22; L16's sixth pass; amends C38 under C139). The
  frontend writes every call `nontail`, and `tail::decide`, run where the
  program becomes first order, writes `tail` and `modulo_context`. No
  source syntax states a context, so the frontend would only restate the
  decider; before that stage a call's fact promises nothing. The context
  is still read off the program before counting, as C38 asks, and from
  that stage on every fact is the decider's answer, checked both ways.
  *Sharpened* (2026-10-23, L10x's handoff; recheck 5's N1 read C20 alone):
  the decider is the one definition of tail position, one downward walk
  per function (`tail::tailsOf`), with no per-call climb (`inTailPosition`
  and `decide(CallOp)` go). It runs where the program becomes first order
  and in each pass whose edit can change a call's position without the
  pass knowing the new kind (an op that records no position removed or
  exposed: the e-graph's write-back, inlining, capture drops, raising,
  narrowing, TRMC, frames), as `decideTails`; a pass that knows the kind
  it makes writes it (the inliner composes the replaced and the held
  call's, contification at a non-tail continuation writes `nontail`).
  The verifier checks both ways against the same walk.
- **C204** (2026-10-22; L05's finding on L16's sixth pass; amends C113's
  routing of integer keys). A literal match on an integer, a char or a
  double stays `idr.lit.match`, as one on a string, a big or a natural
  does, until the lowering. `scf.index_switch` holds neither fact the
  match keeps: its default binds no refined scrutinee (C166), so a
  nonzero divisor proved by a `0` case is tested again at run time, and
  it states no `outers`, so a scoped value through it becomes counted.
  The idr dialect holds what upstream's do not mean; these two facts are
  that. The lowering turns a word match into `scf.index_switch`, its
  default handed the scrutinee, and a double match into its chain of
  `cmpf oeq`; the frontend writes no `scf.index_switch`, which is
  admitted only where the lowering writes it.
- **C205** (2026-10-22; L14's eighth pass; under C191). A node's
  constant in the rewrite graph is a value, an `APInt` read off its
  singleton range (the rule upstream's range optimizations use), never
  an attribute: no attribute is made while the graph is built or
  rewritten, and the write-back makes each constant's attribute once
  (on the function's own worker, as every function pass rewrites). A rule's literal is
  generated as a value, and a rule that builds `c0 . c1` over two
  constants gets its constant from the built node's range at once, as
  the folds did before C191. The ops C198 never folds are a generated
  list the rewrite graph reads once, when it is built, and skips.
  *Amended by D127* (2026-10-23): the value a node holds is not an
  integer alone. A string, a Double and a big past the small range are
  values the graph computes, by the runtime's functions through the one
  fold (`Fold.h`'s `evaluate` over the graph's own values), never read
  only off an op that already held them; the write-back still makes each
  attribute once.
- **C206** (2026-10-22; L04's finding on L18's seam). `data.reindex` is
  one op: the same value at new indices. Whether it does work at run
  time is a fact of its two types, since inline or in a cell is layout,
  computed when a type is made and never the frontend's choice, and the
  frontend, which writes the reindex, cannot know it. Where the two
  layouts agree it is free; where they differ it re-packs, and a re-pack
  into a cell acquires memory, an effect that follows from its types.
  `DataType` answers "these two share a run-time layout" from its stored
  layout facts. The tail decider looks through a free reindex and stops
  at a re-pack, which is work after the call. The lowering re-packs
  instead of failing to convert, since no representation limit refuses
  a program. It is not `ResultCarriesOperand`, whose check and readers
  mean a change of grade alone.
- **C207** (2026-10-22; L12's seventh pass; completes C194). An
  `array.update` whose region calls into its caller's own cycle is split
  by the take, inline and place form generating ops already use, widened
  to mutable memory and boxed elements: the element is taken out, the
  region's code runs inline where frames can split it, and the result is
  placed back. One mechanism covers it, whether the call was written in
  the region or moved there by fusion, so fusion needs no call graph and
  no second guard.
- **C208** (2026-10-22; L07's eighth pass; amends C85). An element read
  from an exclusive array is a view; one from a linear array is not, for
  that reason alone: a linear binder does not imply unique heap
  ownership (`f arr arr` passes one array to two linear parameters, and a
  write through one is seen by a read through the other). The row of
  each op in the element's stretch decides otherwise, as C85 says; the
  function's own row does not, since it leaves out writes to memory the
  function allocated.
- **C209** (2026-10-22; L07's eighth pass). A part read from an owner
  with no reference of its own (a field read, an element view, a lent
  element) is given up with its owner. At the owned stage the
  linearity rule reads the flow edge that makes it a part and counts its
  owner's consumption for it, so it needs no type of its own and no
  consumption of its own.
- **C210** (2026-10-22; L13's eighth pass; carries C198 to LLVM). LLVM's
  constant folder folds calls to `exp`, `log`, the trigonometric
  functions and `pow` with the compiling machine's libm, so C198 holds
  only if the nine never-folded math ops reach LLVM in a form it does
  not fold. The mechanism is upstream's own switch if the pin has one,
  else a carried patch narrowed to those functions; `nobuiltin` only if
  neither exists, since it also blocks the vector library's mapping of
  the call.
  The pin has upstream's switch, `-disable-fp-call-folding`, which the
  tools pass after the user's arguments so none can unset it; it stops
  every float call folding in LLVM, `sqrt`, `floor` and `ceil` among
  them, a loss of speed the qualification measures (L06, 2026-10-22).
- **C215** (2026-10-22; L06's finding; completes C198 on MLIR's side).
  MLIR's own `math` folders call the compiling machine's libm, and
  upstream drivers in the pipeline call them: `convert-to-llvm` folds
  before its patterns, with no option to stop it, and sparse constant
  propagation folds what it visits. So the never-folded math ops are
  lowered in `idr-lower`'s own conversion, which never folds, before any
  upstream driver meets them, and the constant analysis built on sparse
  constant propagation skips them, reading the same generated list the
  rewrite graph does. A vector math op with constant operands reaching
  `VectorToLLVM`'s greedy pre-lowering is the one reader left; it is
  patched only if the qualification finds a program that reaches it.
- **C216** (2026-10-22; L17's sixth pass; under D44). 0011's O5 lands in
  two halves. The flat parse tree lands first, whole: the parser emits
  columns (each node's location in its payload, a size column, children
  before parents, ids shared where the grammar shares a subtree), and a
  decoder gives `PTerm` to Desugar, Resugar and the printer, so the
  parser is converted entirely and nothing reads it half and half.
  Resolution as R1's interval join is not P0's (D125): Idris resolves
  names during elaboration, against the typed environment, and the only
  scope over syntax is Desugar's bound-name set, which needs each
  clause's pattern variables after operators are regrouped by the
  fixities in force, so a join over the parse tree has no reader unless
  Desugar reads the columns.
- **C217** (2026-10-22; L16's eighth pass; extends C213). A polymorphic
  function kept at run time (in a field, as a result, or chosen at run
  time) is a value of a closed sum keyed by its function type: its
  constructors are the functions and closures the whole program puts at
  that type, each with its captures, and each use matches on it and
  calls that member monomorphized at the use's own types. The frontend
  writes it as a data family, as C174's dictionary, so the C++ meets no
  polymorphic value. It is refused only where that set or the use types
  are unbounded.
- **C218** (2026-10-22; the decisions audit C3). Two settlements. The
  e-graph makes no attribute while it is built or rewritten, for
  any constant (sharpens C205): an integer is an `APInt` off its range, a
  double an `APFloat`, and a string, a big past the small range or a
  data constant is read only from an op that already holds it, never
  made by a fold inside the graph; the write-back makes what it writes.
  And `idr.refusal` stays bare under C158, as an op that sits in the
  module and acts on no type or resource.
  *Amended by D127* (2026-10-23): its first settlement's reading of
  strings and bigs is reversed. The graph computes a string, a Double
  and a big past the small range as values of its own (a runtime string
  or big it holds a count of, a Double's bits), by the runtime's
  function each op's fold calls; a data constant is still read only from
  an op that holds it. No attribute is made while the graph is built or
  rewritten, for any constant, as before.
- **C219** (2026-10-22; L16's growth passes; under D46, D68). The growth
  graph's remaining shapes. A choice is held program-wide under the key
  the translation gives it (an interface's address for a dictionary, the
  function type for C217's), so the graph splits a dispatch by every
  member the translation can request, not only a site's own leaves.
  Each implementation field is a position of the graph, so a nested
  field read is arcs between positions and needs no second mechanism
  with its own cycle refusal. A member's application is walked once per
  member, its binders standing for the use's positions, so the requests a
  member's body makes are met. And the places where members are made are
  one table, read once at the boundary by the translation and the growth
  check alike, so neither mirrors the other. *Sharpened* (L16's evidence:
  three of the four places are decided by the instance's types): the
  table holds, per definition, what each binder its normalised type
  shows takes and what it gives after each count of arguments, each a
  `Holding`, `AMember | NoMember | ByInstance`; both readers test a type
  only at `ByInstance`, the case the instance alone decides.
- **C220** (2026-10-22; L16's C175 pass). Two consequences of reading
  the program once at the boundary. A case block is named from what
  `main` reaches: the search that fell back to every name in the context
  reads only the boundary's table, and a block it cannot place is an
  internal error. A block's symbol may change with it, which is text
  for a reader, deterministic either way. And a reachable function whose
  totality the TTC leaves unchecked is checked once, at the boundary,
  not on demand inside the translation, which wrote verdicts into the
  live context; the qualification measures what that costs.
- **C211** (2026-10-22; L09's finding; the mechanism under C166 and
  C204). `idr.lit.match` forwards its scrutinee into its default, as C166
  reads it (`sourceOf` maps the binding to its scrutinee), so upstream's
  range analysis gives the binding the scrutinee's range and never asks
  the op. The range analysis applies `ranges::excluding` to that
  forwarded value itself, in an override of upstream's
  `visitRegionSuccessors`; `lit.match` declares no `InferIntRange`. The
  binding stays the scrutinee for every reader of forwarding, so no
  ownership, sharing or counting reader changes.
- **C212** (2026-10-22; L17's fourth pass; under C154). `mlir-array`
  gives code the stock host runs a read and a write by a `Nat` with its
  bound at quantity 0, beside the `Fin`-indexed ones. A `Fin` is unary on
  the stock host, so each index costs as many steps as its value, and
  the fork's parser, arena and size-change graphs turned quadratic on the
  host that builds stage 1. Programs keep `Fin`: under idris-mlir a
  closed `Fin` is a fixed-width word whose bound the ranges read, which
  a `Nat` is not. Both reads mean the same element; idris-mlir writes
  them as the one operation of the generating set, its index the word
  the bound proves, so the dialect holds one read.
  *Withdrawn* (2026-10-22; L20's fifth pass, read in the pinned Idris).
  Its premise was false and unmeasured: the stock host compiles every
  type of `Nat`'s shape as an integer, `Fin` among them
  (`TTImp/ProcessData.idr:342-363`), and its identity pass makes
  `finToNat` and its kin free (`Compiler/Opts/Identity.idr`), which
  upstream's `tests/base/data_fin/performance.idr` checks at 2^64-1. A
  `Fin` index is constant time on both hosts, so `mlir-array` keeps one
  index, and the fork's bounded indices are `Fin` again. The one
  quadratic at those sites is base's `allFins`, rebuilt per call in the
  size-change graphs, which the fork computes once.
- **C213** (2026-10-22; L16's seventh pass; extends C174 under D83). A
  rank-2 argument, a polymorphic function or implementation passed as a
  value, and a field computed at run time that chooses an implementation
  are values of a closed sum, as C174's dictionary is: its constructors
  are the closures and instances the whole program passes there, each
  carrying its captures and its own constraints' choices. Each use in
  the callee matches on it and calls that member monomorphized at the
  use's own types, so no polymorphic value exists at run time. The
  frontend refuses with `runtime closure` only where that set or the
  set of use types is one no analysis bounds; a program whose choices
  the program fixes compiles. *Corrected* (recheck 3): the text named a
  `static argument` refusal too, which 52ec023e removed from the
  specification because nothing refused with it.
- **C214** (2026-10-22; L21's re-pack under C206). Three consequences of
  one re-pack. A `dest.write` converts the written value to its slot's
  layout with the same re-pack, so `!idr.dest<T>` keeps the field's type
  and TRMC makes a hole wherever it finds one. A re-pack reaches into
  arrays: an array field whose elements lay out differently at the two
  types is re-packed element by element, and `layoutMatch` says
  `OtherLayout` for it. A re-pack that builds a cell gives a fresh
  counted value, claimed unique, whatever the operand's hold, so
  counting frees it as any fresh cell. A reindex that builds nothing,
  free or not (a cell taken apart in place, a numeral re-widened), keeps
  its operand's hold, since its result's memory is the operand's.
- **C221** (2026-10-22; L16's growth passes; under D68). What the
  growth proof's readings are. Every reading of the growth check takes
  its term normalised by the host and then eta-contracted, so a family
  is read as itself whatever stands for it. The proof covers that form:
  a reading is the host's reduction followed by eta contraction, a
  relation of the frontend's proof beside the host's, and the
  contraction gives its result with that evidence at quantity 0. The
  host's reduction relation gains no eta step: its trusted claim that
  every reduction of a term goes on to the normaliser's result would
  then be false, since a contracted term does not reduce back to the
  uncontracted form the normaliser can return. Reading the uncontracted
  reduct instead would make two forms of one family two keys.
- **C222** (2026-10-22; L16's growth passes; under D68, extends C219).
  The translation's requests and the growth model's sites are one
  table. Today the translation makes each request on its own (a call in
  a term, a held field's re-request, a dispatch's arms, a family's
  instance) and imports nothing from the model, so the model's site for
  that request is a second copy no proof can link to it. The model's
  sites, built once at the boundary, are the table: each place the
  translation requests an instance reads its site from it and carries
  the site's membership at quantity 0, and the request's derivation is
  built from that site's reading. A request with no site is then
  unrepresentable rather than an error the run-time re-check reports.
- **C223** (2026-10-22; L16's growth passes; under D68). The held count
  is a constant of the graph. A held dispatch re-packs the dictionary
  parameter with one more held value, nested in a pair whose height is
  the count plus its types' heights, a sum no arc's gain expresses, and
  any term that names n types grows with n, so the count needs a bound
  whatever packs it. The graph computes that bound from the program:
  the longest held list a writing site packs, plus, for each distinct
  stuck path the program's dictionaries have, the most values a member
  closes over plus one. Each held type's position bounds its pair at
  that count plus the types' heights. It rests on two facts of the
  translation, which the proof states and carries rather than assumes: a
  chain holds each stuck path at most once, and every member a dispatch
  inserts reduces. It is derived from the program, never a round
  constant, and refuses nothing the translation makes finitely; a
  program on which either fact fails is reported as a counterexample.
- **C224** (2026-10-22; L16's growth passes; amends C223). Held values
  have a position per holder, not one for the program. A dictionary that
  mentions a dictionary parameter holding values holds those values as
  one value, of their packed type; with one program-wide held position,
  writing that type there is an arc from the position to itself, which
  the graph would refuse though the program wraps nothing deeper. So
  each dictionary that holds values (a node's parameter, a field, a
  choice) has its own held position, and a held dictionary wrapped into
  another is written from its own held position into the new one's by
  an arc whose gain is its count. It counts as one value in the new
  list, which C223's longest list now includes. A cycle through such
  arcs is a recursion that wraps a dictionary deeper at each call, a
  type that grows at each call, refused as any unbounded growth is.
  *Sharpened* (L16bb's evidence): a holder's held values are two
  positions, a one-value list's value as itself and the values of a
  longer list in pairs, so a recursion that passes its dictionary on
  unchanged has gain 0 and reaches its fixed key, while wrapping it
  deeper is still refused. With one position per holder, passing on was
  an arc of gain count−1, refused at a count of two.
- **C225** (2026-10-22; L17's assertion sweep). The fork's parser
  terminates by its types. The shallow-embedded grammar (a grammar is
  the parser, a function of its input) lost what upstream's deep
  embedding gave the totality checker, and five combinators (`some`,
  `count1`, `someTill`, `afterSome`, `blockEntries`) assert totality. A
  consuming grammar's type carries erased evidence that it advances its
  position, so a repetition recurses on the tokens left, accessible by
  their count, and every assertion goes. `covering` would meet the rule
  too, but it spreads to every caller and proves nothing; the evidence
  costs nothing at run time.
  *Superseded* by D113 the same day: the parser returns to upstream's
  deep embedding, which the totality checker sees as guarded with no
  assertion, and the compiler gains what it needs to compile it.

## 4. Open: the owner's decisions, in order

What stands open comes first, each to be raised alone with its full
context (D11); then what is settled, each item naming its ruling in §2
or its decision in §3.

**Open**: none. The last, a tail call's data result (L16dv's evidence,
2026-10-23), is settled by D129 (B*: a copy of the callee keyed to the
open layout, the tail call's layout checked by the call's verifier).

The optimizer e-graph's MLIR form (D107, under D106's narrow scope and
D109's C++ over MLIR) is C153's, for the owner's review in the plan's
approval (settled, below).

**Not a question** (the owner, 2026-10-21: not enough evidence to ask):
whether an optimization may raise a program's peak memory
(`unknowns.md` U24). The qualification measures the program suite's
peak footprint with and without sharing, and the question returns only
if that shows growth.

**Settled**: the owner's twenty-one decision points
(`synthesis/F-decisions.md` §2.1 holds each one's options, evidence, and
what it unblocks), and the later queue.

1. **DP-01.** Settled: a dead crash or divergence by D13, `exit` by D14;
   only a row carrying neither `crash` nor `divergence` licenses
   deleting or moving a call, totality removing divergence alone (D102).
2. **DP-02.** Settled by D20: effects only after the frontend; the world
   is gone from the IR.
3. **DP-03.** Settled: a crash and the heap by D21, what a summary
   covers by D22, runtime state a read-only child of IO by D27.
4. **DP-04. The effect system's structure.** Settled by D9.
5. **DP-05.** Settled by D17: no fence; P0 may undo the agent's work.
6. **DP-06.** Off the owner's list (D17): counting's redesign decides
   `Positions` on its merits.
7. **DP-07.** Struck by the owner (2026-10-21) as process above the
   compiler ("this is meta-work ... strike out this question"); the
   questions resting on it (Q4, perf-Q3, drv-Q1, oom-3, drv-Q6) go with
   it, and no step gate is drawn from it.
8. **DP-08.** Settled by D7 and D47 (the skill's wording).
9. **DP-09.** Settled by D44: P0 absorbs 0003 and 0011 whole, with
   0010's A0 and 0015's R1 and R2; 0011's O6 and O7 included, with
   0009's plain-Idris layer and 0015's R4 (D69), R4 only as far as O7
   consumes it, its union-find (D107).
10. **DP-10.** Settled by D43: 0009's array cutover is P0's.
11. **DP-11.** Settled by D23: out of memory is a named crash of the
    machine, outside the language.
12. **DP-12.** Settled by D24: the in-place promise is a rule read off
    the program before counting, which counting honours; it obliges
    only the family's own cells (D70), covers `LArray` and `Linear.Vec`
    (D71) and every value of an `in_place` type bound at quantity 1
    (D72), and counts a use only if it may still hold the value (D79).
13. **DP-13.** Settled: frame-limited by D26, its never-line reworded by
    D73, holding on a path that ends the process (D74); the order of
    counting and borrows follow from it (C1, §3); checked at run time by
    a typed record from the checked runtime (C138).
14. **DP-14.** Settled by D30: proper tail calls; a call in tail
    position never grows the stack; tail position has one definition
    (C139).
15. **DP-15.** Settled by D19: regions as the base, join points for
    linear tail continuations, blocks only at the lowering; a join point
    promised where the program as written makes one (D75), its target
    upstream's builtin `token` (D76), upstream's merged early exits
    adopted only in a form that keeps every fact (D82).
16. **DP-16.** Settled by D39, amended by D63: a lifetime is an SSA
    value opened by a region, not a parameter of a type; the grade and
    lifetime vocabulary is D88 to D90's.
17. **DP-17.** Settled: inline arithmetic by D41, the array library's
    generating set by D42.
18. **DP-18.** Settled: statuses by D37, sites as data by D38; an
    `exit` status outside 0 to 255 a crash at its site (D64), a
    function's name in a crash as data (D80), a reader going away an
    honest `SIGPIPE` (D81).
19. **DP-19.** Settled: strict hosts by D35, the host's memory limit
    by D36, read as the kernel's kill point (D65); the small stack
    charged when its thread starts (D66).
20. **DP-20.** Settled by D45, amended by D53 to D55: no count refuses
    a program in the elaborator.
21. **DP-21.** Settled by D46: the growth proof is over the code's own
    templates, with one stated trust in the fork's normaliser (D68).

Also settled, not on F's list:
- **Suspected bugs** (§8): folded into the cutover with their causes
  and reproduced in its qualification (C8, D56).
- **D45's mechanisms**: settled by D53, D54 and D55.
- **The cutover's later questions**: a held buffer's storage by D122,
  the e-graph's form by D123, lending an array to upstream's ops by
  D124, 0011's O5 by D125, the C++'s type dispatch by D126, constant
  folding by D127, the walk of a settled implementation by D128.
- **The execution's shape** (§7): settled by D56, one whole cutover
  built at its end.
- **Equality saturation** (G's DP-25): reopened by D57; narrow (D106),
  replacing greedy rewriting where our ops are (D98), nothing run at
  the points that hold upstream's ops only (D100), upstream's own passes
  left as they are (D99); built from MLIR's mechanisms in C++, its rules
  and laws data of the specification, generated into the C++ and never
  run in Idris (D107, D109), the frontend keeping its own union-find
  (D107, reversing D86 and D87's place in P0); effectful ops in a
  skeleton (D103, measured by C151), a call deleted or floated only if
  its row carries neither `crash` nor `divergence` (D102), its budget
  in nodes from the program alone (D108). Its MLIR form, D107's open
  question: a C++ pass with its own typed tables over MLIR's ops, our
  own solver in the solver layer, the research `eqsat` dialect rejected
  (C153, for the owner's review in the plan's approval); no rule
  synthesizer in P0 (C155). The owner's later queue: D93 to D109.
- **The e-graph research's questions to the owner**
  (`design/egraph-full/unknowns.md`): U1 by D102, U13 by D103, U17 by
  D108, U28 by D104; U24 is not a question (above). The libraries by
  D101, the two representation bugs the workloads found by D105.
- **The verification swarm's queue** (`verify/status.md`, items 1 to
  38; §3's "§4's queue"): settled by D58 to D96 and by C6, C137, C138,
  C139 and C142, each item naming its ruling there; D93 to D96 settled
  the lifetime questions 31 to 33 and 35 (`design/lifetimes/lowering.md`),
  with C144 to C148; the e-graph's items 36 to 38 by D84, D85 and D97,
  each since reversed, the standing word D107's.

## 5. The target, by area

What the compiler becomes, as the syntheses' consensus designs and the
design documents state it, held to §2 and §3. Where a piece waits on an
open decision, it names §4.

### 5.1 The effect system (D9)

Designed in `audits/p0/design/effect-vocabulary.md` (the vocabulary, the
tree, the atoms, the specification, the lowering, the stress test) on
`audits/p0/design/effects.md`'s machinery (one source, one query API,
one derivation, the verifier), with `typed-effects.md` (rows on ops).
In logical order:
- **What it protects** (D13, D14, D20, D21, D23, D102): a program is
  sequential, per shard; asynchrony only as futures, awaiting the one
  point where other tasks run; eager evaluation, crash and divergence
  kept; divergence removed only by `total` (termination decided per
  Idris component, C74), a crash only where its check folds (a divisor
  or index proved safe), so only a row carrying neither licenses
  deleting or moving a call (D102); `exit` an IO action; no world after
  the frontend; out of memory outside the language.
- **The tree** (D27). An op's effects are MLIR's four kinds and nothing
  more: consuming is `Free` on `count` alone (C69), acquiring `Allocate`
  on `heap` of the result, a fresh identity `Allocate` on `identity`
  (C3, C71), ending a `Write` on `exit`, `crash` or `divergence`; a
  guard's hazard is held by data dependence (D21); an exclusive drop
  reads no count (D10). The one query API compares `ResourceId` exactly,
  never upstream's `isa` (C69).
- **A declaration is two facts** (C70), replacing "five forms, exactly
  one per op", which cannot hold `idr.match`: its own effects, static or
  by typed rules each reading one value's own type, operand or result
  (`Consumes`, `NewIdentity`, `Acquires`, `ReadsMemo`, `CountsIfShared`,
  `Recycles`, `Summarized`, `ReleasesForeign`); and its bodies' effects,
  its own or recursive. At HEAD 112 static and 57 typed, not 175 and 14
  (L01 §1.11). Every declaration states what its runtime function does
  (C69), and none carries a counting decision early: before counting
  `array.get` is a borrowing read, `Read` on contents only, counting
  placing the element's dup (C152).
- **A function's row** (D22, D61): eleven atoms on its op, nine a caller
  orders with (`io runtime_state exit crash divergence read write count
  memo_state`), two that only report (`alloc free`), and D61's part per
  exclusive owned parameter; a call carries its callee's. Derived by one
  fold over declaration forms, a call contributing its row, and written
  over the call graph's components callees first wherever a pass adds
  effects; after every pass a row covers its derivation and equals it at
  each re-derivation, and a call's row equals its callee's (C64). Rows
  live on ops, never in value types: none of our effects changes a
  calling convention (D20), and allocation into a caller's lifetime, the
  first fact that would, is an operand, the lifetime's token (D63; C2 R3
  as amended).
- **One source** (D15, D16): `Spec.Effects` in the dialect's Idris
  specification declares resources, parents, admitted kinds, every op's
  declaration, rules, atoms, the projection and the LLVM tables, with
  its laws as types (a well-founded tree; nothing addressable under
  opaque; kinds per resource; each ordering atom round-trips; no op's
  effect lost; an acquisition names its result and carries no crash;
  whatever writes `exit` writes `io`; a row never refuses). Everything
  else is generated; nothing else names a resource.
- **The C++** (D7): a `consteval` effect set per op class; concepts
  reading ODS facts, never op lists; one interface dispatch for an
  `Operation *`; one query API and one classifier; region-op sets folded
  by each reader's walk, never a pointer-keyed map, and no `bool` in an
  effect set; the few dynamic facts listed with their reasons, which
  resource an upstream effect names among them (C70).
- **Upstream, the e-graph and LLVM** (C72, C73, D98, D102, D103,
  C151): dead code, sinking and the inliner read the declared effect
  kinds; where our ops are, the e-graph pass replaces canonicalize and
  CSE (D98), effectful ops staying outside it in a skeleton, a partial
  order per resource subtree with one-way rules (D103; measured to free
  few pairs and to cost little, C151), and a call is deleted or floated
  only if its row carries neither `crash` nor `divergence` (D102); LICM
  moves only pure ops, so lifting a read out of a loop, should a
  measurement ask for it, is a carried patch to upstream's LICM, never a
  pass of ours (C151, D99); `idr.call` is speculatable from its row. A
  row reaches LLVM through `llvm.func`
  built directly from `idr.func`: `memory(...)` over a `read` floor,
  never `none` (reuse rebuilds a cell under the same pointer), `write`
  joined to readwrite, D61's writes `argmem` only; `willreturn` not with
  `io`, `exit`, `crash` or `divergence`; `mustprogress` not with
  `divergence`; `nofree` not with `free` or `exit`; `nounwind`; `nosync`
  per atom; `noalias` on exclusive owned pointers, a buffer descriptor's
  pointers included through a carried patch to upstream's FuncToLLVM
  (C149).
- **Allocation** (D23): `Allocate` on `heap` reports and orders nothing;
  reuse, stack cells and static data acquire nothing, a cell put into a
  lifetime acquires on `heap` and the lifetime's end frees there (L05
  §2.3); no promise to users mentions it (D24, D26).
- **Concurrency, the kernel, Rust**: C2's five rules, as amended; a
  Rust call is an IO action into Rust's own runtime, with no
  optimization special to Rust and no call back into Idris (D92).
- **Deleted**: "does IO" held four ways; `PerformsIO`, `ObservableIO`,
  `MayCrashOpInterface`, `ReferenceResource`, `NoReturn`,
  `TakesReference`, `BuildsValue`; the double IO writes; MoveOut's
  second classifier; `bodyEffect` and its helpers; the hand `getEffects`
  bodies; the root resource on 54 ops (51 records, `con`, the two updates
  through `updateEffects`, L01 §1.2); the world (D20); the lying
  declarations (C69, C3); every other reading L02 §1.4 lists
  (`componentEffects`, `writeEffects`, `effectsCovered`, `solveEffects`,
  `Flow.h`'s `classify`, `mayRunAt`'s `isa<IOResource>`, `anyEffect`);
  the verifier rule V0 and the `func.func` stage (C64, C72).
- **Landing**: the tree and the derived row land together, never apart
  (lane 02's trap), and with them the live-cell counter's deletion and
  D37's ending table (C60, C101); `RecursiveMemoryEffects` stays on
  matches.
- **Names** (D28), a hard cutover with no alias of an old one.
- **Atoms' names** (D29), one name per concept.
- **Building a value acquires nothing before counting** (C3 as amended):
  an unforced memo cell, a value of an `in_place` family and a linear or
  owned result take a fresh identity.
- **Its boundary** (L01 §2, L02 §2): twelve resources by D28's names,
  generated from `Spec.Effects`; one fold, one writer, two verifier rules
  (containment per function, equality per call); one generated function
  from a row to LLVM's attributes; `tests/runtime-effects` holds each
  declaration to its runtime function on the four targets.

### 5.2 The C++ (D7)

*Specified by `audits/p0/design/compile-time-cpp.md`, written against
hand TableGen and re-based on D16, D51 and D48 by C121 (its lifetime
laws on the grade of D88 to D90, which replaced D40's three lifetimes),
whose run-time rules come from `audits/p0/design/perf-sources.md`.* What
is settled:
- **Decided when the Idris specification is built** (specgen printing
  `.td` for what mlir-tblgen reads and headers for what only our C++
  reads): ops and their families, types and grades, effects, the runtime
  ABI, the pipeline and its stage chain, refusal rules and their
  categories, data-body kinds, crash causes, clock kinds. A bad table is
  refused by the specification's types; `static_assert` and `consteval`
  check only facts whose subject is C++, and a hand function only against
  its printed table (C76).
- **The shared vocabulary**: typed dense ids and `IndexVector` (raw
  index access deleted); compressed-row graphs with a sentinel root row
  modelling one `Graph` concept, `NodeRef` carrying its graph, wired into
  LLVM's graph algorithms through the carried `scc_iterator` patch
  (C114); `Lattice` and `Summary` concepts, an exact solve and a budgeted
  one two types (C15); direction and every other choice as a type, never
  a `bool` (C120); one fold over each closed sum (libc++'s `std::visit`
  cliff above eleven alternatives, `wave1/5.5-cxx26.md`,
  `libcxx/include/variant:1596-1607`; `TypeSwitch` banned with the
  ladders, C52); transfer functions and every callback as constrained
  template parameters; each summary problem one explicit instantiation
  behind `extern template`, the marking ordinary functions compiled once,
  its gates data (C34; B §2.9, C §2's table); quantity handles where
  counting builds IR (C119).
- **At run time**: nothing static built per function; no attribute or
  type made on a worker's hot path (C116); no pointer-keyed map per node;
  no per-query recomputation of a fact that can be numbered once (the
  linearity verifier numbering nothing on its success path, C41); arenas
  and per-run interning instead of context uniquing on hot paths; no
  recursion on the input's size (D33, C99); D41's template unable to
  branch or build poison (C110).
- **The compiler's own build** stays measured: a `-ftime-trace` baseline
  before the churn, a precompiled header of libc++, LLVM, MLIR and
  `IdrDialect.h` with none of our vocabulary headers (C53), explicit
  instantiation (lane 13, `wave1/5.5-cxx26.md` D6); a C++ feature only
  when the pinned clang and the typecheck host both have it (C9).
- **Assertions on** (D115, reversing D91; D114): the toolchain's LLVM
  and MLIR are built with them in every stage our code compiles against
  or links, and our compiler's C++ without `NDEBUG` to match, so the
  compiler shipped is the one the tests ran; our C++ asserts its
  invariants freely (C226), C++26 contracts once clang has them; the
  price is measured before the cutover lands
  (perf-sources U8).
- **Every surviving runtime dispatch is listed and justified** in the
  design document (L15 §2.10 adds five).
- **Its boundary** (L15 §2): four libraries layered by link dependency,
  `IdrSupport` naming nothing of the dialect (C243), D41's header naming no LLVM or MLIR (in
  `include/idr/IR/Numeric/`, which the runtime includes, C110), `IdrIR`
  holding the one place an IR-handle map lives (freed when its numbering
  is finished); ids minted only by their owner. *Corrected* (recheck 3,
  L14, C236): `IdrSolver`, the solver layer, is built over MLIR's own
  analyses and call graph (C33, C114), so it names MLIR; what it keeps
  is keyed by dense ids, never by an IR handle.

### 5.3 The dialect's surface (synthesis A)

- **Types.** Grades stay in types as `!idr.graded<uses, hold, T>` (D88,
  D90): uses, `once` or `many`, on every type (zero is absence), a value
  of a type that holds no reference and may be used many times being the
  bare type, the form upstream's ops take (C143); a hold
  only on a type that holds references, either `static` (never freed,
  shared by definition, so with no sharing level) or `counted` or
  `scoped` (freed by its count, or when its lifetime ends) with what is
  known of its sharing: nothing printed, `unique self` (its own family's
  cells, D70) or `unique deep` (everything it reaches). Who frees a value
  and what is known of its sharing are two axes, every combination
  meaningful, so no verifier rule hunts a bad one (D88); one algebra,
  its laws proven in the specification and printed as compile-time
  tables (D62, D88), one closed attribute with constexpr methods and no
  interface (C21). A lifetime is not part of the grade: it is a value of
  type `!idr.lifetime<view | room | cursor | home k>`, its kind what it
  is at run time, named by the op that made the value (D63, C140);
  where its memory comes from is the op that opens it, one per source
  (`idr.lifetime`, binding `view`; `idr.lifetime.home`, `.block`,
  `.stack`, `.chain`), every lifetime born decided (D93); this call's own
  `idr.activation` and a lend's lifetime are `view` (C145).
  `static` is graded from what a value holds (C86); static data reaching
  code that counts meets a copy specialized by hold, the runtime's
  static marker only past the budget (D89). A data type a family
  application `!idr.data<#F[ts]>` (D48), index variables as levels
  (C79), a group an SCC of instances with three member kinds (C80), its
  possible constructors, class and layout computed when it is made
  (C81), a run-time natural linked to its index term (D59); a token names
  the family applications and constructors whose cell it may be,
  `!idr.reuse_token<{#F[i] @C, ...}>` (C253), linear, either `counted unique deep`
  and never null or `counted` with no claim (C39);
  `!idr.dest` typed by a family application whose layout is a cell
  (C38); every type and attribute, the family attributes included, native
  in bytecode (C50).
- **Ops.** Defs printed flat from the Idris specification, one per op,
  the families' constants enums (C113); one op per semantics (189 ops
  become 166 by L13's count, before the ops C39, C65, C82, C83 and C90
  add: `cell.new` and `cell.stack` one class, one `lin.cast`, one
  `idr.crash` carrying its site and `io.exit` as terminators, one
  `io.clock <kind>` over four clocks and one file-times op, `divu` and
  `modu` to `arith` behind their guard, `delay` in the capture family,
  output composed, the four shifts kept; C23 to C26, C112); each op's
  legal stages as specification data (C28); no verifier that follows
  def-use chains. The match is a region per case to the lowering, each
  case ending by a yield, a jump or never and binding its scrutinee
  refined to a constructor set, its fields reads of that refined value
  (C19, D105), refinement scoped by `idr.assume`
  and carried across a rejoin by `idr.reindex` (C82, D58). Join points
  (D19): `idr.join` and `idr.loop`, one family (C65), promised where the
  program as written makes one and found beyond that by optimization
  (D75); `idr.jump` with typed arguments and erased index terms, its
  target upstream's builtin `token`, defined per target by the join op,
  which holds each target's argument types (D76); on upstream's early
  exit carried as `upstream/<NN>-early-exits/llvm.patch` with five fixes
  beside it, the encoding our variant of the PR's, moved to upstream's
  merged form only if that form keeps every fact (D82), and
  `match-and-counting.md` §5.4's second tier never built (D25, C93);
  lowered in one conversion with upstream's SCF patterns (C94).
- **Simplification.** One runtime fold read off the generated ABI
  table, replacing 38 hand folders (`ToIntOp::fold` the 38th, L13); no
  greedy rewriter where our ops are (D98: the e-graph pass replaces
  canonicalize and CSE, our ops carry no canonicalization pattern, C47
  and C48 superseded), nothing at the points that hold upstream's ops
  only (D100), and the driver inside upstream's own passes left as it is
  (D99); no pattern rooted at every op; an op's fold stays its meaning,
  read by the e-graph and by `createOrFold` (D98). Search over the
  legal choices, equality saturation among them, is D57's, narrow
  (D106): its rules are today's local patterns with the choice per arm,
  algebra one-way and narrowly triggered. The optimizer's e-graph is C++
  over MLIR's ops (D107, D109): a pass with its own typed tables, our
  own solver in the solver layer, `egraph.md`'s Tier 1 narrowed, rules
  applied at insertion, folds called with constant operands only, D41's
  templates as its analyses (C153); its rules and laws are data of the
  dialect's Idris specification, generated into the C++, never run in
  Idris (D107, D109); the constant-triggered rule families are cases of
  D41's template, and no rule synthesizer is kept (C155). Effectful ops
  stay in a skeleton that is a partial order per resource (D103, C151);
  a call is deleted or floated only if its row carries neither `crash`
  nor `divergence` (D102); a function's budget is B nodes per op, the
  worker pool admitting functions while their arenas fit the host's
  memory, so output never varies by machine (D108).
- **Verification.** Local and parallel per function: no name without a
  body can be written (D48), the program verifier's walk for it gone;
  each function's verifier checks its row's containment and its cases'
  refinements in one fused walk numbering ops once; one linearity
  verifier (C41); grades still checked after every pass (AGENTS.md) and
  kept by construction through the one clone-and-key template (C36),
  since the verifier checks a quantity's use, never that a pass kept it
  (L20 §1.1).
- **Arrays** (D42, D43, D60; L12 §2): destination-style `tabulate`,
  `fold_last` and `scan_last`, each with a tensor and a buffer form,
  implementing three `TilingInterface` methods and declaring iterator
  types from their regions' effects (C107); value arrays tensors, array
  fields buffers through `to_buffer` and `to_tensor restrict`, writable
  only for an exclusive scrutinee (C105); `LArray` and `Linear.Vec`
  `in_place` types, exclusive by construction, so bufferization reads
  their grade and never searches for links (D71); a linear array's read
  gives back a new array value, as Idris's type says, so a read stays
  before the in-place write that consumes the array by data dependence,
  never by the order of ops (C150); `IOArray` and `IORef`
  memory in `#idr.mutable` at `index` coordinates (C109); One-Shot
  bufferizing graded tensors through patches 27 and 64 (C108);
  `lowerToLoopsUsingSCFForOp` right before `idr-lower`; a size a call
  fixes keyed by its index term, so a specialized copy's tensor types
  are static where the term is a constant, and equalities inside a
  function run-time ties, `idr.tie_shape` (D60); `transpose` as C27
  says; each extern one registry row naming its specification op or
  composition (C6).
- **Its boundary** (L04 §2, L09 §2, L13 §2): families with six normal
  forms of index term (`nat`, `var`, `succ`, `lit`, `con`, `opaque`) and
  one unifier and one substitution utility for the verifier, the
  specializer and the inliner; control flow as regions to the lowering,
  upstream's analyses reading jumps through the carried PR; ops whose
  meaning is `Runtime | Inline | HandFolder | NoFold`, `divs`, `mods`,
  the four shifts, the char conversions and three guard conditions each
  one D41 template, the e-graph's constant-triggered rule families among
  its cases (C155).

### 5.4 The analyses and the solver layer (synthesis B)

- **Upstream's framework**, its storage patched upstream and measured
  first (bytes per anchor on all four targets), used where a fact is per
  value inside one function (idr-constants, narrowing's per-loop copy,
  Ranges per function with callees-first return and callers-first
  argument summaries); Returned deleted, its fact carried per result
  field path on the function (C18, C32).
- **One call graph** (C33): a carried patch to `mlir::CallGraph` first;
  dense ids fixed for the analysis's life, rows of `(callee, tail kind,
  sites)`, SCCs as ranges of one permutation; frozen for readers, edited
  only through one restructuring pass's editor and refrozen, preserved
  across nested groups by the carried adaptor patch (C114), none after
  lowering; it deletes `CallCycles`, `Recursion`, the caller-only symbol
  maps and the optimizer's second walk. The optimizer is its one dynamic
  client.
- **Three solve shapes**: per function (upstream's framework, summaries
  at calls); summaries over the call graph's SCCs, callees first and
  callers first; extract, solve, write back (the label solve,
  exclusivity, allocation into a lifetime, deduplication). Every answer
  is then carried (a type, a property, the op), and the first question
  is whether the dialect can carry a fact so that no pass solves for it
  (L14 §1.2).
- **The solver layer as shared types, not one engine**: exclusivity's
  gates, the label solve's growing graph and the optimizer's merges each
  fail to fit a single engine (B §3.2); the marking's four clients share
  one compiled loop with gates as data (C34). The e-graph is equality
  saturation's alone, a C++ pass with its own typed tables, our own
  solver in this layer (§5.3; C153, D107), not a solver for every
  analysis; nothing optimizes on the Idris side (D109).
- **Threading**: decide, apply, restructure (lane 13): whole-program
  facts computed once by decide steps, which make every type and
  attribute their answer needs serially (C116), read through a const view
  by nested function passes the pass manager runs in parallel; transform
  units are MLIR actions, solve units trace zones never skippable (C115;
  "every solve unit an action" is refuted, L14 §1.2); output
  byte-identical at any thread count (C16).
- **Its boundary** (L14 §2): one program-graph index from
  defunctionalization to `idr-lower`; each pass declaring `keeps | edits
  | invalidates` in its specification record; an analysis declaring its
  reads as a type (C34); a fact decidable from checked TT computed in
  Idris (C118).

### 5.5 Memory and the back end (synthesis C)

- **Perceus as MLIR passes**, on the grades already in types: function
  types are counting's ABI; placement, exclusivity, reuse and the take's
  expansion, in that order (C1); one reverse walk per function places
  dups and drops over quantity-many values (C87); drop specialization and
  reuse written into the IR where they are decided; runs and coalescing
  within D26 (C88).
- **Uniqueness a two-region match**: `idr.match_unique`, folded by grade
  (`counted unique deep` to its unique region, a value `scoped` to this
  call's lifetime to its shared one), so only an unproved `counted`
  value is tested at run time; reuse tokens linear, `counted unique
  deep` (never null) or `counted`; the take's expansion is counting's
  last step at the `idr` level, and the lowering decides nothing (C39).
- **The in-place promise before the optimizer** (D24): decided by
  `idr-in-place` right after defunctionalization and idr-knots (C90);
  the obligation is the grade `!idr.graded<once, counted unique self,
  T>` in the function type, exclusivity of the family's own cells only
  (D70, D90), reaching every value of an `in_place` type bound at
  quantity 1 (D72), and each rebuild a linear token consumed by
  `idr.rebuild`; counting lowers them and never pairs a promised cell; a
  use counts only if it may still hold the value at the rebuild (D79);
  a call the check cannot prove exclusive is refused at the user's
  call.
- **Four marking clients, one template** (C34): exclusivity (by context
  mask, its domain what QTT and freshness do not settle; C36, C92),
  allocation into a lifetime (per function, callees first), borrows (C1)
  and the obligation closure (C90), over compressed-row graphs, gates as
  data.
- **Lifetimes** (D39, D63, D88 to D90, D93 to D96; L05 §2): a lifetime
  is a value of type `!idr.lifetime<view | room | cursor | home k>`,
  its kind what it is at run time (`view` no value, nothing allocates
  into it; `room` a block of static size, a pointer in; `cursor` an
  unbounded bump, a pointer in and out; `home k` the per-shard home of
  site k, no value), read in zero steps by every allocation, callee,
  frame, copy and the lowering. Where its memory comes from is the op
  that opens it, one per source: `idr.lifetime` (binding `view`, its
  region the lifetime's extent), `idr.lifetime.home`, `.block`,
  `.stack`, `.chain`; one decide step writes every opener, kind,
  signature and copy, so no lifetime reaches the IR undecided (D93). A
  `view` parameter accepts a lifetime of any kind, and the pure cast
  `idr.lifetime.forget` gives an operand's `view`; every other kind is
  passed only to itself, a mode copy's function type its key (D93).
  `.stack` and `.chain` give one kind, `cursor` (C147); `home k`'s k is
  a dense number per home site (C148); a caller holding a `cursor` that
  calls a `room` copy writes `idr.lifetime.reserve` (C146). How much a
  function puts into a lifetime parameter (`Finite n | Unbounded`) is a
  per-parameter part of `idr.func` beside D61's, derived callees first,
  checked per function, no effect and never copied onto calls (D94). A
  function takes a lifetime as an argument and a call passes it as an
  operand; it is the arena handle where a function allocates into it
  and erased elsewhere (D63), and the op that makes a view or allocates
  names it, so no check follows a def-use chain (C140). This call's own
  `idr.activation` and an `idr.lend`'s lifetime are `view` (C145);
  `idr.lend` lends a counted value for a region and gives its owner back
  (C83, named by D90). A view and a cell allocated into a lifetime are
  one hold, `scoped` (D88); every cell of a lexical lifetime, this
  call's included, is uncounted and freed when its lifetime ends, with
  no stack bit (D78); a borrow's validity rests on its lifetime (D73).
  Cells from `cell.new` (counted), `cell.stack`, `cell.arena` and
  `cell.recycle` (counted only); each lifetime's D26 proof a local
  verifier rule (C84). No lifetime region holds a call in tail position
  and none is handed over at one: every lifetime ends in the function
  that opened it (C84, C97, D96). A lifetime may span a call on its
  function's cycle, one per recursion level, `.stack` or `.chain`,
  packed into a linear value before the push and opened afresh at the
  resume (D95). Views read the lending region's row (C85). The rest is
  `design/lifetimes/`'s (`lowering.md` for D93 to D96).
- **The runtime**: one entry per kind of word (cell, maybe-cell, big;
  C40), counts over runs of slots, two token frees and `is_unique` as
  "count is 1" for counted values (C39); one generated ending and one
  program record (C101); one out-of-memory path through snmalloc's
  failure continuation and a limit range in its pipe (C103, D65),
  snmalloc's fatal errors as internal errors (C8); a heap span with a
  bounded page map, commits reporting failure (C100); no stack probes in
  compiled code, only the runtime and what it links taking stack-clash
  protection (C59, D77); the small stack charged when its thread starts
  (D66); crash causes as enum values with sites as properties (C102), a
  function's name in a cause as data (D80); a reader going away ending
  the program by `SIGPIPE`, every other file flushed (D81); effects
  mapped onto runtime calls; the arena's entries (L05 §2.8).
- **Tail position one fact**: `TailKind` on `idr.call`, verified by the
  function's verifier, lowered as `musttail` under `tailcc` (D30, C20);
  one definition of tail position, used by the frontend and by every
  pass that moves a call, which rewrites the call's tail fact through it
  (C139); no operand's lifetime ends with a tail call (C97). Frames a D48 family with a linear frame-stack layout, after
  counting and TRMC (C96). The native stack's bound computed on the final
  module with a build-time check of every cycle (C98). Tail recursion
  modulo context read before counting (C38).
- **Its boundary** (L07 §2, L08 §2, L10 §2, L11 §2): counting's passes in
  order (cells, allocation into a lifetime, borrows, placement with drop
  specialization, exclusivity's commit, the reuse walk, the take's
  expansion); the in-place rule's boundary tests B1 to B20 (L08); the
  stack laid out `[guard | stack | guard | signal stack]`; the host's
  facts read once behind the OS units.

### 5.6 The Idris side (synthesis D)

- **Representation, never optimization** (D109): the Idris side holds
  the frontend's checking, elaboration and representation decisions,
  the dialect's specification (each op's rules and laws among its data,
  generated into the C++, never run in Idris) and the libraries; every
  pass that makes code faster or smaller is C++ over MLIR.
- **The TTC keeps every fact a reader rebuilds** (the types of a `let`,
  a `PLet` and a `PVTy`, a match's scrutinee type, a leaf's clause index,
  each clause's builder patterns, why a term is erased, a block's typed
  parent (C129), imports, pragma uses, the inserted `Delay` (C124)), each
  one change that deletes its reader; a module's package and the main
  source path are the session's and the driver's (L16 §1.3, L17 §2.2).
- **Read once into typed tables**: erasure decided once from Idris's
  checked quantities on the binders of a definition's normal form, three
  kinds of position (C122, D59); one table per definition, type
  constructor and constructor; the registry resolved once; one dense
  identity per instance; one representation of a static argument (C123).
- **Typed builders and a native handoff**: values as numbers, ops
  indexed by their group counts with one argument per operand group
  (C51), primitives through one generic builder over the
  specification's op value, each registry row naming its op (C6 as
  replaced); every `idr` type and attribute native in
  bytecode (C50); specgen printing the `idr` builders and encoders, and
  D51's one backend reading upstream's records (L03 §1.3).
- **The checks stay where they are** (no budget, no `covering`), with
  their answers returned as values, `Template` indexed by its stage, one
  numbering; a decision only proofs read is erased (C123).
- **Emit counts nothing** (C14): substitution respects quantities and a
  parameter keeps its Pi binder's quantity; refusals are ops (C58);
  termination per Idris component (C74); a `Nat` literal read once at
  the boundary and emitted as one constant of its representation, never
  a chain of `idr.big.add` (D105); a linear array's read gives back the
  array it threads (C150).
- **The fork**: every count classified, those deciding acceptance gone
  (D53 to D55, C66, C126 to C128); one POSIX path model (C125); its
  carried diffs checked against the pin (C129); `WithBounds` a sum,
  `Irrelevant val | Relevant val bounds`, in place of its `Bool` (D101).
- **The elaborator's union-find** (D69's O7): its own, in Idris, for
  unification and the constraint store, which merge and never search;
  R4 in P0 is no more than that (D107). It shares no rule with the
  optimizer: the specification's rules and laws are generated into the
  C++ alone and never run in Idris (D109).
- **The libraries** (D101, D109): `mlir-array` and `mlir-linear` are
  reshaped by hard cutover wherever the compiler's use calls for it,
  with no compatibility; a linear parser's input is a quantity-1 handle
  to immutable bytes, its reads with no resource, tokens views scoped by
  a lifetime, the failure result handing the handle back (D104); a body
  the stock host runs decides with evidence at quantity 0, never a proof
  built at run time (C154).
- **Lands with the specification change that regenerates it**, inside
  the subset both hosts compile; under D56 the whole is one change (L03
  §1.3, L16 §1.3).
- **Its boundary** (L16 §2, L17 §2): the frontend reads checked TT
  through the fork's TTC once into typed tables; growth admission is a
  value carrying an erased derivation over the code's `Template`, with no
  run-time witness, the fork's normaliser covered by one stated trust in
  `Idris.Host` (D68); Emit writes D48's families, index parameters and
  arguments (a run-time value in an index position keeping its term,
  D59), each quantity-1 value's uses as `once` (`!idr.graded<once, …>`,
  D90), refusal ops and the termination fact, with no world, no
  `!idr.box` and no `idr` text.

## 6. What goes

Every step culls what it replaces (D6). By area, the lanes' deletion
lists (each document's section 7) hold the symbols; the largest:
- **Effects**: every reading but the one API (§5.1; L02 §1.4 lists them).
- **Types and ops**: the grade's free enums and functions; the kind and
  role table; `ValueFacts`' 55 hand answers; the marker traits no reader
  needs; the hand `def`s of family members; `own.adopt` and `own.give`'s
  def-use verifiers; 38 hand folders; the `#idr.types` table,
  `MutableType` and sealing, `DataRemap`, `Declarations`, `DataBody.cpp`,
  `Fit.cpp`, `!idr.box`, `Idr_SumKind`, `Idr_CtorRole` (L04 §2.18); the
  `tag` attributes (C19); lifetime variables in types and their binders
  (D63); today's grade, its three fields and every spelling of them,
  with each verifier rule that hunted a bad combination, and the view
  and frame-lifetime op names, none kept as an alias (D88, D90).
- **Analyses**: `CallCycles`, `Recursion`, seven caller-only symbol maps,
  every function membership, number or callers map by name or by pointer
  (twelve and four, L14 §1.4), `Scc.cpp`'s three graph copies, the dead
  worklists, `MonotoneWorklist`, `FiniteLattice`,
  `lib/Analysis/Effects.cpp`, Returned's whole-module solve, each
  solver's private graph and numbering.
- **Counting**: `Classes` and its switches, `Placement`'s per-region use
  scans, Reshape's take-apart predictors, Reuses' simulated body, the
  second exclusivity solve; `Demand.cpp` whole, `Uses.cpp`, `Take.cpp`,
  `unknownFrom`, `givesExclusive` and `copyable`, Borrows' framework
  state, `madeStatic` and `isStatic`, `idr-rc-stack`'s whole-program
  graph, `Owned*.cpp` (L05 §2.10, L07 §2.15, L08 §2.7).
- **Control flow and tail calls**: contification's single-site rule and
  workarounds, `Tail/Loop.cpp`, `Tail/WhileDo.cpp`, case-of-case's
  whole-consumer copy, the three enclosing-match walks, the poison yields
  (L09 §2.11); the two definitions of tail position and the four cycle
  deciders, `Frame.cpp`, frames' answer sum (L10).
- **Lowering and runtime**: the uniqueness branches in C++, the
  `Fields` side table, the per-site crash strings, the NULL and odd-bit
  tests on typed words, the element take's test, `LowerDrop`'s token
  branch, the `Status` root and the hard `idris-mlir:` prefix,
  `heapRegion` and the 4 GiB reservation, the live-cell counter in
  shipped programs and in the compiler's folders (L07, L11 §2.10); the
  stack bit in every header and each run-time test of it (D78).
- **Simplification**: upstream's canonicalize and CSE at every point,
  our three calls of the greedy driver, the ten
  `getCanonicalizationPatterns` hooks and about 1,744 lines of `Canon/`
  patterns the e-graph pass replaces (D98, D100; `payoffs.md` §5).
- **Frontend representation bugs**: a `Nat` literal as a chain of
  additions, a case that binds its fields without its refined
  scrutinee (D105), a linear read that gives back the array it read
  from (C150); the fork's `WithBounds` flag (D101).
- **Arrays**: `Nests.cpp` whole, `GeneratingOpInterface`, `Idr_Iteration`,
  `TabulateIOOp`, `TransposeOp`, `ElementUpdateOp`, `StoreModel`,
  `HeapReadModel`, `UseModel`, `heldType`, `DataRemap`'s buffers block,
  `merge`'s identity entry (L12 §2.7).
- **Idris side**: `Translate/Forced.idr`, the five erasure readers, the
  string-keyed maps, the copied format parser's `idr` use (it stays in
  D51's backend, C50), the Idris printers of our types, `idr.refusals` as
  a discardable attribute, `Registered.Newtype`, `Facts.terminating`,
  `delayedLets`' blanket move, decimal doubles, `Finite.heightWithin` and
  kin (L16 §2.6); in the fork, the run-time tree and `PartialEval.idr`,
  the never-started timer, the count pragmas' machinery and the path
  model's Windows forms (L17 §2.8).
- **Process**: the pipeline order held twice; pass names in tests; the
  dead `remove-dead-values` registration; patches that reach nothing
  (06, 28, 63), retired (C35); the bench's raised `ulimit -s`, the stale
  "1 MiB" test comments, `defunc-tag-limit`'s awk generator (L19 §2.9);
  `LLVM_ENABLE_ASSERTIONS=OFF` and our `NDEBUG` (D115).

## 7. Execution: one cutover, in dependency order

The shape is D56's: the whole cutover is written at once by owned lanes
against §5's contracts, then built and qualified on all four targets as
one change. The stages below are the order in which the lanes' work
depends on itself, never gates; synthesis E's **infrastructure first**,
on which lanes 13, 19, 20 and 21 converge, survives as that order:
- **S0. Settle and fix the tree** (no compiler code): §4's open
  decisions, the starting commit, the corrected records (PINS.md, the
  upstream table); every dependency fast-forwarded to its latest, the
  toolchain's LLVM and MLIR built with assertions in every stage
  (D115), the carried patches rebased or dropped, and PR #166688 carried
  on the new pin,
  rebased by hand (five hunks fail `git apply` at the pin) with C93's
  five fixes beside it (D25); the checkout's `tests/spec/` and
  `tests/build`, which stop the test runner starting (L19 §1.18).
- **S1. Scale fixtures as tests**: Idris generators asserting scaling
  relations, a `threads` one among them (C133), and a per-target
  `musttail` matrix (C98). The 20,000-case match is not in the tree, and
  `tests/defunc-tag-limit`'s 65,536 labels only check that a pass
  finishes (L19 §1.15).
- **S2. Tests that survive the cutover**: the pipeline as one generated
  list (C28); stage-scoped properties and the promises as universal ones
  (C130); the runtime's one ending record (C101); idr-expect generated
  from Idris records; the invariant set as typed behaviour (C131): 235
  program tests (234 with cases, 907 cases), 47 rejects each with its
  `near/`, 144 `semantics@` runs, the 30 benchmarks' outputs, the fuzz
  seeds, changed only in the change of a ruling that changes what a run
  shows (D13, D37, D38, D64, D80); acceptance under every optimization skip
  (C132); the runner on both hosts (C134).
- **S3. Upstream trials, each measured**: the storage patch on Ranges and
  Borrows (Returned is deleted, C32); `remove-dead-values` per function
  with its fixes (C35); the assertions' price, stage 1 against an
  assertions-off MLIR at the same commit (D115, perf-sources U8).
- **S4. The solver layer's spine**: the shared types, the call graph as a
  carried patch (C33, C114), the marking's four clients.
- **S5. The dialect redesign from the Idris specification (D16) and its
  fixtures**, the effect system first (§5.1).
- **S6. Pass redesigns** as decide, apply, restructure, in lane 13's
  order (counting, arrays, tail, optimize, defunctionalization),
  acceptance before optimization (C68, C90); first among them the
  e-graph pass that replaces the greedy rewriter (D98), a C++ pass with
  its own typed tables over MLIR's ops (C153), its rules generated from
  the specification (D106, D107, D109). Beside them, the libraries
  reshaped by hard cutover (D101): `mlir-array`'s linear array read gives
  back a new array (C150), the parser input as a quantity-1 handle to
  immutable bytes with views (D104), the fork's `WithBounds` a sum.
- **S7. Verification re-priced, the build, a hard cleanup**; then 0001
  S4.

**D44's absorbed work** (C136; L16 §2.9 places each item, review §9.1):
0003's 62 items, 0011 whole with O6 and O7 (D69), 0010's A0, 0015's R1,
R2 and R4, and 0009's plain-Idris layer, each written by an owned lane
beside the S-stages:
- F0 (with S0): 0011's baseline record; the package and main path facts.
- F1 (S3, S4): the TTC facts.
- F2 to F5: the typed tables and `Signature`; one instance identity; the
  classification memo; linearity by construction (C14).
- F6: A0's reader side (interned names, the term arena as columns, in
  the fork).
- F7: D46's derivation.
- F8 (S5): D50, D48, and 0011's O2, which is the Emit of the new dialect.
- F9 (S6, S7): R1 and R2 in `libs/mlir-relational`, then O3 (the
  translation as semi-naive evaluation over the instance table) and O8;
  O1 and O5 (the flat parse tree, D125) with the checker.
Their bars are their proposals', ratios measured natively once `make
self` holds; R1's (bumbledb's Rust engine) and R2's (Soufflé) depend on
engines outside the toolchain. 0011's O6 and O7 come in with what they
stand on (D69): O6 with 0009's plain-Idris layer (its stage 7), O7 with
its own union-find in the frontend, which is R4's part in P0 (D107). Each absorbed proposal
is amended in the same change (D44, D69), 0011's rule skipping a stage
under 5% among them (C142).

**No step gate** (D56; DP-07's strike): no step is built, typechecked or
run on its own. The cutover lands only built, run and passing on all four
targets (AGENTS.md); each area deletes what it replaces; an adoption or
removal of upstream code carries its measurement in its record, taken in
the qualification (AGENTS.md's order). The old gate's "invariant set
unchanged" cannot hold across D13, D37, D38, D64 and D80 and is replaced by
C131 (L06 M8, L19 §1.16).

## 8. Suspected bugs found by the audit

Read in code, none reproduced unless marked. Under C8 and D56 each is
folded into the cutover with its cause and reproduced in its
qualification, then recorded in `audits/bugs.md`.

| area | what | where | lanes |
| --- | --- | --- | --- |
| acceptance | the in-place promise depends on whether reuse or stack placement ran, on an optimization deciding a dup, on the inliner's cap on case blocks, on borrow inference and on dead-code deletion; the stack inference runs before exclusivity and ignores the promise | `Demand.cpp:59-77`, `Reuse.cpp`, `Stack.cpp:116-269, 344-353`, `Reshape.cpp:149-210`, `Contify.cpp:22-25`, `Pipeline.cpp:38-41` | 08 NQ1; C #1; L05 §1 D24; L08 §1.1 |
| exclusivity | a crash case counts as an unknown predecessor, so every live crash case shares all its match's results (`bump1 (bump1 …)` with a partial `bump1` refused) | `ExclusivityGraph.cpp:208-222` | 07 G-09; B, C #2; L08 §1.6; L20 I3 |
| effects | a function's summary ignores its ops: a handle-table read lost at the boundary; `exit` claims to return; memo state carried by no bit | `Func.cpp:189-202`, `Call.cpp:65-72` | 02 §3.7; A B1–B3; L02 §1.4 |
| effects | ten IO ops declare no `IOResource`; declarations that do not state their runtime function: `handle.string`'s crash, `array.set`'s and `array.new`'s count writes, `array.yield` and `own.adopt` declared pure, `nat.from_big`'s allocation never made (closures' allocation is right under C3) | the op `.td` files; `IdrPlatformOps.td:365-367`, `Arrays.cpp:110-150, 211-223`, `IdrArrayOps.td:215`, `IdrOwnershipOps.td:357`, `Big/Arithmetic.cpp:64-69` | 02; A B5, B8; L01 §1.9, §1.10 |
| effects (latent) | an `Allocate` on a linear value reads as fresh memory to upstream's alias analysis | `LocalAliasAnalysis.cpp:240-292, 403-421` | L01 §1.1 |
| effects (design) | the designed lowering gives a row `memory(none)` (two calls merged across an in-place rebuild print 2, not 3) and an IO row `willreturn` | `design/effect-vocabulary.md` §7.1, `design/effects.md` 1.9 | L02 F1, F2 |
| primitives | Euclidean division written three times, the total shifts and the char conversions' scalar test twice; `ToIntOp::fold` a second meaning of truncation; three guards' conditions written three times | `IR/Ops.cpp:207-223, 256-276`, `Conversion/Scalars.cpp:61-104, 115-160, 182-184`, `runtime/Big/Arithmetic.cpp:20-33`, `IR/OpsScalars.cpp:31, 66-75`, `OpsChecks.cpp:22-61, 130-168`, `Conversion/Checks.cpp:43-97` | 03 O-47, 12 T12; L13 §1.4; L15 §1.6 |
| dialect | `delay` lacks the capture rule, so a linear capture loses its quantity; `idr.dup` accepts a quantity-1 view, two linear owners of one cell | `IdrClosureOps.td:72-80`; `IdrOwnershipOps.td:57-58, 74`, `Grades.cpp:85-91` | L13 §1.8; L20 I2 |
| dialect | (void: its cause goes with D48) `DataRemap`'s content keys drop the grade's lifetime | `DataRemap.cpp:43-48` | 01 T27; L04 §1.3 |
| Idris side | valid programs refused: a `let` value's type, and a `PLet`'s and `PVTy`'s, is dropped by the TTC | `Terms.idr:261-280, 402`, `TTC.idr:480-495, 611-620` | 17 FB-01; D #1; L16 §1.1; L17 §1.2 |
| Idris side | erasure decided five ways with different defaults; a block's parent kept as printed text, its `Int` a session-wide counter | the five readers; `Name.idr:45-46`, `Core/UnifyState.idr:193-209` | 17 FB-15, FB-10; L17 §1.2 |
| Idris side | Emit demotes a quantity-1 binder used twice, a parameter included, while the function type keeps `!idr.lin`; the verifier checks use, never that a pass kept a grade, and `quantities-kept` keys by location, dropping collisions; every `LArray.read` and `shape` meets the demotion | `Emit/Bodies.idr:56, 139-146`, `Emit/Declarations.idr:44-45`, `Expect/Quantities.cpp:3-19`, `Translate/Terms.idr:1570-1589` | 17 FB-28, FB-31; L20 §1.1; L12 §3.1 |
| Idris side | termination composes unsoundly under specialization (an unused looping call is deleted); `delayedLets` moves an explicit `let` (`f (let x = loop 0 in Delay 3)` prints 0); doubles cross the handoff as host-printed text | `Facts.idr:13-17`, `Emit/Closures.idr:89-93`, `Func.cpp:189-201`; `Translate/Closed.idr:184-197`; `MLIR/Text.idr:129-142` | L16 §1.1, I1, I6; 14 X01 |
| optimizer | nondeterminism: a lift depends on the order workers take a lock | `Requests.cpp:91-104` | 09 OPT-48; L18 §1.2 |
| optimizer | inlining edits a function outside a pass, so its output is verified only after the next inner pass (attribution, not correctness: CSE reads no stale dominance, `Pass.cpp:673-679`) | `Component.cpp:73-81` | 09 OPT-14; L18 §1.2 |
| optimizer | `absorb` clears `total` on every inline and contification, losing `mustprogress` and the deletion the row licenses (D102); a capture-free suspension is folded into a static memo cell that lives until exit; deduplication before the label solve can add a knot refusal; seven tests refuse a choice among implementations the program fixes | `IdrOps.td:181`, `Inline.cpp:156`, `Contify.cpp:109`; `OpsClosures.cpp:159-165`, `OpsCon.cpp:108-120`; `Pipeline.cpp:62-71`; `IdrBase.td:192-202` | L18 §1.1 |
| counting | unrestricted borrows hold a dead array or string across the callee's allocations; a region ending in a crash gets no drops, so an allocating crash path holds everything from outside it; a take of a frame value tests uniqueness, always false; a token free makes three tests; a recycle re-tests the take; an element update frees then allocates the same layout | `Borrows.cpp:3-26`; `Placement.cpp:201`, `Reshape.cpp:78, 83, 97, 104, 280`; `Counting.cpp:91`; `runtime/Rc/Counting.cpp:67-74`; `Cells.cpp:128-140`; `Arrays.cpp:253, 263`, `Elements.cpp:46-49, 75-79` | L07 §1.1, §1.6 |
| analyses | Borrows' solve result is dropped in release behind `[[maybe_unused]]` and an `assert`, and its `own` recurses along a definition chain | `Ownership/Borrows.cpp:272-288, 303-304` | L14 §1.4, I10 |
| control flow | three walks rebuild a match's refined constructor, each with its own identity rule; contification leaves a second block in a function body before the lowering | `OpsMatch.cpp:78-94`, `OpsConReads.cpp:123-138`, `Eta.cpp:39-47`; `Contify.cpp:34-42, 119-121` | L09 §1.1 |
| tail calls | idr-returned-arguments drops a tail callee's result but not its caller's, so a mutual recursion grows a native frame per round | `ReturnedArguments.cpp:59-82` | L10 I-2 |
| frames | a linear value loses its quantity at a frame's push, `heldAs` re-asserting it at the pop (`withFile h` can be closed twice) | `Frames.cpp:243-244`, `FramesTypes.cpp:91` | L10 §1 D31 |
| arrays | every linear array read from a cell is a writable root, so a shared record's array bound at quantity 1 is written in place (prints `5`, `5` where `5`, `0` is meant) | `Bufferize/Linear.cpp:91`, `Data.cpp:14-16`, `Grades.cpp:253-260` | L12 I1 |
| arrays | `merge` treated as an identity drops its extents: an empty frame's shape reads `[<0, 0]`, not `[<0, k]` | `Registry/Entry.idr:285-289`, `Recognized.idr:147`, `Nests.cpp:141-151` | L12 §1.5 |
| lowering | crash sites read from `Location` merge under `MergeIdenticalRegions` (reachability unverified) | `Conversion/Runtime.cpp:42-43`, `Canon/Merge.cpp:36, 48` | L13 I3 |
| runtime | no stack probes; the 1 MiB guard sits directly above the writable signal stack; reaching the guard prints "stack exhausted" with status 1 | `Runner.cpp:33-37, 71-72`, `Entry.cpp:77-80` | 18 R-STK-1, R-STK-2; L10; L19 §1.6 |
| runtime | snmalloc's own fatal errors abort without flushing, in another format, reached at the first allocation on any strict host (the 256 GiB page map); a refused commit is ignored | `Cells.cpp:51`, `pagemap.h:213, 221-224`, `pal_posix.h:189-201, 244-253` | 18 R-AL-3; L11 §1 D23, D35 |
| runtime | every program prints `idris-mlir:`; a crash loses buffered file output; four committed crashes have no site; `getString` crashes inside the runtime with no site | `Posix/Files.cpp:104`; `Ending.cpp:56-71`; `tests/buffer-range/cases/{below-zero,no-input,3,9}`; `Handles.cpp:233-243` | L11 §1 D37, D38 |
| driver | the deep-recursion stack covers the main thread only; pool workers get OS defaults (8 MiB on Darwin); goes with D33 and C43 | `Runner.cpp:44`, `Threading.cpp` | 13 DP-39; L10 §1 D33; L15 §1.3 |
| driver | the pipeline order is held twice and the copies disagree; the dead `remove-dead-values` is registered | `Passes.td`, `Pipeline.cpp` | 13 DP-01, DP-16 |
| canonicalization | `maxNumRewrites` unset: a pattern cycle hangs inside one iteration; the greedy driver goes where our ops are (D98) | `Pipeline.cpp:28-32` | 04 C60; L13 §1.2 |
| per-target | `OsOp::fold` falls back to the build machine's triple; the fork's path module reads every path with Windows's grammar on every target and tests the host's `os` at run time | `OpsPlatform.cpp:22-44`; `Libraries/Utils/Path.idr:28-34, 150-194, 237-245` | 03 O-81; 17 FB-48; L17 §1.4 |
| upstream | patch 27's README cites a test, `tests/upstream-one-shot-tensor-like-copy`, that does not exist | `upstream/27-one-shot-tensor-like-copy/README.md` | L12 §1.6 |
| counting | (fixed on main) `Positions` corrupted under counting's own rewrites, 67 programs | 101edbc5; fixed by 0be4e660 | 21 P-1 |

## 9. Alternatives rejected

- **Reverting the markings onto `DataFlowSolver` whole-program.** What
  left the framework is not per-value dataflow (B §1); the framework
  returns where its state fits, per function, after its storage patch.
- **One engine for every solver.** Exclusivity, the label solve and the
  optimizer each fail to fit one (B §3.2); the layer is shared types.
  The optimizer's e-graph is its own solver (C153).
- **Translating Idris's run-time case trees** (Q-FB1's option (a)):
  AGENTS.md forbids replacing checked TT with run-time case trees.
- **Verification split by build type** (Modular's practice): AGENTS.md
  verifies grades after every pass, and a behaviour chosen by the build
  is excluded; verification is made cheap by nesting instead, and the
  toolchain is one, built with its assertions on (D115).
- **A staged cutover**, with shims or with steps built on their own: D6,
  D56. The Idris side imports the specification's closed sets (D16,
  D50), so no copy of the dialect stands beside it.
- **A lifetime as a type parameter with binders, or as MLIR regions
  alone** (D39, D40 and D48 as first written): D63, a lifetime is an SSA
  value.
- **A grade richer than Idris's** (an affine source quantity, a borrow
  quantity, a fractional permission, a semiring of lifetimes): D62; and
  one field mixing who frees a value with what is known of its sharing:
  D88.
- **A continuation type of our own for join points**: every operand of
  ours that accepts any type would accept it, while the verifier already
  refuses an escaping builtin `token` (D76).
- **One e-graph engine written once in Idris, printed as MLIR and
  shared with the elaborator, over a sparse tensor library** (D85 to
  D87): reversed by D107 ("the frontend stays the frontend, mlir stays
  mlir"); its design is kept in `design/egraph-full/`.
- **Effects inside the e-graph** (eggcc's threaded state): D103; no real
  case needs a cost-chosen order on one resource (C151).
- **The research `eqsat` dialect as the optimizer's e-graph**: C153.
- **A sentinel count marking static data**, which would write it: D89.
- **Stack probes in compiled code** (L10, L11): D77; **the computed
  stack committed page by page from a fault handler**: D66.
- **This document as a research record**: the research lives in
  `audits/p0/`; this file holds decisions.
