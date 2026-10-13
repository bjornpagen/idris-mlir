# Profiles

Tracy captures of the compiler, one compilation each, written by
`tools/profile.sh` as `<date>-<commit>-<name>.tracy`. They are not
committed (only this file is); keep one you want to compare against
outside the tree, or name the commit and command that make it again.

## Taking one

    tools/profile.sh [--memory] [--name NAME] [--] ARGUMENT...

`ARGUMENT...` are `idris-mlir`'s. The script builds the `profile` preset
(Release, `IDRIS_MLIR_PROFILE=ON`, frame pointers and line tables) into
`build/profile`, starts Tracy's capture tool on localhost, runs the
compile with `TRACY_NO_EXIT=1`, and prints the path of the capture it
saved. `make build` first: the profile build runs the same frontend and
prefix. Open the capture with the profiler of the pinned Tracy release
(`third_party/tracy`); another release may not read it.

`--memory` uses a second build, `build/profile-memory`, configured with
`IDRIS_MLIR_PROFILE_MEMORY=ON`: its tools replace the global `operator
new` and `delete` to put every allocation on the timeline. That takes a
lock per allocation while a capture is connected, which across MLIR's
threads changes the timeline, so a profile of time is taken without it.

## What is in one

- A frame per compilation (`compile`) and per round of `idr-simplify`
  (`round`), with the plots `functions`, `clones` and `ops` after each
  round.
- A zone for every pass and every analysis, nested and dynamic pipelines
  included, named as `-mlir-timing` names them; a pass zone's text is the
  operation it ran on (`idr.func @name` for a function pass). Passes are
  ochre, analyses purple.
- The driver's phases (`frontend`, `parse`, `translate`, `link runtime`,
  `optimize`, `codegen`, `link`), and inside a pass at most a few zones
  around a stage worth seeing apart.
- Call stacks sampled from every thread. On macOS the client is built to
  start its sampler without root. On Linux it samples through perf
  events, as far as `kernel.perf_event_paranoid` allows.

The profiler costs nothing until a capture connects: the client is built
on demand, so a zone is a load and a branch until then, and events before
the connection are not kept. The capture tool is already trying to
connect when the compile starts, so only the profiler's own start-up is
missed.

## Every other build holds no Tracy

Only the profile preset defines `TRACY_ENABLE`. Every other build reads
the same header, `idr/Support/Profile.h`, whose macros then expand to
nothing (their arguments are not evaluated), and
`idr::profile::addInstrumentation` adds nothing; the client is not
compiled. So in `dev`, `release`, `hardened` and `lint` no tool holds a
symbol of Tracy's:

    for tool in idris-mlir idris-mlir-opt idris-mlir-reduce; do
      .toolchain/llvm/bin/llvm-nm -C build/dev/foreign/idr/$tool | grep -i tracy
    done

prints nothing, where the same loop over `build/profile` lists
`___tracy_emit_zone_begin_alloc` and the rest of the client.

## The runtime is not profiled

`runtime/` is part of every program the compiler builds, linked into it
and inlined from its bitcode. A zone there would put a profiler with a
thread and a socket into programs, which link nothing but the runtime and
the C library, and would change the code the benchmarks measure. Its
primitives are also called far too often for a zone each. When the
compiler itself calls the runtime (a folder), the time shows in the
enclosing pass's zone and in its sampled call stacks. A program is
profiled with the system's sampling profiler, not with this.
