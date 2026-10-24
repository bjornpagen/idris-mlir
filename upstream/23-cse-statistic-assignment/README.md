<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] CSE's pass statistics depend on thread scheduling

On llvm main at 7208ba24 (the pin then) and at 416f328b (the pin since 2026-10-21, where the pull request still applies), the CSE pass's `num-cse'd` and
`num-dce'd` statistics in a nested pipeline are whatever its last run on
one operation assigned, so the reported total is the count of the last
function each clone ran on: under one thread, the module's last
function; under the pool, the sum over clones of each clone's last
function. The IR is the same either way; only the statistics differ, so
`tests/determinism-threads-*`, which compare the statistics of one
module through the pipeline under one thread and under many, fail on an
unpatched mlir-opt wherever CSE runs nested (ours runs it in
idr-simplify's and idr-pipeline's canonicalize step).

Not reported upstream yet (2026-10-13).

## Reproduce

`cse.mlir`: three functions, one operation CSE'd in `@f`, two in `@g`,
none in `@h`.

```
$ mlir-opt cse.mlir -pass-pipeline='builtin.module(func.func(cse))' \
    -mlir-pass-statistics -mlir-pass-statistics-display=list -o /dev/null
  CSEPass
    (S) 3 num-cse'd - Number of operations CSE'd

$ mlir-opt cse.mlir -pass-pipeline='builtin.module(func.func(cse))' \
    -mlir-pass-statistics -mlir-pass-statistics-display=list \
    -mlir-disable-threading -o /dev/null
  CSEPass
    (S) 0 num-cse'd - Number of operations CSE'd
```

Three operations are CSE'd in both runs; the outputs are byte-identical.

## Expected

3 under both, and in general the sum over every operation the pass ran
on, whichever thread ran it.

## Cause

`CSE::runOnOperation` (`mlir/lib/Transforms/CSE.cpp:46-47`) assigns the
run's counts (`numCSE = cseCount`) instead of accumulating them. A
nested pass's statistics are merged from its clones by summing each
clone's statistic, so the report sums one assignment per clone: the
count of the last operation that clone ran on. With threading disabled
there is one clone, and the report is the last operation's count.

`ControlFlowSink::runOnOperation`
(`mlir/lib/Transforms/ControlFlowSink.cpp:44`) assigns the same way,
once per region-branch operation it walks; the report did not name it
here, and the patch does not touch it.

## Why there is no patch

There is no `llvm.patch`, and there is no `PINS.md` entry. The compiler
met this bug through upstream's `cse`, nested in the optimizer's
per-function pipeline and in the pipeline's cleans. The cutover deletes
every run of it (proposals/0000 D98, D100): at the points that hold our
ops the e-graph pass takes its place, and at the points that hold
upstream's ops only nothing runs. Nothing in the tree runs `cse`, so
nothing reaches the bug. The report stays a submission, with the pull
request as `pull-request.diff`, which the bootstrap does not apply.

## The fix

`pull-request.diff`, a `git diff` against 7208ba24: CSE accumulates
(`numCSE += cseCount`, `numDCE += dceCount`), and a new test,
`mlir/test/Transforms/cse-statistics.mlir`, checks the accumulated
total under one thread and under many.

## Upstreaming plan

Status: not sent; `pull-request.diff` applies to main at 7a83be39.
Send as one pull request to llvm/llvm-project,
`[mlir] Accumulate CSE pass statistics over nested runs`, with
`pull-request.diff` as its diff and the texts in `submission.md`. No issue is
needed: the reproducer is three functions. Mention ControlFlowSink's
same assignment in the pull request body and follow its reviewers on
whether to fix it in the same change. The report goes when the pin
moves past a fix its test passes with.
