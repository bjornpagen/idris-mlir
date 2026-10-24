<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Rederivation audit: control and calls

Family: tail position and tail kinds, the context of a call modulo cells,
which call runs on a frame, join points and loops, contification, the
call graph and its components (ours and Idris's), a callee's facts (gives
back, returns constants), copies and their keys; from the checker and Emit
through defunctionalization, contification, the specializer, frames,
lifetimes and the lowering's calls.

- HEAD at start: `eedaf5d40a36a5423c2516364871ea901c2aaec7`.
- HEAD at finish: `d73863f5e4377ce21574b94896868b12f9403fe9`. It moved
  twice during the audit (`b2aab6e9`, L18aa, then `d73863f5`). Another lane was editing `Transforms/EGraph/*`,
  `Optimize/Settle.cpp` and `Optimize.cpp`, and deleting
  `Analysis/Constants.*`, while this was read; line numbers in those files
  are from the live tree.
- Ground: every claim is *read* unless it says otherwise. Nothing was
  built or timed: no `idris-mlir-opt` is built on this machine and LLVM is
  not built here, so no count below is measured.
- "M" means the file was modified in the checkout when it was read, so a
  fix waits on the lane holding it.

Ranked by how much re-derivation the fix deletes.

---

## R1. The tail fact is decided once, then decided again in full by every pass that edits a body

**Fact.** Where an `idr.call` stands (`TailKind`: `tail`, `nontail`,
`modulo_context`), and whether an op that holds no fact (a region op, a
dispatch, a join point) stands at a tail.

**First known.**
- Decided at defunctionalization, from structure:
  `Defunctionalize/Pass.cpp:77-78` (decideTails over every function),
  reading `IR/Tail.cpp:212-250` (tailsOf, sourcesOf).
- Then known by each pass at the moment it places a call:
  - the inliner interface composes the two facts exactly
    (`IR/Func/Inliner.cpp:66-84`);
  - contify writes the fact (`Optimize/Contify.cpp:238-249`);
  - Redirect's first form writes it (`Specialize/Redirect.cpp:143-154`);
  - trmc states which of its calls are tails (`Tail/Trmc.cpp:156-162`);
  - frames builds each rest as a tail call (`Framed{call, rest}`,
    `Transforms/Tail/Frames.h:122-126`).

**Dropped.** After each pass that rewrites a body, every fact in the
function is treated as unknown:
- the e-graph's extraction: "the function was written back whole"
  (`EGraph/Elaborate.cpp:458-469`, M);
- Narrow, after erasing conversions (`Narrow/Narrow.cpp:188-192`);
- CaptureDrops (`Optimize/CaptureDrops.cpp:113-117`);
- Raise (`Specialize/Raise.cpp:158-161`);
- Frames (`Tail/Frames.cpp:185-189`);
- Trmc (`Tail/Trmc.cpp:156-165`);
- leaf inlining (`Inline/Inline.cpp:160`);
- the upstream inliner run, which throws away what the interface just
  composed: `Inline/InlinePass.cpp:46-51` decides again before the
  function's simplify, Elaborate decides again at the simplify's end, and
  `:58-62` decides a third time after the loop.

Region ops hold no fact at all. Redirect: "it holds no fact of its own"
(`Redirect.cpp:192-195`). Continuations: "A join point holds no fact of
where it stands" (`Tail/Continuations.cpp:224-226`).

**Re-derived.**
- **The whole function, 12 calls at 11 sites.** `optimize::decideTails`
  (`Transforms/Optimize/Tails.h:34-48`) resets every call's fact with
  `withContext`, which runs `contextOf` on every call
  (`IR/Tail/Context.cpp:169-327`). For a self call that is a use-chain
  walk, a `FlowEdges` built per op on the path, and `movableBefore`
  (`:149-160`), which asks `effects::mayMoveAcross` of each op after each
  anchor. It then reads tailsOf down the body. This runs per function, per
  run of each pass: the e-graph's run happens in every optimize round, in
  the inliner's pipeline and in two pipeline nests.
- **Per query, inside loops.** Each reads the tails of the whole function:
  - Redirect, per raise (`Redirect.cpp:194-195`);
  - Continuations, per held join per round (`:226`) and per framed site
    per lift (`:261`);
  - Open, per holder per converted callee (`Specialize/Open.cpp:1051`, M);
  - AccumulatorPlan, per function (`Tail/AccumulatorPlan.cpp:281`).
- **After every pass that does not keep all analyses**, the verifier runs
  again:
  - `verify(FuncOp)` (`IR/Tail.cpp:329-376`) walks tailsOf and walks every
    call twice;
  - `verify(CallOp)` (`:298-327`) runs `contextOf` on every `nontail` call
    once facts are decided, and `passageOf` with an operand-lifetime walk
    on every `tail` call.

**Carrier.** AGENTS.md: "an operand, attribute or enum that changes what
an op means or may do is a flag, and the op is two". `TailKind` changes
what `idr.call` may do: nothing may follow a `tail` call, and a
`modulo_context` call's one result may only fill a hole (`IR/Tail.h:9-21`).

The dialect already keeps this promise by structure for local
continuations. `idr.jump` is a terminator, and "Tail position is a
precondition of a jump, never a fact the jump holds"
(`Transforms/Joins.h:17-21`). It reaches its join token across matches by
upstream's early exit (`IR/Control/Joins.cpp:31-35`;
`upstream/65-early-exits`).

The carrier: a tail call is a jump to another function's entry. It is its
own op, a terminator that leaves through every `PropagateControlFlowBreak`
op to the function's exit, by the same `RegionExitTerminatorOpInterface`
mechanism `idr.jump` uses. Then:
- "nothing follows a tail call" is `IsTerminator`, checked by MLIR's core
  verifier with no walk of ours;
- no pass can put an op after one;
- `tailCallOf` and `lastActOf` become `isa`;
- the lowering emits the op as `musttail` followed by `llvm.return`.

This needs the owner's ruling: it decides which op holds the fact, and it
touches the region rule, as `idr.jump` already does.

Interim, with no ruling needed: each pass writes the fact where it places
a call, as the inliner interface and contify already do, and decideTails
goes. Whether a region op stands at a tail is read once per function per
pass, never per query.

**What the fix deletes.**
- `Transforms/Optimize/Tails.h`, all 52 lines (decideTails).
- Its 12 calls: `Defunctionalize/Pass.cpp:77-78` (see R4),
  `CaptureDrops.cpp:116`, `Narrow.cpp:192`, `Elaborate.cpp:468-469`,
  `Raise.cpp:161`, `Frames.cpp:189`, `Trmc.cpp:164-165`, `Inline.cpp:160`,
  `InlinePass.cpp:50` and `:62`.
- `Redirect.cpp:192-195` and `:213-216`.
- `Continuations.cpp:224-226`, and the per-lift re-read at `:261`.
- Under the structural carrier, also:
  - `IR/Tail.cpp:308-318` (the `tail` case of `verify(CallOp)`);
  - `IR/Tail.cpp:348-376` (the tail-call census of `verify(FuncOp)`);
  - `Conversion/TailCalls.cpp:68-84` (`endAtTailCalls`, the block split
    that puts the return after each `musttail` call).

**Owner and wait.**
- L10: `IR/Tail*`, `Transforms/Tail/*`, `TailCalls.cpp`.
- L18: `Optimize/Tails.h`, Redirect, Raise, Open (M), Inline, InlinePass,
  CaptureDrops.
- L14: Elaborate (being edited now).
- L12: Narrow.
- L02: `IR/Func/Inliner.cpp`.
- Waits on the owner's ruling for the structural form.
  `Spec/Tail/Declarations.idr` is M (L10).

**Confidence.** Read; the costs are not measured.

---

## R2. The call graph is built about eight times per compile, and the spec's `GraphEffect` is read by nothing

**Fact.** The program's calls, indexed: each function's row of (callee,
tail kind, sites), its callers, the components bottom-up, and which
components run calls on frames (`Analysis/Solver/ProgramGraph.h:1-31`).

**First known.** Defunctionalization builds it (`Defunctionalize/Pass.cpp:54`).
A restructuring pass that changes calls edits it through its `Editor`
(`ProgramGraph.h:217-260`), as `Trmc.cpp:173-185`,
`Ownership/Exclusive.cpp:190-198` and `Defunctionalize/Pass.cpp:84-96` do.

**Dropped.**
- **The spec states the fact and nothing reads it.** The specification
  says per pass whether it keeps, edits or invalidates the graph:
  `Spec/Pipeline/Pass.idr:51` (`data GraphEffect = Keeps | Edits |
  Invalidates`), with `:207` (`graph : GraphEffect`) on every pass record.
  Those two lines are the field's only occurrences in the tree: no
  generator and no C++ reads it.
- **Passes recorded `Keeps` do not mark the graph preserved:**
  - rcBorrows (`Counting/Borrows.cpp:379-389`, M) uses the graph, then
    drops it;
  - rcCells (`Counting/Cells.cpp:82`);
  - rcPlace (`Counting/Placement.cpp:339`);
  - rcReuse (`Reuse.cpp:145`);
  - rcExpand (`Expand.cpp:211`);
  - structureLoops (`StructureLoops.cpp:99`, `:124`);
  - orderedLoops;
  - lowerRuntime and lowerStatics keep `Layouts` only
    (`Lower/Declarations.cpp:42`, `Statics.cpp:117`).
- **Passes recorded `Edits` invalidate the graph instead of editing it:**
  - deduplicate (`Deduplicate.cpp:371-408`);
  - contify (`Contify.cpp:353-358`);
  - columns (`Columns.cpp:55`);
  - bufferize (`Bufferize.cpp:289`);
  - accumulate, which makes `.acc` clones (`Accumulate.cpp:348-349`);
  - inline, which invalidates every analysis and rebuilds on purpose
    (`InlinePass.cpp:64-68`).
- **tailLoops' record is wrong.** It is recorded `Keeps` but deletes self
  tail calls (`TailLoops.cpp:128-151`).
- **Two droppers are by design.** Upstream SymbolDCE (steps 8 and 29)
  drops every analysis. The nested function groups drop the graph through
  patch 74's intersection (`upstream/74-pass-adaptor-preserved-analyses`),
  because no member marks it kept.

**Re-derived.** `ProgramGraph::ProgramGraph`
(`Analysis/Solver/ProgramGraph.cpp:60-104`) does all of this each time:
- builds upstream's `CallGraph`: a walk of every op of the program,
  resolving each callee through a symbol table;
- walks each function's calls a second time (`rowFrom`);
- hashes every callee into a name table;
- computes upstream's SCCs and the framed bits.

By the generated step list (`IR/Generated/Pipeline.h.inc`), it is built
at:
- defunctionalize (step 0);
- contify after a merge (4);
- optimize after a placement (5);
- inline's explicit rebuild (6);
- uniqueResults (12);
- writeRows (18, 23 and 28);
- trmc (30);
- lower (37).

That is 8 builds when nothing merges and nothing is contified, and 10
when every pass changes something. AGENTS.md lists this as a never: "the
call graph built up to seven times per compile (05 §2.2)".

**Carrier.** The spec's own field, generated into the pass base:
- `StagedPass` (`IR/IdrDialect.h:157-223`) is already instantiated per
  record with `Requires` and `Sets`; it also takes the record's
  `GraphEffect`.
- `Keeps`: the base marks `ProgramGraph`, and the `CallGraph` it wraps,
  preserved after any run that did not fail.
- `Edits`: the generator places a thaw before the pass and a freeze after
  it, as it already places widenRows and writeRows around nests from
  `adds` (`Generator/Cpp.idr:1460-1463`). The pass writes its rows through
  the Editor, and "a row is replaced whole by the turn that owns its
  function" (`ProgramGraph.h:217-218`), so nested function passes
  (simplify, tailLoops) edit in parallel.
- tailLoops' record becomes `Edits`.
- SymbolDCE is kept (upstream first). The build after step 29 stays unless
  the dead-function sweep reads the graph's `callSites` and root. That is
  L03's call.

**What the fix deletes.**
- Honouring `Keeps` alone deletes the builds at steps 23 and 28: rcBorrows
  and rcPlace keep the graph, rcExclusive already keeps it, and rcReuse
  and rcExpand keep it.
- Honouring `Edits` through the editor deletes the builds at steps 4, 5,
  6, 12, 18 and 37, and `InlinePass.cpp:64-68`.
- That leaves defunctionalize's build and the one after SymbolDCE.

**Owner and wait.**
- L03: `Pass.idr`, `Pipeline.idr` (M), the `StagedPass` base,
  `Generator/Cpp.idr`.
- L14: ProgramGraph.
- Each pass's lane:
  - L07: counting, with `Counting/Borrows.cpp` M;
  - L12: columns, bufferize, structureLoops, narrow;
  - L10: accumulate, tailLoops;
  - L18: dedup, contify, inline;
  - L21: lower.

**Confidence.** Read. The counts come from the generated step list and
each pass's preservation; nothing was timed.

---

## R3. Termination components and their loop verdicts: the checker computes them, drops them, and the frontend computes them again

**Fact.** Which definitions form a component of Idris's call graph, and
whether the loops through each end (size-change). This is the fact
`#idr.terminates<component n>` holds (`Spec/Functions/Termination.idr`).
Its readers: `provedTogether` for rows, joins (`Transforms/Joins.h:73-78`)
and the fold (`IR/Func/Fold.cpp:39`).

**First known.** The checker's `calcTerminating`
(`compiler/checker/src/Core/Termination/SizeChange.idr:580-601`) computes:
- the components, by Tarjan (`components work`, `:170-233`);
- per component, `componentLoops`, which is `loopsTerminate`
  (`:444-464`).

It runs:
- for library definitions, when the library was built;
- for the program's definitions, when they are checked;
- at the boundary, for every definition left unchecked
  (`Frontend/Translate/Boundary.idr:279-290`, `host.checkTerminating`, M).

**Dropped.**
- `calcTerminating` keeps only the transitive verdict, `IsTerminating` or
  `NotTerminating` (setTerminating, `Core/Termination.idr:70-80`). The
  components and each member's `Loops` are thrown away.
- It returns before computing them at all when a callee is not
  terminating (`SizeChange.idr:587`, `totRefs`).
- The TTC keeps the raw size-change graphs (`Core/TTC.idr:1457`,
  `toBuf (sizeChange gdef)`, M) and the verdict.

**Re-derived.** `Frontend/Translate/Recursion.idr` (162 lines):
- re-runs Tarjan over the TTC's size-change graphs from every definition
  `main` reaches (`:49-131`, visit and successors over a `SortedMap` and
  `SortedSet` by address);
- re-runs the checker's own `loopsTerminate` on each component
  (checkComponent, `:133-149`). That is the size-change closure, whose
  search keeps every graph over n arguments it meets
  (`SizeChange.idr:255-265`): finitely many, but more than linear in the
  arguments.

This happens once per compile over the whole reachable program
(`Boundary.idr:1190`). The boundary then holds two readings of
termination: `verdictOf` gives `Ends`, `loopsOf` gives `ComponentId`.

**Carrier.** The checker's totality record holds what it proved. Per
definition it keeps:
- its component, identified by content (its least member by name), never
  by a discovery number;
- its own `Loops` verdict, computed before the `totRefs` early exit.

Both go into the TTC beside the verdict, and the frontend reads them once,
in `verdictOf`, next to `Ends`. This fits: the checker is ours
(`compiler/checker`, D118), and AGENTS.md says the TTC keeps every fact a
reader would otherwise rebuild.

**What the fix deletes.**
- `compiler/src/IdrisMLIR/Frontend/Translate/Recursion.idr`, all 162
  lines.
- `Boundary.idr:1190`, and the `proved` map threaded through
  `State.idr:1203-1205` and `:1405` (M).
- One whole-program Tarjan and size-change closure per compile.

**Owner and wait.**
- L17: the checker (`SizeChange.idr`, `Termination.idr`, `TTC.idr` M,
  `Context.idr` M; `Termination/CallGraph.idr` M).
- L16: `Recursion.idr`, `Boundary.idr` (M), `State.idr` (M).
- Both hosts build the checker's change.

**Confidence.** Read.

---

## R4. Emit knows every tail and writes `nontail`; defunctionalization reads tails three ways; a direct tail call's label unification is dead

**Fact.** Whether a call, apply or force that Emit writes stands at a tail
of its function or join region.

**First known.** Emit, by construction. The fold carries a `Scope` whose
join targets exist only at a tail (`Emit/Bodies.idr:61-70`, M). Every
operand position is written under `offTail` (`:86-90`; for example
`:576`, `:582`, `:602`, `:781-783`). So a call, apply or force written
under a scope that has not been through `offTail` stands at a tail. A call
at a tail is written at its caller's return type and never cast
(`:591-596`).

**Dropped.**
- Emit writes `NonTail` on every call (`Bodies.idr:612`, `:614`). The
  spec states this as policy (`Spec/Functions/Tail.idr:6-8`): "The
  frontend writes every call `nontail`, which promises nothing".
- `fn.apply` (`:791`, `:793`) and `lazy.force` (`:809`) carry no fact.
- The stage table makes it a stage: `Spec/Pipeline/Stage.idr:95`
  (`StageTails`), `:206-208` (`tailsAt Higher = TailsPromised`).

**Re-derived**, all inside idr-defunctionalize, on the program as written:
1. The Labels analysis reads the tails of every function
   (`Analysis/LabelSites.cpp:328-330`) and looks each dispatch up in them
   (`:222-223`, a `Standing` per dispatch).
2. The plan reads the tails of every function again
   (`Defunctionalize/Edits.cpp:91`) and looks each apply up (`:99-101`),
   though the analysis already holds each dispatch's `Standing`
   (`Analysis/Labels.h:122`, `:158`).
3. decideTails runs over every function after the rewrite
   (`Defunctionalize/Pass.cpp:77-78`), with `contextOf` on every call.

The stage itself costs branches: `IR/Tail.cpp:258` (`decided()`), `:305`,
`:336`, and `EGraph/Elaborate.cpp:468`.

**The bug.** The dead branch is read; its effect is a conjecture, because
no test reaches it.
- `LabelSites.cpp:338-339` makes a direct tail call's result points one
  set with its caller's (tailResults, `:175-183`). It does so only where
  the call's fact is `tail`. That never happens on a program Emit wrote,
  because the analysis runs at Higher, before step 3 above.
- Applies do get the unification (readFiring, `:359-362`), from the
  structural `Standing`.
- Take a direct tail call whose callee's result labels are a strict subset
  of its caller's. The plan's move loop places a coercion at the return's
  use (`Edits.cpp:52-57`; the sink of a return is the caller's result
  slot, `Decide.cpp:67-79`).
- decideTails then sees the coercion after the call and writes `nontail`.
  `verify(FuncOp)` never finds a call at that tail, so nothing reports it.
- The result is a tail call lost silently. AGENTS.md: "a tail call the
  compiler fails to make is an internal error, never a silent call", and
  "on a cycle or not".
- On a cycle the label sets are equal (inclusion runs both ways), so the
  cost is one native frame per acyclic chain.
- The only test that starts at Higher with tail calls,
  `tests/expect-call-results`, writes them by hand.

**Carrier.** Emit's `Scope` indexed by where it stands:
- `Scope (p : Position) js nv`, with
  `offTail : Scope p js nv -> Scope Within [] nv`. A join target off a
  tail becomes unrepresentable by the index rather than by resetting a
  list.
- The call's `TailKind` is the index: `Tail` at `Tail`, `NonTail` at
  `Within`.
- Apply and force carry the same property (or, under R1's carrier, are
  the tail form at a tail), so defunctionalization gives each dispatch
  call its apply's kind.
- Every stage is then `Decided`.

**What the fix deletes.**
- `StageTails` and `tailsAt` (`Stage.idr:95`, `:154-160`, `:206-208`,
  `:230`), and its generated `StageFacts` column.
- `IR/Tail.cpp:258`, and the `decided` and `exact` branches (`:305`,
  `:336-347`).
- The guard at `Elaborate.cpp:468`.
- The tails table in `LabelSites.cpp` (`:109`, `:115`, `:140`, `:222-223`,
  `:328-330`); the `Standing` is read off the apply instead.
- `Edits.cpp:37` and `:89-101` (`TailPosition` and the second reading).
- `Defunctionalize/Pass.cpp:66-79`, decideTails over every function; the
  rows are re-read only for runners.
- The comments at `Spec/Functions/Tail.idr:6-11` and
  `Emit/Bodies.idr:595-599`.
- It also makes the dead branch live, which fixes the lost tail call.

**Owner and wait.**
- L16: Emit (M; C286 just landed there).
- L14: LabelSites, `Labels.h`.
- L18: defunctionalization.
- L03: `Stage.idr`.
- L10: `IR/Tail.cpp`; `Spec/Tail/Declarations.idr` is M.
- L02: `Functions/Tail.idr`.

**Confidence.** Read. The lost tail call stays a conjecture until a
program test runs on both hosts: a direct tail call to a closure-returning
function with fewer labels than its caller.

---

## R5. A call's context modulo cells: computed, dropped to an enum, computed again after counting and on every verification

**Fact.** For a self call modulo a context, its `Context`
(`IR/Tail.h:148-170`): the approach, the hole (cell op, operand, field),
the rest of the path to the return, and that every op before the anchors
may move there.

**First known.** `contextOf` (`IR/Tail/Context.cpp:169-327`), at the
decision: decideTails at defunctionalization calls `withContext`
(`IR/Tail.cpp:254-256`).

**Dropped.** Into `TailKind::modulo_context`. The enum keeps the verdict
and loses the path.

**Re-derived.**
- By idr-trmc, after counting (`Tail/Trmc.cpp:107-118`). Its guard, "a
  call modulo a context whose context no longer holds" (`:113-116`), can
  never fire: the verifier has already rejected that state after every
  pass.
- By the verifier, on every verification: for every `modulo_context` call
  (`IR/Tail.cpp:319-323`), and for every `nontail` self call once facts
  are decided (`:302-307`).
- By `withContext`, inside every decideTails (R1), and at
  `Redirect.cpp:153` and `:216`, `Open.cpp:1055`, `Contify.cpp:246`,
  `Deduplicate.cpp:399` and `Accumulate.cpp:307`.

Each is a use-chain walk that builds `FlowEdges` per op on the path, plus
`movableBefore` (`Context.cpp:149-160`), which makes an effects query per
op after each anchor.

**Carrier.** The destination form, written where the context is decided.
The cells are built before the call with the field a hole, and the self
call takes the hole's `!idr.dest`; this is what trmc builds today
(`Trmc.cpp:9-26`). The context is then in the program as operands, and no
later pass recovers it. Counting would then have to count a destination,
a linear, uncounted handle to a field. That is a design for L10, L07 and
the owner, because trmc today relies on counting having run first
(`Trmc.cpp:28-31`).

Interim, with no ruling: delete trmc's guard, and run the missed-context
check at the sites where a pass makes a self call (the `withContext`
sites), not on every verification of every self call.

**What the fix deletes.**
- Under the destination form: the `modulo_context` case (`ModuloContext`
  in `Functions/Tail.idr`, `contextCallOf`, its verifier case) and trmc's
  second `contextOf`. `Context.cpp` then runs once per self call.
- Interim: `Trmc.cpp:111-118` and `IR/Tail.cpp:302-307`.

**Owner and wait.** L10. Waits on the owner's ruling on the destination
form, and on L07 for counting destinations.

**Confidence.** Read. The interaction with counting is a conjecture.

---

## R6. What a function gives back: one solve, two copies, a name lookup, and a reader that cannot see it

**Fact.** Per function, which result components are which argument
components on every return (`identities::GivesBack`), and what may reach
each result (`mayReach`).

**First known.** `identities::givesBackOf`, when a component is finalized
(`Optimize/Settle.cpp:160-179`, being edited now).

**Held twice, dropped once.**
- **Two copies.** Settle writes it as `#idr.given_back` on `idr.func`
  (`Settle.cpp:44-52`, `:178`) and also publishes it in
  `egraph::CalleeFacts` (`:179`; `Transforms/EGraph.h:381-413`), an
  in-memory table that dies with idr-optimize.
- **Read by name.** Readers resolve a `FlatSymbolRefAttr` through the
  editor's name table on every query (`EGraph/Simplify.cpp:63-75`):
  per call node in the e-graph (`Nodes.cpp:559-566`), and per call in the
  specializer (`Open.cpp:969`, `:991`; `Requests.cpp:244`).
- **The attribute has no transforming reader.** Only its own verifiers
  read it (`IR/Func/Verifier.cpp:108-113`, `:198`;
  `IR/Func/Call.cpp:159-163`, `:284-286`). `Edits.cpp:169-179` renumbers
  it, and `Tail/Jumps.cpp:291` and `Outline.cpp:254` clear it. Its spec
  claims a lowering use ("The lowering gives back the register it was
  passed", `Spec/Functions/GivenBack.idr:6`), but no code in `Conversion/`
  reads it.
- **A reader that cannot see it.** The e-graph runs in the pipeline's
  nests and in idr-inline's pipeline are built with no table
  (`createIdrSimplify()`, `EGraph.h:418`). They cannot read what the
  callee's attribute still states.

**Re-derived.** Nothing solves it a second time any more (05 R5's second
solve is gone). The cost is the second copy, kept in step by verifiers,
and a name lookup on every query.

**Carrier.** Keep exactly one of the two copies:
- Either the attribute is the carrier, and both readers read it off the
  callee (`graph.op(id).getGivenBackAttr()`; the `FunctionId` is already
  in hand). `CalleeFacts` then keeps only `mayReach` and returned
  constants, until those move too.
- Or, if no reader is planned after idr-optimize (the spec's register
  claim has no code), the attribute and its verifiers go, under "delete
  before you optimize".

The owner or L02 decides which.

**What the fix deletes.** One of:
- `CalleeFacts`' givesBack half, and its per-query name lookup; or
- `GivenBack.idr` (119 lines), `GivenBack.cpp` (176), `Func.h`'s
  `GivenBack` structs, `Verifier.cpp:108-113` and `:198`,
  `Call.cpp:159-163` and `:284-286`, `Edits.cpp:148-179`,
  `Settle.cpp:44-52`, `Jumps.cpp:291`, `Outline.cpp:254`, and the
  frontend's generated encoding and dialect entries for it.

**Owner and wait.**
- L02: `Spec/Functions`, `IR/Func`.
- L18: Settle, Open (M), Requests.
- L14: EGraph.
- Settle, `EGraph.h`, `Simplify.cpp` and `Nodes.cpp` are being edited now
  (the move of returned constants).

**Confidence.** Read.

---

## Examined, and nothing dropped

- **The termination attribute.** `#idr.terminates` is carried from the
  frontend to `provedTogether` once it is computed (its origin is R3).
- **Join point or loop.** Decided by where the tokens are
  (`IR/Control/Joins.cpp:22-28`). Whether a loop ends comes from Idris's
  proof (`Joins.h:73-78`).
- **Which call runs on a frame.** `ProgramGraph::runsOnFrame`
  (`ProgramGraph.h:142-160`) computes it from the components and the
  call's kind. It is the one query that lifetimes, borrows, placement and
  frames ask.
- **Copy kind.** Written on the copy when its key is granted
  (`Specialize.cpp:486`), and read by the inliner off the function
  (`Inline.cpp:65-95`).
- **Copy names.** A copy's name is a digest of its key's canonical bytes
  (`Specialize.h:444-460`): a symbol MLIR needs, never looked up to
  recover a key. Grade copies refuse a name clash
  (`GradeCopies.h:66-80`).
- **A call's copies of its callee's facts.** The call holds the callee's
  row, `untouched` and `lives_in` (`IR/Func/Call.cpp:70-77`, verified at
  `:265-272`). The row's copy is the owner's ruling ("a call carries its
  callee's"). The other two let upstream's interfaces read a call alone,
  which MLIR's open op set forces.
- **The lowering's tail calls.** They read the fact
  (`Lower/Functions.cpp:227`), and `TailCalls.cpp` reads `musttail`.
- **StackBound.** It reads LLVM's final graph, and code generation's
  frame sizes by name (`Driver/StackBound.h:1-12`, `:38-58`). Both are
  facts known only after code generation. Its refusal of a cycle that is
  not a tail call re-checks idr-frames on the module LLVM inlined: a check
  of the artifact.
- **Returned constants.** Read off the final body, which is the carrier.
  Another lane was moving them into `CalleeFacts` during this audit.

---

## Table

| # | Fact | Dropped at | Re-derived at | Carrier | Deleted | Owner | Waits on |
|---|------|-----------|---------------|---------|---------|-------|----------|
| R1 | tail kind of a call; tail standing of region ops | every body edit: `Elaborate.cpp:458-469`, `Narrow.cpp:188-192`, `CaptureDrops.cpp:113-117`, `Raise.cpp:158-161`, `Frames.cpp:185-189`, `Trmc.cpp:156-165`, `Inline.cpp:160`, `InlinePass.cpp:46-62`; region ops hold none (`Redirect.cpp:192`, `Continuations.cpp:224`) | `Optimize/Tails.h:34-48` at 11 sites (12 calls); per-query tails reads at `Redirect.cpp:195`, `Continuations.cpp:226`, `:261`, `Open.cpp:1051`; verifier after every pass `IR/Tail.cpp:298-376` | a tail call is its own terminator op, leaving to the function's exit as `idr.jump` leaves to its join (early exit); interim: each pass writes the fact where it places a call | `Tails.h` (52), 12 calls, 2 per-query readers, the tail halves of both verifiers, `TailCalls.cpp:68-84` | L10, L18, L14, L12, L02 | owner's ruling; Open.cpp M; Elaborate being edited |
| R2 | the program's call graph and its components | `Pass.idr:51`, `:207` read by nothing; `Keeps` passes don't preserve (`Borrows.cpp:379-389` and others); `Edits` passes invalidate | `ProgramGraph.cpp:60-104` at steps 0, 4, 5, 6, 12, 18, 23, 28, 30, 37 | `GraphEffect` generated into `StagedPass` (`IdrDialect.h:157-223`); generated thaw and freeze around `Edits` nests | 6 to 8 whole-program builds per compile; `InlinePass.cpp:64-68` | L03, L14, L07, L12, L10, L18, L21 | `Pipeline.idr` M; `Counting/Borrows.cpp` M |
| R3 | Idris's components and their loop verdicts | `SizeChange.idr:580-601` keeps only the transitive verdict, and stops at `:587` | `Frontend/Translate/Recursion.idr:49-162` (Tarjan plus `loopsTerminate` again), per compile | the checker's totality record holds the component (content identity) and `Loops`, in the TTC | `Recursion.idr` (162), `Boundary.idr:1190`, the `proved` plumbing | L17, L16 | `TTC.idr`, `Context.idr` M (L17); `Boundary.idr`, `State.idr` M (L16) |
| R4 | tail standing at Emit | `Bodies.idr:612`, `:614` write `NonTail`; apply and force none; `Stage.idr:95`, `:206` | `LabelSites.cpp:328-330`, `:222`; `Edits.cpp:91`, `:99`; `Defunctionalize/Pass.cpp:77-78`; dead tailResults `LabelSites.cpp:338-339` loses a direct tail call to a coercion | Emit's `Scope` indexed by position; `TailKind` from the index; apply and force carry it | `StageTails`, `decided()` and its branches, the LabelSites tails table, `Edits.cpp` second reading, defunctionalization's decideTails; a bug fixed | L16, L14, L18, L03, L10, L02 | `Bodies.idr` M (L16) |
| R5 | context of a self call modulo cells | `TailKind::modulo_context` (path dropped) | `Trmc.cpp:107-118` (with a dead guard); `IR/Tail.cpp:302-307`, `:319-323` every verification; `withContext` at 6 sites plus every decideTails | destination form written at the decision (`!idr.dest` operand) | trmc's second `contextOf` and guard, the verifier's per-pass re-decision; interim: `Trmc.cpp:111-118`, `IR/Tail.cpp:302-307` | L10 (L07) | owner's ruling; counting of destinations |
| R6 | gives back (and `mayReach`) | held twice: `#idr.given_back` (`Settle.cpp:44-52`) and `CalleeFacts` (`EGraph.h:381-413`); invisible to post-optimize e-graph runs | name lookup per query, `Simplify.cpp:63-75`, `Nodes.cpp:566`, `Open.cpp:969`, `:991`, `Requests.cpp:244`; the attribute only verified | one copy: the attribute read off the callee, or the attribute deleted if no reader comes after optimize | the `CalleeFacts` half or about 350 lines of attribute, verifier and renumbering | L02, L18, L14 | Settle and EGraph being edited; Open.cpp M |
