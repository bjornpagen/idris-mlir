# Benchmarks

`make bench` runs `bench/run.sh`, a POSIX shell script, which builds each
program six ways and runs it on the same input (`make bench ARGS='--runs 3
fib tak'` runs fewer):

- **this compiler**: `bench/<name>/Main.idr`, ordinary Idris against the
  stock Prelude and base (`import Prelude`: `Num`, `Ord`, `if`, `cast`,
  `getChar`, `printLn`), or over `Linear.Array` of `libs/mlir-linear`
  where the program says so (`bench/<name>/packages`);
- **Idris Chez**: the same Idris source through the stock Chez backend;
- **MLton**: `bench/sml/<name>.sml`, the same algorithm in Standard ML,
  compiled with `-default-type int64` because Idris's `Int` has 64 bits;
- **clang -O2**: `bench/c/<name>.c`, the same algorithm in C, built with the
  pinned clang as a static PIE on musl, as our programs are, for the CPU
  this compiler targets (`idris-mlir-cc --print-target-cpu`) and without
  floating-point contraction, as this compiler builds Idris;
- **Koka**: `bench/koka/<name>.kk`, with the Perceus benchmarks' flags
  (`-O2 --stack=128M`);
- **Lean 4**: `bench/lean/<name>.lean`, compiled as Lean's own benchmarks
  are (`lean -c`, then `leanc -O3 -DNDEBUG`).

It checks that the Idris backends print the same text and that every
program prints the same numbers (to 1e-9), and reports the best of several
wall-clock runs, timed with GNU `date`'s nanoseconds; each time includes
starting the program, about a millisecond. MLton comes from the Debian
package unpacked into `.toolchain/mlton` with `dpkg -x`, Koka and Lean from
their release archives unpacked by `bench/toolchains.sh` into
`.toolchain/koka` and `.toolchain/lean` (nothing is installed system-wide),
each also looked up on `PATH`; without one, its column reads `n/a`. Every
program runs with an unlimited stack, as Lean's and Koka's benchmarks do
(cfold and deriv recurse as deep as their input is large). The last column
is clang's time over this compiler's: above 1 means this compiler is
faster.

## Results

On the development container (x86-64, 4 CPUs; LLVM 23.1.2, MLton
20210117, Koka 3.2.9, Lean 4.34.1, the pinned clang), best of 3, seconds,
in one run on 2026-10-01 at 6bdcf5d. The run-to-run spread on this machine
reaches 15%, so a ratio within that of 1 is parity.

| benchmark | input | this compiler | Idris Chez | MLton | clang -O2 | Koka | Lean 4 | clang / this |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ack | 10 | 0.004 | 0.901 | 0.041 | 0.045 | n/a | n/a | 11.57x |
| ackdyn | 10 | 0.040 | 0.925 | 0.033 | 0.044 | n/a | n/a | 1.10x |
| binary-trees | 21 | 5.779 | 36.558 | 7.433 | 27.039 | 11.373 | 6.039 | 4.68x |
| cfold | 20 | 0.182 | 0.621 | 0.417 | 0.517 | 0.408 | 0.266 | 2.85x |
| collatz | 3000000 | 0.536 | 20.120 | 2.006 | 0.567 | n/a | n/a | 1.06x |
| deriv | 10 | 1.316 | 3.236 | 1.154 | 3.699 | 1.041 | 1.138 | 2.81x |
| fannkuch-linear | 10 | 0.220 | 3.809 | n/a | 0.492 | n/a | n/a | 2.24x |
| fannkuch-redux | 10 | 0.634 | 11.281 | n/a | 0.421 | n/a | n/a | 0.66x |
| fasta | 250000 | 0.263 | 0.306 | n/a | 0.033 | n/a | n/a | 0.12x |
| fib | 38 | 0.077 | 3.077 | 0.243 | 0.103 | n/a | n/a | 1.34x |
| harmonic | 200000000 | 0.222 | 5.729 | 0.604 | 0.256 | n/a | n/a | 1.15x |
| k-nucleotide | fasta 250000 | n/a | 12.089 | n/a | 0.270 | n/a | n/a | n/a |
| mandelbrot | 2000 | 0.237 | 4.579 | 0.418 | 0.242 | n/a | n/a | 1.02x |
| mandelbrot-pbm | 4000 | n/a | 18.824 | n/a | 1.041 | n/a | n/a | n/a |
| nbody | 5000000 | 0.262 | 5.110 | 1.137 | 0.251 | n/a | n/a | 0.96x |
| nqueens | 13 | 0.875 | 11.822 | 1.001 | 1.213 | 0.855 | 1.798 | 1.39x |
| pidigits | 10000 | 0.977 | 5.044 | n/a | 0.991 | n/a | n/a | 1.01x |
| qsort | 400 | 1.279 | 13.252 | 1.484 | 1.303 | 20.646 | 2.054 | 1.02x |
| rbtree | 4200000 | 0.827 | 2.603 | 6.266 | 0.820 | 0.832 | 1.670 | 0.99x |
| rbtree-ck | 4200000 | 2.505 | 8.763 | 12.137 | 3.465 | 1.793 | 2.784 | 1.38x |
| regex-redux | fasta 250000 | 3.167 | 3.047 | n/a | n/a | n/a | n/a | n/a |
| reverse-complement | fasta 250000 | 0.374 | 0.674 | n/a | 0.014 | n/a | n/a | 0.04x |
| spectral-norm | 5500 | 1.924 | 150.766 | n/a | 1.504 | n/a | n/a | 0.78x |
| spectral-norm-linear | 5500 | 1.411 | 150.100 | n/a | 1.387 | n/a | n/a | 0.98x |
| tak | 18 | 0.094 | 0.986 | 0.128 | 0.101 | n/a | n/a | 1.07x |
| unionfind | 3000000 | 0.150 | 1.980 | 0.294 | 0.147 | 1.907 | 2.039 | 0.98x |

Compiling each program takes 1.7 to 12.5 seconds (idris-mlir, idris-mlir-cc
and the link); fannkuch-redux and regex-redux are the slow ones.

The programs are of three kinds.

**Numeric** (ack, ackdyn, collatz, fib, harmonic, mandelbrot, nbody, tak):
ordinary Idris against the stock Prelude, which costs nothing: its
interfaces, `Integer` literals and `show` internals are all resolved at
compile time, and these times equal those of the same programs written
against a hand-made numeric module.

**The Benchmarks Game** (binary-trees, fannkuch-redux, fasta, k-nucleotide,
mandelbrot-pbm, nbody, pidigits, regex-redux, reverse-complement,
spectral-norm): written as an Idris programmer writes them first (Prelude
and base, `getChar` for input, `putStrLn` for output; lists where the game
uses arrays, except fannkuch-redux, which is on base's `IOArray`), beside
the C of `bench/c`. regex-redux carries its own small regex engine, since
Idris has no regex library; it has no C version, so Chez is its only
reference. fannkuch-linear and spectral-norm-linear are the same two
programs in pure code over `Linear.Array`.

**Counting Immutable Beans' programs** (rbtree, rbtree-ck, cfold, deriv,
nqueens, binary-trees, qsort, unionfind): the benchmarks of the Lean 4 and
Koka (Perceus) papers, in Idris, with their Lean and Koka sources as the
papers' repositories have them (reading `n` from stdin), their C, and
their SML. qsort and unionfind are in pure code over `Linear.Array`.

### Per program

- **unionfind** (parity with C): path compression is a recursion that
  threads the array through every `find` and gives it back, which is the
  worst shape for a threaded value: three words of result (the record and
  the array) around a non-tail call. Two general changes brought it from
  1.4x of C to parity. An array value is its cell and its length (what a
  memref is), so a bounds check compares two registers instead of loading
  the length from the cell before every access, a load LLVM cannot hoist
  past the stores into the same cell. And a result a function always
  returns as one of its arguments (the array, through the recursion's join
  and its recursive call) is dropped after lowering, so `find` returns its
  two-word record in registers and the write after the recursion needs no
  second check, its index having been checked against the same length.
  Nothing in the compiler knows union-find.
- **fannkuch-linear** at 2.2x of C needs explaining, since a loop of array
  reads and swaps does not run twice as fast as C by itself. The work is
  the same (both count the same permutations and the same flips; the
  wall time scales the same from n=9 to n=11). The difference is in the C:
  clang recognizes the copy and the rotate loops as `memcpy` and `memmove`
  and calls musl's, once per permutation, on 40 bytes. Built with
  `-fno-builtin`, the same C takes 0.210 s against 0.503 s on this machine,
  and then runs 10 to 15% faster than the Idris. The C stays as written:
  it is what clang makes of the natural program, and a reader can repeat
  the experiment with one flag. The reading stands: the linear program
  compiles to the loop's loads and stores and nothing else.
- **fannkuch-redux** (`IOArray`) against **fannkuch-linear**: the same
  loops, 2.9x apart. The `IOArray` version pays Idris's own range test
  before the compiler's, a `Maybe` tag per element, and the IO monad's
  plumbing; the linear version is filled at creation so a read gives the
  element, and the compiler proves the thread exclusive, so the loops are
  loads and stores on the one array cell with no count changed and nothing
  allocated (the fixtures `linarray-*` state those properties). Both are
  in place: there is no copying array to turn off, since a linear array
  is a mutable object by construction, which is what the linear API
  promises on every backend; what there is to turn off is each compiler
  mechanism, below. `IOArray` is the escape hatch, imperative code
  compiled to imperative code.
- **Ablation.** `idris-mlir-cc --without=STEP,...` (or `--directive
  without=STEP,...` through `idris-mlir`) leaves pipeline steps out, or
  idr-rc's mechanisms (`reuse`, `borrow`, `sink`), so what each one is
  worth is a measurement, not a claim. fannkuch-linear and unionfind, best
  of 3 on this machine, each variant compiled and run alone (2026-10-01):

  | left out | fannkuch-linear | unionfind |
  | --- | ---: | ---: |
  | nothing | 0.209 | 0.166 |
  | idr-simplify | 4.770 | 1.484 |
  | sink (consumer sinking in idr-rc) | 0.240 | 0.166 |
  | idr-returned-arguments | 0.201 | 0.241 |
  | reuse (reset/reuse in idr-rc) | 0.211 | 0.215 |
  | idr-stack | 0.199 | 0.215 |
  | idr-tail-loops | 0.214 | 0.197 |
  | idr-defunctionalize | 0.215 | 0.203 |
  | idr-contify | 0.194 | 0.190 |
  | idr-trmc | 0.198 | 0.177 |
  | borrow (borrow inference in idr-rc) | 0.196 | 0.163 |
  | idr-narrow | 0.197 | 0.167 |

  The linear library is plain Idris: `read` and `write` wrap base's array
  primitive in `unsafePerformIO`, rebuild the `MkArray` record and give it
  back through `Res` pairs. Without the simplify loop (inlining,
  specialization, compile-time evaluation and the dialect's
  canonicalizations) fannkuch-linear takes 23x longer and unionfind 9x:
  that is what the loops of loads and stores cost to recover from the
  functional program, and it is the compiler's work, not the program's.
  After it, what each remaining mechanism is worth is within the machine's
  spread on fannkuch (consumer sinking's 15% is the one visible one: a
  dup and a drop per swap otherwise), and on unionfind the returned
  argument (1.45x), the reuse of dead cells and the stack (1.3x each) and
  the loops (1.2x) each carry their weight.
- **spectral-norm** (lists, 0.78x) and **spectral-norm-linear** (parity):
  the linear one is loads and multiplies; the list one rebuilds its lists
  in their own cells and pays for it. The input is 5500, the game's, so
  that the run lasts seconds.
- **qsort** (parity with C): Koka's own `qsort.kk` takes 20 s on this
  input; it is the program as the Perceus repository has it, measured as
  written, and the column is there for the comparison, not as a verdict
  on Koka.
- **rbtree, rbtree-ck, cfold, deriv, nqueens:** persistent trees and
  terms rebuilt on every step. Reference counting rebuilds them in the
  cells of the values that die (reset/reuse), as Lean and Koka do, and the
  stack holds what never leaves its frame; the times are Lean's and Koka's
  or better, except rbtree-ck, where Koka is 1.4x faster (it keeps the
  older trees alive, which measures the allocator under a live set) and
  the C at 3.5 s frees through musl's `malloc`.
- **binary-trees:** the C version frees through musl's `malloc`; the
  game's fastest C uses a pool. Ours frees each tree as it dies, through
  the runtime's allocator, and the bottom level is one static cell.
- **pidigits:** C uses GMP in place; ours allocates a new `mpz` per
  operation and still matches it, through the runtime's allocator. The
  in-place form waits for exclusivity on bigs.
- **fasta, reverse-complement:** `List Char` where C has byte buffers, and
  input read a character at a time; byte I/O is the next step.
- **k-nucleotide** is rejected: `Data.SortedMap` keeps its `Ord`
  dictionary in a value chosen at runtime. **mandelbrot-pbm** compiles,
  but `putChar` writes UTF-8 for bytes from 128 on (a decided divergence
  from Chez), so its bitmap is not compared; `mandelbrot` above counts the
  same points instead.

## Caveats

- SML's `int` arithmetic traps on overflow, and Idris's wraps. That costs
  MLton a check per operation (collatz, fib, tak). The C and Idris versions
  wrap.
- The SML n-body is written like the Idris one, with immutable records;
  the usual SML version updates arrays in place. The C version updates an
  array in place, as C programs do.
- All print the same n-body energies to the last digit, so the
  floating-point work is the same.
- `ack` computes `ack 3 n`. With `m` a literal, call-pattern
  specialization makes copies of `ack` with `m` fixed,
  and LLVM turns three of them into closed forms, so almost nothing is left
  to run; clang does none of this. This measures the specialization, not
  recursion.
- `ackdyn` is the same computation with `m` read from the input, so no
  specialization applies. It measures deep, non-tail recursion. Inlining
  `ack` into itself by hand in the Idris source helped `ack` and hurt
  `fib`, so it is not done.
- `fib`: LLVM turns one of the two recursive calls into a loop with an
  accumulator, for this compiler and for clang alike. It was 14% slower
  while it evaluated curried arguments right to left, which made LLVM loop
  on the other call.

## Allocation shapes

`foreign/idr/bench/alloc/` benchmarks the heap traffic the planned runtime
will produce (it is C++, which lives only under `foreign/idr`). It chose
the allocator; its README has the commands
and the results.
