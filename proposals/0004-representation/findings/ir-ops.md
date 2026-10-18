<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Representation survey: ir-ops

Area: `foreign/idr/lib/IR/` `Ops*.cpp`, `Types.cpp`, `Attrs.cpp`, `ConAttr.cpp`,
`Constants.cpp`, `DataBody.cpp`, `DataRemap.cpp`, `Layout/`, `ContentNames.cpp`,
`Asm.cpp`, `Bytecode.cpp`, with their headers under `include/idr/IR/`.
Read-only; every claim below is *read* (source observation at HEAD 73d6dcf3)
unless marked *conjecture*. Nothing was built or run.

## The area as it stands

The data type is in good shape: its body is set once and checked once at
`setBody` (`DataBody.cpp`'s `KindRule` table is already the table SumKind x
CtorRole should be), constructors are tags, and every op names its
constructor by tag. What is left is mostly below and beside the body. A
constant constructor (`#idr.con`) has two storage forms, plain and run, and
every reader in 12 files writes both paths. The layout holds one fact as two
parallel walks (`componentsOf`/`countedOf`) and a sum's words as parallel
vectors with a coordinate offset for the tag. Two ops that build a
constructor with holes (`idr.con`, `idr.reuse`) share everything but an
interface, so their readers use `std::variant` + `std::visit`. The array
yield asks its parent's kind in two `TypeSwitch`es and a `ParentOneOf` list.
"A box constructor without fields has no cell" (the atom) is written as
`fields.empty()` at ten sites with four different token rules. And a
noticeable amount of what ODS declares (operand effects, operand and
attribute constraints, parameterized custom directives) is hand-written C++.

## Findings, ranked (branches removed against risk)

### ir-ops-1: Facts ODS declares are written as C++ hooks

| Field | Content |
|---|---|
| Evidence | **Effects:** 11 hand `getEffects` bodies that only put Read/Write/Allocate on an operand or result in the default resource, or Write on fixed resources: `OpsArrays.cpp:188-204` (`ArrayNewOp`, `ArrayGetOp`, `ArraySetOp`), `OpsClosures.cpp:214-219` (`ForceOp`: Write on Crash, Divergence, IO), `OpsPlatform.cpp:73-109` (`BufferLoad/Store/Copy/SetString/GetString`, `WriteBytes`, `ReadBytes`, with helpers `reads`/`writes`/`transfers`), declared through `DeclareOpInterfaceMethods<MemoryEffectsOpInterface>` (`IdrArrayOps.td:265`, `IdrClosureOps.td:76`, `IdrIOOps.td:77,137`). **Operand constraints:** `verifyBuffer` (`OpsPlatform.cpp:32-38`, 2 branches) called from 7 verifiers (8 calls, `:54-66`), each op `hasVerifier = 1` only for it (`IdrIOOps.td:82,153,164,181,195,209`); `verifyList` (`OpsStrings.cpp:25-33`, 3 branches) behind `StrPackOp`, `StrConcatOp`, `PutListOp`. **Attribute constraints:** `verifyHoles`' `hole < 0 \|\| ... \|\| holes[i-1] >= hole` (`OpsCon.cpp:116-119`, 3 conditions); `MatchOp::verify`'s `key < 0` (`OpsMatch.cpp:87`). Precedent in the same dialect: `Arg<Idr_DestType, "", [MemWrite]>` (`IdrOps.td:361`), `Res<..., [MemAlloc]>` (`IdrOwnershipOps.td:132`), `MemoryEffects<[MemRead<Idr_IOResource>, ...]>` (`IdrPlatformOps.td:298`), `Idr_MemoCell` (`IdrClosureOps.td:133-137`, a constraint in place of a verifier). |
| Counterexample | `idr.io.buffer_load %b[...]` over `memref<?xi32, #idr.world>` passes ODS (`Idr_Rank1ArrayValue`) and is caught only by the hand verifier; a new buffer op that forgets `hasVerifier` accepts it. A new array op that forgets `getEffects` has none. |
| Root cause | The operand type constraint stops at "rank-1 array" and the effects live in C++, so each op restates them. |
| Correction | ODS: `def Idr_ByteBuffer : Type<And<[Idr_Rank1ArrayValue.predicate, <element is i8>]>>` and `Idr_BaseListOf<list elements>` (box of a `BaseList` sum whose element is one of `elements`), operands written `Arg<Idr_ByteBuffer, "", [MemRead]>` / `[MemWrite]`, `Res<..., [MemAlloc, MemWrite]>` for `array.new`'s result, `MemoryEffects<[MemRead<Idr_IOResource>, MemWrite<Idr_IOResource>]>` on the transfer class, `MemoryEffects<[MemWrite<Idr_CrashResource>, MemWrite<Idr_DivergenceResource>, MemWrite<Idr_IOResource>]>` on `idr.force`; `holes` as `ConfinedAttr<..., [DenseArrayNonNegative<DenseI32ArrayAttr>, DenseArrayStrictlySorted<DenseI32ArrayAttr>]>` and `cases` with `DenseArrayNonNegative` (both in the pinned `CommonAttrConstraints.td:854-866`). |
| Deletion | 11 `getEffects` bodies and the three helpers; `verifyBuffer`, `verifyList` and the 10 verifiers that only call them (with their `hasVerifier`); the hole-order and negative-key conditions. `ConOp/ReuseOp`/`ArrayUpdate`/`ElementUpdate`/`OwnGive` keep their C++ effects (conditional or region-derived: essential). |
| Consumers | `IdrIOOps.td`, `IdrArrayOps.td`, `IdrClosureOps.td`, `IdrStringOps.td`, `IdrOps.td`, `IdrOwnershipOps.td`, `IdrMatchOps.td`; `OpsPlatform.cpp`, `OpsArrays.cpp`, `OpsClosures.cpp`, `OpsStrings.cpp`, `OpsCon.cpp`, `OpsMatch.cpp`; `tools/idris-mlir-tblgen.cpp` `dialectWord` (`:953-963`), which maps the constraint *name* `Idr_Rank1ArrayValue` to the C ABI's `Buffer` word, so `Idr_ByteBuffer` needs its entry (see handoff). |
| Discriminator | The verifier rejects the `memref<?xi32>` buffer and a `holes = array<i32: 1, 0>` con from ODS's generated `verifyInvariants`; the generated `getEffects` gives the same effect list (a dialect fixture asking `-test-side-effects`-style questions, or the existing `tests/idr` effect fixtures, unchanged). |
| Verification here | `make typecheck` (tblgen runs, C++ compiles); `make typecheck-dialects` should show no diff in the generated Idris modules. No pass runs. |
| Size and risk | About 110 lines of C++ and 20 hooks go, about 15 lines of ODS come. Low risk: the generated effects are the hand ones. |
| Insight | 6 (the constraint checks once, in the type) and 14 (effects as data). |

### ir-ops-2: `idr.array.yield` switches on its parent's kind

| Field | Content |
|---|---|
| Evidence | `OpsGenerating.cpp:160-171` `ArrayYieldOp::getMutableSuccessorOperands`: a `count == 0` case, then `TypeSwitch` over `TabulateOp, FoldLastOp, ScanLastOp` / `TabulateIOOp` / `UpdateOpInterface` / `DefaultUnreachable` (5 branches). `:178-191` `getFlowEdges`: a second `TypeSwitch` over the same parents, 5 cases + `DefaultUnreachable`, plus the `at < getValues().size()` guard. `IdrArrayOps.td:209-211` `ParentOneOf<[6 op names]>`: the third copy of the parent list. |
| Counterexample | A seventh array op with a region (say a `scan_first`) needs an edit in three places; forgetting one is an `llvm_unreachable` at run time, not a compile error. |
| Root cause | What a yield's values do (the first k move into k arrays, the rest go on to the parent's successor) is the parent's fact, kept in the terminator by kind. The rule is uniform: Tabulate (k arrays, none forwarded), TabulateIO (k arrays, then the world), FoldLast/ScanLast (k results), the updates (the array, then the outs). |
| Correction | One op interface, `Idr_YieldTargetsOpInterface` with `ValueRange getYieldTargets()` (the arrays the yield's leading values move into), which `GeneratingOpInterface` and `UpdateOpInterface` both declare as a base (Tabulate/TabulateIO: `getArrays()`; Fold/Scan: `getResults()`; updates: `getArray()`). The yield forwards `values.drop_front(targets.size())` and flows `zip(values, targets)`; its parent rule is "the parent implements the interface". |
| Deletion | Both `TypeSwitch`es (10 cases, 2 `DefaultUnreachable`), the `count == 0` case, the size guard, the `ParentOneOf` list. |
| Consumers | `IdrInterfaces.td`, `IdrArrayOps.td`, `OpsGenerating.cpp`, `OpsTabulate.cpp`, `OpsFolds.cpp`, `OpsArrays.cpp`. |
| Discriminator | `RegionBranchOpInterface`'s verifier and the flow tests over each array op (`tests/idr/arrays`, the bufferize fixtures) unchanged; a yield whose parent declares no targets is refused by the verifier, not by `llvm_unreachable`. |
| Verification here | `make typecheck`. |
| Size and risk | About 30 lines become 8. Low risk. |
| Insight | 7. |

### ir-ops-3: Components and their countedness are two parallel walks; a sum's words carry the tag as a coordinate offset

| Field | Content |
|---|---|
| Evidence | `Layout/Components.cpp:127-149` `componentsOf` and `:154-172` `countedOf`: the same ladder (world, data, shaped, big, reference, scalar) written twice, results matched by position; `countedOf`'s data case re-prepends `false` for the tag (`:161-162`) as `SumLayout::types()` prepends the tag type (`Layout.h:152-158`). `Layout.h:145-146` `SumLayout::slots` and `counted` are parallel vectors ("for each slot"), `offset()` (`:159`) shifts field indices by the tag. Pairings by position: `sumLayout`'s `zip_equal(componentsOf, countedOf)` (`Components.cpp:49-50`), `Layouts::cellOf`'s nested `fields`/`countedness` (`Layouts.cpp:169-177,199-209`), `Conversion/Cells.cpp:161-163` `LowerPoison`'s `zip_equal(components, counted)`, `Conversion/Words.cpp:74` `layout.offset() + slot`. `Layouts::components`/`counted` are two public queries (`Layout.h:216-219`). |
| Counterexample | Adding a component kind to `componentsOf` (say a two-word value) without the matching case in `countedOf`, whose fallback is `{holdsReferences(type)}` (one entry), makes the lists differ in length: `zip_equal` asserts in debug and reads past the end in release. A tag-shift bug in either prepend misaligns every counted slot of a sum. |
| Root cause | "A component and whether it is counted" is one fact per word, held as two lists; "where a field's words are" is held relative to the tag. |
| Correction | `struct Component { mlir::Type type; bool counted; }`; one `componentsOf(Type) -> SmallVector<Component>`; `Layouts::components` returns it and `counted` goes. `SumLayout` holds `SmallVector<Component> words`, the tag (when there is one) as words[0], and `fields[ctor][field]` as absolute indices into `words`. `Slot` gains `counted`. |
| Deletion | `countedOf` (one ladder, about 5 branches); `SumLayout::counted`, `types()`'s and `countedOf`'s tag prepends, `offset()`; the `countedness` vector and its two `(f, c)` loops become filters over slots; three `zip_equal` pairings. The `tag` optional stays (a sum of at most one constructor has no tag word: essential). |
| Consumers | `Layout.h`, `Layout/Components.cpp`, `Layout/Layouts.cpp`; `Conversion/{Elements,Lower,RuntimeCalls,Arrays,Facts,Cells,Buffers,Counting,Words}.cpp` and the `Runtime` inc/dec helpers that take `ArrayRef<bool>`. |
| Discriminator | Unequal lengths and a misplaced tag become unrepresentable. Behaviour: `make test-idr` lowering fixtures and the e2e suite unchanged (owner); a unit box in `foreign/idr/unittests` over every field type of a module asserting `components(t)` is what `cellOf`/`sumLayout` place. |
| Verification here | `make typecheck`. |
| Size and risk | About 40 lines and 10 branches go. Low to medium: the lowering is touched but mechanically, and does not run here. |
| Insight | 11 (and 4). |

### ir-ops-4: A constant constructor has two storage forms, and every reader writes both

| Field | Content |
|---|---|
| Evidence | `IdrAttrs.td:80-153` `#idr.con`: plain = one cell holding every field, `tail` null, `spine` 0; run = at least two cells without the spine field, a `tail`, a `spine`; `isRun()` is `tail != null`, `getRunCells()` is empty for a plain con. In `ConAttr.cpp`: `continues` (`:58-63`), `takeCells` (`:85-93`), `getRun`'s `pending.size() == 1` (`:162-167`), `getField` (`:194-205`), `getFields` (`:210-212`), `verify` (`:229-245`: the tail-dependent width, `cells.size() != 1 \|\| spine != 0`, `cells.size() < 2`), `getChecked` (`:267-276`): about 11 branches. Outside it, a plain path and a run path at: `Constants.cpp:28,119-132`, `DataRemap.cpp:111-113`, `OpsCon.cpp:243`, `Asm.cpp:77-83`, `Verify/Uses.cpp:99-108`, `Fold/Values.cpp:62`, `Specialize/Keys.cpp:148-151,184`, `Defunctionalize/Declare.cpp:232-240`, `Conversion/StaticNames.cpp:79-110`, `Conversion/StaticData.cpp:148-186`, `Analysis/Labels.h:67-78`, `IdentitiesRecord.cpp:259`: about 14 more, 12 files. |
| Counterexample | The parameters admit `tail == null` with `spine = 3`, `tail == null` with two cells, a tail with one cell, and a tail on a constructor without fields; `verify` rejects each. A new reader that handles only the plain path silently skips the cells of every list constant. |
| Root cause | A plain constructor is the run of one cell, but the storage gives it a form of its own, so "one cell" is a case instead of a length. |
| Correction | `#idr.con` holds `cells` (one or more) linked along `spine`: every cell but the last holds the constructor's fields without the spine field (the next cell is that field), and the last cell holds all of them; the `tail` parameter goes. A plain constructor is one cell, spine 0, spelled as today (`<!T, @C, [fields]>`); a run is `<!T, @C, [1], [2], [3, #idr.con<!T, @Nil, []>] along 1>`. `get` and `getRun` still make the longest run, so one value has one attribute. Every reader walks `cells`, mapping position `i` of cell `k` to field `k + 1 == n ? i : cellField(i, spine)`. |
| Deletion | `tail`, `isRun`, `getRunCells`; the plain/run split at every site above (about 25 branches); `verify`'s plain-form block; `getChecked`'s split; `FieldOp::fold`'s `+ (isRun ? 1 : 0)`; `StaticData::box`/`run` become one walk; `Keys.cpp`'s `isRun() != isRun()` and tail comparisons. The canonical rules (`joinedAt`, a cell holding its own constructor ends a run) stay: they are what makes the attribute unique. |
| Consumers | `IdrAttrs.td`, `ConAttr.cpp`, `Constants.cpp`, `DataRemap.cpp`, `OpsCon.cpp`, `Asm.cpp`, `Verify/Uses.cpp`, `Fold/Values.cpp`, `Specialize/Keys.cpp`, `Defunctionalize/Declare.cpp`, `Conversion/StaticNames.cpp`, `Conversion/StaticData.cpp`, `Analysis/Labels.h`, `Analysis/IdentitiesRecord.cpp`; `tests/idr/syntax/constants.mlir` (the one fixture that spells a run). The frontend writes no `#idr.con` (`Syntax/Idr.idr:585`). |
| Discriminator | The four invalid shapes above no longer exist. `tests/idr/syntax/constants.mlir` (a 10,000-cell list parses and prints flat), `--verify-roundtrip` on every fixture with a constant, and a property box: for every constant `c`, `ConAttr::get(c.getData(), c.getTag(), c.getFields()) == c`. |
| Verification here | `make typecheck`; the property box links MLIR, so the owner's `make test-unit`. |
| Size and risk | About 80 lines and 25 branches go. Medium: canonical uniqueness must hold as before, and static data names (content keys) may change text, which no test should pin. |
| Insight | 12 (the one-cell case is a homogeneous coordinate), 8. |

### ir-ops-5: `idr.con` and `idr.reuse` are one shape with no interface

| Field | Content |
|---|---|
| Evidence | Identical `getField`/`getDest`/`build` pairs (`OpsCon.cpp:81-93`, `OpsOwnership.cpp:42-56`) over shared free functions in `IdrDialect.h:375-389`; `include/idr/Analysis/Tail.h:43` `using Built = std::variant<ConOp, ReuseOp>` with `std::visit` at `Analysis/Tail.cpp:19-39` (an `isa` ladder to make it) and `Transforms/Tail/Trmc.cpp:84-122` (two `rebuilt` overloads, three `visit`s); `FlowOps.cpp:102-107,219-224` call `builtEdges` with the same five arguments each. The rule for a field moving into a cell is spelled twice: `ConOp::verify` with `atPermission` (`OpsCon.cpp:147-153`), `ReuseOp::verify`/`TakeOp::verify` with `movedField` + `movesAs` (`OpsOwnership.cpp:22-28,73-76,107-111`), the `view` comparison 0002 §4.3 (F06) replaced by `atPermission` at four other sites. |
| Counterexample | A third holed builder (a constructor built in a stack slot of a caller, say) means a third arm in every `variant`/`visit`; a change to the field rule made in `ConOp::verify` and not in `ReuseOp::verify` lets the two disagree on the same field. |
| Root cause | "Builds the constructor `tag` with these fields and these holes" is a polymorphism named only by a `std::variant`. |
| Correction | `Idr_BuildsConstructorOpInterface` (ODS): `getDataType`, `getTag`, `getFields`, `getHoles`, `getDests`, with `getField(i)`/`getDest(i)` in its shared class declaration, a `rebuildWithHoles(builder, fields, holes)` method, and the interface's `verify` holding `verifyHoles` and the one field rule (`atPermission` at the value's permission, in Grades.h). Both ops declare it. |
| Deletion | `Built` and the five `std::visit`s; `builtBox`'s `isa` ladder; the duplicated accessors and builders; `movesAs`; the second field-rule spelling. The two ops stay two (a cell taken over vs a new one: their effects and stages differ, essential). |
| Consumers | `IdrInterfaces.td`, `IdrOps.td`, `IdrOwnershipOps.td`, `IdrDialect.h`, `OpsCon.cpp`, `OpsOwnership.cpp`, `FlowOps.cpp`, `Analysis/Tail.{h,cpp}`, `Transforms/Tail/Trmc.cpp`, `Conversion/Fields.cpp`, `Conversion/Cells.cpp`. |
| Discriminator | The trmc fixtures (`tests/idr/tail/*`) and the owned-stage verifier fixtures unchanged; the interface verifier rejects a reuse whose field is plain where the cell owns it, by the same rule as a con. |
| Verification here | `make typecheck`. |
| Size and risk | About 60 lines go. Low to medium. |
| Insight | 7. |

### ir-ops-6: The atom is ten `fields.empty()` tests and four token rules

| Field | Content |
|---|---|
| Evidence | "A box constructor without fields has no cell" is tested at `OpsOwnership.cpp:67` (`ReuseOp::verify`), `:87-92` (`TakeOp::getToken`: `isa<BoxType> && getNumResults() != 0`), `:103` (`TakeOp::verify`: `isBoxed && !fields.empty()`), `Transforms/Ownership/Take.cpp:42` (`!fields.empty()`, no box test), `:57` (`isa<BoxType> && block.getNumArguments() != 0`), `Analysis/Ownership/Reuses.cpp:185,209`, `Transforms/Expect/ReusesEveryCell.cpp:30`, `Verify/Uses.cpp:99` (`!isMemo() && !isRun() && fields.empty()`: the only site with the memo exception), `IdentitiesRecord.cpp:259`, `Conversion/Counting.cpp:138-142` (an atom's take frees nothing). Meanwhile `Layouts::cellOf` gives a nullary constructor a header-only heap cell (`Layouts.cpp:79-92`), which `LowerCon` allocates for any boxed `idr.con` that reaches lowering unfolded (`Conversion/Cells.cpp:64-74`). |
| Counterexample | *Conjecture, latent:* a nullary boxed `idr.con` created after the last canonicalize (folding is what turns it into a static atom, `OpsCon.cpp:160-176`) is lowered to a heap allocation, and its take frees nothing: a leak. A memo state without fields is an atom to `TakeOp` and not to `Verify/Uses.cpp`. |
| Root cause | The atom is a fact of the body (kind and field count of a constructor), held by no type, so each site re-derives it, two of them from proxies (the result count, the region's argument count). |
| Correction | One predicate on the body, `DataType::isAtom(Tag)` (no fields, not a memo sum's state), and `TakeOp`'s results as `(outs Optional<Idr_OwnedToken>:$token, Variadic<AnyType>:$fields)` with `AttrSizedResultSegments`, the verifier tying the token's presence to `!isAtom` once; the layout has no heap cell for an atom (`Layouts::box` gives its static cell), and `LowerCon` lowers a nullary boxed con to the static atom. |
| Deletion | The ten local tests (each becomes the predicate or disappears behind the generated `getToken`); the hand `getToken`/`getFields` and their `drop_front`; `Take.cpp`'s two builders' token rules; the leak path. |
| Consumers | `IdrTypes.td`/`Types.cpp`, `IdrOwnershipOps.td`, `OpsOwnership.cpp`, `Layout/Layouts.cpp`, `Conversion/{Cells,Counting,StaticData}.cpp`, `Transforms/Ownership/Take.cpp`, `Analysis/Ownership/Reuses.cpp`, `Transforms/Expect/ReusesEveryCell.cpp`, `Verify/Uses.cpp`, `Analysis/IdentitiesRecord.cpp`, `FlowOps.cpp:232`, `Transforms/Ownership/{Reuse,Rc}.cpp`, `Verify/Program.cpp:127`, `Demand/Demand.cpp:68`, `Expect/{TestsNothing,ResetsUnshared}.cpp`. |
| Discriminator | A fixture with a nullary boxed `idr.con` handed straight to `idr-lower` (no canonicalize) lowers to a reference to the static atom, not an `idris_rt` allocation; a take with a token on an atom, or without one on a cell, is refused by the one verifier rule. |
| Verification here | `make typecheck`. |
| Size and risk | About 30 lines go; 10 sites converge. Medium: the owned-stage passes all read it. |
| Insight | 6. |

### ir-ops-7: DataRemap decides what a field becomes three times, and the key's copy disagrees

| Field | Content |
|---|---|
| Evidence | `DataRemap.cpp:116-128`: the replacer boxes a data type of `boxed` and applies the leaf at any depth. `:178-216`: change detection re-walks every field, setting `direct` for a nested boxed type or a nested leaf (3 branches). `:231-254`: the content key re-derives the field's new form at the top level only (`dyn_cast<DataType>(unrestricted(field))`, `leafAt(field, place)`), writing `describe(field)` otherwise. |
| Counterexample | Holder `H` with field `!idr.fn<(!idr.data<"T">) -> i64>` and `T` boxed: the replacer makes `!idr.fn<(!idr.box<T>) -> i64>` and detection marks `H` changing, but the key is the old field's text; likewise a leaf replacing a closure type inside `tensor<4x!idr.fn<...>>`. Two remaps of one kind that differ only there give `H` one name, against the class comment (`Symbols.h:73-84`), and `define` then fails with "has another body already". Latent today (fit and defunctionalization run once per context). |
| Root cause | "The field's new shape" has no value of its own; three code paths compute pieces of it. |
| Correction | One function `shapeAt(field, place) -> Type`: the field with boxes and leaves applied and every data type kept by its old name (an `AttrTypeReplacer` holding the box and leaf replacements, not `mapData`). `direct = shape != field \|\| a label is renamed`; the key is `describe(shape)`; `remake` maps the shape's data types to their new types. |
| Deletion | The detection walker's three branches and its leaf walk; the key's top-level box/leaf re-derivation; the mixing of the two concerns in `addReplacements`' per-field replacer. |
| Consumers | `DataRemap.cpp`, `Symbols.h`. Users unchanged: `Layout/Fit.cpp`, `Transforms/Defunctionalize/*`, `Transforms/Bufferize/*`. |
| Discriminator | A unit test: two remaps of kind `box`, one boxing `T` and one not, over the `H` above, give `H` different names (fails today). |
| Verification here | `make typecheck`. |
| Size and risk | About 40 lines go. Medium: remade names change text where nested fields change. |
| Insight | 6. |

### ir-ops-8: A destination of any type is expressible, and a hole at a non-box field is checked only under assertions

| Field | Content |
|---|---|
| Evidence | `IdrTypes.td:315-320` `!idr.dest` takes `"::mlir::Type":$value`; `Types.cpp:321-325` verifies it is a box. `OpsCon.cpp:62-65` `destOf` builds it with `DestType::get`, which verifies only inside `assert` (`StorageUniquerSupport.h:177-181`); `verifyHoles` (`OpsCon.cpp:112-128`) never checks that a hole's field is a box, it compares `dest != destOf(ctor, hole)`, two values of the same unchecked construction. `Ops.cpp:213-223` `parseDests` and `Transforms/Tail/Trmc.cpp:225` call `get` too. `IdrOps.td:358` and `FlowEdges.cpp:59` apply `unrestricted` to the dest's value, which a box never needs. |
| Counterexample | `idr.con !T @C(dest)` whose field 0 is `i64`: an assert build aborts in the parser; a release build makes `!idr.dest<i64>`, the op verifies, and the lowering writes a pointer-sized word through it. |
| Root cause | The parameter's type admits every type; the one rule lives in a verifier `get` skips. |
| Correction | `!idr.dest`'s parameter is `"::idr::BoxType":$value`, and `verifyHoles` checks each hole's field is a box (at any grade) before `destOf` runs. |
| Deletion | `DestType::verify` and its `genVerifyDecl`; the bytecode record's `getChecked` builder (`IdrBytecode.td:46-47`); the two `unrestricted` calls. |
| Consumers | `IdrTypes.td`, `Types.cpp`, `IdrBytecode.td`, `OpsCon.cpp`, `Ops.cpp`, `IdrOps.td`, `FlowEdges.cpp`, `Transforms/Tail/Trmc.cpp`, `Layout/Components.cpp:146`; regenerated Idris bytecode encoders (`make typecheck-dialects`). |
| Discriminator | The fixture above is refused with an op error in every build. |
| Verification here | `make typecheck`. |
| Size and risk | 10 lines. Low. |
| Insight | 4. |

### ir-ops-9: Six custom directives differ only in a plain type

| Field | Content |
|---|---|
| Evidence | `Ops.cpp:102-165`: `parse/print` x `Str/Big/Nat` x `Result/Read`, 12 functions, each a call of `parseResultAtGrade`/`printResultAtGrade` or `parseRead`/`printRead` with `StrType::get`, `BigType::get` or `NatType::get`. Uses: `custom<StrRead>` 31, `StrResult` 15, `BigRead` 10, `BigResult` 10, `NatResult` 3, `NatRead` 1. |
| Counterexample | A fourth carrier with a plain default (a char type, say) costs four more functions. |
| Root cause | The default type is a parameter written as a function name. |
| Correction | `custom<ResultAtGrade>(type($r), "::idr::StrType::get($_ctxt)")` and `custom<Read>($x, type($x), "...")`: a custom directive takes a C++ string with `$_ctxt` (`Operations.md:1012-1015`). |
| Deletion | The 12 wrappers. |
| Consumers | `Ops.cpp`; `IdrStringOps.td`, `IdrBigOps.td`, `IdrIOOps.td`, `IdrPlatformOps.td`, `IdrCheckOps.td` (70 directive uses, mechanical). The Idris side emits ops generically and reads no op format. |
| Discriminator | `tests/idr/asm` and `syntax` round trips unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | 60 lines. Trivial risk. |
| Insight | 14. |

### ir-ops-10: "A literal of this type" is three ladders

| Field | Content |
|---|---|
| Evidence | `OpsMatch.cpp:150-162` `MatchLitOp::verify` (`TypeSwitch`: integer, string, big, natural non-negative, default: 5 branches); `OpsMatchSyntax.cpp:151-182` `parseKey` (i1 keywords, integer, string, big or natural: 4 branches); `Constants.cpp:149-154` `isBuildableWith` (big, natural non-negative, string). The natural's non-negativity is written twice. `IdrMatchOps.td:75-76` lists the scrutinee types again. |
| Counterexample | A literal match on a new scalar carrier needs three edits; a natural key `-1` is caught by one ladder's rule and a natural constant `-1` by the other's, which can drift. |
| Root cause | What a literal of a type is belongs to the type and is held by its readers. |
| Correction | `Idr_LiteralTypeInterface` (type interface): `bool isLiteral(Attribute)` and `ParseResult parseLiteral(AsmParser&, Attribute&)`, on `StrType`, `BigType`, `NatType` and, by external model, `IntegerType`. `match_lit`'s scrutinee is a read of a type with the interface; verify, parse and `isBuildableWith` dispatch once. |
| Deletion | Both ladders in the match ops, the scalar cases of `isBuildableWith`, the duplicated natural rule. |
| Consumers | `IdrInterfaces.td`, `IdrTypes.td`, `Types.cpp` or `ValueFacts.cpp` (external model registration), `IdrMatchOps.td`, `OpsMatch.cpp`, `OpsMatchSyntax.cpp`, `Constants.cpp`. |
| Discriminator | `tests/idr/verify` literal-key fixtures unchanged; a natural key and a natural constant `-1` are refused by the one rule. |
| Verification here | `make typecheck`. |
| Size and risk | About 35 lines go. Low. |
| Insight | 7. |

### ir-ops-11: Every constant attribute carries a type parameter that must be `none` once stored

| Field | Content |
|---|---|
| Evidence | `IdrAttrs.td:41-49` `Idr_Attr` adds `AttributeSelfTypeParameter` and `TypedAttrInterface` to `#idr.con`, `#idr.closure` and `#idr.big` only because MLIR's attribute parser always consumes a trailing `: T` (`DialectSymbolParser.cpp:264-267`); builtin `StringAttr` takes it too. Consequences: `Constants.cpp:24-39` `untyped` (`TypeSwitch` over four kinds, a run branch, a default) and its check in `isBuildableWith` (`:144`); `ConstantOp::parse/print` hand-written (`:159-198`), with the alias case (`:171-172`) and a hand copy of the strict-properties check (`:182-189`); `ConAttr::getChecked`'s typed rebuild (`ConAttr.cpp:279-282`) and the `type` argument of `getStored`/`getStoredChecked`; every builder passing `NoneType`. |
| Counterexample | `#idr.big<5> : !idr.nat` inside a constructor's field list is a typed big that `buildable` must remember to reject; any new constant attribute repeats the dance. |
| Root cause | `idr.constant` writes its type after its value, where the parser hands it to the attribute. |
| Correction | `idr.constant` writes its type first, declaratively: `let assemblyFormat = "type($result) $value attr-dict"`; the constant attributes lose the self type and `TypedAttrInterface`. |
| Deletion | `untyped`, its check, the hand parser and printer with their special cases, `ConAttr`'s typed path and `type` parameters, the `NoneType` arguments. |
| Consumers | `IdrAttrs.td`, `IdrOps.td`, `Constants.cpp`, `ConAttr.cpp`, `Asm.cpp` (alias), `Canon/Captures.cpp`; 306 lines in 101 test files (mechanical). The frontend writes `idr.constant` generically (`Dialect/Idr.idr:231`), so its bytecode is unchanged. |
| Discriminator | `tests/idr/syntax/constants.mlir` and every round trip; a typed constant attribute is no longer expressible. |
| Verification here | `make typecheck`. |
| Size and risk | About 70 lines go. Medium churn in fixtures, low behaviour risk. |
| Insight | 4. |

### ir-ops-12: Facts of a boxed sum are kept per constructor cell and read through constructor 0

| Field | Content |
|---|---|
| Evidence | `Layout.h:110-117` `Cell::group` is "at one offset in every cell of the sum", stored in every cell; `Conversion/RuntimeCells.cpp:60-61` reads it as `data.getCtors().empty() ? nullopt : layouts.box(data, Tag{0}).group`. The memo sum's allocation size is patched into each cell after all are made (`Layouts.cpp:88-96`). `Layouts::boxes` is keyed by `(DataType, Tag)` (`Layout.h:259`), its miss an internal error per pair (`Layouts.cpp:225-233`). |
| Counterexample | A sum without constructors needs the explicit empty test before the group can be read; the memo size is wrong between the two loops. |
| Root cause | Per-sum facts have no per-sum record. |
| Correction | `struct BoxLayout { std::optional<Slot> group; SmallVector<Cell> cells; }` per data type (cells by tag, each with its allocation size, a memo sum's computed as the largest before any cell is stored), `Layouts::box(DataType) -> const BoxLayout&`. |
| Deletion | The constructor-0 read and the empty test; the patch loop; the per-pair map and its error (one per type remains). |
| Consumers | `Layout.h`, `Layout/Layouts.cpp`, `Conversion/{RuntimeCells,Cells,Counting,Strings,MemoCells,StaticData}.cpp`, `Analysis/Ownership/Reuses.cpp`, the stack and owned verifiers that size cells. |
| Discriminator | Lowering fixtures unchanged; a sum of more than `IDRIS_RT_TAG_LIMIT` constructors still reads its group word. |
| Verification here | `make typecheck`. |
| Size and risk | About 15 lines. Low. |
| Insight | 8. |

### ir-ops-13: A guard's condition reads its constants by position and checks their count

| Field | Content |
|---|---|
| Evidence | `OpsChecks.cpp:28-78`: five `holds(ArrayRef<Attribute>)`, each with `constants.size() != N` and `word(constants, i)` by index (5 arity branches); the `GuardOp` concept (`IdrDialect.h:320-323`) and `guardedSpeculatability` build the list from `guarded` + `against`. |
| Counterexample | A caller passing the wrong `against` silently gets "does not hold". |
| Root cause | The guard's operands, which ODS names, travel as an untyped list. |
| Correction | `holds(typename Guard::FoldAdaptor)`, the generated adaptor, read by name (`getOffset()`, `getCount()`, `getSize()`); `guardedSpeculatability` builds the adaptor. |
| Deletion | The five arity checks and `word`. |
| Consumers | `OpsChecks.cpp`, `IdrDialect.h`, `Ops.cpp:264` (the division fold), `OpsScalars.cpp:38`, `OpsStrings.cpp:76-80`. |
| Discriminator | Guard fold fixtures unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | 15 lines. Low. |
| Insight | 6. |

### ir-ops-14: A match's default region binds nothing or the scrutinee

| Field | Content |
|---|---|
| Evidence | `OpsMatch.cpp:105-110` accepts zero arguments or the scrutinee; readers branch on the count: `Transforms/Ownership/Placement.cpp:324`, `Reshape.cpp:117-120`, the printer `OpsMatchSyntax.cpp:100-105`, the parser's optional parenthesis `:57`. |
| Counterexample | A pass that adds the argument for a linear scrutinee and one that assumes none disagree on the same match. |
| Root cause | The argument is needed for a linear scrutinee (which the match used) and optional otherwise, so absence is a case. |
| Correction | The default region always binds the scrutinee (a null object where it is unused). |
| Deletion | The two-form check, the count tests in Placement and Reshape, the printer's and parser's optional form. |
| Consumers | `OpsMatch.cpp`, `OpsMatchSyntax.cpp`, `IdrMatchOps.td` builder, `MatchOp::create` sites (3), `Transforms/Ownership/{Placement,Reshape}.cpp`, and the frontend's emission of defaults (`compiler/src/IdrisMLIR/Emit`). |
| Discriminator | Match fixtures; the verifier refuses a default without the argument. |
| Verification here | `make typecheck`; the frontend half on Chez. |
| Size and risk | About 6 branches. Low to medium (crosses into Emit). |
| Insight | 8. |

### ir-ops-15: A signedness flag on operands that have no sign

| Field | Content |
|---|---|
| Evidence | `OpsStrings.cpp:51-55` refuses `idr.str.show` of an `f64` with `signed` (`IdrStringOps.td:90`: `AnyTypeOf<[Idr_Int, F64]>` beside `UnitAttr:$is_signed`); `OpsBigs.cpp:149-153` refuses `idr.big.from_int` to a natural with `signed` (`IdrBigOps.td:202`). |
| Counterexample | Both invalid combinations parse and need a verifier each. |
| Root cause | One op covers an operand kind for which the flag means nothing. |
| Correction | `idr.str.show` takes an integer only and the Double's show is its own op; a natural from an integer is the unsigned reading by its result type, with no flag accepted there (`PredOpTrait` on the one op, or `idr.nat.from_int` without the flag). |
| Deletion | Both verifiers. |
| Consumers | `IdrStringOps.td`, `IdrBigOps.td`, `OpsStrings.cpp`, `OpsBigs.cpp`, the registry and the generated Idris dialect (`make typecheck-dialects`), `Fold/Strings.cpp`, the runtime ABI table. |
| Discriminator | The two invalid combinations are not expressible. |
| Verification here | `make typecheck`; the registry on Chez. |
| Size and risk | 2 branches; crosses into the registry. Low value. |
| Insight | 4. |

### ir-ops-16: "Used exactly once by its nature" has two encodings

| Field | Content |
|---|---|
| Evidence | The world is a grade of a carrier, `!idr.q<one, plain, !idr.world_carrier>`: `Types.cpp:226-240` (a `wholes` table of one entry and `isGradedWorld`, read in `parseType`/`printType`), `QType::verify`'s world branch (`Types.cpp:306-312`), `Grades.cpp:42-48` (`isLinear` excludes it, `isWorld` strips the grade), `IdrTypes.td:289-290` (`Idr_LinType` "other than the world"). The destination is a plain type with a special case in `quantityOf` (`Grades.cpp:116-119`). |
| Counterexample | A third type used once by nature has no rule to follow; each reader of quantity must know both. |
| Root cause | The quantity of a type that is linear by nature is a grade for one and a special case for the other. |
| Correction | Both are plain types whose quantity is the type's own: `!idr.world` is the carrier's mnemonic, and `quantityOf` asks a `ValueFactsTypeInterface` method `usedOnce()` that the world and the destination answer. |
| Deletion | `wholes`, `isGradedWorld`, `world()`'s grade, `QType::verify`'s world case, `isLinear`'s `!isWorld`, `quantityOf`'s `isa<DestType>`. |
| Consumers | `IdrTypes.td`, `IdrInterfaces.td`, `Types.cpp`, `Grades.{h,cpp}`, every `Idr_WorldType` operand's accessor type, `IdrBytecode.td` and the frontend's world type (Emit, generated bytecode encoders). |
| Discriminator | Linearity verifier fixtures unchanged; `!idr.q<many, plain, !idr.world>` is no longer constructible. |
| Verification here | `make typecheck`, `make typecheck-dialects`, the frontend on Chez. |
| Size and risk | About 6 branches; high risk (grades are the core and cross the frontend). Listed for completeness; do last or not at all. |
| Insight | 4. |

## Judged essential, and kept

- Box against sum held in place in `ConOp`/`FieldOp`/`TakeOp` effects,
  speculatability and lowering: a cell and slots are two runtime
  representations.
- `layout::Element::boxed`, grouped sums, the count word: each is a second
  encoding the header forces past a limit (no count refuses a program).
- `SumLayout::tag` absent for at most one constructor, and the TagOp
  lowering's constant 0 and the range fact that read it: no tag word exists.
- SumKind against CtorRole: already one table (`DataBody.cpp:32-47`) checked
  once at `setBody`. `Ctor`'s `fn`/`byName` payload, valid for labels only, is
  checked there too; readers read the payload, and a C++ variant would add a
  visit to every reader of a name or fields. (`Expect/ByName.cpp:42`
  re-tests the role: a cross-area nit.)
- `getField`/`getDest` returning null for a hole: the case split of a
  constructor with holes, the representation the representation wave chose
  (D15).
- `DataType::replaceLabels`' fatal error, DataRemap's `made` flag: the
  immutable body, and an `AttrTypeReplacer` callback that cannot fail.
- `verifyBody`'s list tail held in place or in a box: before and after fit.
- `printCtorRef`'s `<<no constructor N>>`, `parseDests`' leniency, `Asm.cpp`'s
  `ctorOf` miss: printing and parsing IR the verifier will reject.
- `match` against `match_lit`: tags against literals, already shared
  through `MatchLike`.
- `describe` in DataRemap: a key that writes data types by their old names to
  break the naming cycle; no MLIR printer prints a data type by name alone.
- ContentNames' 64-bit names with the collision check: a name-length policy.
- Bytecode's field codes, `readEnum`, `member`'s checks: decoding at the
  wire boundary, where the DSL hands an untyped `ArrayAttr`.
- A data type's facts cached lazily under the context lock: they cannot
  disagree with an immutable body.
- `TagOp::fold`'s and `inferResultRanges`' `!data` tests are dead under
  `Idr_SumRead`: noise, not a representation defect.
- `aliasFrom` in `Asm.cpp`: a size policy of the printer.
