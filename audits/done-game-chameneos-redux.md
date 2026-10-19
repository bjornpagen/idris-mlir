<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane: the Benchmarks Game's chameneos-redux

## Added

`bench/chameneos-redux/`, in the flat layout every benchmark takes:

- `Main.idr`: the game's chameneos-redux in plain Idris over the stock
  Prelude (no packages). It prints the colour complement table, then runs
  the game for three creatures (blue red yellow) and for ten (blue red
  yellow red yellow blue red yellow red blue). For each creature it prints
  its meetings and the number of times it met itself, spelled out. Then
  it prints the total, spelled out, with each digit after a space.
- `main.c`: the C reference. It is the same algorithm, built by the pinned
  clang at -O2.
- `input`: `6000000`, the size the game measures at.
- `compare`: `bytes`. The game checks this program's output text, so the
  two outputs must agree byte for byte.

The game specifies threads, one per creature, and threads are outside
this compiler's language (AGENTS.md). Both files say so at the top. They
implement the workload as one deterministic cooperative scheduler:

- The creatures that can run wait in a FIFO run queue. At the start it
  holds them in the order they were made.
- The creature at the head arrives at the meeting place:
  - If the place has closed (n meetings done), every creature fades.
  - If nobody is waiting, it waits.
  - Otherwise the two meet. Both take the complement of their two
    colours, both count the meeting, and both count a self-meeting if the
    waiting creature is the arriving one. Then the waiting creature, and
    after it the arriving one, join the back of the queue.

In Idris the queue is a front list with a reversed back list. In C it is
a ring of indices.

Under this schedule:

- Three creatures meet in rounds of three meetings, each creature twice
  a round.
- Ten creatures meet in rounds of five, each creature once a round.

So for any n that is a multiple of 15, every creature gets the same share
of the meetings. That includes the game's 600 and 6000000. The output is
then exactly the game's published reference output.

The meeting-itself count is computed as the game asks. It cannot become
nonzero here, because a creature that is waiting is never in the run
queue.

## Verified

Every run below used the current build in `build/dev`; nothing was
rebuilt.

- `tools/compile.sh --num-threads=2` compiled `Main.idr` with no
  diagnostic.
- I built `main.c` the way `bench/run.sh` builds every C program:
  `.toolchain/llvm/bin/clang -O2 -Xclang -target-cpu -Xclang apple-m1
  -ffp-contract=off`, with the link flags from `idris-mlir
  --print-link-flags`. It built clean with `-Wall -Wextra`.
- For n = 0, 1, 2, 600, 6001 and 6000000, the output of this compiler's
  program and clang's program is byte-identical, and both exit 0.
- At n = 600 the output is byte-identical to the game's published
  reference output, as kept in Go's `test/bench/shootout/chameneosredux.txt`
  (go1.4).
- At the game's size, 6000000, this is arm64 macOS on an M2 Max, one run
  each:

  | build | wall time |
  | --- | --- |
  | this compiler | 0.13 s |
  | clang -O2 | 0.14 s |

  The output has 4000000 meetings per creature for three creatures and
  1200000 for ten, and the total line is ` one two zero zero zero zero
  zero zero` both times.
- Not run on x86_64 Linux: this lane ran on the Mac only.

Things I fixed in my own draft (not compiler bugs): `total` is an Idris
keyword, so the accumulator is named `allMet`.

## Deleted, rewritten, NEEDS-ACCEPTANCE

None. The scope is a new directory.

## Compiler bugs found

None. The compiler accepted the program as first written (apart from the
keyword clash above), and its output agrees with clang's at every size
tried.

## For the orchestrator, the bench lane and future harnesses

- The C reference is `bench/chameneos-redux/main.c`, in the new layout.
  `bench/run.sh` as it stands looks for `bench/c/<name>.c`, so the
  flattening lane's change to `run.sh` is what makes this C column live.
- `bench/README.md` says chameneos-redux "is not here" because it needs
  pre-emptive threads. That sentence and the table of game programs need
  updating: chameneos-redux is here, as the deterministic single-core
  schedule above. thread-ring could be added the same way. `bench/README.md`
  is outside this lane's scope, so I left it unchanged.
- The game compares this program's output text, and the published output
  holds only at sizes that are multiples of 15. If a future harness checks
  each benchmark against the game's published output at a small size, 600
  is the size to use for this program.
