# Benchmarks

`make bench` runs `bench/run.sh`, which builds each program three ways and
runs it on one input (`make bench ARGS='--runs 3 fib tak'` runs fewer):
this compiler on `bench/<name>/Main.idr` (ordinary Idris over the stock
Prelude and base, or over `Linear.Array` of `libs/mlir-linear` where
`bench/<name>/packages` says so); the same source through the stock Chez
backend; and the pinned clang at `-O2` on `bench/c/<name>.c`, linked
as `idris-mlir-cc --print-link-flags` says the target links a program (a
static PIE on musl, a dynamic executable on Darwin), for this
compiler's target CPU without floating-point contraction, as our programs
are built. Every program runs
with the largest stack the system allows: unlimited on Linux, the hard
limit (about 64 MiB) on macOS. Only cfold needs a deep one: its programs
recurse 48 to 56 MiB on x86-64, which fits. The output starts with what it
ran on: the host, its CPU, that stack limit and each compiler's version.

The script checks that the two Idris backends print the same text and that
every program prints the same numbers (to 1e-9), or the same bytes where
the game compares bytes, and reports the best of the runs in wall-clock
seconds, process start included (about a millisecond). The last column is
clang's time over this compiler's: above 1, this compiler is faster.

## Results

The latest record is
[`runs/2026-10-03-861acdc`](runs/2026-10-03-861acdc/results.md): every
program built by every compiler, best of 5 runs, measured on 2026-10-03
at 861acdc on a shared development container (x86-64, 4 CPUs, a Xeon at
2.10 GHz) with LLVM 23.1.2 and Chez Scheme 10.4.1. Its results page holds
the full table, the compile times and the comparison with the record
before it. The macOS record, on the arm64 host, is recorded beside this
one with `make bench ARGS='--record bench/runs/<date>-<rev>-darwin-arm64'`
on that machine.

![This compiler against clang -O2](runs/2026-10-03-861acdc/vs-c.svg)

![This compiler against Idris on Chez Scheme](runs/2026-10-03-861acdc/vs-chez.svg)

![Best time of each compiler](runs/2026-10-03-861acdc/times.svg)

Against clang -O2 this compiler is faster on 10 programs, within 15% on 9
and slower on 6 (fasta, fib, k-nucleotide, reverse-complement,
spectral-norm and unionfind); regex-redux has no C version. Against Idris
on Chez Scheme it is faster on 25 of the 26, from 2.25x (rbtree) to 252x
(ack), and 1.2x slower on regex-redux. Compiling a program takes 1.8 to
11.2 seconds (idris-mlir, idris-mlir-cc and the link); k-nucleotide,
spectral-norm-linear and regex-redux are the slow ones.

Since the record before it (2026-10-02, 903d127): fannkuch-redux went from
0.72x of C to 1.64x (a match knows the case of an enclosing match on its
value), spectral-norm-linear from 0.99x to 1.99x (idr-narrow-lanes' 32-bit
lanes) and reverse-complement from 0.08x to 0.12x; the rest moved within
the spread.

How to read them. The run-to-run spread on this container reaches 15%, so
a ratio within that of 1 is parity. The C column itself moved by up to 2x
between runs on different days (rbtree 0.82 s on one, 1.68 s two days
later), so a ratio is read against its own run's C, and records compare by
those ratios, never by seconds. ack runs in 4 ms: it measures the
specialization (Caveats below), not a loop.

A record is what a run measured, kept: `make bench ARGS='--record
bench/runs/<date>-<revision>'` keeps every timed run (`samples.tsv`), the
compile times and what it ran on (`about`), once every output has agreed.
`bench/report.sh RUN PREVIOUS` makes the results page and the charts from
it, and the table `bench/run.sh` prints is that report's, so the numbers
have one source; `tests/bench/records` checks that every kept record's
results are what the report makes. The first record,
`runs/2026-10-02-903d127`, is the table this file held before, transcribed.

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
nqueens, binary-trees, qsort, unionfind): the Perceus and Lean papers'
benchmarks, written in Idris from the papers' repositories; qsort and
unionfind over `Linear.Array`.

### Per program

- **unionfind** (0.85x of C in the 2026-10-03 record, parity in earlier
  runs): path compression threads the array
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
  (1.49x and 2.42x of C); in the 2026-10-03 record 0.333 s against the
  linear version's 0.250 s and C's 0.546 s. What remains is base's representation: an
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
  is written over `Linear.Array`'s loops over an index space (`generate`,
  `ifoldl`), and idr-vectorize runs each product with A as one loop nest
  computing four rows at a time on AVX2 lanes, each row's sum in index
  order (the C sums in index order too, so clang does not vectorize it).
  The body's index arithmetic is the program's 64-bit `Int`, for which
  x86-64-v3 has no vector multiply nor an int64-to-double conversion: on
  64-bit lanes the inner loop emulates the one (three `vpmuludq`, shifts
  and adds) and scalarizes the other (four `vcvtsi2sd` with the extracts
  and inserts around them), 36 instructions per four rows around the one
  `vdivpd`, which ran at clang's speed. The C computes its indices in
  `int`, for which both instructions exist (`vpmulld`, `vcvtdq2pd`), and
  idr-narrow-lanes gives each row loop a version on 32-bit lanes while n
  is at most 2^14, the bound the analysis of the body's own arithmetic
  finds: 15 instructions per four rows (`vpaddd`, `vpmulld`, a `vpsrad`
  for the `div 2`, `vcvtdq2pd` and the `vdivpd`). Measured at 5500, best
  of 10 interleaved in one session: 0.696 s, against 1.401 s on 64-bit
  lanes and clang's 1.399 s. The 2026-10-03 record shows it in a full run:
  0.874 s against clang's 1.740 s. The list one rebuilds its lists in their own
  cells and pays for it. The input is the game's 5500.
- **qsort** (parity with C): over `Linear.Array`, so the partition writes
  in place.
- **rbtree, rbtree-ck, cfold, deriv, nqueens:** persistent trees and terms
  rebuilt on every step, in the cells of the values that die (reset/reuse),
  as the Perceus and Lean papers' versions do, the rest on the stack.
  rbtree-ck keeps the older trees alive, so it measures the allocator under
  a live set.
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
  before. A line packed only to be written is written as its list is
  walked, without the string (idr.io.put_list, 2026-10-02): about 5% off
  each. What remains is the list itself: a cons cell per character read.
- **k-nucleotide** (2.4x faster than Chez, 18x slower than C): the
  fragments are counted in a `Data.SortedMap String Int`, which keeps the
  `Ord String` it was built with in the map's constructors. The frontend
  holds that dictionary as a compile-time value of the map's data instance
  (`Frontend.Translate.Dictionaries`), so a lookup compares strings with
  the primitive and the field costs nothing at runtime. What remains is the
  program as written: the sequence is a `List Char`, a `String` is packed
  for each of the 1.75 million fragments counted, and each count rebuilds
  the path of a persistent 2-3 tree, where the C hashes fragments packed
  into integers in place. In the 2026-10-03 record: 4.807 s, Chez 11.555
  s, clang 0.260 s; the compilation takes 11 s.
- **mandelbrot-pbm** builds each row in a `Buffer` and writes it through
  `System.File`, byte for byte as the C does.

## Caveats

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
