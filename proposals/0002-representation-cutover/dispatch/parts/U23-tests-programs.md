# U23 — The program suites: discriminators, rejections, divergences

Mandatory findings: none

## Permitted outcome

1. **The new tests.** Every C12 row under `programs/`, `reject/` and
   `accept/` is written as a test of its kind, from `T/templates`.
   Mandatory.
2. **The divergence class `gc-clock`.** It is added to
   `T/lib/chez-divergences`, with the reason C9.4 gives. Mandatory.
3. **The registry tests.** `T/registry` covers the new primitives and
   exclusions. Mandatory.
4. **Retired mechanisms.** Every existing program, accept, reject,
   registry, compiler or properties test that names a retired
   mechanism, or asserts a rejection this packet removes (for example a
   reject fixture for `getEnv` as a raw pointer), is restated or
   deleted. Mandatory.
5. **The runtime's C clients** under `T/toolchain` follow C1.5 (review
   R12): `runtime-api/rc.c` names the thunk kind, and
   `runtime-start/start.c` and `page-size-mismatch/start.c` call the
   four-argument `idris_rt_start`. Mandatory.

## Owner / exclusive writes

- `T/programs`
- `T/accept`
- `T/reject`
- `T/properties`
- `T/lib`
- `T/Main.idr`
- `T/registry`
- `T/compiler`
- `T/toolchain`

**Excluded:**

- `T/idr` (U22).
- `T/upstream` (U01 owns its three directories; the rest stay).
- `T/spec` (the coordinator's).
- `T/upstream-idris` (its results file is the coordinator's
  qualification output).

## Read first

- `contracts.md` C12 (all), C9 (all), C10, C1.5, C13, and the sections
  each test names.
- `review.md` R9, R11 and R12.
- `tests/README.md` and `T/templates/`.
- `T/testutils.sh` (the marks a fixture may carry).
- `T/lib/chez-divergences` and `T/lib/run.sh` (the live-cell rule; no
  arguments are passed).
- `T/toolchain/runtime-api/rc.c`, `T/toolchain/runtime-start/start.c`
  and `T/toolchain/page-size-mismatch/start.c`.
- `T/programs/eval/lazy-double`, the pattern for a test whose
  recomputation would exceed the timeout.
- `grep -rln 'getEnv\|RawPointer\|raw pointer\|%foreign' tests/reject tests/accept tests/registry`.
- Three tests from each of `T/programs/io`, `T/programs/eval` and
  `T/reject`.

## Fixed decisions

- **Names.** Test names are those in C12. A new topic directory joins
  its pool in `T/Main.idr`.
- **Programs against Chez.** Every program test runs against the stock
  Chez backend where C12 says "Chez". It differs only by a named class.
- **The files test** works in its own `mktemp -d` directory, removed
  after, and has a timeout as every test does.
- **The directory listing is sorted** before printing, because the
  order of entries is the file system's.
- **The environment test** prints `length !getArgs`, never `argv[0]`,
  which differs between the native binary and Chez's `(command-line)`
  (review R9). It sets its own variable with `setEnv` and reads it back,
  and reads an unset name; it never prints a host variable's value. It
  runs with `IDRIS_RT_LIVE=1` and ends with 0 live cells.
- **`memo-shared-stream`** observes memoization without an effect
  (review R9): a top-level and a local `fibs`, each shared by two
  consumers, sized so that recomputation exceeds the test's timeout, as
  `eval/lazy-double` is. It forges no world and counts nothing; a
  `by_name` label would not memoize, and user code may not forge a
  world.
- **`lazy-elements`** writes suspensions into an `IOArray (Lazy Int)`
  and forces each twice, against Chez (review R7).
- **`exit-with`** writes a line, then `exitWith (ExitFailure 3)`. It
  carries `expected-exit` 3 and expects no live-cell report
  (review R11).
- **The toolchain C clients.** Rename the kind in `rc.c` to the thunk
  kind of C1.5. Pass `argc` and `argv` from `main` as the third and
  fourth arguments of `idris_rt_start` in both `start.c` files.
- **`guards-messages`** copies each expected crash message from
  ee4ce8e's output, run by the coordinator before integration or taken
  from the existing tests that cover them.

## Inputs

- C12, C9's names, and C10's messages.

## Outputs

- The tests, the divergence class, and the restated suites.

## Implement

- Per the fixed decisions.
- One test per C12 row of these kinds, at least.

## Delete

- Reject fixtures that assert a rejection this packet removes. For
  example, a pointer fixture whose primitive is now a handle becomes an
  accept or program test: rewrite it, do not keep it red.
- Tests whose only subject is a retired mechanism.

## NOT TO DO

- Do not edit `T/spec`, `T/idr` or the compiler.
- Do not weaken an expected output to pass.
- Do not run the suites (C13).
- Do not add a divergence class beyond `gc-clock`.

## Acceptance

- Every C12 row of these kinds has a test.
- At integration, each new test fails against ee4ce8e, or shows the old
  mechanism, and passes after. The coordinator runs both once.
- `tests/spec/frontend-imports`, run alone (common obligations),
  passes: no test module imports the Idris compiler. Do not run
  `make check`.
- **Tempting partial:** a reject fixture that only checks "some error".
  Rejected: it must check the `unsupported (<rule>)` and the line, as
  every reject fixture does.

## Escalate if

- A C12 row's behaviour cannot be observed from a program. Report it,
  and propose a lit test for U22.
- Chez gives an output for a base primitive that C9.2's meaning
  contradicts. Report both outputs.

## Stop and return

You are done when every C12 row of these kinds has a test, `gc-clock`
exists, and no test asserts a removed mechanism. Return the changed
paths, the deleted or rewritten tests with reasons,
`Verification: spec/frontend-imports (run) / suites NotRun (swarm policy)`,
and seams.
