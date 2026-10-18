<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# The 0004 packet, audited against MLIR's own patterns

**Status:** an audit, 2026-10-17, at the owner's request ("audit our entire
swarm proposal against mlir patterns, and make sure our representation
first refactor is mlir aware"; "we can push the heavy lifting to mlir, and
push harder on our types to be representation first"). It grades every §4
contract and every finding's correction against MLIR's own patterns,
inventories the home-rolled mechanisms of `foreign/idr` against their
upstream equivalents, and adds the defects no survey found as
[findings/mlir.md](findings/mlir.md). The standard is S3's: values and
memory at different levels, one op per semantics with its effects in ODS,
shared shapes as interfaces, analyses on the analysis manager and the
dataflow solver, passes and their stages in `Passes.td`.

**Ground.** Read-only, at the packet's base. Every upstream `path:Symbol`
was found by grep in the pinned tree (`.toolchain/llvm-project`, llvm main
7208ba24); paths are relative to it. Every source line cited was read.
Nothing was built or run.

**Edits made to README §4** (where the evidence fixed the MLIR form): S1
(`getTakenRegion` off the interface), S2 (region order ODS accepts,
`MaxSizedRegion<1>`; the default argument declared through
`RegionBranchOpInterface` was later withdrawn, see the S2 row), S3 (realloc's effects on `idr.cell.recycle`, the
cell type's parameters, holes and destinations off `idr.con`, inferred
results on `idr.cell.init`, idr-stack after idr-rc and the escape analysis's
address rule, the cell's lowering), S13 (built on upstream's `CallGraph`),
S16 (the per-op specialization, not a table keyed by op), S22 (keys stay
uniqued attributes), S27 (the stage in a generated base class). Proposed and
left to the owner: S4's split (mlir-5), S25's transport, mlir-12's reversal
of D13.

## §4 contracts

| Contract | Verdict | MLIR mechanism (pinned `path:Symbol`) | Correction |
|---|---|---|---|
| S0 generated names | acceptable | `mlir/include/mlir/TableGen/Operator.h:Operator` (the generator reads ODS records) | As written. |
| S1 match interface | MLIR-native, one method too many | `mlir/include/mlir/Interfaces/ControlFlowInterfaces.td:RegionBranchOpInterface` (`getEntrySuccessorRegions` with constant operands); `mlir/include/mlir/IR/Interfaces.td:OpInterface` | **Made:** `getTakenRegion` is off the interface; it is upstream's `getEntrySuccessorRegions` asked with the constant, which the base class already answers through it (`Regions.cpp:56-82`); its one outside caller (`Canon/MatchPatterns.cpp:104`) asks that. |
| S2 match regions | fought ODS: would not build | `mlir/lib/TableGen/Operator.cpp` ("only the last region can be variadic"); `mlir/include/mlir/Dialect/SCF/IR/SCFOps.td:IndexSwitchOp` (default first), `SCFOps.td:IfOp` (`MaxSizedRegion<1>:$elseRegion`); `mlir/include/mlir/IR/OpBase.td:MaxSizedRegion` | **Made:** `(region <default>:$defaultRegion, VariadicRegion<SizedRegion<1>>:$caseRegions)`, `<default>` `MaxSizedRegion<1>` for `idr.match` (not `AnyRegion`), `SizedRegion<1>` for `idr.match_lit`; the default is region 0. **Withdrawn** (the coordinator, for the owner's review; README §9 B12): declaring the default region's argument through `RegionBranchOpInterface` (`getEntrySuccessorOperands`, `getSuccessorInputs`, mlir-9). The matches register upstream's region-branch canonicalizations (`OpsMatch.cpp:192,200`); given that edge, `ControlFlowInterfaces.cpp:718-760` replaces the argument by the scrutinee, a second use of a linear value the match consumed, and `:859-990` erases an unused argument together with the scrutinee operand. The argument stays a fresh binding whose predecessor is not declared, read as `Same` by S11's own rule. |
| S3 cells | MLIR-native, with five gaps | `mlir/include/mlir/Dialect/MemRef/IR/MemRefOps.td:AllocLikeOp`, `MemRef_AllocaOp`, `MemRef_ReallocOp`; `mlir/include/mlir/Interfaces/SideEffectInterfaces.td:MemAlloc`, `MemFreeAt`; `mlir/include/mlir/Dialect/Bufferization/Transforms/Passes.td:PromoteBuffersToStackPass`; `mlir/include/mlir/Interfaces/InferTypeOpInterface.td:InferTypeOpInterface` | **Made:** (1) `idr.cell.recycle` has exactly `memref.realloc`'s effects, `MemFreeAt<0, FullEffect>` on the token and `MemAlloc<DefaultResource, 1, FullEffect>` on the result (the text said "as realloc" but wrote Read/Write); (2) the cell type's parameters are `(BoxType, Tag)`: data types are named `MutableType`s and constructors tags, never symbols; (3) `idr.con` loses `holes`/`$dests` too: a hole is memory, made only by idr-trmc after idr-rc (`Trmc.cpp:87`, `Pipeline.cpp:99,102`); (4) idr-stack moves after idr-rc, where `idr.cell.new` exists (it ran before, `Pipeline.cpp:94`), as upstream promotes `memref.alloc` to `alloca` after bufferization; Escapes, already an upstream sparse backward analysis, must then follow addresses where the owned stage's flow edges follow references only (`idr.share` releases its operand though its result is the same cell, `FlowOps.cpp:213-215`), or a cell escaping through a share is put on the stack; (5) `idr.cell.init` infers its results (`InferTypeOpInterface`), deleting the hand inference in `parseDests`, two builders and `verifyHoles`. |
| S4 take | acceptable; by S3's standard, three ops in one | `OpBase.td:AttrSizedResultSegments`; an optional result is upstream practice (`mlir/include/mlir/Dialect/GPU/IR/GPUOps.td:GPU_AllocOp`'s `$asyncToken`); the split's precedent `mlir/include/mlir/Dialect/Tensor/IR/TensorOps.td:Tensor_ExtractOp` vs `MemRefOps.td:LoadOp` | **Proposed:** mlir-5. `LowerTake` has three bodies by operand type and ODS declares the cell's `MemFree` for all three; `idr.take` (a cell: token always, no segments) and `idr.unpack` (an unboxed sum or an atom: no memory effect). The owner weighs it as D-A was weighed. |
| S5 one block | MLIR-native | `OpBase.td:SizedRegion`; `mlir/include/mlir/Transforms/RegionUtils.h:eraseUnreachableBlocks`; `mlir/lib/Transforms/InlinerPass.cpp` (`runPipelineHelper`: upstream cleans a callable after inlining with a pipeline, not inside the inliner) | As written. It also answers review D-C: upstream's own inliner leaves the dead block to a cleanup after it, so the erase at our two sites is upstream's shape, not a workaround of an upstream bug. |
| S6 effects property | MLIR-native | `mlir/include/mlir/IR/EnumAttr.td:EnumProp`; `mlir/include/mlir/IR/Properties.td:DefaultValuedProp` | As written. |
| S7 effects of a body | acceptable | `mlir/include/mlir/Interfaces/SideEffectInterfaces.h:SideEffects::Resource`; a function-level summary has upstream precedent in `mlir/include/mlir/Dialect/LLVMIR/LLVMAttrDefs.td:LLVM_MemoryEffectsAttr` | As written; with ir-verify-9's fix (`idr.force` declares a valueless read, and MoveOut's `isa<ForceOp>` goes). |
| S8 runs-labels interface | acceptable | `mlir/include/mlir/Interfaces/CallInterfaces.td:CallOpInterface` (an indirect call's `getCallableForCallee` is a `Value`, as `mlir/include/mlir/Dialect/Func/IR/FuncOps.td:CallIndirectOp`) | As written. `idr.apply` already implements `CallOpInterface` with the closure as its callee (`IdrClosureOps.td:91,113`), so its `getLabelCarrier` is that value; a `CallOpInterface` on `idr.force` would make the interface redundant but costs it argument and result attributes it has no use for. |
| S9 stage facts | acceptable | the stage is an inherent enum of `idr.program` (`IdrOps.td:46,67`), not a discardable attribute | As written. |
| S10 world type | MLIR-native | `mlir/include/mlir/IR/AttrTypeBase.td:TypeDef`; `Interfaces.td:TypeInterface` | As written. |
| S11 structural source | acceptable | `mlir/include/mlir/Interfaces/ViewLikeInterface.td:ViewLikeOpInterface` (`idr.borrow` has it) | As written; ir-verify-11's flow edges already carry `Field` (`Part{Whole, Field}`), so `sourceOf` may read them rather than a new ladder. |
| S12 range a type proves | MLIR-native | `mlir/include/mlir/Analysis/DataFlow/IntegerRangeAnalysis.h:IntegerRangeAnalysis` (`setToEntryState`, overridden in `Analysis/Ranges.cpp`) | As written. |
| S13 call cycles | MLIR-native once built on upstream's graph | `mlir/include/mlir/Analysis/CallGraph.h:CallGraph` (`GraphTraits<const mlir::CallGraph *>`); `llvm/include/llvm/ADT/SCCIterator.h:scc_iterator::hasCycle`; `mlir/include/mlir/Pass/AnalysisManager.h:AnalysisManager::getAnalysis`; precedent `mlir/lib/Transforms/Utils/Inliner.cpp` (`scc_begin(&cg)`) | **Made:** built from the cached `CallGraph` with `llvm::scc_begin`, not by re-indexing the graph for `idr::components`; `callsItself` is `hasCycle()`; invalidated with `CallGraph`. |
| S14 binding time | acceptable | none | As written. |
| S15 runtime ABI | MLIR-native | LLVM declares its runtime calls the same way: `llvm/include/llvm/IR/RuntimeLibcallsImpl.td:RuntimeLibcall`, emitted by a TableGen backend | As written (upstream picks a runtime variant per op the same way: `mlir/lib/Conversion/GPUCommon/OpToFuncCallLowering.h:OpToFuncCallLowering`, `mlir/include/mlir/Conversion/GPUCommon/GPUCommonPass.h:FunctionCallBuilder`). Declarations stay deferred to `Runtime::merge`: `mlir/include/mlir/Dialect/LLVMIR/FunctionCallUtils.h:lookupOrCreateFn` inserts into the module and is not safe from parallel workers. Build each call with `llvm.call`'s `(LLVMFunctionType, StringAttr, ValueRange)` builder from the table, so `LLVM::CallOp::verifySymbolUses` checks every call against the one merged declaration, and drop the proposed assertion in `Runtime::call` (conversion-2). |
| S16 guards | regressed from its finding | `mlir/include/mlir/IR/OpBase.td:ParamNativeOpTrait`; `mlir/include/mlir/Interfaces/SideEffectInterfaces.td:ConditionallySpeculatable` | **Made:** the generated per-op specialization `idr::Guarded<Op>` (ir-ods-2's form), read at compile time; not `guardOf(Operation *)`, a table keyed by op that redoes MLIR's per-op dispatch by hand. A query on an `Operation *` is an op interface. |
| S17 declared facts | MLIR-native | `mlir/include/mlir/IR/CommonAttrConstraints.td:DenseArrayStrictlySorted`, `DenseArrayNonNegative`; `SideEffectInterfaces.td:MemRead`/`MemWrite`/`MemAlloc` on `Arg`/`Res` | As written. |
| S18 one constant form | MLIR-native | an untyped value whose type the op holds, as `mlir/include/mlir/Dialect/Complex/IR/ComplexOps.td:ConstantOp` | As written. |
| S19 data body | acceptable | none (C++ data in a `MutableType`'s storage) | As written. |
| S20 component walk | MLIR-native | `mlir/include/mlir/Transforms/DialectConversion.h:TypeConverter` (1:N `addConversion`, fed by `Layouts::components` at `Conversion/Lower.cpp:91-97`) | As written. |
| S21 show split | MLIR-native, flag left | `mlir/include/mlir/Dialect/Arith/IR/ArithOps.td:Arith_DivSIOp`/`Arith_DivUIOp` | As written for the Double; `show_int` keeps `is_signed`, which mlir-1 splits (three ops). |
| S22 keys | fought MLIR: re-implemented the uniquer | `mlir/include/mlir/Support/StorageUniquer.h:StorageUniquer`; `mlir/include/mlir/IR/AttrTypeSubElements.h:AttrTypeReplacer` | **Made:** the keys stay attributes. The specializer's memo tables are keyed by attribute identity (`Transforms/Specialize.h:291,296`), so C++ keys would need hand hashing, equality and interning; the export the survey objected to goes by `bit idris = 0` (ir-ods-12's own correction), and a hole loses its index and a raise key holds a digest, as before. |
| S23 Core | acceptable (Idris) | none | As written. |
| S24 location sum | acceptable (Idris) | its cases map onto `mlir/include/mlir/IR/BuiltinLocationAttributes.td:UnknownLoc`, `NameLoc`, `FileLineColRange` | As written; idris-emit-8's `Place` is the sum, and mlir-7 writes it through the builtin records. |
| S25 refusal record | the record is right; the transport fights MLIR | `mlir/include/mlir/IR/Diagnostics.h:Diagnostic::getMetadata`, `ScopedDiagnosticHandler`, `SourceMgrDiagnosticVerifierHandler` | **Proposed** (D1 is the owner's): C++ refusals already go through the diagnostic engine with the rule as `RuleAttr` metadata (`Attrs.cpp:40-55`) and one fold decides the verdict (`Driver/Outcome.cpp:142`). Text lines the driver parses are a second channel. The frontend writes its refusals as typed data (an `#idr.refusal<rule, loc, message>` attribute, L17) in its bytecode, and the driver re-emits each with `idr::refuse(loc, rule)`, so `foldDiagnostics` alone decides the verdict and writes the report. |
| S26 idr-expect table | acceptable | `mlir/include/mlir/Pass/PassOptions.h:PassOptions::ListOption` (any `T` with a `cl::parser<T>`) | As written, parsed at the option boundary: a malformed property then fails when the pipeline is parsed, before any pass runs (transforms-a-1). Whether the harness itself should be `-verify-diagnostics` over remarks is in the inventory below. |
| S27 pass stage | MLIR-native either way; the base class chosen | `mlir/include/mlir/Pass/PassBase.td:PassBase` (`baseClass`, as `InterfacePass` uses it); `mlir/tools/mlir-tblgen/PassGen.cpp`; `mlir/include/mlir/Pass/PassInstrumentation.h:PassInstrumentation::signalPassFailure` (honoured by `mlir/lib/Pass/Pass.cpp:OpToOpPassAdaptor::run`) | **Made:** `IdrPass<..., requires, sets>` sets `baseClass` to `::idr::StagedPass<anchor, requires, sets>`, whose `final` `runOnOperation` refuses another stage (`emitError`, `signalPassFailure`), runs `runOnProgram` and sets the stage; the two hand checks and three hand `setStage` calls go. An instrumentation could fail the pass too (transforms-b-6's form), but holds only in the tools that install it and cannot set the stage without writing IR. A function-anchored pass never sets a stage. |
| S28 hub files | n/a (process) | | |
| S29 shared ODS spellings | MLIR-native | TableGen record fields read by a backend (`llvm/include/llvm/TableGen/Record.h:Record::getValueAsString`, `isSubClassOf`) | As written. |
| S30 reserved names | acceptable | `mlir/include/mlir/IR/SymbolTable.h:SymbolTable::insert` (renames on collision) cannot serve: the workers' `llvm.mlir.addressof @n`, made before the merge, share a name with any program symbol `n`, and C names cannot be renamed | As written; except `@__idr_main`, made and named once in Entry, which needs no reserved name: `SymbolTable::insert` it and use the returned name, as `mlir/lib/Dialect/Bufferization/Transforms/BufferUtils.cpp:getGlobalFor` does. |

## Findings

Verdicts: **MLIR-native** (the correction uses the upstream mechanism as
upstream does); **acceptable** (no MLIR mechanism applies, or plain data
that does not fight MLIR; most Idris-side findings); **fighting MLIR** (the
correction keeps or adds what an MLIR mechanism already does, or a flag
switches an op's meaning). "As written" means no change to the finding's
correction. Paths are under `.toolchain/llvm-project/`.

### ir-ods

| Finding | Verdict | MLIR mechanism | Correction |
|---|---|---|---|
| ir-ods-1 | MLIR-native | `mlir/include/mlir/IR/Interfaces.td:OpInterface`; `mlir/include/mlir/Interfaces/ControlFlowInterfaces.td:RegionBranchOpInterface` | As S1 (made): `getTakenRegion` off the interface. |
| ir-ods-2 | MLIR-native | `mlir/include/mlir/Interfaces/SideEffectInterfaces.td:ConditionallySpeculatable`; the generated `FoldAdaptor` | As written; S16 now takes this finding's static `idr::Guarded<Op>`. |
| ir-ods-3 | MLIR-native | `mlir/include/mlir/IR/AttrTypeBase.td:TypeDef`; `Interfaces.td:TypeInterface` | As S10. |
| ir-ods-4 | fighting MLIR (as found), native as corrected | `SideEffectInterfaces.td:MemoryEffects`, `MemWrite`; `mlir/lib/Interfaces/SideEffectInterfaces.cpp:isSpeculatable` | As written: `Idr_MayCrash<bit allocates>` is a bool trait parameter that switches an op's effects; the correction declares each op's effects. |
| ir-ods-5 | MLIR-native | `mlir/include/mlir/IR/OpBase.td:TypesMatchWith`, `PredOpTrait` | As written, except `big.from_int`, which mlir-1 splits rather than keep a flag under a `PredOpTrait`. |
| ir-ods-6 | acceptable | `mlir/include/mlir/Transforms/DialectConversion.h:TypeConverter` (1:N, already fed by `components`) | As S20. |
| ir-ods-7 | acceptable | none (data in a `MutableType`'s storage) | As S19. |
| ir-ods-8 | MLIR-native | an untyped value with the op's type, as `mlir/include/mlir/Dialect/Complex/IR/ComplexOps.td:ConstantOp` | As written (with ir-ops-11). |
| ir-ods-9 | MLIR-native, ODS spelling corrected | `mlir/lib/TableGen/Operator.cpp` (the last region alone may be variadic); `SCFOps.td:IndexSwitchOp`, `IfOp` | As S2 (made): default first, `MaxSizedRegion<1>`. |
| ir-ods-10 | acceptable | `OpBase.td:NativeOpTrait` | As written. |
| ir-ods-11 | MLIR-native | TableGen record fields read by a backend (`llvm/include/llvm/TableGen/Record.h:Record::getValueAsString`) | As S29(b). |
| ir-ods-12 | MLIR-native | `mlir/include/mlir/Support/StorageUniquer.h:StorageUniquer` | As written (`bit idris = 0`); S22 (made) returns to it. |

### ir-ops

| Finding | Verdict | MLIR mechanism | Correction |
|---|---|---|---|
| ir-ops-1 | MLIR-native | `SideEffectInterfaces.td:MemRead`/`MemWrite`/`MemAlloc` on `Arg`/`Res`; `mlir/include/mlir/IR/CommonAttrConstraints.td:ConfinedAttr`, `DenseArrayNonNegative`, `DenseArrayStrictlySorted` | As written; the `holes` constraint moves to `idr.cell.init` (S3). |
| ir-ops-2 | MLIR-native | `ControlFlowInterfaces.td:RegionBranchTerminatorOpInterface`; an `OpInterface` on the parent | As written. |
| ir-ops-3 | acceptable | `DialectConversion.h:TypeConverter` | As S20. |
| ir-ops-4 | acceptable | `AttrTypeBase.td:ArrayRefParameter` | As S18. |
| ir-ops-5 | fighting MLIR (superseded) | `mlir/include/mlir/Dialect/MemRef/IR/MemRefOps.td:AllocLikeOp`, `MemRef_ReallocOp` | S3: one op per source of a cell, not an interface over two cell builders. |
| ir-ops-6 | MLIR-native | `mlir/include/mlir/Interfaces/InferTypeOpInterface.td:InferTypeOpInterface` | As S4; see mlir-5 for the take's split. |
| ir-ops-7 | MLIR-native | `mlir/include/mlir/IR/AttrTypeSubElements.h:AttrTypeReplacer` | As written. |
| ir-ops-8 | MLIR-native | a typed `TypeDef` parameter | As written; after S3 the destinations are inferred on `idr.cell.init`. |
| ir-ops-9 | MLIR-native | a custom directive parameterized by a C++ string (`$_ctxt`) | As written. |
| ir-ops-10 | MLIR-native | `Interfaces.td:TypeInterface`; an external model on `IntegerType` (`mlir/include/mlir/IR/StorageUniquerSupport.h:attachInterface`) | As written. |
| ir-ops-11 | MLIR-native | as ir-ods-8 | Merged with ir-ods-8. |
| ir-ops-12 | acceptable | none | As written. |
| ir-ops-13 | MLIR-native | the generated `FoldAdaptor` | As written, inside S16's generated relation. |
| ir-ops-14 | MLIR-native | `RegionBranchOpInterface::getEntrySuccessorOperands` | As S2. The default argument's declaration through the interface (mlir-9) is withdrawn; see the S2 row. |
| ir-ops-15 | fighting MLIR (half) | `mlir/include/mlir/Dialect/Arith/IR/ArithOps.td:Arith_ExtSIOp`/`Arith_ExtUIOp` | The split of `show` is right (S21); the flag on the other nine ops is mlir-1. |
| ir-ops-16 | MLIR-native | as ir-ods-3 | As S10. |

### ir-verify

| Finding | Verdict | MLIR mechanism | Correction |
|---|---|---|---|
| ir-verify-1 | MLIR-native | `OpBase.td:SizedRegion`; `mlir/include/mlir/Transforms/RegionUtils.h:eraseUnreachableBlocks` | As S5 (erase once, after each site's loop), not "right after each inline". |
| ir-verify-2 | MLIR-native, one spelling wrong | `mlir/include/mlir/IR/OpDefinition.h:HasParent` (prints `ParentOpTypes::getOperationName()`, which an interface lacks) | As S1, but the yield keeps `ParentOneOf<["MatchOp", "MatchLitOp"]>`, as `scf.yield` does; "`HasParent` on the interface" does not compile. |
| ir-verify-3 | MLIR-native | `AttrTypeBase.td:TypeDef` | As S10. |
| ir-verify-4 | MLIR-native | `OpBase.td:ParamNativeOpTrait`; `mlir/include/mlir/Interfaces/SideEffectInterfaces.h:AlwaysSpeculatableImplTrait` | As written; S16 (made) no longer regresses it to a table keyed by op. |
| ir-verify-5 | acceptable | the inherent `Idr_Stage` | As S9; the precondition is S27's. |
| ir-verify-6 | acceptable | `SideEffectInterfaces.h:SideEffects::Resource` | As S7. |
| ir-verify-7 | MLIR-native, one tweak | `OpBase.td:PredOpTrait` | "The result is linear exactly when a capture is" is a declared `PredOpTrait` (S17's standard), not code in `ClosureOp::verify`/`SuspendOp::verify`. |
| ir-verify-8 | MLIR-native | `AttrTypeSubElements.h:AttrTypeWalker` | Reconcile with S10, which deletes `holdsClosure` and names no successor: one walk (`namesLabels` or the finding's `holdsLabels`), not both. |
| ir-verify-9 | fighting MLIR (the force rule) | `SideEffectInterfaces.h:EffectInstance::getValue` (no value: the whole resource) | One classifier as written, and MoveOut's `isa<ForceOp>` (`Canon/MoveOut.cpp:86`) goes: `idr.force` declares in ODS the read its thunk may make, a valueless `MemRead`, which MoveOut counts as touching every array, upstream's meaning. |
| ir-verify-10 | fighting MLIR (residual) | `ArithOps.td:Arith_DivSIOp`/`Arith_DivUIOp` | S21's `show_int` keeps `is_signed`; mlir-1 splits it. |
| ir-verify-11 | acceptable | `mlir/include/mlir/Interfaces/ViewLikeInterface.td:ViewLikeOpInterface` | As written; S11's `sourceOf` can read these edges. |
| ir-verify-12 | MLIR-native | `MemRefOps.td:LoadOp`, `AllocLikeOp`; `SideEffectInterfaces.td:MemRead` | As written: S3's pattern applied to arrays (one op per meaning, lowered progressively). |
| ir-verify-13 | MLIR-native | `SCFOps.td:IndexSwitchOp` | As S1/S2, `knownTag` for `tagOf`. |
| ir-verify-14 | acceptable | typed C++ fields over MLIR type classes | As written. |
| ir-verify-15 | MLIR-native | `mlir/include/mlir/IR/Properties.td:DefaultValuedProp`; `mlir/include/mlir/IR/EnumAttr.td:EnumProp` | As S6. |
| ir-verify-16 | MLIR-native | `Interfaces.td:OpInterface`; `mlir/include/mlir/IR/PatternMatch.h:OpRewritePattern` | As written (DRR matches by op name only, so C++ patterns over an interface are upstream's form). |
| ir-verify-17 | MLIR-native | an interface default method; the fold probe mirrors `mlir/lib/Analysis/DataFlow/ConstantPropagationAnalysis.cpp:SparseConstantPropagation::visitOperation` | As written. |
| ir-verify-18 | acceptable | upstream's relative is a walk too: `mlir/include/mlir/Dialect/Bufferization/IR/BufferDeallocationOpInterface.h:DeallocationState` | As written; a `DataFlowSolver` gives no "exactly once" check, and no upstream verifier runs a solver. |
| ir-verify-19 | acceptable | none | As written. |

### analysis

| Finding | Verdict | MLIR mechanism | Correction |
|---|---|---|---|
| analysis-1 | acceptable | `mlir/include/mlir/Analysis/DataFlowFramework.h:DataFlowSolver` is context-insensitive per anchor, so it cannot hold a polyvariant interpreter | As written; component and "calls itself" from S13. |
| analysis-2 | fighting MLIR (in part) | `mlir/include/mlir/Analysis/CallGraph.h:CallGraph`; `llvm/include/llvm/ADT/SCCIterator.h:scc_iterator` | As S13 (made): built on the cached `CallGraph` with `scc_begin`, not re-indexed. |
| analysis-3 | MLIR-native | `Interfaces.td:OpInterface` | As S7, S8. |
| analysis-4 | acceptable | none | As written; its default-region arm is S11's `Same` by our own rule (mlir-9's interface edge is withdrawn; see the S2 row). |
| analysis-5 | acceptable | Labels' own 0CFA | As written; the inventory below finds the solver no better for it. |
| analysis-6 | acceptable | none | As written. |
| analysis-7 | acceptable | none (a parallel ready-set scheduler has no upstream counterpart) | As written. |
| analysis-8 | MLIR-native | `mlir/include/mlir/Analysis/DataFlow/IntegerRangeAnalysis.h:IntegerRangeAnalysis::setToEntryState` | As written. |
| analysis-9 | MLIR-native | `Properties.td:DefaultValuedProp` | As S6. |
| analysis-10 | acceptable | `mlir/include/mlir/Analysis/DataFlow/DeadCodeAnalysis.h:PredecessorState::allPredecessorsKnown` (its `nullopt` is the negation) | As written. |
| analysis-11 | acceptable | none | As written. |
| analysis-12 | acceptable | none | As written. |
| analysis-13 | fighting MLIR (superseded) | `MemRefOps.td:AllocLikeOp` | S3: `tail::Built` becomes `CellInitOp`, no variant, no interface. |
| analysis-14 | MLIR-native, shape pinned | `DataFlowFramework.h:DataFlowAnalysis`, `DataFlowAnalysis::getOrCreateFor`; `mlir/include/mlir/Analysis/DataFlow/SparseAnalysis.h:Lattice` | Sparse, not dense: a two-point `Lattice<Owned>` on each `Value` (a parameter is its entry block argument), on the generic `DataFlowAnalysis`, not `SparseBackwardDataFlowAnalysis`, whose region-successor meet would contradict "a forwarded value is owned"; a call is the dependent point `getProgramPointAfter(call)`; seeds in `initialize`; precedent `ExclusivityAnalyses.cpp`. |
| analysis-15 | acceptable | none | Folded into analysis-14 (a parameter's static class, not lattice states). |
| analysis-16 | acceptable | none | As written. |
| analysis-17 | acceptable | `Attribute::walkImmediateSubElements` carries neither the field index nor the run form | As written. |
| analysis-18 | acceptable | none | As written. |

### transforms-a

| Finding | Verdict | MLIR mechanism | Correction |
|---|---|---|---|
| transforms-a-1 | acceptable | `mlir/include/mlir/Pass/PassOptions.h:PassOptions::ListOption` with a `cl::parser<Request>` | Parse each request at the option boundary, so a malformed one fails when the pipeline is parsed; the relation is an enum `Option` with `cl::values`; the snapshot is `module->clone()`. |
| transforms-a-2 | MLIR-native | `RegionBranchOpInterface::getEntrySuccessorRegions` | As S1. |
| transforms-a-3 | acceptable | none | As S14. |
| transforms-a-4 | MLIR-native | `StorageUniquer`; `AttrTypeReplacer` | As written: a parameterless `#idr.key_hole`, keys stay uniqued attributes (S22, made). |
| transforms-a-5 | MLIR-native | `mlir/include/mlir/IR/OwningOpRef.h:OwningOpRef`; `mlir/include/mlir/IR/Operation.h:Operation::clone` | As written, the digest a parameter of `#idr.key_raise`; forms `DenseMap<digest, OwningOpRef<idr::FuncOp>>`. |
| transforms-a-6 | acceptable | none | As written. |
| transforms-a-7 | MLIR-native | uniqued attributes as `DenseMap` keys | As written (it holds now that S22 keeps the keys attributes). |
| transforms-a-8 | acceptable | the inherent stage | As S9; the precondition is S27's base class. |
| transforms-a-9 | MLIR-native | `mlir/include/mlir/Dialect/SCF/Transforms/Patterns.h:populateSCFStructuralTypeConversionsAndLegality`; `DialectConversion.h:ConversionTarget::markUnknownOpDynamicallyLegal` | As written, keeping unknown ops legal (`Columns.cpp:40`) by design. |
| transforms-a-10 | acceptable | none | As written. |
| transforms-a-11 | acceptable | none | As S19. |
| transforms-a-12 | acceptable | none | As written. |
| transforms-a-13 | MLIR-native | `mlir/include/mlir/Transforms/InliningUtils.h:DialectInlinerInterface::isLegalToInline`, `allowSingleBlockOptimization` | As written. |
| transforms-a-14 | acceptable | none | As written. |
| transforms-a-15 | fighting MLIR | `Operation.h:Operation::CloneOptions::withResultTypes`, `Operation::clone(IRMapping &, CloneOptions)`; `PatternMatch.h:RewriterBase::inlineRegionBefore` | No hand `OperationState`: clone with an `IRMapping` of the new operands and `CloneOptions::all().cloneRegions(false).withResultTypes(types)`, insert it and move each region; properties, attributes and successors come with the clone. Raise's rebuild is S1's `rebuild`. |

### transforms-b

| Finding | Verdict | MLIR mechanism | Correction |
|---|---|---|---|
| transforms-b-1 | MLIR-native | `InferTypeOpInterface` | As S4 (and mlir-5). |
| transforms-b-2 | fighting MLIR (superseded) | `MemRefOps.td:AllocLikeOp`, `MemRef_AllocaOp`, `MemRef_ReallocOp` | S3 replaced the optional token on `idr.con`. |
| transforms-b-3 | MLIR-native | `SizedRegion`; `eraseUnreachableBlocks` | As S5. |
| transforms-b-4 | MLIR-native, refined | `mlir/include/mlir/Analysis/SliceWalk.h:getControlFlowPredecessors` | Call `getControlFlowPredecessors(value)`, which handles results, entry arguments and `SelectLikeOpInterface`; the fixpoint around it is mlir-8. |
| transforms-b-5 | acceptable | a verifier | As written. |
| transforms-b-6 | MLIR-native | `PassInstrumentation::signalPassFailure`; `PassBase.td:PassBase` (`baseClass`) | S27 (made) takes the base class, which also sets the stage. |
| transforms-b-7 | MLIR-native | `mlir/include/mlir/Transforms/Passes.td:SymbolDCEPass`; `mlir/include/mlir/Pass/Pass.h:Pass::runPipeline` | As written. |
| transforms-b-8 | acceptable | none | As written; the inventory below finds destination style does not fit the ordered nests. |
| transforms-b-9 | MLIR-native | `mlir/include/mlir/Dialect/Affine/IR/AffineOps.td:AffineDelinearizeIndexOp` | As written, and `IdrStructureLoops` lists `::mlir::affine::AffineDialect` in `dependentDialects` (`Passes.td:379` does not). |
| transforms-b-10 | MLIR-native | `Pass.h:Pass::getAnalysis`, `Pass::runPipeline` | As written; `getCachedParentAnalysis` is no substitute here, since no earlier program pass guarantees the table is cached. |
| transforms-b-11 | acceptable | none | As written. |
| transforms-b-12 | acceptable | none | As written. |
| transforms-b-13 | MLIR-native | `Interfaces.td:OpInterface` | As written. |
| transforms-b-14 | acceptable | none | As written. |
| transforms-b-15 | MLIR-native | `mlir/include/mlir/IR/Builders.h:OpBuilder::createOrFold` | As written. |
| transforms-b-16 | MLIR-native | `PatternMatch.h:RewriterBase::modifyOpInPlace`; `ControlFlowInterfaces.td:ReturnLike` | As written, no kind test (both terminators are `ReturnLike`). |
| transforms-b-17 | MLIR-native | a verifier | As written. |

### conversion

| Finding | Verdict | MLIR mechanism | Correction |
|---|---|---|---|
| conversion-1 | MLIR-native | `mlir/lib/Conversion/GPUCommon/OpToFuncCallLowering.h:OpToFuncCallLowering` | As S15. |
| conversion-2 | MLIR-native | `GPUCommonPass.h:FunctionCallBuilder`; `mlir/include/mlir/Dialect/LLVMIR/FunctionCallUtils.h:lookupOrCreateFn`; `LLVM::CallOp::verifySymbolUses` | As S15, with calls built from the table so the LLVM dialect's symbol verifier checks them. |
| conversion-3 | MLIR-native | `mlir/include/mlir/IR/BuiltinTypes.td:MemRefType::getStridesAndOffset`, `isStrided` | As written: one plan from a checked `getStridesAndOffset` (its failure is discarded with `(void)` today), and the verifier refuses `!isStrided()`. |
| conversion-4 | acceptable | none | As written. |
| conversion-5 | acceptable | `mlir/include/mlir/Conversion/UBToLLVM/UBToLLVM.h:populateUBToLLVMConversionPatterns` | As written: poison may be refined to any value, so the static cell is a legal refinement; uncounted components stay `ub.poison`. |
| conversion-6 | acceptable | none | As S20. |
| conversion-7 | acceptable | already `LLVM::cconv::CConv` and the `CallGraph` | As written; the inventory below finds LLVM's `musttail` cannot take the plan over. |
| conversion-8 | MLIR-native | `mlir/include/mlir/Pass/PassManager.h:PassManager::enableVerifier` | As written; with mlir-4 the root's kind is computed in the program's region verifier. |
| conversion-9 | acceptable | none | As written. |
| conversion-10 | acceptable | `mlir/lib/Dialect/SCF/IR/SCF.cpp` (execute_region inlining) | As written; canonicalization inlines an `scf.execute_region` only when its parent is a function, which is harmless elsewhere. |
| conversion-11 | MLIR-native | `mlir/include/mlir/IR/Location.h:LocationAttr::findInstanceOf` | As written. |
| conversion-12 | acceptable | `IntegerRangeAnalysis` | As written; an `llvm.call` is opaque to range analysis until LTO, so the sites that emit IR stay arith. |
| conversion-13 | fighting MLIR | `mlir/include/mlir/Transforms/DialectConversion.h:OpTraitConversionPattern` | One `OpTraitConversionPattern<idr::NoRuntimeForm>` matched by the trait, not a `GET_OP_LIST` instance per op; `Idr_ResultCarriesOperand` becomes a `TraitList` including `Idr_NoRuntimeForm`. |
| conversion-14 | MLIR-native | the op verifier, run by `PassManager::enableVerifier` | As written. |
| conversion-15 | acceptable | `SymbolTable::insert` cannot serve the workers' names or C names | As S30, `__idr_main` excepted. |

### driver-runtime

| Finding | Verdict | MLIR mechanism | Correction |
|---|---|---|---|
| D1 | fighting MLIR (in part) | `llvm/include/llvm/Support/Error.h:llvm::Expected`, `logAllUnhandledErrors`; `mlir/include/mlir/IR/Diagnostics.h:Diagnostic::getMetadata` | Steps returning `Error`/`Expected` is right. A `DriverError` carrying a `Verdict` is a second fold beside `foldDiagnostics` (`Driver/Outcome.cpp:142`), which already decides the class from a diagnostic's rule metadata: each step's error is emitted into the compilation's engine (`emitError(loc) << toString(err)`, or `idr::refuse(loc, rule)`), and the fold decides. |
| D2 | MLIR-native | `mlir/include/mlir/Tools/mlir-opt/MlirOptMain.h:MlirOptMainConfig`; `llvm/include/llvm/Support/CommandLine.h:cl::OptionCategory` | As written, the options in one `cl::OptionCategory`. |
| D3 | acceptable | none | As written. |
| D4 | MLIR-native | `llvm/include/llvm/Object/IRObjectFile.h:IRObjectFile::findBitcodeInMemBuffer` | As written. |
| D5 | MLIR-native | `mlir/include/mlir/Dialect/LLVMIR/LLVMAttrDefs.td:LLVM_TargetAttr` | As written, the refusal through `module.emitError()`. |
| D6 | acceptable | none | As written. |
| S1 | acceptable | `llvm/include/llvm/Support/CrashRecoveryContext.h:CrashRecoveryContext::RunSafelyOnThread` takes an `unsigned` stack size, too small for the 2^40-byte guarded stack | As written. |
| P1 | acceptable | none | As written. |
| U1 | acceptable | none | As written. |
| T1 | MLIR-native | LLVM's own `llvm/include/llvm/IR/RuntimeLibcallsImpl.td:RuntimeLibcall` records | As S15. |
| T2 | acceptable | none (the C ABI) | As written. |
| T3 | MLIR-native | `llvm/include/llvm/TableGen/Record.h:Record::getValueAsString`, `isSubClassOf` | As written; `isCount` reads the record's class and `bitwidth` as `builtinType` already does. |
| T4 | acceptable | none | As written. |
| R1-R7 | acceptable | none (runtime C++) | As written. |

### idris-emit, idris-frontend, lists

All acceptable as written (Idris side; no MLIR mechanism applies) except:

| Finding | Verdict | MLIR mechanism | Correction |
|---|---|---|---|
| idris-emit-2, -3 | MLIR-native | `mlir/include/mlir/TableGen/Operator.h:Operator::getNumOperands`, `getTrait` | As written (generated from ODS). |
| idris-emit-6 | MLIR-native | `Operator.h:Operator::getTrait` over S29(a)'s marks | As written; no dispatch on op-name strings survives on the Idris side. |
| idris-emit-7 | acceptable | `mlir/include/mlir/Dialect/UB/IR/UBOps.td:UnreachableOp` | As written: Emit already writes `ub.unreachable`; `idr.match`'s description should say a constructor with no case and no default is unreachable. |
| idris-emit-8 / idris-frontend-13 | acceptable | `mlir/include/mlir/IR/BuiltinLocationAttributes.td:UnknownLoc`, `NameLoc`, `FileLineColRange` | One finding (S24 takes emit-8's `Place`), and mlir-7 writes it through the builtin records. |
| idris-emit-15 | fighting MLIR (the C++ half) | `mlir/include/mlir/IR/BytecodeBase.td:CompositeBytecode`, `ArrayWithKnownSize`; precedent `mlir/include/mlir/IR/BuiltinDialectBytecode.td` | Declare `Body` and `Ctor` as `CompositeBytecode` records and `FieldCode` as an ODS `I32EnumAttr`, so upstream's `mlir-tblgen -gen-bytecode` writes the C++ reads (`readCtor`, `readBody` go) and the Idris generator the other side. |
| idris-emit-17 | MLIR-native | `BuiltinLocationAttributes.td:NameLoc` | As written. |
| idris-frontend-1 | the record is right; the transport fights MLIR | `Diagnostics.h:Diagnostic::getMetadata`, `ScopedDiagnosticHandler`, `SourceMgrDiagnosticVerifierHandler` | See S25 above: refusals as typed data the driver re-emits into the diagnostic engine, one fold. |

## New findings: [findings/mlir.md](findings/mlir.md)

Twenty-three, each verified in the source and the pinned tree; the
coordinator adds them to `ownership.json` by their `Owner` row.

| Finding | What fights MLIR | Upstream form | Owner | Owner's build |
|---|---|---|---|---|
| mlir-1 | `UnitAttr:$is_signed` switches the meaning of ten integer ops | one op per signedness, `ArithOps.td:Arith_DivSIOp`/`Arith_DivUIOp` | L16 | no |
| mlir-2 | the matches' hand parser re-implements ODS's property check | `custom<...>` directives in a declarative format, as `SCFOps.td:IndexSwitchOp` | L01 | no |
| mlir-3 | flow models verified only at stage `higher` | an interface verifier, `Interfaces.td:OpInterfaceTrait`'s `verify` | L17 | compile time |
| mlir-4 | program rules (and the knot refusal) on `verifySymbolUses`, so no pass is held to them | `verifyRegions`, run after every pass; the refusal a check pass | L03 | yes |
| mlir-5 | `idr.take` is three ops by operand type, with the cell's effects on all | `Tensor_ExtractOp` vs `MemRefOps.td:LoadOp`: one op per memory semantics | L02 | no |
| mlir-6 | the driver registers every upstream dialect, extension and pass | the set the pipeline needs (`InitAllPasses.h`'s own advice) | L18 | yes |
| mlir-7 | locations and strings written as text the reader re-parses | `BuiltinDialectBytecode.td` records | L20 | yes |
| mlir-8 | returned-arguments is a hand forward dataflow | `SparseForwardDataFlowAnalysis` with call hooks | L13 | yes |
| mlir-9 | the match's default argument is not declared through `RegionBranchOpInterface` | `getEntrySuccessorOperands`, `getSuccessorInputs`; **withdrawn** (README §9 B12, for the owner's review): with the edge, the matches' upstream region-branch canonicalizations (`OpsMatch.cpp:192,200`; `ControlFlowInterfaces.cpp:718-760, 859-990`) would replace the argument by the scrutinee, a second use of a linear value, or erase it with the scrutinee operand | L01 | yes |
| mlir-10 | phase 0 renames by re-deriving `mangle` at known uses | `AttrTypeReplacer` over `SymbolRefAttr`; `walkAndApplyPatterns` | L08 | no |
| mlir-11 | patterns compute converted types around their `TypeConverter` | `TypeConverter::convertType` | L07 | no |
| mlir-12 | calls carry no effects, so a second effects API, a canonicalizer wrapper and a hand CSE exist | an effects property on `idr.call`, as `llvm.call`'s `memory_effects`; upstream CSE/DCE | L03 | yes; reverses D13 |
| mlir-13 | nested passes take analyses as constructor arguments, unregistered | AM analyses and `getCachedParentAnalysis` (Exclusivity excepted) | L13 | no |
| mlir-14 | pipeline steps composed inside passes (idr-rc's five, idr-effects, symbol-dce) | every step in `buildPipeline` | L13 | yes |
| mlir-15 | an element's address by our formula beside upstream's | `LLVM::getStridedElementPtr` | L07 | yes |
| mlir-16 | boundary facts recount the signature conversion | `SignatureConversion::getInputMapping` | L07 | no |
| mlir-17 | narrowing runs upstream's patterns under hand drivers | `applyPatternsGreedily` as `IntRangeNarrowingPass` configures it | L12 | yes |
| mlir-18 | while-do's hand dead sweep | `eliminateTriviallyDeadOps` | L13 | no |
| mlir-19 | rewrites to an operand written as patterns | `hasFolder` | L01 | no |
| mlir-20 | Escapes undoes the solver's interprocedural default by hand | `DataFlowConfig::setInterprocedural(false)`, `visitExternalCall` | L09 | compile time |
| mlir-21 | Exclusivity's `Entry` repeats `DeadCodeAnalysis`'s public-callable rule | `DeadCodeAnalysis`, `isPublic` | L10 | no |
| mlir-22 | failing properties checked by FileCheck on stderr | `-verify-diagnostics` (`SourceMgrDiagnosticVerifierHandler`) | L14 | tests only |
| mlir-23 | `expect.facts`: an expected answer as a discardable attribute on the op under test | a remark-emitting test pass and `expected-remark` | L14 | tests only |

## Inventory: home-rolled mechanisms against upstream

What MLIR already does in this tree is not repeated here: the lowering is a
1:N `TypeConverter` with a `ConversionTarget` under `applyFullConversion`
(`Conversion/Lower.cpp`); bufferization is One-Shot with external models;
the parallel, reduction and interchange array forms are `linalg.generic`;
idr-tail-loops uses upstream's while-to-for uplift and LICM; tail calls are
`llvm.call`'s `musttail` with `tailcc`; ranges, constants, escapes and
exclusivity run on `DataFlowSolver`; the canonicalizer runs upstream's greedy
driver; `idris-mlir-opt` is `MlirOptMain`; refusals carry their rule as
diagnostic metadata. Where upstream can take over, the finding is named.

| Mechanism | Upstream | Verdict | Where |
|---|---|---|---|
| `Support/Worklist.h` (`OnceWorklist`, `MonotoneWorklist`: termination in the type), 46 uses | `DataFlowSolver` | partly: the dataflow uses go to the solver where its model fits (Borrows, Returned); the others are graph walks or analyses the solver cannot hold (below) | analysis-14, mlir-8 |
| Labels' 0CFA (`Labels.cpp`, `LabelSites.cpp`, union-find, each (class, label) once) | `SparseForwardDataFlowAnalysis` with `GenericLatticeAnchorBase` field anchors | does not fit better: upstream anchors only values (`SparseAnalysis.h`: "Lattices can only be created for values"), `DeadCodeAnalysis` gives up on exactly the indirect calls and label-used functions the 0CFA resolves, unification has no anchor equivalence during a solve, and the once-per-pair cost bound is lost. A compile-time question if wanted anyway | analysis-5 kept |
| Borrows' queues | `DataFlowAnalysis`, `Lattice` on the `Value` | take over | analysis-14 (sparse, generic base; not `SparseBackwardDataFlowAnalysis`, whose region meet contradicts "a forwarded value is owned") |
| Escapes | `SparseBackwardDataFlowAnalysis` (already) | its call rule by configuration | mlir-20 |
| Exclusivity | `SparseForwardDataFlowAnalysis`, `DeadCodeAnalysis` (already) | `Entry` goes | mlir-21 |
| Identities' greatest fixpoint | `AnalysisState` | does not fit better: a 30-line loop per component inside the ready set, callees frozen | analysis-4, -6 |
| BindingTimes' interpreter | none | does not fit: polyvariant, a state per (value, argument tuple); the solver is context-insensitive | analysis-1, S14 |
| Returned's solver | `SparseForwardDataFlowAnalysis` | take over: its lattice is symbolic (`arg(i)`), so the callee's arguments are seeded by `visitCallableOperation` rather than joined over call sites (the scan's dissent, "per-callee summaries", is answered by this) | mlir-8 |
| Reuses' and Uses' last use | `mlir/include/mlir/Analysis/Liveness.h:Liveness` | does not fit: CFG liveness per region; `usedAfter` walks up through enclosing ops and reads a deciding op's regions as alternatives | analysis-11 |
| The call graph's SCCs, five times | `CallGraph`, `scc_begin` | take over | S13 (made) |
| idr-optimize's ready set and waves | `mlir/include/mlir/Transforms/Inliner.h:Inliner` | does not fit: one SCC at a time (`runTransformOnCGSCCs`), a fixed graph, no callee summaries to a nested pipeline, optimize-then-inline order; only `ProfitabilityCallbackTy` fits, for `worthInlining` | analysis-7, -16 |
| idr-contify | `InlinerPass` | does not fit: `shouldInline` refuses exactly A->B->A, contify's candidates | — |
| idr-pure-calls | `mlir/lib/Transforms/CSE.cpp` | take over once calls carry effects | mlir-12 |
| idr-canonicalize | `createCanonicalizerPass` | upstream's, once mlir-12 removes the callee table it binds | mlir-12 |
| Narrowing's drivers | `applyPatternsGreedily` | take over | mlir-17 |
| Narrowing's word rewrite (`!idr.big` to `i64`) | `IntRangeOptimizations.cpp:NarrowElementwise` | does not fit: upstream narrows integer to integer by cloning the same op; ours changes op and type and tracks ownership | transforms-a kept |
| Canon's `Merge.cpp:sameBody` | `OperationEquivalence::isRegionEquivalentTo` | does not fit: block arguments one to one, cases of different arity unequal | — |
| Canon's `Sink.cpp` | `ControlFlowSinkUtils.h:controlFlowSink` | does not fit: upstream moves into one region and never copies | ir-verify-17 |
| Deduplicate | `DuplicateFunctionElimination.cpp` | does not fit: raw attribute comparison, no reading through renames, `func.func` only | transforms-a kept |
| PDLL for the C++ patterns | `mlir-pdll` | does not fit now: not in the toolchain's distribution (`tools/bootstrap.sh` `stage2_components`); DRR already covers the declarative cases | — |
| Folds written as patterns | `hasFolder` | take over | mlir-19 |
| Element addresses | `getStridedElementPtr` | take over | mlir-15 |
| Boundary facts | `SignatureConversion::getInputMapping` | take over | mlir-16 |
| Runtime declarations | `lookupOrCreateFn` | does not fit: it writes the module, and phase 2 converts in parallel (`Runtime::merge` exists for that) | conversion-2 |
| `ConvertToLLVMPatternInterface` on the dialect | `ToLLVMInterface.td` | does not fit: it hands a pattern only `(target, LLVMTypeConverter, patterns)`, and ours need `Layouts`, a worker's `Runtime` and a 1:N converter | — |
| Crash lowering | `cf.assert`'s `AssertOpLowering` | does not fit: `puts` and `abort`, not the runtime's message and exit | — |
| Counted copies | `MemRefCopyOpLowering` (`memrefCopy`) | does not fit: it counts no element references | — |
| Tail position, results in memory, frame reach | LLVM `musttail`/`tailcc`, sret demotion, TRE's `LocalStackValueTracker` | does not fit: LLVM drops a `tail` call not adjacent to its return, sret demotion is incompatible with tail calls (and `musttail` then aborts the build on both targets), and TRE's tracker only adds hints | conversion kept |
| Ordered array nests under DPS and `TilingInterface` | `lowerToLoopsUsingSCFForOp`, `PartialReductionOpInterface` | does not fit: it refuses ops with results and builds `scf.for` without iter_args; `IteratorType` has no "ordered"; DPS needs a tied init the first-cell case lacks; the parallel forms are already `linalg.generic`, which has both interfaces | transforms-b-8, -9 |
| Stack placement | `PromoteBuffersToStackPass` | the order is upstream's (S3), the pass is not: its escape test reads only terminators, it skips allocations with a dealloc (every cell has drops after idr-rc), and has no per-frame budget | S3 |
| Ownership-based deallocation | `BufferDeallocationOpInterface` | does not fit: counting is the one ownership system | — |
| idr-expect's positive properties | `expected-remark` | does not fit: they hold of every copy of `@f` in pipeline dumps of Idris programs | S26 |
| idr-expect's negative runs, `expect.facts` | `-verify-diagnostics`, a remark-emitting test pass | take over | mlir-22, mlir-23 |
| `ContractInstrumentation` | `PassInstrumentation`, `signalPassFailure` | already upstream's | — |
| Name maps keyed by `StringAttr` (about 16 per-function tables, 57 callee lookups by name) | `SymbolTableCollection`, `SymbolUserMap` | does not fit: they hold per-symbol state, for which upstream has no container; a uniqued `StringAttr` key costs what an `Operation *` key does. Friction, not a defect | — |
| 48 hand "internal error:" prefixes in passes | `emitError` | does not fit: no upstream class for it; the verdict already reads "no rule" as internal | D1 covers the driver's |

## Types that could carry a fact

From the inventories; each belongs to the lane that owns the file.

- `Analysis/Ownership.h:298-300`, `Exclusivity.cpp:102`: `targets`, `callersOf`, `returnsOf`, `runsFrom` are keyed and valued by `Operation *` but hold only `CallOp`, `FuncOp`, `ReturnOp`: `DenseMap<CallOp, FuncOp>`, `DenseMap<FuncOp, SmallVector<CallOp>>` (L10).
- `Analysis/Ownership.h:227,243`: `sitesOf.find(fn)->second` dereferences `end()` for a function the map lacks, with no assert; the closed world is a comment (L10).
- `Analysis/Identities.h:182-186`, `Identities.cpp:87,97`: three containers indexed in parallel by slot, and `Drop = std::pair<unsigned, unsigned>` that a swap would not catch: `enum class Slot : unsigned` and one vector of `Candidate{argument, type}` (L10).
- `Borrows.cpp:74,78,165-173`: `ParamOf = std::pair<FuncOp, unsigned>`, a second name for the entry `BlockArgument` (analysis-14 removes it).
- `Expect/Placement.cpp:76-91` `Order{bool io; bool crash}` and `StructureLoops/Forms.cpp:55-56`: a fifth and sixth translation from effect resources to effect bits, which ir-verify-6's one table misses (L14, L13).
- `tools/idris-mlir-tblgen.cpp:1090,1273,1593`: three more record-name matches T3 does not list (`"I64"`, `"Idr_TagParameter"`, `"MutableType"`), each a field or trait of the record (`mlir/include/mlir/TableGen/AttrOrTypeDef.h:getTraits`) (L06).
- `narrow::Copy` and `Fitting` (`Narrow/Lanes.cpp:134-158`): the copy's bound and the solver kept for it agree by a hand resync (`:156`): a `Copy::Analysed{exponent, solver}` made only by `analyse` (L12).
- `StructureLoops/Lowering.cpp:givenBy` returns `std::optional<SmallVector<Value>>` whose `nullopt` means "ends in `ub.unreachable`", restated by five `orPoison` sites: return the values or poison of the result types (L13).
- `PassThroughMemory.cpp:65` takes `call->getNextNode()` to be the `llvm.return` placement inserted: a `TailCall{call, ret}` value (L07, L08).
- `Optimize/Component.cpp:105-124` finds inner statistics by matching pass and statistic names as strings (L11).

## Where the codebase fights MLIR most

1. **Calls that cannot say what they do** (mlir-12): 82 references to `CalleeEffects` in 31 files, a hand CSE (`PureCalls.cpp`, 183 lines), a canonicalizer wrapper and `CalleePattern`, all to keep a call's effects off the call.
2. **Flags and optionals that switch an op's meaning:** `is_signed` on ten ops (mlir-1); `idr.con`'s `stack`, holes and token (S3, made); `idr.take`'s three bodies (mlir-5); `Idr_MayCrash<bit allocates>` (ir-ods-4).
3. **Verification scheduled by the wrong hook:** program rules and a user refusal on `verifySymbolUses` (mlir-4), flow models checked at one stage (mlir-3), stage preconditions by hand (S27, made).
4. **The pipeline hidden inside passes:** idr-rc's five steps and unregistered nested passes (mlir-13, mlir-14).
5. **Contracts that would not have built or would have miscompiled:** S2's region order (refused by ODS), S3's realloc effects, S3's stack placement before any cell exists, and its escape analysis blind to `idr.share` (all made).
