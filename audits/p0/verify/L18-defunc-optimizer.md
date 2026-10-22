<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane L18: defunctionalization, specialization, the optimizer

**Engagement.** HEAD `e96bb991` at start (2026-10-21T21:31Z) and at
finish (see the last line). Read in full first: the representation-first
skill, AGENTS.md, `proposals/0000-mlir-native.md` (whole, re-read at
21:58Z when it had grown D53 to D55). Reread: 06 whole; 09 whole;
synthesis B; §5.9; `design/perf-sources.md` (C1, C2, C3, §3, §4); 15
(§2, §3, §5, §6: the frontend's specialization); 16 (§2, §3.1: the growth
check); `design/match-and-counting.md` §4, §6, §7, §9; synthesis G's
drafts DP-26, DP-33, DP-34, DP-36, DP-38, DP-40, DP-48 to DP-55, DP-64,
DP-65, DP-68 (not yet in the proposal: "G's decisions: being folded in",
§3); `proposals/0003-facts-once.md` (its items in this area). Code read:
`foreign/idr/lib/Transforms/{Defunctionalize,Specialize,Optimize,Inline,Deduplicate,Identity}/`,
their headers, `lib/Analysis/{Labels,LabelSites,Inline}.cpp`,
`include/idr/Analysis/{Labels,Inline}.h`, and what they call where a
claim rests on it (`lib/IR/OpsCon.cpp`, `OpsClosures.cpp`,
`Constants.cpp`, `Verify/Knots.cpp`, `Canon/Force.cpp`, `IdrOps.td`,
`IdrTypes.td`, `IdrBase.td`, `IdrClosureOps.td`, `IdrAttrs.td`,
`Tail/Loop.cpp`, `Tail/WhileDo.cpp`, `Pipeline.cpp`); the frontend's
`Frontend/Growth.idr`, `Translate/Recursion.idr`, `Translate/Programs.idr`,
`Emit/Closures.idr`; `libs/mlir-linear/Linear/{List,Nat}.idr`; the
megamorphic refusal tests under `tests/`; upstream at the pin:
`mlir/lib/Pass/Pass.cpp`, `mlir/lib/Transforms/CSE.cpp`,
`mlir/lib/Transforms/Utils/Inliner.cpp`, `mlir/include/mlir/Transforms/Inliner.h`.
Sibling files read for seams only (read-only): L13, L14, L16.

Marks: *read* (path:line at HEAD; `idr/` is `foreign/idr/`, `mlir/` is
`.toolchain/llvm-project/mlir/`), *measured* (the command), *recalled*,
*conjecture*, *decision* (a ruling Dn or Cn). Nothing was built or run.

## 1. Verification

Classifications: **defect** (confirmed in the source), **incomplete**
(structural incompleteness), **mismatch** (integration mismatch),
**unverified** (behaviour not run), **simplification** (optional).

### 1.1 The rulings and decisions this lane names

| ruling / claim | verdict | evidence | class |
| --- | --- | --- | --- |
| **D10**, the example AGENTS.md and §1 cite: defunctionalization "built, froze and destroyed a pattern set of one pattern per registered op for every function, about 11% of the dialect suite's sampled CPU, in a per-function step that took 70%" | **holds with a correction** | *read*: `convert` builds a converter, a target and a `RewritePatternSet` per function (`idr/lib/Transforms/Defunctionalize/Pass.cpp:87-104`), run for every function in parallel (`:138-141`); `populateDefunctionalizePatterns` adds one `RetypePattern` per `getRegisteredOperations()` entry but a hand list of nine (`Patterns.cpp:277-284`); `applyFullConversion` freezes it per call. *Measured by the agent* (perf-sources M9, 51a4771b): populate 4.7 %, freeze 4.3 %, destroy about 1.9 % of `make test-idr`'s on-CPU samples, the per-function lambda 70 % by total. *Correction*: 52 % of those samples are one fixture (`defunc-tag-limit`, 65,538 functions), so "11 % of the suite" is mostly that fixture; the stage-1 share is unmeasured (perf-sources U4). The fix does not depend on the share: no pattern set exists in the target (DP-48, §2.1). | defect |
| D10's residue in this area: anything else static built per function | **holds with a correction** (a residue the design has not named) | *read*: idr-identity, an inner step run per member per round, builds and freezes a one-pattern `RewritePatternSet` in `runOnOperation` (`idr/lib/Transforms/Identity/Identity.cpp:79-81`), not in `initialize`. The other inner steps are fine: a dynamic pipeline is initialized once per generation (`mlir/lib/Pass/Pass.cpp:482-495`), so the inner canonicalize freezes its patterns once per pooled pipeline copy (`Component.cpp:83-98`). Deleted with idr-identity itself (§4 I8). | incomplete |
| **D19**, contification: "a local tail call contification finds, is a join point"; contification after Fluet and Weeks | **holds as the target; today's code is a restricted form** | *read*: idr-contify moves only a function of one call site from a member of its own cycle (`Contify.cpp:3-13, 95-123`), because "a second call site would need a branch out of a match region into a block they share" (`:10-13`), which D25's early exit now provides. It runs once, before the optimizer (`Pipeline.cpp:78-81`); MLton runs contification three times, once after inlining exposes tail calls (§5.9 E1). The encoding and the algorithm are L09's; this lane fixes where it runs in the optimizer's sequence and what it may not change (`total`, 1.2). | incomplete |
| D19, the QTT claim in this lane's charge: "a linear closure applied once is never counted and becomes a join point" | **holds with a correction** | It holds where the closure's construction and every application are in one function (after inlining): each application's dispatch is a match on a known constructor, which folds, so the constructor is never built (no cell, no count); if every application is in tail position the label's body becomes one join region (`design/match-and-counting.md` §6). It does **not** hold for a closure that escapes (passed to a callee that is not inlined, stored): it is a cell, consumed by its one dispatch, and that take reads no count only if the value is exclusive. Linearity proves exclusivity only for a closure born linear (a linear capture, `Idr_LinearWhenACaptureIs`, `IdrClosureOps.td:22-26`): QTT's scaling forbids duplicating it. An unrestricted closure passed into a quantity-1 parameter is linear in the callee and may be shared (AGENTS.md: "a linear binder does not imply unique heap ownership"). §3 states the corrected rule. | incomplete |
| **D44**: 0003 whole; the items in this area | **holds; each item placed** | §1.3 maps every 0003 item of this area to its disposition. One correction: 0003 B7 says "C++ keys specialization nodes by the string" of the instance. *Read*: no C++ reads a function's `instance` but dedup, which excludes it (`Equivalence.cpp:66-76`; `grep getInstance lib`: types only). C++ keys nodes by the owner's *symbol*, a `StringAttr` (`Requests.cpp:138-140`), which is the frontend's printed identity. DP-65's arena keys over `FunctionId` delete that too. | mismatch |
| **D48**, closure and memo sums as families a pass declares | **holds with corrections** | *read*: today a closure sum is a `DataType` of kind `Closures`, one constructor per label in name order, each `role::Label{fn, byName}` holding its captures; a memo sum adds `running` (no field) and `forced` (the value) (`Declare.cpp:172-213`; `IdrDialect.h:146-172`). Identity is the key `(carrier at no grade, label set)` (`Defunctionalize.h:54-65`), and content (labels, captures' slot types) determines the key, so D48's "identity is content" fits. *Corrections*: (1) D48 makes indices type-level variables (`idr.func @map<n : nat>`), so a closure built in `@map<n>` that captures `xs : #Vect[n]` and flows out as `Int -> Nat` needs the family to bind `n` per constructor (an existential index binder) or to take the carrier's free index variables as its indices; neither is designed (§4 I5). (2) A memo cell is "always a box" today (`Declare.cpp:34-42`); D48 deletes `!idr.box` as a type, so the memo family's "one shared cell" must be declared by its kind and its construction op, not by layout (§4 I2, I5). (3) `byName` is a `bool` in the role (`IdrDialect.h:155-160`): a sum `Memoized | ByName` (06 D-20). (4) DP-40's "defunctionalization boxes its closure sums by the same rule" is stale against D48: a closure family's recursive field is a cell by D48's layout rule, and no pass boxes anything. | incomplete |
| **C3**, pure construction before counting (`con`, `closure`, `suspend`, `delay` of an unrestricted value pure: merged, deleted, hoisted) | **holds with a correction**: not for an unforced memo cell, nor for a value of an `in_place` type | (a) *read*: today a memo cell is a box, `con` of a box allocates (`OpsCon.cpp:50-56`), so CSE never merges one; C3 with D48 removes that guard. A memo cell is "the one cell that changes while references to it live" (`IdrClosureOps.td:164-166`): merging, hoisting or folding one changes when its forced value dies, and folding makes it static data whose forced value is made persistent (`Verify/Knots.cpp:10-14`, `Conversion/StaticData.h:3-5`; `Symbols.h:40-45` already names "one static cell every run of the program shares and forces"). (b) *read*: `SuspendOp::fold` folds a suspension of constant captures into a constant (`OpsClosures.cpp:159-165`), and `ConOp::fold` folds a constructor of constant fields, a memo sum's included (`OpsCon.cpp:108-120`; `Constants.cpp:122-127` admits it): **today**, after defunctionalization, idr-optimize's canonicalize turns every capture-free suspension of a function body into one program-wide static memo cell (§4 I2, counterexample (a)). (c) `in_place` values (`LList`, `LNat`, `libs/mlir-linear/Linear/List.idr:13-15`) bound at ω: merging two equal ones turns two exclusive arguments into one shared one, so D24's call is refused after an optimization (§4 I2, counterexample (c)). (d) `closure`, `delay` and every other `con` are pure as C3 says: merging immutable values never extends anything's life by more than one cell header. | defect (b); mismatch (a, c) |
| C3's own deletes: "the hand list in `Expect/Allocation.cpp:28-33`" | holds | *read*: `Allocation.cpp:24-29` lists closure and suspension by hand. Under C3 no construction allocates before counting, so the property is asked after counting (at `cell.new`) and the list goes. | — |
| §5.1's bullet "**A closure acquires its cell** (C3)" | **refuted** (stale) | It states C3's first version; C3 as revised says a closure is pure before counting. | mismatch |
| **AGENTS.md's megamorphic refusal**: refused "with an `unsupported` error that names the site and the value whose set is unbounded, never compiled to a uniform boxed form"; "defunctionalization makes every closure set of the closed, monomorphic module a sum" | **holds for growth; refuted for implementation choices from a set the program fixes** | *read*: the C++ side refuses nothing: defunctionalization "refuses nothing, and fails only when the compiler broke its own invariant" (`Pass.cpp:7-9`); the label solve has no unknown (`Labels.h:19-23`); the specializer emits no `unsupported` (09 §6, *measured* there). The growth refusal names the site (`place.at`) and the value that grows (`Growth.idr:255-268, 288-298`). But seven tests refuse, under rules of category `Megamorphic` (`IdrBase.td:192-202`), programs whose choice is among a set the program fixes: `runtime-closure-implementation` picks `Semi Int`'s `plus` or `times` by input; `dictionary-field-two-implementations` and `dictionary-field-opaque-type` hold two `Ord`s in one map type; `static-argument-stuck-implementation` picks between two by a `covering` function; `runtime-closure-index-function`, `-scope-constructor-field`, `-shape-constructor-field` hold one implementation over a runtime value (*measured*: `grep -l -- "-- expect: runtime closure,\|dictionary field,\|static argument," tests/*/Main.idr`, 7 files). Each set has one or two members: a closed sum of method records, which defunctionalization compiles, so these refusals are a representation limit. AGENTS.md's own example ("an implementation chosen by a runtime value") contradicts its definition ("whose set at a site no compile-time analysis bounds") here: owner question Q1. | mismatch |
| **DP-48** (types first, no per-function conversion) | holds | 06 T1's evidence re-read (`Pass.cpp:56-104`, `Patterns.cpp:240-285`, `Defunctionalize.h:99-108`). It also needs no type made on a worker: every family and sum type is made in the serial decision, the walk only reads them (§2.1). | — |
| **DP-49** (one sink per operand, kept) | holds; now part of an acceptance specification | `LabelSites.cpp:106-110`. Since knots reads the sums (1.2), the unification rule is part of what the knot rule refuses (Q2). | — |
| **DP-50** (effects in defunctionalization's decision; `by_name`) | holds with a correction | `by_name` is read off the label's row: the `io` atom of D29, which is the outside's read and write and excludes `exit`, `crash` and `divergence` (a crash or an exit happens once, so memoizing it changes nothing); `ObservableIO`'s own text says the same set (output, input, a file, a clock; `IdrInterfaces.td:299-307`). The row's first solve is over the graph the label solve's firings complete (L14 §2.1.4 #1). | — |
| **DP-26** (dedup by partition refinement, cycles merged) | holds with a correction: it must run after knots | §4 I1: deduplication before the label solve can add a knot refusal. Placed after defunctionalization and knots, it compares closure families' labels as class slots (06 U-13's gap, closed by the refinement itself). | mismatch |
| **DP-64** (MLton's order: specialize to completion, inline once with true counts; polyvariance a C++ pass before defunctionalization under a budget) | holds with corrections | (1) Polyvariance before the label solve makes the knot rule's verdict depend on a budget (§4 I1): excluded, unless it follows an acceptance solve. (2) Separating the phases loses keys only inlining exposes (09 Q-opt-1); leaf inlining (a body with no call) cannot unroll anything and needs no count, so it interleaves with specialization (§4 I7). (3) A `Beta` node is weighed, not always inlined: its inlining cannot unroll, but it saves no allocation (its key already removed the closures, `Requests.cpp:42-52`), so MLton's product rule with true counts applies. (4) The weighed phase on upstream's `mlir::Inliner` first (§4 I7). | incomplete |
| **DP-65** (keys as the run's interned data, no context lock) | holds with a correction | Names stay digests of the key, but of a canonical byte encoding with owners spelled by symbol, not of printed text (`Requests.cpp:139-140` digests `canonicalText`, `Symbols.h:253-271`: R9's "identity is never text"); keys gain index patterns under D48 (§2.2). | — |
| **DP-68** (a canonicalization before defunctionalization) | **refuted** | §4 I1 (it changes the label sets knots reads, under a budget, DP-33) and §4 I2 (it folds a function's suspension into a static memo cell, and the decision then treats its label as a static suspension, memoized even when its runs are observed, `Pass.cpp:116-134`: a trusted library's effect would happen once instead of where the value is demanded). Its gain is compile-time set size; the optimizer's known-constructor fold after defunctionalization gives the same code. | defect |
| **DP-33** (no budget in an analysis a refusal rests on: the label solve, defunctionalization, idr-knots) | holds with a correction | The list is right; the inputs must be named too: the knot rule reads the label solve's sets, so nothing that is an optimization may run before that solve (§4 I1). | mismatch |
| **DP-34** (determinism at any thread count; deletes OPT-48's lock-ordered chain) | holds | §1.2 OPT-48. | — |
| **DP-36** (deletes "the optimizer's facts that die with its run") | holds with a correction | gives-back becomes DP-38's call fact (one holder); binding times and inline verdicts are read by the optimizer alone, so each is computed once in the run and dies with it, which DP-36's "a cached analysis holds only what one pass reads" allows (§2.4). | — |
| **DP-52** (one program graph) | holds; seam fixed | The label solve runs before the graph is born (L14 §2.1.1: "exists from defunctionalization"); it numbers functions in program order, the graph is born with those ids (§2.8). | — |
| **DP-54** (dead parameters as demand bits; "a function a closure label names has an unknown caller") | holds with a correction | After defunctionalization every caller of a label function is a dispatch case or a force function, all in the program graph (`Patterns.cpp:124-176`, `Forces.cpp:88-156`): no caller is unknown. An unread capture is narrowed by dropping its constructor's field (a family the pass declares anew), which only shrinks the type graph after knots. The "unknown caller" rule holds before defunctionalization only, where no demand bit is solved. | simplification |
| **C8** for OPT-48 and OPT-14 ("outside what P0 replaces; reproduced and fixed on main") | **corrected** | Both are inside what P0 replaces (DP-64 and DP-65 rewrite `Requests.cpp`; DP-52 and §4 I7 rewrite the inline step), so by C8's own rule each goes with its cause. OPT-14's consequence is refuted (next row); OPT-48 holds and its test (DP-34's) can land on main now, since a behaviour test survives the cutover. | mismatch |

### 1.2 Load-bearing claims under them

| claim | verdict | evidence | class |
| --- | --- | --- | --- |
| 09 OPT-14 / §8: "inlining edits a function outside a pass; CSE may read stale dominance" | **refuted** in its consequence | *read*: every `Pass::runPipeline` ends by clearing the nested analysis manager of the op it ran on, children included (`mlir/lib/Pass/Pass.cpp:673-679`, `am.clear()`; `AnalysisManager.h:365-367`). So nothing CSE preserved survives to the inline step that follows (`Component.cpp:148-160`), and no stale `DominanceInfo` can be read. What remains: the inline step's and the effect stamps' output is verified only after the next inner pass (attribution, not correctness). Upstream's `Inliner` has the same shape and the same protection (`Inliner.cpp:570-585`). | — |
| 09 OPT-48: the lifted key depends on lock order | **holds** (occurrence *conjecture*) | *read*: a node's `parents` are pushed under the table's lock in the order workers take it (`Requests.cpp:153-155`); `chainOf` reads them first-in-first-out (`:91-104`); `differing` lifts against the *first* same-shape key of `earlier` (`:194-216`). Two requesters of one new key in one wave, whose chains hold two distinct same-shape keys of one owner, make the node depend on the schedule. | defect |
| 09 OPT-12, OPT-84 (made nodes inlined as one call; five rules after five unrollings) | holds | `Optimize.h:177-181`; `Analysis/Inline.h:41-52`; `Inline.cpp:59-112`; commits named in 09. DP-64 deletes both. | — |
| `idr.func`'s `total` and `absorb` ("a body that takes in a callee without it loses its own") | **defect**: the proof is lost by an optimization | *read*: `absorb` clears `total` whenever the callee lacks it (`IdrOps.td:181`), called on every inline (`Inline.cpp:156`) and every contification (`Contify.cpp:109`); a made node keeps its origin's (`IdrOps.td:133-136`). Loop formation reads `total` to decide whether a self-recursion's loop may run forever (`Tail/Loop.cpp:131-134`, `Tail/WhileDo.cpp:280-283`); the row reads it as the body's divergence (`Func.cpp:190`). Inlining a callee from another call-graph component never adds a loop through the caller, so clearing the caller's proof there loses a fact (§4 I3). | defect |
| 06 L-10, L-11: the label solve's waves cost O(W·(P+E) + W·D) | holds | `Labels.cpp:213-300`; W unmeasured (06 §8). 06 T2 fixes it (difference propagation, dispatches hung on their callee's class); kept in §2.3. | — |
| The label solve is an acceptance analysis (DP-33, B §3.11) | **holds, and its inputs matter** | idr-knots refuses "an array whose element type can reach the array again" on the types defunctionalization made (`Verify/Knots.cpp:1-21`; `Pipeline.cpp:72-74`), whose closure fields are the label sets. Whatever runs before the solve and changes those sets changes what knots refuses: today deduplication (§4 I1). | mismatch |
| Deduplication runs first "so the label sets are made over fewer functions" (`Pipeline.cpp:62-66`) | holds as a compile-time gain; its cost is acceptance | *read*: it merges label functions too (`EliminateDuplicateFunctions.cpp:23-26, 202-212`); a merged function's parameter points become one (`LabelSites.cpp:27-32, 150-163`). The gain was 7 % of functions at stage 0 (234b81a0, *read* in 06 §2.5: 7,505 of 107,732). | mismatch |
| 09 §2.4: no pass of this subsystem defines a data type | holds today; changes | D48 and §4 I5 make defunctionalization declare families, and DP-54's narrowing redeclares one; both run serially. | — |
| The specializer terminates with no count (Kruskal: an embedding is a well-quasi-order; a lift turns a scalar into a hole) | holds | `Requests.cpp:27-40, 172-223`; `Order.cpp:131-164, 217-224`. D53 adopts the same mechanism for the elaborator's search, which confirms the argument's standing with the owner. | — |
| The inliner terminates by construction | holds today by the cap and the order; re-argued for the target in §2.5 | `Inline.cpp:116-168` takes the call list once; `kCallerCap` (`Analysis/Inline.h:30`); never a member of a cycle but by `betaReduces` (`Inline.cpp:83-112`). | — |

### 1.3 0003 (D44) in this area

| 0003 item | disposition |
| --- | --- |
| `Effects.cpp` preserves only `SymbolTable`, so Contify rebuilds `CallCycles` | idr-effects goes (DP-50); the graph is born in defunctionalization and kept (DP-52). |
| `Defunctionalize/Pass.cpp` builds a `TypeGraph` for a statistic; `layout::fit`'s second remap | both go: layout is D48's function of the type, the statistic is read off the decision (06 T5). |
| `givesBack` solved twice | DP-38's call fact; Returned's re-solve deleted (L10, L14). |
| the optimizer rescans each wave; restamps every call's effects each round | counts per component on the program graph (09 T1); a call carries its callee's row, written when the callee becomes final (D22). |
| a consumer form cloned per request and named by printing | forms interned in the run's arena by the structural hash dedup uses; named by that hash's bytes (§2.2). |
| a raise node's consumer at `UnknownLoc` | `CallSiteLoc(op, terminator)` (09 T7). |
| Deduplicate fuses only the function's location | op by op along the equivalence's correspondence (06 U-6). |
| frames' `closureLabels` walks every value's type | the declared closure families are the pass's output list (§2.2); frames reads the families (L10). |
| no `DataType::memo()`; the force dispatch's catch-all internal error | the memo family's own view (§2.2), so the dispatch's match is exhaustive by type (06 D-24). |
| `holdsLabels(Value)` repeats `carriesLabels(Type)` | one fact on the carrier (06 L-1), read once per type. |
| the optimizer matching inner statistics by name strings | deleted with the inner cse's statistics (09 OPT-33): upstream's `eliminateCommonSubExpressions` counting into our statistic. |
| B7: an instance's identity printed for C++ | C++ keys by `FunctionId` (DP-65); `#idr.instance` is text for humans and the dedup key excludes it. |
| `SpecKeyAttr`'s `origin` means the owner | keys are arena data with an `owner : FunctionId` (DP-65); the attribute goes. |
| a refusal rule's category false of some of its sites (`static-argument-stuck-implementation`) | Q1: compile the bounded choice rather than recategorize the refusal. |

## 2. Boundaries

### 2.1 The end state, in pipeline order

1. **The frontend's program** (L16): monomorphic in types and
   implementations, index variables kept as quantity-0 parameters
   (D48), closures as `idr.closure`/`idr.suspend`/`idr.delay`, applies
   and forces, `total` per function. No pass of ours runs before step 2.
2. **The label solve** (an analysis, shape G, the solver layer): extracts
   each function in parallel into arrays (sources, links, dispatches),
   functions numbered in program order, parameter and result points
   `(FunctionId, index)`, anchors interned (per family declaration,
   constructor and field; per element type; per lazy type's forced
   state); solves by union-find over interned sets with difference
   propagation and each dispatch hung on its callee's class (06 T2);
   answers a set per point and the firings `(dispatch, label)`. Total, no
   budget, refuses nothing. **It reads the program as the frontend wrote
   it** (§4 I1).
3. **idr-defunctionalize** (a program pass), serial decision then a
   parallel walk:
   1. the program graph is born from the extraction's calls and the
      firings (L14 §2.1.4 #1); SCCs computed once;
   2. the first row solve, callees first (L02's derivation, DP-50);
   3. `by_name` per memo label from its row's `io` atom;
   4. keys `(carrier, label set)`, widening (06 `Moves.cpp`), and every
      closure and memo family declared, serially, with every type made
      here (§2.2);
   5. per function in parallel, one walk: each carrier value takes its
      key's type in place, each operand whose sink key differs gets the
      coercion match (MLton's `coerce`), a closure becomes its label's
      constructor, an unforced suspension its memo cell's construction
      op, a `delay` the `forced` constructor, an apply a match whose
      cases call the labels, a force a call of `<family>.force`;
   6. each memo family's dispatch function defined (serial), added to the
      graph.
   No pattern set, no conversion driver, no type made on a worker; the
   stage verifier refuses any closure op or closure-typed value left.
4. **idr-knots** (acceptance): reads the families' fields and array
   element types; refuses a cycle through an array. Nothing before it
   is an optimization.
5. **idr-deduplicate**: partition refinement over the program graph and
   the families' label references, upstream's `OperationEquivalence`
   with a symbol hook (06 T4, DP-26); duplicates in cycles merged; the
   kept member the first in symbol order; one replacement of every
   merged symbol, types' labels included; the graph edited in place.
6. **idr-contify** (L09's algorithm): Fluet and Weeks over the program
   graph, functions whose continuation is one become join regions.
7. **idr-optimize**, two phases, a fixed sequence:
   - *specialize*: bottom-up over components with made nodes and parked
     requesters (the one dynamic client of the graph, DP-52); per member
     a pipeline of inner passes: redirect (keys, §2.2), leaf inlining
     (a callee whose final body holds no call and at most 40 ops),
     upstream canonicalize (configured once, DP-67), cse, idr-constants
     (upstream SCCP per function); a member's turn ends when a round
     asks for no node and inlines no leaf; its demand bits (DP-54) when
     its component finishes;
   - *inline*: once, on the final graph, upstream's `mlir::Inliner` with
     the verdict sum as its profitability callback (§2.5), the
     simplification pipeline per callable; then contification once more
     and join-point formation for known closures (§3), then the row
     re-derivation (L14 §4 I2).
8. symbol DCE and the rest of the pipeline (columns, arrays, counting,
   tail passes, lowering), not this lane's.

**MLton's order against ours.**

| step | MLton (§5.9) | ours today | the target |
| --- | --- | --- | --- |
| monomorphization | `Monomorphise`, never refuses | the frontend; the growth check refuses | the frontend (L16) |
| polyvariance | before 0CFA, `small 30, product 300, rounds 2` | none | none: before the acceptance solve it would move acceptance with a budget (§4 I1) |
| function dedup | none (`Redundant` merges arguments) | first | after knots (§4 I1) |
| closure conversion | 0CFA, a sum per flow set, `coerce` | the same, a conversion per function | the same, types first, families declared |
| reference knots | (a collector) | after dedup | right after defunctionalization |
| contification | three times in SSA | once, one call site | before the optimizer and after its inline phase, join points (L09) |
| inlining | leaves early, product rule once, never recursive | interleaved per round with specialization, five rules | leaves during specialization; product rule once with true counts; `Beta` weighed |
| specialization | none beyond polyvariance | constructor keys after defunctionalization, embedding and lifting | the same, keys in an arena, index patterns, a lift over sets |
| dead arguments, results, fields | `removeUnused`, four times | none since 16005000 | demand bits (DP-54), unread captures as dropped fields |
| normal form | the shrinker after every pass | greedy canonicalize per round | upstream canonicalize configured once (DP-67) |

### 2.2 Types, attributes, ops and data, by name and shape

**Closure family** (declared by defunctionalization; grammar L04's):
`#idr.family<kind closures, [i₁ … iₖ : sort] { @c₀ fn @l₀ where m… (f₀ …) ; … }>`
- indices `i₁ … iₖ`: the free index variables of the key's carrier, in
  first-occurrence order (§4 I5);
- one constructor per label, tags in the label's rank order (name order,
  `Labels.cpp:184-208`); each names its function as a **symbol use**
  (upstream's walkers see it: `IdrTypes.td:101-115` today); binds the
  label's index parameters the carrier does not fix (`where m : sort`,
  no equation); fields are the captures at their slot types, with
  their quantities in the types (`!idr.lin<T>`);
- identity: content, so `(carrier, labels)` and the family are one fact.
  Every empty-label family is the one uninhabited family (an apply of it
  is poison, `Patterns.cpp:102-107`).

**Memo family** (declared by defunctionalization):
`#idr.family<kind memo, [i… ] { @l₀ fn @… mode memoized|by_name (captures) ; … ; running () ; forced (value) }>`
- `mode` a two-case enum, never a `bool` (06 D-20);
- the kind says "one shared mutable cell": layout is always a cell,
  whatever recursion, and a value of it is built only by the cell's
  construction op (an unforced label state, `Allocate` on `identity`)
  or as `forced` (pure), and changed only by `memo.run` (§4 I2).
- its view `memo()` gives the labels, `running` and `forced` by role, so
  `<family>.force`'s match is exhaustive by type (06 D-24, 0003).

**`<family>.force`**, one function per memo family: takes the cell
(borrowed), matches its state: a memoized label's case runs `memo.run`,
a `by_name` label's case calls the label, `running` crashes with the
cause "a suspension forced itself" from the crash-cause enum (D38),
`forced` yields. Its `total` is true (its body is a match and calls, no
loop of its own; `Forces.cpp:73-78`).

**Specialization keys** (arena data of one optimizer run, DP-65):
```
Key     = Spec{owner : FunctionId, params : Vect arity Pattern, indices : Vect k IndexPattern}
        | Raise{callee : FunctionId, form : FormId}
Pattern = Hole | Con{tag : Tag, fields : List Pattern} | Const{value : Attribute}
IndexPattern = Var | Term{t}            -- t in D48's index language
```
- hash-consed in a bump arena freed with the pass; equal keys one node;
- a node's name: `<owner symbol>.<spec|raise>.<16 hex>` from XXH3-128 of
  the key's canonical bytes (owner by symbol, tags, constants' value
  bytes, index terms), never printed text (R9); stable across runs and
  thread counts (stage 2 = stage 3);
- the order (embedding) and the lift as today, extended to index terms,
  which compare and lift as scalars do (a differing index constant
  becomes `Var`);
- **the lift is anti-unification over the set** of every same-shape key
  on the requester's given keys and its chain at once: positions where
  the request differs from any of them become holes (`Var` for indices).
  Order-independent by construction (§4 I6);
- consumer forms (`FormId`) interned in the same arena by the structural
  hash deduplication uses.

**Node kinds and phases** (the optimizer's schedule, 09 T2, T4):
`Kind = Held | Spec | Raise | Beta | Step`, decided at the grant;
`Phase = Waiting | Parked{on, solved} | Done{solved} | Final{summary}`.

**Inline verdict** (per final function, inline phase only):
`Verdict = Keep(Cycle | Step | Cap) | Leaf | Weighed{size, calls}`, with
`Beta` nodes weighed although on a cycle (§2.5).

**Facts held on the IR** that this area writes or reads: `total` on
`idr.func` (written by the frontend, by defunctionalization on force
functions, and by the specializer on a made node; nobody clears it,
§4 I3); the effect row (L02); `gives_back` and tail kind on calls (L10,
L14).

### 2.3 Invariants

- (V1) After step 3 no closure op, closure-typed or lazy-typed value, apply
  or force exists (stage verifier, `Verify/Program.cpp:214-219` today).
- (V2) Every carrier value's type is its key's family; every coercion sits
  at an operand whose sink key differs from its value's.
- (V3) A memo family's cell is built only by its construction op or as
  `forced`; no folder, CSE or motion merges, moves or folds the former.
- (V4) Every closure family's labels name functions of the program; a
  label's constructor fields equal the label's capture slot types.
- (V5) The label solve's answer is the least solution of the frontend's
  program's constraints (`labels-least`, `Expect/LabelsLeast.cpp`).
- (V6) A specialization node's key is unique in its run; its name is a
  function of the key alone.
- (V7) Inlining never inlines a call whose callee is on the caller's
  cycle, except a `Beta` node, whose body calls no node of its own key.
- (V8) `total` is never cleared by a pass; a made node's is its origin's,
  or true when its final component has no cycle (§4 I3).
- (V9) No context attribute or type is made by a worker of the optimizer
  or of the walk (keys in the arena; types in the serial decision).

### 2.4 Constructor provenance

| fact | constructed by, alone | read by |
| --- | --- | --- |
| a point's label set | the label solve, on the frontend's program | defunctionalization; knots (through the families); `labels-least` |
| firings `(dispatch, label)` | the label solve | defunctionalization (apply cases, force functions); the program graph's birth |
| the program graph | L14's builder, born from the extraction and the firings; edited by defunctionalization (force functions), dedup (merges), contify, the optimizer (made nodes, inlines, redirects) | every summary, the schedule |
| effect rows | L02's one derivation; first solve in defunctionalization; re-derived after the optimizer | `by_name`; CSE, DCE, LICM through the ops' effects; LLVM |
| `by_name` (`mode`) | defunctionalization, from the label's row | `<family>.force` |
| closure and memo families | defunctionalization's decision, serially; DP-54's narrowing (a field dropped, after knots) | every type reader; knots; counting; frames (L10) |
| coercion matches | defunctionalization's walk | — (ordinary matches after) |
| knot refusals | idr-knots, on the post-defunctionalization types, before any optimization | the driver |
| dedup classes | idr-deduplicate | its one replacement |
| spec and raise keys, node kinds | the specializer, at the grant, from binding times and the call's operands | the redirect step; the inline verdict |
| node names | the arena's digest of the key | the program's symbol table |
| binding times | one analysis per component of the run | the specializer; idr-binding-times' report (09 OPT-78) |
| inline verdicts | the inline phase, per final function | the profitability callback |
| `total` | the frontend (Idris's verdict, L16 I1's component); defunctionalization (force functions); the specializer (made nodes) | the row derivation (L02); loop formation (L10) |
| `gives_back`, tail kind | DP-38's writers (L10, L14) | idr-identity's replacement, a call folder (§4 I8); lowering |

### 2.5 The inliner's termination and its budget (argued)

Setting: the final graph G after the specialize phase. Its functions are
finitely many (held functions, and made nodes, finite by the keys'
well-quasi-order, 1.2). Each function f has a final body B(f) whose own
inline step has run, and a verdict V(f) decided once from B(f) and the
static count of call sites naming f.

1. *One pass per caller.* The inline step of a caller c takes c's calls
   once, before the first inline (today `Inline.cpp:121`); a call brought
   in by an inlined body is not taken in this step.
2. *No later step is owed.* A call inside B(f) to g was kept when f was
   finalized: V(g) was `Keep`, or the cap kept it. A verdict is per
   callee, so it is `Keep` in c too; and a capped call stays capped,
   since after inlining f into c, c's size minus one plus g's size is at
   least f's size minus one plus g's size, which exceeded the cap. So the
   whole inliner is one pass over each function's call list in
   callees-first order: O(Σ calls + Σ inlined sizes), each caller at most
   `kCallerCap` ops unless it began larger.
3. *No unrolling.* `Keep(Cycle)` holds every callee on the caller's cycle
   but a `Beta` node, whose body calls the recursion, never itself or a
   node of its own key (a chain of `Beta` nodes is finite by the keys'
   order; a node that calls itself is `Keep(Cycle)`).
4. *Leaf inlining during specialization* brings a body with no call: it
   adds no call, so it cannot feed itself.
5. *The budget*: MLton's numbers (`kLeafSize` 40, `kSmall` 60, `kProduct`
   320) and `kCallerCap` 10,000, in ops and call sites (program units,
   deterministic). A spent budget is a `Keep`: the call stays, a valid
   program; nothing in the inliner refuses (the one failure is upstream's
   `inlineCall` declining, which also leaves the call).

On upstream's `mlir::Inliner` (§4 I7) the callback answers `V(callee)`;
its `maxInliningIterations` is then a budget that point 2 shows is never
spent.

### 2.6 Consumers, errors and cleanup

- Defunctionalization's failures are internal errors only: two keys on
  one name, two dispatch functions on one name (`Declare.cpp:120-128`),
  a family a body cannot make. With `SumId`s minted by the decision, the
  `assert`s and `.at()`s go (06 D-16).
- The label solve's state is freed when defunctionalization ends: its
  answer is in the types (D18: written where it is read).
- The specializer's internal errors (digest collisions) become
  `llvm::Error` at the table's boundary (09 OPT-59); the arena is freed
  with the pass; no key outlives it.
- Deduplication fails nothing: a class whose `isRegionEquivalentTo` check
  fails is split, never merged.

### 2.7 What it deletes

- `Defunctionalize.h`: `Plan`, `SlotTypeConverter`, `SlotPattern`, the
  three `populate*` functions; `Pass.cpp`: `addTarget`, `convert`'s
  converter, target, pattern set and rollback, the `observableRuns`
  callback, the statics walk, `layout::fit`, the statistic's `TypeGraph`;
  `Patterns.cpp`: `RetypePattern`, `FuncSignaturePattern`, the `handled`
  list; `PatternsCalls.cpp` whole; `Converter.cpp` but the coercion,
  which becomes a free function over two keys (06 §7 T1, T5).
- `Labels.h`: `PointKey`, `ResultKey`, `keyOf`, `Statements`,
  `Graph::Builder`, `Solution::nodes`, `sinks`, its `SymbolTable`
  reference; `ClosureParts`; the per-wave dispatch scan and SCC copy
  (06 §7 T2, T6).
- `Analysis/Effects.cpp`'s `observableRuns`, `LabelsRun`; `Idr_ObservableIO`
  (DP-50).
- `Deduplicate/`: heights, waves, the cycle exclusion, `Reading`,
  `BodyHash`, `BodyEqual`, the 32-bit hash, the port's header and its
  `PINS.md` entry (06 §7 T4, DP-26).
- `Specialize/`: `Idr_KeyHoleAttr`, `Idr_KeyConAttr`, `Idr_SpecKeyAttr`,
  `Idr_KeyRaiseAttr` (their records in the specification); the node
  table's mutex and `const` writers; `Requester`'s tables; `Forms`'
  `unordered_map` and mutex; the 34-line ladder over key attributes;
  `canonicalHash` of printed keys; `chainOf`'s first-found lift (09 §7).
- `Optimize/`: the ready set's second walk (`ReadySet.cpp:34-74`), `enable`,
  `reaches`, `merge`'s searches, `byName`, `specialize::Schedule`,
  `RunPipeline`, the `hasActionHandler` branch, `writeCallEffects`'
  restamping, the fixed last step, statistics by name (09 §7, OPT-33).
- `Inline/`: `betaReduces`, `callsOnlyBeside`, `dispatched`, the `Sibling`
  arm, `Facts::inlines`, `factsOf`'s `shared` and self-call walk,
  `no_inline` and its read (DP-64); `FuncOp::absorb` and its two calls
  (§4 I3).
- `Identity/` whole (§4 I8).
- `OpsClosures.cpp`'s `SuspendOp::fold`; `ConOp::fold` of a memo cell's
  label state (§4 I2).
- In the pipeline: `idr-effects`, deduplication's first slot, DP-68's
  canonicalization.

### 2.8 Essential distinctions, and the seams

**Essential** (Brooks's limit): the coercion where two flow sets meet
(two sets genuinely differ); `Beta` against `Step` (a node that consumes
what its caller built against a step of a recursion on static data);
the frontend's specialization (types and implementations, an acceptance
analysis with a proof and no budget) against the optimizer's (values
after defunctionalization, an optimization that may stop): two
specializers because one decides acceptance and one never refuses, in two
languages; an unforced memo cell (an identity) against every other
construction (a value).

| seam | the declaration both sides write against | state |
| --- | --- | --- |
| L04 (families) | the family attribute: a kind (`closures`, `memo` beside Idris's kinds), per constructor a function symbol, a mode for memo labels, existential index binders, fields with quantities in their types; the memo kind's layout always a cell | unfixed: existential binders per constructor and indices from a carrier's free variables (§4 I5) |
| L13 (ops) | the capture family `closure`, `suspend`, `delay` (L13 §2): `suspend`'s construction is an identity, the other two values; after defunctionalization an unforced memo cell keeps its own construction op | mismatch with L13's "one capture family", pure (§4 I2) |
| L01 (declarations) | `con`'s typed rule: `Allocate` on `identity` for a linear or owned result **or a value of an `in_place` family**; the memo cell's construction `Allocate` on `identity` | proposed (§4 I2) |
| L02 (rows) | `by_name` reads the `io` atom; divergence from `total` and callees' rows; first solve in defunctionalization | fixed by DP-50; the atom per D29 |
| L14 (graph) | ids in program order minted by the label solve's extraction, adopted by the graph's birth; edits through `Editor`; reference edges (family labels) for dedup | fixed (L14 §2.1.4 #1) but for reference edges, which this lane needs and L14 row 8 names |
| L16 (frontend) | index variables never monomorphized (quantity 0 parameters); `Termination` with its component (L16 I1); the top-level lazy constant as its own op (09 OPT-82); a dictionary as a runtime record where no static one exists (Q1) | L16 I1 fixed in substance; OPT-82's op and Q1 open |
| L09 (control flow) | contification's algorithm and join regions; this lane fixes when it runs and that it clears no `total` | fixed by D19, D25 |
| L10 (tail) | loop formation reads `total` (V8); `gives_back` and tail kind are DP-38's | fixed |
| L07, L08 (counting, exclusivity) | grade copies use the specializer's clone-and-key template (DP-55) with a finite key; D24's obligation must survive inlining (§3, last item) | the template's shape fixed here (§2.2); the obligation's holder unfixed |
| L19 (tests) | one thread against many, byte for byte, for idr-optimize and the label solve (DP-34) | fixed by DP-34 |

## 3. QTT

**Where quantities enter, are kept, read or lost in this area.**

| quantity / fact | enters | kept by this area | read by this area | lost |
| --- | --- | --- | --- | --- |
| quantity 0 (erased values) | the frontend emits no parameter, field or argument (AGENTS.md; 15 §2.3) | a closure captures values used from outside (`Emit/Closures.idr:28-40`), so no erased capture exists; a label's capture count is its runtime inputs less its carrier's (`Defunctionalize/Keys.cpp:139-143`) | — | nothing |
| quantity 0 indices (D48) | `idr.func @f<n : nat>` | the closure family's indices and its constructors' existential binders (§4 I5); keys' index patterns (§2.2) | the coercion and dispatch match bind them at compile time only | nothing, once §4 I5 holds; today the concept does not exist |
| quantity 1 (`!idr.lin<T>`) | `Binder` → the type (`Emit/Index.idr:59`); a closure linear iff a capture is (`IdrClosureOps.td:22-26`) | keys are at no grade (`Defunctionalize.h:56-58`) and `held` re-applies the grade (`Declare.cpp:39-41`); the coercion and the dispatch match take the value at its grade (`Patterns.cpp:100-111, 189`); dedup compares types, grades included; inlining maps operands to parameters of the same types | the force folder refuses to duplicate a linear value (`OpsClosures.cpp:181-182`); `Beta` keys over closures built for one call | nothing found |
| Idris's termination | `total` (L16 I1: per component) | made nodes copy it; force functions get it | loop formation, rows | **lost** by `absorb` on every inline of a callee without it (§4 I3) |

**What quantities prove here that the design still pays for.**
1. *A dispatch of a linear closure is its last use.* The match that
   replaces the apply consumes its scrutinee on every path, so counting
   needs no liveness for it (L07's QTT focus).
2. *A closure born linear is exclusive.* A closure op with a linear
   capture has a linear result (`Idr_LinearWhenACaptureIs`), and QTT's
   scaling forbids a value built from a linear value to be bound at ω,
   so it is never shared: its dispatch's take reads no count, with no
   exclusivity solve. The label solve's sets do not record birth
   quantity (a label's closures may be born linear at one site and
   unrestricted at another), so L08's marking must see it; a label set
   of `(label, birth quantity)` pairs would make it a type fact, at the
   price of a constructor per pair. Left to L08 (its QTT focus); not
   proposed here.
3. *A linear suspension is forced at most once per path.* When it is
   also exclusive (born linear), no reader can see its cell `running`
   or `forced`, so its force needs no exchange: take the cell, run the
   label, give the cell back as a token. `Canon/Force.cpp:7-8` does this
   for a suspension whose one use is its force; the same holds for an
   exclusive one anywhere, which L07's grade copies can key (DP-55).
4. *A closure known at all its applications in one function is never
   built*, linear or not: each application's match folds on the known
   constructor (§1.1's D19 row). Linearity adds that each path applies it
   once, so tail applications make one join region, never a copy per
   path (L09).
5. *Erased index captures are absent as values and present as
   binders* (§4 I5): the label function's index parameter is supplied at
   its dispatch from the case's binder, at compile time.

**Representations that make a misuse unwritable.**
- The memo cell's construction as its own op with an identity effect:
  merging two suspensions, hoisting one, folding one into static data
  cannot be written (§4 I2).
- Index binders on the closure family: a field whose index variable is
  out of scope cannot be written (§4 I5).
- `mode` as an enum: a `by_name` flag on a closure label cannot be
  written (06 D-20).
- D24's obligation today lives in the callee's type (§5.5); inlining
  removes the call and the obligation with it, so the rebuild in the
  caller is kept in place by C1's walk (reuse recycles the dropped cell
  for the next construction that fits), not by construction. A linear
  token from the take to the rebuilding constructor, carried by every
  pass and checked after each, would make the obligation survive
  inlining by type. The holder is L08's to decide; this lane names the
  seam.

## 4. Improvements

### I1. Nothing that optimizes runs before the solve acceptance reads. *Coordinator.*
- *Evidence*: knots refuses on the types defunctionalization makes from
  the label sets (`Verify/Knots.cpp:1-21`); deduplication runs before the
  solve and merges label functions (`Pipeline.cpp:62-71`,
  `EliminateDuplicateFunctions.cpp:23-26, 202-212`); a function's
  parameters are points of the solve (`LabelSites.cpp:27-32`), so merging
  two functions unions their parameters' sets. DP-68 adds a
  canonicalization before the solve under DP-33's budget; DP-64 allows
  polyvariance there under a budget.
- *Counterexample* (*conjecture* until run; each step *read* above):
  ```idris
  import Data.IORef
  wrapA : (Int -> IO Int) -> Int -> IO Int
  wrapA g x = map (+ 1) (g x)
  wrapB : (Int -> IO Int) -> Int -> IO Int
  wrapB g x = map (+ 1) (g x)        -- the same body: merged into wrapA
  main : IO ()
  main = do
    r <- newIORef (wrapA pure)       -- r holds wrapA-closures over `pure`
    let reader = \x => do f <- readIORef r; f x
    printLn !(wrapB reader 1)        -- a wrapB-closure over `reader`
  ```
  As written: `wrapA`'s capture holds `{pure}`, `wrapB`'s `{reader}`;
  the families are `KA(g : K{pure})`, `KB(g : K{reader})`,
  `K{reader}(r : IORef KA)`: no cycle through the `IORef`. After the
  merge, `wrapA`'s capture holds `{pure, reader}`, so
  `KA → K{pure, reader} → IORef KA`: `unsupported (cycle)`. The program
  has no knot at run time; an optimization refused it.
- *Root cause*: the representation an acceptance rule reads (label
  sets) is computed after passes that coarsen or refine it; acceptance
  becomes a property of the optimizer, against AGENTS.md.
- *Correction*: the label solve runs on the frontend's program, knots
  right after defunctionalization, and every optimization after knots:
  deduplication on the first-order program (labels in families compared
  as class slots, which partition refinement does anyway); DP-68 is
  withdrawn; polyvariance is excluded, or, if ever taken, runs after an
  acceptance solve and before a second solve (refining sets only removes
  type edges, so knots needs no second run).
- *Deletes*: deduplication's first slot and its label reading before
  defunctionalization; DP-68's pass; polyvariance before the solve.
- *Discriminated by*: the program above as a test that compiles and runs
  (exit 0, its output); fails before (refused), passes after; and the
  `labels-least` property run on the frontend's module.

### I2. Construction is pure exactly where nothing reads the value's identity. *Coordinator.*
- *Evidence*: §1.1's C3 row: `ConOp::fold` and `SuspendOp::fold` make
  static memo cells today (`OpsCon.cpp:108-120`, `OpsClosures.cpp:159-165`,
  `Constants.cpp:122-127`); a static memo cell's forced value is made
  persistent (`Verify/Knots.cpp:10-14`); a constant suspension's label is
  memoized even if observed (`Pass.cpp:116-134`); a memo cell is today
  guarded only by being a box (`OpsCon.cpp:50-56`), which D48 deletes;
  `LList`'s values can be bound at ω (`Linear/List.idr:13-15`).
- *Counterexamples*:
  (a) *today* (*read*; footprint *conjecture*):
  `f : Nat -> Maybe (List Nat) -> Nat; f n m = sum (take n (fromMaybe (replicate 1000000 1) m))`.
  The default is `Delay (replicate …)` with no capture; after
  defunctionalization it is a memo constructor of no field, which the
  optimizer's canonicalize folds into one static cell: once forced, a
  million-cell list lives until exit, where the program as written frees
  it when `f` returns. D26's "never: any structure held past its last
  use" is voided through its "persistent static data" exception.
  (b) under DP-68: a trusted library's capture-free suspension that runs
  IO (by `unsafePerformIO`) folds to a constant before the decision,
  becomes a "static suspension", is memoized, and its effect happens at
  the first demand only, against AGENTS.md ("its effects happen where
  the value is demanded").
  (c) under C3 with D48: `let a = n :: []; b = n :: []` (`LList`, `n`
  read at run time), then `bump a` and `bump b` with
  `bump : (1 _ : LList Int) -> LList Int` rebuilding in place. CSE merges
  `a` and `b`; one value goes to two calls; exclusivity fails;
  `unsupported (uniqueness)` refuses a program accepted as written.
- *Root cause*: one effect declaration (pure) for constructions of three
  kinds: immutable values, a memo cell whose state is written later, and
  a value whose freshness a promise reads.
- *Correction*: the unforced memo cell keeps its own construction op
  after defunctionalization, declared `Allocate` on `identity` (never
  merged, hoisted or folded; deletable when unused); `forced` (a `delay`)
  is a pure constructor; `con` of an `in_place` family takes a fresh
  identity as a linear result does; `SuspendOp::fold` goes, and
  `ConOp::fold` never folds a memo cell's label state; the only static
  memo cell is the frontend's top-level lazy constant, its own op (09
  OPT-82, which deletes `no_inline`). Every other `con`, `closure` and
  `delay` stays pure, as C3 wants.
- *Deletes*: `SuspendOp::fold`; the memo case of `ConOp::fold`; the statics
  walk (`Pass.cpp:116-127`); `no_inline`; C3's "suspend … pure".
- *Discriminated by*: (a) a property that `f`'s module holds no static
  memo cell, and a run of `f` in a loop whose peak footprint stays flat;
  (c) the program as a test that compiles and runs.

### I3. Idris's termination is never cleared by inlining. *Coordinator* (builds on L16 I1).
- *Evidence*: §1.2's `total` row.
- *Counterexample* (*conjecture* until run):
  ```idris
  search : (Nat -> Bool) -> Nat -> Nat
  search p n = if p n then n else search p (S n)   -- no proof: total false
  count : Nat -> Nat
  count Z = 0
  count (S k) = count k + search (const True) 0      -- decreasing: total true
  ```
  The specializer makes `search` at `p = const True`; its body folds to
  `return n`, a leaf, inlined into `count`; `absorb` clears `count`'s
  `total`; loop formation gives `count`'s loop a may-loop op; `count`'s
  row now carries divergence, so an unused call of it is no longer
  deleted (D13) and its loop loses `mustprogress`.
- *Root cause*: a fact about cycles held per body and recomputed by
  inlining, which never adds a cycle through the caller: a cycle through
  c after inlining g into c ran through g before, and c's proof covered
  it; inside a component (contification, `Beta`), every loop through c
  was a loop through c before.
- *Correction*: `absorb` goes; nobody clears `total`. A made node's
  `total` is its origin's, or true when its final component has no
  cycle (a specialization that removed the recursion removed its loop).
  With L16 I1, a component's divergence is decided over the members'
  Idris components, and an acyclic component carries none of its own.
- *Deletes*: `FuncOp::absorb`, its calls in `Inline.cpp` and
  `Contify.cpp`.
- *Discriminated by*: idr-expect's `proved` property (`Expect/Proved.cpp`)
  on `count` at the pipeline's end: fails before, holds after; a sibling
  where the inlined callee closes a cycle through `count` keeps the
  divergence.

### I4. A runtime choice among a fixed set of implementations is a closed sum. *Owner* (Q1).
- *Evidence*: §1.1's megamorphic row: seven tests refuse sets of one or
  two implementations.
- *Counterexample*: `tests/runtime-closure-implementation`: `op @{choose k} 6 7`
  where `choose` returns `plus` or `times` of `Semi Int`, refused under
  `runtime closure`. Its sibling comment says "a choice among a fixed set
  of functions is a tag" (`tests/runtime-closure-growing-choice/Main.idr`),
  which is accepted.
- *Root cause*: the frontend holds an implementation only as a
  compile-time value; where it cannot fix one, it refuses instead of
  passing the dictionary as the record it is.
- *Correction*: where no static implementation exists, the dictionary is
  a runtime value of the interface's record family at the instance's
  type, its methods closures; the label solve bounds each method field's
  set (an anchor per field), and defunctionalization dispatches. Refused
  stays only what AGENTS.md's definition names: an implementation whose
  type or whose methods' instantiation a runtime value chooses from a set
  no analysis bounds, and growth.
- *Deletes*: the refusals of the seven tests (their `near/` stays as the
  static form); 0003's owed "split each rule until its category is
  true" for these rules.
- *Discriminated by*: the seven programs compile and run with their
  `near/` outputs; a test whose method is polymorphic at a runtime-chosen
  instantiation stays refused, naming the site and the method.

### I5. Closure and memo families bind the indices their captures mention. *Coordinator* (seam L04).
- *Evidence*: D48 (`idr.func @map<n : nat>`); keys are `(carrier, labels)`
  and a family's fields are its labels' capture slot types
  (`Declare.cpp:172-197`).
- *Counterexample*: in `@lengths<n>`, `\y => length xs + y` with
  `xs : #Vect[n]`, returned as `Int -> Nat` and applied in `main`. The
  family's field `xs : #Vect[n]` names an `n` no binder in `main` holds;
  and two calls `@lengths<3>` and `@lengths<k>` would either share an
  ill-scoped family or need one family per index value, which the frontend
  never monomorphizes (and must not: index recursion would grow without
  bound, a growth refusal of a program Idris types).
- *Root cause*: indices become type-level variables (D48) but a pass that
  declares families from flow sets has no binder for them.
- *Correction*: a closure or memo family takes as indices the free index
  variables of its key's carrier (in first-occurrence order), applied at
  each use to the use's terms; each constructor binds, with no equation,
  its label's index parameters the carrier does not fix; the dispatch's
  case passes them to the label (`idr.call @lbl<m>`), compile time only.
  The memo kind's layout is a cell by its kind.
- *Deletes*: nothing of today (the concept is new); it prevents a
  per-index-value family, which would be a second monomorphization.
- *Discriminated by*: the family verifier refuses a field whose index
  variable no binder holds; the program above compiles to one family.

### I6. Keys lift against the set of their peers; index patterns; one clone-and-key template. *Coordinator.*
- *Evidence*: §1.2's OPT-48 row; D48's "impossible arms vanish under
  specialization"; DP-55 (grade copies "by the optimizer's own
  clone-and-key template").
- *Counterexample*: a node made in one wave by two requesters, whose
  chains hold `k1 = f[A 1 2]` and `k2 = f[A 3 4]` (one shape: constructor
  `A` over two scalars). The node then requests `f[A 1 4]`. Lifted
  against `k1` first, it becomes `f[A 1 _]`, which is no longer of `k2`'s
  shape (a hole is not a scalar, `Order.cpp:58-77`), so the loop stops at
  `f[A 1 _]`; against `k2` first, it stops at `f[A _ 4]`. Which one is
  first is the order the two workers took the lock
  (`Requests.cpp:153-155`): the node, and its name, follow the schedule.
- *Root cause*: a set (the chain) represented as a list in arrival order,
  and the lift defined against one element.
- *Correction*: the lift is anti-unification of the request with every
  same-shape key of `earlier` at once (a position becomes a hole if it
  differs from any): commutative and associative, so the order cannot
  reach the node (above: `f[A _ _]` either way); termination as before
  (each lift adds a hole). Keys
  gain index patterns, compared and lifted as scalars. The template is
  generic over a key alphabet with an order and a lift; grade copies
  instantiate it with a finite alphabet (equality, no lift). The
  specializer may also stop at a budget in program units (made ops per
  origin against the origin's size), pessimistic, deterministic, so the
  well-quasi-order's unbounded worst case never reaches compile time.
- *Deletes*: `chainOf`'s order dependence, the node table's mutex (DP-65),
  counting's own cloning code (DP-55).
- *Discriminated by*: DP-34's test (one thread against many, byte for
  byte) on a fixture built to hold two same-shape chain keys.

### I7. MLton's order, with leaves interleaved and upstream's inliner first. *Coordinator.*
- *Evidence*: DP-64; 09 Q-opt-1 (keys inlining exposes); upstream's
  `Inliner` takes a profitability callback and a simplification pipeline
  (`mlir/include/mlir/Transforms/Inliner.h:125-155`) and runs parallel
  only inside one component (§5.1 E1); AGENTS.md: upstream, then
  upstream patched, then ours.
- *Counterexample* (to DP-64 as drafted): `h y = k (wrap y)` with
  `wrap y = Just y`; `k` specializes on `Just _`. Specializing to
  completion before inlining sees `call @wrap(y)` at `k`'s call, not a
  constructor, and makes no key.
- *Root cause*: separating the phases hides constructors behind calls that
  cost nothing to remove.
- *Correction*: leaf inlining (no call, at most 40 ops) runs inside the
  specialize phase (it cannot unroll, needs no count); the weighed rule
  runs once after, with true counts, `Beta` weighed (DP-64's correction
  in 1.1). The weighed phase runs on upstream's `mlir::Inliner` with the
  verdict as callback, measured at stage 1; if its serial walk over
  components is the wall, a patch upstream runs independent components
  in parallel (`upstream/<id>/llvm-project.patch`); our own scheduler
  for inlining only if that fails. The specialize phase keeps our
  dynamic schedule (made nodes, parked requesters), which upstream has no
  mechanism for (D2).
- *Deletes*: `inlineCalls`, `inlineStep`, the inline step outside a pass
  (OPT-14's contract), the five rules (DP-64).
- *Discriminated by*: the counterexample as a fixture whose `k` call is
  specialized (a property on the redirect, or the absence of the match on
  `Just` after the pipeline); stage-1 time of the inline phase on
  upstream's inliner, recorded.

### I8. idr-identity becomes a folder of `idr.call`. *Coordinator.*
- *Evidence*: §1.1's D10 residue (`Identity.cpp:79-81`); DP-38 makes
  "gives back argument i" a fact the call carries, checked against its
  callee in `verifySymbolUses`.
- *Counterexample*: none of behaviour; the cost is a pattern set frozen
  per member per round.
- *Root cause*: a fact of the callee read by a pass through the ready
  set, because the call did not carry it.
- *Correction*: `CallOp::fold` returns the argument the call's fact names;
  the canonicalize already in the pipeline applies it.
- *Deletes*: `Transforms/Identity/` and its inner pass record.
- *Discriminated by*: the existing gives-back fixtures pass unchanged.

## 5. Work units (draft; none dispatched)

| unit | exclusive write set | outcome | deletes | must not | acceptance |
| --- | --- | --- | --- | --- | --- |
| U1 order | the pipeline's one list (the specification's stage module, C7's `compiler/spec/`, named by L03); `idr/lib/Transforms/Pipeline.cpp` until then | label solve and knots before every optimization (§4 I1) | dedup's first slot; DP-68's pass | add a pass before defunctionalization | §4 I1's program runs; every test's verdict unchanged otherwise |
| U2 label solve | `idr/include/idr/Analysis/Labels.h`, `idr/lib/Analysis/Labels.cpp`, `LabelSites.cpp`, `idr/lib/Transforms/Expect/LabelsLeast.cpp` | extraction per function into arrays, ids in program order, difference propagation, answer by point id, firings | §2.7's label-solve list | hold a `Value`- or name-keyed map in its state; mint ids after the graph exists | `labels-least` holds on every fixture; `defunc-tag-limit` within its limit; one thread against many byte for byte |
| U3 defunctionalization | `idr/include/idr/Transforms/Defunctionalize.h`, `idr/lib/Transforms/Defunctionalize/` | the decision (graph birth, first rows, `by_name`, keys, families) and the parallel walk (§2.1 step 3) | §2.7's defunctionalization list | build a pattern set; make a type or attribute on a worker; fold a suspension | the 22 `defunc-*` and 16 `effects-*` fixtures' behaviour; `by_name` unmoved (`effects-memo-label`, `defunc-memo-by-name`) |
| U4 families | with L04's grammar: the family declarations this pass writes (in U3's files) | closure and memo families with index binders, `mode`, the memo view (§2.2, §4 I5) | role `Label`'s `byName` bool; the force dispatch's catch-all | add a box | the family verifier refuses an unbound index; §4 I5's program compiles |
| U5 identity of a memo cell | `idr/lib/IR/OpsClosures.cpp`, `OpsCon.cpp` (folders); declarations through L01's specification | §4 I2 | `SuspendOp::fold`, the memo case of `ConOp::fold`, the statics walk | change any other construction's purity | §4 I2's (a) and (c) tests |
| U6 dedup | `idr/include/idr/Transforms/Deduplicate.h`, `idr/lib/Transforms/Deduplicate/`, `upstream/<id>/` (the `OperationEquivalence` hook: report, reproducer, patch, `tests/upstream-<id>`, `PINS.md` entry) | partition refinement after knots | §2.7's dedup list | run before knots; make an attribute per op | duplicates in cycles merged on a fixture; a second run finds nothing; byte-identical at any thread count |
| U7 keys | `idr/include/idr/Transforms/{Specialize,SpecializeState}.h`, `idr/lib/Transforms/Specialize/`, the key attributes' records in the specification | arena keys, index patterns, the lift over sets, digests of bytes, the clone-and-key template | §2.7's specialize list | take a lock while judging; create a context attribute on a worker | DP-34's test; node names equal across runs and thread counts |
| U8 schedule | `idr/include/idr/Transforms/{Optimize,OptimizeScheduler}.h`, `idr/lib/Transforms/Optimize/{Optimize,ReadySet,Component,Waves}.cpp` | the specialize phase on the program graph: counts, phase sum, node kinds, leaf inlining as an inner pass | §2.7's optimize list | rescan components per wave; look a function up by name | the optimizer's fixtures' behaviour; no regression in ed9b2a0b's compile-time table |
| U9 inline phase | `idr/include/idr/Transforms/Inline.h`, `idr/lib/Transforms/Inline/Inline.cpp`, `idr/include/idr/Analysis/Inline.h`, `idr/lib/Analysis/Inline.cpp` | the verdict sum and upstream's `Inliner` with it (§4 I7); measured first | §2.7's inline list, `absorb` (§4 I3) | inline a member of the caller's cycle but a `Beta` node; clear `total` | §4 I3's `proved` property; §4 I7's fixture; stage-1 inline-phase time recorded |
| U10 identity | `idr/lib/Transforms/Identity/` (deleted), `idr/lib/IR/Func/Call.cpp` (the folder) | §4 I8 | idr-identity | read the callee | gives-back fixtures unchanged |
| U11 megamorphic boundary (gated on Q1) | L16's files (`compiler/src/IdrisMLIR/Frontend/Translate/{Instances,Terms,Dictionaries}.idr`); the seven tests' expected files | a dictionary as a runtime record where no static one exists | the seven refusals | change a growth refusal | the seven programs run with their `near/` outputs |

## 6. Owner questions

**Q1. Is a runtime choice among implementations the program fixes
megamorphic?** AGENTS.md defines megamorphic as a construct "whose set at
a site no compile-time analysis bounds", and gives as an example "an
implementation chosen by a runtime value". Seven tests refuse choices
among one or two implementations of one instance type (§1.1).
- *(a) Compile them*: the dictionary becomes a runtime record of
  closures where no static one exists, and defunctionalization dispatches.
  Costs: frontend work (L16's dictionary path), a dispatch at run time
  where the static form had none, seven expected files changed. Buys:
  AGENTS.md's definition holds as written; programs that pick a
  `Semigroup`, an `Ord` or a `Show` by input compile, as their `near/`
  forms do; the refusal list shrinks to what is truly unbounded.
- *(b) Keep refusing*: AGENTS.md's example binds; the definition is
  narrowed to say so. Costs: users rewrite such programs into the
  static form; the category stays false of these sites until each rule
  is split (0003). Buys: no new runtime form for dictionaries.
- *Recommendation*: (a). The set is a closed sum, which is what the
  compiler exists to compile away (AGENTS.md: "specialization, closed
  sums and defunctionalization").

**Q2. What the knot rule promises about closures.** The rule refuses
"an array whose element type can reach the array again", and a closure's
reach is its captures, known only through the label solve. So which
programs it refuses depends on the solve's precision: per-type anchors
(every array of one element type shares one set), one sink per operand
(DP-49), no polyvariance.
- *(a) Stated over the label solve's least solution on the program as
  written*, its precision as today, part of the rule; a change of
  precision is a change of the language, in a commit that says so, with
  a test at the boundary. Costs: a few programs with no run-time knot are
  refused (two arrays of one element type, one holding closures that
  capture the other). Buys: a rule users and tests can state; acceptance
  no optimization moves (§4 I1).
- *(b) A coarser rule, without the solve*: a closure type reaches every
  capture of every lambda of that carrier. Costs: refuses more. Buys:
  the rule is readable from the source's types.
- *(c) Sharper now* (anchors per allocation site). Costs: compile time
  and a larger solver state. Buys: fewer false refusals.
- *Recommendation*: (a), with (c) left for a later change that says so.

HEAD at finish: `e96bb991`.
