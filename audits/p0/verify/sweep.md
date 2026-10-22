<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 verification swarm: the C++ rule sweep

*A read-only sweep of `foreign/idr` and `runtime/`, 2026-10-22. HEAD at start
`c6ccc87f`, at finish `a67e622c` (06:58Z); the working tree read, uncommitted
included (at finish, one modified C++ file: `foreign/idr/lib/IR/OpsChecks.cpp`,
no hit). Every rule was rerun at `a67e622c` and the hits below are at that
tree. Nothing was built or run.*

Rules: AGENTS.md's C++ section; P0 C52 (one exhaustive `match`, no
accessors), C200 (no `match` case takes every type), C184 (no header under
`lib/`), D91 (no `assert`); `tests/file-size/run` (400 lines, ratchet in
`tests/file-size/allowed`). Lanes are by longest prefix in
`audits/p0/verify/ownership.json`; every swept file has an owner (no
unowned file). Grounds: *measured* (a `grep`, `find` or `wc` over the tree,
or a scan that strips comments and strings and walks a `match(` call's
argument list); the classifications under rules 1, 3, 7 and 9 are *read*
(each hit's context opened).

Scope: every `.cpp`, `.h`, `.inc` and `.c` under `foreign/idr` and
`runtime/`. `foreign/idr/include/idr/IR/Generated/` (INT, generator L03) was
swept too and has no hit under any rule.

## 1. Accessors over our own sums (C52)

No `std::get_if`, `std::holds_alternative`, `std::visit`, `llvm::TypeSwitch`
or `makeVisitor` outside the fold itself. The hits below read an
alternative by another spelling, which C52's ban on accessors covers.

**L07**: `std::get<Alternative>` on a walk stack's `std::variant` frame
- `foreign/idr/lib/Transforms/Counting/PlacementWalk.cpp:205` (`std::get<BlockWalk>`)
- `foreign/idr/lib/Transforms/Counting/PlacementWalk.cpp:228` (`std::get<OpWalk>`)
- `foreign/idr/lib/Transforms/Counting/ReuseAssign.cpp:198` (`std::get<Path>`)
- `foreign/idr/lib/Transforms/Counting/ReuseDemand.cpp:77` (`std::get<BlockAt>`)
- `foreign/idr/lib/Transforms/Counting/ReuseDemand.cpp:94` (`std::get<OpAt>`)

**L10**: `index() != 0` on `Making = std::variant<std::monostate, Hole, Outer, Part>` (`include/idr/Transforms/Tail/Trmc.h:44`), a `holds_alternative` by index
- `foreign/idr/lib/Transforms/Tail/TrmcRewrite.cpp:92`
- `foreign/idr/lib/Transforms/Tail/TrmcRewrite.cpp:250`

**L15**: `llvm::cast<mlir::Region *>` on the `Place` PointerUnion (`include/idr/Testing/FlowCases.h:26`), which C52 says the fold reads
- `foreign/idr/unittests/Flow.cpp:251`
- `foreign/idr/unittests/Flow.cpp:259`

Excluded, and why:
- The fold's own read: `foreign/idr/include/idr/Support/Match.h:109`
  (`std::get_if<I>` after the index test), and that header's comments
  (lines 6, 13, 14).
- `llvm::zip` / `zip_equal` tuples read by `std::get<N>`:
  `lib/IR/Func/Call.cpp:244-246, 308-310`; `lib/IR/Counting/Takes.cpp:237-239`;
  `lib/IR/Families/Directives.cpp:42`.
- Other tuples, not sums: storage `KeyTy` tuples
  (`include/idr/IR/Families/FamilyStorage.h:125-174`, `lib/IR/Types.cpp:108,112`);
  the `reads(am)` analysis tuples (`lib/Analysis/Ownership/Borrows.cpp:379-381`,
  `Exclusivity.cpp:39-40`, `lib/Analysis/Labels.cpp:343`, `lib/Analysis/Ranges.cpp:178`);
  the folder's argument tuple (`include/idr/IR/Fold.h:183,185`);
  `Ctor = std::tuple<...>` (`lib/Transforms/Optimize/CaptureDrops.cpp:168`);
  the unit test's rows (`unittests/Calls.cpp:132-280`).
- TableGen's open `Init`/`Record` classes, read with LLVM casting in
  `foreign/idr/tools/idris-mlir-tblgen.cpp:251, 334, 352, 945, 1236, 1596, 1809`
  (`DefInit`, and `AttributeSelfTypeParameter` at 1236).
- `TypeID::get<Ops>` (`lib/Analysis/Constants.cpp:26`,
  `lib/Transforms/EGraph/Rules.cpp:53-54`) is not `std::get`.

## 2. A `match` case that takes every type (C200)

None. 349 `match(` calls scanned (lambdas at the call's top level, plain
`auto`, `auto *`, `auto &`, `auto &&`, packs, and unconstrained template
lambdas; generic lambdas held in a variable and passed in were checked
too). The only two are the refusal test's witnesses, which expect the
fold's `static_assert` and are excluded:
`foreign/idr/unittests/Refusals.cpp:165` (`const auto &`) and
`foreign/idr/unittests/Refusals.cpp:176` (`auto *`).

## 3. `llvm::function_ref` / `std::function` with no upstream API requiring it

None. No `std::function` or `unique_function` anywhere. The 23
`function_ref` lines are all, *read*:
- ODS's generated `verify(function_ref<InFlightDiagnostic()>, ...)`
  signatures: `lib/IR/Func/GivenBack.cpp:170`, `LivesIn.cpp:179`,
  `Values.cpp:91`; `lib/IR/ConAttr.cpp:253`; `lib/IR/Families/DataNormal.cpp:122`;
  `lib/IR/Families/FamilyVerify.cpp:36` (the alias for `FamilyAttr::verify`);
  `lib/IR/Grades.cpp:108`; `lib/IR/Counting/Types.cpp:38,55`;
  `lib/IR/Tail/Destinations.cpp:32`; `lib/IR/OpsBigs.cpp:256`.
- Upstream hooks: properties' `convertFromAttribute`
  (`lib/IR/Func/Rows.cpp:55`); bufferization's
  `verifyCompatibleBufferType` (`lib/Transforms/Bufferize/Linear.cpp:40`);
  the sub-element walk (`lib/IR/Families/SubElements.cpp:130-131`, its
  comment says so).
- Forwarding the `emitError` an upstream signature handed in:
  `lib/IR/ConAttr.cpp:108` (`verifyNumeral`), `:126` (`verifyShape`), `:276`
  (`getNormalized`); `lib/IR/Families/DataNormal.cpp:90` (`checkParts`),
  `:147` (`getNormalized`). The two `getNormalized` builders are ours, in
  `getChecked`'s form, and run `verify`'s check; a template parameter would
  erase one call later. Noted, not counted.
- A comment: `include/idr/Support/Actions.h:59`.

## 4. `assert(` (D91)

None, and no `<cassert>`. Not counted, noted: five `llvm_unreachable`
(`lib/IR/Layout/Layouts.cpp:373`, `include/idr/Transforms/Counting/Facts.h:61`,
`lib/Driver/Main.cpp:56`, `lib/Driver/Options.cpp:330`,
`lib/Driver/Outcome.cpp:62`), each after an exhaustive switch.

## 5. A header under `lib/` (C184)

None: no `.h`, `.inc`, `.hpp` or `.def` under any `lib/` directory of
`foreign/idr` (`runtime/` has no `lib/`). The one hand-written `.inc`,
`foreign/idr/include/idr/Transforms/ExpectProperties.inc` (L19), is under
`include/`, where C184 put it.

## 6. Units over 400 lines

None unlisted, none listed and under. `tests/file-size/allowed` lists one
unit, `foreign/idr/tools/idris-mlir-tblgen.cpp`, at 1954 lines. The next
largest are at exactly 400 (`lib/IR/Verify/Linearity.cpp`,
`lib/IR/OpsClosures.cpp`, `lib/Driver/Artifacts.cpp`,
`lib/Analysis/Ownership/Borrows.cpp`, `include/idr/Transforms/Defunctionalize.h`);
`runtime/idris_rt.h` (418) is exempt by the rule.

## 7. Maps keyed by `Value`, `Operation *`, `Block *`

No map keyed by `Block *` or `Region *`.

Per-node state:
- **L09** `foreign/idr/lib/Transforms/Joins/IdenticalRegions.cpp:42`
  `DenseMap<Value, Value> same`: one comparison's value correspondence, fed
  to upstream's `OperationEquivalence` callbacks; its comment says so.
- **L18** `foreign/idr/lib/Transforms/Deduplicate/Deduplicate.cpp:122`
  `DenseMap<Value, Value> equivalent`: the same pattern, for
  `isRegionEquivalentTo`.
- **L19** `foreign/idr/lib/Transforms/Expect/ConstantStack.cpp:61`
  `DenseMap<Operation *, SmallVector<Reference>> read`: each function's
  references, cached by pointer.

Per-body numbering maps (sanctioned; listed, not counted as hits):
- **L08** `foreign/idr/lib/Transforms/InPlace/Unique.cpp:218`;
  `foreign/idr/lib/Transforms/InPlace/UniqueResults.cpp:207`.
- **L12** `foreign/idr/include/idr/Transforms/BufferizeModels.h:79`;
  `foreign/idr/lib/Transforms/StructureLoops/Linalg.cpp:41` (keyed by
  `(Value, AffineMap)`, numbering a loop's distinct inputs).
- **L14** `foreign/idr/include/idr/Analysis/Solver/Extraction.h:100`;
  `foreign/idr/include/idr/Analysis/Solver/LabelPoints.h:110`;
  `foreign/idr/include/idr/Analysis/Solver/LabelPoints.h:161` (`OpOperand *`
  to `enum class Sink`); `foreign/idr/lib/Transforms/EGraph/Simplify.cpp:107`
  (`Operation *` to `Root`, the erased bit in a `BitSet<Root>`).
- **L18** `foreign/idr/lib/Transforms/Deduplicate/Deduplicate.cpp:190`.
- **L19** `foreign/idr/include/idr/Transforms/Expect.h:238`.

7s. Pointer-keyed sets (per-node membership; the same AGENTS.md rule read
as "and the like", counted in their own column):
- **L12** `foreign/idr/lib/IR/OpsArrayFusion.cpp:120`;
  `foreign/idr/include/idr/Transforms/Narrow.h:301` and
  `foreign/idr/lib/Transforms/Narrow/Widths.cpp:95, 96` (`accumulations`,
  returned and queried by callers); `Widths.cpp:105` (worklist),
  `:115`, `:144`; `foreign/idr/lib/Transforms/Narrow/Copy.cpp:95`.
- **L18** `foreign/idr/lib/Transforms/Optimize/Results.cpp:100`;
  `foreign/idr/lib/Transforms/Specialize/Consumer.cpp:107, 109`;
  `foreign/idr/lib/Transforms/Specialize/Patterns.cpp:147`;
  `foreign/idr/lib/Transforms/Specialize/Requests.cpp:38` (a listener's set
  of erased ops, keyed by dead pointers).
- **L19** `foreign/idr/include/idr/Transforms/Expect.h:202`;
  `foreign/idr/lib/Transforms/Expect/ConstantStack.cpp:81`;
  `foreign/idr/lib/Transforms/Expect/Cycles.cpp:19`;
  `foreign/idr/lib/Transforms/Expect/NarrowedLanes.cpp:27`;
  `foreign/idr/lib/Transforms/Expect/Reached.cpp:28`.

Excluded: `SetVector<Value>` for `getUsedValuesDefinedAbove`, whose
upstream signature takes it (`include/idr/Transforms/Narrow.h:278, 318`,
`lib/Transforms/Narrow/Widths.cpp:56-57`, `Copy.cpp:30`, `Lanes.cpp:176`);
`IRMapping` (upstream's clone map, 28 uses).

## 8. `isa<A, B, ...>` over two or more of our ops

- **L12** `foreign/idr/lib/Transforms/Narrow/Narrow.cpp:142`
  `isa<BigSmallOp, BigFromSIntOp, BigFromUIntOp>(op)`, the head of a
  ladder that goes on with single `isa<BigToIntOp>`, `isa<ub::PoisonOp>`
  and `isa<ConstantOp>` (lines 144-148).

Scanned per statement, so `isa<A>(x) || isa<B>(x)` chains count too; the
only chains mix one op of ours with `ModuleOp`
(`lib/Transforms/Contracts/Contracts.cpp:75`,
`lib/Transforms/Expect/Stages.cpp:33`). Lists of our types (`isa<FnType,
LazyType>`, `isa<BigType, NatType>`, `isa<CellType, TokenType>`) and of
interfaces or upstream ops are outside the rule and not listed.

## 9. A `bool` that encodes a choice

Judgment; clear cases only. Locals, truth values (`holds`), outcomes
(`failed`) and run-time data (`setEnvironment`'s `overwrite`, from the
program) are left out.

- **L03** `foreign/idr/tools/idris-mlir-tblgen.cpp:105` `camel(name, bool
  upper)` (upper or lower camel case); `:1232`, `:1276`, `:1313`, `:1389`
  `bool isType` (type or attribute; set at `:1370` by a string compare of
  the record's kind); `:1092` `Piece::isLiteral` (literal or expression);
  `:1516` `Atom::one` and `:1665` `PartsPiece::one` (one `Part` or a `List
  Part`); `:1614` `IdrisType::closed` (a word or an applied type).
- **L04** `foreign/idr/include/idr/IR/Layout.h:351` and
  `foreign/idr/lib/IR/Layout/Layouts.cpp:304` `cellOf(..., bool grouped,
  ...)`, one parameter: tag in an object slot or not, passed as
  `/*grouped=*/false` at `Layouts.cpp:276`.
- **L08** `foreign/idr/include/idr/Analysis/Ownership/Local.h:253`
  `originOf(bool fresh, ...)`, which maps `true` straight to
  `Origin::Fresh`.
- **L11** `foreign/idr/include/idr/Driver/Artifacts.h:59`
  `FrontendArgs::noPrelude` (Prelude imported implicitly or not).
- **L19** `foreign/idr/lib/Transforms/Expect/ConstantStack.cpp:26`
  `Reference::tailCall`, a guaranteed tail call or not, where `TailKind`
  exists and a closure or address reference also lands on `false`.

## Counts

Hits per lane per rule. R7 counts per-node-state maps only; R7s counts
pointer-keyed sets; sanctioned numbering maps are in their own column and
in no total.

| Lane | R1 | R2 | R3 | R4 | R5 | R6 | R7 | R7s | R8 | R9 | Total | Numbering (sanctioned) |
|------|----|----|----|----|----|----|----|-----|----|----|-------|------------------------|
| L03  |    |    |    |    |    |    |    |     |    | 9  | 9     |                        |
| L04  |    |    |    |    |    |    |    |     |    | 2  | 2     |                        |
| L07  | 5  |    |    |    |    |    |    |     |    |    | 5     |                        |
| L08  |    |    |    |    |    |    |    |     |    | 1  | 1     | 2                      |
| L09  |    |    |    |    |    |    | 1  |     |    |    | 1     |                        |
| L10  | 2  |    |    |    |    |    |    |     |    |    | 2     |                        |
| L11  |    |    |    |    |    |    |    |     |    | 1  | 1     |                        |
| L12  |    |    |    |    |    |    |    | 8   | 1  |    | 9     | 2                      |
| L14  |    |    |    |    |    |    |    |     |    |    | 0     | 4                      |
| L15  | 2  |    |    |    |    |    |    |     |    |    | 2     |                        |
| L18  |    |    |    |    |    |    | 1  | 5   |    |    | 6     | 1                      |
| L19  |    |    |    |    |    |    | 1  | 5   |    | 1  | 7     | 1                      |
| All  | 9  | 0  | 0  | 0  | 0  | 0  | 3  | 18  | 1  | 14 | 45    | 10                     |

Lanes not in the table (INT, L01, L02, L05, L13, L21) have no hit; L06,
L16, L17 and L20 own no swept file. Without the sets, the order is L03 (9),
L07 (5), then L04, L10, L15 and L19 (2 each).
