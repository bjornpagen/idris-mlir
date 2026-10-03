# R1 lane: ownership (`idr.ownership`)

Read `README.md` beside this file first.

lib/Ownership is the owned stage: idr-rc's passes (borrow inference,
signatures, counts, exclusivity, reset/reuse), the owned stage's verifier,
and the hooks of the ownership ops. Make it the module `idr.ownership`
(namespace `idr::ownership`, as today), library `idr_ownership`.

## Files

| File | Lines | What it holds |
|---|---|---|
| Ownership.h | 169 | `stageAttr`, `ownedStage`; `isStatic`, `reachesOnlyAtoms`; class `Counting`; `readFrom`, `isArrayLoop`, `usedAfter`, `isBorrowed`, `Use`, `useOf`, `callee`, `usersIn`, `whereDies`, `takeAt`, `keepsCountedField`, `onlyReads`, `takeAtEntry`, `takeFields`; `inferBorrows`, `ownSignatures`, `insertCounts`, `inferExclusive`, `verifyOwned` |
| Counting.cc | 124 | `Counting::counted`, `readFrom`, `isStatic`, `isArrayLoop`, `usedAfter`, `isBorrowed`, `callee`, `useOf` |
| Take.cc | 168 | `usersIn`, `whereDies`, `keepsCountedField`, `takeAt`, `onlyReads`, `takeAtEntry`, `takeFields` |
| Borrow.cc | 221 | class Inference (anonymous); `inferBorrows`, `ownSignatures`; imports idr.graph |
| Counts.cc | 601 | classes Class, Changes, Counter (anonymous); `insertCounts` |
| Exclusive.cc | 538 | Sharing, Cells, CellsLattice, NoConstants, ExclusiveAnalysis (a dataflow analysis), Commit, Specialize; `reachesOnlyAtoms`, `inferExclusive` |
| ResetReuse.cc | 152 | class Reuser; `insertResetReuse`; imports idr.layout |
| Verify.cc | 625 | class Checker; `verifyOwned`; imports idr.layout |
| Rc.cc | 75 | idr-rc's glue (GEN_PASS_DEF_IDRRC) and the pipeline it runs; R0 declared `insertResetReuse` here, since a plain header cannot forward-declare `idr::layout::Layouts` |
| Ops.cc | 116 | hooks of the ownership ops (`DupOp::verify`, `DropOp::verify`, `ReuseOp::verify`/`verifySymbolUses`, `TakeOp::verify`/`getToken`/`getFields`/`verifySymbolUses`) and their helpers (`ctorOf`, `movedField`, `movesAs`, `inOwnedStage`) |

## Proposed map

- `Ownership.cppm`: `export import` of the partitions.
- `:stage` (Stage.cppm): `stageAttr`, `ownedStage` (inline constexpr data).
- `:counting` (Counting.cppm): `Counting`, `isStatic`, `readFrom`,
  `isArrayLoop`, `usedAfter`, `isBorrowed`, `Use`, `useOf`, `callee`;
  units `Counting/Counting.cc` (the members: constructor, `counted`,
  `tracked`), `Counting/ReadFrom.cc`, `IsStatic.cc`, `IsArrayLoop.cc`,
  `UsedAfter.cc`, `IsBorrowed.cc`, `UseOf.cc`, `Callee.cc`.
- `:take` (Take.cppm): units `Take/UsersIn.cc`, `WhereDies.cc`, `TakeAt.cc`,
  `KeepsCountedField.cc`, `OnlyReads.cc`, `TakeAtEntry.cc`,
  `TakeFields.cc` (the shared private helpers `fromPoint`, `eachField` in
  the partition outside `export`, each in its unit).
- `:borrow`: `Borrow/InferBorrows.cc`, `Borrow/OwnSignatures.cc`, the
  Inference class declared in the partition (module linkage) with its
  members in `Borrow/Inference.cc`.
- `:counts`: `Counts/InsertCounts.cc`; Counter is 550 lines of one class:
  split it by concern (its classes, its walk, its insertion) into types of
  their own, each under 400 lines.
- `:exclusive`: one unit per type (the lattice, the analysis, Commit,
  Specialize) and `Exclusive/InferExclusive.cc`,
  `Exclusive/ReachesOnlyAtoms.cc`. ExclusiveAnalysis is a dataflow
  analysis: if it uses MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID,
  declare `static mlir::TypeID resolveTypeID();` and define it in a unit
  (MODULES.md, lib/Support/Actions).
- `:reuse`: `Reuse/InsertResetReuse.cc` and Reuser; then delete R0's
  declaration in Rc.cc.
- `:verify`: Checker (625 lines) split by what it checks; `verifyOwned` in
  `Verify/VerifyOwned.cc`.
- Glue: `Pass.cc` (from Rc.cc: the base, its options and statistics, and a
  call into the module, which runs the passes in order). Hooks:
  `Ops/<Op>.cc`, plain, importing the module for the helpers, which move
  into a partition.

## Imports and links

idr.mlir, idr.dialect, idr.graph (Borrow), idr.layout (ResetReuse, Verify,
the pass). `idr_ownership`, linked from `idr_dialect`.

## Cross-lane edits that are yours (one line each, nothing else)

Other areas include Ownership.h for a few names:

- `lib/Dialect/Dialect.cc`: `stageAttr`, `ownedStage`, `verifyOwned`;
- `lib/Expect/Counting.cc`: `readFrom`;
- `lib/Passes/Narrow.cc`: `isStatic`, `stageAttr`, `ownedStage`;
- `lib/Passes/TailLoops.cc` includes it and uses nothing (the passes lane
  drops that include).

In the first three, replace `#include "Ownership/Ownership.h"` with
`import idr.ownership;` after the unit's last include, and delete these
allowed lines:

    foreign/idr/lib/Dialect/Dialect.cc: Ownership/Ownership.h
    foreign/idr/lib/Expect/Counting.cc: Ownership/Ownership.h
    foreign/idr/lib/Passes/Narrow.cc: Ownership/Ownership.h

The other lanes leave those lines alone. If the dialect lane has split
Dialect.cc, the include is in the unit that defines
`verifyOperationAttribute`.

## Allowed lines that are yours

no-local-headers:

    foreign/idr/lib/Ownership/Borrow.cc: Ownership/Ownership.h
    foreign/idr/lib/Ownership/Counting.cc: Ownership/Ownership.h
    foreign/idr/lib/Ownership/Counts.cc: Ownership/Ownership.h
    foreign/idr/lib/Ownership/Exclusive.cc: Ownership/Ownership.h
    foreign/idr/lib/Ownership/Ops.cc: Ownership/Ownership.h
    foreign/idr/lib/Ownership/Rc.cc: Ownership/Ownership.h
    foreign/idr/lib/Ownership/ResetReuse.cc: Ownership/Ownership.h
    foreign/idr/lib/Ownership/Take.cc: Ownership/Ownership.h
    foreign/idr/lib/Ownership/Verify.cc: Ownership/Ownership.h

plus the three cross-lane lines above.

file-size:

    foreign/idr/lib/Ownership/Counts.cc
    foreign/idr/lib/Ownership/Exclusive.cc
    foreign/idr/lib/Ownership/Verify.cc

## Do not touch

Other lanes' files beyond the three include lines; idr.layout and
idr.graph (R0's: ask before changing an interface).
