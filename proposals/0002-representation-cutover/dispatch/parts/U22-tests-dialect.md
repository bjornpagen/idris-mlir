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

- **The committed files are the specification.** A test's `CHECK`
  lines, `idr-expect` properties and `name/expected` state what it
  checks. No test compares with Idris's Chez backend or stock evaluator
  (AGENTS.md: there is no oracle).
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
  In the custom form an inherent attribute (`cause`, `memo`, `labels`,
  `by_name`) goes where the op's format binds it, never in a trailing
  `{...}`: at the pin the generated parser rejects it there (20fcfadb).
- **Tests the cutover keeps as they are.** `T/idr/canon/force-of-choice`
  (new at 1677b8cb) and `T/idr/canon/held-not-read` (its `@all_constant`
  restated there) run `canonicalize` on the symbol form, which C4.4
  keeps. `T/idr/obs/budget` and `T/idr/obs/round-failure` (20fcfadb)
  test `idr-simplify`'s budget on upstream's composite pass, which U01
  does not change. An `idr.suspend` in a test of `canonicalize` or the
  simplify loop is not the retired code-pointer suspension.
  `T/idr/specialize/breaker-clones` and the raised-clone case of
  `T/idr/specialize/binding-times.mlir` (`@loop$raise$1`), new at
  ccc3e1dc, test that a clone of a loop breaker stays a breaker, which
  the cutover keeps (C2.4, C12). `T/idr/stack/hot-loop`'s
  `expected-stdout`, which phase 1b (08a065e4) wrote where the oracle
  was, is its specification (C0). Leave them all.

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
  `-verify-diagnostics` that the owned-stage rule rejects it. At the
  launch base it passes, since the rule runs only under the attribute.
  Check also that `idr-rc`'s output carries no `idr.stage`.
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
- At integration, each new test fails against the launch base's tools,
  or shows the old mechanism, and passes after. The coordinator runs both once.
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
