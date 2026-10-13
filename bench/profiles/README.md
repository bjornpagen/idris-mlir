# Profiles

Time traces of the compiler, one compilation each, written by
`tools/profile.sh` as `<date>-<commit>-<name>.time-trace.json`. They are
not committed (only this file is); keep one you want to compare against
outside the tree, or name the commit and command that make it again.

## Taking one

    tools/profile.sh [--name NAME] [--] ARGUMENT...

`ARGUMENT...` are `idris-mlir`'s. The script runs the dev build's
compiler (`make build` first; `IDRIS_MLIR` names another, a release
build's for timings worth comparing) with `--time-trace`, prints the
twenty entries the compilation spent most time in, and prints the
trace's path last. There is no profile build and nothing to bootstrap:
every build carries the trace, off until a tool is given
`--time-trace=<file>`, as clang's `-ftime-trace` is. `idris-mlir` and
`idris-mlir-opt` both take it (and `--time-trace-granularity=<µs>`,
which drops shorter spans; at the default 0 every span is kept).

The trace is Chrome trace JSON. Open it in Perfetto
(ui.perfetto.dev): each thread is a track, each zone a slice, and a
zone's detail names what it ran on (`idr.func @name` for a function
pass, a function or module name on the LLVM side). A `Total <name>`
slice per entry name sums its runs, which is what the script prints.

## What is in one

- The compilation as one span (`compile`), and inside it the driver's
  phases (`frontend`, `parse`, `translate`, `link runtime`, `optimize`,
  `codegen`, `link`).
- A zone for every MLIR pass and every analysis it computes, nested
  and dynamic pipelines included, named as `-mlir-timing` names them;
  inside a pass at most a few zones around a stage worth seeing apart.
  An instant event (`round`) marks the end of each round of
  `idr-simplify`.
- A zone for every pass and analysis of LLVM's optimization pipeline,
  under `optimize`. The code generator's legacy pipeline has no such
  callbacks; `codegen` is its one span.
- The passes a pass manager runs on its pool threads are zones on
  those threads' tracks: a pipeline hook begins each pool thread's
  profiler and finishes it with the outermost pipeline there, so a
  trace holds every thread's work. What a thread was doing between
  zones is not sampled; for that, use the system's sampling profiler.

Nothing is recorded until `--time-trace` is given: with no trace
started, a zone is a load and a branch and no output byte changes, so
the same build is profiled and shipped. The trace has no counters, so
the per-round counts a profile once plotted are `--stats`'s and the
round trace's, not this one's. Allocations are not tracked; a zone's
nesting is the memory story this tells.

## The runtime is not profiled

`runtime/` is part of every program the compiler builds, linked into it
and inlined from its bitcode. A zone there would change the code the
benchmarks measure, and its primitives are called far too often for a
zone each. When the compiler itself calls the runtime (a folder), the
time shows in the enclosing pass's zone. A program is profiled with the
system's sampling profiler, not with this.
