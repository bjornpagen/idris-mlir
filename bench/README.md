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
| nbody | 5000000 | 0.333 | 5.756 | 1.347 | 0.338 | 4.04x |
| mandelbrot | 2000 | 0.359 | 5.128 | 0.516 | 0.368 | 1.44x |
| fib | 38 | 0.110 | 3.431 | 0.287 | 0.065 | 2.60x |
| tak | 18 | 0.116 | 1.290 | 0.170 | 0.105 | 1.46x |
| collatz | 3000000 | 0.473 | 21.135 | 1.934 | 0.590 | 4.09x |

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
- `fib` is the one case where gcc is clearly faster, by 1.7x. LLVM turns
  one of the two recursive calls into a loop with an accumulator; gcc also
  inlines the function into itself, which LLVM does not do. This compiler
  now matches clang 18 at `-O2` on the C version (0.109 s); it was 14%
  slower while it evaluated curried arguments right to left, which made
  LLVM loop on the other call (`SEM-EVAL-2`).
