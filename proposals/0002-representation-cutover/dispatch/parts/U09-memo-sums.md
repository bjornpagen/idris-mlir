# U09 — Thunks become memo sums in idr-defunctionalize

Mandatory findings: F-lazy-6 F-lazy-8 F-poison-8

## Permitted outcome

1. **Memo sums.** `idr-defunctionalize` turns every `!idr.lazy<T>` key
   into a memo sum (C5.1). Mandatory:
   - suspensions become constructors of a `box memo` data declaration,
     whose `labels` names the label functions;
   - lazy constants become constructor constants;
   - lazy types become the box type;
   - `idr.force` takes the box.
2. **Arrays in Slots.** The analysis follows values through array
   elements, for closure keys and lazy keys alike, so that
   `IOArray (Lazy Int)` keeps compiling (review R7). Mandatory.
3. **`by_name`** by C5.1's rule (O3, review R8). Mandatory.
4. **Nothing lazy is left.** No `!idr.lazy` type, no `idr.suspend` and
   no closure is left after the pass. A key the analysis cannot convert
   is `unsupported (laziness)` or `unsupported (runtime closure)` from
   the pass, and the function reports it to its other caller, the
   evaluator (C6.4). Mandatory.
5. **The verifiers and the force's effects.** `idr::isMemo`, the
   memo-sum verifier, `idr.force` accepting a memo box, and
   `ForceOp::getEffects`. Mandatory.
6. **The sentinels.** The two `ub.poison` sites are classified (C2.4).
   Mandatory.
7. **The walk rule** (C7.2) in `Closures`, `Analysis`, `Converter` and
   `Slots`. Mandatory.

## Owner / exclusive writes

- `IDR/Defunctionalize`
- `IDR/Dialect/Ops/Lazy.cc`
- `IDR/Dialect/Ops/Data.cc`

**Excluded:**

- `INC/` (the coordinator adds `memo`, `labels`, `by_name` and the
  force's operand type, C1.1 item 5).
- `IDR/Layout` (U10 sizes memo cells).
- `IDR/Lower` (U11 and U12 lower them).
- `IDR/Eval` (U14 calls your function and reads memo sums back).
- `CS/Rule.idr`: `laziness` and `runtime closure` are existing rules.

## Read first

- `contracts.md` C1.1 item 5, C5.1, C5.4, C2.1 (the paragraph on
  `idr.force`), C2.4, C6.4, C7.2 and C13.
- `findings.md` F-lazy-6, F-lazy-8 and F-poison-8.
- `review.md` R7, R8 and R12 (the label bodies).
- `IDR/Defunctionalize/*`, all of it, especially:
  - `Sums.cppm`'s header comment;
  - `Slots.cppm`'s `isFollowed`, and its anchors per constructor field;
  - `Converter.cppm`;
  - `Closures.cppm`;
  - `Pass.cc`, and the public `defunctionalize` function and its
    counts.
- `IDR/Dialect/Ops/Lazy.cc` (the verifiers, the four `ForceOf*`
  patterns).
- `IDR/Dialect/Ops/Data.cc`.
- `IDR/Facts/ClosureLabel.cppm`.

## Fixed decisions

- **The declaration's shape:**

  ```mlir
  idr.data @lazy$<n> box memo labels [@<label fn>, ...] {
    idr.ctor @<label fn>(captures...)
    idr.ctor @running()
    idr.ctor @forced(T)
  }
  ```

  There is one label constructor per label, named after its function as
  closure sums name theirs. The two protocol constructors come last.
  `labels` lists exactly the label functions, so that every
  interprocedural solver between `idr-defunctionalize` and `idr-lower`
  sees them as address-taken and keeps their bodies live.
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
- **Arrays.** One anchor per array element type, as there is one per
  constructor field. It is written by `idr.array.new`'s fill,
  `idr.array.set`'s value and `idr.array.generate`'s yield, and read by
  `idr.array.get`'s result and `idr.array.fold`'s element block argument.
- **`by_name`.** A label constructor is `by_name` iff both hold:
  - its function reaches, through direct calls after conversion, an op
    with `Idr_PerformsIO` other than an `idr.array.*` or buffer op
    (output, input, a file, a clock). `trace` reaches `put_str`, so it
    is `by_name`. `Linear.Array`, `runST` and `strerror` reach only
    array and buffer ops, or none, so they keep their memo;
  - no static constant names the label. A top-level `Delay` is memoized
    by Chez (`(define n (delay …))`), and a static thunk is our nearest
    equivalent.

  Compute it by a walk over the label's call graph with a visited set.
- **Unknown keys.**
  `idr::defunctionalize::defunctionalize(ModuleOp)` returns, beside its
  counts, the keys it could not convert, each with the op where the
  analysis lost the value. `Pass.cc` reports each as
  `unsupported (laziness)` (a suspension) or
  `unsupported (runtime closure)` (a closure) at that op, and fails.
  The evaluator (U14) calls the function, not the pass, and leaves the
  round for runtime on any unknown key.
- **`idr::isMemo(DataOp)`** returns `data.getMemo()`, and it lives in
  `Data.cc`.
- **The memo-sum verifier** in `DataOp::verify` checks:
  - `box` is set;
  - there is exactly one `@running` with no fields, and one `@forced`
    with one field;
  - every other constructor is a label, and `labels` names exactly
    their functions;
  - `by_name` appears only on label constructors.
- **`ForceOp::verify`** accepts a lazy value whose `T` is the result
  type, or a memo-sum box whose `@forced` field type is the result
  type.
- **`ForceOp::getEffects`** reports what it reports today, and also:
  - `Free` on `ReferenceResource` of the operand when its grade is `own`
    or `excl`. `consumes` is false for a force (C2.1), so this is the
    op's own code, not `consumedEffects`;
  - `MemWrite` on `Idr_IOResource` when the operand's sum has a
    `by_name` constructor, so a force that may write output stays in
    order with output.
- **The four `ForceOf*` patterns stay** on the symbol form (C4.4). After
  defunctionalization they do not match, because no `idr.suspend` is
  left.

## Inputs

- C1.1 item 5: `memo`, `labels`, `by_name`, the force's operand.
- `ConAttr`'s C7.2 accessors, U19's.

## Outputs

- Memo sums in the defunctionalized module, which U10, U11, U12, U14
  and U02 read.
- `idr::isMemo`.
- `defunctionalize`'s unknown keys, which U14 reads.

## Implement

- **Follow lazy keys** through the existing analysis. Slots already
  follow `SuspendOp` and `ForceOp`, so give lazy keys their own key
  kind, alongside closure keys.
- **Follow arrays** per the fixed decision, for both key kinds.
- **Convert** each known key per the fixed decisions, in `Converter`
  and `Sums`.
- **Unknown keys.** Return them from the function; report them from
  the pass.
- **`by_name`.** The call-graph walk, after conversion.
- **`Lazy.cc` and `Data.cc`.** The verifiers, `isMemo` and
  `ForceOp::getEffects`.
- **Walkers.** `Closures`, `Analysis`, `Converter` and `Slots` follow a
  list constant's spine through `getRunCells()` and `getTail()` (C7.2).
- **Splits.** `Slots.cppm` is at 376 lines. Split it by concept as you
  add the array anchors, so that no unit passes 400.
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
- Do not decide `by_name` by `idr.effects`' `io` bit: linear arrays and
  `runST` would lose their memo (review R8).
- Do not memoize, or decline to memoize, here. The protocol is the
  lowering's (C5.3); you only mark `by_name`.
- Do not turn an unknown key into an internal error or leave it in the
  module.

## Acceptance

- After the pass on `T/idr/defunc/*` and `T/programs/eval/memo-lazy`,
  `stream-share` and `lazy-double`, no `!idr.lazy` type and no
  `idr.suspend` remains.
- Each lazy key is a `box memo` sum with `running`, `forced` and
  `labels`.
- A label that reaches `idr.io.put_str` is `by_name`; one that reaches
  only array ops is not; one a static constant names is not.
- `IOArray (Lazy Int)` converts: U23 writes
  `T/programs/arrays/lazy-elements`.
- A suspension the analysis loses gives `unsupported (laziness)` at the
  op it flows through. U22 writes `T/idr/defunc/unknown-lazy`.
- U22 writes `T/idr/defunc/memo-*` from C12.
- **Tempting partial:** leaving keys the analysis "might not know" as
  `!idr.lazy`. Rejected: nothing lowers `!idr.lazy` any more, and an
  unknown key must be a named rejection, never a miscompile.

## Escalate if

- A test program in `T/programs` has a lazy key the analysis cannot
  know, because a suspension flows through something the analysis does
  not follow beyond arrays. Report the program and the op. The
  coordinator decides whether to extend the analysis or accept the
  rejection.

## Stop and return

You are done when every lazy key is a memo sum, the verifiers accept
the new forms, and the Delete list is empty of survivors. Return the
changed paths, `Verification: NotRun (swarm policy)`, and seams.
