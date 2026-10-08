# U09 — Thunks become memo sums in idr-defunctionalize

Mandatory findings: F-lazy-6 F-lazy-8 F-poison-8

## Permitted outcome

1. **Memo sums.** `idr-defunctionalize` turns every `!idr.lazy<T>` key
   into a memo sum (C5.1). Mandatory:
   - suspensions become constructors of a `box memo` data declaration;
   - lazy constants become constructor constants;
   - lazy types become the box type;
   - `idr.force` takes the box.
2. **`by_name`.** A label whose function forges a world gets a `by_name`
   constructor. Mandatory.
3. **Nothing lazy is left.** No `!idr.lazy` type and no `idr.suspend`
   op is left after the pass; an unknown key is an internal error.
   Mandatory.
4. **The verifiers.** `idr::isMemo`, the memo-sum verifier, and
   `idr.force` accepting a memo box. Mandatory.
5. **The sentinels.** The two `ub.poison` sites are classified (C2.4).
   Mandatory.

## Owner / exclusive writes

- `IDR/Defunctionalize`
- `IDR/Dialect/Ops/Lazy.cc`
- `IDR/Dialect/Ops/Data.cc`

**Excluded:**

- `INC/` (the coordinator adds `memo`, `by_name` and the force's
  operand type, C1.1 item 5).
- `IDR/Layout` (U10 sizes memo cells).
- `IDR/Lower` (U11 and U12 lower them).
- `IDR/Eval` (U14 reads them back).

## Read first

- `contracts.md` C5.1, C5.4, C2.1 (the `idr.force` row), C2.4 and C13.
- `findings.md` F-lazy-6, F-lazy-8 and F-poison-8.
- `IDR/Defunctionalize/*`, all of it, especially:
  - `Sums.cppm`'s header comment;
  - `Slots.cppm`'s `isFollowed`;
  - `Converter.cppm`;
  - `Closures.cppm`.
- `IDR/Dialect/Ops/Lazy.cc` (the verifiers, the four `ForceOf*`
  patterns).
- `IDR/Dialect/Ops/Data.cc`.
- `IDR/Facts/ClosureLabel.cppm`.

## Fixed decisions

- **The declaration's shape:**

  ```mlir
  idr.data @lazy$<n> box memo {
    idr.ctor @<label fn>(captures...)
    idr.ctor @running()
    idr.ctor @forced(T)
  }
  ```

  There is one label constructor per label, named after its function as
  closure sums name theirs. The two protocol constructors come last.
- **Numbering.** `n` numbers memo sums by first appearance, separately
  from `@fn$<n>`.
- **The rewrites:**
  - `idr.suspend @f(caps)` becomes `idr.con @lazy$n::@f(caps)`;
  - a `#idr.closure<@f, caps>` at a lazy type becomes
    `#idr.con<@lazy$n::@f, caps>`;
  - every type `!idr.lazy<T>` of that key becomes `!idr.box<@lazy$n>`,
    in values, block arguments, signatures, constructor fields and
    array elements;
  - `idr.force` keeps its op and result.
- **Coercions** between two lazy keys rebuild the label constructor in
  the other sum, as closure coercions do.
- **`by_name`.** A label constructor is `by_name` iff the label
  function's `idr.effects` attribute contains `io`.
- **An unknown key** is an internal error at the first value of it:
  "internal error: a suspension is left after idr-defunctionalize".
- **`idr::isMemo(DataOp)`** returns `data.getMemo()`, and it lives in
  `Data.cc`.
- **The memo-sum verifier** in `DataOp::verify` checks:
  - `box` is set;
  - there is exactly one `@running` with no fields, and one `@forced`
    with one field;
  - every other constructor is a label;
  - `by_name` appears only on label constructors.
- **`ForceOp::verify`** accepts a lazy value whose `T` is the result
  type, or a memo-sum box whose `@forced` field type is the result
  type.
- **`ForceOp`'s `getEffects`** adds `idr::consumedEffects(*this, effects)`.
- **The four `ForceOf*` patterns stay** on the symbol form (C4.4). After
  defunctionalization they do not match, because no `idr.suspend` is
  left.

## Inputs

- C1.1 item 5: `memo`, `by_name`, the force's operand.
- `idr::consumedEffects` (C1.4).

## Outputs

- Memo sums in the defunctionalized module, which U10, U11, U12, U14
  and U02 read.
- `idr::isMemo`.

## Implement

- **Follow lazy keys** through the existing analysis. Slots already
  follow `SuspendOp` and `ForceOp`, so give lazy keys their own key
  kind, alongside closure keys.
- **Convert** each known key per the fixed decisions, in `Converter`
  and `Sums`.
- **Unknown keys.** Report the internal error.
- **`Lazy.cc` and `Data.cc`.** The verifiers and `isMemo`.
- **Sentinels.** Classify the two `ub.poison` sites per C2.4. A value
  the analysis never reaches stays `ub.poison`; any C++ "no value"
  becomes `std::optional`.

## Delete

- `IDR/Defunctionalize/AdaptLazy.cc`, its declarations
  (`suspensionResults`, `adapt`, `adaptLazy`), and its line in the
  area's `CMakeLists.txt`. The key now carries what it adapted.
- The comment in `Sums.cppm` claiming that suspensions are left alone,
  if it says so. U11 deletes the matching comment in the lowering.

## NOT TO DO

- Do not lower anything.
- Do not size cells.
- Do not change closure sums' names, numbering or coercions.
- Do not make a memo sum unboxed.
- Do not memoize, or decline to memoize, here. The protocol is the
  lowering's (C5.3); you only mark `by_name`.

## Acceptance

- After the pass on `T/idr/defunc/*` and `T/programs/eval/memo-lazy`,
  `stream-share` and `lazy-double`, no `!idr.lazy` type and no
  `idr.suspend` remains.
- Each lazy key is a `box memo` sum with `running` and `forced`.
- A trusted forged-world label is `by_name`.
- U22 writes `T/idr/defunc/memo-*` from C12.
- **Tempting partial:** leaving keys the analysis "might not know" as
  `!idr.lazy`. Rejected: nothing lowers `!idr.lazy` any more, and an
  unknown key must be a named internal error, never a miscompile.

## Escalate if

- A test program in `T/programs` has a lazy key the analysis cannot
  know, because a suspension flows through something the analysis does
  not follow. Report the program and the op. The coordinator decides
  whether to extend the analysis or reject.

## Stop and return

You are done when every lazy key is a memo sum, the verifiers accept
the new forms, and the Delete list is empty of survivors. Return the
changed paths, `Verification: NotRun (swarm policy)`, and seams.
