# U22 — The dialect suite: discriminators in tests/idr

Mandatory findings: none

## Permitted outcome

1. **The new lit tests.** Every `T/idr/...` row of C12 is written as a
   lit test in the suite's form: `name.mlir` with `RUN:` lines, beside
   `name/run`. Mandatory.
2. **The retired mechanisms leave the suite.** Every existing test under
   `T/idr` that names a retired mechanism (README "Retired mechanisms")
   is restated in the new terms. A test whose only purpose was the
   retired mechanism is deleted. Mandatory.

## Owner / exclusive writes

- `T/idr`

**Excluded:**

- Every other test directory (U23, or U01 for `T/upstream`).
- Every compiler and runtime file.

## Read first

- `contracts.md` C12 (all), C13, and the sections each test names.
- README "Retired mechanisms".
- `tests/README.md`.
- Three existing tests per directory you touch, to copy their form:
  `T/idr/defunc/`, `T/idr/in-bounds/`, `T/idr/fold/`, `T/idr/eval/`.
- `grep -rln 'in_bounds\|idr.stage\|jit\|idr.suspend\|idr-dead-values\|lazy_kept' tests/idr`.

## Fixed decisions

- **Each test states a property** (AGENTS.md "Tests check behaviour").
  - Use `CHECK-NOT` for what must be gone, and `CHECK` for what must
    be there. Use `idr-expect` properties where a test is about a
    module's shape.
  - Never match SSA names, clone numbers or function order.
- **The directories:**
  - `guards/` (new);
  - `isolate/` (new);
  - `defunc/memo-*` and `defunc/unknown-lazy`;
  - `lower/` for `force-*`, `static-thunk`, `no-mode`, `entry` and
    `meter`;
  - `ownership/` for `consumed-effects` and `owned-stage`;
  - `constants/` (new);
  - `verify/` (new), for `cycle`;
  - and the restated `in-bounds/` tests.
- **The new ops' syntax** is C1.1's assembly formats. Where a format is
  open, write the generic op form (`"idr.check.nonzero"(%x) {cause = "..."}`).

## Inputs

- C1.1's op definitions and C12's table.

## Outputs

- The lit tests, and the restated or deleted old ones.

## Implement

- One test per C12 `idr/` row, at least.
- For `guards/speculation`, use an `scf.while` whose condition is
  `%i < idr.str.length %s`, with `%s` and `%i` loop-invariant and
  `idr.str.index %s, %i` (its guard proved away) at the top level of the
  after region. Run `loop-invariant-code-motion` and check that the index
  is still in the loop. `licm` visits only a loop body's top-level ops,
  so an op inside an `scf.if` would prove nothing (C12).
- For `ownership/owned-stage`, write a module with no `idr.stage` and
  an `!idr.own` value that is never consumed, and check with
  `-verify-diagnostics` that the owned-stage rule rejects it. At ee4ce8e
  it passes, since the rule runs only under the attribute. Check also
  that `idr-rc`'s output carries no `idr.stage`.
- For `constants/run`, check that a list written cell by cell in text and
  the same list written as a run print the same, and that both
  round-trip through bytecode.
- Restate the old tests.

## Delete

- Tests whose only subject was `in_bounds $in_bounds`, the `jit` option,
  `idr.stage`, `idr-dead-values`, or the code-pointer suspension. Each
  is restated if it has another subject.

## NOT TO DO

- Do not write program tests (U23).
- Do not weaken a test to pass. A test that cannot be stated is a seam.
- Do not run the suite (C13).

## Acceptance

- Every C12 `idr/` row has a test.
- At integration, each new test fails against ee4ce8e's tools, or shows
  the old mechanism, and passes after. The coordinator runs both once.
- `grep -rn 'in_bounds \|idr.stage\|jit=' tests/idr` finds nothing.
- **Tempting partial:** a test that greps for the new op's name.
  Rejected: that tests that a name exists, not the property C12 states.

## Escalate if

- A C12 row cannot be observed in the dialect suite. Report it, and
  propose the program test U23 should write instead.

## Stop and return

You are done when every `idr/` row of C12 has a test and no test names
a retired mechanism. Return the changed paths, the list of deleted
tests with the reason for each, `Verification: NotRun (swarm policy)`,
and seams.
