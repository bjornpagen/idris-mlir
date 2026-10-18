<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Representation survey: mlir

Area: the whole of `foreign/idr` and the runtime ABI glue, read against the
pinned MLIR (`.toolchain/llvm-project/mlir`) for what no other survey
found: places where the dialect fights MLIR, and home-rolled mechanisms MLIR
can take over. Read-only, at the base of the packet (73d6dcf3 plus the
uncommitted checker); every upstream `path:Symbol` below was found in the
pinned tree by grep, and every source line read. Nothing was built or run.
The audit that grades the packet's contracts and the other findings against
MLIR is [../mlir-audit.md](../mlir-audit.md).

The standard is the one the owner set with §4 S3: values and memory at
different levels, one op per semantics (no flag, optional operand or enum
switches an op's meaning or effects), shared shapes as interfaces, and
facts declared in ODS. A finding that adopts an upstream mechanism and can
change the pipeline's output or its compile time says so under
"Verification here" (NEEDS-OWNER-BUILD).

## Findings

### mlir-1: `is_signed` is a unit attribute that switches the meaning, folder, lowering and runtime function of ten ops

| Field | Content |
|---|---|
| Evidence | `UnitAttr:$is_signed` on ten ops: `IdrScalarOps.td:20` (`Idr_DivisionOp`: div, mod), `:50` (`Idr_ShiftOp`: shl, shr), `:75` (to_char), `:113` (int_head); `IdrStringOps.td:90` (str.show), `:225` (str.to_int); `IdrBigOps.td:202` (big.from_int); `IdrIOOps.td:40` (io.put_int). `Ops.cpp:29-41` is the `custom<Signedness>` directive. `getIsSigned()` is read 16 times in 8 files (`OpsScalars.cpp`, `Ops.cpp`, `OpsStrings.cpp`, `OpsBigs.cpp`, `Fold/Bigs.cpp`, `Fold/Strings.cpp`, `Narrow/Facts.cpp`, `Conversion/Scalars.cpp`). `Conversion/Scalars.cpp:70-74` lowers to `arith.divui`/`remui` or to a Euclidean sequence by it; `tools/idris-mlir-tblgen.cpp:2150,2222-2239` picks a `_s` or `_u` C function per op instance by the attribute's name; `Canon/Canonicalize.td:31-70` threads `$isSigned` through six DRR patterns. ir-ops-15 and S21 take the flag off `show`'s Double case only; ir-ods kept the rest as essential. |
| Counterexample | `isa<DivOp>` and every pattern on it cover two functions, Euclidean signed division and unsigned division. A rewrite of `idr.shr` that drops `$isSigned` turns an arithmetic shift into a logical one, and nothing in the op's kind catches it. |
| Root cause | Idris's `Int8..Int64` and `Bits8..Bits64` have different operations over one MLIR integer type, which is signless; the signedness is the operation, held as a flag on a signless op. |
| Correction | One op per signedness, as `arith` has them (`mlir/include/mlir/Dialect/Arith/IR/ArithOps.td:Arith_DivSIOp`/`Arith_DivUIOp`, `Arith_RemSIOp`/`Arith_RemUIOp`, `Arith_ShRSIOp`/`Arith_ShRUIOp`, `Arith_ExtSIOp`/`Arith_ExtUIOp`): `idr.divs`/`idr.divu`, `idr.mods`/`idr.modu`, `idr.shls`/`idr.shlu`, `idr.shrs`/`idr.shru`, `idr.to_char_s`/`_u`, `idr.int_head_s`/`_u`, `idr.str.show_sint`/`show_uint` (beside S21's `show_double`), `idr.str.to_sint`/`to_uint`, `idr.big.from_sint`/`from_uint` (the natural result only on the unsigned one: ir-ops-15's check becomes the result constraint), `idr.io.put_sint`/`put_uint`. Each pair stays one TableGen class with a `bit isSigned` template argument, as `Idr_DivisionOp<..., bit isQuotient>` already is, so a folder reads a `static constexpr`; each op names its own `Idr_Runtime` symbol, and S29(b)'s ABI word carries the extension (`Idr_AbiWord<"Signed">`/`<"Unsigned">` on two constraints `Idr_SInt`/`Idr_UInt`). |
| Deletion | The ten `$is_signed`; `parseSignedness`/`printSignedness`; the 16 `getIsSigned()` reads (each becomes the op's class or its `static constexpr`); the generator's `is_signed` branch and its per-instance `_s`/`_u` choice; `BigFromIntOp::verify`; the `$isSigned` threading in DRR (the patterns pair by op, `Idr_PutStrOfShowSInt` → `Idr_PutSIntOp`). |
| Consumers | L16 (`IdrScalarOps.td`, `IdrStringOps.td`, `IdrBigOps.td`, `Ops{Scalars,Strings,Bigs}.cpp`, `Fold/**`), L24 (`IdrIOOps.td`), L03 (`Ops.cpp`), L08 (`Conversion/Scalars.cpp`), L01 (`Canon/Canonicalize.td`), L06 (the generator), L12 (`Narrow/Facts.cpp`), L20 (the registry's primitive-to-op map, by S0's names). S21 becomes three ops. |
| Discriminator | `idr.div signed %a, %b : i64` no longer parses; the generator refuses an op carrying `is_signed`; the signed and unsigned fold and lowering fixtures keep their output. |
| Verification here | `make typecheck`, `make typecheck-dialects`; the registry built on Chez. |
| Size and risk | Ten ops become twenty with no new C++; about 16 reads, a directive pair, a generator branch and a verifier go. Medium: it crosses into the registry. The runtime is unchanged (its `_s`/`_u` names stay). |
| Insight | 1, 4, 7 |
| Owner | L16 |

### mlir-2: the matches' syntax is hand C++ that copies ODS's generated property check and finds the default by position

| Field | Content |
|---|---|
| Evidence | `IdrMatchOps.td:24` `hasCustomAssemblyFormat = 1` on both matches. `OpsMatchSyntax.cpp:24-39` `parseAttrs` re-implements the strict-properties check ODS generates (`mlir/tools/mlir-tblgen/OpFormatGen.cpp`, "cannot be parsed from attr-dict when strict properties"), over a hand list of spelled names; `:45-60` `parseMatchBody` adds the default as "one more region"; the printer serves both ops through the `MatchLike` template. 202 lines. Upstream writes this shape declaratively: `mlir/include/mlir/Dialect/SCF/IR/SCFOps.td:IndexSwitchOp`'s format is `custom<SwitchCases>($cases, $caseRegions)` then `default $defaultRegion`. |
| Counterexample | A property later added to a match is taken silently from `attributes {...}` unless someone also adds it to `parseAttrs`' list. After S2 names the default region first, this parser still adds it last. |
| Root cause | The positional region list (ir-ods-9) forced a hand parser; S2 removes the reason. |
| Correction | After S2, `let assemblyFormat` for both: `$scrutinee `:` type($scrutinee) (`->` type($results)^)? attr-dict-with-keyword custom<MatchCases>(ref(type($scrutinee)), $cases, $caseRegions) `default` custom<DefaultCase>($defaultRegion)` (the literal match's default required), as `scf.index_switch` does; the directives parse `case @C(%x : A) {...}` with the region's arguments named by the pattern variables. The generated parser keeps properties out of the dictionary by itself. |
| Deletion | Both hand `parse`/`print`, `parseAttrs`, `parseMatchHead`, `parseMatchBody`, `printMatch`, `hasCustomAssemblyFormat` (about 120 of the 202 lines). |
| Consumers | L01 (`IdrMatchOps.td`, `OpsMatchSyntax.cpp`); L20 if the Idris syntax writer emits the form (it writes the generated syntax). |
| Discriminator | `tests/idr` round trips unchanged; `cases = ...` in the attribute dictionary is refused by the generated parser. |
| Verification here | `make typecheck`. |
| Size and risk | About 120 hand lines become a directive pair of about 50. Low. |
| Insight | 6 |
| Owner | L01 |

### mlir-3: an op's flow model is verified only while the program is at stage `higher`

| Field | Content |
|---|---|
| Evidence | `lib/IR/Flow.cpp:285-294`: `verifyFlow` returns success unless the program's stage is `Higher`; `verifyEdges` (`:127-216`, each edge's ends) is reached only from `verifyOp` (`:219-221`) inside it. The flow models of `idr.dup`, `drop`, `borrow`, `share`, `reuse`, `take`, `own.adopt` and `own.give` (`FlowOps.cpp:202-245`) take `Idr_OwnType` operands, which exist only from the owned stage on, so none of them is ever checked, and S3 item 7's four cell-op models would not be either. Yet `idr::consumes` and `consumedEffects` (`Effects.cpp:79-98`) turn exactly these edges into the `Free` effects that keep ops alive and ordered. |
| Counterexample | A `CellInitOp::getFlowEdges` that names another op's value as its `to`, or releases a use it does not hold, verifies at every stage; `consumedEffects` then puts a `Free` on the wrong operand, and DCE or CSE acts on a false effect. |
| Root cause | A per-op invariant of an interface implementation is checked by a stage-gated walk over the function instead of by the interface. |
| Correction | `Idr_FlowOpInterface` gets `let verify = [{ return ::idr::detail::verifyFlowEdges($_op); }];` (`mlir/include/mlir/IR/Interfaces.td:OpInterfaceTrait`'s `verify`, as `mlir/include/mlir/Interfaces/DestinationStyleOpInterface.td:DestinationStyleOpInterface` verifies its ops), holding `verifyEdges`' rules for every op that declares the interface, on every verification, at every stage. `verifyFlow` keeps only its stage-`higher` rule for ops without the interface. External models (on tensor ops, `ub.poison`) are not reached by an interface verifier and get a unit box. |
| Deletion | `verifyOp`'s interface arm and the stage gate in front of it. |
| Consumers | L17 (`IdrFlow.td`, `Flow.h`, `Flow.cpp`, `FlowOps.cpp`); every lane writing a flow model (S3 item 7) is checked from the start. |
| Discriminator | A unit box: a test op whose model names another op's value, in an owned-stage program, is refused ("declares a flow edge whose end is neither ..."); before, it verifies. Fixtures unchanged. |
| Verification here | `make typecheck`. Compile time: the edges of each ownership op are computed on each verification (NEEDS-OWNER-BUILD for the time). |
| Size and risk | About 15 lines move, one gate goes. Low; any model it newly refuses was wrong. |
| Insight | 6 |
| Owner | L17 |

### mlir-4: the program's rules hang on a symbol-use hook, so no program pass is held to them

| Field | Content |
|---|---|
| Evidence | `lib/IR/Func/Func.cpp:66-72`: `ProgramOp::verifySymbolUses(SymbolTableCollection &)` ignores its table and runs `verify::program`; `IdrOps.td:63-65` declares `SymbolUserOpInterface` on `idr.program` for this alone, and its comment says it is meant to run "never when a pass manager verifies the program". Upstream calls a symbol-table op's `verifySymbolUses` only from its parent table's verification (`mlir/lib/IR/SymbolTable.cpp:detail::verifySymbolTable`); the pass manager verifies the anchor op after each pass (`mlir/lib/Pass/Pass.cpp:OpToOpPassAdaptor::run`), and `Pipeline.cpp:34` nests every program pass under `pm.nest<idr::ProgramOp>()`. So the root, effect-coverage, memo-in-box, containment, knot and reuse-size rules run at parse and after the last program pass, never between deduplicate, defunctionalize, optimize, bufferize, rc, trmc and narrow. `Verify/Program.cpp:66-75` says `effectsCovered` exists because idr-pure-calls trusts the solved effects, and pure-calls (`Optimize.cpp:60`) runs before the first check. |
| Counterexample | idr-effects solves a set that misses `io`, idr-pure-calls erases a call on it, and six passes run on the result before the module's verifier refuses it, blamed on the whole nested pipeline. |
| Root cause | Invariants of the whole program, and one user refusal, are placed on the one hook MLIR calls only from the module's verifier, a mechanism for checking symbol uses repurposed as a schedule. The knot rule (`Verify/Knots.cpp:105`, `refuse(..., Rule::Cycle)`, called from `Verify/Program.cpp:305`) is a refusal of the user's program raised by a verifier, while every other refusal is a pass's (idr-demand is a check pass), so a frontend module with an IORef knot cannot even be loaded by `idris-mlir-opt` or `idris-mlir-reduce` to inspect or reduce it. |
| Correction | Run `verify::program` from `ProgramOp::verifyRegions` (`hasRegionVerifier`, already set; `mlir/include/mlir/IR/OpDefinition.h:Op::verifyRegionInvariants` runs the `SymbolTable` region trait first, the order `effectsCovered` relies on). The pass manager then holds every program pass to the rules. The threading concern of the base's comment does not arise: the program is verified after a program pass, when no nested function pass is running (`mlir/lib/IR/Verifier.cpp:OperationVerifier` runs `verifyRegions` after the nested ops), and a function pass's verification is of its function alone; per-function parts (the root's type) go to `FuncOp`'s verifier. The knot rule leaves the verifier for a check-role pass, `idr-knots` in `Passes.td`, reading `getAnalysis<TypeGraph>()` right after idr-defunctionalize (where closures are data), refusing with the same `Rule::Cycle` text. |
| Deletion | `ProgramOp::verifySymbolUses`; `DeclareOpInterfaceMethods<SymbolUserOpInterface>` on `idr.program`; the root lookup duplicated between `verifyRegions` and `verify::program`; the `knots` call in the verifier and the comment that calls this hook the place "where every pass's input is checked" (`Verify/Program.cpp:100-101`). |
| Consumers | L03 (`IdrOps.td`, `Func/Func.cpp`, `Verify/Program.cpp`), L15 (`Verify/Knots.cpp` becomes the pass's body), L13 (`Passes.td`, `Pipeline.cpp`: `idr-knots`); the coordinator (`tests/reject/*cycle*` expected output unchanged). |
| Discriminator | A unit box: a `PassManager` nested on `idr.program` runs a test pass that clears a function's `io` bit, then a second pass; before, both succeed and only the module verification fails; after, the run fails at the first pass. `tests/idr/verify/*` unchanged; `idris-mlir-opt` round-trips a module with a knot, and `--idr-knots` refuses it with the expected text. |
| Verification here | `make typecheck`; NEEDS-OWNER-BUILD: `TypeGraph` and `Layouts` are built once per program pass, and a rule broken between two passes today surfaces as a failure (each one a bug). |
| Size and risk | About 10 lines and one hook. Medium, for the compile time and what it may expose. |
| Insight | 6 |
| Owner | L03 |

### mlir-5: `idr.take` is three operations chosen by its operand's type, declared with the cell's effects for all three

| Field | Content |
|---|---|
| Evidence | `LowerTake` (`Conversion/Counting.cpp:122-184`) has three bodies: an unboxed sum's take is a projection of its slots (`:131-136`), an atom's take is erased (`:140-143`), and only a cell's take loads, tests uniqueness and yields the cell or null (`:144-181`). ODS declares the cell's effects for all three (`IdrOwnershipOps.td:170`, `Arg<Idr_OwnType, "", [MemRead, MemWrite, MemFree]>:$value`), while the op's own description says an unboxed sum "changes no count". The token is an optional first result found by testing the type (`OpsOwnership.cpp:87-92`); S4 keeps that, as `Optional<Idr_OwnedToken>` beside `Variadic` fields, which ODS can only split with `AttrSizedResultSegments`, a stored copy of what the type and the tag fix. 15 `getToken()` reads in 12 files. |
| Counterexample | A pass that hoists or merges a pure projection sees `MemFree` on an unboxed sum's take and leaves it alone; a new consumer that forgets `if (take.getToken())` treats a projection as a cell. |
| Root cause | One op for "take a constructor value apart", whatever holds it; S3's standard (one op per source of memory, its effect in ODS) was applied to building a cell and not to taking one. |
| Correction | Two ops, as a value read and a memory read are two ops upstream (`mlir/include/mlir/Dialect/Tensor/IR/TensorOps.td:Tensor_ExtractOp`, `mlir/include/mlir/Dialect/MemRef/IR/MemRefOps.td:LoadOp`): `idr.take %box @C -> (token, fields...)`, the take of a cell, its operand a box whose constructor is not an atom, results `(outs Idr_OwnedToken:$token, Variadic<AnyType>:$fields)` with the token always there (no segments), `MemRead, MemWrite, MemFree` on the box as at the base; and `idr.unpack %v @C -> (fields...)`, the take of a value with no cell of its own (an unboxed sum's slots; an atom, no results), with no memory effect (its consumption is its flow edges). Both `InferTypeOpInterface` with S4's field rule and `isCompatibleReturnTypes`; one builder helper picks the op by `isBoxed && !isAtom(tag)`, the one place the two cases meet (essential: a cell or none). |
| Deletion | `TakeOp::getToken`/`getFields` and every token-presence test (S4's ten sites become `isa<TakeOp>`); `LowerTake`'s two type branches (the projection is `LowerUnpack`); S4's `Optional` result and `AttrSizedResultSegments`. |
| Consumers | S4's (L07, L10, L12, L13, L14, L15, L03), and L08 (`Counting.cpp`'s `LowerTake`), L17 (`FlowOps.cpp`: `unpack`'s edges). |
| Discriminator | `idr.take` of an unboxed sum does not verify; the generated `getEffects` of `idr.unpack` is empty; lowering fixtures unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | One op more, one optional result and two lowering branches less. Medium: it is S4 restated, and the owner may weigh it as D-A was weighed (consumers that treat both alike gain an `isa` pair). |
| Insight | 4, 7 |
| Owner | L02 |

### mlir-6: the compiler registers every upstream dialect, extension and pass, so the set it needs is written nowhere

| Field | Content |
|---|---|
| Evidence | `lib/Driver/Main.cpp:120` calls `mlir::registerAllPasses()`; `lib/Driver/Run.cpp:316-318` calls `registerAllDialects(everything)` and `registerAllExtensions(everything)`. The pinned `mlir/include/mlir/InitAllPasses.h:21-25` says of `registerAllPasses`: "If you're building a compiler, you likely don't need this ... The global registry is interesting to interact with the command-line tools." The pipeline runs twelve upstream passes (`Transforms/Pipeline.cpp`: CSE, RemoveDeadValues, SymbolDCE, the transform interpreter, LinalgToLoops, VectorToSCF, ExpandStridedMetadata, LowerAffine, SCFToControlFlow, VectorToLLVM, ConvertToLLVM, ReconcileUnrealizedCasts); `Passes.td` names `dependentDialects` 17 times. The tools (`idris-mlir-opt`, `-reduce`) already use `MlirOptMain`/`mlirReduceMain`, where `registerAll*` is upstream's practice. |
| Counterexample | `idris-mlir x.idr -o a -mlir-print-ir-after=gpu-kernel-outlining` is accepted and prints nothing. Which dialects `convert-to-llvm` lowers depends on what `registerAllExtensions` happens to attach (`mlir/include/mlir/Conversion/ConvertToLLVM/ToLLVMInterface.h:ConvertToLLVMPatternInterface`), not on a list the compiler states; the static driver links every upstream dialect and pass library. |
| Root cause | "Everything" stands in for the set of dialects, extensions and passes the compiler needs. |
| Correction | One registration function of the driver's (`include/idr/Driver/`, `lib/Driver/`) that registers the handoff dialects, LLVM and DLTI, the `ConvertToLLVMPatternInterface` extensions the pipeline lowers through (e.g. `mlir/include/mlir/Conversion/ArithToLLVM/ArithToLLVM.h:registerConvertArithToLLVMInterface`, `mlir/include/mlir/Conversion/MemRefToLLVM/MemRefToLLVM.h:registerConvertMemRefToLLVMInterface`, and the transform extensions the schedule library uses), and the twelve upstream passes by their generated `register...Pass()`. The tools keep `registerAll*`. |
| Deletion | The driver's three `registerAll*` calls and the comment that justifies them; the link of unused upstream libraries (coordinator, CMake). |
| Consumers | L18 (`lib/Driver/Main.cpp`, `Run.cpp`); the coordinator (the driver's CMake link list). |
| Discriminator | `-mlir-print-ir-after=gpu-kernel-outlining` is refused after the change; a missing extension fails loudly in `convert-to-llvm` ("failed to legalize"). |
| Verification here | `make typecheck`; NEEDS-OWNER-BUILD (an omitted extension shows only in `make test`; the driver's size and link time change). |
| Size and risk | About 40 lines. Medium: an omission is a loud failure on the owner's build, never a silent one. |
| Insight | One fact, one place; upstream's own guidance. |
| Owner | L18 |

### mlir-7: every location and dictionary key reaches the C++ reader as MLIR text, which it parses again

| Field | Content |
|---|---|
| Evidence | `compiler/src/IdrisMLIR/MLIR/Bytecode.idr:299-303` (`locationNumber` writes `Textual (location at)`), `:439` (each dictionary key through `attrTextEntry (StringAttr name)`), and `:428` (every attribute other than an array, dictionary or type as text). `MLIR.idr:249-274` (`span`, `wrapped`, `location`) hand-prints MLIR's location grammar: three range spellings and `fused<"library">[...]`. The generated `Encoding/Builtin.idr` encoders `encodeFileLineColLoc`, `encodeFusedLocWithMetadata`, `encodeNameLoc`, `encodeUnknownLoc` and `encodeStringAttr` are referenced nowhere else in `compiler/src`. The reader parses each textual entry with `parseAttribute` (`mlir/lib/Bytecode/Reader/BytecodeReader.cpp`). idris-emit's kept list says the builtin records "are generated", not that they go unused. |
| Counterexample | One op's location is held three times: as the Idris `Location`, as hand-printed text, and as the grammar the C++ parser re-runs on every distinct location; a printing slip is a parse error at read time, or a different location silently. |
| Root cause | The writer prints locations and strings instead of writing them through the generated builtin records. |
| Correction | With S24's sum: no source is `encodeUnknownLoc`, a binder's name `encodeNameLoc`, a library location `encodeFusedLocWithMetadata` with `"library"`, and keys and strings `encodeStringAttr` (`mlir/include/mlir/IR/BuiltinDialectBytecode.td:NameLoc`, `UnknownLoc`, `FusedLocWithMetadata`, `StringAttr`). A span is `FileLineColRange`, whose member layout is upstream C++ (`mlir/lib/IR/BuiltinDialectBytecode.cpp`), so `Bytecode.idr` writes it by hand as it writes the rest of the container. |
| Deletion | `span`, `wrapped`, `location`, the `Textual` location path and the textual keys. |
| Consumers | L20 (`MLIR.idr`, `MLIR/Bytecode.idr`, `Loc.idr`). |
| Discriminator | The `.mlirbc` bytes change; `idris-mlir-opt --mlir-print-debuginfo` prints the same module before and after, locations included. |
| Verification here | The Chez build writes the bytecode; the identity check is NEEDS-OWNER-BUILD. |
| Size and risk | About 40 lines of Idris. Low to medium: a layout slip fails loudly at read. |
| Insight | One representation: the generated module already carries the records. |
| Owner | L20 |

### mlir-8: returned-arguments solves an optimistic forward dataflow by hand

| Field | Content |
|---|---|
| Evidence | `lib/Transforms/Tail/Returned.cpp` (259 lines): `:71` `class Solver`, a recursive evaluator with its own cycle guard (`visiting`, `:84-87,164`) and loop hypotheses (`assumed`, `:131,154-157,163`); around it a loop over `llvm::scc_begin` (`:210`) and a `MonotoneWorklist<ResultOf, Known>` (`:59`) that re-walks the callers on a cycle. `Known` (`Transforms/Tail.h`, height 2) is already a join-semilattice. transforms-b-4 replaces only the op ladder and analysis-2 only the SCC loop; the fixpoint machinery is no finding's. |
| Counterexample | Each new region shape needs an evaluator arm and a hypothesis rule, and termination rests on the `visiting` and `assumed` guards rather than on a lattice the framework propagates; the optimistic start `assumed` simulates is the solver's own (every lattice starts at bottom). |
| Root cause | A sparse forward analysis over SSA values (which entry argument a value is) is written as an evaluator and a call-graph scheduler. |
| Correction | `SparseForwardDataFlowAnalysis<Lattice<Known>>` with `DeadCodeAnalysis` loaded, interprocedural: override `visitCallableOperation` (argument `i` is `arg(i)`) and `visitCallOperation` (a result is the caller's operand lattice where the callee's return operand is `arg(a)`, read with `getOrCreateFor(getProgramPointAfter(call), operand)`); `visitOperation` leaves `ub.poison` at bottom and joins a `SelectLikeOpInterface`'s two values; region branches come from the base. Upstream: `mlir/include/mlir/Analysis/DataFlow/SparseAnalysis.h:AbstractSparseForwardDataFlowAnalysis::visitCallOperation`, `visitCallableOperation`; `mlir/include/mlir/Analysis/DataFlowFramework.h:DataFlowAnalysis::getOrCreateFor`. In-tree precedent: `Analysis/Ownership/ExclusivityAnalyses.cpp:254,274` overrides both hooks. |
| Deletion | `Solver`, `assumed`, `visiting`, `Results` and the worklist, the SCC loop and the `CallGraph` include, the `resultOf`/`argumentOf` ladder (which subsumes transforms-b-4), Returned's part of analysis-2: about 90 lines go, about 50 come. |
| Consumers | L13 (`Tail/Returned.cpp`, `Transforms/Tail.h`: `Known` gains `join`, `print` and `==` for `Lattice`). transforms-b-4 is folded in. |
| Discriminator | `tests/idr/returned/` is empty today: fixtures that thread an argument through `scf.if`, `scf.while`, `scf.execute_region` and mutual recursion, checked through the pass's `dropped` statistic. |
| Verification here | `make typecheck`; NEEDS-OWNER-BUILD (the fixtures; a result returned only by calls that never return must stay unconstrained, which dead callee returns give at bottom). |
| Size and risk | Medium. |
| Insight | 13, 14: one fixpoint engine, upstream's. |
| Owner | L13 |

### mlir-9: a match does not tell `RegionBranchOpInterface` that its default region's argument is the scrutinee

| Field | Content |
|---|---|
| Evidence | `lib/IR/Regions.cpp:66-68,85-87`: `getSuccessorInputs` gives nothing for a region, and no `getEntrySuccessorOperands` is declared (`IdrMatchOps.td:20-21`), although the default region takes the scrutinee (`OpsMatch.cpp:105-108`; S2). Upstream solvers therefore set that argument to its entry state (`mlir/include/mlir/Analysis/DataFlow/SparseAnalysis.h:SparseForwardDataFlowAnalysis::visitNonControlFlowArguments`), and `ExclusivityAnalyses.cpp:193-250` overrides neither hook. The same fact is written by hand in four places: `FlowOps.cpp:139-141`, `BindingTimes.cpp:177`, `IdentitiesRecord.cpp:153,275`, and S11's planned `Same` arm. |
| Counterexample | (Inferred from the code path, not run.) An exclusive list matched with a default region whose argument goes to an in-place update: Exclusivity calls the argument shared, so no in-place path is taken; Constants and Ranges also see it at entry state. |
| Root cause | The default argument's meaning is stated in prose, a verifier and four hand arms, not through the interface every upstream solver and `getControlFlowPredecessors` read. |
| Correction | `Idr_MatchOpBase` declares `getEntrySuccessorOperands` (the scrutinee for the default region, nothing for a case region) and `getSuccessorInputs(defaultRegion)` gives its one argument (`mlir/include/mlir/Interfaces/ControlFlowInterfaces.td:RegionBranchOpInterface`). Then `mlir/include/mlir/Analysis/SliceWalk.h:getControlFlowPredecessors(arg)` is `{scrutinee}`, and S11's arm is that call. S2 now states this. |
| Deletion | `FlowOps.cpp:139-141` (`Flow.cpp`'s `forwardFrom` derives the edge from the interface); BindingTimes' default arm; IdentitiesRecord's two default tests; S11's hand default-region case. |
| Consumers | L01 (`IdrMatchOps.td`, `Regions.cpp`); L17 (`FlowOps.cpp`); L09 (`BindingTimes.cpp`); L10 (`IdentitiesRecord.cpp`, `Borrows.cpp`); L04 (S11); and the other readers of `forwardedValues` (`Ownership/Commit.cpp:82` L13, `Verify/OwnedOps.cpp:33`, `Verify/OwnedRegions.cpp:79` L15, `Verify/Program.cpp:166` L03), which must read this entry edge as `FlowOps.cpp:139` reads it today: Borrows' "a forwarded value is owned" (`Borrows.cpp:287`) applies to terminator edges only. |
| Discriminator | An Exclusivity fixture whose default argument reaches an in-place update (excl after, shared before); a unit box for `getControlFlowPredecessors` on a default argument. |
| Verification here | `make typecheck`; NEEDS-OWNER-BUILD (analyses see a new edge). |
| Size and risk | About 10 lines added, 15 deleted. Medium-high: every `forwardedValues` reader sees the edge. |
| Insight | One fact, one place, the interface upstream reads. |
| Owner | L01 |

### mlir-10: lowering's phase 0 renames functions by recomputing `mangle` at each use it knows, outside a rewriter

| Field | Content |
|---|---|
| Evidence | `lib/Conversion/FuncToFunc.cpp:24-36` `lowerCallsAndReturns` walks a body, rebuilds each `idr.call` as `func.call` on `mangle(call.getCallee())` and each `idr.return`, with `replaceAllUsesWith` and `erase` inside the walk and outside any rewriter; `:43-62` rebuilds each definition on `mangle(fn.getSymName())` and sets the root again by hand. The rename covers exactly two kinds of symbol use. |
| Counterexample | Any other symbol use of a function that reaches idr-lower keeps its unmangled name and fails symbol verification after phase 0. None does today (closures are gone after defunctionalization), so a new op that names a function is missed silently. |
| Root cause | A rename is a map, re-derived at each use site the file knows instead of applied to every use. |
| Correction | Compute `old -> mangle(old)` once; definitions take their mangled name where they become `func.func`; every use is rewritten by one `AttrTypeReplacer` over `SymbolRefAttr` (`mlir/include/mlir/IR/AttrTypeSubElements.h:AttrTypeReplacerBase::recursivelyReplaceElementsIn`), which covers calls, the root and any attribute or type; the op change (`idr.call`/`idr.return` to `func`) is 1:1 patterns under `mlir/include/mlir/Transforms/WalkPatternRewriteDriver.h:walkAndApplyPatterns`. Phase 0 stays serial. |
| Deletion | The hand rebuild and RAUW in `lowerCallsAndReturns`, the per-call `mangle`, the hand reset of the root. |
| Consumers | L08 (`FuncToFunc.cpp`, `FuncToFunc.h`, `Lower.cpp`). |
| Discriminator | A unit box: a function with a non-ASCII name referenced through a `FlatSymbolRefAttr` that is not a call names the mangled symbol after phase 0; `tests/idr/lower/*` lower identically. |
| Verification here | `make typecheck`. |
| Size and risk | About 15 lines. Low: names are byte-identical. |
| Insight | One mapping, applied by MLIR's replacer. |
| Owner | L08 |

### mlir-11: lowering patterns compute converted types through `Layouts`, around their `TypeConverter`

| Field | Content |
|---|---|
| Evidence | `lib/Conversion/RuntimeCalls.cpp:130` (`this->layouts.components(type)` for each result of every runtime-call op); `Arrays.cpp:220-222` (`LowerUpdate` takes its yielded types from `layouts.components`, then calls `applySignatureConversion(..., this->getTypeConverter())` at `:228`: two sources for one conversion in one pattern); `Buffers.cpp:40`. The worker's converter (`Lower.cpp:85-92`) answers idr types and memrefs with the same `layouts.components`. |
| Counterexample | The paths agree only because the converter's one 1:N conversion calls the same function; a conversion added to the converter (context-aware, or memrefs through descriptors) changes `convertType` and not these sites, and a pattern then replaces an op with values of another arity than its uses were converted to. |
| Root cause | A value's lowered types belong to the `TypeConverter`, and these patterns go around it. |
| Correction | `this->getTypeConverter()->convertType(type, out)` / `convertTypes` (`mlir/include/mlir/Transforms/DialectConversion.h:TypeConverter::convertType`, cached by the converter). `Layouts::components` is read directly only where a pattern needs a component's `counted` bit (S20's `Component`), which no `TypeConverter` carries. |
| Deletion | The three direct calls. |
| Consumers | L07 (`Arrays.cpp`, `Buffers.cpp`), L06 (`RuntimeCalls.cpp`). |
| Discriminator | Lowered LLVM identical on `tests/idr/lower/{io,arrays,buffer}.mlir`; a grep spec: no `layouts.components(` in a pattern that does not read `counted`. |
| Verification here | `make typecheck`. |
| Size and risk | Three sites, about 6 lines. Low. |
| Insight | One fact, kept in its MLIR home. |
| Owner | L07 |

### mlir-12: a call cannot tell MLIR what it does, so the tree keeps a second effects API, a canonicalizer bound to a table, and its own CSE

| Field | Content |
|---|---|
| Evidence | `lib/IR/Func/Call.cpp:1-16,61-68`: every `idr.call` declares IO read and write, crash and divergence, because "the callee's effects are the one copy; the call holds none". Everything that wants the real answer goes around `MemoryEffectOpInterface`: `CalleeEffects` (`include/idr/IR/Flow.h:90-111`) and `ownEffects`/`onlyAllocates`/`performsIO` over it, 82 references in 31 files; `calleeEffect` and an `erase_if` that edits the interface's answer (`lib/IR/Effects.cpp:120-157`); `CalleePattern`, `withCallees`, `bindCallees` (`include/idr/IR/Canon.h:29-77`, `lib/IR/Canon/Callees.cpp`) used by Sink, CaseOfCase and MoveOut; an idr canonicalizer pass that exists to carry the table (`Transforms/Canonicalize/Canonicalizer.cpp`), which the static pipeline builds with `nullptr` (`Pipeline.cpp:57,87`); `idr-pure-calls` (`Optimize/PureCalls.cpp`, 183 lines), which does "for idr.call what canonicalize and CSE do" with its own `ScopedHashTable` and dominator walk; function passes reading sibling functions through a program symbol table (`StructureLoops.cpp:52-53`). transforms-b's kept list records this as D13 ("calls hold no effects"). The dialect already does the opposite for grades: a call's types restate its callee's signature, checked in `CallOp::verifySymbolUses` (`Call.cpp:35-57`). |
| Counterexample | In the static pipeline's `idr.func(canonicalize, cse)` groups (`Pipeline.cpp:55-59,85-89`) a dead call of a pure callee is never erased and two identical ones never merged; upstream liveness keeps every call's operands live. |
| Root cause | "What a call may do" lives only on the callee, so the op cannot answer the question MLIR asks every op. |
| Correction | `idr.call` holds `DefaultValuedProp<EnumProp<Idr_Effect>, "::idr::anyEffect">:$effects`, S6's property (`mlir/include/mlir/IR/Properties.td:DefaultValuedProp`, `mlir/include/mlir/IR/EnumAttr.td:EnumProp`), as `llvm.call` carries `memory_effects` (`mlir/include/mlir/Dialect/LLVMIR/LLVMOps.td:LLVM_CallOp`). `CallOp::getEffects` returns ir-verify-6's table of the property, plus `consumedEffects`, plus `MemAlloc` on each linear result (so CSE never merges two calls that each give a fresh linear value, PureCalls' `isLinear` guard today, while `mlir/include/mlir/Interfaces/SideEffectInterfaces.h:wouldOpBeTriviallyDead` still erases an unused one). The one solve writes a call's effects when it writes its callee's (Waves' turn, where no worker holds the caller); `CallOp::build(FuncOp, ...)` copies them; `verifySymbolUses` checks that a call's effects contain its callee's, as it checks the types. Then upstream does the work: CSE (`mlir/lib/Transforms/CSE.cpp`), the greedy driver's trivially-dead erase, `mlir/lib/Analysis/DataFlow/LivenessAnalysis.cpp`; and `idr-canonicalize` is upstream's `canonicalize{region-simplify=disabled top-down}` (`mlir/include/mlir/Transforms/Passes.td:Canonicalizer`). |
| Deletion | `CalleeEffects` and every effects-only `const CalleeEffects *` parameter (the signature mode of `consumes` stays, judged essential); `calleeEffect`, the `erase_if`; `withCallees`/`bindCallees`; `idr-pure-calls` (the pass, its `InnerPasses.td` entry, two statistics); `idr-canonicalize`'s wrapper; the table walk in `effectsCovered`; StructureLoops' table; transforms-b-10's helper. About 400 lines over about 25 files; about 15 added. |
| Consumers | L03 (`IdrOps.td`, `Func/Call.cpp`, `Effects.cpp`, S6/S7), L01 (`Canon/**`, `Canonicalize/**`), L11 (PureCalls, Optimize, Waves, Specialize), L13 (Rc, Place, Placement, Reshape, StructureLoops, `Pipeline.cpp`), L10 (Identities), L17 (`Flow.h`), L14 (Expect); the coordinator (`IdrDialect.h`). The Idris builders do not change (a property with a default is no parameter, S0). |
| Discriminator | A fixture with a dead call and two identical calls of one pure callee: `idr.func(canonicalize, cse)` alone erases the first and merges the others (all three stay today); a call whose `effects` lacks a bit of its callee's fails verification naming the call; two calls returning `!idr.lin<...>` stay two under `-cse`. |
| Verification here | `make typecheck`; NEEDS-OWNER-BUILD (CSE and canonicalize start erasing and moving calls). |
| Size and risk | Medium-high: a wrong `effects` write becomes a miscompile instead of a missed optimization; the verifier's containment rule is the guard. It reverses D13 (one copy of a call's effects on the callee) for a verified copy, as the dialect already keeps the callee's types on the call: the owner's decision. |
| Insight | 13 (a second CSE and DCE), 6 |
| Owner | L03 |

### mlir-13: nested and inner passes get their parent's analyses as C++ constructor arguments, so they are unregistered pass wrappers

| Field | Content |
|---|---|
| Evidence | Four `PassWrapper`s hold references to a parent's analysis, each with a hand `getArgument`/`getDescription` and no `Passes.td` entry: `NarrowWords(const Ranges &)` (`Narrow/Narrow.cpp:68`), `DropReturned(const Returned &)` (`Tail/ReturnedArguments.cpp:101`), `RcPlace(const Reuses &, const CalleeEffects &)` (`Ownership/Place.cpp:24`), `RcCommit(const Exclusivity &, const SymbolTable &)` (`Ownership/Commit.cpp:103`); idr-rc builds `Reuses` and `Borrows` by hand and hands them down (`Rc.cpp:73-75,87,110`). Four inner passes take the ready set, the node table and `Pass::Statistic &` through `let constructor` (`InnerPasses.td`, "none is registered"). |
| Counterexample | None of these can be run, tested or reduced with `--pass-pipeline`, and a crash reproducer names a pass the parser cannot read back. |
| Root cause | A program fact is a C++ value handed to a child, not an analysis held by the program's `AnalysisManager`. |
| Correction | Where the fact can be an analysis, it is one, with the `(Operation *, AnalysisManager &)` constructor (calling `getAnalysis` inside an analysis constructor is supported: `mlir/include/mlir/Pass/AnalysisManager.h:AnalysisManager::getAnalysis`; Escapes and Labels do it): `Reuses` (reading `am.getAnalysis<Layouts>()`), `Borrows` (reading `Reuses`), `Returned`, `Ranges` (its `FailureOr` inside). The parent calls `getAnalysis<T>()` and runs the pipeline; the child reads `getCachedParentAnalysis<T>(program)` (`mlir/include/mlir/Pass/Pass.h:Pass::getCachedParentAnalysis`; precedent `mlir/lib/Dialect/OpenACC/Transforms/ACCEmitRemarksData.cpp`); each pass gets a `Passes.td` or `InnerPasses.td` entry with no `constructor`, so it is registered and reproducible. `Exclusivity` stays a constructor argument: it takes the copy table, can fail, is solved twice, and is read after `redirectCalls` changes the IR inside the pass (`Rc.cpp:97-110`), none of which an analysis built from `(op, am)` can be. With mlir-14 the steps of idr-rc are passes of their own, and `Reuses` crosses a pass boundary as an analysis in any case. |
| Deletion | The `PassWrapper` boilerplate in Narrow, ReturnedArguments and Place; their factory parameters; the `let constructor` lines of the inner passes whose inputs are analyses. |
| Consumers | L13 (Rc, Place, ReturnedArguments, `Passes.td`, `InnerPasses.td`), L10 (the constructors of Reuses and Borrows), L12 (Narrow), L11 (Optimize's inner passes). |
| Discriminator | `idris-mlir-opt --pass-pipeline='builtin.module(idr.program(idr.func(idr-rc-place)))'` parses, and without its parent fails with "internal error: idr-rc-place: no Reuses of the program"; `grep -rn 'PassWrapper<' foreign/idr/lib` lists only test passes and `RcCommit`. |
| Verification here | `make typecheck`. |
| Size and risk | About 120 lines changed. Low to medium. The cost, raised by the analyses' inventory (mlir-audit.md), is real: `getCachedParentAnalysis` returns an optional, so each child gains an internal-error branch for a state its constructor makes impossible today, and the nested run uses the parent's own analysis manager, so the cache lives exactly as long as the argument does. What is bought is registration: passes MLIR's tools can name, run and reduce. The owner weighs the two. |
| Insight | 13, 14 |
| Owner | L13 |

### mlir-14: pipeline steps are composed inside passes: idr-rc's five steps, idr-effects inside idr-defunctionalize, symbol-dce inside idr-optimize

| Field | Content |
|---|---|
| Evidence | idr-rc runs five steps in one `runOnOperation` (`Ownership/Rc.cpp:55-120`): a per-function rewrite with hand parallelism, the reuse and borrow decisions and signature writes, `program.setStage(Owned)` midway (`:81`), two nested runs (`:87`, `:110`), an erase (`:112`) and a counting walk for statistics. idr-defunctionalize ends by calling idr-effects' body, `solveEffects` (`Defunctionalize/Pass.cpp:139`), and `buildPipeline` never lists idr-effects. idr-optimize runs symbol-dce as a dynamic pipeline to count `numErased` (`Optimize/Optimize.cpp:111-119`), though the pipeline runs it anyway (`Pipeline.cpp:77`) and upstream counts `num-dce'd` (`mlir/include/mlir/Transforms/Passes.td:SymbolDCE`). |
| Counterexample | `-mlir-print-ir-after=idr-rc` shows the program after all five steps, and a crash in placement reproduces as the whole of idr-rc; S27 cannot describe idr-rc, which requires `first` and sets `owned` partway through. |
| Root cause | The pipeline's order lives partly in `buildPipeline` and partly in pass bodies. |
| Correction | `buildPipeline` lists every step, inside the registered `idr-pipeline` (`mlir/include/mlir/Pass/PassRegistry.h:PassPipelineRegistration`): idr-effects after idr-defunctionalize; symbol-dce after idr-optimize; idr-rc as `idr.func(idr-rc-buffers)`, `idr-rc-grades` (a program pass that writes the owned grades, sets `owned` under S27, and leaves `Reuses` cached and preserved), `idr.func(idr-rc-place)` (reads `Reuses`, mlir-13), `idr-rc-exclusive` (solve, grade copies, redirect), `idr.func(idr-rc-commit)`, then symbol-dce (transforms-b-7). Each step a `Passes.td` entry with its statistics and its S27 stage. |
| Deletion | Rc's `runNested` calls and its counting walk; the `solveEffects` call in defunctionalize; Optimize's dynamic symbol-dce and `numErased`. |
| Consumers | L13 (`Rc.cpp`, `Pipeline.cpp`, `Passes.td`), L12 (`Defunctionalize/Pass.cpp`), L11 (`Optimize.cpp`), L10; the coordinator (S27's spec test of pipeline order). |
| Discriminator | `-mlir-print-ir-after=idr-rc-place` prints the placed program; S27's spec test passes with idr-rc's steps listed. |
| Verification here | `make typecheck`; NEEDS-OWNER-BUILD (the canonicalize/CSE groups between the steps, if any are added, change output). |
| Size and risk | About 100 lines move; four new `Passes.td` entries. Low to medium. |
| Insight | 14, 13 |
| Owner | L13 |

### mlir-15: an element's address is computed by two formulas, ours and upstream's `getStridedElementPtr`

| Field | Content |
|---|---|
| Evidence | `lib/Conversion/Descriptors.cpp:254-276` `elementAddress` (offset plus each index times its stride in `arith`, then an `i8` GEP of `place * stride` from `elementsOf(cell)`) and `:278-285` `bufferElementAddress`, declared in `include/idr/Conversion/Arrays.h:92-104`; four callers (`Memrefs.cpp:70`, `Arrays.cpp:143-146` through an ad hoc `Descriptor{cell, 0, {count}, {1}}`, `Arrays.cpp:164-168`, `Buffers.cpp:30-33`). In the same functions a word's `memref.load` lowers through upstream's `LoadOpLowering`, which calls `getStridedElementPtr` on the descriptor our materialization builds (`Descriptors.cpp:131-143,202-209`), and our descriptor converter already gives an idr element as `!llvm.array<stride x i8>` (`:191-195`), so upstream's GEP steps `stride` bytes. |
| Counterexample | A load at `[%i, %j]` of `memref<?x?xi64>` and of `memref<?x?x!idr.str>` lowers to two expressions of the same descriptor fields (upstream's `llvm.mul`/`add nsw` over `alignedPtr`; ours `arith` without `nsw` over `cell + sizeof(header)`); a change to how a view's offset applies (conversion-3) is made twice, and CSE cannot share them. |
| Root cause | An element's address is a fact of the descriptor, held as upstream's helper for words and our own for everything else. |
| Correction | `elementAt`, `addressOf` and `byteAt` call `LLVM::getStridedElementPtr(b, loc, descriptors, type, descriptorOf(...), indices, LLVM::GEPNoWrapFlags::inbounds)` (`mlir/include/mlir/Conversion/LLVMCommon/Pattern.h:getStridedElementPtr`, over `mlir/include/mlir/Conversion/LLVMCommon/MemRefBuilder.h:MemRefDescriptor::bufferPtr`); `LowerArrayNew`'s fill is one `llvm.getelementptr inbounds` of the converted element type at the flat index. Reading and writing an element's slots stays ours. |
| Deletion | `elementAddress`, `bufferElementAddress`, their declarations, the ad hoc `Descriptor`, the `unpack` calls in `addressOf` and `byteAt`: about 45 lines and one formula. |
| Consumers | L07 (`Descriptors.cpp`, `Memrefs.cpp`, `Arrays.cpp`, `Buffers.cpp`, `Arrays.h`). |
| Discriminator | After idr-lower, canonicalize and cse, a word load and an element load at one index of two views of one cell share one offset computation. |
| Verification here | `make typecheck`; NEEDS-OWNER-BUILD (the lowered IR changes: `nsw` arithmetic, an `insertvalue`/`extractvalue` chain canonicalize folds). |
| Size and risk | About 45 lines. Low to medium: on a strided view `bufferPtr`'s offset GEP carries no `inbounds` where ours did; the `nsw` upstream adds is sound since every index is guarded in bounds. |
| Insight | One thing, one representation. |
| Owner | L07 |

### mlir-16: the facts at function boundaries are written by a second walk that recounts the signature conversion

| Field | Content |
|---|---|
| Evidence | `lib/Conversion/Facts.cpp:96-121` `Facts::apply` runs after the parallel conversion and the merge (`Lower.cpp:226`), serially over every `func.func`, finds each function's idr signature in a map by mangled name filled before phase 0 (`Facts.cpp:73-74`, `Facts.h:46`, `Lower.cpp:180`), and recounts each parameter's components with `layouts.components(type).size()` and a running index, held equal to the conversion only by `assert(at == fn.getNumArguments())` (`:113`). The conversion that made those parameters, upstream's `populateFunctionOpInterfaceTypeConversionPattern<func::FuncOp>` (`Lower.cpp:128`), knew the mapping and dropped it. |
| Counterexample | None reachable today: the recount agrees because both sides call `layouts.components`. A changed rule writes `nonnull` on the wrong parameter in a release build. |
| Root cause | The map from a parameter to its components is held twice: by the dialect conversion's `SignatureConversion` and by Facts. |
| Correction | idr-lower's signature pattern becomes ours under the same driver (`OpConversionPattern<func::FuncOp>` doing what `convertFuncOpTypes` does for a one-block body), and for each old input `i` writes the component facts at `getInputMapping(i)->inputNo + k` (`mlir/include/mlir/Transforms/DialectConversion.h:TypeConverter::SignatureConversion::getInputMapping`), as upstream's FuncToLLVM moves argument attributes across a 1:N signature (`mlir/lib/Conversion/FuncToLLVM/FuncToLLVM.cpp:propagateFunctionArgResAttrs`). With conversion-5 the facts depend on the type alone, and the pattern runs on the workers. |
| Deletion | `Facts::apply`, `signatures` and its fill, the `program` member, the assert, `Lower.cpp:180,226` and the `populateFunctionOpInterfaceTypeConversionPattern` line: about 40 lines out, 25 in. |
| Consumers | L07 (`Facts.h`, `Facts.cpp`), L08 (the two `Lower.cpp` lines). Lands with conversion-5. |
| Discriminator | `tests/idr/lower/llvm-facts.mlir` prints the same attributes; a function whose memref parameter sits between two boxes keeps its facts on both pointers. |
| Verification here | `make typecheck`; output unchanged by design (the owner's `make test-idr` checks it); compile time only improves (a serial walk moves onto the workers). |
| Size and risk | Low. |
| Insight | Do not recompute what the framework recorded. |
| Owner | L07 |

### mlir-17: narrowing runs upstream's patterns and our folders under two hand-written drivers

| Field | Content |
|---|---|
| Evidence | `lib/Transforms/Narrow/Copy.cpp:120-163`: `arith::populateIntRangeNarrowingPatterns(patterns, solver, {32})` driven by a hand `PatternApplicator` (`:134-137`), an `ops()` re-walk and an `applyOnce` loop, three times (users first, index casts defs first, a reverse trivially-dead sweep), defended by a 16-line comment. `Narrow/Narrow.cpp:102-128`: a pre-order walk collects conversions, `OperationFolder::tryToFold` runs on each, a reverse trivially-dead erase follows, under two actions of its own (`:51-63`). |
| Counterexample | `applyOnce` is correct only while "a pattern erases only the op it matched" (`Copy.cpp:145-146`), a property of upstream's pattern set, which tracks main: a pattern added upstream that erases a neighbour leaves the pre-collected list dangling. The greedy driver has no such precondition. |
| Root cause | The patterns were adopted without the driver upstream runs them under; the users-first order `NarrowCmpI` needs was rebuilt by hand. |
| Correction | `applyPatternsGreedily(function, patterns, GreedyRewriteConfig().setUseTopDownTraversal(false).enableFolding(false).setRegionSimplificationLevel(GreedySimplifyRegionLevel::Disabled).setListener(&listener))`, as upstream's own pass configures it (`mlir/lib/Dialect/Arith/Transforms/IntRangeOptimizations.cpp:IntRangeNarrowingPass::runOnOperation`); in `NarrowWords`, `applyOpPatternsGreedily(conversions, {}, GreedyRewriteConfig().setStrictness(GreedyRewriteStrictness::ExistingOps)...)` under the one fold action (`mlir/include/mlir/Transforms/GreedyPatternRewriteDriver.h`). The driver skips folding `ConstantLike` ops and erases trivially dead ones itself. |
| Deletion | `Copy.cpp:134-163` and most of the comment; `Narrow.cpp:107-128`, `NarrowEraseAction`: about 55 lines out, 15 in. |
| Consumers | L12 (`Narrow/**`); L13 (`tests/idr/actions/narrow.mlir`: the `idr-narrow-erase` counter goes). |
| Discriminator | The vectorize fixtures keep their 32-bit lanes and `nneg` flags; the narrow fixtures keep their words; skipping the narrow actions still leaves the module unchanged. |
| Verification here | `make typecheck`; NEEDS-OWNER-BUILD (visit order and constant placement can change printed IR). |
| Size and risk | Low to medium. The driver stops at its iteration budget and the result is ignored, as AGENTS.md's budget rule asks: a spent budget leaves the copy less narrowed, never wrong. |
| Insight | Take the driver along with the patterns. |
| Owner | L12 |

### mlir-18: while-do's dead sweep is upstream's `eliminateTriviallyDeadOps`

| Field | Content |
|---|---|
| Evidence | `lib/Transforms/Tail/WhileDo.cpp:302-308` lists the before block's ops and erases each `isOpTriviallyDead` one in reverse, with a comment explaining the iterator hazard it works around. |
| Counterexample | None in output; a hand copy of a utility the pin ships. |
| Root cause | The utility was not adopted. |
| Correction | `eliminateTriviallyDeadOps(rewriter, loop.getBefore(), /*includeNestedRegions=*/false)` (`mlir/include/mlir/Transforms/RegionUtils.h:eliminateTriviallyDeadOps`, whose first step is this reverse sweep). |
| Deletion | 8 lines. |
| Consumers | L13 (`Tail/WhileDo.cpp`). |
| Discriminator | `tests/idr/loops/*` unchanged. |
| Verification here | `make typecheck`; output unchanged by construction. |
| Size and risk | Very low. |
| Insight | Use the shipped utility. |
| Owner | L13 |

### mlir-19: rewrites to an existing value are written as patterns instead of folds

| Field | Content |
|---|---|
| Evidence | `lib/IR/Canon/Output.cpp:20-32` `PutStrOfEmpty` matches the constant `""` and replaces the op by its world, under a comment that says "A folder of put_str would say the same; the op declares none"; `Canon/PutList.cpp:33-36` restates the empty case; DRR `Idr_HeadOfCons`, `Idr_HeadOfCheckedCons` (`Canon/Canonicalize.td:52,60-62`) `replaceWithValue`, though `StrHeadOp` has a folder (`Fold/Strings.cpp:168`). |
| Counterexample | `createOrFold`, `OperationFolder` and a pattern-free greedy run apply folds only; none drops `put_str ""` or reads the head of a cons. |
| Root cause | "This op is one of its operands" is the folder's job, which every folding client sees; a canonicalization pattern is seen by the canonicalizer alone. |
| Correction | `let hasFolder = 1` on `idr.io.put_str`, `OpFoldResult PutStrOp::fold(FoldAdaptor)` giving the world for `""`; `StrHeadOp::fold` gives the `str.cons` character, looking through `idr.check.nonempty`; the C++ head pattern (ir-verify-16) keeps only the cases that build an op. |
| Deletion | `PutStrOfEmpty`, the empty branch, two DRR patterns: about 22 lines out, 8 in. |
| Consumers | L01 (`Canon/Output.cpp`, `Canon/PutList.cpp`, `Canon/Canonicalize.td`), L16 (`OpsStrings.cpp`, `Fold/Strings.cpp`), L24 (`IdrIOOps.td`'s `hasFolder`). |
| Discriminator | The canon fixtures with `put_str ""` and head-of-cons unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | Low. |
| Insight | A fold for "this op is one of its operands". |
| Owner | L01 |

### mlir-20: Escapes keeps calls away from upstream's backward base by hand; the solver's configuration and external-call hook state its call rule

| Field | Content |
|---|---|
| Evidence | `lib/Analysis/Escapes.cpp:149-156`: `Solve::visit` returns on an `idr.call` before the base's visit runs (`:139-141`: "so that the base never takes an idr.call by its rule"); `Escapes.h:69-71` keeps a `SymbolTableCollection unresolved` that "stays empty"; the solver is default-constructed, so interprocedural (`mlir/include/mlir/Analysis/DataFlowFramework.h:DataFlowConfig`), and the base would otherwise meet the callee's whole entry state into the argument (`mlir/lib/Analysis/DataFlow/SparseAnalysis.cpp`), which `EscapesDetail.h:25-32` says must not happen. The analysis's real rule is `visitCall` (`Escapes.cpp:294-314`). |
| Counterexample | None in output; in structure the solver is configured for one call rule while the analysis enforces another, held in place by the order of two statements. |
| Root cause | The solver's default configuration is kept and its consequence undone by hand. |
| Correction | `DataFlowSolver solver{DataFlowConfig().setInterprocedural(false)}` and `void visitExternalCall(CallOpInterface call, ...) override { visitCall(cast<CallOp>(call)); }` (`mlir/include/mlir/Analysis/DataFlow/SparseAnalysis.h:SparseBackwardDataFlowAnalysis::visitExternalCall`, which the base calls for every call when the solver is not interprocedural); in-tree precedent: Constants takes callee summaries through the forward hook (`Constants.h:40-50`). |
| Deletion | `Escapes.cpp:153-156`, the clause at `:140-141`, the comment and the unused collection at `Escapes.h:69-71`. |
| Consumers | L09 (`Escapes.h`, `Escapes.cpp`). |
| Discriminator | `tests/idr/stack/expect.mlir` and the stack e2e fixtures unchanged. |
| Verification here | `make typecheck`; NEEDS-OWNER-BUILD (the base also revisits a call when its results' states grow: idempotent, extra visits). |
| Size and risk | About 7 lines. Low. |
| Insight | The configuration states the rule. |
| Owner | L09 |

### mlir-21: Exclusivity's `Entry` analysis repeats upstream's rule for public callables

| Field | Content |
|---|---|
| Evidence | `lib/Analysis/Ownership/ExclusivityAnalyses.cpp:114-132`: `class Entry : DataFlowAnalysis` marks the predecessors of `program.lookupRoot()` unknown; loaded at `:330` beside `DeadCodeAnalysis`, whose `initializeSymbolCallables` already marks every public callable so (`mlir/include/mlir/Analysis/DataFlow/DeadCodeAnalysis.h:DeadCodeAnalysis`), and an `idr.func` is public exactly when it is the root (`IdrOps.td`, `getVisibility`). `Ranges.cpp:61` relies on the upstream rule alone. |
| Counterexample | None in behaviour; "the root is entered from outside" is stated twice, and a second entry point would be added to both. |
| Root cause | The analysis was written without relying on the visibility the IR already derives from the root. |
| Correction | Delete `Entry`; the root runs from outside because it is public (`mlir/include/mlir/IR/SymbolInterfaces.td:SymbolOpInterface::isPublic`). The same fact is `fn == root` in `Borrows.cpp:98,103,135-137` and in analysis-14's design; both read `fn.isPublic()`. |
| Deletion | About 21 lines and one analysis class. |
| Consumers | L10 (`ExclusivityAnalyses.cpp`, `Borrows.cpp`). |
| Discriminator | `tests/idr/rc/exclusive.mlir` and the rc fixtures unchanged; a root with box parameters keeps them shared. |
| Verification here | `make typecheck`; output unchanged by construction. |
| Size and risk | Trivial. |
| Insight | One fact, stated once in the IR and read by upstream. |
| Owner | L10 |

### mlir-22: failing properties and the one remark-emitting pass are checked by FileCheck on stderr, where `-verify-diagnostics` checks place and count

| Field | Content |
|---|---|
| Evidence | `tests/idr/expect` (45 files): 59 runs `%status 1 idris-mlir-opt ... --idr-expect=... 2> %t.err`, matched by 111 `CHECK`/`CHECK-DAG: error: expected ...` lines with `{{.*}}` holes and no `file:line:col`, counted by 34 `grep ... \| count N` lines; 17 of its 37 `NEEDS-ACCEPTANCE` lines ask for exactly the place this cannot confirm (`calls.mlir:1`). Outside it, 63 negative idr-expect runs, 44 checking only the exit status. `tests/idr/specialize/binding-times.mlir:1-2` checks the remarks of `Specialize/Report.cpp:35` with location-free `CHECK-DAG: remark:`. `idris-mlir-opt` is `MlirOptMain` (`tools/idris-mlir-opt.cpp:102`), and 29 files in `tests/idr` already use `-verify-diagnostics`. |
| Counterexample | Move `Calls.cpp:63`'s error from the function to `module.getLoc()` and `calls.mlir` still passes; misspell `@changed` in `tail-calls/positions.mlir:3` and the run exits 1 for "names no function" and passes. |
| Root cause | Expected diagnostics are matched as text in a captured stream, not as diagnostics at locations. |
| Correction | Each negative run becomes `idris-mlir-opt %s [passes] --idr-expect=... -verify-diagnostics -o /dev/null` with `// expected-error @below {{...}}` at the op or function the property names (`@unknown` for a function with no file position); binding-times uses `expected-remark` (`mlir/include/mlir/IR/Diagnostics.h:SourceMgrDiagnosticVerifierHandler`; precedent `mlir/test/IR/test-side-effects.mlir`). Positive properties over pipeline dumps of Idris programs stay S26's table (they hold of every copy of `@f`, which no annotation at one line states). |
| Deletion | The `%status 1` prefix, `2> %t.err`, the FileCheck and count lines of 122 negative runs; about 130 CHECK lines, each replaced by one annotation; the 17 acceptance requests the verifier then answers. |
| Consumers | Tests only: L14 (`tests/idr/expect/**`, `tests/idr/contracts/**`); handoffs to L01 (canon), L08 (tail-calls), L11 (optimize, raise, specialize), L13 (bufferize). |
| Discriminator | The two counterexamples pass today and fail after. |
| Verification here | No C++; the fixtures run on the owner's build; no pipeline output or compile time changes. |
| Size and risk | Low. |
| Insight | An expectation belongs at the op it is about. |
| Owner | L14 |

### mlir-23: `facts-as-marked` is `expected-remark` written as a discardable attribute on the op under test

| Field | Content |
|---|---|
| Evidence | `lib/Transforms/Expect/Facts.cpp:51-67` (`factsAsMarked`) reads `op->getAttrOfType<StringAttr>("expect.facts")` (`:55`), skips unmarked ops (`:56`), and compares the mark with `answers(op, callees)`; 58 marks in 9 files (`tests/idr/effects/**`, `tests/idr/func/**`, `tests/idr/expect/facts.mlir`, `tests/idr/verify/attributes.mlir`); a failing case is built by `sed` rewriting a mark (`effects/queries.mlir:2-4`). |
| Counterexample | An op erased or rebuilt without its discardable attributes before the check carries no mark and the property holds, so a module with no marks passes; and the marks change the IR under test (`OperationEquivalence` compares attribute dictionaries, `mlir/lib/IR/OperationSupport.cpp`), so the `--cse` runs of `effects/div.mlir:2` and `func/call-effects.mlir:2` see ops the test altered. |
| Root cause | The expected answer is stored in the IR under test instead of in the test's text: a fact in a discardable attribute. |
| Correction | A test pass `test-idr-facts`, registered by `idris-mlir-opt` alone (as `test-idr-break-contract` is), emits `op.emitRemark() << "facts: " << answers(op, callees)` for every op in a function body; each op a test asks about gets `// expected-remark @below {{facts: move delay}}`, run with `-verify-diagnostics=only-expected` (`mlir/test/lib/IR/TestSideEffects.cpp` with `mlir/test/IR/test-side-effects.mlir` is upstream's form). |
| Deletion | `factsAsMarked`'s mark read and compare, its row in `Lookup.cpp` and `Expect.h` (one row fewer in S26's table); the 58 marks; the 9 `sed`/`CLEAN:`/count RUN lines; `verify/attributes.mlir`'s two marks. |
| Consumers | L14 (`Expect/**`, `tests/idr/expect/**`); handoffs to L03 (`tests/idr/effects/**`, `tests/idr/func/**`), L15 (`tests/idr/verify/attributes.mlir`), L18 (the registration in `tools/idris-mlir-opt.cpp`). |
| Discriminator | An expectation on an op `--idr-effects` erases: passes today (the mark goes with the op), fails after ("expected remark ... was not produced"); `grep -c expect.facts tests` is 0. |
| Verification here | `make typecheck` compiles the test pass; the fixtures run on the owner's build. |
| Size and risk | About 20 C++ lines; low. |
| Insight | An expectation is test text at a location, not IR. |
| Owner | L14 |
