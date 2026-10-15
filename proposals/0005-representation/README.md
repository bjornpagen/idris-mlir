# 0005: one representation for every fact, and no fuel

Status: decided 2026-10-15 and executing as one swarm wave of eighteen
lanes on disjoint files (`ownership.json`), on the typecheck machine, on
top of the cutover (0004 and 0003's stage 1, commits c7aa7b62 and
5d5f3312). Every question is decided below; the owner's open questions are
§9's, each with its default taken.

## 1. Why

The cutover made the program first-order, total and content-named in
design. An audit of the tree it left (four readers, 2026-10-15) found that
much of it is so only by convention:
- A constructor is a string, a label is a function that happens to share its
  constructor's name, and a force is not a call, so the call graph is
  incomplete and about nine passes build their own. Fifty-two sites in 26
  files look a constructor up by name.
- "No closure is left" and "the owned stage" are re-derived by walks, and
  the root by counting public functions.
- Programs are still refused by count: the frontend's `whnf 64` and
  `implementationOf 64` (`Closed.idr:344`, `Cases.idr:631`, `Instances.idr:284,305`,
  `Dictionaries.idr:139`, `Terms.idr:704,713`), the layout limits (2^16
  constructors, 255 counted fields, a 64 KiB stride), and an internal
  error when the lowering's greedy driver runs out of iterations.
  spec/totality cannot see any of them.
- Concepts held twice or more: the array generating set (Idris bodies,
  registry shapes, `ArrayPrim`, an evaluator); "how a value moves"
  (flow, escapes, exclusivity, `consumes`); "holds references"
  (five ladders that disagree); the runtime ABI (ODS, hand-kept suffix
  lists, 215 hand prototypes no tool checks); guards (an Idris table and a
  C++ enum); boxing (frontend and C++); per-function summaries (four stores);
  effects (three drivers, and a copy on every call); a memref (our
  components and upstream's descriptor inside one function); the
  big/word op pairing (three tables).
- An emitter writes `scf.for` and a 600-line pass recognizes it back as
  linalg (`StructureLoops.h:12`: "a small inverse of a small emitter").
- Bugs found by reading, none of them run yet (§7): no module loads (the
  bytecode writer meets an upstream reader bug), the owned verifier rejects
  every buffer, a constant array is retyped to owned, the parallel lowering
  races on a `DataLayout` cache, a view read in a loop outlives its owner,
  and nine internal errors on ordinary programs.

The owner's guideline (`proposals/0004-compile-time/dispatch/parts/representation-first.md`)
binds every lane: a new case changes the data until it is not special or
not expressible; never a flag, a fallback, a second path, a guard that
validates and discards, a fact in a discardable attribute, or fuel.

## 2. Rules this wave adds to every lane

- **No fuel.** No recursion, loop or reduction in the compiler is bounded
  by a count to make it terminate. Termination is by structure: a
  structurally smaller argument, a set of unvisited items that shrinks, a
  bottom-up order over a finite DAG, Idris's own totality proof, or a
  well-quasi-order (the request-chain rule). Idris code that needs a measure
  for the totality checker uses `Control.WellFounded` (`sizeInd`,
  `SizeAccessible`) or structural recursion on the shrinking set, never a
  `fuel : Nat` parameter. A size budget that only stops optimizing (the
  inliner's caller cap, 0004 D11) is a policy, not fuel, and stays; a
  count that bounds termination is fuel and goes. Every lane removes every
  fuel site and every to-a-fixpoint loop in its files and lists each in its
  report.
- **No count refuses a program,** in C++ or Idris (AGENTS.md). A
  representation limit is lifted by a representation (§4 D4), not refused.
- **Every lane fixes the bugs of §7 in its files** and lists each as fixed
  or, with the reason, not fixed.

## 3. Upstream mechanisms this wave adopts

`mlir::CallGraph` with `llvm::scc_iterator` (one call graph for every pass,
complete once forces are calls); `RegionBranchOpInterface`/`BranchOpInterface`
for region forwarding; `ViewLikeOpInterface` and our existing
`ResultCarriesOperand` trait for grade-only ops; `TensorLikeType`/
`BufferLikeType` (`Bufferization/IR/BufferizationTypeInterfaces.td`) for
`!idr.lin<T>`; upstream's memref-to-LLVM patterns on a descriptor built at
the use; one-to-N type conversion for record elements; `APIntParameter` for
big constants; `matchPattern(m_One())`; `walkAndApplyPatterns` where a
greedy driver's iteration count could fail.

## 4. Decisions

Each names its lane (§6) and the API the other lanes write against. Lanes
implement against these names whether or not the owner has landed them.

**D1. A constructor is its tag** (R01; users everywhere).
- The data body's record becomes
  `struct Ctor { mlir::StringAttr name; llvm::ArrayRef<mlir::Type> fields; bool byName; CtorRole role; mlir::FlatSymbolRefAttr fn; }`.
- `CtorRole` is one ODS enum in IdrAttrs.td, `Plain | Nil | Cons | Label | Running | Forced`, generated into Idris. It replaces U14's `Con.role`, the memo states found by position or by the strings "running"/"forced", and `isLabel`.
- `fn` is set exactly when `role == Label`: the label's function. A label is never found by name again.
- Every op that names a constructor (`idr.con`, `idr.match` cases, `idr.field`, `idr.take`, the reuse forms) holds `tag : I32Prop`, printed and parsed by name through `custom<CtorRef>(type($x), $tag)`. R01 writes `parseCtorRef`/`printCtorRef` in lib/IR/Asm.cpp; `#idr.con` holds tags the same way.
- `DataType::getTag(StringRef)` survives only in the parser and printer.

**D2. A force is a call** (R06 emits; R02 defines ops; R12 lowers; R07 reads the graph).
- idr-defunctionalize gives each memo sum one dispatch function, content-named `<sum>.force`, and turns every `idr.force` into an `idr.call` to it.
- The body matches the cell's state:
  - **Label:** `idr.memo.enter %cell` (the state becomes Running), then `idr.call` of the label's `fn`, then `idr.memo.settle %cell, %v` (the state becomes Forced(v)).
  - **Running:** `idr.crash`, the loop.
  - **Forced:** the value.
- R02 adds `idr.memo.enter` and `idr.memo.settle`, with effects on the cell. R12 lowers them as header writes and deletes Force.cpp's lowering of `idr.force` past defunctionalization; `idr.force` stays only before it.
- With D1's `fn` the call graph is complete: `forcedLabels`, every hand-built call graph, and the label-equals-function convention go. Deduplication renames labels freely with `SymbolTable::replaceAllSymbolUses`.

**D3. The program and its stage are an op** (R02 defines; R04 verifies; R17 nests the pipeline; R15 emits; every pass lane re-anchors).
- `idr.program @name root(@f) stage(higher|first|owned) { idr.func ... }` has `SymbolTable`, `IsolatedFromAbove`, `SingleBlock` and `NoTerminator`. Every `idr.func` inside is private. The root is the property, not publicity, so "one public function" and the root count go. This reverses 0004 D28, whose reason (publicity already holds the root) no longer stands once publicity holds nothing.
- `ProgramOp` API: `getRoot()`, `getStage()`, `setStage(Stage)`, the symbol table.
- idr-defunctionalize sets `first` and idr-rc sets `owned`. idr-lower and idr-entry move the program's functions into the `builtin.module` and erase the op.
- R04's region verifier makes:
  - `!idr.fn`, `!idr.lazy`, `idr.apply` and `idr.force` illegal past `higher`;
  - own and excl grades illegal before `owned`;
  - a plain counted reference illegal at `owned` (a borrow is the explicit view grade).
- Deleted: `inOwnedStage`, `definesOwned`, `checkNoClosures` (Lower.cpp), the root count, and the null-symbol-table test in `consumes`.
- Passes.td: every pass anchored on `::mlir::ModuleOp` that reads the idr program is anchored on `::idr::ProgramOp`; function passes nest under it.

**D4. No fuel, no count refusals** (R14 frontend; R01 layout; R08 specialization; R12 lowering; R18 spec).
- **Frontend `whnf`/`implementationOf`:** unfold a head definition only while it is not already on the head path being unfolded. Termination comes from the shrinking set of unvisited definitions. Idris's normaliser is asked only for definitions Idris proved total, so its termination is Idris's proof.
- **What the frontend's reduction returns:** a constructor with its arguments, or `Stuck on x`, naming the runtime binder or the definition that is not total. A stuck implementation is the refusal AGENTS.md describes, naming the value. The fuel arguments at the sites §1 lists are deleted.
- **Graph.idr and Emit/Types.idr** lose their `fuel` parameters for well-founded recursion on the unvisited set.
- **The `Laziness` refusal** ("a match on a lazy value") becomes a force followed by the match: it is neither megamorphic nor outside the language.
- **Layout limits are lifted, not refused** (R01):
  - more than 2^16 constructors becomes a two-level sum (an outer tag picks a group, each group a sum of at most 2^16);
  - more than 255 counted fields becomes a cell with a count word after its header;
  - an element stride over 64 KiB becomes a boxed element.
  - The `Rule::Layout` refusals for counts are deleted. `tests/reject/layout-*-counted-fields` become programs that compile.
- **Specialization stops by the request-chain rule, not `kKeysPerOwner`** (R08): a new key is not made when it embeds an ancestor key on its request chain. That's 0012's feature 2, the frontend's own rule over instance keys, here over specialization keys. A well-quasi-order, not a count. `kKeysPerOwner` is deleted.
- **The inliner's 10,000-op caller cap stays:** a size policy that only stops inlining.
- **Lowering** (R12): `walkAndApplyPatterns`, or no iteration limit, where a greedy driver's default of 10 could report an internal error.
- **Rule categories:** each `Rule` case carries its category in ODS, `Megamorphic | OutsideLanguage` (R01 defines; R13 generates into Idris and into the tests' rule list).
- **spec/totality** (R18) checks structure, not spellings:
  - no `fuel` parameter or Nat budget argument anywhere in compiler/src;
  - no `Rule` case without a category;
  - one program per lifted limit that must compile (a reduction deeper than 64 steps, a 256-counted-field constructor, a 70,000-constructor sum generated by the test).

**D5. The array generating set is declared once** (R16 library; R14 registry).
- `Array.Core`'s generating functions become bodiless `%extern` declarations, as mlir-linear's primitives already are (`Linear/String/Iterator.idr:27-29`). The types `Array`/`LArray` are exported without constructors, and everything else in the library is code over them.
- R14 derives each registry entry's arity, quantities and erasure from the declaration's own type in the context. That deletes the restated shapes (`Registry/Recognized.idr:140-160`), `ArrayPrim` (`Entry.idr:197`) and the evaluator over it (`Terms.idr:1121-1240`, `Types.idr:237-286`). A static extent is read from the type's normal form, never by evaluation.
- The compiler's own Idris imports no mlir-array (checked), so stage 0 on Chez is unaffected. No Chez backend runs array programs, which AGENTS.md wants.

**D6. Arrays are ops from end to end** (R10 ops and lowering; R15 emits).
- New ops `idr.tabulate`, `idr.fold_last`, `idr.scan_last` and `idr.tabulate_io`, each with a region from indices (and accumulator) to an element. Each carries its iterator kinds and its row-major order and implements `RegionBranchOpInterface`.
- Emit writes these ops, never `scf.for` nests (`Emit/Tensors.idr:162-190`).
- idr-structure-loops becomes their one-to-one lowering once effects are final:
  - a region with no effect beyond Crash, over word elements, becomes `linalg.generic`;
  - otherwise it becomes an ordered `scf.for` nest (a float fold always ordered, as before).
  - The recognizers (`Plans.cpp`, `Generics.cpp`) are deleted. This reverses 0003 D13.
- Arrays of non-word elements never reach linalg, which removes §7's B9.

**D7. One account of how a value moves** (R03; ODS by R02; readers R09, R04).
- The flow interface is declared in the ODS of each of our ops that holds, takes or gives a carrier. Carriers are closures, suspensions and counted references. External models remain only for upstream ops.
- `idr/IR/FlowEdges.h` (R03) declares `FlowEdges`, and `IdrDialect.h` (R02) includes it before the interfaces. IdrInterfaces.td (R01) includes IdrFlow.td.
- Region and branch forwarding is derived once, in `idr::forwardedValues(Operation*, ...)` (Flow.h, R03), from `RegionBranchOpInterface` and `BranchOpInterface`.
- Escapes, Exclusivity, `consumes` (lib/IR/Effects.cpp) and the owned region walk read it, and each filters to the carrier it asks about.
- This deletes the closure-only filter `isKeyed`, the ladders in `Escapes.cpp:257-290` and `Exclusivity.cpp:108-145`, the hard-coded scf list in `consumes`, and the six-op table in `OwnedRegions.cpp:45-58`.

**D8. One type interface for what a value holds** (R01).
- `Idr_ValueFactsTypeInterface` in IdrInterfaces.td: `holdsReferences()`, `holdsWorld()`, `holdsClosure()`, `isCounted()`. It has external models for builtin integer, float, index, memref, tensor and vector types.
- `DataType` computes its answers once, in `setBody`.
- It replaces:
  - `holds()` (`Symbols.cpp:39-60`);
  - `Idr_CountedValueType`'s list (it becomes a constraint calling `isCounted`);
  - the ladders in `Components.cpp:92-145`, `Grades.cpp:204` and `Conversion/Facts.cpp:31-60`;
  - OwnedWalk's cache.
- It fixes `Holds` stopping at arrays, where `mayHoldWorld` misses a world held in an array's elements.

**D9. The runtime ABI is generated from ODS** (R13 generator and runtime; R02 marks ops; R12 consumes).
- `class Idr_Runtime<string symbol>` (IdrBase.td, R01) gives a primitive op its C symbol. Operand and result word kinds come from the op's types, and `noreturn` from its trait.
- `idris-mlir-tblgen -gen-runtime-abi` writes `idris_rt_ops.h` (the C prototypes, which runtime/idris_rt.h includes in place of its hand prototypes for those functions) and `IdrRuntimeAbi.inc` (the table RuntimeCalls.cpp and the folders read).
- Deleted: the suffix logic and the `returnsWord`/`ownLowering` lists (`RuntimeCalls.cpp:45-57,96-114`), the three-name `noreturn` test (`Runtime.cpp:196`), and the folders' hand-named symbols (`Fold/Bigs.cpp:21-37`).
- A mismatch between ODS and the runtime becomes a compile error of the runtime.

**D10. Guards are a trait** (R01 defines; R02 attaches; R13 generates; R15 reads).
- `class Idr_Guarded<string operand, string kind, string cause>` on each partial op. `CheckKind` is an ODS enum, and the string mirror (`IdrCheckOps.td:60-71`) goes.
- Guard ops implement `holds()`. The string index guard takes the string, not a bare length, so `OpsChecks.cpp:229-237` goes.
- R13 generates `guardsOf : IdrOp -> List Guard` into Idris, and Emit's `guardOf` (`Operations.idr:197-247`) is deleted.

**D11. Boxing is decided once, in C++** (R01 Fit; R14 and R15 delete).
- The frontend emits every data instance as `!idr.data`, with no box choice. `layout::fit` boxes by the type graph's components and remakes types through `DataRemap`.
- Deleted: the frontend's cycle finding for boxing (`Graph.idr`'s use there, `Translate/Programs.idr:176-177`) and Emit's `BoxType` choice.

**D12. Grade-only ops are asked, not listed** (R02, R05, R09, R07).
- The roughly fourteen `isa` lists (`Tail.cpp:71`, `IdentitiesRecord.cpp:228`, `Escapes.cpp:282`, `Exclusivity.cpp:135`, `Grades.cpp:122,155`, `Owned.cpp:223`, `Feeds.cpp:43,170`, `Sink.cpp:97`, `Demand.cpp:39`, `Fields.cpp:22`) ask the `ResultCarriesOperand` trait, or `ViewLikeOpInterface` for views.

**D13. One summary per function, one effects driver, no copy on the call** (R07; R02 deletes the call's copy).
- One `idr::Summary` on the ready set's node holds effects, `givesBack`, binding times, constants and inline facts. It replaces the four stores with their four mutexes (`Identities.h`, `Analysis/Specialize.h`, `Constants.h`, `Inline.h`); the wave barrier orders the reads.
- Effects are solved once over the call graph.
- `idr.call` holds no effects: a call's effects are its callee's (`idr::effectsOf(CallOpInterface, SymbolTableCollection&)`, in Func.h, R02). C02's call-site copy and "absent means everything" go.

**D14. idr-rc decides its key set first and clones once** (R09): the `for(;;)` re-solve (`Rc.cpp:82-101`) goes, as 0004 §6 already said.

**D15. No intermediate state the IR can hold** (R02, R10).
- `idr.con` and its reuse form return their destinations as results. The destination-placeholder peeling (`OpsCon.cpp:287-315`) and its readers' special cases go.
- The array element moved out by `get{moves}` is `idr.array.update`, a region op shaped like `memref.generic_atomic_rmw` (R10), replacing the def-use verifier at `OpsArrays.cpp:82-96`.

**D16. A data type without a body is not representable** (R01; R14 for SumKind).
- `DataType::define(ctx, name, llvm::function_ref<Body(DataType self)>)` returns a type with its body. Only the parser and `define` see a bodiless type, so the 16 `hasBody()` guards go.
- The frontend carries the generated `SumKind` directly (its two hand enums, `Types.idr:306,322`, and the collapse at `Emit/Types.idr:28-35` go).

**D17. One memref representation inside a function** (R12).
- Inside a function a memref is lowered by upstream's memref-to-LLVM patterns, on a descriptor built at the use: allocated = cell, aligned = cell + header, sizes and strides from the components.
- The six patterns that redo upstream's work (`Memrefs.cpp:100-280`) go.
- D23's one-pointer components stay at function boundaries and in cell fields.

**D18. Bufferization through upstream's own models** (R11).
- Patch 24 is extended upstream: One-Shot's function-boundary models become written over `FunctionOpInterface`/`CallOpInterface`, not `func::CallOp`. The patch, its report, reproducer, `tests/upstream` check and PINS entry are updated in this change.
- `Bufferize/Functions.cpp`'s re-implementation goes.
- `!idr.lin<T>` implements `TensorLikeType`/`BufferLikeType`, so the grade survives bufferization and the post-hoc `DataRemap` (`Bufferize.cpp:254-263`) goes.

**D19. A big op names its word op in ODS** (R02 marks; R13 generates): one `bigToWord` table replaces `Narrow/Ops.cpp:69-110,163-164`, `Conversion/Bigs.cpp:266` and `RuntimeCalls.cpp:56`.

**D20. Twins in the frontend, and record elements by upstream's one-to-N** (R14, R15, R10).
- `Cmp` is the generated `CmpPredicate`.
- Hooks become a record with one field per hook kind, not `List Hook` read through `firstOf` projections (`Hooks.idr:16-130`, `Terms.idr:369-405`, `Profile.idr:71,282`).
- `ColumnsT` leaves `Ty`. A record array's Core type is `TensorT ds (DataT r)`, and Emit writes `tensor<...x!idr.data<r>>`.
- R10 adds `idr-columns`, which decomposes a tensor of records into one tensor per field by upstream's one-to-N type conversion (signatures, calls, block arguments, the D6 ops, ties) before bufferization. That is the mechanism 0003 D44 named.
- Emit's columns machinery (`Emit/Monad.idr`'s column holding, `fieldsOf`, the per-column cases of `Emit/Tensors.idr`) and the frontend's per-column ties go.

**D21. Dead code and stringly values go:** `Analysis/References.{h,cpp}` and `Holds::mayHoldClosure` (R07, R01); `BigAttr` becomes an `APIntParameter` (R01); `isOne`'s text comparison becomes `m_One()` (R07).

**D23. One canonical text and hash for every content key** (R01; R06, R08 and R12 use it).
- `idr::canonicalText(Attribute | Type | Operation*)` prints with an explicitly built `OpPrintingFlags`: every option set, so no command-line flag reaches it.
- `idr::canonicalHash` is XXH3-128 of that text, memoized per uniqued attribute or type. `ContentNames` keys on it.
- This replaces each lane's own printing of keys (`Specialize.cpp:66-71`, `Consumer.cpp:121-126`, `Decide.cpp:31-38`, `StaticData.cpp:76`).

**D22. Tests state properties** (R18).
- Lowering, canonicalization, folding, effects and guards facts become `idr-expect` properties where the fact is one. The worst directories by FileCheck share are lower 34/36, canon 19/23, fold 14/17, effects 10/13 and guards 8/8.
- Every test module is wrapped in `idr.program` (D3), by script.
- `tests/lower/arrays.mlir`'s stale two-pointer expectation is fixed.
- The rule spellings tests match come from the generated rule list (D4), not from `compile.sh`, `profile.sh` or `common.sh`'s `outside_rules`.
- New property names R18 needs are added to `idr-expect` (R18 owns `lib/Transforms/Expect`).

## 5. What it keeps (judged justified by the audit)

- XXH3 in both halves: the same algorithm over different keys, pinned to the published vectors on both sides.
- Our own 0CFA label solve: upstream's sparse dataflow sends an indirect callee to the entry state, which is the unknown element 0004 deleted.
- `Support/Scc.cpp`, an adapter over `llvm::scc_iterator`.
- `idr.tie_shape`.
- The inliner's caller cap (a policy).
- D23's one-pointer components at boundaries.

## 6. Lanes

Each owns its writes outright (`ownership.json`). Paths under `foreign/idr/` unless shown as `compiler/src/IdrisMLIR` (`SRC/`) or the root.

| Lane | Owns | Decisions | §7 bugs |
| --- | --- | --- | --- |
| R01 types | IR/IdrTypes.td, IdrAttrs.td, IdrBase.td, IdrInterfaces.td; IR/Symbols.h, TypeGraph.h, Layout.h, Grades.h; lib/IR/Types.cpp, Attrs.cpp, ConAttr.cpp, TypeGraph.cpp, Symbols.cpp, Grades.cpp, Asm.cpp, Layout/*; Analysis/Holds.{h,cpp} | D1, D4 layout, D8, D9/D10 trait classes, D11, D16, D21 BigAttr | |
| R02 ops | IR/IdrOps.td and every op .td but IdrArrayOps.td and IdrFlow.td; IR/IdrDialect.h, Func.h, Ownership.h, Ranges.h; lib/IR/Dialect.cpp, Ops*.cpp but OpsArrays.cpp, Func/*, Constants.cpp, Crashes.cpp, Regions.cpp, Ranges.cpp | D1 op side, D2 ops, D3 ProgramOp, D7 ODS declarations, D9/D10/D19 marks, D12, D13 (call copy), D15 con | B16 (OpsCon part) |
| R03 flow | IR/IdrFlow.td, Flow.h, FlowEdges.h (new); lib/IR/Flow.cpp, Effects.cpp; Analysis/Escapes.h, Escapes.cpp, EscapesCycles.cpp, Ownership/Exclusivity.cpp | D7 | |
| R04 verify | IR/Verify.h; lib/IR/Verify/* | D3 verifier, D7 owned walk | B2 |
| R05 canon-fold | IR/Canon.h, Fold.h; lib/IR/Canon/*, Fold/* | D1, D9 folders, D12 | B16 (Captures part) |
| R06 defunc | Transforms/Defunctionalize.h, lib/Transforms/Defunctionalize/*; Analysis/Labels.h, Labels.cpp, LabelSites.cpp | D1, D2, D3 stage | |
| R07 optimizer | Transforms/Optimize.h, Effects.h, Inline.h, Identity.h; lib/Transforms/Optimize/*, Effects/*, Inline/*, Identity/*; Analysis/Effects, Constants, Identities, Inline, Specialize.h, References (delete) and their .cpp, BindingTimes.cpp | D2 graph, D12, D13, D21 | middle-end hunt |
| R08 specialize | Transforms/Specialize.h, Deduplicate.h; lib/Transforms/Specialize/*, Deduplicate/* | D1, D2 renames, D4 whistle | middle-end hunt |
| R09 memory | Transforms/Ownership.h, Stack.h, Tail.h, Narrow.h, Demand.h; lib/Transforms/Ownership/*, Stack/*, Tail/*, Narrow/*, Demand/*; Analysis/Ownership.h, Ownership/* but Exclusivity.cpp, Tail.{h,cpp}, Ranges.{h,cpp} | D3 stage, D7 readers, D12, D14 | B3, B5, B12, B13, B21 borrows |
| R10 arrays | IR/IdrArrayOps.td; lib/IR/OpsArrays.cpp; Transforms/StructureLoops.h, lib/Transforms/StructureLoops/* (+ Columns) | D6, D15 update, D20 idr-columns | B9 |
| R11 bufferize | Transforms/Bufferize.h, BufferizeModels.h; lib/Transforms/Bufferize/*; upstream/24-* | D18 | B6, B7, B14, minor |
| R12 lowering | include/idr/Conversion/*, lib/Conversion/* | D2 lowering, D3 erase, D4 driver, D9 consume, D17 | B4, B8, B17, B18 driver, B21, minor |
| R13 generator | tools/idris-mlir-tblgen.cpp; runtime/*; SRC/Syntax/*, SRC/Dialect/* | D4 categories, D9, D10, D19 generation, regeneration | |
| R14 frontend | SRC/Frontend/**, SRC/Registry/**, SRC/Registry.idr, Graph.idr, Types.idr, Facts.idr, Term.idr, Ids.idr, Loc.idr | D4 frontend, D5 registry, D11, D16, D20 | B10 part, B18, B19, B20 |
| R15 emit | SRC/Emit/**, SRC/Emit.idr, MLIR.idr, MLIR/**, SyntaxSamples.idr; upstream/25-bytecode-unregistered-properties (new) | D3 emit, D4 Emit fuel, D6 emit, D10, D11, D20 | B1, B10, B11, B15 |
| R16 libs | libs/** | D5 | library friction |
| R17 pipeline | Transforms/Passes.td, Pipeline.h, lib/Transforms/Pipeline.cpp; include/idr/Target/*, lib/Target/*; include/idr/Driver/*, lib/Driver/*; include/idr/Support/*, lib/Support/*; tools/idris-mlir.cpp, idris-mlir-opt.cpp, idris-mlir-reduce.cpp; tools/self.sh, tools/host.sh | D3 anchors and nesting | B21 schedules, IdrRc dialects, `make self`'s `.mlirbc`, host.sh peak memory |
| R18 tests | tests/**; lib/Transforms/Expect/*, Transforms/Expect.h | D4 spec, D22 | |
| coordinator | every CMakeLists.txt, CMakePresets.json, Makefile, AGENTS.md, README.md, HANDOFF.md, PINS.md, proposals/**, upstream/README.md, bench/**, tools/*.sh but self.sh and host.sh, compiler/idris-mlir.ipkg, compiler/idris/** | build lists, regeneration, the stale texts of §8, integration | |

## 7. Bugs found by reading (2026-10-15), by owner

Back end and frontend:
- **B1 (R15, crash, every program).** `MLIR/Bytecode.idr:276-283,429` writes properties as an attribute of an op marked unregistered. The pinned reader tests `if (wasRegistered)` on a `std::optional<bool>` (`BytecodeReader.cpp:2597`), so that branch is dead and the number is read as a properties index.
  - Write each op's inherent attributes in its attribute dictionary, with no `kHasProperties`; `Operation::create` moves them into properties. That is the honest encoding: a registered op is not claimed unregistered.
  - The reader bug is upstream's: report it as `upstream/25-bytecode-unregistered-properties/` with its reproducer and `pull-request.diff` (`*wasRegistered`). Nothing in the tree then reaches it, so no patch is carried. C22 §2 is corrected.
- **B2 (R04, crash).** The owned verifier rejects every buffer value (`Verify/Owned.cpp:263-270`). Views are views of their `readFrom` source, and alloc/give results are untracked. D3 restates which grades are legal at `owned`.
- **B3 (R09, crash).** `memref.get_global` is retyped owned (`Placement.cpp:110`); `isStatic` accepts it.
- **B4 (R12, race).** `LowerToLLVMOptions` is built inside the workers on a shared `DataLayout` cache (`Runtime.cpp:58-61`, `Lower.cpp:259-263`); build it once, serially.
- **B5 (R09, use-after-free).** `usedAfter` and `aliveAt` let an owner die while a view of it is read in a loop (`Classes.cpp:57-72`, `Uses.cpp:53-70`, `Placement.cpp:160-205`). Ask about the user's ancestor in the owner's block.
- **B6 (R11, miscompile).** A released buffer can be overwritten by a later write-only op: two `tensor.empty` merged by CSE, or a buffer escaping through `lin.enter`, `idr.con` or a storing call (`Linear.cpp:45-55`, `Data.cpp:29-38`).
- **B7 (R11, miscompile).** A call result is always a writable fresh buffer (`Functions.cpp:168-246`). D18 replaces the file; the replacement must record non-writable results.
- **B8 (R12, UB).** Element loads and stores claim alignment 8 (`Words.cpp:32-34`); use `MinAlign(MinAlign(8, stride), offset)`.
- **B9 (R10, internal error).** linalg over non-word elements (`Plans.cpp:13`); D6 removes it.
- **B10 (R15 with R14, internal error).** A static-extent lambda against a dynamic closure parameter type (`Bodies.idr:378-389`, `Tensors.idr:156`, `Translate/Types.idr:496`).
- **B11 (R15).** Array results of closures are never cast back to static types (`Bodies.idr:390-431`, `Tensors.idr:277,280`).
- **B12 (R09).** Exclusive grades are not met at `scf.for` inits and yields (`Commit.cpp:72-81`).
- **B13 (R09).** Unused counted loads made by `linalgOpToLoops` get no dup (`Reshape.cpp:135`).
- **B14 (R11).** `thaw (freeze la)` is forced in place (`Linear.cpp:29-41`).
- **B15 (R15).** A tabulation whose body never returns leaves `ub.unreachable` mid-block (`Tensors.idr:527-536,656-657`). D6's region op makes it the region's terminator.
- **B16 (R02, R05).** `idr.con` folds around a dense tensor to a constant the verifier rejects (`OpsCon.cpp:101-113`, `Canon/Captures.cpp:17-20`); exclude shaped types.
- **B17 (R12).** Constant names depend on printer flags (`StaticData.cpp:76`, `StaticNames.cpp:29-34`); key on raw data and type.
- **B18 (R14, R12).** The count refusals of D4, and the greedy driver's iteration limit at `Lower.cpp:206-208`.
- **B19 (R14).** Two instances can get one symbol (`Keys.idr:470-482`, `Term.idr:434-443`); write a marker for each non-keying position.
- **B20 (R14).** Linearity is dropped at hook and tie sites (`Shapes.idr:214,264,307`); bind at the binder's quantity, and take witnesses only from Many arguments.
- **B21 (perf; R09, R12, R17).**
  - A self tail call passing `arr[i]` loses its tail call (`Borrows.cpp:169-177`).
  - Returning an element owns the whole buffer parameter (`Borrows.cpp:150-161`).
  - A static datum's drop still calls `idris_rt_dec` (`Counting.cpp:44-55`).
  - The constant is re-printed at every use (`StaticData.cpp:76`).
  - The widest-word count ignores `index` (`Schedules.cpp:88-104`).
- **Minor:**
  - `IdrRc` declares no dependent dialects (R17);
  - EmptyTensorElimination never reaches `reportAnalysisFailure` (R11);
  - `Bufferize.cpp:262` ignores DataRemap's status (R11);
  - Phase 0's `walkAndApplyPatterns` never signals failure (R12);
  - `toMemref` is null for `#idr.world` (R12);
  - a non-dense `memref.global` initializer is an internal error (R12);
  - `Reshape.cpp:40-41` (R09);
  - the HANDOFF gaps: a suspension of an array of records (D20 removes the columns case) and a cell with dynamic extents (R15, R10).

Middle end:
- **M1 (R03, crash, every program).** `Flow.cpp:357-359`: `getBeginOperandIndex()` on an empty forwarded list asserts, and `idr.match` passes no operands into its regions. Build the range as upstream's `operandsToOpOperands` does.
- **M2 (R01, heap corruption).** `TypeGraph.cpp:120`: `edges[from].push_back(insert(type))` holds a reference across a reallocation.
- **M3** is B2.
- **M4 (R04, race).** `Owned.cpp:303-304` builds module-wide `Layouts` inside the per-function verifier. Size the cells from their own types, or move the rule to the program verifier.
- **M5.** A memo label function is erased while forces of its type remain (`Optimize.cpp:76-121`, `Force.cpp:44-51`). D2 removes it: the dispatch function calls every label. R01 also makes `DataType`'s sub-element walk visit each `fn`, so symbol uses see labels.
- **M6 (R07, R08).** A raise node gets a component with no edges and becomes final before the functions it calls (`Waves.cpp:79-96`, `Consumer.cpp:59-116`). The node waits on, or merges with, its requester's component.
- **M7 (R08).** A constant list is unrolled into a key as deep as the list and printed quadratically (`Keys.cpp:71-81`, `Specialize.cpp:66-71`). Keys are named by D23's canonical hash, memoized, and runs stay runs.
- **M8 (R07, count refusal).** `arith` int-range optimization in the inner pipeline fails the pass when its greedy driver does not converge in 10 rounds, and does almost nothing inside an `idr.func`. Drop it from the inner pipeline; narrowing is idr-narrow's.
- **M9 (R06, UB).** `Declare.cpp:28-34`: `sumOf` reads past `end()` for types `noteType` never noted. `noteType` walks every sub-type.
- **M10 (R07, nondeterminism).** Constant summaries are published mid-wave (`Component.cpp:138`, `Constants.cpp:46-52`). D13's summary is published in `settle`.
- **M11 (R01; used by R06, R08, R12; miscompile under debug flags).** Content keys printed with flags the command line can change (`Specialize.cpp:66-71`, `Consumer.cpp:121-126`, `Decide.cpp`, `StaticData.cpp:76`). That is D23.
- **M12 (R02).** A force before defunctionalization declares no crash or diverge (`OpsClosures.cpp:225-235`). Ruling: a force is strict like a call, so it declares both unless by-name proves otherwise. After defunctionalization D2 makes it a call.
- **M13 (R04, count refusal).** `Owned.cpp:73` and `OwnedLoops.cpp:118` stop after 1024 steps on acyclic chains. Delete the caps.
- **M14 (R01, leak).** Value arrays have no type-graph edge, so a knot through an array is accepted (`TypeGraph.cpp:107-121`).
- **M15 (R07, R08).** The static-label rule is dead (`Analysis/Effects.cpp:115-137`); delete it. Dedup never merges labels whose by-name differs.
- **M16 (R08).** The unroll limit applies to `IntegerType` only (`Patterns.cpp:156-165`). D4's request-chain rule replaces the limit, for every integer kind.
- **M17 (perf).**
  - R06: Labels' interned difference sets, and `keyText` re-printing shared DAGs.
  - R03: `verifyFlow` on every pass; by D3 it runs only at stage `higher`.
  - R08: a consumer printed for each candidate.
- **M18 (R07, R08).** `DebugCounter`/action logging on worker threads: threading is off while either is active.
- **M19 (minor).**
  - R01, R11: `DataRemap::status()` is ignored.
  - R01: a remade type's key omits nested replacements.
  - R01 D8: `holdsReferences` matches `VectorType`.
  - R07: Constants marks everything preserved.
  - R08: Report.cpp disagrees on force-only cycles.
  - R07: BindingTimes counts default-region arguments as proper parts.
- **M20 (R18).** `dedup/keep-apart.mlir`, `canon/facts.mlir` and `effects/memo-label.mlir` contradict the call verifier and C10; D13 changes all three anyway.

Library friction (R16):
- every constructor needs a fill value, even at size 0;
- `Vec.pop` keeps the popped element referenced;
- `freeze` copies through `take`;
- take, drop, `++` and pad work on the last axis only, and there is no `transpose`;
- there is no linear map, fold or traverse over `LArray`;
- naming clashes (`shape`/`lshape`, `read`/`write` against Vec's);
- `unzipWith` applies `f` twice;
- `foldr` goes through `toList`.

R16 fixes what D5 lets it fix: a linear traverse and fold over the generating set, `transpose` as a generating function (a `linalg.transpose`, R10's lowering), and Vec's pop moving the element out.

## 8. Coordinator's work in the wave

- Build lists; regeneration (`make typecheck`); `make check` to green; one commit and push at each green point.
- The stale texts the chain reader found: the status lines of proposals/README.md, 0003, 0012 and 0001; the claims that 0003 stage 1 comes after `make self`; the instance budget in 0007 and 0009; process-per-module in 0007 and 0010; 0008's constants; the Presburger patch and `kClonesPerOwner` references.
- 0004 D28 and 0003 D13 marked reversed by D3 and D6.
- HANDOFF.

## 9. The owner's questions, each with its default taken

1. **C++ refusals.** AGENTS.md says the only refusals are the frontend's, but `Rule::Cycle` (`Verify/Knots.cpp:99`, a reference knot that counting would never free) and `Rule::Uniqueness` (`Demand.cpp:89`, a library's in-place promise that exclusivity cannot meet) are refused in C++, each by a total analysis and not by a count. Default: keep both, with category `OutsideLanguage` (D4), and say so in AGENTS.md at integration.
2. **The fill value at size 0** (R16): default, keep it. An uninitialized slot is a state the representation should not hold.

## 10. Gate

On this machine: `make typecheck` every part and `make check` green, at integration. On the owner's machine, HANDOFF's list, now against this wave's tree:
- bootstrap (patch 24 changed);
- build;
- the three suites, with the NEEDS-ACCEPTANCE files;
- determinism at 1, 2 and 8 threads;
- the bench;
- `make self`.
