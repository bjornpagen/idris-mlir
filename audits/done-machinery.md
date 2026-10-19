<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Machinery lane: what was done

Scope: `tests/Main.idr`, `tests/Runner.idr`, `tests/runner/one.sh`,
`tests/testutils.sh`, `tests/lib/*.sh`, `tests/templates/`,
`tests/tests.ipkg`, `tests/README.md`, `tests/ACCEPTANCE.md`, and the test
targets of the `Makefile`. No test directory or fixture was edited, moved
or renamed. Success transcripts are unchanged: every change below alters
only what a failing, unrun or vacuous check prints, so the area lanes'
`expected` files stay valid.

## Deleted

| path | reason |
| --- | --- |
| `tests/ACCEPTANCE.md` | a hand-kept copy of a grep, 69 entries stale (MACH-2) |
| the `INTERACTIVE=--interactive` path (Makefile variable, `GOLDEN`'s flag, `runnerWith` branch and its `instanceIn`/`selected` helpers in `Main.idr`, the README's two instructions to accept with it) | ignored `expected.<host>`, so it would overwrite the Linux expectation on macOS; ran on the threaded runner that can hang (MACH-4). `--interactive`, `--timing`, `--failure-file` and `--cg` are now refused instead of being parsed and ignored |
| NEEDS-ACCEPTANCE marks in `tests/lib/properties.sh:3` and `tests/lib/lit.sh:3` | marks of no test (MACH-2) |
| `lib/rules.sh: refusal_rule` | no caller (MACH-18) |
| `lib/mlir.sh: filecheck, mlir_input, check_mlir` and `module_checks`'s mlir.check branch | the FileCheck-on-compiled-modules path; its two fixtures were converted to mlir.expect by the programs lane (MACH-18). An `mlir.check` left in a fixture now fails the test (see `fixture_files_known`) |
| `lib/heap.sh: heap_marked` | a one-line wrapper with one caller, inlined |
| 13 untracked output-only directories: `idr/actions/canonicalize`, `idr/canon/{covered-default,match-in-generate,unused-call}`, `idr/constants/run` (and the then-empty `idr/constants`), `idr/contify/never-returns`, `idr/dedup/refuse`, `idr/defunc/{block-argument,dead-move-empty-key,evaluated-refused,fit,numbering,unknown-lazy}`; plus the empty untracked `programs/linear/leet-valid-parentheses/build/exec` | litter of deleted tests (MACH-15). Each was checked with `git ls-files <dir>` empty and held only `output`. The other ~168 of the 181 had already been removed by the area lanes when this lane scanned (a rescan found no others) |

## Rewritten

**Runner (`Main.idr`, `Runner.idr`).**
- The count is against the selected tests, not the verdict files: `passed/selected`.
  A test that gave no verdict (its `one.sh` died first) is listed under
  "Tests that gave no verdict" and fails the run (MACH-3).
- Tests whose `targets` file names another host are no longer dropped
  silently. They are counted and named as "not run on this host" (MACH-3;
  AGENTS: skipped is not passed).
- A selection that matches no test fails the run ("no test matches the
  selection"). Before, a misspelt `only=` printed `0/0` and passed.
- The usage text lists only the options the runner honours.

**`runner/one.sh`.**
- On a failure it prints a unified diff of the expectation against the
  output, not two full texts.
- It captures the run script's stderr and prints it under the failing
  test's report. Before, that stderr reached the terminal with no test
  named (MACH-3).
- With no expectation it prints the whole output. That is now the way to
  write a new test's `expected`: read the output, then copy it.

**`lib/lit.sh`** (MACH-5):
- The RUN lines stop at the first one that fails, as lit does. Each later
  line prints `RUN n: not run, as RUN m failed`.
- An expected failure (`not CMD`, `%status N CMD`) goes through one
  function, `lit_fails`:
  - `not` accepts statuses 1 to 123 only, so a crash, a timeout or a
    command that cannot run does not count.
  - `not diff|cmp|grep` means exactly status 1, so a missing file (status 2)
    fails. This was the vacuous `not diff` of two files that were never
    written.
  - A failing command that asks idr-expect for properties must fail by one
    of them: its stderr must name `expected <property>:`. So a fixture that
    no longer parses no longer passes every `%status 1` line.
- A `not CMD` or `%status 1 CMD` that names no failure is refused before
  it runs (`lit_unnamed`). A line names its failure in one of these ways:
  - CMD is a decision tool (diff, cmp, grep, test, ls);
  - CMD is `idris-mlir` under `%status` (its status is its typed verdict);
  - CMD runs `-verify-diagnostics`;
  - CMD asks idr-expect for properties;
  - CMD pipes its stderr on (`2>&1 |`);
  - CMD writes stderr or `--report=` to a file that a later command reads.

  A scan of every `.mlir` under `tests/` found one such line:
  `idr/rc/counted-linalg.mlir` RUN 1, `not idris-mlir-opt %s -o /dev/null`.
- `--verify-roundtrip --idr-contracts` are now added only to an
  idris-mlir-opt that is expected to succeed. A `not` or `%status N≠0` one
  now fails for the reason its line states, not for a round-trip or
  contract failure.
- `lit_stage` (lit's pipefail) is inserted only at top-level pipes, by a
  quote-aware pass (`lit_stages`). The old `s/ | / | lit_stage /g` also
  rewrote pipes inside quoted `sh -c` and awk programs.
- `%%` is protected from substitution. Lit would turn `%%` into `%`. This
  harness leaves it as `%%`, because 8 fixtures' awk programs rely on `%%`
  reaching printf, and those fixtures belong to the idr lanes. The
  difference is documented in the comment.

**Fail closed instead of vacuously true** (MACH-19, SEARCH-1, MACH-14):
- `quantities_kept` (properties.sh) and `heap_free` (heap.sh) pick the
  module before lowering by the dump named `idr-lower`. Each now fails when
  no such dump exists. Before, it would run over lowered modules, where the
  property holds of nothing.
- `fuzz.sh`: after a step fails (the program was not generated, or a
  compile or run failed), every later check prints
  `not run: <the step>`, which fails the test. Before, it printed `ok`.
- `e2e.sh: fixture_files_known`: a fixture file that no check reads
  (a misspelt mark, a leftover `mlir.check`) fails the test. Before, it
  was copied and ignored. The list of allowed files exists only here, and
  `testutils.sh` points to it.
- `profile_accept` refuses a fixture that carries e2e marks or inputs it
  does not read, such as `stdin` or `heap-free`. At the time of the scan,
  no accept fixture carried any.

**Read the rule from the report, not the wording** (MACH-9, §8 `unsafePerformIO`):
- `prelude.sh: escape_hatch` compiles its probe with `--report` and
  accepts when two things hold:
  - the verdict is `refused`;
  - every error is the `escape-hatch` or `world` rule at a line of the
    probe.

  A probe that misses keeps its report and output as evidence, and the
  "these not" line prints that evidence. The §8 measurement on today's
  build: the probe for `PrimIO.unsafePerformIO` is refused,
  `diagnostic: error world Main.idr:6`, with the message
  `unsupported (world): Main.main: uses PrimIO.unsafePerformIO`. So the
  compiler did not lose the rule. The old text match was wrong, because
  the message now starts with the definition's name.
  `programs/prelude/every-primio-export` should pass again with this change.
- `profile.sh: registry_shadowed` reads `--report`: the verdict must be
  `refused` and every error must be the `hook` rule. The message is still
  checked for the entry's name, because naming the entry and what it
  expects is the refusal's contract.

**One helper.** `harness.sh: package_options DIR` replaces the five copies
of the `packages` loop (e2e.sh, profile.sh, determinism.sh twice,
bench.sh) (MACH-7).

**Makefile.**
- `INTERACTIVE` is gone.
- The CPU budget is split: each test's compilations get
  `IDRIS_MLIR_NCPU = max(1, NCPU / threads)`, so runner threads × compile
  threads ≤ NCPU (MACH-17, §6 step 2).
- The header comment describes the new summary.

**Docs.**
- `tests/README.md`:
  - names `make test-unit`;
  - describes the summary and the diff report;
  - states lit's rules: stop at the first failure, failures must be named;
  - points at `Main.idr`'s `suites` instead of repeating the topic list;
  - replaces the accept-with-interactive step with "run, read `output`,
    copy to `expected`".
- `testutils.sh` and `mlir.sh` comments follow the deletions.

**Templates.** I ran all three by hand:
- `dialect` prints `RUN 1: ok`.
- `program` prints the standard six-line transcript.
- `reject` prints `reject does not start with pragma`, as intended until
  it is renamed.

None of them carries `expected`, which fits the new flow.

## Tests left failing, and why

Left failing by this lane's rules, which the owning lanes must fix:
- `idr/rc/counted-linalg` RUN 1 (idr-c lane): a bare
  `not idris-mlir-opt %s -o /dev/null` names no failure. It should name
  the verifier rule it expects, through `-verify-diagnostics` or its
  stderr checked by FileCheck.

Compiler bugs that the more truthful harness now shows directly. These
were seen in this lane's runs; the area lanes own the tests:
- `foldsBalanced` dereferences an unloaded dialect (SUMMARY §5.1 item 1).
  `idr/tail-calls/positions` RUN 1 and `idr/actions/returned-arguments`
  RUN 2 crash with exit 139 in `IdrDialect::foldLeakCount` from
  `ContractInstrumentation::runAfterPass`. The later lines now report
  "not run" instead of running against missing files.

Seen in this lane's sample. These are not harness failures; each is the
fixture's or the compiler's, for the owning lane to settle:
- `idr/narrow/descending` RUN 2:
  `expected word-loop: @parity computes on bigs in each of its loops`.
- `idr/actions/narrow` RUN 6: `%status 1 diff` finds the files identical,
  so the debug counters change nothing.
- `idr/defunc/tag-limit` RUN 2: idris-mlir-opt timed out after 60 s on
  65,536 functions.
- `idr/lower/layout`: its RUN line is malformed, which gives a shell
  syntax error.

## Runs on today's build (arm64 macOS, `NCPU=2 threads=2`)

- **`make check`: 29/32.**
  - `spec/file-size` and `spec/dialect-text` fail on code and fixtures
    owned by other lanes.
  - `spec/licenses` fails on `audits/machinery.md` and
    `bench/chameneos-redux/compare`, which have no licence header.
  - None of the three is the harness.
- **`make test-idr`: 280/342**, and 3 x86-64 tests named "not run on this
  host". The area lanes were editing during the run. Every failure was
  classified:
  - one fails by the new naming rule (`idr/rc/counted-linalg`);
  - the rest fail on the fixture or the compiler: the crashes and
    assertions of §5, stale syntax in verify/ and syntax/ fixtures, and
    properties that do not hold.
- **The pipe fix.** After the full run, `lit_stage` is inserted only at
  top-level pipes. Before, it was also inserted inside quoted `sh -c` and
  awk programs, where `lit_stage` is undefined. The 21 passing tests whose
  RUN lines use pipes were rerun after the fix: all 21 pass.
- **`idr/tail-calls/mutual` RUN 9** used to pass vacuously. Its inner
  command broke on the `lit_stage` that the old sed inserted into the
  quoted `$(tail | head)`. It now runs, and `constant-stack=@Prog.main`
  holds, so `%status 1` fails. The fixture's claim that the step's module
  fails constant-stack is stale. This is for the idr-c lane.
- **`idr/structure/columns` RUN 2** writes `signature=@pairs:(index)->(...)`
  without quotes, so it is a shell syntax error under this harness and the
  old one alike. It is a fixture bug, for the idr lanes.
- **`make test` sample of 9: 5 pass.**
  - Passing: `programs/basic/hello`, `programs/prelude/every-primio-export`
    (it passes again with the escape-hatch probe that reads the report),
    `registry/broken-entry` (with the report-read hook rule),
    `accept/indexed-tags` (heap-free), `accept/bounded-capped`.
  - Failing, on the compiler:
    - `programs/eval/memo-shared-stream`: `idris-rt: live cells 355`
      (§5 leaks);
    - `programs/stack/for-long-list`: `idris-mlir: stack exhausted`;
    - `programs/arrays/linarray-reserve`: refused as
      `unsupported (polymorphism)` on `Builtin.DPair.(#)` and
      `Linear.Notation.MkBang`;
    - `reject/cycle-ioref-knot`: reported at line 16 where the header
      says 18.
- **Runner paths, run by hand:**
  - `only=no-such-test-xyz` fails with "no test matches the selection";
  - `--interactive` is refused;
  - a test without `expected` prints its output.

## What a future harness must cover (not built here)

These need the machinery of SUMMARY §6 steps 2 and 3, or would rewrite
other lanes' transcripts. They are deliberately not done:
- **Outputs under `tests/build/results/`** (MACH-15). Not moved now. The
  area lanes read `<test>/output` beside their tests while they work, and
  moving it in the middle of the swarm would leave them reading stale
  files. Do it with the flattening and discovery rewrite.
- **A typed verdict** (`Check`, `Verdict`, `Outcome = Exited | Signalled |
  TimedOut`) and the `Fixture` record (MACH-1, MACH-11, MACH-14). With it,
  `fixture_files_known` becomes the parser's refusal of unknown files, and
  conflicting marks become unrepresentable. The live-cell count moves to a
  file named by `IDRIS_RT_LIVE`, which is a runtime change.
- **Acceptance as data** (MACH-2): `(test, host, expectation hash)`
  records, written by `make accept`, and an `Unaccepted host` verdict. A
  new expectation is written by hand meanwhile.
- **Dropping `Test.Golden` and contrib** (MACH-13), so the runner builds
  under idris-mlir. The runner still uses Golden's option parser and
  `filterTests`. `tests.ipkg` is unchanged.
- **Pools derived from the tree**, and `targets` parsed into a closed host
  type (MACH-12). The list of valid names belongs beside `tools/host.sh`'s
  `host_names`, which is outside this scope. A misspelt `targets` word
  still makes a test run nowhere, but the test is now named as
  "not run on this host".
- **`make test-unit` as a pool** of the one runner (REPO-14), and
  `bench/smoke@<name>` per benchmark (MACH-20). The bench lane is
  rebuilding `bench/` now.
- **One program runner**: merge `profile_accept`, `bench_smoke`,
  `fuzz_check` and `two_levels` into `e2e_io` (MACH-7). This changes the
  accept transcripts' line order, so it belongs to the accept lane or
  stage 3.
- **Contract lines instead of harness constants**: the `artifacts:` line,
  the prelude counts, and determinism's thread list (MACH-8). This
  rewrites about 300 transcripts, so do it with the stage-3 typed result.
- **A typed `%refuses <rule>` lit directive** read from `--report`
  (MACH-5, IDC-6), so a dialect test names the verifier rule and not only
  the failing command.
- **lit's own `%%` rule.** This needs the 8 awk-generating fixtures
  rewritten to `%%%%`.
- **Remark filter by role, not pass name** in `determinism_threads`
  (MACH-19). Today only `threads-linarray-lanes` asserts that remarks were
  seen.
- **Tests of the harness itself** (MACH-16):
  - every selected test gets exactly one verdict;
  - a `not` line whose input was never produced fails;
  - the host expectation is chosen.

## Left for others (outside this scope)

- `HANDOFF.md` and several `proposals/**` files still mention
  `tests/ACCEPTANCE.md` and NEEDS-ACCEPTANCE.
- `foreign/idr/unittests/Main.cpp:3` carries a NEEDS-ACCEPTANCE comment.
  It is compiler code, so this lane did not edit it.
- `spec/licenses` fails on `audits/machinery.md`, which has no SPDX header
  (this report has one), and on `bench/chameneos-redux/compare`.
