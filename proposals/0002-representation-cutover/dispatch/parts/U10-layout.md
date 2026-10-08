# U10 — Layout without labels or code: memo sums sized once

Mandatory findings: F-clo-4 F-lazy-9

## Permitted outcome

1. **Memo cells.** A memo sum's cells all have one size, the largest of
   its constructors' cells. Each constructor's info word carries
   `IDRIS_RT_KIND_THUNK` and that state's tag and objs (C5.2). The
   accessors the lowering needs give each state's cell layout by
   constructor, as boxes do. Mandatory.
2. **No labels or code.** Layout keeps no label table, no code names
   and no closure or forced-suspension cells. Mandatory.
3. **The walk rule** (C7.2). `Layouts.cppm` follows a list constant's
   spine through `getRunCells()` and `getTail()`. Mandatory.

## Owner / exclusive writes

- `IDR/Layout`

**Excluded:**

- `IDR/Lower` (U11 and U12 read your accessors).
- `RT/idris_rt.h`, where the coordinator renames the kind.
- `IDR/Defunctionalize`, which makes the memo sums.

## Read first

- `contracts.md` C5.1, C5.2, C1.5 (the kind), C7.2 and C13.
- `review.md` R12 (the unit size).
- `findings.md` F-clo-4 and F-lazy-9.
- `IDR/Layout/*`, all of it, especially:
  - `Layouts.cppm:40-100` and `:230-400`;
  - `PlaceClosures.cc`;
  - `Labels.cppm` and `CodeName.cppm`;
  - `CellInfo.cppm` (the info word).
- The users of Layout's label and closure accessors in `IDR/Lower` and
  `IDR/Eval` (`grep -rn 'label\|closure(\|forced(\|codeName\|numLabels' foreign/idr/lib/Lower foreign/idr/lib/Eval`).
  Those lanes delete their uses.

## Fixed decisions

- **The box accessor, `Layouts::box(CtorOp)`**, gives a memo sum's
  constructor the cell layout of that state, with the memo sum's common
  size as `Cell::size`.
- **The info word.** `CellInfo` for a memo constructor uses the kind
  `IDRIS_RT_KIND_THUNK` (1). Every other box keeps `IDRIS_RT_KIND_BOX`.
- **`bool Layouts::isMemo(mlir::Type type) const`** tells the lowering
  a box type is a memo sum. It goes through `idr::isMemo` on the
  declaration. U11, U12 and U14 call it by this name.
- **`Layouts::counted` stays as it is** (C2.3). It answers which lowered
  components are counted pointers, and is not the holds-references
  question.

## Inputs

- Memo-sum declarations (C5.1): `idr.data ... box memo`.
- `idr::isMemo` (C1.4), defined by U09.
- `IDRIS_RT_KIND_THUNK` (C1.5).
- `ConAttr`'s C7.2 accessors, U19's.

## Outputs

- The box layouts and size for memo sums, and the memo query, which
  U11, U12 and U14 use.

## Implement

- **Size memo sums.** Where box cells are sized, a memo sum's size is
  the maximum over its constructors. Each constructor's field slots stay
  "object slots first", from the header, as for any box.
- **Write the kind** into the info word per the fixed decisions.
- **Remove every label and closure path.** Nothing lowers closures, and
  nothing reads code.
- **Split `Layouts.cppm`.** It is at exactly 400 lines today. Split it by
  concept as you edit (boxes, sums, constants), so that no unit passes
  400 and `T/spec/file-size/allowed` gains no line.
- **Walkers.** Wherever `Layouts.cppm` walks a constant's fields along a
  list, it walks the run's cells and tail.

## Delete

- `Labels.cppm`, `CodeName.cppm`, and `PlaceClosures.cc`, or its
  closure half if a memo-sum part is left.
- From `Layouts`: `Layouts::label`, `labelId`, `numLabels`,
  `Layouts::closure`, `Layouts::forced`, `forcedCells`, `codeName` and
  `lazyDoneName`.
- Every `LazyType` and `FnType` case that only served closures or
  suspensions as cells. No such value reaches the lowering after
  defunctionalization.

## NOT TO DO

- Do not change any box's or unboxed sum's layout but memo sums'.
- Do not change array, string or bignum cells.
- Do not add a cell kind beyond the rename.
- Do not keep a deleted accessor "for eval". Eval reads sums now (U14).

## Acceptance

- A memo sum with labels of 1 and 3 captures and `forced(i64)` has a
  cell of the 3-capture size, and each constructor's layout fits in it.
  U22 checks this through the lowering's output in
  `T/idr/lower/force-*`.
- `grep -rn 'label\|closure(\|forced(\|CodeName\|lazyDone' foreign/idr/lib/Layout`
  finds nothing.
- **Tempting partial:** sizing a memo cell by its label constructor
  alone. Rejected: the force writes `forced v` into the same cell, and
  `v` may be larger than the captures.

## Escalate if

- A consumer outside `IDR/Lower` and `IDR/Eval` reads a deleted
  accessor. Report it.

## Stop and return

You are done when memo sums are sized once and the label machinery is
gone. Return the changed paths, the names of any accessor beyond `isMemo`,
`Verification: NotRun (swarm policy)`, and seams.
