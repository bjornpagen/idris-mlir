# Memory theory: loose notes on the code

These are notes from reading the code for the memory-theory stream. They
are unstructured. Each is small, and each is a place where a fact the memory
model relies on sits somewhere weaker than a type.

- **`assert_linear` has no rejection test.**
  - `tests/profile/v0/reject/` covers `believe_me` only.
  - `assert_linear` is `believe_me id` (Builtin.idr:198-199), and it is
    rejected today (checked: "unsupported (escape hatch): the escape hatch
    Builtin.assert_linear").
  - Any exclusivity analysis is unsound the day it stops being rejected.
- **Borrow.cc ignores returns.**
  - `collect` makes a parameter owned for reset/take, owned-call arguments,
    applies and constructors, but not for `func.return`.
  - So `pick xs = xs` borrows `xs`, and Counts.cc incs it before the
    return. That is correct for counting.
  - But "a borrowed call preserves the caller's exclusivity" is false for
    such parameters. The escape summaries of lib/Stack are the right test,
    not borrowedness.
- **`ConOp::getEffects` reads a discardable attribute.**
  - It picks its allocation resource from `idr.stack` (Ops.cc:334-342).
  - It is harmless today, since idr-stack re-derives the attribute on every
    run. But it is a fact whose loss changes an op's effects.
  - With owned-stage types, a stack cell could be an op or a type of its
    own.
- **ResetReuse copies discardable attributes from the con to the reuse**
  (`reuse->setDiscardableAttrs(con->getDiscardableAttrDictionary())`).
  - Stack cons are excluded from reuse, so nothing wrong travels today.
  - It is a channel through which a stale fact could travel tomorrow.
- **`idr.closure` is `Pure`, so CSE may merge two identical closures.**
  - That is fine while a closure value is counted.
  - A one-shot closure (captures moved out on apply) must not be merged,
    which is another reason the apply-consumes design needs a type.
- **idr-specialize and scalars.** mlir-ownership-types.md says idr-specialize
  "already clones a callee for constant arguments". It does, but only for
  structured constants. `hasStructure` (Specialize/Pattern.h:83-85)
  excludes a lone scalar on purpose, so an `i1` exclusivity key needs its
  own rule.
- **The dynamic take's else branch is Perceus's copy path.**
  - It is `inc` fields, then `dec` cell, then a null token
    (Lower/Counting.cc:118-133).
  - Once the exclusivity operand folds true, canonicalization of the
    `scf.if` deletes the whole branch.
  - That is the entire static-reuse payoff at the machine level: no
    branch, no incs, no dec.
- **Stack cells and reuse today.** In `bump (C n (C 2 (C 3 N)))` the top cell
  is `{idr.stack}` and so never exclusive, and the tail is a static
  constant. So bump allocates all three cells, although the top cell was
  fresh.
