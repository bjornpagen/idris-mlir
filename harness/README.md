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
  checked as every compilation is; with an `expected-stdout`,
  `expected-exit` or `expected-crash` it is also run against them, on its
  `stdin`. `mlir.expect` states properties of its module (idr-expect), and
  its marks are listed in `testutils.sh`. Its `expected` is the transcript
  of a good run.
- a `Main.idr` whose first line is `-- expect: <rule>, line <n>`: a
  program refused by that one rule at that line (`kinds/reject`,
  `profile_reject`), optionally with `-- message: <text>` next; its name
  starts with the rule.
- one `.mlir` file, `<name>.mlir`, and nothing else: a dialect fixture
  (`kinds/fixture`, `lit_fixture` in `lib/lit.sh`). Its `// RUN:` lines
  run in order and every one must hold; a command that is to fail names
  the failure it expects. A module of it is one `idr.program`, which
  names its root and its stage.

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
what the contract says, copy it to `expected`.
