<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane 19: tests-harness

Subsystem: `tests/`, `harness/`, `foreign/idr/lib/Transforms/Expect/` and
`Contracts/` with their headers, the Makefile's test targets,
`bench/README.md`. Read-only audit; no built compiler exists in this
checkout, so every measurement is a count over the source with its command.

Marks: *read* (path:line, commit, proposal section), *measured* (a count,
with its command), *recalled*, *conjecture*.

## 1. Reading notes

Notes taken while reading the skills, AGENTS.md and P0 top to bottom.
Each names what bears on the tests and the test machinery.

**Skills and AGENTS.md (read).**
- testing-by-search: the oracles this tree may use are ours only — a
  specification turned into a checker (`Sem.idr`, the runtime's documented
  semantics, `idr-expect`, `--idr-contracts`), a second implementation we
  own (`Fuzz.idr`'s two forms; clang's C in `bench/` for outputs), and
  universal oracles (the verifier after every pass, sanitizers,
  `universal: holds`). A golden transcript is right only where the
  contract fully determines it; SSA names, clone numbers, op order, a
  pass's incidental output are brittle. Brittleness is a missing test
  vocabulary (Winters). "Encode the invariants of the harness, not the
  expected behaviour of the system under test" (§4.3). Distribution is a
  value (`Weights`, swarm). Determinism of a solver across schedules is
  §11's "bind the hidden input".
- representation-first: every string that names a thing is a missing
  type (applies to expected files that spell op names); a fact held in a
  test and in the code under test is generated or deleted; delete in the
  same change the test that checked the impossible state.
- AGENTS.md: tests check behaviour (exit status, artifacts, the property a
  pass guarantees), never clone numbers, function order, SSA names; a
  brittle test means a missing test API; every command times out; no
  oracle (Chez, stock evaluator); the harness compiles under both hosts;
  `make check`, `make test`, `make test-idr`, `make test-unit`,
  `make test-mlir-tools`.

**P0 §0–§4 (read).**
- §2: the dialect surface P0 renames whole (§1 "redesign it whole, with
  every rename it needs"): every expected file that spells an `idr.` op
  mnemonic, a type syntax (`!idr.q<...>`, `!idr.lin`), an attribute
  (`#idr.types<...>`), a trait or a pass name breaks at the cutover.
  Pipeline §2 lists passes `idr-rc-cells`, `idr-rc-stack`,
  `idr-rc-grades`, `idr-rc-exclusive`, which tests name as flags.
- §3: the stage-1 module (71 MB, 70,000 functions) — the walls were all
  memory or time; no test today states a space guarantee (confirmed, §6
  rc-Q3).
- §4: "tests check behaviour" is part of AGENTS.md kept whole.

**§5.1 mlir-analysis (read).** U1 (state-storage patch) needs an
`upstream/<bug>` with a `tests/upstream-<bug>` check; Design 1 solves per
function in parallel, so results must not depend on the schedule (feeds
Q-llvm-6); D2's table: which upstream passes read effects — a test that
an effect declaration buys CSE/DCE is a property test (effects-as-data).
W1 asks for V, B, P, F on the stage-1 module at each solve: a measurement
API the harness lacks (no op/value counter per pass).

**§5.2 mlir-ods (read).** H1–H5: the verifier after every pass is the
universal oracle; H3 says a module pass re-verifies the whole module;
H4/W7: measure the pipeline with and without `--verify-each=0`. M9:
grades become type parameters checked once per unique type plus
`verifyTrait`/`verifyRegionTrait` for uses — the tests that today
exercise our hand verifier (`tests/verify-*`) are restated against the
traits' diagnostics or deleted. E2: greedy non-convergence must never
become a rejection (a property: no test may expect a refusal from a
budget). G2: `OpAsmOpInterface` result names make IR readable without
hand printers — fixtures written against hand printers break. M12/F2:
`idris-mlir-tblgen` on the wrappers changes what the Idris side's
generated mirror holds; the harness's `Prims.idr` reads no generated
module: it copies Idris's primitive list and the lowering's guards by
hand (§4 G6).

**§5.3 llvm (read).** S1 solver layer: whole-program solves run SCC
levels with `mlir::parallelForEach`; "a result independent of the
schedule (the least fixpoint of a monotone transfer is unique; an
analysis that widens must widen at points fixed by the graph)".
**Q-llvm-6**: should a solver test run each analysis with one thread and
with many and compare the frozen `Solution`s? M9: budgets never errors
(clang's `Expected` error rejected). I8: lists in C++ that mirror records
are generated — applies to the test passes' own lists (Expect's property
names, Contracts' pass list).

**§5.4 modular (read).** F4: Modular's best transform test states the
property it guarantees, "regardless of the parallel processing order,
every equivalence class collapses to its lexicographically smallest
symbol" (`eliminate-duplicated-functions-multilevel.mlir:1-12`): the
shape of a determinism-across-schedules test. F11/F15: caches "reset
between functions for determinism", interpreter results "asserted
deterministic across threads". F16: `kgen-verifier` at phase boundaries
in production, verification off after every pass (Q-M2). F18: a custom
tblgen backend whose validation errors are themselves tested. F25, item
13: Mojo's transform tests are FileCheck over op sequences, "weaker than
our testing rule; not a model".

**§5.5 cxx26 (read).** Library hardening (libc++ extensive mode) "in
debug and test builds" (D8, Q4): a universal oracle the C++ test
targets could gain. `static_assert` against generated tables (D4b) moves
list-completeness checks from tests into the compiler.

**§5.6 ecosystem (read).** E3: Flang's effect cache "exposes hit and
miss counters for tests" — statistics as a test API. C3/D2: IREE turns
a spent budget into a compile error ("failed to solve for usage
analysis"), the thing AGENTS.md forbids; a test that a spent budget
never refuses is the property (Q-E3). Item 6: solvers testable on
arrays, without MLIR (extract, solve, write back): a unit-test seam the
solver layer opens (`foreign/idr/unittests`). W-E5: every budget and
whether it becomes a failure.

**§5.7 library (read).** QL4: "Is byte-identical output for any thread
count a requirement? It fixes the threading rules (sorted hand-offs,
ids after the fixpoint, no thread-tagged ids in output: A2, G3)." F1
(LVars), F2 (deterministic reservations): determinism by construction;
G3: thread-tagged ids are schedule-dependent. M8: "Determinism follows
from monotone joins and sorted hand-offs".

**§5.8 dialect-design (read; the cutover's surface).** DS4's mapping
renames or merges most of §2's surface: `!idr.q` to `!idr.g<T, #grade>`
with the unrestricted grade normalized to `T` (DS1.1, T3); the world
type and `world.new` possibly deleted (DS2.1); `check.nonzero` and kin
to `arith.cmpi` + `idr.check %c, <reason>`; `check.crash`/`crash_str`
to one terminator; `divs`… to `arith.*`; `put_*` to `str.show_*` +
`io.write` (O5); six stat ops to one `io.file.stat`; eight clocks to
`io.clock <kind>`; `tabulate_io` into `tabulate`; `con/field/tag` to
`data.*`; `func/call/return` maybe `func.*`; `match_lit` to
`scf.index_switch`; `cell.new/stack` one class. N1: every op in one
family. S2/S3: generated aliases (`!List_Nat`), result names, fields
printed by name and stored by index. DD-Q8: "Is every name open,
including … the `idr` namespace itself?" B10: "verifiers are local;
whole-function invariants are passes"; EF3: "consumed exactly once on
every path" is a pass run after every pass by instrumentation. So:
every committed expected file that spells a mnemonic, a type, a trait,
a resource or a pass flag of today's dialect is written against a
surface P0 deletes.

**§5.9 mlton (read).** A3: MLton's driver can print, after every pass,
`PropertyList.stats`, `HashSet.stats` and the live heap — "the footprint
of the analysis state is a first-class, per-pass report"; Design 6
proposes the same as a Tracy plot per pass. A4: each pass states its
input precondition and output postcondition (contify's phases): the
shape of our `--idr-contracts`. G2.7/Design 3: every fact a later pass
reads is written into a type. Q-O5/Q-W7: grade verifier cost per pass,
measured.

**§5.10 rc (read).** A5: space characterized as a property — Perceus is
*garbage-free*, drop-guided reuse is *frame-limited*; ICFP 2022 proves
which placements hold which bound. **rc-Q3**: "Should compiled programs
carry one of these as a stated property, with a test, as the grades are
verified?" R1.4: `is_unique` folds on an exclusive type — a test that
"static exclusivity deletes the test" is a property of the lowered IR,
not an op count. M3: the grade verifier as OSSA's linear walk (W5). W1–W9
ask what the counting passes compute; tests that pin today's counting
(`tests/rc-*`) are written against the passes P0 replaces.

**§5.11 oom (read).** O3: "bounded memory is a G1 item measured by
`peak_memory` (0006 §1), whose test does not exist yet." C7: a budget in
program units keeps output identical across machines and thread counts,
which "the determinism tests (0006 G1)" rely on. A2: per-pass footprint
`PassInstrumentation`; oom W3: `peak_memory` (`tools/host.sh`) reads
`ru_maxrss`, which misses compressed pages. B1: one named `OutOfMemory`
crash with its own status; B2: stack probes (a frame past the guard is
silent corruption). **oom-6**: "one [exit status] for an out-of-memory
crash and one for a stack overflow, distinct from other crashes?"
`tests/foldlm-deep` is cited as the deep-recursion test.

**§6–§9 (read).** §8.6 verification (ods-Q6, Q-M2, Q-O5); §8.7
threading and determinism (QL4, Q-llvm-6, rc-Q4); §8.5 rc-Q3; §8.11
oom-6 (can wait). §9: D4, no code until the plan is approved; §7 not
written.

**What the reading adds up to, for this lane.** P0 (a) renames almost
every name an expected file spells (§5.8 DS4, DD-Q8); (b) moves
whole-program solves onto parallel schedules whose answer must not
depend on the schedule (§5.3 S1, §5.7 M8, QL4, Q-llvm-6); (c) moves
grade checks into types and traits and "consumed once" into a pass run
after every pass (§5.2 M9, §5.8 EF3, B10); (d) asks for space as a
stated property (rc-Q3, 0006 G1) and named OOM/stack-overflow crashes
(oom-6, B1, B2); (e) asks for per-pass footprint and verifier cost to be
measured (A2, W7, Q-W7). The test suite must survive (a) by stating
properties instead of spellings, and must gain APIs for (b), (d), (e).

**0003 facts-once (read), the harness's items.** Target lane: "The
ending lost: the harness infers return, exit and crash from the status
and stderr (`exitWith ExitSuccess` fails spuriously; three copies of the
protocol). One report channel from the runtime." "The upstream runner:
`rejection_skip` calls the deleted `refusal_rule` … `skip_reason` greps
identifiers … Classify by the report's rule category." "Held twice or
re-parsed: … `%differential` rebuilds the pipeline from text; the
handoff dialect list twice, already disagreeing on `scf`; … artifact
layout and the checked runtime's path spelled in the harness; the lock
and stamps parsed four or five ways; the test-unit box list from a glob;
… `page-size-mismatch` hand-spells flags `baseline-cpu-flags` holds; …
bench duplicates (`labels=`, CPU count, `bounded`, two timing parsers)."
Ownership lane: "`quantities-kept` identifies binders by location
(`Expect/Quantities.cpp`) and drops colliding keys silently". Wave
leftovers: "Resources read as effect bits by hand
(`Expect/Placement.cpp` `Order` …)"; "`Expect/CrashSites.cpp` counts
every `NoReturn` op, `idr.exit` among them, while `bodyEffect` counts
`MayCrash` … breaks `crash-sites-not-added`". The static-lifetime item's
acceptance names tests `nat-parity`, `escape-hatch-hole-at-runtime`,
`lower-static-thunk`, `lower-value-buffers`, `verify-sources`,
`effects-memo-state`. Each is checked in §3 and §4.

**0004 tests (read; the planned suite, nothing built, queued after
self-hosting).** §1 where the harness can lie: `%differential` common
mode (BEFORE compiled with the pass under test); stderr not compared;
`lit_lowered` reads the stage from the first matching line; `%s`/`%t`
substituted inside identifiers; `--check-prefixes=` plural unread;
`--mlir-print-ir-tree-dir` file names from symbols (NAME_MAX); one
verdict for `bench-smoke`, `semantics` named in `Main.idr`'s
`parameterized`. §2 a typed runner: `contrib`/`test` dependencies,
`system`, `Test.Golden`, `Language.JSON` block the second host; a
`Fixture` record parsed once and a typed `Verdict`; acceptance per host
as data; one program runner; `make test-unit` a pool. §3 vocabulary:
idr-expect rows missing (`boxed`, `merged=`, `copies`, `stack-bytes<=N`,
`crash-sites<=n`, `loops>=1`); Roots forms of `counts-nothing`,
`tests-nothing`, `reuses-in-place`; unreachable-function requests
refused; frontend lambdas named apart; a rule identity on every verifier
diagnostic and `%refuses <rule>`; "the pipeline as data"
(`--idr-pipeline=from:<stage>`/`to:<step>`, a generated (pass, role,
stage, action tags) table). §4 universal checks owed: Emit's quantities,
the lowered module's facts, byte round trip, no `idr.*` discardable
attribute, the checked runtime on every program, **sampled determinism
(one compilation in k redone at a drawn thread count)**. §5 relations:
the action census over every tag; fold against run generated from
`Sem`'s table; the guard family generated from `Idr_Guarded` records;
Sem both ways (literals and stdin); TwoLevels dissolved;
**`determinism@<program>`** deleting `determinism-rbtree`, `-shapes`,
`-threads-rbtree`, `-threads-linarray-lanes`, and `names@<seed>`
replacing `names-from-keys`, `determinism-name-stability`; refusal
relations; the effects model as observable-trace invariance under
canonicalize/cse/sink "in place of the per-op `effects-*` tables". §6
search: Fuzz widened; a corpus and `make fuzz` with a Good–Turing stop;
compile failures shrunk; the typed program generator G1–G13 with the
examples each deletes; prop.h; bench properties; `Labels.cpp`'s
example as `labels=`. §7 rules: `spec/target-confined`, module-graph
rules, static-linking planted witness, cpu-features per entry, fork
reproducers in `make test`, work counts not wall-clock ratios, a shared
test package (`readInt` copied into 51 tests), reject headers, stage 2 =
stage 3 as a test. §8: the stage chain unchecked; ~75 negative
idr-expect runs read stderr; generated output nobody compares
(`Fuzz.twoHosts`' sections, `TwoLevels.checkOf`/`verdict` dead,
`fuzz.sh` greps `[djrs]1`). This lane reconciles P0 against 0004 rather
than restating it: an item of 0004 that P0's cutover makes more urgent
is marked so in §5.

## 2. What the subsystem is

### 2.1 Files and sizes (*measured*)

`find harness -type f | xargs wc -l`; `wc -l foreign/idr/lib/Transforms/{Expect,Contracts}/*.cpp foreign/idr/include/idr/Transforms/{Expect,ExpectArguments,Contracts}.h`.

| part | files | lines | what it is |
| --- | ---: | ---: | --- |
| runner (Idris) | `Main.idr`, `Runner.idr`, `Lock.idr`, `harness.ipkg` | 341 + 92 + 98 + 18 | discovery, kinds, suites, pools; xargs of `one.sh`; the toolchain lock check |
| generators and oracles (Idris) | `Gen.idr`, `Prims.idr`, `Sem.idr`, `Fuzz.idr`, `Lazy.idr`, `TwoLevels.idr` | 627 + 728 + 161 + 902 + 331 + 429 | choice-stream generators, the primitive table and its meaning, the semantics tables, the four-way fuzzer, the lazy fuzzer, the two-level corpora |
| one run | `one.sh`, `kinds/*` (3 + 1 expected), `testutils.sh` | 85 + 26 + 94 | one test in a process; the kind scripts; limits and the library loader |
| shell library | `lib/*.sh` (21 files) | 2,868 | compile, run, dumps, idr-expect, e2e, differential, lit, profile (rejects), determinism, actions, fuzz, prelude coverage, planted witnesses, lexers, bench |
| runtime property kit | `prop/prop.h`, `bigmodel.h`, `utf8model.h`, `prop.sh` | 484 + 254 + 124 + 64 | header-only property runner with mutants; GMP and Unicode models |
| templates, README | `templates/*` (7), `README.md` | 51 + 143 | a test of each kind to copy; the vocabulary |
| idr-expect | 53 `.cpp` + `Expect.h` + `ExpectArguments.h` | 4,180 + 234 + 243 | 82 properties by name, typed argument shapes |
| contracts | `Contracts.cpp` + `Contracts.h` | 366 + 55 | pass instrumentation: five relations between the module before and after each module/program pass; a pass that breaks them on purpose |
| test targets | `Makefile:113-123, 271-318` | — | `check`, `test`, `test-idr`, `test-mlir-tools`, `test-unit`, `runner` |

The test tree (*measured*: a loop over `tests/*/` classifying by
`run`/`Main.idr` header/one `.mlir`, and reading `suite`; the command is
in §9):

| kind | count | suites |
| --- | ---: | --- |
| dialect fixtures (one `.mlir`) | 339 | test-idr |
| compiled programs (`Main.idr`) | 235 | 229 test, 6 test-mlir-tools |
| refused programs (`-- expect:` header) | 47 | test |
| scripts (`run`) | 126 | 61 test, 34 check, 28 test-mlir-tools, 3 test-idr |
| not a test | 2 | `tests/build`, `tests/spec` (ignored/untracked leftovers in this checkout, §8) |

Families by first word (*measured*, same loop, `awk` on the name):
expect 46 (45 fixtures), upstream 37 (29 scripts, 8 programs), lower 37,
canon 24, runtime 22 (15 scripts, 4 rejects, 3 programs), defunc 22,
verify 21, rc 20, fold 17, effects 16, every 14 (13 programs), bounded 13
(programs), linarray 12 (programs), pipeline 11, obs 11, guards 11 (6
fixtures, 5 programs), arrays 10, raise 9, actions 9, syntax 8,
specialize 8, polymorphism 8 (rejects), escape 8 (rejects), e2e 8,
bufferize 8, leet 7, func 7, and 70 smaller families.

### 2.2 What the subsystem holds and derives

- **A test is a directory; its kind is what it holds** (`Main.idr:110-159`,
  `kindOf`), and the kind picks a script (`one.sh:35-38`,
  `harness/kinds/<kind>`). A program test's record is spread over files:
  marks (`packages`, `heap-free`, `covers`, `mlir.expect`, the list at
  `e2e.sh:201-202`) and cases (`cases/<case>/{stdin, expected-stdout,
  expected-exit, expected-crash, libm-lines}`, the list at `e2e.sh:70`).
- **The verdict is a byte compare of a transcript** against `expected`
  (or `expected.<host>`, or the kind's `kinds/<kind>.expected`),
  `one.sh:52-62`. For programs the transcript is a handful of constant
  lines: 221 of 235 program `expected` files are one of three texts
  (*measured*: `md5 -q tests/*/expected` over program tests, `uniq -c`:
  161, 41 and 19).
- **The ending of a run** (return, exit, crash) is inferred from the
  status and stderr: `run.sh:26-39` (`IDRIS_RT_LIVE`, `idris-rt: live
  cells N`), `e2e.sh:153-187` (a crash is status 1 and stderr exactly
  `idris-mlir: <cause>`), and `differential.sh:142-172` again.
- **The oracles**: `%differential` (`differential.sh:127-174`: two modules,
  each lowered from its own stage, run on the empty input and every byte,
  same status and stdout, no cell live); `idr-expect` (82 named properties,
  `Lookup.cpp:19-251`); `--idr-contracts` (five relations at each
  module/program pass boundary, `Contracts.cpp:56-62`); `Sem.idr`'s tables
  (144 `semantics@` runs: 9 fixed types × 16 operations, read from
  `Sem.idr:87-101`); `Fuzz.idr`'s four renderings per case
  (`Fuzz.idr:25-36`) plus the integer model (`Fuzz.idr:459-515`);
  `Lazy.idr`'s model (`Lazy.idr:78-94`); `LabelsLeast.cpp`'s second
  derivation of the label solve; `prop.h`'s models (GMP, the Unicode
  standard) with planted mutants; bench outputs against clang's C
  (`bench/README.md:22-26`); the determinism comparisons
  (`determinism.sh:3-206`); upstream reproducers (`tests/upstream-*`).
- **What is derived again**: a step's module is found by parsing the IR
  tree printer's file names (`mlir.sh:73-116`, directories named after the
  op, `idr_program_*` at `:78`); the pipeline from a stage is rebuilt from
  `--dump-pass-pipeline` text and `IdrPassStages.txt`
  (`differential.sh:15-48`); a module's stage by a regex on its text
  (`differential.sh:58`); the reject header is parsed twice
  (`Main.idr:151-153`, `profile.sh:9-17`); the rules from `IdrRules.txt`
  text (`rules.sh:17-39`); prelude coverage from printed Core and REPL
  text (`prelude.sh:41-507`); idr-expect's property list from
  `Lookup.cpp`'s C++ source by `sed` (`tests/expect-coverage/run`).
- **Data structures (Idris)**: `Kind` (4 constructors), `Test` (`name`,
  `kind`, `suite : String`, `here : Bool`), `Pool` (`runs : List (String,
  String)`), Prims' `FixedTy`/`IntTy`/`Ty`/`Op`/`Family`/`Domain`/`Params`/
  `Expr` (well typed by construction), Gen's linear `Tape`/`Slots`,
  `Weights n` with a non-zero proof, `Subset`-typed shrink candidates with
  a `SizeAccessible` measure, Fuzz's `Case`/`Verdict`/`Scan`, Lazy's
  `Case`/`Step`.
- **Data structures (C++)**: `expect::Property {name, run}` table rows
  built by a template that ties a check to its argument shape
  (`Expect.h:83-100`); 17 argument shapes, each parsed once
  (`ExpectArguments.h:31-239`); `Snapshot {pass, before}` per op in a
  `DenseMap` under a `std::mutex` (`Contracts.h:30-47`).

### 2.3 Who reads its results; threading

- The runner (`Runner.idr:44-56`) runs `one.sh` with `xargs -P <threads>`,
  one process per test; verdicts are lines appended to
  `results/passed|failed` (`one.sh:85`), counted by `Runner.idr:71-92`.
- Every test compilation runs on one thread: `make` sets
  `IDRIS_MLIR_NCPU=1` (`Makefile:123`) and `tools/compile.sh:42` passes
  `--num-threads="$ncpu"`. Only the determinism helpers (`determinism.sh`,
  1/3/5/13/drawn) and the fuzzer (`Fuzz.idr:648-653`, one of 1/3/5/13 per
  seed) compile at other counts; `idris-mlir-opt` in fixtures runs with
  MLIR's default context threading (no thread count is compared there).
- The contracts run in the pass manager's instrumentation: a run is
  checked only on the module or the program (`Contracts.cpp:92`), so on
  the pass manager's own thread; the mutex (`Contracts.h:45`) guards a map
  no other thread reaches today (*conjecture*, from `:89-92` and `:296-307`:
  a nested run returns before locking).

## 3. Reconciliation with the proposal

### 3.1 Wave-1 findings and designs that touch the tests

| finding (P0) | verdict | evidence in our code |
| --- | --- | --- |
| §1/§5.8 DS4, DD-Q8: the dialect redesigned whole, every name open | **holds, and it is the suite's largest exposure** | Fixtures spell today's dialect: 26,025 `idr.` names in 339 fixtures (151 distinct), 322 name `#idr.types` and a `stage(...)`, 223 `!idr.world`, 68 a grade type; 1,024 lines of embedded reference IR (`// REF:`, `// REFERENCE:`); 644 RUN lines name 24 `--idr-*` passes, 86 spell a `--pass-pipeline` nest over `idr.program(...)`/`idr.func(...)` (*measured*, §9 commands). History: the data-table cutover b9d4d592, one representation change, touched 322 test directories (+1,794/−953 lines in `tests/`; `git show --shortstat b9d4d592 -- tests`). |
| §5.8 N1/S2/S3: readable names, generated aliases, fields printed by name | holds | `asm-aliases`, `asm-names`, `asm-prefix`, `syntax-*`, `verify-roundtrip` are FileCheck tests of today's printer (170 check lines naming idr ops in 21 fixtures, 86 in `verify-roundtrip` alone); their contract is the syntax, so exact comparison is right, and the cutover rewrites them. |
| §5.2 M9, M11, H1–H5: verification after every pass; grades in types, uses in traits | holds; the suite already enforces it | `tests/verifier-every-pass/run` refuses any `enableVerifier(false)`, `verify-each=0` or `disable-verifier` in the tree, RUN lines and patches included; `lit.sh:229` adds `--verify-roundtrip --idr-contracts` to every `idris-mlir-opt` that is to succeed. The contracts are a per-pass relation check between before and after (`Contracts.cpp:296-352`) that a verifier cannot be (it sees one module). |
| §5.2 H3: a module pass re-verifies the whole module | holds, and the contracts double it | `ContractInstrumentation::runBeforePass` clones the whole module before every module or program pass (`Contracts.cpp:306`) and walks it after (`:325-349`): at the stage-1 module's 71 MB this is a second copy per pass, in tests only (`--idr-contracts` is test-only, `Contracts.h:14-15`). |
| §5.2 E2, M6; §5.3 M9; §5.6 C3: a spent budget is never a rejection | holds; tests treat non-convergence as a test failure, not a refusal | 25 canon fixtures run `--canonicalize=... test-convergence=true` (`grep -l test-convergence tests/*/*.mlir`): convergence of our patterns on those inputs is the tested property; no test expects a program refused by a count. |
| §5.2 M4 / §2 "traits read once or never" | refuted in part for `BuildsValue`: its only readers are test properties | `Idr_BuildsValue` is read by `Expect/Does.cpp:34` and `Expect/Placement.cpp:117` and nothing else (`grep -rn BuildsValue foreign/idr/lib foreign/idr/include`); 7987388b added it "to replace two hand lists in idr-expect". Lane 02 (`audits/p0/02-ods-effects.md:468`) records the same. |
| §5.3 S1, §5.7 M8: whole-program solves run SCC levels in parallel; results independent of the schedule | the requirement is already tested, at the whole-compiler level only | `determinism.sh:3-144`: compilations at 1, 3, 5, 13, a drawn 2..31 and a second process, every artifact and every step's dump byte for byte, every executable on every input; `determinism.sh:146-206`: the pipeline under one thread and under the pool, module, statistics and remarks byte for byte. Users: `determinism-rbtree`, `determinism-shapes`, `determinism-threads-rbtree`, `determinism-threads-linarray-lanes`; fuzz seeds draw a count from {1, 3, 5, 13} (`Fuzz.idr:648-653`). No solver is compared with itself across thread counts (no unit test of a solve's frozen answer). |
| §5.4 F4: a transform test states the property it guarantees "regardless of the parallel processing order" | holds as a model | `names-from-keys`, `determinism-name-stability` state the dedup/naming property metamorphically (reorder, edit, swap) but through regexes over printed text (`tests/determinism-name-stability/run`, `symbols()`/`body()`/`span()`). |
| §5.4 F16, Q-M2: verification off in production, verifier passes at boundaries | conflicts with a check-suite rule | `tests/verifier-every-pass` forbids the flag in the tree; see §6 (Q-M2). |
| §5.6 item 6: "solvers testable on arrays, without MLIR" | holds in part | `foreign/idr/unittests` holds googletest boxes for Labels, Cycles, Flow, Identities, Constants, Ranges, Words, Hooks, Sources, Verify (1,862 lines, `wc -l foreign/idr/unittests/*.cpp`); `make test-unit` finds them by a glob (`Makefile:312`). |
| §5.9 A3, Design 6; §5.11 A2: a footprint record per pass | refuted: none exists | `harness/lib/timing.sh:32-63` records each compilation's wall time only; `peak_memory` (`tools/host.sh:121-150`, `ru_maxrss` through `wait4`) is used by `tools/self.sh:71-81` and `tools/bootstrap.sh:1245,1386`, by no test (`grep -rln peak_memory harness tests` is empty). |
| §5.9 A4: each pass states its pre- and postconditions | holds in part | `Passes.td`'s `requires`/`sets` stages are generated into `IdrPassStages.txt`; `%differential` reads it only to start a pipeline (`differential.sh:16-28`); `tests/pipeline-stages` checks four stages and four refusals by FileCheck of error text. 0004 §8's "stage chain, unchecked" holds. |
| §5.10 A5, rc-Q3: space as a stated property | refuted: no space bound is tested | §6 (rc-Q3). |
| §5.11 B1/B2, oom-6: a named OOM crash, a named stack overflow, statuses | holds in part | Both are named today and share the one crash status 1 (§6, oom-6); the 1 MiB guard's claim "a frame larger than this could step over them, and none is" (`runtime/Start/Runner.cpp:35-37`) is tested by nothing. |
| 0003 "the ending lost" | holds | three copies of the protocol: `run.sh:26-39`, `e2e.sh:153-187`, `differential.sh:142-172`; `exitWith ExitSuccess` reads as a return whose count is missing (`run.sh:23-25`). |
| 0003 "`%differential` rebuilds the pipeline from text" | holds | `differential.sh:15-48`. |
| 0003 "quantities-kept identifies binders by location" | holds | `Expect/Quantities.cpp:38-69, 105-121` (a colliding key is dropped, `:117-119`). |
| 0003 "Expect/Placement.cpp `Order` reads resources as effect bits" | holds | `Placement.cpp:78-93`. |
| 0003 "crash-sites counts every `NoReturn` op" | holds | `CrashSites.cpp:27-38`; `crash-sites-not-added` reads it (`Contracts.cpp:183-193`). |
| 0004 §1.6 dumps through `--mlir-print-ir-tree-dir` | holds, and P0 adds a rename exposure | `mlir.sh:63, 73-86`: the dump directories are named after the op (`idr_program_*`), so renaming `idr.program` silently changes where `step_dumps` looks; `step_module` then reports "no module dumped after" (`expect.sh:34-37`), which fails loudly. |
| 0004 §3.6 the pipeline as data | holds, and P0 makes it urgent | 41 `mlir.expect` files name steps by pass argument (20 `idr-rc-exclusive:`, 13 `idr-tail-calls:`, 7 `idr-optimize:`, 3 `idr-returned-arguments:`, 3 `idr-bufferize:`, 1 each `idr-rc-stack:`, `idr-narrow:`, `idr-contify:`, `emitted:`; *measured*), as do `heap.sh:119` (`idr-lower`), `fuzz.sh:86,101` (`idr-optimize`), `actions.sh:24-27` (action tags), `determinism.sh:174` (`idr-narrow-lanes`). 28274bd3 already met this: "fuzz-two-hosts' mlir.expect named the step idr-rc, which no pass is any more". |

### 3.2 Wave-2 questions answered

- **§5.1 W1** (V, B, P, F at each solve on the stage-1 module): no test
  or harness function counts them; the only per-pass record is wall time
  (`timing.sh:28-63`) and MLIR's statistics, which `determinism_threads`
  compares but never reads (`determinism.sh:173-199`). A measurement API
  is owed (§5, change C6).
- **§5.2 W7** (the verifier's cost, with and without `--verify-each=0`):
  the check suite forbids `verify-each=0` anywhere in the tree
  (`tests/verifier-every-pass/run`, `off_flag`). The verifier's time is
  already reported per pass by `--mlir-timing`: `tests/pipeline-timing/run`
  parses that report and sets aside rows matching `Verifier`
  (`timing_rows`, `timing.sh:70-84`), so W7 can be measured from the
  timing report without turning the verifier off (§6, new question T-Q5).
- **§5.2 W9** (passes that change nothing mark all analyses preserved):
  idr-expect does (`Expect.cpp:51`), and `test-idr-facts` does
  (`Facts.cpp:68`); the contract test pass changes the module by design.
- **§5.3 wave 2, the mutexes**: `Contracts.h:45`'s `std::mutex` guards
  `before`; the instrumentation is on MLIR's pass manager (not
  `llvm::parallelFor`); a checked run is only on the module or the program
  (`Contracts.cpp:92`), so no worker thread takes it today (*conjecture*;
  it becomes real if contracts are checked per function, §5 C7).
- **§5.4 wave 2, "whether release builds verify after every pass"**: the
  driver's checks are `PassChecks { Verifier, Contracts }`
  (`foreign/idr/lib/Driver/Options.cpp`, added in 28274bd3); the tests
  always give `--idr-contracts` (`e2e.sh:51`, `lit.sh:229`); the
  verifier is never off (`tests/verifier-every-pass`).
- **§5.4 wave 2, "every option that selects between two implementations"
  (F17)**: none in the harness; `--idr-contracts` adds checks and changes
  no output (`tests/no-behaviour-options/run` keeps it in its allowed
  list, line 4 of the `kept` string).
- **§5.6 W-E4** (facts in discardable attributes): `lowered` refuses a
  discardable attribute named for an `idr.func` fact after lowering
  (`Lowered.cpp:69-80`); 0004 §4.4's "no `idr.*` discardable attribute on
  any dump" is not built.
- **§5.6 W-E5** (budgets and whether they fail): in the harness, the
  test limits fail a test by design (`testutils.sh:60-88`: 60 s a step,
  300 s a test, 256 KiB of output); `Gen.exhaustive`'s `limit` makes a box
  "not whole", never a failure (`Gen.idr:326-335`); Fuzz's
  `caseCapacity` turns a short tape into an `overran` case that fails the
  check (`Fuzz.idr:381-392`, `fuzz.sh:80`); `prop.h`'s `classLimit` folds
  classes into `other`, `propertyLimit` aborts the program
  (`prop.h:37-39, 408-414`); `Sem.maxCases` is a self-check of a constant
  (`Sem.idr:40-43, 142-144`). None rejects a program; all are the
  harness's.
- **§5.9 Q-W7** (the grade verifier's cost per pass): no test measures it.
- **§5.11 wave 2 #3** (which measure `peak_memory` reads): `ru_maxrss` from
  `os.wait4` (`tools/host.sh:127-149`), resident size in KiB, which misses
  compressed pages on macOS; no test calls it.
- **§5.11 wave 2 #4** (whether an overflow is named today): yes, as
  `idris-mlir: stack exhausted` (`runtime/Start/Entry.cpp:77-80`) through
  the guard's fault handler (`runtime/Start/Runner.cpp:20-25`), status 1;
  no test reaches it (`grep -rh "" tests/*/cases/*/expected-crash` holds no
  "stack exhausted").

## 4. Issues

All *read* unless marked *measured* (commands in §9). "P0-brittle" in
*what* means the item names a thing P0 renames or deletes (§5.8 DS4,
DD-Q8), so it breaks at the cutover whatever else changes.

### 4.1 The runner (Idris)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| H1 | `harness/harness.ipkg:7`, `Main.idr:61`, `Runner.idr:17` | idris (two hosts) | the runner depends on `contrib` and `test` (`Test.Golden`), which idris-mlir does not ship: it builds under one host only (0004 §2.1) | own option parser and filter; the dependency goes |
| H2 | `Main.idr:112-119` | idris | `Kind`'s `Eq` written clause by clause, read once (`:224`) | an index (`Fin 4`) or `DecEq`; low |
| H3 | `Main.idr:122-138`, `one.sh:35-38` | ladder | three switches over `Kind` (`kindName`, `kindTitle`, `defaultSuite`) and a fourth over its name string in `one.sh` | one `facts : Kind -> KindFacts` record; `one.sh` given the script path, not a name to switch on |
| H4 | `Main.idr:163-188, 270` | idris | suites a `List (String, String)` looked up by string; `Test.suite : String` | `data Suite` parsed at the `suite` file once; its description a total function |
| H5 | `Main.idr:99-108, 163-168` | idris | `Test.here : Bool` from a `targets` word list | a `Placement` sum from a closed host type (0004 §2.3) |
| H6 | `Main.idr:144-153`; `profile.sh:9-17, 48-54` | rederivation | the reject header is recognized in Idris and parsed again by awk/sed | `Reject` carries rule, line and message, parsed once; `profile_reject` takes them |
| H7 | `Main.idr:202-213` | list | `parameterized` names `semantics` in the runner's source (0004 §1.7) | a test's parameters read from data the test holds |
| H8 | `Main.idr:228-232, 263-268` | idris | `--suite` peeled off before `Test.Golden`'s parser, whose four options this runner ignores and so refuses | own options record (with H1) |
| H9 | `Main.idr:234-248, 311-341` | idris | the commands (`--sem-program`, `--fuzz-check`, ...) matched as string lists, usage text three times | one `Command` sum parsed from argv; each module exports its request parser |
| H10 | `Runner.idr:24-27` | idris | `Pool.runs : List (String, String)`, a run and its kind's name | `List (Run, Kind)` |
| H11 | `Runner.idr:53, 69, 73` | idris (two hosts) | `system` for `xargs` and `rm` (0004 §2.1) | process creation in sh glue |
| H12 | `Runner.idr:71-92`; `one.sh:62-85` | state | verdicts are lines appended to two files and re-read; "no verdict" is selected minus reported | a typed `Verdict` per run (0004 §2.2), one line form |
| H13 | `Lock.idr:14` | idris (two hosts) | `Language.JSON` from contrib | a JSON reader in `libs/` or base |
| H14 | `harness/README.md:133-134` | dead (doc) | the module list omits `Lazy.idr` | the ipkg's module list is the one list |

### 4.2 The generators and oracles (Idris)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| G1 | `Prims.idr:330-473` | ladder | four full switches over `Op`'s 37 constructors (`opIndex`, `family`, `hostOf`, `spelling`); a new primitive is four new cases | one `facts : Op -> OpFacts` (family, host, spelling), `Eq`/`Ord` from one index |
| G2 | `Prims.idr:47-153` | ladder | five switches over `FixedTy`/`Ty` (`fixedName`, `fixedIndex`, `intIndex`, `tyIndex`, `width`) | one record per fixed type |
| G3 | `Prims.idr:94-129` | idris | `Eq` by index, then `sameTy : Maybe (a = b)` beside a coverage proof `sameIndex` | `DecEq` instances returning `Dec`; `sameTy` deleted |
| G4 | `Prims.idr:418-432, 689-708`; `TwoLevels.idr:48-53` | idris | host dependence as `Maybe String`, read by `isJust` (`onHost`) | `data Host = Exact \| Libm`; the sentence printed from it |
| G5 | `Prims.idr:138-153` | idris | `Width {bits, signed : Bool}`: signedness, which changes `wrap`, `quotient`, `remainder`, is a flag | `data Width = Signed Nat \| Unsigned Nat` (two cases the problem has) |
| G6 | `Prims.idr:3-10, 535-610` | list, rederivation | the primitive list is a hand copy of Idris's `Core.Primitives`, and the domains restate the lowering's guards ("idr-lower checks the divisor", `:535-536, 542-545, 550-553, 590-592`; P0-brittle names in comments) | the *meaning* stays here (the oracle); the *list* and *domains* from a generated module (the dialect's guard records, `idris-mlir-tblgen`), lane 14; the harness may not import the fork |
| G7 | `Prims.idr:239-251` | budget | `bitLength` recurses on a `fuel` bounded by the magnitude, the comment's argument | essential under the subset (Integer has no measure); keep |
| G8 | `Sem.idr:76-81` | idris | `Case = (String, FixedTy, Integer)`, the expression as text | a record over `Prims.Expr`, rendered once |
| G9 | `Sem.idr:40-43, 140-144` | dead | `maxCases` and `checks`: a check of the harness's own constant (0004 §5.4) | delete |
| G10 | `Sem.idr:136-161` | idris | `byName : SortedMap String`, `programOf : String -> Maybe String` | the parameter resolved at the boundary to the test's record |
| G11 | `Sem.idr:66-127` | coverage | every case on literals, so each program folds to a constant and codegen is never run (0004 §5.4) | each case also on stdin values |
| G12 | `Gen.idr:52-54, 259-265, 299-304` | idris | `overran : Bool` on the tape and the drawn value, `whole : Bool` on a box | sums: `Complete \| Overran`, `Whole \| Partial` |
| G13 | `Gen.idr:162-167` | idris | `weightsOf : Vect n Nat -> Maybe (Weights n)` | a `Dec` on the sum's positivity; low |
| G14 | `Gen.idr:299-347` | dead | `exhaustive`, `Box`, `advance`, `shortlex` have no consumer outside Gen's own checks (*measured*: `grep -lw exhaustive harness/*.idr`) | a consumer (small-scope exhaustion of a generator, testing-by-search §8) in the same change, or delete |
| G15 | `Gen.idr:587-627`; `Fuzz.idr:822-845`; `Lazy.idr:292-307`; `TwoLevels.idr:283-296, 418-429`; `Sem.idr:140-144` | idris | self-checks as `List (String, Bool)`: a failure carries no counterexample | `record Check {name; outcome}`, `Fails` carrying what was found; compile-time ones stay `Refl` (Gen has five) |
| G16 | `Fuzz.idr:851-853`; `Lazy.idr:318-319`; `tests/fuzz-two-hosts/Main.idr` (`line`) | list | three copies of the `<owner>: <name>: ok\|failed` line | one function |
| G17 | `Fuzz.idr:622-684` vs `Lazy.idr:230-290` | rederivation | `File`, `parseFile`, `parseSeed`, `parseCases`, `programText`'s shape copied | one request module both use |
| G18 | `Fuzz.idr:112-135` | list | `familyIndex : Family -> Fin 9` by hand; the count 9 written in `Fin 9`, `Weights 9`, `Vect 9` and a nine-element literal | the index and the weights from one table over `Family` |
| G19 | `Fuzz.idr:648-653`; `determinism.sh:19-25` | list | the thread counts {1, 3, 5, 13} held twice | one source |
| G20 | `Fuzz.idr:707-717, 753, 780-783`; `fuzz.sh:116, 172` | rederivation | `Verdict.first : Maybe String` printed as `"<n> agree"` and compared by the shell (`= "1 $3"`) | `data Failure = Disagrees \| MissesModel`, one printed form, the shrink decision in Idris |
| G21 | `Fuzz.idr:859-878`; `tests/fuzz-seeds/run:21` | dead | `twoHosts`' `== <request>` sections and its `gen:`/`sem:`/`two-levels:` lines on the stock host are read by no test; the stock host's results of those checks are never compared with idris-mlir's (0004 §8) | a two-hosts diff of both outputs, or delete what is unread |
| G22 | `Fuzz.idr:89-110` | idris | `writes`/`has` Boolean filters decide what a part may hold | an `Expr` indexed by part would carry it; low (the filter is the generator's own invariant) |
| G23 | `Fuzz.idr:361-392`; `Lazy.idr:134-136` | budget | `depthBound`, `caseCapacity`: a short tape is an `overran` case that fails | essential (the harness's search bound); keep |
| G24 | `Lazy.idr:50-72` | idris | `modulus` "at least 2" and `taken` "at least one" said in comments | `S (S k)` / `S k` or erased `LTE` proofs |
| G25 | `Lazy.idr:100-114`; `Fuzz.idr:112-122` | list | `Fin n -> constructor` maps by hand (`structureOf`, `genReader`) | `oneOf` over the constructors |
| G26 | `TwoLevels.idr:1-8, 362-429` | dead | "No test of tests/ runs a corpus today"; `checkOf` is called by nothing (*measured*: `grep -n "TwoLevels.checkOf" harness`), and `verdict`, `differences`, `printedValues`, `keyed` serve only it and its own checks | 0004 §5.5: the terms into Sem's tables, the module deleted |
| G27 | `TwoLevels.idr:277-281, 347-356` | idris | `corpusOf : String -> Maybe`, files named by string | goes with G26 |

### 4.3 The shell library and the run protocol

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| S1 | `testutils.sh:31-56, 90-91` | list | the lib files listed twice, in two orders | one list |
| S2 | `e2e.sh:70, 196-209`; `README.md:59-65`; `testutils.sh:17-26` | list | case fields and marks spelled in three places | the `Fixture` record (0004 §2.2), one source |
| S3 | `run.sh:13-39`; `e2e.sh:153-187`; `differential.sh:111-174` | rederivation | three copies of the ending protocol (the live-cells line, a crash as status 1 and `idris-mlir: <cause>`); `exitWith ExitSuccess` reads as a return with no count (`run.sh:23-25`) (0003) | one report channel from the runtime and one typed `Ending` (§5 C4), lane 18 |
| S4 | `e2e.sh:107-109, 159-167` | state | "expected-exit beside expected-crash" refused at run time; a crash's status written as the literal 1 | the `Ending` sum makes the pair unrepresentable; the status from `IDRIS_RT_CRASHED` (`runtime/idris_rt.h:297`) |
| S5 | `mlir.sh:20-34, 88-116`; `expect.sh:20-46`; `heap.sh:117-127`; `fuzz.sh:82-106` | rederivation, P0-brittle | steps named by pass argument (`after:idr-lower`, `idr-optimize`), found by parsing dump file names | steps by stage or role from the generated pass table; the compiler dumps a named stage (§5 C2) |
| S6 | `mlir.sh:5-17, 63, 73-86` | upstream, P0-brittle | the IR tree printer: file names from symbols (NAME_MAX, 0004 §1.6), directories from op names (`idr_program_*`, `:78`) | as S5 |
| S7 | `differential.sh:7-48` | rederivation | the pipeline from a stage rebuilt from `--dump-pass-pipeline` text and `IdrPassStages.txt`, nests re-parsed by awk (0003) | `--idr-pipeline=from:<stage>` in the compiler (0004 §3.6), lane 13 |
| S8 | `differential.sh:58` | rederivation, P0-brittle | a module's stage by a regex over its text, the first matching line (0004 §1.3) | the stage read from the op by the tool |
| S9 | `differential.sh:152-164` | coverage | status and stdout compared, stderr not: two crashes of different causes agree (0004 §1.2) | the ending compared whole (with S3) |
| S10 | `differential.sh:57-78` | coverage | BEFORE lowered through the pipeline that holds the pass under test: common mode (0004 §1.1) | the pass under test skipped by its action tags (needs the pass table) |
| S11 | `lit.sh:198-240` | rederivation | RUN lines rewritten by `sed`: `--verify-roundtrip --idr-contracts` inserted after the text `idris-mlir-opt ` and removed after `not`/`%status`; `%s`/`%t` substituted inside identifiers (0004 §1.4) | the tool's checks set by the harness's environment, not by text rewriting; word-bounded substitution |
| S12 | `lit.sh:32-46, 75-82` | rederivation | idr-expect property names re-read from RUN text by an awk regex | one failure line form idr-expect prints (`expected <property>:` already is) read directly |
| S13 | `lit.sh:100-101`; `profile.sh:37`; `harness-near/expected` | list | idris-mlir's statuses (1 internal, 2 usage, 3 refusal) spelled in the harness | read from the driver's one definition (lane 13) |
| S14 | `actions.sh:17-27`; `tests/actions-skip-programs/expected` | list, P0-brittle | action tags by hand (`idr-stack-cell`, `idr-reuse-site`, `idr-optimize-inline`) in the script and its transcript | tags from the generated pass table (0004 §3.6, §5.1) |
| S15 | `determinism.sh:146-206`; `tests/determinism-threads-linarray-lanes/run` | P0-brittle | `--remarks-filter=idr-narrow-lanes`, and a grep for the pass's name | by role (0004 §5.6) |
| S16 | `determinism.sh:1-144`; `Makefile:123` | coverage | determinism held on two programs and two pipelines; every other compilation on one thread | `determinism@<program>` and sampled determinism in `universal` (0004 §4.6, §5.6); per-solver checks (Q-llvm-6) |
| S17 | `profile.sh:63-67` | P0-brittle | a reject test's directory must start with its rule's phrase: a renamed rule renames directories | owner (DD-Q8): rules as a stable API, or the prefix rule goes |
| S18 | `profile.sh:69-104, 154-166` | rederivation | the report's text (`verdict:`, `diagnostic: <severity> <rule> <file:line>`, dashes for spaces) and the registry's wording (`:159-160`) grepped | a typed report record; the rule a key |
| S19 | `rules.sh:17-18` | rederivation | the rule list read from one of two build trees | lane 13 |
| S20 | `prelude.sh:253-300` | list | `decided_exclusion` and `registry_value`: registry facts held by hand | the report lists reached definitions and the registry's dispositions (0003) |
| S21 | `prelude.sh:41-251, 430-507` | rederivation | Core's print and the REPL's text parsed (`browsed`, `name-at`, `core_uses`) | as S20 |
| S22 | `tests/every-*-export/expected` (13 tests) | brittle | the line lists compile-time-only names and export counts of the pinned prelude, more than "every run-time export is used"; Idris tracks main, so a prelude change re-records 13 transcripts | fixed once in the shared helper (`covers_prelude`, `prelude.sh:408-427`): its line states the contract (each used, or the missing ones) |
| S23 | `timing.sh:28-63` | list | options that "change what is compiled" filtered by a hand list | record the source and module only; low |
| S24 | `compile.sh:50-67` | list | artifact kinds and their path patterns (0003) | the driver names its artifacts (lane 13) |
| S25 | `fuzz.sh:153-154` | brittle | the `[djrs]1` label grammar grepped (0004 §8) | the shrunk case printed by Fuzz.idr |
| S26 | `bench.sh:10-38` | coverage | one verdict for 30 benchmarks (0004 §1.7) | `bench-smoke@<name>` |
| S27 | `heap.sh:54-60` | list | libm's symbols by hand (0003) | lane 13/18 |
| S28 | `one.sh:44-59` | idris | the expectation chosen by host name order; no program test has an `expected.<host>` (*measured*) | 0004 §2.3; low |

### 4.4 idr-expect and the contracts (C++)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| E1 | `Expect.h:146-230`; `Lookup.cpp:19-251`; `tests/expect-coverage/run` | list | 82 checks declared by hand and listed again as table rows; the coverage test `sed`-parses the C++ table | one TableGen record per property generating declarations, table and a list the coverage test reads |
| E2 | `Arguments.cpp:127-372` | cpp | ten shape parsers repeat `headAndRest`, `Symbol::parse`, `resolve` | one composable template over shapes (`@f:` head, then the rest) |
| E3 | `ExpectArguments.h:107-114` | cpp | `Loops.count : std::optional<unsigned>` means "some" or "exactly n" | a two-alternative sum; low |
| E4 | `ExpectArguments.h:148-163`; `Values.cpp` | attribute, P0-brittle | expected values written as dialect attributes (`#idr.big<-4>`, `#idr.con<...>`) | keep the form (MLIR's), rewrite the uses with the dialect |
| E5 | `Allocation.cpp:21-44` | ods | `no-heap-allocation` special-cases `ClosureOp` and `SuspendOp` ("Pure as a value but built in a cell") and excepts `LinResource` and the frame's resource: allocation is not one declared fact | a heap `MemAlloc` declared on every allocating op (lane 02); the property reads that alone |
| E6 | `Closures.cpp:21-43` | ladder, P0-brittle | `no-closures` is a `ClosureOp`/`ApplyOp`/`ConstantOp`+`ClosureAttr` ladder | the higher stage's closure family as one interface or a `ConversionTarget` fact (DS4) |
| E7 | `CountsNothing.cpp:15-29` | ladder, P0-brittle | `isa<DupOp, DropOp>` with a static-data exception | "no effect on the count resource" (§5.10 R1.5), the exception decided by the type (0003's static lifetime), lane 08 |
| E8 | `Does.cpp:23-44, 91-120` | ladder | an `Action` table of function pointers over `isa<ForceOp>`, `isa<FieldOp>`, `isa<ApplyOp>`, `hasTrait<BuildsValue>` | each action a declared interface or effect; lane 02/03 |
| E9 | `Placement.cpp:28-46` | ladder, P0-brittle | `MatchLitOp`/`MatchOp` told apart by `dyn_cast`, cases a `std::variant<Attribute, Tag>` | `MatchOpInterface` answers its keys (`match_lit` may become `scf.index_switch`, DS4) |
| E10 | `Placement.cpp:74-93` | rederivation | `Order {bool io; bool crash}` from resources by hand (0003) | the one effect classifier (lane 02) |
| E11 | `Placement.cpp:117`; `Does.cpp:34` | ods | `Idr_BuildsValue`'s only readers (*measured*) | with E8: the property reads allocation; the trait goes (lane 02) |
| E12 | `TestsNothing.cpp:17-60`; `ResetsUnshared.cpp:17-62`; `ReusesInPlace.cpp:17-41`; `ReusesEveryCell.cpp:15-31` | ladder, P0-brittle | counting's properties name `TakeOp`, `CellRecycleOp`, `CellInitOp`, `DropOp`, `DupOp`, `BorrowOp`, and walk `sourceOf` by `std::get_if<Same>` (`ResetsUnshared.cpp:31-34`) | restated over P0's counting IR (§5.10 R1: `is_unique` folding on exclusivity, `cell.reuse`), lane 08; names kept |
| E13 | `Output.cpp:17-33` | P0-brittle | `output-fused` names `PutStrOp` | over the write family after DS4's O5 (`str.show_*` then `io.write`) |
| E14 | `CrashSites.cpp:22-46`; `Contracts.cpp:180-193` | rederivation | "may crash" counted from `NoReturn` ∪ `GuardOpInterface` ∪ LLVM `noreturn`, apart from `MayCrash` (0003; lane 02 F5) | one ODS fact both read |
| E15 | `SolvedEffects.cpp:15-38`; `Contracts.cpp:164-178` | P0-brittle | `effects` and `effects-not-widened` read `idr.func`'s `Effect` bit enum (io, crash, diverge), which DS2/T6 replace | over the function's effect summary where P0 puts it |
| E16 | `Proved.cpp:15-38`; `Sizes.cpp:15-34`; `Stage.cpp:15-28`; `Lowered.cpp:81-93`; `Continuations.cpp:28-46` | P0-brittle | properties read `FuncOp` facts (`getTotal`, `inlineSize`, `getAttributeNames`), `ProgramOp`, the `Stage` enum; P0 may take `func.func` (DD-Q7) | through `FunctionOpInterface` and the facts' new carriers |
| E17 | `Quantities.cpp:38-69, 105-121` | rederivation, state | binders known by location; a colliding key silently dropped (0003) | known by the binder; P0's grade types compared position by position where positions are stable |
| E18 | `Quantities.cpp:90-98` | cpp | `spelled(Quantity)` beside the generated `stringifyQuantity` (`Contracts.cpp:153`) | one spelling |
| E19 | `Facts.cpp:30-70` | rederivation | `test-idr-facts` answers through `onlyAllocates`/`performsIO` (two of §2's "does IO" forms) | delete with T5 |
| E20 | `Folds.cpp:15-30` | state | a fold-leak counter on the dialect, read only here (lane 04 C42) | lane 04 |
| E21 | `LabelsLeast.cpp:9-161` | keep | a second derivation of the label solve: an oracle | essential; restated over the solver layer's graph (lane 06) |
| E22 | `Named.cpp:47-80`; `Report.cpp` | keep | `@f` names every copy by its location: the vocabulary that survives specialization and renaming of symbols | essential |
| E23 | `Contracts.cpp:54-87` | cpp | `Relation` enum, its `nameOf` switch, `Breakable` mirroring values by `static_cast` | one table of (name, check, breaker); low |
| E24 | `Contracts.cpp:89-100` | ladder | `isa<ModuleOp, ProgramOp>` decides what is checked | the pipeline's anchor (P0 nesting); low |
| E25 | `Contracts.cpp:296-307` | budget (memory) | a whole-module clone before every module or program pass | per-function snapshots on the worker that runs each function (§5 C7) |
| E26 | `Contracts.h:42-47` | state | a mutex that guards nothing concurrent today (*conjecture*) | goes, or becomes real with E25 |
| E27 | `Contracts.cpp:137-162` | keep | `linear-kept` compares each kept function's parameter and result grades before and after a pass: a relation, which the after-every-pass verifier (one module) cannot state | essential; over P0's grade type |
| E28 | `Contracts.cpp:195-292` | keep | `test-idr-break-contract`: a planted mutant per relation | essential; restated with the relations |

### 4.5 The tests

| ID | where | category | what (*measured*) | disposition |
| --- | --- | --- | --- | --- |
| T1 | 339 fixtures | P0-brittle (input text) | 26,025 `idr.` names (151 distinct); 322 with `#idr.types` and `stage(...)`; 223 with `!idr.world`; 68 with a grade type; 1,024 lines of embedded reference IR | §5 C3 |
| T2 | 41 `mlir.expect` files | P0-brittle | steps by pass argument (20 `idr-rc-exclusive:`, 13 `idr-tail-calls:`, 7 `idr-optimize:`, ...) | §5 C2 |
| T3 | 644 RUN lines; 86 `--pass-pipeline` strings | P0-brittle | 24 distinct `--idr-*` passes named (515 `idr-expect`, 64 `idr-rc`, 55 `idr-lower`, 44 `idr-defunctionalize`, 16 `idr-effects`, ...); nests over `idr.program(...)`, `idr.func(...)` | rewritten with P0's names, or by stage through `--idr-pipeline=from:/to:` |
| T4 | 390 `expected-error` lines | brittle | 260 match our own diagnostics' prose (130 `verify-*`, 27 `func-*`, 27 `expect-*`, 14 `syntax-*`, 11 `optimize-*`, 10 `rc-*`, 10 `identity`, 6 `world-*`, 5 `lower-*`, 5 `contracts-*`, 4 `tie-*`, 4 `arrays-*`, 3 `raise-*`, 3 `canon-*`, 1 `defunc-*`); 130 are idr-expect's `expected <property>:` | the 260 deleted outright (the owner's rule: never restated); what they claimed is covered by shared infrastructure, verifier mutation operators over the corpus and a rule identity on every diagnostic (0004 §3.5, §6.4.10); idr-expect's own vocabulary stays |
| T5 | 8 fixtures (six `effects-*`, `expect-facts`, `func-call-effects`) | brittle | 84 `facts: [...]` remarks, a table per op | trace-invariance programs (0004 §5.8), then delete |
| T6 | 21 fixtures (`asm-*`, `syntax-*`, `verify-roundtrip`, ...) | P0-brittle (contract is the syntax) | 170 check lines naming idr ops (86 in `verify-roundtrip`) | rewritten for P0's assembly formats; their once/twice `diff` made universal in lit |
| T7 | 13 check lines | brittle | an op name inside a property failure (`expected in-place: memref.copy` ×6, `expected tests-nothing: idr.take` ×3, `expected no-heap-allocation: idr.con` ×2, ...) | delete the lines: `lit_fails` already requires a failing idr-expect run to fail by one of the properties it asks (`lit.sh:48-83`), which is the contract |
| T8 | 53 check lines | brittle (AGENTS.md) | name an SSA value | delete |
| T9 | `actions-*` (8 fixtures), `actions-skip-programs` | P0-brittle | action tags in RUN lines and transcripts | the census (0004 §5.1) deletes the 8 fixtures |
| T10 | `determinism-rbtree`, `-shapes`, `-threads-rbtree`, `-threads-linarray-lanes` | list | four copies of one property over hand-picked programs | `determinism@<program>` (0004 §5.6) |
| T11 | `names-from-keys`, `determinism-name-stability` | brittle | regexes over printed IR (`symbols`, `body` by `/func/`, `span` by `loc("Main.step"(...))`) | `names@<seed>` (0004 §5.6) |
| T12 | `every-*-export` (13) | brittle | S22 | S22 |
| T13 | `upstream-forward-dataflow-callee-lookup`, `upstream-bytecode-deferred-quadratic` (`now_ns`), `upstream-liveness-trivially-dead` (`/usr/bin/time` CPU) | budget | ratios of time | work counts (0004 §7.5); `upstream-greedy-multi-region-ancestors` already counts visits through `-debug-only`, the model |
| T14 | 25 canon fixtures | keep | `test-convergence=true`: the pattern set converges on these inputs | keep; its meaning changes if one-shot rewrites move to the walk driver (§5.2 M6) |
| T15 | `pipeline-stages` | brittle | stage names and refusal wording by FileCheck | the stage chain from the table (0004 §8) |
| T16 | 235 program `expected` files | ceremony | 221 are one of three constant texts | typed verdict; no `expected` for programs (0004 §2.2) |
| T17 | `fuzz-two-hosts` | coverage | the only place harness Idris runs under idris-mlir; the runner never does (H1) | 0004 §2.1 |
| T18 | `crash-integer-shift-huge` | coverage | the one test of `out of memory`; none of `stack exhausted` | oom-6, B2 (§6) |
| T19 | — | coverage | no test of a space bound, a peak, or a footprint | rc-Q3, oom-3 (§6) |
| T20 | `tests/build`, `tests/spec` | — | not tests: an ignored old runner build and 36 untracked `output` files; `discover` refuses them (`Main.idr:192-200, 274-275`) | removed from the checkout (§8) |
| M1 | `Makefile:306-318` | list | `make test-unit`'s boxes found by a glob (0003; 0004 §2.5) | the build's list |
| M2 | `Makefile:116-123` | coverage | every test compilation on one thread | S16 |
| M3 | `Makefile:271-287` | idris (two hosts) | the runner built only by the stock Idris on its own prefix | H1 |
| P1 | `prop/prop.h:41-57`; `Gen.idr:79-99` | keep | splitmix's case seed defined in C++ and in Idris, both checked against the published vectors (`prop.h:194-199`, `Gen.idr:593-595`) | essential (two languages), cross-checked |
| P2 | `prop/prop.h:259-279` | idris | a failing case shrinks by halving its bytes only (0004 §6.5) | low |

## 5. Target design

The lens: P0 changes the system under test whole, so the suite must be
split by what P0 touches. Its **checks** are already mostly stated in a
vocabulary that need not change (idr-expect's property names, `@f` by
location, `%differential`, cases, contracts); its **inputs and step
names** are written in today's dialect and pipeline. The changes below
make the checks the fixed API and move every name P0 changes out of the
tests and into one generated table. Each change ends with the one line
the skill asks for.

**C1. idr-expect's vocabulary as the fixed test API, generated from one
record and read over declared facts.**
- *Representation.* One TableGen record per property (name, argument
  shape, the sentence the table's comment holds today), from which
  `idris-mlir-tblgen` (or an `MlirTblgenMain` backend, §5.3 Q-llvm-5)
  writes the declarations, the table and a list the coverage test reads.
  Every check reads an interface, a trait or an effect the dialect
  declares: `no-heap-allocation` the heap `MemAlloc` alone (E5), `builds*`
  the allocation of a result (E8, E11), `counts-nothing` an effect on the
  count resource (E7; §5.10 R1.5), `crash-sites` the one "may crash" fact
  (E14), `effects` the function's effect summary wherever P0 puts it
  (E15), `no-closures` the higher stage's closure family (E6). No file of
  `Expect/` names an idr op class; 14 of 53 do today (*measured*, §9).
- *Deletes.* `Expect.h:146-230`'s hand declarations, `Lookup.cpp`'s hand
  table, `tests/expect-coverage/run`'s `sed` over C++, `Allocation.cpp`'s
  closure, suspension and `LinResource` cases, the `isa` ladders of E6–E13,
  `Idr_BuildsValue` (lane 02), `Placement.cpp`'s `Order` (E10).
- *One line.* The property list held twice in C++ and a third time in a
  test's `sed` becomes one record; a property that names no op cannot be
  broken by an op's rename, so P0's renames reach the tests only through
  their input text.
- *Order and dependencies.* Each property is re-implemented in the change
  that redeclares the fact it reads (lanes 02, 03, 06, 08, 12); the names
  and argument shapes stay (owner, T-Q3).

**C2. Steps named by stage and role: the pipeline as data.**
- *Representation.* The generated pass table (pass, role, `requires`,
  `sets`, action tags; 0004 §3.6), which `Passes.td` already half holds
  (`IdrPassStages.txt`). The compiler dumps the module at a named stage
  itself (a `PassInstrumentation` after the pass that sets it, the file
  named by the stage), and `idris-mlir-opt --idr-pipeline=from:<stage>`
  and `to:<stage>` run the registered pipeline's slice. `mlir.expect`
  lines name stages (or roles), never passes; `heap-free`, the fuzzer's
  folded check, the action census and the remarks filter read the table.
- *Deletes.* `mlir.sh`'s IR-tree-printer discovery (`:5-116`: file names
  from symbols, directories from op names), `differential.sh`'s pipeline
  reconstruction and stage regex (`:7-58`), the action tags of
  `actions.sh:17-27` and `actions-skip-programs/expected`, the remarks
  filter of `determinism.sh:174`, and the 41 `mlir.expect` files' pass
  names (S5–S8, S14, S15, T2).
- *One line.* A step is a stage the pass table defines, so a pass P0
  renames, merges or splits changes the table, not the tests, and no dump
  is named by a symbol (NAME_MAX) or an op (`idr_program_*`); the case
  28274bd3 met ("named the step idr-rc, which no pass is any more") cannot
  recur.
- *Order.* First: it lands before the dialect cutover, so every later step
  of P0 is checked by mlir.expect files that need no edit. Lane 13 owns the
  table and the flags.

**C3. The cutover's oracle is the tests whose inputs P0 does not touch;
fixtures are rewritten once, with checks that survive.**
- *The invariant set.* The 234 program tests with cases (907 cases), the
  47 rejects and their `near/` neighbours, the 144 `semantics@` runs, the
  30 benchmarks' outputs against clang's, the fuzz and lazy-fuzz seeds:
  their inputs are Idris sources and bytes, and their checks are behaviour
  (*measured*: §2.1, `ls tests/*/cases | wc -l`). Each step of P0 must
  leave every one of them passing, unchanged, with C2's stage names.
- *The fixtures.* 339 fixtures hold 26,025 idr names in their input text
  and 1,024 lines of reference IR (T1). Their checks are mostly already of
  the surviving kind (235 run idr-expect, 186 `%differential`); what is
  not is deleted outright in the same change, never restated (the owner's
  rule), with shared infrastructure covering what it claimed: the 260
  prose-matching `expected-error`s go, verifier mutation operators and a
  rule identity on every diagnostic cover them (T4; 0004 §3.5, §6.4.10);
  the 84 `facts:` remarks go, trace-invariance programs cover them (T5;
  0004 §5.8); the 13 op names inside property failures and the 53 SSA
  names go (T7, T8; `lit_fails` already checks the failing property); the
  syntax tests are
  rewritten for P0's assembly formats with their once/twice `diff` made a
  check of every lit run (T6). A fixture whose subject is a program's
  behaviour through a pass becomes a program test where it can, so the
  next dialect change does not touch it.
- *One line.* What a test checks no longer moves with the dialect, so
  the cutover's rewrite of a fixture is its input alone, and the program
  tests stay an oracle the cutover cannot rewrite to agree with itself.
- *Owner.* How the fixtures are rewritten (T-Q2).

**C4. The ending of a run is one record the runtime states once.**
- *Representation.* The runtime writes one ending (lane 18; 0003's "one
  report channel"), which the harness reads into `data Ending = Returned
  Live | Exited Status | Crashed Cause`, the cause's category the
  runtime's own enum (a guard's, out of memory, stack exhausted, ...). A
  case is `record Case {stdin, stdout, ending, libmLines}` parsed from its
  directory once.
- *Deletes.* The three copies of the protocol (`run.sh:13-39`,
  `e2e.sh:153-187`, `differential.sh:111-174`), the run-time refusal of an
  exit beside a crash (`e2e.sh:107-109`), the status literal 1
  (`e2e.sh:161`), `exitWith ExitSuccess` read as a return (`run.sh:23-25`),
  and `%differential`'s blindness to the crash's cause (S9).
- *One line.* An ending inferred from a status and a stderr becomes a
  value: a case with both an exit and a crash is unrepresentable, and a
  distinct status for out of memory or a stack overflow (oom-6) is one
  constructor, not a branch in three scripts.
- *Order.* With C2, before the cutover; lane 18 owns the runtime side.

**C5. Determinism tested at the compiler, the solver and the action
levels.**
- *Representation.* (i) `determinism@<program>` over the bench list and
  fuzz seeds, and a sampled redo at a drawn thread count in `universal`
  (0004 §4.6, §5.6), the thread counts one constant (G19). (ii) For each
  solver of P0's solver layer (§5.3 S1, §5.6 Design 1), a googletest box
  that builds its graph from generated arrays, with no MLIR (§5.6 item 6),
  and compares the frozen `Solution`s at one thread and at many, and under
  a permutation of the node numbering, mapped back (S1's "a result
  independent of the schedule"). (iii) The action census (0004 §5.1).
- *Deletes.* The four `determinism-*` copies (T10), `names-from-keys`'s and
  `determinism-name-stability`'s text regexes once `names@<seed>` lands
  (T11), the duplicated thread counts (G19).
- *One line.* A schedule-dependent answer becomes a failing box that
  replays from its seed, where today it shows only if it happens to reach
  the bytes of one of two programs.
- *Owner.* QL4 and Q-llvm-6 decide whether (ii) is a rule (§6).

**C6. Space and footprint as test APIs, if the owner asks for them.**
- *Representation.* (a) The runtime's live-cell count is exact and
  deterministic (`runtime/Alloc/Cells.cpp:151-223`); a high-water mark of
  it (none exists: `grep -rn peak runtime`) would let a case state
  `peak-cells` as a bound, or relate two compilations of one program (with
  reuse and borrowing skipped by their action tags, and without), which is
  the testable form of "frame-limited" (§5.10 A5). (b) The compiler's
  footprint per pass as a record (oom-3, §5.11 A2), never a gate (0001 D4).
- *One line.* A space property becomes a number the runtime counts in
  cells, which a case can bound byte-for-byte across machines, where RSS
  (`tools/host.sh:121-150`) differs by allocator and host.
- *Owner.* rc-Q3, oom-3 (§6).

**C7. The contracts per function, over what the relations read.**
- *Representation.* When P0 nests passes on functions (ods-Q6), the
  instrumentation keeps, per function and on the worker that runs it, the
  facts the relations read (parameter and result grades, binder
  quantities keyed by binder, the effect summary, the crash-site count),
  not a clone of the module; a program-level pass keeps those records for
  every function. The relations are restated over P0's facts (E14, E15,
  E17) and keep their planted breakers (E28).
- *Deletes.* The whole-module clone per pass (`Contracts.cpp:306`), the
  mutex that guards nothing today, or makes it guard something (E25, E26).
- *One line.* The state before a pass is what the contracts compare,
  sized by binders and functions, so `--idr-contracts` on the stage-1
  module costs a record per function, not a second 71 MB module per pass.
- *Order.* With lane 13's nesting.

**C8. The runner on both hosts, type-driven.**
- *Representation.* 0004 §2.1's split (process creation in sh glue, no
  `Test.Golden`, no contrib); `Kind` carries its parsed header (H6),
  `Suite` and `Placement` are types parsed once (H4, H5), `Verdict` is a
  value (H12); Prims' facts one record per `Op` and per fixed type, `Dec`
  equality, `Host` and `Width` as sums (G1–G5); Gen's `Complete | Overran`
  (G12); `Check` with a counterexample (G15); one request module for Fuzz
  and Lazy (G16, G17); TwoLevels dissolved (G26). All of it is plain data,
  records, `Fin` and `Dec`: inside the subset both hosts compile.
- *One line.* The strings that name kinds, suites, verdicts and outcomes
  across the runner and `one.sh` become types parsed once, so a misspelt
  suite or an unread verdict is a parse failure, and the self-hosted
  compiler runs its own test runner.
- *Order.* Any time; 0004 §2 queues it after `make self`.

**Order inside the subsystem.** C2 and C4 first (they make every later
step's tests survive and need only the pass table and the runtime's
ending); C1 with each dialect lane's change; C3 at the dialect cutover;
C7 with function nesting; C5's solver boxes with the solver layer; C6 on
the owner's answers; C8 independent.

## 6. Evidence for the owner's questions

No answers; what our code says.

**QL4 (byte-identical output for any thread count?).**
- The suite already holds it as a property of the whole compiler, for a
  few programs: `determinism.sh:3-25` compiles at 1, 3, 5 and 13 threads,
  a count drawn from 2 to 31 per run, and 13 again in a second process,
  and requires every artifact (Core, the module, the objects, the
  executable), every step's dump, and every executable's output and status
  on every input to be byte-identical (`:66-143`); `determinism.sh:146-206`
  requires the pipeline's module, statistics and remarks to be identical
  under one thread and under MLIR's pool. Two programs use the first
  (`determinism-rbtree`, `determinism-shapes`), two the second
  (`determinism-threads-rbtree`, `determinism-threads-linarray-lanes`).
- The fuzzer compiles each seed at a count drawn from {1, 3, 5, 13}
  (`Fuzz.idr:648-653`: "The compiler's output must not depend on it").
- Everything else compiles on one thread (`Makefile:123`,
  `tools/compile.sh:42`), so a schedule-dependent result anywhere but in
  those programs is not looked for.
- Names are held stable under edits, reordering and swaps
  (`tests/names-from-keys`, `tests/determinism-name-stability`).
- `make self`'s stage 2 = stage 3 is the same requirement at the largest
  scale (0004 §7.10, not a test yet).

**Q-llvm-6 (each solver run at one thread and many, frozen solutions
compared?).**
- No solver is tested that way; the only thread-count comparisons are the
  whole-pipeline ones above, which see a solver's answer only where it
  reaches the module's bytes, the statistics or the remarks.
- The googletest boxes (`foreign/idr/unittests`: Labels, Cycles, Flow,
  Identities, Constants, Ranges, ...) run single-threaded and are the
  natural home of such a check (§5.6 item 6, "solvers testable on
  arrays"); `make test-unit` runs whatever the build made, found by a glob
  (`Makefile:310-318`).
- `LabelsLeast.cpp` is already a second derivation of the label solve,
  compared point by point: the shape of an oracle a solver box can reuse.

**rc-Q3 (a space guarantee, tested?).**
- What is tested: no cell live at a normal exit, for every program run
  (`run.sh:13-39`, `IDRIS_RT_LIVE`) and every `%differential` run
  (`differential.sh:165-172`); `heap-free` (19 programs) and
  `no-heap-allocation` (40 uses in fixture RUN lines): no heap cell at all;
  `constant-stack` (36 uses in fixture RUN lines): no recursion grows the
  stack; the reuse
  properties per site (`reuses-in-place`, `reuses-every-cell`,
  `tests-nothing`, `counts-nothing`). *(measured: counts in §9.)*
- What is not: any bound on the peak. The runtime counts live cells
  exactly (`runtime/Alloc/Cells.cpp:151-223`) but keeps no high-water mark
  (`grep -rn "peak\|high.water" runtime` finds none); `peak_memory`
  (`tools/host.sh:121-150`, resident size) serves `tools/self.sh` and the
  bootstrap and no test; the benchmarks record time only
  (`bench/README.md:13-31`). 0004 §3.1 owes `stack-bytes<=N`, and 0006 G1's
  bounded-memory item has no test (§5.11 O3).
- Garbage-freedom (Perceus) is a statement at every point of a run, which
  an exit-time count cannot check; frame-limited reuse relates two
  placements of one program, which the action tags (`actions.sh`) can
  already produce (reuse skipped against reuse made).

**oom-6 (one exit status for out of memory, one for a stack overflow?).**
- Today every crash is status `IDRIS_RT_CRASHED` = 1
  (`runtime/idris_rt.h:297`, `runtime/Io/Ending.cpp:66-71`), out of memory
  (`runtime/Alloc/Cells.cpp:163-166`) and the stack's guard
  (`runtime/Start/Entry.cpp:77-80`, cause `stack exhausted`) included; lane
  18 records the same (`audits/p0/18-runtime.md:328`).
- The harness hard-codes it: a case with `expected-crash` must exit 1 and
  print exactly `idris-mlir: <cause>` (`e2e.sh:159-182`;
  `tests/harness-cases/expected`: "exit 0, but a crash exits 1"); the
  cause, not the status, tells crashes apart today.
- One test reaches `out of memory` (`tests/crash-integer-shift-huge`);
  none reaches `stack exhausted` (§3.2, §5.11 wave 2 #4). The stack is one
  64 GiB reservation with no runtime setting (1445d894, "one stack size,
  and no runtime setting or harness bound"), so a test that exhausts it
  must recurse through 64 GiB of frames.
- idris-mlir's own statuses (1 internal, 2 usage, 3 refusal) are spelled
  in `lit.sh:100-101` and expected by `profile_reject` (exit 3).

**Bearing on other questions.**
- *ods-Q6, Q-M2, Q-O5 (verification after every pass).* The check suite
  forbids turning the verifier off anywhere in the tree, RUN lines and
  patches included (`tests/verifier-every-pass/run`); lit adds
  `--verify-roundtrip` and `--idr-contracts` to every succeeding
  `idris-mlir-opt` (`lit.sh:229`). The verifier's per-pass time is already
  in `--mlir-timing`'s report, whose `Verifier` rows
  `tests/pipeline-timing/run` sets aside, so W7's measurement needs no
  `--verify-each=0`. The contracts clone the whole module per
  module/program pass (`Contracts.cpp:306`).
- *DD-Q8 (renames).* One representation change, the data-table cutover
  b9d4d592, touched 322 test directories (+1,794/−953 lines in `tests/`);
  the fixtures hold 26,025 idr names (§4 T1); the 47 rejects' directory
  names must start with their rule's phrase (`profile.sh:63-67`), so a
  renamed rule renames its tests.
- *Q-llvm-2, Q-E3, oom-2 (budgets never refuse).* No test expects a
  program refused by a count; 25 canon fixtures require the greedy driver
  to converge on their input (`test-convergence=true`), which tests our
  patterns, not a program's acceptance.
- *oom-3 (a footprint record per pass).* None exists (§3.1); the
  harness's timing record is wall time per compilation
  (`timing.sh:28-63`).
- *oom-4 (stack probes).* The guard is 1 MiB (`runtime/Start/Runner.cpp:37`)
  and its comment's claim "a frame larger than this could step over them,
  and none is" is checked by no test.
- *Q3 (the frontend's mirror cut over in the same change).* The harness
  mirrors Idris's primitive list and the lowering's guards by hand
  (`Prims.idr:3-10, 535-610`), not the dialect; it is unaffected by the
  mirror's cutover except through C2's table.

### New questions for the owner

- **T-Q1. The cutover's invariant oracle.** Should P0 name the program
  tests (234, 907 cases), the rejects with their neighbours, the
  `semantics@` runs, the benchmarks' outputs and the fuzz seeds as the set
  every step must pass unchanged, so that no step's correctness rests on
  tests the same step rewrote?
- **T-Q2. Rewriting the fixtures.** 339 fixtures hold 26,025 names of
  today's dialect. Rewrite them by hand in the cutover, convert them once
  by a script that is not kept, or replace each that can be a program test
  by one (whose emitted module no later dialect change touches)?
- **T-Q3. idr-expect's names.** Are the 82 property names and argument
  shapes a frozen test API across P0 (their implementations restated over
  declared facts), or open to DD-Q8's renames like everything else?
- **T-Q4. Contracts at scale.** Keep `--idr-contracts` test-only, and move
  it from a module clone per pass to per-function records under P0's
  nesting (C7)?
- **T-Q5. Measuring the verifier.** Measure W7 from `--mlir-timing`'s
  `Verifier` rows, keeping `tests/verifier-every-pass`'s rule whole, or
  allow a `--verify-each=0` run outside the tree for the measurement?

## 7. Deletion list

What goes, by file and symbol, each with the change that makes it dead
(§5) or the issue that names it (§4). Nothing here is deleted before its
replacement lands in the same change (hard cutover).

| file | symbol or lines | goes with |
| --- | --- | --- |
| `harness/harness.ipkg:7` | `depends = contrib, test` | C8, H1 |
| `harness/Main.idr` | `import Test.Golden` (`:61`), `takeOwn` (`:228-232`), the refusal of Golden's options (`:265-268`), `parameterized` (`:202-205`), `kindName`/`kindTitle`/`defaultSuite` as three switches (`:121-138`), `Eq Kind` (`:114-119`), `suites : List (String, String)` (`:171-177`) | C8, H1–H9 |
| `harness/Runner.idr` | `import Test.Golden` (`:17`), the `system` calls (`:53, 69, 73`), the verdict files' re-reading (`:71-75`) | C8, H11, H12 |
| `harness/Lock.idr:14` | `import Language.JSON` | H13 |
| `harness/TwoLevels.idr` | the module (its terms into `Sem`'s tables first; `checkOf`, `verdict`, `differences`, `printedValues`, `keyed`, `corpusOf` are dead now) | G26, 0004 §5.5 |
| `harness/Sem.idr` | `maxCases`, `checks` (`:40-43, 140-144`) | G9 |
| `harness/Prims.idr` | `opIndex`, `family`, `hostOf`, `spelling` as four switches (`:330-473`); `fixedName`, `fixedIndex`, `intIndex`, `tyIndex` (`:47-92`); `sameTy`, `sameIndex` (`:106-129`) | C8, G1–G4 |
| `harness/Gen.idr` | `exhaustive`, `Box`, `advance`, `shortlex` unless given a consumer (`:299-347`) | G14 |
| `harness/Fuzz.idr` | `parsePart`'s siblings `parseFile`, `parseSeed`, `parseCases`, `File` (into one request module, `:622-684`); `checkLines` (`:851-853`); `twoHosts`' unread `== <request>` sections (`:868-878`); `familyIndex` (`:112-122`) | G16–G21 |
| `harness/Lazy.idr` | `File`, `parseFile`, `parseSeed`, `parseCases` (`:230-290`); the `checks` rendering (`:318-319`) | G16, G17 |
| `harness/testutils.sh:31-56` | the second list of lib files | S1 |
| `harness/lib/run.sh:13-39`, `e2e.sh:153-187`, `differential.sh:142-172` | the three copies of the ending protocol | C4, S3 |
| `harness/lib/e2e.sh:107-109, 161` | the exit-beside-crash refusal; the status literal 1 | C4, S4 |
| `harness/lib/mlir.sh:5-116` | IR-tree-printer dumps and their discovery (`dump_options`' tree dir, `step_dumps`, `step_of`, pass-named `step_module`) | C2, S5, S6 |
| `harness/lib/differential.sh:7-58` | `lit_pipeline_from`'s text reconstruction; the stage regex | C2, S7, S8 |
| `harness/lib/actions.sh:17-27` | hand-spelled action tags | C2, S14 |
| `harness/lib/determinism.sh:174` | `--remarks-filter=idr-narrow-lanes` | C2, S15 |
| `harness/lib/fuzz.sh:153-154, 172` | the `[djrs]1` grep; the `"1 $3"` comparison | G20, S25 |
| `harness/lib/prelude.sh:253-300, 430-507` | `decided_exclusion`, `registry_value`, `core_uses` (once the report lists reached definitions) | S20, S21 |
| `harness/README.md:59-65, 133-134` | the hand table of case files; the module list | S2, H14 |
| `foreign/idr/include/idr/Transforms/Expect.h:146-230` | the 82 hand declarations | C1, E1 |
| `foreign/idr/lib/Transforms/Expect/Lookup.cpp:19-251` | the hand table | C1, E1 |
| `foreign/idr/lib/Transforms/Expect/Allocation.cpp:26-41` | the closure, suspension and `LinResource` special cases | C1, E5 |
| `foreign/idr/lib/Transforms/Expect/Closures.cpp:27-35`, `CountsNothing.cpp:20-25`, `Does.cpp:29-44`, `Placement.cpp:31-46, 78-93`, `TestsNothing.cpp:33-38`, `ReusesInPlace.cpp:24-30`, `ReusesEveryCell.cpp:20-27`, `ResetsUnshared.cpp:24-37`, `Output.cpp:23-29`, `CrashSites.cpp:27-38` | the op-class ladders (re-implemented over declared facts, names kept) | C1, E6–E14 |
| `foreign/idr/lib/Transforms/Expect/Quantities.cpp:90-98` | `spelled(Quantity)` | E18 |
| `foreign/idr/lib/Transforms/Expect/Facts.cpp` | `test-idr-facts` (with T5's fixtures) | C3, E19 |
| `foreign/idr/lib/Transforms/Contracts/Contracts.cpp:306`; `Contracts.h:45-46` | the module clone per pass; the mutex (or made real) | C7, E25, E26 |
| `foreign/idr/include/idr/IR/Traits.h:119-123` and its ODS | `Idr_BuildsValue` (lane 02's call) | C1, E11 |
| `tests/expect-coverage/run` | the `sed` over `Lookup.cpp` | C1, E1 |
| `tests/actions-accumulate`, `-columns`, `-narrow`, `-narrow-lanes`, `-returned-arguments`, `-stack`, `-tail-loops`, `-trmc`, `roles-contify`, `obs-debug-counter` | per-pass action fixtures | 0004 §5.1, T9 |
| `tests/determinism-rbtree`, `-shapes`, `-threads-rbtree`, `-threads-linarray-lanes` | four copies of one property | C5, T10 |
| `tests/names-from-keys`, `tests/determinism-name-stability` | text-regex name stability | C5, T11 |
| the `facts:` remark tables of `effects-alloc`, `effects-crash-call`, `effects-div`, `effects-force-strict`, `effects-io`, `effects-queries`, `expect-facts`, `func-call-effects` (84 remarks) | per-op effect tables | C3, T5, 0004 §5.8 |
| the 260 prose-matching `expected-error` lines (130 in `verify-*`) | wording of our own diagnostics | C3, T4 |
| the 53 SSA-naming and 13 op-naming check lines | incidental names | C3, T7, T8 |
| `tests/every-*-export/expected` (13) | the counts and compile-time-only names in the line | S22 |
| `tests/upstream-forward-dataflow-callee-lookup`, `-bytecode-deferred-quadratic`, `-liveness-trivially-dead` | wall-clock and CPU-time ratios (restated as work counts) | T13 |
| 221 constant program `expected` files | transcripts of harness constants | C8, T16, 0004 §2.2 |

## 8. Risks, unknowns, measurements needed

**Risks.**
- **The cutover rewrites its own oracle.** P0 is one hard cutover of the
  dialect, the pipeline and the passes; if the fixtures, the idr-expect
  implementations, `%differential`'s stage reader and the contracts are
  rewritten in the same change, a miscompile the cutover introduces can be
  written into the tests that should catch it. The program tests, rejects,
  `semantics@`, benchmarks and fuzz seeds are the only checks whose inputs
  P0 does not touch (C3, T-Q1); they must pass unchanged at every step,
  which needs C2 (stage names) to land first.
- **Effort and drift in the fixture rewrite.** 26,025 idr names, 1,024
  lines of reference IR, 644 pass-naming RUN lines, 86 pipeline nests
  (T1, T3). One earlier representation change (b9d4d592) touched 322 test
  directories; a converter that is not kept, or hand rewriting, is the
  owner's call (T-Q2).
- **The oracle can be weaker after the rewrite than before.** A fixture
  rewritten so that its `%differential` REF is regenerated from the new
  pass's output compares the pass with itself. Every REF of the 1,024
  lines must stay a hand-stated meaning, not an output copied back.
- **Contracts at the stage-1 module.** A module clone before every module
  or program pass (`Contracts.cpp:306`) on a 71 MB module; P0's
  measurements on the stage-1 module, if taken under `--idr-contracts`,
  would measure the clones too.
- **Parallel paths untested by the suite.** Every test compilation runs on
  one thread (`Makefile:123`); P0's parallel solver schedules (§5.3 S1,
  §5.4 Design 1) would be exercised by fuzz (one count per seed) and four
  determinism tests only, until C5.
- **The runner on one host.** The harness's Idris runs under idris-mlir
  only through `fuzz-two-hosts` (the generators); the runner itself cannot
  (H1), so a self-hosted compiler does not yet run its own tests (0004
  §2.1).
- **This checkout's `tests/` holds two non-tests.** `tests/build` (an
  ignored old runner build, 26 files) and `tests/spec` (36 untracked
  `output` files of the pre-purge spec layout, d346040c) make `discover`
  refuse to start (`Main.idr:192-200, 274-275`) here; the owner's tree may
  differ (*measured*: `find tests/build tests/spec -type f | wc -l`; `git
  status` shows `?? tests/spec/`).
- **A stack-exhaustion test is impractical as the runtime stands.** One
  64 GiB reservation and no setting (1445d894) means a test must recurse
  through 64 GiB of frames; oom-6's and B2's checks need a design answer
  before a test (§6).

**Unknowns.**
- How many fixtures could become program tests (C3): a fixture's subject
  is often one pass's handling of one IR shape the frontend may never
  emit; not counted.
- Whether P0 keeps stages at all as `Passes.td` has them (`higher`,
  `first`, `owned`, `lowered`), which C2's names and `tests/pipeline-stages`
  rest on (lane 13).
- Which idr-expect properties P0 makes vacuous: `effects` (if functions
  carry effects in their types, DS2.1/T6), `stage` (if stages change),
  `lowered` (if `idr.program` goes), `labels*` (if closure sums are per
  flow set, §5.9 D3).

**Measurements needed** (none can be taken here: no built compiler).
- The suite's time and its split by kind, and the share of a program
  test's time spent in `--idr-contracts` (28274bd3 measured dumping: 13
  program tests in 32 s against 149).
- `--idr-contracts`' memory on the largest test program and on the
  stage-1 module.
- The verifier's share of each pass from `--mlir-timing`'s `Verifier` rows
  on the stage-1 module (W7, T-Q5).
- The live-cell high-water mark of the benchmarks, if C6's counter is
  built, against their input sizes (rc-Q3).

## 9. Sources read

**Required reading, in order.** `.claude/skills/representation-first/SKILL.md`
(whole); `.claude/skills/testing-by-search/SKILL.md` (whole); `AGENTS.md`
(whole); `proposals/0000-mlir-native.md` (whole: §0–§4, every lane of §5
from 5.1 to 5.11 including their findings, designs, questions and notes,
§6–§9); `proposals/0003-facts-once.md` (whole); `proposals/0004-tests.md`
(whole); `audits/p0/README.md` (whole).

**The subsystem, line by line.**
- `harness/`: `Main.idr`, `Runner.idr`, `Lock.idr`, `Gen.idr`, `Prims.idr`,
  `Sem.idr`, `Fuzz.idr`, `Lazy.idr`, `TwoLevels.idr`, `harness.ipkg`,
  `one.sh`, `testutils.sh`, `README.md`, `kinds/{fixture,fixture.expected,program,reject}`,
  `templates/` (all seven files), `lib/{harness,timing,rules,compile,run,heap,mlir,expect,properties,e2e,profile,determinism,actions,lit,differential,planted,bench,fuzz,idris-lex,cpp-lex,prelude}.sh`,
  `prop/{prop.h,prop.sh}` (whole), `prop/{bigmodel.h,utf8model.h}` (heads
  and declarations).
- `foreign/idr/include/idr/Transforms/{Expect.h,ExpectArguments.h,Contracts.h}`;
  `foreign/idr/lib/Transforms/Contracts/Contracts.cpp`;
  `foreign/idr/lib/Transforms/Expect/`: `Expect.cpp`, `Lookup.cpp`,
  `Arguments.cpp`, `Report.cpp`, `Named.cpp`, `CrashSites.cpp`,
  `Allocation.cpp`, `Quantities.cpp`, `Facts.cpp`, `Placement.cpp:1-140`,
  `Does.cpp:1-100`, `CountsNothing.cpp`, `TestsNothing.cpp`,
  `ResetsUnshared.cpp`, `ReusesInPlace.cpp`, `ReusesEveryCell.cpp`,
  `MovesOut.cpp`, `Closures.cpp`, `Output.cpp`, `Guards.cpp`, `Stage.cpp`,
  `SolvedEffects.cpp`, `Proved.cpp`, `LabelsLeast.cpp`, `Lowered.cpp`,
  `Clones.cpp`, `NotCalled.cpp`, `Continuations.cpp`, `Folded.cpp`,
  `Folds.cpp`, `ComputesNothing.cpp`, `StructuredLoops.cpp`, `InPlace.cpp`,
  `Sizes.cpp`, `Growth.cpp`, `Cycles.cpp`, `Paths.cpp`, `Words.cpp`,
  `CountedLoop.cpp`, `Apart.cpp`, `Reaches.cpp` (whole); `Calls.cpp`,
  `ConstantStack.cpp`, `Returns.cpp`, `Signature.cpp`, `Memory.cpp`,
  `NarrowedLanes.cpp`, `ByName.cpp`, `Vectorized.cpp`, `DimsKnown.cpp`,
  `Fused.cpp`, `LinkerNames.cpp`, `Values.cpp` (heads and every cast, by
  `grep`).
- `Makefile` (head, `:100-125`, `:265-330`); `bench/README.md`;
  `tools/host.sh:115-160`; `tools/compile.sh` (thread handling);
  `runtime/Io/Ending.cpp:1-76`, `runtime/Alloc/Cells.cpp:150-223`,
  `runtime/Start/Runner.cpp:1-90`, `runtime/Start/Entry.cpp:77-145`,
  `runtime/idris_rt.h:290-310` (the ending and the crash status);
  `foreign/idr/unittests/` (listing, `CMakeLists.txt:76-78`).
- Tests read in full: `determinism-rbtree`, `determinism-threads-rbtree`,
  `determinism-name-stability`, `determinism-shapes`,
  `determinism-threads-linarray-lanes`, `fuzz-seeds`, `fuzz-two-hosts`,
  `fuzz-lazy`, `semantics`, `actions-skip-programs`, `verifier-every-pass`,
  `expect-coverage`, `rules-covered`, `harness-cases`, `harness-near`,
  `upstream-forward-dataflow-callee-lookup`,
  `upstream-greedy-multi-region-ancestors`,
  `upstream-liveness-trivially-dead`, `pipeline-timing`,
  `no-behaviour-options` (its kept list); RUN and check lines of
  `rc-live`, `effects-io`, `lower-to-llvm`, `lower-cells`, `defunc-cycle`,
  `canon-case-of-case`, `fold-division`, `obs-stats`, `pipeline-stages`,
  `obs-debug-counter`, `names-from-keys`, `verify-roundtrip`,
  `asm-aliases`, `asm-names`, `syntax-grades`, `rc-share-trap`,
  `rc-exclusive`, `rc-atom-pairs`, `canon-facts`, `stack-expect`,
  `e2e-statuses`; heads and marks of `foldlm-deep`, `deep-recursion`,
  `tail-loop-deep`, `bounded-capped`, `bounded-dictionary-root`,
  `bounded-family-applied`, `linarray-bubble`, `linarray-combinators`,
  `linarray-fill-sum`, `guards-messages-array-index`,
  `guards-messages-cast-nan`; every program's `expected` (by hash) and the
  14 non-constant ones in full; every `cases/*/expected-crash`.
- Other lanes' documents, for what is theirs: `audits/p0/02-ods-effects.md`
  (`BuildsValue`, F5), `04-canon.md` (C42, the fold-leak counter),
  `18-runtime.md` (`:223-252, 328-334`, crashes and live cells).

**History.** `git log --oneline -- harness/` (14 commits) and of
`Expect`/`Contracts` (18); `git show` of d346040c (the purge), ef45c0a7
(cases, `%differential`, `near/`, planted witnesses), 28274bd3 (contracts
in process; dumps only of read steps; the `idr-rc` step that no pass was
any more), 7987388b (`Idr_BuildsValue` added for idr-expect), b9d4d592
(`--shortstat -- tests`: 322 test directories), 31daec54, c4a046e0,
1445d894 (one stack size, no setting).

**Commands for the measured claims** (run from the repository root; zsh
needs `bash -c` for the loops).
- Kinds and suites: `for d in tests/*/; do d=${d%/}; if [ -f $d/run ];
  then k=script; elif [ -f $d/Main.idr ]; then head -1 $d/Main.idr | grep
  -q '^-- *expect:' && k=reject || k=program; else n=$(ls $d | grep -c
  '\.mlir$'); [ $n = 1 ] && k=fixture || k=other; fi; echo "$k
  $(cat $d/suite 2>/dev/null || echo default) $d"; done | awk '{print $1,
  $2}' | sort | uniq -c`.
- Fixture mechanisms: for each fixture's `.mlir`, `grep -q FileCheck`,
  `grep -q idr-expect`, `grep -q %differential`, `grep -q
  verify-diagnostics`, `grep -q test-idr-facts`, counted (140, 235, 186,
  104, 8).
- Dialect exposure: `cat <fixtures> | grep -o '[!#]\?idr\.[a-z_.]*' | wc
  -l` (26,025); `... | sort -u | wc -l` (151); `grep -l '#idr\.types'`
  (322), `grep -l '!idr\.world'` (223), `grep -l '!idr\.\(q\|lin\|own\|excl\)<'`
  (68); `grep -c '^ *// *\(REF\|REFERENCE\):'` (1,024); RUN lines with
  `--idr-[a-z]` (644) and `pass-pipeline` (86).
- Check lines (prefixes other than RUN, STDIN, REF, REFERENCE): 718,
  of which naming `idr.` 170, an SSA value 53; `expected-error` 390, of
  which `{{expected <property>: ` 130; `expected-remark` with `facts: ` 84.
- Program transcripts: `md5 -q tests/<program>/expected | sort | uniq -c`
  (161, 41, 19 and 14 singletons); cases: `ls tests/<program>/cases | wc
  -l` summed (907).
- `mlir.expect` steps: `grep -v '^#' tests/*/mlir.expect | grep -o
  '^[^:]*:[a-z][a-z0-9-]*:'` counted by step.
- `grep -rn BuildsValue foreign/idr/lib foreign/idr/include | grep -v
  '\.td:'`; `grep -l test-convergence tests/*/*.mlir | wc -l` (25);
  `grep -rln peak_memory harness tests` (none);
  `git show --shortstat --format= b9d4d592 -- tests`.
