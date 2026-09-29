# Benchmarks: the Benchmarks Game against idris-mlir, and our hot loops against clang's

Stream "benchmarks". Two parts:

- **Part A.** The ten Computer Language Benchmarks Game (CLBG) programs.
  For each one:
  - what it asks for and what it stresses;
  - what the fastest single-threaded C and Rust do;
  - how an Idris 2 programmer would write it;
  - what our compiler does with that today, measured;
  - which Idris facts could reach or beat C;
  - what is missing;
  - which MLIR machinery should do the heavy lifting.
- **Part B.** The seven numeric benchmarks in `bench/`. I built ours and
  clang's, compared the hot loops instruction by instruction, and traced
  each difference back through `--dump-after=all`.

Raw commands, timings, IR and assembly excerpts, and the MLIR experiments
are in `findings/benchmarks-experiments.md`. Scratch files are in
`scratchpad/research/bm/`:
- `b/` holds the bench copies;
- `k/` holds the CLBG kernels;
- `c/` holds the C baselines;
- `mlir/` holds the upstream-dialect experiments.

This file builds on:
- `architecture.md`: contification, TRMC, LLVM attributes, ackdyn;
- `linear-libs.md`: arrays through One-Shot Bufferize, and why no linear
  library compiles;
- `representation.md`: R5 Fin, R6 closed `Vect`, R12 contiguous `Vect`;
- `facts-ledger.md`: uniqueness, ghosts, size-change.

It does not repeat their arguments.

Status of claims:
- **measured**: I ran it here;
- **read**: a file:line;
- **recalled**: from memory of the CLBG site, which is unreachable from
  this container; treat these as orders of magnitude;
- **conjecture**: my judgment, untested.

## The questions

1. For each CLBG program: the spec, what it stresses, the fastest C and Rust,
   idiomatic Idris (Prelude and base, and contrib/linear), the Idris facts
   that could reach or beat C, what we do today, the missing pieces, and the
   MLIR passes that would do the work.
2. For `bench/`'s nbody, mandelbrot, fib, tak, collatz, ackdyn and harmonic:
   where our hot loops differ from clang's, where each difference comes
   from, and which fact or representation removes it.

## Verdict

- **On the seven numeric benchmarks we are at clang's code, not near it.**
  - fib and tak are byte-identical, and so are the inner loops of collatz
    and mandelbrot (measured).
  - Three differences remain:
    - ackdyn: block layout, 6%;
    - harmonic: a branch where clang unrolled, 0%;
    - nbody: 30 loop-carried scalars spilled, 5%.
  - Each one traces to a representation or a missing fact, not to the
    optimizer.
  - The README's comparison has a flaw, though (**measured**, **read**):
    - it pits our AVX2 code (`--cpu` defaults to `x86-64-v3`,
      `foreign/idr/tools/idris-mlir-cc.cc:99-104`) against clang's SSE2
      code (`bench/run.sh:116` passes no `-march`);
    - on equal ISA, and with `-ffp-contract=off` so that clang may not
      fuse multiply-adds, clang is 5% ahead on nbody. That flag matters
      because our target options are `FPOpFusion::Strict`
      (`Lower/Target.cc:9`) and the results must match Chez to the bit.
- **On the Benchmarks Game, the heap and the I/O decide, and today we
  mostly cannot play.** Of the ten programs:
  - three compile idiomatically and run (binary-trees, pidigits, fasta);
  - three compile at small sizes but overflow the stack at benchmark sizes
    (fannkuch-redux, reverse-complement, regex-redux);
  - two run at C's speed only in their numeric core (mandelbrot, n-body);
  - one runs 56x slower than C (spectral-norm on lists);
  - one is rejected outright (k-nucleotide);
  - every array formulation is rejected (`IOArray`, `Buffer`, `IORef`,
    `LinArray`, `Vect n` with a runtime `n`).
- **One bug:** `putChar` diverges from Chez for characters 128–255
  (**measured**).
  - We write UTF-8 (`runtime/io.cc:121-124`), while the primitive is
    `C:putchar` (`Registry/Primitives.idr:70`) and Chez writes one byte.
  - So mandelbrot's PBM output differs from both Chez's and C's.
  - The Chez diff in the tests never prints such a character, so it does
    not catch this.
- **The global maximum is reachable with upstream MLIR, and it beats clang
  at bit-identical results.** I measured two upstream-only experiments:
  - **n-body.** Five bodies as structure-of-arrays `vector<8xf64>`, with
    each body's updates kept in the program's order: **1.36x faster than
    clang -O2 and than us**, and the energies are identical to the last
    digit.
  - **spectral-norm.** `linalg.generic`, tiled and vectorized over the
    parallel dimension, then `loop-invariant-subset-hoisting`,
    `arith-int-range-narrowing` and One-Shot Bufferize: **1.7x faster
    than clang -O2**, with the same digits.

  Both use only facts Idris proves: closed indices, purity and totality,
  ranges, and uniqueness of the output. harmonic is the counterexample.
  Its time is set by the in-order `addsd` chain, which Idris's
  floating-point semantics forbid reassociating. The vectorized form with
  ordered reductions is exact but no faster, so harmonic is at its floor.

---

## Part A. The ten CLBG programs

### The table

"Ours" is the measured state of an idiomatic Idris program over Prelude and
base. "C" is the same algorithm in C, built with the pinned clang
`-O2 -march=x86-64-v3` (plus `-ffp-contract=off` where there is floating
point), single-threaded, measured here. The "fastest C/Rust" column is
**recalled**.

| # | program | stresses | fastest C / Rust (recalled) | ours today (measured) | Idris facts that reach or beat C | missing | MLIR doing the work |
|---|---|---|---|---|---|---|---|
| 1 | binary-trees | allocation and freeing of short-lived trees; a long-lived tree beside them | a memory pool per tree (apr_pools; Rust: typed arena/bumpalo), freed at once, parallel over depths | **compiles**: depth 21 in 9.25 s, against C with a pool 4.73 s, C with musl malloc 36.4 s and Chez 56.4 s. The bottom level `Node Leaf Leaf` is one static cell (`make` in `01-idr-simplify`), so we allocate half the nodes C does | `make d` is fresh and unique, `check` borrows it, and it dies right after (`idr.dec` after the call): its **lifetime is one loop iteration**, which is a region. `check ∘ make` is total and pure, so it fuses to arithmetic with no allocation at all (legal Idris; the CLBG rules forbid it) | a region or arena for cells that die together; uniqueness types to free a whole tree without walking its counts | none upstream for regions of cells. It is our residue: idr-stack's escape lattice, grown to "escapes the iteration, not the loop" (architecture.md I.2) |
| 2 | fannkuch-redux | small permutations: prefix reversal and rotation, max flips and a checksum | permutation index to permutation (factorial base), flips by one SIMD byte shuffle (`pshufb`) per flip with a mask table, parallel blocks | **lists**: n=8 in 0.193 s, against C 0.020 s and Chez 0.35 s; **n≥9 segfaults** (stack: non-tail `concatMap`/`filter`). **IOArray**: rejected, `unsupported (escape hatch): %extern Data.IOArray.Prims.prim__newArray` | `Vect n (Fin n)` with n ≤ 16 closed: elements < 16, so **i8, and the whole permutation is one `vector<16xi8>` register**. Linearity plus uniqueness give in-place updates. `Fin` bounds remove the checks | arrays (linear-libs.md §4.2); R6 closed Vect as a vector; a dynamic byte shuffle | `tensor` → One-Shot Bufferize for the array formulation (linear-libs e3: in place, C's machine code); `vector.shuffle` for static rotations. **Residue:** the vector dialect has no dynamic shuffle and the X86 dialect no `pshufb` (read: `include/mlir/Dialect/X86/`, `VectorOps.td`) |
| 3 | fasta | an LCG, cumulative-probability lookup, 60-column line output (I/O bound) | a lookup table from the random value to the symbol, block `fwrite`; threads generate ahead | **compiles** (after two rewrites: `strIndex` is not covering, and `assert_total` is rejected). n=250k in 1.11 s against C 0.25 s (4.5x); output **byte-identical** to C | the seed is in `[0, 139968)` (range after `mod`); `pick t (cast s / 139968.0)` is pure and total over that finite domain, so **tabulate it at compile time** (compile-time evaluation producing a table: control flow as data). `putStrLn (pack cs)` builds a list and a string per line, to be fused into writes to a unique output buffer | byte output; list → string → write fusion; finite-domain tabulation | `IntegerRangeAnalysis` for the domain; `idr-eval` builds the table as a `dense<>` constant; output as `memref<?xi8>` |
| 4 | k-nucleotide | a hash table of k-mer counts, k = 1, 2, 3, 4, 6, 12, 18 | 2-bit packed keys in a uint64, open-addressing hash (khash; Rust: hashbrown), one table per k in parallel | **rejected**: `Data.SortedMap.Dependent.lookup: unsupported (runtime closure): an implementation chosen at runtime`. Also rejected: `getLine` (`%foreign Prelude.IO.prim__getStr`), `System.File` (not trusted), `fastConcat` (`%foreign`) | a 4-constructor enum is 2 bits; `Vect k Nucleotide` with a closed k ≤ 32 is a **packed `i64` key**; the map is unique, so updates are in place; the `Ord` dictionary stored in `SortedMap` is a **constant field** (always the one passed to `empty`) | constant propagation of data fields (MLton's `constantPropagation`, architecture.md §3.1); stdin line input; a hash table | **residue**: MLIR has no hash table; a runtime primitive with a registry meaning. Keys through `arith`; ranges for packing |
| 5 | mandelbrot (PBM) | floating-point iteration, 8 pixels per output byte | 8 pixels at once in SIMD, the escape test every 8 iterations, rows in parallel | **compiles**: 4000² in 2.36 s against the same scalar C 2.24 s. **Output differs from Chez and C** (the `putChar` bug) | `escapes` is pure and total, so the 8 calls in a byte are independent: **vectorize across lanes, exact per lane**, with the escape as a lane mask | the putChar fix; byte output; a lane-vectorized `escapes` | `scf.while` over `vector<8xf64>` with `vector.reduction <or>` of the mask for exit; the lanes are exact (no reassociation) |
| 6 | n-body | 5 bodies, 10 pairs, `sqrt` and divide per pair, a serial time loop | SSE/AVX over the 10 pairs, with `rsqrtps` plus Newton steps in place of `sqrt`/`div` (not bit-exact) | **records** (`bench/nbody`): 0.326 s against clang -O2 at x86-64-v3 0.311 s. **`Vect 5 Body` + `Fin 5` pairs**: 10.56 s, **32x slower** (Fin is `!idr.big`, the Vect is a list of boxes, `index` walks with `big.pred`) | a closed `Vect 5` of records is **SoA `vector<8xf64>` per field** (R6); each body's velocity updates happen in pair order, and that order is the same across bodies in 4 rounds, so **exact** vectorization exists. Measured: 0.232 s, **1.36x over clang**, energies bit-identical | R5 (`Fin n` as index), R6 (closed Vect as vector), unrolling folds over static lists (`pairs` stays a runtime list) | `vector` ops, `vector.shuffle` for the pair gathers, `math.sqrt` on vectors; the fastest C's `rsqrt` is off-limits (Chez equality) |
| 7 | pidigits | bignum arithmetic (GMP), a digit spigot | GMP `mpz` in place, one division per digit (remainder trick) | **compiles**: 10,000 digits in 2.32 s against my C with GMP over musl malloc 5.31 s (our GMP allocates through snmalloc, `runtime/gmp.cc:31`); identical output. Every `idr.big.*` op allocates a new mpz | the operands are dead after each step (**unique**), so update the mpz in place (`mpz_mul_ui(q,q,10)`); `q*x + r` fuses to `mpz_addmul` | uniqueness types on `!idr.big`; `_owned` runtime entry points that reuse a dead operand | `!idr.uniq<!idr.big>` (facts-ledger #1) via the DataFlow solver; patterns for fused big ops |
| 8 | regex-redux | a regex engine over about 50 MB | PCRE2 with JIT; Rust's `regex` (lazy DFA) | **no regex library** in base/contrib (`Text.Lexer` is a lexer toolkit). A hand-written matcher compiles; 100 KB in 0.063 s; **2.5 MB segfaults** (stack), where Chez takes 1.85 s | the regexes are **static data**: specializing an Idris regex interpreter on them (first Futamura projection, with `idr-eval` plus `idr-specialize`) yields a DFA at compile time where PCRE JITs at runtime (conjecture) | TRMC (stack); a regex library in Idris; I/O | our specializer (the residue); scf for the DFA loop |
| 9 | reverse-complement | stream about 250 MB: reverse and complement each record, 60-column output | read everything, table lookup, reverse in place with SIMD shuffles | **compiles**: 100 KB in 0.096 s, against Chez 0.30 s, identical output; **2.5 MB segfaults** (non-tail `map`, `splitAt`, `++`) | the input buffer is **unique**, so reverse in place; complement is total on a finite domain, so a 256-entry table | TRMC; a byte buffer type; stdin | `memref<?xi8>` with bufferization; a `linalg.generic` with a reversing indexing map (open: the vectorizer needs projected permutations) |
| 10 | spectral-norm | O(n²) matrix-vector products, a division per element | vectorize over i (2 or 4 lanes), keeping each lane's sum order; rows in parallel | **lists**: n=1000 in 3.10 s against C 0.055 s (**56x**) and Chez 15.5 s. **`Vect n` with a runtime n**: rejected (`an implementation chosen at runtime`). **IOArray**: rejected | `A` is pure and total; i and j are `Fin n` (**range**, so i32 is enough); the output vector is **fresh and unique** (in place); each lane keeps Idris's order. Measured: **1.7x faster than clang -O2**, same digits | arrays; recognizing `sum (zipWith …)` over `[0..n-1]` as a reduction | `linalg.generic` → `tile_using_for` → `structured.vectorize` → `loop-invariant-subset-hoisting` → `int-range-optimizations` + `arith-int-range-narrowing` → One-Shot Bufferize |

### What the table says about the representation

Where we reach C, the representation is right:
- scalars in registers;
- records unboxed;
- closed calls evaluated at compile time.

Where we are orders of magnitude off, a representation is missing:
- no array: fannkuch, spectral, k-nucleotide, reverse-complement;
- `Fin` as a big and `Vect` as boxes: `Vect` n-body, 32x;
- no destination-passing for constructor-building recursion: the stack
  overflows;
- no byte buffer: fasta, reverse-complement, mandelbrot output.

No optimizer change touches these; every one of them is a type the
Idris side must choose. That is the principle document's claim, measured
ten times.

### Per-benchmark notes

What the table cannot hold.

**1. binary-trees.**
- **Spec.** Depth `max 6 n`. Build a stretch tree of depth +1 and check
  it. Keep a long-lived tree. For each depth d = 4, 6, …, n, build and
  check 2^(n−d+4) trees. Check counts the nodes.
- **Idiomatic Idris** is the ADT `Leaf | Node Tree Tree` shown in the
  experiments. With contrib/linear:
  - `LList`-style linear trees make `check` consuming;
  - but no linear library compiles today (linear-libs.md, "Answers in
    brief").
- **Ours, cost per node:**
  - the allocation fast path is inlined snmalloc, about 12 instructions,
    plus the `incq %fs:-0x10` live-cell counter (`Main.make` disassembly);
  - `check` is a borrowed recursion;
  - `idr.dec` frees through the recursive `release`.
- **Global maximum.**
  - Cells whose lifetime is one iteration of `iter` are allocated from
    that iteration's region and released by resetting it.
  - Idris supplies the facts: the result of `make` is fresh (the only
    producer is `idr.con`), `check` is borrowed, and the tree is dropped
    at a known point.
  - This is Tofte–Talpin region inference restricted to what uniqueness
    proves, and it is our residue: MLIR's ownership-based deallocation is
    for memrefs, not for trees of cells.
  - Fusion of `check ∘ make` goes further and is sound because both are
    total and pure. The CLBG rules would forbid it; a program that is not
    a benchmark would get it.

**2. fannkuch-redux.**
- **Spec.** Over all permutations of 1..n (n = 12):
  - flip the first `perm[0]` elements until the first element is 1;
  - report the maximum flip count and the alternating checksum;
  - enumerate in the order given by rotation counts.
- **Idiomatic Idris** is lists (`splitAt`, `reverse`, `++`) or
  `Data.IOArray`. The list version fails from n = 9 with a segfault (stack
  overflow in the non-tail list builders), which is the TRMC gap measured
  in architecture.md. The `IOArray` version is rejected at
  `prim__newArray`.
- **Representation.** The permutation type `Vect n (Fin n)` carries both
  facts a SIMD programmer uses:
  - every element is below n ≤ 16;
  - the length is closed.

  Hence `vector<16xi8>`: one register holds the permutation, and a flip is
  one shuffle.
- **Control flow as data.** The 16 flip masks are a table indexed by
  `perm[0]`, the fastest C's `pshufb` table.
- **MLIR gap.** `vector.shuffle` takes a static mask only, and the pinned
  tree has no `pshufb` in the X86 dialect. A `scf.index_switch` over 16
  static shuffles is expressible but branches unpredictably
  (conjecture: slower than `pshufb`). This is an upstream gap worth a
  report.

**3. fasta.**
- **Byte-identical.** Our output matches C byte for byte, the LCG's
  floating point included (**measured**).
- **Where the 4.5x goes** (conjecture, from the IR shape):
  - `randomLine` builds a `List Char` of 60 cells, `pack` copies it, and
    `putStrLn` writes it;
  - C writes into a line buffer.
- **The representation fix** is a unique byte buffer that `pack`'s
  consumer fills in place (deforestation of `List Char` into the write).
- **Finite-domain tabulation** is the Idris-only lever. `pick t` composed
  with the scaling is total and pure over the 139,968 values the seed can
  take. With the range known (`mod` gives it), `idr-eval` can run it on
  every value and emit a `dense<…> : tensor<139968xi8>` table; a pick is
  then one load.
  - No C compiler does this: it would have to prove the domain and the
    purity.
  - Conjecture on payoff: `pick` is a 4–15-step compare chain per
    character.

**4. k-nucleotide.**
- **The blocking rejection.** `Data.SortedMap` stores its `Ord` implementation in the map
  value, so every `lookup` reads the dictionary from data. It is
  "an implementation chosen at runtime" to our frontend.
  - Idris knows more: every map is built from `empty`, and `insert`
    passes the dictionary through unchanged.
  - A constant-field analysis (a field whose value is the same at every
    construction site) turns it into a static call. This is MLton's
    constant propagation for data (architecture.md §3.1, "missing").
- **The same rejection hits `Vect n` with a runtime n** (the spectral
  experiment `vn/`): the `Foldable (Vect n)` dictionary is built at
  runtime.
- **I/O.** Only `getChar` is admitted for input. It returns `'\255'` at
  end of file, on Chez as on ours (measured).

**5. mandelbrot.**
- **Ours matches the bench loop.** With PBM output, the escape loop is
  bench/mandelbrot's, and it is clang's to the instruction (Part B).
- **The putChar bug** is the finding here:
  - `putChar (chr 200)` writes `c3 88` with us and `c8` with Chez;
  - `putStr (pack [chr 201])` writes `c3 89` on both (**measured**).
  - The primitive is registered as `C:putchar`
    (`Registry/Primitives.idr:70-71`), whose meaning is one byte, but the
    runtime encodes UTF-8 (`runtime/io.cc:121-124`).
  - By AGENTS.md this is a silent miscompile. Fix it to Chez's meaning,
    and extend the Chez diff with a character above 127.
- **Beyond C -O2.** Vectorize `escapes` across the 8 pixels of a byte,
  exact per lane, with "all lanes escaped or 50 iterations" as the exit.
  - The Idris facts are purity and totality: the 8 calls are
    independent, and running a lane past its escape changes no result.
  - Upstream MLIR has no pass that vectorizes calls (no `declare simd`).
    The form is a representation decision on the Idris side: `byte`'s
    fold over `k` becomes a `vector<8xf64>` computation.
  - Conjecture.

**6. n-body.**
- **The measured gap between two Idris programs is the thesis.**
  - The same physics with records runs 0.326 s.
  - With `Vect 5 Body` and `Fin 5` it runs 10.56 s (32x).
- **The `Vect` version's IR** (`k/nbv/dump/06-idr-tail-loops.mlir`):
  - `Data.Vect.index[Main.Body]` takes a `!idr.big` and loops over
    `idr.big.pred`;
  - the `Vect` is `!idr.box<@Data.Vect.Vect[[__], Main.Body]>` (the 5 is
    erased);
  - `foldl` walks the static `pairs` list at runtime, with `idr.inc` on
    the bigs.
- **Four missing pieces:**
  - R5, `Fin 5` as `index` in [0,5);
  - R6, `Vect 5 Body` as a value;
  - known-constructor over static data, so that the fold over `pairs`
    unrolls;
  - uniqueness for `replaceAt`.
- **The global maximum.** SoA vectors, with the update order kept per
  lane. Measured 1.36x over clang, bit-identical (Part B §nbody, and the
  experiments file).

**7. pidigits.**
- **Allocator.** Our time beats my musl C because of the allocator, not
  the code. Against the fastest C (recalled: about 0.6 s at 10,000 digits
  with glibc) we are about 4x behind.
- **The two levers are Idris facts:**
  - the dead-operand reuse that uniqueness proves;
  - fusing `q * x + r` into one GMP call.

**8. regex-redux.**
- **Spec.** Count matches of 9 alternation patterns, then apply 5
  substitutions to the whole input (about 50 MB). It stresses the regex
  engine.
- **No regex engine exists** in Idris's Prelude, base or contrib. An Idris
  programmer writes a small backtracking matcher or uses `Text.Lexer`.
- **Where this could beat PCRE's JIT.** The regexes are closed values.
  `idr-eval` plus `idr-specialize` on `match (compile re)` could produce a
  specialized automaton at compile time.
  - This is the only CLBG program where compile-time evaluation is the
    main lever.
  - Conjecture; it depends on the specializer's budgets.

**9. reverse-complement.**
- **Idiomatic Idris** accumulates each record as a reversed `List Char`
  and prints 60-column lines; the output is identical to Chez's.
- **What fails at benchmark size:** the non-tail `map comp`, `splitAt`
  and `++` over 2.5 M-element lists overflow the stack.
- **The representation fix** is a unique byte buffer: `memref<?xi8>`, with
  an in-place two-pointer swap-and-complement loop.

**10. spectral-norm.**
- **Spec.** `A(i,j) = 1/((i+j)(i+j+1)/2 + i + 1)`. Ten rounds of
  `u = AᵀA v`, `v = AᵀA u`, then `sqrt(u·v / v·v)`.
- **Idiomatic Idris** is the list version in the experiments (3.1 s at
  n=1000, 56x clang). It cannot be written over an array that we accept.
- **The MLIR experiment**:
  - it is the global maximum's array stage, written in upstream dialects
    only;
  - the result is bit-identical (`1.2742241481294836`, the same as C and
    Chez);
  - it is 1.7x faster than clang -O2 at x86-64-v3;
  - it went through five stages:

| stage | what it adds | time n=1000 |
|---|---|---|
| clang -O2 -march=x86-64-v3 | scalar; the j-reduction is sequential | 0.055 s |
| linalg tile [4,1] + vectorize + subset hoisting + bufferize | 4 lanes over i, j sequential per lane, `vdivpd ymm` | 0.064 s |
| + `int-range-optimizations`, `arith-int-range-narrowing{32}` | i64 index math → i32 (`vpmulld`, not scalarized) | 0.067 s (with a runtime transpose flag) |
| + the transpose flag specialized (two functions, as Idris writes `mulAv`/`mulAtv`) | the index math simplifies | **0.032 s** |

Every step is an upstream pass fed by one Idris fact:
- **order** kept per lane, because the dimension is parallel;
- **range**: `Fin n` and the loop bounds give i32;
- **uniqueness** of the output, so bufferization is in place;
- **specialization**: our own specializer, on a known argument.

Clang cannot vectorize this loop. The only vectorizable dimension is the
outer one, and LLVM's loop vectorizer is inner-loop only, while the inner
reduction would need reassociation.

### contrib/linear in this suite

linear-libs.md established that no linear library compiles. I did not redo
that. Nothing in the CLBG suite needs `LList`/`LVect`. What it needs is
linear *arrays*: fannkuch, spectral-norm, reverse-complement and
k-nucleotide's table. Per decision-linear-libraries.md they come from the
compiler proving uniqueness on `tensor`, not from a library.

---

## Part B. The seven bench programs, instruction by instruction

Setup (**measured**, best of 7, seconds):
- ours is `tools/compile.sh --io` in a scratch copy, which gives
  x86-64-v3 and LLVM O3;
- clang is the pinned clang with `bench/c/*.c`, built two ways:
  - `-O2` as `bench/run.sh` builds it (generic x86-64);
  - `-O2 -march=x86-64-v3 -ffp-contract=off`, the equal-ISA and equal-FP
    baseline.

| benchmark | ours | clang -O2 (bench/run.sh) | clang -O2 -march=x86-64-v3 -ffp-contract=off | hot-loop comparison |
|---|---:|---:|---:|---|
| nbody | 0.326 | 0.329 | **0.311** | different: ours is fully unrolled scalar, 489 insns/step with 176 stack references; clang keeps a pair loop over memory, 2-wide SLP, about 420 dynamic insns/step |
| mandelbrot | 0.346 | 0.378 | 0.358 | **identical** inner loop (22 insns per 2 iterations, unrolled 2x), modulo registers |
| fib | 0.114 | 0.114 | 0.113 | **identical** function body |
| tak | 0.119 | 0.119 | 0.119 | **identical** function body |
| collatz | 0.477 | 0.473 | 0.467 | **identical** inner loop (9 insns); our outer loop is unrolled 2x (O3 against O2) |
| ackdyn | 0.179 | 0.174 | 0.169 | same instructions; **block layout** differs |
| harmonic | 0.257 | 0.263 | 0.260 | ours: 1 iteration per trip with a parity branch; clang: unrolled 2x with parity folded |

With `-ffp-contract=on` (clang's C default) and `-march=x86-64-v3`, clang's
nbody runs 0.269 s but prints `-0.16908313397885641` instead of
`…92985`. FMA changes the answer, so FMA is not ours to use, and the fair
baseline is `-ffp-contract=off`.

### The differences, traced

**nbody (5%). 30 loop-carried doubles spill.**
- **The trace:**
  - `06-idr-tail-loops.mlir`: `Main.run` is an `scf.while` carrying
    `!idr.data<@Main.System>`, whose body reads 35 `idr.field`s and
    rebuilds five `idr.con @Main.Body` and one `@Main.System`;
  - `07-idr-lower` makes these LLVM structs, which SROA scalarizes;
  - the masses fold to constants: `offset initial` was evaluated at
    compile time, so the loop-carried mass fields are invariant, and the
    `vmulsd` use constant-pool operands;
  - that leaves 30 live doubles against 16 xmm registers. The result is
    158 `vmovsd`, of which 176 instructions touch `%rsp`.
- **clang instead:**
  - keeps `bs[5]` in memory, loops over pairs (not unrolled), and forms
    2-wide `vsubpd`/`vmulpd` on (x, y);
  - the SLP vectorizer does not fire on our straight-line SSA form: no
    `vmulpd` appears in ours.
- **What removes it:**
  - not a better spill heuristic, but the representation;
  - `MkSystem` holds five same-typed records, which is `Vect 5 Body`, a
    closed index (R6);
  - SoA gives one `vector<8xf64>` per varying field;
  - the per-body update order is the pair order, so the program runs in
    4 rounds of lane-wise ops with a select between the `a` and `b` roles.
- **Measured:** 0.232 s against 0.311 and 0.326, energies identical, 3
  `vsqrtpd` + 3 `vdivpd` in place of 10 + 10 scalar ones, 330
  instructions per step.
- **Clang's rsqrt route is unavailable** at bit-exactness, so this is the
  ceiling I can see (conjecture).

**ackdyn (6%). Branch layout, from a missing weight.**
- **The trace:**
  - `06-idr-tail-loops.mlir`: `Main.ack` is `scf.while { idr.may_loop;
    match_lit m {0 → …; default → match_lit n {0 → …; default → call}}}`;
  - `ackdyn.pre.ll`: `switch i64 %4, label %8 [0, label %6]` twice, with
    no `!prof`. Lowering emits no branch weights (grep of `Lower/*.cc`:
    none).
- **The layouts.** LLVM puts the `n == 0` block on the fall-through path
  inside the loop (`test; jne <call>`), while clang falls through to the
  call.
- **Proof it is layout:** C with `__builtin_expect(n == 0, 1)` produces
  our layout and runs 0.183 s; with `expect(…, 0)` it runs 0.171 s. Ours
  runs 0.178 s.
- **The fact.** Size-change says the recursive case descends and the base
  case ends a descent, so the base case is taken once per chain: "the
  recursive branch is likely".
- **The mechanism is MLIR's:**
  - `idr.match`/`match_lit` implement `WeightedRegionBranchOpInterface`
    (`ControlFlowInterfaces.td:575`);
  - lowering carries the weights to `cf.cond_br`/`cf.switch`
    (`WeightedBranchOpInterface`, `ControlFlowOps.td:119`) and on to
    LLVM `!prof`.
  - architecture.md §4 listed branch weights as "conjecture; measure
    first". This is that measurement.
- **`llvm.sideeffect`** (`Lower/Runtime.cc:106-109`, because `ack` on
  `Int` is partial) costs no instruction here.

**harmonic (0%). The loop is formed by LLVM, not by MLIR.**
- **The trace.** After `01-idr-simplify`, `Main.series` calls
  `case block 831 in series` from both arms of a `match_lit`, passing a
  `Bool` constant, and the case block calls `series` back.
  - The case block is never inlined: the inliner's A→B→A refusal
    (architecture.md §3.1).
  - `idr-tail-loops` cannot form a loop over two functions, so
    `06-idr-tail-loops.mlir` has no `scf.while` in `series`.
  - LLVM's inliner and tail-call elimination make the loop at O3.
- **The alternating `a ± x`:**
  - ours stays a branch (`testb $1,%al; jne`);
  - clang unrolled by 2 and folded the parity.
- **Why it costs nothing:** both are bound by the 4-cycle `vaddsd` chain
  (200M iterations × 4 cycles ≈ 0.26 s).
- **What removes the structural difference:** case blocks emitted as
  continuations (architecture.md, path step 2). The loop then exists in
  MLIR, and `scf.for` uplift can read its trip count.
- **Not faster, even vectorized** (**measured**): `vdivpd ymm` over 4
  i's with two *ordered* `vector.reduction <add>` (no `reassoc`) is
  bit-identical, and `convert-vector-to-llvm` keeps fadd reductions
  ordered unless `reassociate-fp-reductions` is set
  (`ConvertVectorToLLVM.cpp:887`). It runs 0.385 s:
  - `sitofp` of `vector<4xi64>` is scalarized on AVX2;
  - the in-order chain remains.
- **The floor.** Only reassociation beats it, and Idris's semantics (the
  Chez diff) forbid it.

**collatz, mandelbrot, fib, tak: nothing to remove.**
- The hot loops are clang's, instruction for instruction (experiments
  file). The remaining differences are outside the hot loops:
  - our buffered `read`/`write` input and output against `getchar` and
    `printf`;
  - O3's 2x outer unroll in collatz.
- The Idris facts at work are the ones already used:
  - `Int` wraps, so plain `add` (no `nsw` needed);
  - `mod 2 == 0` becomes `testb $1`;
  - `div 2` on the even branch becomes `sarq` alone. LLVM proves
    evenness from the branch, as in C.

### What Part B says

- **Scalar code is done.** On scalar-register code, MLIR plus LLVM O3
  already gives clang's code. Further gains on these seven come from:
  - one fact LLVM lacks: branch weights from size-change;
  - one representation: SoA vectors for n-body.
- **Nothing is left in the optimizer's control flow.** That matches
  architecture.md's verdict that the outer frame is right.
- **The bench harness should compile C as we compile Idris:**
  `-march=x86-64-v3 -ffp-contract=off`. Otherwise the README credits the
  ISA to the compiler (mandelbrot 0.346 against 0.378 generic, but 0.358
  at equal ISA).

---

## The global maximum for this suite, and the path

**The target.**
- **Faithful.** Every CLBG program, written as an Idris programmer writes
  it (Prelude, base, `Data.Vect`, and arrays whose uniqueness the
  compiler proves), compiles to an executable whose output is
  byte-identical to Chez's.
- **As fast as the fastest single-threaded C that keeps the same
  floating-point semantics**, and faster where Idris proves what C
  cannot:
  - closed indices become registers (n-body, fannkuch);
  - finite domains become tables (fasta);
  - the lifetimes of fresh values become regions (binary-trees);
  - static data becomes specialized code (regex).
- **Upstream does the heavy lifting**, on the representations the Idris
  side chooses:
  - `tensor`, `linalg`, `vector`, bufferization and ownership-based
    deallocation;
  - `IntegerRangeAnalysis` and narrowing;
  - weighted branches.
- **Home-rolled residue:**
  - regions for cells;
  - a hash-table primitive;
  - finite-domain tabulation (an `idr-eval` client);
  - a dynamic byte shuffle, as an upstream report.

### Ranked work list

Ranked by programs unblocked times payoff, measured where possible. Each
names the fact or representation, and what it deletes.

1. **Fix `putChar` to Chez's meaning** (bug). Add a character above 127
   to the Chez diff. This unblocks correct mandelbrot output, and costs
   nothing.
2. **Arrays on tensor → bufferization → memref** (linear-libs.md §4.2
   steps 2–4):
   - registry meanings for `prim__newArray`/`arrayGet`/`arraySet` and the
     `Buffer` primitives;
   - `tensor` plus the in-place check for unique arrays.

   Unblocks fannkuch, spectral-norm, reverse-complement and k-nucleotide's
   table, and makes fasta's output buffer possible: **5 of 10 programs**.
3. **Destination-passing (TRMC)** for constructor-building non-tail
   recursion (architecture.md §3.2). Removes the segfaults measured here
   in fannkuch (n ≥ 9), reverse-complement and regex-redux (2.5 MB).
   These are silent crashes: until it lands, reject such recursion with an
   explicit `unsupported` rather than overflow.
4. **Input and output primitives.** `getLine`/`fGetLine` on stdin
   (`prim__getStr`), trusting `System.File`'s stdin subset, `fastConcat`,
   and byte output. Unblocks k-nucleotide, reverse-complement and
   regex-redux as written, and removes `List Char` I/O from fasta.
5. **R5 + R6: `Fin n` as a ranged index, closed `Vect` as a value or
   vector, known-constructor over static lists.** `Vect` n-body goes from
   32x slower to parity. With SoA vectors, 1.36x *faster* than clang
   (measured). This also gives fannkuch's `vector<16xi8>`.
6. **Vectorize the parallel dimension, keeping each lane's floating-point
   order.** Raise the recursion schemes of `Data.Vect`/arrays to
   `linalg.generic`, then tile, vectorize, `loop-invariant-subset-hoisting`,
   narrow with `IntegerRangeAnalysis`, and bufferize. spectral-norm is
   1.7x over clang (measured); mandelbrot's lanes are the same idea.
   Deletes nothing of ours; adds nothing of ours beyond the raising.
7. **Constant fields of data** (dictionaries stored in values). Unblocks
   `SortedMap`, so k-nucleotide compiles, and `Vect n` with a runtime n
   under interfaces. MLton's constant propagation over the shape lattice
   (architecture.md I.2), not a new engine.
8. **Uniqueness as a type on big and cells** (facts-ledger #1):
   - in-place `mpz` for pidigits (about 4x to the fastest C);
   - iteration regions for binary-trees (2x to pool C).
9. **Branch weights from size-change** through
   `WeightedRegionBranchOpInterface`: ackdyn's 6% (measured cause).
10. **Case blocks as continuations** (architecture.md step 2): harmonic's
    loop in MLIR, and `scf.for` uplift.
11. **Finite-domain tabulation** in `idr-eval`: fasta's `pick`
    (conjecture on payoff).
12. **Bench hygiene.** Compile `bench/c` with `-march=x86-64-v3
    -ffp-contract=off`. Report equal-ISA numbers in the README.

---

## Open questions

- **Dynamic shuffles.**
  - Should the vector dialect grow a dynamic shuffle, lowered to
    `pshufb`/`vpermb`/`tbl`? That is the upstream report for fannkuch's
    representation.
  - Until then, is a `scf.index_switch` over static shuffles acceptable?
- **Lane-vectorizing a pure total function** (mandelbrot's `escapes`).
  Upstream has no call vectorizer. Is recognition of "a fold of k
  independent calls" a representation decision on the Idris side (a
  `Vect 8` of lanes), or a pass?
- **Regions for cells.** Where does "dies within the iteration" live as a
  type, so that the verifier checks it? A frame cell (`!idr.cell`) scoped
  to a loop body, as `AutomaticAllocationScope` scopes `alloca`?
- **Finite-domain tabulation.** When does a table beat the code? The
  domain size, the code's cost and the cache footprint decide. Is there
  an MLIR cost model to reuse?
- **CLBG legality versus Idris legality.** Fusion of `check ∘ make` and
  compile-time tables are legal Idris and against the spirit of the CLBG
  rules. Do we report both numbers?
- **Beyond one thread.** CLBG's fastest entries are parallel. Idris's
  purity and totality make `map` over independent work parallelizable
  (`scf.forall`, the async dialect), but that is outside this brief.
