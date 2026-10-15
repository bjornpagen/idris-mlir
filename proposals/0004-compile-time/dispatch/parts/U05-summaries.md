# U05 — Effects and constants as bottom-up summaries

## Permitted outcome
1. Mandatory. One effects summary replaces the three effects computations
   of today: `idr::ModuleEffects`, `idr::writeCallEffectsOnReady` and
   `idr::writeEntriesOnFinal`, with `idr::forcedLabels` for the graph
   after the conversion, declared exactly as C10 §3 gives them, in
   `foreign/idr/include/idr/Analysis/Effects.h` and
   `foreign/idr/lib/Analysis/Effects.cpp`, computing the lattice over the
   graph of C10 §2.
2. Mandatory. Which memo labels are `by_name` is `ModuleEffects::byName`,
   read from the summary's observable bit and the static labels (C10 §2);
   `foreign/idr/lib/Transforms/Defunctionalize/ByName.cpp` is deleted.
3. Mandatory. idr-effects is the test entry of C10 §5: on a
   defunctionalized module it writes every entry and every call's
   `effects` component by component, with the two functions of item 1;
   on a module that still applies a closure or forces a suspension it is
   an error at that op.
4. Mandatory. The constants summary: `idr::ConstantResults`,
   `idr::ConstantSummaries` and `idr::SummarizedConstantPropagation`,
   exactly as C10 §4, in the new `foreign/idr/include/idr/Analysis/Constants.h`
   and `foreign/idr/lib/Analysis/Constants.cpp`.
5. Mandatory. idr-constants, the inner pipeline's last step (C10 §5), in
   the new `foreign/idr/lib/Transforms/Effects/Constants.cpp`, declared in
   `foreign/idr/include/idr/Transforms/Effects.h`.
6. Consumer adaptations: none outside the exclusive writes. The lines
   other owners write are listed under Stop and return.

## Owner / exclusive writes
- `IDR/Transforms/Effects` (`foreign/idr/lib/Transforms/Effects/`):
  `Effects.cpp` rewritten; `Constants.cpp` new.
- `INC/Transforms/Effects.h` (`foreign/idr/include/idr/Transforms/Effects.h`):
  declares both passes.
- `IDR/Analysis/Effects.cpp` (`foreign/idr/lib/Analysis/Effects.cpp`):
  rewritten.
- `INC/Analysis/Effects.h` (`foreign/idr/include/idr/Analysis/Effects.h`):
  rewritten.
- `IDR/Transforms/Defunctionalize/ByName.cpp`
  (`foreign/idr/lib/Transforms/Defunctionalize/ByName.cpp`): deleted.
- `IDR/Analysis/Constants.cpp` (`foreign/idr/lib/Analysis/Constants.cpp`):
  new.
- `INC/Analysis/Constants.h` (`foreign/idr/include/idr/Analysis/Constants.h`):
  new.

**Excluded:**
- `foreign/idr/include/idr/Transforms/Passes.td` and
  `lib/Transforms/Pipeline.cpp`: U06 (C12). The `IdrConstants` def and the
  new `IdrEffects` description are U06's lines.
- `foreign/idr/include/idr/Transforms/Defunctionalize.h`,
  `lib/Transforms/Defunctionalize/Pass.cpp` and every other file of
  `lib/Transforms/Defunctionalize/`: U02. The `markByName` declaration
  and call go there.
- `foreign/idr/lib/Transforms/Specialize/Clones.cpp`, `Redirect.cpp`,
  `RedirectPass.cpp`: U04. The clone's first facts go there.
- `foreign/idr/lib/Transforms/Simplify/` (the round, its SCCP and its
  idr-effects), `lib/Transforms/Optimize/`, `include/idr/Analysis/Holds.h`,
  `lib/Analysis/Holds.cpp`, `include/idr/Analysis/References.h`,
  `lib/Analysis/References.cpp`, `include/idr/Support/Scc.h`: U03.
- `foreign/idr/include/idr/IR/` and `lib/IR/` (the `Effect` enum, the
  `effects` attributes, `CallOp::verifySymbolUses`, `ForceOp::getEffects`):
  U01.
- `foreign/idr/lib/Analysis/CMakeLists.txt`,
  `lib/Transforms/CMakeLists.txt`: the coordinator.
- `tests/idr/effects/`, `tests/idr/defunc/memo-by-name.mlir`: U17.

## Read first
- `proposals/0004-compile-time/contracts/C10-summaries.md` whole (the
  contract this lane produces), then `contracts.md` C01, C02, C03, C06, C07,
  C12 as they appear.
- 0004 `README.md`: §2.7 the last two bullets ("Effects are first known
  inside it"), §2.9's `by_name` row, §4 stage 4, stage 6's inner pipeline,
  stage 9 whole, §6's rows on effects and the registry table's
  `idr-effects` row, §8 rank 6, D16, D34, D38, D47.
- Today's effects: `foreign/idr/include/idr/Analysis/Effects.h:1-76`,
  `lib/Analysis/Effects.cpp:1-187` (the local part at 44-62, the
  component pass at 82-100, `passed` at 146-187),
  `lib/Transforms/Effects/Effects.cpp:1-121`,
  `lib/Transforms/Defunctionalize/ByName.cpp:1-91` (statics at 64-69, the
  walk at 30-53), `lib/Transforms/Specialize/Clones.cpp:49-66`,
  `Redirect.cpp:31-34`, `lib/Transforms/Simplify/Round.cpp:25-67` (where
  module SCCP and idr-effects run today and why).
- The IR facts read: `include/idr/IR/IdrAttrs.td:151-174` (`Idr_Effect`),
  `IdrInterfaces.td:70-84` (`PerformsIO`, `ObservableIO`),
  `IdrOps.td:18-37, 59-76` (the `effects` of `idr.func` and `idr.call`),
  `lib/IR/Func/Call.cpp:33-98` (the verifier and `getEffects`),
  `lib/IR/OpsClosures.cpp:155-217` (closure and suspension captures),
  `263-277` (`ForceOp::getEffects`), `tests/idr/defunc/memo-by-name.mlir`
  (the observable and static cases).
- The defunctionalization pass that calls the summary:
  `lib/Transforms/Defunctionalize/Pass.cpp:86-137`, `Patterns.cpp:89-186,
  264-280` (applies become dispatches of direct calls; a force keeps its
  op; a function is retyped in place).
- The analysis manager's parent reads and the inner pipeline:
  `lib/Transforms/Identity/Identity.cpp:48-62`,
  `lib/Transforms/Specialize/RedirectPass.cpp:100-115`;
  `M/include/mlir/Pass/AnalysisManager.h:301-311`,
  `M/lib/Pass/Pass.cpp:572-594` (`runPipeline` nests the module's manager).
- Upstream's solver: `M/include/mlir/Analysis/DataFlowFramework.h:285-303,
  329-336`, `M/lib/Analysis/DataFlowFramework.cpp:119-127`,
  `M/include/mlir/Analysis/DataFlow/SparseAnalysis.h:298-321`,
  `M/lib/Analysis/DataFlow/SparseAnalysis.cpp:229-243`,
  `M/include/mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h:27-104`,
  `M/include/mlir/Analysis/DataFlow/DeadCodeAnalysis.h:40-66`,
  `M/lib/Analysis/DataFlow/DeadCodeAnalysis.cpp:140-158, 410-450`,
  `M/lib/Transforms/SCCP.cpp:38-144`, `M/include/mlir/Transforms/FoldUtils.h:50-80`.
- `sources/notes/compile-pipeline/upstream-mlir-llvm.md` §3 and §4,
  `casework-audit.md` lines 42 and 50.

## Fixed decisions
- The lattice, the own part, the graph, the transfers, the static rule and
  the one bottom-up pass are C10 §2, without alternatives. In particular:
  making a closure or a suspension runs nothing; an apply and a force run
  every label of their key; the observable bit crosses a force run only
  from a `by_name` label; the world parameter's `io` is part of the own
  part and flows like every other bit.
- The stage-4 solve and the ready set's recomputation are one walk of a
  body (`entry` and `visit`, in `lib/Analysis/Effects.cpp`'s anonymous
  namespace) and one component sum; they differ only in where a force's or
  an apply's labels come from: `LabelsRun` before the conversion, the
  memo sum's type (C01) after it. The ready set's recomputation sums the
  effect bits only; the observable bit has no reader after the sums are
  made.
- Names: the types and functions of C10 §3 and §4, exactly. The passes:
  `IdrEffects` and `IdrConstants`, both declared by
  `GEN_PASS_DECL_IDREFFECTS` and `GEN_PASS_DECL_IDRCONSTANTS` in
  `include/idr/Transforms/Effects.h`; their bases
  `idr::impl::IdrEffectsBase` and `idr::impl::IdrConstantsBase`.
- `idr::anyEffect` stays in `include/idr/Analysis/Effects.h` with its
  present definition; U04's `Redirect.cpp` keeps reading it there.
- The full set is never written: a writer removes the attribute (today's
  rule, `IdrOps.td:25-26`).
- `ModuleEffects::writeEntries` gives every function its stage-4 entry and
  every call its callee's, once the conversion has made its calls: C02 §4
  verifies `mayDo(call) == mayDo(callee)` with absence every effect on
  both sides, so a call left without effects beside an entry would fail
  the verifier after idr-defunctionalize. The ready set rewrites both from
  final bodies (D38's moments); a stage-4 value is an upper bound of the
  final one, so whatever reads it first reads it soundly.
- idr-constants finds its table only through
  `getCachedParentAnalysis<idr::ConstantSummaries>()`; its absence is the
  internal error C10 §5 words, never a solve without summaries.
- idr-constants' rewrite is this lane's own function (upstream's is
  static to `SCCP.cpp`): a block worklist over the function's body, an
  existing constant handed to the folder, every result and block argument
  whose lattice holds a constant replaced through
  `OperationFolder::getOrCreateConstant` with the lattice's dialect, and an
  op erased when all its results were replaced and
  `wouldOpBeTriviallyDead` holds.
- The table's lock is one `std::shared_mutex`: lookups share it, a
  publish takes it alone. A summary is read from the final body at
  publish (C10 §4), so idr-constants writes nothing but its function.
- Parallelism: the stage-4 walk is `mlir::parallelFor` over the module's
  functions, each into its own slot, merged in module order; the
  component sum is serial in `idr::components`' order. Output is the same
  at 1, 2 and 8 threads (0004 §4, determinism rules).

## Inputs
- C01: `idr::dataTypeOf`, `DataType::getCtors`, `DataType::isLabel` and
  `Ctor::name` (C01 §3): after the conversion, the labels of the memo sum
  an `idr.force` reads, a label constructor's name being its function's
  symbol name (C01 §6); and the type body's `byName` that U02 sets from
  this lane's answer.
- C02: `idr.func`'s and `idr.call`'s `effects` as
  `OptionalAttr<Idr_EffectAttr>` with the generated `getEffectsAttr`,
  `setEffectsAttr`, `removeEffectsAttr`; `total`; `MayCrashOpInterface`;
  the `ObservableIO` trait; `WorldNewOp`; the call verifier of D38 (C02
  §4: equality, absence every effect on both sides).
- C03: the closed world: every callee and label is an `idr.func` of the
  module with a body.
- C06: the `LabelsRun` callback U02 builds from its label solve, read-only
  and callable from workers.
- C07: the ready set's graph, which carries a force run's edges; when it
  calls this lane's functions, with its members' functions and the
  module's symbol table; `idr::Holds` frozen (C07 §9);
  `idr::components` (`include/idr/Support/Scc.h:23-24`) unchanged (C07
  §2); idr-constants last in the inner pipeline (C07 §4.2).
- C12: the `IdrEffects` and `IdrConstants` defs as C10 §5 words them.

## Outputs
- C10, whole: `include/idr/Analysis/Effects.h`,
  `include/idr/Analysis/Constants.h`, `include/idr/Transforms/Effects.h`
  and their units.
- Consumers: U02 (`ModuleEffects`, `byName`, `writeEntries`), U03
  (`forcedLabels`, `writeCallEffectsOnReady`, `writeEntriesOnFinal`,
  `ConstantSummaries::publish`, `idr::createIdrConstants()`), U04
  (`idr::anyEffect`), U06 (the two pass declarations), U17 (idr-effects as
  a test entry; idr-constants through idr-optimize).

## Implement
- `include/idr/Analysis/Effects.h`: C10 §3 verbatim in shape, with the
  repository's comments: why the summary is built from runs and not from
  makers, why a force crosses the observable bit only from a `by_name`
  label, and why a call's `effects` copies its callee's entry.
- `lib/Analysis/Effects.cpp`:
  - `entry(FuncOp, const Holds &)`: what a function does before its body
    runs an op: `diverge` without `total`, `io` for a parameter that may
    hold a world (today's `takes`, `Effects.cpp:40-42`).
  - `visit(Operation *, Body &, ...)`: what one op does itself (today's
    `local`, `:48-62`, with `observable` for an op with the `ObservableIO`
    trait) and what it runs: `idr.call` by its callee (looked up in the
    symbol table), `idr.apply` and `idr.force` through a label source (a
    `LabelsRun` before the conversion; after it, `forcedLabels`, C01), the
    runs kept in two lists, called and forced.
  - `ModuleEffects::ModuleEffects`: number the module's `idr.func`s in
    module order; `parallelFor` over them filling a slot each (own part,
    runs as positions, the static labels its `idr.constant`s name);
    merge the static labels; build the successor lists and take
    `idr::components`; sum each component (C10 §2), the observable bit of
    a force run read through `byName` of a target in an earlier component.
  - `ModuleEffects::byName`, `writeEntries`.
  - `writeCallEffectsOnReady`, `writeEntriesOnFinal`: the same walk and
    sum, each target outside the component read from its `effects`
    (absent is `anyEffect`), the writes through one helper that removes the
    attribute for the full set and skips an equal value.
- `lib/Analysis/Constants.cpp`: `ConstantSummaries` (empty construction,
  `lookup` copying under the shared lock, `publish` reading each member's
  returns and writing under the exclusive lock) and `SummarizedConstantPropagation::visitExternalCall`
  (C10 §4).
- `include/idr/Transforms/Effects.h`: the two `GEN_PASS_DECL` lines and a
  header comment for both passes.
- `lib/Transforms/Effects/Effects.cpp`: idr-effects (C10 §5): the
  precondition walk, the graph with the force runs from types, the
  components, then for each, `writeCallEffectsOnReady` and
  `writeEntriesOnFinal`; statistics counted from the written entries;
  `SymbolTable` preserved, since only facts on functions and calls
  change.
- `lib/Transforms/Effects/Constants.cpp`: idr-constants (C10 §5): the
  parent analysis, the solver with `DeadCodeAnalysis` and
  `SummarizedConstantPropagation`, interprocedural off, the rewrite,
  `numConstants`.
- Failure paths: a callee or label the symbol table lacks is an assertion
  (C03 makes it impossible); a failed `initializeAndRun` is pass failure;
  idr-constants without its table is the internal error above; idr-effects
  on a module outside its domain is the error above.

## Delete
- The `idr::Effects` analysis class and everything only it had:
  `Effects::of`, `Effects::passed`, `Effects::declared`, `label`,
  `inConstant`, `isInvalidated`, `positions`, `answers`
  (`include/idr/Analysis/Effects.h:26-72`, `lib/Analysis/Effects.cpp:66-187`),
  with its reads of `References` (`References::functions`, `of`,
  `components`, `callsUnknown`) and of `closureLabel`.
- The `isExternal()` tests and the "may do anything" answers for bodiless
  functions and unknown callees (`lib/Analysis/Effects.cpp:47-50, 114-120,
  122-126`): the closed world makes them unexpressible (D7).
- The maker's count of a closure's or a suspension's label and
  `Effects::passed`'s count at the call that is given one: a call's
  effects are its callee's (D38).
- In idr-effects: the per-site loop over `References`, the attribute
  values built before the workers (`lib/Transforms/Effects/Effects.cpp:69-73,
  86-101`), the preserved list of `References`, `Effects`, `Layouts`,
  `TypeGraph` (`:116-117`), and the description's "each round".
- `lib/Transforms/Defunctionalize/ByName.cpp` whole: `markByName`,
  `reaches`, `observable`, the per-label walk through direct calls.
  `markByName`'s declaration (`include/idr/Transforms/Defunctionalize.h:269`)
  and call (`Pass.cpp:105`) are U02's to delete.
- The third computation, `giveFirstFacts` (`Clones.cpp:49-66`), is U04's to
  delete; module SCCP in every round and the round's idr-effects
  (`Round.cpp:26, 56`), with `buildSimplifyRound`, are U03's to delete.

## NOT TO DO
- No option on either pass, and no mode of `ModuleEffects` or of the two
  ready-set functions (C12 §1; D2).
- No observable bit in the `Idr_Effect` enum or on any attribute: its one
  reader is the memo sums' bodies, set once at stage 4 (U01 owns the enum
  in any case).
- No second walk of labels for `by_name`, no fallback to "may do anything"
  for an apply or a force whose labels are not known, no `passed`-style
  count at a call.
- No reads of `References`, `closureLabel`, `declarationOf` or the module's
  top level for a type's constructors: a force's labels come from its type
  (C01).
- No edit of `Passes.td`, `Pipeline.cpp`, `Defunctionalize.h`,
  `Defunctionalize/Pass.cpp`, `Clones.cpp`, `Redirect.cpp`, `Holds.*`,
  `Scc.h`, the IR, the build lists, or any test: their owners write the
  lines listed under Stop and return.
- No summary of what callers pass (0004 §4 stage 9: specialization, C09,
  carries a static argument down).
- No interprocedural solve on the module, no `scc_iterator` of upstream's
  `CallGraph` of our own, no thread pool of our own: the ready set (U03)
  schedules, this lane computes.
- No copy of upstream's `SCCP.cpp` text: its rewrite is static there, and
  ours is written for this pass.
- No assertion that an entry only shrinks, and no guard that drops a
  summary it disagrees with.

## Tempting partial solutions
- Keeping the `idr::Effects` analysis in the analysis manager and calling
  it from defunctionalization. Rejected by acceptance 2: an analysis built
  by the manager cannot take the label solve's `LabelsRun`, so applies
  and forces would be unknown and the summary would fall back to "may do
  anything" before the conversion.
- Making only the observable bit new and leaving the maker's count of
  labels. Rejected by acceptance 4: with a call's effects its callee's
  (D38), a function that forces a cell made by its caller would carry none
  of the label's crash, and a call of it with an unused result would be
  erased.
- Following force runs for every bit, the observable one included, from
  every label. Rejected by acceptance 3: a memo label that forces a cell
  which keeps its value would become `by_name` and run at every force,
  repeating any other IO its body does.
- Leaving force runs out of the graph, as a call graph of `idr.call`s
  alone would. Rejected by acceptance 4 and by determinism: a label not
  ordered before its forcer is read at a schedule-dependent entry.
- idr-constants falling back to a plain solve when the table is missing.
  Rejected by acceptance 6: two ways to run the step, one of them never
  in the pipeline (D2).
- Publishing a function's summary as soon as idr-constants has run on it.
  Rejected by acceptance 6: a member of a component would then read a
  sibling's summary in whatever order the workers ran.

## Acceptance
1. `python3 proposals/0004-compile-time/check-units.py
   foreign/idr/lib/Analysis/Effects.cpp
   foreign/idr/lib/Transforms/Effects/Effects.cpp` passes, except for
   errors caused by another lane's header that does not exist yet, each
   reported with the contract that declares it; the two new units are checked
   with the compile command of `lib/Analysis/Effects.cpp` and of
   `lib/Transforms/Effects/Effects.cpp` and `-fsyntax-only`.
2. Source review: `ModuleEffects` takes a `LabelsRun`; no file of this lane
   includes `References.h`, calls `isExternal()`, names `closureLabel`,
   `declarationOf` or `markByName`, or holds the string `"unsupported ("`.
3. On `tests/idr/defunc/memo-by-name.mlir` (owner's machine, through
   idr-defunctionalize): `@traced` and `@clocked` are `by_name`, `@sized`,
   `@shout` and `@errtext` are not. A memo label that forces a `by_name`
   cell is `by_name`; one that forces only cells that keep their value is
   not.
4. On a defunctionalized module where `@g` forces a cell whose label
   crashes and `@f` calls `@g` without using the result, idr-effects gives
   `@g` `crash` and the call in `@f` the same `effects`; after idr-optimize
   the call stays. The D38 fixture: a call of a pure callee whose result is
   unused is gone after idr-optimize.
5. Old binary against new on the corpus and stage 0 (0004 §2.9, D34): the
   `by_name` marks agree but for labels that force a `by_name` cell, which
   the new rule marks, and labels whose observable call the old pipeline's
   optimization had removed before the old walk ran; every laziness and
   output test of `tests/programs` prints the same bytes.
6. idr-constants: a call of a function whose every live return is the
   constant 3 gives its caller the constant 3, materialized, whatever the
   thread count; a call to a member of the caller's own component gives
   nothing; run outside idr-optimize the pass fails with C10 §5's message.
7. Output byte-identical at 1, 2 and 8 threads (`tests/determinism`).

## Stop and return
Return when the seven files are in the state above and acceptance 1 and 2
hold. Report, without stopping other work, the lines other owners write:
- the coordinator: in `lib/Analysis/CMakeLists.txt`, `Constants.cpp` in
  `IdrAnalysis`; in `lib/Transforms/CMakeLists.txt`,
  `Effects/Constants.cpp` in `IdrEffects`, which also links
  `MLIRTransformUtils` and `MLIRAnalysis`, and `Defunctionalize/ByName.cpp`
  removed from `IdrDefunctionalize`;
- U06 (C12): the `IdrConstants` def and the `IdrEffects` description of
  C10 §5, and `IdrConstants` in C12 §2's table;
- U02 (C06): the `LabelsRun` callback; `ModuleEffects` constructed after
  the solve, `byName` read when a memo body is set, `writeEntries` called
  once; `markByName`'s declaration and call deleted;
- U03 (C07): force runs in the ready set's graph; the calls of C10 §7 at
  their moments, in place of C07 §6's four U05 hooks and `Node::constants`
  (C10 §7 gives the reason: a cycle of libraries); idr-constants
  (`idr::createIdrConstants()`) last in the inner pipeline; the
  `ConstantSummaries` analysis taken before any task runs;
- U04 (C09): `giveFirstFacts` deleted; a redirected call takes its node's
  final entry;
- U01 (C01, C02): the memo label constructors readable from a force's
  operand type (C01 §3: `dataTypeOf`, `getCtors`, `isLabel`); the call
  verifier's equality as C02 §4 states it, which `writeEntries` satisfies
  by writing every call's effects at stage 4.
Any mismatch between C10 and another contract is reported with the path,
the line and the change proposed.
