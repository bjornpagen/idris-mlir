# Benchmarks

`make bench` runs `bench/run.sh`, a POSIX shell script, which builds each
program four ways and runs it on the same input (`make bench ARGS='--runs 3
fib tak'` runs fewer):

- **this compiler**: `bench/<name>/Main.idr`, ordinary Idris against the
  stock Prelude alone (`import Prelude`: `Num`, `Ord`, `if`, `cast`,
  `getChar`, `printLn`);
- **Idris Chez**: the same Idris source through the stock Chez backend;
- **MLton**: `bench/sml/<name>.sml`, the same algorithm in Standard ML,
  compiled with `-default-type int64` because Idris's `Int` has 64 bits;
- **clang -O2**: `bench/c/<name>.c`, the same algorithm in C, built with the
  pinned clang as a static PIE on musl, as our programs are, for the CPU
  this compiler targets (`idris-mlir-cc --print-target-cpu`) and without
  floating-point contraction, as this compiler builds Idris.

It checks that the Idris backends print the same text and that every
program prints the same numbers (to 1e-9), and reports the best of several
wall-clock runs, timed with GNU `date`'s nanoseconds; each time includes
starting the program, about a millisecond. MLton comes from the Debian
package unpacked into `.toolchain/mlton` with `dpkg -x` (nothing is
installed system-wide), or from `PATH`; without it, its column reads `n/a`.

## Results

On the development container (x86-64, 4 CPUs; LLVM 23.1.2, MLton 20210117,
the pinned clang), best of 5, seconds:

| benchmark | input | this compiler | Idris Chez | MLton | clang -O2 | vs MLton |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| nbody | 5000000 | 0.325 | 6.634 | 1.388 | 0.311 | 4.27x |
| mandelbrot | 2000 | 0.346 | 5.772 | 0.528 | 0.361 | 1.53x |
| fib | 38 | 0.120 | 3.766 | 0.301 | 0.115 | 2.51x |
| tak | 18 | 0.124 | 1.370 | 0.183 | 0.123 | 1.48x |
| collatz | 3000000 | 0.474 | 21.896 | 1.988 | 0.486 | 4.20x |
| ack | 10 | 0.004 | 1.091 | 0.096 | 0.169 | 25.36x |
| ackdyn | 10 | 0.183 | 1.062 | 0.096 | 0.172 | 0.53x |
| harmonic | 200000000 | 0.259 | 6.797 | 0.662 | 0.259 | 2.56x |

Compiling each program takes 2.1 to 4.1 seconds (idris-mlir, idris-mlir-cc
and the link).

The Prelude costs nothing: its interfaces, `Integer` literals and `show`
internals are all resolved at compile time, and these times equal those of
the same programs written against a hand-made numeric module.

## The Benchmarks Game

The ten programs of the Computer Language Benchmarks Game, written as an
Idris programmer writes them first (Prelude and base, lists where the game
uses arrays, `getChar` for input, `putStrLn` for output), beside the C of
`bench/c`. regex-redux carries its own small regex engine, since Idris has
no regex library; it has no C version, so Chez is its only reference.
Same machine and method as above, best of 3 (2026-10-01, at 60176f4):

| benchmark | input | this compiler | Idris Chez | clang -O2 |
| --- | --- | ---: | ---: | ---: |
| binary-trees | 21 | 5.579 | 35.598 | 25.821 |
| fannkuch-redux | 10 | 1.650 | 2.408 | 0.461 |
| fasta | 250000 | 0.319 | 0.255 | 0.036 |
| k-nucleotide | fasta 250000 | rejected | 12.787 | 0.263 |
| mandelbrot (PBM) | 4000 | differs | 18.817 | 0.985 |
| n-body | 5000000 | 0.325 | 6.634 | 0.311 |
| pidigits | 10000 | 0.990 | 5.062 | 1.042 |
| regex-redux | fasta 250000 | 3.244 | 3.124 | n/a |
| reverse-complement | fasta 250000 | 0.325 | 0.592 | 0.014 |
| spectral-norm | 1000 | 0.069 | 4.777 | 0.052 |

- **binary-trees:** the C version frees through musl's `malloc`; the
  game's fastest C uses a pool. Ours frees each tree as it dies, through
  the runtime's allocator, and the bottom level is one static cell.
- **pidigits:** C uses GMP in place; ours allocates a new `mpz` per
  operation and still matches it, through the runtime's allocator. The
  in-place form waits for exclusivity on bigs.
- **spectral-norm:** on lists of doubles, where it was 56x slower than C
  before reference counting learned to rebuild lists in their own cells.
- **fannkuch-redux, fasta, reverse-complement:** lists and `List Char`
  where C has arrays and byte buffers, and input read a character at a
  time; arrays on the tensor path and byte I/O are the next steps.
- **k-nucleotide** is rejected: `Data.SortedMap` keeps its `Ord`
  dictionary in a value chosen at runtime. **mandelbrot (PBM)** compiles,
  but `putChar` writes UTF-8 for bytes from 128 on (a decided divergence
  from Chez), so its bitmap is not compared; `bench/mandelbrot` above
  counts the same points instead.

## Caveats

- The programs compute on numbers, with no lists or trees, so they
  measure code generation and specialization, not the heap. MLton's
  strengths on allocation-heavy code are not measured here.
- SML's `int` arithmetic traps on overflow, and Idris's wraps. That costs
  MLton a check per operation (collatz, fib, tak). The C and Idris versions
  wrap.
- The SML n-body is written like the Idris one, with immutable records;
  the usual SML version updates arrays in place. The C version updates an
  array in place, as C programs do.
- All four print the same n-body energies to the last digit, so the
  floating-point work is the same.
- `ack` computes `ack 3 n`. With `m` a literal, call-pattern
  specialization makes copies of `ack` with `m` fixed,
  and LLVM turns three of them into closed forms, so almost nothing is left
  to run; clang does none of this (0.18 s, as on `ackdyn`). This
  measures the specialization, not recursion.
- `ackdyn` is the same computation with `m` read from the input, so no
  specialization applies. It measures deep, non-tail recursion, and MLton
  is 2.3x faster, as it is than clang on the C version (0.17 s). Inlining
  `ack` into itself by hand in the Idris source helped `ack` and hurt
  `fib`, so it is not done.
- `fib`: LLVM turns one of the two recursive calls into a loop with an
  accumulator, for this compiler and for clang alike; the two run in the
  same time (0.11 s) to within this machine's run-to-run spread, which
  reaches 15% (the table's 0.128 is one such run). It was 14% slower while
  it evaluated curried arguments right to left, which made LLVM loop on the
  other call.

## Allocation shapes

`foreign/idr/bench/alloc/` benchmarks the heap traffic the planned runtime
will produce (it is C++, which lives only under `foreign/idr`). It chose
the allocator; its README has the commands
and the results.
