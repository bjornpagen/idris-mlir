# U06 — Guards proved away: idr-in-bounds as the guards' prover, the expect properties

Mandatory findings: F-guard-3 F-poison-6

## Permitted outcome

1. **Erasing guards.** `idr-in-bounds` erases every
   `idr.check.in_bounds` its index systems prove, replacing the guard's
   result with its operand. It also erases any guard that a dominating
   identical guard checks, or that `IntegerRangeAnalysis` proves at its
   point (C3.5). Mandatory.
2. **Properties.** `idr-expect`'s `in-bounds=@f` means "no
   `idr.check.in_bounds` is left in `@f`". The new property
   `no-guards=@f` means "no `idr.check.*` is left in `@f`". Mandatory.
3. **Sentinels.** The C2.4 sites in `IDR/InBounds` use no sentinel.
   Mandatory.

## Owner / exclusive writes

- `IDR/InBounds`
- `IDR/Expect`

**Excluded:**

- `INC/Passes.td`: the coordinator rewrites `idr-in-bounds`'s summary
  and description.
- `IDR/Dialect/Registration`: the coordinator writes the pipeline.
- `IDR/Dialect/Ops/Check.cc`, U04's, which holds the guards' local
  folders.

## Read first

- `contracts.md` C3.3, C3.5, C2.4, C1.3 and C13.
- `findings.md` F-guard-3, F-guard-6 and F-poison-6.
- `IDR/InBounds/*` (the pass, `Prove.cppm`, `System.cppm`,
  `Induction.cppm`, `Returned.cppm`).
- `IDR/Expect/InBounds.cppm`, `IDR/Expect/Named.cppm` (how properties
  are named) and `IDR/Expect/Pass.cc`.

## Fixed decisions

- **The facts behind a proof.**
  - The index systems prove `0 <= index < length` for a guard's
    `(index, length)` operands from the same facts they use today, the
    path conditions and the lengths callers pass.
  - The array's length is now the guard's `length` operand, not read
    from the access.
- **A proof erases the guard.** `replaceAllUsesWith(guard.getChecked(), guard.getIndex())`,
  then `erase`. Nothing marks the access.
- **Dominating identical guards.** A guard dominated by another of the
  same kind with the same operands is erased the same way. Use MLIR's
  `DominanceInfo`.
- **Range proofs.** A guard of kind `nonzero`, `byte` or `range` on
  integers, or `in_bounds`, whose condition `IntegerRangeAnalysis`
  proves at its point, is erased. Use the solver the pass already runs,
  if it runs one; otherwise load `IntegerRangeAnalysis` on a
  `DataFlowSolver` once per module.
- **The pass needs no fixed position.** It no longer has to run
  immediately before `idr-lower` (C1.3). Its index systems keep their
  current inputs.
- **`no-guards=@f`** is a new property. It is named and reported as the
  existing ones are.

## Inputs

- The guard ops and their accessors from ODS (`getIndex`, `getLength`,
  `getChecked`, `getCause`).
- C3.3: a total op whose guard you erase becomes `NotSpeculatable` by
  U04's rule. You need do nothing for that.

## Outputs

- `idr-in-bounds` erasing guards.
- The two properties.

## Implement

- **The pass.** Change it from setting `in_bounds` on accesses to
  erasing proved `idr.check.in_bounds` ops. Read the index and length
  from the guard. Add the dominance and range erasure for every guard
  kind, per the fixed decisions.
- **`IDR/Expect/InBounds.cppm`.** Restate `in-bounds=@f` as above, and
  add `no-guards=@f`.
- **Sentinels.** Apply C2.4 to the five sites in `IDR/InBounds`.

## Delete

- Every write and read of the `in_bounds` property in `IDR/InBounds` and
  `IDR/Expect`.
- The `ub.poison` sentinels in `InBounds/{Returned,Components,Lengths}.cppm`.

## NOT TO DO

- Do not weaken a proof.
- Do not add a guard.
- Do not erase a guard whose condition you cannot prove at its point:
  "the access is in a loop whose bound is the length" proves nothing
  where the guard sits outside that loop.
- Do not change which programs `in-bounds=@f` accepts in
  `T/programs/arrays`. The same accesses are proved; only the
  statement changes.
- Do not write tests (U22, U23).

## Acceptance

- Every program whose `mlir.expect` says `in-bounds=@f` today still
  satisfies it, restated. The coordinator runs it.
- A guard dominated by an identical guard is gone after the pass. U22
  writes the lit test.
- `grep -rn 'InBounds()\|in_bounds' foreign/idr/lib/InBounds foreign/idr/lib/Expect`
  finds only the property's name `in-bounds`.
- **Tempting partial:** keeping a mark on the access "for the
  lowering". Rejected: the lowering no longer reads one (U05), and a
  mark is the predecessor this lane deletes.

## Escalate if

- An index system needs the access op itself, beyond the index and
  length. Report which.

## Stop and return

You are done when the pass erases guards, the properties are restated
and added, and the sentinels are gone. Return the changed paths,
`Verification: NotRun (swarm policy)`, and seams.
