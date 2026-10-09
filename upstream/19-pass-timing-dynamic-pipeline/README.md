# [mlir] `-mlir-timing` times a dynamic pipeline outside the pass that runs it

On llvm main at 7208ba24 (the pin), and on main at 626eeb8e (2026-10-09),
whose four files involved are the pin's, MLIR's pass timing nests the
timer of a pipeline that a pass runs through `Pass::runPipeline` under the
root of the report, not under the timer of the pass. The pipeline's row
prints at the top level beside the pass, its time is counted twice (in the
pass's row and in its own), and the report's Rest, the total less its
top-level rows, goes negative. Two such pipelines on the same op name, one
run while the other runs, share one timer, which then adds up the wrong
intervals. Upstream, the inliner (its default pipeline on each callable)
and `composite-fixed-point-pass` show it. Here, idr-simplify, idr-eval,
idr-inline, idr-target and idr-canonicalize run pipelines that way, so
`idris-mlir-cc --timing` shows it inside those steps' rows: a step's rows
add up to more than the step.

Reported upstream as llvm/llvm-project#169443 (2025-11-25). The fix is
the open pull request llvm/llvm-project#169615, whose code change
`llvm.patch` carries; its test does not test it (see Patch).

## Reproduce

`inline.mlir` (a private function and one call of it):

```mlir
func.func private @g(%a: i32) -> i32 {
  %c = arith.constant 1 : i32
  %r = arith.addi %a, %c : i32
  return %r : i32
}

func.func @f(%a: i32) -> i32 {
  %r = func.call @g(%a) : (i32) -> i32
  return %r : i32
}
```

```
$ mlir-opt inline.mlir -mlir-disable-threading -pass-pipeline='builtin.module(inline)' \
    -mlir-timing -mlir-timing-display=tree -o /dev/null
...
  ----Wall Time----  ----Name----
    0.0004 ( 54.7%)  Parser
    0.0002 ( 30.9%)  InlinerPass
    0.0000 (  1.1%)    (A) CallGraph
    0.0001 ( 11.4%)  'func.func' Pipeline
    0.0001 ( 11.2%)    CanonicalizerPass
    0.0001 (  9.5%)  Output
   -0.0000 ( -6.5%)  Rest
    0.0007 (100.0%)  Total
```

The `'func.func' Pipeline` row is the inliner canonicalizing the two
functions, which happens inside `InlinerPass`. Rest was negative in 100
of 100 runs in a row on arm64 macOS; the first run after a pause can print
it positive, as the doubled time is small beside the parser's. With
threading the tree is the same.

A composite pass in a composite pass:

```
$ mlir-opt inline.mlir -mlir-disable-threading -pass-pipeline='builtin.module(composite-fixed-point-pass{name=Outer pipeline="composite-fixed-point-pass{name=Inner pipeline=canonicalize}"})' \
    -mlir-timing -mlir-timing-display=tree -o /dev/null
...
    0.0001 ( 19.0%)  Outer
    0.0001 ( 18.1%)  'any' Pipeline
    0.0001 ( 17.4%)    Inner
    0.0001 (  8.6%)    CanonicalizerPass
    0.0001 ( 10.4%)  Output
   -0.0001 ( -7.7%)  Rest
```

Both pipelines are op-agnostic, so both nest under the root with the same
key: one row holds Inner and the canonicalizer Inner runs side by side,
and its time is that of one timer started twice before it stopped.
`tests/upstream/pass-timing-dynamic-pipeline` checks both reproducers.

## Expected

Each pipeline row nested in the row of the pass that runs it, as the rows
of an adaptor's nested pipelines are; so every row at least the sum of the
rows nested directly in it, and Rest not negative.

## Cause

- `OpToOpPassAdaptor::run` (`mlir/lib/Pass/Pass.cpp:570`) gives the
  dynamic-pipeline callback of every pass the parent info
  `{thread, pass}`, which `runPipeline` passes to the instrumentation
  (`:592`).
- `PassTiming::runBeforePipeline` (`mlir/lib/Pass/PassTiming.cpp:55-75`)
  nests the pipeline's timer under the timer whose index
  `parentTimerIndices` holds for that key, and under `rootScope` when it
  holds none (`:63-67`). The timer's key is the op name (`:71`).
- `runBeforePass` (`:88-106`) records an index there only for an
  `OpToOpPassAdaptor` (`:93-94`), and `runAfterPass` erases only those
  (`:110-111`). For any other pass the lookup fails, and the pipeline's
  timer is a child of the root.
- The root has one child per key (`TimerImpl::nest`,
  `mlir/lib/Support/Timing.cpp:247-253`). A second pipeline on the same op
  name, started before the first stops, starts that timer again: `start`
  overwrites the start time (`:232`) and each `stop` adds the time since it
  (`:235-239`), so the row counts the inner run twice and loses the start
  of the outer one.
- Rest is the total less the root's children (`Timing.cpp:431-434`), and
  the pipeline's time is in two of them.

Before D132979 (d1ef9f142e58, 2022-09, first in LLVM 16: "Always use
parentInfo for determining pipeline parent scope"), a pipeline on a thread
with an active timer nested under the innermost one, which for a dynamic
pipeline is its pass's. That change made the lookup the only way, so that
the threaded adaptor's pipelines find their adaptor, and only adaptors
record themselves.

## Patch

`llvm.patch`, a `git diff` against 7208ba24. `runBeforePass` records the
index of every pass's timer in `parentTimerIndices`, before it pushes the
timer, and `runAfterPass` erases it for every pass. The `PassTiming.cpp`
hunk is #169615's, byte for byte (the file's blob after it is c67f994, as
on the pull request). The key `{thread, pass}` is still one running pass,
as it was for adaptors. A dynamic pipeline on another thread (the
inliner's, with threading on) finds its pass's timer as an adaptor's
asynchronous pipelines find theirs, and nests in it as an asynchronous
child; the instrumentor calls PassTiming under its lock.

The test hunk is ours: #169615's test, revised so that it fails without
the change. Review of #169615 found its test passing at HEAD (2025-11-28,
pinged 2025-12-22, unanswered). It passes because FileCheck collapses
whitespace by default, so the checks' indentation is not compared, and the
rows come in the same order whether the pipeline is nested or not. The
revised RUN lines pass `--strict-whitespace`, and each check starts at
the `%)` that ends the time column, since FileCheck strips a pattern's
leading whitespace even then; the indentation of each name is matched
exactly. That test is what `submission.md` posts to #169615.

The patch touches no file the other patches touch, so it applies to the
pinned source alone and after the others (`tests/spec/upstream-patches`).

## Testing at the pin

On arm64 macOS, with two scratch `mlir-opt`s: a main that registers every
upstream dialect, extension and pass (no test dialect or test passes),
compiled by Apple clang 21 with the toolchain's flags (`-std=c++17
-fno-rtti -fno-exceptions`, assertions on) and linked against the static
libraries of `.toolchain/llvm-macos` (7208ba24 with 02-07, 09 and 15
applied), one with `PassTiming.cpp` as pinned and one with this patch.

- With the patch, the reproducer's pipeline row is nested in
  `InlinerPass`, with threading and without, and Rest was not negative in
  100 of 100 runs (without the patch, negative in 100 of 100). The
  composite passes print two `'any' Pipeline` rows, one in each pass.
  `tests/upstream/pass-timing-dynamic-pipeline` prints its expected output
  with the patched binary (through a copy of `.toolchain` whose `mlir-opt`
  is that binary) and "still reproduces" twice with the toolchain's own.
- `pass-timing.mlir` as patched: every RUN line but the
  `-test-pm-nested-pipeline` one (the scratch binary has no test passes)
  passes with the toolchain's FileCheck, under `pipefail`. The two new
  RUN lines fail without the change, at the `'func.func' Pipeline` row,
  and pass with it; each passed 300 of 300 runs with it (12 cores). The
  test as #169615 has it passes with and without the change.
- clang-format did not run (none here); the hunk is #169615's, which
  LLVM's format check passed on 2025-11-26.

`check-mlir` has not run with this patch.

## Upstreaming plan

Status: not posted. #169443 and #169615 are open; #169615's change is as
reviewed, its author has not answered the review's question about the
test since 2025-11-28 (last push 2026-01-26). `PassTiming.cpp`,
`pass-timing.mlir`, `Pass.cpp` and `Timing.cpp` on main at 626eeb8e
(2026-10-09) are the pin's blobs, so the bug and the test stand on main as
at the pin.

- Where: one comment on #169615, the text in `submission.md`: why its test
  passes at HEAD, and the revised test, which fails there and passes with
  the change. No new issue (#169443 is the report) and no pull request of
  our own while #169615 is open. If its author does not answer within a
  month of the comment, a pull request with its change and the revised
  test, naming #169443 and #169615, is Bjorn's call: it takes over
  another author's change.
- Before posting: check that main's four files are still the pin's (or
  that the diff in `submission.md` still applies to #169615's file). Before
  a pull request of our own: `git apply --check` on then-current main;
  `check-mlir` is left to LLVM's pre-merge CI, as LLVM is not built here.
- Upstream test: the `DYNAMIC-PIPELINE` RUN lines and checks in
  `mlir/test/Pass/pass-timing.mlir`.
- The patch is dropped when the pin includes #169615 (or another fix the
  revised test passes with); then this directory,
  `tests/upstream/pass-timing-dynamic-pipeline` and the `PINS.md` entry go.
