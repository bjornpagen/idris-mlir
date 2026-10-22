<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Benchmarks

Each benchmark is one directory, `bench/<name>/`: the program in Idris
(`Main.idr`), the same program in C (`main.c`; the two `-linear`
programs link to the C of the program they port), its input (`input`, the
stdin itself, or `input-from`, a generator benchmark and its argument,
whose C output is the stdin), and `packages` where it uses the packages of
`libs/`. Nothing else is a benchmark's. `bench/records/` holds what was
measured, and nothing in it is a benchmark.

`make bench` runs `bench/run.sh` (`make bench ARGS='--runs 3 fib tak'`
runs fewer), which builds each program three ways and times each on the
input: this compiler on `Main.idr`; the same source through the stock
Idris Chez backend, except a program over `libs/mlir-array`, whose
generating set means only what this compiler makes of it; and the pinned
clang at `-O2` on `main.c`, for this compiler's target CPU, without
floating-point contraction, linked as `idris-mlir --print-link-flags` says
the target links a program. Every program runs on the stack the system
gives, and every build and run is killed after 1800 seconds.
This compiler's output must agree with clang's: the same text, with a
decimal number held to 1e-9 (a double prints as its shortest text in Idris
and as `printf` writes it in C), and a binary output byte for byte. A
benchmark either compiler does not build fails the run, which still
measures the rest but keeps no record. The Chez column is a time and
nothing more. The output starts with what the run
measured on, then `bench/report.sh`'s table: the best of the runs in
wall-clock seconds, process start included, clang's time over this
compiler's (above 1, this compiler is faster), and each compile's time.

The programs are of three kinds. Numeric ones over the stock Prelude (ack,
collatz, fib, harmonic, mandelbrot-count, tak). The Computer Language
Benchmarks Game's programs, under the game's own names and at the size the
game measures (`fasta-redux` is from its retired set); each `main.c` says
which of the game's C entries it follows, and `fannkuch-linear` and
`spectral-norm-linear` are two of them over the typed arrays. And the
programs of the Perceus and Counting Immutable Beans papers (rbtree,
rbtree-ck, cfold, deriv, nqueens, binary-trees, qsort, unionfind), written
in Idris from the papers' repositories. Each `Main.idr` says what it
computes and how.

A run record is `bench/records/<date>-<revision>-<os>-<arch>/`, kept by
`make bench ARGS='--record bench/records/<…>'` once every output has
agreed: every timed run (`samples.tsv`), the compile times and what it ran
on (`about`), with the results page and charts `bench/report.sh RUN
PREVIOUS` makes from them, which `tests/bench-records` checks are current.
The latest is [`records/2026-10-13-9a1b7b1-darwin-arm64`](records/2026-10-13-9a1b7b1-darwin-arm64/results.md).
The dated `<date>-<name>.md` files beside the run records are measurements
of the compiler itself, and `tools/profile.sh` writes its time traces there
too, uncommitted.

Reading a run: the run-to-run spread on a desktop reaches 15%, so a ratio
within that of 1 is parity, and the C column of one machine moves between
days, so records compare by each benchmark's ratio to its own run's C,
never by seconds. `ack` computes `ack 3 n` with `m` a literal, which
specialization copies and LLVM closes, so it measures the specialization;
in `fib` LLVM turns one recursive call into a loop for both compilers.
