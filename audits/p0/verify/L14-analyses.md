<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L14: analyses, the solver layer, the program graph, threading

Lane L14 of the P0 verification swarm. HEAD at start: `e96bb991`
(2026-10-21T21:31Z, `git rev-parse --short HEAD`); at finish: see the end.
Grounds as proposals/README.md: *read* (path:line at HEAD), *measured*
(the command is given), *recalled*, *conjecture*, *decision* (a ruling Dn
or a coordinator decision Cn / DP-nn). Paths under `foreign/idr/` are
written from `lib/` or `include/`; upstream paths are relative to
`.toolchain/llvm-project/` at `7208ba24`.

Read for this file, in full: the representation-first skill, AGENTS.md,
the proposal; synthesis B; lane 05; §5.1. In the parts that bear on this
lane: lanes 06 (§2-§6), 09 (§2-§5), 13 (§2-§6), 21 (§3-§5); §5.3 (B7, B8,
D1-D4, M4-M9, S0-S4, I1-I8, Q-llvm-*); synthesis G (DP-22 to DP-54);
proposals 0015 (whole), 0008 (§3.2, D13), 0011 (§4.7, §4.8). Code, in
full: `lib/Analysis/{CallCycles,Recursion,Effects,Ranges,Constants}.cpp`
and their headers, `lib/Transforms/Optimize/*.cpp`, `lib/Transforms/Pipeline.cpp`,
`lib/Support/Scc.cpp`, `include/idr/Support/{Scc,Worklist,Actions}.h`,
`lib/Transforms/Effects/Effects.cpp`; in part: `BindingTimes.cpp`,
`Ownership/Borrows.cpp`, `Stack/Stack.cpp`, `Tail/Frames.cpp`,
`Tail/Returned.cpp`, `Conversion/TailCallPlan.cpp`, `IR/Func/Call.cpp`,
`IR/Verify/{Program,Linearity}.cpp`, `IR/Canon/MatchPatterns.cpp`,
`unittests/Cycles.cpp`. Upstream: `mlir/include/mlir/Analysis/DataFlowFramework.h`,
`mlir/include/mlir/Analysis/CallGraph.h`, `mlir/lib/Analysis/CallGraph.cpp`,
`llvm/include/llvm/ADT/{SCCIterator,PostOrderIterator,GraphTraits}.h`,
`mlir/include/mlir/Pass/AnalysisManager.h`, `mlir/lib/Pass/Pass.cpp`,
`llvm/lib/IR/PassManager.cpp`, `llvm/include/llvm/Support/ThreadPool.h`.

---

## 1. Verification

Classification per observation: **defect** (a defect confirmed in the
source), **incomplete** (structural incompleteness), **mismatch** (an
integration mismatch), **unverified** (behaviour not checked), **simpler**
(an optional simplification).

### 1.1 The rulings

| claim | verdict | evidence | class |
| --- | --- | --- | --- |
| **D2.** Our own solvers where upstream cannot do the job, refactored into code of their own whose composition and threading are clear. | **holds with a correction** | Today each honest solver has its own graph type, worklist and numbering (lane 05 §2.6; 21 P-14: three graph types in twelve hours with no shared code). The proposal's answer, shared types and no one engine (§5.4, §9; DP-53), fits the misfits *read* in the code: the optimizer grows its graph and merges components mid-solve (`Waves.cpp:150-176, 259-275`), the label solve's graph grows with firings (06 §3.2), Identities is a greatest fixpoint (`Identities.cpp:92-120` per 05). Correction: "composition explicit" is so far prose. Composition is explicit only when a solver's inputs are part of its type: each analysis declares the frozen answers it reads as a type list, and its invalidation follows from that list (§4 I11). Today invalidation is hand-written per analysis and can drift (`CallCycles.cpp:48-50`, `Recursion.cpp:46-48`). | incomplete |
| **D10** as it bears on analyses: no static fact recomputed, re-derived or looked up. | **holds as a target; today violated** | *Read* at HEAD: the call graph and its cycles are rebuilt by each of nine readers, and no pass preserves them by name (*measured*: `grep -rn 'markAnalysesPreserved<.*\(CallCycles\|CallGraph\|Recursion\)' lib` finds 0). Self calls are found again by re-walking bodies (`Recursion.cpp:33-36`, `Waves.cpp:228-234`, `Inline.cpp:25-28`). Tail position is recomputed at every visit (`Borrows.cpp:236-237`, `Stack.cpp:233`, `Recursion.cpp:35`). Callees are looked up by name per call per visit (`BindingTimes.cpp:143-151`, `Borrows.cpp:234`, `Effects.cpp:27`). The correction is in §2.1: the program graph is an *index* of the call ops, built once per stage and kept. It is not a second source of the calls, so building it once is not a re-derivation. One hash resolution of each callee symbol per build is the single lookup MLIR's name-based symbol references force (D7's listed exception). | defect (today) |
| **D22.** A function's summary covers every state a caller orders with, derived from its ops, never by hand, checked per function; §5.1 adds "written once over the call graph's SCCs, verified per function after every pass (a row equals its derivation, a call's row its callee's)". | **holds with a correction** | Shape: a summary over the SCCs, callees first, with one derivation as the transfer (lane 05 T5.3). Today: three bits over `CallCycles` (`Effects.cpp:36-47`). The verifier checks *cover*, not equality: a call's bits contain its callee's (`Call.cpp:52-57`), and a function's bits cover its body (`Verify/Program.cpp:53-71`, "a solve says too much of a function, never too little"). §5.1's **equality after every pass is not satisfiable across upstream's canonicalizer**: a match whose taken region is known is replaced by that region (`IR/Canon/MatchPatterns.cpp:1-5`), which deletes crash and IO ops of the other cases. The function's derivation then shrinks with no hook to rewrite its row, its callers' rows or its calls' rows before the verifier runs (`Pass.cpp:618-642`). Correction (§4 I2): cover after every pass, which is today's check. A row equals its derivation right after each re-derivation, an incremental upward re-solve over the program graph's caller rows, scheduled where precision pays (when the optimizer finishes a component, before lowering). The first solve is defunctionalization's (DP-50): over calls and label runs, which is the converted program's call graph, built from the decision without a walk (§2.1.4). | mismatch |
| **D39.** Lifetime parameters in signatures, "inferred bottom-up over the call graph's SCCs as the effect rows are". | **holds with a correction** | It is a callees-first summary (shape S), as Tofte and Talpin's region inference is (*recalled*: a region-polymorphic scheme per SCC, iterated within a recursive SCC). Corrections: (1) its answer *is* the function's type (quantity-0 lifetime parameters, D48: `idr.func @map<n : nat, ρ : lifetime>`), so it needs no summary table across passes: it is computed once, written into the signature, and checked lexically per function (D39: "local and linear given the signatures"). (2) Inside a recursive SCC the iteration ends because each member's outlives relation over its own signature's lifetime parameters only grows and is bounded by that signature (finite per instance; no compile-time height, the case `Worklist.h:15-23` already describes). (3) It is no refusal analysis: counting is the fallback (D39), so a budget is allowed but none is needed. (4) A caller picks its callee's lifetime instantiation while it is itself being inferred: one bottom-up pass, no callers-first step. L05 owns the transfer. | incomplete |
| **D44.** P0 absorbs 0011 whole, with 0010's A0 and 0015's R1 and R2 (the relational core, in plain Idris, both hosts). | **holds** | The seam is drawn by two decisions already written. 0008 D13: "Whole-program facts are computed on the side that owns them: the frontend's in Idris, the dialect's in C++. 0015 serves the Idris side only" (`proposals/0008-...md:453-455`, *read*). 0015 D6: "Every consumer is Idris. The C++ side's fixpoints are C++ over MLIR's machinery" (`proposals/0015-relational-core.md:243-245`). 0015 §3 lists as non-consumers "every C++ fixpoint, and the C++ optimizer" and the multiplicity check (`:138-144`). D44 moves R1 and R2 into P0 without changing that boundary. §2.7 states which solves sit on which side, what crosses Emit, and the rule for a new solve. | — |

### 1.2 §5.4, bullet by bullet

| claim (§5.4) | verdict | evidence | class |
| --- | --- | --- | --- |
| Upstream's framework, its storage patched upstream and measured first, used where a fact is per value inside one function (idr-constants, the per-loop copy; Ranges and Returned per function unless a carried fact deletes them). | **holds with a correction** | idr-constants is already per function, interprocedural off, with summaries through `visitExternalCall` (`Transforms/Effects/Constants.cpp:186-191`, `Analysis/Constants.cpp:37-43`), and it ran on stage 1 (05 §3.1). Corrections: (1) **Returned is not "per function"**. D10 deletes it: the optimizer solves the fact (Identities), drops it, and Returned solves it again on lowered code (`Tail/Returned.cpp:152-191` against `Component.cpp:238-239`). The carried fact replaces it (DP-38), and its residue is a map, not a solve (§4 I13). (2) Ranges per function loses the interprocedural argument precision it has today (`Ranges.cpp:67`, interprocedural) unless a callers-first argument summary feeds it (05 T5.7). DP-51 states this; §5.4 does not. (3) "Measured first" binds Borrows too. AGENTS.md: "upstream is not dropped for ours with the middle step skipped". Borrows sits on the framework today (`Borrows.cpp:299-304`) and leaves it for a marking (C1, DP-53), so the patched framework's numbers on it are owed before it leaves (§2.6 M3a). | incomplete |
| One maintained program graph: dense function ids minted by the graph, callers and callees as compressed rows, SCCs as id ranges, an analysis the passes preserve and edit in place. | **holds with corrections** | (1) **Preservation cannot survive a nested group at the pin.** An adaptor's pass state preserves nothing, so after every `idr.func(...)` group the parent's analyses are invalidated (`Pass.cpp:618-619`; `NestedAnalysisMap::invalidate` clears every child map when nothing is preserved, `:1172-1186`). The adaptor never intersects its nested passes' preserved sets, as LLVM's adaptor does (`llvm/lib/IR/PassManager.cpp:137-169`, `PA.intersect`). So every apply group would rebuild the graph (§4 I1). (2) "SCCs as id ranges" renumbers ids by SCC, which clashes with ids stable under edits. Correction: ids stay fixed for the analysis's life, and SCCs are ranges of one permutation (§2.1). (3) "Compressed rows edited in place": a packed CSR cannot be edited in place in O(edit). Correction: a frozen form (the analysis, read-only) and an editable form held by the restructuring pass that thaws and freezes it (§4 I7). (4) The lowered-module instance DP-52 names has no client left (§4 I6). | mismatch (1); incomplete (2-4) |
| It deletes `CallCycles`, `Recursion`, the caller-only symbol maps and the optimizer's second walk; the optimizer is its one dynamic client. | **holds** | Nine `CallCycles` readers, one `Recursion` reader (*measured*, §1.4). Seven `SymbolUserMap` constructions (*measured*). The second walk is `ReadySet.cpp:34-42`. The dynamic part is essential: made nodes are inserted (`Waves.cpp:259-275`) and components merge when waits close a cycle (`Waves.cpp:181-192`). The merged components are a coarsening of the call SCCs by *wait* edges, which are requests and not calls. So the merge belongs to the optimizer's overlay (an `IntEqClasses` over SCC ids, 09 T1), not to the program graph's partition. | — |
| Three solve shapes: per function; summaries over the SCCs, callees first and callers first; extract, solve, write back. | **holds with a correction** | Every analysis of today fits a shape, a carried fact or a deletion (§2.3's table). Correction: the first filter is §5.3's S0, "could the dialect carry this answer so no pass solves for it?". Tail position (D30), "gives back argument i" (DP-38), lifetimes (D39), borrow conventions and exclusive grades (written into signatures), label sets (written into types) and effect rows (on ops) are each *produced* by a solve and *carried* afterwards. §5.4 should name "carried" as the state after every solve, so that no later pass treats a solve's output as something to solve again. | incomplete |
| The solver layer as shared types, not one engine. | **holds** | B §3.2's misfits are *read* above (D2 row). | — |
| Threading: decide, apply, restructure; whole-program facts computed once, read by nested function passes the pass manager runs in parallel; every solve unit an MLIR action. | **holds with corrections; one part refuted** | (1) It needs §4 I1's patch, or every apply group drops the decision's siblings. (2) `getCachedParentAnalysis` returns a mutable reference to an analysis that "may not exist and if it does it may be out-of-date" (`AnalysisManager.h:299-311`). The apply step must read a const view, and the decide step must be paired with it in the pipeline's record (§2.5). (3) Per-function analyses are cleared after every nested pipeline run ("Clear out any computed operation analyses", `Pass.cpp:673-678`). So a per-function cached numbering (DP-53; 06 T2) lives at most one group, and a per-function fact that crosses groups must sit in the IR. (4) **"Every solve unit an MLIR action" is refuted for soundness-critical units.** An action's handler decides whether the unit runs (`support::perform`, `Actions.h:51-62`), and idris-mlir-opt installs a debug counter that skips by tag (`Actions.h:4-9`). A skipped unit of a marking whose start is the optimistic bottom (exclusive, borrowed) leaves an unsound answer. A skipped unit of a refusal analysis moves acceptance. Correction: transform units are actions; solve units are trace zones, never skippable (§4 I3). | refuted (4); mismatch (1-3) |

### 1.3 The coordinator's decisions in this lane (synthesis G, being folded in)

| decision | verdict | evidence | class |
| --- | --- | --- | --- |
| DP-30: a maintained call graph RFC, recorded; no dataflow-scope RFC. | holds | 05 §6 Q-E5: no solve of ours wants a per-SCC framework scope. Add the adaptor intersection (§4 I1) to the recorded upstream work, as a carried patch. | incomplete |
| DP-33: no budget in a refusal analysis, named exactly. | holds with a correction | The list is right. Add: a refusal analysis's units are never skippable by an action handler (§4 I3), since a skip acts as a budget of zero. | incomplete |
| DP-34: byte-identical output at any thread count, tested per solver. | holds | Shape S wavefronts write disjoint slots and read only finished slots; markings and union-find are serial; least and greatest fixpoints of monotone transfers are unique (§2.5). | — |
| DP-36: summaries in the IR, a cached analysis holds only what one pass reads. | holds, and is forced | `Pass.cpp:673-678` clears per-function analyses after each nested run, so nothing else could hold. | — |
| DP-38: `idr.func`/`idr.call` carry the effect summary and three facts (tail position, the callee's conventions, "gives back argument i"), checked against the callee in `verifySymbolUses`. | holds with a correction | The call's copy of its callee's *row* is forced: an op's `getEffects` must answer from the op alone (`Call.cpp:61-72`), and D20 rules it. Tail kind is the call's own fact. "The callee's conventions" are the call's operand types, already checked equal to the callee's (`Call.cpp:34-43`). But "gives back argument i" on each call is a second copy of a function fact, kept in step by a verifier, which AGENTS.md calls "still a copy". No MLIR interface needs it op-locally. A parallel step that needs a callee's fact reads the decide step's table (§2.5). Correction: held once, on the function (§4 I12). | incomplete |
| DP-50: idr-effects folded into defunctionalization's decision, one summary over calls and label runs, deciding `by_name`. | holds | The conversion makes exactly the calls its decision implies: each apply becomes one call per label, each force a call of its sum's dispatch function (06 §2.4, `Patterns.cpp:92-205`). So the summary graph *is* the converted program's call graph, and the program graph is born there with no walk (§2.1.4). This deletes `observableRuns` and its private graph (`Effects.cpp:49-95`). | — |
| DP-51: patch first (P1), measure Ranges, Borrows, Returned; keep the framework only per function; no P2. | holds with a correction | Returned needs no measurement: it is deleted as a re-derivation (D10), not replaced by a solver of ours. The measurements owed are §2.6's M3a-M3e, with the census at each solve. | incomplete |
| DP-52: `ProgramGraph` on `idr.program` and on the lowered module; three shapes on one static schedule (`scc_iterator`); the optimizer the one dynamic client; giant SCC serial first. | holds with corrections | (1) The lowered-module instance has no client (§4 I6). (2) `scc_iterator` keys its visit numbers by a `DenseMap<NodeRef, unsigned>` (`SCCIterator.h:73-75`) and ignores `GraphTraits::getNumber`, which `po_iterator` uses when present (`PostOrderIterator.h:30-53`). It walks from one entry node only (`:96-107`), hence today's synthetic root vertex (`Scc.cpp:34-43`). Correction: §4 I5. (3) "Preserved by name by the rest" needs §4 I1. | mismatch |
| DP-53: shared types; three generic algorithms; one instantiation each; a function's numbering one cached analysis, invalidated by change. | holds with a correction | The numbering can be cached only within one pass or one nested pipeline (`Pass.cpp:673-678`). It is rebuilt per group, which is honest: an index of IR the group may have changed. Block ids are MLIR's per region (`Block.h:65-67`, `Region.h:80-86`), so a function-wide index of blocks is (region, id) plus an offset. | incomplete |
| DP-54: `remove-dead-values` stays out; patches 06, 28, 63 retired now. | **refuted in its "retired now"** | AGENTS.md names this exact drop as a "never": "remove-dead-values adopted ... and dropped, four patches later, on a run stopped by hand at 52 GB (16005000)". It also says "upstream is not dropped for ours with the middle step skipped". DP-24 (patch before dropping) and the proposal's own S3 ("`remove-dead-values` per function, or its patches retired") agree. Its per-function half was never measured on a patched framework (21 P-9; 20 H1). Correction: §4 I4. | defect (in the decision) |

### 1.4 The deletions this lane must verify

| deletion | exists at HEAD | readers | replacement covers every reader? |
| --- | --- | --- | --- |
| `CallCycles` (`include/idr/Analysis/CallCycles.h`, `lib/Analysis/CallCycles.cpp`) | yes (*read*) | *measured* (`grep -rn -E 'CallCycles' lib include unittests`): `Transforms/Effects/Effects.cpp:31`, `Contify.cpp:128`, `Optimize.cpp:85` (via `ReadySet.cpp:27`), `Specialize/Report.cpp:29`, `Tail/Frames.cpp:349`, `Stack/Stack.cpp:289`, `Ownership/Borrows.cpp:299`, `Conversion/TailCalls.cpp:139` (via `TailCallPlan.cpp:69,123`), `Recursion.cpp:17`; test `unittests/Cycles.cpp:142,212` | yes: SCC order, `together` (same SCC), `callsItself` (self edge) are §2.1's queries. TailCallPlan's cycle condition is deleted by D30 and needs nothing. `unittests/Cycles.cpp`'s property (against reachability over every 3-function graph) is retargeted to the new type in the same change. |
| `Recursion` (`include/idr/Analysis/Recursion.h`, `lib/Analysis/Recursion.cpp`) | yes | one: `Stack.cpp:288, 310` (the recursive frame budget); test `Cycles.cpp:143` | yes: `onCycle(id)` plus each edge's tail kind. Under D32 a function on a cycle keeps one native frame (its recursion's depth moves to the typed frame stacks), so the reader's reason changes too (L10, L07). |
| the caller-only symbol maps | yes: 7 (*measured*: `grep -rn 'SymbolUserMap [a-z]*(' lib`): `Analysis/Effects.cpp:39`, `Contify.cpp:89`, `Contracts.cpp:200, 244`, `Tail/Returned.cpp:163`, `Expect/Continuations.cpp:26`, `TailCallPlan.cpp:77` | themselves | yes: callers and call counts from the graph. Effects' goes with DP-50, Returned's with Returned, TailCallPlan's with D30 (its "internal" set is the private functions the lowering marks, §4 I6). Contracts' and Continuations' (test instrumentation, L19) use the graph builder. |
| name-keyed function maps | yes; "nine" is loose. *Measured* (`grep -rn 'DenseMap<\(mlir::\)\?StringAttr' lib include`), maps from a function's name to membership, number, callers or plan: `BindingTimes.cpp:47`, `Identities.h:55, 58`, `Identities.cpp:86`, `ReadySet.cpp:39`, `Optimize.h:242`, `Tail.h:135` (frames' `Members`), `Tail.h:306` (Returned's), `TailCallPlan.cpp:28`, `TailCallPlan.h:72`, `ExclusivityDetail.h:61`, `Demand.cpp:104`: twelve. Pointer-keyed ones of the same class: `Effects.cpp:52` (`positions`), `CallCycles.h:56-58`, `ReadySet.cpp:47` (`sccOf`), `Stack.cpp:261-266` | their files | yes for all but three that belong to other lanes' redesigns: `ExclusivityDetail.h:61` (L08), `Demand.cpp:104` (D24 moves the promise into the function type, L08), `Tail.h:306` (with Returned). The proposal's "nine name-keyed maps" should read "every function membership, number or callers map, by name or by pointer" (the list above). |
| `Scc.cpp`'s graph copies | yes: per call, the caller's adjacency, the `Vertex` copy with one `SmallVector` each plus a root vertex, and the output (`Scc.cpp:37-51`); `stronglyConnected`'s `DenseMap` numbering and by-value successor lists (`Scc.h:31-52`) | ten users (05 SC3; *measured* there) | yes, once each user builds one `Csr` (§2.2) and `components` runs over it with no copy (§4 I5). |
| Returned's whole-module solve | yes: `Tail/Returned.cpp:152-191`; its result dropped in release (`:158-159`, the `[[maybe_unused]]` AGENTS.md names, 10 R-2) | `ReturnedArguments.cpp:108` | yes once DP-38's fact reaches lowering, mapped per result field path (§4 I13, seam with L10). |
| each solver's private graph and numbering | yes: Labels' union-find classes and per-wave map (`Labels.h:260-270`, `Labels.cpp:216-261`); exclusivity's items, `dependents`, `liveOf`, `sharing` (`ExclusivityDetail.h:150-156`, `ExclusivityAnalyses.cpp:310-317`); the stack inference's `index`, `ids`, `byNode`, `out`, `in` (`Stack.cpp:261-268`); Identities' `Record` map (`IdentitiesRecord.cpp:97`); BindingTimes' `std::map` of tuples (`BindingTimes.cpp:110`); `observableRuns`' positions and runners (`Effects.cpp:52-82`); the ready set's; dedup's (`EliminateDuplicateFunctions.cpp:92`); the owned verifier's `Numbering` (`Verify/Linearity.cpp:42-66`) | their passes | yes, by §2.2's `Id`/`IndexVector`/`Csr` and §2.3's shape templates. The clients' internals belong to their lanes (L07, L08, L18). |

New, in passing (*read*): `Ownership/Borrows.cpp:303-304` repeats the
pattern AGENTS.md cites for Returned. The solve's `LogicalResult` is
`[[maybe_unused]]` behind an `assert`, so release drops it. Its `own`
recurses along a definition chain (`:272-288`, the call at `:287`), which
D33 rules out for our C++. Both go with Borrows' cutover to a marking
(L08). **defect**.

---

## 2. Boundaries

### 2.1 The program graph, exact

**2.1.1 What it is.** `idr::ProgramGraph`, an `AnalysisManager` analysis
on `idr.program`. It is an *index* of the program's call ops: it holds no
fact the ops do not hold, and nothing reads a call's callee another way
(*decision*, from AGENTS.md's "one fact, held once"). It exists from
defunctionalization to `idr-lower`. Before defunctionalization, closure
calls are not calls (lane 05 R14). After lowering, nothing reads such a
graph (§4 I6). The graph after LLVM's own inliner, with code generation's
frame sizes for D32's bound, is LLVM's `CallGraph` over the final module,
upstream's (L10).

**2.1.2 Representation** (*decision* of this lane; C++ idiom is L15's).

```cpp
namespace idr::solver {
// Minted only by ProgramGraph's builder and its Editor; fixed for the
// analysis object's life; never written into the IR.
using FunctionId = Id<struct FunctionTag>;
using SccId      = Id<struct SccTag>;   // increasing = callees first

struct Call {                 // one distinct (callee, kind) of a function
  FunctionId callee;
  TailKind kind;              // read off the call's own fact (D30), L10's enum
  std::uint32_t sites;        // how many calls of this function have it
};

class ProgramGraph {          // frozen; read through const& only
public:
  std::span<const Call> callees(FunctionId) const;     // forward CSR
  std::span<const FunctionId> callers(FunctionId) const; // reverse CSR
  std::uint32_t callSites(FunctionId) const;           // calls naming f
  SccId sccOf(FunctionId) const;
  std::span<const FunctionId> members(SccId) const;    // a range of `order`
  bool onCycle(FunctionId) const;                      // |SCC| > 1 or self edge
  idr::FuncOp op(FunctionId) const;
  FunctionId id(mlir::FlatSymbolRefAttr) const;        // the one name index
  template <typename T> IndexVector<FunctionId, T> table() const;
  Editor thaw() const;                                 // §2.1.5
private:
  Csr<FunctionTag, Call> forward; Csr<FunctionTag, FunctionId> reverse;
  IndexVector<SccPosition, FunctionId> order;          // SCCs contiguous
  IndexVector<SccId, SccPosition> sccStart;
  IndexVector<FunctionId, SccId> scc;
  llvm::BitVector cyclic;
  IndexVector<FunctionId, idr::FuncOp> ops;
  llvm::DenseMap<mlir::StringAttr, FunctionId> byName; // one per graph
};
}
```

- *Ids*: dense in program order at build, appended by the editor, never
  reused. An erased function leaves a gap that `order` skips, until the
  next build compacts it. LLVM's numbered graphs work the same way (§5.3
  B7: a maximum and an epoch). Ids are not kept across passes, so no epoch
  is stored.
- *SCCs as ranges*: members of SCC k are `order[sccStart[k],
  sccStart[k+1])`, in callees-first order of k. Ids do not move when the
  partition is recomputed.
- *No call-op pointers.* Edges hold callee ids, tail kinds and counts.
  So a pass that recreates a call op without changing its callee or kind
  (counting rewrites operands, a canonical form rebuilds a call) does not
  stale the graph, and no dangling pointer can exist. A client that needs
  its own function's call ops walks its own body: a per-function
  extraction it does anyway (§2.3, shape G).
- *The name index* is the single place a callee symbol becomes an id.
  Each call is resolved once per build, and clients read ids from rows.
  It is listed as a runtime lookup forced by MLIR's name-based symbol
  references (D7's exception), and it replaces every `SymbolTable` lookup
  of a function in the clients.

**2.1.3 Invariants.** (I-a) For every function f, the multiset of
`(callee, kind)` over f's `idr.call` ops equals `callees(f)` with
`sites`. (I-b) `callers` is the exact transpose. (I-c) `order`
partitions the live ids into SCCs, each after every SCC it calls.
(I-d) `onCycle(f)` holds iff f's SCC has two members or f calls itself.
(I-e) Nothing outside the builder and the editor mints a `FunctionId`, and
`IndexVector`'s raw-integer index is deleted. In test builds the contract
instrumentation (`--idr-contracts`, `Contracts.cpp`) rebuilds the graph
after every pass whose declared effect is *keeps* or *edits* (2.1.6) and
compares it with the kept one, keyed by symbol name. A pass that broke
the declaration fails its test (05 §8's mitigation, made mechanical).

**2.1.4 Construction.** Three constructors and no other:
1. *Born in defunctionalization*, from its decision. Every apply case's
   call, every force's dispatch call and every dispatch function's label
   calls are known from the label solve's answer (06 §2.4), and direct
   calls from the extraction walk the label solve already makes
   (`LabelSites.cpp:165-175`). No walk of the converted IR. The effect
   rows' first solve runs over this graph (DP-50).
2. *Built* on first request after an invalidation: one walk per function
   in parallel (`mlir::parallelFor`, each writing its own row slot, read
   back in program order: deterministic), then serial: a prefix sum into
   the CSR, the transpose, `components` (§2.2).
3. *Frozen* from an `Editor` (2.1.5).

Failure paths: none. In a first-order program every callee is an
`idr.func` of the program, which `CallOp::verifySymbolUses` checks before
any pass runs (`Call.cpp:29-33`). A missing callee is a verifier error,
never a graph state.

**2.1.5 Edits.** `Editor` (move-only, owned by one restructuring pass):
`insert(FuncOp) -> FunctionId`, `erase(FunctionId)`, `setCallees(f,
span<Call>)` (a function's row replaced whole by the turn that owns that
function: disjoint across workers), `moveInto(f, caller)` (contify: f's
row joins the caller's, and the edge caller→f goes). `freeze()` rebuilds
the transpose and the partition from the rows (one Tarjan over ids, no IR
walk). The partition is never patched in place. Merging and splitting SCCs
under edits is what makes incremental SCC maintenance hard, and
recomputing it from rows is O(F + E) with no IR (*conjecture* on cost:
milliseconds at 70,000 functions).

**2.1.6 How each pass keeps it current.** A pass declares its effect on
the graph, a closed sum `keeps | edits | invalidates`. The declaration is
in its record in the Idris specification (L03 generates the pass bases
and the pipeline, D50), and the generated base marks the graph preserved
for *keeps*. A *decide* step changes no op, so it keeps by construction.
The pipeline as it stands, with DP-50 applied:

| step | role | effect on the graph | reads it |
| --- | --- | --- | --- |
| idr-deduplicate | restructure | none (runs before the graph exists; its reference graph is its own, §2.3 row 8) | — |
| idr-defunctionalize | restructure | **births** it (2.1.4 #1) | its own decision |
| idr-knots | decide (refusal) | keeps | — (type containment) |
| idr-contify | restructure | edits (`moveInto`) | callers, call sites, SCCs |
| idr-optimize | restructure | edits: thaw; each turn sets its members' rows; made nodes inserted at settle; freeze at the end | SCCs, callers (the dynamic client) |
| symbol-dce | upstream | keeps when it erased nothing (13 U-a), invalidates otherwise | — |
| idr-columns | apply | keeps (declared; the contract checks it) | — |
| `idr.func(canonicalize, cse)` | upstream | invalidates (they erase and replace calls) | — |
| `idr.func(idr-structure-loops)` | apply | keeps | — |
| idr-bufferize | restructure (upstream One-Shot) | invalidates (it rewrites call ops' types) | — |
| idr-accumulate | restructure | edits (clones, redirects) | tail kinds of self edges |
| idr-frames | restructure | edits (run and resume functions) | **first rebuild here**; SCCs, tail kinds |
| `idr.func(idr-rc-cells)` | apply | keeps | — |
| idr-rc-stack, idr-rc-grades | decide + apply | keep | `onCycle`, tail kinds, callers (borrows) |
| idr-rc-exclusive | restructure (grade copies, redirects) | edits | for exclusivity (L08) |
| idr-demand | decide (refusal) | keeps | — |
| idr-trmc | restructure | edits | tail kinds |
| `idr.func(idr-tail-loops)` | apply | invalidates (self tail calls become loops) | — |
| idr-narrow | restructure | invalidates; no later reader | — |

So on the program the graph is born without a walk and rebuilt once, at
idr-frames. Today `CallGraph` and `CallCycles` are rebuilt up to seven
times (05 §2.2; *conjecture* for the design's count, which depends on the
final pipeline). This needs §4 I1's patch, so that nested groups of
*keeps* passes keep it.

**2.1.7 Consumers** (each a const reader): the shape S schedule and its
clients (effect rows, lifetimes, Identities, BindingTimes, demand bits,
Ranges' summaries), contify, the optimizer (editor), idr-frames, the stack
inference, the borrow and exclusivity markings (as call edges between
their per-function extractions), the contract check, and the
`idr-binding-times` report.

### 2.2 The shared vocabulary this lane needs (idiom is L15's)

`Id<Tag>`; `IndexVector<IdT, T>` (raw index deleted); `Csr<Tag, Edge>`
modelling one `Graph` concept, with a sentinel root row whose successors
are every node, so that one walk from the root meets every node (the
sentinel replaces `Scc.cpp`'s synthetic vertex: Insight 8), and
`GraphTraits` with `getNumber`/`getMaxNumber`; `components(const Csr &)`
over the patched `scc_iterator` (§4 I5); `mark<Direction>(const Csr &,
seeds) -> BitVector` and `mark<Direction, Gates>` (exclusivity, L08);
`Forward`/`Backward`/`CalleesFirst`/`CallersFirst` as types; a `Summary`
concept (join returning `enum class Changed`); per solver one explicit
instantiation behind `extern template` (DP-53, D7). Deleted with them:
`Scc.{h,cpp}`, `MonotoneWorklist` and `FiniteLattice` (no user,
*measured* in 05 WL1-WL2), the solvers' `function_ref` callbacks
(`Effects.h:51`, `Constants.h:39`, `Identities.h:45`, `Scc.h:34`).
`OnceWorklist` stays for its honest uses: a set of things to visit once
that is not a marking.

### 2.3 Every analysis, its solve shape and its state's bound

Shapes: **L** per function (upstream's framework or one walk, callees'
facts read from a table); **S** summaries over the program graph's SCCs
(callees first or callers first; *static* or the optimizer's *dynamic*);
**G** extract per function, link, solve, write back. **C** carried (no
solve after the producing one: a type, an inherent property, or the op
itself); **D** deleted; **I** Idris side (§2.7). F functions, E call
edges, N extracted nodes, V values of one function.

| # | analysis today (entry) | shape | state bound | carrier of the answer | owner |
| --- | --- | --- | --- | --- | --- |
| 1 | upstream `CallGraph` via CallCycles (`CallCycles.cpp:34`) | D | — | the program graph | L14 |
| 2 | `CallCycles` (`CallCycles.cpp:16-46`) | D → program graph | O(F + E) | analysis (one program) | L14 |
| 3 | `Recursion` (`Recursion.cpp:16-44`) | D → `onCycle` + edge kinds | 1 bit per function | analysis | L14 |
| 4 | caller-only `SymbolUserMap`s (7) | D → `callers` | — | analysis | L14 |
| 5 | `idr::components`, 10 users (`Scc.cpp:32-53`) | `components(Csr)` | O(N + E) per call | per solve | L14 (users: L03/L04/L13/L18/L19) |
| 6 | contify's single use (`Contify.cpp:88-104`) | reads `callSites`, `sccOf`; edits | — | IR | L18 (contify), L09 |
| 7 | ready set and waves (`ReadySet.cpp`, `Waves.cpp`) | S dynamic over the thawed graph | O(F + E) + a summary per function | optimizer's node summaries | L18 |
| 8 | dedup's reference graph and heights (`EliminateDuplicateFunctions.cpp:91-189`) | G: partition refinement over a reference `Csr` (labels as edges) | O(F + references) | the program (merged functions) | L18 |
| 9 | partition into bins (`Target/Partition.cpp:234`) | over LLVM IR; shared `Csr` + `components` | O(F + E) | bins | L15/L03 (target) |
| 10 | effects summary (`Effects.cpp:36-47`, `Func.cpp:189-230`) | S callees-first: first in defunctionalization (DP-50), then per component in the optimizer, then incremental upward re-derivations (§4 I2) | 11 bits per function (D29) | property on `idr.func` and copy on `idr.call` (D20) | L02 (derivation), L14 (schedule), L18 (defunc) |
| 11 | `observableRuns` (`Effects.cpp:49-95`) | D: `by_name` read off a label's row | — | the label's body role | L18 |
| 12 | BindingTimes (`BindingTimes.cpp:90-177`) | S intra-SCC, dynamic client | today bounded only by the tuple space, (P+1)^arity per member (§4 I9) | optimizer summary, dies with the pass | L18, L14 |
| 13 | Identities (`Identities.cpp`) | S greatest fixpoint per SCC, dynamic client | candidates per function (type-filtered, `Identities.cpp:24-36`) | **C**: "gives back" per result field path on `idr.func` (§4 I12, I13) | L14 (solve), L10 (carrier, lowering) |
| 14 | inline facts (`Inline.cpp`) | per node data, no solve: size kept and updated per inline (`Inline/Inline.cpp:158`), verdict a sum | O(F) | optimizer node | L18 |
| 15 | Returned (`Tail/Returned.cpp:152-191`) | D (D10) | — | 13's carried fact, mapped by the lowering | L10 |
| 16 | Ranges (`Ranges.cpp:65-92`) | L per function in idr-narrow-words (upstream `IntegerRangeAnalysis`, U1) + S return ranges (callees first) and argument ranges (callers first) (DP-51) | L: V × ≈0.2 KB per state after U1 (§5.1 A4 P1), freed per function; S: 2 ranges per parameter and result | transient to narrowing (or 0003's range facts, L12) | L12 (narrow), L14 (summaries) |
| 17 | lifetime inference (D39, new) | S callees-first | O(arity²) bits per signature | **C**: the function type's quantity-0 lifetime parameters | L05 (transfer), L14 (schedule) |
| 18 | dead parameters and results (09 T5) | S: a bit per parameter in the optimizer's summary (callees first); results callers first | 1 bit per parameter and result | **C**: erased from the signature | L18 |
| 19 | frames plan (`FramesPlan.cpp`, `Frames.cpp:349-358`) | one structural walk per SCC on S's order, no fixpoint (10 §3.1) | per SCC | the restructured program | L10 |
| 20 | idr-constants (`Transforms/Effects/Constants.cpp:171-201`) | L (upstream SCCP per function, U1), callees' returns from the summary table | V × ≈0.2 KB after U1, per function per round | **C**: constants written into the body; `returnedConstants` reads the body (`Constants.cpp:16-30`) | L18 |
| 21 | `Copy::analyse` (`Narrow/Copy.cpp:66-76`) | L per loop (kept) | one loop's values | transient | L12 |
| 22 | Reuses (`Reuses.cpp:272`) | L: C1's forward walk per function | per function | **C**: `cell.recycle` in the IR | L07 |
| 23 | classes and placement (`Classes.cpp`, `Placement.cpp`) | L: C1's reverse walk per function | per function | **C**: dups and drops in the IR | L07 |
| 24 | `whereDies`, `usedAfter` (`Uses.cpp`) | D: the reverse walk's state (§5.10 M2); a quantity-1 value needs none (§3) | — | — | L07 |
| 25 | `tracked`, `isStatic` (`Values.cpp`, `Verify/Uses.cpp`) | D → **C**: static graded from what a value holds (D39) | — | the grade | L05 |
| 26 | tail position (`IR/Tail.cpp`, `Conversion/TailPosition.cpp` and seven readers) | D → **C** (D30) | — | the call's tail kind | L10 |
| 27 | accumulator plan, TRMC's context (`AccumulatorPlan.cpp`, `IR/Tail.cpp`) | **C**: D34's promise read off the program, on the call (DP-57) | — | the call | L10 |
| 28 | `TailCallPlan` (`TailCallPlan.cpp:69-140`) | D for its cycle condition (D30); its frame bound goes (D30, D32) | — | the lowering's `tail` kind | L10 |
| 29 | narrow facts, versions (`Narrow/*.cpp`) | L per function | per function | transient | L12 |
| 30 | One-Shot module analysis (`Bufferize/Bufferize.cpp`) | upstream as is (its own callee order) | upstream's | the program | L12 |
| 31 | owned verifier's numbering and linearity (`Verify/Linearity.cpp:42-66`) | L per function, after every pass | V | — (a check) | L13, L07 |
| 32 | program verifier (`Verify/Program.cpp`) | per function where its facts are a function's (13 T3); the call checks in `verifySymbolUses` | — | — | L13, L02 |
| 33 | flow edges (`IR/Flow.cpp`) | per op declaration, read once per op by extractors | — | ODS | L02 |
| 34 | lifetimes' edges and `isRepetitiveRegion` per terminator (`IR/Lifetimes.cpp:50-54, 68-129`) | per op; the match answers in O(1) (05 T5.11) | — | ODS/overrides | L07, L09 |
| 35 | canonicalization helpers (`Canon/*`) | per op | — | — | L13 |
| 36 | expect properties (`Transforms/Expect/*`) | read the same analyses | — | tests | L19 |
| 37 | `TypeGraph`, `Layouts`, sealing (`IR/TypeGraph.cpp`, `Layouts.cpp`, `ValueFacts.cpp`) | computed once per type (D48) | per type | the type | L04 |
| 38 | knots (`idr-knots`) | G over type containment (refusal, no budget) | O(types + fields) | a diagnostic | L04, L07 |
| 39 | Labels, LabelSites (`Labels.cpp`) | G: extraction per function in parallel, union-find + interned sets, difference propagation (06 T2, L-10, L-11) | P + E + Σ distinct sets + firings | **C**: sum types and coercions written by the conversion | L18 |
| 40 | exclusivity (`Exclusivity*.cpp`) | G: `mark<Dir, Gates>` | O(N + E) bits | **C**: `!idr.excl` grades | L08 |
| 41 | Borrows (`Borrows.cpp`) | G: two-point marking over parameter nodes; seeds from types and from counting's reverse walk (§3) | O(parameters + call edges) bits | **C**: conventions in the signature's grades | L08 |
| 42 | stack inference (`Stack.cpp:116-269`) | G marking (escape) | O(N + E) bits | **C**: `frame` lifetimes | L07, L10 |
| 43 | in-place promise (`Demand.cpp`) | the rule: L per function from the program as emitted (D24), carried in the function type; the obligation at calls: exclusivity (G) | per function | **C**: the function type | L08 |
| 44 | specialization's order and keys (`Specialize/Order.cpp`, `Requests.cpp`) | optimizer-internal (embedding per request chain), no graph solve | keys per run | spec nodes | L18 |
| 45 | `Captures` (`Ownership/Captures.cpp`) | read by exclusivity's extraction | per memo label | — | L08 |
| 46 | frontend `Recursion.idr` (Tarjan over size-change graphs) | **I** on 0015 layer 2 (§2.7) | — | `total` (C) | L16, L17 |
| 47 | growth check, reachability, Translate's worklist | **I** on 0015 (0011 O3) | — | the emitted program | L16 |
| 48 | the fork's termination closure, the multiplicity check | **I** (the latter not on 0015, `0015-...md:138-140`) | — | `total`; quantities as types | L17 |

Nothing in the table keeps state sized by a product of two program
quantities, except row 12 today (§4 I9) and the label solve's time
O(W·(P+E) + W·D) (06 L-10, L-11), which is L18's to fix.

### 2.4 Every summary computed once

| summary | computed (once per change) | shape | carrier | maintained by | verified | deleted re-derivations |
| --- | --- | --- | --- | --- | --- | --- |
| effect rows (D22) | defunctionalization's decision (DP-50); the optimizer per component when final (`Component.cpp:215` today); an incremental upward re-derivation after each body-changing stage (§4 I2) | S callees-first | `idr.func` property; copy on each `idr.call` (D20) | the re-derivation: seeds = functions whose derived row shrank; walk `callers` SCC by SCC, callees first; stop where a row does not change | cover after every pass (today's `Call.cpp:52-57`, `Program.cpp:53-71`, under the new atoms); equal right after each re-derivation | idr-effects as a pass, `observableRuns`, `solveEffects`' user map, the optimizer's three walks per function writing call bits (05 EF11) |
| lifetimes (D39) | once, at counting's stage, bottom-up | S callees-first | the signature's quantity-0 lifetime parameters | restructures that make functions (frames, TRMC, copies) give theirs by the same transfer | lexical, per function, after every pass | `isStatic`'s chain search, the owned verifier's def-use walk (D39) |
| borrows (C1) | once, in counting's decide step | G marking | grades in the signature (counting's ABI) | grade copies (L08) | operand types equal parameter types at every call (`Call.cpp:34-43`) | Borrows on the framework, its prediction of TRMC (DP-57), its forced-owned reason from reuse sites (C1) |
| tail position (D30) | by the pass that makes or moves a call | C (no solve) | the call's tail kind | every pass obeys it (D30) | locally, per call | `IR/Tail.cpp`'s climb, `TailPosition.cpp`, the per-query readers (`Borrows.cpp:236-237`, `Stack.cpp:233`, `Recursion.cpp:35`) |
| "gives back argument i" (DP-38) | Identities, when the optimizer finishes a component | S greatest fixpoint per SCC | `idr.func` property, per result field path (§4 I13); no call copy (§4 I12) | restructures update their own functions | per function, assuming callees' claims (a post-fixpoint check: §4 I12) | Returned's whole-module solve, idr-returned-arguments' plan |
| SCC membership, self call, on a cycle | the program graph | — | analysis (one per stage) | edits by restructures, rebuild after invalidation | rebuild-and-compare in test builds | CallCycles ×9 readers, `Recursion`, three self-call walks |
| constants of returns | idr-constants, written into the body | L | the body | — | — | — (already one copy: `Constants.cpp:16-30`) |
| demand bits | the optimizer's summary (09 T5) | S | the signature (parameters erased) | — | — | `remove-dead-values`' whole-module liveness (but see §4 I4) |
| inline size | per node, updated by each inline | — | optimizer node | per inline (`Inline/Inline.cpp:158`) | — | `inlineSize` per ask, five callers (05 R10) |

### 2.5 Threading: decide, apply, restructure

*Decision* of this lane (13 T1 adopted, with the corrections of §1.2):

- **Decide** (a pass on `idr.program`, changes no op, marks everything
  preserved, so the verifier skips it, `Pass.cpp:629-640`). It computes
  the program graph (if invalidated) and one decision analysis: a shape S
  table, a shape G answer, or both. **Every attribute and type the answer
  will need is made here, serially, in id order**, and handed to the apply
  step in the table: interned lifetime signatures, effect bit sets (a
  property word, no attribute), grade types. Workers then create nothing
  in the context (§5.1 F3; 98c6315c's class; §4 I8).
- **Apply** (a nested `idr.func(...)` group, parallel under the pass
  manager). Each function reads the decision through a *const* view
  (`getCachedParentAnalysis` returns a mutable reference that may be
  absent, `AnalysisManager.h:299-311`; the view's accessor makes absence
  an internal error naming the missing decide step) and rewrites itself
  whole: body, signature, its own calls' copies of callee rows. It reads
  no sibling (§5.8 B9). The pipeline's record pairs each apply with its
  decide (L03 generates the pipeline, D50), so an apply cannot be placed
  without its decision.
- **Restructure** (a pass on `idr.program` that adds, erases or redirects
  functions): defunctionalization, contify, the optimizer, accumulate,
  frames, TRMC, exclusivity's grade copies, symbol-dce. It may run
  per-function work inside itself on the context's pool where B9 allows
  (06 D-32).

What runs in parallel, by shape:

| work | parallel how | serial part | determinism |
| --- | --- | --- | --- |
| graph build | per function on `mlir::parallelFor`, each into its own slot | prefix sum, transpose, Tarjan | slots read in program order |
| shape L | the pass manager over functions (nested group), or the optimizer's turns | none | per function |
| shape S static | dependency-count tasks on the context's pool (`ThreadPoolTaskGroup`; workers may submit tasks, `ThreadPool.h:45-50`): an SCC starts when its last callee SCC finishes; no wave barrier, since a decide step runs no nested pipeline | inside an SCC, iterate to a fixpoint (a giant SCC serial first, DP-52) | each SCC writes its members' slots and reads finished ones; least and greatest fixpoints are unique |
| shape S dynamic | the optimizer's waves (`Waves.cpp:323-347`), a barrier per wave kept: a dynamic pipeline needs its op nested under the pass, and nesting an analysis manager inserts into a map other pipelines read (`Pass.cpp:574-591`, 09 T1) | settle between waves | name order of placements (`Waves.cpp:304-309`); OPT-48's fix (L18) |
| shape G | extraction per function in parallel into arrays at a base offset (prefix sum of per-function counts); write-back as the apply group | link, then the solve (marking linear, union-find) | extraction order is the walk order, read back by the same walk (one walk template for both) |

**Solve units are traced, transform units are actions** (§4 I3). A unit
of a decide step (an SCC, an extraction) gets a time-trace zone named by
its analysis and function. A transform unit is an action
(`support::perform`, `Actions.h:51-62`), which a debug counter may skip,
leaving valid IR.

### 2.6 The storage patch's measurement, as the exact measurement to take

Nothing here was run (no build: the swarm's rule). Each record names its
commit, build type (stage 2 is built with `LLVM_ENABLE_ASSERTIONS=ON`,
`tools/bootstrap.sh:1022-1031`, stated in every record), target, thread
count, input digest and counter (AGENTS.md: a number carries its measure,
build and input).

- **The patch (U1, P1).** `mlir/include/mlir/Analysis/DataFlowFramework.h:481-482`:
  the inner map becomes `SmallDenseMap<TypeID, std::unique_ptr<AnalysisState>, 2>`.
  `:559`: `dependents` becomes `SetVector<WorkItem, SmallVector<WorkItem, 0>,
  DenseSet<WorkItem>, 4>`. In the constructor (`:327-330`), add
  `uniquer.disableMultithreading()` (`StorageUniquer.h:143`), since the
  solver is single-threaded (§5.1 A5). Carried as
  `upstream/<NN>-dataflow-state-storage/llvm.patch` with README,
  submission and `tests/upstream-dataflow-state-storage` (the repository's
  layout, `upstream/README.md`).
- **M1, bytes per anchor on all four targets.** §5.1 A4's harness (one
  million synthetic `Value` anchors with the solver's exact container
  types, from the pinned headers, linked with the pinned
  `llvm/lib/Support/{MemAlloc,SmallVector,SmallPtrSet,DenseMap}.cpp`) is
  committed under the patch's directory as its reproducer. It reports heap
  bytes per anchor at 0, 1 and 3 dependents, at the pin and with P1, on
  arm64 macOS (libmalloc), arm64 Linux 16 KiB, arm64 Linux 4 KiB and x86_64
  Linux (glibc). A4 measured libmalloc only, and its harness was not kept
  (`/tmp/mlir-sizeof`). Expected (*measured* on macOS by §5.1): 1,460 /
  2,756 / 2,788 B at the pin, 182 / 198 / 230 B with P1.
- **M2, the pull request's numbers.** Peak heap (Linux: `valgrind
  --tool=massif`, the peak `mem_heap_B`; macOS: `/usr/bin/time -l`, "peak
  memory footprint") of `mlir-opt --sccp`, `--int-range-optimizations` and
  `--remove-dead-values` on the pinned in-tree tests for those passes and
  on a synthetic 16,000-function module of `upstream/05-forward-dataflow-callee-lookup/calls.sh`'s
  shape, at the pin and with P1. #135325's review asked for exactly this
  (§5.1 A8).
- **M3, ours, on the stage-1 module** at a recorded commit, threads 1 and
  all. For each solve, the module is saved at the point before its pass
  (`idris-mlir-opt --idr-target --pass-pipeline='builtin.module(idr.program(<steps before it>))'
  stage1.mlirbc -o at.mlirbc`), and the pass runs alone on it under 13 T5's
  per-pass footprint record (macOS `task_info` `phys_footprint` and its
  peak; Linux the cgroup's `memory.peak`, 13 M4). The census pass (13 T5's
  companion) records V, B, P, F and the anchor count at that point. Pin
  against P1 for:
  - **M3a** idr-rc-grades: Borrows on the framework. AGENTS.md owes this
    before Borrows leaves the framework. The marking's figure (W9) goes in
    the same record.
  - **M3b** idr-narrow: whole-program Ranges at the pin, with P1, and per
    function after W10. This replaces DP-51's recalled "3 s against 30 s"
    with our own number.
  - **M3c** idr-optimize: the peak of idr-constants' per-function solves
    (the largest function times the threads; §5.1 Design 1's "about 60 MB
    per analysis per thread" at 300,000 values is *conjecture* until then).
  - **M3d** upstream `remove-dead-values` with each function as root
    (`builtin.module(idr.program(idr.func(remove-dead-values)))`, after
    idr-optimize, in idris-mlir-opt's pipeline text only, never an option
    of the compiler), with P1 and U2 (§5.1: the backward analysis's callee
    resolution in a scoped solve, `SparseAnalysis.cpp:521-540`). Recorded:
    footprint, time, and the values it erases that canonicalize, CSE and
    the optimizer's demand bits left. This is the measurement 16005000
    skipped; it decides §4 I4.
  - **M3e** the pre-ffa91113 exclusivity at that commit with P1 (L08; 20
    H1, 21 §8 item 6).
- **What it decides.** Whether Borrows' marking stands on numbers (it
  should: one bit per node against about 0.2 KB per state). Ranges' shape
  (DP-51). Whether `remove-dead-values` returns per function (§4 I4).
  That §5.1 H1's "52 GB ⇒ V ≈ 10 million" and H2's "627 GB ≈ 200 million
  states" are measured rather than arithmetic (21 §3.1).

### 2.7 The seam with 0015's relational core (D44)

The rule (*decision*, restating 0008 D13 and 0015 D6 as an operating
test). A fact decidable from Idris's checked TT and the frontend's tables
is computed in Idris, on 0015's core where it is a fixpoint, and crosses
Emit as a type or an inherent property. A fact about the `idr` IR after
Emit is C++, on this solver layer. No fact is computed on both sides.
When both need one, the side that first knows it computes it and the
other reads it (D10).

| solve | side | where | why there |
| --- | --- | --- | --- |
| instance fixpoint (Translate), reachability from `main` | Idris, 0015 layer 2 (0011 O3, R3) | `Frontend/Translate*`, `Profile.idr:306` (`checkReachable`) | over Idris terms and substitutions, before Emit |
| growth check | Idris, layer 2 (16 G7) | `Frontend/Growth*` | a refusal over Idris types, before translation |
| size-change termination (the fork's closure, `Recursion.idr`'s Tarjan) | Idris, layer 2 with subsumption (0015 D9; 0011 §4.7) | `compiler/idris/src/Core/Termination/*`, `Frontend/Translate/Recursion.idr:42` | over every argument, erased ones included (a decrease on an erased index is legitimate) |
| multiplicity check | Idris, a semiring fold, not 0015 (`0015-...md:138-140`) | the fork | Idris's own QTT |
| name resolution, elaborator postponement, invariants as law queries | Idris (0011 O5, O7, O8) | the frontend | before Emit |
| label solve (0CFA) | C++, G | `lib/Analysis/Labels*.cpp` | over the IR's closures; 0008 rejects "0CFA on 0015" |
| program graph, every summary, every marking, dedup, the optimizer | C++ | `lib/Solver/`, the passes | over the IR after Emit |

What crosses Emit, read once and never re-derived: `total` (Idris's
termination; read by the row derivation as divergence; cleared only by
`absorb` when merging a function that lacks it, `Contify.cpp:109`),
quantities as types (`!idr.lin<T>`; erased values absent; quantity-0
index and lifetime parameters as compile-time parameters, D48), `no_inline`
until 09 T4 replaces it. Two facts D24 and D34 say are "read off the
program as the frontend wrote it" are per-function syntactic facts, with
no fixpoint and no need for 0015. The frontend constructs the program, so
by D10 it is their natural constructor, and they cross as function-type
facts. Seam with L08, L10 and L16, unfixed: who computes them.

Essential, kept: the Idris side's call graph (instances, size-change
edges, closures not yet calls) and the C++ program graph (after
defunctionalization) are two graphs. Neither is derivable from the other
(lane 05 R14). The C++ `FunctionId` is a graph-local index and never a
carried identity. A function's identity in MLIR is its symbol, and an id
carried from 0011's instance table would be a second identity for one
function.

### 2.8 Constructor provenance

| fact | constructed by | and only by |
| --- | --- | --- |
| `FunctionId`, `SccId` | `ProgramGraph`'s builder, `Editor::insert` | those |
| call edge `(callee, kind, sites)` | the build, from each `idr.call`'s symbol (resolved once) and its tail kind | the build; the editor from a restructuring pass's known edits |
| SCC partition and order | `components` over the rows, at build and `freeze` | those two |
| a call's tail kind | the pass that makes or moves the call (D30) | L10's rule |
| effect row of a function | the shape S solve with L02's one derivation as transfer (defunctionalization; optimizer per component; upward re-derivation) | those three schedules of one transfer |
| effect row on a call | written in the same step as its callee's (today's `writeEffects` discipline, `Func.cpp:225-230`) | same |
| `by_name` | a predicate over a label function's row, generated from the specification | defunctionalization's decision |
| `total` | Idris's termination checker, through Emit | Emit; cleared by `absorb` |
| "gives back" per result field path | Identities when a component is final | the optimizer; restructures for the functions they make |
| lifetime parameters in a signature | the lifetime summary (L05's transfer) | counting's decide step |
| borrow conventions, exclusive grades | the markings (L08) | counting's decide steps |
| label sets → sum types | the label solve, written by the conversion | defunctionalization |
| constants in bodies | idr-constants | the optimizer's inner step |
| a pass's effect on the graph | its record in the specification | L03's generator |
| decision tables | the decide analysis | read by apply through a const view |

### 2.9 Seams with other lanes

- **L01/L02**: the transfer of the row solve is L02's one derivation. The
  rows' storage is a generated bit set as a property (no attribute made per
  function). The verifier's row check is cover after every pass (§4 I2,
  L02 decides). The call's copy of the row is D20's.
- **L03**: each pass record declares `keeps | edits | invalidates` for the
  program graph and its role (decide, apply, restructure). The pipeline
  pairs each apply with its decide. Unfixed until L03 adopts it.
- **L04**: type containment for knots, layouts once per type (D48).
- **L05**: the lifetime transfer, and the signature form of quantity-0
  lifetime parameters.
- **L07**: counting's two walks (shape L); the stack inference's marking
  (shape G); `whereDies` deleted.
- **L08**: exclusivity's and borrows' markings on §2.2's `mark`. Seeds of
  the borrow marking from types (§3). Whether the in-place rule is
  computed by the frontend. **Unfixed**: the program a refusal analysis
  reads. Acceptance must not move with the optimizer (AGENTS.md; D24's
  "never from what an optimization did"), and the program graph after the
  optimizer reflects its inlining.
- **L09**: a jump to a join point is no call, so contification removes call
  edges (contify edits the graph).
- **L10**: the tail-kind enum (`TailKind` here), frames reading SCCs and
  edge kinds, D32's bound over LLVM's final call graph (not this graph,
  §2.1.1), "gives back"'s carrier and its lowering per field path (§4 I13).
- **L12**: Ranges per function in idr-narrow-words, with this lane's
  summaries.
- **L13**: the match's interface overrides (05 T5.11); `idr.call` and
  `idr.func` carrying rows and tail kind.
- **L15**: the C++ form of §2.2.
- **L16/L17/L20**: §2.7.
- **L18**: the graph's birth in defunctionalization (DP-50); dedup's
  partition; the optimizer as the dynamic client; BindingTimes (§4 I9).
- **L19**: the rebuild-and-compare contract; per-solver determinism (DP-34);
  `unittests/Cycles.cpp` retargeted.

### 2.10 What it deletes (paths and symbols)

`include/idr/Analysis/CallCycles.h`, `lib/Analysis/CallCycles.cpp`;
`include/idr/Analysis/Recursion.h`, `lib/Analysis/Recursion.cpp`;
`include/idr/Support/Scc.h`, `lib/Support/Scc.cpp`; `Worklist.h`'s
`MonotoneWorklist` and `FiniteLattice`; `lib/Analysis/Effects.cpp` and
`include/idr/Analysis/Effects.h` whole (`solveEffects` into the S
schedule inside defunctionalization, `observableRuns` gone, DP-50);
`lib/Transforms/Effects/Effects.cpp` and its `Passes.td` record; the seven
`SymbolUserMap` constructions (§1.4); the twelve name-keyed and four
pointer-keyed membership maps of §1.4 that this lane's units reach;
`ReadySet.cpp:34-42` (the second walk) and `calls`; the self-call walks
(`Waves.cpp:228-234`, `Inline.cpp:25-28`); `Tail/Returned.cpp`'s
`ReturnedAnalysis`, `KnownLattice` and solve (with L10);
`Ranges::Solved`'s whole-program solver and interprocedural configuration
(with L12); `Transforms/Effects/Constants.cpp:73-169` once upstream's SCCP
rewrite is exported (05 CO1); `Identities.h`'s `Outside`, `Members`,
`Assumed`; `BindingTimes.cpp`'s `Members`, tuple map and the per-member
re-interpretation (§4 I9). In tests: `unittests/Cycles.cpp`'s target
types (its property stays).

### 2.11 Distinctions that must remain

- Static summaries and the optimizer's dynamic one: the graph grows and
  components merge only there (`Waves.cpp:150-192, 259-275`).
- Refusal analyses (no budget; units never skippable; exact program) and
  optimization analyses (budget allowed; pessimistic fallback).
- Least fixpoints (rows, markings) and the greatest (Identities).
- The program graph, the Idris side's graph, dedup's reference graph and
  LLVM's final call graph: four graphs of four stages.
- Frozen graph (read by everyone) and editable graph (held by one
  restructuring pass).

---

## 3. QTT

**Where quantities enter this area, and what each makes unnecessary.**

- **Quantity 0** is no value of the module (AGENTS.md). So no solver of
  this layer can hold state for an erased thing: no label-solve point, no
  marking node, no range lattice, no call edge. This holds by
  construction, since Emit writes none (*read*: AGENTS.md's rule; the
  extractors walk values). The quantity-0 *parameters* D48 adds (index and
  lifetime variables) are compile-time arguments at calls (`idr.call
  @map<k, frame>`). They create no call edge, and the lifetime summary's
  transfer reads them on the call op as the instantiation. A summary of
  this layer never needs a run-time representation of them: the lifetime
  inference's answer *is* quantity-0 data in the signature (§2.4), so the
  most expensive summary of the design costs nothing at run time and is
  checked locally.
- **Quantity 1** (`!idr.lin<T>`) proves a single use. It answers, by type,
  questions the design would otherwise solve:
  - *"Is the argument used after the call?"* C1's borrow rule needs this
    at every call. For a linear operand the call is its one use, so the
    answer is no, read off the operand's type with no liveness query. Only
    an unrestricted operand needs counting's reverse walk. So the borrow
    marking's seeds come from two sources, the type and the walk, and the
    marking itself holds **no node for a quantity-1 parameter**: Borrows
    already makes such a parameter owned by type (`Borrows.cpp:22-24`).
  - *"Where does it die?"* A linear value dies at its use, so counting's
    reverse walk (row 23) tracks no linear value and `whereDies` (row 24)
    has nothing to answer for one.
  - *"Can it be shared through this binder?"* No: a linear binder is used
    once, so exclusivity's marking needs no duplicate-use seed for it.
    Sharing can come only from where the value came from. A linear binder
    still does not imply unique ownership (AGENTS.md), so exclusivity
    still follows the source (L08).
  - *Join points*: a linear, non-escaping continuation called in tail
    position is a join point (D19). Contified before defunctionalization,
    it never becomes a label-solve point, a dispatch match or a call edge,
    so P, D and E all shrink by type (L09, L18; *conjecture* on how much).
- **ω** values are what every solver of §2.3 is for.

**Where a quantity is kept or read in this area.** Borrows reads quantity 1
(`Borrows.cpp:22-24`). The owned verifier's numbering collects the linear
values of each function and checks each is used once after every pass
(`Verify/Linearity.cpp:47-49`). That is AGENTS.md's check that no pass
drops what Idris proved: it guards the passes, not Idris, and stays.
`total` crosses Emit and is read as divergence. Inlining and contify clear
it when merging a non-total body (`Contify.cpp:109`, `Inline/Inline.cpp:156`).

**Where it is lost.** Not in this lane's code. Specialization keys
(optimizer, stage First) are formed before grades exist (09 §3.1), but
`!idr.lin<T>` is a type from Emit on and is verified after every pass.

**Using it harder** (proposals; §4 I10's companion):
1. **A solver's domain is a type.** Every shape G extractor takes only
   values whose type leaves its question open, through a filter generated
   from the grade (§5.6 Design 2; B §2.2). Make it unwritable to do
   otherwise: the extractor's input is an `Open<Question>` value that only
   the filter constructs. A node for a linear parameter in the borrow
   marking, or for an erased thing anywhere, then does not type-check.
2. **The borrow seed is a type, never a query** (C1 as written already
   implies it; state it in C1's text so no implementation asks liveness of
   a linear operand).
3. **No count effect for what quantity and exclusivity together prove.**
   That is L01/L02's (D10: an exclusive drop reads no count). This lane's
   rows carry what the ops declare.

---

## 4. Improvements

Each: evidence, counterexample, root cause, one correction, what it
deletes, how it is discriminated, and who decides.

**I1. A nested group keeps what every nested pass kept: carry the
adaptor-intersection patch.** *(coordinator)*
- *Evidence*: an adaptor's preserved set is empty, so `am.invalidate`
  drops every parent analysis and clears every child map
  (`mlir/lib/Pass/Pass.cpp:618-619, 1172-1186`; `PreservedAnalyses::isNone`,
  `AnalysisManager.h:43-44`). LLVM's adaptor intersects its passes'
  preserved sets so module analyses survive (`llvm/lib/IR/PassManager.cpp:137-169`).
- *Counterexample*: `idr.program(decide-grades, idr.func(apply-grades),
  decide-exclusivity)`. `ProgramGraph`, built by `decide-grades`, is
  dropped after the group though no call changed, and rebuilt by
  `decide-exclusivity`. With a group per counting step, the "seven builds"
  chain (05 CC3) comes back by mechanism.
- *Root cause*: MLIR's adaptor loses its nested passes' preservation facts,
  which the passes stated.
- *Correction*: `upstream/<NN>-adaptor-preserved-intersection/llvm.patch`.
  `OpToOpPassAdaptor::runPipeline` returns the intersection of the
  preserved sets of the passes it ran. The sync and async adaptors
  intersect over children and set their own pass state's preserved set to
  it, so a group whose passes all preserved everything also skips the
  parent's verifier (`Pass.cpp:629-640`). Test: an analysis that counts
  its constructions, in `mlir/unittests/Pass/AnalysisManagerTest.cpp`'s
  style.
- *Deletes*: the rebuild per group; nothing of ours (it enables §2.1.6).
- *Discriminated by*: the upstream unit test (count 1 after the patch, 2
  before), and in our tree a pipeline test that `ProgramGraph`'s
  construction counter is 1 across `idr.func(idr-rc-cells)`.

**I2. Rows cover their derivation after every pass, and equal it after
each re-derivation; the re-derivation is incremental upward.**
*(coordinator; the owner's question in §6 asks whether equality must
hold at every pass)*
- *Evidence*: the canonicalizer replaces a match by its known region
  (`IR/Canon/MatchPatterns.cpp:1-5`), deleting other cases' crash and IO
  ops. The verifier runs after the group, before any pass of ours could
  rewrite rows (`Pass.cpp:618-642`). Today's checks are cover
  (`Call.cpp:52-57`, `Program.cpp:53-71`). §5.1 states equality.
- *Counterexample*: `f` calls `g`; `g`'s row is `{crash}` from a partial
  match arm. After the optimizer, `g`'s scrutinee is a known constructor,
  canonicalize folds the match, and `g`'s derivation is `{}`. Under
  equality the verifier rejects `g` (row ≠ derivation) after a correct
  pass. Rewriting `g`'s row alone would make `f`'s call row ≠ `g`'s row.
- *Root cause*: equality makes every pass that deletes code responsible
  for a whole-program propagation it cannot perform, inside a pass that
  is not ours.
- *Correction*: the after-every-pass invariant is cover, under the new
  tree and atoms (D27, D29). Equality holds at each re-derivation: a
  decide step whose seeds are the functions whose derived row shrank. It
  walks `callers` SCC by SCC in callees-first order, writes rows and call
  rows together, and stops where a row does not change. It runs after the
  optimizer (per component, as today) and once before `idr-lower`, so
  LLVM receives exact `willreturn`, `nofree` and `memory(...)` (§5.1).
- *Deletes*: §5.1's "a row equals its derivation" as an after-every-pass
  check; any whole-program re-solve of rows.
- *Discriminated by*: a fixture where a fold removes a crash. It passes
  the verifier after canonicalize, and the function's and every caller's
  `willreturn` appears on the lowered call (an `idr-expect` property, L19).

**I3. Solve units are traced, never skippable; only transforms are
actions.** *(coordinator: AGENTS.md's acceptance rule settles it)*
- *Evidence*: `support::perform` runs its body only if the handler does
  (`Actions.h:51-62`), and idris-mlir-opt's debug counter skips by tag
  (`Actions.h:4-9`). §5.4 and B §2.7 make every solve unit an action.
- *Counterexample*: `idris-mlir-opt --idr-pipeline
  -mlir-debug-counter=idr-exclusivity-scc-skip=1`. An SCC of exclusivity's
  marking is skipped, its values stay at the marking's start (exclusive),
  and an in-place update is emitted for a shared cell: a miscompile, from
  a bisection tool. A skipped refusal unit equally moves acceptance.
- *Root cause*: one mechanism (the action) is used for two kinds of unit,
  only one of which may be skipped.
- *Correction*: `support::trace<Unit>(scope, name)`, a time-trace zone
  (13 T4's one trace), for every solve unit of every decide step. The
  action stays the form for transforms, whose skip leaves valid IR
  (`Actions.h:6-7`). The two are different templates, so a solve unit
  cannot be written as a skippable action.
- *Deletes*: nothing today: no solve unit is an action yet (21 §3.2,
  *measured* there). It prevents the next one.
- *Discriminated by*: a unit test that every solver of `lib/Solver/` gives
  the same answer under an action handler that skips everything.

**I4. `remove-dead-values` per function is measured on the patched
framework before its patches retire (DP-54 overruled in part).**
*(coordinator: AGENTS.md's dated "never" line, DP-24 and §7 S3 settle it)*
- *Evidence*: AGENTS.md: "remove-dead-values adopted in place of our pass
  (0451b1b8) and dropped, four patches later, on a run stopped by hand at
  52 GB (16005000)". DP-54 retires 06, 28 and 63 now. §5.1 5.1.2 #4: the
  per-function half is upstream as it is, and 06, 16, 22, 28 and 63 stay
  relevant to it. 21 P-9: what it alone removed is unmeasured.
- *Counterexample*: a match whose results are unread in one function. If
  no pattern of ours drops unused match results, per-function
  `remove-dead-values` would (upstream's region-branch dead results,
  `RemoveDeadValues.cpp:272-396` per §5.1 B3), and the optimizer's
  parameter bits would not. *conjecture* until M3d.
- *Root cause*: the drop was made on a kill, not on a measurement of the
  patched, per-function form.
- *Correction*: take M3d (§2.6) with U1 and U2. If per-function
  `remove-dead-values` erases values the rest left and fits (peak = the
  largest function times the threads), it returns per function as an
  upstream pass, nested on `idr.func`, with 06, 28 and 63 carried, and
  the interprocedural half stays the optimizer's demand bits (09 T5),
  the same split as idr-constants. If it erases nothing beyond them, its
  patches retire with the measurement in their `upstream/` record.
- *Deletes*: either `Register.cpp:139`'s dead registration and the three
  patches (with a recorded reason), or nothing.
- *Discriminated by*: M3d's count of erased values on stage 1.

**I5. `scc_iterator` reads node numbers; our graphs carry a sentinel
root.** *(coordinator)*
- *Evidence*: `scc_iterator` keeps `DenseMap<NodeRef, unsigned>
  nodeVisitNumbers` (`SCCIterator.h:73-75`) and starts from one entry
  (`:96-107`). `po_iterator` already switches to a bit vector by
  `getNumber` (`PostOrderIterator.h:30-53`, `GraphHasNodeNumbers`).
  `Scc.cpp:34-43` adds a root vertex for the one entry.
- *Counterexample*: `components` over a value-level graph of 10 million
  nodes (exclusivity's or the stack's extraction) builds a transient hash
  map of 2^24 buckets or more beside the graph's 8(N + E) bytes
  (*conjecture*, arithmetic from `DenseMap`'s sizing, §5.3 B7).
- *Root cause*: upstream's Tarjan does not read the dense numbers its own
  `GraphTraits` can offer.
- *Correction*: `upstream/<NN>-scc-iterator-node-numbers/llvm.patch`.
  When `GraphHasNodeNumbers<GraphT>`, visit numbers live in a vector
  indexed by `getNumber`, as `po_iterator`'s set does. Our `Csr` gives
  `getNumber` and a sentinel root row (§2.2), so one walk meets every node
  without a synthetic vertex.
- *Deletes*: `Scc.cpp`'s `Vertex` copy and root; `stronglyConnected`'s map
  (05 SC1-SC2).
- *Discriminated by*: LLVM's `SCCIteratorTest` extended to a numbered
  graph; our `components` property test against reachability (today's
  `unittests/Cycles.cpp` shape).

**I6. No program graph on the lowered module.** *(coordinator; simpler)*
- *Evidence*: its readers today are Returned (`Returned.cpp:162-169`,
  deleted by D10), `TailCallPlan`'s cycle condition (`TailCallPlan.cpp:118-123`,
  deleted by D30) and its "internal" set (`:72-88`, a `SymbolUserMap`).
  D32's bound needs code generation's frame sizes, which exist only after
  LLVM, on LLVM's final call graph.
- *Counterexample*: DP-52's second instance, built for no reader: a walk
  of every lowered function for nothing.
- *Root cause*: the design carried today's readers forward without
  applying D10 and D30 to them.
- *Correction*: no instance after `idr-lower`. "Only the module's calls
  reach it" is the private visibility the lowering gives every function
  but the root, plus an address-taken fact the lowering knows where it
  takes an address (L10). D32 reads LLVM's `CallGraph` with the frame
  sizes code generation reports (upstream first; L10).
- *Deletes*: `TailCallPlan.cpp:72-88`'s user map; the lowered instance.
- *Discriminated by*: `idr-tail-calls` gives `tailcc` to the same
  functions on the corpus (L10's test).

**I7. Edges hold ids, not call ops; a frozen form and an editable form.**
*(coordinator)*
- *Evidence*: a pass that recreates a call op keeps the call graph as a
  set of edges but would stale a pointer to the old op. The optimizer
  edits rows from parallel turns (`Component.cpp:148-160`). A CSR cannot
  take an edit in place.
- *Counterexample*: counting rebuilds a call with new operand types
  (`replaceOpWithNewOp`), declares *keeps* because the callee is
  unchanged, and a graph holding call-site pointers then holds a freed op.
- *Root cause*: holding IR pointers in an index whose invariant is about
  callees.
- *Correction*: §2.1.2-§2.1.5. Rows of `(callee, kind, sites)`. A
  restructuring pass thaws an `Editor` whose rows are per function (each
  written by the turn that owns its function) and freezes it, recomputing
  the transpose and the partition from rows. The frozen analysis has no
  edit API.
- *Deletes*: the ready set's private graph (`ReadySet.cpp:27-75`'s maps);
  any in-place SCC maintenance.
- *Discriminated by*: the rebuild-and-compare contract after every *keeps*
  or *edits* pass (§2.1.3).

**I8. The decide step makes every type and attribute its answer needs.**
*(coordinator)*
- *Evidence*: workers creating attributes and types take the context's
  shard locks and grow it for good (§5.1 F3). The parallel agent measured
  lock contention at about a fifth of the reduced corpus (21 §3.4). Keys,
  names and types are made on workers today (09 §2.4).
- *Counterexample*: lifetime signatures written by an apply group, each
  worker calling `FunctionType::get` with lifetime parameters: N
  concurrent writer-lock acquisitions for types that are mostly equal.
- *Root cause*: uniqued IR objects created at the point of use, on
  workers.
- *Correction*: the decide step interns every distinct type and attribute
  the answer needs, serially in id order (also deterministic), and the
  table hands the apply step finished objects. Effect rows are a property
  word, not an attribute (L02).
- *Deletes*: context writes on workers in every apply step of this layer.
- *Discriminated by*: a test instrumentation that counts context storage
  allocations during an apply group: zero.

**I9. BindingTimes' state is sized by the program.** *(coordinator; L18
decides with it)*
- *Evidence*: a tuple assigns each parameter of a reached member one of
  `Anything` or `Same{k}` over the root's parameters (`BindingTimes.cpp:83-116`).
  Reaches are bounded only by that space, (P+1)^arity per member. One
  interpretation runs per member (`Component.cpp:245`).
- *Counterexample*: an SCC of eight mutually recursive functions of arity
  six that permute their arguments reaches up to 7^6 tuples per member
  per root (*conjecture*, arithmetic).
- *Root cause*: polyvariance inside an SCC duplicates what specialization
  already provides per call site.
- *Correction*: one monovariant solve per root over (member, parameter)
  nodes with a flat lattice (bottom, `Same{k}`, `Anything`): O(members ×
  parameters) per root. It adopts only if the `idr-binding-times` remarks
  are equal on the corpus (05 T5.4's test).
- *Deletes*: the tuple map, the per-visit body walks, the name lookups
  (05 BT2-BT9).
- *Discriminated by*: the remarks compared on the corpus; a fixture whose
  tuple count grows exponentially in arity, timed.

**I10. The two "never" patterns still in Borrows go with its marking.**
*(coordinator)* Evidence: `Borrows.cpp:303-304` (`[[maybe_unused]]` and an
`assert` dropping the solve's result, the pattern AGENTS.md cites as 10
R-2) and `:272-288` (recursion along a definition chain, D33). Correction:
the marking returns no failure (a marking cannot fail: its type says so)
and runs on a worklist. Deletes both. Discriminated by L08's marking tests
and the absence of `[[maybe_unused]]` on any `LogicalResult` in
`lib/Analysis` (a grep in `make check`, L19).

**I11. An analysis declares what it reads as a type; its invalidation is
generated.** *(coordinator)*
- *Evidence*: invalidation is hand-written per analysis
  (`CallCycles.cpp:48-50`, `Recursion.cpp:46-48`; Labels on
  `SymbolTable`, 06 L-13).
- *Counterexample*: an analysis whose constructor reads `Borrows` but
  whose `isInvalidated` names only `ProgramGraph` survives a pass that
  changed borrows, and answers from stale input.
- *Root cause*: the dependency lives in a constructor body, not in a type.
- *Correction*: `using Reads = TypeList<ProgramGraph, Borrows>`. A generic
  constructor fetches them as const references, and `isInvalidated` is
  generated (invalidated if any read is). The pipeline's stage chain (L03)
  checks that each `Reads` is available at its decide step.
- *Deletes*: the hand `isInvalidated`s.
- *Discriminated by*: it does not compile to read an analysis not listed
  (the generic constructor hands out only listed ones).

**I12. A summary is held once, on the function; a call copies only what
an op-local interface must answer.** *(coordinator)*
- *Evidence*: AGENTS.md: "a copy kept in step by a verifier is still a
  copy". DP-38 puts "gives back argument i" on calls. The row copy is
  forced (`Call.cpp:61-72`: `getEffects` answers from the op; D20).
- *Counterexample*: a restructure updates a function's fact and misses one
  of its calls; the verifier then fails on a fact no reader needed at the
  call.
- *Root cause*: a cross-function read inside a parallel step solved by
  copying instead of by a decide table.
- *Correction*: "gives back" lives on `idr.func` only. A parallel reader
  (the lowering's conversion) reads it from a decide table collected
  before the parallel step. The per-function check assumes callees'
  claims, which is how a greatest fixpoint is checked (a post-fixpoint:
  each claim holds given the others).
- *Deletes*: the call copy and its verifier arm.
- *Discriminated by*: the lowering produces the same signatures on the
  corpus.

**I13. "Gives back" per result field path, so lowering needs no residue
solve.** *(coordinator; L10 decides the carrier)*
- *Evidence*: Returned works "component by component" after the lowering
  splits values (`Pipeline.cpp:170-172`; `Returned.cpp:5-13`), a finer fact
  than "result r is argument i".
- *Counterexample*: a threaded state `(arr, n)` returned inline with `arr`
  the argument's first field and `n` new. A per-result fact misses it, and
  05 T5.5 would keep a residue solve on lowered code.
- *Root cause*: the carried fact's granularity is coarser than the
  lowering's split.
- *Correction*: Identities' lattice per (result, field path of an inline
  value) → (argument, field path), over constructor fields (independent
  of layout, D48). The lowering maps each path to its words.
- *Deletes*: the residue solve 05 T5.5 kept as an option.
- *Discriminated by*: the corpus' dropped results equal today's
  `idr-returned-arguments` statistic.

---

## 5. Work units (draft; none dispatched by this swarm)

Each unit is a hard cutover: it deletes what it replaces in the same
change, builds and passes on all four targets (AGENTS.md).

**W1. Upstream: the dataflow state storage (U1, P1).**
- *Write*: `upstream/<NN>-dataflow-state-storage/{README.md,submission.md,llvm.patch,measure/}`,
  `tests/upstream-dataflow-state-storage/`, `PINS.md` (its entry).
- *Outcome*: §2.6's patch carried, M1 and M2 recorded in its README.
- *Deletes*: nothing of ours.
- *Must not*: change any analysis of ours; add P2.
- *Acceptance*: `tests/upstream-patches` applies it; its test checks that
  a solve's states use the small containers (heap per anchor below the
  pin's at 0 and 1 dependents on the four targets).

**W2. Upstream: an adaptor keeps what its passes kept.**
- *Write*: `upstream/<NN>-adaptor-preserved-intersection/*`,
  `tests/upstream-adaptor-preserved-intersection/`, `PINS.md`.
- *Outcome*: §4 I1.
- *Must not*: preserve anything a nested pass did not.
- *Acceptance*: the construction count of a parent analysis is 1 across a
  group that preserved it, 2 across one that did not.

**W3. Upstream: `scc_iterator` reads node numbers.**
- *Write*: `upstream/<NN>-scc-iterator-node-numbers/*`, its test, `PINS.md`.
- *Outcome*: §4 I5.
- *Acceptance*: the same SCCs, in the same order, as the unpatched
  iterator on every graph of up to five nodes (exhaustive) and on random
  numbered graphs.

**W4. The solver layer's shared types.**
- *Write*: `foreign/idr/include/idr/Solver/{Id,IndexVector,Csr,Direction,Summary,Mark,Components,Trace}.h`,
  `foreign/idr/lib/Solver/{Csr,Components,Mark}.cpp`,
  `foreign/idr/lib/Solver/CMakeLists.txt`; the ten `idr::components` call
  sites (`Labels.cpp:261`, `TypeGraph.cpp:110,185`, `ValueFacts.cpp:266`,
  `Layout/Components.cpp:167`, `DataRemap.cpp:257`, `Target/Partition.cpp:234`,
  `EliminateDuplicateFunctions.cpp:126`, `Expect/Cycles.cpp:34`) as
  consumer adaptations; `include/idr/Support/{Scc,Worklist}.h`,
  `lib/Support/Scc.cpp`.
- *Outcome*: §2.2; `support::trace` (§4 I3).
- *Deletes*: `Scc.{h,cpp}`; `MonotoneWorklist`, `FiniteLattice`.
- *Must not*: change any analysis's answer; list ops in a concept.
- *Acceptance*: `components` against reachability on every graph of up to
  five nodes; every changed client's tests pass unchanged; raw-integer
  indexing of an `IndexVector` does not compile (a negative compile test).

**W5. The program graph, and every reader cut over.**
- *Write*: `include/idr/Solver/ProgramGraph.h`, `lib/Solver/ProgramGraph.cpp`;
  readers: `Contify.cpp`, `Optimize.cpp` and `ReadySet.cpp` (the ready set
  over graph ids, no second walk), `Specialize/Report.cpp`,
  `Tail/Frames.cpp:349-358`, `Stack/Stack.cpp:118-311`,
  `Ownership/Borrows.cpp:165-299` (until W9 replaces it),
  `Transforms/Contracts/Contracts.cpp:190-250` (the rebuild-and-compare
  contract), `Expect/Continuations.cpp:26`; `unittests/Cycles.cpp`
  retargeted; deleted: `include/idr/Analysis/{CallCycles,Recursion}.h`,
  `lib/Analysis/{CallCycles,Recursion}.cpp`. The `keeps | edits |
  invalidates` field in the pass records is L03's to generate. Until it
  lands, each pass marks it by hand in the same change (a seam, not a
  shim: L03's generator replaces the hand calls in its own unit).
- *Outcome*: §2.1, with contify editing and the graph born where
  defunctionalization's unit (L18) wires it.
- *Deletes*: §2.10's call-graph part; the seven user maps but Returned's
  and TailCallPlan's (with W8 and L10).
- *Must not*: hold `Operation *` call sites; let a frozen graph be edited;
  read the graph across `idr-lower`.
- *Acceptance*: the property of `unittests/Cycles.cpp` (SCCs against
  reachability over every 3-function graph, tail and non-tail self calls)
  on the new type; the contract finds no difference after any pass on the
  suites; `make test` and `make test-idr` unchanged.

**W6. Shape S, static and incremental.**
- *Write*: `include/idr/Solver/Summaries.h`, `lib/Solver/Summaries.cpp`
  (`solve<CalleesFirst|CallersFirst>`, dependency-count tasks,
  `reSolveUpward`).
- *Outcome*: §2.5's static S schedule; §4 I2's re-derivation. First
  clients are other lanes' units: rows' transfer (L02), their first solve
  in defunctionalization (L18), lifetimes (L05).
- *Must not*: iterate by count; create attributes on workers (§4 I8).
- *Acceptance*: the answer table is identical at one thread and many on
  every graph of up to five nodes with a random monotone transfer (DP-34);
  a re-derivation after a removed crash reaches exactly the callers whose
  rows change.

**W7. Shape G: extract, link, solve, write back.**
- *Write*: `include/idr/Solver/Extraction.h`, `lib/Solver/Extraction.cpp`
  (per-function arrays at base offsets, the one walk-order template used
  by both extraction and write-back, the `Open<Question>` domain type of
  §3).
- *Outcome*: the template L07 (stack), L08 (exclusivity, borrows) and L18
  (labels, dedup) instantiate.
- *Must not*: key state by `Value` or `Operation *`; skip a unit.
- *Acceptance*: a toy marking over the template agrees with a direct BFS
  on random programs (search, L19's harness); extraction and write-back
  visit values in the same order (asserted by construction: one template).

**W8. Ranges per function with summaries.**
- *Write*: `include/idr/Analysis/Ranges.h`, `lib/Analysis/Ranges.cpp`,
  `lib/Transforms/Narrow/{Narrow,Facts}.cpp` (with L12).
- *Outcome*: DP-51's form after M3b. Upstream's `IntegerRangeAnalysis`
  per function, return ranges callees first, argument ranges callers
  first, the re-solve after versioning only for the versioned functions.
- *Deletes*: `Ranges::Solved`'s whole-program solver,
  `Narrow.cpp:154-165`'s invalidate-and-resolve (05 RA2, RA3, AM4).
- *Must not*: refuse or fail on a range.
- *Acceptance*: every narrowing on the corpus that today's solve permits
  still happens, or the difference is listed and explained by widening
  inside a recursive SCC (05 QA2).

**W9. The optimizer's analyses on graph ids.**
- *Write*: `lib/Analysis/{BindingTimes,Identities,IdentitiesRecord,IdentitiesRebuilds,Inline}.cpp`,
  `include/idr/Analysis/{BindingTimes,Identities,Inline}.h` (with L18,
  whose unit owns `Transforms/Optimize/*`).
- *Outcome*: Identities over SCC ids, its answer the carried "gives back"
  per field path (§4 I13; L10 owns the property's definition);
  BindingTimes monovariant if the remarks agree (§4 I9); inline facts as
  a sum with the size kept.
- *Deletes*: 05 BT1-BT9, ID1-ID7, IN1-IN4.
- *Acceptance*: `idr-binding-times` remarks and the optimizer's statistics
  (`identityCalls`, `inlined`, `made`) equal on the corpus, or each
  difference explained.

**W10. The measurements.**
- *Write*: none in the compiler. The census pass and the footprint record
  are 13 T5's (S1). The record goes where the stage-1 records live.
- *Outcome*: §2.6's M3a-M3e taken and recorded; §4 I4 decided.
- *Acceptance*: every number carries commit, build, assertions, target,
  threads, input digest and counter.

**W11. Upstream: SCCP's rewrite exported.**
- *Write*: `upstream/<NN>-sccp-rewrite-export/*`, its test, `PINS.md`,
  `lib/Transforms/Effects/Constants.cpp`.
- *Outcome*: upstream's `rewrite` over a `RewriterBase` with a listener;
  our actions wrap it (05 CO1, 06 C-1).
- *Deletes*: `Transforms/Effects/Constants.cpp:73-169`.
- *Acceptance*: idr-constants' statistic `constants` equal on the corpus.

---

## 6. Owner questions

**OQ1. What a function's effect row means between two passes: an upper
bound or the exact row.** This concerns AGENTS.md's "held to it by the
verifier" (§4 I2). Equality checked after *every* pass is not satisfiable
across upstream's canonicalizer, which deletes effectful dead cases with
no hook of ours (`MatchPatterns.cpp:1-5`; `Pass.cpp:618-642`).
- *(a) Cover after every pass; equal right after each re-derivation*
  (after each optimizer component, before lowering). Buys: today's check
  kept, no extra steps, exact rows wherever LLVM or a summary reads them.
  Costs: between a fold and the next re-derivation a row may name an
  effect its body no longer has. CSE and dead-code removal are a little
  less free there. Nothing is unsound.
- *(b) Equal at every pass boundary.* A re-derivation step follows every
  group that can delete code, and the verifier's row check moves to after
  that step. Buys: rows exact everywhere (D18's lossless reading). Costs:
  a program-level step after every canonicalize group (incremental,
  *conjecture*: small), and the row check is no longer literally after
  every pass.
- *Recommendation*: (a). The precision (b) adds lives only between a fold
  and the next re-derivation, where no LLVM attribute is written, and (a)
  keeps the check after every pass.

HEAD at finish: `e96bb991` (2026-10-21; unchanged, so every anchor above
stands).
