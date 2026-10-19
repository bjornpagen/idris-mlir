<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# The test harness

`tests/` holds the tests and nothing else: every test is one directory,
`tests/<name>/`, all at that one level, named in words joined by dashes.
This directory holds what runs them.

Run from the repository root: `make check` (the repository's rules, no
build), `make test` (the compiler on programs, and what it builds), `make
test-idr` (the `idr` dialect), `make test-mlir-tools` (the upstream bugs
still reproduce), `make test-unit` (the googletest boxes of
`foreign/idr/unittests`, once `make build` has built them). `only=NAME`
runs the tests whose name contains NAME, `except=NAME` leaves them out,
`threads=N` runs N at once, each compilation getting `NCPU / N` of the
CPU budget. A run ends with how many of the selected tests passed, the
tests not run on this host, and the tests that failed or gave no verdict;
it fails if any did.

## What a test is

A test's kind is what its directory holds (`kindOf`, Main.idr):

- a `run` script: a scripted test. It runs with the compiler as `$1`,
  sources `testutils.sh`, prints one line per check, and its stdout must
  be its `expected`.
- a `Main.idr` and no `run`: a compiled program (`kinds/program`,
  `e2e_io` in `lib/e2e.sh`). It is compiled once with its dumps and
  checked as every compilation is (the dumps, quantities kept, the
  object's imports, live cells), then run once per case of its `cases`
  (below); with no `cases` it is compiled only (a program that never
  ends). `mlir.expect` states properties of its module (idr-expect);
  `packages`, `heap-free` and `covers` are marks of the
  compilation (`testutils.sh`). Its `expected` is the transcript of a good
  run, which says `cases: each as expected` whatever the number of cases.
- a `Main.idr` whose first line is `-- expect: <rule>, line <n>`: a
  program refused by that one rule at that line (`kinds/reject`,
  `profile_reject`), optionally with `-- message: <text>` next; its name
  starts with the rule. It may hold its nearest accepted neighbour in
  `near/` (below).
- one `.mlir` file, `<name>.mlir`, and nothing else: a dialect fixture
  (`kinds/fixture`, `lit_fixture` in `lib/lit.sh`). Its `// RUN:` lines
  run in order and every one must hold; a command that is to fail names
  the failure it expects. A module of it is one `idr.program`, which
  names its root and its stage. `%differential` (below,
  `lib/differential.sh`) is the oracle for what a pass's output means.

## The vocabulary: one way of saying each thing

**Cases.** A program's cases are `cases/<case>/`, one directory per run,
named in letters, digits and dashes, each one record of its run; the
runs go in the order of the names. Its files (`case_fields`, `e2e_case`
in `lib/e2e.sh`):

| file | what it says; when absent |
| --- | --- |
| `stdin` | the bytes on standard input; none |
| `expected-stdout` | the bytes on standard output, exactly; none |
| `expected-exit` | the exit status (first word); 0 |
| `expected-crash` | the cause the runtime names: stderr is exactly `idris-mlir: <cause>` and the status 1; without it stderr is empty |
| `libm-lines` | stdout's line numbers that hold libm results, compared to a few ulp |

A case with any other file, a crash beside an exit status, or a `cases`
with no case stops the test before it compiles, naming the fault. A
program that reads nothing is one case with no `stdin`. To add an input,
add a directory: no transcript changes. A script that builds a program
in its work directory gives it `cases/` the same way.

**The differential.** `%differential BEFORE AFTER`, on a fixture's RUN
line, compiles the modules BEFORE and AFTER, each from the stage its
program is at (the rest of idris-mlir's pipeline after the step that makes
that stage, read from the registered pipeline and `IdrPassStages.txt`),
runs both on every input and fails unless both exit alike and print the
same stdout on each; it names the first input that differs and both
outcomes, on stderr. The inputs are the empty one and every one-byte one,
0x00 to 0xff (getChar reads the end of input as 0xff), unless the fixture
declares its own, one per `// STDIN: <text>` line, `<text>` read with
printf's `%b` escapes (`\n`, `\\`, `\0NNN`). Every run is also held to
what every run of a program is: one that returns from main leaves no cell
live (`idris-rt: live cells 0`), or the module whose run leaked is named
with the input. Translation validation of a pass is two lines:

    // RUN: idris-mlir-opt %s --idr-defunctionalize -o %t.mlir
    // RUN: %differential %s %t.mlir

`tests/differential-wrong-rewrite` and `tests/differential-declared-stdin`
show it failing on a wrong rewrite (`not %differential ... 2>&1 |
FileCheck %s`), and `tests/rc-live` on a release taken out.

**A refused program's neighbour.** A refused test may hold `near/`, the
accepted program nearest to it: the same program with the one construct
the rule refuses changed, as a program test's files (`Main.idr`, its
modules, `cases/`, marks), with no header and none of a test's own files.
It must compile and give what its cases say, so the rule is pinned from
both sides (`near_neighbour`). Its transcript lines follow the refusal's,
each prefixed `near: `.

**Planted witnesses.** A repository rule (a `check` script) writes its
check as a shell function of a tree's root that prints one finding per
line, `path:line: what` with the path from that root, and runs `planted
CHECK` (`lib/planted.sh`) beside its run over `$root`. The test holds
`witness/`, files laid out as in the repository that break the rule, one
per way of breaking it, each of which a finding must name; and
`near-miss/`, files as close as the rule allows, which must give none.
A check that walks the whole repository leaves out every test's
`witness/` and `near-miss/`; a planted file carries the licence line its
kind needs. `tests/harness-planted` shows the form failing a check that
finds too little or too much.

A fixture is in `test-idr` and every other test in `test`, unless a
`suite` file names another suite (`check`, `test-mlir-tools`). A
`targets` file runs a test only on the hosts it names (`x86-64`,
`aarch64`, `linux`, `macos`), and `expected.<host>` is the expectation
on that host in place of `expected`. `tests/semantics` runs once per
entry of Sem.idr's table, as `semantics@<name>`.

A test's expected files are its specification, reviewed when they
change; no other implementation is asked. Tests check behaviour, never
clone numbers, function order or SSA names.

## Here

- `Main.idr`, `Runner.idr`: the runner (`harness.ipkg`), which every test
  command builds; `one.sh` runs one test in a process of its own and
  writes its output to `build/output/<name>`.
- `testutils.sh` and `lib/`: what the scripts share, one file per concern.
- `kinds/`: the script of each kind of test that has no `run` of its own.
- `prop/`: the headers and the build of the runtime's property programs.
- `Fuzz.idr`, `Gen.idr`, `Prims.idr`, `Sem.idr`, `TwoLevels.idr`,
  `Lock.idr`: what the runner computes for tests that ask it.
- `templates/`: a minimal test of each kind to copy.

## Adding a test

Copy the template of its kind to `tests/<name>/`, write it, and run it
with `make test only=<name>` (or the suite it is in). With no `expected`
a test fails and prints its whole output: read it, and when every line is
what the contract says, copy it to `expected`. The `harness-*` tests are
the vocabulary's own: each shows a form above failing where it must.
