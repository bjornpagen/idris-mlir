# Benchmarks

`make bench` runs `bench/run.sh`, which builds each program six ways and
runs it on one input (`make bench ARGS='--runs 3 fib tak'` runs fewer):
this compiler on `bench/<name>/Main.idr` (ordinary Idris over the stock
Prelude and base, or over `Linear.Array` of `libs/mlir-linear` where
`bench/<name>/packages` says so); the same source through the stock Chez
backend; MLton on `bench/sml/<name>.sml` (`-default-type int64`, as Idris's
`Int` has 64 bits); the pinned clang at `-O2` on `bench/c/<name>.c`, a
static PIE on musl for this compiler's target CPU without floating-point
contraction, as our programs are built; Koka on `bench/koka/<name>.kk`
(`-O2 --stack=128M`, the Perceus benchmarks' flags); Lean 4 on
`bench/lean/<name>.lean` (`lean -c`, `leanc -O3 -DNDEBUG`, as Lean's
benchmarks are built). Every program runs with an unlimited stack.

The script checks that the two Idris backends print the same text and that
every program prints the same numbers (to 1e-9), or the same bytes where
the game compares bytes, and reports the best of the runs in wall-clock
seconds, process start included (about a millisecond). MLton, Koka and
Lean are unpacked into `.toolchain/` by `bench/toolchains.sh` or found on
`PATH`; a missing one reads `n/a`. The last column is clang's time over
this compiler's: above 1, this compiler is faster.

## Results

Development container, x86-64, 4 CPUs; LLVM 23.1.2, MLton 20210117, Koka
3.2.9, Lean 4.34.1, the pinned clang; best of 3, in one run on 2026-10-02 at
903d127, except k-nucleotide, measured once it compiled, in a run of its
own on the same container (its note below). The run-to-run spread on this
machine reaches 15%, so a ratio within that of 1 is parity.

| benchmark | input | this compiler | Idris Chez | MLton | clang -O2 | Koka | Lean 4 | clang / this |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ack | 10 | 0.004 | 1.207 | 0.068 | 0.253 | n/a | n/a | 68.02x |
| ackdyn | 10 | 0.266 | 1.205 | 0.086 | 0.254 | n/a | n/a | 0.95x |
| binary-trees | 21 | 6.522 | 46.112 | 7.606 | 31.746 | 12.557 | 7.221 | 4.87x |
| cfold | 20 | 0.187 | 0.588 | 0.412 | 0.477 | 0.360 | 0.370 | 2.55x |
| collatz | 3000000 | 0.589 | 23.318 | 2.379 | 0.634 | n/a | n/a | 1.08x |
| deriv | 10 | 1.258 | 3.067 | 1.122 | 3.935 | 1.166 | 1.307 | 3.13x |
| fannkuch-linear | 10 | 0.259 | 4.737 | n/a | 0.555 | n/a | n/a | 2.14x |
| fannkuch-redux | 10 | 0.722 | 12.686 | n/a | 0.522 | n/a | n/a | 0.72x |
| fasta | 250000 | 0.094 | 0.309 | n/a | 0.047 | n/a | n/a | 0.50x |
| fib | 38 | 0.130 | 3.589 | 0.282 | 0.124 | n/a | n/a | 0.96x |
| harmonic | 200000000 | 0.284 | 6.879 | 0.784 | 0.294 | n/a | n/a | 1.03x |
| k-nucleotide | fasta 250000 | 6.194 | 14.072 | n/a | 0.278 | n/a | n/a | 0.04x |
| mandelbrot | 2000 | 0.297 | 5.384 | 0.519 | 0.302 | n/a | n/a | 1.02x |
| mandelbrot-pbm | 4000 | 1.172 | 23.222 | n/a | 1.187 | n/a | n/a | 1.01x |
| nbody | 5000000 | 0.305 | 5.698 | 1.553 | 0.298 | n/a | n/a | 0.98x |
| nqueens | 13 | 1.023 | 14.859 | 1.211 | 1.303 | 1.076 | 2.422 | 1.27x |
| pidigits | 10000 | 1.165 | 6.235 | n/a | 1.220 | n/a | n/a | 1.05x |
| qsort | 400 | 1.495 | 16.288 | 1.774 | 1.511 | 26.342 | 2.505 | 1.01x |
| rbtree | 4200000 | 1.197 | 2.498 | 5.933 | 1.675 | 0.949 | 2.937 | 1.40x |
| rbtree-ck | 4200000 | 2.837 | 9.149 | 9.354 | 4.532 | 2.157 | 4.851 | 1.60x |
| regex-redux | fasta 250000 | 3.573 | 3.023 | n/a | n/a | n/a | n/a | n/a |
| reverse-complement | fasta 250000 | 0.155 | 0.714 | n/a | 0.013 | n/a | n/a | 0.08x |
| spectral-norm | 5500 | 2.259 | 191.642 | n/a | 1.749 | n/a | n/a | 0.77x |
| spectral-norm-linear | 5500 | 1.752 | 187.927 | n/a | 1.735 | n/a | n/a | 0.99x |
| tak | 18 | 0.124 | 1.386 | 0.173 | 0.130 | n/a | n/a | 1.05x |
| unionfind | 3000000 | 0.174 | 2.351 | 0.345 | 0.134 | 2.313 | 2.271 | 0.77x |

Compiling each program takes 1.9 to 13.7 seconds (idris-mlir, idris-mlir-cc
and the link); fannkuch-redux, regex-redux and spectral-norm are the slow
ones. The C column moved by up to 2x between this run and the one two days
earlier on the same container (rbtree 0.82 s then, 1.68 s now), so a ratio
is read against its own run's C, never against an older table.

Three kinds of program. **Numeric** (ack, ackdyn, collatz, fib, harmonic,
mandelbrot, nbody, tak): Idris over the stock Prelude, whose interfaces,
literals and `show` resolve at compile time and cost nothing. **The
Benchmarks Game** (binary-trees, fannkuch-redux, fasta, k-nucleotide,
mandelbrot-pbm, nbody, pidigits, regex-redux, reverse-complement,
spectral-norm): written as an Idris programmer writes them first, with
lists where the game uses arrays except fannkuch-redux on base's
`IOArray`; regex-redux carries its own small regex engine and has no C
version, so Chez is its only reference; fannkuch-linear and
spectral-norm-linear are the same two programs over `Linear.Array`.
**Counting Immutable Beans' programs** (rbtree, rbtree-ck, cfold, deriv,
nqueens, binary-trees, qsort, unionfind): the Lean 4 and Koka (Perceus)
papers' benchmarks in Idris, with their Lean and Koka sources as the
papers' repositories have them; qsort and unionfind over `Linear.Array`.

### Per program

- **unionfind** (parity with C): path compression threads the array
  through every `find` and gives it back around a non-tail call. Two
  general changes brought it from 1.4x of C to parity: an array value is
  its cell and its length, so a bounds check compares two registers
  instead of loading the length from the cell, a load LLVM cannot hoist
  past the stores into that cell; and a result a function always returns
  as one of its arguments is dropped after lowering, so `find` returns its
  record in registers and the write after the recursion needs no second
  check. Nothing in the compiler knows union-find.
- **fannkuch-linear** at about 2x of C: the work is the same (the same
  permutations and flips, the same scaling from n=9 to n=11); clang turns
  the C's copy and rotate loops into `memcpy` and `memmove` calls into
  musl, once per permutation, on 40 bytes. Built with `-fno-builtin` the
  same C takes 0.21 s against 0.50 s, then 10 to 15% faster than the
  Idris. The C stays as written. The Idris compiles to the loop's loads and
  stores and nothing else.
- **fannkuch-redux** (`IOArray`) against **fannkuch-linear**: the same
  loops. The table's 3x was the simplify loop's, not the program's:
  inlining base's `readArray` and `writeArray` left each index's range
  test nested in the regions of the same test made for the read before
  it, where nothing folded it, so every test doubled the continuation
  after it, the IO binds on the out-of-bounds paths stayed closures built
  and applied, and the loops became code LLVM would not inline (`rev` was
  a thousand lines after the loop, the linear `rev` 33). A match now
  knows the case of an enclosing match on its value (2026-10-02), and
  both compile to the loops' loads and stores: in one run after the
  change, 0.397 s against the linear version's 0.245 s and C's 0.591 s
  (1.49x and 2.42x of C). What remains is base's representation: an
  `IOArray` holds `Maybe elem` cells, an unboxed tag beside each `Int` at
  a stride of 16 bytes, so every read loads and tests a tag and every
  write stores one. The same program over the raw primitive takes the
  same time with Idris's range tests (0.253 s) as without (0.256 s), and
  with the `Maybe` cells alone 0.314 s: the tags are the whole remaining
  gap, the range tests nothing measurable, and `Int` has no spare value
  for `Nothing` that a layout could use. The linear version is filled at
  creation and proved exclusive, so its loops are loads and stores with no
  count changed and nothing allocated (the `linarray-*` and
  `ioarray-fannkuch` fixtures state those properties). There is no
  copying array to turn off: a linear array is mutable by construction on
  every backend. What can be turned off is each compiler mechanism:
- **Ablation.** `idris-mlir-cc --without=STEP,...` (or `--directive
  without=STEP,...` through `idris-mlir`) leaves pipeline steps out, or
  idr-rc's mechanisms (`reuse`, `borrow`, `sink`). fannkuch-linear and
  unionfind, best of 3, each variant compiled and run alone (2026-10-01):

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
  primitive in `unsafePerformIO` and rebuild the record through `Res`
  pairs. Without the simplify loop (inlining, specialization, compile-time
  evaluation, the dialect's canonicalizations) fannkuch-linear takes 23x
  longer and unionfind 9x: that is the compiler's work, not the program's.
  After it, consumer sinking is worth 15% on fannkuch (a dup and a drop per
  swap otherwise), and on unionfind the returned argument 1.45x, reuse and
  the stack 1.3x each, the loops 1.2x; the rest is within the spread.
- **spectral-norm** (lists) and **spectral-norm-linear**: the linear one
  is loads and multiplies at parity with C; the list one rebuilds its lists
  in their own cells and pays for it. The input is the game's 5500.
- **qsort** (parity with C): Koka's own `qsort.kk` takes 20 s on this
  input; it is measured as the Perceus repository has it, for the
  comparison, not as a verdict on Koka.
- **rbtree, rbtree-ck, cfold, deriv, nqueens:** persistent trees and terms
  rebuilt on every step, in the cells of the values that die (reset/reuse),
  as Lean and Koka do, the rest on the stack; the times are Lean's and
  Koka's or better, except rbtree-ck, where Koka is 1.4x faster (it keeps
  the older trees alive, which measures the allocator under a live set).
- **binary-trees:** the C frees through musl's `malloc`; the game's fastest
  C uses a pool. Ours frees each tree as it dies through the runtime's
  allocator, and the bottom level is one static cell.
- **pidigits:** C uses GMP in place; ours allocates a new `mpz` per
  operation and matches it. The in-place form waits for exclusivity on
  bigs.
- **fasta, reverse-complement:** `List Char` where C has byte buffers, and
  input read a character at a time. Before `pack` built its string once
  (idr.str.pack, 2026-10-02) fasta took 0.38 s of which 0.098 s was
  computation and 0.002 s output, the rest a string per character; it now
  takes about its computation, and reverse-complement 2.8x less than
  before. What remains is the list itself: a cons cell per character read.
- **k-nucleotide** (2.3x faster than Chez, 22x slower than C): the
  fragments are counted in a `Data.SortedMap String Int`, which keeps the
  `Ord String` it was built with in the map's constructors. The frontend
  holds that dictionary as a compile-time value of the map's data instance
  (`Frontend.Translate.Dictionaries`), so a lookup compares strings with
  the primitive and the field costs nothing at runtime. What remains is the
  program as written: the sequence is a `List Char`, a `String` is packed
  for each of the 1.75 million fragments counted, and each count rebuilds
  the path of a persistent 2-3 tree, where the C hashes fragments packed
  into integers in place. Best of 3 on 2026-10-02: 6.194 s, Chez 14.072 s,
  clang 0.278 s; the compilation takes 17 s.
- **mandelbrot-pbm** builds each row in a `Buffer` and writes it through
  `System.File`, byte for byte as the C does.

## Caveats

- SML's `int` traps on overflow where Idris's and C's wrap: a check per
  operation for MLton (collatz, fib, tak).
- The SML n-body uses immutable records like the Idris; the C updates an
  array in place. All print the same energies to the last digit.
- `ack` computes `ack 3 n` with `m` a literal: call-pattern specialization
  copies `ack` with `m` fixed and LLVM closes three of the copies, so this
  measures the specialization; `ackdyn` reads `m` from the input and
  measures deep non-tail recursion.
- `fib`: LLVM turns one of the two recursive calls into a loop, for this
  compiler and clang alike.

## Allocation shapes

`foreign/idr/bench/alloc/` benchmarks the heap traffic of the runtime's
allocation patterns; it chose the allocator, and its README has the
results.
