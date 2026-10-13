# U12 — Bounds proofs as a Lengths analysis and per-function proving

Mandatory findings: none

## Permitted outcome

1. **`idr::Lengths`.** An analysis of the module under the pass manager,
   constructed `(Operation *, AnalysisManager &)`, declared in
   `INC/Analysis/Lengths.h`. It holds what a proof needs of the whole
   module: the ranges of the interprocedural solver, the calls and the
   returns of each `idr.func`, what each call gives back, and whether the
   pairs bound at a function's or a call's interface are related. It is
   immutable once built and is read from the function passes' threads.
   Mandatory.
2. **`idr-in-bounds` proves per function.** The module pass computes
   `Lengths`, runs one `idr.func` pass over every function through
   `Pass::runPipeline`, and keeps its two statistics. The function pass
   reads its own function, `Lengths` and the parent `SymbolTable`, and
   nothing else of the module. Mandatory.
3. **The same proofs.** Every guard proved at 25890d32 on
   `T/idr/in-bounds/*` is proved; every guard kept there is kept; a proof
   is the guard's erasure, as today. Mandatory.
4. **The Presburger system stays.** No part of the proving moves to
   `ValueBoundsConstraintSet` (Fixed decisions). Mandatory.
5. **Consumer adaptation.** `accessedArray` and `guardedArray` are
   declared in `INC/Analysis/Lengths.h`, which `idr-expect` includes for
   its `bounds-checked` property (U15). Mandatory.

## Owner / exclusive writes

- `IDR/Transforms/InBounds` (new): the thirteen `.cpp` of `IdrInBounds`,
  listed in Implement.
- `INC/Transforms/InBounds.h` (new): the library's header: the
  constraint system and what adds constraints to it.
- `INC/Analysis/Lengths.h` (new): the analysis, its per-function
  question, and the relation's vocabulary.
- `IDR/Analysis/Lengths.cpp`: owned and left unwritten; the definition
  of `Lengths` is `IDR/Transforms/InBounds/Lengths.cpp` (Escalate if,
  item 1).
- `IDR/InBounds` (deleted): the fifteen files of today, Delete.

**Excluded:**

- `INC/Transforms/Passes.td` (`IdrInBounds`, its statistics) and every
  `CMakeLists.txt`: the coordinator's.
- `IDR/Transforms/Expect` and `INC/Transforms/Expect.h`: U15's. It
  includes `idr/Analysis/Lengths.h` for `accessedArray`.
- `IDR/Transforms/Narrow` and `INC/Transforms/Narrow.h`: U11's. The
  solver glue `idr::narrow::runSolver` and `idr::narrow::rangeOf` is
  consumed, never copied.
- `IDR/Transforms/Pipeline.cpp`: U14's; it keeps `idr-in-bounds` after
  `idr-narrow` and before `idr-lower` (C1.4).
- The guards' folders (`IDR/IR/Fold`, U16) and canonicalizations
  (`IDR/IR/Canon`, U17); the guards' lowering (`IDR/Conversion`, U10);
  `arrayRoot` and `isRank1Array` (`IDR/IR`, U01).
- Every fixture: `T/idr/in-bounds/*` and `T/idr/guards/*` are U21's;
  `T/programs/arrays/*` and `bench/` runs are U22's and the coordinator's.

## Read first

- `contracts.md` C0, C1.1, C1.3 (`idr-in-bounds`), C1.4, C2.0, C2.1
  (`Lengths`), C2.2, C4, C9.1.
- `findings.md` F-pass-1, F-pass-5, F-state-1, F-state-4 (the evidence
  for module passes that rebuild what they need).
- Every file of `IDR/InBounds/`, whole: `InBounds.cppm` (the map of the
  parts, :1-19), `Pass.cc`, `Prove.cppm` (`prove(ModuleOp)` :145-172;
  `provenInBounds` :45-85; `checkedBefore` :90-97; `provenByRanges`
  :103-136), `System.cppm` (wrapping :17-21, :284-289; `nsw` :296-298;
  `rangeOf` :127-141; `emptyWith` :235-252), `Linear.cppm`,
  `Lengths.cppm` (`related` and its hops :102-120; `clampsEqual` to
  `eachEdge` :144-216; `needsOf` :219-262; `solve` :277-313; the members
  :315-325), `Returned.cppm` (`Origin` :36-67; the fixpoint :138-182;
  `given` :187-206; `callOrigin` and its rewalk :336-366; the scratch
  members :383-390), `Components.cppm` (`pairFields` :73-103; `expand`
  :108-157), `Joins.cppm` (`Calls` :93-143; `argumentJoin` :179-201;
  `resultJoin` :203-226), `Paths.cppm` (`knownAt` :168-177; `pathFacts`
  :180-189), `Induction.cppm` (:157-183, :191-255), `Masks.cppm`
  (`relateMask` :215-241), `Quotients.cppm` (:73-77), `Guards.cppm`,
  `CMakeLists.txt` (:20-24, what the library links).
- `INC/Passes.td:395-445` (`IdrInBounds`: the description is the pass's
  specification; :433-437 the proof is the guard's absence; :441-444 the
  statistics).
- `INC/IdrOps.td:944-1036` (Guards: `GuardOpInterface` :950-958; the
  proof is the absence of the guard :965-968; `Idr_CheckOp` :971-986;
  `Idr_CheckInBoundsOp` :997-1003).
- `IDR/Narrow/Naturals.cppm:17-64` (`NaturalRanges`, `runSolver`,
  `rangeOf`: the one read of the lattice, :56-58).
- `IDR/Expect/InBounds.cppm:36-39, 54-87` (the consumer of
  `accessedArray`; the three properties).
- `IDR/Dialect/Registration/PipelineSteps.cc:37-41` (the pass's place).
- `INC/Idr.h:267, 284` (`isRank1Array`, `arrayRoot`).
- `sources/code/mlir/include/mlir/Analysis/DataFlowFramework.h:350-360`
  and `:767-778` (`lookupState` and `getLeaderAnchorOrSelf` are `const`
  reads: a finished solver may be read from several threads).
- `sources/code/mlir/include/mlir/Analysis/Presburger/IntegerRelation.h:341-347`,
  `:432`, `:991-1009` and `PresburgerSpace.h:170` (what `System` uses).
- `sources/docs/mlir/docs/PassManagement.md:29-46` (an operation pass
  inspects no sibling and keeps no state) and `:459-495` (dynamic
  pipelines: `runPipeline` on the current operation).
- `sources/code/mlir/include/mlir/Interfaces/ValueBoundsOpInterface.td:14-60`
  (index-typed values and shaped dimensions; entry-block arguments
  only).
- The survey item 2, `git show f2d6df36:findings/mlir-survey.md`, lines
  134-176 (`ValueBoundsOpInterface` for array indices; Risk :161-168;
  Moves :169-176).
- `tests/idr/in-bounds/*.mlir`, the RUN lines and the comment at the
  head of each: they say in words which guards go and which stay.

## Fixed decisions

- **The split.** `idr-in-bounds` is a `ModuleOp` pass (C1.3) with two
  jobs: `getAnalysis<Lengths>()`, then a nested pipeline
  `OpPassManager pm(ModuleOp::getOperationName()); pm.nest<idr::FuncOp>().addPass(createProveInBoundsPass())`
  run with `runPipeline(pm, getOperation())`. The nested pass,
  `ProveInBounds : PassWrapper<ProveInBounds, OperationPass<idr::FuncOp>>`,
  is internal: not in `Passes.td`, no argument, constructed only by the
  module pass. Every proof and every erasure happens in it. The verifier
  of each function follows it, as the dynamic pipeline inherits
  verification.
- **What the function pass reads of the module.** Exactly two parent
  analyses: `getCachedParentAnalysis<Lengths>()` and
  `getCachedParentAnalysis<SymbolTable>()`. Either absent is an internal
  error (`emitError` on the function, `signalPassFailure`): the pass ran
  outside `idr-in-bounds`. The `SymbolTable` resolves an `idr.call`'s
  callee to the `idr.func` that keys the tables of `Lengths`. The pass
  reads no other function's body, signature or attributes, walks no
  symbol uses, and runs no solver. `DominanceInfo` is its own function's,
  `getAnalysis<DominanceInfo>()`.
- **Why `Lengths` is eager and immutable.** Today the relation is solved
  lazily per question with shared memo (`Lengths.cppm:116-119`,
  :144-155), the returned arrays are solved on first use (:133-137), the
  returns are cached on first ask (`Joins.cppm:132-137`), and a question
  follows joins into callers' call operands and callees' return
  operands (`Joins.cppm:184-192`, :212-219). A function pass may do none
  of that while sibling passes erase guards. So every cross-function
  fact is computed once, in the constructor, and the per-function
  question keeps its memo in an object of its own.
- **The API of `Lengths`** (`INC/Analysis/Lengths.h`, namespace `idr`):

  ```cpp
  class Lengths {
  public:
    Lengths(mlir::Operation *module, mlir::AnalysisManager &am);
    // Preserved by none (C2.1), and stale when the symbol table it was
    // built with is.
    bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa);
    // The range the module's solver recorded for `value`; none where the
    // analysis never reached it, which proves nothing.
    std::optional<mlir::ConstantIntRanges> rangeOf(mlir::Value value) const;
    // The calls of a private function every use of which is a direct
    // call; null for any other function.
    const llvm::SmallVector<CallOp> *callsOf(FuncOp fn) const;
    llvm::ArrayRef<ReturnOp> returnsOf(FuncOp fn) const;
    // What result `slot` of `fn` gives back (Fixed decisions, Origin).
    const Origin &given(FuncOp fn, unsigned slot) const;
    // Whether the pair bound at an interface holds everywhere it is bound.
    bool interface(const InterfaceKey &key) const;
    // The relation asked within one function, on that function's values.
    Local local(FuncOp fn, const mlir::SymbolTable &symbols,
                mlir::DominanceInfo &dominance) const;
  };
  class Lengths::Local {
  public:
    // Whether `array` has `max(size, 0)` elements wherever both are in
    // scope: today's `related`, hops over given-back arrays included.
    bool related(mlir::Value size, mlir::Value array);
    // The caller-side value `value` is, when a call gives it back.
    std::optional<GivenBack> givenBack(mlir::Value value);
  };
  ```

  `Lengths` holds the `DataFlowSolver` (one, interprocedural, as
  `Prove.cppm:146` builds it), the call sites, the returns, the
  returned-arrays table and the interface table. All of it is `const`
  after construction. `Local` holds every mutable thing: the pair
  graph's memo, the clamp cache, the scratch sets of the given-back
  walk. One `Local` per function per run, on that pass's thread.
- **The interface table.** A pair whose values are both bound at one
  non-local join is an interface pair. There are three kinds, each per
  `idr.func` and per side (its parameters, bound by its calls; its
  results, bound by its returns): `(size position, array position)`,
  `(size position, record position, field)` for a field of array type
  of one of the record type's constructors, and
  `(record position, size field, array field)` for two fields of one
  constructor. Positions are i64 for a size, array or `!idr.data` for
  the other. The constructor's declaration (`idr.data`, through the
  `SymbolTable`) gives the fields. Every key is enumerated and solved in
  the constructor, as today's greatest fixpoint, one question per key
  with today's `pairLimit` per question (`Lengths.cppm:69`, :281-284):
  a pair reached by an earlier question is settled. A record read out of
  another record is not followed, as today (`Components.cppm:130-132`:
  a field read is no join). Nested records need no table.
- **One pair graph, two drivers.** The graph has four node kinds: a size
  and an array; a size and the component `field` of a record; the two
  components of a record; an interface key. `needsOf` is today's
  `needsOf`, `expand` and `pairFields`, written once over these nodes.
  The graph a constructor builds expands an interface node into the
  local nodes of the callers (for parameters) or of the function (for
  results). The graph a `Local` builds treats an interface node as a
  leaf whose state is the table's. Nothing else differs.
- **The returned arrays record what every return built.** `Origin`
  gains a case `Built(ctor, fields)` beside `Unknown`, `None` and
  `Argument(index, path)`: a return of `idr.con @C(a, b)` is
  `Built(C, [origin(a), origin(b)])`, two `Built` of one constructor
  meet field by field, and a projection `(ctor, k)` of an `Origin`
  descends a `Built`, extends an `Argument`'s path, and leaves `Unknown`
  and `None`. With that, `given` on the caller side reads the table and
  its own function only; today's rewalk of the callee for a projection
  (`Returned.cppm:349-365`, `rewalking`) goes. The depth of a `Built`
  tree is bounded by today's `originLimit` through the existing `depth`
  counter (:250-258).
- **The ranges.** `Lengths`' constructor runs the solver as today
  (`DataFlowConfig().setInterprocedural(true)`, then
  `idr::narrow::runSolver`) and `rangeOf` is `idr::narrow::rangeOf` on
  it. `System`, `Induction` and `provenByRanges` take `const Lengths &`
  where they take `DataFlowSolver &` today, and call `rangeOf`. A
  solver that has run is read only through `lookupState`, which is
  `const`; no state is created at query time.
- **The calls.** The call sites of each private function come from one
  `SymbolTable::getSymbolUses(module)` walk in the constructor, bucketed
  by the symbol used: a function every use of which is an `idr.call`
  naming it has a list; any other use (a closure, a constant, a
  reference from a data declaration) leaves it without one, as today
  (`Joins.cppm:107-116`). The returns of an `idr.func` are the
  terminators of its body's blocks (`idr.return` has
  `HasParent<"FuncOp">`, C1.2), read once. `Calls::function`
  (`Joins.cppm:128`) goes: the `SymbolTable` analysis is the one map from
  a name to its function.
- **The Presburger system stays; `ValueBoundsConstraintSet` replaces
  nothing.** The rule, once: the system encodes a word's wrapping exactly
  (`System.cppm:17-21`, `wrapped` :284-289) and reads `nsw` (:296-298);
  the value-bounds infrastructure assumes its integer computations do
  not overflow, and the `arith` implementation reads no flag (survey
  item 2, Risk, :161-168; the header is upstream's
  `ValueBoundsOpInterface.h:62-64`, not in `sources/`). Idris's `Int`
  wraps, so an index through a plain `arith.addi` is unsound there, and
  a guard of ours that stops the query at an unflagged op would be a
  second encoding of the same arithmetic beside the first. Both decide
  by the same library: `System::emptyWith` is `IntegerPolyhedron`
  (`System.cppm:236`, `:251`), and the value-bounds set is a
  `FlatLinearValueConstraints` over it. What value bounds would add, an
  `scf.for` counter inside its bounds and a `memref.dim`, the system has
  (`Paths.cppm:127-135`, `System.cppm:332-336`). What it lacks, a
  `match_lit` case taken, a guard that ran before, an `scf.while`
  condition and the induction over its counters, quotients, masks and
  the length relation, is the proving. So `System`, `Linear`, `Paths`,
  `Induction`, `Masks` and `Quotients` move as they are. Conjecture,
  marked as such and not in this packet: a `ValueBoundsOpInterface`
  implementation on `idr.check.in_bounds` and `idr.array.new` would let
  upstream's folders answer the program's own `arith.cmpi` after the
  guard is proved, which is the survey's gain (Moves :169-176); that is
  an addition for a later packet, measured, never a replacement.
- **A guard's erasure is still the proof.** The 0002 packet's rule is
  the tree's: a proven guard is erased and its result replaced by its
  operand (`Passes.td:433-437`, `IdrOps.td:965-968`,
  `Prove.cppm:140-144`, :168-171). No attribute, no mark, no second
  representation of "proved". Those that hold in one function are
  erased together after the function's walk, as today, so each is
  judged on the function as it was.
- **Statistics and preservation.** The module pass counts the module's
  `GuardOpInterface` ops before and after the nested run: `numProved`
  gains the difference, `numChecked` gains the count after. The nested
  pass has no statistics. When the counts are equal the module pass
  calls `markAllAnalysesPreserved()`; otherwise it calls
  `markAnalysesPreserved<SymbolTable>()`: a guard is no symbol and names
  none. The function pass calls `markAllAnalysesPreserved()` when it
  erased nothing and `markAnalysesPreserved<DominanceInfo>()` when it
  did: erasing an op inside a block changes no block.
- **Order in the module pass.** `getAnalysis<Lengths>()` first, so the
  nested passes find it cached; then the count; then `runPipeline`; a
  failed pipeline is `signalPassFailure()`; then the count and the
  marks.
- **Limits.** Every number keeps its value and its comment:
  `pairLimit` 4096, `walkLimit` 64 and `edgeLimit` 64 of the relation
  (`Lengths.cppm:69-71`), `walkLimit` 64 of the record walks
  (`Components.cppm:28`, now the depth of a component node's chain), the
  64 hops of `related` (`Lengths.cppm:107`), `originLimit` 64
  (`Returned.cppm:27`), `definitionLimit` 96 (`System.cppm:42`),
  `quotientLimit` 96 (`Quotients.cppm:30`), `powerLimit` 96
  (`Masks.cppm:70`), `edgeLimit` 64 of induction (`Induction.cppm:45`).
- **Namespaces and names.** `idr::Lengths`, `idr::Lengths::Local`,
  `idr::Origin`, `idr::InterfaceKey`, `idr::GivenBack`. The proving
  classes keep today's names in `idr::inbounds`: `Linear`, `System`,
  `Bounds`, `CarriedBounds`, `Related`, `Induction`, `knownAt`,
  `pathFacts`, `relateQuotients`, `relateMask`, `accessedArray`,
  `guardedArray`, `componentOf`, `dimensionOf`, `clampOf`, `measured`,
  `positionIn`, `Join`, `joinOf`. `joinOf` takes `(Value, const
  Lengths::Local &)`: the `Local` holds the symbols and the tables a join
  needs.

## Inputs

- C1.2: `idr.func` (`getBody`, `isPrivate`, `isExternal`,
  `getArguments`, `getNumResults`), `idr.call` (`getCalleeAttr`,
  `getArgOperands`, `getResults`), `idr.return` (`getOperands`), through
  the generated accessors.
- C1.3: `idr-in-bounds` on `ModuleOp`; its constructor `createIdrInBounds`
  from the generated `Passes.h.inc`; the statistics `numProved` and
  `numChecked` as `Passes.td` declares them today (:441-444).
- C2.0: `getAnalysis<SymbolTable>()` in the analysis's constructor;
  `getCachedParentAnalysis<SymbolTable>()` in the function pass.
- C2.1: the shape of an analysis; `Lengths` preserved by none.
- U01's `INC/IR/IdrDialect.h`: `arrayRoot`, `isRank1Array`
  (`INC/Idr.h:284`, :267 today), `GuardOpInterface`, `CheckKind`, the
  check ops, `ArrayNewOp`, `ArrayGenerateOp`, `ArrayFoldOp`, `ConOp`,
  `FieldOp`, `TakeOp`, `MatchOp`, `MatchLitOp`, `LinUseOp`, `ShlOp`,
  `DivOp`.
- U11's `INC/Transforms/Narrow.h`: `idr::narrow::runSolver(DataFlowSolver &, Operation *)`
  and `idr::narrow::rangeOf(DataFlowSolver &, Value)`, the names of
  `Narrow/Naturals.cppm:48` and `:59`.
- Upstream: `mlir::PassWrapper`, `Pass::runPipeline`, `OpPassManager`,
  `DataFlowSolver`, `DominanceInfo`, `SymbolTable::getSymbolUses`,
  `IntegerPolyhedron`, `PresburgerSpace::getSetSpace`,
  `RegionBranchOpInterface`, `scf`, `arith`, `memref`, `ub`.

## Outputs

- `INC/Analysis/Lengths.h`: `idr::Lengths`, `idr::Lengths::Local`,
  `idr::Origin`, `idr::InterfaceKey`, `idr::GivenBack`, and in
  `idr::inbounds` the vocabulary `Component`, `componentOf`,
  `dimensionOf`, `clampOf`, `measured`, `positionIn`, `Join`, `joinOf`,
  `accessedArray`, `guardedArray`. Consumers: `IdrInBounds`; U15's
  `idr-expect` (`accessedArray`).
- `INC/Transforms/InBounds.h`: `idr::inbounds::Linear`, `power`,
  `widthOf`, `isColumn`, `Bounds`, `CarriedBounds`, `Related`, `System`,
  `knownAt`, `pathFacts`, `Induction`, `relateQuotients`, `relateMask`,
  and `std::unique_ptr<mlir::Pass> createProveInBoundsPass()`. Consumer:
  `IdrInBounds` alone.
- `idr-in-bounds`, registered by U14 from the generated constructor, at
  its place in C1.4.
- Hub text for the coordinator: `IdrInBounds` links `IdrIR`, `IdrNarrow`,
  `MLIRPresburger`, `MLIRAnalysis`, `MLIRPass`, `MLIRSCFDialect`,
  `MLIRArithDialect`, `MLIRMemRefDialect`, `MLIRUBDialect`; `IdrExpect`
  links `IdrInBounds`.

## Implement

`IDR/Transforms/InBounds/`, thirteen units, each at most 400 lines:

- `InBounds.cpp`: the `idr-in-bounds` module pass of Fixed decisions
  (`getAnalysis<Lengths>()`, the count, the nested pipeline, the count,
  the statistics, the marks). Takes `Pass.cc` and the shape of
  `Prove.cppm:145-151`.
- `Prove.cpp`: `ProveInBounds`, the function pass, and
  `createProveInBoundsPass`. Takes `Prove.cppm:45-136` as it is and
  :154-171 on the function: one `Lengths::Local`, one `Induction`, one
  `DominanceInfo`, the walk over the function's `GuardOpInterface` ops,
  the erasure of those that hold.
- `Lengths.cpp`: `idr::Lengths`: the constructor (the symbol table, the
  call sites from one `getSymbolUses`, the returns, the solver, the
  returned table, the interface keys and their fixpoint), `rangeOf`,
  `callsOf`, `returnsOf`, `given`, `interface`, `local`, `isInvalidated`.
  Takes `Lengths.cppm:91-98`, `Joins.cppm:93-143` and
  `Prove.cppm:146-150`.
- `Relation.cpp`: `Lengths::Local`: `related` with its hops
  (`Lengths.cppm:102-120`), `givenBack`, the pair graph with its four
  node kinds, `needsOf` (`Lengths.cppm:219-262`, `Components.cppm:73-157`
  folded in), `solve` (`Lengths.cppm:264-313`), and the interface leaf.
- `Clamps.cpp`: `clampsEqual`, `agrees`, `atPoint`, `eachEdge`
  (`Lengths.cppm:139-216`), as members of `Local`.
- `Joins.cpp`: `componentOf`, `dimensionOf`, `clampOf`, `measured`,
  `positionIn`, `joinOf` and its two halves (`Joins.cppm:28-87`,
  :150-236); the function and call cases read the `Local`'s tables.
- `Returned.cpp`: `Origin` with `Built`, the table's fixpoint
  (`Returned.cppm:138-182`), `given`, `fromCall`, `materialize`, `walk`,
  `argument`, `carried`, `callOrigin` without the rewalk, `meetIncoming`.
  The scratch sets live in `Local`.
- `Guards.cpp`: `accessedArray`, `guardedArray` (`Guards.cppm:21-47`).
- `System.cpp`: `power`, `widthOf`, `isColumn` (`Linear.cppm:43-62`) and
  `System`'s members (`System.cppm`), `rangeOf` through `Lengths`.
- `Paths.cpp`: `Paths.cppm` as it is.
- `Induction.cpp`: `Induction.cppm` as it is, over `const Lengths &`.
- `Quotients.cpp`: `Quotients.cppm` as it is.
- `Masks.cpp`: `Masks.cppm` as it is, `relateMask` over a
  `Lengths::Local &`.

Every `.cpp` includes `idr/IR/IdrDialect.h` first among ours, then its
own header, then the MLIR headers it uses by name (C1.1). Comments move
with the code and say why, as today's do; the header comments of the
old partitions become the comments of the new headers' declarations.

Failure paths: a missing parent analysis in `ProveInBounds` is an
internal error and fails the pass; a failed solver fails the module pass
(`Prove.cppm:147-148`, kept); a failed nested pipeline fails the module
pass. No `unsupported` is new: the pass proves or leaves a guard, never
rejects a program.

## Delete

- `IDR/InBounds/` whole: `InBounds.cppm`, `Pass.cc`, `Prove.cppm`,
  `System.cppm`, `Linear.cppm`, `Lengths.cppm`, `Returned.cppm`,
  `Components.cppm`, `Joins.cppm`, `Paths.cppm`, `Induction.cppm`,
  `Masks.cppm`, `Quotients.cppm`, `Guards.cppm`, and the lane reports
  that `IDR/InBounds/CMakeLists.txt` goes with them (the coordinator's
  file).
- The module `idr.inbounds` and its partitions, the `export module` and
  `import idr.` lines, and `Mlir.cppm` as their source of MLIR.
- `Lengths(ModuleOp, DataFlowSolver &)` and its lazy memo; `ReturnedArrays`
  as a lazily built member; `Calls` as a class and `Calls::function`;
  the `mutable` returns cache; `callOrigin`'s rewalk and `rewalking`.
- `System(DataFlowSolver &, …)` and `Induction(DataFlowSolver &, …)`:
  both take `const Lengths &`.
- `prove(ModuleOp)` and `Proved`: the module walk, the module-wide
  `DominanceInfo`, the erasure loop over the module.

## NOT TO DO

- Do not read another function in `ProveInBounds`: no `callsOf` on a
  caller's body, no walk of a callee's returns, no `SymbolTable::getSymbolUses`,
  no `DominanceInfo` of the module. Everything cross-function is a table
  of `Lengths`.
- Do not run a second solver per function, and do not make the solver
  intraprocedural: callers' ranges reach callees today.
- Do not record a proof anywhere but by erasing the guard: no
  attribute on a guard or an access, no `arg_attrs` fact on `idr.func`.
- Do not implement `ValueBoundsOpInterface` on any idr op, and do not
  call `ValueBoundsConstraintSet` (Fixed decisions; a later packet).
- Do not copy `NaturalRanges`, `runSolver` or `rangeOf` from U11's area;
  include its header.
- Do not register `ProveInBounds` in `Passes.td` or give it an argument;
  do not give it statistics.
- Do not add a limit, a budget or a depth, and do not change a kept
  one's value.
- Do not change which guards are proved: no new encoding in `System`,
  no new path fact, no new relation. The fixtures of `T/idr/in-bounds`
  are the specification.
- Do not write under `IDR/Transforms/Expect`, `IDR/Transforms/Narrow`,
  `IDR/IR`, `IDR/Conversion` or `T/`; report the seam.
- Do not define `Lengths` in two libraries, and do not write
  `IDR/Analysis/Lengths.cpp` while Escalate item 1 stands.

## Stop and return

You are done when `IDR/InBounds/` is gone, the thirteen `.cpp` and two
headers above exist, `idr-in-bounds` builds its `Lengths` and nests
`ProveInBounds`, and nothing in `IDR/Transforms/InBounds/` reads a
sibling function from the function pass. Return the changed paths mapped
to the five outcomes, the thirteen `.cpp` for `IdrInBounds`'
`CMakeLists.txt` with the link list of Outputs, the names supplied
(Outputs), the consumer adaptation (U15 includes
`idr/Analysis/Lengths.h`), `Verification: NotRun (swarm policy)`, and
the seams: the Escalate items that applied, and any guard of a fixture
whose proof you could not carry over, named by function.

## Acceptance

- `T/idr/in-bounds/*`, the thirteen fixtures (`counters`,
  `counters-kept`, `dominated`, `doubled`, `kept`, `masked`, `proven`,
  `ranges`, `records`, `records-take`, `returned-twice`, `size-guard`,
  `string-index`), on `idr.func` as U21 writes them: every
  `in-bounds=@f`, `bounds-checked=@f` and `no-guards=@f` of their RUN
  lines holds as at 25890d32, and their FileCheck lines match. In
  particular `proven`'s `@givenBack`, `@givenSecond` and `@halfBack` (a
  call that gives the array back), `records`' `@fill`, `@packed` and
  `@passed` (the relation through a private function's parameters and a
  record's two fields), `records-take`, and `returned-twice` (two runs
  with `remove-dead-values` between) prove what they prove today.
- `T/idr/guards/*`: unchanged; the folders and the lowering of guards
  are other lanes', and this lane changes no guard op.
- `idr-expect`'s `in-bounds`, `bounds-checked` and `no-guards` (U15)
  answer on the same functions, `bounds-checked` through
  `accessedArray` from `INC/Analysis/Lengths.h`.
- `T/programs/arrays/*`, the forty programs: byte-identical output and
  status (C0), the bounds programs (`bounds-*`, `linarray-read-past-size`,
  `linarray-write-past-size`) crashing with the same message.
- `bench/fannkuch-linear` and `bench/unionfind` within the run-to-run
  spread (`bench/README.md:101`) of the record the coordinator compares
  against; they are the two programs whose remaining checks the survey
  names (:169-173).
- Source conditions compilation does not establish: no `std::function`
  or walk in `ProveInBounds` reaches a value outside its function;
  `Lengths` has no non-`const` member function but the constructor;
  `grep -rn 'thread_local\|std::atomic\|static .*=' IDR/Transforms/InBounds`
  finds nothing; `grep -rn 'getAttr\|hasAttr' IDR/Transforms/InBounds`
  finds nothing.
- Deletion conditions: `IDR/InBounds/` does not exist; no file names
  `idr.inbounds` or `Proved`.
- **Tempting partial:** keeping `Lengths::related` lazy with a mutex.
  Rejected: the question still walks callers' and callees' bodies while
  their passes erase guards, which a lock on the memo does not stop.
- **Tempting partial:** a `DataFlowSolver` per function in
  `ProveInBounds`. Rejected: a callee's parameter loses the ranges of
  its callers, and `records.mlir:378-384` says a caller's fact is
  not the callee's; the proofs that rely on the converse would go
  silently.
- Compile time: the eager interface table solves pairs no guard asks.
  The coordinator's record (`T/compile-times.sh --against`) is the
  check; a program over twice its earlier time is this lane's bug.

## Escalate if

1. **C1.1 places `Lengths` in `IdrAnalysis` as `IDR/Analysis/Lengths.cpp`.**
   The relation decides clamps with the Presburger `System`
   (`Lengths.cppm:192-196`) and reads ranges through
   `idr::narrow::runSolver` (`Prove.cppm:147`), both of Transforms
   libraries (`IdrInBounds`, `IdrNarrow`), so `IdrAnalysis` would link
   Transforms libraries and `IdrInBounds` would link `IdrAnalysis` back.
   And the analysis is 1137 lines at 25890d32 before its system
   (`Lengths.cppm` 328, `Returned.cppm` 393, `Joins.cppm` 238,
   `Components.cppm` 178), which no one `.cpp` holds. The lane defines
   `Lengths` in `IdrInBounds` under the header C2.1 names and leaves
   `IDR/Analysis/Lengths.cpp` unwritten. Report it. The alternatives are
   the coordinator's: grant `IDR/Analysis/Lengths/` and
   `INC/Analysis/Lengths/` and move the range solver glue below
   Transforms, or record the placement in C1.1.
2. `INC/Transforms/Narrow.h` does not declare `idr::narrow::runSolver`
   and `idr::narrow::rangeOf` with the signatures of
   `Narrow/Naturals.cppm:48` and `:59`. Report the names found; do not
   copy `NaturalRanges`.
3. `Pass::runPipeline(pm, getOperation())` is refused at the pin for the
   current operation as root, or the nested `idr.func` passes do not
   find `Lengths` through `getCachedParentAnalysis`. Report the error
   text and the pin's `Pass.cpp` lines; `PassManagement.md:467-470`
   permits the current operation.
4. `idr.func`'s body may have several blocks, or `idr.return` may appear
   below a nested region, in the ODS as landed: `returnsOf` then walks
   the body once in the constructor. Report which.
5. `arrayRoot` or `isRank1Array` is not declared in
   `INC/IR/IdrDialect.h`. Report the header that declares it.
6. C1.1's one-header-per-public-class rule is read to require headers of
   their own for `System`, `Linear` and `Induction`: the lane owns one
   header under `INC/Transforms`. Report; the classes are the library's
   own and no other library includes them.
7. A fixture of `T/idr/in-bounds` proves at 25890d32 only through the
   callee rewalk `callOrigin` does for a projection
   (`Returned.cppm:349-365`) and the `Built` tree does not carry it.
   Report the function and the return; the rule stands and the fixture's
   expectation is the question for the coordinator.
