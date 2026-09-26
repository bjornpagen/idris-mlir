# 14. Testing and conformance

Tests check exit status and produced artifacts, never just stdout. A test
that cannot run because a toolchain is missing is reported as skipped, with
the reason, and never counted as passed.

## Commands

- **TEST-CMD-1 (p0).** `tools/dev.py` runs every suite:

  | Command | Runs | When |
  | --- | --- | --- |
  | `check` | `tests/tooling` (repository rules, `TEST-SPEC-1`) | always |
  | `build` | the Idris compiler and the C++ `dev` preset | after any code change |
  | `test` | `tests/compiler`, `tests/profile`, `tests/e2e` | after compiler changes |
  | `test-idr` | `tests/idr` via `lit` and `FileCheck` | after C++ or contract changes |
  | `test-mlir-tools` | `tests/mlir` | after changing upstream MLIR usage |

  Each command ends with a summary line of passed, failed and skipped
  tests. It exits non-zero if any test failed.

## Oracles

- **TEST-ORACLE-1 (v0).** An end-to-end accept fixture is a directory with:
  - `Prog.idr`, the program;
  - `Oracle.idr`, which imports `Builtin` and `Prog` and contains exactly
    one proof `check : Prog.main = <integer literal>` with `check = Refl`.

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
- **TEST-CRASH-1 (v0).** A crash fixture has an `expected-crash` file. The
  harness asserts exit status 1, empty stdout, and a stderr that contains
  the cause it names (`SEM-CRASH-1`).

## Profile fixtures

- **TEST-REJ-1 (v0).** A reject fixture is
  `tests/profile/vN/reject/<RULE-ID>-<desc>.idr`. Its first line is
  `-- expect: <RULE-ID> line <n>`. The harness asserts that:
  - `idris-mlir … --check` exits 1;
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
  pass, and every conversion pattern, has `lit` tests in `tests/idr/`. They
  run hand-written `.mlir` through `idris-mlir-opt` and check the result with
  `FileCheck`, without involving Idris.
- **TEST-EMIT-1 (v0).** The Idris side's output is checked against the
  contract with `FileCheck` on the `.mlir` of selected fixtures (erased
  arguments present, quantity attributes, locations, switch shape), and by
  `idr-check-input`.

## Whole-program properties

- **TEST-HEAP-1 (v0).** For every end-to-end program, the undefined symbols
  of the object file (`llvm-nm --undefined-only`) are a subset of
  `{write, _exit}` (`LOW-EXT-1`). There is no `malloc`, no runtime, and no
  other libc call.
- **TEST-DET-1 (v0).** Compiling a fixture twice gives byte-identical
  `.core`, `.mlir` and object files (`FE-DET-1`, `DRV-DET-1`).
- **TEST-SEM-1 (v0).** Every `SEM-INT-*` rule has table-driven end-to-end
  tests over every integer type, each with a `Refl` oracle. They cover:
  - wrapping at both ends of the range;
  - `div` and `mod` with every sign combination, including `MIN` and `-1`;
  - comparisons across the sign boundary for `BitsN`;
  - every cast pair at the range boundaries.

## Spec conformance

- **TEST-SPEC-1 (p0).** A tooling test parses every rule identifier in
  `docs/architecture/`. A rule starts with a bold `**<ID>`, then an optional
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
