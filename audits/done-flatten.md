<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane flatten: one flat tests/, the harness in harness/

`tests/` now holds tests and nothing else. Each of the 703 tests is one
directory, `tests/<name>/`, all at one level. The runner, its libraries,
the templates and the property headers moved to a top-level `harness/`.
No git command was used; the orchestrator's `git add -A` records the moves
as renames.

## Counts, before and after

The before counts come from the old `tests/Main.idr` pools at the start of
this lane. The other lanes' deletions had already happened. The after
counts come from the new runner's `--list` and from full runs (arm64 macOS,
build/dev, threads=4).

| suite | before | after | run now |
| --- | --- | --- | --- |
| check | 32 | 32 | 30 pass; the 2 failures are outside this scope (below) |
| test | 462 | 463 | 362 pass, 101 fail, each on a bug a lane reported |
| test-idr | 328 | 327 | 296 pass, 31 fail: exactly the 7 + 7 + 17 that idr-a, idr-b and idr-c reported |
| test-mlir-tools | 24 | 24 | 24 pass |

The one difference is `idr/stack/hot-loop`. It is a compiled program
(Main.idr), so its kind puts it in `make test` as `hot-loop` (idr-c: it
belongs with the stack programs). Directories: 703 before and 703 after.
`semantics` runs as 144 instances, `semantics@prim-<type>-<op>`, which the
test count includes.

`make check` fails on two tests, both outside this scope:
- **file-size:** 8 C++ units are over 400 lines (SUMMARY 5 #37).
- **licenses:** `bench/chameneos-redux/compare` has no comment syntax, and
  `audits/{machinery,done-game-chameneos-redux,done-game-regex-dna,done-game-thread-ring}.md`
  have no SPDX line.

## The layout and the one way of each thing

- **A test's kind is what it holds** (`kindOf` in harness/Main.idr). A
  `run` script is a scripted test. Otherwise a `Main.idr` is a compiled
  program, and a refused one when its first line is
  `-- expect: <rule>, line <n>`. Otherwise exactly one `.mlir` file is a
  dialect fixture. Any other directory, or a file, directly in `tests/`
  stops the runner with the reason ("tests/ holds what is no test"). So no
  leftover can sit there unread. Dotfiles (`.DS_Store`) are ignored.
- **Suite by kind, overridden by one declared fact.** A fixture is in
  `test-idr`; every other kind is in `test`. A `suite` file holding one
  word overrides that, the same way for every kind. It is used by:
  - the 32 repository tests (`check`);
  - the 24 upstream tests (`test-mlir-tools`), 6 of them programs;
  - three scripts that stay in `test-idr`: `expect-coverage`,
    `pipeline-timing` and `e2e-even-group` (a lit fixture with a longer
    time limit).

  An unknown suite name stops the runner.
- **Each kind runs one way.** `harness/one.sh RESULTS COMPILER KIND TEST`
  runs a test in its directory: its own `./run`, or `harness/kinds/<kind>`
  (`program`: `e2e_io .`; `reject`: `profile_reject .`; `fixture`:
  `lit_fixture`). The expectation is `expected[.<host>]`, or for a fixture
  the kind's own: `harness/kinds/fixture.expected`, "RUN lines: each holds".
- **Outputs left the tests.** A run writes to
  `harness/build/output/<name>`, not to `<test>/output`. The 378 stale
  `output` files were deleted, and so was the `.gitignore` rule for them.
  This is MACH-15, which machinery deferred to this lane. The results
  directory and the timing records are under `harness/build/` too.
- **The runner.** harness/Main.idr and Runner.idr were rewritten around
  `Kind`, `Test` and `Pool` (runs paired with their kind). The topic pool
  list and `subpools` are gone. The new `--list` prints the selected test
  names; this lane's counts come from it. `only=`/`except=` still match
  substrings, now of flat names.
- **Fixtures carry no harness files.** Each dialect fixture is
  `tests/<name>/<name>.mlir` alone. Its `run` (`lit ../x.mlir`) and its
  `expected` (only `RUN n: ok` lines) were deleted: 324 of each.
  `lit_fixture` refuses any other file beside the module (a `suite` or
  `targets` file is allowed).
- **Program tests carry no run script.** 271 `run` scripts were deleted:
  193 `e2e_io .`, 43 `profile_reject .` and 35 `profile_accept .`. Their
  kind runs them. The comments of 6 upstream-program run scripts (which
  pull-request.diff the fork carries, and when the test goes) were moved
  into the top comment of their Main.idr. These programs compile and are
  not refused, so no line number they depend on moved. The comments of the
  other 5 (registry, hot-loop) repeated what their Main.idr already says.
- **One program runner.** `profile_accept` is deleted, because an accepted
  program is a compiled program. `e2e_io` now runs a program only when it
  states what running gives (`expected-stdout`, `expected-exit` or
  `expected-crash`). A program that states none is compiled only (today
  `nonterminating`). Such a program may carry no file that only a run
  reads (`stdin`, `live-cells`, `constant-stack`, `default-stack`,
  `libm-lines`). The 35 accept transcripts were reordered to e2e's order
  (universal last); the 6 upstream ones among them pass.
- **Dead harness removed:**
  - `lib/two-levels.sh` and the runner's `--two-levels-program` and
    `--two-levels-check` (no test uses them since the two-levels test was
    deleted; done-accept-reject flagged them). TwoLevels.idr stays,
    because Fuzz.idr and fuzz-two-hosts read its checks; its doc no longer
    names a test path.
  - profile_reject's `idris` header branch (no fixture names it).
  - The single-file fixture paths of `profile_prepare` and `fixture_name`.
- **`harness/`** holds: Main.idr, Runner.idr, harness.ipkg (was
  tests.ipkg), one.sh (was tests/runner/one.sh), testutils.sh, lib/,
  kinds/, prop/ (was tests/toolchain/lib: prop.h, prop.sh, bigmodel.h,
  utf8model.h), templates/ (one per kind: fixture, program, reject,
  script), Fuzz/Gen/Lock/Prims/Sem/TwoLevels.idr, README.md (rewritten
  short; it replaces tests/README.md), and build/.
- **`reject/without-fixture`** is now `tests/rules-covered/without-fixture`,
  the data of the test that reads it.
- **`harness/lib/harness.sh`:** `here` is the directory the test runs in
  (`$(pwd)`), because a kind's script is not in the test's directory. To
  run a script by hand, run it from its directory. `copy_fixture` no longer
  copies `expected.*`, `suite` or `targets` into the build.

## Names

Every test is `tests/<name>`. The renames follow these rules (the full
table is the rename set git records):
- **idr/<pass>/<x>:** `<pass>-<x>`, unless `<x>` already starts with or is
  the pass (`contify/contify` → `contify`, `identity/identity` →
  `identity`). The pass is what makes a fixture's name meaningful
  (`defunc-choice`, `rc-arrays`). The `.mlir` file is renamed to the
  directory's name.
- **programs/<topic>/<x>, accept/<x>, reject/<x>, spec/<x>,
  toolchain/<x>, compiler/<x>:** `<x>`, which is unique. A reject name
  still starts with its rule.
- **determinism/, registry/, fuzz/, bench/, upstream/:** the topic is
  prefixed (`determinism-rbtree`, `registry-nat-operations`, `fuzz-seeds`,
  `bench-smoke`, `upstream-termination-closure`). Without it, the bare
  names collide (rbtree, shapes, records) or lose their meaning.
- **Exceptions:**
  - `programs/semantics/prim` → `semantics` (run as `semantics@<name>`);
  - `programs/interfaces/choice` → `runtime-choice`;
  - `idr/stack/hot-loop` → `hot-loop`.

## References updated

- **Makefile:**
  - `RUNNER` and the `runner` target are in harness/ (it builds
    harness.ipkg);
  - the test targets still run from tests/;
  - the opening comment and the comments on suites now describe kinds and
    `suite`.
- **Spec tests that read paths:**
  - **dialect-text:** the fixtures of printed syntax are named by their
    name prefixes `asm-`, `syntax-` and `verify-`, plus
    `lower-llvm-facts`, in place of their old directories;
  - **prelude-coverage:** `tests/*/covers`;
  - **rules-covered:** every `tests/*/Main.idr` whose header names a rule;
  - **zones:** `harness/prop/*.h` and `tests/runtime-*/*.{cpp,h}`;
  - **verifier-every-pass:** `tests/*/*.mlir`;
  - **frontend-imports:** searches tests/ and harness/;
  - **expect-coverage:** a property must fail in some fixture of tests/,
    not only in the expect fixtures.
- **Scripted tests:**
  - determinism-shapes and determinism-threads-linarray-lanes;
  - handoff-round-trip and frontend-beside;
  - runtime-prepared, executable-pages and static-linking;
  - prop.sh;
  - fuzz-two-hosts, which copies its modules from harness/.
- **tools/:**
  - licenses.sh: `*/suite`, `*.expected` and the templates' sources are
    exempt as fixture data;
  - compile-times.sh: harness/build/timing;
  - verify-pins.sh, and the comment of upstream-idris/one.
- **AGENTS.md** (`tests/upstream-<bug>`), README.md, HANDOFF.md, PINS.md,
  the representation-first skill, bench/README.md, upstream/README.md and
  the bug READMEs, compiler/idris/README.md.
- **Comments only:** SyntaxSamples.idr, runtime/CMakeLists.txt,
  runtime/Io/Io.h and runtime/check-archive.sh.
- **Cross-references inside fixtures:**
  - `world/world-twice` → `world-once`;
  - `defunc/lazy-choice` → `defunc-memo-sum`;
  - verify-flow, canon-facts and pipeline-one-pipeline;
  - the comments of the reject programs, edited in place so their line
    numbers did not move.
- **The idr-c note:** PINS.md now names `tests/linarray-lanes-exact` for
  vectorize/lanes-x86-64. upstream/22 names `tests/vectorize-rows`.
- **proposals/:** every exact test path was rewritten mechanically.
  References to an old topic directory (`tests/idr/rc`, `tests/programs`)
  are left in the dispatch and lane prompts of past swarms, as the record
  of what those swarms were given. `audits/` is the record of this audit
  and was not rewritten.

## Tests left failing, each on a compiler bug a lane reported

- **test-idr (31):** idr-a's 7, idr-b's 7 and idr-c's 17, under their new
  names. For example, `actions/narrow-lanes` is now `actions-narrow-lanes`
  and `idr/verify/flow` is now `verify-flow`. Every one failed with the
  evidence its lane recorded. Two checked here:
  - verify-flow: an i1 capture is accepted;
  - expect-coverage: the `typed-reads` row has no fixture.
- **test (101):** each name appears in a lane's failing list:
  - programs-1, A to L: leaks, `File name too long` from the tree
    printer, MkBang polymorphism, heap-free, the owned verifier,
    llvm.call i64/ptr, idr-rc-exclusive and the rest;
  - programs-2;
  - accept-reject:
    - bounded-field and bounded-method-own: 5.38;
    - bounded-synonym, polymorphic-recursion-swapped and
      string-primitive-runtime-match: 5.12;
    - stream-take and stream-take-before: 5.20;
    - runtime-lazy-value-growing-choice: 5.10;
    - recursive-string: 5.13;
    - higher-order-dictionary: new;
    - cycle-ioref-knot: 5.29;
    - artifacts: 5.32;
    - dialect-syntax: 5.33;
    - handoff-round-trip: 5.8;
    - content-hash: new;
  - registry-* and registry-only;
  - repo-tests: bench-smoke, fuzz-seeds, fuzz-two-hosts and
    determinism-threads-linarray-lanes.

  No failure comes from the move. No diff names a harness path, an unread
  fixture file, or a missing file. The 35 accepted programs now run
  through `e2e_io`, and each that fails does so on its lane's bug.

## For the orchestrator

- `git add -A` records the renames. The deletions are:
  - the fixtures' run and expected files (324 each);
  - the programs' run scripts (271);
  - the `output` files, which were ignored and are not tracked;
  - `harness/lib/two-levels.sh`;
  - `harness/templates/dialect`, replaced by `templates/fixture` and
    `templates/script`.
- Outside this scope, still failing make check:
  - delete `bench/chameneos-redux/compare` (bench-flat said so);
  - give the four audit files above an SPDX header (this report has one).
- `harness/build/timing` keeps the records keyed by the old paths. They
  gate nothing; tools/compile-times.sh reads whatever is there, and new
  runs write records under the new names.

## What a future harness or generator must cover

- **A test kind for the semantics test.** Today it is a script with a
  parameter list kept in Main.idr's `parameterized`, the one test the
  runner knows by name. A generated kind (a `Sem` table as data) would
  remove that last name from the runner, and so would the
  `determinism@<program>` and `bench-smoke@<name>` that repo-tests asked
  for.
- **Program transcripts.** A program's `expected` can be computed from
  its fixture files when the run is good, as the fixture kind's already
  is. Computing it would remove 271 hand-kept transcripts, many
  identical. That needs the typed verdict of MACH-1, MACH-11 and MACH-14,
  and was not done here.
- **The printed-syntax exemption of dialect-text** is now a rule on name
  prefixes. A declared fact in the fixture would make it data, if the
  owner wants that rather than names.
