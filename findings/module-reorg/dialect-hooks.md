# R1 lane: the dialect's hooks

Read `README.md` beside this file first.

The dialect's definitions stay plain units for good: what TableGen
generates (`IdrDialect.cc.inc`, `IdrOps.cc.inc`, ...) and the hooks that
define its members (an op's `verify`, `fold`, `canonicalize`, parsers and
printers, interface methods), and the free functions `idr/Idr.h` declares
in the global module (`isWorld`, `unrestricted`, `lookupCtor`, ...), which
the generated code and the traits in `Idr.h` call. Your job is to split
them to one concept per file and to make every helper that is not a member
or a global-module declaration a module.

## Files

| File | Lines | What it holds |
|---|---|---|
| lib/Dialect/Dialect.cc | 951 | the dialect's initialization, inliner interface, constant materialization, the generated dialect/enum/attr/type definitions (`.cc.inc`), FnType/QType/DestType/BigAttr/ConAttr hooks, type parsing and printing, every grade helper of Idr.h (`gradeOf` ... `heldAs`, `quantityOf`, `unrestricted`, `throughLinear`, `fieldReadOnce`), symbol lookups (`getSumName`, `lookupData`, `lookupCtor` x2), `eliminationAt`, the program verifier (`verifyProgram`, linearity), `onlyAllocates`, `performsIO`, `verifyDiscardableAttrs`, `verifyOperationAttribute`, `verifyRegionArgAttribute` |
| lib/Dialect/Ops.cc | 1534 | `knownNonZero`, `knownFinite`, `knownNonEmpty`; custom parsers and printers for the ops' assembly formats; the generated op definitions (`IdrInterfaces.cc.inc`, `IdrOps.cc.inc`); every op's hooks (data, constant, con, field, lin, tag, match, match_lit, closure, crash, bytes, strings, dest, arrays) |
| lib/Dialect/BigRanges.cc | 164 | `inferResultRanges` of the big and natural ops, `BigFromIntOp::verify`; already imports idr.ranges |
| lib/Dialect/Sharing.cc, Sharing.h | 59, 12 | `addSharingInterfaces` (the OpAsm interface that names shared values) |
| lib/Dialect/Canonicalize/*.cc, Matches.h | 77-158 each, 47 | canonicalization hooks (`ApplyOp::canonicalize`, `ConOp::fold`, `FieldOp::canonicalize`, `getCanonicalizationPatterns` of match, match_lit, put_str, put_list, str_head) and their helpers in `idr::canon` (`rebuildMatch`, `feeds`, `meetsInSomeRegion`, `addCaseOfCase`, `addMerge`, `addSink`) |
| lib/Dialect/Canonicalize.td | 58 | DRR patterns (IdrCanonicalize.inc), used by Canonicalize/Strings.cc |
| lib/Registration.cc | 77 | `registerIdr`, `pipelineSteps`, `registerIdrPipeline` (declared in Idr.h) |
| lib/Dialect/Dialect.cppm | 228 | idr.dialect, R0's; leave it as it is unless TableGen grows a name |

## Proposed map

Plain units (global module), one concept each, in lib/Dialect:

- `Dialect/Initialize.cc` (IdrDialect::initialize, the inliner interface,
  ReadForwardedOnce, the generated dialect definitions), `Dialect/Constants.cc`
  (materializeConstant), `Dialect/Patterns.cc` (getCanonicalizationPatterns).
- `Types/FnType.cc`, `Types/QType.cc` (with printGrade/parseGrade),
  `Types/DestType.cc`, `Types/Syntax.cc` (parseType/printType),
  `Attrs/BigAttr.cc`, `Attrs/ConAttr.cc`, plus one unit with the generated
  enum/attr/type definitions.
- `Grades/<Name>.cc`, one per helper: GradeOf, Graded, Linear, Erased,
  World, IsWorld, IsErased, IsLinear, IsOwned, Owned, View, AtQuantity,
  IsExclusive, Times, FieldType, HeldAs, QuantityOf, Unrestricted,
  ThroughLinear, FieldReadOnce, IsFieldType, IsArray.
- `Symbols/GetSumName.cc`, `LookupData.cc`, `LookupCtor.cc` (both
  overloads: one concept), `ListCons.cc`, `EliminationAt.cc`.
- `Verify/Program.cc`, `Verify/Linearity.cc`, `Verify/DiscardableAttrs.cc`,
  `Verify/Attributes.cc` (verifyOperationAttribute,
  verifyRegionArgAttribute); `Effects/OnlyAllocates.cc`,
  `Effects/PerformsIO.cc`; `Crashes/KnownNonZero.cc`, `KnownFinite.cc`,
  `KnownNonEmpty.cc`.
- `Ops/<Family>.cc`, one per op family as listed above, each under 400
  lines; `Ranges/<Family>.cc` from BigRanges.cc likewise if you split it.
- `Registration/RegisterIdr.cc`, `PipelineSteps.cc`,
  `RegisterIdrPipeline.cc` (move lib/Registration.cc here).

Modules for what is neither a member nor declared in Idr.h:

- `idr.canon` (namespace idr::canon, lib/Canon): Matches.h's `rebuildMatch`
  and the helpers the canonicalization hooks share (feeds,
  meetsInSomeRegion, addCaseOfCase, addMerge, addSink), each in its unit,
  the pattern structs with the function that adds them. The hooks
  (`MatchOp::getCanonicalizationPatterns`, ...) stay plain and import it.
  (`lib/Canonicalize` is another lane's: the idr-canonicalize pass.)
- `idr.sharing` (namespace idr::sharing): `addSharingInterfaces` and its
  OpAsm interface. Imports: idr.mlir, idr.dialect.
- The custom parsers and printers of Ops.cc and the op helpers that are not
  members (`idrisDivMod`, `foldDivision`, `verifyMatchRegions`,
  `takenRegion`, ...) may become a module (`idr.syntax`, `idr.ops`), with
  one caveat below.

## Special

- The generated `IdrOps.cc.inc` calls the custom directives' parse/print
  functions and the hooks by name, so the unit that includes it must
  declare them before the include. An import must come after the last
  include, so they cannot come from a module there: keep the generated
  include in one unit (`Ops/Generated.cc`) that declares (or defines) the
  custom directive functions, and put every hook body elsewhere.
- Including a generated `.cc.inc` after an `import` is the clang #61465
  risk (MODULES.md): every generated include comes before the unit's
  imports.
- Dialect.cc includes `Ownership/Ownership.h` (for `verifyOwned`,
  `stageAttr`, `ownedStage`). The ownership lane replaces that one line
  with `import idr.ownership;` and deletes its allowed line; you leave the
  line (and its allowed entry) alone. If you split Dialect.cc, keep that
  include in the unit that defines `verifyOperationAttribute` and say so in
  your report, so that the ownership lane's edit lands.
- `idr/Idr.h` and `IdrOps.td` are yours to keep as they are: an edit
  recompiles everything and every lane. Change them only if a split needs
  it, and say so.

## Allowed lines that are yours (delete them as you go)

no-local-headers:

    foreign/idr/lib/Dialect/Canonicalize/CaseOfCase.cc: Dialect/Canonicalize/Matches.h
    foreign/idr/lib/Dialect/Canonicalize/Matches.cc: Dialect/Canonicalize/Matches.h
    foreign/idr/lib/Dialect/Canonicalize/Meet.cc: Dialect/Canonicalize/Matches.h
    foreign/idr/lib/Dialect/Canonicalize/Merge.cc: Dialect/Canonicalize/Matches.h
    foreign/idr/lib/Dialect/Canonicalize/Sink.cc: Dialect/Canonicalize/Matches.h
    foreign/idr/lib/Dialect/Dialect.cc: Dialect/Sharing.h
    foreign/idr/lib/Dialect/Sharing.cc: Dialect/Sharing.h

(`foreign/idr/lib/Dialect/Dialect.cc: Ownership/Ownership.h` is the
ownership lane's to delete.)

file-size:

    foreign/idr/lib/Dialect/Dialect.cc
    foreign/idr/lib/Dialect/Ops.cc

## Imports and links

New modules import idr.mlir and idr.dialect (idr.ranges for range helpers);
the hooks stay in `idr_dialect`, which links your new libraries.

## Do not touch

Any other lane's directory; lib/Facts, lib/Graph, lib/Layout, lib/Ranges,
lib/Support, lib/Target (R0's modules: ask before changing an interface);
lib/Canonicalize (the stack/inline/expect/canonicalize/fold lane).
