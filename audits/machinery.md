# Audit lane: machinery

**Scope.** The test machinery itself, not the tests it runs: `tests/Main.idr`,
`tests/Runner.idr`, `tests/runner/one.sh`, `tests/testutils.sh`, the 19
helpers in `tests/lib/*.sh`, `tests/templates/` (program, reject, dialect),
`tests/tests.ipkg`, `tests/ACCEPTANCE.md` and the NEEDS-ACCEPTANCE process,
the Makefile's test targets (`runner`, `check`, `test`, `test-idr`,
`test-unit`, `test-mlir-tools`, `typecheck`), and `tests/README.md`. I judged
it as a harness: how it represents a test and a result, what assertions it
lets an author state, which helpers are duplicated, which paths are legacy,
how it reports failures, and how acceptance works.

**What I read.** Both guidelines in full: `.claude/skills/testing-by-search/SKILL.md`
(TBS, cited by section) and `.claude/skills/representation-first/SKILL.md`
(RF: "How it binds", "Program with the types", SPOV 1-3). Every file in scope,
line by line. The parts of `third_party/Idris2/libs/test/Test/Golden.idr` the
runner calls (`runTest`, `findTests`, `testsInDir`, `normalize`). The
`expected` and `output` of every test directory, compared by script. The logs
`test.log` (make test, still being written at audit time), `test-idr.log`
(218/368) and `test-mlir-tools.log` (16/25), and the session's out-of-tree
`scratchpad/accept.sh`. I ran no build, no compiler and no runner.

**Counts.**
- Machinery files in scope: 3 Idris/sh entry points, 1 `testutils.sh`, 19
  `lib/*.sh` (2,291 lines of sh and awk), 3 templates, 1 ipkg, 1 ACCEPTANCE.md
  (608 lines), 7 Makefile targets, 1 README. **Verdict rows: 39** (one per
  component, plus the acceptance process, the interactive path and the stale
  `output` litter).
- Verdicts: **keep 19, rewrite 17, delete 3** (one rewrite merges
  `profile_accept` into `e2e_io`).
- Tree facts: 828 `expected` files; 511 equal their `output` right now. 376
  files carry `NEEDS-ACCEPTANCE` (314 `.mlir` comments, 60 `expected` first
  lines, 2 lib files). ACCEPTANCE.md lists **445**, so 69 entries are stale.
  **182** test-shaped directories hold only an untracked `output` left by
  deleted tests. 368 of the 371 dialect tests' `expected` files contain only
  `RUN n: ok` lines. 280 of the 303 e2e/accept transcripts take one of 5
  fixed forms.

---

## 2. Verdict table

Status: **works**, or **defect: cause** for a component that misbehaves on
the evidence. These are components, not tests, so pass/fail is replaced by
whether the component does what it claims.

| path | what it claims to check / do | verdict | reason | current status |
|---|---|---|---|---|
| `tests/Main.idr` | finds pools, filters by `targets`, dispatches suites and the helper sub-commands (`--sem-*`, `--fuzz-*`, `--two-levels-*`, `--lock`) | rewrite | the pool list repeats the tree layout by hand, a new topic is silently never run, an `Entry` is turned into a `dir@param` string and parsed again in sh (RF "Parse at the boundary, once", "One fact, one place"); runsHere/applicableTests use bare Bools (RF "Decide, don't test") | defect: unregistered topics and typo'd `targets` run nowhere, unnoticed |
| `tests/Runner.idr` | runs each test in its own process through xargs; summary `passed/(passed+failed)` | rewrite | the denominator is built from the verdict files, not from the selected tests, so a test that never reports drops out of the count; the xargs status is ignored; skipped tests are never counted (TBS 7 perception; AGENTS "do not report skipped tests as passed") | works on the happy path; can under-count |
| `tests/runner/one.sh` | runs `./run`, picks `expected.<host>` or `expected`, byte compare, prints Expected and Given | rewrite | the verdict is a text compare of whole transcripts with no diff; the run script's stderr leaves the report unattributed (seen in test.log line 15); there is no typed outcome (TBS 6.2, 7) | works; poor perception |
| `tests/testutils.sh` | the self re-exec under `timeout`, 256 KiB output cap, sourcing order, documents the marks | keep | bounding every test and cutting long output is right (AGENTS: "a hang is a failure"); `spec/timeouts` tests it. Move the mark list into data the runner checks (see MACH-14) | works |
| `tests/lib/harness.sh` | work dir, `bounded`, `say/show/empty`, `copy_fixture`, `repeated` | keep | small and correct, but `bounded`'s status needs to become a sum (MACH-11) | works |
| `tests/lib/timing.sh` | records each compile's wall time, gates nothing | keep | a measurement side channel, not an assertion (TBS 8 "these numbers measure the generator"); could move to tools/ | works |
| `tests/lib/rules.sh` | the rule phrases and categories from the generated `IdrRules.txt` | rewrite | reading the generated list is right (RF "One fact, one place"); `refusal_rule` is dead, defined and never called (RF "Delete what the representation makes dead") | works; dead code |
| `tests/lib/compile.sh` | `compile_program`, `link_program`, artifact kinds, `artifacts`, `no_artifacts` | rewrite | `say "artifacts:$artifacts_found"` prints the harness's own constant list (`core module objects executable`) into some 300 transcripts, so adding a kind changes every one (TBS 1.1: the assertion is stronger than the contract) | works; brittle line |
| `tests/lib/run.sh` | `run_program`, `run_ours` with the live-cell count on stderr | rewrite | the count comes back as the last line of the program's own stderr, and the code admits "exitWith ExitSuccess reads as a return whose count is missing" (RF SPOV 2: a state the channel cannot tell apart) | works; ambiguous channel |
| `tests/lib/heap.sh` | `object_imports` (allowed undefined symbols), `heap_free` mark | rewrite | `object_imports` is a good universal oracle (TBS 7) and stays. `heap_free` picks its module by the pass name `idr-lower`: if that is renamed, the loop runs past lowering and the property can hold vacuously (TBS 9.2 step 5 "check that the system entered the state") | works; would fail open on a rename |
| `tests/lib/mlir.sh` | `filecheck`, `step_dumps`, `step_of`, `mlir.check` input selection | rewrite | keep `step_dumps`/`step_module`. Delete the `mlir.check` path (FileCheck on compiled modules): only 2 fixtures use it, both pinning printed form or op order (TBS 1.1; README: "a property ... is stated in mlir.expect") | works; legacy path |
| `tests/lib/expect.sh` | `expect_holds`, `mlir.expect` per step | keep | the right vocabulary: named properties checked by idr-expect, not op text (TBS 1.1, 10) | works |
| `tests/lib/prelude.sh` | `covers MODULE`: every run-time export of a prelude module is used, found by scraping the stock REPL (`:browse`, `:doc`, `:di`, IDE `name-at`) and grepping Core text | rewrite | 497 lines of awk over printed REPL text and printed Core names (RF "Every string that names a thing is a missing type"); the transcript pins counts and name lists the contract leaves open (TBS 1.1); the escape-hatch probe throws its evidence away | defect: every-primio-export fails with no evidence shown |
| `tests/lib/e2e.sh` | `e2e_io` (compile, run, stdout/exit/crash/stderr, marks, universal, heap, module checks), `sem_case` | rewrite | the core is sound. It re-implements what `profile_accept`, `bench_smoke`, `fuzz_check` and `two_levels` each do in their own way; there should be one "run against its expected files" (RF "One fact, one place") | works |
| `tests/lib/properties.sh` | `universal`: objects, dumps verify, quantities kept, as one line | keep | the right shape: a check added to every compilation changes no transcript (TBS 1.1, 7 universal oracle) | works; reveals real bugs (section 4) |
| `tests/lib/profile.sh` | `profile_reject` (rule, line, message, no artifacts, read from `--report`), `profile_accept`, `registry_shadowed` | rewrite | keep `profile_reject`: it reads the typed report, not the text. Merge `profile_accept` into `e2e_io` (it runs without stdin, without the 1 MiB stack, without libm-lines or crash support, and prints the same lines in another order). `registry_shadowed` greps message text where the report has the rule (RF "Parse at the boundary") | works; duplicated |
| `tests/lib/determinism.sh` | artifacts and dumps byte-identical at 1/3/5/13 threads and in a second process; one module under one thread and the pool | keep | exact comparison is the contract here (TBS 1.3). `determinism_threads` filters remarks to `idr-narrow-lanes` by name, so a rename makes both sides empty and the check holds vacuously (TBS 9.2 step 5) | works |
| `tests/lib/lit.sh` | runs the dialect tests' RUN lines without lit, injecting `--verify-roundtrip --idr-contracts` | rewrite | it runs every RUN line after a failure, so failures cascade and a `not` line passes vacuously; the injected flags turn `not idris-mlir-opt` into "fails for any reason"; it is a private lit dialect (no `%%`, `%s` replaced inside quoted programs); the verdict is restated in an `expected` file the `.mlir` already determines (TBS 1.1, 7; RF "One fact, one place") | defect: vacuous `not` lines, cascades |
| `tests/lib/fuzz.sh` | fuzzer driver: compile, agree, folded, model, shrink | keep | a real oracle (second forms plus the integers' meaning) and a search with shrinking (TBS 1.2, 8). Its content is the fuzz lane's | unknown here (fuzz lane) |
| `tests/lib/two-levels.sh` | closed terms against recorded values | keep | a thin driver; whether the corpus is right is the two-levels lane's | unknown here |
| `tests/lib/idris-lex.sh` | lexes Idris to tell code from comments and strings, for spec rules | keep | good enough for the spec rules; it is a second lexer beside Idris's, and misses `"""` multi-line and `#"` raw strings (RF "One fact, one place", low) | works |
| `tests/lib/cpp-lex.sh` | the same for C/C++ | keep | the same remark; raw strings are handled | works |
| `tests/lib/bench.sh` | every benchmark builds and prints its recorded output on a small input | rewrite | one test covers every benchmark, so one failure hides the others (TBS 6.2: the feature is too coarse); make it a parameterized entry per benchmark, which the runner already supports | works |
| `tests/templates/program` | the minimal e2e test to copy | keep | right shape; it is never run, so it can rot (add it to `make check` once e2e runs there, or check it in spec) | unknown (never run) |
| `tests/templates/reject` | the minimal reject test | keep | as above; the directory name `reject` fails `profile_reject`'s prefix rule until renamed, which the README says to do | unknown (never run) |
| `tests/templates/dialect` | the minimal dialect test | keep | states a property with idr-expect, as it should (TBS 1.1); drop the `expected` it would need once lit's verdict is derived (MACH-6) | unknown (never run) |
| `tests/tests.ipkg` | the runner package: `depends = contrib, test` | rewrite | `Test.Golden` imports `System.Concurrency` (threads are outside the language) and `Lock.idr` imports contrib's `Language.JSON`, so the machinery cannot build under idris-mlir, which RF "The subset we compile" asks of it | works on Chez only |
| `tests/ACCEPTANCE.md` | the list of every file owing acceptance, "the tree's own list, `grep -rl NEEDS-ACCEPTANCE tests`" | delete | a hand-kept second copy of a grep, already wrong: it lists 445 files, the tree has 376 (RF "One fact, one place"); generate it or drop it | defect: 69 stale entries |
| NEEDS-ACCEPTANCE process (marks in `expected` line 1, in `.mlir` comments, in `lib/properties.sh` and `lib/lit.sh`) | a file's expectation is unconfirmed until a build shows it | rewrite | one state with three encodings that act differently: an `expected` mark fails the test by construction, a `.mlir` mark changes nothing, a lib mark belongs to no test; acceptance is by host but the mark is one line (RF SPOV 2, "A sum, never a flag") | defect: the state cannot be told from a regression |
| `make check` | the spec pool | keep | right split: no build needed | works (spec lane owns results) |
| `make test` | the program pools | keep | right; but it multiplies the CPU budget: `threads ?= $(NCPU)` and each compile `--num-threads=$ncpu`, so NCPU tests each run NCPU threads under a 60 s wall-clock step limit (TBS 11: load is a hidden input) | works; timeouts depend on load |
| `make test-idr` | the dialect pools | keep | as `make test` | works |
| `make test-mlir-tools` | the upstream reproducers | keep | right | works |
| `make test-unit` | the googletest boxes, a shell loop in the Makefile | rewrite | a second runner with its own report format, not in tests/README.md and not in AGENTS.md's "Checks" list; make it a pool of the one runner (RF "One fact, one place") | works |
| `make typecheck` | compiles what it can where stage 2 is not built | keep | a build gate, not a test; its summary names every part | works |
| `make runner` | builds the runner aside and installs it by rename | keep | correct under concurrent runs | works |
| `tests/README.md` | how a test is laid out and run | rewrite | repeats the topic list that Main.idr also holds; does not mention `make test-unit`; describes `INTERACTIVE=--interactive` as the way to accept, which is unsafe (MACH-4) | works as prose; drifts |
| `INTERACTIVE=--interactive` path (`Test.Golden.runnerWith` in Main.idr) | accept new output one test at a time | delete | it is the threaded runner Runner.idr's own header says can hang; it compares only `expected` and ignores `expected.<host>`, so on macOS it would offer to overwrite the Linux expectation of `toolchain/runtime-archive-check`; it cannot run parameterized tests (RF "One fact, one place": two runners) | defect: wrong file accepted on host-specific tests |
| 182 stale `output`-only directories (for example `registry/base-surface/`, `programs/semantics/prim-*`, `idr/actions/canonicalize/`) | none: litter from deleted tests | delete | `output` is written into the source tree beside the test; deleting a test leaves a directory that looks like one, with old-harness transcripts (`budget: kept`, `simplify: idempotent`) that mislead audits (TBS 12: a testing failure is information about the infrastructure) | defect: litter |

---

## 3. Findings

### MACH-1 · harness-representation · high
**A result is a transcript of prose lines compared byte for byte, and for
most tests that transcript is a copy of facts held elsewhere.**
Paths: `tests/runner/one.sh`, `tests/lib/e2e.sh`, `tests/lib/lit.sh`, every `expected`.
Evidence:
- 368 of 371 dialect `expected` files contain only `RUN n: ok`, which the number of `// RUN:` lines in the `.mlir` already decides. The 367 run scripts are one line, `lit ../X.mlir`.
- 280 of 303 e2e/accept transcripts take one of 5 forms, decided by which files the fixture has: 152 are exactly
  ```
  compile: exit 0
  artifacts: core module objects executable
  run: exit status as expected
  stdout: as expected
  stderr: empty
  universal: holds
  ```
  and the rest add `mlir.expect: holds` (44), `heap: nothing is allocated on the heap` (16), or swap in the crash lines (20), or print the same lines in another order (48, `profile_accept`).
- `one.sh`: `if [ -f "$expected" ] && cmp -s "$expected" "$output"; then ... success`.

Guideline: RF "One fact, one place" ("in a test and in the code under test"), RF Insight 6 (a validator that throws away what it learned), TBS 1.1 (a weak testing vocabulary).
Recommendation: make the verdict a typed value the harness computes, `data Check = Holds Name | Fails Name Evidence`, collected per test. A test passes when every check it ran holds. `expected` stays only where the contract fully decides a text (program stdout, refusal messages, printed syntax under `asm/`, `syntax/`, `verify/`). The set of checks a fixture runs comes from its files, so a missing `mlir.expect` cannot go unnoticed: the runner prints the checks that ran, and a spec test asserts that each mark file produced its check.

### MACH-2 · infrastructure-gap · high
**The NEEDS-ACCEPTANCE state has three encodings that act differently, and
a hand-kept page that is already wrong.**
Paths: `tests/ACCEPTANCE.md`, marks in 60 `expected`, 314 `.mlir`, `tests/lib/properties.sh:3`, `tests/lib/lit.sh:3`.
Evidence:
- ACCEPTANCE.md: "The files are the tree's own list, `grep -rl NEEDS-ACCEPTANCE tests` ... 445 files ... A change that adds or removes a mark lists it here again." The tree has 376 marked files. 69 listed files no longer carry a mark (for example `tests/accept/fib/expected`, `tests/accept/pair-maybe/expected`). Commits 6911742a ("16 tests accepted") and dcafd452 ("48 tests accepted") removed marks without updating the page.
- An `expected` mark is line 1, which no run prints, so the test fails by construction. The runner then counts it with the regressions: `193/542` does not say how many failures are owed acceptance and how many are real.
- A `.mlir` mark is a comment that changes no output, so 314 dialect tests pass or fail whatever their acceptance state.
- `lib/properties.sh:3` and `lib/lit.sh:3` carry marks that belong to no test.
- Acceptance is done by `scratchpad/accept.sh`, outside the repository: "Accept every test whose expected file starts with a NEEDS-ACCEPTANCE line and whose output ... is the rest of it exactly".
- Acceptance happens per host, but the mark is one line. Marks such as `runtime-doubles` ask "confirm ... its 13 properties hold on both targets". Commit 6911742a is titled "accepted on arm64 macOS" and removes such lines.

Guideline: RF SPOV 2 and "A sum, never a flag" (one state, three encodings), RF "One fact, one place", TBS 9.2 step 5 (otherwise the test can silently check nothing).
Recommendation: delete ACCEPTANCE.md and the marks. Record acceptance as data: a file `tests/accepted` (or a field per test) of `(test, host, commit of the expectation)`, written by a `make accept` target that keeps accept.sh's rule (output equals the proposed expectation exactly) and runs per host. The runner reports three typed outcomes, `Passed | Failed | Unaccepted host`, and prints the count of each. An expectation that changed after its acceptance record is `Unaccepted` again, which also covers `.mlir` fixtures.

### MACH-3 · perception · high
**The summary can under-count, never shows skips, and a failure report has
no diff.**
Paths: `tests/Runner.idr:49-63`, `tests/runner/one.sh:44-63`, `tests/Main.idr:102-112`.
Evidence:
- `putStrLn (show (length passed) ++ "/" ++ show (length passed + length failed) ...)`. The number of selected tests (`tests` in `runPool`) is known but not used. `ignore $ system $ "xargs -P ..."` drops xargs's status, so a `one.sh` that dies before `printf '%s\n' "$test" >> "$results/$list"` removes its test from both counts.
- `applicableTests` filters `targets` tests out before the pool exists, and nothing reports them. AGENTS.md: "do not report skipped tests as passed". Here they are not reported at all.
- On a failure, `one.sh` prints `Expected:` and `Given:` in full (`cat "$expected"`, `cat "$output"`). The reader must diff 6 to 40 lines by eye for each of hundreds of failures.
- A run script's stderr goes to the runner's terminal, unattributed. In test.log line 15, `diff: /var/folders/.../idris-mlir-test.fWhqf2/printed.mlir: No such file or directory` appears between pool banners with no test name.

Guideline: TBS 6.2 ("coverage is a choice of features"; what the harness lets you notice), TBS 7, TBS 12 ("a testing failure is information about the testing infrastructure").
Recommendation: count verdicts against the selected list (`selected = passed + failed + unreported`, and fail the run if unreported is nonzero); print `N skipped on this host` with their names; print a unified diff and the failing checks' evidence; capture each run script's stderr into its report.

### MACH-4 · code-bug-revealed (in the machinery) · high
**`--interactive` accepts through Test.Golden's runner, which ignores
`expected.<host>`, cannot run parameterized tests, and is the runner
Runner.idr says hangs.**
Paths: `tests/Main.idr:247-255`, `third_party/Idris2/libs/test/Test/Golden.idr:228-260`, `tests/toolchain/runtime-archive-check/{expected,expected.macos}`.
Evidence:
- Main.idr: `then case instanceIn (...) of Just name => die (... "--interactive cannot give" ...) Nothing => runnerWith opts (map golden pools)`.
- Golden.idr: `Right exp <- readFile $ testPath ++ "/expected"` and `when b $ do Right _ <- writeFile (testPath ++ "/expected") out`. It never reads `expected.<host>`.
- Runner.idr's header: "a thread that dies ... or misses a wakeup leaves the others waiting for ever, holding the tree's lock".
- So on macOS, `make test only=toolchain/runtime-archive-check INTERACTIVE=--interactive` compares against the Linux `expected` and offers to overwrite it with macOS output, while `one.sh` keeps reading `expected.macos`.

Guideline: RF "One fact, one place" (two runners, two rules for choosing the expectation), RF "Delete what the representation makes dead".
Recommendation: delete the interactive path and the dependency on `Test.Golden` (MACH-13). Acceptance goes through `make accept` (MACH-2), which reuses `one.sh`'s choice of expectation.

### MACH-5 · cannot-fail · medium
**lit.sh runs every RUN line after a failure and rewrites every
`idris-mlir-opt`, so `not` lines can pass for the wrong reason.**
Path: `tests/lib/lit.sh:76-104`, `:79`.
Evidence:
- `-e 's/idris-mlir-opt /idris-mlir-opt --verify-roundtrip --idr-contracts /g'` applies to `not idris-mlir-opt ...` too. `tests/idr/rc/counted-linalg.mlir`, whose whole check is `// RUN: not idris-mlir-opt %s -o /dev/null`, then passes if the module fails to round-trip or a contract check fails for any reason, not only when the verifier rule it names refuses the module.
- Lines run independently. In test-idr.log, `idr/actions/trmc`: RUN 1, 2 and 4 fail on a fixture parse error, RUN 3 fails with `diff: ... t.none.mlir: No such file or directory`, and RUN 5 `not diff %t.none.mlir %t.done.mlir` reports `RUN 5: ok`. It passes vacuously because both files are missing. Real lit stops at the first failing line.
- `%s` is replaced everywhere, `%%` is not unescaped, so RUN lines are written for this emulation, not for lit (for example `printf "...%%k..."` inside awk programs in `idr/` RUN lines).

Guideline: TBS 9.2 step 5 ("Check that the real system actually entered each state the model claimed ... Otherwise the test can silently check nothing"), TBS 1.1.
Recommendation: stop at the first failing RUN line, as lit does. Inject the round-trip and contract flags only on lines expected to succeed, or run them as a separate universal check of the input. Add a typed refusal directive (`%refuses <rule>`, read from the report, as `profile_reject` does) so a dialect test can say which rule refuses, instead of a bare `not`. Handle `%%`.

### MACH-6 · redundant · medium
**Every dialect test is three artifacts where one would do.**
Paths: `tests/idr/**/<name>.mlir`, `<name>/run`, `<name>/expected`; `tests/templates/dialect`.
Evidence: 367 run scripts are `. "$IDRIS_MLIR_ROOT/tests/testutils.sh"` then `lit ../X.mlir`. 368 `expected` files are `RUN 1: ok` ... `RUN k: ok`. Adding a RUN line therefore means editing a second file.
Guideline: RF "One fact, one place", RF Insight 14 (data plus an evaluator).
Recommendation: the runner discovers `*.mlir` directly, and the verdict is "every RUN line succeeded" (MACH-1). Keep a `run` directory only for the 3 dialect tests that are scripts (`idr/expect/coverage`, `idr/pipeline/timing`, `idr/stack/hot-loop`).

### MACH-7 · redundant · medium
**One procedure, "run a compiled program against its expected files", is
written five times with different subsets of the marks.**
Paths: `lib/e2e.sh:e2e_io`, `lib/profile.sh:profile_accept`, `lib/bench.sh:bench_smoke`, `lib/fuzz.sh:fuzz_check`, `lib/two-levels.sh`.
Evidence:
- `profile_accept`: `run_ours accept "$work/fixture/build/exec/Main" /dev/null`. No stdin, no `small` stack, no `libm-lines`, no `expected-crash`, no `live-cells`. Yet `e2e_io` runs every program "on a 1 MiB stack". So an accept fixture and a programs fixture with the same program run under different conditions.
- The `packages` → `-p` loop appears five times: `e2e.sh:49-51`, `profile.sh:33-36`, `determinism.sh:36-38` and `:123-125`, `bench.sh:21-23`.
- accept transcripts put `universal: holds` before the run lines, e2e transcripts after them (48 vs 152 transcripts).

Guideline: RF "One fact, one place", RF "A switch on a tag is a polymorphism not yet named".
Recommendation: one `program_case` record (source, packages, stdin, stack, expected stdout, expected outcome, marks), parsed once from the fixture directory, and one runner of it. `accept/` fixtures with `expected-stdout` become ordinary programs. Without one, the accept test is "compiles, universal holds".

### MACH-8 · brittle-overspecified · medium
**Transcript lines restate harness constants or pin facts the contract
leaves open.**
Paths: `lib/compile.sh:85-100`, `lib/prelude.sh:403-420`, `lib/determinism.sh:18-24`.
Evidence:
- `artifacts: core module objects executable` is the harness's own `artifact_kinds='core module objects executable'`, printed into some 300 transcripts. ACCEPTANCE.md's upstream entries even note "the artifacts line is the kinds lib/compile.sh names".
- `prelude PrimIO: 21 exports, each used (8 compile-time only: AnyPtr GCAnyPtr GCPtr IO IORes PrimIO Ptr ThreadID; 1 escape hatch, ...: unsafePerformIO)`. The contract is "every run-time export is used". The counts and the compile-time list change with the Idris pin.
- `core: identical at 1, 3, 5 and 13 threads and in a second process` prints `determinism_runs`, so changing the thread set rewrites five transcripts. This one is mild: the set is part of what the test claims.

Guideline: TBS 1.1 (a brittle test asserts more than the contract; Winters' `ElementsAre` vs `UnorderedElementsAre`).
Recommendation: one contract line per check (`artifacts: every kind written`, `prelude PrimIO: every run-time export used`), with lists and counts only in failure evidence.

### MACH-9 · perception · medium
**The escape-hatch and registry probes read refusal text and discard their
evidence. `profile_reject` reads the typed report.**
Paths: `lib/prelude.sh:232-248`, `lib/profile.sh:212-222`.
Evidence:
- `escape_hatch` compiles a probe into `$eh_dir/out` and matches `/unsupported \((escape hatch|world)\): /`, then `"the escape hatch " full || ... == bare || ... "uses " full`. On a miss, nothing from `$eh_dir/out` is shown.
- `tests/programs/prelude/every-primio-export/output` currently says `21 exports; 12 used, these not: unsafePerformIO`. The transcript cannot say whether the compiler stopped refusing `unsafePerformIO` or only reworded the refusal.
- `registry_shadowed` greps `"unsupported (hook): "` and `"expects .*, but found "`. Meanwhile `profile_reject` reads `diagnostic: error <rule> <file:line>` from `--report`, "the one record of every refusal".

Guideline: RF "Every string that names a thing is a missing type", RF Insight 6, TBS 7.
Recommendation: every refusal check reads `--report` (rule and location). Print the probe's report on a miss.

### MACH-10 · harness-representation · medium
**`covers` scrapes the stock REPL's printed output to learn what the
prelude exports, and greps Core text to learn what a program uses.**
Path: `lib/prelude.sh` (497 lines).
Evidence: `printf ':browse %s\n:q\n' "$1" | browsed` with `awk -v FS=' : '`; IDE-mode `name-at` parsed with `match(s, /\("([^"\\]|\\.)*" \(:filename .../)`; pairing names by sort order ("the copies of a name pair off with its definitions in that order"); `core_uses` builds regexes over printed names such as `Prelude.Num.fromInteger_Num_Int(`. Two names are hard-coded (`decided_exclusion`, `registry_value`) because "The registry's hooks are the compiler's Idris source, which this check cannot ask".
Guideline: RF "Every string that names a thing is a missing type", RF "Parse at the boundary, once", RF Insight 13 (Greenspun: a bad interpreter grown by accident).
Recommendation: the frontend already holds the checked context and the registry. Add a report section (`--report`) that lists, as typed records, each export of the requested module with its classification (`RunTime | CompileTime | EscapeHatch | Excluded | RegistryValue`) and whether the program's Core references it. The check then becomes one comparison, and the hard-coded names move into the registry, their one home.

### MACH-11 · harness-representation · medium
**A process outcome is an integer. Timeouts, signals and the program's own
exit codes collide.**
Paths: `lib/harness.sh:31-40`, `lib/run.sh:32-45`, `lib/e2e.sh:90-100`.
Evidence:
- `bounded`: `case $bounded_status in 124 | 137) printf ... "timed out" ...; return 124`. A program or compiler that exits 124, or is SIGKILLed (137, for example by memory pressure), is reported as a timeout.
- A crash shows only as a number: test.log `programs/io/directory-listing` prints `run: exit 138, expected 0`, and the signal (`Bus error: 10`) survives only as a shell job message inside the evidence.
- `run_ours` takes the live-cell count off "the last line of stderr", and its comment concedes "exitWith ExitSuccess reads as a return whose count is missing".

Guideline: RF "A sum, never a flag", RF SPOV 2, TBS 11 (hidden inputs).
Recommendation: `data Outcome = Exited Int | Signalled Signal | TimedOut`, decided once where the process ends (timeout's `--preserve-status` plus `kill -l`). The runtime writes the live-cell count to a file named by `IDRIS_RT_LIVE`, not to the program's own stderr, so a missing count is told apart from an exit.

### MACH-12 · perception · medium
**Pools and topics are listed by hand. A new directory, or a typo in
`targets`, runs nowhere and nothing says so.**
Paths: `tests/Main.idr:165-196`, `:102-106`; `tests/README.md` Layout.
Evidence:
- `pool "programs/arrays: ..." ["programs/arrays"]` is one line per topic, and README repeats the same list ("`semantics`, `basic`, `io`, ... `arrays`"). No spec test checks that every directory under `tests/` is in a pool. A `tests/programs/<new>/` would be found by nobody.
- `findTests` is one level deep, and a directory without `run` "is not a test", silently. Today 182 such directories exist (MACH-15).
- `runsHere` keeps a test if `any (\word => contains word names)`. A `targets` naming `x86_64` (the uname spelling) instead of `x86-64` never runs and is never reported.

Guideline: RF "One fact, one place", TBS 8 (the "absent, not rare" row: something the representation cannot express at all).
Recommendation: derive the pools from the tree, with one data table for the descriptions keyed by directory and a check that every directory has an entry. Parse `targets` into a closed `Host = X86_64 | AArch64 | Linux | MacOS` and refuse unknown names. Report every directory that looks like a test but is not one.

### MACH-13 · stale-legacy · medium
**The runner depends on `Test.Golden` (threads) and contrib (`Language.JSON`),
so the machinery cannot build under idris-mlir.**
Paths: `tests/tests.ipkg` (`depends = contrib, test`), `tests/Main.idr` (`import Test.Golden`), `tests/Runner.idr`, `tests/Lock.idr` (`import Language.JSON`).
Evidence: `Test/Golden.idr:89: import System.Concurrency`. Threads are a decided exclusion (`lib/prelude.sh: decided_exclusion`: `Prelude.IO.fork ...`; rules list `threads	outside the language`). AGENTS.md calls contrib and test "no commitment". The runner uses Golden only for `Options`, `filterTests`, `TestPool`, `usage` and the interactive runner, all of which Runner.idr already works around.
Guideline: RF "The subset we compile (two hosts)", which says "the test machinery build[s] under stock Idris and under idris-mlir itself". AGENTS.md accepts the runner on Chez, so the conflict is between the two guidelines; I side with RF because the fork lane's self-hosting needs it.
Recommendation: replace Golden with a small `Options` parser and the typed `Entry`/`Outcome` of MACH-1 and MACH-11, and drop the contrib JSON dependency (a small JSON reader in `libs/`, or a lock file format the runner already parses). Then the runner is one more program the compiler compiles: two-hosts coverage for free.

### MACH-14 · harness-representation · low
**Marks are files whose names and meanings are documented in a comment and
checked by scattered `[ -f ... ]` tests.**
Paths: `tests/testutils.sh` header; `e2e.sh:52-61, 82-88, 108, 170`; `heap.sh:111`.
Evidence: `default-stack` and `constant-stack` conflict, and the conflict is caught at run time (`marks: constant-stack runs on the 1 MiB stack, which default-stack refuses`). An unknown mark file (a misspelt `heap_free`) is copied into the build and ignored.
Guideline: RF "Make illegal states unrepresentable" (SPOV 2), "Parse at the boundary, once".
Recommendation: parse a fixture's marks once into a record (`stack : Stack = Small | Default Reason | Constant Nat Reason`, `heap : Maybe HeapFree`, `liveCells : Maybe (Nat, Reason)`, ...). Refuse unknown files, and make conflicting marks unrepresentable.

### MACH-15 · stale-legacy · medium
**182 directories of litter: `output` files of deleted tests.**
Evidence: `find tests -name output` whose directory has no `run`: 72 under `programs/semantics` (old `prim-*` layout, transcripts with `budget: kept`, `simplify: idempotent`), 13 in `idr/in-bounds`, 10 in `idr/specialize`, and others, including `registry/base-surface/`, `registry/string-iterator/` (deleted in the index), `toolchain/arena-page/`, `spec/cpp-starter/`. All are git-ignored (`/tests/**/output`), so they never show in review.
Guideline: TBS 12; RF "Delete what the representation makes dead in the same change".
Recommendation: write outputs under `tests/build/results/<test>` instead of beside the source, and delete the 182 directories now (`git clean -X` scoped to them).

### MACH-16 · infrastructure-gap · medium
**The machinery has almost no tests of its own.**
Evidence: `spec/timeouts` tests `bounded` and the script limit, and it is good. Nothing tests `one.sh`'s choice of expectation, the summary's count, lit's line semantics (MACH-5), the mark parser, `stdout_within_a_few_ulp`, `step_dumps` ordering, or `object_imports`. Every defect in this audit was found by reading.
Guideline: TBS 1.2 ("When a bug slips past the fuzzer, treat that as a bug in the fuzzer first"), TBS 7 ("Making a system testable is a design activity").
Recommendation: once the harness is typed Idris (MACH-1, MACH-13), test it with properties over generated fixture trees: every selected test gets exactly one verdict; a fixture whose files say check C produces C's line or C's failure; the chosen expectation is `expected.<h>` for the first host name `h` that has one. Keep one spec test per lit directive, including a `not` line whose command never ran.

### MACH-17 · distribution · low
**Wall-clock limits under a doubled CPU budget make timeouts depend on load.**
Paths: `Makefile:103-112` (`threads ?= $(NCPU)`), `tools/compile.sh:42` (`--num-threads="$ncpu"`), `lib/harness.sh` (`step_limit=60`).
Evidence: the comment says "make's own job count, the test runner's threads ... and each compilation's --num-threads all read this one number". With 12 CPUs that means 12 concurrent tests × 12 compile threads. test.log has `timed out after 60s: Main` for `accept/partial-stream` and `accept/runtime-lazy-value-growing-choice`. Whether those are hangs or slowness is not decidable from the record.
Guideline: TBS 11 (timing as a hidden input: "bind the other half").
Recommendation: split the budget (runner threads × per-compile threads ≤ NCPU), record each timed-out command's CPU time beside its wall time, and treat a timeout's verdict as `TimedOut` (MACH-11), not a failure of the property.

### MACH-18 · stale-legacy · low
**Dead and single-use legacy paths.**
Evidence:
- `lib/rules.sh:refusal_rule` has no caller (grep across `tests/`).
- `mlir.check` (FileCheck on compiled modules) has 2 fixtures: `programs/partial/lambda-terminates/mlir.check`, which pins `attributes {instance = #idr.instance<"Main.main", []>}`, and `programs/partial/partial-divergent-call/mlir.check`, which pins op order with `CHECK: call @Main.spin(` before `CHECK: call @Main.collatz(`. idr-expect has `total`, `calls` and `calls-closed`.
Guideline: TBS 1.1; RF "Delete what the representation makes dead".
Recommendation: rewrite both as `mlir.expect`, then delete `check_mlir`, `mlir_input` and `module_checks`'s mlir.check branch, and `refusal_rule`.

### MACH-19 · cannot-fail (latent) · low
**Checks that pick their module or remarks by a pass name hold vacuously
when that name changes.**
Paths: `lib/heap.sh:121-123` (`[ "$(step_of "$heap_dump")" = idr-lower ] && break`), `lib/properties.sh:53`, `lib/determinism.sh:139` (`--remarks-filter=idr-narrow-lanes`).
Evidence: if `idr-lower` were renamed, `heap_module` becomes the last dump (after lowering, no `idr` ops), where `no-heap-allocation` likely holds trivially. If `idr-narrow-lanes` were renamed, both remark files are empty and compare equal.
Guideline: TBS 9.2 step 5.
Recommendation: select by the program's stage (`idr.program ... stage(lowered)`, which idr-expect's `stage` property reads) or by the pass role in `Passes.td` (`IdrRoleLowering`), and fail when the selection is empty. Assert at least one remark was seen.

### MACH-20 · perception · low
**Coarse tests hide failures behind the first one.**
Paths: `lib/bench.sh`, `bench/smoke`.
Evidence: `tests/bench/smoke/output` shows `binary-trees: exit 0 | idris-rt: live cells 63`, `deriv: ... live cells 1750` and `fannkuch-linear: compile exit 3 ... unsupported (polymorphism)`: three independent failures under one verdict.
Guideline: TBS 6.2 (the feature granularity table: "too coarse").
Recommendation: one entry per benchmark through the existing `parameterized` mechanism (`entriesOf`), as `programs/semantics/prim@<name>` already does.

---

## 4. Code bugs the tests reveal

Only what the outputs show. These came through the machinery's universal
checks and the e2e driver. The lanes that own each test should confirm.

1. **Specialization loses a proved quantity.** `tests/programs/linear/leet-reverse-list/output`:
   `quantities: lost after 0_5_idr-optimize.mlir` / `Main.idr:13:1: error: expected quantities-kept: parameter 1 of @Main.rev.spec.56ff8c21ff170171 has quantity w, and Idris proved 1`, repeated for every parameter of three `rev.spec.*` clones. One more output shows the loss after `idr-defunctionalize`, `idr-knots`, `idr-effects`, `idr-contify` and `idr-optimize` (`grep -rh '^quantities: lost after'`). Reading: the clones the specializer makes rebuild parameter types without the `!idr.lin` wrapper. The uncommitted change to `foreign/idr/lib/Transforms/Specialize/Specialization.cpp` may be the fix in progress. This is the AGENTS.md rule "No pass may drop what Idris proved", caught by the universal oracle as designed.
2. **Crashes after main returns.** test.log `programs/io/directory-listing`: `run: exit 138, expected 0`, stderr `idris-rt: live cells 7` then `Bus error: 10`. `programs/stack/io-loop-through-helper`: `idris-rt: live cells 30017` then `Segmentation fault: 11`. The runtime printed the exit count, so the fault is at or after process teardown, with cells still live. Probably freeing or finalizing a cell reached at exit. That is a reading; the signal's site is not in the record.
3. **Leaks at exit.** 38 outputs show `stderr: not empty` with `idris-rt: live cells N` (N ≠ 0) after a normal exit, for example `bench/smoke`'s `binary-trees` (63) and `deriv` (1750). These are counting bugs, or stale budgets for the 3 fixtures that carry `live-cells`. Commits 3d279eb9 and 9696ecc5 suggest work on counting is ongoing.
4. **`unsafePerformIO` no longer refused as an escape hatch, or refused in other words.** `programs/prelude/every-primio-export/output`: `21 exports; 12 used, these not: unsafePerformIO`. The probe discards its evidence (MACH-9), so I cannot tell which.
5. **Uncertain: the dialect sample generator against the root rule.** `compiler/dialect-syntax` (test.log): `'idr.func' op is the root, so its type must be () -> i64, or ... (!idr.world) -> (...) ... not '(!idr.data<"T", ...>, i64, !idr.str, !idr.world) -> (i64, !idr.world)'`. Either SyntaxSamples writes a root with arguments (a stale generator, a test bug) or the verifier's root rule applies to a sample that is not meant as a program root. Not decidable from the output.

Failures that are **test bugs, not compiler bugs**: `idr/actions/trmc` (fixture does not parse: `use of value '%nil' expects different type than prior uses`, a pre-wave borrowed type), and `bench/smoke`'s `fannkuch-linear` (refused by `polymorphism`; whether that refusal is right is the bench lane's call).

---

## 5. What the rebuilt machinery should look like

**One typed core, a thin shell.** The runner becomes one Idris program
inside the subset idris-mlir compiles (no `Test.Golden`, no contrib), so it
builds on both hosts.
- `Fixture`: parsed once from a directory. Its kind (`Program`, `Reject`, `Dialect`, `Script`), its files and its marks as a record whose conflicting states cannot be built (MACH-14). Unknown files are refused.
- `Outcome = Exited Int | Signalled Signal | TimedOut`, decided where a process ends (MACH-11).
- `Check = Holds Name | Fails Name Evidence`, and `Verdict = Passed | Failed (List1 Check) | Unaccepted Host | Skipped Host` per test. The summary counts each against the selected list (MACH-3).
- Shell remains only to spawn the compiler, the program and the tools. Stdout, stderr, the live-cell count (from its own file) and `--report` come back as files the core parses.

**Expectations only where the contract decides the text.** Keep `expected-stdout`, `stdin`, `expected-exit`/`expected-crash`, the reject header (`-- expect: <rule>, line N`, `-- message:`), printed syntax under `asm/`, `syntax/`, `verify/`, and determinism's byte equality (TBS 1.3). Delete the per-test `expected` transcripts of e2e, accept and dialect tests (MACH-1, MACH-6). A fixture's checks are its files: the runner states which ran.

**Universal oracles, run on everything** (TBS 7), as `universal` already does: the verifier on every dump, quantities kept, allowed object imports, no live cells at a normal exit, round-trip and contracts on every dialect input that should verify. Add determinism as a sampled universal check rather than five fixtures: compile a random 1-in-k of the e2e fixtures at a random second thread count, with the seed printed, which is swarm testing over the existing corpus (TBS 5).

**Vocabulary instead of text** (TBS 1.1):
- refusals: `%refuses <rule> [at line]` for dialect tests, read from the report; the same reader for `profile_reject`, the escape-hatch probe and the registry probe (MACH-5, MACH-9);
- module selection by stage or pass role, never by pass name, failing when empty (MACH-19);
- prelude coverage as a report section the frontend writes from the checked context and the registry (MACH-10);
- `mlir.expect`/idr-expect for every property of a compiled module; no FileCheck on compiled modules (MACH-18).

**Acceptance as data** (MACH-2): `make accept HOST=...` writes `(test, host, expectation hash)` records after confirming that output equals the proposed expectation. The runner reports `Unaccepted` separately, per host. ACCEPTANCE.md and the marks are deleted; a list of what is owed is `runtests --unaccepted`, generated, never kept by hand.

**Granularity and layout.** One entry per benchmark, per fuzz seed and per
semantics primitive, through the existing parameter mechanism (MACH-20).
Pools derived from the tree with one description table and a check that every
directory belongs (MACH-12). Results under `tests/build/results`, never
beside sources (MACH-15). `test-unit`'s boxes as one more pool (verdict
table).

**Tests of the harness** (MACH-16): properties over generated fixture trees
(every selected test gets exactly one verdict; each mark produces its check;
the host-specific expectation is chosen), and one spec case per lit directive,
including a `not` line whose input was never produced, which must fail.
