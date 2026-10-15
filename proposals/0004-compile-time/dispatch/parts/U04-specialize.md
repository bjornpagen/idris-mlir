# U04 — Specialization as content-keyed nodes of the ready set

## Permitted outcome
1. Mandatory. `idr-specialize` is gone as a pass; specialization and
   arity raising are requests the inner pipeline's `idr-redirect` makes of
   `idr::specialize::Nodes`, each key's node built once by `Nodes::build`
   and run by the ready set like any function (C09 sections 4 to 6,
   C07 §5.3).
2. Mandatory. Every node is named `<owner>.spec.<hex16>` or
   `<callee>.raise.<hex16>` from its key by C21's helper; no counter,
   insertion order or thread reaches a key, a name, a body or a place
   (D18).
3. Mandatory. The clone budget is `kKeysPerOwner = 1024`, the distinct
   keys one function requests of one owner in call-site order; a key past
   it is not requested and its call stays; nothing in the lane emits
   `unsupported` (D39, D17).
4. Mandatory. Raising is first-order: its consumer is the dispatch, a
   match on a value of a data type of kind closures, keyed by the callee
   and the consumer's printed form (C09 section 5).
5. Mandatory. `BindingTimes` and `Identities` are filled per component by
   `solve` and read frozen (D47); a node's binding times are its owner's,
   written by its build; both read C01's data types and no symbol table.
6. Mandatory. `idr-binding-times` reports `bindingTimesOf`, component by
   component; `idr-redirect` runs only inside `idr-optimize` and says so
   as an internal error elsewhere.
7. Consumer adaptations inside the lane only: every unit of
   `lib/Transforms/Specialize/` and the analyses move from `ClosureOp`,
   `ApplyOp`, `ClosureAttr`, `DataOp` and `CtorOp` to C01's data types,
   C02's constructor references and C06's dispatch.

## Owner / exclusive writes
- `IDR/Transforms/Specialize` (`foreign/idr/lib/Transforms/Specialize/`):
  `Specialize.cpp` becomes the node table `Nodes`; `Keys.cpp`, `Patterns.cpp`,
  `Consumer.cpp`, `Raise.cpp`, `Specialization.cpp`, `Redirect.cpp`,
  `RedirectPass.cpp`, `Report.cpp` rewritten; `Clones.cpp` deleted.
- `INC/Transforms/Specialize.h`: C09 section 4 and the `detail` part.
- `IDR/Analysis/Specialize.cpp`: deleted (it held `CloneTable`).
- `INC/Analysis/Specialize.h`: `BindingTime`, `nameOf`, `BindingTimes`,
  `bindingTimesOf`.
- `IDR/Analysis/BindingTimes.cpp`: `solve` per component, `inherit`.
- `IDR/Analysis/Identities.cpp`, `IDR/Analysis/IdentitiesRecord.cpp`,
  `IDR/Analysis/IdentitiesRebuilds.cpp`, `INC/Analysis/Identities.h`:
  `solve` per component.

**Excluded:** `INC/IR/IdrAttrs.td`, `INC/IR/IdrOps.td`, `INC/IR/Symbols.h`,
`IDR/IR/Symbols.cpp`, `IDR/IR/Func` (U01: the key attributes, the `clone`
property and its verifier, `Elimination`); `INC/Transforms/Optimize.h`,
`IDR/Transforms/Optimize`, `IDR/Transforms/Identity`,
`IDR/Analysis/Inline.cpp`, `INC/Analysis/Holds.h`, `INC/Support/Scc.h`
(U03); `INC/Analysis/Effects.h` and `IDR/Analysis/Effects.cpp` (U05);
`INC/Transforms/Passes.td`, `INC/Support/Actions.h` (U06);
`IDR/Transforms/Ownership`, `IDR/Transforms/Tail`,
`IDR/Transforms/Deduplicate`, `IDR/Transforms/Expect` (U08, U09, U16, U17:
their `removeCloneAttr` and `copiedFrom` sites); `tests/idr` (U17); every
`CMakeLists.txt` (coordinator).

## Read first
- `contracts.md`: C09 whole; C01 (identified types, constructors by name,
  kinds), C02 (call-site effects), C06 postconditions 1 to 3, C07 and C08,
  C10 sections 3 and 7, C12 rows `IdrRedirect` and `IdrBindingTimes`, C21.
- 0004 `README.md`: §2.5 (budgets), §2.7 (specialization on known
  constructors, Raise's closure cases), §4 stages 6, 7, 8 and the
  determinism rules (lines 808-931, 1018-1024), §6 rows at lines 1246-1248
  and 1265, D14, D15, D18, D39, D45, D47.
- `sources/notes/compile-pipeline/mojo.md` §4 and
  `sources/code/modular/Mojo/lib/Elaborator/Elaborator.cpp:1675-1693,
  2944-2989` (nodes by content, order restored by name).
- Today's lane: `include/idr/Transforms/Specialize.h:56-243`,
  `include/idr/Analysis/Specialize.h:26-134`,
  `lib/Transforms/Specialize/Keys.cpp:1-197`, `Patterns.cpp:1-263`,
  `Specialization.cpp:46-135`, `Raise.cpp:35-214`, `Consumer.cpp:26-62`,
  `Redirect.cpp:18-56`, `RedirectPass.cpp:39-136`, `Clones.cpp:20-110`,
  `Specialize.cpp:44-82`, `lib/Analysis/BindingTimes.cpp:63-286`,
  `Identities.cpp:20-116`, `IdentitiesRecord.cpp:80-347`,
  `IdentitiesRebuilds.cpp:147-158`.
- Consumers: `lib/Transforms/Identity/Identity.cpp:29-63`,
  `lib/IR/Symbols.cpp:134-154`, `lib/IR/OpsCon.cpp:83-94`,
  `lib/Transforms/Defunctionalize/Patterns.cpp:89-165` (the dispatch).
- `M/include/mlir/IR/OperationSupport.h` (`OpPrintingFlags`),
  `M/lib/IR/SymbolTable.cpp:483-497` (symbol uses are checked at the
  module only), `M/include/mlir/Pass/AnalysisManager.h`
  (`getCachedParentAnalysis`), `L/include/llvm/Support/xxhash.h:58-70`.

## Fixed decisions
- A key is C02's dialect attribute (`SpecKeyAttr` over `KeyHoleAttr`,
  `KeyConAttr` and scalar constants; C09's `KeyRaiseAttr`), held by the
  node table only; no op carries a key or a clone fact.
- A pattern's type is its position's: the owner's parameter, or the field
  of the enclosing constructor in its data type's body. The key holds no
  type.
- A node's body is built from its key and its owner's final body alone;
  every op the build creates takes a location of the owner's body (the
  replaced parameter's, the terminator's), never a requester's. A raise
  node's consumer is parsed back from the key's form.
- The table is a module analysis `idr-optimize` takes; its mutable state
  is behind one pointer and one mutex; `idr-redirect` reaches it with
  `getCachedParentAnalysis`.
- A call is requested only when its callee is final
  (`Schedule::isFinal`); raise first, then spec, by one `decide`.
- A node's binding times are written once, by its build, from its
  owner's; `solve` fills only the members that have none.
- A node's function has no `effects` until C10 writes its entry; a call of
  a final node takes that entry.
- The redirect step is one pre-order walk, not a greedy pattern set: its
  order is the call-site order the budget counts in.

## Inputs
- C01: `DataType` (`getName`, `getCtors`, `getCtor`, `getTag`,
  `isClosures`, `isMemo`), `Ctor` (`name`, `fields`), `dataTypeOf`,
  `Elimination`.
- C02: constructor references by `FlatSymbolRefAttr`,
  `ConOp::create(b, loc, type, ctor, fields)`; the key attributes that
  stay; call-site `effects` verified equal to the callee's entry.
- C06: postconditions 1 to 3 (the dispatch).
- C07: `ReadySet` implementing C09's `Schedule`; the calls of C07 §6 at
  the points it names.
- C10: `idr::writeCallEffectsOnReady` runs before `solve`; a node's entry
  is absent until `idr::writeEntriesOnFinal`.
- C12: the `IdrRedirect` and `IdrBindingTimes` rows; no `IdrSpecialize`.
- C21: `contentName(owner, kind, key)` in `idr/IR/Symbols.h`.
- `Holds::mayHoldWorld`, `idr::onlyAllocates`, `idr::isWorld`,
  `idr::isLinear`, `idr::unrestricted`, `idr::stronglyConnected`
  (C07 §2), `support::perform` (`Actions.h:46`).

## Outputs
- C09: `include/idr/Transforms/Specialize.h` (`Nodes`, `Node`,
  `Schedule`, `kKeysPerOwner`, the two actions, the two pass
  declarations), `include/idr/Analysis/Specialize.h` (`BindingTime`,
  `nameOf`, `BindingTimes`, `bindingTimesOf`),
  `include/idr/Analysis/Identities.h` (`Identities`). Consumers: U03 (the
  ready set, idr-identity), U05, U06, U17, U18.

## Implement
- `Specialize.h` (Transforms): C09 section 4, then
  `namespace idr::specialize::detail` with `Pattern` (Hole, Constant,
  Con, Linear), `Argument`, `Composed`, `Consumer` (`idr::Elimination`),
  `Want` (a key, its owner, the new call's operands, a raise's consumer),
  `shapeOf`, `leafOf`, `rebuild`, `holeTypes`, `countHoles`, `renumber`,
  `hasStructure`, `unrollSize`, `isClosed`, `usedOnce`, `eraseUnused`,
  `keyOf`, `composeKey`, `consumerOf`, `consumerFunction`, `formOf`,
  `decide`, `buildSpec`, `buildRaise`, `redirect`.
- `Specialize.cpp`: `Nodes`. Its state: the mutex, the `Schedule`,
  `BindingTimes` and `Holds` pointers, nodes by key (`MapVector`) and by
  name, per requester the nodes asked in order and the keys counted per
  owner, the claimed set. A request counts, names (`contentName`), checks
  the name against the table and `Schedule::lookup` (internal error), and
  records. `build` dispatches on the key, writes the binding times, runs
  `redirectCalls`. `insert` places after the owner, past the nodes whose
  names sort before. `redirectCalls`: C09 section 6, with a rewriter
  listener recording erased ops.
- `Keys.cpp`: `keyOf` (constants expanded as `keyOfConstant` does, a
  nested constant's type its field's in C01's body), `composeKey` as today
  with `specializesOn` reading the closures kind, `own` the callee's spec
  key, `fill` over its patterns; no `KeyClosure`.
- `Patterns.cpp`: today's file without the closure cases; `rebuild` reads
  a key pattern, a position type and a location.
- `Consumer.cpp`: `consumerOf(call, holds)`, `consumerFunction`, `formOf`,
  `decide`.
- `Specialization.cpp`: `buildSpec`, today's `Specializer::substitute`
  over the key's holes.
- `Raise.cpp`: `buildRaise`, today's `push` and `retyped` with the parsed
  consumer inlined at each tail; `labelOf` goes.
- `Redirect.cpp`: `redirect(rewriter, call, target, effects, want)`: the
  new call returns what the replaced op did; the steps, the call and the
  shapes no op uses go.
- `RedirectPass.cpp`: `idr-redirect` over `Nodes::redirectCalls`.
- `Report.cpp`: `idr-binding-times`: the components of the module's direct
  calls (`idr::stronglyConnected`, module order), `bindingTimesOf` on
  each, one remark per function as today.
- `BindingTimes.cpp`: `BindingTimes` and `bindingTimesOf`; the
  `Interpreter` follows the `idr.call`s between members.
- `Identities*.cpp`: `Identities::solve`; `Record` takes the members by
  name instead of the symbol table; the type facts (`memoType`,
  `remaining`, `singleCtor`, a fieldless constant) from C01; the
  assumptions are the members' candidates and the frozen answers of
  callees outside.
- Failure paths: an internal error is a diagnostic at the call or the
  owner's function and a failed `LogicalResult`; no assertion stands in
  for one.

## Delete
- `idr-specialize`'s pass and its generation loop (`Specialize.cpp:30-137`),
  `Specializer`, `Statistics`, `Call`, `Entry`, `Slot`.
- `Clones.cpp` whole: `makeClone`, the `unsupported (compile-time budget)`
  error, the `.spec<n>`/`.raise<n>` counter names, `giveFirstFacts`,
  `canonicalizeAndCollect` (the second canonicalization configuration and
  pattern set), `settle` and its `no_inline` juggling.
- `CloneTable`, `Clone`, `kClonesPerOwner` and its comment calling it the
  check of a finiteness argument; `lib/Analysis/Specialize.cpp`.
- Reading and writing the self-referencing `CloneAttr`
  (`Specialization.cpp:125-128`, `Raise.cpp:175`), and every use of
  `KeyClosureAttr`, `KeyApplyAttr` and `KeyApplyFieldAttr`.
- The round's facts read through `getCachedParentAnalysis` from
  `RoundFacts` (`RedirectPass.cpp:8-12, 104-117`).
- The closure cases: `Closure` patterns, `ClosureOp`/`ClosureAttr` in
  `shapeOf`, `rebuild`, `labels`, `hasStructure`, `isClosed`,
  `constantSize`, `keyOfConstant`, `labelOf`; `BindingTimes`' closure
  sites and raised-clone inheritance (`BindingTimes.cpp:177-183, 214-285`).
- `lookupData`, `lookupCtor`, `DataOp`, `CtorOp`, `isMemo` in
  `IdentitiesRecord.cpp` and `IdentitiesRebuilds.cpp`; the
  `SymbolTable &` in `Identities::Record`.
- The debug-counter remark in comments ("a debug counter may skip");
  actions stay.

## NOT TO DO
- No `clone` or key fact on any op, no new attribute in `IdrAttrs.td`
  (U01's), no edit of `Symbols.h`; report what C01 lacks.
- No pass option, no mode, no second key composition for "the module's
  own clones", no owner-wide counter, no counter name.
- No refusal: no `unsupported`, no `compile-time budget`; a spent budget
  leaves the call.
- No scheduling: do not write the ready set, its waiting or its threads
  (U03); do not read the call graph or `References` in the redirect step.
- No effects computation (C10 is the one home): no `giveFirstFacts`, no
  union of label effects, no `Effects::declared`.
- No canonicalization inside the lane: a node is cleaned by the ready
  set's inner pipeline (U03); no `applyPatternsGreedily` here.
- No edit of `Passes.td` (U06), `Identity.cpp` (U03), any test (U17,
  U18) or build list (coordinator).
- Do not keep `idr-in-bounds`, `LoopBreakers`, `break_last` or the
  rounds alive through a call from this lane.

## Tempting partial solutions
- Keeping `CloneTable` and naming clones `<owner>.spec.<hash>` while the
  generation loop stays: rejected by outcome 1 and by the ready set's
  one-pass order (a clone made in a generation would be simplified by a
  second configuration).
- Building a node from the first requester's patterns (their locations,
  their leaf values): two schedules then write different locations;
  rejected by determinism at 1, 2 and 8 threads.
- Counting the budget owner-wide as requests arrive: which call stays
  unspecialized would follow the schedule (D39); rejected by the budget
  fixture's determinism.
- Turning a spent budget into `unsupported`: rejected by AGENTS.md and
  D17; the budget fixture compiles and runs.
- Raising any match on a call's result: keys from an unbounded space and a
  clone per consumer of every data result; rejected by the termination
  invariant of C09 section 9.
- Keying a raise by the dispatch's sum type and arity and rebuilding the
  dispatch: the arms after cleanup are not the sum's alone, and the
  coercions are U02's; rejected by section 5's form.
- Re-solving binding times for the whole module per request, or keeping
  `RoundFacts`-style caches: rejected by D47's one home per fact.

## Acceptance
- `python3 proposals/0004-compile-time/check-units.py` on every `.cpp`
  the lane leaves: no failure but those that name a C01, C07, C10 or C21
  declaration not yet in the tree, each reported as a seam.
- Source review: `grep -rn 'CloneTable\|CloneAttr\|getCloneAttr\|KeyApply\|KeyClosure\|kClonesPerOwner\|ClosureOp\|ApplyOp\|ClosureAttr\|lookupData\|lookupCtor\|DataOp\|CtorOp\|unsupported\|applyPatternsGreedily\|Twine(n)\|\.spec"\|\.raise"' foreign/idr/lib/Transforms/Specialize foreign/idr/lib/Analysis/BindingTimes.cpp foreign/idr/lib/Analysis/Identities*.cpp foreign/idr/include/idr/Transforms/Specialize.h foreign/idr/include/idr/Analysis/Specialize.h foreign/idr/include/idr/Analysis/Identities.h`
  prints nothing.
- `lib/Transforms/Specialize/Clones.cpp` and `lib/Analysis/Specialize.cpp`
  do not exist.
- On the owner's machine (NEEDS-ACCEPTANCE through U17's fixtures):
  `tests/idr/specialize/budget` with 1,025 distinct requests of one owner
  from one node compiles, the 1,025th call stays a call of the owner,
  and the program runs; `names/reorder` and `names/edit` keep every
  `.spec.`/`.raise.` symbol; `tests/idr/specialize/binding-times`' remarks
  are today's; `tests/idr/raise/io-loop` ends in an `scf.while` after
  `idr-tail-loops`; the debug-counter fixture's skipped
  `idr-specialize-clone` leaves a call of the original; `tests/determinism`
  at 1, 2 and 8 threads.

## Stop and return
Return the common obligations' handoff when the units above are written
and check-units.py has run on them. Report without stopping: every C01,
C07, C10 and C21 name the code uses that the tree lacks (file, line,
contract); the build-list lines (remove `Specialize.cpp` from
`IdrAnalysis` and `Specialize/Clones.cpp` from `IdrSpecialize`); any
consumer outside the lane that still reads `CloneTable`, `CloneAttr` or the
key attributes.
