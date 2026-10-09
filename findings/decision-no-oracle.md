# Decision: no oracle; the tests' expected files are the specification

The user decided this on 2026-10-09.

- **Why.** The stock Chez backend was the tests' oracle: every e2e fixture
  was also compiled by Idris's Chez backend and its stdout and exit status
  compared, with every deliberate difference a named class in
  `tests/lib/chez-divergences`. That was the right check while the
  compiler was young. It no longer is:
  - the runtime is already the specification and Chez only the oracle
    (`decision-primitive-semantics.md`), and the list of divergences grows
    with every decision that improves on Chez (UTF-8, subnormal doubles,
    `getLine`, numbers from strings, drop timing, crashes);
  - the compiler refuses things Chez accepts (`%foreign`, C, threads,
    finalizers), so more of what matters cannot be compared at all;
  - every new feature had to be expressible on Chez first (`libs/` written
    "so that the stock Chez backend runs them unchanged", proposal 0001's
    `C:` entries and shared library), which cost design, a C path, and
    build time, to check against something the compiler is overtaking.
- **What replaces it.** Each fixture's committed expected files
  (`expected-stdout`, `expected-status`, `expected-crash`, and the rest of
  `expected`) are its specification, reviewed when they change, as any
  golden test. Behaviour is pinned by the runtime's documented semantics
  (`decision-primitive-semantics.md`) and by the properties the e2e
  harness already checks (dumps verify, quantities kept, budgets, live
  cells, determinism, the no-eval run agreeing with the evaluated one).
- **What goes:**
  - the Chez comparison in the e2e harness (`chez_agrees`, `oracle-chez`,
    `no-chez`), `tests/lib/chez.sh`, `tests/lib/chez-doubles.ss` and
    `tests/lib/chez-divergences`, and every `chez:` line of the fixtures'
    `expected` files;
  - the stock evaluator's `Oracle.idr` proofs (`tests/lib/oracle.sh`) and
    the fixtures' `Oracle.idr` files: `expected-stdout` states the value;
  - the requirement that `libs/` and future features run unchanged on
    Chez; proposal 0001's Chez entries, `C:` specs, shared library and
    divergence classes.
- **What stays:**
  - Chez Scheme as the host Idris 2 itself runs on: the frontend is built
    by the pinned Idris, which runs on the pinned Chez. That is a
    toolchain dependency, not an oracle.
  - Idris on Chez as a benchmark baseline in `bench/` (speed, not
    correctness).
- **Migration.** Before the Chez comparison goes, a fixture whose stdout
  was checked against Chez alone (`oracle-chez`) gets an `expected-stdout`
  written from this compiler's output on the same run that still agrees
  with Chez, so nothing is frozen that Chez disagreed with. Then the
  harness and files above are deleted in one change, with `make test`
  green after it.
