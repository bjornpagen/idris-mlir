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
  pinned clang as a static PIE on musl, as our programs are.

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
| nbody | 5000000 | 0.326 | 6.496 | 1.402 | 0.327 | 4.30x |
| mandelbrot | 2000 | 0.358 | 5.842 | 0.517 | 0.398 | 1.45x |
| fib | 38 | 0.128 | 3.688 | 0.288 | 0.111 | 2.26x |
| tak | 18 | 0.121 | 1.307 | 0.185 | 0.118 | 1.52x |
| collatz | 3000000 | 0.492 | 24.226 | 2.016 | 0.470 | 4.09x |
| ack | 10 | 0.003 | 1.144 | 0.094 | 0.177 | 31.98x |
| ackdyn | 10 | 0.207 | 1.136 | 0.090 | 0.167 | 0.44x |
| harmonic | 200000000 | 0.251 | 7.448 | 0.639 | 0.261 | 2.54x |

Compiling each program takes 1.9 to 3.1 seconds (idris-mlir, idris-mlir-cc
and the link).

The Prelude costs nothing: its interfaces, `Integer` literals and `show`
internals are all resolved at compile time, and these times equal those of
the same programs written against a hand-made numeric module.

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
