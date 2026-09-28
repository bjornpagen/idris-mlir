# 14. Testing and conformance

Tests check exit status and produced artifacts, never just stdout. A test
that cannot run because a toolchain is missing is reported as skipped, with
the reason, and never counted as passed.

## Commands

- **TEST-CMD-1 (p0).** `make` runs every suite (`make` alone lists the
  commands):

  | Command | Runs | When |
  | --- | --- | --- |
  | `make check` | `tests/spec` (repository rules, `TEST-SPEC-1`) | always |
  | `make build` | the C++ `dev` preset and the Idris compiler | after any code change |
  | `make test` | `tests/compiler`, `tests/profile`, `tests/e2e`, `tests/determinism`, `tests/registry`, `tests/toolchain` | after compiler changes |
  | `make test-idr` | `tests/idr`, with `FileCheck` | after C++ or contract changes |
  | `make test-mlir-tools` | `tests/mlir` | after changing upstream MLIR usage |

  The suites are golden tests on Idris's own `Test.Golden`, run by
  `tests/Main.idr`. A test is a directory with a POSIX-sh `run` script and
  an `expected` file; `run` prints the exit status of what it runs and the
  artifacts that must exist, so every test checks both. Each command ends
  with the number of tests that passed and the list of those that failed,
  and exits non-zero if any test failed. A command whose pinned toolchain is
  missing or stale refuses to run and names the bootstrap step to run
  (`TC-PIN-2`); nothing is skipped silently.

## Oracles

- **TEST-ORACLE-1 (v0).** An end-to-end accept fixture is a directory with:
  - `Prog.idr`, the program;
  - `Oracle.idr`, which imports `Builtin` and `Prog` and contains exactly
    one proof `check : Prog.main = <integer literal>` with `check = Refl`.
    Every definition of `Prog` is `public export`, because Idris reduces
    only public definitions of other modules.

  The harness asserts that:
  1. the pinned stock `idris2 --no-prelude --check Oracle.idr` succeeds, so
     Idris's own evaluator agrees with the expected value (`SEM-REF-1`);
  2. `DRV-FLOW-1` succeeds and writes every artifact;
  3. the executable exits with the literal `mod 256`;
  4. stdout and stderr are empty.
- **TEST-ORACLE-2 (v0).** A fixture whose result Idris cannot evaluate at
  type-checking time, such as `tests/e2e/v0/tail-loop-deep`, instead has an
  `expected-exit` file and a comment deriving the value. Only
  resource-behaviour tests may use this form.
- **TEST-IO-1 (v1).** An IO fixture is a directory with `Main.idr` (and any
  other user modules), optionally `stdin`, and `expected-stdout` and
  `expected-exit`. The harness asserts that:
  - `DRV-FLOW-2` succeeds;
  - running the program with that stdin produces exactly `expected-stdout`,
    byte for byte, and the expected exit status;
  - stderr is empty unless the fixture expects a crash.

  Pure parts of IO fixtures also get `Refl` oracles where Idris can evaluate
  them.
- **TEST-DIFF-1 (v1).** Every IO fixture is also compiled with the stock Chez
  backend:

  ```sh
  idris2 --no-prelude --cg chez -o prog Main.idr
  ```

  Both executables MUST produce identical stdout and exit status on the same
  stdin. This is possible because programs do their IO through the Prelude,
  which the Chez backend implements (`PROF-IO-4`); fixtures put only ASCII
  characters with `putChar`, where the two agree (`SEM-IO-2`). Crash
  messages are not compared (`SEM-DEV-1`).
- **TEST-ELIM-1 (v1).** Each `ELIM-*` rule has tests on the module after the
  simplify loop: a small program, its expected MLIR after `idr-simplify`
  (checked with `FileCheck` on `idris-mlir-cc --dump-after=all` output,
  `DRV-DUMP-1`), and an e2e run. They are `tests/e2e/v1/ELIM-G-*` and the
  other e2e fixtures with an `mlir.check` file; the first line of the file
  may choose another module (`// input: emitted` for what `Emit` wrote,
  `// input: after <step>` for another step). *Revised at the cutover:*
  before, a `core.check` file matched first-order Core after `Simplify`.
  The passes also have their own tests in `tests/idr/` (`TEST-IDR-1`).
- **TEST-CRASH-1 (v0).** A crash fixture has an `expected-crash` file. The
  harness asserts exit status 1, empty stdout, and a stderr that contains
  the cause it names (`SEM-CRASH-1`).

## Profile fixtures

- **TEST-REJ-1 (v0).** A reject fixture is
  `tests/profile/vN/reject/<RULE-ID>-<desc>.idr`. Its first line is
  `-- expect: <RULE-ID> line <n>`. The harness asserts that:
  - `idris-mlir … --check` exits 1 (for `PROF-PROG-1`, which Idris never
    passes to the backend, the `DRV-FLOW-1` chain fails with it instead);
  - the message contains `unsupported (<RULE-ID>)`;
  - the reported location is on line `n`;
  - no `.core` or `.mlir` file exists afterwards.
- **TEST-ACC-1 (v0).** An accept fixture is
  `tests/profile/vN/accept/<RULE-ID>-<desc>.idr`. The harness asserts that
  it compiles through `DRV-FLOW-1` with every artifact written. If an oracle
  accompanies it, the fixture is also run.
- **TEST-VER-1 (v1+).** Every accept fixture of a version remains an accept
  fixture of all later versions with the same oracle (`PROF-GEN-4`), but
  for the exceptions `PROF-GEN-4` lists, each with its reason. A changed
  expectation keeps its program: a fixture split at the cutover keeps its
  total part as an accept and moves the rest to a named reject fixture.

## C++ and contract tests

- **TEST-IDR-1 (v0).** Every `idr` op, verifier, folder, canonicalization,
  effect rule and pass, and every conversion pattern, has tests in
  `tests/idr/`. They run
  hand-written `.mlir` through `idris-mlir-opt` and check the result with
  `FileCheck`, without involving Idris. Each `.mlir` file keeps its
  `// RUN:` lines, which the `lit` function of `tests/testutils.sh` runs as
  lit's internal shell did, without lit or Python: `%s` is the file, `%t` a
  path in the work directory, and `%status N cmd` checks an exact exit
  status.
- **TEST-EMIT-1 (v0).** The Idris side's output is checked against the
  contract with `FileCheck` on the `.mlir` of selected fixtures (erased
  arguments present, quantity attributes, locations, match shape: an
  `mlir.check` with `// input: emitted`), and by the dialect's verifiers
  when `idris-mlir-cc` parses every fixture's output (*revised at the
  cutover*: before, by `idr-check-input`). A test checks that `Emit` names
  only the dialects of `IDR-IN-1` and writes no flag `IDR-IN-2` forbids
  (`TEST-ENF-1`).

## Whole-program properties

- **TEST-HEAP-1 (v0).** For every end-to-end program, the undefined symbols
  of the object file (`llvm-nm --undefined-only`) are a subset of
  `{write, _exit}`, and from v1 `{write, read, _exit}`, and from v2 the
  `libm` functions of `LOW-EXT-1`. There is no `malloc` and no other libc
  call. *Revised at the cutover:* the runtime's code joins the object where
  the program reaches it (`TC-LINK-1`), and what a heap-free program
  reaches of it allocates nothing.
- **TEST-DET-1 (v0).** Compiling a fixture twice gives byte-identical
  `.core`, `.mlir` and object files (`FE-DET-1`, `DRV-DET-1`).
- **TEST-SEM-1 (v0).** Every `SEM-INT-*` rule has table-driven end-to-end
  tests over every integer type, each with a `Refl` oracle. They cover:
  - wrapping at both ends of the range;
  - `div` and `mod` with every sign combination, including `MIN` and `-1`;
  - comparisons across the sign boundary for `BitsN`;
  - every cast pair at the range boundaries.


## The two evaluations

*New at the cutover.* Compile-time evaluation runs the program's own code
(`SEM-EVAL-6`), so these suites check that it computes what the executable
computes, and what Idris's evaluator computes.

- **TEST-EQUIV-1 (v3). Equivalence.** Every e2e program that compiles both
  with and without `idris-mlir-cc --no-eval` gives, both ways, the same
  stdout and exit status on the same stdin. And in the final MLIR of every
  e2e fixture, compiled with `--remarks=idr-eval`, no closed call to a pure
  total function survives but those whose evaluation crashed.
  - *planned* (stop point 3 of the cutover)
- **TEST-FUZZ-1 (v3). The fuzzer.** Closed pure expressions over every
  primitive, generated at random, give the same value at compile time
  (folders and `idr-eval`), at runtime (`--no-eval`), and on Chez. Each
  folder is also run against its own lowering through the JIT.
  - *planned* (stop point 3 of the cutover)
- **TEST-LEVELS-1 (v3). The two levels.** Closed terms that Idris's
  evaluator normalizes in a type (`Refl` proofs) give the same value under
  `idr-eval`, for every primitive but those of `SEM-HOST-1`.
  - *planned* (stop point 3 of the cutover)
- **TEST-ENF-1 (v3). Enforcement.** Tests that fail when the division of
  labour erodes:
  - no primitive has semantics in Idris: `compiler/src` computes no
    primitive's result (no host `prim__` call, no folding);
  - `Emit` names only the dialects of `IDR-IN-1`, with no flag `IDR-IN-2`
    forbids;
  - every canonicalization has a lit test (`TEST-IDR-1`).
  - *planned* (stop point 3 of the cutover)
- **TEST-TERM-1 (v3). Termination.** A closed call to a partial function
  that diverges only on a path never taken compiles, runs, and is not
  evaluated (`SEM-EVAL-6`); an accumulator that would specialize forever
  stops at the clone limit (`ELIM-SPEC-2`) and is rejected with
  `PROF-HEAP-4` or compiles, as its closures decide.
  - *planned* (stop point 3 of the cutover)

Compile time is measured and reported for every fixture, with the slowest
broken down by pass, JIT compilation and evaluation (`idris-mlir-cc
--timing`); it is never a gate ([the plan](../plan.md), decision 13, is
withdrawn).

## Debugging a rewrite (informative)

When an optimization breaks a program (an e2e fixture's output differs, or
the verifier fails after a pass), the module and the step that broke it are
found as follows.

- **The step.** `idris-mlir --directive dump-mlir` (`DRV-DUMP-1`), or
  `idris-mlir-cc --dump-after=all --dump-dir=DIR`, writes the module after
  every step as `NN-STEP.mlir`. The first dump that is wrong names the step,
  and the dump before it is the step's input, which `idris-mlir-opt` runs
  the step on alone.
- **The rewrite.** MLIR's action framework makes every pattern application
  (`apply-pattern`) and pass run (`pass-execution`) an action that a debug
  counter can skip or limit:

  ```sh
  idris-mlir-opt in.mlir --canonicalize \
    --mlir-debug-counter=apply-pattern-skip=0,apply-pattern-count=N
  ```

  applies only the first `N` patterns. Bisecting on `N`, with the check
  that fails as the oracle, finds the one application that breaks the
  module; `--mlir-print-debug-counter` lists the actions counted.
- **A small module.** `idris-mlir-reduce` (`mlir-reduce` with the `idr`
  dialect and passes registered, built by `foreign/idr`) shrinks a module
  while an interestingness script, which exits 1 while the failure still
  happens, keeps holding:

  ```sh
  idris-mlir-reduce in.mlir -reduction-tree='traversal-mode=0 test=fails.sh'
  ```

  The reduced module becomes the regression test in `tests/idr/` that the
  fix comes with (`DIAG-ICE-1`).
## Spec conformance

- **TEST-SPEC-1 (p0).** `make check` (`tests/Spec.idr`) parses every rule
  identifier in `docs/architecture/`. A rule starts with a bold `**<ID>`, then an optional
  ` (<version>)`, then a period. It asserts that:
  1. every rule whose version has been implemented is referenced by at least
     one test file, through the identifier in its file name or a
     `rule: <ID>` comment. Exempt are rules marked *planned*, rules that name
     review as their check, and rules without a version (principles and
     reserved rules);
  2. every identifier referenced by a test exists in the spec;
  3. no identifier is defined twice.

  The implemented version is recorded in `docs/architecture/VERSION`, which
  p0 creates and each version's release updates.
