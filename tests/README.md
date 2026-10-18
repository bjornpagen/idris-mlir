<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Tests

Run from the repository root: `make check` (the repository's rules, no
build), `make test` (the compiler on programs), `make test-idr` (the `idr`
dialect, with FileCheck), `make test-mlir-tools` (the upstream bugs still
reproduce). `make test only=NAME` runs the tests whose path contains NAME:
`only=programs/basic` a topic, `only=programs/basic/hello` one test,
`only=reject` the rejections; `except=` leaves tests out; `threads=N` and
`INTERACTIVE=--interactive` (accept new output) as in upstream Idris.

A test is a directory with a POSIX-sh `run` script and an `expected` file:
the runner (Main.idr, Runner.idr) calls `run` with the compiler under test
and compares its stdout with `expected`. `run` prints one line per check
(the exit status, the artifacts, the output against the expected files,
and one line, `universal: holds`, for what holds of every compilation),
so a failure shows as a difference and `expected` is the transcript of a
good run. `testutils.sh` holds what the scripts share and lists the marks
a fixture may carry.

A test's expected files are its specification: what a program must print
and how it must exit is written down beside it and reviewed when it
changes, as any golden test's. No other implementation is asked.

## Layout

- `spec/`: the repository: pins, commands, source rules (`make check`).
- `programs/<topic>/<name>/`: end-to-end programs, each compiled once,
  with the module after every top-level pass dumped by upstream's IR tree
  printer, and run against its expected output; one topic directory per
  subject (`semantics`, `basic`, `io`, `prelude`, `interfaces`, `eval`,
  `partial`, `stack`, `nat`, `data`, `linear`, `arrays`), one pool each in
  Main.idr. `programs/semantics/prim/` is one test per entry of Sem.idr's
  table, `Sem.names`, which the runner runs as
  `programs/semantics/prim@<name>`, giving its `run` the name; the program
  and the values it must print are computed from what each primitive
  means. A fixture whose program is a benchmark's builds it from
  `bench/<name>` (its `Main.idr`, and its `packages` where it has one)
  beside the fixture's own input and expected files.
- `accept/<name>/`: programs the profile compiles; an `expected-stdout`
  or `expected-exit` beside one also runs it.
- `reject/<name>/`: programs rejected with one `unsupported (<rule>)` on
  the line the header `-- expect: <rule>, line N` names, and, under a
  second header `-- message: <text>`, a refusal that holds that text; the
  name starts with the rule, one of the rules the build's generated list
  names (`lib/rules.sh`). A `packages` file beside a fixture of either
  kind names the packages it compiles with. A rule with no fixture has a
  line of `reject/without-fixture` saying why (`spec/rules-covered`).
- `compiler/`, `registry/`, `determinism/`, `toolchain/`, `fuzz/`,
  `two-levels/`, `bench/`: the other pools of `make test`, named for what
  they check; `toolchain/lib/` holds the helpers the runtime's property
  tests source, and is no test.
- `idr/<pass>/`: the dialect suite, one directory per pass or concern; a
  test is `name.mlir` with its `RUN:` lines beside `name/run`. A module of
  it is one `idr.program`, which names its root and its stage (`higher`
  before defunctionalization, `first` after it, `owned` after counting,
  `lowered` after lowering), and a property of it is stated with
  idr-expect, FileCheck kept for printed syntax, under `asm/`, `syntax/`
  and `verify/`, for the attributes LLVM reads (`lower/llvm-facts.mlir`),
  and for text the runtime or a pass prints as diagnostics
  (`spec/dialect-text`).
- `upstream/`: the reproducers of the bugs recorded in `../upstream/`.
- `lib/`: the helpers `testutils.sh` sources, one file per concern;
  `runner/`: `one.sh`, which runs one test for the runner (Runner.idr) in
  a process of its own and compares its output with its expectation;
  `templates/`: a minimal test of each kind to copy.
- In any test's directory, `expected.<name>` is the expectation on a host
  of that name (its architecture, `x86-64` or `aarch64`, or its operating
  system, `linux` or `macos`) in place of `expected`, for a test whose
  output is the target's own; and a `targets` file runs the test only on
  the hosts whose names it lists.

## Adding a test

Copy the template of its kind into the topic it belongs to, give it a
descriptive name (words joined by dashes, no numbers), write the program,
and run it once with `INTERACTIVE=--interactive` to accept its transcript
as `expected`; read the transcript before accepting it. A program test
also carries `expected-stdout`, and `stdin`, `expected-exit`,
`expected-crash` or `packages` as it needs. Tests check behaviour, never
clone numbers, function order or SSA names; a property of the compiled
module is stated in `mlir.expect` (idr-expect) rather than by matching ops,
at a top-level pass of the pipeline (`idr-optimize`, `idr-rc`, ...), whose
module the tree printer dumps; a pass nested in a group over functions
dumps one function at a time and is no step. A function a property is
stated of is named by its Idris definition, which names every copy made of
it, never by a generated name.
