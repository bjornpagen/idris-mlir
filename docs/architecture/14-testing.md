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
- **TEST-ELIM-1 (v1).** Each `ELIM-G-*` rule has Core-level tests: a small
  program, its expected Core after `Simplify` (checked with `FileCheck` on
  `--directive dump-core` output, `prog.dump/02-simplify.core`), and an e2e
  run. They are `tests/e2e/v1/ELIM-G-*`, with a `core.check` file.
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
  fixture of all later versions with the same oracle (`PROF-GEN-4`).

## C++ and contract tests

- **TEST-IDR-1 (v0).** Every `idr` op, verifier, folder, effect rule and
  pass, and every conversion pattern, has tests in `tests/idr/`. They run
  hand-written `.mlir` through `idris-mlir-opt` and check the result with
  `FileCheck`, without involving Idris. Each `.mlir` file keeps its
  `// RUN:` lines, which the `lit` function of `tests/testutils.sh` runs as
  lit's internal shell did, without lit or Python: `%s` is the file, `%t` a
  path in the work directory, and `%status N cmd` checks an exact exit
  status.
- **TEST-EMIT-1 (v0).** The Idris side's output is checked against the
  contract with `FileCheck` on the `.mlir` of selected fixtures (erased
  arguments present, quantity attributes, locations, switch shape), and by
  `idr-check-input`.

## Whole-program properties

- **TEST-HEAP-1 (v0).** For every end-to-end program, the undefined symbols
  of the object file (`llvm-nm --undefined-only`) are a subset of
  `{write, _exit}`, and from v1 `{write, read, _exit}`, and from v2 the
  `libm` functions of `LOW-EXT-1`. There is no `malloc` and no other libc
  call: no runtime code is reached (`TC-LINK-1` joins only what is).
- **TEST-DET-1 (v0).** Compiling a fixture twice gives byte-identical
  `.core`, `.mlir` and object files (`FE-DET-1`, `DRV-DET-1`).
- **TEST-SEM-1 (v0).** Every `SEM-INT-*` rule has table-driven end-to-end
  tests over every integer type, each with a `Refl` oracle. They cover:
  - wrapping at both ends of the range;
  - `div` and `mod` with every sign combination, including `MIN` and `-1`;
  - comparisons across the sign boundary for `BitsN`;
  - every cast pair at the range boundaries.

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
