# U03 — Ownership declared on ops and grades: consumption, the derived owned stage, one holds-references

Mandatory findings: F-own-1 F-own-2 F-own-3 F-poison-5

## Permitted outcome

1. **Consumption.** It is declared per op in ODS (C1.1 item 1), and two
   readers derive from it:
   - `idr::consumes(OpOperand &)`, which `idr-rc` uses;
   - `idr::consumedEffects(...)`, which reports `Free` on
     `ReferenceResource` for owned operands after `idr-rc`.

   `useOf`'s `isa` list is gone. `idr.con`'s own effects and
   speculation call `consumedEffects` (C2.1). Mandatory.
2. **The owned stage is derived** (C2.2, O6).
   `bool ownership::inOwnedStage(ModuleOp)` replaces `idr.stage`. Views
   stay plain `T`. `idr.stage` and `IDR/Ownership/Stage.cppm` are gone.
   Mandatory.
3. **One "holds references".** `idr::holdsReferences(type, symbols, scope)`
   replaces the private walks in Ownership. Mandatory.
4. **The force's grade.** `idr-rc` passes `idr.force`'s operand owned at
   its last use, and `excl` where `ExclusiveAnalysis` proves it (C5.4).
   Mandatory.
5. **The guards' grade.** `idr-rc` grades the result of
   `idr.check.nonzero` and `idr.check.nonempty` as it graded the
   operand, which the guard takes over (C2.1, review R5). Mandatory.
6. **Sentinels.** The C2.4 sites in `IDR/Ownership` and
   `IDR/Facts/Evaluation.cppm` use no sentinel. Mandatory.
7. **The walk rule** (C7.2) in `IDR/Ownership/ReachesOnlyAtoms.cppm`
   and `IDR/Facts/Passed.cppm`. Mandatory.

## Owner / exclusive writes

- `IDR/Ownership`
- `IDR/Facts`
- `IDR/Dialect/Grades`
- `IDR/Dialect/Types` (new `Counted.cc`)
- `IDR/Dialect/Effects` (new `Consumed.cc`)
- `IDR/Dialect/Verify`
- `IDR/Dialect/Dialect/Initialize.cc`
- `IDR/Dialect/Ops/Lin.cc`
- `IDR/Dialect/Ops/Dest.cc`
- `IDR/Dialect/Ops/Con.cc`

**Excluded:**

- `INC/` (the coordinator applies C1.1 item 1, C1.4, and the removal of
  `idr.stage` from `IdrOps.td`).
- `IDR/Dialect/Ops/Arrays.cc` (U04 adds `consumedEffects` to the array
  ops' effects).
- `IDR/Dialect/Ops/Check.cc` (U04's guards).
- `IDR/Dialect/Ops/Lazy.cc` (U09: `ForceOp::getEffects`).
- `IDR/Narrow/Words.cppm`, U21's, which asks `inOwnedStage` (C2.2).
- `IDR/Layout`, U10's: `Layouts::counted` stays.
- `IDR/Dialect/Ops/Field.cc`, `Matches.cc` and `Tag.cc`: views stay
  plain, so their verifiers do not change.

## Read first

- `contracts.md` C1.1 item 1, C1.4, C2 (all), C3.1 (the guards), C5.4,
  C7.2 and C13.
- `findings.md` F-own-1, F-own-2, F-own-3 and F-poison-5.
- `review.md` R1, R2 and R5.
- `IDR/Ownership/{UseOf,Stage,Rc,Verify,Borrowed,OpChecks,Counting,Ops}.cppm`
  and `Ops.cc`, `IDR/Ownership/Borrow.cppm`, `Commit.cppm`,
  `ExclusiveAnalysis.cppm`, `Take.cppm` and `ReachesOnlyAtoms.cppm`.
- `IDR/Facts/Passed.cppm`.
- `IDR/Dialect/Grades/{View,IsOwned,Owned}.cc`.
- `IDR/Dialect/Ops/Con.cc`.
- `IDR/Dialect/Verify/Attributes.cc`.
- `INC/Idr.h`'s grade section.

## Fixed decisions

- **`idr::consumes(operand)`:**
  - true when the owner implements `ConsumingOpInterface` and
    `consumesOperand(number)` holds;
  - true for every operand of `func.return` and `scf.yield`, the carried
    values of `scf.condition`, and the inits of `scf.while`;
  - for `func.call`, true unless the callee borrows the parameter (the
    existing `isBorrowed`);
  - false otherwise, and false for `idr.force` (C2.1).
- **`idr::consumedEffects(op, effects)`** adds
  `MemoryEffects::Free::get()` on `ReferenceResource::get()`, with the
  operand's value, for each operand `consumes` names whose grade is
  `own` or `excl`.
- **`idr.con`** has `Idr_Consumes<"0">`, the interface only. Its
  `getEffects` in `Con.cc` reports what it reports today (`Allocate` for
  a box) and then calls `consumedEffects`. Its `getSpeculatability` is
  today's (`NotSpeculatable` for a box, `Speculatable` for a sum), except
  that a sum with an `own` or `excl` field is `NotSpeculatable`: hoisted
  out of a branch, it would take a reference on a path that never gave
  it one.
- **`idr::view(type)`** is unchanged: views are plain.
- **`ownership::inOwnedStage(ModuleOp)`** is true when any operand,
  result or block argument in the module has permission `own` or
  `excl`. One walk. Callers ask once per pass or per verification, and
  pass the answer down.
- **`idr-rc`** grades as it goes, so it hands its own stage to
  `Counting` and `isBorrowed` explicitly instead of asking the module.
- **`OpChecks.cppm`** needs no module query. A `dup`'s result and a
  `drop`'s operand are owned by their ODS types.
- **`idr.force`'s operand** is owned at its last use, and `excl` when
  `ExclusiveAnalysis` proves the cell exclusive there, exactly as
  `idr.take`'s is. Otherwise it is a view. This is the one place that
  makes a force an owned use.
- **A guard's result** (`check.nonzero`, `check.nonempty`) gets its
  operand's grade, which `SameOperandsAndResultType` requires. The guard
  is a consuming use of the operand. `ReadFrom.cppm` does not treat the
  result as a view.

## Inputs

- The C1.1 item 1 ODS: `Idr_ReferenceResource`,
  `ConsumingOpInterface`, `Idr_Consumes` and `Idr_ConsumesOnly`.
- The C1.4 declarations.
- The C2.1 table.
- `ConAttr`'s C7.2 accessors (`getRunCells`, `getTail`, `getField`),
  U19's.

## Outputs

- `IDR/Dialect/Effects/Consumed.cc`, defining `idr::consumes` and
  `idr::consumedEffects`.
- `IDR/Dialect/Types/Counted.cc`, defining `idr::holdsReferences`.
- `inOwnedStage`, exported from the `idr.ownership` module.
- The `consumedEffects` calls in `Con.cc`, `Lin.cc`, `Dest.cc` and
  `IDR/Ownership/Ops.cc`'s `getEffects`.

## Implement

- **`Consumed.cc`.** Define the two functions per the fixed decisions.
  Keep `consumes` free of op-specific `isa` lists except the upstream
  ops named.
- **`UseOf.cppm`.** `useOf(operand, symbols)` becomes
  `consumes(operand) ? Use::Consume : Use::Borrow`, and the enum stays.
- **`Counted.cc`.** `holdsReferences` answers per carrier:
  - str, big, nat, box, fn, lazy, token and arrays: yes;
  - scalars, the world and erased: no;
  - an unboxed sum: whether any constructor field of its declaration
    holds references, looked up from `scope` through `symbols`, with a
    visited set for recursive declarations.

  It looks through `!idr.q`. `IDR/Ownership/Counting.cppm`'s `counted`
  and every other such walk in your files call it.
- **`Con.cc`.** `getEffects` and `getSpeculatability` per the fixed
  decision. Its verifier is unchanged.
- **The stage.** Replace each reader of `idr.stage`:
  - `Rc.cppm`: "already in the owned stage" asks `inOwnedStage` once;
    the stage it builds is passed to `Counting` and `isBorrowed`;
  - `Borrowed.cppm`: takes the stage as a parameter;
  - `OpChecks.cppm`: no query;
  - `Verify.cppm`: the owned-stage verifier asks `inOwnedStage` once
    per module verification;
  - `IDR/Dialect/Verify/Attributes.cc`: the `idr.stage` entry goes.
- **The guards.** `Rc.cppm` (and `Commit.cppm` where it writes result
  grades) gives a guard's result its operand's grade.
- **The walkers.** `ReachesOnlyAtoms.cppm` and `Passed.cppm` follow a
  list's spine through `getRunCells()` and `getTail()`, never
  `getFields()[s]` (C7.2).
- **`Initialize.cc`.** Change it only if a new interface or resource
  needs registering; ODS-declared ones do not.
- **`Lin.cc`, `Dest.cc`, `IDR/Ownership/Ops.cc`.** Their ops' existing
  `getEffects` call `idr::consumedEffects(*this, effects)` too.
- **Sentinels.** Apply C2.4 to the five sites in your files.

## Delete

- `IDR/Ownership/Stage.cppm`, every import and use of its stage
  attribute, and the `idr.stage` entry in
  `IDR/Dialect/Verify/Attributes.cc`.
- The `isa<...>` list in `useOf`.
- `counted` in `IDR/Ownership/Counting.cppm`, and every other private
  holds-references walk in your files.
- The five `ub.poison` sentinels.

## NOT TO DO

- Do not grade views. A `borrow` grade on views is O6's alternative,
  not this lane (C2.2).
- Do not change what `idr-rc` decides: placement, borrowing, reuse and
  exclusivity stay. Only the stage, the force's operand and the guards'
  results change.
- Do not change `Layouts::counted`.
- Do not add a type interface for holds-references (C2.3 refutes it).
- Do not add effects to ops outside the C2.1 table.
- Do not edit the array, guard or lazy ops' files.

## Acceptance

- After `idr-rc`, no module carries `idr.stage`, and
  `grep -rln 'idr\.stage' foreign/idr/lib` finds nothing outside
  `IDR/Narrow`, which U21 adapts.
- The owned-stage rule runs on a module with an `own` value and no
  `idr.stage`: an owned value that is never consumed is rejected. U22
  writes `T/idr/ownership/owned-stage`.
- Before `idr-rc`, `idr.con` with plain fields has no effects:
  `isMemoryEffectFree` holds, and `canonicalize` erases an unused one.
  After it, an unused `idr.con` of owned fields is kept by
  `remove-dead-values`. U22 writes `T/idr/ownership/consumed-effects`.
- A guard on a string's last use takes it over: no `drop` of the operand
  comes before the result's last read.
- Program outputs and `IDRIS_RT_LIVE=1` counts are unchanged. That is
  the coordinator's run.
- **Tempting partial:** keeping `idr.stage` "as a cache" beside the
  derived stage. Rejected: two homes for one fact.
- **Tempting partial:** making the effects unconditional. Rejected: it
  makes every `idr.con` impure before `idr-rc` and stops the simplify
  loop's DCE.

## Escalate if

- `ConsumesOperands<...>::Impl` cannot reach
  `getODSOperandIndexAndLength`, or the interface's default method
  cannot call `consumedByTrait`. Report the compile error you foresee
  and the ODS text that works.
- A reader of the stage outside your files and U21's appears. Report
  the path.
- A module with no `own` or `excl` value still has a counted value whose
  stage matters. Report the case.

## Stop and return

You are done when the seven outcomes are in your files and the Delete
list has no survivor. Return the changed paths, `Verification: NotRun (swarm policy)`,
and seams.
