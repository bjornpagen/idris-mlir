<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 synthesis B: the analyses and the solver layer

Reader B, 2026-10-21. Read in full: the representation-first skill,
AGENTS.md, the proposal's §0–§4, §5.1, §5.3, §5.4, §5.6, §5.7, §5.9, §6,
§8, §9; lanes 05, 06, 07, 09, 21; lane 20 §3–§5; §5–§6 of lanes 08, 10,
11, 13, 16. A citation "07 §4 G-09" is `audits/p0/07-ownership-analysis.md`,
section 4, row G-09; "§5.1 A4" is the proposal. Nothing here is decided
except what the owner ruled; §5 lists the decisions left.

**Owner ruling relayed by the coordinator (2026-10-21):** "heavy use of
templates and concepts pls". Our own C++ is concept-constrained templates
by default: the solver layer, the shared graph and state types and pass
internals; callbacks become templates; ladders over our own types become
concept-constrained overloads or one fold over a closed sum; MLIR
interfaces stay where the op set is open; a concept may read ODS facts,
never list ops. §8 Q1, Q-M3, Q-llvm-1 (and cxx-Q1 with them) are settled
that way. Every change is a hard cutover that culls the old code. §2's
design is written in those terms.

## 1. In plain words

**What this cluster is.** Every place the compiler works a fact out by
solving instead of reading it: the call graph and its cycles, effects,
what a function gives back, binding times, constants, integer ranges, the
closure-label solve, deduplication, exclusivity, borrows, the stack-cell
inference, the optimizer's schedule; and who runs each solve on which
thread.

**What is wrong today.**
- Each honest solver has its own graph type, worklist and numbering,
  keyed by pointer through hash maps (05 §2.6; 21 P-14). Dense ids are
  minted separately in at least six places (05 §2.6). "Build a graph
  once and mark it", the idea that fixed three walls, was written three
  times in two days with no shared code (20 §3.4, H17).
- Facts are rebuilt instead of kept. The call graph and its cycles are
  built up to seven times per compile, because no pass preserves them
  (05 §2.2, CC3). Four whole-program `SymbolUserMap`s exist only to find
  callers (05 §3.1). What a function gives back is solved by the
  optimizer, dropped, and solved again on the lowered module (05 R5,
  10 §5 D3). Tail position is recomputed per query by seven readers
  (05 R3).
- Three whole-program solves still sit on upstream's `DataFlowSolver`
  with a heap state per value: Ranges, Returned, Borrows (05 §2.3).
  Ranges and Returned have never run on stage 1; they are the likeliest
  next walls (05 §8, 21 §3.4).
- Upstream was adopted with no scale test and dropped with no patch:
  exclusivity went onto the framework (595ed341) and off it after a
  627 GB kill (ffa91113), no storage patch tried; Borrows went onto it
  three days earlier (20 §3.3, §4.2 item 1).

**What "undo the damage of replacing upstream" turns into.** Not putting
the markings back on `DataFlowSolver`. Wave 1 showed the framework failed
on two container choices, about 2.9 KB per one-bit fact, cut about 15× by
a two-line patch (§5.1 A4). Wave 2 showed that what left the framework is
not per-value sparse dataflow: exclusivity is a gated two-point marking
across both call directions (07 §3.1 rows 5, 9); Borrows is a marking the
framework adds no algorithm to (07 §3.1 row 1); Recursion and BindingTimes
hold no per-value lattice (05 §3.1); frames' plan solves nothing
(10 §3.1). So the phrase becomes four jobs:
1. **Patch upstream's storage (U1) and measure**, because §4's order
   requires it and history skipped it (20 L1). It changes the outcome
   only for solves not yet run on stage 1 (05 §6 QA1).
2. **Keep upstream's sparse framework where a problem is per value inside
   one function**: idr-constants (already so, and run at stage-1 scale,
   05 §3.1), narrowing's per-loop Copy (05 §2.3), Ranges if made per
   function (05 T5.7, 11 C8), Returned unless carrying the fact deletes it
   (05 T5.5, 10 D3).
3. **Use much more upstream machinery that is not a solver**: the
   `AnalysisManager`'s caching and preservation, `CallOpInterface` and
   `scc_iterator` through `GraphTraits`, actions and debug counters,
   upstream SCCP's rewrite and dataflow listener exported instead of
   copied (05 CO1, NL1), `OperationEquivalence` with a symbol hook instead
   of our dedup hash (06 U-8..U-12), interface methods a match overrides so
   every query is per op (§5.1 C4, 05 T5.11).
4. **Put what upstream has no mechanism for into one honest solver
   layer**: the label solve, exclusivity, borrows, the stack inference,
   summaries over the call graph in both directions, dedup's partition,
   signature demand bits (05 §5, 06 §5 "What belongs in the solver layer",
   07 D2–D3, 08 T9, 09 T5).

## 2. Where the lanes agree: the consensus design

**2.1 The call graph: one, maintained, dense.** `ProgramGraph`, an
`AnalysisManager` analysis on `idr.program` (and one on the lowered
module): `FunctionId` minted only by the graph, callees and callers as
compressed rows, call sites per function, SCCs bottom-up as id ranges,
the self edge, the recursion bit (05 T5.1; §5.6 Design 1; 09 T1; 10 D4).
Built in one parallel walk and one serial link through `CallOpInterface`,
kept current in place by the passes that know their edits (contify,
the optimizer), preserved by name by passes that change no call (05
T5.10; 09 OPT-30). It deletes `CallCycles`, `Recursion`, the caller-only
`SymbolUserMap`s, nine name-keyed membership maps (05 R9) and the
optimizer's second walk of every body (09 OPT-29). `idr.call` already
implements `CallOpInterface` (05 §3.2). Cost: a few MB at 70,000
functions (05 T5.1, *conjecture*).

**2.2 The state representation: dense ids, arrays, bits.** Per node, a
slot in a vector indexed by a dense id, never a map per node (§5.3 B7,
I7; §5.7 M9). Typed ids whose index vector deletes raw-integer access
(§5.5 D3, 05 T5.2, 07 D7). A one-bit fact is a bit (0.13 B against
2.9 KB, §5.1 A4). State only for values whose type leaves the question
open, read off a type interface (§5.6 Design 2; 07 D6; 08 §3.1). Answers
frozen and cached, never handed by constructor (05 AM5, 07 O-01).

**2.3 The scopes of a solve.** Three shapes (§5.6 Design 1), and wave 2
sorts every analysis into them (05 §6 Q-E1):
- *Per function* (shape L): upstream's framework with `top` = one
  function, summaries through `visitExternalCall` (§5.1 A6). Built
  already for idr-constants (05 §3.1). Candidates: Ranges, Returned.
- *Summaries over the call graph's SCCs* (shape S), callees first and
  callers first: effects, observability, Identities, inline facts,
  Borrows per parameter, Ranges' argument and return summaries, signature
  demand (05 T5.3; 06 T3; 09 T5; 11 C8).
- *Extract, solve, write back* (shape G): label solve, exclusivity, the
  stack inference, dedup (06 T2, T4; 07 D2; 08 T9).
Nothing keeps whole-program per-value state on the framework after the
cutover (05 T5.9).

**2.4 The schedule.** SCCs from `scc_iterator` over our graphs'
`GraphTraits` (with `getNumber`), no copy (05 SC1–SC3; `Scc.cpp` is not
hand-rolled Tarjan but copies the graph three times, 05 §3.1). Inside an
SCC, iterate until no summary changes; finite lattices end it with no
count (§5.6 item 3; 05 T5.3). A component is queued when its count of
unfinished callees reaches zero, not by rescanning (09 T1, OPT-36).
Markings propagate per edge: a node that rises walks its row once
(07 D2; §5.9 B4).

**2.5 Threading.** The contract upstream supports: whole-program facts
computed once at program level, read through `getCachedParentAnalysis`
by nested function passes the pass manager runs in parallel (§5.1 F1).
Lane 13 names it decide / apply / restructure (13 T1). Extraction runs per
function in parallel; solves are serial or by SCC wavefront; no lock on a
state a solve reads; no attribute or type made on a solver's hot path
(§5.1 F3; §5.3 M8; §5.7 M8). The context's pool only (§5.3 D1; the tree
already complies, 05 §2.5). Modular's three tiers (immutable inputs, a
cache per worker, state per function) stated in each header (§5.4
Design 2).

**2.6 Budgets.** An optimizing analysis may stop at a budget in program
units and finalize pessimistically, reporting success; an analysis a
refusal rests on has no budget and ends by its lattice (§5.3 M9; §5.6
item 5). Every lane finds the tree already complies: no budget fails
anywhere in this cluster (05 W-E5; 06 §3.2; 07 W-E5; 09 §6; 10 §6;
16 §6).

**2.7 Measurement as part of the layer.** Each unit (a function, an SCC)
is an action, so traces name it and `-mlir-debug-counter` bisects it
(§5.1 G2); none of the three newest solvers is (21 §3.2). Each header
states what upstream lacks, the measurement, and the state's size in
program units (§4; §5.11 A1). A footprint report per pass (§5.9 Design 6;
13 T5).

**2.8 Interface queries once per op.** Enumerate an op's edges once,
never per region (§5.1 C1–C4; §5.7 M3). e96bb991 did it for exclusivity;
residues remain (07 X-09, A-12; 05 IQ1; 10 §3.1 TRMC's join).

**2.9 The layer in concept-constrained templates (the ruling).** The
lanes' sketches agree on the pieces (§5.3 S1; §5.5 D3; §5.4 Design 1;
§5.6 Design 1; 05 T5.2; 07 D7):
- `Id<Tag>`, `IndexVector<Id<Tag>, T>` (raw index `= delete`).
- `concept Graph`: `size`, `successors(Id)`, `predecessors(Id)` as spans;
  `Csr<Tag>` its one model, with `GraphTraits` so `scc_iterator`,
  `post_order` and `GenericDomTree` take it.
- `concept Lattice` (`bottom()`, `join` returning `enum class Changed`);
  `concept Summary` (a lattice keyed by `FunctionId`).
- Direction as a type (`Forward`, `Backward`), never a `bool`
  (08 C-51's `bool backward`).
- `mark<Direction>(const G &, seeds) -> BitVector` for plain markings;
  `mark<Direction, Gates>` where `Gates` is a concept giving each edge's
  gate node and switch, for exclusivity (07 §3.1 row 9, D2).
- `solve<CalleesFirst | CallersFirst>(const ProgramGraph &, T &&transfer)`
  returning `SummaryTable<S>`; `transfer` a template parameter, never a
  `function_ref`.
- `concept Extractor`: per-function arrays with a base offset, linked
  serially (shape G).
- Each solver one explicit instantiation in its own translation unit,
  `extern template` in the header (Q-llvm-1 settled); compile time
  measured (§5.5 finding 13: a template callback costs 2–3× a
  `function_ref` to compile).
- Transfers dispatch once over ops through interfaces (or a `TypeSwitch`
  inside one pass), typed code below; a concept may read a trait, never
  list ops (cxx-Q1).
- Culled in the same change: the callbacks 05 §3.2, 06 D-10, 07 O-08 and
  X-03, 09 OPT-08 and 21 P-19 list; `specialize::Schedule`'s one-implementation
  `virtual` (09 OPT-22); the item-kind switch (07 A-07); the key ladder
  (09 OPT-60).

## 3. Where they disagree, and what each disagreement turns on

**3.1 Does upstream's framework come back, and for what?** §5.1 Design 1
(recommended) puts every per-value sparse problem back per function after
U1, including "`Recursion`, `BindingTimes`, `Ranges`' return ranges"
(§5.1 5.1.2 item 2). §5.4 (Modular uses no `DataFlowSolver`, F2) and §5.9
Q-O2 (MLton's interpreter as *the* layer, the framework only where its
state fits) lean the other way. Wave 2 narrows it: Recursion and
BindingTimes are refuted as lattices (05 §3.1); Borrows is a marking
(07 §3.1 row 1; 05 §3.1); a return re-imports the baseline coupling that
cost exclusivity two bugs before memory did (4108916a, e8e38bd7; 07 §3.1
row 3) unless U4 lands upstream. *Turns on:* the measured footprint of
Ranges and Returned per function after U1, and whether Returned is deleted
by a carried fact (Q-AN1).

**3.2 One engine, or shared pieces?** S1 (§5.3: one graph, one state
vector, a worklist schedule), §5.9 Design 1 (cells with handlers, a
domain concept), §5.7 L2 (one scope, a product solve) and L4 (relations,
union-find) each propose one engine. Wave 2's misfits: exclusivity needs
gates, a target switch and a made-label stratum (07 §3.1 row 9, D2); the
label solve's graph grows during the solve, so a frozen CSR serves its
input, not its state (06 §3.2); Identities is a greatest fixpoint (05
§6 Q-O2); BindingTimes is relational (05 §3.1); the optimizer inserts
nodes and merges SCCs mid-solve (05 §3.1; 09 §3.1). *Turns on:* whether
"one layer" means one algorithm or one set of types (§5 B2).

**3.3 Frames' plan.** §5.1 item 3 and §5.6 item 6 put it in the layer;
lane 10 refutes: one structural walk, no state per point, no solve
(10 §3.1). *Turns on:* nothing to decide; §5.1 item 3 is wrong here.

**3.4 SSI as the cure for per-point state.** §5.7 M1/L1 says the 627 GB
was a dense formulation and SSI deletes per-point state in exclusivity,
borrows and stack lifetimes. Lane 07: the removed solve was already
sparse; what was dense was the dead-code baseline and A4's containers;
exclusivity and Borrows keep no per-point fact; the per-point facts left
are deaths, which are liveness (07 §3.1 rows 13, 14). Lane 08: counting
undoes one binding SSI would keep (08 §6 QL2). *Turns on:* QL2, which
cluster A owns; this cluster gains nothing from it beyond what exists.

**3.5 SCC wavefront: new, or built?** §5.6 item 7 says no precedent, ours
to design. Lane 05: idr-optimize already runs one, dynamic besides
(05 §3.1; 09 §3.1). The rest of the cluster is serial (05 §2.5; 06 §2.7;
07 §2.4). Lane 09: the barrier between waves is MLIR's, since a dynamic
pipeline needs an op nested under the pass and nesting an analysis
manager is not thread-safe (09 T1, `Pass.cpp:574-591`). *Turns on:* the
idle time per wave on stage 1 (09 §8 item 1).

**3.6 SCCGraph and the optimizer.** §5.4 Design 1 deletes "optimize's
own bottom-up scheduling". Lanes 05 and 09: `SCCGraph` has neither
insertion nor merge; the optimizer needs both, essentially (specialization
makes functions while summaries are pending) (05 T5.3; 09 T1). *Turns
on:* Q-AN2.

**3.7 Upstream's `CallGraph` or our own.** §5.6 Design 1 builds on
`CallOpInterface`; §5.4 Design 1 allows `mlir::CallGraph` if cheap. Lane
05: every client wants dense ids and callers, which upstream's graph does
not give; `eraseNode` is O(nodes) (05 T5.1). *Turns on:* Q-E5.

**3.8 The per-function scope and numbering: three designs on one code
path.** 101edbc5's `Positions` (spans per function, landed on main);
lane 07 D5 (a scope analysis with a block-start sentinel, shared with the
verifier's `Numbering`); lane 08 T3 (placement as one reverse walk that
needs no position queries) (21 §3.6, §5.4). *Turns on:* perf-Q2 and
Q-llvm-3; cluster C owns placement.

**3.9 Where cross-pass facts live.** Effects already live in the IR as a
verified property (05 T5.0; 06 §6). Lanes 05 and 10 want tail position
and "gives back argument i" as call and function facts the same way
(05 T5.0, T5.8; 10 D1b); 10 D1a offers a cached analysis instead; §5.6
Q-E2 and §5.9 Design 3 frame the choice. *Turns on:* Q-AN1 / tail-Q1,
which depend on cluster A's function op (DD-Q7).

**3.10 Effects: a pass after defunctionalization, or one summary
before.** Lane 06 folds idr-effects into defunctionalization's decision,
one summary over calls and label runs in MLIR's resources, also deciding
`by_name` (06 T3). Lane 05 keeps a summary pass over `ProgramGraph`,
result as today's property (05 T5.3). *Turns on:* defunc-Q2 and cluster
A's resource tree (eff-Q1).

**3.11 With AGENTS.md.**
- §5.1 Design 1 iterates a recursive SCC "up to a budget that only leaves
  facts less precise". Fine for optimization summaries; not for
  exclusivity, which a refusal rests on (07 §1; §5.6 item 5).
- The proposal's lists of acceptance analyses ("knots, the in-place
  promise"; "defunctionalization, the label solve, counting, lowering")
  omit the frontend's growth check and reachability walk (16 §3.1) and
  name exclusivity only through "the in-place promise". The list should
  be exact so no later change budgets one.
- Exclusivity's precision decides acceptance (07 §6 rc-Q2; own-Q2): a
  precision fix (07 D1) or a redesign (07 D2) moves which programs pass.
  AGENTS.md says acceptance is the program's, never the optimizer's.
- 09 OPT-83: optimizer comments cite designs and papers, which AGENTS.md
  says comments do not do.

## 4. Suspected bugs and rule violations

| what | where | ground | lane |
| --- | --- | --- | --- |
| A crash case (`ub.unreachable`) counts as a predecessor whose operands are unknown; when live, every input of every successor of its match is shared. Every memo force and non-covering function. Precision loss on the path `unsupported (uniqueness)` rests on | `ExclusivityGraph.cpp:208-222`, `ExclusivityAnalyses.cpp:236-243` | read; effect conjecture | 07 G-09, D1; 21 P-11 |
| `Positions` corrupts under counting's own rewrites: `make test` 403/480 against 470/480; overlapping spans of a match's case blocks | `Positions.cpp` (101edbc5) | measured by the agent (51a4771b) | 21 P-1, P-16 |
| `decides` silently narrowed to five idr ops; the owned verifier still calls `scf.if`'s regions alternatives: two classifiers differ | `Positions.cpp:211` vs `Linearity.cpp:27-33` | read | 21 P-3 |
| `Idr_Decides` restates `RegionBranchOpInterface`; its `verifyTrait` re-asks it per region of every such op on every verification | `IdrBase.td:295-303`, `Traits.h:133-147` | read | 21 P-5 |
| The inline step and effect stamps mutate a function outside any pass; the nested analysis manager is not invalidated; CSE may read stale `DominanceInfo` | `Component.cpp:73-81, 148-160` | read; effect conjecture | 09 OPT-14 |
| Determinism leak: a node's request chain in lock order, so the lifted key, and the node, can depend on the schedule | `Requests.cpp:91-104, 153-155, 194-200` | read; occurrence conjecture | 09 OPT-48 |
| A global mutex over the node table across embedding checks, lifts and canonical printing; keys, names and types made on workers in the context, never freed | `SpecializeState.h:50-62`; `Keys.cpp`, `Order.cpp` | read | 09 OPT-49, OPT-64 (§4's "no global lock on a hot path" unmet) |
| Defunctionalization builds and freezes a pattern set of one pattern per registered op, per function: functions × registered ops | `Pass.cpp:87-100`, `Patterns.cpp:274-285` | read; measured at suite scale (populate 4.7 %, freeze 4.3 %, destroy 1.9 % of test-idr) | 06 D-3; 21 P-6 |
| Exclusivity's op successor re-joins all N predecessors per run: O(N²) on a wide match | `ExclusivityAnalyses.cpp:244-251` | read | 07 A-12; 21 P-12 |
| `isRepetitiveRegion` asked per terminator of a match from idr-rc-stack: O(N²) bytes zeroed per match | `IR/Lifetimes.cpp:50-54` | read | 05 IQ1 |
| TRMC's join recounts a match's running regions at every arrival: O(N²) | `IR/Tail.cpp:200-216` | read | 10 §3.1 |
| Label solve re-sweeps every downstream class each wave and scans every dispatch each wave: O(W·(P+E)) + O(W·D) | `Labels.cpp:218-228, 288-298` | read; W unknown | 06 L-10, L-11 |
| Exclusivity re-solves the whole program and rebuilds its graph per dropped memo label; solved twice per pass; not an analysis | `Exclusivity.cpp:73-122`; `Exclusive.cpp:39-52` | read | 07 E-01, A-01; 21 P-13 |
| Dedup builds two uniqued dictionaries per op per hash and per compare side, from workers, under the context's locks | `Equivalence.cpp:69, 101-102, 143-146` | read | 06 U-9..U-11 |
| Three graph or numbering types written in twelve hours, no shared code, none an action, two serial and whole-program | b8301ebe, ffa91113, 101edbc5 | read | 21 P-14; 20 H17 |
| Upstream adopted without a scale test and dropped without a storage patch; `remove-dead-values` dropped on a manual stop at 52 GB, its replacement claim unmeasured; patches 06, 28, 63 now reach nothing | 595ed341, ffa91113, 16005000 | read | 20 H1, H2; 21 P-9 |
| Pass description says "a sparse dataflow analysis finds the labels"; it is a union-find inclusion solve | `Passes.td:127-133` | read | 06 L-17 |
| `MonotoneWorklist`, `FiniteLattice`: dead | `Worklist.h:52-153` | measured | 05 WL1, WL2 |
| `Recursion.cpp:30`, `Effects.cpp:63`: `mlir::parallelFor`, the right pool | | read | 05 §2.5 (no violation) |

**Predicted next stage-1 walls** (none measured; 21 §3.4 tabulates the
agent's record against each):
1. Ranges / idr-narrow: one whole-program interprocedural solve, two
   lattices per value, re-solved after versioning; held alive through a
   nested pass (05 RA1–RA3, §8; 11 §6). The nearest unmeasured solve past
   the frontier (21 §3.4).
2. Returned on the lowered module, where V is largest (05 RT1; 10 D3).
3. idr-rc-exclusive on the module itself, not a fixture: the O(N²)
   re-join, the crash-case sharing, the outer re-solve (07 §8).
4. idr-rc-grades once `Positions` is fixed: inserts × block size (21 P-4).
5. Defunctionalization's per-function pattern freeze (06 D-3) and the
   label solve's waves on CPS-shaped code (06 §8 item 2).
6. The verifier after every pass, including `effectsCovered`'s
   whole-program walk (05 EF10; 13 §6 ods-Q6).
7. `RecursiveMemoryEffects` on a match: every `wouldOpBeTriviallyDead` in
   idr-constants walks its body (05 §3.1).
8. The optimizer on a giant SCC: BindingTimes O(members × reach), serial
   turns, `enable` rescans (05 §8; 09 OPT-36, OPT-39).

## 5. The decisions this cluster hinges on

Settled by the ruling, not repeated below: Q1, Q-M3, Q-llvm-1, cxx-Q1.

**B1. Upstream's framework: patch first, and at what scope.**
IDs: QA1, QA2, Q-AN3, hist-Q1, Q-E5 (its second RFC).
- *Options.* (a) U1 as P1 (two declarations) or P2 (flat map and typed
  arenas), then per-function solves for Ranges and Returned; (b) U1, then
  whole-program solves wherever measured small (§5.1 Design 2); (c) no
  return beyond what is already per function (idr-constants, Copy); Ranges'
  cross-call facts as our summaries over upstream's per-function solve.
- *Evidence.* U1 cuts the fixed cost about 15× (§5.1 A4); it changes only
  solves not yet run (05 §6 QA1). P2's per-type freeing has no client:
  every solve drops its solver whole (05 §6 QA1). idr-constants is the
  per-function design, run at stage-1 scale (05 §3.1). Ranges' precision
  on naturals' arguments comes from joins over callers, which a
  per-function form rebuilds as a callers-first summary; inside a
  recursive SCC upstream's 128-merge widening already gives that up
  (05 §6 QA2; 11 §6). Returned needs one bit per (result, argument), far
  less than its per-value state (05 §6 QA2). No patch was tried before
  either drop (20 §3.1). No backward analysis exists, so U2 matters only
  if per-function `remove-dead-values` returns (05 W7).
- *Depends on.* B5, B4 (Returned), cluster E's stage-1 record (Q4,
  perf-Q3, drv-Q1), cluster A's match interface overrides and
  `RecursiveMemoryEffects` decision.

**B2. The solver layer: one engine, or one set of types?**
IDs: QA4, Q-O2, QL1, QL3, Q-llvm-3, Q-E1. (§8.4 already groups QA4, Q-O2,
QL1, Q-llvm-3.) The ruling fixes the form (concept-constrained templates,
one instantiation per solver) and presumes shared graph and state types,
which is QA4's direction.
- *Options.* (a) One engine: S1's worklist (§5.3), MLton's cells with
  handlers (§5.9 Design 1), or L2's product solve (§5.7); (b) shared types
  only (§2.9's pieces), each solver its own algorithm stated in its
  header; (c) rules over relations (Flix, Soufflé; §5.7 D4, QL3).
- *Evidence.* Misfits for one engine (§3.2 above). The label solve's
  reading is already rules as data, read by two engines (the solve and the
  `labels-least` oracle, 06 §6 QL3); elsewhere composition is one-way
  frozen reads, no mutual dependence (05 §6 QL3). Numbering is per solve
  today, six times over; MLIR's block numbers unused (05 §6 Q-llvm-3); two
  per-function numberings exist (`Positions`, the verifier's `Numbering`,
  21 P-2). A scoped read-only view already exists in Identities' `Record`
  (05 §6 QL1).
- *Depends on.* B9 (numbering), cluster C (which markings counting reads),
  cluster A (the type interface that filters a solver's domain).

**B3. The call graph and its schedule.**
IDs: Q-M1, Q-AN2, Q-E5 (first RFC), Q-E4, Q-M4, Q-llvm-7.
- *Options.* Graph: on `mlir::CallGraph` or ours on the interfaces.
  Schedule: static only, the optimizer its one dynamic client; or a schedule
  with insertion and merge for all. Code: port Modular's `SCCGraph` (header
  kept, `PINS.md` entry) or write fresh. Giant SCC: serial, or lld's
  double-buffered rounds.
- *Evidence.* Three schedules exist (`CallCycles`' static order, the
  optimizer's dynamic wavefront, dedup's waves by height with a barrier
  per height) (05 §6 Q-M1). Contify and the optimizer know their edits
  exactly (05 §6 Q-E5). SCC sizes on stage 1 are recorded nowhere (05 §6
  Q-llvm-7). Little of Modular's dedup remains in our port (06 §6 Q-M4).
- *Depends on.* Cluster E's pipeline (13 T1), B8.

**B4. Where facts that cross passes live.**
IDs: Q-AN1, tail-Q1, Q-E2, Q-O3, count-Q4, defunc-Q2, DD-Q7.
- *Options.* An inherent property verified like `effects` (call: tail
  kind, conventions; function: `gives_back`), or a cached per-function
  analysis read by every client.
- *Evidence.* Effects are the precedent, checked in `verifySymbolUses` and
  after every pass (05 T5.0). Carrying `gives_back` deletes the
  whole-module Returned solve, unless lowering splits results beyond it
  (05 §8; 10 D3 ranks carrying above per-function). LLVM's `tail_call_kind`
  can receive a tail fact; `func.call` cannot carry it (10 §6 DD-Q7). Both
  exclusivity's and Borrows' answers are already written into signatures
  (07 §6).
- *Depends on.* Cluster A (properties, function op), cluster C (tail,
  counting conventions, lowering).

**B5. Dead parameters and results.**
IDs: QA3, Q-opt-4, hist-Q3.
- *Options.* Split `remove-dead-values` (upstream per function, our
  signature solver); whole module on the patched framework; or a demand
  bit per parameter in the optimizer's summary, results by a callers-first
  pass (09 T5).
- *Evidence.* Already out of the pipeline (16005000); no idr pass erases
  an unused parameter since; spec nodes keep a parameter per hole whether
  read or not (09 OPT-75, §6 QA3). The claim that specialization and
  counting cover it is unmeasured (21 P-9). Narrowing a function named by
  a closure label must count that use as an unknown caller (09 §8 risk 4;
  upstream 29's lesson).
- *Depends on.* B3 (callers-first direction), B1.

**B6. Budgets, and the exact list of acceptance analyses.**
IDs: Q-llvm-2, Q-E3, oom-2, canon-Q2.
- *Options.* Confirm the line of §2.6 as written; name the acceptance
  analyses exactly (exclusivity, knots, the label solve, defunctionalization,
  the growth check, the reachability walk) or leave the categories general.
- *Evidence.* No budget fails anywhere in the cluster (§2.6). Every
  optimizer budget is in ops or calls (09 §6). The frontend's acceptance
  analyses have no budget at all (16 §6).
- *Depends on.* Cluster D (frontend's list), cluster C (knots).

**B7. What specifies exclusivity, and its engine.**
IDs: own-Q2, count-Q1, rc-Q2, own-Q3 (with count-Q2/own-Q1 as neighbours).
- *Options.* The refusal defined by the analysis's answer (more precision
  admits more), or by a declarative rule the analysis must decide exactly,
  tested at its boundary; grade copies kept inside counting, or a key of
  the one specializer.
- *Evidence.* idr-demand refuses on the grades exclusivity writes
  (07 §6 rc-Q2). D1 can only grade more values exclusive (07 D1). D2 keeps
  today's answer by design (made labels as a stratum, run bits only rise)
  and needs a corpus comparison before the old solve goes (07 §8). The
  promise is read off reuse's output, so an optimization's choice can
  decide a refusal (08 §6.1 NQ1).
- *Depends on.* Cluster C (counting, demand), B2.

**B8. Threading and determinism.**
IDs: QL4, Q-llvm-6, drv-Q3, Q-opt-3, perf-Q1.
- *Options.* Byte-identical output at any thread count as a requirement;
  a one-thread-against-many test per solver; decide/apply/restructure as a
  pipeline rule; keys as the run's interned data outside the context; the
  parallel agent fenced to measurement.
- *Evidence.* The harness already compares whole pipelines at 1, 3, 5 and
  13 threads; no solver is compared alone (13 §6 QL4, Q-llvm-6). OPT-48
  leaks the schedule into a node (09 §4). Keys are held by no op
  (09 T3). The agent changed this cluster's code nine times in eighteen
  hours, two commits after every lane read it (21 §3.5, §6.1 Q2).
- *Depends on.* Cluster E.

**B9. The per-function scope and numbering.**
IDs: Q-llvm-3 (its scope half), perf-Q2.
- *Options.* Repair `Positions` toward one scope analysis shared with the
  verifier (block-start sentinel, listener invalidation); revert to
  e96bb991's queries; or let counting's reverse walk delete the queries
  (08 T3).
- *Evidence.* 21 P-1, P-2; 07 D5; 08 T3.
- *Depends on.* Cluster C (placement), B2.

**B10. The label solve, dedup and the specializer's shape.**
IDs: defunc-Q1, defunc-Q3, defunc-Q4, Q-O4, ft-Q3, Q-M5, Q-opt-1, Q-opt-2.
- *Options.* Dedup by partition refinement (merges cycles) or CIRCT's
  barrier-free hashing (keeps the exclusion); types-first conversion or the
  dialect conversion; one sink per operand or coercion per sink;
  polyvariance before the label solve (in the frontend or C++); inlining
  interleaved with specialization or decided once after it; a made node's
  call count.
- *Evidence.* Sums are already one per flow set (06 §3.1). Specialization
  recovers per-site labels only where an `idr.con` chain is visible at the
  call (09 §3.2 Q-W5). Five rules followed five unrollings (09 OPT-84).
  Dedup must run before any polyvariance step or merge it back (06 §6
  Q-O4).
- *Depends on.* Cluster D (frontend polyvariance, ft-Q3), cluster A.

## 6. Order of work inside the cluster, and dependencies

A suggested order from the lanes' own orders (05 T5.14; 06 §5; 07 §5;
09 §5; 20 §5.2 item 3; 13 §5; 21 §5.1). Each step a hard cutover: it
deletes what it replaces in the same change and passes the five suites
and a stage-1 run before the next (20 L2).
1. **Measure first** (cluster E): the footprint record per pass, a census
   pass (V, B, P, F, SCC sizes, match widths), actions around every solve;
   main green again (`Positions`, perf-Q2). Every later step is judged
   against it (13 §5 order item 1; 21 §5.1).
2. **U1 upstream patch, measured** on Ranges, Borrows and Returned
   alone, in parallel with step 3 (20 §5.2 item 3; B1).
3. **Shared types**: `Id`, `IndexVector`, `Csr` with `GraphTraits`,
   `mark`, `components`; dead worklists deleted (05 T5.2, T5.12).
4. **`ProgramGraph` and preservation**, cutting over every `CallCycles`
   and `Recursion` reader and caller-only `SymbolUserMap` in one change
   (05 T5.1, T5.10).
5. **Summary schedule**; effects onto it (05 T5.3), or into
   defunctionalization (06 T3) per defunc-Q2. Needs cluster A's resources.
6. **The three markings ported together** (20 L4): stack (08 T9), Borrows
   (07 D3), exclusivity (07 D2), with lane 07 D1 and its test first.
   Needs cluster A's type interface (07 D6) and cluster C's commit pass.
7. **Label solve on ids** (06 T2), types-first conversion and one remap
   (06 T1, T5), dedup (06 T4, its upstream hook first).
8. **The optimizer on `ProgramGraph`** (09 T3, T1, T2, T4 in that order),
   with Identities, BindingTimes and inline facts (05 T5.4–T5.6).
9. **Per-function framework solves**: Ranges per B1 (05 T5.7, 11 C8);
   Returned deleted by B4 or made per function (05 T5.5, 10 D3).
10. **Carried facts** (tail kind, `gives_back`) with clusters A and C
    (05 T5.8; 10 D1).

*Cluster A (dialect):* the effects resource tree (06 T3, 05 EF8); the
match's interface overrides, `isRepetitiveRegion` and
`RecursiveMemoryEffects` (05 IQ1, §3.1); a type interface for "followed"
(07 D6); the static lifetime in the grade (07 D6, 08 T1); one forwarding
declaration read by Borrows and exclusivity (07 B-06); `Idr_Decides` or
the interface (21 P-5); properties for B4; key attributes or none
(09 T3); typed data-body views (06 D-24, 09 OPT-65).
*Cluster C (counting, tail, lowering, arrays):* readers of the markings;
placement's form (B9); reuse order (own-Q1); the in-place promise (B7);
Returned and tail position (lane 10); narrowing (lane 11).
*Cluster D (Idris side):* the growth check's semi-naive flow and one
Tarjan (16 G7, G8); polyvariance in the frontend (ft-Q3); the lazy
constant as its own definition (09 OPT-82); `total` as the one
divergence fact (05 R14).
*Cluster E (pipeline, tests, history, the parallel agent):* decide /
apply / restructure (13 T1); per-function verification and
`effectsCovered` (13 T3); the stage-1 record; determinism tests; the
fence around the agent (perf-Q1); hist-Q1, Q2, Q5.

## 7. Risks, and the measurements that must exist

**Risks.**
- *Acceptance moves* with exclusivity's precision (07 §8). Needs a corpus
  comparison of old and new answers before the old goes, as the label
  solve's 314-solve differential did (20 §5.3 lane 06).
- *A maintained `ProgramGraph` is a new invariant*; a pass that forgets it
  gives a silent wrong answer. Rebuild-and-compare in test builds
  (05 §8).
- *The optimizer's inlining* changed with every recent rule, each answered
  by a compile-time blow-up (09 §8 risk 1); node names must stay stable
  across machines and thread counts (09 §8 risk 3).
- *The wave barrier may be MLIR's to keep* (09 §8 risk 2).
- *Types-first conversion* must never read a retyped value through an
  accessor that casts the old type (06 §8 risk 4); T3's effects must equal
  today's bits on the 16 `effects-*` fixtures (06 §8 risk 5).
- *BindingTimes' merge* may lose polyvariant precision (05 §8).
- *Lowering changes function identity*, so the lowered module needs its
  own graph, and carried facts must survive the conversion (05 §8).
- *Upstream reception*: no LLVM patch of about 25 has been filed (20 H4);
  each new one (U1, SCCP rewrite export, dataflow listener, poison as
  bottom, overridable `isRepetitiveRegion`, the dedup hook) needs a
  report, reproducer, test and plan (05 §8).
- *Collisions with the parallel agent's pushes* (21 §8).

**Measurements needed** (release build, one recorded commit, stage 1):
- V, B, P, F at each solve point; SCC size distribution; widest matches
  and their crash cases (§5.1 W1; 05 §8; 21 §8 item 3).
- Peak footprint of Ranges and of Returned run alone (05 §8; 21 §8
  item 5), and both after U1 per function (B1).
- idr-rc-exclusive on the module, with item, edge and followed counts
  (07 §8); Borrows' states and time (07 §8).
- The pre-ffa91113 exclusivity and a per-function `remove-dead-values` on
  the U1-patched framework (21 §8 item 6; 20 H1): the measurement the drops
  skipped.
- Label solve P, E, D, F, W, distinct sets (06 §8); registered ops and
  `convert` time per function (06 §8 risk 1); dedup's per-height idle time.
- Optimizer: waves, idle time, node-table lock hold time, keys and
  attributes created, made-node inlining growth (09 §8).
- The verifier's share per pass (13 §8 M1, M2).
- One thread against many, byte for byte (09 §8 item 4).
- The followed fraction of values with state (07 §8).
- §5.1 A4 on glibc (wave 1 measured libmalloc only, §5.1 A4).

## 8. What is stale, and what wave 2 left unverified

**Stale since the audited tree (e96bb991).**
- 101edbc5 moved counting's vocabulary into `Positions` and added
  `Idr_Decides`. Stale in lane 07: §2's `Uses.cpp` and vocabulary rows,
  §2.3's per-query costs, §3 rows 6 and 7 (both reverse), O-04..O-07,
  O-10, U-01..U-09, R-03, R-10, W3, W-E6; D5 is half built, differently
  (21 §3.5). Lane 08's C-06, C-22, C-27, C-29, C-37, C-79 and its T3
  target (21 §3.5).
- 51a4771b: `make test` at 403/480, not lane 20's 470/480; a new open
  counting bug; the first written measurement record (suites only:
  defunctionalization's pattern set the largest named cost, context-lock
  contention about a fifth, the verifier 1.6–1.7 % self; rankings "known to
  invert at scale") (21 §2.3, §3.4).
- Lanes 05, 06 and 09 are not contradicted by either commit (21 §3.5).
- Proposal §2's recalled trait report described 101edbc5's work before it
  landed (21 §1); §2's list of patches carried at the RDV drop is wrong
  (20 §3.1).

**Unverified.** Nothing in wave 2 was built or run (05 §3.2 W1; 06 §8;
07 §8; 09 §1). Every cost in lanes 05–10 is *read* or *conjecture*. In
particular: W1's counts; whether G-09 changes any expectation; whether
7987388b raised D-3's cost; whether any `scf.if` reaches counting (P-3);
OPT-14's and OPT-48's effects; how much of the 627 GB was A4's container
cost, and whether the 52 GB run would have finished (21 §8); U2's race
(§5.1 U2, until a TSan run); the precision of BindingTimes' merge and of
Ranges per function; whether carried `gives_back` survives lowering's
splitting of results.
