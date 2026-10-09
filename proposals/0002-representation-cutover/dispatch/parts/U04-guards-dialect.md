# U04 — Guards and total ops in the dialect: folders, speculation, causes

Mandatory findings: F-guard-1 F-guard-6

## Permitted outcome

1. **The guards.** The six guard ops of C1.1 item 2 have their folders
   and range inference, in a new `IDR/Dialect/Ops/Check.cc`.
2. **The total ops.** Every op C1.1 item 3 makes total:
   - has no crash cause;
   - folds only where its guard's predicate holds;
   - if it is one of the six pure ones the hub makes `NoMemoryEffect`
     and `ConditionallySpeculatable` (`idr.div`, `idr.mod`,
     `idr.to_byte`, `idr.to_int`, `idr.str.index`, `idr.str.head`), is
     speculatable only by C3.3's rule. The allocating ones
     (`idr.str.tail`, `idr.big.div`, `idr.big.mod`,
     `idr.big.from_double`) and the IO, buffer and array ones keep their
     effects and declare no speculatability.
3. **Guards built where needed.** Every C++ pass in your files that
   builds one of those ops on an unproved operand builds its guard first
   (C3.2).
4. **The array ops' effects.** The array ops declare consumption by
   the hub's `Idr_Consumes` (C2.1 table), the trait and the interface
   only. Their own `getEffects` in `Arrays.cc` report today's effects
   without the crash, and do not call `consumedEffects` (C2.1, review
   R2): an IO op is impure anyway.
5. **Constants as runs.** Folders and builders build `#idr.con` lists
   with `ConAttr::getRun`, and walkers follow the walk rule (C7.2).
6. **Rewrites that matched a partial op** look through a `nonempty`
   guard (C3.4).

All six are mandatory.

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
- `IDR/Dialect/Ops/Generated.cc`
- `IDR/Canon`
- `IDR/Dialect/Ops/Field.cc`, whose folder reads one field of a constant
  (README S7)
- `IDR/Dialect/Canonicalize/Con.cc` and `IDR/Dialect/Ops/Closure.cc`, whose
  folders build a constant of their fields (README S17)

**Excluded:**

- `INC/` (the coordinator writes the ODS).
- `IDR/Dialect/Canonicalize.td`, the coordinator's. Its `HeadOfCons`
  and `HeadOfShow*` patterns gain a `nonempty` guard in their source
  pattern there. Report the exact DRR text you need.
- `IDR/Lower` (U05 lowers the guards).
- `IDR/InBounds` (U06 removes the guards it proves).
- `CS/` (U17 emits the guards from Idris).
- A C++ creator of a total op in another lane's file: name it in your
  handoff, with the exact guard it must build.

## Read first

- `contracts.md` C1.1 items 2 and 3, C2.1, C3.1 to C3.4, C7.2 and C13.
- `findings.md` F-guard-1, F-guard-5 and F-guard-6.
- `review.md` R4 and R6.
- Every `getCrashCause` in your files.
- `IDR/Dialect/Crashes/*.cc` (`knownFinite`, `knownNonEmpty`,
  `knownNonZero`).
- The folders in `IDR/Fold`, `IDR/Dialect/Ops/Generated.cc`'s
  `foldDivision`, and `IDR/Ops/IoEffects.cppm` (`ioEffects`).
- `IDR/Canon/Feeds.cppm` and `IDR/Canon/MatchPatterns.cppm`.
- `IDR/Ops/Constants.cppm` and `IDR/Ops/Untyped.cppm`.
- The pinned `mlir/Interfaces/SideEffectInterfaces.h`
  (`ConditionallySpeculatable`, `Speculation::Speculatability`).

## Fixed decisions

- **One predicate per guard kind for constants.**
  `bool idr::checkHolds(CheckKind kind, ArrayRef<Attribute> constants)`
  in `Check.cc`. `CheckKind` is
  `{Nonzero, InBounds, Nonempty, Byte, Finite, Range}`. It is declared
  for your files in a partition you choose.
- **`IDR/Dialect/Crashes` stays.** `knownNonZero`, `knownNonEmpty` and
  `knownFinite` keep their meaning and become the guards' folders'
  predicates (C3.4).
- **A guard's folder returns its operand** exactly when:
  - `nonzero`: `knownNonZero` holds of the operand;
  - `finite`: `knownFinite` holds;
  - `nonempty`: `knownNonEmpty` holds, which covers `str.cons` and
    every string built with a character or a number in it;
  - `in_bounds`, `byte`, `range`: `checkHolds` holds of constant
    operands;
  - or the operand is the result of an identical guard.

  Otherwise it does not fold, and a failing constant keeps its crash.
  No folder reads an analysis.
- **`idr::checkSpeculatability(Operation *op, ArrayRef<unsigned> guarded)`**
  returns `Speculatable` iff each guarded operand is either:
  - the result of a guard whose length operand is the length of the
    op's own string: `idr.str.length` of `idr.str.index`'s string
    operand, the one speculatable total op whose guard takes a length.
    For `nonzero`, `nonempty`, `byte` and `finite` it is that operand's
    own guard;
  - or a constant for which `checkHolds` holds.

  Otherwise `NotSpeculatable` (C3.3). The `getSpeculatability` of each
  of the six pure total ops calls it, with the operand indices C3.1
  guards. No other total op has one.
- **A total op's folder** computes nothing where `checkHolds` fails on
  its constant operands. That includes `foldDivision` in
  `Generated.cc`, the total `div` and `mod` folder: APInt division by
  zero aborts the compiler.
- **Range inference.** Each guard with `InferIntRangeInterface`
  intersects the operand's range with its condition.
- **Causes.** The cause strings are today's crash texts (C3.1). They
  move from your files to the guard's `cause` attribute, which Emit and
  the C++ creators fill.

## Inputs

- The C1.1 items 2 and 3 ODS (guards; total ops without `Idr_MayCrash`).
- `ConAttr::getRun` and `getField` (C7.2), U19's, and `getRunCells`
  and `getTail`, the hub's (C1.1 item 6).

## Outputs

- `Check.cc`: the guards' `fold`, `inferResultRanges`, `checkHolds` and
  `checkSpeculatability`.
- The total ops without causes.
- The DRR text for the coordinator's `Canonicalize.td`.
- The list of other lanes' creators, for your handoff.

## Implement

- **`Check.cc`.** Write the six folders, range inference, `checkHolds`
  and `checkSpeculatability` per the fixed decisions. Split the file if
  it would pass 400 lines.
- **The total ops.**
  - Delete each `getCrashCause` of a now-total op, and its
    `Idr_MayCrashOpInterface` use.
  - Add `getSpeculatability` calling `checkSpeculatability` to exactly
    the six the hub makes `NoMemoryEffect` and
    `ConditionallySpeculatable`: `DivOp` and `ModOp` (`Generated.cc` or
    `Scalars.cc`), `ToByteOp`, `ToIntOp`, `StrIndexOp` and `StrHeadOp`.
    The ODS declares the method on those six only, so a definition on
    any other op does not compile.
  - Keep each op's other effects: IO and array resources, and
    `MemAlloc` on allocating results. The allocating total ops
    (`StrTailOp`, `BigDivOp`, `BigModOp`, `BigFromDoubleOp`) have their
    `MemAlloc` from ODS and need no code.
  - `ops::ioEffects(getCrashCause(), ...)` becomes `ioEffects` without
    the crash part, in `IDR/Ops/IoEffects.cppm`.
- **`IDR/Dialect/Crashes`.** Keep the three predicates. Delete only
  what served crash causes and nothing else reads.
- **`IDR/Fold` and `Generated.cc`.** Each folder of a total op folds
  through `checkHolds`. `StringOfList.cc` and `Lists.cppm` build lists
  with `ConAttr::getRun`.
- **`IDR/Canon`.** `Feeds.cppm`'s consumer test sees through a
  `nonempty` guard to the `str.head` behind it (`Feeds.cppm:137-138`).
  Its two rules from 1677b8cb stay (C3.4, C4.4): a force meets a
  suspension nothing else uses (`:141-142`), which you keep to
  `!idr.lazy` operands now that `idr.force` also takes a memo box; and a
  box constructor is never folded with constants into static data
  (`:149-150`).
  `MatchPatterns.cppm` keeps calling `knownNonEmpty`.
- **`IDR/Ops`.** `Constants.cppm`, the constant verifier that runs after
  every pass, walks a run's cells and tail, never `getFields()[s]`.
  `Untyped.cppm` rebuilds a list constant with `getRun`.
- **Creators.** Grep `foreign/idr/lib` for `create` of each C1.1 item 3
  op (`DivOp`, `ModOp`, `StrIndexOp`, `StrHeadOp`, `StrTailOp`,
  `BigDivOp`, `BigModOp`, `ToByteOp`, `ToIntOp`, `BigFromDoubleOp`,
  `ArrayGetOp`, `ArraySetOp`, the buffer and transfer ops). In your
  files, build the guard first unless the operand is proved there. List
  the rest.
- **`Arrays.cc`.** The five array ops' `getEffects` report today's
  effects without the crash, through `ioEffects` without its crash part;
  none calls `consumedEffects` (C2.1). The hub's `Idr_ArrayOp` no longer
  declares the crash interface, so all five lose `getCrashCause`. That
  of `new`, `generate` and `fold` always returned nothing (C1.1 item 3),
  so their effects do not change.

## Delete

- `getCrashCause` of every op C1.1 item 3 lists, and of
  `ArrayNewOp`, `ArrayGenerateOp` and `ArrayFoldOp`
  (`Arrays.cc:54`, `:157-158`), which lost the interface with their
  class and never had a cause.
- The `in_bounds` property's reads in `Arrays.cc` (`getInBounds()`).
- The crash halves of `ops::ioEffects`.
- Any constant walk in your files that steps a list by
  `getFields()[s]`.

## NOT TO DO

- Do not change any crash text.
- Do not make a total op `AlwaysSpeculatable`, and do not give an
  allocating, IO, buffer or array total op a speculatability.
- Do not fold a failing guard.
- Do not fold a guard by an analysis (range, dominance): that is
  `idr-in-bounds`'s (U06).
- Do not delete `knownNonZero`, `knownNonEmpty` or `knownFinite`.
- Do not add a guard kind beyond the six.
- Do not change `idr.crash` or `idr.crash_str`: they keep their causes.
- Do not write the lowering (U05) or the proofs (U06).
- Do not drop `Feeds.cppm`'s force and box-constructor rules:
  `T/idr/canon/force-of-choice` and `T/idr/canon/held-not-read` state
  them.

## Acceptance

- **Folding.** For each guard: a proving operand folds it; a failing
  constant does not; an identical guard's result folds it.
  `str.head (check.nonempty (str.cons c s))` folds to `c` through the
  guard's folder and the coordinator's pattern. U22 writes
  `T/idr/guards/fold-*` from C12.
- **Speculation.** In an `scf.while` whose condition is
  `%i < idr.str.length %s`, `idr.str.index %s, %i` with its guard proved
  away stays in the loop under `loop-invariant-code-motion`. U22 writes
  `T/idr/guards/speculation`.
- **Folders.** `idr.div` of constants `7, 0` does not fold, and the
  compiler does not abort on it.
- **Search.** `grep -rn getCrashCause foreign/idr/lib/Dialect/Ops`
  finds only `Crash.cc` (`CrashOp`'s; `crash_str`'s and the guards'
  are defined in ODS).
- **Arrays.** `idr.array.new`, `idr.array.generate` and
  `idr.array.fold` report the effects they reported at the launch base,
  and `idr.array.get` and `idr.array.set` those effects without the
  crash.
- **Tempting partial:** keeping `getCrashCause` on the total ops,
  returning nothing "for compatibility". Rejected: it leaves two homes
  for the precondition.
- **Tempting partial:** `AlwaysSpeculatable` on the total ops.
  Rejected by F-guard-6: an index proved by a path condition would be
  hoisted out of it.
- **Tempting partial:** folding guards on constants only. Rejected by
  R4: it kills `HeadOfCons` and today's string folds.

## Escalate if

- An op not in C1.1 item 3 crashes today (has `Idr_MayCrash`, or a
  crash interface whose cause is not always nothing, and is not `crash`,
  `crash_str` or a guard). Report it.
- A creator cannot know the cause text. Report the site.
- A total op's length operand is not reachable as C3.3 states. Report
  the op.

## Stop and return

You are done when `Check.cc` exists, the total ops are total, the
creators in your files build guards, the walkers and builders follow
C7.2, and the Delete list is empty of survivors. Return the changed
paths, the creator list for other lanes, the DRR text for the
coordinator, `Verification: NotRun (swarm policy)`, and seams.
