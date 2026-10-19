<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# ir-verify: representation survey

Area: `foreign/idr/lib/IR/` Verify/, Canon/, Fold/, Func/, Flow.cpp,
FlowEdges.cpp, FlowOps.cpp, Grades.cpp, Effects.cpp, Crashes.cpp,
Dialect.cpp, with their headers (Verify.h, Grades.h, Flow.h, FlowEdges.h,
Canon.h, Fold.h, Func.h, Ownership.h). The files the brief names for neither
surveyor (Ranges.cpp, Regions.cpp, Symbols.cpp, TypeGraph.cpp,
ValueFacts.cpp) were read too, and a finding uses one only where its root
cause starts in this area. Everything below is by reading the tree at HEAD
73d6dcf3 plus the working changes; nothing was built or run.

## The area as it stands

Much of the area is already in good shape. Flow is data: anchors, points
and edges are sum types read with exhaustive visitors, and what a branch
forwards is read from upstream's interfaces. The stage is one property of
`idr.program`. Every refusal carries its rule, and every `idr.*`
discardable attribute is refused. The owned walk knows no op by its kind.
The defects fall into five groups:
- **Transient states the IR admits:** an `idr.func` body of several blocks
  after an inline, and a world whose type says quantity many (the bare
  carrier).
- **Shapes named only at compile time:** the C++ concept `MatchLike` exists
  for templates, but there is no op interface, so 25 `isa<MatchOp,
  MatchLitOp>` pairs stand in for one.
- **Facts written by hand beside their one source:** the guards of
  `Idr_Guarded`, the translation between `Effect` bits and resources, the
  facts of each stage, what the string patterns rewrite, and the type a flow
  anchor holds.
- **Linearity outside the type:** a closure or suspension that captures a
  linear value has a plain type, and a side rule enforces its one use.
- **Two hand-written classifiers of what an op does,** which disagree on
  `idr.force`.

## Findings, ranked (branches removed against risk)

### ir-verify-1: an `idr.func` body may have several blocks, a state only inlining makes

| Field | Content |
|---|---|
| Evidence | `IdrOps.td:147` `AnyRegion:$body`, and the ODS note at `IdrOps.td:214-218` ("several blocks only after the inliner takes in a callee that ends in ub.unreachable, until canonicalize erases the unreachable block"). The cases this costs: `Func/Func.cpp:121-122` (the verifier's "expects a body") and `IdrOps.td:160` (`isExternal`); `Func/Inliner.cpp:30-39` (the multi-block `handleTerminator`, which writes a `cf.br` into an `idr.func`); `Verify/Linearity.cpp:67-71` (a multi-block region "counts every use in it"); `Verify/Owned.cpp:44-60` (walks only the entry block, which is sound only if there is one block); `Canon/MatchPatterns.cpp:91-94,109-117` (the `idr::FuncOp` parent case and the `isUsedOutsideOfBlock` guard of EndAfterNoYield); `lib/Transforms/Inline/Inline.cpp:37-38` (the `hasNItemsOrMore(body, 2)` arm of `fitsRegion`); `Specialize/Raise.cpp:127` (an internal error guarded by `!region.hasOneBlock()`); `Specialize/Consumer.cpp:147`; `Tail/AccumulatorPlan.cpp:167`; `Optimize/PureCalls.cpp:131-145` (a dominance-tree path for multi-block bodies). About 10 branches, plus every `getBody().front()` that assumes one block. |
| Counterexample | After idr-inline takes in `@never() { idr.crash "x"; ub.unreachable }`, the caller's body is two blocks: the inlined code ending in `ub.unreachable`, and an unreachable block holding the rest of the caller. That state survives to the pass boundary and the verifier accepts it. The owned walk checks only the first block, and every pass has to reason about the second. |
| Root cause | The body's one-block shape is not part of `idr.func`. The upstream inliner (as patched by `upstream/07-inline-unreachable-terminator`) inlines a callee ending in `ub.unreachable` as several blocks, and our two inlining sites leave the dead block for a later canonicalize to remove. |
| Correction | `idr.func`'s body becomes `SizedRegion<1>`. The two sites that call `inlineCall` (`inlining::inlineCalls`, `Optimize/Contify.cpp`) erase the unreachable rest right after each inline, with upstream's `eraseUnreachableBlocks`, which `Conversion/TailCalls.cpp:106` already uses. Patch 07 stays as upstream behaviour. |
| Deletion | `FuncOp::verify`'s body check; `isExternal`'s question (it becomes `false`); the multi-block `handleTerminator` (no `idr.return` ends a block of a multi-block callee any more); EndAfterNoYield's `FuncOp` parent case and `isUsedOutsideOfBlock` guard with its comment; Linearity's multi-block note; `fitsRegion`'s two-block arm; the `hasOneBlock` guards in Raise, Consumer and AccumulatorPlan; PureCalls' multi-block dominance path; the ReturnOp ODS note. |
| Consumers | `include/idr/IR/IdrOps.td`; `lib/IR/Func/Func.cpp`, `Func/Inliner.cpp`, `Dialect.cpp`, `Verify/Linearity.cpp`, `Verify/Owned.cpp`, `Canon/MatchPatterns.cpp`; `lib/Transforms/Inline/Inline.cpp`, `Optimize/Contify.cpp`, `Optimize/PureCalls.cpp`, `Specialize/Raise.cpp`, `Specialize/Consumer.cpp`, `Tail/AccumulatorPlan.cpp`. |
| Discriminator | A dialect fixture that runs idr-inline on a caller of a never-returning callee. Before: the output has two blocks and verifies. After: the output has one block, and a hand-written two-block `idr.func` is rejected by the region constraint (`expected-error`). |
| Verification here | `make typecheck` (C++ compiles). The fixture runs only on the owner's build. |
| Size and risk | About 80 lines out, about 10 branches. Low to medium risk: `eraseUnreachableBlocks` on a region whose second block has no predecessor only removes dead code. Essential and kept: `fitsRegion`'s rule for a call inside a single-block region (a match), which upstream's inliner imposes. |
| Insight | 4 (a state no program needs), 8 (the boundary block made unrepresentable) |

### ir-verify-2: the two matches share one shape that no interface names

| Field | Content |
|---|---|
| Evidence | 25 `isa<MatchOp, MatchLitOp>` pairs in 15 files (in this area: `Canon/Feeds.cpp:136,205`, `Canon/CaseOfCase.cpp:46,52`, `Canon/Callees.cpp:30,33`, `Canon/Sink.cpp:64,198,218`, `Canon/MatchPatterns.cpp:109`; elsewhere: `OpsClosures.cpp:65`, `Analysis/Tail.cpp:60`, `Analysis/IdentitiesRecord.cpp:221,317`, `Expect/Placement.cpp:60,170,244,266`, `Expect/Returns.cpp:163`, `Expect/Does.cpp:30`, `Expect/Quantities.cpp:72,131`, `Specialize/Raise.cpp:81`, `Columns/Columns.cpp:45`). `Canon/Rebuild.cpp:56-69`: a `TypeSwitch` over the two, whose `Default` is `report_fatal_error("internal error: a match rebuilt from …")`. `Regions.cpp:51-87`: four RegionBranchOpInterface members written twice, word for word. Templates instantiated once per match: `Canon/Merge.cpp:113-119`, `Canon/Rebuild.cpp:51-54`, `Canon/MatchPatterns.cpp:95-133` (`EndAfterNoYield<Match>`, `populate<Match>`). `IdrMatchOps.td:83` `ParentOneOf<["MatchOp", "MatchLitOp"]>`. The shape is already written down as a compile-time concept, `IdrDialect.h:365-373` `MatchLike`. |
| Counterexample | A third match (for example one on a tag word after lowering) would need an arm at each of the 25 sites. `rebuildMatch(rewriter, someOtherOp, types)` compiles and ends the compiler with an internal error. |
| Root cause | The match shape (a scrutinee, cases, case regions, an optional default, the region a constant takes) exists only as a C++ concept for templates. Code that holds an `Operation *` cannot ask for it. |
| Correction | An op interface `Idr_MatchOpInterface` in `IdrInterfaces.td`, declared by `Idr_MatchOpBase`, with `getScrutinee`, `getNumCases`, `getCaseRegion`, `getDefaultRegion`, `getTakenRegion` and `rebuild(RewriterBase &, TypeRange, ArrayRef<unsigned> keep, Region *fallback)`. The four RegionBranchOpInterface members are written once in `Idr_MatchOpBase`'s `extraClassDefinition` (`$cppClass`). |
| Deletion | The TypeSwitch and its internal error; the template pairs and their explicit instantiations; the duplicate members in `Regions.cpp`; the `MatchLike` concept (the interface replaces it); every pair becomes one `isa<MatchOpInterface>`; `ParentOneOf` becomes `HasParent` on the interface (a one-line native trait). |
| Consumers | `include/idr/IR/IdrInterfaces.td`, `IdrMatchOps.td`, `IdrDialect.h`, `Canon.h`; `lib/IR/Regions.cpp`, `OpsMatch.cpp`, `OpsMatchSyntax.cpp`, `OpsClosures.cpp`, `Canon/{Rebuild,Merge,MatchPatterns,CaseOfCase,Sink,Feeds,Callees}.cpp`; `lib/Analysis/{Tail,IdentitiesRecord}.cpp`; `lib/Transforms/{Expect/Placement,Expect/Returns,Expect/Does,Expect/Quantities,Specialize/Raise,Columns/Columns,Tail/Loop,Tail/Trmc}.cpp`. |
| Discriminator | Mechanical. `make typecheck` proves every former pair site compiles against the interface. The existing match fixtures (merge, case-of-case, sink, end-after-no-yield) must not change on the owner's build. |
| Verification here | `make typecheck`. |
| Size and risk | About 120 lines out, the internal error gone, 25 alternation sites reduced to one alternative each. Low risk (no behaviour change). Essential and kept: the two ops themselves. Tags against literals is a real difference in case keys, which their parsers and verifiers keep. |
| Insight | 7 |

### ir-verify-3: the world's quantity is said three ways, and one of them is quantity many

| Field | Content |
|---|---|
| Evidence | The world is `!idr.q<one, plain, !idr.world_carrier>` (`IdrTypes.td:247-253`, `Grades.cpp:38-40`). `isWorld` accepts the bare carrier as well (`Grades.cpp:46-48`: "graded or stripped"). `Idr_WorldType` (`IdrTypes.td:286-288`) is `CPred<isWorld>` with C++ type `::idr::QType`. A destination is linear by a special case instead (`Grades.cpp:116-119`: `isa<DestType>(type) ? One : …`). The cases this costs: `Grades.cpp:43` (`isLinear` excludes the world), `:88` (`view` excludes it), `:208-209` (`fieldType` returns early on it), `:230` (`isElementType`), `:254` (`isFieldType`); `Types.cpp:226-249` (`isGradedWorld` and the `wholes` spelling table), `:306-312` (QType::verify's world clause); `Transforms/Contracts/Contracts.cpp:208-209` ("the world, a destination" left as they are). About 8 branches, and 19 `isWorld` calls tree-wide that must remember the stripped form. |
| Counterexample | `idr.func @f(%w: !idr.world_carrier) -> (!idr.world_carrier, !idr.world_carrier) { idr.return %w, %w : … }` verifies today. The return's types match, and `verify::linearity` collects only values with `quantityOf == One` (`Linearity.cpp:46`), while the bare carrier is many. The same parameter passes `rootType`'s `isWorld` test (`Verify/Program.cpp:58`), so it is accepted as an IO root's world. In generic form, or from bytecode, `"idr.io.put_str"(%s, %w)` passes `Idr_WorldType`'s predicate, while the generated `getWorld()` casts to `TypedValue<QType>` and asserts. The world is used twice and nothing refuses it. (The custom syntax hides this only because it builds the operand's type from `builderCall`.) |
| Root cause | "Used once by its nature" is a fact of two types, the world and the destination. One of them is forced into the grade wrapper meant for values that entered a linear position, and the other is a special case in `quantityOf`. Stripping the grade off the world (`unrestricted`) leaves a type that is still the world but no longer linear. |
| Correction | `!idr.world` becomes a type of its own with no carrier and no grade. It is linear by its type, as `!idr.dest` is. Both carry one native type trait, `Idr_UsedOnce`, which `gradeOf` and `quantityOf` read. `graded()` leaves a `UsedOnce` type unchanged, the one place that rule lives. QType never wraps the world. |
| Deletion | `isLinear`'s world exclusion; the `unrestricted` inside `isWorld`; `view`'s and `fieldType`'s world cases; `quantityOf`'s DestType special case; QType::verify's world branch; `isGradedWorld` and the `wholes` table; the `world()` builder's wrapper; the bare-carrier type itself; `Idr_WorldType` becomes the type definition. |
| Consumers | `include/idr/IR/IdrTypes.td`, `Grades.h`; `lib/IR/Grades.cpp`, `Types.cpp`, `Asm.cpp`, `Bytecode.cpp`, `IdrBytecode.td` (the world's encoding); `lib/Transforms/Contracts/Contracts.cpp`; `lib/Layout/Components.cpp`, `Conversion/StaticNames.cpp`, `Conversion/StaticData.cpp` (their `isWorld` arms stay correct but read the new type); the generated `compiler/src/IdrisMLIR/{Syntax,Dialect}/Idr.idr` and `MLIR/Bytecode.idr` (regenerated). |
| Discriminator | The fixture above. Before: it verifies. After: `!idr.world_carrier` does not parse, and `%w : !idr.world` used twice is refused ("uses a world that is already used on the same path"). The existing `tests/syntax-grades*.mlir` move to the new spelling. |
| Verification here | `make typecheck`; the regenerated Idris modules build on Chez. |
| Size and risk | About 60 lines out, about 8 branches, one unsound acceptance closed. Medium to high risk: every world the frontend writes changes encoding. Essential and kept: `isFieldType`'s world arm (a world is a field type), and Linearity's two messages (world against linear value). |
| Insight | 4, 5, 12 (the world and the destination become the same case) |

### ir-verify-4: each guard's operand and kind are written again by hand in C++

| Field | Content |
|---|---|
| Evidence | `IdrBase.td:250-259` `Idr_Guarded<operand, kind, cause>`: "no C++ is generated from one". The fact is restated in seven folders (`Fold/Bigs.cpp:77,82,160`, `Fold/Strings.cpp:90,159`, `Ops.cpp:264`, `OpsScalars.cpp:38`) and in five `getSpeculatability` bodies (`OpsScalars.cpp:49,55,59`, `OpsStrings.cpp:76,80`), each naming the operand and the check op again: 12 copies of the ODS mark. `Crashes.cpp:14-25` adds one wrapper per kind (`knownNonZero`, `knownFinite`). |
| Counterexample | A new guarded op whose folder forgets `CheckXOp::holds` folds a division by zero at compile time (APInt aborts), or folds an index that the runtime guard would refuse. Mark `rhs` in ODS and name `lhs` in the folder, and the two disagree silently. |
| Root cause | The guard is data in TableGen that only the Idris generator reads. The C++ side copies it by hand. |
| Correction | `idris-mlir-tblgen` generates from `Idr_Guarded` a native trait per guarded op (`GuardedBy<Kind, operand indices…>`). It provides `getSpeculatability()` (calling `guardedSpeculatability` with the named check) and `guardsHold(ArrayRef<Attribute> operands)`. Every folder of a guarded op begins with `if (!guardsHold(adaptor.getOperands())) return {};`. |
| Deletion | The 12 hand restatements; the `DeclareOpInterfaceMethods<ConditionallySpeculatable>` on those ops; `knownNonZero` and `knownFinite` become `known(CheckKind, Value)`. |
| Consumers | `tools/idris-mlir-tblgen.cpp`; `include/idr/IR/IdrBase.td`, `IdrBigOps.td`, `IdrScalarOps.td`, `IdrStringOps.td`, `IdrArrayOps.td`, `IdrIOOps.td`; `lib/IR/Fold/{Bigs,Strings}.cpp`, `Ops.cpp`, `OpsScalars.cpp`, `OpsStrings.cpp`, `OpsChecks.cpp`, `Crashes.cpp`. |
| Discriminator | A fixture per guard kind in which a guard-failing constant stays unfolded (division by zero, tail of `""`, index out of bounds, a non-finite cast). The property now holds for any op marked guarded, without per-op code. |
| Verification here | `make typecheck` (the generated trait compiles). |
| Size and risk | About 50 lines out, 12 copies. Low risk. Essential and kept: the guard ops and their `holds` (the check's one meaning). |
| Insight | 6, 14 (the TableGen record is the table) |

### ir-verify-5: what each stage implies is written in five places, two of them as a two-bool struct

| Field | Content |
|---|---|
| Evidence | `Verify/Program.cpp:187-212`: `StageFacts { bool closures; bool counted; }` from a switch, with `std::nullopt` for Lowered, read at `:219-221`, `:260-267`, `:282`, `:299`, `:307`, `:311-316`. `Flow.cpp:285-289`: `verifyFlow` reads the stage again, and handles "a function outside a program", which `HasParent<ProgramOp>` (`IdrOps.td:98`) rules out. `Transforms/Narrow/Facts.cpp:31-43`: its own `counted(Stage)` switch, which says Lowered *is* counted where `factsOf` says it has no facts. `Analysis/Identities.cpp:25`: `>= Stage::Owned`. `Transforms/Effects/Effects.cpp:31`: `== Stage::Higher`. |
| Counterexample | `StageFacts{closures = true, counted = true}` can be written and means nothing. A fifth stage needs a new arm in two switches and a check of three comparisons that already disagree in form. |
| Root cause | The stages are a chain the pipeline only moves forward through, so each fact is a threshold on that order. The code holds the facts as per-stage booleans, re-derived wherever a pass asks. |
| Correction | Three predicates, written once beside `Stage` (in `IdrOps.td` `extraClassDeclaration` of `ProgramOp`, or `IdrDialect.h`): `holdsClosures(s) = s < First`, `counts(s) = s >= Owned`, `holdsIdrFunctions(s) = s < Lowered`. Every reader asks these. |
| Deletion | `StageFacts`, `factsOf`, its `optional`; Narrow's `counted` switch; `verifyFlow`'s stage read and its dead `!program` arm (`verify::function` calls it only when `holdsClosures`); the comparisons in Identities and the effects pass. |
| Consumers | `include/idr/IR/IdrOps.td` or `IdrDialect.h`; `lib/IR/Verify/Program.cpp`, `Flow.cpp`; `lib/Transforms/Narrow/Facts.cpp`, `Transforms/Effects/Effects.cpp`; `lib/Analysis/Identities.cpp`. |
| Discriminator | A type check, not a test: no reader holds a stage boolean of its own. The existing stage fixtures (`tests/reduce-regions/*stage*`) must not change. |
| Verification here | `make typecheck`. |
| Size and risk | About 40 lines out, 2 switches, 1 dead branch, 1 invalid combination. Low risk. Essential and kept: Lowered as a stage (decided in the representation wave, D3 and §11). |
| Insight | 4, 11 (the order is the coordinate) |

### ir-verify-6: the translation between `Effect` bits and MLIR's resources, and the rule for what a call may do, are written several times

| Field | Content |
|---|---|
| Evidence | Bits to resources: `Func/Call.cpp:61-68` (`CallOp::getEffects`: four hand-written instances), `OpsClosures.cpp:214-219` (`ForceOp::getEffects`: three), `IdrDialect.h:155-170` (`MayCrash`: crash means a write of Crash and of IO). Resources to bits: `Effects.cpp:102-114` (`bitOf`). What a call may do: `Effects.cpp:116-131` (`calleeEffect`, used by `ownEffects`' `erase_if`, `:147-152`); `Verify/Program.cpp:76-95` (`effectsCovered`: a call is its callee's effects, an apply or force everything); `Analysis/Effects.cpp:35-62` (`bodyOf`/`sumOf`: calls only). Three copies of the call rule, four of the bit↔resource table. |
| Counterexample | The copies already disagree. A crash writes the IO resource (`MayCrash`, `IdrDialect.h:167-168`), but `bitOf` maps every IO effect to the `io` bit, so `ownEffects` of a call to a function whose effects are `crash` alone erases the IO write (`Effects.cpp:149-151`) that an inline `idr.crash` keeps. Today that is harmless only because every asker treats a crash write as "something". Adding a bit, for allocation say, means an edit in four places. |
| Root cause | The `Effect` bitset (what a function may do) and MLIR's resource effects (what an op declares) are two vocabularies for one fact, with no table between them. |
| Correction | One constexpr table in `IdrDialect.h`, each row a bit with the resource effects it means (io: read and write IO; crash: write Crash and IO; diverge: write Divergence), and `effectInstances(Effect)`. `CallOp::getEffects` is `effectInstances(anyEffect)`, `ForceOp`'s is `effectInstances(crash | diverge)`, `MayCrash`'s is `effectInstances(crash)`, `bitOf` is the table read backwards, and `ownEffects` of a known call is `effectInstances(callee)` plus what the call consumes. One `idr::effectOfCall(Operation *, const SymbolTable &)` serves `effectsCovered` and the solver. |
| Deletion | The hand lists in Call.cpp, OpsClosures.cpp and `MayCrash`; `bitOf`'s ladder; `ownEffects`' `erase_if`; `effectsCovered`'s inline call rule. |
| Consumers | `include/idr/IR/IdrDialect.h`; `lib/IR/Func/Call.cpp`, `Effects.cpp`, `OpsClosures.cpp`, `Verify/Program.cpp`; `lib/Analysis/Effects.cpp`. |
| Discriminator | A googletest box (`foreign/idr/unittests`) that round-trips every bit set through `effectInstances` and `bitOf`. The effects fixtures must not change. |
| Verification here | `make typecheck`. The box runs on the owner's build (it links MLIR). |
| Size and risk | About 40 lines out, about 10 hand-kept rows. Low risk. Essential and kept: `bodyEffect` as the one own-part rule (0002 §4.3). |
| Insight | 14, one fact one place |

### ir-verify-7: a closure or suspension that captures a linear value has a plain type, so a side rule enforces its one use

| Field | Content |
|---|---|
| Evidence | `Grades.h:129-138` and `Grades.cpp:183-205` (`holdsLinear`, `takenOnce`). They are read by `OpsClosures.cpp:111-116` (ClosureOp::verify), `:157-162` (SuspendOp::verify), `OpsScalars.cpp:111-121` (LinUseOp::fold's guard) and `Canon/Feeds.cpp:179-184` (a special case of the profit rule). `IdrClosureOps.td:91-97`: `idr.apply` casts its callee's type to `FnType`, so a closure entered into a linear type must be `lin.use`d back to plain before it is applied. |
| Counterexample | An `idr.closure` whose capture is `!idr.lin<!idr.str>` has a plain `!idr.fn<…>` type, so the linearity verifier does not count its uses. Its one-use rule lives in two op verifiers, a folder guard and a canonicalization exception, so each new rewrite that duplicates a value must remember it. |
| Root cause | Quantity 1 is a type (AGENTS.md), but the quantity a closure gets from its captures is not written into its type. The frontend knows it: Idris binds such a lambda at quantity 1. |
| Correction | `idr.closure` and `idr.suspend` give their result at quantity one exactly when some capture is (`!idr.lin<!idr.fn<…>>`), which their verifiers hold as a type rule. `idr.apply`'s callee and `idr.force`'s suspension constraints read the carrier (`unrestricted`). `verify::linearity` then checks the one use like any other. |
| Deletion | `holdsLinear`, `takenOnce`, the two verifier rules, LinUseOp::fold's guard, and Feeds' closure exception. |
| Consumers | `include/idr/IR/IdrClosureOps.td`, `Grades.h`; `lib/IR/Grades.cpp`, `OpsClosures.cpp`, `OpsScalars.cpp`, `Canon/Feeds.cpp`; `lib/Transforms/Defunctionalize/**` (a linear closure becomes a linear sum); `compiler/src/IdrisMLIR/Emit/Closures.idr` (writes the closure's quantity). |
| Discriminator | A fixture that uses a closure capturing a linear value twice. Before: ClosureOp::verify refuses it with its own message. After: `verify::linearity` refuses it, and a closure typed plain with a linear capture is refused by the closure's type rule. Exactly once is checked in one place. |
| Verification here | `make typecheck`; the frontend's emission builds on Chez. |
| Size and risk | About 50 lines out, 6 branches. Medium to high risk: closure types through defunctionalization and Emit. Essential and kept: the rule that a world is never captured (separate and type-level). |
| Insight | 6, AGENTS.md's quantity rule |

### ir-verify-8: `holdsClosure` is computed for every type and never read, while the verifier finds labels by its own type walk

| Field | Content |
|---|---|
| Evidence | `IdrInterfaces.td:45` `holdsClosure` is implemented by 13 types (`ValueFacts.cpp`: 11 member definitions plus the two templates) and solved as `Held::Closure` in `DataType::facts()`. No file outside ValueFacts.cpp reads it (`grep holdsClosure`). Meanwhile `Verify/Program.cpp:40-49` (`namesLabels`, an `AttrTypeWalker` over every value's type), `:222-229` (results and every value) and `:282-291` (a three-level loop over each data type's fields) compute "names a closure or a suspension" afresh. |
| Counterexample | The two facts already differ: `LazyType::holdsClosure()` is false (`ValueFacts.cpp:118`), while `namesLabels` counts a suspension as a label. A future reader of `holdsClosure` checking "no label past higher" would wrongly pass a suspension. |
| Root cause | The label fact ("a closure or a suspension anywhere a value reaches") was put into the type interface without the suspension half, so the verifier kept its own walk. One fact, computed twice, one copy dead. |
| Correction | ValueFacts' `holdsClosure` becomes `holdsLabels` (`Held::Labels`; `FnType` and `LazyType` answer true, a data type through its body as now). The stage rule asks `holdsLabels` of each value's type. |
| Deletion | `namesLabels`; the data-body loop in `verify::program` (each declared data type is reached from some value or signature, which the value rule then catches); the dead `holdsClosure`. |
| Consumers | `include/idr/IR/IdrInterfaces.td`, `IdrDialect.h` (`Held`), `Grades.h`; `lib/IR/ValueFacts.cpp`, `Verify/Program.cpp`. |
| Discriminator | Fixtures past higher holding a suspension in a data field and in a block argument. Both refused before and after, now through one predicate. |
| Verification here | `make typecheck`. |
| Size and risk | About 35 lines out, one walker and one loop. Low risk. |
| Insight | one fact one place, 6 |

### ir-verify-9: two classifiers of "what an op does", with one walk written twice and a force rule in only one

| Field | Content |
|---|---|
| Evidence | `Effects.cpp:156-207`: `enum class Does { Nothing, IO, Something }`, `does()`, and `anyDoes()` (a pre-order walk: unknown effects are the top, RecursiveMemoryEffects goes in, anything else is skipped). `Canon/MoveOut.cpp:56-98`: `enum class Does { Computes, Effects, Touches }` and `doesOf()` with the same walk again, plus `isa<ForceOp>(op)` as Touches (`:86`), a rule no other asker applies. |
| Counterexample | A change to how ub.unreachable or a recursive-effects op counts must be made in both walks. `onlyAllocates` and `performsIO` read a force by its declared effects, while MoveOut treats it as touching every array. Two answers to "may a force read this array". |
| Root cause | The lattice (computes < has effects < touches what the asker cares about) and its walk are written per asker. Only the "touches" predicate differs. |
| Correction | One `idr::classify(Operation *, const CalleeEffects *, function_ref<bool(const EffectInstance &, Operation *)> touches) -> Does` in `Effects.cpp`, owning the walk. `onlyAllocates` asks it with nothing touched, `performsIO` with an IO read, and MoveOut with "a read of IO, a read or write of this array type, or a force". The force rule stays MoveOut's, written as its predicate. |
| Deletion | MoveOut's `Does` enum and `doesOf` walk; Effects.cpp's `does`/`anyDoes` pair becomes the one classifier. |
| Consumers | `include/idr/IR/Flow.h`; `lib/IR/Effects.cpp`, `Canon/MoveOut.cpp` (and the CalleePatterns that call `onlyAllocates`). |
| Discriminator | The move-out and sink fixtures must not change on the owner's build. A googletest box can drive `classify` over a scratch block. |
| Verification here | `make typecheck`. |
| Size and risk | About 40 lines out, one duplicated walk. Low to medium risk. Essential and kept: the two askers' different "touches". |
| Insight | 7, 14 |

### ir-verify-10: `idr.str.show` is two ops in one, and its consumers split it back

| Field | Content |
|---|---|
| Evidence | `IdrStringOps.td:87-95`: `UnitAttr:$is_signed, AnyTypeOf<[Idr_Int, F64]>:$value`, the only op taking either. `OpsStrings.cpp:51-55`: the verifier refuses `is_signed` on a Double. `Canon/Canonicalize.td:12-15`: `Idr_IsInteger` and `Idr_IsDouble` exist only to split six patterns by operand type (`:31-35,54-58,66-71`). `Fold/Strings.cpp:54-66`: a two-arm `dyn_cast` ladder. `tools/idris-mlir-tblgen.cpp` (around 2150-2240, 2359): the runtime ABI's per-operand-kind variants, whose Double kind only this op uses (`Abi<StrShowOp>::doubleFunction`). |
| Counterexample | `idr.str.show signed %d : f64` is a state the op admits and its verifier refuses. Every consumer must test which half it holds. |
| Root cause | Two operations (the text of an integer, which has a signedness, and the text of a Double, which has none) share one op. Their consumers (`put_int`/`put_double`, `int_head`/`double_head`) are already separate. |
| Correction | `idr.str.show_int` (`is_signed`, `Idr_Int`) and `idr.str.show_double` (`F64`), each with its own `Idr_Runtime` symbol. |
| Deletion | `StrShowOp::verify`; the two DRR constraints and their clauses; the fold ladder; the Double variant of the ABI generator's multi-kind operands (Signed and Unsigned stay). |
| Consumers | `include/idr/IR/IdrStringOps.td`; `lib/IR/OpsStrings.cpp`, `Canon/Canonicalize.td`, `Canon/Feeds.cpp:193`, `Crashes.cpp:43`, `Fold/Strings.cpp`; `tools/idris-mlir-tblgen.cpp`; `runtime/` (symbol names, if they change); the generated Idris dialect and `compiler/src/IdrisMLIR/Emit/Operations.idr` / `Registry` (which op a show of a Double emits). |
| Discriminator | `idr.str.show_double signed` does not parse. The output-fusion and head fixtures must not change. |
| Verification here | `make typecheck`; the regenerated Idris builds on Chez; the runtime builds with host clang. |
| Size and risk | About 30 lines out, 1 invalid state, 7 type-split clauses. Low risk. |
| Insight | 4, 16 (two genuinely different things, separated) |

### ir-verify-11: `ownership::readFrom` re-derives from an isa ladder what the flow edges already declare

| Field | Content |
|---|---|
| Evidence | `Verify/Uses.cpp:56-72`: `FieldOp` gives its value, a `ViewLikeOpInterface` view its source, a `memref.load` of a counted element its buffer, a match's case argument its scrutinee. The flow edges declare the same reads: `FlowOps.cpp:110-114` (`FieldOp`: a part of the value, read, flows to the result), `:130-142` (`MatchOp`: a part of the scrutinee flows to each case argument), `:269-273` (`tensor.extract`). `memref.load` has no flow model. 15 files call `readFrom`, `viewRoot` or `isStatic`. |
| Counterexample | A new projecting op (for example a field read of a record column) declares its flow edge, and the owned walk still treats its result as made from nothing ("makes a value that holds references, which neither holds one of its own nor is read from a value that does") until someone adds an arm here. |
| Root cause | The decision of the representation wave (D7, "one account of how a value moves") was not carried into `readFrom`. It keeps its own list of projections. |
| Correction | `readFrom(v)` is the `of` value of the flow edge into `v` whose `from` is a `Part` of a `Whole` (read, not taken), from `flowEdgesOf` of `v`'s defining op or its region's owner. `memref.load` gets an external flow model (a part of the buffer's elements flows to the result), as `tensor.extract` has. `ViewLikeOpInterface` stays (upstream's). |
| Deletion | The `FieldOp`, `MatchOp` and `memref::LoadOp` arms. |
| Consumers | `lib/IR/Verify/Uses.cpp`, `FlowOps.cpp` (the memref.load model); readers whose answers must not change: `lib/Analysis/Ownership/{Borrows,Reuses,Values}.cpp`, `lib/Transforms/Ownership/{Classes,Placement,Reshape,Share}.cpp`, `lib/Transforms/Narrow/Facts.cpp`, `lib/Conversion/{Runtime,StaticData}.cpp`, `lib/Transforms/Expect/ResetsUnshared.cpp`. |
| Discriminator | A googletest box: for each op with a Part→Whole read edge, `readFrom(result)` is the edge's source. The owned-stage fixtures must not change. |
| Verification here | `make typecheck`. |
| Size and risk | About 15 lines out, 3 arms. Medium risk: every ownership reader leans on `readFrom`, and the new memref.load model is seen by Escapes and Exclusivity too. |
| Insight | 7, one fact one place |

### ir-verify-12: the owned stage's crossings into upstream's buffer ops are protocols of position and use count

| Field | Content |
|---|---|
| Evidence | `Verify/OwnedOps.cpp:94-106`: a counted element loaded by an upstream op must have one use, "the idr.dup right after it" (`op.getNextNode()`). `:36-39`, `:190-214`, `:233-243`: a fresh allocation's or an `idr.own.give`'s reference rides a plain value (`carry`) until an `idr.own.adopt` or a store takes it (`takesCarried`, `storedBy`). `Verify.h:159-161`: a `transit` set for "a reference their plain type cannot say". `OpsOwnership.cpp:120-139`: the adopt and give verifiers check the same pairs from the other side. |
| Counterexample | Any pass that puts an op between a `memref.load` and its `idr.dup` (a debug counter, a cast) makes the owned verifier refuse correct code. A reference in transit is a third kind of value the walk must test for at every use (`carried` appears in 7 functions). |
| Root cause | Upstream's memref ops take plain types, so each place a counted reference enters or leaves memory is split into an upstream op plus an op of ours. Their pairing is held by position and use count, not by an op. |
| Correction | idr-rc writes the three crossings as ops of ours: `idr.own.load` (load a counted element with a reference of its own), `idr.own.store` (store an owned element, which takes its reference) and `idr.own.alloc` (an owned buffer at once). Each lowers to the upstream op and the count operation, before upstream's memref lowering. |
| Deletion | `loaded()`'s adjacency rule; `carry`, `carried`, `transit`, `takesCarried`, `storedBy` and `make`'s allocation arm; `OwnAdoptOp`, `OwnGiveOp` and their verifiers. |
| Consumers | `include/idr/IR/IdrOwnershipOps.td`, `Verify.h`; `lib/IR/Verify/{Owned,OwnedOps}.cpp`, `OpsOwnership.cpp`, `FlowOps.cpp`; `lib/Transforms/Ownership/**` (idr-rc's placement and reshape, which today insert dup, adopt and give); `lib/Conversion/**` (lowering of the three ops). |
| Discriminator | Before: a fixture with an unrelated pure op between a counted load and its dup is refused. After: it cannot be written, and the owned fixtures over buffers verify. |
| Verification here | `make typecheck`. |
| Size and risk | About 90 lines out, one value role and 3 position rules. Medium to high risk: the bufferization handoff and idr-rc. Essential and kept: that upstream types hold no grade (`view` of a builtin buffer is plain, `upstreamHolds`). Only the pairing by position goes. |
| Insight | 4, 6 |

### ir-verify-13: `rebuildMatch` takes the kept cases and their regions as parallel lists, with the default as one extra entry

| Field | Content |
|---|---|
| Evidence | `Canon.h:119-132`: `rebuildMatch(rewriter, op, types, ArrayRef<unsigned> cases, ArrayRef<Region *> regions)`, "the default last if there is one". Every caller builds the regions as the case regions of `cases` plus the fallback: `Canon/MatchPatterns.cpp:71-78` (with an `index < getCases().size()` test), `Canon/Merge.cpp:90-104`, `Canon/Rebuild.cpp:59-63`. The same coordinate ("region i < cases.size() is case i, one more is the default", `IdrMatchOps.td:16,31-33`) makes `Canon/Eta.cpp:31-33,45-46` and `Canon/MatchPatterns.cpp:146-148` test `region >= getCases().size()` before reading a tag. |
| Counterexample | `rebuildMatch(…, cases = {0, 2}, regions = {&r2, &r0})` builds a match whose case 0 runs region 2. `regions.size() == cases.size() + 2` builds a match with two defaults. Both are accepted until the verifier sees the result. |
| Root cause | The case regions follow from the kept cases, so passing them is a second copy. The default is encoded as a position past the end. |
| Correction | Rebuilding takes `(ArrayRef<unsigned> keep, Region *fallback)` (the interface method of ir-verify-2). Reading a region's case goes through one accessor, `std::optional<Tag> MatchOp::tagOf(Region &)`, empty for the default. |
| Deletion | The parallel `regions` vectors in three callers; the `index < cases.size()` arithmetic; the bounds tests in Eta and `readField`. |
| Consumers | `include/idr/IR/Canon.h`, `IdrMatchOps.td`; `lib/IR/Canon/{Rebuild,Merge,MatchPatterns,Eta}.cpp`; `lib/Transforms/Tail/{Loop,Trmc}.cpp`. |
| Discriminator | Type-level: the mismatched call no longer exists. The merge and drop-case fixtures must not change. |
| Verification here | `make typecheck`. |
| Size and risk | About 25 lines out, 5 branches. Low risk. Essential and kept: the default region as its own case (it binds the scrutinee, not fields). |
| Insight | 11, parallel lists |

### ir-verify-14: flow anchors hold an `mlir::Type` where they always mean a particular type, and the slot rule is written twice

| Field | Content |
|---|---|
| Evidence | `FlowEdges.h:85-129`: `Field::data`, `Forced::lazy`, `Hole::dest` and `Capture::carrier` are each an `mlir::Type`. Readers cast them: `FlowEdges.cpp:43-62` (`cast<DataType>`, `dyn_cast<LazyType>`, `cast<DestType>`) and `Transforms/Defunctionalize/Keys.cpp:99-117` (`cast<DataType>`, `cast<LazyType>`). `Forced` holds a `LazyType` before idr-defunctionalize and a memo `DataType` after (`FlowOps.cpp:35` against `:176`), so `slotOf` has to test which. `Keys.cpp`'s `anchorKey` repeats `slotOf`'s five-arm visitor (the type held at an anchor), differing only at Hole and in where it strips grades. |
| Counterexample | `FlowAnchor::fieldOf(StrType, …)` compiles and crashes the label solve's `cast`. A sixth anchor needs a new arm in both copies of the slot rule. |
| Root cause | The anchors' fields are wider than what they hold. The two meanings of `Forced` share one field, and the slot rule lives in an anonymous namespace, so Defunctionalize wrote its own. |
| Correction | Typed fields: `Field{DataType, Tag, unsigned}`, `Forced{LazyType}`, a separate `MemoState{DataType}` for a memo sum's state, `Hole{DestType}`, `Capture{Type}`. One public `FlowAnchor::slot()` gives the type held at an anchor; `anchorKey` calls it. |
| Deletion | The 5 casts; `slotOf`'s `dyn_cast` on Forced; Keys.cpp's duplicate visitor. |
| Consumers | `include/idr/IR/FlowEdges.h`; `lib/IR/FlowEdges.cpp`, `FlowOps.cpp`; `lib/Analysis/{Labels,LabelSites}.cpp`; `lib/Transforms/Defunctionalize/Keys.cpp`. |
| Discriminator | Type-level: an anchor built with the wrong kind of type does not compile. The label fixtures must not change. |
| Verification here | `make typecheck`. |
| Size and risk | About 30 lines out, 6 casts or arms. Low risk. |
| Insight | 6, one fact one place |

### ir-verify-15: a function's effects have two spellings of "everything", which a verifier rule and a writer keep apart

| Field | Content |
|---|---|
| Evidence | `IdrOps.td:126-131,145`: `DefaultValuedOptionalAttr<Idr_EffectAttr, "::idr::anyEffect">`. `Func/Func.cpp:116-127`: the verifier refuses the attribute written at its default. `Analysis/Effects.cpp:67-76` (`setEntry`) removes it when the value is everything and sets it otherwise. `Verify/Program.cpp:79-80` skips a function without it. `Specialize/Specialization.cpp:35` and `Specialize/Raise.cpp:135` call `removeEffectsAttr`. |
| Counterexample | `idr.func @f() attributes {effects = #idr.effects<io, crash, diverge>}` is a state the attribute admits, refused only by a rule that exists to keep two spellings of one value from both appearing. |
| Root cause | Absence and a full set both mean "everything". |
| Correction | `effects` becomes a property with a default, `DefaultValuedProp<EnumProp<Idr_Effect>, "::idr::anyEffect">`, which always holds a value. The custom printer elides the default. |
| Deletion | The verifier rule; `setEntry`'s two-way branch (a plain `setEffects`); the skip in `effectsCovered`; the `removeEffectsAttr` calls. |
| Consumers | `include/idr/IR/IdrOps.td`; `lib/IR/Func/Func.cpp`, `Verify/Program.cpp`, `Bytecode.cpp` if properties need an encoding; `lib/Analysis/Effects.cpp`; `lib/Transforms/Specialize/{Specialization,Raise}.cpp`; the generated `compiler/src/IdrisMLIR/Dialect/Idr.idr` (`attrIf "effects"`). |
| Discriminator | The doubly-spelled function above no longer parses as two forms. Round-trip (`--verify-roundtrip`) of a function at the default prints no `effects`. |
| Verification here | `make typecheck`; the regenerated Idris builds on Chez. |
| Size and risk | About 15 lines out, 3 branches. Low risk (watch the bytecode of properties: upstream/25's reader bug concerns unregistered properties). |
| Insight | 4, 8 |

### ir-verify-16: the string patterns' left-hand sides are copied into three hand lists

| Field | Content |
|---|---|
| Evidence | `Canon/Canonicalize.td:22-71`: seven output-fusion patterns and six head patterns, three of which exist only to look through `idr.check.nonempty` (`HeadOfChecked*`). Their left-hand sides are copied by hand: `OpsStrings.cpp:100-105` (`writtenInPieces`: append, cons, from_char, show, and pack/concat with one use), `Canon/Feeds.cpp:193-196` (append, cons, from_char, show, through the guard), `Crashes.cpp:43` (cons, from_char, show, big.show; append walked). `lib/Transforms/Expect/Output.cpp:27` (the `output-fused` property) uses `writtenInPieces` as its oracle. |
| Counterexample | The copies already drift: Feeds treats a head of an append as a profit, but no head pattern exists for append; `knownNonEmpty` knows `big.show` and Feeds does not. Add a builder (for example `str.from_codepoints`) and four places need an edit, one of which is the test's own oracle. |
| Root cause | A DRR pattern cannot be asked whether it applies, so each fact about a builder (written in pieces, has a readable first character, is non-empty) is restated wherever a predicate needs it. |
| Correction | An op interface on the string builders, `Idr_StrBuilderOpInterface`, declared by `Idr_StrBuilderOp` (and by `big.show`), with `nonEmpty()`, `writePieces(OpBuilder &, Value world) -> FailureOr<Value>` and `firstChar(OpBuilder &) -> FailureOr<Value>`. Two C++ patterns (`put_str` of a builder; `str.head` of a builder, looking through the guard once) replace the thirteen DRR patterns. `writtenInPieces`, `knownNonEmpty` and Feeds ask the interface. |
| Deletion | The 13 DRR patterns and their two constraints; the three hand lists; the three checked twins. |
| Consumers | `include/idr/IR/IdrInterfaces.td`, `IdrStringOps.td`, `IdrBigOps.td`; `lib/IR/Canon/{Canonicalize.td,Output.cpp,Feeds.cpp}`, `Crashes.cpp`, `OpsStrings.cpp`, `OpsBigs.cpp`; `lib/Transforms/Expect/Output.cpp`. |
| Discriminator | The output-fusion and head fixtures must not change. A new builder implementing the interface is fused and guard-folded with no other edit. |
| Verification here | `make typecheck`. |
| Size and risk | About 60 lines out, 3 lists. Medium risk: it trades declarative DRR for an interface plus two C++ patterns, which the owner may weigh against "upstream first" (both are upstream mechanisms). |
| Insight | 7, 14 |

### ir-verify-17: case-of-case's profit rule is a ladder over consumer kinds that restates each consumer's canonicalization

| Field | Content |
|---|---|
| Evidence | `Canon/Feeds.cpp:171-213`, `feeds()`: arms for call, linear closure, `PutStrOp`, string builders under `StrHeadOp` or the guard, `PutListOp`, `ForceOp`, `MatchOp`/`MatchLitOp`/`FieldOp`/`TagOp`, `CallOp`, a box `ConOp`, then a fold probe (`foldsWith`, `:80-113`, which runs `op->fold` and restores operands and properties). About 12 arms, each a copy of some op's pattern. |
| Counterexample | Give `idr.tag` a new canonicalization against a known box, and case-of-case does not move a consumer to meet it until Feeds learns of it. The rule and the profit drift. |
| Root cause | Whether an op canonicalizes against a known operand is a fact of that op, kept in a central switch away from the op's own patterns. |
| Correction | An op interface `Idr_MeetsOpInterface::meets(OpOperand &use, Value value)`, implemented beside each consumer's canonicalizations. Ops without it get the fold probe as the default. |
| Deletion | The ladder in `feeds()`; it becomes the interface query, the call-raise test and the default. |
| Consumers | `include/idr/IR/IdrInterfaces.td`, the ODS of the consumers named above; `lib/IR/Canon/Feeds.cpp`, `OpsMatch.cpp`, `Ops.cpp`, `OpsClosures.cpp`, `OpsStrings.cpp`, `OpsCon.cpp`. |
| Discriminator | Case-of-case and sink fixtures must not change. Each op's `meets` is tested next to its pattern. |
| Verification here | `make typecheck`. |
| Size and risk | Few branches deleted (they move to the ops), but drift goes. Medium risk (a heuristic whose firing changes code size). Ranked low for that reason. |
| Insight | 7 |

### ir-verify-18: the owned walk's view of a value is three overlapping predicates over three maps

| Field | Content |
|---|---|
| Evidence | `Verify/Owned.cpp:63-121` and `Verify.h:108-166`: `tracked` (owned and not static), `carried` (in `transit`), `isView` (counts, not owned, not static, not carried) and `alive`. They are kept in `held`, `transit` and `owners`, plus a `counted` cache. `ownership::isStatic` (`Verify/Uses.cpp:48-54`) walks a definition chain on every call, and `tracked`/`isView` are called at nearly every use (regrade 7 times, operands 3, `enter` 2, `ownersAcross` 2). |
| Counterexample | The predicates are disjoint only through their definitions' order (`isView` excludes `carried`, `tracked` excludes static). A reorder of the tests in `regrade` changes meaning, and nothing states which roles exist. |
| Root cause | A value's role in the walk (untracked, owned, in transit, a view of some owners) is a sum, computed again at each question. |
| Correction | `enum class Role { Untracked, Owned, Carried, View }`, decided once per value at its definition and memoized. The state is one `DenseMap<Value, Slot>` with `Slot = std::variant<Held{int}, Viewing{SmallVector<Value>}>`. (If ir-verify-12 lands, `Carried` goes too.) |
| Deletion | `transit`; the predicate chains (`switch (role)` at each site); the repeated `isStatic` walks. |
| Consumers | `include/idr/IR/Verify.h`; `lib/IR/Verify/{Owned,OwnedOps,OwnedRegions}.cpp`. |
| Discriminator | The owned fixtures (`tests/idr/ownership/**`, `tests/reduce-regions/owned*`) must not change. |
| Verification here | `make typecheck`. |
| Size and risk | About 30 lines out; few branches deleted (each role's arm is essential). Low to medium risk. Value is clarity and cost. |
| Insight | 4 |

### ir-verify-19: knot reporting keeps three parallel lists matched by position

| Field | Content |
|---|---|
| Evidence | `Verify/Knots.cpp:71-103`: `knotted`, `where` and `named`, plus `knotOf` mapping a type to `(knot index, member)`, zipped at `:103`. |
| Counterexample | An edit that pushes onto one list in a loop that skips a knot misaligns the other two. `zip_equal` asserts only in debug. |
| Root cause | One knot's facts (its members, the array named, where it is reported) are spread over three vectors. |
| Correction | `struct Knot { SmallVector<unsigned> members; unsigned named; std::optional<Location> at; }`, with `knotOf` mapping to a `Knot *`. |
| Deletion | The three vectors and the pair-valued map. |
| Consumers | `lib/IR/Verify/Knots.cpp`. |
| Discriminator | `tests/reject/*cycle*` messages must not change. |
| Verification here | `make typecheck`. |
| Size and risk | About 10 lines; trivial risk. |
| Insight | parallel lists |

## Judged essential, and kept

- **Linearity (at most once on the worst path) and the owned walk (exactly
  once, at owned) are two rules,** not one. They share
  `verify::alternatives`, which reads `RegionBranchOpInterface`.
- **Linearity's constant exemption** (`Linearity.cpp:145-152`): a constant
  has no identity, and MLIR's folder materializes, merges and hoists it
  however the program was written.
- **The fold-time guards that check quantity one and one use**
  (`OpsCon.cpp:230,268,290`, `OpsClosures.cpp:231`, `Eta.cpp:22,29`,
  `LinEnterOp::fold`): the cost of linear types on an SSA IR whose folder
  does not know them. Each rewrite forwards a different value. A shared
  helper would save little, and ir-verify-7 removes the closure case.
- **The boundary with upstream's types:** `view()` keeps a builtin buffer
  plain, and `upstreamHolds`/`plainReference` exempt values an upstream op
  fixes. Upstream's types hold no grade. Only the pairing by position goes
  (ir-verify-12).
- **`CalleePattern::kLabel`** (0002 §9 lists it among the strings owed):
  debug labels are upstream's own way to select patterns in a set
  (`FrozenRewritePatternSet`'s enable and disable filters), and MLIR gives a
  `RewritePattern` no other run-time identity. It is one constant read in
  one place.
- **The nullable `const CalleeEffects *`:** `ownsParameter` has two
  genuinely different sources (the callee's signature during placement, the
  operand's grade otherwise), and `getEffects` can never receive a table. A
  null object would only move the branch.
- **Lowered as a stage inside `idr.program`,** with `lookupRoot` null after
  lowering: decided (representation wave D3 and §11).
- **ValueFacts' interface of separate methods:** decided (D8). Only the
  dead, half-stated `holdsClosure` is a finding (ir-verify-8).
- **`effectsCovered` as a verifier of the solver's output:** decided (0002
  F02, §4.3).
- **`reuses()`' search for the `idr.take` behind each token:** it needs the
  target's layouts, which exist only at program level, so a token type
  carrying a size would move the check, not delete it.
- **`ProgramOp::verifyRegions`' root check beside `verify::program`'s:**
  they run at different moments (a pass manager verifying the program, and
  module symbol-use verification).
- **`FlowPoint::Part` holding a `Taken` or `Whole`:** the label solve
  treats a part by its anchor and a whole value by its value, so the two
  arms are different cases. Flattening `value()`/`taken()` would be
  cosmetic.
- **`FlowEdges::add` dropping edges that carry nothing:** a null object
  that already removes a category of checks.
- **TypeGraph's numbering, data types first and arrays after**
  (`isArray(at) = at >= dataTypes.size()`): a half-open split that works.
- **The match's default region:** it binds the scrutinee, not fields, so it
  is a case of its own. Only its encoding as "one past the cases" goes
  (ir-verify-13).
- **`Verify/Attributes.cpp` refusing every `idr.*` discardable attribute**,
  and **`ResultCarriesOperand::verifyTrait`**: these are the right
  representation already.
