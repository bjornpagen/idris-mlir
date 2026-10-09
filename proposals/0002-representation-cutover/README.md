# 0002: the representation cutover, what remains

**Status:** accepted in part, integrated in 93f5d9c9, 327c2e30 and
0451b1b8. The work it compiled is in the tree, and the code is its
specification. What follows is what its qualification has not run or
proved, and the one owner decision not yet carried out. When every item is done, this directory is deleted.

## Not run

- **The suites on both targets.** `make check`, `make build`, `make test`,
  `make test-idr` and `make test-mlir-tools` last passed in round 3, on
  arm64 macOS, on the toolchain of the time (7208ba24 with 02-07, 09 and
  15), with `upstream/16`'s group set aside: check 25/25, test 373/373,
  test-idr 251/251, test-mlir-tools 10/10. Nothing committed after round 3
  has been built, 327c2e30's compile-time fix and 0451b1b8 among them, and
  x86_64 Linux has never run them. They run with the toolchain the one
  recipe builds, which is proposal 0003's remaining step. On x86_64 Linux
  that run is also the first of the runtime platform layer's Linux
  branches and of `tests/upstream/clang-module-layout-forward-declaration`.
  A target that has not run them is NotRun, never green.
- **The bench.** `bench/run.sh` on each target, compared with that
  target's last record (`bench/runs/2026-10-07-f5a4dff9-darwin-arm64`,
  `bench/runs/2026-10-03-861acdc`) by each program's ratio to its own C
  (`bench/README.md`). The launch base's build is deleted, and
  `tools/verify-pins.sh` refuses to build it again on a toolchain carrying
  patches it lacks; the ratio to C takes out the clang both columns share.
  A program whose ratio is worse beyond the run-to-run spread is a
  regression, bisected and fixed. Chez's column is not part of this
  comparison, so a Chez time-out (fannkuch-linear's, over 300 s, stopped
  the last attempt) does not stop the run.
- **Peak live cells of `thunk-consumes-list`.** The runtime reports live
  cells only at exit (`runtime/Io/Ending.cppm`), and a peak counter would
  put a compare on every allocation of every program. The measure is max
  RSS at two lengths of the consumed list, 10^5 and 10^6: bounded means
  the larger run's max RSS is less than twice the smaller's, where a list
  kept alive gives ten times.
- **`tests/upstream-idris/run`.** Its `common.sh` still skips base's
  pointer and environment functions as raw pointers, which the cutover
  made compile as runtime handles. That skip goes, then it runs, and
  its results (`build/upstream-idris/results`) show the tests that now
  pass (the file, directory, clock and environment tests).

## Not proved

- **Compile times.** The whole suite met the bound: 649 compilations,
  1551.3 s against the launch base's 1440.0 s (x1.08, within 10%). Of the
  outliers, `bounds-unrelated-size` (8.2 s against 0.22 s in
  `idr-in-bounds`: a guard length's `maxsi` and a clamp rule doubling
  their witnesses) was fixed in 327c2e30 and not timed since; above twice
  its launch-base time it is a bug of ours. `every-io-export` (x2.10, the
  simplify loop on a module 16% larger) and `io-loop-through-helper`
  (x3.09) are read with pass timing on the first build of the current
  tree, and the pass that grew is fixed or its cost stated.
- **Sensitivity.** Of the 32 program, accept and reject rows, 13 fail at
  the launch base and so discriminate, and 15 pass there by design as
  non-regression rows. `memo-shared-stream`, `thunk-consumes-list`,
  `closure-result-roundtrip` and `deep-list-constant` pass there too: they
  stay as non-regression rows, since what they were meant to show is
  shown by the rows that fail at the base and by the peak above. The 37
  idr rows fail at the base; `idr/lower/meter` was not in the run, and
  needs none, since `idr-meter` did not exist there.

## Owner decision not yet carried out

- **The in-place promise becomes the default.** `--demand in-place`
  stays opt-in until the bench run above passes with it on; then it is
  the default.

## Seams the lanes left

Each is in the tree today, and each is a branch or a list where the
representation should say it once:

- `Lower/Facts.cppm`'s `isCell` still names `FnType` and `LazyType`;
- `Lower/Lowering.cppm` marks `func.call_indirect` and `func.constant`
  legal, which nothing produces;
- `Defunctionalize/ByName.cppm`'s `by_name` exemptions are a list of op
  names, where a trait would say it once;
- `ForceOp::verify` looks up its callee's declaration
  (`Dialect/Ops/Lazy.cc`);
- `Facts/ClosureLabel.cppm`'s `closureLabel` does not see memo labels;
- `--demand` with `--without idr-demand` is accepted silently
  (`Driver/Run.cppm`);
- an `array.new` fill function that never returns is an internal error;
- a partially applied `castPtr` is still rejected;
- `idr-canonicalize` runs its inner passes with test-convergence and
  verifies twice per round.
