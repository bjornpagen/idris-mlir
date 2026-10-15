# U01 — The IR states its facts: identified data types, inherent facts, the root, refusals as data

## Permitted outcome
1. Mandatory. A data type is an identified type with a body set once
   (C01): `!idr.data<"T", kind [ctors] instance ...>`, `!idr.box<T>`;
   `idr.data` and `idr.ctor` are gone; every verifier, fold, range,
   canonicalization and layout in `lib/IR` reads the type, and no
   `lib/IR` code looks a data type up in a symbol table.
2. Mandatory. Constructor references are flat names within the value's
   type (C02 §1), with `getDataType()`/`getTag()` on each op that names one.
3. Mandatory. Inherent facts (C02): `idr.con`'s `stack`; `idr.func`
   with exactly C02 §3's properties; call-site effects verified equal to
   the callee's; `idr.delay %value`; `idr.lambda` gone; no discardable
   attribute declared.
4. Mandatory. The root (C03): the function verifier demands a body and a
   root type of a public function; the module rules run from the root's
   symbol-use verifier; `idr.program` is gone.
5. Mandatory. Refusals as data (C04): the `Rule` enum and `#idr.rule` in
   ODS; `refuse`, `refusalHead`, `refusalRule`; the C++ refusals of
   `lib/IR` through them; the generated Idris `Rule` with `Show`;
   `compiler/src/IdrisMLIR/Rule.idr` deleted.
6. Mandatory. Names from content, the C++ half (C21): `contentHash`,
   `contentName`, `ContentNames`; `DataRemap` names its types with them.
7. Mandatory. `idris-mlir-tblgen` taught the identified type, the enum
   `Show` and keyword-or-string spellings (C01 §4a, C04 §4); the generated
   `Dialect/Idr.idr` and `Syntax/Idr.idr` written as the generator writes
   them, for `make typecheck` to confirm.
8. Mandatory. A memref's or tensor's components are the fields of its
   descriptor its type leaves to the value, the element-0 pointer never
   carried: `[cell, dynamic offset of a strided layout, each dynamic size,
   each dynamic stride]` (C01 §9, the coordinator's ruling with C16/C17),
   in `lib/IR/Layout/Components.cpp`.
9. Mandatory. C05 on these files: no op declares the flow interface in
   ODS and `IdrDialect.h` includes none of it (every op's flow is an
   external model in U02's `lib/IR/Flow.cpp`); `FuncOp::verifyRegions`
   calls `idr::verifyFlow` on every op nested in the body, including
   `idr/IR/Flow.h` in `lib/IR/Func/Func.cpp`.
10. Mandatory. C11 on these files (0003's stage 1): `isArray` the
   world-ordered memref (`#idr.world`), `isFieldType` taking a ranked
   tensor and a value buffer; `QType::verify` taking a ranked tensor at
   (one, plain) only; the effects of the IO and buffer ops on their own
   memref and `ioEffects` gone; the unordered array ops' yields, regions
   and owned-stage walks gone (`Regions.cpp`, `IdrMatchOps.td`,
   `Verify/Uses.cpp`, `Ownership.h`'s `isArrayLoop`,
   `Verify/OwnedRegions.cpp`, `Verify.h`'s `walkArrayLoop`); the
   `ValueBoundsOpInterface` include.
11. Mandatory. C14 §1's `stack` invariants in `ConOp::verify` and
   `Verify/Owned.cpp`; C14 §3's vocabulary (`idr.own.adopt`,
   `idr.own.give`, `isIndexLoop`, `readFrom` of buffer views and counted
   loads, `reachesOnlyAtoms(Value)`, every memref counted, the owned
   walk's buffer checks); C16 §3's memref components (with outcome 8).
12. Mandatory. `#idr.con` holds its data type (C02 §1): a constant is
   untyped, and a run's cells are one type's, so `Just (Just 3)` over two
   `Maybe` instances never joins into one run.

Consumer adaptations made here: every reader of a data type, constructor
reference, `idr.stack`, `idr.program`, a function's deleted properties, `idr.lambda`
or region `idr.delay` inside the write set below.

## Owner / exclusive writes
Headers (`INC` = `foreign/idr/include/idr`): `INC/IR/Canon.h`,
`INC/IR/Fold.h`, `INC/IR/Func.h`, `INC/IR/Grades.h`, `INC/IR/IdrAttrs.td`,
`INC/IR/IdrBase.td`, `INC/IR/IdrBigOps.td`, `INC/IR/IdrCheckOps.td`,
`INC/IR/IdrClosureOps.td`, `INC/IR/IdrDialect.h`, `INC/IR/IdrInterfaces.td`,
`INC/IR/IdrIOOps.td`, `INC/IR/IdrMatchOps.td`, `INC/IR/IdrOps.td`,
`INC/IR/IdrOwnershipOps.td`, `INC/IR/IdrPlatformOps.td`,
`INC/IR/IdrScalarOps.td`, `INC/IR/IdrStringOps.td`, `INC/IR/IdrTypes.td`,
`INC/IR/Layout.h`, `INC/IR/Ownership.h`, `INC/IR/Ranges.h`,
`INC/IR/Symbols.h`, `INC/IR/TypeGraph.h`, `INC/IR/Verify.h`.

Sources (`IDR` = `foreign/idr/lib`): `IDR/IR/Asm.cpp`, `IDR/IR/Attrs.cpp`,
`IDR/IR/Canon`, `IDR/IR/ConAttr.cpp`, `IDR/IR/Constants.cpp`,
`IDR/IR/Crashes.cpp`, `IDR/IR/Dialect.cpp`, `IDR/IR/Effects.cpp`,
`IDR/IR/Fold`, `IDR/IR/Func`, `IDR/IR/Grades.cpp`, `IDR/IR/Layout`,
`IDR/IR/Ops.cpp`, `IDR/IR/OpsBigs.cpp`, `IDR/IR/OpsChecks.cpp`,
`IDR/IR/OpsClosures.cpp`, `IDR/IR/OpsCon.cpp`, `IDR/IR/OpsData.cpp`
(deleted), `IDR/IR/OpsMatch.cpp`, `IDR/IR/OpsMatchSyntax.cpp`,
`IDR/IR/OpsOwnership.cpp`, `IDR/IR/OpsPlatform.cpp`,
`IDR/IR/OpsScalars.cpp`, `IDR/IR/OpsStrings.cpp`, `IDR/IR/Ranges.cpp`,
`IDR/IR/Regions.cpp`, `IDR/IR/Symbols.cpp`, `IDR/IR/TypeGraph.cpp`,
`IDR/IR/Types.cpp`, `IDR/IR/Verify`. In `IDR/IR/Canon`,
`Canon/ClosureOf.cpp` is deleted (its one caller was the apply rewrite
that goes).

Tool: `TL/idris-mlir-tblgen.cpp` (`TL` = `foreign/idr/tools`).

Idris (`SRC` = `compiler/src/IdrisMLIR`): `SRC/Rule.idr` (deleted),
`SRC/Dialect`, `SRC/Syntax` (generated; written here as the generator
writes them).

New files: none. `OpsData.cpp`'s logic moves into `Types.cpp`; the storage
of the data type lives in `Types.cpp` with the type definitions.

**Excluded:** `INC/IR/IdrArrayOps.td`, `IDR/IR/OpsArrays.cpp` (U11, C11);
`INC/IR/IdrFlow.td`, `INC/IR/Flow.h`, `IDR/IR/Flow.cpp` (U02, C05); `INC/IR/CMakeLists.txt`,
`IDR/IR/CMakeLists.txt` (coordinator: `OpsData.cpp` leaves the list, the
link line of `IdrIR` gains LLVM's `Support` if absent); `tools/dialects.sh`
(coordinator); `SRC/Emit*`, `SRC/MLIR*`, `SRC/SyntaxSamples.idr` (U15);
`SRC/Frontend`, `SRC/Registry*`, `compiler/idris-mlir.ipkg` (U14); every
`lib/Transforms`, `lib/Analysis`, `lib/Conversion`, `lib/Driver` file (their
lanes); `tests/` (U17, U18).

## Read first
- `contracts.md` (or `contracts/` until it exists): C01, C02, C03, C04, C21
  whole; C05 (the ops that declare the flow interface); C11 (what changes
  in `isArray`, `isFieldType` and `idr.yield`'s parents); C16, C17 (the
  memref components).
- 0004 `README.md`: §2.2 (the closed world), §4 stage 1 (D29's bullets),
  §4 stage 2, §6 rows `idr.stack`, `idr.program`, the loop-breaker row,
  `CloneAttr`, lookup-dodging branches, `listElement`, names from counters,
  the driver's decision by prefix; §11 D18, D19, D28, D29, D31, D36, D37,
  D38, D42, D48.
- The live IR: `include/idr/IR/IdrOps.td:14-176` (func, call, data, ctor),
  `IdrTypes.td:19-38`, `IdrAttrs.td:181-243`, `IdrBase.td:49-58`,
  `IdrClosureOps.td:46-102`, `IdrMatchOps.td:65-78`,
  `IdrOwnershipOps.td:120-160`, `IdrDialect.h:216-305`, `Symbols.h`,
  `Layout.h`, `TypeGraph.h`, `Verify.h`; `lib/IR/OpsData.cpp`,
  `Symbols.cpp`, `OpsCon.cpp`, `OpsMatch.cpp`, `OpsOwnership.cpp`,
  `OpsClosures.cpp:87-135, 230-297`, `OpsStrings.cpp:25-60`,
  `Constants.cpp:100-160`, `ConAttr.cpp`, `Asm.cpp`, `Dialect.cpp`,
  `Types.cpp`, `TypeGraph.cpp`, `Layout/*.cpp`, `Verify/Program.cpp`,
  `Verify/Attributes.cpp`, `Verify/Owned.cpp:50-75, 200-215`,
  `Verify/Uses.cpp:80-95`, `Verify/Knots.cpp`, `Func/Func.cpp`,
  `Func/Call.cpp`, `Canon/MatchPatterns.cpp:95-125`, `Canon/Eta.cpp:40-89`,
  `Canon/MoveOut.cpp:55-75`, `Regions.cpp`.
- The generator: `tools/idris-mlir-tblgen.cpp:210-330` (enums),
  `700-1130` (types and attributes), `1644-1666` (discardable),
  `1690-1800` (the modules); the modules it writes, `Syntax/Idr.idr`,
  `Dialect/Idr.idr:1-60, 250-345`.
- Upstream: `M/include/mlir/Dialect/LLVMIR/LLVMTypes.td:153-280`,
  `M/lib/Dialect/LLVMIR/IR/LLVMTypes.cpp:469-536`,
  `M/lib/Dialect/LLVMIR/IR/TypeDetail.h:40-262`,
  `M/lib/Dialect/LLVMIR/IR/LLVMTypeSyntax.cpp:52-240` (identified,
  cyclic print and parse); `M/include/mlir/IR/OpImplementation.h:286-346,
  1485-1530` (`tryStartCyclic*`); `M/lib/IR/AsmPrinter.cpp:1356-1390`
  (aliases of recursive types); `M/lib/IR/SymbolTable.cpp:484-500`
  (symbol-use verification); `M/include/mlir/IR/Diagnostics.h:150-331`
  (metadata); `M/include/mlir/IR/EnumAttr.td:281-345`;
  `M/include/mlir/IR/AttrTypeSubElements.h:505-600`;
  `L/include/llvm/Support/xxhash.h:58-70`,
  `L/unittests/Support/xxhashTest.cpp:16-125`.

## Fixed decisions
- The data type: `Idr_DataType`, `MutableType`, custom storage
  `idr::detail::DataTypeStorage` defined in `lib/IR/Types.cpp`; key the
  name, mutable part the kind, the constructors (names, fields, `byName`,
  copied into the storage allocator), the instance, and a name index
  sorted by `StringAttr` for `getTag`. `setBody` checks C01 §5 before it
  mutates; the mutate succeeds again only for the same body, as
  `TypeDetail.h:242-257`. The key holds no type, so upstream's walker and
  replacer treat the type as an atom: its body is never a sub-element.
- The type definitions move from `Dialect.cpp` to `Types.cpp`
  (`GET_TYPEDEF_CLASSES`, `parseType`, `printType`, a `registerTypes()`
  the dialect's `initialize` calls, declared in `IdrBase.td`'s
  `extraClassDeclaration`), since the storage must be complete where the
  types are registered.
- The syntax is C01 §4, written by hand in `Types.cpp` with the cyclic
  print and parse; the alias is the shortened name (`Asm.cpp`), for the
  data type only.
- `BoxType` holds a `DataType` and prints it `qualified`.
- Constructor references: `FlatSymbolRefAttr` everywhere (C02 §1); the
  op verifiers that need the body move from `verifySymbolUses` to `verify`
  (`ConOp`, `FieldOp`, `DestOfOp`, `ReuseOp`, `TakeOp`, `MatchOp`,
  `ForceOp`), and `ConstantOp`'s constant check reads the type.
- `idr.con` gets `UnitAttr:$stack`; `ConOp::getEffects` reads `getStack()`.
- The dialect's `discardableAttrs` line goes; `verifyOperationAttribute`
  refuses every `idr.*` attribute; `verifyRegionArgAttribute` as today.
- `idr.func`: C02 §3's arguments exactly; `SymbolUserOpInterface`
  added; `verify()` demands a body and the root type of a public function;
  `verifySymbolUses()` of the public one runs `verify::program(module,
  root)`; `verifyRegions()` loses its external early return.
- `verify::program` keeps one root, gains C03's type rules over one
  `TypeGraph`, keeps containment and knots; the tag limit is the refusal
  `layout` through `refuse`.
- `Idr_Rule`, `Idr_RuleAttr` in `IdrBase.td`/`IdrAttrs.td` as C04 §1;
  `refuse`/`refusalHead`/`refusalRule` declared in `IdrDialect.h` after
  the generated attributes, defined in `Attrs.cpp`, which holds the one
  `"unsupported ("` literal.
- `Idr_SumKind` in `IdrBase.td` as C01 §2.
- `CloneAttr`, `KeyClosureAttr`, `KeyApplyAttr`, `KeyApplyFieldAttr`
  deleted; `KeyHoleAttr`, `KeyConAttr`, `SpecKeyAttr` kept; `KeyRaiseAttr`
  added (C02 §3).
- `ApplyOp::canonicalize` and `hasCanonicalizeMethod` on `idr.apply`
  deleted: its one rewrite reads a signature by module scan (§6's row),
  and after defunctionalization no apply is left for it.
- `idr.delay`: C02 §5; `Regions.cpp` drops the lambda and delay cases of
  `idr.yield`'s successors; `idr.yield`'s parents are the two matches and
  whatever C11 keeps.
- `DataRemap` (C01 §7) and the C21 helpers in `Symbols.h`/`Symbols.cpp`,
  on `llvm::xxh3_128bits`. Its leaf is asked with the place a type is held
  (owner, tag, field), since a field's sum is keyed by its anchor; each
  field has a replacer of its own. A constant's data type is remapped and
  never boxed.
- `#idr.con<!T, @C, ...>`: the attribute holds its `DataType` as its
  first parameter (C02 §1), the identity of the constructor with its name.
- A data type has no location: the `cycle` refusal that today stands at a
  declaration in the program's source stands at the first `idr.con` there
  of a type on the cycle (C03 §3).
- `layout::fit` keeps its signature; it decides every box with the
  measure counting a chosen type as one pointer, then applies one
  `DataRemap` of kind `box` to the module.
- `TypeGraph`'s nodes: data types in name order, then arrays as met;
  `boxed`, `inlined` per node.
- `Layouts`: cells for every data type `TypeGraph` marks `boxed`, keyed by
  (type, tag); sums by type; the memref components of C01 §9.
- The generator: identified types (C01 §4a); every enum's exported
  `Show`; `<enum>Spelling` as keyword or quoted string (C04 §4); a
  parameter of C++ type `::idr::DataType` is a type (`ty`, `t {0}`);
  `emitDiscardable` writes nothing when the dialect declares none.

## Inputs
- C05 (U02): `Idr_FlowOpInterface` in `INC/IR/IdrFlow.td`, the declaration
  block for `IdrDialect.h`, the table of ops that declare it, `verifyFlow`.
- C09 (U04): `KeyRaiseAttr` for `KeyApplyAttr`/`KeyApplyFieldAttr`;
  `Elimination` ending in the dispatch match (the coordinator's decision).
- C11 (U11): `#idr.world` (`WorldSpaceAttr`), the array ops that stay,
  the predicates of §1, the effects of §5, the deletions of §6 in these
  files.
- C14 (U08): `stack`'s invariants (§1); the in-place kind (§2).
- C16 (U10) §3 and C17 (U19) §2, §6: a memref's components.
- C06 (U02), C15 (U12): `DataRemap` of kinds `defun` and `buffers`, as C01
  §7 declares it.

## Outputs
- C01: `DataType`, `BoxType`, `Ctor`, `SumKind`, the syntax, `dataTypeOf`,
  `isBoxed`, `holdsReferences`, `DataRemap`, `TypeGraph`, `Layouts`,
  `Components`, `Holders`, `boxable`, `fit`; the generated Idris
  `SumKind`, `IdrCtor`, `IdrSum`, `DataType`, `BoxType`. Consumers: U02,
  U03, U04, U05, U08, U09, U10, U11, U14, U15, U16, U17.
- C02: constructor references and `getDataType`/`getTag`; `idr.con`
  `stack`; `idr.func`'s properties; `KeyRaiseAttr`; equal call effects;
  `idr.delay %value`; the flow trait on the ops of C05's table. Consumers: U02, U03, U04, U05, U08, U09, U10, U15, U16, U17.
- C03: `FuncOp::verify`, `FuncOp::verifySymbolUses`,
  `verify::program(module, root)`, the diagnostics of C03 §3. Consumers:
  U02, U08, U09, U10, U15, U17, U18.
- C04: `Idr_Rule`, `Idr_RuleAttr`, `refuse`, `refusalHead`,
  `refusalRule`, the generated `Rule` and `Show Rule`. Consumers: U06,
  U08, U10, U14, U17, U18.
- C21: `contentHash`, `contentName`, `ContentNames`, the vectors.
  Consumers: U02, U03, U04, U08, U09, U10, U14, U17, U18.

## Implement
- `IdrBase.td`: `Idr_SumKind`, `Idr_Rule`; the dialect's
  `extraClassDeclaration` gains `void registerTypes();`; the
  `discardableAttrs` line and its comment go; the attribute-verify comment
  says no `idr.*` attribute is accepted.
- `IdrTypes.td`: `Idr_DataType` and `Idr_BoxType` as C01 §2; the comment
  at `:19-24` about arrays of values stays.
- `IdrAttrs.td`: `ConAttr`'s `$ctor` a `FlatSymbolRefAttr`; `RuleAttr`;
  `CloneAttr`, `KeyClosureAttr` deleted; the instance comment no longer
  names a data declaration's op.
- `IdrOps.td`: `idr.func` as C02 §3 and C03 §1; `idr.call`'s comment;
  `Idr_PublicSymbol`, `Idr_DataOp`, `Idr_CtorOp` deleted; `idr.con`,
  `idr.field`, `idr.dest.of` as C02 §1-2, with `getDataType`/`getTag`.
- `IdrOwnershipOps.td`: `idr.reuse`, `idr.take` as C02 §1.
- `IdrMatchOps.td`: `idr.match`'s `getDataType`, `getCaseTag`;
  `idr.yield`'s parents.
- `IdrClosureOps.td`: `idr.lambda` deleted; `idr.delay` as C02 §5;
  `idr.apply` without its canonicalize method; comments without the
  region forms and the pass that outlined them.
- `IdrDialect.h`: `detail::DataTypeStorage`, `Ctor`; `PublicSymbol` and
  `evaluatedValue` deleted; `refuse`, `refusalHead`, `refusalRule`.
- `lib/IR/Types.cpp`: the storage, `get`, `getChecked`, `setBody` with
  C01 §5's checks (OpsData.cpp's memo and by_name rules move here as body
  rules), accessors, print and parse, `registerTypes`, `parseType`,
  `printType`, the existing verifiers.
- `lib/IR/Dialect.cpp`: keep attributes, enums, ops, materializer,
  canonicalizer; call `registerTypes()`.
- `lib/IR/Attrs.cpp`: `refusalHead`, `refuse`, `refusalRule`.
- `lib/IR/Symbols.cpp`, `Symbols.h`: C01 §3, §7; C21 §2.
- `lib/IR/OpsCon.cpp`, `OpsMatch.cpp`, `OpsOwnership.cpp`,
  `OpsClosures.cpp`, `OpsStrings.cpp`, `Constants.cpp`, `ConAttr.cpp`,
  `Asm.cpp`, `Canon/*`, `Verify/*`, `Layout/*`, `TypeGraph.cpp`,
  `Func/*`: read the type where they read a declaration; `idr.tag`'s fold
  and range with no scan; `ForceOp::getEffects` from the type's
  `byName`s with no scan; `listCons`/`listElement` callers read
  `getListElement` and `listCons` of a `BaseList` type, and refuse a list
  argument of another kind in the op's verifier.
- `Verify/Attributes.cpp`: the refusal of every `idr.*` attribute.
- `Verify/Program.cpp`, `Verify.h`: C03.
- `Verify/Knots.cpp`, `Layout/Layouts.cpp`: `refuse(…, Rule::Cycle)`,
  `refuse(…, Rule::Layout)`.
- `Layout/Components.cpp`: C01 §9's memref components.
- `TL/idris-mlir-tblgen.cpp`: C01 §4a, C04 §4.
- `IdrDialect.h`: C05's block and include; `mlir/Interfaces/ValueBoundsOpInterface.h`.
- No ODS of this lane names `Idr_FlowOpInterface`; `Func/Func.cpp`'s
  `verifyRegions` walks the body with `verifyFlow`.
- `IdrOwnershipOps.td`: `idr.own.adopt`, `idr.own.give` exactly as C14 §3;
  `Idr_CountedValueType` with `AnyMemRef`. `OpsOwnership.cpp`: their
  verifiers and the give's `consumedEffects`. `Ownership.h`,
  `Verify/Uses.cpp`, `Verify/Owned.cpp`, `Verify/OwnedRegions.cpp`: C01
  §9a, and the walk's checks of `memref.alloc`, a counted `memref.load`
  and a counted `memref.store`.
- `IdrAttrs.td`, `ConAttr.cpp`, `Constants.cpp`: `#idr.con`'s `data`.
- `Grades.cpp`: C11 §1's `isArray`; `isFieldType` takes a ranked tensor
  whose element is a field type at no grade, and a memref C16 §2 names.
- `Types.cpp`: `QType::verify` takes a ranked tensor at (one, plain).
- `IdrIOOps.td`, `OpsPlatform.cpp`, `Effects.cpp`: C11 §5's effects;
  `ioEffects` deleted; `performsIO` and `onlyAllocates` as C11 says.
- `Regions.cpp`, `IdrMatchOps.td`, `Verify/Uses.cpp`, `Ownership.h`,
  `Verify/OwnedRegions.cpp`, `Verify.h`: C11 §6's deletions.
- `IdrAttrs.td`: `KeyRaiseAttr` (C02 §3); `Symbols.h`: `Elimination`
  with `MatchOp dispatch` (C01 §3); `Canon/Feeds.cpp`'s sink reads it.
- `SRC/Syntax/Idr.idr`, `SRC/Dialect/Idr.idr`: what the new generator
  writes from the new ODS (no `program`/`stack` helpers, no `dataOp`,
  `ctorOp`, `lambdaOp`; `conOp`, `reuseOp`, `takeOp` with a flat
  constructor; `delayOp` with an operand; `funcOp` without `breakLast` and
  `clone`; `Rule`, `SumKind`, `IdrCtor`, `IdrSum`); fingerprints are the
  build's to rewrite.
- Failure paths: a body that breaks C01 §5 fails `setBody` with its
  error; a parser that meets a bodiless reference outside its own body
  fails; an op verifier that meets a type without a body fails; the
  module rules fail with C03 §3's words.

## Delete
- `IdrOps.td:105-176` (`idr.data`, `idr.ctor`, `Idr_PublicSymbol`),
  `lib/IR/OpsData.cpp`, `PublicSymbol` in `IdrDialect.h`.
- `getSumName`, `lookupData`, `lookupCtor`, `declarationOf`,
  `constructorOf`, `listCons`, `listElement`, `isMemo(DataOp)`, the
  callback of `holdsReferences`.
- `idr.stack` and `idr.program` as discardable attributes, their helpers'
  every use in `lib/IR`, `verify::program`'s entry through
  `verifyOperationAttribute`.
- `break_last` and `clone` on `idr.func`; the self-referencing
  `CloneAttr`, `KeyClosureAttr`; `FuncOp::verify`'s clone-key check.
- `idr.lambda`, the region `idr.delay`, `EvaluateDelay`,
  `evaluatedValue`, the lambda/delay cases of `Regions.cpp` and of
  `idr.yield`'s parents.
- `ApplyOp::canonicalize` and its module scan (`OpsClosures.cpp:303-346`),
  with `canon::closureOf` (`Canon/ClosureOf.cpp`) and `canon::materialize`
  (`Canon/Captures.cpp:19-25`), which only it called.
- The custom directive `FieldTypes` (`Ops.cpp:123-142`), `idr.ctor`'s.
- `KeyApplyAttr`, `KeyApplyFieldAttr`; `Elimination`'s `ApplyOp apply`.
- `idr::ioEffects` (`Effects.cpp:58-65`); `isArrayLoop`, `walkArrayLoop`,
  the array-loop cases of `Regions.cpp`, `Verify/Uses.cpp:106-116`,
  `Verify/OwnedRegions.cpp:55-96`.
- The module-scanning declaration lookups in `lib/IR`: `OpsClosures.cpp:274,
  326`, `OpsCon.cpp:233, 250`, `Canon/MatchPatterns.cpp:114`,
  `Canon/MoveOut.cpp:66`, `Canon/Eta.cpp:83`, `Verify/Owned.cpp:56`, and
  the lookup-dodging branches `Canon/MatchPatterns.cpp:101-121`,
  `Canon/Eta.cpp:43-87`.
- `Verify/Program.cpp:46-90` (every sum or box names a declaration of
  its kind), `layout::fit`'s in-place `setBox` and declaration retype.
- The containment test on a call's effects (`Func/Call.cpp:64-73`).
- `compiler/src/IdrisMLIR/Rule.idr`; `CompileBudget` and the
  `compile-time budget` phrase.
- Every `"unsupported ("` literal in `lib/IR` but `Attrs.cpp`'s.

## NOT TO DO
- No `IdrFlow.td`, `Flow.h`, `Flow.cpp`, flow trait in ODS or flow method
  bodies (U02, C05).
- No array op, no tensor lowering, no `idr.tie_shape` (U11); no change of
  `isArray` beyond what C11 states.
- No pass, no pipeline line, no `Passes.td` entry (U03-U12, U06).
- No edit of an Emit, MLIR, Frontend, Registry, ipkg or test file, even
  where it no longer typechecks against the new modules: report it.
- No `CMakeLists.txt` edit: list the coordinator's lines.
- No `root` property on `idr.func` (D28: publicity is the root).
- No `box` flag in the data type's body; no `role` beside the kind.
- No second spelling of a constructor reference, no `@T::@C` left.
- No discardable attribute of any kind, no `idr.*` attribute accepted.
- No bytecode dialect interface for the types (D36: assembly).
- No running of `tools/dialects.sh generate`, make, cmake or ninja.

## Tempting partial solutions
- Keeping `idr.data` as the body's holder and making the type point at
  it: a pattern still reads the module. Rejected by the spec check that no
  `declarationOf`, `constructorOf` or `lookupNearestSymbolFrom` on a data
  type is left in `lib/`.
- A `box` unit in the body "for the frontend": boxing said twice, which
  `Verify/Program.cpp:59-63` checks today. Rejected by C01 §2.
- Mutating a body after it is set (a second `setBody` with other fields,
  `setBox` on a type): the storage refuses it; a changed body is a
  `DataRemap`.
- Counter suffixes for remade types (`T.1`, `getNewIdentified`'s rename):
  creation order reaches output. Rejected by C21.
- Running the module rules from `FuncOp::verify()`: a function pass's
  verifier then walks siblings another thread rewrites. Rejected by C03 §2.
- The rule as a printed first argument of the diagnostic: every reject
  test's text changes. Rejected by C04 §2.
- Leaving `Rule.idr` and generating a copy: two copies of one concept.
  Rejected by the spec check that the file does not exist.
- Validating `by_name` or memo shape in each op that meets it: the body
  is checked once, by `setBody`.

## Acceptance
- `python3 proposals/0004-compile-time/check-units.py` on every `.cpp`
  under `foreign/idr/lib/IR` (but `OpsArrays.cpp`) and
  `foreign/idr/tools/idris-mlir-tblgen.cpp` reports no failure caused by
  this lane's files; failures caused by a sibling's file (a consumer of
  the deleted API, `OpsArrays.cpp`, the flow interface) are listed with
  the contract that declares what they need.
- A search of `foreign/idr/lib/IR` and `foreign/idr/include/idr/IR`
  finds no `DataOp`, `CtorOp`, `declarationOf`, `constructorOf`,
  `lookupData`, `lookupCtor`, `getSumName`, `StackAttrHelper`,
  `ProgramAttrHelper`, `getBreakLast`, `CloneAttr`, `LambdaOp`,
  `evaluatedValue`, `getLeafReference` on a constructor, or
  `lookupNearestSymbolFrom` on a data type; one `"unsupported ("` literal,
  in `Attrs.cpp`; `discardableAttrs` absent.
- `compiler/src/IdrisMLIR/Rule.idr` does not exist; `Syntax/Idr.idr`
  exports `Rule`, `Show Rule`, `SumKind`, `IdrCtor`, `IdrSum`.
- The private Idris typecheck of `compiler/idris-mlir.ipkg` passes for
  `IdrisMLIR.Syntax.Idr` and `IdrisMLIR.Dialect.Idr`; modules of U14 and
  U15 that fail against them are listed as their seams.
- NEEDS-ACCEPTANCE on the owner's machine: `make typecheck` regenerates
  the two modules and `tools/dialects.sh check` reports them current;
  `tests/idr/verify/data`, `asm/aliases`, `syntax/*` (U17) parse and
  round-trip the C01 §4 syntax; the C03 §3 diagnostics appear verbatim.

## Stop and return
Return when every Mandatory outcome is written and check-units shows no
failure of this lane's own. Report, without stopping: C05's op list if
absent (outcome 9 open); C11's array ops if absent; every consumer file
that breaks against C01-C04 (they are their lanes'); the coordinator's
build lines (`OpsData.cpp` out of `lib/IR/CMakeLists.txt`); the fact that
the generated modules' fingerprints are the build's.
