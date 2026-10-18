<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# ir-ods: the dialect's declarative representation

Area: every `.td` and `.h` under `foreign/idr/include/idr/IR/` (ops, types,
attributes, enums, interfaces, traits, and the IR headers Grades.h, Layout.h,
Symbols.h, FlowEdges.h, Flow.h, Canon.h, Fold.h, Verify.h), with the C++ in
`lib/IR`, `lib/Conversion`, `lib/Transforms` and `tools/idris-mlir-tblgen.cpp`
read only to count what each representation costs. Nothing here was built or
run; every count is source observation at HEAD (73d6dcf3 plus the working
tree).

## The area as it stands

The earlier waves did most of the large work: constructors are tags with
roles (D1), the program and its stage are an op (D3), movement is one flow
interface whose anchors, points and edges are C++ sums (D7, FlowEdges.h),
what a value holds is one type interface (D8), the runtime ABI, guards, rules
and big-to-word table are generated from ODS marks (D9, D10, D19), and a data
type's body is checked once, when it is set (D16). What remains is mostly
the next layer down. Two op kinds that share an ODS base class but no
interface are told apart by hand at 24 sites. ODS marks that are already
data (the guard marks) are restated by hand in C++. The world is held as a
grade of a carrier, so every grade function has to exclude it again. A trait
and an interface admit values no op ever uses (a crash cause that is never
absent, an `allocates` flag that is never set, operand groups nothing reads).
About twenty verifier checks state type constraints that ODS can declare. The
layout's components and their counted bits are two parallel walks over the
same types. A constructor carries a label's fields whatever its role. Every
constant attribute carries a type that is always `NoneType` once stored.

## Findings, ranked (branches removed against risk)

### ir-ods-1: no interface for the two match ops

| Field | Content |
|---|---|
| ID | ir-ods-1 |
| Evidence | `IdrMatchOps.td:16-39` (`Idr_MatchOpBase`, a shared ODS class with no interface); `IdrDialect.h:364-373` (`MatchLike`, a C++ concept standing in for one). `isa<MatchOp, MatchLitOp>` and its variants appear at 24 lines in 15 files: `Analysis/Tail.cpp:60`, `Analysis/IdentitiesRecord.cpp:221,317`, `IR/OpsClosures.cpp:65`, `IR/Canon/Sink.cpp:64,198,218`, `IR/Canon/CaseOfCase.cpp:46,52`, `IR/Canon/Feeds.cpp:136,205`, `IR/Canon/MatchPatterns.cpp:109`, `IR/Canon/Callees.cpp:30,33`, `Transforms/Specialize/Raise.cpp:81`, `Transforms/Expect/Does.cpp:30`, `Expect/Placement.cpp:60,170,244,266`, `Expect/Returns.cpp:163`, `Expect/Quantities.cpp:72,131`. A hand dispatch `scrutineeOf` (`Expect/Placement.cpp:47-51`, 2 arms). `canon::rebuildMatch(Operation*)` (`IR/Canon/Rebuild.cpp:56-71`) is a TypeSwitch whose `Default` is an internal error. Template pairs: `rebuildMatch<MatchOp>`/`<MatchLitOp>` and `addMerge<…>` explicit instantiations (`Canon.h:143-150`, `Rebuild.cpp:52-55`, `Merge.cpp:118-119`), and three `MatchLike` templates (`OpsMatch.cpp:39,56`, `OpsMatchSyntax.cpp:83`). About 26 branches and 1 internal error. |
| Counterexample | A third op that branches on a scrutinee (or a pass that asks "is this a match?") has to be added to 24 lists. `rebuildMatch(rewriter, op, types)` accepts any `Operation*`, so a caller that passes a non-match compiles and fails at run time with an internal error. |
| Root cause | "Is a multi-way branch on a scrutinee whose regions are alternatives" is a property the two ops share and every pass asks about. It is written as a closed list of class names, not as an op interface. |
| Correction | `Idr_MatchOpInterface` in `IdrInterfaces.td`, attached by `Idr_MatchOpBase`, with the methods the passes use: `getScrutinee`, `getNumCases`, `getCaseRegion(i)`, `getDefaultRegion`, `getTakenRegion(Attribute)`, and `rebuild(RewriterBase&, TypeRange, ArrayRef<unsigned> cases, ArrayRef<Region*>)`. The bodies are the members `matchClassDeclaration` already holds. Passes ask `isa<MatchOpInterface>` and call the methods. |
| Deletion | The `MatchLike` concept; `rebuildMatch(Operation*)` with its internal-error default; `scrutineeOf`; the explicit template-instantiation pairs, since the functions become non-template over the interface (`addMerge` stays registered per op name); 24 class lists become one interface test. |
| Consumers | `IdrInterfaces.td`, `IdrMatchOps.td`, `IdrDialect.h`, `Canon.h`, `lib/IR/{OpsMatch,OpsMatchSyntax,OpsClosures}.cpp`, `lib/IR/Canon/{Rebuild,Merge,Sink,CaseOfCase,Feeds,MatchPatterns,Callees}.cpp`, `lib/Analysis/{Tail,IdentitiesRecord}.cpp`, `lib/Transforms/Specialize/Raise.cpp`, `lib/Transforms/Expect/{Does,Placement,Returns,Quantities}.cpp`. These stay as they are: `Columns.cpp:45` (a conversion target's list of legal op names) and `YieldOp`'s `ParentOneOf`, which names its parents in ODS. |
| Discriminator | Behaviour is preserved, so the existing canon fixtures for case-of-case, sink, merge and rebuild, on both `idr.match` and `idr.match_lit`, pass unchanged. Before, `rebuildMatch` given a non-match reaches `report_fatal_error`; after, there is no overload that takes an arbitrary `Operation*`, so that call does not compile. A spec grep for `MatchOp, MatchLitOp` outside the two kept lists comes back empty. |
| Verification here | `make typecheck` (ODS through TableGen, every unit compiled). No pass runs. |
| Size and risk | Removes about 30 lines and 26 branches. Low risk: mechanical, behaviour-preserving. One essential split stays: IdentitiesRecord's `KnownTag` vs `KnownLiteral` arms (`:270-284`), because a tag and a literal are different keys. |
| Insight | 7 |

### ir-ods-2: the guard marks are restated by hand in C++

| Field | Content |
|---|---|
| ID | ir-ods-2 |
| Evidence | `IdrBase.td:254-259`: `Idr_Guarded<string operand, string kind, string cause>` says which guard op checks which operands of a partial op. idris-mlir-tblgen parses it into the Idris `guardsOf` (`tools/idris-mlir-tblgen.cpp:1052-1180`), and "no C++ is generated from one". The C++ side then names the same guard and operands by hand. Five `getSpeculatability` bodies: `OpsScalars.cpp:48-60` (ToInt, Div, Mod), `OpsStrings.cpp:75-81` (StrIndex, StrHead). Seven folder preconditions: `OpsScalars.cpp:38`, `Ops.cpp:264` (div/mod), `Fold/Bigs.cpp:77,82,160`, `Fold/Strings.cpp:90,159`. `knownNonZero` and `knownFinite` (`Crashes.cpp:16-25`) repeat the guard's own `holds` on the same constants that `foldCheck` already receives from the fold adaptor (`OpsChecks.cpp:107,121`). The kind is a string twice over: `Idr_CheckOp` finds its `CheckKind` case with `!filter` on the symbol (`IdrCheckOps.td:74-76`), and the generator looks the mark's kind up by name, with an error for a misspelling (`tblgen:1055-1060`). About 14 restatements and 2 string lookups. |
| Counterexample | A new pure partial op whose author forgets the hand precondition folds past its guard, for example dividing by a constant zero in APInt, which aborts the compiler. A partial op whose hand `getSpeculatability` names the wrong guard class or the wrong operands is hoisted above the check that makes it safe. Nothing compares the hand C++ with the ODS mark. |
| Root cause | The guard relation (op, guard op, operands in the guard's order) is held once as an ODS mark for Idris and again as C++ code for MLIR. The kind is a string where it should be an enum case record. |
| Correction | `idris-mlir-tblgen -gen-guards` writes `IdrGuards.inc` from the same marks. For each partial op whose guard reads only the op's own operands, it writes a specialization `idr::Guarded<Op>` naming the guard op class and the op's operands in the guard's order, both as values and as FoldAdaptor constants. `IdrDialect.h` defines two generic functions over it, `guardHolds(adaptor)` and `guardedSpeculatability(op)`, which every partial op's folder and `getSpeculatability` call. `CheckKind`'s cases become named defs, as `Idr_Megamorphic` is, and both `Idr_Guarded` and `Idr_CheckOp` take the case record, as `Idr_RuleCase` takes its category. |
| Deletion | The guard naming in five `getSpeculatability` bodies; seven hand `CheckXOp::holds({…})` preconditions; `knownNonZero` and `knownFinite`, together with the `known` argument they feed (keep `knownNonEmpty`, which adds the built-with-a-character fact); the `GuardOp` concept and its template overload (`IdrDialect.h:319-330`); the `!filter` in `Idr_CheckOp`; the generator's name lookup and its "no case of CheckKind" error. |
| Consumers | `IdrBase.td`, `IdrCheckOps.td`, `IdrScalarOps.td`, `IdrStringOps.td`, `IdrBigOps.td`, `IdrIOOps.td`, `IdrArrayOps.td`, `IdrDialect.h`, `include/idr/IR/CMakeLists.txt` (one more tablegen output), `tools/idris-mlir-tblgen.cpp`, `lib/IR/{OpsScalars,OpsStrings,Ops,OpsChecks,Crashes}.cpp`, `lib/IR/Fold/{Bigs,Strings}.cpp`. The generated Idris `guardsOf` is unchanged. |
| Discriminator | A googletest box in `foreign/idr/unittests`, enumerated from the generated table: for every guarded pure op, build it on constants where the guard fails and check that `fold` gives nothing and the op is not speculatable, and on constants where the guard holds check the reverse. A new guarded op is covered with no new test. Before, an op without its hand precondition is not covered and can fold past its guard. |
| Verification here | `make typecheck` builds idris-mlir-tblgen and compiles the units. `typecheck-dialects` shows the Idris output is byte-identical. The box does not run here, because it links MLIR. |
| Size and risk | About 60 generator lines added and about 50 hand lines removed; about 14 restatements and 2 string lookups go. Low to medium risk (generator work). The IO buffer guards, whose counts are computed (`WordSize`, `BytesOf`), stay Idris-only, as they are now: they neither fold nor speculate. |
| Insight | 6, 14 |

### ir-ods-3: the world is a grade of a carrier, so every grade function excludes it

| Field | Content |
|---|---|
| ID | ir-ods-3 |
| Evidence | `IdrTypes.td:247-253,286-290`: the world is `!idr.q<one, plain, !idr.world_carrier>`, and `Idr_WorldType` is a CPred over `QType`. Because the world's grade is a constant, each function over grades excludes it again. `Grades.cpp:43` (`isLinear … && !isWorld`), `:48` (`isWorld` must look through `unrestricted`), `:88` (`view`'s `!isWorld`), `:208` (`fieldType`'s early return: "the world stays the world"). `Types.cpp:228-240,255-257,276-280`: `isGradedWorld`, a `Whole` struct and a one-entry `wholes` table, each walked by a loop in the parser and in the printer. `Types.cpp:306-308`: QType::verify's world arm. A destination is "used once by its type" too, by a different mechanism: `quantityOf`'s `isa<DestType>` (`Grades.cpp:118`). So `isLinear` and `quantityOf` disagree on both the world and the destination, each by an exception. The frontend already says the fact: "the world, which is linear by its own type and held as itself" (`Emit/Monad.idr:74-80`). It then wraps the world in a grade at `Emit/Index.idr:47`. About 9 exception arms and a spelling table. |
| Counterexample | `!idr.q<many, own, !idr.world_carrier>` and `!idr.q<one, borrow, !idr.world_carrier>` are representable, and only QType::verify's world arm refuses them. A new grade function (`atQuantity`, `owned`, a future `times`) that forgets the exclusion grades the world. `fieldType` without its early return would make a world field of a used-many scrutinee "many". |
| Root cause | "Used exactly once by its type alone" is a fact of two types, the world and the destination. It is encoded once as a fixed grade on a carrier and once as a hard-coded branch, rather than as one fact of the type. |
| Correction | `!idr.world` becomes a TypeDef of its own (`Idr_WorldType`, mnemonic `world`). "Every value is used exactly once, by its type" becomes one method of `ValueFactsTypeInterface`, true for the world and for `!idr.dest`. `quantityOf` reads it. `graded` never grades such a type, and QType::verify refuses a grade of one, which is a single rule shared with the destination. |
| Deletion | `Idr_WorldCarrier`, the CPred `Idr_WorldType` and its `builderCall`; `idr::world()`; `isGradedWorld`, `Whole`, `wholes` and its two loops; QType::verify's world arm, replaced by the shared rule; the `!isWorld` in `isLinear` and in `view`; `fieldType`'s world return; `quantityOf`'s `isa<DestType>`; `isWorld`'s `unrestricted`. On the Idris side, the `QType One Plain` wrapper at `Emit/Index.idr:47` and the generated mnemonic `world_carrier`. |
| Consumers | `IdrTypes.td`, `IdrInterfaces.td`, `Grades.h`, `lib/IR/{Grades,Types,ValueFacts}.cpp`, `tests/idr/syntax/grades{,-invalid}.mlir` (the two `world_carrier` lines), `compiler/src/IdrisMLIR/Emit/Index.idr`, and the regenerated `Syntax/Idr.idr` and `SyntaxSamples.idr`. The bytecode needs no edit: a parameterless type is written as its text. The printed form `!idr.world` is unchanged. |
| Discriminator | In `grades-invalid.mlir`, `!idr.lin<!idr.world>`, `!idr.q<many, own, !idr.world>` and `!idr.lin<!idr.dest<!T>>` are each refused by the one rule. A unit property over the dialect's types: `quantityOf(T) == One` exactly when T is used once by its type or graded one, with no per-type case. Today the property holds only because of two separate exceptions. |
| Verification here | `make typecheck`, `typecheck-dialects`, and the frontend built on Chez (Emit). No pass runs. |
| Size and risk | Net about 7 branches and 1 table removed. Medium risk: the world's C++ type changes from `QType` to `WorldType` in every generated accessor. Essential cases that stay: `isFieldType`'s world arm (a world may be a field but is no memref element), `isElementType`'s, `Layout/Components.cpp`'s and `Conversion/Static*.cpp`'s (a world has no runtime form), the root-type check, and the frontend's `linear One WorldT = False`, which is its own statement of the same rule. |
| Insight | 4, 12 |

### ir-ods-4: MayCrash admits a crash that cannot happen and an allocation no op makes

| Field | Content |
|---|---|
| ID | ir-ods-4 |
| Evidence | `IdrInterfaces.td:85-102`: `getCrashCause` returns `std::optional<StringRef>`, "or nothing when the op cannot crash". All four implementers always return a cause (`Crashes.cpp:53`, `IdrCheckOps.td:36-38,88`, `OpsArrays.cpp:260`). Readers test for its absence anyway: `IdrDialect.h:166,172` (MayCrash's effects and speculatability), `Func/Func.cpp:142` (`mayCrash && mayCrash.getCrashCause()`), `StructureLoops/Forms.cpp:47` (`.has_value()`), `Conversion/Bigs.cpp:56` (a dereference). `Idr_MayCrash<bit allocates>` is never instantiated with 1, so `if constexpr (Allocates)` and `Allocates ||` (`IdrDialect.h:162-173`) are dead. In all, 5 tests of an absence that never occurs and 2 dead arms, in a 30-line hand C++ trait. |
| Counterexample | An op could declare the interface and return no cause. It would then report no crash effect while still being "an op that may end the program", a state with no meaning. |
| Root cause | A null in the interface's return type (Hoare), and a parameter for a case nobody has. Both force a hand-written C++ trait where ODS's own declarative effects would do. |
| Correction | `getCrashCause` returns `StringRef`: an op that cannot crash does not hold the interface. `Idr_MayCrash` becomes ODS's `MemoryEffects<[MemWrite<Idr_CrashResource>, MemWrite<Idr_IOResource>]>` plus the interface. It declares no `ConditionallySpeculatable`, which MLIR already reads as not speculatable. |
| Deletion | `MayCrash<bool>::Impl` (`IdrDialect.h:151-183`); `Idr_MayCrashTrait`; the `std::optional` in four implementers; the presence tests in `Func.cpp:142` (which becomes `isa<MayCrashOpInterface>`), `Forms.cpp:47` and `Conversion/Bigs.cpp:56`. |
| Consumers | `IdrInterfaces.td`, `IdrDialect.h`, `IdrCheckOps.td`, `lib/IR/{Crashes,OpsArrays}.cpp`, `lib/IR/Func/Func.cpp`, `lib/Transforms/StructureLoops/Forms.cpp`, `lib/Conversion/Bigs.cpp`. |
| Discriminator | Each of `idr.check.*`, `idr.crash`, `idr.crash_str` and `idr.nat.to_extent` reports a write on `idr.crash` and `idr.io` and is not speculatable: one idr-expect or unit property over every op holding the interface. The existing effects fixtures pass unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | About 40 lines and 7 branches removed. Very low risk. |
| Insight | 5 |

### ir-ods-5: about twenty verifier checks are type constraints ODS can declare

| Field | Content |
|---|---|
| ID | ir-ods-5 |
| Evidence | `OpsPlatform.cpp:33-66`: `verifyBuffer`, an i8 buffer, written as 7 hand verifiers (8 checks) on ops whose operand ODS already types as `Idr_Rank1ArrayValue`. `OpsStrings.cpp:25-48`: `verifyList`, base's list of a given element, as 3 verifiers. `OpsClosures.cpp:95,110,156`: "captures a world", 3 times. `OpsClosures.cpp:97-99,202-207,246-253`: Delay, Force and MemoSettle each compare the carrier by hand, where `idr.apply` states the same relation with `TypesMatchWith` (`IdrClosureOps.td:92-97`). `Types.cpp:321-325`: DestType's parameter is `mlir::Type`, and a verifier requires a `BoxType`; the bytecode then needs a `getChecked` builder (`IdrBytecode.td:46-47`), and `FlowEdges.cpp:59` unwraps a grade that cannot be there. `Attrs.cpp:24-29`: InstanceAttr's arguments are an `ArrayAttr` that a verifier requires to be all strings, while the generated Idris `InstanceAttr` takes `List at` (`Syntax/Idr.idr:536`). `OpsBigs.cpp:149-153`: a signed `big.from_int` to a natural. `OpsStrings.cpp:50-54`: `str.show` with `is_signed` on a Double. `OpsOwnership.cpp:40`: `DropOp::verify() { return success(); }`, because `Idr_OwnedOp` sets `hasVerifier` for its whole class (`IdrOwnershipOps.td:55-57`). |
| Counterexample | `idr.str.show` of a Double with `is_signed` is representable. So is a destination of an `i64`. The Idris side can build an `InstanceAttr` with an integer argument that the C++ side refuses. Each buffer op can be handed a buffer of i64. |
| Root cause | Operand, parameter and attribute types are declared wider than they are, and the narrowing is done in hand verifiers, which validate rather than declare. The wide types then reach the generated Idris types too. |
| Correction | Declare each constraint in ODS. `Idr_ByteBuffer` (an `Idr_Rank1ArrayValue` of i8) on the seven buffer operands. `Idr_BaseListOf<[…]>` (a box of a `list`-kind data type over one of the elements) on pack, concat and put_list. `Idr_Capture` (any type but the world) on the captures of closure, suspend and delay. `TypesMatchWith<…, "::idr::sameCarriers">`-style relations on force, delay and memo.settle. DestType's parameter typed `"::idr::BoxType"`. InstanceAttr's arguments as `ArrayRefParameter<"::mlir::StringAttr">`, so the generated Idris constructor takes `List String`. BigFromInt's rule as a `PredOpTrait`. `idr.str.show` split into the integer op with `is_signed` and `idr.str.show_double`, as `put_int` and `put_double` already are, with the same runtime functions (`_s`, `_u`, `_f64`). `Idr_OwnedOp` stops setting `hasVerifier`. |
| Deletion | `verifyBuffer` and its 7 verifiers; `verifyList` and its 3; the 3 world-capture checks; the carrier checks of Force, Delay and MemoSettle; `DestType::verify`, its `genVerifyDecl` and the bytecode `cBuilder`; `InstanceAttr::verify`; `BigFromIntOp::verify`; `StrShowOp::verify`; `DropOp::verify`. Each drops its `hasVerifier = 1` too, about 16 in all. |
| Consumers | `IdrIOOps.td`, `IdrStringOps.td`, `IdrClosureOps.td`, `IdrTypes.td`, `IdrAttrs.td`, `IdrBigOps.td`, `IdrOwnershipOps.td`, `IdrBytecode.td`, `lib/IR/{OpsPlatform,OpsStrings,OpsClosures,Types,Attrs,OpsBigs,OpsOwnership,FlowEdges}.cpp`; `Conversion` for `str.show_double`; the frontend's emitter of `str.show` for Doubles; `tests/idr/verify` messages. idris-mlir-tblgen's `dialectWord` must learn the new constraint names unless ir-ods-11 lands first. |
| Discriminator | Each invalid form above is still refused, now by ODS's constraint message. These are verify fixtures, one per form. On the Idris side, an `InstanceAttr` with a non-string argument no longer type-checks under `typecheck-dialects`. |
| Verification here | `make typecheck` and `typecheck-dialects`. The frontend is built on Chez. |
| Size and risk | About 120 lines and about 20 checks removed. Low risk. The checks that read structure (a closure's linear capture used once, OwnAdopt's `memref.alloc` of one use) stay: they relate ops, not types. |
| Insight | 6 |

### ir-ods-6: a value's components and their counted bits are two parallel walks

| Field | Content |
|---|---|
| ID | ir-ods-6 |
| Evidence | `Layout.h:216-219,269-274`: `components(type)` and `counted(type)` are two lists matched by position, each its own walk. `Layout/Components.cpp:128-172`: `componentsOf` and `countedOf` both branch on world, data, shaped and the rest. `countedOf` must mirror the tag that `SumLayout::types()` puts first (`if (layout.tag) all.push_back(false)`). `Layout.h:141-158`: `SumLayout` keeps `slots` and `counted` as parallel vectors. Consumers zip the two calls back together: `Components.cpp:50`, `Conversion/Cells.cpp:162`; and `Elements.cpp:57,80`, `Arrays.cpp:134,181` and `Counting.cpp:33,49,157` call `counted()` beside a `components()` made elsewhere. That is 3 duplicated arms, 1 mirror and 2 parallel vectors. |
| Counterexample | A value kind added to `componentsOf` but not to `countedOf`, or a sum's tag placed differently in the two, is caught only by `zip_equal`'s assertion, on the program that reaches it. |
| Root cause | A component and whether it is counted are one fact, held as two lists. |
| Correction | `struct Component { mlir::Type type; bool counted; }`. `Layouts::components(Type)` returns `SmallVector<Component>` from one walk. `SumLayout` holds `SmallVector<Component> slots`, and its optional tag becomes a leading component, not counted, built in one place. The runtime's `inc` and `dec` take the components. |
| Deletion | `countedOf` and `Layouts::counted`; `SumLayout::counted`; the tag mirror; both `zip_equal`s of two calls. |
| Consumers | `Layout.h`, `lib/IR/Layout/{Components,Layouts}.cpp`, `lib/Conversion/{Cells,Counting,Elements,Arrays,Words,Facts,Lower,RuntimeCalls,Buffers,StaticData}.cpp`, the runtime-call helpers' `inc`/`dec` signatures. |
| Discriminator | Unit box: for each type of a generated family of data types, `components(t).size()` equals the arity the lowering's type converter gives, and every counted component is a pointer or an i64. After the change the two cannot be written apart. |
| Verification here | `make typecheck`. The box does not run here. |
| Size and risk | About 40 lines and 4 duplicated branches removed. Low risk. The sum's optional tag stays: a sum of fewer than two constructors has no tag word, and LLVM has no `i0`. |
| Insight | 4, 6 |

### ir-ods-7: every constructor carries a label's fields

| Field | Content |
|---|---|
| ID | ir-ods-7 |
| Evidence | `IdrDialect.h:270-277`: `Ctor { name; fields; bool byName; CtorRole role; FlatSymbolRefAttr fn; }`. `fn` is valid only when the role is `Label`, and `byName` only for a memo sum's label. That is checked at `DataBody.cpp:74-80` and tested again by readers: `Types.cpp:163,176` (walkLabels and replaceLabels), `DataRemap.cpp:180,249,316`, `Conversion/Facts.cpp:71` (`role == Label ? fn : null`), `Expect/ByName.cpp:42` (`role != Label \|\| !fn`), `DataBody.cpp:127-130` (print). The same flat record is generated into Idris (`Syntax/Idr.idr:440-445`, `tblgen:1603-1624`) and written in the module's bytecode table (`IdrBytecode.td:58`, `Bytecode.cpp:190-197`, `MLIR/Bytecode.idr:462`). Yet the frontend only ever writes `False … Nothing` (`Emit/Index.idr:74`, "none is a label, which only defunctionalization makes"). About 10 branches, and two fields copied to Idris and to the bytecode as constants. |
| Counterexample | A plain constructor naming a function, or a closure-sum label `by_name`, is representable in C++, in Idris and in the bytecode; only `setBody` refuses it. |
| Root cause | The label's function and its by-name flag are a payload of one role, held as independent fields of every constructor. |
| Correction | The role is a sum whose label case holds the payload: `Ctor { StringAttr name; ArrayRef<Type> fields; Role role; }`, where `Role` is a `std::variant<Plain, ListNil, ListCons, Label, Running, Forced>` with `Label { FlatSymbolRefAttr fn; bool byName; }`. It is taken apart with `std::visit`, as FlowEdges' sums are. `CtorRole kindOf(Role)` stays the enum that the KindRule table, the printer and the bytecode name. The bytecode table, which only the frontend writes and which never holds a label, drops `b byName, a? fn`. The generated `IdrCtor` drops `byName` and `fn`, and the reader refuses a label role in the table. |
| Deletion | `DataBody.cpp:74-76` (fn exactly when label); the `fn` null tests in walkLabels, replaceLabels, DataRemap (3) and the printer; ByName.cpp's double test; Facts.cpp's conditional; the bytecode's per-constructor bool and optional attribute, on both sides; `Emit/Index.idr`'s constants. |
| Consumers | `IdrDialect.h`, `IdrTypes.td`, `IdrBytecode.td`, `lib/IR/{DataBody,Types,DataRemap,Bytecode}.cpp`, `lib/Conversion/Facts.cpp`, `lib/Transforms/Defunctionalize/{Declare,Forces,Converter,Patterns}.cpp`, `lib/Transforms/Expect/{ByName,Closures}.cpp`, `lib/Transforms/Specialize/Specialize.cpp`, `lib/Transforms/Tail/Trmc.cpp`, `lib/Transforms/Contracts/Contracts.cpp`, `tools/idris-mlir-tblgen.cpp`, `compiler/src/IdrisMLIR/{Emit/Index,MLIR/Bytecode,SyntaxSamples}.idr` (whose closure and memo samples move to text). |
| Discriminator | `!idr.data<"T", plain [@C() by_name]>` becomes a parse error, with no grammar for it, rather than a verifier error. Frontend bytecode samples round-trip with the shorter record. A table entry with role `label` is refused at read. |
| Verification here | `make typecheck`, `typecheck-dialects`, and the frontend on Chez. |
| Size and risk | About 10 branches removed. Medium risk: the bytecode layout changes on both sides in one step. What stays: KindRule's roles per kind (D1's per-constructor role), the clause "by name only in a memo sum", and Forces.cpp's unreachable arms for non-memo roles (`:86-88`), which are the cost of D1's flat roles. |
| Insight | 4, 5 |

### ir-ods-8: every constant attribute carries a type that is always NoneType when stored

| Field | Content |
|---|---|
| ID | ir-ods-8 |
| Evidence | `IdrAttrs.td:41-49`: `Idr_Attr` adds `TypedAttrInterface` and an `AttributeSelfTypeParameter`, "only because MLIR's parser reads the `: T` after an attribute into the attribute". `Constants.cpp:24-38`: `untyped` rebuilds every kind without it, in a TypeSwitch of 4 cases plus a run branch. `Constants.cpp:144`: `isBuildableWith`'s `untyped(value) != value`. `Constants.cpp:164-172`: the TypedAttr cast and the alias branch in `ConstantOp::parse`. `ConAttr.cpp:136,143,166,203,205,279`: `NoneType::get` in every builder, and a type branch in `getChecked`. The upstream parser does this for builtin strings too (`"a" : !idr.str` parses into a typed `StringAttr`). About 8 branches, and a parameter whose stored value is always the same. |
| Counterexample | `#idr.big<5> : i64` held in an op unstripped (a pass that builds an attribute through `getChecked` with a type) is a different attribute from the stored form. `isBuildableWith` exists to refuse it. |
| Root cause | The constant's syntax puts its type after the value, where the attribute parser consumes it, so the type is carried through the attribute and stripped afterwards. |
| Correction | `idr.constant` writes its type first, `idr.constant !idr.big #idr.big<5>`, as `idr.con` writes `!T @C(…)`. No attribute of ours carries a type: `Idr_Attr` drops the interface and the parameter. |
| Deletion | `untyped`; the check in `isBuildableWith`; the alias branch and cast in `ConstantOp::parse`; the type branch of `ConAttr::getChecked` and the type parameter of `getStoredChecked`; the `NoneType::get` arguments; BigAttr::verify's unused type. |
| Consumers | `IdrAttrs.td`, `lib/IR/{Constants,ConAttr,Attrs}.cpp`, and about 300 fixture lines in 72+ files under `tests/idr` (200 `idr.constant #…`, 98 `idr.constant "…"`). The Idris side prints the generic form and is unaffected. |
| Discriminator | `--verify-roundtrip` over every fixture. No attribute of the dialect has a type parameter, a property of the generated attribute classes. |
| Verification here | `make typecheck`. The fixtures are only rewritten here, not run. |
| Size and risk | About 40 lines and 8 branches removed. Medium risk: a mechanical rewrite of fixtures. |
| Insight | 11, 12 |

### ir-ods-9: a match's default region is known by counting

| Field | Content |
|---|---|
| ID | ir-ods-9 |
| Evidence | `IdrMatchOps.td:15,23,31-33`: one `VariadicRegion`, where the default is "one more region" than the cases. `OpsMatch.cpp:83-84,146`: verifiers check the count (cases or cases+1; cases+1). Region index arithmetic decides case versus default at `OpsMatch.cpp:64`, `Canon/MatchPatterns.cpp:75`, `Canon/Eta.cpp:46` and `Tail/WhileDo.cpp:171`. `Canon.h:119-126`: `rebuildMatch` takes "the default last if there is one". That is 4 coordinate tests, 2 count checks and 1 positional convention. |
| Counterexample | An `idr.match` with cases.size()+2 regions is representable, and only the verifier refuses it. A rebuild that passes regions in another order silently makes a case the default. |
| Root cause | The default region has no name, only a position derived from the case count. |
| Correction | scf.index_switch's layout: a named `$defaultRegion` and a `VariadicRegion<SizedRegion<1>>:$caseRegions`, where case i is caseRegions[i]. For idr.match the default is an `AnyRegion`, empty when the cases are exhaustive, as scf.if's else region is; for idr.match_lit it is a `SizedRegion<1>`, which is required. |
| Deletion | `getDefaultRegion`'s size comparison; both count checks; the 4 `index < getCases().size()` tests; the "default last" convention of `rebuildMatch`. |
| Consumers | `IdrMatchOps.td`, `lib/IR/{OpsMatch,OpsMatchSyntax}.cpp`, `lib/IR/Canon/{MatchPatterns,Eta,Merge,Rebuild}.cpp`, `lib/Transforms/Tail/WhileDo.cpp`, `lib/Conversion/Matches.cpp`, every `MatchOp::build` caller (Defunctionalize, Ownership), and the frontend's match emitter, which then writes the default in its own place. |
| Discriminator | A match written with two defaults is a parse error. The canon fixtures pass unchanged. |
| Verification here | `make typecheck`, and the frontend on Chez. |
| Size and risk | About 7 branches removed. Medium risk: the syntax and every builder change. What stays: the default's two shapes (it binds nothing, or binds the scrutinee back, which idr-rc's placement uses), and the empty or null default of an exhaustive match. Best done together with ir-ods-1, whose interface hides the layout. |
| Insight | 11 |

### ir-ods-10: ConsumesOnly's operand groups are a copy nothing reads

| Field | Content |
|---|---|
| ID | ir-ods-10 |
| Evidence | `IdrInterfaces.td:191-197`: `Idr_ConsumesOnly<string groups>`, written `<"0">` at all 7 uses. `IdrDialect.h:188-198`: `ConsumesOperands<unsigned... Groups>` never reads `Groups`. "What it takes over is its flow's … `groups` … say nothing more." No reader in `lib/` or in `tools/` reads it. |
| Counterexample | `Idr_ConsumesOnly<"1">` on an op whose flow consumes operand 0 compiles and means nothing, a second statement of consumption that can disagree with the flow. |
| Root cause | A parameter kept after the flow interface became the one account of consumption (D7). |
| Correction | `Idr_ConsumesOnly` takes no parameter: a NativeOpTrait `ConsumesOperands`. |
| Deletion | The parameter at 7 uses, and the variadic template. |
| Consumers | `IdrInterfaces.td`, `IdrDialect.h`, `IdrOps.td`, `IdrMatchOps.td`, `IdrClosureOps.td`, `IdrBigOps.td`, `IdrOwnershipOps.td`. |
| Discriminator | None needed: the change is behaviour-free and the generated code is identical. |
| Verification here | `make typecheck`. |
| Size and risk | One dead copy removed; no branches. No risk. |
| Insight | 6 |

### ir-ods-11 (crosses into the generator): the runtime ABI word of a type constraint is held by its name in the generator

| Field | Content |
|---|---|
| ID | ir-ods-11 |
| Evidence | `tools/idris-mlir-tblgen.cpp:954-967`: `dialectWord`, a 15-entry table from ODS constraint record names (`"Idr_StrRead"`, `"Idr_BigOrNatValue"`, `"Idr_Rank1ArrayValue"`, …) to C words. The guards' `LengthOf`/`BytesOf` read it (`:1093-1097`), and so does the ABI (`:2160`). The generator also recognises the attributes `"is_signed"` and `"predicate"` by name (`:2212-2216`). |
| Counterexample | A new read constraint, say ir-ods-5's `Idr_ByteBuffer`, or a renamed one, falls out of the table, and the generator fails with "which no C function takes" until someone edits a second file. |
| Root cause | The ABI word is a fact of each ODS constraint, held as a string table in the tool. |
| Correction | Each constraint the runtime ABI passes carries its word as a TableGen field (`class Idr_AbiWord<string word> { string abiWord = word; }`, mixed into `Idr_StrRead`, `Idr_StrValue`, `Idr_BigValue`, `Idr_WorldType`, `Idr_Rank1ArrayValue`, …), and the generator reads that field. |
| Deletion | The `dialectWord` table, and its name comparisons. |
| Consumers | `IdrTypes.td`, `IdrOps.td`, `IdrBigOps.td`, and `tools/idris-mlir-tblgen.cpp` (the generator lane). |
| Discriminator | `IdrRuntimeAbi.inc` and `idris_rt_ops.h` regenerate byte-identical. A constraint without the field that an op passes to the runtime is a TableGen error at its own record. |
| Verification here | `make typecheck`: tblgen is built and its outputs diffed. |
| Size and risk | About 20 lines removed. Low risk. |
| Insight | 6, 14 |

### ir-ods-12 (crosses into specialization and the generator): the specializer's in-memory keys are dialect attributes exported to Idris

| Field | Content |
|---|---|
| ID | ir-ods-12 |
| Evidence | `IdrAttrs.td:228-264`: `KeyHole`, `KeyCon`, `SpecKey` and `KeyRaise`. No op holds one (`git grep` finds them only in `lib/Transforms/Specialize` and in the generated or sample Idris). Yet the generator writes four Idris constructors, mnemonics and printers for them (`Syntax/Idr.idr:538-578`), and `SyntaxSamples.idr:130-142` exercises them. `KeyRaise`'s `consumer` is the whole printed consumer function, kept as a `StringAttr` (`Specialize/Consumer.cpp:128`). |
| Counterexample | The Idris side can build a `KeyRaiseAttr` that no Idris program has a use for, a second copy of a C++-only concept. |
| Root cause | They are attributes for uniquing and hashing, and the generator exports every AttrDef. |
| Correction | `Idr_KeyAttr` carries `bit idris = 0`, which the generator reads, so no Idris syntax is written for the keys. |
| Deletion | The four generated constructors and their samples. |
| Consumers | `IdrAttrs.td`, `tools/idris-mlir-tblgen.cpp`, `compiler/src/IdrisMLIR/SyntaxSamples.idr`, and `tests/compiler/dialect-syntax/expected`, which is stale anyway: it still names `#idr.clone`, `#idr.key_apply` and `#idr.key_closure`, which no longer exist. |
| Discriminator | `typecheck-dialects` output loses the four constructors. The syntax round trip still covers every attribute the IR can hold. |
| Verification here | `make typecheck-dialects`, and `syntax-samples` built on Chez. |
| Size and risk | Removes generated Idris only. Low risk. Holding the consumer as its digest rather than its text is the specialization lane's to weigh: it saves memory and removes no branch. |
| Insight | 6 |

## Judged essential, and kept

- **The permission's meaning by stage.** Plain means "nothing to say" before
  idr-rc. After it, our counted types are borrow, own or excl, and builtin
  buffers stay plain, because upstream's ops take no grade. The stage
  verifier is the boundary.
- **A tensor's grade.** A tensor is one or many, and always plain, because
  bufferization owns its memory.
- **idr.take's token.** It exists exactly when there is a cell (a box with
  fields), so a take of an unboxed sum or of an atom has none.
- **Box versus in-place in idr.con, idr.field and idr.tag.** Boxing is the
  value's type (D11): a cell and slots are two runtime forms.
- **idr.con's holes and destinations by position.** Decided in D15.
- **#idr.con's plain and run forms.** One value in two canonical shapes, a
  compression with canonicity by construction (M7).
- **SumLayout's optional tag, Cell::group and Element::boxed.** No tag word
  below two constructors; the other two are lifted limits (D4).
- **Stage::Lowered and lookupRoot's null.** A lowered program holds
  upstream's functions. StageFacts is already a table with no default.
- **FuncOp::isRoot's null checks.** An op not yet inserted into a program.
- **no_inline.** It records where a function came from (an Idris constant),
  and after specialization the signature no longer implies it.
- **total next to effects' diverge.** Its own loops, as against its callees'.
- **effects' absent-means-everything form.** This is how MLIR's
  default-valued attributes work; the one writer (`setEntry`) normalizes, and
  the verifier keeps the single form.
- **is_signed on signless integer ops.** Idris's Int/Bits pair; two cases.
- **Handles as i64 with -1 for null.** Base's `AnyPtr` can be null, and
  that is Idris's semantics.
- **match_lit's keys as an untyped ArrayAttr.** Literals of four types.
- **The default region's two shapes.** idr-rc's placement needs the
  scrutinee bound back.
- **OwnAdopt's and OwnGive's def-use verifiers.** The boundary with
  `memref.alloc` and `memref.store`, which hold no grade.
- **The KindRule table.** D1's boundary check, already data.
- **GeneratingOpInterface, UpdateOpInterface and the FlowEdges sums.** The
  mechanisms are already right.
- **Rule categories per rule rather than per site.** Recorded in 0002 §9, so
  not found again here.
