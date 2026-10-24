<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Cull audit: the analyses and the solver layer

Area: `foreign/idr/lib/Analysis/`, `foreign/idr/include/idr/Analysis/`
(9,103 lines at start), and the analysis classes the analysis manager
serves elsewhere (`getAnalysis<…>` census: ProgramGraph, SymbolTable,
Layouts, Ranges, WalkNumbering, Labels, CallGraph, TypeGraph, Exclusivity,
DataLayoutAnalysis, Borrows).

- HEAD at start: `363dcc0d755505730d48412e73a5c64245e8421f`.
- HEAD at finish: `d378e120ee0813b9c170fa5b85c294bc49a45b6d`. Between the
  two, only `Analysis/Ownership/Local.h` and `Transforms/EGraph.h` changed
  among the files below; neither change touches a candidate (EGraph.h's
  `CalleeFacts` text, lines 355-390, is unchanged).
- Method: AGENTS.md's "Delete before you optimize" (the owner,
  2026-10-23), then representation-first and testing-by-search. A part is
  kept only with its rule and the fact only it supplies.
- Grounds: "measured" here means a search of the tree, named with its
  count; no build was possible (no LLVM/MLIR install under `.toolchain/`,
  and LLVM is not built on this machine). "read" is a reading of the code.
- Nothing here touches `sources/`. Every verdict keeps its search.
- Owners are from `audits/p0/verify/ownership.json`; "modified" is
  `git status` at finish.

Line counts are counted from the line ranges given; a range that also
needs a few lines added (a replacement) is given as a net figure.

---

## A. `#idr.given_back` on `idr.func`: written once, read by nothing that acts on it

**The part.** The attribute and everything that keeps it in step:
- `foreign/idr/lib/IR/Func/GivenBack.cpp:1-176`: parse, print, `get`,
  `renumber` and `verify` of `GivenBackAttr` and `GivenBackEntryAttr`.
- `foreign/idr/include/idr/IR/Func.h:181-210`: `GivenBackPath`, `GivenBackEntry`.
- `foreign/idr/lib/IR/Func/Verifier.cpp:107-120` (`givenBackFits`) and its call at `:198`.
- `foreign/idr/lib/IR/Func/Edits.cpp:148, 169-170, 179`: renumbering on a signature edit.
- `foreign/idr/lib/IR/Func/Call.cpp:158-163` (`givenBackResults`) and
  `:284-286`, the tail-call check "gives back other result components than its caller".
- `foreign/idr/lib/IR/Func/Func.cpp:70`: the attribute's name in the elided list.
- `foreign/idr/lib/Transforms/Optimize/Settle.cpp:42-52` (`writeGivenBack`) and its call at `:177`.
- `foreign/idr/lib/Transforms/Tail/Jumps.cpp:291` and `Tail/Outline.cpp:254` (`setGivenBackAttr(nullptr)`).
- The specification: `compiler/spec/IdrisMLIR/Spec/Functions/GivenBack.idr`
  (119 lines); its `positionDirective`/`positionKind` (lines 20-31, 52-58)
  move to `Functions/Extents.idr`, which reads them (`Extents.idr:84-85`).
  Also `Functions/Declarations.idr:24-25, 43, 216, 387`, `Spec.idr:40`,
  `spec.ipkg:57`, and `Generator/Package.idr:47` (one list entry).
- Generated from it: `Generated/IdrTypes.td:282-305`,
  `Generated/IdrBytecode.td:100-105` (and one entry of `:146`), the
  `$given_back` argument of `Generated/IdrOps.td:73`,
  `compiler/src/IdrisMLIR/Encoding/Idr.idr:91, 100-101`, and
  `compiler/src/IdrisMLIR/Dialect/Idr.idr:49-50` (one parameter).
- `foreign/idr/lib/IR/CMakeLists.txt:71`.

**The fact it supplies.** "On every path that returns, result component r
is argument component a." While the optimizer runs, the fact is held in
the optimizer's `egraph::CalleeFacts` table (`include/idr/Transforms/EGraph.h:357-385`),
published by `Settle.cpp:178`. The two readers that act on it read that
table:
- `Transforms/EGraph/Nodes.cpp:549` replaces a call by the argument part.
- `Transforms/Specialize/Open.cpp:431-475` (`keyGivenBack`) keys a copy's results.

`EGraph.h:365-366` says the rest outright: "The pipeline's own points run
after the optimizer has rewritten every such call, and read none." So the
attribute is a second copy of the fact, made at the optimizer's end for
no reader.

**The rule that once required it.** C18: "'Gives back argument i' is held
once, on `idr.func`, per result field path … a parallel reader reads it
from its decide step". `Analysis/Identities.h:7-11` names its reader: "the
lowering reads it to give back a register it was passed, and idr-simplify
replaces a call". That reader does not exist:
- `getGivenBack`, `GivenBack` and `given_back` give 0 hits in
  `foreign/idr/lib/Conversion/`, `include/idr/Conversion/` and
  `lib/Target/` (measured).
- idr-simplify reads `CalleeFacts`, never the attribute.

C18's own premise is "every fact a later pass reads is written into a type
or a verified property". No later pass reads this one, so the premise
holds with the attribute gone. The tail-call check (`Call.cpp:284`)
guards "a result one drops is dropped by both". Nothing drops a given-back
component: Results.cpp's dead results read no given-back fact
(`Optimize/Results.cpp:1-26, 195-215`). The check guards a lowering that
was never written.

Recheck 6 marks C18 Done on `Identities.h:3-6`'s claim that the fact is
"held once" (`recheck6/decisions-C1-C130.md:213`). In fact it is held twice.

**Every reader, with the search.**
`git grep -l given_back` (excluding `sources/`, `audits/`, `proposals/`)
finds 10 files. Each is the spec, its generated output, the attribute's own
C++, or a comment in Identities. `grep -rn 'getGivenBack\|givenBack('` gives:
- `Func.cpp:70` (the name list);
- `Verifier.cpp:109` (its own bounds);
- `Edits.cpp:169` (renumbering);
- `Call.cpp:160` (the tail check);
- `Counting/Bound.cpp:89`, an unrelated local `givenBack(Value)`.

No test names it: `git grep -c given_back -- tests` gives 0 (measured).

**The exact deletion.**
- The ranges above.
- Rewrite `Identities.h:7-13` to say what is true: the fact goes to
  `CalleeFacts` and to the specializer, and dies with the optimizer's run,
  as C18 already says of binding times.
- Regenerate the generated `.td` and Idris files and `generated.manifest`.
- `Settle.cpp:161-163`'s comment drops "what each member gives back …
  which later turns read" only as far as the attribute goes; the publish
  to `CalleeFacts` stays.

**Verdict.** DELETE, about 399 lines:
- 251 hand-written C++;
- about 112 of specification (119 less the 13 moved, plus 6 elsewhere);
- about 36 generated.

Confidence: measured (searches above), read (EGraph.h:363-366, C18).

**Owners and what it waits on.**
- L02 (`lib/IR/Func/`, `IR/Func.h`, `spec/Functions/`; none modified).
- L03 (the generator list in `Generator/Package.idr`). The generated
  `Generated/IdrOps.td` and `generated.manifest` are modified in the
  checkout now, and an untracked `Generated/IdrOps.td.orig` sits beside
  them, so regeneration waits on the lane holding them.
- L18 (`Optimize/Settle.cpp`), L10 (`Tail/Jumps.cpp`, `Tail/Outline.cpp`).
- L16 (the generated Idris bindings, regenerated, not edited).
- INT (`lib/IR/CMakeLists.txt`).
- The coordinator records C18 amended: the fact is the optimizer's alone.

---

## B. The summary solve and the lattice vocabulary: one client, whose answer is a union per component

**The part.**
- `include/idr/Analysis/Solver/Summarize.h:1-55` (`SummaryProblem`, `summarize`).
- `include/idr/Analysis/Solver/SummarizeImpl.h:1-81` (the rounds-to-fixpoint
  loop, with its `Budgeted` branch that writes top).
- `include/idr/Analysis/Solver/Lattice.h:1-64`: `JoinSemilattice`,
  `NodeState`, `FiniteHeight`, `Bounded`, `Summary`, `Exact`, `Budgeted`
  and `Policy`. `CalleesFirst`, `CallersFirst` and `Order` (lines 57-60)
  survive and move into `Schedule.h`, their one includer.
- `unittests/Refusals.cpp:268-313` (`budget_without_top`).
- The client's side:
  - `include/idr/Transforms/Effects.h:86-102` (`AtomsProblem`) and `:114-118` (its extern template);
  - `lib/Transforms/Effects/Writer.cpp:14, 33-35`.

**The fact it supplies.** Each function's row atoms joined callees first.
There is exactly one `SummaryProblem`, `rows::AtomsProblem`, with `Policy
= Exact` (measured: `summarize<` is in `Transforms/Effects.h` and
`Effects/Writer.cpp` only; `Budgeted` appears in `Lattice.h`,
`SummarizeImpl.h` and `Refusals.cpp` only). Its transfer is
`own[f] | ⋃ done[callee]` (`Effects.h:94-100`).

For a union transfer the least fixpoint needs no rounds. Every member of a
cyclic component reaches every other, so each member's row is the union of
all members' own parts and the rows of the callees outside the component.
A non-cyclic component's single member is its own part joined with its
callees'. That is one pass over the components bottom-up.

`lib/Transforms/Effects/Component.cpp:113-120` computes exactly this for
the optimizer's components ("One row for every member"). So one fact, the
rows, is joined by two code paths: an iterated generic solve for the
program and a union for a component. The generic loop also costs up to
(k+1)·k transfers on a k-member component where the union costs k.

**The rule that once required it.** C34 ("`summarize<Order, Problem>`,
explicitly instantiated once per problem") and C15 ("an exact solve and a
budgeted one two types"). Both were written for several problems: a row,
a lifetime signature, a binding time, a dead result, a borrow mask
(`Lattice.h:44-45`, `Summarize.h:4-6`). Of those, only the row is still a
summary problem:
- binding times are per component (`BindingTimes.h:32-60`);
- dead results are a marking (`Optimize/Results.cpp:3-17`);
- borrows are a marking (`Borrows.cpp:109-127`);
- lifetimes are their own planner.

No analysis uses a budget (`Budgeted` 0 production hits). Under the
2026-10-23 rule a vocabulary with no second client goes.

**Every reader, with the search.**
- `Solver/Summarize.h` is included by `Transforms/Effects.h` and `unittests/Refusals.cpp`.
- `SummarizeImpl.h` is included by `Effects/Writer.cpp`.
- `Solver/Lattice.h` is included by `Schedule.h` alone.
- `FiniteHeight`, `Bounded<`, `NodeState`, `JoinSemilattice` and `Summary`
  have 0 hits outside these headers.
- `CalleesFirst` and `CallersFirst` are read by `Schedule.h`,
  `Analysis/Ranges.cpp` and `InPlace/Unique.cpp`, and stay.
- `rows::solveAtoms` (`Effects.h:129-142`, called at `Defunctionalize/Decide.cpp:269`)
  and `rows::write` (`Writer.cpp:104`) are the two call sites.

**The exact deletion.**
- Delete `Summarize.h`, `SummarizeImpl.h`, `Lattice.h` and `Refusals.cpp:268-313`.
- Move `Order`, `CalleesFirst` and `CallersFirst` (6 lines) into `Schedule.h`.
- Replace `AtomsProblem` and the extern template with one
  `joinComponents(graph, own)`: a loop over `graph.sccCount()` that ORs
  each member's own part and each outside callee's row, then writes the
  row to every member. It is about 14 lines and adds members plus edges
  to `work`, which the scale relation reads.
- Both call sites call it. `Component.cpp`'s union is the same rule on the
  optimizer's members.
- Fix the comments at `Schedule.h:7` and `Trace.h:3`.

**Verdict.** MERGE into the effect writer's one join per component (the
`Component.cpp` rule), net about 248 lines. Confidence: read (the lattice
argument, Component.cpp), measured (the client census).

**Owners and what it waits on.**
- L14 (`Solver/`), L02 (`Transforms/Effects.h`, `Effects/Writer.cpp`), L15
  (`unittests/Refusals.cpp`). None is modified.
- The coordinator records the departure from C34's and C15's text.

---

## C. The gated graph and the gated marking: no graph is ever built

**The part.**
- `include/idr/Analysis/Solver/Graph.h`:
  - `:178-258`: `GatedCsr`, `detail::GuardedEdge`, `layOutGuarded`'s
    declaration, `GatedCsrBuilder`;
  - `:170-176`: the `Graph` concept;
  - `:125-127`: `Csr::predecessors`.
- `lib/Analysis/Solver/Graph.cpp:28-58` (`layOutGuarded`).
- `include/idr/Analysis/Solver/Mark.h:51-90`, the `mark(const GatedCsr&)`
  overload, and the "two loops" in its header (`:4-6`).
- `unittests/Refusals.cpp:239-267` (`monotone_gate`, and the "Solves" heading).

**The fact it supplies.** Horn propagation of exclusivity's gates.
Exclusivity has no gates now. It marks plain `Csr`s:
`ExclusivityAnalyses.cpp:217, 395` call `mark<Forward>` on `Csr`, and
`Ownership.h`/`ExclusivityDetail.h` name no guard.

No reader:
- `GatedCsrBuilder` gives 0 hits outside `Graph.h`, so no `GatedCsr` can
  be made (measured).
- `GatedCsr` is named only in `Mark.h` and `Refusals.cpp`.
- `layOutGuarded` appears only in `Graph.h`/`Graph.cpp`.
- `.predecessors(` gives 0 callers; the backward rows stay, read by
  `mark<Backward>` at `Lifetimes/Decide.cpp:37`.
- The `Graph` concept has 0 users. `Expect/ConstantStack.cpp:42`'s `Graph`
  is its own class.

**The rule that once required it.** C34 ("`GatedCsr` … its gates data
propagated as Horn clauses, never a callback"), for exclusivity's gated
marking (P0 §2, line 122). The client is gone, so the requirement is gone.
`Refusals.cpp`'s check that the marking refuses a gate callback guards an
overload no one calls.

**The exact deletion.** The ranges above, and fix the header comment at
`Mark.h:4-6`. No CMake or spec entry. No test outside `Refusals.cpp`
names it (`grep GatedCsr` over the tree outside `audits/`: 0).

**Verdict.** DELETE, about 191 lines (Graph.h 91, Graph.cpp 31, Mark.h 40,
Refusals.cpp 29). Confidence: measured.

**Owners and what it waits on.**
- L14 (`Solver/`), L15 (`Refusals.cpp`). None is modified.
- The coordinator records C34's `GatedCsr` struck.

---

## D. Extraction's "extract, solve, write back" shape: a template no solver calls

**The part.** `include/idr/Analysis/Solver/Extraction.h`:
- `:149-224`: `Offsets`, `extract`, `Openness`, the `Question` concept and `Open`;
- the header prose that describes them (`:3-16`, "Extract, solve, write
  back" and "A solver's domain is a type: an extractor takes only Open
  values …");
- the includes only they need: `ProgramGraph.h`, `MLIRContext.h`,
  `Threading.h`, `<algorithm>`.

**The fact it supplies.** None. Every solver numbers its function with
`Numbering` and walks with `inWalkOrder`, which stay. Measured:
- `Offsets<` 0;
- `extract<`/`solver::extract` 0 (the one hit is LLVM's `mdconst::dyn_extract`);
- `Openness`/`openness` 0;
- `Open<` 0;
- the `Question` hits are `IR/Effects/Classify.h:52`, a different concept.

**The rule that once required it.** C34's "extract-solve-link" and P0's
"three solve shapes". The shape lives on in how the solvers are written;
the template that was to carry it has no caller. Its promise that "a node
for a value whose type settles it cannot be written" is kept by no one.

**The exact deletion.** The ranges above. Includers that leaned on its
`ProgramGraph.h` include add it directly.

**Verdict.** DELETE, about 89 lines. Confidence: measured.

**Owner and what it waits on.** L14. The file is not modified. The
coordinator records C34's text.

---

## E. The second instantiation of every per-component solve: the frozen graph is never passed

**The part.** Each of these is a template over `solver::FunctionNames N`,
explicitly instantiated for both `solver::ProgramGraph` and `solver::Editor`:
- `bindingTimesOf` (`BindingTimes.h:49-60`, `BindingTimes.cpp:90, 196, 209-214`);
- `identities::Component::read`/`givesBackOf` (`Identities.h:125, 147-150, 155`,
  `Identities.cpp:25, 64-67`);
- `readRecord` (`IdentityRecords.h:205`, `IdentitiesRecord.cpp:90-303`'s
  eight `template` heads, `:329-332`);
- `rows::writeComponent` (`Transforms/Effects.h:77-84`, `Effects/Component.cpp:76, 149-152`).

The concept `FunctionNames` is at `Solver/ProgramGraph.h:262-268`.

**The fact it supplies.** It resolves a callee name to an id through either
graph. Every call passes the optimizer's `schedule.graph`, a
`solver::Editor` (`Transforms/Optimize.h:242`). The call sites are
`Optimize/Component.cpp:136` and `Optimize/Settle.cpp:168, 170` (measured:
`bindingTimesOf|givesBackOf|Component::read|writeComponent` gives these
three call sites and no other, unit tests included). The `ProgramGraph`
instantiations are compiled and never called. `FunctionNames` has no
other user (measured: 2 hits, its definition and `Identities.h:155`).

**The rule that once required it.** None written. The comments say "the
frozen graph, or the editor the optimizer holds" (`Effects.h:75-76`). No
caller ever handed the frozen graph.

**The exact deletion.**
- Make the four functions take `const solver::Editor &`.
- Delete both sets of explicit instantiations and the extern templates,
  and the concept.

**Verdict.** DELETE (de-template), about 55 lines, and a body compiled
once instead of twice in each of four units. Confidence: measured.

**Owners and what it waits on.** L14 (Analysis) and L02 (`Transforms/Effects.h`,
`Effects/Component.cpp`). None is modified.

---

## F. `Analysis/Inline.h`: the inliner's constants, not an analysis

**The part.** `include/idr/Analysis/Inline.h:1-36`, which holds
`kLeafSize`, `kSmall`, `kProduct`, `kCallerCap`, `Fit` and `fitsCap`.

**The fact it supplies.** MLton's budget, a constant of the inliner. Its
readers are `Transforms/Inline.h:17` (an include only) and
`Transforms/Inline/Inline.cpp:78, 98, 105, 142` (measured). It analyses
nothing.

**The rule that once required it.** None. Its place in `Analysis/` is
history. The budget itself is kept by AGENTS.md: "may stop at a budget; a
spent budget … never rejects".

**The exact deletion.**
- Delete the file.
- Move the four constants and `fitsCap` into `Transforms/Inline.h`, whose
  `inlining` namespace already documents them (`Inline.h:8-12, 55-60`).
- Drop the include at `Inline.cpp:21`.

**Verdict.** MERGE into `include/idr/Transforms/Inline.h`, net about 23
lines. Confidence: measured.

**Owners and what it waits on.** L14 (the file) and L18 (`Transforms/Inline.h`,
`Inline/Inline.cpp`). None is modified.

---

## G. Exclusivity's recoverable "broke the invariant" path

**The part.**
- `include/idr/Analysis/Ownership.h:98-102, 110` (`brokeInvariant`, `read`).
- `lib/Analysis/Ownership/Exclusivity.cpp:46-53`.
- `ExclusivityGraph.cpp:77-85` (an emitted error plus `WalkResult::interrupt`)
  and `readBody`'s `FailureOr` (`ExclusivityDetail.h:127-131`).
- `Transforms/Ownership/Exclusive.cpp:141-142`.

**The fact it supplies.** A body holds no terminator with block
successors before the lowering. Every `idr` op's region is at most one
block (measured over `Generated/IdrOps.td`: 22 `SizedRegion<1>`, 4
`VariadicRegion<SizedRegion<1>>`, 1 `MaxSizedRegion<1>`, 0 `AnyRegion`).
The state is the compiler's bug, never the program's.

**The rule that once required it.** AGENTS.md lets our C++ check its
invariants freely ("`assert`, or an always-on fatal internal error",
2026-10-22). It does not ask for a recoverable path threaded through an
analysis's result into its pass.

**The exact deletion.**
- Replace the emit-and-interrupt with `reportFatalInternalError` naming the op.
- `readBody` returns `Body`.
- Delete `read`, `brokeInvariant` and the check in `Exclusive.cpp`.

**Verdict.** MERGE into one always-on fatal internal error at the op, net
about 16 lines. Confidence: read.

**Owner and what it waits on.** L08. None of these files is modified.

---

## H. `Analysis/Effects.h`: the one derivation, compiled in IR

**The part.** `include/idr/Analysis/Effects.h:1-300` (namespace `rows`:
`Fold`, `Derivation`, `CallCopies`, `Check`, `told`, `provedTogether`).

**The fact it supplies.** The one derivation of a function's row
(AGENTS.md "One effect system … derived from its ops by one derivation").
It is unique and live: 12 includers. Its definitions are in
`lib/IR/Func/Fold.cpp:37`, `Rows.cpp:113, 150` and `Call.cpp`, compiled
into IdrIR. `ownership.json` names a `lib/Analysis/Effects.cpp` that does
not exist.

**Verdict.** KEEP. Move the header beside its definitions in
`include/idr/IR/Func/` or `IR/Effects/`. No line is deleted. Rule: the one
derivation (AGENTS.md, D20/D22). Unique fact: a function's row and record.
Confidence: read.

**Owner.** L02.

---

## Kept, each with its rule and the fact only it supplies

- **Labels** (Labels.h, Labels.cpp, LabelSites.cpp, Solver/LabelGraph.h,
  LabelPoints.{h,cpp}, LabelSets.cpp; 1,452 lines).
  - Rule: AGENTS.md "defunctionalization makes every closure set of the
    closed, monomorphic module a sum", and C68 (the label solve on the
    program as written).
  - Unique fact: which functions each closure or suspension may be. A
    closure's type is a function type and holds no set.
  - Readers: `Defunctionalize/{Pass,Decide,Edits,Convert,Declare}.cpp`.
    `Points::described` and `labelsAt(PointKey)` are read only by
    idr-expect's `labels-least` (`Expect/LabelsLeast.cpp:94, 175`), an
    oracle check the testing guideline names; keep both.
  - Survives, could be simplified (conjecture): `ClosureParts`
    (`LabelSites.cpp:46-80`) walks a constant by value to learn whether
    it holds a closure, where the constant's type could rule most out
    at once.
- **Identities** (1,560 lines), less A and E.
  - Rule: C18.
  - Unique fact: gives back, and may reach, per result field path.
  - Readers: the e-graph (`EGraph/Nodes.cpp:549`) and specialization
    (`Specialize/Open.cpp:431-475`).
- **BindingTimes** (277 lines).
  - Rule: C117 and C18 ("the optimizer's alone").
  - Unique fact: a fixed parameter of a recursion.
  - Readers: `Specialize/Keys.cpp:46`, `Requests.cpp`, `Specialize.cpp`.
- **Constants** (188 lines).
  - Rule: C32 (idr-constants on upstream's framework).
  - Unique fact: constants through loops, join points and callees'
    returns, which the e-graph's per-expression folds do not see.
  - Readers: `Effects/Constants.cpp`, `Optimize/Settle.cpp:184`, and
    `Conversion/Lower.cpp:140` (`foldingOf`).
- **Ranges** (398 lines).
  - Rule: C32.
  - Unique fact: interprocedural integer ranges for narrowing.
  - Reader: `Narrow/Narrow.cpp:89`.
- **TypeGraph** (291 lines).
  - Rule: AGENTS.md "`idr-knots` refuses every one [cycle]".
  - Unique fact: which array types reach themselves.
  - Reader: `Ownership/Knots.cpp:108-167`.
  - The CMake comment that exclusivity reads it is stale
    (`lib/Analysis/CMakeLists.txt:5-6`); `Exclusive.cpp:213` only
    preserves it.
  - Survives, could be simplified (conjecture): a family group already is
    a strongly connected set of declarations, so the module walk might be
    a per-group read.
- **ProgramGraph, Components, Csr and the plain marking, Schedule,
  UnionFind, Work, Trace, Decision** (about 1,300 lines).
  - Rule: C33 and C34; the cycle rule held once (N2); AGENTS.md's solve
    sized by the problem.
  - Each has live clients.
  - Survives, could be simplified:
    - ProgramGraph lays its components two ways: upstream's `getSCCs()` at
      construction (`ProgramGraph.cpp:98-112`) and `components()` at
      freeze (`:142-165`). C33 keeps upstream's call graph, so this stays
      KEEP.
    - `DecisionAnalysis`/`decided`/`decideStep` serve one pair (Ranges
      and idr-narrow).
- **Exclusivity** (about 1,180 lines) **and Borrows** (393 lines), with the
  shared Ownership headers.
  - Rule: AGENTS.md's frame-limited rule and counting's proved copy
    optimizations, C91/C92.
  - Unique facts: `unique deep` by context, written into grades by
    idr-rc-exclusive, and each parameter's release axis, written by
    idr-rc-borrows.
  - Survives, could be simplified (conjecture): "an argument reaches a
    result" is derived four times over the flow interface, in Identities'
    may-reach, Borrows (a returned parameter is counted), the lifetimes'
    `reachesReturn` (`Lifetimes/Decide.cpp:37`) and Exclusivity's result
    bits. They run at different stages on different IR, and no carrier
    crosses them; worth a design question, not a deletion here.

---

## Table

| | Candidate | Verdict | Lines removed | Owner | Waits on |
|---|---|---|---|---|---|
| A | `#idr.given_back` attribute chain | DELETE | ~399 | L02, L03, L18, L10, L16 (generated), INT | the lane holding the modified `Generated/IdrOps.td` and `generated.manifest` (regeneration; untracked `IdrOps.td.orig`); C18 amended by the coordinator |
| B | `summarize`, `SummarizeImpl`, `Lattice` (one Exact client, no Budgeted) | MERGE into the effect writer's per-component join | ~248 net | L14, L02, L15 | C34/C15 text recorded |
| C | `GatedCsr`, gated `mark`, `layOutGuarded`, `Graph` concept, `predecessors` | DELETE | ~191 | L14, L15 | C34 text recorded |
| D | `Extraction.h`'s `Offsets`/`extract`/`Open`/`Question` | DELETE | ~89 | L14 | C34 text recorded |
| E | `ProgramGraph` instantiations of four per-component solves, `FunctionNames` | DELETE | ~55 | L14, L02 | nothing |
| F | `Analysis/Inline.h` | MERGE into `Transforms/Inline.h` | ~23 net | L14, L18 | nothing |
| G | Exclusivity's recoverable invariant path | MERGE into one fatal internal error | ~16 net | L08 | nothing |
| H | `Analysis/Effects.h` placement | KEEP (move to IR) | 0 | L02 | nothing |
| - | Labels, Identities core, BindingTimes, Constants, Ranges, TypeGraph, solver core, Exclusivity, Borrows | KEEP | 0 | L14, L08 | - |

**Total removed by the DELETE and MERGE verdicts: about 1,021 lines.**
About 399 are A's chain into IR, the specification and generated output,
which the Identities analysis feeds. The other about 622 are B to G,
mostly the solver layer and the analyses, with the effect writer's and
the inliner's sides of B, E and F.
