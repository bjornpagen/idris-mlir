# U21 — Narrow, Tail and Specialize on the new grades, without sentinels

Mandatory findings: F-poison-1

## Permitted outcome

1. **The sentinels.** The C2.4 sites in `IDR/Narrow`, `IDR/Tail` and
   `IDR/Specialize` use no `ub.poison` sentinel. Mandatory.
2. **The grade.** `IDR/Narrow/Words.cppm` decides whether a big is
   counted from its grade (`own`, `excl` or `borrow`), not from the
   module's stage (C2.2). Mandatory.
3. **The guards.** Every total op these areas build gets its guard
   (C3.2), and every place they read `idr.lazy` or closure types after
   defunctionalization is removed. Mandatory.

## Owner / exclusive writes

- `IDR/Narrow`
- `IDR/Tail`
- `IDR/Specialize`

**Excluded:**

- `IDR/Ownership` (U03, which defines the grades).
- `IDR/Dialect/Ops/Check.cc` (U04, which defines the guards).
- `INC/`.

## Read first

- `contracts.md` C2.2, C2.4, C3.1, C3.2 and C13.
- `findings.md` F-poison-1 and F-own-2.
- `IDR/Narrow/{Words,Facts,Versions,Naturals}.cppm`.
- `IDR/Tail/{Returned,Loop}.cppm`.
- `IDR/Specialize/ShapeOf.cppm`.
- `grep -rn 'create<\|::create(' foreign/idr/lib/Narrow foreign/idr/lib/Tail foreign/idr/lib/Specialize`,
  for the creators of partial ops.

## Fixed decisions

- **The sentinel rule** is C2.4's, verbatim.
- **Counted bigs.** A big value is counted iff its type's permission is
  `own`, `excl` or `borrow`. That is the grade test replacing the
  module-attribute test at `Words.cppm:42-43`.
- **Guards.** A narrowed division (`idr.div` or `idr.mod` built by
  Narrow on words) gets `idr.check.nonzero` on its divisor, unless the
  divisor is proved nonzero where it is built. The cause is
  `division by zero`.

## Inputs

- The grades (U03).
- The guard ops (C1.1 item 2) and their builders.

## Outputs

- Narrow, Tail and Specialize on the new representation.

## Implement

- Per the fixed decisions.

## Delete

- The eight `ub.poison` sentinels.
- The stage test in `Words.cppm`.

## NOT TO DO

- Do not change what Narrow narrows, what Tail makes into loops, or
  what Specialize clones.
- Do not touch `Idr_CloneAttr`: F-own-4 refutes changing it.

## Acceptance

- `T/idr/narrow`, `T/idr/tail` and `T/idr/specialize` (U22 keeps them)
  and all programs pass at integration.
- `grep -rn 'PoisonOp' foreign/idr/lib/Narrow foreign/idr/lib/Tail foreign/idr/lib/Specialize`
  shows only IR values of the program, each with a comment saying so.
- **Tempting partial:** replacing a sentinel with a different sentinel
  op. Rejected: "no value" is `std::optional` or a null `Value` in C++.

## Escalate if

- A Narrow or Tail decision depended on the stage attribute in a way
  the grade cannot express. Report the site.

## Stop and return

You are done when the three outcomes hold. Return the changed paths,
`Verification: NotRun (swarm policy)`, and seams.
