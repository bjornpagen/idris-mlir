<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Cull audit: the tests, the harness, the tools, the benchmarks and the build glue

HEAD at start: `d378e120`. HEAD at finish: `45599c62`. Ten commits landed
while this was read (49a26442 to 45599c62). None of them touches `tests/`,
`harness/`, `tools/`, `bench/`, the `Makefile`, `CMakeLists.txt`,
`CMakePresets.json` or `toolchain.lock.json`
(`git diff --stat d378e120 HEAD -- <those>` is empty). So every line cited
below holds at both heads.

Area:
- `tests/`: 646 tests, 4,322 files, 52,350 lines. By kind: 201 scripts,
  314 programs, 58 refused programs and 73 dialect fixtures. By suite: 33
  in `check`, 3 in `test-idr` beside the fixtures, and 127 in
  `test-mlir-tools`.
- `harness/`: 55 files, 13,639 lines.
- `tools/`: 19 files, 4,281 lines.
- `bench/`: 126 files, 8,893 lines.
- The `Makefile` (498 lines), `CMakeLists.txt` (465) and
  `CMakePresets.json` (56).

## Method

This is the Elon algorithm, in order:
1. Each part names the ruling (Dnnn), the decision (Cnnn) or the AGENTS.md
   rule that requires it, and the fact only it supplies.
2. A part is deleted when its rule is gone, or when a type, a construction,
   a generated table or another part already holds its fact.
3. Only then is what survives looked at for simplification.

The tests were also read against the testing-by-search skill: delete a
test that checks more than its contract, checks nothing, or cannot fail.

Grounds:
- *read*: the cited line was opened.
- *measured*: a search or count, with its command.
- *conjecture*: the verdict needs a judgement or a measurement that is
  named.

How things were checked:
- "No reader" is a `git grep` over `compiler/ foreign/ harness/ tests/
  tools/ bench/ Makefile CMakeLists.txt`, leaving out `audits/`,
  `proposals/`, `sources/`, `third_party/` and every planted
  `witness/`/`near-miss/`.
- A dead-name scan was run over `harness/*.idr`
  (`/tmp/tests-tools/dead.py`: every top-level name, with its uses counted
  outside comments, qualified uses included). It found no dead top-level
  name, so the harness is live at the symbol level. A first pass flagged
  six names, and each turned out to be a qualified use (`Prims.tInt`,
  `Lazy.checkOf`). What dies below dies at a mode of the runner or at a
  test, not at a symbol.
- Each shell function of `harness/lib/harness.sh` and
  `harness/testutils.sh` was counted against the test scripts that call
  it (57 functions).
- Each runner mode of `harness/Main.idr` was counted against its callers.
- Each tool of `tools/` was counted against its callers.
- Each `make` target was counted against its callers.
- Every `option(` and `CACHE` variable of the CMake lists was found
  (`git grep -E 'option\(|CACHE (STRING|BOOL|PATH)'`).
- Nothing was built, generated or run, and no `make` target was run.

The user's request, "keep all the sources", is kept:
- no file under `sources/` is a candidate;
- no `upstream/<bug>/` report is a candidate;
- no run record or measurement note under `bench/records/` is a
  candidate. These are the grounds that proposals and audits cite, and
  C251 keeps them as history.
- Every citation below stays.

Other lanes are editing the checkout. `git status` at finish shows, in the
area, edits by others to `tests/built-of-a-shared-part*`, three deleted
`lowered-hold-*`/`opened-hold-*` fixtures, and seven untracked test
directories (`checker-backtick-prefix-refused`,
`checker-builtin-natural-reduced-successor`, `checker-search-repeats`,
`closure-type-keeps-index` and others). None of those is a candidate.
Every file named in a candidate below is clean at finish.

Owners come from `audits/p0/verify/ownership.json`: `tests/`, `harness/`
and `bench/` are L19's; `tools/`, `toolchain.lock.json` and `PINS.md` are
L06's; the `Makefile`, `CMakeLists.txt` and `CMakePresets.json` are INT's.

## 1. Candidates, ranked by lines deleted

### 1. `tests/file-size`: a ratchet whose rule was deleted on 2026-10-03

- **The part.** `tests/file-size/` is 14 files and 3,390 lines:
  - `run` (67 lines): `file_size ROOT`, a 400-line limit on every `.cpp`
    and `.h` of `foreign/idr` and `runtime/`;
  - `allowed`, which lists one unit, `foreign/idr/tools/idris-mlir-tblgen.cpp`;
  - `witness/` and `near-miss/`, 3,312 lines of padding files of 400,
    401 and 450 lines.
- **The fact it supplies.** No C++ unit of ours is over 400 lines. The
  test states the reason: "a unit holds one concept ... one that grows
  past a screenful is two" (`run:4-8`).
- **The rule that once required it.**
  - The rule was "One concept per file ... A unit over 400 lines is two
    concepts". It entered AGENTS.md and `foreign/idr/lib/MODULES.md` in
    0641826a (2026-10-03, the C++20 named-modules design).
  - 4cfce768 deleted it the same day (2026-10-03, "MODULES.md and the
    reorganization's plans are gone"; the commit removes 4 lines of
    AGENTS.md).
  - No later AGENTS.md has it: `git show <c>:AGENTS.md | grep -c 400` is
    0 at 4cfce768, d06ed15c, d346040c and 28ef777e, and 0 at HEAD.
  - No ruling or decision restates it: `grep -n '400 lines\|file-size'
    proposals/0000-mlir-native.md` finds 0 hits.
  - `audits/p0/verify/sweep.md:13` lists the test among the rules it ran,
    but only as a test, with no rule behind it.
  - So the test has outlived the rule it checked by twenty days.
- **Readers.** None. `git grep -n 'file-size\|file_size' -- ':!tests/file-size'
  ':!audits' ':!proposals' ':!sources'` finds only `io.file_size`, an
  unrelated op. *Measured.*
- **The deletion.**
  - `tests/file-size/` whole (3,390 lines).
  - Nothing else names it. Planted.idr runs whatever check a test hands
    it, so it needs no change.
- **Verdict.** DELETE. *Read* (the rule's deletion, 4cfce768) and
  *measured* (no reader).
- **Owner.** L19. Clean; waits on nothing.

### 2. `tools/upstream-idris`: runs upstream's test suite, with no caller and against the oracle rule

- **The part.** `tools/upstream-idris/` is 517 lines: `run` 98, `one`
  124, `as-idris` 133 and `common.sh` 162. It runs a group of
  `third_party/Idris2/tests` through idris-mlir and records `pass`,
  `fail` or `skip` in the uncommitted file
  `build/upstream-idris/results` (`run:1-17`). `as-idris` is the compiler
  upstream's run scripts receive. It maps Idris's command line onto
  idris-mlir and the frontend, `--check` included (`as-idris:104-110`).
- **The fact it supplies.** How many of upstream's test programs
  idris-mlir passes, judged by upstream's transcripts. Nothing holds
  that fact. No rule asks for it either:
  - AGENTS.md: "There is no oracle. A test's committed expected files are
    its specification ... Do not add a comparison against Idris's Chez
    backend or stock evaluator". Upstream's `expected` files are no
    committed test of ours, and they are the outputs of upstream's own
    runs.
  - D116: "i don't care about idris-mlir compiling upsteram".
  - The programs this compiler commits to are its own tests
    (`every-*-export`, `prelude-coverage`).
- **The rule that once required it.** None found. It is a measurement
  harness from the 0004 wave (2c042728, 2026-10-18) that has no gate.
- **Readers.**
  - No make target, test or script runs it
    (`git grep -n 'upstream-idris'`: `Makefile:129`, a comment;
    `tools/toolchain.sh:6`, a comment; its own files). *Measured.*
  - Readers it keeps alive:
    - `export IDRIS2_PREFIX` (`Makefile:126-130`) gives its only reason
      as "What reads Idris's environment is upstream's test scripts".
    - The frontend's `--check` task has
      `tools/upstream-idris/as-idris:109` as its only reader
      (`audits/p0/cull/frontend.md` §"Driver.idr's tasks";
      `compiler/src/IdrisMLIR/Frontend/Driver.idr:19, 123, 130, 158-159,
      186`). *Read.*
- **The deletion.**
  - `tools/upstream-idris/` whole (517 lines).
  - `tools/toolchain.sh:6`.
  - `Makefile:126-129`, the comment that justifies the export.
  - Chained, outside this area:
    - the frontend's `--check` task (L16), about 10 lines;
    - the `export IDRIS2_PREFIX` line, once a run of `make check` and
      `make test` shows nothing else inherits it. `tests/idris-environment/expected:2`
      prints it and would change too. That step is *conjecture*: no
      reader was found besides upstream's scripts, but an `idris2`
      started without its own prefix would read it.
- **Verdict.** DELETE. *Read* (no caller, and the oracle rule) and
  *measured* (the caller search). About 522 lines in this area.
- **Owner.** L06 (`tools/`), INT (`Makefile`), L16 (the chained
  `--check`). Clean; waits on nothing. The `export` waits on one suite run.

### 3. `tools/compile-times.sh` and the timing record every compilation writes for it

- **The part.**
  - `tools/compile-times.sh`, 408 lines. "The compile times the golden
    tests recorded ... It reports; it gates nothing" (`:4-9`). It
    compiles each recorded module again under `--mlir-timing` and splits
    the report into parse, optimize, verify, analyses, llvm and the rest.
  - What feeds it, in `harness/Harness.idr:486-551`: `recordedWhat`,
    `timingId` and `recordTime`, 66 lines. There is also the clock in
    `compileProgram` (`:556` "its wall time recorded", `:560`, `:563`,
    `:564`).
  - On every compilation of every test run, `recordTime` appends a row to
    `harness/build/timing/<test>.tsv` and copies the emitted module there
    (`:516-539`).
- **The fact it supplies.** A per-test breakdown of compile time across
  the suite. The per-run figure is MLIR's own `--mlir-timing`. Its rows
  are already checked by `tests/pipeline-timing` (through `timing_rows`,
  which stays).
- **The rule that once required it.** None. AGENTS.md asks that "what
  templates cost the compiler's own build is measured", but that is the
  C++ build, not this. The tool also reads rows by pass name (`:27,
  34-40`: `IdrOptimize`), so a renamed pass zeroes a column silently,
  which is the shape AGENTS.md forbids in tests.
- **Readers.** `recordTime` has one: `compileProgram` (`Harness.idr:564`).
  The timing directory has one reader, `tools/compile-times.sh:106`
  (`git grep -n 'compile-times\|recordTime\|timingId\|recordedWhat\|harness/build/timing'`).
  No make target, test or script runs the tool. *Measured.*
- **The deletion.**
  - `tools/compile-times.sh` (408).
  - `harness/Harness.idr:486-551` (66).
  - `:556` (the clause), `:560`, `:563`, `:564` (3 lines). `compileProgram`
    becomes the bounded call alone.
  - About 477 lines.
- **Verdict.** DELETE. *Conjecture*: the owner values measurement
  (memory: "Tracy everywhere"). If the owner keeps it, it needs a caller,
  and its rows need the pass name from the specification rather than a
  literal.
- **Owner.** L06 (`tools/`), L19 (`harness/`). Clean; waits on nothing.

### 4. `bench/regex-dna`: the retired twin of `regex-redux`

- **The part.** `bench/regex-dna/` (Main.idr, main.c, input-from), 268
  lines. Its smoke inputs are `tests/bench-smoke/regex-dna.in` (421
  lines) and `.out` (13), plus one line of `tests/bench-smoke/expected`
  (`:23`).
- **The fact it supplies.** The time of the Benchmarks Game's retired
  regex program. Its own header says "retired for regex-redux"
  (`Main.idr:5`). It has the same `Re` type, the same backtracking
  matcher in continuation style, and the same generated input
  (`input-from`: `fasta 5000000` for both) as `bench/regex-redux`. It
  differs in eleven IUB replacements against regex-redux's five, written
  front to back modulo the constructor.
- **The rule that once required it.** None. `bench/README.md:34-37`
  takes the game's programs "under the game's own names", but the game
  replaced this one with regex-redux. No ruling names a benchmark.
  `proposals/0000-mlir-native.md` cites "the benchmarks" only as a corpus
  (C152).
- **Readers.** `tests/bench-smoke` and nothing else
  (`git grep -n regex-dna`, records excluded). *Measured.*
- **The deletion.** About 703 lines:
  - `bench/regex-dna/` (268);
  - `tests/bench-smoke/regex-dna.in` and `regex-dna.out` (434);
  - `tests/bench-smoke/expected:23` (1).
- **Verdict.** DELETE. *Conjecture*: its one distinct trait, output
  written in tail position modulo the constructor, is what the `trmc-*`
  tests hold, and a benchmark measures speed, not that.
- **Owner.** L19. Clean; waits on nothing.

### 5. `tools/bisect.sh`: a debugging aid with no caller

- **The part.** `tools/bisect.sh`, 197 lines. It finds the action of one
  tag whose application changes what a program does, by MLIR's debug
  counter in idris-mlir-opt (`:4-34`).
- **The fact it supplies.** Which single action of a tag (for example
  `idr-specialize-clone` or `idr-raise`, both still in
  `Generated/Actions.h.inc:37, 39`) changes behaviour. Nothing else
  locates it. `harness/Universal.idr:128-183` finds that a drawn set of
  skipped actions changes a run, and names the seed, but does not
  bisect.
- **The rule that once required it.** None.
- **Readers.** Only the comment at `tools/toolchain.sh:4`. *Measured*
  (`git grep -n bisect.sh`). No test runs it, so nothing tells when it
  breaks.
- **The deletion.** `tools/bisect.sh` (197) and the word at
  `tools/toolchain.sh:4`. About 198 lines.
- **Verdict.** DELETE. *Conjecture*: it is the natural companion of
  Universal.idr's skipped-actions check. If the owner keeps it, a test
  should run it on a planted case, so that it can fail.
- **Owner.** L06. Clean; waits on nothing.

### 6. The CMake configure gate: a second, weaker check of the pinned toolchain (the owner's call)

- **The part.**
  - `CMakeLists.txt:5-29`: the lock's `accept` series of Ninja, CMake
    and LLVM, read and matched against the running tools.
  - `:88-90`: the compiler's version against the LLVM series.
  - The three `accept` fields of `toolchain.lock.json`.
  - `tests/configure-gate/` (103).
  - In `harness/Lock.idr` (`:6, 29, 46, 72-75`) and `tests/lock`, the
    series parts: the witnesses `outside-series` and
    `series-cut-in-a-number`, and the near-misses `wider-series` and
    `no-series`.
  - About 180 lines.
- **The fact it supplies.** A configure refuses a CMake, a Ninja or a
  clang outside its release series.
- **Where the representation holds that fact.** `tools/verify-pins.sh`
  holds it, more strongly: each tool's provenance stamp must name the
  lock's exact revision (`verify-pins.sh:156-160`, `llvm`). Every make
  target that configures runs it first (`Makefile` `build`:
  `$(PINS) cmake ninja llvm sysroot`). The presets name the pinned Ninja
  and toolchain file themselves (`CMakePresets.json:9, 12`). So under
  `make` the gate can never fail. It catches only a hand-run
  `cmake --preset` with a foreign CMake binary.
- **The rule that once required it.** PINS.md:7-9 says the language
  profile and configure gate were "adopted from bjornpagen/cpp-starter",
  and PINS.md:62, 128-129 calls the lock the one source of the accepted
  series. That makes it the owner's own profile. It is no ruling of P0,
  and AGENTS.md does not name it.
- **Readers.** `CMakeLists.txt:8-10` reads `accept`. So do
  `harness/Lock.idr:46, 74` and `tests/configure-gate/run`
  (`git grep -n '\baccept\b'`). *Measured.*
- **The deletion.**
  - The lines above.
  - PINS.md:62's `versions-in-lock-file` sentence and :128-129.
  - The Clang-ID and libc++ checks (`:85-87` and `:386-395`) are not
    this fact and stay.
- **Verdict.** MERGE into `tools/verify-pins.sh`, the one place a pin is
  checked. *Conjecture*: this is the owner's adopted profile, so it goes
  to the owner before anyone acts.
- **Owner.** INT (`CMakeLists.txt`), L06 (the lock, PINS.md), L19 (the
  tests). Clean. Waits on the owner.

### 7. `tests/build-preset` and `tests/commands`: tests of the Makefile's text

- **The parts.**
  - `tests/build-preset/` (57). The rule: `make -n build` names the
    presets and the pinned CMake, never Ninja or a compiler directly.
  - `tests/commands/` (123):
    - every `make X` the Makefile's opening comment documents is a
      target;
    - every `make X` AGENTS.md names is documented;
    - `tools/bootstrap.sh` is executable;
    - `make doctor` prints four lines.
- **The facts they supply.** That the Makefile says certain things, and
  that the help text and the targets agree. No behaviour of the compiler
  or of a build product is checked:
  - a missing target already fails at once when it is run
    (`No rule to make target`);
  - a build that bypassed the presets still builds from the same
    toolchain file.
- **The rule that once required them.** None in AGENTS.md or P0. "The
  presets are the only interface for building C++" is a comment in the
  Makefile (`:180`) and the cpp-starter profile. AGENTS.md's test
  rule reads: "Tests check behaviour: exit status, produced artifacts,
  the property a pass guarantees".
- **Readers.** Only the runner.
- **The deletion.** Both directories (180 lines). The Makefile comment
  stays as documentation.
- **Verdict.** DELETE. *Conjecture* (ceremony by the testing guideline).
- **Owner.** L19. Clean; waits on nothing.

### 8. `tools/lanes`: the clone-per-lane process of 2026-10-19

- **The part.** `tools/lanes/README.md` (85) and `tools/lanes/setup.sh`
  (29). They make one clone per lane at `../idris-mlir-lanes/<lane>`, and
  the README tables six lanes ("ownership, defunc, control, arrays,
  target, upstream").
- **The fact it supplies.** None now:
  - the lanes it names are gone, and the P0 swarm is L01 to L21 with INT,
    working in this checkout (`audits/p0/verify/ownership.json`);
  - `../idris-mlir-lanes` does not exist on this host (`ls`, *measured*);
  - its state is stale: "While main does not compile (the `idr.memo.run`
    and array-role WIP commits at the head of 2026-10-19)";
  - its "rules (binding)" restate AGENTS.md (hard cutover, upstream
    patches, read both skills) except one line: "Main only. No branches,
    no worktrees."
- **The rule that once required it.** The 2026-10-19 lane process, since
  replaced by the P0 swarm.
- **Readers.** `setup.sh` is read only by the README. `tools/toolchain.sh:11`
  names `(tools/lanes)` in a comment (`git grep -n 'lanes/setup.sh'`).
  *Measured.*
- **The deletion.** `tools/lanes/` (114) and the parenthesis at
  `toolchain.sh:11`. The `pwd -P` resolution it explains stays, because
  agent worktrees under `.claude` also link `.toolchain`. The one owner's
  line ("main only") goes to the coordinator, to be kept in AGENTS.md if
  the owner still wants it.
- **Verdict.** DELETE. *Read.* About 116 lines.
- **Owner.** L06. Clean. The "main only" line waits on the coordinator.

### 9. `harness/Trace.idr`'s `--trace-totals` and `--trace-units`: modes no one calls

- **The part.**
  - In `harness/Trace.idr`:
    - `traceTotals` (`:74-82`) and `totals` (`:69-72`);
    - `millis` (`:61-67`), read only by those two;
    - `Sums`, `instantiation`, `sumEvent`, `mostFirst` and `traceUnits`
      (`:84-116`; `add` at `:91-92` stays, because `zoneCounts` reads
      it);
    - the event fields `count` and `detail` that only they read;
    - the header (`:3-12`).
  - Their dispatch in `harness/Main.idr`: `:95-96`, the usage at `:381`,
    and `:509-510`.
- **The fact it supplies.** Sums of a time trace for a human reading a
  baseline.
- **The rule that once required it.** None. The mode is manual; the
  module says "the baseline every measurement of a change is taken
  against".
- **Readers.** None. `git grep -n -e trace-totals -e trace-units -e
  traceTotals -e traceUnits` hits only `Trace.idr` and `Main.idr`. *Measured.*
  `zoneCounts`, which `Scale.idr` imports (`:51`), stays.
- **The deletion.** About 65 lines.
- **Verdict.** DELETE. *Measured.*
- **Owner.** L19. Clean; waits on nothing.

### 10. `harness/templates/`: copy-from examples nothing runs

- **The part.** `harness/templates/` is 9 files and 49 lines: script,
  program, reject with `near/`, and fixture. `harness/README.md:180, 184`
  points at them.
- **The fact it supplies.** An example of each kind of test. Each kind
  is already defined by `kindOf` (Main.idr), stated in
  `harness/README.md:23-50`, and shown by every test of that kind. The
  `harness-*` tests are the vocabulary's own executable examples.
- **The rule that once required it.** None. A template nothing runs
  cannot fail, which is what the testing guideline deletes.
- **Readers.** None (`grep -rn templates harness tests Makefile`: only
  the README). *Measured.*
- **The deletion.** `harness/templates/` (49). `harness/README.md:180`
  goes, and `:184` becomes "copy a test of its kind". About 52 lines.
- **Verdict.** DELETE. *Read.*
- **Owner.** L19. Clean; waits on nothing.

### 11. `tests/scale-threads`: the determinism property on one more input

- **The part.** `tests/scale-threads/` (41 lines of `run`, 5 of
  `expected`). It compiles the `functions` scale fixture on one thread
  and on the pool, then compares the module, the objects and the
  executable byte for byte.
- **Where the fact is held.** `harness/Determinism.idr` holds the same
  property, more strongly: 1, 3, 5 and 13 threads, a drawn count, and a
  second process, comparing the core, module, objects, executable and
  dumps (`Determinism.idr:3-8, 47-54`). It runs on `bench/rbtree` and
  `tests/shapes` (`tests/determinism-rbtree`, `tests/determinism-shapes`).
  What scale-threads adds is input size: a split of the work "many ways".
- **The rule that once required it.** AGENTS.md's determinism under
  threads, which Determinism.idr carries.
- **Readers.** The runner.
- **The deletion.** `tests/scale-threads/` (46). If the larger split is
  wanted, a `determinism` call over the scale fixture replaces it.
- **Verdict.** MERGE into Determinism.idr's check. *Conjecture*: whether
  rbtree's split is wide enough is a measurement, the number of
  functions per thread at 13 threads.
- **Owner.** L19. Clean; waits on nothing.

### 12. `tests/bench-records`: a golden that re-renders a historical record

- **The part.** `tests/bench-records/run` (26) and `expected` (1). It
  runs `bench/report.sh` again over each record in `bench/records/` and
  requires `results.md` and the three SVGs to be byte for byte what
  `report.sh` makes now.
- **Where the fact is held.** `tests/bench-report` already checks what
  `report.sh` does with a record (`run:4-20`, a `before`/`now` fixture
  of its own). bench-records adds a requirement that a 2026-10-13
  record's chart bytes follow every later change to `report.sh`. That
  rewrites history to match the tool. It is also Winters' brittle case:
  an exact comparison of SVG bytes, which the contract does not fix.
- **The rule that once required it.** None. C251 keeps the records as
  history, and history is not re-rendered.
- **Readers.** `bench/README.md:53` names it.
- **The deletion.** `tests/bench-records/` (27), and
  `bench/README.md:52-53`'s clause. The record itself stays, as the
  user's request and C251 ask.
- **Verdict.** DELETE. *Read.* About 28 lines.
- **Owner.** L19. Clean; waits on nothing.

### 13. `tests/expect-table-current` and `--expect-table`: a second generator beside specgen

- **The part.**
  - `tests/expect-table-current/` (22 lines of `run`, 1 of `expected`).
  - The runner's `--expect-table` (`harness/Main.idr:85-86, 384, 515`).
  - The exception for the table at `tests/zones/run:11, 33`.
- **The fact it supplies.** `foreign/idr/include/idr/Transforms/ExpectProperties.inc`
  is what `harness/Properties.idr` prints.
- **Where the representation should hold it.**
  - `harness/Properties.idr` is a generator of a C++ table that
    idris-mlir compiles in. It already imports
    `IdrisMLIR.Spec.Generator.Render`.
  - Its records include the contracts' relations: "the one list of what
    every pass keeps" (`Properties.idr:3-12`). Those are compiler facts,
    not test vocabulary.
  - AGENTS.md: "Every fact knowable when the compiler is built is a
    compile-time constant, generated from the dialect's Idris
    specification", and the generated files' fingerprints live "in one
    committed manifest ... `make check` regenerates them".
  - Moved into `compiler/spec`, `specgen` writes the table, the manifest
    fingerprints it, and `tests/spec-current` holds it. The harness
    imports the records for `expect-coverage` as it imports the rest of
    the specification.
- **The rule that once required it.** None beyond L19's placement (C184
  put the table under `include/`; it did not choose the generator).
- **Readers.**
  - The table: `foreign/idr/lib/Transforms/Expect/Lookup.cpp` and the
    contracts.
  - The records: `tests/expect-coverage`.
- **The deletion.** About 28 lines: `tests/expect-table-current/` (23),
  the `--expect-table` mode and its usage line (3), and zones' exception
  (2). `Properties.idr` (351 lines) moves; it is not deleted.
- **Verdict.** MERGE into the specification's generator. *Read.*
- **Owner.** L19, and L03 (`compiler/spec/IdrisMLIR/Spec/Generator/`).
  Waits on L03's generator. `Pipeline/Pipeline.idr` and the
  `Generated/` outputs are modified by others now.
  `audits/p0/cull/pipeline.md` §3 and `verifiers.md` touch rows of the
  same table; they land first or together.

### 14. The runner's `--rules` and `--rule-category`: modes with no reader

- **The part.**
  - In `harness/Facts.idr`: `ruleLines` (`:161-168`) and
    `categoryOfPhrase` (`:177-181`).
  - Their dispatch in `harness/Main.idr` (`:520`, `:523`, and the usage
    at `:74` and `:380`).
  - Their shell wrappers in `harness/lib/harness.sh:174` (`rules_lines`)
    and `:176` (`rule_category`).
- **The fact it supplies.** Every rule's phrase with its category, and
  one rule's category. `--rule-phrases` (which stays) answers what is
  asked.
- **Readers.** None. `rules_lines` and `rule_category` are called by no
  test (the function count above, 0 callers each). `tests/rules-covered`
  calls `rule_phrases` (`run:23`). Its comments and one `say` line
  (`run:9, 25`; `without-fixture:3`) still name `runtests --rules`, which
  it no longer calls. *Measured.*
- **The deletion.** About 18 lines. `rules-covered`'s three mentions are
  corrected to `--rule-phrases`.
- **Verdict.** DELETE. *Measured.*
- **Owner.** L19. Clean; waits on nothing.

### 15. `tests/determinism-threads-rbtree`: rbtree's thread check, held twice

- **The part.** `tests/determinism-threads-rbtree/` (12 lines of `run`,
  5 of `expected`). It runs `bench/rbtree`'s module through the pipeline
  on one thread and on the pool, and compares the module, the
  statistics and the remarks.
- **Where the fact is held.**
  - The module's sameness on rbtree across thread counts is
    `tests/determinism-rbtree`'s (Determinism.idr, six compilations
    including the pool).
  - The statistics and remarks under the pool are
    `tests/determinism-threads-linarray-lanes`', on an input whose
    remarks are not empty (its `run:13-18`). The remarks on rbtree are
    empty, and the rbtree test does not say so.
- **The rule that once required it.** Determinism under threads, which
  holds through the two tests above.
- **Readers.** The runner. `audits/p0/cull/pipeline.md` §3 cites its
  `expected:4` beside linarray-lanes' as the tests that compare
  statistics. Linarray-lanes' check remains.
- **The deletion.** The directory (17).
- **Verdict.** DELETE. *Read.*
- **Owner.** L19. Clean; waits on nothing.

## 2. Bugs found on the way (no deletion; each needs a fix)

- **`tests/bench-smoke` fails at HEAD.**
  - Five benchmarks have no recorded smoke input: json-bytes, json-comb,
    json-hand, json-linear and json-lines, all added in b29b6239
    (2026-10-21).
  - `Bench.idr:30-35` reports each one as "<name>: no recorded input and
    output in bench-smoke". That line is in no `expected`
    (`tests/bench-smoke/expected` has no `json`).
  - *Measured*: a loop over `bench/*/Main.idr` against
    `tests/bench-smoke/<name>.{in,out}` prints exactly those five.
  - Fix: give each its `.in`/`.out` (L19). The parser workloads are the
    owner's case (memory: parser combinators), so they stay.
- **`tests/rules-covered/run:9, 25` and `without-fixture:3`** name
  `runtests --rules`, which the test does not call (candidate 14).
- **`CMakePresets.json:25`**: the release preset's display name says "no
  sanitizer traps". No CMake list of ours names a sanitizer
  (`grep -i sanitiz` over the root, `foreign/idr` and `runtime`
  CMakeLists: 0). The text describes a build that is gone.
- **`tools/toolchain.sh:3-6`** lists `tools/bisect.sh` and
  `tools/upstream-idris/as-idris` among the files that source it. That
  list goes with candidates 2 and 5.

## 3. Kept, with the rule and the fact only each supplies

Each of these was questioned and survives.

| part | rule | unique fact |
| --- | --- | --- |
| the typecheck build: `IDRIS_MLIR_TYPECHECK` (`CMakeLists.txt:68`), the `typecheck` preset, `make typecheck*` | D120 | the C++ checked on a host that builds no LLVM. It is no knob of what a compiled program does: nothing it compiles runs (`:420-432`) |
| CMake cache variables `IDRIS_MLIR_TOOL_STACK_BYTES` and the two others (`CMakeLists.txt:216-223`) | AGENTS.md "every size is the program's or the host's"; D35-D38 | the tools' stacks, measured per target, refused until given |
| `IDRIS_MLIR_IDRIS_PREFIX` (`foreign/idr/CMakeLists.txt:126`) | AGENTS.md (idris-mlir reads no environment) | the prefix idris-mlir records |
| presets `dev`, `release`, `lint` | AGENTS.md (assertions on, clang-tidy of stage 2: `tests/mlir-layout`) | the build types. They differ in optimization, not in meaning (NDEBUG is stripped from both, `foreign/idr/CMakeLists.txt:36-45`) |
| `harness/` search oracles: Fuzz, FuzzRun, Gen, Lazy, Linear, Prims, Sem, Scale, ScaleRun, Universal, Determinism, Covers, RuntimeEffects | testing-by-search; AGENTS.md "there is no oracle" (only our own models) | each is the only model, generator or relation for its property. No harness module has a dead top-level name (scan above) |
| the runtime property tests (`runtime-*`, `big-cell`, `io-buffer`, `heap-region`) | AGENTS.md (a primitive's meaning is `runtime/`'s) | models (`harness/prop/*model.h`) against the runtime |
| the check suite's rule tests: no-fuel, no-behaviour-options, spec-current, spec-self, emit-dialects, registry-only, no-erased-inputs, no-primitive-semantics, verifier-every-pass, upstream-patches, pin-sites, licenses, static-linking, timeouts, idris-environment, no-environment | each names its AGENTS.md rule in its header | the rule's check, with planted witnesses (Planted.idr) |
| `no-local-headers` | C184 ("The rule stands as written") | where a header may be included from. Its "no header beside a .cpp" finding is also `zones`' (`zones/run:6-9`): one of the two should hold it (simplification, not counted) |
| `zones`, `mlir-layout`, `driver-shape`, `language-profile`, `dialect-text` | AGENTS.md (upstream's layout, one command line, the profile, tests never check module text); C53 (no C++ modules) | each the only check of its rule |
| `rules-covered`, `prelude-coverage`, `expect-coverage` | AGENTS.md (every refusal's rule; programs over the prelude; a property a test states) | ratchets that only shrink |
| `ccache-shared`, the ccache launcher | C53 (ccache sloppiness) | one checkout's compile is another's hit, and agent worktrees are other checkouts |
| `tests/upstream-*`, `tests/checker-*` | AGENTS.md (each carried patch has `tests/upstream-<bug>`); D121; D116 (two hosts) | each patch's reproducer on each host. Their fate follows their patch, which is the upstream audit's question |
| `bench/` (other benchmarks), `bench/run.sh`, `bench/report.sh`, `tests/bench-report`, `tests/bench-smoke` | the corpus measured claims rest on (C152, workloads.md); the parser workloads (memory) | performance and clang agreement. `fasta-redux` stays: same output as `fasta`, but a different program, at 0.27x of clang against fasta's 0.43x in the 2026-10-13 record (*measured*, `results.md:22-23`) |
| `bench/records/` | C251; the user's request | the grounds of cited measurements |
| `tools/bootstrap.sh`, `verify-pins.sh`, `patches.sh`, `toolchain.sh`, `host.sh`, `compile.sh`, `dialects.sh`, `licenses.sh`, `policies.txt`, `self.sh` | AGENTS.md (one recipe, pins, licences, size policies); D116 (self-host) | each has callers (`git grep`, counts above) and holds its fact once |
| `tools/doctor.sh`, `make doctor`, `tests/doctor-without-idris-source` | none strong; kept | the one list of what the host must provide (git, make, cc, python3, m4, coreutils). Every pin check in it delegates to verify-pins. Weak; a candidate if the owner wants fewer commands |
| `make env` | `tests/idris-environment` | the environment the commands run in |

## 4. Table

| # | candidate | verdict | lines deleted | owner | waits on |
| --- | --- | --- | ---: | --- | --- |
| 1 | `tests/file-size` | DELETE (read, measured) | 3,390 | L19 | nothing |
| 2 | `tools/upstream-idris` (+ toolchain.sh, Makefile comment) | DELETE (read) | 522 | L06, INT (L16: `--check`) | nothing; the `export` line, one suite run |
| 3 | `tools/compile-times.sh` + `Harness.idr` timing record | DELETE (conjecture) | 477 | L06, L19 | the owner's view on measurement tools |
| 4 | `bench/regex-dna` + its smoke files | DELETE (conjecture) | 703 | L19 | nothing |
| 5 | `tools/bisect.sh` | DELETE (conjecture) | 198 | L06 | nothing |
| 6 | the CMake configure gate, lock `accept`, `configure-gate`, Lock.idr series | MERGE into verify-pins (conjecture) | 180 | INT, L06, L19 | the owner (cpp-starter profile) |
| 7 | `tests/build-preset`, `tests/commands` | DELETE (conjecture) | 180 | L19 | nothing |
| 8 | `tools/lanes` | DELETE (read) | 116 | L06 | the coordinator, for the "main only" line |
| 9 | Trace.idr `--trace-totals`/`--trace-units` | DELETE (measured) | 65 | L19 | nothing |
| 10 | `harness/templates` | DELETE (read) | 52 | L19 | nothing |
| 11 | `tests/scale-threads` | MERGE into Determinism (conjecture) | 46 | L19 | nothing |
| 12 | `tests/bench-records` | DELETE (read) | 28 | L19 | nothing |
| 13 | `expect-table-current`, `--expect-table` | MERGE into specgen (read) | 28 | L19, L03 | L03's generator; the Generated/ edits in flight |
| 14 | `--rules`, `--rule-category` and wrappers | DELETE (measured) | 18 | L19 | nothing |
| 15 | `tests/determinism-threads-rbtree` | DELETE (read) | 17 | L19 | nothing |

The candidates are ranked by how much they delete. Rows 4 to 6 sit out
of order by size because their counts include smoke inputs (row 4) or are
estimates (row 6).

**Total removed by the DELETE and MERGE verdicts: about 6,020 lines.**
- *Read* or *measured*: rows 1, 2, 8, 9, 10, 12, 13, 14 and 15, 4,236
  lines.
- *Conjecture*: rows 3 to 7 and 11, about 1,784 lines.
- Not counted:
  - the chained frontend `--check` task (L16, about 10 lines);
  - the `export IDRIS2_PREFIX` line;
  - `Properties.idr`'s 351 lines, which move rather than go.

HEAD at start `d378e120`; at finish `45599c62`.
