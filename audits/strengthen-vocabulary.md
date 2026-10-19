<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Strengthening the suite: the vocabulary lane (the harness)

## What was built, one way each

All four forms are documented, short, in `harness/README.md` ("The
vocabulary: one way of saying each thing"), which the ten lanes after this
one read. Each has a test of its own that shows it failing where it must
(the `harness-*` tests and the two `differential-*` fixtures).

1. **Multi-case programs** (`harness/lib/e2e.sh`: `e2e_io`, `cases_known`,
   `e2e_cases`, `e2e_case`, `case_fields`).
   - Representation: `cases/<case>/`, one directory per run, the one record
     of it; its fields are files named as the old single-run files were
     (`stdin`, `expected-stdout`, `expected-exit`, `expected-crash`, and
     the per-run marks `constant-stack`, `live-cells`, `libm-lines`).
     Directories, not a cases file, because stdins hold NUL, CR, ill-formed
     UTF-8 and no final newline (file-bytes-echo, prelude-getline,
     getline-ill-formed, 60 stdins without a final newline): a directory
     is byte-exact with no escaping, and the field names are the ones
     `tools/licenses.sh` already excludes. Absent fields mean: no stdin,
     empty stdout, exit 0, empty stderr.
   - Parse at the boundary: `cases_known` refuses, before anything
     compiles, a file no field names, a case that is no directory, a name
     outside letters/digits/dashes, an `expected-exit` beside an
     `expected-crash`, and a `cases` with no case. So no case can pass
     unread, and the transcript need not count cases.
   - The universal checks (dumps verify, quantities kept, the object's
     imports, heap-free, mlir.expect, covers) run once per compilation;
     the executable runs once per case.
   - Transcript: the three run lines (`run:`, `stdout:`, `stderr:`) are
     one line, `cases: each as expected`, the same whatever the number of
     cases, so adding an input changes no `expected`. A failing case is
     named with what differs (`case <name>: exit 3, expected 0`, `stdout
     differs` with the diff, `stderr is not the crash expected-crash
     names`, `stderr not empty`).
   - A crash is now checked exactly: stderr must be `idris-mlir: <cause>`
     and nothing else, the runtime's documented crash format
     (`runtime/Io/Ending.cpp`), where before it was a substring search
     (`grep -F`), which also passed a stderr with extra lines or a cause
     that only began like the expected one.
   - Test-level marks are now only those of the compilation: `packages`,
     `heap-free`, `covers`, `default-stack`. `fixture_files_known` refuses
     a top-level `stdin` or `expected-*` (the old form), naming it.
   - `copy_fixture` no longer copies `cases/` or `near/` into the build.
   - `sem_case` writes its fixture's one case as `cases/no-input/`.
   - Fixed in passing (harness, mine): `stdout_within_a_few_ulp` used awk's
     `NR == FNR`, which is true for the second file when the first is
     empty, so a libm case with an empty expected-stdout would have
     compared nothing; it now tests `FILENAME == ARGV[1]`.

2. **The meaning oracle for fixtures**, `%differential BEFORE AFTER`
   (`harness/lib/differential.sh`, substituted in `lib/lit.sh`).
   - Form: two modules, not `%differential PIPELINE`, so that the module a
     fixture already writes with `idris-mlir-opt %s <pass> -o %t.mlir` is
     the one validated, and a hand rewrite (a planted mutant) is compared
     the same way. Translation validation of a pass is the existing line
     plus `// RUN: %differential %s %t.mlir`.
   - Each module is compiled from the stage its program is at: idris-mlir
     only accepts `higher` modules or LLVM-dialect ones, so the harness
     runs, by idris-mlir-opt, the rest of idris-mlir's own pipeline after
     the step that makes that stage, then hands the lowered module to
     idris-mlir and links it as `%cc` does. The rest of the pipeline is
     read, not written down: from the registered pipeline as
     `--dump-pass-pipeline` prints it, cut after the pass whose `sets` is
     the stage and whose `requires` is not (`IdrPassStages.txt`), keeping
     `idr-target`, and dropping nests left empty. So it follows the
     pipeline and the passes' stages when they change. Tested at `higher`,
     `first` (after idr-defunctionalize) and `owned` (after idr-rc).
   - Inputs: the empty input, then every one-byte input 0x00..0xff, or the
     fixture's own, one per `// STDIN: <text>` line (`printf %b` escapes).
     Both programs run every input under one bound; the first input on
     which exit status or stdout differ is named on stderr with both
     outcomes. Each fixture costs about two compiles and 514 runs, a few
     seconds.
   - Negative fixtures in the suite (test-idr):
     - `differential-wrong-rewrite`: a closure chosen at run time; the
       differential holds after `--idr-defunctionalize` (stage first) and
       after `--idr-defunctionalize --idr-rc` (stage owned); a sed-made
       rewrite capturing 2 instead of 1 is caught, named on the byte 0x00,
       with both outputs (FileCheck on the report).
     - `differential-declared-stdin`: the declared inputs are the ones run:
       a rewrite that differs only when the second byte is a newline (which
       no one-byte input has) is caught on the declared `'7\n'`, after two
       declared inputs on which it agrees; `--canonicalize` holds.

3. **A refused program's neighbour**, `near/` (`near_neighbour`, run by
   `kinds/reject` after `profile_reject`).
   - `near/` holds a program test's files (`Main.idr`, modules, `cases/`,
     marks): the refused program with the one refused construct changed.
     It must compile and give what its cases say; its transcript lines
     follow the refusal's, prefixed `near: `. A `near/` whose Main.idr
     carries a `-- expect:` header, or that holds a test's own file
     (`run`, `expected`, `suite`, `targets`), is refused by name.
   - The reject template (`harness/templates/reject/near/`) shows it.

4. **Planted witnesses for repository rules** (`harness/lib/planted.sh`,
   `planted CHECK`).
   - A rule's check is a shell function of a tree's root printing one
     finding per line, `path:line: what`, path from that root. The test
     holds `witness/` (laid out as the repository; one file per way of
     breaking the rule; each must be named by a finding) and `near-miss/`
     (as close as the rule allows; no finding allowed). Empty trees fail.
     A check walking the whole repository must leave out every test's
     `witness/` and `near-miss/`; planted files carry the licence line
     their kind needs.
   - The script lanes apply it to the 32 `check` scripts; the existing
     inline witnesses (no-fuel's `planted.cpp`, facts-in-types'
     `Planted.td`) are the ones to move into `witness/`, and none of them
     has a near miss yet.

New tests of the vocabulary itself (each fails if its form stops failing):

| test | suite | what it shows |
| --- | --- | --- |
| `harness-cases` | test | one compile, seven cases: the three that hold are silent; a wrong stdout, a wrong exit, a wrong crash cause and a crash expected where the program exits 0 are each named; a misspelt field, a non-directory case, an exit beside a crash, and an empty `cases` stop the test before compiling |
| `harness-near` | test | a pragma refusal whose neighbour compiles; its right case is silent, its wrong case named with `near: `; a marked neighbour and one holding `expected` are refused |
| `harness-planted` | check | the right check passes; a check that finds only a line's start misses one witness; one that finds nothing misses both; one that finds every line fails the near miss |
| `differential-wrong-rewrite` | test-idr | above |
| `differential-declared-stdin` | test-idr | above |

`harness-planted` caught a bug in its own form before it landed: the
witness comparison used awk's `NR == FNR`, so a check with no findings
(an empty first file) was reported as finding everything, exactly the
check that cannot fail the form exists to stop. It reads the findings by
`getline` now.

## The program tests, converted

Every one of the 228 tests of kind program now holds `cases/`, except
`nonterminating`, compiled only (it states no run). The old top-level
`stdin`, `expected-stdout`, `expected-exit`, `expected-crash`,
`constant-stack`, `live-cells` and `libm-lines` are gone; each `expected`
has the one `cases:` line in place of the three run lines. Case names: the
stdin itself when it is one short token (`5`, `1000000`, `abcd`),
`no-input` when there is none (105), `given` otherwise (22: multi-line or
non-printing input), for the lanes to rename when they add cases.

What each checks now that it did not:
- the 12 crash tests whose cause was matched as a substring now pin the
  whole cause, site included, and that nothing else is on stderr:
  bounds-back-edge, bounds-mixed-calls, bounds-negative-index,
  bounds-negative-size, bounds-one-past, bounds-unrelated-size,
  crash-div-zero, crash-mod-zero, double-cast-nan, forever-until-crash,
  let-after-output, missing-case (each `expected-crash` gained its ` at
  <file>:<line>:<col>`, read from the run and checked to extend the old
  text). stack-exhausted's file lost the `idris-mlir: ` prefix the
  substring search needed.
- every program: a case file the harness does not read, or a stray
  top-level stdin, now fails instead of being ignored.
- No inputs were added here: the input-adding lanes own that and now need
  only a directory per input.

`tests/semantics/expected` (a script, but its program is built by the
harness's `sem_case`) was updated to the one `cases:` line, the mechanical
consequence of the new transcript; nothing else of it changed.

## Runs

| run | before | after |
| --- | --- | --- |
| `make test`, the 222 programs of suite test (threads=4) | 134 pass, 88 fail | 134 pass, 88 fail (the same 88) |
| `make test-mlir-tools`, its 6 programs | 6/6 | 6/6 |
| `make test only=semantics`, the 144 runs | not run before | 144 fail only on the transcript, fixed; `semantics@prim-bits16-add` checked |
| new: harness-cases, harness-near, harness-planted, differential-wrong-rewrite, differential-declared-stdin | | all pass |
| `make check` | | every test passes but `file-size`, which fails on eight C++ units of foreign/idr over 400 lines, none of this lane's; harness-planted and licenses pass |
| `make test-idr` (threads=2) | | 298/329; the two differential fixtures pass; the 31 failures involve no form of this lane (lit's only change is the new substitution, which no other fixture uses): actions-narrow-lanes, actions-narrow, actions-returned-arguments, canon-output-fusion, defunc-capture-field, defunc-memo-by-name, effects-io, defunc-tag-limit, fold-strings, identity, lower-big-fast-path, lower-match-lit, lower-value-buffers, narrow-descending, narrow-select-lanes, narrow-versioned, pipeline-do-block, raise-builds-actions, raise-shared-key, rc-regions-counted, rc-second-redirect, returned-threaded, structure-dynamic-cells, structure-never-returns, structure-ordered, tail-calls-decided-loops, tail-calls-positions, vectorize-rows, verify-flow, verify-roundtrip, and expect-coverage (a new `typed-reads` property with no failing fixture) |

The 88 failures are the same before and after; none comes from the
conversion. They are the known ones (audits/SUMMARY.md §5): the dump tree
printer's "File name too long" for long symbol names (buffer-ops,
sortedmap, ...), heap-free marks that allocate (double-basics,
double-cast-nan, ...), `tests-nothing`/`counts-nothing` properties, and
wrong stdout (stream-take: 34 for 55; stream-take-before;
closure-result-roundtrip; for-long-list; traverse-deep).

## What this lane breaks for other lanes, to finish

Nine scripts build a program fixture with the old top-level files and
call `e2e_io` on it; `e2e_io` now refuses those files by name
(`fixture: files no check reads: expected-stdout stdin`). Each needs its
`stdin`/`expected-stdout` moved under `cases/<name>/` (in the test and in
what the script copies) and its `expected` given the `cases:` line:
cfold, directory-listing, every-types-export (its `live-cells` too),
files-roundtrip, fuzz-two-hosts, implementation-a-hundred-definitions-deep,
rbtree, sum-of-seventy-thousand-constructors, system-info (which writes
`expected-stdout` from the host: it writes `cases/<name>/expected-stdout`
instead). They are another lane's tests, so they were not edited.

## Compiler bugs found

None new. Observed while pinning crash causes, not a bug by the runtime's
contract: a crash in a primitive is attributed to the start of the
enclosing definition (`division by zero at Prog.idr:5:1`, the `partial`
line of `divide`, whose division is on line 7), while an array bound is
attributed to an expression (`at Main.idr:25:3`). The tests pin what the
compiler names today; a lane that owns crash sites may decide whether a
definition's start is the promised site.
