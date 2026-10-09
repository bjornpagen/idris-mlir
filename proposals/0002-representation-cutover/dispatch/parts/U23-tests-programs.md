# U23 — The program suites: discriminators and rejections

Mandatory findings: none

## Permitted outcome

1. **The new tests.** Every C12 row under `programs/`, `reject/` and
   `accept/` is written as a test of its kind, from `T/templates`, with
   its committed expected files (C12). Mandatory.
2. **The GC clocks by their meaning.** `programs/io/clock-monotonic`'s
   `expected-stdout` states that `clockTime GCCPU` and
   `clockTime GCReal` give `Nothing`, the runtime's documented meaning
   (C9.4, O2). Mandatory.
3. **The registry tests.** `T/registry` covers the new primitives and
   exclusions. Mandatory.
4. **Retired mechanisms.** Every existing program, accept, reject,
   registry or compiler test that names a retired
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
- `T/lib`
- `T/Main.idr`
- `T/registry`
- `T/compiler`
- `T/toolchain`

**Excluded:**

- `T/idr` (U22).
- `T/upstream` (U01 owns `T/upstream/remove-dead-values-unchanged-call`;
  the rest stay).
- `T/spec` (the coordinator's).
- `T/upstream-idris` (its results file is the coordinator's
  qualification output).

## Read first

- `contracts.md` C12 (all), C9 (all), C10, C1.5, C13, and the sections
  each test names.
- `review.md` R9, R11 and R12.
- `tests/README.md` and `T/templates/`.
- `T/testutils.sh` (the marks a fixture may carry).
- `findings/decision-no-oracle.md`: a test's committed expected files
  are its specification.
- `T/lib/run.sh` (the live-cell rule; no arguments are passed) and
  `T/lib/e2e.sh` (what a program fixture's `expected` lines check).
- `T/toolchain/runtime-api/rc.c`, `T/toolchain/runtime-start/start.c`
  and `T/toolchain/page-size-mismatch/start.c`.
- `T/programs/eval/lazy-double`, the pattern for a test whose
  recomputation would exceed the timeout.
- `T/programs/semantics/crash-location`, the pattern for a crash's
  location.
- `T/programs/eval/lazy-branch-loop` and
  `T/programs/prelude/char-list-accumulated`, new at 1677b8cb. They name
  no retired mechanism, and their `mlir.expect` (a force meeting its
  suspension; reuse in place) must still hold after the cutover. Leave
  them.
- `T/programs/eval/latent-loop`, `latent-loop-delay` and
  `latent-loop-accumulator`, new at ccc3e1dc: each hung in `idr-simplify`
  before a clone of a loop breaker stayed a breaker. Their `mlir.expect`
  (`idr-simplify: every-cycle-has-breaker`) and expected files must
  still hold after the cutover (C2.4, C12). Leave them.
- The expected files phase 1b (08a065e4) wrote where the oracle was:
  the `expected-stdout` of `T/programs/arrays/buffer-ops`,
  `arrays/linarray-bubble`, `stack/forever-until-crash` and
  `stack/io-loop-through-helper`,
  `T/toolchain/double-print/expected-doubles` and
  `T/toolchain/runtime-api/expected-operations`. They are those tests'
  specification (C0, C12). Leave them.
- `grep -rln 'getEnv\|RawPointer\|raw pointer\|%foreign' tests/reject tests/accept tests/registry`.
- Three tests from each of `T/programs/io`, `T/programs/eval` and
  `T/reject`.

## Fixed decisions

- **Names.** Test names are those in C12. A new topic directory joins
  its pool in `T/Main.idr`.
- **Expected files are the specification** (C0, C12). Write each
  program test's `expected-stdout`, and its `expected-exit`,
  `expected-crash` or `stdin` where the row names one, by hand from the
  row and C9's documented meaning, never from another backend's or
  evaluator's output. Each holds on both targets, so no test prints
  `strerror`'s text, an unsorted directory order, a clock reading,
  `argv[0]` or a host variable's value. Write the `expected` transcript
  as a like fixture's is; no line of it compares with another backend.
  The coordinator reads both at integration.
- **The files test** works in its own `mktemp -d` directory, removed
  after, and has a timeout as every test does.
- **The directory listing is sorted** before printing, because the
  order of entries is the file system's.
- **The environment test** prints `length !getArgs`, never `argv[0]`,
  which is the path the harness ran the binary by, not a fixed text
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
  and forces each twice; its `expected-stdout` is the forced values,
  each twice (review R7).
- **`exit-with`** writes a line, then `exitWith (ExitFailure 3)`. It
  carries `expected-exit` 3 and expects no live-cell report
  (review R11).
- **The toolchain C clients.** Rename the kind in `rc.c` to the thunk
  kind of C1.5. Pass `argc` and `argv` from `main` as the third and
  fourth arguments of `idris_rt_start` in both `start.c` files.
- **`guards-messages-*`** are six fixtures, one per cause, since a
  program crashes once (`guards-messages-div-zero`, `-str-index`,
  `-str-head`, `-cast-nan`, `-byte`, `-array-index`). Each takes its
  expected crash message from the
  committed `expected-crash` of the existing test that covers it, which
  is its specification: division by zero
  (`programs/semantics/crash-div-zero`), the cast of NaN
  (`programs/prelude/double-cast-nan`) and an array index
  (`programs/arrays/bounds-one-past`). The three cases no test covers
  take their cause from the launch base's source, where each partial
  op states it. The swarm changes all three files (the hub has already
  deleted `Idr_StrHeadOp`'s cause, and U04 deletes the other two), so
  read each at the launch base, with
  `git show ccc3e1dc:<path>`; the text is quoted here:
  - `strIndex` out of range: `string index out of range`
    (`foreign/idr/lib/Dialect/Ops/Strings.cc:59`,
    `StrIndexOp::getCrashCause`);
  - `strHead ""`: `head of an empty string`
    (`foreign/idr/include/idr/IdrOps.td:960`, in `Idr_StrHeadOp`'s
    `getCrashCause`:
    `return ::llvm::StringRef("head of an empty string");`);
  - a byte out of range: `a byte outside 0 to 255`
    (`foreign/idr/lib/Dialect/Ops/Scalars.cc:39`,
    `ToByteOp::getCrashCause`).

  The location follows `programs/semantics/crash-location`, whose
  `expected-crash` is `division by zero at Prog.idr:6:1`: the cause,
  then `at`, then the file, line and column of the definition whose
  operation failed, in a module of its own (its `Prog.idr` says why).
  The runtime prints `idris-mlir: <cause> at <file>:<line>:<column>`,
  and `T/lib/e2e.sh` checks `expected-crash` as a fixed substring of
  stderr (`grep -qF`), so each file holds the cause and the location
  only. No run is needed to write them.

## Inputs

- C12, C9's names, and C10's messages.

## Outputs

- The tests, with their committed expected files, and the restated
  suites.

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
- Do not compare a test with Idris's Chez backend or stock evaluator,
  and do not write an expected file from either's output (AGENTS.md:
  there is no oracle).

## Acceptance

- Every C12 row of these kinds has a test.
- At integration, each new test fails against the launch base, or
  shows the old mechanism, and passes after. The coordinator runs both
  once.
- `tests/spec/frontend-imports`, run alone (common obligations),
  passes: no test module imports the Idris compiler. Do not run
  `make check`.
- **Tempting partial:** a reject fixture that only checks "some error".
  Rejected: it must check the `unsupported (<rule>)` and the line, as
  every reject fixture does.

## Escalate if

- A C12 row's behaviour cannot be observed from a program. Report it,
  and propose a lit test for U22.
- C9's documented meaning does not settle a row's expected output, or
  settles a different one on each target. Report the row and the
  candidate outputs; the coordinator settles the meaning in C9.

## Stop and return

You are done when every C12 row of these kinds has a test with its
committed expected files, and no test asserts a removed mechanism.
Return the changed paths, the deleted or rewritten tests with reasons,
`Verification: spec/frontend-imports (run) / suites NotRun (swarm policy)`,
and seams.
