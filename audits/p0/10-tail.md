<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane `tail`: frames, accumulation, TRMC, tail loops, returned arguments, contification, the tail-call lowering

Status (2026-10-21): complete for wave 2, at e96bb991. Read-only: nothing
built or run; every count is a `grep` or `wc` over the source, with its
command.

**In short.** No part of this subsystem is a solver except `Returned`,
which is the whole-program `DataFlowSolver` shape §3 shows failing; it
should be a per-function upstream solve with summaries, seeded from what
idr-optimize already knows (D3). Frames' plan is a structural match, not a
per-point solve (§5.1 item 3 refuted); since 16005000 it clones per key,
and what is left a product is impossible cases, which a stack indexed by
the value a frame waits for makes unrepresentable (D2). Tail position is
the subsystem's central fact and it has no home: recomputed per query on
`idr`, redefined on the LLVM dialect, and "a tail call on a cycle" decided
four times, two of which must agree for constant stack (D1, NQ-1, NQ-2).
The five `isa<ReturnOp, YieldOp>` restate the `ReturnLike` both ops
declare (D5). Contify is the single-call-site case of Fluet and Weeks,
and regions are why (Q-O1). No budget anywhere (Q-llvm-2).

## 1. Reading notes

(written while reading the skill, AGENTS.md, the proposal, 0003 and the
lane README; filled in chunk by chunk)

**The skill and AGENTS.md** (*read*). The binding questions for this lane:
for every branch, `Maybe`, flag or "unknown" arm in the tail passes, what
representation makes the state impossible; a check whose result is thrown
away is a parse not yet written; a switch on a tag in more than one place
is a polymorphism not yet named; one fact, one place. "Map onto MLIR's
grain": shared shape is an interface (`RegionBranchOpInterface`,
`CallOpInterface`, `LoopLikeOpInterface`), never an `isa<A, B>` ladder;
`DataFlowSolver` for dataflow, `AnalysisManager` for cached analyses;
upstream dialects (`scf`, `cf`, `func`, `llvm`) before ours. AGENTS.md:
inlining, specialization and every pass that only makes code faster stop
at a budget at most and never reject; acceptance is a property of the
program; "a round count ... is never a reason to refuse a program"; no
per-target case outside the target's entry; no discardable-attribute fact;
`!idr.lin<T>` survives every pass and the verifier checks it after each.

**§2 (the brief).** Facts that name this subsystem:
- The pipeline order (*read*, §2 "The pipeline"): ... knots, effects,
  **contify**, optimize, symbol DCE, columns, canonicalize/CSE, structure
  loops, bufferize, **accumulate, frames**, counting (rc-cells, rc-stack,
  rc-grades, rc-exclusive), demand, **TRMC, tail loops**, narrow, lower to
  func/memref/vector, entry, vectorization, linalg to loops, upstream's
  LLVM lowering, **tail calls**. So the tail subsystem straddles counting:
  accumulate and frames before it, TRMC and tail loops after it, the
  tail-call lowering at the very end on the `llvm` dialect.
- "More [solvers] live inside passes (`Transforms/Stack`'s lifetime
  inference, **`Tail/Frames`'s plan**, `Optimize`'s demand)".
- "Still on upstream's dataflow framework": **`Transforms/Tail/Returned`**.
- Trait layer: "**four copies of `isa<ReturnOp, YieldOp>` in
  `Transforms/Tail`**" restating a trait class (to be checked).
- `lib/Support/Scc.cpp` holds an SCC utility (frames may use it).

**§3 (walls).** Row **16005000: `idr-frames`: 43 GB, "ours: a body cloned
per pair of member and result type"**. 16005000's title is "A component's
answer is data". The conjecture: walls of ours were each fixed by a
representation; e96bb991's lesson (an interface query per pair of
terminator and region successor, quadratic in a match's cases) applies to
any graph build in frames or contify.

**§4 (the bar).** Upstream as is, then upstream patched, then our own
solver in the solver layer with a header naming what upstream lacks. No
ladders; a ladder over ops is a trait or interface not declared.
Threaded by construction.

**§5.1 mlir-analysis.**
- A4/A6: `DataFlowSolver` costs ~2.9 KB per state at the pin (two
  64-bucket tables); a function-scoped solve (`top` = a function) is
  supported, and calls then go to `visitExternalCall`.
- 5.1.2 item 2: **`Tail/Returned` should return to the framework as a
  per-function solve** with interprocedural facts through
  `visitExternalCall`/`visitCallableOperation` from a module-level summary.
  Item 3: **`Tail/Frames`' plan stays ours** (per program point,
  set-valued), in the solver layer. (To check: is frames' plan really
  per-program-point and set-valued? See §3 of this document.)
- C1-C4: per-edge interface methods are O(1); `getPredecessors`,
  `getSuccessorOperandInputMapping()`, `isRepetitiveRegion` are O(N) per
  call on a match; a client builds an op's edge table once.
- Design 1 (recommended): patched framework (U1), per-function solves,
  one summary layer over call-graph SCCs; the summary layer iterates inside
  a recursive SCC "up to a budget that only leaves facts less precise".
- Wave-2 questions: **W1** (V, B, P, F), **W2** (each analysis's lattice,
  interprocedural or not, its summaries, Design 1 or 3; applies to
  `Tail/Returned` and frames' plan), **W3** (every call of
  `getPredecessors`, `getSuccessorOperandInputMapping()`, etc.), **W4**
  (`RecursiveMemoryEffects` ops), **W5** (attributes or types created on a
  hot path), **W6** (pass anchoring on functions), **W7** (callee
  resolution in a non-interprocedural backward solve).

**§5.2 mlir-ods.**
- M5: "four copies of `isa<ReturnOp, YieldOp>` are
  `hasTrait<OpTrait::ReturnLike>()` or
  `RegionBranchTerminatorOpInterface`" (to be checked against what our
  `ReturnOp` and `YieldOp` declare).
- E1/M6: `MatchAnyOpTypeTag` patterns cost ops x patterns; E3: the walk
  driver is the one-shot shape that terminates by construction.
- Recipe row 10: `ReturnLike`, `HasParent`, `ParentOneOf` replace
  `isa<ReturnOp, YieldOp>` and parent checks. Row 11: a shape several ops
  share is an `OpInterface`. Row 19: pass facts in `Passes.td`.
- H3/M11: a module pass re-verifies all 70,000 functions; function-nested
  passes verify their own function in parallel. Wave-2 W2 (every
  `MatchAnyOpTypeTag`), W3 (every `verify()`), W4 (every `isa<` over ops),
  W9 (passes that change nothing mark analyses preserved).

**§5.3 llvm.**
- B1/M1/I1: `isa<ReturnOp, YieldOp>` is not slow; it is a fact restated;
  the cure is `ReturnLike` (`ControlFlowInterfaces.td:638-640`).
- B3/I3: `get_if`/`holds_alternative` chains become one exhaustive
  `std::visit`; B4/I4: sums of handles are `PointerUnion`.
- B5/I5: a hot callback is a template; `function_ref` for cold ones.
- B7/I7: per-node state is a vector indexed by a dense number; a
  `DenseMap` per node costs >= 64 buckets.
- B8/I6: `scc_iterator` over `GraphTraits` instead of a hand SCC.
- S0: "before any solver, the representation that makes the solve
  unnecessary"; S1: the solver layer (dense `Node`, CSR `Graph`,
  `Lattice`/`Analysis` concepts, `Solution`, `mark`).
- M9 and **Q-llvm-2** (budgets in the solver layer: no budget for
  analyses a refusal rests on; optimization-only analyses may stop at a
  budget and take the pessimistic state; never an error). Frames, TRMC,
  accumulation and contification are optimization-only or ABI-level
  passes: whether any of them carries a cap, and whether any cap refuses,
  is this lane's evidence for Q-llvm-2.
- Wave-2 questions (5.3.4): every worklist, every per-node `DenseMap`,
  every `function_ref`, every variant, `Scc.cpp`, the seven
  `DataFlowSolver` files (S1 or S2), every mutex.

**§5.4 modular.**
- F3/Design 1: `SCCGraph`, one call-graph schedule for every summary
  analysis (callees-first, callers-first). F7/Design 4: region control
  flow as a table built once (`CFGAnalysis`). F8/Design 6: dead arguments
  as a bit per argument and result (relevant to ReturnedArguments: a
  per-argument summary, not per value).
- F17: no option selecting between two implementations.
- Wave-2: which analyses are summaries over the call graph and compute
  their own SCC order; where state is copied per region or per edge;
  "Whether our call op can implement upstream's `CallOpInterface`".

**§5.5 cxx26.** D1 (the boundary rule): dispatch over ops by interface
or trait, then typed code below; concepts may read ODS, never list ops.
D2: closed sums of our own types as `std::variant` plus one exhaustive
`match`; `holds_alternative`/`get_if` outside `match` are validators.
D3: solver state in `IndexVector<Id, T>` indexed by a typed id the graph
mints; transfer as a template parameter, not a `function_ref`. D4b: a
C++-only list is one `constexpr` table checked by `consteval`. D8:
`std::expected` where a failure is data; `zip_equal` over `zip`.
Wave-2: sort the `isa<>`s, variants (and their alternative counts),
`function_ref`s, virtuals and templates.

**§5.6 ecosystem.** Item 1: state only for what the problem is about.
Item 2 and Design 1: one `ProgramGraph`, kept up to date by **the passes
that change calls (defunctionalize, contify, inline, specialize, symbol
DCE)** and preserved by name. Item 5: a budget degrades a site and never
fails a pass. Item 6: extract, solve, write back (names **`Tail/Frames`'
plan** as fitting this shape). Item 8: a structured walk copying state
per branch is b8301ebe's wall; deltas per case remove it. Wave-2:
**W-E1** (analyses deriving call-graph or SCC facts on their own; passes
changing calls without telling anyone: contify is one), **W-E4**
(discardable-attribute facts), **W-E5** (every budget, round count,
cap, and whether it fails), **W-E6** (queries on a match that enumerate
its regions), **W-E7** (`DenseMap<Value, ...>` solver state), **W-E8**
(single-block regions after defunctionalization?), **W-E9** (state copied
per edge or branch).

**§5.7 library.** **M5: "`idr-frames` (43 GB) and the specializer walls
are clones materialized before they are deduplicated"**; **L5, clones as
keys**: "Specialization, frames and grade contexts first compute the set
of keys each function needs (a key is interned, so equal keys are one
id), then materialize each distinct key once; termination comes from
keys drawn from a finite alphabet, so a budget only ever limits
profitability. Made unrepresentable: two clones of one key". M3: an
interface queried once per op, kept as a flat edge array. L2's `Scope`.
Wave-2: "For each specializer: what its key is, whether keys come from a
finite alphabet, and whether any budget decides termination (L5)" (frames
is a specializer of this kind).

**§5.8 dialect-design.** T6: a function type carries conventions and
effects. O4: a lower form is another op (often another dialect), legal or
illegal through `ConversionTarget`, never a flag on the high one. DS4:
`func`, `call`, `return` become `func.*` unless `!idr.fn` carries
conventions; `match_lit` on words becomes `scf.index_switch`/`cf.switch`.
DD-Q7 (our own function op or `func.func`) bears on what the tail-call
lowering and frames read.

**§5.9 mlton (read most carefully).**
- **C3:** MLton's calls carry their continuation in the IR: `Return.t =
  Dead | NonTail {cont, handler} | Tail`: "tail position and exception
  routing are a sum in the call, never an analysis". This is the direct
  model for our `TailPosition.cpp` and any "is this call in tail
  position" query (to be checked: do we recompute it?).
- **E1, contification:** one whole-program graph over functions,
  continuations and a root (root to main, to every continuation, to every
  unreachable function, to every function called with a dead return;
  tail calls f->g; non-tail calls c->g), **one dominator tree**
  (`Graph.dominators`), each function's return read from its ancestor
  below the root: `Areturn = Uncalled | Unknown | Cont of Cont.t | Func
  of Func.t`; a function whose A is a continuation or another function
  is spliced into it as blocks; state is one record per function and per
  (label, handler) on plists; cost one graph build, one dominator
  computation, one rewrite; runs three times in the SSA list.
- **E2/E3:** the shrinker is the normal form each pass calls on what it
  rewrote.
- **F1:** the inliner's decision is a pure function of the call graph
  computed once before any rewrite; the budget only leaves code
  uninlined.
- **H (walls table), row 16005000 `idr-frames`:** "instances are
  demanded and cached per key (D1); differing representations meet at a
  coercion (D3), not a clone; a clone per pair has no counterpart".
- **M2:** e96bb991 and `idr-frames` are "a cost per pair (terminator and
  successor, member and result type) that MLton's flat case and demanded
  instances do not have".
- **Design 2** (`case` as a terminator after defunctionalization) lists
  as its cost: "structured passes that want regions (structure loops,
  **TRMC, frames**, counting's lexical scopes) either run before the
  lowering or recover structure from the CFG".
- **Q-O1** (owner): is the structured `match` kept past
  defunctionalization, and for which passes? This lane gives evidence on
  what accumulate, frames, TRMC, tail loops and contify read of the
  region structure.
- Wave-2 questions in this lane: **Q-W4** ("Which passes read the region
  structure of `match` (TRMC, frames, structure loops, counting's
  scopes), and could each run before Design 2's lowering or work on a
  CFG?"), **Q-W6** ("What liveness or last-use facts do ... demand and
  frames compute, per what"), **Q-W8** ("Does `contify` build one
  whole-program graph and one dominator tree, as Fluet and Weeks's
  algorithm does (E1), or something per function or iterated?"). Q-W2
  also touches frames' plan and the returned-arguments analysis.

**§5.10 rc.** **M10: "The order of our pipeline puts counting after
optimization and before TRMC; Koka puts TRMC before Perceus**
(`koka/src/Compile/Optimize.hs:108-109` runs `ctailOptimize` in core,
before code generation's Parc), and the ICFP 2022 paper credits the
combination of TRMC and reuse ... Wave 2 checks that our TRMC keeps the
reuse the counting passes set up." **W8** (rc's wave-2 list): "Whether
counting runs on `idr.match` regions (Perceus's tree) or on a CFG, and
whether TRMC, which runs after counting here and before it in Koka,
keeps the reuse counting set up (M10)." A5: frame-limited space (a
tail-position question: TRMC and frames change what a frame holds). B2:
Lean's borrow inference forces ownership for "self tail call, join-point
argument and tail call" (`OwnReason`): "a tail call must not be followed
by a `dec`" (a correctness fact at the tail/counting boundary).

**§5.11 oom.** Wave-2 item 4 ("Whether lowering sets `probe-stack`")
and item 7 ("Every solver and pass whose state is sized by a product of
two program quantities (A1): the next walls"). Frames was one such
(member x result type); the lane checks whether any product remains in
frames, TRMC, accumulation or tail loops. A4: budgets in program units
only.

**§8 (owner's questions) this lane bears on:** **Q-O1** (structured
match after defunctionalization: which of our passes read region
structure), **Q-llvm-2** (budgets: no budget where a refusal rests; a
spent optimization budget is the pessimistic state, never an error),
with Q-E3 and oom-2 ("answer with Q-llvm-2"); also Q-O3 (facts into
types: `givesBack`, tail position), Q-E2 (where a summary lives:
`Returned`'s per-function returned argument), DD-Q7 (our own function op
or `func.func`: what tail calls read), QA2 (per-function solves:
`Returned`).

**§9 decisions.** D1-D4: P0 first; our own solvers allowed, honestly
named; no code until the plan is approved.

**Proposal 0003 (facts once)**, items in this subsystem (*read*):
- "**Tail loops** (`Tail/Loop.cpp`, `WhileDo.cpp`) put the loop, its
  block arguments and yields at the function's location though the self
  call's and the match's are known. **Frames' resume cases**
  (`Frames.cpp`) at the member's, though the frame site's is known;
  `closureLabels` walks every value's type on every run though the sums
  are `TypeGraph::declarations()`."
- "**`givesBack` solved twice:** idr-optimize's summaries go at the
  pass's end and `Tail/Returned.cpp` solves it again on the lowered
  module. Carry it as LLVM's `returned`, and seed the lowered solve with
  it."
- "`Effects.cpp` preserves only `SymbolTable` though it writes only
  effects, so **Contify rebuilds `CallCycles`**."
- The static lifetime: "6f774119: a capture became non-static once
  idr-tail-loops moved its match into a loop" (a tail-loops rewrite that
  changed a fact other passes search for).
- Target lane: "Function facts not lowered" (`willreturn`, `mustprogress`)
  and "No stack probes" are lane 12's and 13's, but the tail-call lowering
  sits beside them.

## 2. What the subsystem is

### 2.1 Files and sizes

*Measured* at e96bb991 (`wc -l`; `bash -c 'wc -l <files>'`):

| file | lines | pass or role |
| --- | ---: | --- |
| `lib/Transforms/Tail/Frames.cpp` | 378 | `idr-frames` (rewrite) |
| `lib/Transforms/Tail/FramesPlan.cpp` | 198 | its plan |
| `lib/Transforms/Tail/FramesTypes.cpp` | 99 | its stack and answer data types |
| `lib/Transforms/Tail/Accumulate.cpp` | 215 | `idr-accumulate` (rewrite) |
| `lib/Transforms/Tail/AccumulatorPlan.cpp` | 230 | its plan, the countdown |
| `lib/Transforms/Tail/Trmc.cpp` | 271 | `idr-trmc` |
| `lib/Transforms/Tail/TailLoops.cpp` | 192 | `idr-tail-loops`, `forTails`, `copyName` |
| `lib/Transforms/Tail/WhileDo.cpp` | 311 | the while-do loop |
| `lib/Transforms/Tail/Loop.cpp` | 150 | the general loop |
| `lib/Transforms/Tail/Returned.cpp` | 194 | the `Returned` analysis (on `DataFlowSolver`) |
| `lib/Transforms/Tail/ReturnedArguments.cpp` | 149 | `idr-returned-arguments`, `-drop` |
| `lib/Transforms/Optimize/Contify.cpp` | 137 | `idr-contify` |
| `lib/Conversion/TailCalls.cpp` | 158 | `idr-tail-calls` (rewrite) |
| `lib/Conversion/TailCallPlan.cpp` | 179 | its plan |
| `lib/Conversion/TailPosition.cpp` | 332 | tail position on the LLVM dialect |
| `lib/Conversion/ReturnRegisters.cpp` | 76 | "does a result fit the return registers" |
| `lib/Conversion/Frame.cpp` | 63 | "may a call reach the frame" |
| `lib/Conversion/PassThroughMemory.cpp` | 102 | results through a pointer |
| `include/idr/Transforms/Tail.h` | 313 | the shared declarations |
| `include/idr/Conversion/{TailCallPlan,TailPosition,ReturnRegisters,Frame,PassThroughMemory}.h` | 79 + 37 + 61 + 37 + 45 | |
| total (the above) | 4,000 | |
| `lib/IR/Tail.cpp`, `include/idr/IR/Tail.h` (lane 03 owns; read here) | 291 + 90 | tail position, tail modulo a context |

`Frame.h`, `TailPosition.h`, `ReturnRegisters.h` and `TailCallPlan.h` have
no reader outside the tail-call lowering, and `PassThroughMemory.h` only
`TailCalls.cpp` (*measured*: `grep -rn "Conversion/Frame.h\|PassThroughMemory.h\|TailPosition.h\|ReturnRegisters.h\|TailCallPlan.h" lib include tools unittests`),
so they are this lane's, not lane 12's.

Patterns over the 4,000 lines (*measured*: `bash -c 'cat <files> | grep -c -- <pattern>'`):
`isa<` 25 (6 over several types), `dyn_cast` 37, `cast<` 20,
`std::variant<` 4, `std::visit`/`get_if`/`holds_alternative`/`std::get<` 13,
`function_ref<` 2, `DenseMap<`/`DenseSet<` 21, `.walk(` 12, `getAnalysis<` 7,
`markAnalysesPreserved`/`markAllAnalysesPreserved` 13, `internal error` 7,
`(void)` 12, `DataFlowSolver`/`dataflow::` 9, `parallelFor` 2. No budget,
cap or round count (*measured*: `grep -n -i "budget\|cap\b\|limit\|kMax\|max[A-Z]\|threshold\|rounds"`,
only comments of Contify.cpp naming idr-optimize's cap). No per-target
case (*measured*: `grep -n -i "x86\|aarch64\|darwin\|linux\|elf\|triple\|page"`:
one explanatory comment, `TailCalls.cpp:22`).

Tests that run a tail pass by name: 50 directories (*measured*:
`grep -rl "idr-frames\|idr-trmc\|idr-accumulate\|idr-tail-loops\|idr-tail-calls\|idr-returned-arguments\|idr-contify" tests | sed 's|/[^/]*$||' | sort -u | wc -l`),
among them `frames-answer-types`, `frames-resume-by-type`, `foldlm-deep`,
`loops-trmc`, `dup-deep`, `tail-calls-mutual`, `tail-calls-positions`,
`contify`, `returned-threaded`, `actions-*`. Lane 19 owns them.

### 2.2 Where each pass runs, and on what

*Read*: `lib/Transforms/Pipeline.cpp:80-196`, `include/idr/Transforms/Passes.td:207-232, 430-478, 629-676, 817-886`.

| pass | anchored on | stage (requires → sets) | role | position |
| --- | --- | --- | --- | --- |
| `idr-contify` | `idr.program` | any → any | optimization | after `idr-effects`, before `idr-optimize` (`Pipeline.cpp:80`) |
| `idr-accumulate` | `idr.program` | First → First | optimization | after bufferize, before frames (`:122`) |
| `idr-frames` | `idr.program` | First → First | optimization | before counting (`:125`) |
| `idr-trmc` | `idr.program` | Owned → Owned | optimization | after counting and demand (`:131`) |
| `idr-tail-loops` | `idr.func` (nested) | any → any | optimization | right after TRMC (`:132`) |
| `idr-returned-arguments` (+ `-drop` on each `func.func`) | `builtin.module` | any → any | optimization | after lowering and linalg-to-loops (`:173`) |
| `idr-tail-calls` | `builtin.module` | any → any | lowering | last, on the LLVM dialect (`:196`) |

Only `idr-tail-loops` and `idr-returned-arguments-drop` are function
passes the pass manager runs in parallel; `idr-tail-calls` parallelizes
its own planning and rewrite with `mlir::parallelFor`/`parallelForEach`
(`TailCallPlan.cpp:97`, `TailCalls.cpp:148`). The four program passes and
`Returned`'s solve are serial.

### 2.3 What each part holds and derives

- **Tail position on `idr`** (`lib/IR/Tail.cpp:23-53`, lane 03's file):
  `endsTail`, `inTailPosition`, `passesOnPrevious`, `tailMatch`,
  `isSelfCall`. Nothing stores it: every query walks from the op to its
  block's terminator and then up the chain of tail matches
  (`endsTail` calls `inTailPosition(match)`, `:28`). Its readers: every
  pass of this lane, and `Analysis/Recursion.cpp:35`,
  `Analysis/Ownership/Borrows.cpp:236-237`, `IR/Lifetimes.cpp:64-65`,
  `Transforms/Stack/Stack.cpp:233-234` (*measured*: grep above).
- **Tail modulo a context** (`lib/IR/Tail.cpp:57-289`): `contextAt`, a walk
  from a self call's result through grades, cells, constructors, part
  reads and match joins, with state `Where = variant<Result, Inside,
  Somewhere>` per carried value, a `MapVector<Operation*, Arrival>` per
  join, `seen`; recomputed by every query of `inTailPositionModuloContext`
  (`:282-289`), which Borrows and Lifetimes ask, and by TRMC twice
  (`Trmc.cpp:198`, on the function; `:156`, again on its clone).
- **Frames' plan** (`FramesPlan.cpp`): per call-graph component
  (`CallCycles`, upstream `CallGraph` + `scc_iterator`), the members by
  name (`Members = DenseMap<StringAttr, FuncOp>`), the frame sites (one
  `Operation *` per tail block, a call or a dispatch match), the values
  each rest reads (`SetVector<Value> held`), the members' distinct result
  types, and the content names of the runs, the resumes, the stack and the
  answer. The set of closure labels (`Labels`, a `DenseSet<StringAttr>`) is
  read off every result and block-argument type of the program on every
  run (`FramesPlan.cpp:123-140`). No dataflow: the plan is a structural
  match per component.
- **Frames' rewrite** (`Frames.cpp`, `FramesTypes.cpp`): per component one
  stack data type (`empty`, then `frame<i>` at tag `i + 1`), at most one
  answer sum (one constructor per result type, tag = index in
  `plan.results`), one run per member (its body cloned once), one resume
  per result type (each frame's rest cloned once, into the resume of its
  value's type). Since 16005000 nothing is cloned per (member, result
  type) pair; what remains a product is *regions*: each resume has a case
  for every frame and `ub.unreachable` in those of another value type
  (`Frames.cpp:237-240`), and each member's `fromAnswer` match a case per
  result type, `ub.unreachable` in all but one (`FramesTypes.cpp:84-94`):
  R·(F+1) + M·R regions for M members, R result types, F frames
  (*read*; the counts at stage 1 are not measured).
- **Accumulation** (`AccumulatorPlan.cpp`, `Accumulate.cpp`): per
  function, the self calls in tail position or added by a tail
  (`Site{CallOp, optional<Addition>}`); the countdown recognized by its
  exact op sequence (`isCountdown`, `:167-200`). One clone per function,
  content-named `<f>.acc.<hash>`.
- **TRMC** (`Trmc.cpp`): per function returning one box, the contexts of
  its tails (`Context{call, holes, grades, joins}`); one destination-passing
  clone `<f>.trmc.<hash>`; at the Owned stage, on `idr.cell.init`.
- **Tail loops** (`TailLoops.cpp`, `WhileDo.cpp`, `Loop.cpp`): per
  function, a `Decision{match, loops, exits}` or the general loop (a
  payload `(i1 continue, A, R)` with poison in the half a path does not
  fill, `Loop.cpp:7-14`); upstream LICM (`moveLoopInvariantCode`) and
  `upliftWhileToForLoop` after.
- **Returned arguments** (`Returned.cpp`): one interprocedural
  `SparseForwardDataFlowAnalysis<Lattice<Known>>` over the whole lowered
  module with `loadBaselineAnalyses` (DeadCodeAnalysis and SCCP); `Known`
  a flat three-point lattice per value (`variant<Unconstrained, unsigned,
  NoOne>`, `Tail.h:238-276`); its answer a `DenseMap<StringAttr, Function>`
  read by the nested drop through `getCachedParentAnalysis`.
- **Contification** (`Contify.cpp`): one `SymbolUserMap`, one `CallCycles`,
  one sweep in program order; a function whose one use is a call from
  another member of its component moves into that call by upstream's
  `inlineCall`.
- **Guaranteed tail calls** (`TailCallPlan.cpp`, `TailPosition.cpp`,
  `Frame.cpp`, `ReturnRegisters.cpp`, `TailCalls.cpp`,
  `PassThroughMemory.cpp`): on the LLVM dialect, the internal functions
  (by `SymbolUserMap`), per caller in parallel its calls in tail position
  (a *second* definition of tail position: a path walk with a lattice
  `Known = variant<Unknown, Part, Constant, Poison, Struct>` per value
  and a `OnceWorklist<Entry>` of block entries, per call) that reach no
  frame slot (a points-to walk from every `llvm.alloca`); `CallCycles`
  rebuilt over `llvm.func`; `tailcc` for the callers and callees of such
  calls on one cycle; results that do not fit the return registers (asked
  of a `TargetMachine` built from `#llvm.target`) through a pointer.

### 2.4 State, threading, who reads the results

- No state of this subsystem is per (value, program point). Per value:
  `Returned`'s lattice (on `DataFlowSolver`: one `KnownLattice` per value
  of the lowered module, plus the baseline's constant lattice, an
  `Executable` per block and a `PredecessorState` per callable and call;
  §5.1 A4's 2.9 KB per state at the pin); `TailPosition`'s
  `DenseMap<Value, Known>` per walk; `Frame`'s `DenseSet<Value>` per
  function. Per site: frames, contexts, accumulator sites. Per component or
  function: the plans.
- Cached analyses: `CallCycles` (upstream-backed, built three times by this
  subsystem: Contify.cpp:128, Frames.cpp:349, TailCalls.cpp:139, since no
  pass between preserves it), `SymbolTable`, `Returned` (module, read by the
  nested drop). Nothing else is cached; the tail-position and context
  walks are recomputed per query.
- Who reads the results: the IR itself (clones, loops, conventions);
  counting reads tail position and context (Borrows, Lifetimes, Stack);
  `Recursion` reads tail position; idr-tail-calls reads what idr-tail-loops,
  frames and TRMC left in tail position, and assumes what idr-rc-stack
  promised (`Stack.cpp:30-40`; `TailCalls.cpp:47-52`).

## 3. Reconciliation with the proposal

### 3.1 Findings and designs, against the code

- **§2, "four copies of `isa<ReturnOp, YieldOp>` in `Transforms/Tail`"
  — holds in part.** There are five (*measured*: `grep -rn "isa<ReturnOp, YieldOp>" lib include`):
  three in `Transforms/Tail` (`Accumulate.cpp:104`, `Frames.cpp:119`,
  `Trmc.cpp:177`) and two in `lib/IR/Tail.cpp` (`:39` in
  `passesOnPrevious`, `:269` in `contextAt`). Both ops already declare
  `ReturnLike` (`IdrOps.td:242`, `IdrMatchOps.td:163`), so each copy
  restates a declared trait (§5.2 M5 and §5.3 I1 hold). Beside them the
  same question is asked one op at a time: `isa<YieldOp>`
  (`FramesPlan.cpp:42`, `Frames.cpp:188`, `TailLoops.cpp:129`,
  `Loop.cpp:100`), `isa<ReturnOp>` (`IR/Tail.cpp:25`, `Loop.cpp:65`),
  `dyn_cast<ReturnOp>` (`Frames.cpp:255`), `dyn_cast<YieldOp>`
  (`WhileDo.cpp:292`, `AccumulatorPlan.cpp:55, 105`). Every one of them
  asks of a tail block "does it pass a value on, or never return", and
  most go on to re-check that the op before the terminator is the one
  whose results it passes (`FramesPlan.cpp:45`, `Frames.cpp:124-125`),
  which `passesOnPrevious` already answers. §4 I-1 to I-3 and §5 D5.
- **§3, row 16005000 (`idr-frames`, 43 GB, a body cloned per pair of
  member and result type) — holds, and the fix is incomplete.** The diff
  (*read*: `git show 16005000 -- foreign/idr/lib/Transforms/Tail/Frames.cpp`)
  replaced `Made{run, resume}` keyed by `(member, answer)` with one run per
  member and one resume per result type over an answer sum. What is left
  a product is regions, not bodies: R·(F+1) case regions over the
  resumes (an `ub.unreachable` for every frame of another value type,
  `Frames.cpp:237-240`) and M·R over the members' `fromAnswer` matches
  (`FramesTypes.cpp:84-94`). Each is an empty block and one op, so the
  factor is small; it is still the "state sized by a product" §5.11 A1
  says is a wall waiting. §5 D2 removes both.
- **§5.1 5.1.2 item 2, "`Tail/Returned` back on the framework as a
  per-function solve" — holds in part.** It is on the framework already
  (2c042728 replaced a hand `MonotoneWorklist` solver with
  `SparseForwardDataFlowAnalysis`, *read*: `git show 2c042728 -- .../Returned.cpp`),
  but as one interprocedural solve over the whole lowered module with
  `loadBaselineAnalyses` (`Returned.cpp:153-158`): Design 2's shape, the
  state model §3 shows failing. The per-function form needs a summary
  per function (which argument each result is), and 0003 says
  idr-optimize already computes that fact (`givesBack`) and throws it
  away. §5 D3 ranks S0 (carry it) above S2 (per function).
- **§5.1 item 3, "`Tail/Frames`' plan ... per program point and
  set-valued, stays ours" — refuted.** The plan holds no per-point state
  and solves nothing: `framesPlanOf` (`FramesPlan.cpp:146-196`) is one
  structural walk per tail block of each component's members
  (`framesFrom`, `:108-118`), the only analysis it reads is `CallCycles`
  (upstream `CallGraph` and `scc_iterator`, `lib/Analysis/CallCycles.cpp:33-44`)
  and a walk of types for the labels. Likewise §5.6 item 6 ("extract,
  solve, write back" fits frames' plan): there is no solve to extract
  for. Frames is a transformation (the defunctionalization of the
  continuation, §5 D2), and belongs in no solver layer.
- **§5.1 C2/C4 and §5.4 Design 4 (ask per op, not per region) — holds
  for TRMC's join.** `Walk::join` (`IR/Tail.cpp:200-216`) recounts the
  match's running regions (`runningRegions`, `:93-96`, a `count_if` over
  every region) at every region's arrival: O(N²) per match of N cases a
  context crosses (*read*; e96bb991's shape, in lane 03's file but
  TRMC's question). No call of `getPredecessors`, `getPredecessorValues`,
  `getSuccessorOperandInputMapping()`, `isRepetitiveRegion` or
  `insideMutuallyExclusiveRegions` in the subsystem (*measured*: grep).
- **§5.2 E1/M6 (rooted patterns) — holds.** No `MatchAnyOpTypeTag`
  (*measured*); the one pattern set (`ReturnedArguments.cpp:59-101`) is
  rooted on `func.call` and `func.return` and runs on the walk driver
  (`:129`), as §5.2 E3 recommends.
- **§5.3 B3/I3 (variants visited once, exhaustively) — holds.** Four
  variants: `Returned::Known` (3 alternatives) read by `get_if` and
  `holds_alternative` (`Tail.h:246, 253, 255`; `Returned.cpp:133`);
  `IR/Tail.cpp`'s `Where` (3) by `get_if` (`:83, 147, 184`);
  `TailPosition.cpp`'s `Known` (5) visited exhaustively with
  `llvm::makeVisitor` (`:62-74, 93-109`) but also probed by `get_if`
  (`:131, 133, 149`) and its `Step` (`variant<bool, Edge>`, `:164`) by
  `get_if`/`get` (`:314-316`); `Accumulate.cpp`'s `Plan` (2) visited with
  a local `Visit` overload set (`:130-133`) that restates
  `llvm::makeVisitor`, which the other file uses.
- **§5.3 I6/B8 (worklists are schedules; `scc_iterator`) — holds; the
  subsystem already uses upstream's SCCs.** Every component order comes
  from `CallCycles` (upstream); `lib/Support/Scc.cpp` is not used here.
  The three worklists are `OnceWorklist` (termination in the type,
  `include/idr/Support/Worklist.h:1-25`): `TailCallPlan.cpp:52` (block
  reachability, which `llvm::depth_first` over `Block *` does),
  `Frame.cpp:30`, `TailPosition.cpp:310`.
- **§5.6 item 2 and W-E1 (one call graph kept up to date) — holds.**
  `CallCycles` is built three times by this subsystem alone
  (`Contify.cpp:128`, `Frames.cpp:349`, `TailCalls.cpp:139`) because no
  pass between preserves it, though Contify's own comment proves its
  update is local ("no other function changes cycle", `Contify.cpp:29-32`)
  and Effects writes only effects yet preserves only `SymbolTable`
  (`lib/Transforms/Effects/Effects.cpp:39`, as 0003 says).
- **§5.6 item 5, §5.3 M9 (a budget degrades, never fails) — holds
  vacuously.** No budget in the subsystem (§2.1). Termination is by
  construction everywhere: one plan and one rewrite per component or
  function (Frames, Accumulate, TRMC, tail loops, Contify's one sweep);
  a finite lattice (`Returned`: three points per value; `TailPosition`:
  finitely many `Known`s, `TailPosition.cpp:301-309`).
- **§5.7 M5 and L5 (clones as keys) — holds in part.** Frames, TRMC and
  accumulation already materialize one clone per key: a run per member, a
  resume per result type, one `<f>.acc` and one `<f>.trmc` per function,
  named from content (`FramesPlan.cpp:175-194`, `TailLoops.cpp:81-88`),
  keys from a finite alphabet (the component's members and their result
  types), no budget. L5's "two clones of one key" is already
  unrepresentable (a content name, its collision an internal error). What
  L5 does not name is frames' residual product of impossible cases, which
  is not a clone (above).
- **§5.8 DS4 (`match_lit` on words as `scf.index_switch`) — bears.** The
  only ladder over match kinds here is the decision's test
  (`WhileDo.cpp:138-144`, `TailLoops.cpp:141`): a literal key or a
  constructor tag. Both would be one interface method (§5 D8) whatever
  DS4 decides.
- **§5.9 C3 (tail position is a sum in the call, never an analysis) —
  our code is its opposite.** Tail position is recomputed per query on
  `idr` (`IR/Tail.cpp:23-35`), redefined from scratch on the LLVM dialect
  (`TailPosition.cpp`, a path walk per call), and the fact "a call in tail
  position on its caller's cycle" is decided four times: in counting's
  borrows (`Borrows.cpp:236-237`), in stack cells (`Stack.cpp:233-234`),
  in `Recursion` (`Recursion.cpp:34-35`, the negation for self calls) and
  in the tail-call plan (`TailCallPlan.cpp:106, 123`), the agreement
  between the second and the fourth kept by comments
  (`Stack.cpp:36-40`, `TailCalls.cpp:47-52`) and re-checked conservatively
  by `Frame.cpp`. §5 D1.
- **§5.9 E1 (contification by dominators) — refuted for ours.**
  `idr-contify` builds no graph of continuations and no dominator tree:
  one `SymbolUserMap` (`Contify.cpp:88-89`), one `CallCycles`, one sweep
  in program order, and the criterion is "one use, a call from another
  member of the same component" (`:95-101`). That is the case of Fluet
  and Weeks's analysis where a function's `A` is a `Func` because it has
  one caller; the general case (several call sites returning to one
  continuation) is out of reach because a body of regions cannot jump to
  a shared block (`Contify.cpp:10-13`, *read*). Q-W8 below.
- **§5.9 H, row 16005000 — holds** (instances per key since 16005000,
  above).
- **§5.10 M10 and W8 (TRMC keeps the reuse counting set up) — holds.**
  TRMC runs after counting (`Pipeline.cpp:126-131`) and rebuilds a holed
  cell on the same cell (`withHole` keeps `built.getCell()`,
  `Trmc.cpp:95-96`), so a recycled cell stays the one written; a context
  through a stack cell is refused (`IR/Tail.cpp:168`). The order differs
  from Koka's for a representational reason, not a choice: a context is
  found on the `idr.cell.init` that counting creates
  (`IR/Tail.h:53-57`).
- **0003's items in this subsystem — all hold** (*read*): tail loops at
  the function's location (`Loop.cpp:115, 119, 136-139`;
  `WhileDo.cpp:242-260`); frames' resume cases at the first member's
  location (`Frames.cpp:216`, `resume.getLoc()` from `fn.getLoc()`,
  `:319`); `closureLabels` walking every type (`FramesPlan.cpp:123-140`);
  `givesBack` solved twice (`Returned.cpp`); Contify rebuilding
  `CallCycles` (`Contify.cpp:128`, `Effects.cpp:39`).

### 3.2 The wave-2 questions of §5, by ID

**§5.1 (mlir-analysis).**
- **W1** (V, B, P, F): not measurable here; no built compiler and no
  stage-1 module in this checkout. What this lane can say: `Returned`
  pays per value of the *lowered* module (func, scf, memref, llvm-level
  values after linalg-to-loops), the largest V of the pipeline; frames
  pays R·(F+1) + M·R regions per component.
- **W2** (each analysis's lattice, scope, summaries, design):
  `Returned`: one flat three-point lattice per value (`Tail.h:238-276`),
  interprocedural (`visitCallOperation` reads callee returns through
  `PredecessorState`, `Returned.cpp:105-125`), the summary it needs is per
  function per result (`Known`); fits Design 1 (per function, summaries
  over SCCs from the optimistic start), and better S0 (§5 D3). Frames'
  plan: no lattice (above). `TailPosition`: per call, a lattice per value
  and a set of block entries per walk, intraprocedural: a per-function
  analysis of its own (S2-sized), or deleted by D1.
- **W3**: none (above). The per-query edge counting is `runningRegions`.
- **W4** (`RecursiveMemoryEffects` and whole-body effect queries):
  `mayRunAt` calls `getEffectsRecursively` on every op between a self
  call and its terminator (`IR/Effects.cpp:161-184`), a whole-body walk
  of each match it meets, per self call TRMC considers; idr-tail-loops'
  LICM asks `isMemoryEffectFree` and `isSpeculatable` of every op of the
  loop (`TailLoops.cpp:149-152`), matches included (matches are
  `RecursivelySpeculatable`, `IdrMatchOps.td:27`, so each such query walks
  its body); `AccumulatorPlan.cpp:140` asks them of the ops between a call
  and its addition. `WhileDo.cpp:199` and `TailPosition.cpp:204` exclude
  region ops first.
- **W5** (attributes and types made on a hot path): frames makes a
  `StringAttr` per run, resume, stack and answer, two data types per
  component through `Declarations` (`FramesTypes.cpp:27, 54`) and the
  constructors' names by `std::to_string` (`:37, 58`); TRMC a `DestType`
  per function (`Trmc.cpp:255`); `canonicalHash(result)` per resume
  (`FramesPlan.cpp:185`). None per value. `TailPosition` makes none.
- **W6** (anchoring): only `idr-tail-loops` (`Pipeline.cpp:132`) and
  `idr-returned-arguments-drop` (`ReturnedArguments.cpp:140`) are nested
  on functions. Contify, accumulate, frames and TRMC are program passes
  whose planning reads one function (accumulate, TRMC) or one component
  (frames) and could run in parallel (§5 D10); the symbol insertions are
  what keeps them at the program.
- **W7**: no backward solve in the subsystem. `Returned` is forward and
  interprocedural (the module is a symbol table), so U2 does not apply.

**§5.2 (mlir-ods).** W1: no hand `getEffects` in the subsystem; it reads
effects through the interface. W2: none (above). W3: no `verify()` here;
`idr.dest.write`'s rule is a `PredOpTrait` (`IdrOps.td:372-375`), already
declared. W4: §4's ladder rows. W9: every pass here marks all analyses
preserved when it changed nothing (`Frames.cpp:371-372`,
`Trmc.cpp:264-265`, `Accumulate.cpp:208-209`, `TailLoops.cpp:158, 170`,
`Contify.cpp:130-131`, `ReturnedArguments.cpp:117, 136-137`), except
idr-tail-calls, which never does (`TailCalls.cpp:137-153`).

**§5.3 (llvm).** Worklists: the three `OnceWorklist`s above, FIFO,
identity by `Block *`, `Value`, and a structural `Entry` (block plus the
`Known` of its arguments and live-ins, hashed whole,
`TailPosition.cpp:265-279`). Per-node maps: none per node; per walk
(`TailPosition`'s `DenseMap<Value, Known>`, `:258`) and per function
(`Frame`'s `DenseSet<Value>`, `Frame.h:22`). `function_ref`: `forTails`
(`Tail.h:58`), cold, but every caller collects into a vector first
(`Frames.cpp:113-114`, `Accumulate.cpp:100-101`), so it should return
the blocks. Variants: above. `DataFlowSolver` files: `Returned`, whole
program today (S1 or delete). Graphs: the call graph is upstream's.

**§5.4 (modular).** Summary analyses with their own SCC order: none here.
State copied per edge: `TailPosition`'s `Entry`, a copy of the `Known` of
every live-in value at every block the walk enters (`:243-247`), per
call. Predecessors of region successors: TRMC's arrivals per region;
`Returned` through the framework's `PredecessorState`. `CallOpInterface`:
`idr.call` implements it (`IdrOps.td:210`). No option selects between two
implementations.

**§5.6 (ecosystem).** W-E1: contify, frames, TRMC and accumulate change
calls or add functions; none updates `CallCycles`. W-E2: `Returned` keeps
a lattice for every value of every type, though only a value of some
argument's type can be an argument. W-E3: `CallCycles` (above). W-E4: no
pass here writes a discardable attribute; three copy whatever a call
carries (`Trmc.cpp:76`, `Accumulate.cpp:73`, `ReturnedArguments.cpp:73`),
and nothing in `lib/` writes one on a call (*measured*:
`grep -rn "setDiscardableAttr\|->setAttr(" lib include`). W-E5: none.
W-E6: `runningRegions` and `mayRunAt`'s recursive effects (above). W-E7:
`TailPosition`'s and `Frame`'s value maps. W-E8: yes: every case region
is `SizedRegion<1>` (`IdrMatchOps.td:33`), a function's body
`SizedRegion<1>` (`IdrOps.td:165`) save contify's transient second block
(`Contify.cpp:34-42`), and every pass here reads `region.front()` only.
W-E9: `TailPosition`'s `Entry`.

**§5.7 (library).** Fact kinds: `Returned` is a partitioned lattice per
variable, forward; `TailPosition` a per-call path property; frames
structural. Specializers: frames' keys are members (runs) and result
types (resumes), accumulate's and TRMC's (function, kind); all finite, no
budget.

**§5.9 (mlton).**
- **Q-W2**: `Returned` is per value and flow-insensitive on SSA, a
  Design 1 domain (a flat cell per value) or deleted (§5 D3);
  `TailPosition` is flow-sensitive because lowering made it so: a
  general loop's exit flag is a constant the path must decide
  (`Loop.cpp:7-14`, `TailPosition.cpp:30-35`).
- **Q-W4** (which passes read the region structure of `match`): all of
  this lane's `idr` passes. Accumulation: tails through tail matches
  (`forTails`, `Accumulate.cpp:100-101`). Frames: tail blocks, a
  dispatch's case regions, the rest of a block (`FramesPlan.cpp:59-118`,
  `Frames.cpp:183-201`), and it builds matches (resumes, `fromAnswer`).
  TRMC: joins through match yields (`IR/Tail.cpp:200-255`),
  `MatchOpInterface::rebuild` (`Trmc.cpp:166-168`). Tail loops: the
  decision's two regions (`TailLoops.cpp:116-144`), inlined into
  `scf.while` (`WhileDo.cpp:147-172`), or every tail match rebuilt with
  payload results (`Loop.cpp:90-104`). Contify: limited to one call site
  *by* the regions (`Contify.cpp:10-13`). On a CFG core each would read
  blocks and branches: TRMC's arrival per region becomes one per
  predecessor of a join block, frames' "rest of the block" becomes the
  continuation of the call (its block suffix and what it reaches), tail
  loops would come from upstream's `lift-cf-to-scf` or stay CFG loops.
  Only contify gains outright.
- **Q-W6** (liveness or last-use facts): frames computes one at one
  point: `held`, the values the rest of a block reads that it does not
  make (`FramesPlan.cpp:88-95`), by a walk with an O(rest) membership
  test per operand (`madeInRest`, `:31-35`): O(rest²) per site.
  `TailPosition` reads upstream's `mlir::Liveness` per function for a
  block's live-ins (`TailPosition.h:32`, `.cpp:317`). Neither keeps a set
  per value along edges.
- **Q-W8**: one `SymbolUserMap`, one `CallCycles`, one sweep; no
  dominator tree, no continuation graph, nothing iterated (above).

**§5.10 (rc).** W8: counting runs on `idr.match` regions ("a match's
yield is its join point", `Pipeline.cpp:126-127`); TRMC keeps its reuse
(above).

**§5.11 (oom).** Item 4: idr-tail-calls sets no `probe-stack`; that is the
lowering's (lane 12) and the target's (lane 13). Item 7: frames' R·(F+1)
+ M·R regions is the one product of two program quantities left in this
subsystem; `TailPosition`'s per-call walks (calls × path length per
function) are a second, time not state.

## 4. Issues

Every row is *read* at the line cited unless it says *measured* or
*conjecture*. "D*n*" points to the change in §5 that disposes of it.
Rows for `lib/IR/Tail.cpp` are lane 03's file; they are listed because
every pass here reads it, and their disposition is lane 03's to take.

### 4.1 The shared header, `include/idr/Transforms/Tail.h`

| ID | where | category | what | disposition |
| --- | --- | --- | --- | --- |
| H-1 | `Tail.h:58`; `TailLoops.cpp:57-65` | cpp | `forTails(Block &, function_ref<void(Block &)>)`: every caller collects the blocks into a vector first (`Frames.cpp:113-114`, `Accumulate.cpp:100-101`) | return the blocks; part of D1's per-function tail table |
| H-2 | `Tail.h:62`; `TailLoops.cpp:67-79` | rederivation | `reachesTailCall` answers a bool by recursing into every tail match, asked again per block on the way down (`Loop.cpp:90`), per region (`TailLoops.cpp:132`) and per function (`:157`): O(blocks × depth) | D1 |
| H-3 | `Tail.h:72`; `TailLoops.cpp:81-88`; `FramesPlan.cpp:176-190` | dead (*conjecture*) | an internal error when a content name `<f>.<kind>.<hash>` is already a symbol: impossible unless a program names a function so; three copies of the check | keep one `copyName` for every clone (frames' two too), or reserve the form in the frontend's names (lane 15) and delete the checks |
| H-4 | `Tail.h:81-85`; `WhileDo.cpp:180` | rederivation | `Decision` keeps the looping region but not the self call `decisionOf` found (`TailLoops.cpp:127-130`); `whileDo` finds it again by position | D8: `Decision` holds its `CallOp` |
| H-5 | `Tail.h:101-111`; `AccumulatorPlan.cpp:155-210` | ladder | the countdown `f(0)=0, f(n)=f(n-1)+1` recognized by its exact op sequence (H-5 is the special case; AP-2, AP-6 its ladders) | D7; whether the case is essential (the accumulated loop does not finish at a word's range, `AccumulatorPlan.cpp:14-19`) is lane 09's and 04's to judge |
| H-6 | `Tail.h:117-124` | cpp | `Site{CallOp; optional<Addition>}`: two cases as an optional; "a plan has an addition" re-counted (`AccumulatorPlan.cpp:225`, `Accumulate.cpp:200-203`) | D7: a sum `{TailCall, AddedTail}` |
| H-7 | `Tail.h:135-138`; `FramesPlan.cpp:19-22` | rederivation | `Members = DenseMap<StringAttr, FuncOp>`: a second copy of the component, by name, beside `CallCycles` | D2: read `CallCycles::componentOf` and the call's resolved callee |
| H-8 | `Tail.h:141-142`; `FramesPlan.cpp:123-140` | rederivation | `Labels`: every op result type and block-argument type of the program walked, every run, to find the closure labels (0003) | D2: the label's function as a fact written by idr-defunctionalize, or `TypeGraph::declarations()` |
| H-9 | `Tail.h:149-154` | ladder | `Frame::site` is an `Operation *` that is a call or a dispatch match, told apart by `isa`/`dyn_cast` (`FramesPlan.cpp:67-71`, `Frames.cpp:173`); the plan finds which case region calls which member and keeps only the callees (`FramesPlan.cpp:69-71`), so the rewrite finds it again (`Frames.cpp:191-192`) | D2: `variant<CallSite, DispatchSite{match, cases}>` |
| H-10 | `Tail.h:157-163` | state | `restOf`, `madeInRest`, `isConstant`, `caseCallee` as free functions; `madeInRest` is O(rest) (FP-2) | D2 |
| H-11 | `Tail.h:171-185` | state | `FramesPlan::answer` is null exactly when `results.size() == 1`: one fact in two fields; `runs` keyed by `Operation *`, `resumes` by `Type` | D2: `variant<OneResult, AnswerSum>` decided once |
| H-12 | `Tail.h:197-206`; `FramesTypes.cpp:65, 78`; `Frames.cpp:280-288` | rederivation | `FramesMade::answer` and `optional<DataType> sum`: the same one-or-many fact a second and third time, three branches on it | D2 |
| H-13 | `Tail.h:208-220`; `Frames.cpp:237-240`; `FramesTypes.cpp:84-94` | state | one stack type for frames of every value type, so a resume enumerates frames that can never be on top (`ub.unreachable`), and `fromAnswer` result types a member can never get: R·(F+1) + M·R regions | D2 |
| H-14 | `Tail.h:238-276`; `Returned.cpp:133` | ladder | `Known = variant<Unconstrained, unsigned, NoOne>` read by `get_if` and `holds_alternative` | D3 (the lattice goes with the solve) or one exhaustive `match` (§5.5 D2) |
| H-15 | `Tail.h:286-291`; `ReturnedArguments.cpp:66, 90, 122-126` | rederivation | which results drop is derived three ways: `kept()` per call and per return, the `dropped` bit vector again | D3: one partition, stored once |
| H-16 | `Tail.h:305-308` | (essential) | `Returned`'s answer keyed by symbol name: the identity MLIR's nested passes may read without touching a sibling | keep |

### 4.2 `idr-frames`: `FramesPlan.cpp`, `Frames.cpp`, `FramesTypes.cpp`

| ID | where | category | what | disposition |
| --- | --- | --- | --- | --- |
| FP-1 | `FramesPlan.cpp:19-22` | rederivation | `memberCalled`: `dyn_cast<CallOp>` and a name lookup in `Members` | D2 (H-7) |
| FP-2 | `FramesPlan.cpp:31-35, 93`; `Frames.cpp:250` | state | `madeInRest` scans the whole rest per query and is asked per operand of every op of the rest: O(rest²) per frame site | D2: `block->findAncestorOpInBlock(*def)` and `site->isBeforeInBlock(ancestor)` |
| FP-3 | `FramesPlan.cpp:38-46` | ladder | `caseCallee`: `isa<YieldOp>`, one operand, and `def->getNextNode() == terminator`, which is `passesOnPrevious` (`IR/Tail.cpp:37-41`) restated | D5 |
| FP-4 | `FramesPlan.cpp:48-51` | upstream | `isConstant` restates `matchPattern(value, m_Constant())` | upstream's matcher |
| FP-5 | `FramesPlan.cpp:59-73` | ladder | `closuresRun`: `isa<CallOp>` / `isa<MatchOpInterface>` over the two site kinds; `inTailPosition(&op)` for every op of every tail block, each a walk up the tail matches | D2 (H-9), D1 |
| FP-6 | `FramesPlan.cpp:80-103` | rederivation | `frameAt`: per candidate, a nested walk of the rest asking `inTailPosition` of every member call in it | D1 |
| FP-7 | `FramesPlan.cpp:123-140` | rederivation | `closureLabels` (H-8) | D2 |
| FP-8 | `FramesPlan.cpp:150-153` | dead | `!fn \|\| fn.getBody().empty()`: every function is defined (`IdrOps.td:118, 176-178`), and a component of an `idr.program` holds only `idr.func` (*conjecture* for the second half: the program's only callables after idr-defunctionalize) | delete |
| FP-9 | `FramesPlan.cpp:151` | budget (a limit, never fails) | a member with other than one result keeps its calls | keep; essential to the stack's shape |
| FP-10 | `FramesPlan.cpp:157-160` | dead (*conjecture*) | members whose `effects` differ get no plan; the comment says the effects solve gives a cycle one set, which would make the branch unreachable | lane 06 confirms the invariant; then the branch goes, or the invariant is checked once where it is made |
| FP-11 | `FramesPlan.cpp:166-171` | budget (a limit, never fails) | a result type no constructor field may hold (`isFieldType`) keeps the component's calls | keep, and §8 R-3: such a component keeps its stack growth silently |
| FP-12 | `FramesPlan.cpp:172-173` | list | the answer's tag order is the position in `plan.results`, found again by `llvm::find` (`FramesTypes.cpp:67-68`) | D2: the tag stored with the result type |
| FP-13 | `FramesPlan.cpp:191-193` | state | `plan.answer` written iff more than one result type (H-11) | D2 |
| Fr-1 | `Frames.cpp:96-104` | cpp | `answerTails` retypes match results with `setType` outside the rewriter: no listener sees it | `rewriter.modifyOpInPlace` |
| Fr-2 | `Frames.cpp:119` | ladder | `isa<ReturnOp, YieldOp>(terminator)` | D5 |
| Fr-3 | `Frames.cpp:124-125` | rederivation | `def->getNextNode() == terminator`: `passesOnPrevious` again | D5 |
| Fr-4 | `Frames.cpp:150-152` | state | each member's `fillRun` scans every frame of the component for its own: O(M·F) | D2: frames grouped by owner in the plan |
| Fr-5 | `Frames.cpp:166-167, 230-231, 336`; `FramesTypes.cpp:30-37` | list | frame *i* is tag *i*+1 and `empty` tag 0, a coordinate computed in four places | D2: the tag stored in the frame when the stack is defined |
| Fr-6 | `Frames.cpp:173, 188, 191-193` | rederivation | the site's kind by `dyn_cast<CallOp>`; a case's callee found again by `caseCallee` and `cast<CallOp>(yield->getOperand(0).getDefiningOp())` | D2 (H-9) |
| Fr-7 | `Frames.cpp:216-219, 236, 238, 256` | rederivation | resume cases at the resume's location, the first member's, though each frame's site is known (0003) | D2: `FusedLoc` or the site's location per case |
| Fr-8 | `Frames.cpp:237-240` | state | `ub.unreachable` for every frame of another value type, in every resume (H-13) | D2 |
| Fr-9 | `Frames.cpp:243` | cpp | `zip_first(frame.held, block->getArguments())` truncates silently (the last argument is the stack) | `zip_equal(frame.held, args.drop_back())` (§5.5 D8) |
| Fr-10 | `Frames.cpp:246-252` | state | constants of the rest re-made by a walk with `madeInRest`: O(rest²) | D2 (FP-2) |
| Fr-11 | `Frames.cpp:254-262` | ladder | `dyn_cast<ReturnOp>` to turn the owner's return into the case's yield | D5 (the tail-block view) |
| Fr-12 | `Frames.cpp:291` | state | every member's whole `IRMapping` from its clone kept until that member's run is filled: peak memory the sum of all members' bodies | fill each run right after its clone, or map only the frame sites |
| Fr-13 | `Frames.cpp:296, 318` | attribute (lane 03's ODS) | `plan.total ? UnitAttr::get(ctx) : UnitAttr()` twice: `total` is a `UnitAttr` on `idr.func` (`IdrOps.td:161`) | a `BoolProp` or the absorb rule (`FuncOp::absorb`) applied to the clone; lane 03 |
| Fr-14 | `Frames.cpp:299-301` | cpp | `(void)run.insertArgument(...)` then the function type rebuilt by hand | one `FunctionOpInterface` call that sets both |
| Fr-15 | `Frames.cpp:307-309` | state | the first member of each result type found by `find_if`, per result type | D2 (members grouped by result type) |
| Fr-16 | `Frames.cpp:320` | rederivation | a resume's `effects` copied from one member, resting on FP-10 | D2, with FP-10 |
| Fr-17 | `Frames.cpp:349` | rederivation | `getAnalysis<CallCycles>()` rebuilt: nothing since Contify preserved it (W-E3) | D4 (one maintained call graph) |
| Fr-18 | `Frames.cpp:352-358` | cpp (threading) | the plans, which read only their component, made serially | D10 |
| Fr-19 | `Frames.cpp:362-369` | cpp | `bool failedOne \|=` over the components: the only failures are internal errors (H-3) | D2: plan failures before any rewrite, one result |
| FT-1 | `FramesTypes.cpp:63-70` | rederivation | `asAnswer` branches on `sum` (H-12) and finds the tag by `llvm::find` (FP-12) | D2 |
| FT-2 | `FramesTypes.cpp:76-97` | state | `fromAnswer` enumerates every result type, `ub.unreachable` in all but one (H-13): the start member is not in the answer's type, so the impossibility is essential (Brooks), the enumeration is not | D2: one case and the default region |

### 4.3 `idr-trmc`, `idr-accumulate`

| ID | where | category | what | disposition |
| --- | --- | --- | --- | --- |
| Tr-1 | `Trmc.cpp:74-77`; `Accumulate.cpp:73` | attribute | a new call takes the old call's discardable attributes; nothing in `lib/` writes one on a call (*measured*: grep), so the copy carries nothing or a fact AGENTS.md forbids (W-E4) | delete the copies |
| Tr-2 | `Trmc.cpp:111-120` | cpp | `Type destType` set inside the loop over holes, null if a context had none: `Context::holes` non-empty is an invariant no type states | `holes` non-empty by type (an `llvm::SmallVector` with a first element apart, `List1`'s C++ form) |
| Tr-3 | `Trmc.cpp:156, 198` | rederivation | `contextAt` computed on the function (the plan) and again on its clone (`rewriteClone`), the clone being `fn.clone()` | D9: map the plan's contexts through the clone's `IRMapping` |
| Tr-4 | `Trmc.cpp:177` | ladder | `isa<ReturnOp, YieldOp>(terminator)` | D5 |
| Tr-5 | `Trmc.cpp:179` | rederivation | `passesOnPrevious` and `isSelfCall` (a string compare, IT-3) per tail | D1 |
| Tr-6 | `Trmc.cpp:238-244` | cpp (threading) | planning, which reads one function, serial over the program | D10 |
| Tr-7 | `Trmc.cpp:257-258` | cpp | `(void)clone.insertArgument`, `(void)clone.eraseResult(0)` | the interface's calls whose result is used or checked |
| A-1 | `Accumulate.cpp:68-75` | attribute | `retarget` copies `res_attrs` and the discardable attributes (Tr-1) | delete the discardable copy |
| A-2 | `Accumulate.cpp:104` | ladder | `isa<ReturnOp, YieldOp>(terminator)` | D5 |
| A-3 | `Accumulate.cpp:107` | rederivation | `isSelfCall(value.getDefiningOp(), clone)` by name | D1 |
| A-4 | `Accumulate.cpp:121-133, 191-206` | list | a local `Visit` overload set restating `llvm::makeVisitor` (STLExtras, used by `TailPosition.cpp:63`) | the tree's one `match` (§5.5 D2) |
| A-5 | `Accumulate.cpp:157` | cpp | `(void)clone.insertArgument` | as Tr-7 |
| A-6 | `Accumulate.cpp:180-186` | cpp (threading) | serial planning | D10 |
| AP-1 | `AccumulatorPlan.cpp:39-45` | upstream | `constantOf`: `getDefiningOp<ConstantOp>` and `dyn_cast<BigAttr>` | `matchPattern(value, m_Constant(&attr))` |
| AP-2 | `AccumulatorPlan.cpp:75-107` | ladder | `addsOneToPredecessor`: `isa<ConstantOp, YieldOp>`, `dyn_cast<BigPredOp>`, `<CallOp>`, `<BigAddOp>` over a block to match one op sequence | D7: one rooted rewrite (DRR, §5.2 M13) or `m_Op` matchers |
| AP-3 | `AccumulatorPlan.cpp:110-119` | upstream | `dependsOnSelfCall`: a recursive walk of the def chain with its own `DenseSet<Value>`, recursion depth the chain's length | `getBackwardSlice` with a filter (`mlir/Analysis/SliceAnalysis.h`) |
| AP-4 | `AccumulatorPlan.cpp:125, 130` | rederivation | `inTailPosition` of the call and of the addition, each a walk up | D1 |
| AP-5 | `AccumulatorPlan.cpp:140` | (W4) | `isMemoryEffectFree && isSpeculatable` per op between call and addition: a body walk for a region op | keep (upstream's query); D1 records the run between call and use once |
| AP-6 | `AccumulatorPlan.cpp:167-200` | ladder | `isCountdown`: `isa<ConstantOp>`, `dyn_cast<MatchLitOp>`, `dyn_cast<ReturnOp>` over the entry block | D7 |

### 4.4 `idr-tail-loops`: `TailLoops.cpp`, `WhileDo.cpp`, `Loop.cpp`

| ID | where | category | what | disposition |
| --- | --- | --- | --- | --- |
| TL-1 | `TailLoops.cpp:128-133` | ladder | `isa<YieldOp>(end) && passesOnPrevious(end) && isSelfCall(...)`; two `find_if`s over the regions | D1, D5 |
| TL-2 | `TailLoops.cpp:141`; `WhileDo.cpp:112-145` | ladder | the decision's test per match kind: `isa<MatchLitOp>` (a literal key, an integer only) or `cast<MatchOp>` (a tag) | D8: a `MatchOpInterface` method "the `i1` that holds when region *r* runs" |
| TL-3 | `TailLoops.cpp:149-152`; `WhileDo.cpp:193-205` | rederivation | "may run once before the loop" stated twice, differently: LICM's predicate asks speculatability, the while-do construction's does not (the before region runs at least once) and excludes region ops | D8: both predicates in one place, named for the two cases (the difference is essential) |
| TL-4 | `TailLoops.cpp:162-169` | cpp | `FailureOr<scf::WhileOp>` whose failure means "the general loop was made instead": a sum of two outcomes as a failure | D8: `variant<WhileDoLoop, GeneralLoop>` |
| L-1 | `Loop.cpp:7-14, 48-58` | (essential) | the general loop's payload `(i1, A, R)` with poison in the half a path does not fill: the sum `Continue A \| Exit R` as a flag and a product, because `scf.condition` takes an `i1` (upstream's form) | keep; its cost is TPo-5 (the flag decided again on LLVM) |
| L-2 | `Loop.cpp:65, 100` | ladder | `isa<ReturnOp>`, `isa<YieldOp>` | D5 |
| L-3 | `Loop.cpp:90` | rederivation | `reachesTailCall` per block of the recursive rewrite (H-2) | D1 |
| L-4 | `Loop.cpp:115, 119-123, 136-139`; `WhileDo.cpp:242, 253-260` | rederivation | the loop, its blocks and arguments at the function's location though the self call's and the match's are known (0003) | the call's and the match's locations |
| L-5 | `Loop.cpp:131-134`; `WhileDo.cpp:280-283` | (evidence, ods-Q1) | `idr.may_loop` (`IdrCheckOps.td:46-52`: `MemWrite<Divergence>`, `MemWrite<IO>`) put in every loop of a function without `total` so that upstream does not delete it | the owner's ods-Q1/DD-Q2 |
| W-1 | `WhileDo.cpp:80-96` | state | `in()`: `llvm::find` over `carried` and `passed` per operand of every op moved: O(ops × (carried + passed)) | an `IRMapping` per scope |
| W-2 | `WhileDo.cpp:180` | rederivation | the self call found again (H-4) | D8 |
| W-3 | `WhileDo.cpp:225-226, 238-239` | budget (a limit, never fails) | a value the regions need that holds a reference, or a linear argument the decision takes, sends the function to the general loop | keep |
| W-4 | `WhileDo.cpp:292-296` | ladder | `dyn_cast<YieldOp>(exitEnd)`, else the region never returns | D5 |

### 4.5 `idr-returned-arguments`: `Returned.cpp`, `ReturnedArguments.cpp`

| ID | where | category | what | disposition |
| --- | --- | --- | --- | --- |
| R-1 | `Returned.cpp:152-159` | state (upstream at the pin) | one interprocedural `DataFlowSolver` solve over the whole lowered module with `loadBaselineAnalyses`: a `KnownLattice` and a constant lattice per value, an `Executable` per block, a `PredecessorState` per callable and call, uniqued program points (§5.1 A4, A7, H1; Design 2) | D3 |
| R-2 | `Returned.cpp:156-159` | cpp | `[[maybe_unused]] LogicalResult solved` and an `assert`: in a release build the solve's result is dropped | D3 (the solve's failure is a value, or impossible by type) |
| R-3 | `Returned.cpp:152, 162-163` | rederivation | the `AnalysisManager` parameter unused; its own `SymbolTableCollection` and `SymbolUserMap` | D3 |
| R-4 | (0003) | rederivation | `givesBack` decided by idr-optimize's summaries and thrown away, then solved again here on lowered IR | D3 |
| R-5 | `Returned.cpp:173-179` and the solve | state | a lattice for every value of every type, though only a value of an argument's type can be an argument (W-E2) | D3 |
| R-6 | `Returned.cpp:74` | ladder (small) | `isa<ub::PoisonOp>` as the bottom | keep (one op, one meaning) |
| RA-1 | `ReturnedArguments.cpp:73` | attribute | the discardable-attribute copy (Tr-1) | delete |
| RA-2 | `ReturnedArguments.cpp:108-114`; `Passes.td:842-854` | ods | `idr-returned-arguments-drop` is a registered pass meaningful only inside its parent; run alone it is an internal error | do not register the inner step (build it in the parent only), so the bad pipeline cannot be written; lane 13 |
| RA-3 | `ReturnedArguments.cpp:122-126` | rederivation | the dropped bits recomputed (H-15); `(void)fn.eraseResults(dropped)` | D3 |

### 4.6 `idr-contify`, `Contify.cpp`

| ID | where | category | what | disposition |
| --- | --- | --- | --- | --- |
| C-1 | `Contify.cpp:80-123` | (essential, Q-O1) | contification only of a function with one call site, from a member of its component; the general case is unrepresentable in a body of regions (`:10-13`) | keep under regions; D4 and Q-O1 |
| C-2 | `Contify.cpp:96` | rederivation | `fn.getSymName() == program.getRoot()`: a string compare beside `FuncOp::isRoot()` (`IdrOps.td:184-185`) | `fn.isRoot()` |
| C-3 | `Contify.cpp:104-115` | cpp | `bool moved` set inside the action, beside `perform`'s own "ran" | `perform`'s result and the inliner's |
| C-4 | `Contify.cpp:128` | rederivation | `CallCycles` rebuilt: Effects writes only effects and preserves only `SymbolTable` (`Effects.cpp:39`) | lane 06 preserves it; D4 |
| C-5 | `Contify.cpp:129-133` | rederivation | `CallCycles` not preserved, though the update is the erasure of one member from its component (`:29-32`) | D4: update and preserve it |
| C-6 | `Contify.cpp:15-21` | idris | the functions it targets are Idris's case blocks, whose one call site in their parent the frontend knows (0003 B1: the TTC's block parent), and which the C++ rediscovers from symbol uses | D4: lane 15/17's fork fix first; then whether the frontend emits such a block in place (*conjecture*) |

### 4.7 `idr-tail-calls`: `TailCalls.cpp`, `TailCallPlan.cpp`, `TailPosition.cpp`, `Frame.cpp`, `ReturnRegisters.cpp`, `PassThroughMemory.cpp`

| ID | where | category | what | disposition |
| --- | --- | --- | --- | --- |
| TC-1 | `TailCalls.cpp:119` | state | `is_contained(tailCalls, call)` per call | a set, or the plan's own mark |
| TC-2 | `TailCalls.cpp:139` | rederivation | `CallCycles` rebuilt over `llvm.func`: the cycles the program's passes had, recomputed after conversion | essential across the conversion (the ops are new); cheap (upstream `CallGraph`); keep |
| TC-3 | `TailCalls.cpp:137-153` | cpp | never marks analyses preserved, even with an empty plan (§5.2 W9) | mark when the plan is empty |
| TC-4 | `TailCalls.cpp:149-152` | cpp | a walk of the whole module for a statistic | count in `place` |
| TC-5 | `TailCalls.cpp:47-52`; `TailCallPlan.cpp:108-113`; `Frame.cpp`; `Stack.cpp:36-40, 228-235` | rederivation | idr-rc-stack keeps off the stack every cell a tail call on its caller's cycle may take; idr-tail-calls finds again, conservatively, whether a call reaches the frame, and a call that does stays a call, counted (`numFrameBound`) and otherwise silent | D1, D6, and a question for the owner (§6) |
| TP-1 | `TailCallPlan.cpp:28-34, 74-88` | rederivation | `ByName = DenseMap<StringAttr, LLVMFuncOp>`: a hand symbol table of the internal functions | `SymbolTable` and a set of internal functions |
| TP-2 | `TailCallPlan.cpp:49-65` | upstream | `reach`: block reachability by an `OnceWorklist` | `llvm::depth_first` over `Block *`, cut at a planned call |
| TPo-1 | `TailPosition.cpp:131-153, 164, 313-316` | ladder | `get_if` probes beside the exhaustive visits (`isPart`, `decided`, `take`) | one `match` per use (§5.5 D2) |
| TPo-2 | `TailPosition.cpp:81-86, 243-247, 265-279` | state | an `Entry` copies the `Known` of every live-in value at every block the walk enters, hashed whole: state per edge (b8301ebe's shape, per call) | D6 |
| TPo-3 | `TailPosition.cpp:176-185` | ladder | `dyn_cast_or_null<LLVM::ConstantOp>`, `isa_and_nonnull<LLVM::PoisonOp, LLVM::UndefOp>` | `m_Constant` for the constant; poison and undef stay (no interface names both) |
| TPo-4 | `TailPosition.cpp:209-238` | upstream (patched) | `follow`: a ladder over `llvm.return`, `llvm.br`, `llvm.cond_br`, `llvm.switch`; upstream's `BranchOpInterface::getSuccessorForOperands` is that question, implemented by `cf.br`, `cf.cond_br`, `cf.switch` (`lib/Dialect/ControlFlow/IR/ControlFlowOps.cpp:295, 579, 738`) and not by the LLVM dialect's branches (*measured*: grep of `lib/Dialect/LLVMIR`) | D6: `upstream/<bug>/llvm.patch` giving `llvm.br`, `cond_br`, `switch` the method; then `getSuccessorForOperands` plus `ReturnLike` |
| TPo-5 | `TailPosition.cpp:283-330` | rederivation | one walk per call: calls × path length per function | D6: one backward pass per function answering every call |
| TPo-6 | `TailPosition.cpp` (the file) | rederivation | the second definition of tail position, beside `IR/Tail.cpp` (§5.9 C3) | D1, D6 |
| Fra-1 | `Frame.cpp:44-46` | ladder | `isa<GEPOp, AddrSpaceCastOp, SelectOp, InsertValueOp, ExtractValueOp, IntToPtrOp, PtrToIntOp>`: GEP and addrspacecast implement `ViewLikeOpInterface`, select `SelectLikeOpInterface` (*read*: `mlir/include/mlir/Dialect/LLVMIR/LLVMOps.td:294-298, 649-653, 1090-1094`) | the interfaces for those; the rest stay named |
| Fra-2 | `Frame.cpp:50-52`; `Frame.h:22-23` | state | `bool leaked`: one frame pointer stored outside the frame makes every call of the function frame-bound | D6: the set of slots that escaped, so only calls that may reach those are bound |
| RR-1 | `ReturnRegisters.cpp:25-38` | rederivation | a `TargetMachine` built from `#llvm.target` with default options, beside the driver's `idr::target::machine` (0003, target lane) | lane 13: one machine recipe, this asks it |
| RR-2 | `ReturnRegisters.cpp:31-33` | upstream | `LLVM::detail::initializeBackendsOnce` and `getTargetMachine`: upstream's `detail` namespace | lane 13, with RR-1 |
| PT-1 | `PassThroughMemory.cpp:52-58` | cpp | `(void)insertArgument` then the function type rebuilt by hand | as Fr-14 |
| PT-2 | `PassThroughMemory.cpp:61-73` | cpp | `passOnPointer` takes `call->getNextNode()` to be the return, which the plan's split guarantees (`TailCalls.cpp:101-106`) without saying so in a type | the planned call and its return as one record |

### 4.8 `lib/IR/Tail.cpp` (lane 03's), as this subsystem reads it

| ID | where | category | what | disposition (lane 03's) |
| --- | --- | --- | --- | --- |
| IT-1 | `IR/Tail.cpp:23-35` | rederivation | `endsTail`/`inTailPosition` walk up the chain of tail matches per query; asked by every pass here and by Borrows, Lifetimes, Stack, Recursion | D1 |
| IT-2 | `IR/Tail.cpp:39, 269` | ladder | `isa<ReturnOp, YieldOp>` (copies 1 and 2 of 5) | D5 |
| IT-3 | `IR/Tail.cpp:50-53` | rederivation | `isSelfCall` compares the callee's string with the function's; `Recursion.cpp:34` compares the uniqued `StringAttr`s | compare `getCalleeAttr().getAttr()` with `fn.getSymNameAttr()` |
| IT-4 | `IR/Tail.cpp:62-89, 147, 184` | ladder | `Where = variant<Result, Inside, Somewhere>` read by `get_if` | one `match` |
| IT-5 | `IR/Tail.cpp:99-106` | cpp | `fieldOf`: `for (;; ++index)` with `is_contained(holes, ...)`, resting on an invariant, O(fields × holes) | an accessor of `idr.cell.init` in ODS: "the field this operand fills" |
| IT-6 | `IR/Tail.cpp:145-195` | ladder | `step`: `hasTrait<ResultCarriesOperand>`, `dyn_cast<CellInitOp>`, `<ConOp>`, `isa<YieldOp>`, `dyn_cast<UnpackOp>`, `<FieldOp>`: how each op forwards a value, the forwarding interface §5.8 DS4 proposes | DS4's forwarding interface (lanes 02, 03) |
| IT-7 | `IR/Tail.cpp:93-96, 213` | state | `runningRegions` recounted at each region's arrival: O(N²) per match | count once per match |
| IT-8 | `IR/Tail.cpp:271-278`; `IR/Effects.cpp:161-184` | (W4) | per self call, `mayRunAt` asks the recursive effects of every op up to the terminator | D9 (once per block) |
| IT-9 | `IR/Tail.cpp:282-289` | rederivation | `inTailPositionModuloContext` recomputes `contextAt` for the block at every query (`Borrows.cpp:237`, `Lifetimes.cpp:65`) | D1, D9 |

## 5. Target design

What the subsystem becomes, in the proposal's order of preference
(§4): upstream as it is, upstream patched, then ours. None of it belongs
in the solver layer: the only solve here is `Returned`'s, and it goes to
upstream's framework per function (D3); frames, TRMC, accumulation and
contification are transformations over structure (§3.1, the refutation
of §5.1 item 3). Each change ends with the one line the skill asks for.

**D1. Tail position is one fact per call, computed once.** (*conjecture*,
the design; the costs it removes are *read*.)
- *D1a, within today's representation.* One cached analysis per
  `idr.func`, `TailPositions` (nested in the `AnalysisManager`, so the
  pass manager's per-function threads each hold their own, §5.1 F1),
  built by one walk down from the function's `idr.return` through the
  tail matches: the blocks in tail position, each one's end (D5's view),
  the calls in tail position, the self tail calls, and on demand each
  tail block's context modulo a constructor (D9). Every reader asks it in
  O(1): the tail passes, `Borrows.cpp:236-237`, `Lifetimes.cpp:64-65`,
  `Stack.cpp:233-234`, `Recursion.cpp:34-35`. `endsTail`'s climb,
  `reachesTailCall`, `forTails`' callback and the per-query `contextAt` go.
  *One line:* two readers can no longer disagree about whether a call is
  in tail position, because there is one computation of it per function
  and every reader reads it (the per-query re-check is deleted).
- *D1b, if the owner wants it (§6, NQ-1): tail position in the call, as
  MLton's `Return.t` (§5.9 C3).* An inherent enum property of `idr.call`,
  `continuation = nontail | tail`, as `effects` already is
  (`IdrOps.td:210-221`): written where a call is made in or moved into
  tail position (the frontend, contify, frames, TRMC, accumulation),
  checked by the call's own verifier (the op after it passes its results
  to a return, or to the yield of a match whose result is in turn in tail
  position: a walk up the tail matches, the same cost as one query today,
  paid once per verify), and lowered into `llvm.call`'s upstream
  `tail_call_kind` (`TailCallKind::Tail`, *read*:
  `mlir/include/mlir/Dialect/LLVMIR/LLVMEnums.td:311-314`), which
  idr-tail-calls raises to `musttail`. Then `TailPosition.cpp` has nothing
  to rediscover, and idr-rc-stack and idr-tail-calls read one fact
  (TC-5). Its cost is that every pass that moves a call keeps the
  property right, under the verifier; and the call must reach `llvm.call`
  with it, which `func.call` cannot carry (DD-Q7). *One line:* "is this a
  tail call" stops being an analysis anywhere; the state where idr-rc-stack
  and idr-tail-calls answer it differently becomes a verifier error.
- *Deletes:* `endsTail`/`inTailPosition`'s per-query climb (IT-1), H-2,
  L-3, FP-5, FP-6, AP-4, IT-9, Tr-5; with D1b also TPo-5, TPo-6 and most
  of TC-5. *Depends on:* lane 03 (IR/Tail.cpp), lanes 07 and 08 (the
  readers).

**D2. Frames are the defunctionalized continuation, and their stack is
indexed by the value it waits for.** (*conjecture*, the design; the
products it removes are *read*.) A run of a closure whose result the rest
of its block consumes is a continuation; frames makes it data, a
constructor of a sum (`<f>.frames`) applied by `resume`: Reynolds's
defunctionalization of the continuation, as idr-defunctionalize does for
closures (and contify is its dual: a continuation with one return point
becomes code, D4). The representation:
- *Stacks per value type.* One data type per member result type T,
  `frames_T = empty | frame_i(held_i..., frames_O(i))` for the frames *i*
  whose value is of type T, `O(i)` the result type of the frame's owner,
  declared as one group (`Declarations::define` seals a nested group at
  once, `include/idr/IR/Symbols.h:88-118`). A run of a member of result
  type O takes `frames_O`; `resume_T` takes `(T, frames_T)` and matches
  every constructor of `frames_T`, none impossible. The invariant
  `Frames.cpp:33-35` states in a comment ("a frame whose value is of
  another type than f's result is never on top when f returns") becomes
  the type. R·(F+1) regions become F + R.
- *The answer.* Which member started a run is not in any type (the runs
  are shared by every start), so `fromAnswer`'s impossible cases are
  essential (Brooks): keep the answer sum, and give each member's match
  one case and the default region (`ub.unreachable`) instead of R cases.
  M·R becomes 2M.
- *The plan as one decision.* `FramesPlan` becomes
  `{SmallVector<ResultGroup> groups; Answer answer}` with
  `Answer = variant<OneResult, AnswerSum>` decided once, each
  `ResultGroup{Type result; Tag tag; members; frames}` and each
  `Frame{site: variant<CallSite{CallOp, FuncOp callee}, DispatchSite{match,
  cases: (Region *, FuncOp) pairs}>, owner, Tag tag, held}`, the tag
  assigned when the stack is declared. The three branches on "one result
  or a sum" (H-11, H-12, FT-1), the tag arithmetic in four places (Fr-5),
  the per-member scan of every frame (Fr-4) and the re-found case callees
  (Fr-6) go.
- *Its inputs, once.* Members by `CallCycles::componentOf` and the call's
  resolved callee (H-7); labels as idr-defunctionalize's fact, read from
  the type graph's declarations (H-8, 0003); `madeInRest` by
  `findAncestorOpInBlock` and `isBeforeInBlock` (FP-2); every resume case
  at its frame site's location (Fr-7).
- *One line:* a frame of the wrong value type on top of a resume's stack
  is unrepresentable (the `ub.unreachable` cases are deleted, not
  handled); the one-or-many answer is decided once and three branches on
  it are deleted.
- *Depends on:* lane 01 (data types, `total` as a property, Fr-13), lane 06
  (the labels' fact; FP-10's effects invariant).

**D3. Returned arguments: no whole-module solve.** (*conjecture*, the
ranking.)
1. *Seed from where the fact is known* (S0, partly): idr-optimize's
   `givesBack` summaries (0003) carried to the lowering, and every result
   they settle never solved again. The fact is not wholly known before
   lowering: a recursion that reinitializes the cell it took from its
   parameter returns "the argument" only once lowering makes the cell's
   pointer one SSA value (`Pipeline.cpp:170-172` says why the pass waits),
   so S0 seeds; it does not delete.
2. *Upstream's framework per function* (§5.1 Design 1, §5.6 Design 3):
   `ReturnedAnalysis` solved with `top` = one `func.func` in a
   function-anchored pass the pass manager runs in parallel, calls read
   through `visitExternalCall` from a table of per-function summaries
   (`SmallVector<Known>` per function, one per result), solved callees
   first over `CallCycles`' components, a recursive component iterated
   from the optimistic start until no summary rises: three points per
   result, so it ends by its lattice and has no budget (AGENTS.md). A
   value whose type no argument of its function has is known to be no
   argument at once (W-E2). With §5.1's U1 the per-value state is about
   0.2 KB; peak memory is the largest function's states times the
   threads, not the module's.
3. *Upstream as it is, for buffers:* `drop-equivalent-buffer-results`
   (`mlir/lib/Dialect/Bufferization/Transforms/DropEquivalentBufferResults.cpp:78-189`,
   *read*) drops a `func.func` result that is syntactically its
   argument, modulo `memref.cast`, revisiting callers until none changes.
   It is pessimistic (a result given back through a recursive call or an
   `scf` join is not "equivalent"), so it is the baseline D3.2 must beat,
   not a replacement.
- *Deletes:* the whole-module solve and its baseline analyses (R-1), the
  dropped `LogicalResult` (R-2), the private symbol tables (R-3), the
  second solve of `givesBack` (R-4), the three derivations of the
  partition (H-15, RA-3), and the inner pass's run-time pipeline check
  (RA-2, by not registering it). *One line:* the state model that failed at
  §3 (a lattice per value of the whole program) cannot be built by this
  pass; which results drop is one partition stored once.
- *Depends on:* lane 05 (the summary schedule, U1), lane 09 (`givesBack`).

**D4. One call graph, kept by the passes that change calls; contify where
regions allow.** (*conjecture*.)
- `CallCycles` preserved by idr-effects (which writes only effects,
  `Effects.cpp:39`), updated in place by idr-contify (the erased member
  leaves its component; nothing else changes, `Contify.cpp:29-32`), and
  extended by frames (its runs and resumes join the members' component),
  TRMC and accumulation (each clone a new component of its own, or its
  function's), so that this subsystem builds it once before the lowering
  and once after (TC-2, essential across the conversion) instead of three
  times (§5.6 Design 1's maintained graph). *One line:* a pass that
  changes a call without telling the graph is unwritable once every such
  pass updates it and preserves it by name.
- Contification stays the single-call-site case under regions (C-1,
  essential: `Contify.cpp:10-13`). With a CFG core after
  defunctionalization (Q-O1, §5.9 Design 2) it would become Fluet and
  Weeks's: one graph of functions and continuations, one dominator tree
  (`llvm::DominatorTreeBase` over a `GraphTraits` of that graph, §5.3 B8),
  `A = Uncalled | Unknown | Cont | Func` per function, and several call
  sites returning to one continuation joined at a block. That is the one
  pass of this lane that a CFG core would make strictly stronger.
- `fn.isRoot()` for the string compare (C-2).
- *The Idris side* (*conjecture*, for lanes 15 and 17): the functions
  contify moves are Idris's case blocks (`Contify.cpp:15-21`), whose one
  call site the elaborator made and whose parent the fork's TTC loses
  (0003 B1). Once the TTC keeps a block's parent as a resolved `Name`
  with its kind and ordinal, the frontend knows at the boundary which
  functions are a clause's case blocks; whether it should then emit such
  a block as a match region of its parent, so that contify's C++ only
  sees what defunctionalization and specialization make, is a question
  for those lanes (whether every case block keeps one call site through
  the frontend's own specialization is not settled here).

**D5. One view of how a tail block ends.** (*read*, the copies;
*conjecture*, the form.) In `IR/Tail.h` (lane 03):
`TailEnd = std::variant<Passes{Operation *op}, Gives{Value value},
Never{}>`, made from `hasTrait<OpTrait::ReturnLike>()` (both `idr.return`
and `idr.yield` declare it, `IdrOps.td:242`, `IdrMatchOps.td:163`) and
`passesOnPrevious`; every pass matches on it once. *Deletes:* the five
`isa<ReturnOp, YieldOp>` (IT-2, Fr-2, Tr-4, A-2), the single-op checks
(FP-3, Fr-11, TL-1, L-2, W-4), the restated `getNextNode() == terminator`
(FP-3, Fr-3) and the `getNumOperands() != 1` guards beside them. *One
line:* a tail block that never returns can no longer be read as one that
passes a value, since the view has a case for it and no caller re-tests
the terminator.

**D6. The tail-call lowering on upstream interfaces.** (*conjecture*, the
patch's acceptance.)
- *Upstream patched:* give `llvm.br`, `llvm.cond_br` and `llvm.switch`
  `BranchOpInterface::getSuccessorForOperands`, as `cf.br`, `cf.cond_br`
  and `cf.switch` have it (`ControlFlowOps.cpp:295, 579, 738`), in
  `upstream/<bug>/llvm.patch` with its report, a `tests/upstream-<bug>`
  check and a test in `mlir/test/Dialect/LLVMIR` (SCCP's dead-code
  analysis folding an LLVM-dialect branch is the upstream test, since
  `DeadCodeAnalysis` asks this method, §5.1 A7). Then `follow`
  (`TailPosition.cpp:209-238`) is `ReturnLike` plus
  `getSuccessorForOperands` and `getSuccessorOperands`: TPo-4's ladder
  goes.
- *One pass per function:* all of a function's calls answered in one walk
  sharing its `Known` state, instead of a walk per call (TPo-5); entries
  keyed by the block and an interned vector of `Known`s, not copied whole
  (TPo-2); `m_Constant` (TPo-3); `match` over the sums (TPo-1).
- `Frame.cpp`'s ladder on `ViewLikeOpInterface` and
  `SelectLikeOpInterface` (Fra-1); the set of escaped slots instead of
  `leaked` (Fra-2); `SymbolTable` for `ByName` (TP-1); `depth_first` for
  `reach` (TP-2); `ReturnRegisters` asking the target's one machine (RR-1,
  lane 13).
- With D1b, the walk is gone and `TailPosition.cpp` with it.
- *One line:* the branch ladder is an upstream interface method, declared
  where upstream already declares it for `cf`; a frame-bound call is
  decided per escaped slot, not by a flag over the whole function.

**D7. Accumulation without op-shape ladders.** `Site` as
`variant<TailCall, AddedTail>` (H-6); the countdown either a rooted
rewrite (DRR, §5.2 M13: the self call's pattern) or, better if lane 09
agrees, a closed-form fold of the accumulated loop after idr-tail-loops
(`acc + n` for a loop that adds one n times), which makes it no special
case of this pass (H-5, AP-2, AP-6); `m_Constant` (AP-1);
`getBackwardSlice` (AP-3); the tree's `match` for `Visit` (A-4). *One
line:* "a plan with no addition" is a count of a sum's case, and the
countdown is no longer a shape matched op by op.

**D8. Tail loops: the decision carries what it found.** `Decision` holds
its `CallOp` (H-4, W-2); the test "region *r* runs" is a method of
`MatchOpInterface` (`MatchOp` a tag compare, `MatchLitOp` a key compare),
which deletes the per-kind ladder in two files (TL-2); the two hoisting
predicates side by side, named for their two essential cases (TL-3);
`variant<WhileDoLoop, GeneralLoop>` for the `FailureOr` (TL-4); an
`IRMapping` per scope for `in()` (W-1); the loop at the self call's and
the match's locations (L-4). *One line:* the decision's test is declared
once on the interface and asked, not re-derived per match kind.

**D9. TRMC: the context found once.** Each tail block's context is part of
D1a's table, computed once per function and mapped into the clone through
its `IRMapping` (Tr-3, IT-9); a join's running regions counted once per
match (IT-7); the ops between a self call and the terminator walked once
per block for `mayRunAt` (IT-8); `Context::holes` non-empty by type
(Tr-2); the discardable copies deleted (Tr-1); `step`'s ladder replaced by
§5.8 DS4's forwarding interface when lanes 02 and 03 declare it (IT-6).
*One line:* TRMC, borrows and lifetimes read one context per tail block;
the quadratic join is gone.

**D10. Plans in parallel, rewrites where symbols require.** Accumulation's
and TRMC's plans read one function, frames' one component: each made by
`mlir::parallelForEach` on the context's pool into its own slot (as
`TailCallPlan.cpp:97-116` already does), then the clones' symbols inserted
serially and their bodies filled (*conjecture*: the fills of different
functions are independent once every symbol exists, as frames already
creates every run and resume before filling any, `Frames.cpp:290-329`).
*One line:* the passes' threading is stated by construction (read-only
plans in parallel, one serial insertion), not left serial by default.

*Order inside the subsystem:* D5 → D1a → D9, D8, D7 (each local, on D1a
and D5) → D2 → D4 → D3 → D6 → D10 → D1b (the owner's). *Dependencies on
other lanes:* lane 03 (`IR/Tail.cpp`, the property of D1b, `total`),
lane 01 (data-type groups, D2), lane 02 (the forwarding interface, D9),
lane 05 (the summary schedule and `CallCycles`' maintenance, D3, D4),
lane 06 (labels and effects invariants, D2; Effects preserving
`CallCycles`, D4), lanes 07 and 08 (the readers of D1), lane 09
(`givesBack`, the countdown's fold), lane 12 (`func.call` to `llvm.call`,
D1b), lane 13 (one target machine; not registering inner passes), lane
20 (the upstream patch of D6), lanes 15 and 17 (case blocks, D4).

## 6. Evidence for the owner's questions

No answers; what this subsystem's code says.

**Q-O1 (structured `match` after defunctionalization; for which passes).**
- Every `idr`-level pass of this lane reads and rewrites the region
  structure (§3.2 Q-W4): accumulation and frames find tails through tail
  matches; frames builds matches (each resume, each `fromAnswer`); TRMC's
  context crosses joins region by region (`IR/Tail.cpp:200-255`) and
  rebuilds matches through `MatchOpInterface::rebuild` (`Trmc.cpp:166`);
  tail loops inline a decision's two regions into `scf.while`
  (`WhileDo.cpp:147-172`) and rebuild every tail match with payload
  results (`Loop.cpp:90-104`).
- Tail loops want structured output: they end in upstream's structured
  tools, `moveLoopInvariantCode` and `upliftWhileToForLoop`
  (`TailLoops.cpp:176-187`), and the narrowing and vectorization after
  them work on `scf` loops. On a CFG core those loops would come from
  upstream's `lift-cf-to-scf` or not be `scf` at all.
- The structured form is what limits contification to one call site
  (`Contify.cpp:10-13`: "A second call site would need a branch out of a
  match region into a block they share, which a structured body cannot
  hold"). A CFG core would give MLton's full contification (D4).
- Tail position exists twice because the form changes at lowering:
  structural on `idr` (`IR/Tail.cpp:23-35`), a path walk on the LLVM CFG
  (`TailPosition.cpp`), the second needed because the general loop's
  payload (`Loop.cpp:7-14`) turns "tail" into a constant flag a path must
  decide. A CFG core from defunctionalization on would leave one
  definition (the CFG one); D1b would leave one without changing the form.
- Every region here is single-block by type (`IdrMatchOps.td:33`,
  `IdrOps.td:165`), and every pass relies on it (`region.front()` only):
  W-E8's precondition for a structured walk holds.

**Q-llvm-2 (budgets: none where a refusal rests; a spent optimization
budget is the pessimistic state; never an error), with Q-E3 and oom-2.**
- The subsystem has no budget, cap or round count (*measured*, §2.1), and
  refuses no program. Every pass terminates by construction: one plan and
  one rewrite per function or component (frames, accumulation, TRMC, tail
  loops), one sweep with the call graph taken once (contify), a lattice of
  finite height (`Returned`: three points per value; `TailPosition`:
  finitely many `Known`s, "so the walk ends however long the path",
  `TailPosition.cpp:301-309`).
- Its failures are internal errors, not refusals: a content name already
  taken (`TailLoops.cpp:85-87`, `FramesPlan.cpp:179-188`), a module without
  its target or machine (`ReturnRegisters.cpp:29-36`), an inner pass run
  alone (`ReturnedArguments.cpp:111-114`).
- Its limits leave code as it is and never fail: frames without a plan
  for a multi-result member or an unstorable result type
  (`FramesPlan.cpp:151, 170-171`); the general loop where the while-do
  form cannot pass a reference (`WhileDo.cpp:225-226, 238-239`); a tail
  call that may reach its caller's frame left a call (`TailCallPlan.cpp:110-113`).
  The last two touch a promise this subsystem makes about space (an IO
  loop or a mutual tail recursion runs in constant stack,
  `TailCalls.cpp:3-7`; left-nested binds run in constant stack,
  `Passes.td:430-447`), whose loss is only a statistic (`numFrameBound`)
  or nothing at all (FP-11). See NQ-2.
- Contify defers every size decision to idr-optimize's cap and stays
  inside call cycles so that the cap governs the rest
  (`Contify.cpp:21-24`): the one budget near this lane is lane 09's.

**Q-O3 and Q-E2 (facts into types or the IR; where a summary lives).**
Two facts of this lane are recomputed for want of a place: tail position
(four deciders, §3.1 on §5.9 C3; D1) and which results a function gives
back (`givesBack` decided by idr-optimize and solved again by `Returned`,
0003; D3). A summary per function is what `Returned` needs either way
(`SmallVector<Known>` per function, §5 D3.2).

**DD-Q7 (`idr.func` or `func.func`).** Carrying tail position to the LLVM
dialect (D1b) needs a call op between `idr.call` and `llvm.call` that holds
it: `func.call` has no such property, `llvm.call` has `tail_call_kind`.
`Returned` and the drop run on `func.func` today
(`Returned.cpp:164`, `ReturnedArguments.cpp:59-101`) and would move with
whatever the lowering's function op is.

**ods-Q1 and DD-Q2 (a dead divergence: kept or deletable).** idr-tail-loops
adds `idr.may_loop` (`MemWrite<Divergence>`, `MemWrite<IO>`,
`IdrCheckOps.td:46-52`) to every loop of a function without `total`
(`Loop.cpp:131-134`, `WhileDo.cpp:280-283`), "so that a loop without
effects whose results are unused" is not deleted upstream
(`TailLoops.cpp:20-23`): today's answer, written as an op per loop.

**QA1 and QA2 (patch the framework's storage first; per-function solves).**
`Returned` is the one dataflow solve here, whole-module and interprocedural
(`Returned.cpp:152-159`); it has not run on the stage-1 module (the
pipeline has never reached it, §3). Its cost at the pin is §5.1 A4's per
state times the lowered module's values; D3.2 is QA2's per-function form.

**ods-Q6, Q-M2, Q-O5 (verification after every pass).** Contify,
accumulation, frames and TRMC are passes on `idr.program`, so each pays a
verification of the whole program when it changed one component or a few
functions (§5.2 H3), though each marks everything preserved when it changed
nothing (§3.2, W9).

**New questions for the owner.**
- **NQ-1 (tail position in the call).** Should "this call is in tail
  position" be a property of `idr.call` (MLton's `Return.t`, §5.9 C3),
  written by the passes that make tail calls, checked by the call's
  verifier, and lowered into `llvm.call`'s `tail_call_kind`, so that
  neither `IR/Tail.cpp`'s per-query climb nor `TailPosition.cpp`'s path
  walk exists? Or a cached analysis per function (D1a) and the LLVM walk
  kept? It bears on DD-Q7 and Q-O1.
- **NQ-2 (the constant-stack promise).** Is "a mutual tail recursion and
  an IO loop run in constant stack" part of a program's meaning (then a
  tail call on a cycle left a call because it reaches the frame is a
  broken contract between idr-rc-stack and idr-tail-calls, an internal
  error, TC-5), or a performance property (then a statistic, as today)?
  The same question for a frames component left without a plan (FP-11):
  its left-nested binds keep their stack growth with nothing said.
- **NQ-3 (frames' stack per value type).** D2 turns one stack data type
  per component into one per member result type, a mutually recursive
  group, to make "a frame of another type on top" unrepresentable and
  delete the R·(F+1) impossible cases. Acceptable, or is one stack type
  per component (with the impossible cases moved to a default region) the
  line you want?
- **NQ-4 (case blocks at the boundary).** Once the fork's TTC keeps a
  block's parent (0003 B1), should the frontend emit a clause's case block
  in place, as a match region of its parent, so that idr-contify only sees
  what the compiler itself makes (D4)? (Lanes 15 and 17 hold the
  evidence for whether a case block keeps one call site through the
  frontend's specialization.)

## 7. Deletion list

By file and symbol; each goes with the change named.
- `lib/IR/Tail.cpp` (lane 03): `endsTail`'s and `inTailPosition`'s
  per-query climb, `inTailPositionModuloContext`'s recomputation (D1a,
  D9); the `isa<ReturnOp, YieldOp>` of `passesOnPrevious` and `contextAt`
  (D5); `runningRegions` per arrival (D9); `fieldOf`'s loop (IT-5); with
  D1b, `inTailPosition` and `endsTail` as analyses.
- `include/idr/Transforms/Tail.h`: `forTails`' callback form and
  `reachesTailCall` (D1a); `Members`, `memberCalled`, `Labels`,
  `closureLabels`, `madeInRest`'s scan (D2); `FramesPlan::answer` as a
  nullable name, `FramesMade::sum` and `answer` as a pair (D2);
  `Returned::Known`'s `get_if`/`holds_alternative` reads and
  `Function::kept()`'s recomputation (D3); `Site::addition` as an
  optional (D7); `Decision` without its call (D8).
- `lib/Transforms/Tail/FramesPlan.cpp`: `closuresRun`'s `isa` pair,
  `frameAt`'s per-op tail-position queries, `closureLabels`, the dead
  `!fn || getBody().empty()` (FP-8), the answer-name branch (D2, D1a).
- `lib/Transforms/Tail/Frames.cpp`: the `ub.unreachable` cases of
  `fillResume` (`:237-240`), the tag arithmetic (`:166-167, 230-231,
  336`), the re-found case callees (`:191-193`), the `isa<ReturnOp,
  YieldOp>` (`:119`), the per-member scan of every frame (`:150-152`),
  `failedOne` (D2, D5).
- `lib/Transforms/Tail/FramesTypes.cpp`: `asAnswer`'s and `fromAnswer`'s
  branches on `sum`, `fromAnswer`'s R-1 unreachable cases, the
  `llvm::find` tag lookup (D2).
- `lib/Transforms/Tail/Trmc.cpp`: the second `contextAt` on the clone,
  the `isa<ReturnOp, YieldOp>`, `callClone`'s discardable copy (D9, D5).
- `lib/Transforms/Tail/Accumulate.cpp`: the local `Visit`, the
  `isa<ReturnOp, YieldOp>`, the discardable copy in `retarget` (D7, D5).
- `lib/Transforms/Tail/AccumulatorPlan.cpp`: `addsOneToPredecessor`'s and
  `isCountdown`'s op ladders (to a rooted rewrite or the closed-form
  fold), `constantOf`, `dependsOnSelfCall` (D7).
- `lib/Transforms/Tail/TailLoops.cpp`, `WhileDo.cpp`, `Loop.cpp`: the
  per-kind decision test (`TailLoops.cpp:141`, `WhileDo.cpp:138-144`), the
  `FailureOr`-as-sum, `in()`'s linear finds, the re-found call, the
  `isa<ReturnOp>`/`isa<YieldOp>`/`dyn_cast<YieldOp>` checks (D8, D5).
- `lib/Transforms/Tail/Returned.cpp`: the whole-module solve and
  `loadBaselineAnalyses` (D3).
- `lib/Transforms/Tail/ReturnedArguments.cpp`: the discardable copy, the
  `dropped` recomputation, the missing-parent internal error with the
  inner pass's registration (D3, RA-2).
- `lib/Transforms/Optimize/Contify.cpp`: the root string compare, the
  `moved` flag, the un-preserved `CallCycles` (D4).
- `lib/Conversion/TailPosition.cpp`: `follow`'s terminator ladder (after
  the upstream patch), the per-call walks and per-edge `Entry` copies
  (D6); the whole file with D1b.
- `lib/Conversion/TailCallPlan.cpp`: `ByName`, `reach` (D6).
- `lib/Conversion/Frame.cpp`: the op ladder in part, `leaked` (D6).
- `lib/Conversion/ReturnRegisters.cpp`: its own machine recipe (lane 13).
- `lib/Conversion/TailCalls.cpp`: the statistic walk, the linear
  `is_contained` (TC-1, TC-4).

## 8. Risks, unknowns, measurements needed

- **R-1, `Returned` is the next wall** (*conjecture*). Its whole-module
  solve sits after lowering, where the module has the most values; the
  pipeline has never reached it on the stage-1 module, so it is
  unmeasured. Measure first: values, blocks and functions of the lowered
  stage-1 module, and the solve's peak footprint (§5.11 A2's per-pass
  record).
- **R-2, the cross-level contract** (TC-5, NQ-2). If idr-rc-stack's and
  idr-tail-calls' readings of "a tail call on a cycle" differ, a
  recursion loses constant stack with only a statistic to show it. No
  test today asserts `numFrameBound == 0` on a cycle (*conjecture*: not
  searched by this lane; lane 19's).
- **R-3, frames' silent limits** (FP-9, FP-11). A component whose result
  type no field may hold keeps its stack growth; no remark says so.
- **R-4, the residual product** (H-13): R·(F+1) + M·R regions per
  component; bindGrammar's component was the 336 s wall (16005000), so its
  R and F are the numbers to count at stage 1.
- **R-5, quadratic walks** that the stage-1 module may meet: TRMC's join
  over a wide match (IT-7), `madeInRest` over a long block (FP-2),
  `in()` over a long body (W-1), `mayRunAt`'s recursive effects over a
  match after a self call (IT-8), LICM's effect and speculation queries
  on matches in a tail loop (W4). Each is *read*; none is measured.
- **R-6, D2's group of data types.** `Declarations` seals a nested group
  (`Symbols.h:88-118`); a group of R mutually recursive stacks per
  component has not been tried (*conjecture*), and the type graph's knot
  rule (idr-knots runs before frames) must accept it.
- **R-7, the upstream patch of D6.** Whether LLVM-dialect maintainers take
  `getSuccessorForOperands` on `llvm.br`/`cond_br`/`switch` is unknown;
  until they do it is ours to carry (AGENTS.md's process).
- **R-8, D1b's maintenance cost.** Every pass that moves a call must keep
  its `continuation` right; the verifier catches a wrong one, but the
  passes that build calls (here and in lanes 06 and 09) all change.
- **Measurements needed:** at stage 1, per frames component M, R, F and
  the regions made; per function the calls in tail position and the
  length of their paths after lowering; `CallCycles`' build time and size
  on `idr.program` and on the LLVM module; `Returned`'s footprint; the
  time of each tail pass under `-mlir-timing`.

## 9. Sources read

- `.claude/skills/representation-first/SKILL.md` (whole); `AGENTS.md`;
  `proposals/0000-mlir-native.md` (whole, lines 1-11141: §0-§4, every lane
  of §5, §6-§9); `proposals/0003-facts-once.md` (whole);
  `audits/p0/README.md`.
- The subsystem, line by line: `foreign/idr/lib/Transforms/Tail/{Accumulate,AccumulatorPlan,Frames,FramesPlan,FramesTypes,Loop,Returned,ReturnedArguments,TailLoops,Trmc,WhileDo}.cpp`;
  `foreign/idr/lib/Transforms/Optimize/Contify.cpp`;
  `foreign/idr/lib/Conversion/{TailCalls,TailCallPlan,TailPosition,ReturnRegisters,Frame,PassThroughMemory}.cpp`;
  `foreign/idr/include/idr/Transforms/Tail.h`;
  `foreign/idr/include/idr/Conversion/{TailCallPlan,TailPosition,ReturnRegisters,Frame,PassThroughMemory}.h`;
  `foreign/idr/lib/IR/Tail.cpp`, `foreign/idr/include/idr/IR/Tail.h`.
- Beside it, as read: `foreign/idr/include/idr/Transforms/Passes.td`
  (`:1-60, 195-240, 420-480, 620-680, 805-900`);
  `foreign/idr/lib/Transforms/Pipeline.cpp` (whole);
  `foreign/idr/include/idr/Analysis/CallCycles.h`,
  `foreign/idr/lib/Analysis/CallCycles.cpp` (whole);
  `foreign/idr/include/idr/IR/IdrOps.td:100-270, 365-395`;
  `foreign/idr/include/idr/IR/IdrMatchOps.td:1-190`;
  `foreign/idr/include/idr/IR/IdrCheckOps.td:40-60`;
  `foreign/idr/include/idr/IR/Symbols.h:84-140`;
  `foreign/idr/lib/IR/ContentNames.cpp:1-60`;
  `foreign/idr/lib/IR/Effects.cpp:161-184` (`mayRunAt`);
  `foreign/idr/include/idr/Support/{Actions,Worklist}.h` (heads);
  `foreign/idr/lib/Analysis/Recursion.cpp:25-45`,
  `foreign/idr/lib/Analysis/Ownership/Borrows.cpp:225-245`,
  `foreign/idr/lib/IR/Lifetimes.cpp:55-70`,
  `foreign/idr/lib/Transforms/Stack/Stack.cpp:30-48, 222-240`,
  `foreign/idr/lib/Transforms/Effects/Effects.cpp:39`.
- Pinned upstream (`.toolchain/llvm-project/mlir`):
  `include/mlir/Interfaces/ControlFlowInterfaces.td:80-100, 415, 630-645`;
  `include/mlir/Dialect/LLVMIR/LLVMOps.td:294-298, 649-662, 956-1026,
  1090-1094, 1125-1260, 2571-2592`; `include/mlir/Dialect/LLVMIR/LLVMEnums.td:308-316`;
  `lib/Dialect/ControlFlow/IR/ControlFlowOps.cpp` (`getSuccessorForOperands`,
  by grep); `lib/Dialect/Bufferization/Transforms/DropEquivalentBufferResults.cpp`
  (`:1-200`).
- History: `git log --oneline` of every file above (21 commits); `git show`
  of 16005000 (message, stat, the `Frames.cpp` diff), b0b9fbe2 and
  0c98b266 (messages), 2c042728 (the `Returned.cpp` diff).
- Measurements: the `wc -l` and `grep -c` commands of §2.1; the greps of
  §3 (`isa<ReturnOp, YieldOp>`, `setDiscardableAttr\|->setAttr(`,
  `MatchAnyOpTypeTag`, the W3 interface methods, budgets, per-target
  words, the headers' readers, the tests naming each pass).
