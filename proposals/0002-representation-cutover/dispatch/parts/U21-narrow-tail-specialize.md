# U21 — Narrow, Tail and Specialize on the new grades, without sentinels

Mandatory findings: F-poison-1

## Permitted outcome

1. **The sentinels.** The C2.4 sites in `IDR/Narrow`, `IDR/Tail` and
   `IDR/Specialize` use no `ub.poison` sentinel. Mandatory.
2. **The stage.** `IDR/Narrow/Words.cppm` asks
   `ownership::inOwnedStage(module)` once per pass, instead of reading
   the module's stage attribute (C2.2). Mandatory.
3. **The guards.** Every total op these areas build gets its guard
   (C3.2), and every place they read `idr.lazy` or closure types after
   defunctionalization is removed. Mandatory.
4. **The walk rule** (C7.2) in `IDR/Specialize/{KeyOf,Specialization,ShapeOf,UnrollSize}.cppm`.
   Mandatory.

## Owner / exclusive writes

- `IDR/Narrow`
- `IDR/Tail`
- `IDR/Specialize`

**Excluded:**

- `IDR/Ownership` (U03, which defines the grades).
- `IDR/Dialect/Ops/Check.cc` (U04, which defines the guards).
- `INC/`.

## Read first

- `contracts.md` C2.2, C2.4, C3.1, C3.2, C7.2 and C13.
- `review.md` R1 and R3.
- `findings.md` F-poison-1 and F-own-2.
- `IDR/Narrow/{Words,Facts,Versions,Naturals}.cppm`.
- `IDR/Tail/{Returned,Loop}.cppm`.
- `IDR/Specialize/{KeyOf,Specialization,ShapeOf,UnrollSize}.cppm`.
- `IDR/Specialize/Clones.cppm` (`CloneTable::settleBreaker`) and
  `IDR/Specialize/BindingTimes.cppm` (the join for raised clones), new
  at ccc3e1dc, and `T/idr/specialize/breaker-clones.mlir`, which states
  what they keep.
- `grep -rn 'create<\|::create(' foreign/idr/lib/Narrow foreign/idr/lib/Tail foreign/idr/lib/Specialize`,
  for the creators of partial ops.

## Fixed decisions

- **The sentinel rule** is C2.4's, verbatim.
- **Counted bigs.** `Words.cppm:42-43`'s module-attribute test becomes
  `inOwnedStage(module)`, asked once per pass and passed down. Views
  stay plain (C2.2), so a big's own type does not say it.
- **Guards.** A narrowed division (`idr.div` or `idr.mod` built by
  Narrow on words) gets `idr.check.nonzero` on its divisor, unless the
  divisor is proved nonzero where it is built. The cause is
  `division by zero`.

## Inputs

- `ownership::inOwnedStage` (U03).
- `ConAttr`'s C7.2 accessors (U19).
- The guard ops (C1.1 item 2) and their builders.

## Outputs

- Narrow, Tail and Specialize on the new representation.

## Implement

- Per the fixed decisions.
- **Walkers.** The four `Specialize` units (`KeyOf.cppm:29`,
  `Specialization.cppm:107`, `ShapeOf.cppm:43`, `UnrollSize.cppm:34`,
  review R3; the same lines at ccc3e1dc) follow a list constant's
  spine through `getRunCells()` and `getTail()`, never `getFields()[s]`.
  A key or a shape computed from a run is the same as from the nested
  form, since the attribute is the same value.

## Delete

- The eight `ub.poison` sentinels.
- The stage test in `Words.cppm`.

## NOT TO DO

- Do not change what Narrow narrows, what Tail makes into loops, or
  what Specialize clones.
- Do not change which clone is a loop breaker. Keep
  `CloneTable::settleBreaker` and the binding-time join for raised
  clones (ccc3e1dc): without them `idr-simplify` never ends on
  `T/programs/eval/latent-loop*` (C2.4, C7.2).
- Do not touch `Idr_CloneAttr`: F-own-4 refutes changing it.

## Acceptance

- `T/idr/narrow`, `T/idr/tail` and `T/idr/specialize` (U22 keeps them)
  and all programs pass at integration.
- Among them, `T/idr/specialize/breaker-clones`, the raised-clone case
  of `T/idr/specialize/binding-times.mlir`, and
  `T/programs/eval/latent-loop`, `latent-loop-delay` and
  `latent-loop-accumulator` (ccc3e1dc) pass: the lane keeps
  `CloneTable::settleBreaker` and the binding-time join for raised
  clones.
- `grep -rn 'PoisonOp' foreign/idr/lib/Narrow foreign/idr/lib/Tail foreign/idr/lib/Specialize`
  shows only IR values of the program, each with a comment saying so.
- **Tempting partial:** replacing a sentinel with a different sentinel
  op. Rejected: "no value" is `std::optional` or a null `Value` in C++.

## Escalate if

- A Narrow or Tail decision depended on the stage attribute in a way
  `inOwnedStage` cannot express. Report the site.

## Stop and return

You are done when the four outcomes hold. Return the changed paths,
`Verification: NotRun (swarm policy)`, and seams.
