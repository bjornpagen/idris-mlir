# Benchmarks

`python3 bench/run.py` builds each program four ways and runs it on the same
input:

- **this compiler**: `bench/<name>/Main.idr`, ordinary Idris against the
  stock Prelude alone (`import Prelude`: `Num`, `Ord`, `if`, `cast`,
  `getChar`, `printLn`);
- **Idris Chez**: the same Idris source through the stock Chez backend;
- **MLton**: `bench/sml/<name>.sml`, the same algorithm in Standard ML,
  compiled with `-default-type int64` because Idris's `Int` has 64 bits;
- **gcc -O2**: `bench/c/<name>.c`, the same algorithm in C.

It checks that the Idris backends print the same text and that every
program prints the same numbers (to 1e-9), and reports the best of several
wall-clock runs. MLton comes from the Debian package unpacked into
`.toolchain/mlton` with `dpkg -x` (nothing is installed system-wide).

## Results

On the development container (x86-64, 4 CPUs; LLVM 23.1.2, MLton 20210117,
GCC as pinned), best of 5, seconds:

| benchmark | input | this compiler | Idris Chez | MLton | gcc -O2 | vs MLton |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| nbody | 5000000 | 0.338 | 5.909 | 1.340 | 0.341 | 3.97x |
| mandelbrot | 2000 | 0.358 | 5.195 | 0.518 | 0.366 | 1.45x |
| fib | 38 | 0.109 | 3.426 | 0.286 | 0.065 | 2.64x |
| tak | 18 | 0.117 | 1.303 | 0.175 | 0.105 | 1.49x |
| collatz | 3000000 | 0.466 | 21.007 | 1.972 | 0.596 | 4.23x |
| ack | 10 | 0.001 | 1.067 | 0.090 | 0.039 | 64.51x |
| ackdyn | 10 | 0.212 | 1.026 | 0.088 | 0.038 | 0.42x |
| harmonic | 200000000 | 0.254 | 6.412 | 0.649 | 0.247 | 2.56x |

The Prelude costs nothing: its interfaces, `Integer` literals and `show`
internals are all resolved at compile time, and these times equal those of
the same programs written against a hand-made numeric module.

## Caveats

- The programs are the ones the heap-free profile can express: no arrays,
  lists or trees. MLton's strengths on allocation-heavy code are not
  measured, and nothing here says how this compiler will do once it has a
  heap.
- SML's `int` arithmetic traps on overflow, and Idris's wraps. That costs
  MLton a check per operation (collatz, fib, tak). The C and Idris versions
  wrap.
- The SML n-body is written like the Idris one, with immutable records;
  the usual SML version updates arrays in place. The C version updates an
  array in place, as C programs do.
- All four print the same n-body energies to the last digit, so the
  floating-point work is the same.
- `ack` computes `ack 3 n`. With `m` a literal, call-pattern
  specialization (`ELIM-G-19`) makes copies of `ack` with `m` fixed,
  and LLVM turns three of them into closed forms, so almost nothing is left
  to run; gcc gets part of the way with its own constant cloning. This
  measures the specialization, not recursion.
- `ackdyn` is the same computation with `m` read from the input, so no
  specialization applies. It measures deep, non-tail recursion, and MLton
  is 2.4x faster: LLVM's code here matches clang's on the C version
  (0.16 s), and gcc is faster still by inlining `ack` into itself. Doing
  that by hand in the Idris source helped `ack` (0.13 s) and hurt `fib`,
  so it is not done.
- `fib` is one of the cases where gcc is clearly faster, by 1.7x. LLVM turns
  one of the two recursive calls into a loop with an accumulator; gcc also
  inlines the function into itself, which LLVM does not do. This compiler
  now matches clang 18 at `-O2` on the C version (0.109 s); it was 14%
  slower while it evaluated curried arguments right to left, which made
  LLVM loop on the other call (`SEM-EVAL-2`).

## Allocation shapes

`foreign/idr/bench/alloc/` benchmarks the heap traffic the planned runtime
will produce (it is C++, which lives only under `foreign/idr`). It chose
the allocator (`docs/plan.md` section 5.6); its README has the commands
and the results.
