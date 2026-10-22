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
runs the tests whose name contains NAME, `except=NAME` leaves them out;
NCPU of them run at once (the CPU budget), each compilation on one
thread. A run ends with how many of the selected tests passed, the
tests not run on this host, and the tests that failed or gave no verdict;
it fails if any did.

## What a test is

A test's kind is what its directory holds (`kindOf`, Main.idr):

- a `run` script: a scripted test. It runs with the compiler as `$1`,
  sources `testutils.sh`, prints one line per check, and its stdout must
  be its `expected`.
- a `Main.idr` and no `run`: a compiled program (`kinds/program`,
  `e2e_io` in `lib/e2e.sh`). It is compiled once, linked with the checked
  runtime, with every pass's contracts and the promises every compiled
  program keeps checked as it runs (`--idr-contracts`) and the properties
  its `mlir.expect` states of each stage checked after every pass of that
  stage (`--idr-expect-at`, `lib/expect.sh`); it is checked as every
  compilation is (the object's imports; compiled again from its emitted
  module with a drawn set of the optimizations' actions skipped, it ends
  every case as before, `lib/actions.sh`), then run once per case of its
  `cases` (below); with no `cases` it is compiled only (a program that
  never ends). `packages`, `heap-free` and `covers` are marks of the
  compilation (`testutils.sh`). Its `expected` is the transcript of a good
  run, which says `cases: each as expected` whatever the number of cases.
- a `Main.idr` whose first line is `-- expect: <rule>, line <n>`: a
  program refused by that one rule at that line (`kinds/reject`,
  `profile_reject`), optionally with `-- message: <text>` next; the
  header holds the rule, so its name is free. It may hold its nearest
  accepted neighbour in `near/` (below).
- one `.mlir` file, `<name>.mlir`, and nothing else: a dialect fixture
  (`kinds/fixture`, `lit_fixture` in `lib/lit.sh`), for an IR shape a
  pass must handle that no program reaches. Its `// RUN:` lines run in
  order and every one must hold; a command that is to fail names the
  failure it expects. No RUN line names a pass: a stage slice
  (`--idr-pipeline="from=<stage> to=<stage>"`), a property
  (`--idr-expect=holds=...`) or `%differential` (below, the oracle for
  what the pipeline's output means).

## The vocabulary: one way of saying each thing

**Cases.** A program's cases are `cases/<case>/`, one directory per run,
named in letters, digits and dashes, each one record of its run; the
runs go in the order of the names. Its files (`case_fields`, `e2e_case`
in `lib/e2e.sh`):

| file | what it says; when absent |
| --- | --- |
| `stdin` | the bytes on standard input; none |
| `expected-stdout` | the bytes on standard output, exactly; none |
| `expected-ending` | how the run ends, the specification's ending (`Facts.idr`): `returned`, `exited <n>`, `crashed <cause>`, `crashed said`, `crashed unreportable`, `out_of_memory`, `cannot_run <reason>`, `broken_pipe`, `internal_error <what>`; `returned` |
| `expected-stderr` | the bytes on standard error, the runtime's `prog: fatal: ...` line for the ending among them; none |
| `libm-lines` | stdout's line numbers that hold libm results, compared to a few ulp |

A case with any other file, or a `cases` with no case, stops the test
before it compiles, naming the fault; an ending that is none fails its
case. The status a run must end with is the runner's to compute from the
ending, from the specification's table, never spelled in a test but in
`tests/endings`, the one test of the table against the promise. A
program that reads nothing is one case with no `stdin`. To add an input,
add a directory: no transcript changes. A script that builds a program
in its work directory gives it `cases/` the same way.

**The differential.** `%differential BEFORE AFTER`, on a fixture's RUN
line, compiles the modules BEFORE and AFTER, each from the stage its
program is at (the registered pipeline from there, which the tool reads
off the program), BEFORE with every optimization's actions skipped so the
reference shares no optimization with what it checks, both linked with
the checked runtime; it runs both on every input and fails unless both end
alike (the same status, stdout and stderr) on each; it names the first
input that differs and both outcomes, on stderr. The inputs are the empty one and every one-byte one,
0x00 to 0xff (getChar reads the end of input as 0xff), unless the fixture
declares its own, one per `// STDIN: <text>` line, `<text>` read with
printf's `%b` escapes (`\n`, `\\`, `\0NNN`). A run that leaks a cell ends as the checked runtime's internal error,
which differs from a clean return. Translation validation of a stage is
two lines:

    // RUN: idris-mlir-opt %s --idr-pipeline=to=first -o %t.mlir
    // RUN: %differential %s %t.mlir

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
entry of Sem.idr's table, as `semantics@<name>`, each entry twice: its
operands written in the program, where they fold, and read from stdin,
where they reach the code the program is compiled to; each pair its
builtin's guard stops is a case of its own of the second, which must
crash by the guard's cause.

A test's expected files are its specification, reviewed when they
change; no other implementation is asked. Tests check behaviour, never
clone numbers, function order or SSA names.

## Here

- `Main.idr`, `Runner.idr`: the runner (`harness.ipkg`), which every test
  command builds, under either host: it depends on base and the dialect's
  specification alone and creates no process. `runs.sh` makes the runs
  between the runner's plan and its tally; `one.sh` runs one test in a
  process of its own and writes its output to `build/output/<name>`.
- `Facts.idr`: what the harness reads of the specification (endings,
  rules); `Case.idr`, `Reject.idr`: a case's ending and a refused
  program's header, each read once into its record; `Trace.idr`: time
  traces summed; `Json.idr`, `Files.idr`: what they read.
- `testutils.sh` and `lib/`: what the scripts share, one file per concern;
  `lib/spec.sh`, the specification's generated files as the spec tests
  read them, and `lib/scale.sh`, a scale fixture compiled at two sizes and
  held to its relation, are sourced by their tests alone.
- `kinds/`: the script of each kind of test that has no `run` of its own.
- `prop/`: the headers and the build of the runtime's property programs,
  and the program a runtime C test runs as, through the runtime's start.
- `Fuzz.idr`, `Gen.idr`, `Lazy.idr`, `Linear.idr`, `Prims.idr`, `Sem.idr`,
  `Scale.idr`, `Properties.idr`, `RuntimeEffects.idr`, `Lock.idr`: what the runner computes for tests that ask it; `Linear.idr`
  generates linear programs, each with its de-linearized twin and the
  verdict the in-place rule predicts for it; `Scale.idr` the scale
  fixtures, the dialect's text spelled from the specification;
  `Properties.idr` idr-expect's properties, one record each, from which
  its C++ table is printed; `RuntimeEffects.idr` what each op that calls
  the runtime declares, against which its runtime function is read.
- `templates/`: a minimal test of each kind to copy.

## Adding a test

Copy the template of its kind to `tests/<name>/`, write it, and run it
with `make test only=<name>` (or the suite it is in). With no `expected`
a test fails and prints its whole output: read it, and when every line is
what the contract says, copy it to `expected`. The `harness-*` tests are
the vocabulary's own: each shows a form above failing where it must.
