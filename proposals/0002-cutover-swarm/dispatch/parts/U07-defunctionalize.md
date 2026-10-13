# U07 — Defunctionalization through dialect conversion

Mandatory findings: none

## Permitted outcome

1. **`idr::Labels`**, the analysis of the labels each `!idr.fn` and
   `!idr.lazy` value may hold, as a class the pass manager constructs
   with `(Operation *, AnalysisManager &)` and caches (C2.1). It owns
   the `DataFlowSolver`, the sparse forward analysis on it and the sites
   it joins by hand (closures, suspensions, constants, applies, escaping
   functions). Mandatory.
2. **`idr-defunctionalize` as a dialect conversion** (C2.4): a
   `ConversionTarget` under which every closure, suspension and apply is
   illegal and every value, signature, field and element of a keyed type
   is illegal until it has its sum's type; a `TypeConverter` whose
   conversion is the slot's decided type and whose target
   materialization is today's coercion between keys; one conversion
   pattern per op the rewrite changes, and one generic pattern that
   retypes any other op's results and region arguments; applied once by
   `applyFullConversion`. Mandatory.
3. **The same program after as before.** Every sum is declared, named,
   numbered and shaped as today (`fn$<n>` unboxed or boxed, `lazy$<n>`
   boxed with `running` and `forced`, `labels`, `by_name`); every
   unsupported program is refused with today's message at today's op;
   `idr::layout::fit` runs once after the conversion; the statistics
   keep their names. Mandatory.
4. **`IDR/Defunctionalize` deleted.** Mandatory.

Consumer adaptations: none outside the lane. The pipeline names the pass
by name (C1.4); the lowering reads the memo sums it reads today.

## Owner / exclusive writes

- `IDR/Transforms/Defunctionalize` (new): `Pass.cpp`, `Keys.cpp`,
  `Moves.cpp`, `Decide.cpp`, `Declare.cpp`, `Converter.cpp`,
  `Patterns.cpp`, `ByName.cpp`, and the library's one private header
  `Defunctionalize.h` beside them.
- `IDR/Analysis/Labels.cpp` (new), `INC/Analysis/Labels.h` (new).
- `IDR/Defunctionalize` (deleted: all twelve units).

**Excluded:**

- `INC/Transforms/Passes.td` (`IdrDefunctionalize`'s name, anchor,
  statistics and dependent dialect) and every `CMakeLists.txt`: the
  coordinator's.
- `IDR/IR/Layout`, `INC/IR/Layout.h` (`fit`, `Layouts`) and
  `IDR/Conversion` (the memo switch a force lowers to): U10's.
- `IDR/IR/*` (the ops, `heldAs`, `getSumName`, `fieldType`, the folders
  of `idr.closure` and `idr.suspend`): U01's. `IDR/IR/Func`, the
  verifier of `idr.func`: U02's.
- `IDR/Transforms/Expect` (`no-closures`, `cells-fit`): U15's.
- `IDR/Analysis/{References,Effects,Holds,TypeGraph}.cpp`: U03's.
- `T/idr/defunc` and every other fixture: U21's. `T/programs`: U22's.

## Read first

- `contracts.md` C2.4, C2.1 (the `Labels` row), C2.0, C1.1 (the
  `IDR/Defunctionalize` and `IDR/Layout` rows and the rules of the
  layout), C1.2 (`idr.func`, `idr.call`, `idr.return`), C1.3 and C1.4
  (the anchor and the position: after `idr-simplify`, before
  `idr.func(canonicalize)`), C4, C6.1, C9.1.
- `findings.md` F-state-1 and F-state-4 (why the symbol table is an
  analysis), F-pass-1.
- Today's library, all of it, in this order:
  `IDR/Defunctionalize/Sums.cppm:1-70` (the design, in one comment),
  `Labels.cppm:17-120` (the lattice and the anchors),
  `Closures.cppm:15-154` (the type helpers, `eachField`, the sites),
  `Analysis.cppm:22-281` (the dataflow analysis), `Slots.cppm:20-302`
  (keys, `fits`, `forced`, keying, `order`), `Moves.cppm:18-201`
  (`sinkOf`, `isFollowed`, `widen`, `lost`, `connect`),
  `Decided.cppm:24-240` (`canCoerce`, `convertible`, the capture cycle,
  `decide`, `unknownKeys`), `Declared.cppm:20-130` (`typeOf`,
  `arrayed`, `retype`, `declareSums`), `Converter.cppm:47-304` (`build`,
  `coerce`, `coerceCalls`, `coerceSinks`, constants, `rewrite(apply)`,
  `construct`, `rewrite`), `ByName.cppm:23-85`, `Pass.cc:16-36`,
  `CMakeLists.txt:20-24` (what it links).
- `INC/Passes.td:267-303` (`IdrDefunctionalize`).
- `INC/IdrOps.td:141-171` (`!idr.fn`, `!idr.lazy`), `:544-600`
  (`idr.data` with `box`, `closures`, `memo`, `labels`; `idr.ctor` with
  `by_name`), `:623-636` (`idr.con`), `:800-826` (`idr.closure`,
  `idr.suspend`, both with folders), `:828-854` (`idr.lambda` and
  `idr.delay`, which `idr-isolate` has made closures and suspensions
  before this pass runs), `:856-874` (`idr.force` takes a lazy value or
  a box), `:876-908` (`idr.apply`).
- `IDR/Dialect/Ops/Lazy.cc:303-320` (`ForceOp::verify`: a box operand
  must be a memo sum) and `IDR/Dialect/Ops/Data.cc:28-62` (the memo
  sum's verifier).
- `INC/Idr.h:390-394`, `:445-471` (`fieldType`, `heldAs`, `getSumName`,
  `lookupCtor`, `isMemo`, `memoRunning`, `memoForced`); these move to
  `INC/IR/IdrDialect.h` (U01) under the same names.
- `IDR/Layout/Fit.cppm:24-32`, `:55-60`, `:157-193` (`fit`: what it
  boxes and that it retypes the module itself) and
  `IDR/Layout/Layout.cppm:1-5`.
- `IDR/Lower/Closures.cppm:1-6`, `:59-130` (`LowerForce`: the memo
  switch is the lowering's and reads the sums this pass declares).
- `IDR/Graph/Scc.cppm:1-10`, `:64-67` (the SCC helper is a wrapper over
  LLVM's `scc_iterator`).
- `IDR/Expect/Closures.cppm:15-33` and `IDR/Expect/CellsFit.cppm:18-37`
  (what the two acceptance properties check).
- `IDR/Dialect/Registration/PipelineSteps.cc:17-19` (the position).
- `T/idr/defunc/*.mlir`, the RUN lines and the comment of each (the
  sixteen properties under Acceptance), and
  `T/idr/lower/closure-left.mlir:1-6`.
- `sources/docs/mlir/docs/DialectConversion.md`: "Modes of Conversion",
  "Conversion Target", "Conversion Patterns" (remapped operands, the
  rollback modes, "Type Safety"), "Type Conversion" (conversions,
  source and target materializations), "Region Signature Conversion".
- `sources/code/mlir/include/mlir/Transforms/DialectConversion.h:41-356`
  (`TypeConverter`: `addConversion` at :174, the materializations at
  :200 and :224, `isLegal` at :304-326, `materializeTargetConversion`
  at :353), `:602-730` (`ConversionPattern`, `OpConversionPattern`,
  `OneToNOpAdaptor`), `:812-822`
  (`populateFunctionOpInterfaceTypeConversionPattern`), `:861-880`
  (`applySignatureConversion`, `convertRegionTypes`), `:1078-1240`
  (`ConversionTarget`), `:1372-1379` (`DialectConversionFoldingMode`),
  `:1382-1474` (`ConversionConfig`), `:1517-1535` (`applyFullConversion`).
- `sources/code/mlir/include/mlir/Analysis/DataFlowFramework.h:291`
  (`setInterprocedural`), `:325-375` (`DataFlowSolver`);
  `sources/code/mlir/include/mlir/Analysis/DataFlow/SparseAnalysis.h:300-395`
  (`SparseForwardDataFlowAnalysis` and the hooks the analysis overrides);
  `sources/code/mlir/include/mlir/Analysis/DataFlow/Utils.h:29`
  (`loadBaselineAnalyses`).
- `sources/docs/mlir/docs/PassManagement.md:215-300` (what an analysis
  is, `isInvalidated`, `getAnalysis`).

## Fixed decisions

**What each of today's partitions becomes.**

| Today | Becomes | Where |
| --- | --- | --- |
| `Labels.cppm` (lattice, anchors, field state), `Analysis.cppm` (the dataflow analysis), `Closures.cppm` (the sites, `holdsClosure`, `closuresIn`) | the analysis `idr::Labels`: one solver, one solve in the constructor, read-only queries | `INC/Analysis/Labels.h`, `IDR/Analysis/Labels.cpp` |
| `Slots.cppm`, `Moves.cppm` (`sinkOf`, `widen`, `lost`, `connect`), `Decided.cppm` | the key decision `Slots`, a value the pass builds from `Labels` and the `SymbolTable` analysis before converting: the key of every slot, which keys convert, each converted key's sum type, the unknown keys. It is what the `TypeConverter`'s conversion callbacks answer from | `Keys.cpp`, `Moves.cpp`, `Decide.cpp` |
| `Declared.cppm` `declareSums` | the sums' declarations, inserted at the module's start before the conversion runs, through the `SymbolTable` analysis's `insert` | `Declare.cpp` |
| `Declared.cppm` `typeOf`, `arrayed`, `retype` | the converter's two conversion callbacks; `retype` goes, the conversion retypes | `Converter.cpp` |
| `Converter.cppm` `coerce`, `build`, `boundCaptureTypes` | the converter's target materialization: a sum into another sum, a label rebuilt in the other sum, a cell's state kept | `Converter.cpp` |
| `Converter.cppm` `rewrite(apply)`, `construct`, constants, `coerceCalls`, `coerceSinks` | conversion patterns: `ApplyPattern`, `ClosurePattern`, `SuspendPattern`, `ForcePattern`, `ConstantPattern`, `CtorPattern`, `FuncSignaturePattern`, `CallPattern`, `ReturnPattern`, and `RetypePattern` for every other op | `Patterns.cpp` |
| `Sums.cppm` `defunctionalize`, `Pass.cc` | the pass: analysis, refusal, declarations, target, patterns, conversion, `by_name`, `fit`, statistics | `Pass.cpp` |
| `ByName.cppm` | kept as today, over the `SymbolTable` analysis | `ByName.cpp` |

Reading of C2.4's "the analysis (`Labels`) decides the keys as today":
the keys are decided from `Labels`, by `Slots`, as today's `Converter::decideKeys`
decides them from the solver (`Converter.cppm:31-41`). `Labels` itself is
what C2.1's row says: the label lattice on a `DataFlowSolver`.

**`idr::Labels` (`INC/Analysis/Labels.h`).** Namespace `idr`. The
header declares:

- `struct LabelSet` (today's `Labels`, `Labels.cppm:17-57`: `unknown`,
  the sorted `names`, `of`, `top`, `join`, `mayHold`, `print`);
- the lattice `LabelLattice`, the anchors `FieldAnchor` (data,
  constructor, index) and `ElementsAnchor` (element type), and the state
  `FieldLabels` (`Labels.cppm:59-120`), each with its `resolveTypeID`;
- the type helpers `isClosureType`, `isLazyType`, `isKeyed`,
  `cellField` and `eachField` over a `ConAttr`'s fields and run cells
  (`Closures.cppm:22-51`), inline, so that the analysis and the pass
  read a constant the same way;
- `class Labels` with `Labels(mlir::Operation *, mlir::AnalysisManager &)`
  and `bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &)`
  returning true unless `Labels` and `mlir::SymbolTable` are both
  preserved; the queries `LabelSet labelsOf(mlir::Value) const`
  (`Slots.cppm:76-88`, the defining closure, suspension or constant
  joined in), `LabelSet fieldLabels(mlir::SymbolRefAttr ctor, unsigned) const`,
  `LabelSet elementLabels(mlir::Type element) const` (the two anchor
  reads of `Slots.cppm:147-187`), `bool holdsClosure(mlir::Attribute) const`,
  and the sites read-only: closures and closure constants per label,
  suspensions and suspension constants per label, the applies, the
  escaping functions (`Closures.cppm:58-68`).

`IDR/Analysis/Labels.cpp` holds the gather (`Closures.cppm:132-153`,
over `idr::FuncOp`, `idr::CallOp` and `idr::ReturnOp` in place of
`func.*`), the sparse analysis (`Analysis.cppm:22-281`, same hooks,
same joins: constants' closures reach fields before anything runs,
captures and apply arguments into entries, label results into applies
and forces, fields and elements through the anchors) and the
constructor: `am.getAnalysis<mlir::SymbolTable>()` for every lookup,
`DataFlowSolver(DataFlowConfig().setInterprocedural(true))`,
`loadBaselineAnalyses`, `load<LabelAnalysis>`, `initializeAndRun`
(`Sums.cppm:101-107`). A solver that fails is an internal error the
constructor records and the pass reports; the analysis mutates nothing.
The analysis constructs no `SymbolTable` of its own: `Closures.cppm:54`
goes.

**`Slots` (the key decision, `Defunctionalize.h`, namespace
`idr::defunctionalize`).** `using Key = std::pair<mlir::Type, mlir::ArrayAttr>`
as today (`Slots.cppm:20`). Built as `Slots(ModuleOp, Labels &, SymbolTable &)`
and run in today's order: `keyFields`, `keyArrays`, `keyFunctions`,
`keyValues`, `widen`, `keyForces`, `order`, `connect`, `decide`
(`Converter.cppm:31-41`). It answers `keyOf(Value)`,
`argumentKey(StringAttr fn, unsigned)`, `resultKey(StringAttr fn, unsigned)`,
`fieldKey(SymbolRefAttr ctor, unsigned)`, `elementKey(Type element)`,
`sinkKey(OpOperand &)` (today's `sinkOf`, `Moves.cppm:43-75`),
`isConverted`, `isEmpty`, `sumOf(Key)` (null when the key stays),
`typeOf(Type, Key)` (the sum or the type unchanged, at the slot's grade,
arrays retyped by their elements' keys: `Declared.cppm:20-54`),
`typeOf(Value)`, `captureTypes(label, Key)` and `forcedType(Key)` as
converted, `keys()` in first-appearance order with their sums, and
`unknownKeys()` (`Decided.cppm:223-240`). A `Value` the table does not
hold (one the conversion created) has its own type: `typeOf(v)` is
`arrayed(v.getType())`, which is the identity on a type the conversion
already retyped. Keys are by the original module's values, which the
conversion keeps alive until it ends (below).

Sums are named and numbered as today: `fn$<n>` for closure keys, boxed
when the key is on a capture cycle, `lazy$<n>` for lazy keys, always
boxed, each counted by first appearance (`Decided.cppm:206-217`). The
capture cycle (`Decided.cppm:85-106`) is found with `llvm::scc_iterator`
over a `GraphTraits` specialization of the key graph written in
`Decide.cpp`; today's helper is a wrapper over the same iterator
(`IDR/Graph/Scc.cppm:1-10`).

**The converter (`SlotTypeConverter : mlir::TypeConverter`, `Converter.cpp`).**
Holds `Slots &` and `SymbolTable &`. Two conversions, registered in this
order so that the second is tried first:

1. `addConversion([&](Value v, SmallVectorImpl<Type> &out) -> std::optional<LogicalResult>)`:
   `out.push_back(slots.typeOf(v))`, one to one. This is the key
   decision for results and block arguments: a match case's argument
   gets its field's key, a fold's element its array's, a force's result
   its cell's `forced` slot, every other value the labels the analysis
   found for it (`Slots.cppm:209-255`).
2. `addConversion([&](Type t) -> std::optional<Type>)`: a grade is kept
   around its carrier; an array's element type is retyped by
   `elementKey` (`Declared.cppm:43-54`); a bare `!idr.fn` or
   `!idr.lazy` carrier returns `std::nullopt`, since no slot is known
   without a value; any other type is itself.

One target materialization,
`addTargetMaterialization([&](OpBuilder &, Type to, ValueRange inputs, Location, Type) -> Value)`:
exactly one input whose type and `to` both name sums (`getSumName`);
builds today's `coerce` (`Converter.cppm:77-127`): a linear value is
`lin.use`d, rebuilt and `lin.enter`ed; otherwise an `idr.match` over the
input sum's label constructors (its declaration's constructors but
`running` and `forced`), each case binding the captures at the
scrutinee's grade (`fieldType`), holding them as the target
constructor's fields (`heldAs`) and yielding `idr.con @to::@label`; a
memo sum's `running` yields `running`, its `forced` yields `forced`
with the value held at the target's `forcedType`. Anything else returns
`nullptr`, which fails the conversion: a materialization the patterns
did not ask for is a slot the target did not cover, an internal error.
No source materialization is registered: a converted value used by an
op the conversion left as it was is the same internal error.

Patterns ask for a coercion through
`getTypeConverter()->materializeTargetConversion(rewriter, loc, sinkType, operand)`,
once per sink and once per call result, so that one coercion serves
every use as today's `coerceCalls` and `coerceSinks` do
(`Converter.cppm:139-169`). The two cases that are not a sum into a sum
are the patterns' own, decided by keys: a move out of or into an empty
key is `ub.poison` of the sink's type (`Converter.cppm:88-89`); a move
between equal types is the operand. `canCoerce` (`Decided.cppm:40-43`)
is what `decide` guarantees for every flow, and the materialization
asserts nothing: a label the target sum lacks is `nullptr`.

**The target (`Pass.cpp`).**

- `addIllegalOp<idr::ClosureOp, idr::SuspendOp, idr::ApplyOp>()`:
  none survives. A closure or suspension is a source of its own key,
  so its key is never empty, and a non-empty key that does not convert
  was refused before the conversion started.
- `addDynamicallyLegalOp<idr::FuncOp>`: legal when each argument type
  equals `slots.typeOf(argument)` (for an external function,
  `typeOf(type, argumentKey(fn, i))`), each result type equals
  `typeOf(type, resultKey(fn, i))`, and the body's block arguments are
  legal values. Not `isSignatureLegal`: a result's key is the
  function's, not the type's.
- `addDynamicallyLegalOp<idr::CtorOp>`: legal when each field type
  equals `typeOf(field, fieldKey(data::ctor, i))`.
- `addDynamicallyLegalOp<idr::ConstantOp>`: legal when its result is a
  legal value and `labels.holdsClosure(value)` is false.
- `addDynamicallyLegalOp<idr::ForceOp>`: legal when its operand is not
  a lazy value and its result is a legal value.
- `addLegalOp<idr::DataOp, ModuleOp>()`.
- `markUnknownOpDynamicallyLegal`: `converter.isLegal(op)` and
  `converter.isLegal(&region)` for each region, which is the value
  conversion above on operands, results and block arguments. An op
  whose operand still is an original keyed value is illegal until a
  pattern recreates it with the remapped operand.

A value of `!idr.fn` type is legal only when its key is empty, as today
a slot no label reaches keeps its type (`Declared.cppm:24-29`,
`T/idr/defunc/curried-apply-poison.mlir`). No `!idr.lazy` value is
legal: a lazy key whose labels are known is a memo sum even with no
label (`Decided.cppm:45-48`), and one whose labels are unknown was
refused.

**When a key stays a closure.** Before anything is declared or
converted, the pass reads `slots.unknownKeys()`. For each, at the op
where the analysis lost the value (`Moves.cppm:109-118`), else where the
key first appears, else the module: `unsupported (laziness): a
suspension reaches '<op>', where the analysis of its labels loses it`
for a lazy key, `unsupported (runtime closure): a closure reaches
'<op>', where the analysis of its labels loses it` for a closure key
(`Pass.cc:22-29`), once per op and kind; then `signalPassFailure`, the
module unchanged (`Sums.cppm:111-113`). The ops the analysis follows are
today's `isFollowed` list with `idr.func`, `idr.call` and `idr.return`
in place of `func.*` (`Moves.cppm:81-87`); any other op with a keyed
operand, result or region argument is where a value is lost.

**The patterns (`Patterns.cpp`).** Every pattern is an
`OpConversionPattern<Op>` constructed with the converter, benefit 2;
`RetypePattern` is a `ConversionPattern` on `MatchAnyOpTypeTag`,
benefit 1, that fails on `idr.func`, `idr.data`, `idr.ctor` and the
module.

- `FuncSignaturePattern`: a `TypeConverter::SignatureConversion` with
  `addInputs(i, typeOf(argument i))`, the result types
  `typeOf(type, resultKey(fn, i))`, `rewriter.convertRegionTypes(&body, converter, &signature)`,
  then `modifyOpInPlace` setting the `FunctionType`. This is the body
  of upstream's function-interface pattern with the result types taken
  from the slot table instead of from the type (see Escalate if).
- `CallPattern` (added by `populateCallOpTypeConversionPattern`): each
  keyed operand coerced to `typeOf(argumentKey(callee, i))`; a new
  `idr.call` with result types `typeOf(type, resultKey(callee, i))`;
  each keyed result coerced to `typeOf(result)` and the op replaced
  with the coerced values (`Converter.cppm:139-160`).
- `ReturnPattern` (added by `populateReturnOpTypeConversionPattern`):
  operands coerced to `typeOf(type, resultKey(parent, i))`.
- `ClosurePattern`, `SuspendPattern`: `idr.con @sum::@label` of the
  captures held as the constructor's field types (`Converter.cppm:47-58`,
  `:276-284`).
- `ApplyPattern`: a callee of an empty key replaces its results by
  `ub.poison` (`Converter.cppm:227-236`); otherwise `idr.match` on the
  remapped callee over its labels, each case binding the captures at
  the scrutinee's grade, holding them as the label's parameters,
  coercing each keyed argument to `argumentKey(label, captures + i)`,
  calling the label with `idr.call`, coercing each keyed result from
  `resultKey(label, j)` to `typeOf(apply result j)`, and yielding
  (`Converter.cppm:238-271`).
- `ForcePattern`: a new `idr.force` of the remapped cell with result
  type `typeOf(result)`. The op stays; the switch on the cell's state is
  the lowering's (`IDR/Lower/Closures.cppm:1-6`).
- `ConstantPattern`: the attribute converted part by part with the slot
  of each part (`Converter.cppm:173-214`, runs cell by cell), the result
  type `typeOf(result)`.
- `CtorPattern`: `modifyOpInPlace` setting `field_types` from
  `fieldKey`.
- `RetypePattern`: an `OperationState` of the same name, location and
  attributes; each operand the remapped one, coerced to its sink's type
  when the operand's key and `sinkKey` differ (poison for an empty
  side); result types `typeOf(result)`; each region moved with
  `inlineRegionBefore` and converted with `convertRegionTypes`;
  `replaceOp`. A yield's sink type is the type its parent's result
  already has, since the parent is legalized before its regions
  (preorder) and a generate's yield goes to the array's element slot.
  This is `retype` (`Declared.cppm:68-93`) and the sink coercions, as
  patterns: `idr.yield`, `idr.con`, `idr.field`, `idr.match`,
  `idr.match_lit`, `idr.lin.enter`, `idr.lin.use`, `ub.poison` and the
  array ops are all it rewrites.

**The run (`Pass.cpp`).** `applyFullConversion(module, target, patterns, config)`
with `config.allowPatternRollback = true` (the default: erasures are
delayed to the end, so the original values the key table is indexed by
stay distinct for the whole run), `config.foldingMode = DialectConversionFoldingMode::Never`
(`idr.closure` and `idr.suspend` have folders, `INC/IdrOps.td:808`,
`:824`; a fold inside the driver would make a constant the key table
never saw; `canonicalize` follows this pass in the pipeline, C1.4) and
`config.buildMaterializations = true`. A failed conversion is an
internal error: the framework names the op it could not legalize; the
pass adds `internal error: idr-defunctionalize: the conversion left an
op the target does not accept` at the module and fails.

Then `markByName(module, symbols)` as today (`ByName.cppm:59-85`: a
label whose function reaches, through `idr.call`s, an op with
`PerformsIO` that is not an array, buffer, `world.new` or `strerror`
op, unless a constant names it), then `numBoxed += idr::layout::fit(module)`
(`INC/IR/Layout.h`, U10; `Sums.cppm:116`), then `numSums` and
`numClosures` from `slots` (`Sums.cppm:117-120`). The boxing decision
is consumed only through that call: the pass reads neither `Layouts`
nor the headers' limits.

Analyses: when `slots.keys()` is empty and `fit` returned zero,
`markAllAnalysesPreserved()`; otherwise nothing is preserved, since
declarations and types changed. The pass holds no state across runs;
`Slots` and the converter are locals of `runOnOperation`.

**The library's shape.** `Defunctionalize.h`, private to
`IDR/Transforms/Defunctionalize`, declares `Slots`, `SlotTypeConverter`,
`declareSums`, `populateDefunctionalizePatterns`,
`populateCallOpTypeConversionPattern`,
`populateReturnOpTypeConversionPattern` and `markByName`, in
`idr::defunctionalize`. Every `.cpp` includes `idr/IR/IdrDialect.h`
first, then `idr/Analysis/Labels.h`, then the MLIR headers it uses
(`mlir/Transforms/DialectConversion.h`,
`mlir/Analysis/DataFlowFramework.h`, `llvm/ADT/SCCIterator.h`, ...).
Each unit is 400 lines or fewer; a unit that grows past it is split in
the lane (`Patterns.cpp` into `Patterns.cpp` and `PatternsCalls.cpp`).

## Inputs

- `idr::FuncOp`, `idr::CallOp`, `idr::ReturnOp` and their generated
  accessors (C1.2); `isExternal`, `getArgumentTypes`, `getResultTypes`,
  `cloneTypeWith`.
- `getAnalysis<mlir::SymbolTable>()` in the pass and
  `am.getAnalysis<mlir::SymbolTable>()` in the analysis (C2.0).
- `IdrDefunctionalize` in `INC/Transforms/Passes.td` (coordinator):
  name `idr-defunctionalize`, anchor `ModuleOp`, statistics `numSums`,
  `numClosures`, `numBoxed`, dependent dialect `ub` (`INC/Passes.td:267-303`
  as today).
- From `INC/IR/IdrDialect.h` (U01), by today's names: `unrestricted`,
  `gradeOf`, `graded`, `linear`, `isLinear`, `isArray`, `fieldType`,
  `heldAs`, `getSumName`, `lookupData`, `lookupCtor`, `isMemo`,
  `memoRunning`, `memoForced`, `ConAttr` with `isRun`, `getSpine`,
  `getRunCells`, `getTail`, `getRun`, `ClosureAttr`, the `PerformsIO`
  trait.
- `unsigned idr::layout::fit(mlir::ModuleOp)` from `INC/IR/Layout.h`
  (U10; C1.1's `IDR/Layout` row).
- `idr-expect`'s `no-closures` and `cells-fit` (U15), unchanged, as the
  instruments of Acceptance.

## Outputs

- `idr::Labels` in `INC/Analysis/Labels.h` and `IDR/Analysis/Labels.cpp`
  (the `IdrAnalysis` library's unit list gains `Labels.cpp`).
- The `IdrDefunctionalize` library: `IDR/Transforms/Defunctionalize/{Pass,Keys,Moves,Decide,Declare,Converter,Patterns,ByName}.cpp`
  (and `PatternsCalls.cpp` if split). It links `IdrIR`, `IdrAnalysis`,
  `MLIRTransformUtils`, `MLIRAnalysis`, `MLIRUBDialect`.
- The pass `idr-defunctionalize`: today's name, statistics, remarks and
  `unsupported` messages; the sums it declares in today's shape, which
  the lowering (U10), `idr-expect` (U15), the fixtures (U21) and the
  programs (U22) consume.

## Implement

- **`INC/Analysis/Labels.h`.** As under Fixed decisions. The anchors
  and the state carry `resolveTypeID` as today (`Labels.cppm:60-64`).
- **`IDR/Analysis/Labels.cpp`.** The `LabelAnalysis` of
  `Analysis.cppm:22-281` with `idr::FuncOp`, `idr::CallOp`,
  `idr::ReturnOp`; the gather of `Closures.cppm:132-153`, whose test for
  an escaping function names the new ops; the constant walks
  `holdsClosure` and `closuresIn` (`Closures.cppm:96-130`); the
  constructor and `isInvalidated`. The result of a failed
  `initializeAndRun` is kept as a flag the pass reads and reports as
  `internal error: idr-defunctionalize: the analysis of labels did not
  converge`.
- **`Keys.cpp`.** `Slots`'s keying (`Slots.cppm:64-255`), `sinkKey`,
  `widen` (`Moves.cppm:43-107`), `order` and the numbering
  (`Slots.cppm:257-302`, `Decided.cppm:206-217`), `typeOf`, `arrayed`,
  `captureTypes`, `forcedType` (`Declared.cppm:20-66`). Lookups through
  the `SymbolTable` analysis; nothing walks to rewrite.
- **`Moves.cpp`.** `Flow`, `Sink`, `move`, `lost`, `constantSources`,
  `connect` and `connect(apply)` (`Moves.cppm:18-27`, `:109-201`).
- **`Decide.cpp`.** `canCoerce`, `convertible`, `holds`, the capture
  cycle with `llvm::scc_iterator`, `decide` to its fixpoint,
  `unknownKeys` (`Decided.cppm:40-240`). The logic is unchanged.
- **`Declare.cpp`.** `declareSums(ModuleOp, Slots &, SymbolTable &)`:
  for each converted key in order, an `idr.data` at the module's start
  with `box` for a boxed or memo key, `closures` or `memo`, `labels`
  for a memo key; a constructor per label whose field types are
  `typeOf(captureType, argumentKey(label, i))`; for a memo key,
  `running` with no field and `forced` with `forcedType(key)`
  (`Declared.cppm:101-130`, with the capture types computed instead of
  read back from a retyped function). Each declaration goes through
  `symbols.insert`.
- **`Converter.cpp`.** `SlotTypeConverter` with the two conversions and
  the target materialization as fixed above; the label rebuild (today's
  `build`, `Converter.cppm:47-58`) and the bound capture types
  (`:131-136`) as its private helpers.
- **`Patterns.cpp`.** The ten patterns and the three `populate`
  functions. Each coercion goes through `materializeTargetConversion`;
  each empty-key move is `ub.poison`.
- **`ByName.cpp`.** `observable`, `reaches` over `idr.call`, `markByName`
  (`ByName.cppm:23-85`), with the symbol table passed in.
- **`Pass.cpp`.** `IdrDefunctionalizeBase`'s `runOnOperation` as fixed
  above: analyses, refusal, declarations, target, config, conversion,
  `by_name`, `fit`, statistics, preserved analyses.
- **Failure paths.** `unsupported (laziness)` and `unsupported (runtime
  closure)` before any change; `internal error: ...` for a solver that
  does not converge, a conversion that fails, or a materialization the
  patterns did not ask for. No path rewrites a closure into a uniform
  boxed form.

## Delete

- `IDR/Defunctionalize/Defunctionalize.cppm`, `Analysis.cppm`,
  `ByName.cppm`, `Closures.cppm`, `Converter.cppm`, `Decided.cppm`,
  `Declared.cppm`, `Labels.cppm`, `Moves.cppm`, `Slots.cppm`,
  `Sums.cppm`, `Pass.cc`. The directory's `CMakeLists.txt` goes with
  the directory (the coordinator's).
- The `Module` struct's own `SymbolTable` (`Closures.cppm:54`).
- The hand walks that rewrite: `retype` (`Declared.cppm:68-93`),
  `coerceCalls`, `coerceSinks`, the constant walk, the apply loop and
  the closure walk of `rewrite` (`Converter.cppm:139-169`, `:287-304`).
- `FailureOr<Defunctionalized>` and `defunctionalize(ModuleOp)`
  (`Sums.cppm:91-122`): the pass is the entry.
- The two `assert`s of `Converter.cppm:56` and `:87`: the first case
  cannot reach a pattern, the second is the materialization's
  `nullptr`.
- The link to `idr_graph` (`CMakeLists.txt:23`): the SCC is LLVM's
  iterator in `Decide.cpp`.

## NOT TO DO

- Do not move the memo switch into this pass: `idr.force` keeps its op
  on the memo box, and the switch is `IDR/Conversion`'s (U10).
- Do not reimplement, call into, or read the internals of `fit` or
  `Layouts`: one call to `idr::layout::fit` (U10).
- Do not change `no-closures` or `cells-fit` (U15), and do not add a
  property.
- Do not add an op (no `idr.coerce`), an attribute (no key on a value or
  a function) or an option to the ODS or `Passes.td` (coordinator).
- Do not key sums by type alone (`T/idr/defunc/state.mlir`,
  `coerce.mlir`), and do not change their names or numbering.
- Do not run `applyPartialConversion`, turn rollback off, or let the
  driver fold.
- Do not register a source materialization that builds a closure from
  a sum: a closure left is the compiler's error, never a program lowered
  some other way (`T/idr/lower/closure-left.mlir:1-6`).
- Do not replace `observable` and `reaches` by the `Effects` analysis
  (U03) in this packet; `by_name` is kept as today.
- Do not construct a `SymbolTable`, hold a cache on the pass, or keep
  the analysis's solver anywhere but in `idr::Labels`.
- Do not make the pass or any part of it a function pass: signatures
  and declarations change together (C1.3).
- Do not write or edit a fixture or a program test: U21 writes
  `T/idr/defunc`, U22 the programs.
- Do not spell `func.func`, `func.call` or `func.return` anywhere in
  the lane.

## Stop and return

The lane is complete when `INC/Analysis/Labels.h`,
`IDR/Analysis/Labels.cpp` and the eight (or nine) `.cpp` files under
`IDR/Transforms/Defunctionalize` exist, every unit is 400 lines or
fewer, `IDR/Defunctionalize` is gone, and no `walk` in the library
mutates IR. Return the changed paths mapped to the four outcomes, the
`.cpp` list of each library (`IdrAnalysis`: `Labels.cpp`;
`IdrDefunctionalize`: the eight or nine), the names supplied
(`idr::Labels`, `populateCallOpTypeConversionPattern`,
`populateReturnOpTypeConversionPattern`), the hub text you need (none
expected: `IdrDefunctionalize` in `Passes.td` is today's),
`Verification: NotRun (swarm policy)`, and the seams below as you met
them. Report as a seam, without stopping: a slot kind the patterns
could not express (the slot, the fixture, the op), with the hand walk
left out and the fixture named as failing.

## Acceptance

Each fixture of `T/idr/defunc` states a property the lane must keep
(U21 rewrites each on `idr.func`; the RUN lines run the pass alone, then
`idr-expect`):

| Fixture | Property |
| --- | --- |
| `choice.mlir` | two labels of one type become one unboxed sum with a constructor per label; the apply is a match calling each; `no-closures` holds |
| `coerce.mlir` | (type, labels) keys: `mkInc` and `mkAdd` return different sums of one closure type; a move into the larger key is a match rebuilding the constructor, once per call and once per yield |
| `numbering.mlir` | sums numbered by first appearance; two runs print the same module |
| `state.mlir` | a state monad's one type gets a sum per label set, none boxed, no closure left |
| `cycle.mlir`, `growing.mlir` | a key on a capture cycle is a boxed sum; the unrelated type stays unboxed; no closure, apply or `!idr.fn` left |
| `growing-lazy.mlir` | a lazy key on a cycle is a boxed memo sum; force stays a force of the box |
| `lazy.mlir`, `memo-sum.mlir` | a lazy value picked at runtime is a memo sum with a constructor per label, `running`, `forced` and `labels`; no `!idr.lazy`, no `idr.suspend` left |
| `memo-by-name.mlir` | the label reaching output is `by_name`; the one forging a world for an array is not; the one a constant names is not |
| `ioref-closure.mlir` | a rank-0 array's one element slot joins the fill and every write; the apply of a read calls both labels |
| `curried-apply-poison.mlir`, `dead-move-empty-key.mlir`, `unreached-cell.mlir` | an empty key: the apply is poison, the move is poison, the cell is still a memo sum with no label; no apply or closure left |
| `unknown-lazy.mlir` | `unsupported (laziness)` at the `arith.select`, the module unchanged |
| `fit.mlir` | after the conversion, `fit` boxes widest first, ties by name, closure sums included; `cells-fit` holds; a second run changes nothing; the unfitted input fails `cells-fit` by name |

- `T/idr/expect/closures.mlir` (`no-closures`) and `fit.mlir`'s
  `cells-fit` lines are the instruments; they are U15's and unchanged.
- `T/idr/lower/closure-left.mlir`: the lowering still meets no closure
  and no lazy value from a converted module.
- `T/idr/verify/cycle.mlir`, `T/idr/fold/poison-fields.mlir`,
  `T/idr/lower/layout.mlir`, `T/idr/effects/idr-effects.mlir` run the
  pass as a step and keep their properties.
- Programs (U22, `expected` and `expected-stdout` byte-identical, C0):
  `T/programs/basic/force-delay` (its `mlir.expect` states
  `no-closures`), and the memo programs under `T/programs/eval`:
  `memo-lazy` (each constant forced once: two hundred additions, the
  printed sum), `memo-shared-stream` (`live-cells` stays `3`),
  `lazy-branch-loop`, `lazy-list-branches`, `lazy-double`,
  `stream-share`, `thunk-consumes-list`, `latent-loop-delay`.
- Source conditions compilation does not establish: no `walk` that
  mutates; no `SymbolTable(` constructor call in the lane; no
  `thread_local`, `static` mutable or member kept across runs; no
  `assert` in the materialization; every `.cpp` and `.h` at 400 lines
  or fewer.
- **Tempting partial:** converting the types in place with a walk and
  leaving the framework to the closures and applies only. Rejected: a
  type changed in place bypasses the driver's mapping, so a later
  pattern's adaptor sees the wrong type, and the hand walk is the thing
  C2.4 deletes.
- **Tempting partial:** a source materialization that rebuilds an
  `idr.closure` from a sum so that an unconverted user compiles.
  Rejected: that is a closure left for the lowering, which the lowering
  refuses as an internal error.

## Escalate if

- **C2.4 names `populateFunctionOpInterfaceTypeConversionPattern<idr::FuncOp>`.**
  Upstream's pattern converts a function's result types from the types
  alone (`convertTypes` on `getResults()`), and a result slot's key is
  the function's: `T/idr/defunc/coerce.mlir` has two functions of one
  closure type returning two sums (`Slots.cppm:109-112`, `:189-205`).
  The lane writes `FuncSignaturePattern` with the same
  body and the result types from `Slots`, and reports it. If the
  coordinator wants the upstream helper kept, report that a result's
  key must then become a property of the type, which `state.mlir` and
  `coerce.mlir` refuse.
- **C2.4 says `idr.force` → the memo switch.** The switch is the
  lowering's phase 2 (`IDR/Lower/Closures.cppm:1-6`, `:59-130`), and
  `T/idr/defunc/memo-sum.mlir` states that the force keeps its op and
  takes the box. The lane retypes the force and leaves the switch to
  U10; report if the coordinator meant the switch to move.
- **`IDR/Analysis/Labels.cpp` passes 400 lines.** The solve, the gather
  of its sites and the constant walks are 439 lines today
  (`Analysis.cppm` 283, `Closures.cppm` 156), with the lattice already
  counted in the header. If the unit cannot be brought under 400 at the
  lane's density, report the count and ask for
  `IDR/Analysis/LabelSites.cpp` in the lane's ownership; do not put the
  solve in the transform library.
- **The SCC helper has no owner in C1.1.** `IDR/Graph` becomes U03's
  four analyses, and nine units of seven lanes call
  `graph::stronglyConnected` today. The lane uses `llvm::scc_iterator`
  directly; report the duplication so the coordinator can name a home
  if one is wanted.
- **`T/spec/no-local-headers` as rewritten (C9.3) refuses a private
  header beside a library's `.cpp` files.** The lane has no public
  header under `INC/Transforms` for its internals and needs
  `Defunctionalize.h` beside them, as upstream's libraries have. Report
  the rule's text; the alternative is `INC/Transforms/Defunctionalize.h`
  added to the lane.
- **`INC/IR/Layout.h` (U10) does not declare `unsigned fit(mlir::ModuleOp)`**,
  or declares it with another shape (a method of `Layouts`, a different
  return). Report the declaration found; the pass consumes the boxing
  decision by that one call and nothing else.
- **An `idr.func` fact matters to the decision.** Today the analysis
  reads `isPublic` and the symbol uses to find escaping functions
  (`Analysis.cppm:142`, `Closures.cppm:146-152`); if `instance` or
  `clone` (C1.2) makes a function reachable in a way the symbol uses do
  not show, report the attribute and the fixture.
- **A slot kind the framework cannot express.** Values, arguments,
  results, fields, elements, region arguments and constants all have a
  conversion or a pattern above. If one does not fit (the counterexample
  is a fixture of `T/idr/defunc` that cannot hold), report the slot, the
  op and the fixture, and leave no hand walk in its place.
