# Benchmarks

`python3 bench/run.py` builds each program four ways and runs it on the same
input:

- **this compiler**: `bench/<name>/Main.idr`, ordinary Idris against the
  stock Prelude (`import Prelude`: `Num`, `Ord`, `if`, `cast`, `printLn`),
  with `IdrisMLIR.IO` only for reading the input;
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
GCC as pinned), best of 3, seconds:

| benchmark | input | this compiler | Idris Chez | MLton | gcc -O2 | vs MLton |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| nbody | 5000000 | 0.349 | 5.790 | 1.343 | 0.341 | 3.85x |
| mandelbrot | 2000 | 0.361 | 5.188 | 0.516 | 0.364 | 1.43x |
| fib | 38 | 0.135 | 3.545 | 0.290 | 0.067 | 2.15x |
| tak | 18 | 0.116 | 1.291 | 0.174 | 0.104 | 1.50x |
| collatz | 3000000 | 0.456 | 20.765 | 1.928 | 0.597 | 4.23x |

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
- `fib` is the one case where gcc is clearly faster, by 2x. LLVM already
  turns one of the two recursive calls into a loop with an accumulator;
  gcc also inlines the function into itself, which LLVM does not do.
