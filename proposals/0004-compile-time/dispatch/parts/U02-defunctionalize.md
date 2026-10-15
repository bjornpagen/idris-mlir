# U02 — Total defunctionalization: one flow interface, a label solve with no unknown

## Permitted outcome

1. **Mandatory.** The flow interface exists as C05 fixes it:
   `IdrFlow.td` declares `Idr_FlowOpInterface`; `Flow.h` holds its
   vocabulary and includes the generated interface; `Flow.cpp` holds the
   generated definitions, the vocabulary's members, an external model for
   every op of C05's table (ours and `tensor.insert`, `tensor.extract`,
   `tensor.from_elements`, `tensor.splat`, `tensor.yield`, `ub.poison`),
   `registerFlowInterfaceExternalModels`, `flowEdgesOf`, and the flow rule
   `verifyFlow`, which checks a modelled op edge by edge and any other op
   for a declaration of every keyed value.
2. **Mandatory.** The label solve is C06's `Labels`: MLton's 0CFA on our
   own graph built from `flowEdgesOf`, with union-find, hash-consed sets,
   difference propagation and dispatch handlers; no unknown element, no
   escape, no external function, no MLIR `DataFlowSolver`.
3. **Mandatory.** Every key converts. The sums are C06's identified types
   (closure, empty closure, memo with `by_name` from the effects summary in
   the body), every touched user data type is retyped to a new identified
   type, and every name is made from content (C21). A key on a capture
   cycle is boxed.
4. **Mandatory.** The conversion runs per function, in parallel, after
   every type exists; the patterns read only the decision.
5. **Mandatory.** `idr-defunctionalize` fails only with an internal error;
   it emits no `unsupported` diagnostic.
6. **Mandatory.** The isolation pass, its header and its directory are
   deleted (the frontend writes the symbol form, C22).
7. **Mandatory.** The pass assigns the statistics of C06 (`numSums`,
   `numConstructors`, `largestBoxedSum`, `numBoxed`).
8. **Consumer adaptations.** None outside the writes below. The lines
   other owners write for this lane are listed under Outputs.

## Owner / exclusive writes

Every path of ownership.json's U02 entry:

- `INC/IR/IdrFlow.td` (new): the interface, exactly as C05 gives it.
- `INC/IR/Flow.h` (new): the vocabulary of C05 (`isKeyed`, `FlowAnchor`,
  `FlowPoint`, `FlowEdges`, `flowEdgesOf`, `verifyFlow`,
  `registerFlowInterfaceExternalModels`), then the generated interface; it
  includes `IdrDialect.h`, which includes none of it.
- `IDR/IR/Flow.cpp` (new): see Implement.
- `INC/Analysis/Labels.h`: rewritten to C06.
- `IDR/Analysis/Labels.cpp`: rewritten (the solver).
- `IDR/Analysis/LabelSites.cpp`: rewritten (the graph build).
- `INC/Transforms/Defunctionalize.h`: rewritten.
- `IDR/Transforms/Defunctionalize/Converter.cpp`
- `IDR/Transforms/Defunctionalize/Decide.cpp`
- `IDR/Transforms/Defunctionalize/Declare.cpp`
- `IDR/Transforms/Defunctionalize/Keys.cpp`
- `IDR/Transforms/Defunctionalize/Moves.cpp`
- `IDR/Transforms/Defunctionalize/Pass.cpp`
- `IDR/Transforms/Defunctionalize/Patterns.cpp`
- `IDR/Transforms/Defunctionalize/PatternsCalls.cpp`
- `INC/Transforms/Isolate.h` (deleted).
- `IDR/Transforms/Isolate` (deleted, with `Isolate.cpp`).

**Excluded:** `IDR/Transforms/Defunctionalize/ByName.cpp` (U05; its walk is
replaced by the effects summary U05 owns); `INC/IR/IdrDialect.h`,
`INC/IR/IdrClosureOps.td`, `INC/IR/IdrOps.td`, `INC/IR/IdrMatchOps.td`,
`INC/IR/IdrOwnershipOps.td`, `IDR/IR/OpsClosures.cpp`, `IDR/IR/Regions.cpp`,
`IDR/IR/Func` and `IDR/IR/Layout` (U01: the flow rule's call,
`layout::fit`); `INC/IR/IdrArrayOps.td` and `IDR/IR/OpsArrays.cpp` (U11); `INC/Analysis/Effects.h`, `IDR/Analysis/Effects.cpp` and
`IDR/Transforms/Effects` (U05: the effects summary);
`INC/Support/Scc.h` (U03); `INC/Transforms/Passes.td`,
`IDR/Transforms/Pipeline.cpp`, `INC/Transforms/Pipeline.h` and the three
tools (U06); every `CMakeLists.txt` (coordinator); `tests/idr` and
`IDR/Transforms/Expect` (U17); `compiler/src/IdrisMLIR/Emit` (U15).

## Read first

- `contracts.md`: C05 and C06 (this lane's), C01, C02, C03, C07, C10,
  C21, C22.
- `proposals/0004-compile-time/README.md`: §2 whole (2.1 to 2.9); §4
  stages 1 to 5; §6, the rows on the closure analysis's unknown element,
  the second flow table, the forced anchor, the isolation round trip and
  names from counters; D7 to D12, D18, D27, D29, D34, D35, D37, D48.
- `proposals/0003-typed-apl/README.md` §4.5 (closure elements), D28, D41.
- `sources/notes/compile-pipeline/mlton.md` §2 and
  `casework-audit.md` §2; MLton's 0CFA:
  `sources/code/mlton/mlton/closure-convert/abstract-value.fun:42-148`
  (sets, `send`, `coerce`, `unify`) and
  `closure-convert.fun:246-391, 499-546, 596-708` (constraints, sums,
  coercions, dispatch).
- Today's solve: `foreign/idr/include/idr/Analysis/Labels.h` (all),
  `foreign/idr/lib/Analysis/Labels.cpp` (all; the op cases at 68-123, the
  apply at 126-156, entries at 162-190, region arguments at 196-229),
  `foreign/idr/lib/Analysis/LabelSites.cpp` (all).
- Today's decision and conversion: `foreign/idr/include/idr/Transforms/Defunctionalize.h`
  (all), `foreign/idr/lib/Transforms/Defunctionalize/Keys.cpp` (all),
  `Moves.cpp` (all), `Decide.cpp` (all; the cycle rule at 49-95),
  `Converter.cpp` (all), `Declare.cpp`, `Patterns.cpp`,
  `PatternsCalls.cpp`, `Pass.cpp`, and `ByName.cpp:26-89` (the rule the
  summary now answers).
- The ops whose edges Flow.cpp writes: `foreign/idr/include/idr/IR/IdrClosureOps.td`,
  `IdrOps.td:59-100, 182-240`, `IdrMatchOps.td`,
  `IdrOwnershipOps.td:175-205`; their verifiers
  `foreign/idr/lib/IR/OpsClosures.cpp:140-293`,
  `foreign/idr/lib/IR/Func/Call.cpp:41-118`, `foreign/idr/lib/IR/Regions.cpp`.
- Upstream: `.toolchain/build/llvm-project/mlir/include/mlir/Interfaces/ControlFlowInterfaces.td:180-380, 420-480`
  and `ControlFlowInterfaces.h:49-120, 199-247` (forwarded operands,
  successor inputs); `mlir/Dialect/Tensor/IR/TensorOps.td` (insert,
  extract, from_elements, splat, yield); `mlir/Transforms/DialectConversion.h`
  (value conversions, `applyFullConversion`); `mlir/IR/Threading.h`
  (`failableParallelForEach`); `mlir/IR/DialectRegistry.h`
  (`addExtension`).

## Fixed decisions

- The interface, the vocabulary, the edge table, the flow rule and the
  solve's reading of each edge kind are C05's, exactly.
- Every op holds the interface as an external model in `Flow.cpp`, ours
  (the three world-ordered array ops, `idr.array.new`, `get`, `set`, C11,
  included) and upstream's; no ODS declares it, so `IdrDialect.h` needs
  none of it, and the flow rule is the only check of the edges.
- `isKeyed` lives in `Flow.h` (C05); `Labels.h` keeps `eachField` and
  `cellField`.
- The solve is ours, not MLIR's `DataFlowSolver`: points, a union-find of
  classes, inclusion successors, dispatch handlers, sets as sorted arrays
  of label numbers (a label numbered when first met), uniqued with a join
  cache, difference propagation from a worklist. The answer is a uniqued
  `ArrayAttr` of `FlatSymbolRefAttr` in name order, one per distinct set,
  made when the solve ends.
- A Flow of lazy carrier is a Unify; a second Flow from one operand
  unifies its targets; a suspension's label result is unified with the
  forced anchor of its lazy type (C05). So a memo cell is never rebuilt.
- Every key converts; an empty closure key is the empty sum, and an apply
  on it is `ub.poison` of each result; an empty lazy key is a memo sum
  with only `running` and `forced`.
- A value moves between closure keys by the rebuild match; `fits` is an
  internal error check at the dispatch arm, not a decision.
- Names: C06's `keyText` and `bodyText` hashed by C21's `contentName`;
  owners `fn$`, `lazy$`, or the retyped type's name. A collision is an
  internal error.
- Order inside `runOnOperation`: solve; the effects summary (C10) with
  `Labels::runs`; the key decision; every identified type created by
  name, then every body set; the per-function parallel conversion;
  `layout::fit`; statistics.
- Internal errors read `internal error: idr-defunctionalize: ...` and fail
  the pass; there is no other failure.

## Inputs

- C01: identified data types: making one by name, setting its body once
  (kind closures, memo or plain; constructors in tag order, each with its
  name, field types and `by_name`; `instance`, role and in-place promise
  copied when retyping), reading a body (a constructor's tag by name, its
  field types), `!idr.box` of an identified type; `ConAttr`'s constructor
  name; the builders of `idr.con`, `idr.field` and `idr.match` naming a
  constructor within the value's type; `layout::fit`.
- C02: `idr.delay %value` (one operand, no region); the call-site
  `effects` attribute left absent on the calls the dispatch makes.
- C03: no external `idr.func`; one public root; U01's
  `FuncOp::verifyRegions` calling `verifyFlow` on every nested op, from
  `idr/IR/Flow.h`.
- C07: `stronglyConnected` in `include/idr/Support/Scc.h` (the capture
  cycles), unchanged in shape.
- C10: `idr::ModuleEffects`, constructed once after the solve with
  `Holds`, the symbol table and a `LabelsRun` over `Labels::runs`;
  `byName(label)` for each memo constructor; `writeEntries()`.
- C21: `contentName(owner, key)`, the C++ names-from-content helper.
- C11: `idr.array.new`, `get` and `set` kept with today's accessors
  (`getFill`, `getValue`, `getArrayType`).
- C22: the emitted module in symbol form: no `idr.lambda`, no region
  `idr.delay`, no `idr.data` or `idr.ctor` op.

## Outputs

- C05: `IdrFlow.td`; `Flow.h`; `Flow.cpp` with every model and
  definition C05 assigns to it.
- C06: `Labels.h` and its solve; `Defunctionalize.h`; the sums, names,
  conversion and postconditions; the statistics.
- Lines other owners write from these contracts: U01 the `verifyFlow`
  call in `FuncOp::verifyRegions` with the include of `idr/IR/Flow.h`;
  U06 the `idr-defunctionalize` entry C06 gives, the deletion of the
  isolation entry and of its include in `Pipeline.h`, and
  `registerFlowInterfaceExternalModels` (from `idr/IR/Flow.h`) in the three
  tools; the
  coordinator the build lines of C05 and `Flow.cpp` in `IdrIR`.

## Implement

- **`Flow.h`.** C05's vocabulary, exactly; it includes only
  `idr/IR/Grades.h` and MLIR headers.
- **`Flow.cpp`.** `#include "idr/IR/IdrFlow.cpp.inc"`. The `FlowPoint`
  factories and `FlowEdges` adders. One external model per op of C05's
  table, reading the constructor's tag from the identified type (C01):
  `CallOp`, `ReturnOp`, `ConstantOp`, `ConOp`, `FieldOp`, `MatchOp`,
  `ClosureOp`, `SuspendOp`, `DelayOp`, `ForceOp`, `ApplyOp`, `LinEnterOp`,
  `LinUseOp`, `ArrayNewOp`, `ArrayGetOp`, `ArraySetOp`, and the tensor
  and ub ops, attached by `registry.addExtension` per dialect. `flowEdgesOf`: the op's FlowOpInterface edges, then
  BranchOpInterface (`getSuccessorOperands`, produced operands skipped),
  RegionBranchTerminatorOpInterface (`getMutableSuccessorOperands` against
  the parent's `getSuccessorInputs` for each of
  `getSuccessorRegions(RegionBranchPoint(term))`) and
  RegionBranchOpInterface's entry (`getEntrySuccessorOperands` against
  `getSuccessorInputs` for each parent successor), keyed values only.
  `verifyFlow`: an op with a model has each edge's ends and carriers
  checked (C05); any other op must have each keyed operand forwarded by
  one of the three upstream interfaces, each keyed result a successor
  input, each keyed block argument a successor input or the argument of a
  non-entry block; the error names the edge, operand, result or argument.
- **`LabelSites.cpp`.** The graph build: one module walk calling
  `flowEdgesOf`; a node per point (C06); parameters joined with entry
  arguments for every function; Flow, Unify, Source and Dispatch recorded;
  Constant expanded by C05's rule against the carrier of its point (a
  parameter's from the label function's signature, a field's from the
  identified type's body), with one memo of (part, point) per solve; the
  sink of each operand recorded. A label is numbered when an edge first
  names it.
- **`Labels.cpp`.** The solver of C06: union-find with path compression,
  classes holding set, successors and handlers; `send` of a difference
  from a worklist; `unify` merging two classes and sending each side's
  difference to the other's successors and handlers; a handler running a
  dispatch rule per arriving label (the label's capture count from its
  function's signature). The answers of C06, each set's `ArrayAttr` made
  once.
- **`Keys.cpp`.** `Slots`: the key of every point (carrier and the solve's
  set), argument, result, field, element and forced keys, the widening of
  a closure, suspension or constant whose every use sinks into one key
  containing its own (today's `Moves.cpp:81-98`), `typeOf`, the converted
  signature, capture and forced types, and the set of touched data types
  (those whose body reaches a keyed carrier, transitively), each with its
  retyped type.
- **`Moves.cpp`.** The sink key of each operand from `Labels::sinkOf`;
  nothing else.
- **`Decide.cpp`.** The capture cycles (today's rule, reading identified
  bodies through C01 instead of `idr.data`), which box a closure key; the
  names of C06 interned, a collision an internal error; the counts for the
  statistics.
- **`Declare.cpp`.** Every sum and retyped type created by name first,
  then every body set once (C06's table), the memo `by_name` from C10's
  `ModuleEffects::byName`.
- **`Converter.cpp`.** `SlotTypeConverter`: the value conversion from the
  decision; the type conversion through grades, `!idr.box`, identified
  data types (to their retyped type), and shaped types (element by its
  elements key, `ShapedType::clone`); `coerce` and `rebuild` over the
  identified bodies; poison for a move from an unreached or into an empty
  key.
- **`Patterns.cpp`, `PatternsCalls.cpp`.** Closure and suspend to `idr.con`
  of the label; delay to `idr.con` of `forced` holding its operand moved
  into the forced key; apply to the dispatch match of C06 (or poison);
  force retyped; constants from conversions the decision made once,
  before the parallel phase; signatures; calls and returns; the generic
  retype pattern. The declaration pattern goes (no declaration op is
  left).
- **`Pass.cpp`.** C06's order, `ModuleEffects::writeEntries` after the
  conversion; the conversion by
  `failableParallelForEach` over the `idr.func` ops, each task making its
  function's plan (the types and keys of its own values, the sink key of
  each operand) from the frozen decision and then its own converter,
  target and patterns, with rollback on so that no value or operand the
  plan names is freed before the task ends; statistics.
- **Failure paths.** A name collision, a conversion that leaves an illegal
  op, or a dispatch arm whose label signature is shorter than the carrier
  is an internal error. Nothing else fails.

## Delete

- `LabelSet::top`, the `unknown` member and every `unknown` test
  (`Labels.h:43-133`); `LabelLattice`, `FieldAnchor`, `ElementsAnchor`,
  `FieldLabels`, the `LabelAnalysis` on MLIR's dataflow framework and its
  `loadBaselineAnalyses` (`Labels.cpp:40-318`); `labelsFor` and the
  `byType` filing (`LabelSites.cpp:92-114`); `escapes` and `escaping`
  (`Labels.h:277-281`, `LabelSites.cpp:116-122`); the external tops
  (`Labels.cpp:145-148, 164-166, 242-243, 265-267`).
- `isFollowed` and every hard-coded sink (`Moves.cpp:22-79, 208-247`);
  `unifySuspensions` (`Moves.cpp:147-206`); the evaluated-delay case
  (`Moves.cpp:32-38`, `Patterns.cpp:67-87`'s use of `evaluatedValue`).
- `UnknownKey`, `unknownKeys`, `lost`, `reportUnknown` and both
  `unsupported (runtime closure)` and `unsupported (laziness)`
  (`Pass.cpp:43-50, 96-101`, `Decide.cpp:201-219`); `convertible`,
  `canCoerce` and the sealing cascade (`Decide.cpp:27-47, 97-184`);
  `numClosures`; `Signature::external`, `unknown()` keys, `fits` as a
  decision (`Keys.cpp:64, 81-95, 217-243`).
- The `fn$<n>` and `lazy$<n>` counter names and first-appearance order
  (`Decide.cpp:186-198`, `Keys.cpp:295-342`, `firstSeen`).
- `declareSums` on `idr.data`/`idr.ctor`, the `labels` attribute
  (`Declare.cpp:19-66`); `CtorPattern` (`Patterns.cpp:249-258`); the
  module-wide `applyFullConversion` (`Pass.cpp:115-136`).
- `markByName`'s declaration (`Defunctionalize.h:266-269`).
- `INC/Transforms/Isolate.h` and `IDR/Transforms/Isolate` (the
  `idr-isolate` pass, its `.lam<n>`/`.delay<n>` names and its
  evaluated-delay branch, `Isolate.cpp:80-86, 124-125`).

## NOT TO DO

- No polyvariance and no duplication before the solve (D35).
- No unknown, top, escape or boxed fallback for a closure, and no key left
  a closure: a state the solve cannot reach is not given a code path.
- No refusal, no option, no flag, no counter-made name, no discardable
  attribute.
- Do not edit `ByName.cpp`, `Analysis/Effects*` or `Transforms/Effects`
  (U05), `IdrDialect.h` or any `.td` but `IdrFlow.td` (U01, U11),
  `Layout/Fit.cpp` (U01), `Scc.h` (U03), `Passes.td`, `Pipeline.cpp`,
  `Pipeline.h` or the tools (U06), any `CMakeLists.txt` (coordinator),
  any test (U17). List the line you need instead.
- Do not keep `isExternal()` tests, `idr-isolate`'s region handling, or
  a `DataOp`/`CtorOp` lookup in any file of this lane.
- Do not make the solve parallel or sharded; it is one serial whole-program
  solve (0004 §1, §9).
- Do not write `effects` on the calls the dispatch makes (D38 is U03's).

## Tempting partial solutions

- **Keep MLIR's `DataFlowSolver` and drop only the unknown.** Rejected:
  D12 decides difference propagation and union-find for mutable cells,
  which that solver has neither of, and its interprocedural mode needs
  whole-module constant propagation (`loadBaselineAnalyses`). Acceptance:
  no `DataFlowSolver`, `Lattice` or `loadBaselineAnalyses` in
  `Labels.cpp` or `LabelSites.cpp`.
- **Keep `isFollowed` beside the interface for ops that lack it.**
  Rejected: closure flow held twice. Acceptance: no op list in
  `Defunctionalize/` or `Analysis/Label*`; an op without the interface is
  refused by the verifier.
- **Leave an empty closure key a closure, as today.** Rejected:
  postcondition 1 of C06. Acceptance: a fixture whose higher-order
  function is never called converts with no `!idr.fn` left.
- **Coerce memo cells between lazy keys.** Rejected: a rebuilt cell is a
  second cell, forced again. Acceptance: `memo-shared-stream` and
  `stream-share` keep their live-cell marks.
- **Mark `by_name` after the conversion.** Rejected: a body is set once
  (D29), and the summary answers before the sums (D34). Acceptance: no
  write to a type's body after it is made.
- **Run one `applyFullConversion` on the module.** Rejected: the
  conversion is per function (0004 §2.7). Acceptance: `Pass.cpp` converts
  through `failableParallelForEach`.
- **Number sums by first appearance, or keep `fn$`/`lazy$` as fixed
  names.** Rejected: creation order reaches output. Acceptance: the
  name-stability fixture (one definition edited, every other symbol and
  type name unchanged).

## Acceptance

- `python3 proposals/0004-compile-time/check-units.py` on
  `foreign/idr/lib/IR/Flow.cpp`, `foreign/idr/lib/Analysis/Labels.cpp`,
  `foreign/idr/lib/Analysis/LabelSites.cpp` and every `.cpp` of
  `foreign/idr/lib/Transforms/Defunctionalize/` but `ByName.cpp` shows no
  error of this lane's own; an error caused by a C01, C02, C10 or C21
  declaration not written yet is reported as a seam with the contract it
  names. `Flow.cpp` is reported as not in the build until the coordinator
  adds it.
- Source review: no `unsupported` in this lane's files; none of
  `isExternal`, `DataOp`, `CtorOp`, `lookupData`, `lookupCtor`,
  `declarationOf`, `DataFlowSolver`, `LabelLattice`, `escapes`,
  `evaluatedValue`, `LambdaOp`; no `Twine(` building a symbol name;
  `IDR/Transforms/Isolate` and `INC/Transforms/Isolate.h` absent.
- On the owner's machine (U17's fixtures, listed for them): every former
  source of unknown of 0004 §2.2 converts (an op with a closure result,
  a non-entry block argument after multi-block inlining, an evaluated
  delay holding a closure, a closure crossing a match region argument, a
  fold accumulator in `scf.for`, a closure element of a tensor); the
  grade fixtures of §2.9 convert and pass the linearity verifier; a module
  with an op carrying a closure and no declaration is refused by the
  verifier naming the operand; the corpus and stage 0 verify and convert;
  the solve under 10 s on stage 0; `largestBoxedSum`, `numSums` and
  `numConstructors` recorded on stage 0; every laziness and output test
  prints the same bytes.

## Stop and return

Return when every Mandatory outcome is written and the check-units run is
done, with the handoff the common obligations define. Report, without
stopping other work: any C01 or C02 builder or accessor whose shape
differs from what this part assumes (file, line, the contract), C10's
summary call if its declaration differs, C21's helper if absent, and any
op of the live corpus that carries a closure and has no row in C05's
table.
