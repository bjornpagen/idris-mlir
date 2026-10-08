# U04 — Guards and total ops in the dialect: folders, speculation, causes

Mandatory findings: F-guard-1 F-guard-6

## Permitted outcome

1. **The guards.** The six guard ops of C1.1 item 2 have their folders
   and range inference, in a new `IDR/Dialect/Ops/Check.cc`.
2. **The total ops.** Every op C1.1 item 3 makes total:
   - has no crash cause;
   - folds only where its guard's predicate holds;
   - is speculatable only by C3.3's rule.
3. **Guards built where needed.** Every C++ pass that builds one of
   those ops on an unproved operand builds its guard first (C3.2).
4. **The array ops' consumption.** The array ops report consumption
   (C2.1 table).
5. **Folders build runs.** List folders build `#idr.con` runs with
   `ConAttr::getRun` (C7.2).

All five are mandatory.

## Owner / exclusive writes

- `IDR/Dialect/Ops/Check.cc` (new)
- `IDR/Dialect/Ops/Scalars.cc`
- `IDR/Dialect/Ops/Strings.cc`
- `IDR/Dialect/Ops/Bigs.cc`
- `IDR/Dialect/Ops/Arrays.cc`
- `IDR/Dialect/Ops/Buffer.cc`
- `IDR/Dialect/Ops/Bytes.cc`
- `IDR/Dialect/Ops/Crash.cc`
- `IDR/Dialect/Crashes`
- `IDR/Fold`
- `IDR/Ops`

**Excluded:**

- `INC/` (the coordinator writes the ODS).
- `IDR/Lower` (U05 lowers the guards).
- `IDR/InBounds` (U06 removes the guards it proves).
- `CS/` (U17 emits the guards from Idris).
- A C++ creator of a total op in another lane's file: name it in your
  handoff, with the exact guard it must build.

## Read first

- `contracts.md` C1.1 items 2 and 3, C2.1, C3.1 to C3.4, C7.2 and C13.
- `findings.md` F-guard-1, F-guard-5 and F-guard-6.
- Every `getCrashCause` in your files.
- `IDR/Dialect/Crashes/*.cc` (`knownFinite`, `knownNonEmpty`,
  `knownNonZero`).
- The folders in `IDR/Fold`, and `IDR/Ops/IoEffects.cppm` (`ioEffects`).
- The pinned `mlir/Interfaces/SideEffectInterfaces.h`
  (`ConditionallySpeculatable`, `Speculation::Speculatability`).

## Fixed decisions

- **One predicate per guard kind.**
  `bool idr::checkHolds(CheckKind kind, ArrayRef<Attribute> constants)`
  in `Check.cc`. `CheckKind` is
  `{Nonzero, InBounds, Nonempty, Byte, Finite, Range}`. It is the only
  place a precondition is written, and it is declared for your files in
  a partition you choose.
- **`idr::checkSpeculatability(Operation *op, ArrayRef<unsigned> guarded)`**
  returns `Speculatable` iff each guarded operand is the result of that
  operand's guard op, or a constant for which `checkHolds` holds.
  Otherwise it returns `NotSpeculatable`. Every total op's
  `getSpeculatability` calls it, with the operand indices C3.1 guards.
- **A guard folds to its operand** when its constants satisfy
  `checkHolds`, when the operand's type proves it (`!idr.nat` is never
  negative), or when the operand is the result of an identical guard.
  A guard never folds when the predicate fails.
- **A total op's folder** computes nothing where `checkHolds` fails on
  its constant operands, so the compiler never computes a division by
  zero.
- **Range inference.** Each guard with `InferIntRangeInterface`
  intersects the operand's range with its condition.
- **Causes.** The cause strings are today's crash texts (C3.1). They
  move from your files to the guard's `cause` attribute, which Emit and
  the C++ creators fill.

## Inputs

- The C1.1 items 2 and 3 ODS (guards; total ops without `Idr_MayCrash`).
- `idr::consumedEffects` (C1.4).
- `ConAttr::getRun` (C7.2).

## Outputs

- `Check.cc`: the guards' `fold`, `inferResultRanges`, `checkHolds` and
  `checkSpeculatability`.
- The total ops without causes.
- The list of other lanes' creators, for your handoff.

## Implement

- **`Check.cc`.** Write the six folders, range inference, `checkHolds`
  and `checkSpeculatability` per the fixed decisions. Split the file if
  it would pass 400 lines.
- **The total ops.**
  - Delete each `getCrashCause` of a now-total op, and its
    `Idr_MayCrashOpInterface` use.
  - Add `getSpeculatability` calling `checkSpeculatability`.
  - Keep each op's other effects: IO and array resources, and
    `MemAlloc` on allocating results.
  - `ops::ioEffects(getCrashCause(), ...)` becomes `ioEffects` without
    the crash part, in `IDR/Ops/IoEffects.cppm`.
- **`IDR/Dialect/Crashes`.** Fold `KnownNonZero.cc`, `KnownNonEmpty.cc`
  and `KnownFinite.cc` into `checkHolds`'s cases, and delete them. If
  the type-proof part is wanted, keep it as private helpers of
  `Check.cc`.
- **`IDR/Fold`.** Each folder of a partial op folds through
  `checkHolds`. `StringOfList.cc` and `Lists.cppm` build lists with
  `ConAttr::getRun`.
- **Creators.** Grep `foreign/idr/lib` for `create` of each C1.1 item 3
  op (`DivOp`, `ModOp`, `StrIndexOp`, `StrHeadOp`, `StrTailOp`,
  `BigDivOp`, `BigModOp`, `ToByteOp`, `ToIntOp`, `BigFromDoubleOp`,
  `ArrayGetOp`, `ArraySetOp`, the buffer and transfer ops). In your
  files, build the guard first unless the operand is proved there. List
  the rest.
- **`Arrays.cc`.** The array ops' `getEffects` call
  `idr::consumedEffects(*this, effects)` too.

## Delete

- `getCrashCause` of every op C1.1 item 3 lists.
- The `in_bounds` property's reads in `Arrays.cc` (`getInBounds()`).
- `IDR/Dialect/Crashes/Known{NonZero,NonEmpty,Finite}.cc` once
  `checkHolds` covers them. Their unit lines are in the coordinator's
  `IDR/Dialect/CMakeLists.txt`; name them in your handoff.
- The crash halves of `ops::ioEffects`.

## NOT TO DO

- Do not change any crash text.
- Do not make a total op `AlwaysSpeculatable`.
- Do not fold a failing guard.
- Do not add a guard kind beyond the six.
- Do not change `idr.crash` or `idr.crash_str`: they keep their causes.
- Do not write the lowering (U05) or the proofs (U06).

## Acceptance

- **Folding.** For each guard: a proving constant folds it; a failing
  constant does not; an identical guard's result folds it. U22 writes
  `T/idr/guards/fold-*` from C12.
- **Speculation.** `licm` does not hoist `idr.str.index` whose operand
  is not a guard's result out of an `scf.if`. With the guard in place,
  `idr.str.index` stays below it. U22 writes `T/idr/guards/speculation`.
- **Folders.** `idr.div` of constants `7, 0` does not fold.
- **Search.** `grep -rn getCrashCause foreign/idr/lib/Dialect/Ops`
  finds only `Crash.cc` and the guards.
- **Tempting partial:** keeping `getCrashCause` on the total ops,
  returning nothing "for compatibility". Rejected: it leaves two homes
  for the precondition.
- **Tempting partial:** `AlwaysSpeculatable` on the total ops.
  Rejected by F-guard-6: an index proved by a path condition would be
  hoisted out of it.

## Escalate if

- An op not in C1.1 item 3 crashes today (has `Idr_MayCrash` and is not
  `crash` or `crash_str`). Report it.
- A creator cannot know the cause text. Report the site.

## Stop and return

You are done when `Check.cc` exists, the total ops are total, the
creators in your files build guards, and the Delete list is empty of
survivors. Return the changed paths, the creator list for other lanes,
the unit lines for the coordinator,
`Verification: NotRun (swarm policy)`, and seams.
