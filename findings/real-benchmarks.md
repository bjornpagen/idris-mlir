# Real benchmarks: beating Lean and Koka on their own programs

Stream "real-benchmarks". The programs this stream wrote are quoted in full
in `real-benchmarks-programs.md`. The scripts, raw result files and builds
are in `scratchpad/research/real-benchmarks/`:
- `cpu.sh` does interleaved timing;
- `dyn2.sh` counts runtime entries through gdb;
- `cg.sh` counts callgrind calls for Koka, Lean and C;
- the `results-*` files hold the raw results.

This file builds on `uniqueness-pipeline.md` (defects D1 to D4 in reuse
placement, and uniqueness inference on DataFlow), `representation.md` (R1
to R14) and `decision-nat.md`, and does not repeat them. It adds:
- the benchmark-level numbers against Koka and Lean;
- what each program needs;
- the suite that should gate the work.

## The questions

1. On the Perceus and Counting Immutable Beans programs, how do we compare
   with Koka, Lean, MLton, C and Chez today? That covers time, memory, and
   allocation and reuse per operation.
2. For each program: what does it stress, which Idris fact could make us
   win, and what is missing?
3. What do FP²'s fully-in-place (fip) programs add?
4. Which 10 to 15 programs should form the real-programs suite, each with
   a claim that can be checked? And what does `bench/` need to run it
   routinely?

## The answer in one page

**At HEAD, nothing can be measured.** Other agents are changing the
ownership passes and Nat right now, and no toolchain in the tree is
consistent.

- At `a886f5c` (01:52 UTC) the shared build's `idris-mlir-cc` dated from
  21:15, but the runtime archive had just been rebuilt. Every program
  failed with `runtime member start.cc.o defines the appending global
  llvm.global.annotations`.
- At `de2fc32` (02:28) `idris-mlir-cc` had been relinked (02:27), but the
  frontend `compiler/build/exec/idris-mlir` still dated from 00:46. Every
  program failed with `prog.mlir:3:21: error: expected '('` on
  `idr.ctor @MkUnit tag 0 ()`, because the two sides disagree on the
  syntax.
- I built the committed frontend in scratch at `de2fc32` and again at
  `bd274ba`. It does not typecheck:
  - at `de2fc32`, `Frontend/Translate/Terms.idr:241` has an undefined
    `libraryCall`;
  - at `bd274ba`, `Frontend/Main.idr:330` has an unsolved hole.

So the numbers below come from the **last consistent toolchain**. Its
C++ side (`idris-mlir-cc`, the passes and the runtime) was built at 21:15.
The frontend was built at 00:46. The programs were built with it at 00:50,
when HEAD was `061b98d`. All the logs are in `results-build*.txt`. Neither
`idr.reset` → `idr.take` (committed in `bd274ba`) nor the Nat
representation is in these binaries. `run-head2.sh` reruns everything
unchanged once the tree builds.

**Where we stand** (CPU seconds, best of 5, rounds interleaved; `lower` is
better; the input sizes are the papers'):

| program | ours | Koka | Lean | MLton | C | Chez | ours ÷ best(Koka, Lean) |
|---|---:|---:|---:|---:|---:|---:|---:|
| rbtree | 4.94 | **1.53** | 3.39 | 9.09 | 1.95 | 3.74 | **3.24** (lose) |
| rbtree-ck | 7.28 | **3.77** | 6.95 | 12.16 | 4.53 | 12.13 | **1.93** (lose) |
| deriv | 1.73 | 3.28 | 1.81 | **1.60** | 4.03 | 5.37 | 0.96 (win) |
| nqueens | **1.03** | 1.25 | 3.11 | 1.40 | 1.40 | 18.31 | 0.82 (win) |
| cfold | 0.37 | **0.25** | 0.46 | 0.54 | 0.54 | 0.97 | **1.46** (lose) |
| binarytrees | **7.92** | 16.64 | 9.25 | 10.22 | 25.30 | 61.59 | 0.86 (win) |
| qsort | rejected | 36.39 | 2.79 | 1.88 | **1.38** | 18.62 | n/a |
| unionfind | rejected | 3.11 | 2.93 | 0.44 | **0.17** | 3.71 | n/a |
| fbip-rb (FP²) | **1.86** | 1.97 (fip) | – | – | – | 3.59 | 0.95 vs Koka fip |
| rbidx (typed rbtree) | **2.39** | 1.53 (std rbtree) | 3.39 | – | – | – | 1.56 vs Koka's rbtree |

- **We already win** four of the suite's programs:
  - `nqueens` and `binarytrees` against both Koka and Lean;
  - `deriv` against both, narrowly against Lean;
  - FP²'s `fbip-rb` against Koka's fip version.
- **We lose** where the benchmark exists to test reuse:
  - `rbtree` (3.2x Koka);
  - `rbtree-ck` (1.9x);
  - `cfold` (1.5x).
- **We cannot compile** Lean's two array programs.

**The mechanism of the losses is measured, and it is reuse.** Counts per
insert, n = 20 000:

| per insert | ours rbtree | ours fbip-rb | ours rbidx | Koka rbtree | Koka fbip | Lean rbtree | C rbtree |
|---|---:|---:|---:|---:|---:|---:|---:|
| cells allocated | 18.7 | 20.3 | 6.0 | **1.01** | **1.01** | 21.3 | 1.00 |
| reset tests | 17.8 | – (inlined) | 0 | – | – | – | – |
| … that found the cell shared | **15.8 (89%)** | | | | | | |
| decs (out of line) | 19.8 | | 5.0 | | | | |

- Koka and C allocate one cell per insert, which is the ideal.
- Lean allocates about 21 per insert: its reset frees the cell instead of
  reusing it (bench/gate/README.md, experiment 2).
- We allocate 18.7 per insert. 89% of our runtime uniqueness tests find
  the cell shared, so we copy the path, as Lean does.
- This is uniqueness-pipeline.md's D1 at benchmark scale: a reset placed
  after a consuming use, so the callee sees count 2. It measured 78% failures
  at n = 10^5 with a different binary.
- Even without reuse, **our allocator makes path copying cheap**. We copy
  18.7 cells per insert and are still only 1.46x Lean. Our fbip-rb copies 20
  per insert and still beats Koka's fully-in-place version. So once reuse
  works, the rbtree family should go below Koka. That is conjecture until
  measured: the static-reuse half of it is what the suite must prove.

**The representation lever is visible even before reuse works.** rbidx is
rbtree with its invariants in its type:
- the colour is the constructor;
- the black height is an erased index;
- a balance has no Leaf case.

It runs in 2.39 s against rbtree's 4.94 s. Its cells take 43 bytes per
node against 53 (173 against 212 MiB), and it allocates 6.0 cells per
insert against 18.7, with no reuse at all.

## 1. How it was measured

- **Machine:** 4 cores of a Xeon at 2.80 GHz, shared with six other
  agents' builds (load 2.8 to 6.9 during the main run, 00:52 to 01:08
  UTC).
- **Time:**
  - `cpu.sh` reports CPU time (user + sys, from `wait4`'s rusage), which
    load inflates less than wall time.
  - Every compiler's run is interleaved in each round, best of 5; Chez runs
    once.
  - The stack is unlimited and `LEAN_STACK_SIZE_KB` is 4 GiB, as in the gate.
  - Outputs are compared by md5 against the first label. All agreed.
- **A quieter cross-check** (`results-q.tsv`, 23:22 UTC, binaries from the
  same C++ build), which agrees on every ratio:
  - rbtree: ours 3.83, Koka 1.32, Lean 2.60, rbidx 1.79, fbip 1.50,
    Koka fip 1.80;
  - cfold: 0.31, 0.21, 0.28;
  - deriv: 1.31, 2.21, 1.36;
  - nqueens: 0.93, 0.92, 2.00.
- **Our allocation counts:** gdb breakpoint hit counts on the out-of-line
  runtime entries (`dyn2.sh`).
  - `idris_rt_cell` counts allocations, `rt::freeCell` frees, and
    `idris_rt_reset` uniqueness tests.
  - The not-exclusive outcome of a reset is counted by a breakpoint on the
    target of the `count != 1` branch in `idris_rt_reset` (`runtime/rc.cc`,
    the function that `bd274ba` deleted).
  - Every count is printed with the number of static call sites, because an
    entry that LTO inlines counts nothing. That is why binarytrees, and
    nqueens's allocations, have no count.
- **Why not callgrind on ours:** snmalloc aborts under valgrind with
  "Failed to initialise snmalloc", so our binaries cannot be counted that
  way. A routine suite needs runtime counters (§6).
- **Koka, Lean and C counts:** callgrind call counts (`cg.sh`).
  - Koka: `mi_theap_wmalloc_small` and `mi_free_small_nonnull`.
  - Lean: `mi_malloc_small`, minus the 10 143 allocations Lean's start-up
    makes with input 0.
  - C: `malloc` and `free`.
- **C** is the gate's: GCC -O2 (bench/gate/README.md). `bench/run.sh` has
  used clang for x86-64-v3 since `01fb73a`; the two should agree (§6).

### Allocation counts, all programs (small inputs)

| program (input) | ours cells | Koka | Lean (minus start-up) | C | notes on ours |
|---|---:|---:|---:|---:|---|
| rbtree (20 000) | 374 648 | 20 229 | 426 446 | 20 002 | 356 469 resets, 316 490 shared; 99 240 tokens freed unused |
| rbtree-ck (20 000) | 381 014 | 97 967 | 430 435 | 97 294 | 356 456 resets, 320 477 shared |
| fbip-rb (20 000) | 406 450 | 20 284 (fip) | – | – | no out-of-line reset; takes inlined |
| rbidx (20 000) | 119 240 | – | – | – | no reset, no take |
| cfold (14) | 46 147 | 49 408 | 46 143 | 32 769 | 10 378 resets, all exclusive; 20 756 tokens freed unused |
| deriv (5) | 2 327 | 3 090 | 2 683 | 3 687 | fewest of all: closed terms are static cells |
| nqueens (8) | 4 112 (frees) | 4 305 | 4 100 | 4 115 | allocation inlined |
| binarytrees (12) | inlined | 676 244 | 334 528 | 674 480 | allocation and free both inlined |

Every one of our programs ends with `idris-rt: live cells 0`
(`IDRIS_RT_LIVE=1`), so the counting frees everything.

## 2. The programs, one by one

The table's "Idris fact" column is what the program needs and what Koka and
Lean do not have. "Missing" says what stops us from using it today.

### rbtree (Perceus `rbtree.kk`, Lean `rbmap.lean`)

- **Stresses:** n inserts into a tree nobody shares. Every cell on the
  path can be updated in place, so the ideal is one allocation per insert,
  for the new leaf's node. Koka and C reach it.
- **Today:**
  - 3.24x Koka and 1.46x Lean;
  - 18.7 cells and 17.8 uniqueness tests per insert, 89% of which fail;
  - 53 bytes per node against Koka's 33 and C's 48.
- **Idris facts:**
  1. **Uniqueness of the tree, inferred.** `makeTree` passes `t` to
     `insert` once and never again. The source binds at quantity ω, so Idris
     proves nothing. The compiler must infer it over the call graph, and a
     unique scrutinee then needs a take without a test
     (uniqueness-pipeline.md steps 1 and 2).
  2. **`Color` and `Bool` are closed finite types.** After monomorphisation
     a `Node` field of type `Color` has two values. Our cell spends a word
     on each, where 1 bit each is enough.
     - Two-valued fields can go into the constructor tag: split `Node` into
       `NodeRed` and `NodeBlack`, which is what rbidx does by hand.
     - Or they can be packed into one word, or into the header's spare bits.
     - Either way the cell drops to 40 bytes. rbidx measures what this is
       worth: 173 MiB against 212, and 2.39 s against 4.94 (§2.2 has the
       caveats).
  3. **`isRed l` followed by `ins l` is a match on a field of a unique
     cell.** With the field moved out by a take, the inner match can reuse
     it too. Koka does this.
- **Missing:**
  - D1 to D4 (uniqueness-pipeline.md), as the 89% shows;
  - the untested take for proved-unique values;
  - finite-field packing, which is not in representation.md's catalogue.
    The nearest entries are R3, which packs constructors, and R7, which
    removes useless fields.
- **Claim for the suite:**
  - at most 1.05 cells per insert;
  - no failed uniqueness test;
  - no count test at all on the build path;
  - at most Koka's time.

### rbidx: rbtree with its invariants in its type

The program is in real-benchmarks-programs.md.

- **Stresses:** the same workload. The colour is the constructor, the black
  height `n` is erased, and a red node's children are black by type. The
  balance functions have no `Leaf` case and no mixed-height cases: the
  checker rejects them when they are written.
- **Today:**
  - 2.39 s, which is 2.07x faster than our rbtree and 1.42x faster than
    Lean's rbtree;
  - 1.56x Koka's rbtree;
  - 43 bytes per node and 6.0 cells per insert;
  - no reuse at all: the binary contains no reset, and no take shows up
    in the counts.
- **Caveat:** rbidx is also a different algorithm (Okasaki with
  existential wrappers, no `isRed` tests). Part of the 2x is fewer matches,
  not only smaller cells. To separate the two, the suite needs rbtree with
  only the colour moved into the constructor (§5, program 2b).
- **Idris facts:**
  - indices at quantity 0 (`!idr.erased`): the height costs nothing;
  - the colour as the tag: no field and no load;
  - coverage: impossible cases are unwritable, so the code is smaller;
  - the wrappers `AnyRB`, `Almost` and `Root` are `idr.data`, which live
    in registers, never in cells.
- **Missing:** reuse. We do not know why a matched `TB` cell is not reused
  for the `TR`/`TB` built in `balL`/`balR`. Both are same-size constructors
  of the same type (open question 1).
  - A plausible cause: the scrutinee reaches `balL` inside an `Almost`
    (an `idr.data` value), and the reuse pass only considers a match on a
    box whose own value dies (`ResetReuse.cc`, `run`).
  - Once the matched box sits inside a register sum, the inner match is on
    a field of a value that is not a box, and nothing tracks the field's
    cell.
- **Claim:**
  - at most rbtree's allocations with full reuse;
  - 40 bytes per node;
  - strictly faster than Koka's rbtree;
  - "the type is the representation", measured.

### linrb and linrb-shared (gate experiment 4)

- **Stresses:** the same insert with every tree bound at quantity 1. The
  shared variant keeps one tree for one more step, which Idris accepts,
  because a shared value may be passed to a quantity-1 parameter.
- **Today:** neither compiles. With the 00:46 frontend, Emit produces a
  module that `idr-simplify`'s verifier rejects: "'idr.match' op uses a
  linear value that is already used on the same path". That is an internal
  error, neither a compilation nor an `unsupported` rejection, so it
  violates AGENTS.md.
  - Of the two reproducers in real-benchmarks-programs.md, `lincase` (a
    catch-all naming the scrutinee) now compiles and prints 65, like Chez.
  - `lincase2` (nested patterns) still fails with the same error.
  - The other compilers, from the earlier run (`results-cpu.tsv`), with
    shared ÷ unique:

    | | unique (s) | shared (s) | shared ÷ unique |
    |---|---:|---:|---:|
    | Koka | 1.04 | 2.94 | 2.8 |
    | Lean | 3.02 | 3.32 | 1.1 |
    | Chez | 2.67 | 2.76 | 1.0 |

  - Koka and Lean compile the shared variant silently.
- **Idris fact:** `!idr.lin`. A quantity-1 parameter is used once, so every
  take on it is exclusive, *if every caller passes a unique value*.
  - That condition is a fact about the call sites, not about the binder
    (AGENTS.md: "a linear binder does not imply unique heap ownership").
  - linrb-shared is the test that the compiler respects the condition.
- **Missing:**
  - a fix for lincase2 (real-benchmarks-programs.md: after a match on a
    linear scrutinee, the whole value is the constructor rebuilt from its
    fields);
  - the call-site uniqueness check that rejects linrb-shared, or compiles
    it with a tested take.
- **Claim:**
  - linrb compiles with no inc, no dec test and no count test on the tree;
  - one cell per insert;
  - faster than Koka's linrb (1.04 s);
  - linrb-shared is rejected with `unsupported` naming its call site, or
    compiled correctly with tested takes. The choice between them is the
    open question of uniqueness-pipeline.md §4.

### fbip-rb (FP² / Koka `samples/basic/rbtree-fbip.kk`)

- **Stresses:** insertion that walks down building a zipper out of the
  cells it takes apart, then rebuilds the tree in them. Every constructor
  built has the size of one just matched: `Node`, `NodeR` and `NodeL` all
  have five fields. With unique cells, only the new leaf's node is
  allocated. Koka checks this statically (`fip`/`fbip`) and allocates 1.01
  cells per insert.
- **Today:**
  - 1.86 s, which beats Koka's own fip version (1.97 s) and Chez (3.59 s);
  - but 20.3 cells per insert against Koka's 1.01.
  - So our speed comes from cheap allocation and a tail-recursive shape,
    not from reuse. Koka's *std* rbtree (1.53 s) is faster than both fip
    versions.
- **Idris facts:**
  - uniqueness, inferred as for rbtree;
  - reuse across types: a `Tree` cell becomes a `Zipper` cell of the same
    size. Our reuse pairs by size (`ResetReuse.cc`: "a box with a cell of
    the same size"), so this is allowed in principle.
  - The 22:27 dump has 11 `idr.reuse` ops after `idr-rc`. The runtime count
    shows the tokens are null, which is the same D1/D3 failure.
- **Claim:**
  - at most 1.05 cells per insert;
  - stack depth independent of n (run under `ulimit -s 8192` with n = 4.2M);
  - at most Koka fip's time, and at most Koka std's.
- **Why it matters beyond rbtree:** FP² writes a program so that the
  *programmer* proves it in place. We should get the same from the
  ordinary program (rbtree) by inference, plus a report where inference
  fails. fbip-rb is then the upper bound that rbtree must reach.

### rbtree-ck (Perceus `rbtree-ck.kk`, Lean `rbmap_checkpoint.lean`)

- **Stresses:** the same inserts, keeping every fifth tree. Four inserts in
  five run on a tree that is unique again once the checkpoint's list has
  taken its copy. Koka and C allocate 4.9 cells per insert.
- **Today:** 1.93x Koka and 1.05x Lean. We allocate 19.1 cells per insert,
  as in plain rbtree: the same failures, plus the real sharing.
- **Idris facts:** none that prove uniqueness, which is the point of this
  program. It is the **control**: whatever makes rbtree static must leave
  rbtree-ck correct and keep runtime tests exactly where cells are shared.
  The tests are Perceus's dynamic reuse, which uniqueness-pipeline.md §7
  keeps next to static reuse.
- **Claim:**
  - at most Koka's 4.9 cells per insert;
  - the same output;
  - at most Koka's time;
  - `live cells 0`.

### deriv (Perceus `deriv.kk`, Lean `deriv.lean`)

- **Stresses:** symbolic terms with shared subterms (`d x (Mul f g)` uses
  `f` and `g` twice). It needs cheap sharing, not reuse.
- **Today:**
  - 1.73 s: 0.53x Koka and 0.96x Lean, but 1.08x MLton;
  - the fewest cells of all: 2 327, against 3 090 for Koka and 3 687 for C.
- **Idris facts:**
  - closed terms are static cells (count 0);
  - `d "x"`'s string literal is a closed argument that specialization
    ("finite specialization") can fix;
  - every closed call of total code is evaluated at compile time (AGENTS.md).
- **Missing:** the last 8% against MLton is not traced here. A guess is the
  `String` compare in `d x (Var y)` (`x == y` on every `Var`), which
  specialization on `x = "x"` would turn into a compare with a constant.
- **Claim:**
  - at most Koka's allocations;
  - faster than MLton;
  - no count operation on static cells.

### nqueens (Perceus `nqueens.kk`)

- **Stresses:** lists of lists that share their tails. Nothing can be
  reused: every solution list is shared by its extensions.
- **Today:**
  - 1.03 s: 0.82x Koka and 0.33x Lean;
  - frees equal C's (4 112 against 4 115);
  - 94 MiB, the least of all.
- **Idris facts:**
  - `safe` only reads its list, so it borrows it;
  - `Int` elements are unboxed in the cons cell.
- **Claim (control):** we stay at most Koka's time and C's allocations.

### cfold (Perceus `cfold.kk`, Lean `const_fold.lean`)

- **Stresses:**
  - building a term of depth 20, then reassociating and folding it;
  - `reassoc`'s right spine recurses 2^19 deep.
  - `e` is used by `eval e` (which only reads it) and then by `reassoc e`,
    its last use. From there on it is unique, and `reassoc` and `cfold` can
    reuse every `Add`/`Mul` cell.
- **Today:**
  - 0.37 s: 1.46x Koka and 0.80x Lean;
  - 46 147 cells, fewer than Koka's 49 408, but C needs only 32 769;
  - 10 378 resets, all of them exclusive, but 20 756 tokens freed unused:
    two thirds of the cells taken apart are not rebuilt in place.
- **Why the tokens go unused:** in `cfold`, `Add e1 e2` becomes `Val (a+b)`,
  a constructor of another size, or it becomes `Add` in the `Val a` branch
  only after the inner `case`. Koka also reuses by size, yet allocates more
  than we do. So our allocation count is not what makes us slower; the time
  goes elsewhere (not traced: the deep recursion's frames, or the counts).
- **Idris facts:**
  - `eval` borrows, so `e`'s reference count is 1 when `reassoc` starts;
    that is uniqueness after the last borrowed use;
  - `Expr` is total and finite, so a take of a unique `Add` whose `Val`
    result is smaller can keep the cell, when the size classes allow it,
    instead of freeing it and allocating a new one.
- **Claim:**
  - at most C's cell count;
  - at most Koka's time;
  - recursion depth 2^19 without an unlimited stack. The frames are the
    evaluation contexts of FP² §2.5 ("Stack Safe FIP"). TRMC (architecture.md) or an explicit
    zipper would bound them; this is where Koka's TRMC wins.

### binarytrees (Benchmarks Game; Lean `binarytrees.st.lean`)

- **Stresses:** allocate a tree, walk it, free it, many times, beside one
  long-lived tree.
- **Today:**
  - 7.92 s: 0.86x Lean, 0.78x MLton, 0.48x Koka and 0.31x C (glibc
    malloc);
  - 110 MiB, the least;
  - allocation and free are both inlined, so the fast path is a
    snmalloc free-list pop and push (runtime/alloc.cc:1-6).
- **Idris facts:**
  - `check (make' i d)`: the tree is built and consumed at once, and no
    reference survives `check`;
  - `make'` and `check` are total and pure.
  - So the whole tree can live in a region freed in one step, or
    `check ∘ make'` can be fused: it computes the node count, which depends
    only on `d`.
  - Fusing is legal, but it would defeat the benchmark. The honest claim is
    the region.
- **Claim:**
  - stay ahead of Lean and MLton;
  - freeing a checked tree costs O(1), not O(nodes). Measure it as frees
    per iteration with runtime counters.

### qsort (Lean `qsort.lean`) and unionfind (Lean `unionfind.lean`)

- **Stresses:**
  - qsort updates arrays in place (Bits32);
  - unionfind keeps an array of two-`Int` records and compresses paths.
  - Both are written with base's `Data.IOArray.Prims`, because
    `Data.IOArray` boxes every element in a `Just`.
- **Today, both are rejected:**
  - qsort: `Main.mkRandomArray: unsupported (escape hatch): %extern
    Data.IOArray.Prims.prim__newArray`;
  - unionfind: `unsupported (program): imports System, which is neither a
    user module nor a trusted module`, because of `exitWith`.
  - The rejections are explicit, as AGENTS.md asks.
  - The field for comparison:

    | | qsort (s) | unionfind (s) |
    |---|---:|---:|
    | C | 1.38 | 0.17 |
    | MLton | 1.88 | 0.44 |
    | Lean | 2.79 | 2.93 |
    | Koka | 36.4 | 3.11 |

    Koka has no mutable array, so its vector is copied.
- **Idris facts:**
  - elements of closed scalar type are unboxed: `Bits32` as `i32`, and
    `NodeData` as two `i64` inline;
  - indices below the length can be `Fin n`, which removes the bounds
    check (representation.md R5);
  - a pure array that is threaded uniquely is updated in place (the
    tensor → bufferization path of decision-linear-libraries.md and
    mutable-buffers.md).
- **Missing:** a registry meaning for the array primitives (mutable-buffers.md
  and linear-libs.md) and for `System.exitWith`.
- **Claim:**
  - qsort: IOArray and pure `Fin` versions both within 1.1x of C.
    Lean's pure-`Array` qsort is the one to beat.
  - unionfind: within 1.5x of C, which is 6x ahead of Lean and Koka.

### Idiomatic variants (earlier run, `results-cpu.tsv` and `results-q.tsv`)

These are the same workloads written the way an Idris programmer writes
them: Nat, Integer, ranges, `sum`/`map`, contrib's `SortedMap`. They
measure what idiomatic Idris costs, which the Int versions hide.

| variant | ours | Chez | notes |
|---|---:|---:|---|
| binarytrees, Nat and ranges | 172 s (depth 14) | 0.11 s | superlinear: 6.6 s at depth 12. Chez is fast partly because upstream CSE shares `make d`. The rest is not traced. |
| deriv, Integer | 13.2 s, 3.5 GB | 2.9 s, 0.8 GB | |
| cfold, Integer and Nat | 0.35 s | 0.76 s | win |
| nqueens, Nat and `length` | 25.0 s | 68.9 s | win against Chez, but 25x our Int version |
| binarytrees with a depth-indexed `PTree d` | 8.7 s | 15.3 s | win |
| rbtree via `Data.SortedMap` | rejected | – | `unsupported (runtime closure): an implementation chosen at runtime` in `Data.SortedMap.Dependent.insert` |

decision-nat.md (being implemented now) targets the first three. The
suite must hold at least one idiomatic program, or the Int versions will
flatter us.

## 3. FP²'s fully-in-place programs

FP² (Lorenzen, Leijen, Swierstra, ICFP 2023) §6, Fig. 10 benchmarks five
programs: rbtree, ftree, msort, qsort and tmap. Each does 100 iterations
over 100 000-element structures. The paper finds that fip is faster than
std; that std-reuse (Koka's default) is close to fip; and that both are
near C++.

- **fbip-rb** is §2.1 above.
- **tmap (§3)**: I wrote it for this stream, in Idris and Koka (fip and
  std). The sources are in `src/tmap-{fip,std}/Main.idr` and
  `src/kk/tmap{fip,std}.kk`, 100 maps over a tree of n leaves.

  | n | Koka fip | Koka std | Chez fip | Chez std |
  |---:|---:|---:|---:|---:|
  | 100 000 | 0.11 s | 0.08 s | 2.28 s | 1.39 s |
  | 1 000 000 | 1.78 s | 1.57 s | 25.1 s | – |

  - All print 5010050000.
  - Koka's checker accepted `fip` for `down`/`app` once they were declared
    `div`: they are mutually recursive and not structurally decreasing.
  - Ours could not be built on any tree state today (above).
- **The claim this program carries:** tmap-std compiles to what tmap-fip
  is: no allocation and a flat stack on a unique tree.
  - FP² §3.1 shows that the fip version *is* the defunctionalized CPS form
    of the std version. The zipper constructors are the closures of
    `tmap(l, f, fn(l') …)`.
  - We already defunctionalize (`Defunctionalize.cc`), and TRMC is in
    architecture.md.
  - What is left is the side condition of FP²'s TRMReC translation: each
    zipper constructor fits in a cell the recursion just freed. Size
    arithmetic over known constructors makes that decidable at compile
    time.
  - Idris facts: uniqueness for the reuse; totality, so that the transformed
    loop is the same function.
- **msort and qsort (§4.2):** in-place list sorts through a partition type
  (`Sub`/`One`/`End`, `Cons2`/`Nil2`) that holds n elements in the n cells
  of the input list. They are worth adding because reuse happens across
  *three* types of equal cell size. Not ported here.
- **ftree (§4.3)** and **splay trees (§1)**: splay is the paper's opening
  example, where lookup restructures the tree. Porting them is left for
  later; ftree needs the unboxed tuples and "atoms" of §1.2.

## 4. What the measurements say about the design

1. **Reuse is the whole gap on rbtree, rbtree-ck and fbip-rb, and it is
   placement, not proof.**
   - 89% of our tests fail on a tree that is unique by construction. Lean
     loses the same way, for a different reason (it frees the reset cell).
   - Fixing D1 to D4 turns the dynamic test into Koka's behaviour.
   - uniqueness-pipeline.md's static proof then removes the test.
   - Koka never removes it, so that is the step that beats Koka rather than
     matching it.
2. **Cell size is the second lever, and Idris knows the finite types.**
   - rbtree spends 53 bytes per node on five fields, two of which carry one
     bit each.
   - A representation rule is missing from representation.md: a field whose
     type is closed and finite after monomorphisation (an enum like `Color`
     or `Bool`, or a `Fin k` with small k) is packed. One option splits the
     constructor by the field's value (`Node Red …` → `NodeRed …`), so the
     field becomes part of the tag, which the match already reads. The
     other packs the field into one word with its siblings.
   - The first option is rbidx, done by the compiler. It is sound because
     the field's value set is closed and the tag space is known (R3's
     disjointness verifier covers it).
   - The layout attribute (R2/R3) would hold it, so nothing is stored in a
     discardable attribute.
3. **Where we win, we win on allocation cost, not on facts.** In
   binarytrees, nqueens and deriv:
   - allocation is inlined;
   - frees are iterative;
   - closed terms are static.

   None of the Idris-specific facts (linearity, erasure, indices, totality)
   is used yet. The suite has to separate these, which is why every
   program's claim names its fact.
4. **Correctness gaps block the flagship.**
   - linrb, the program the memory gate was designed around, does not
     compile (lincase2's error).
   - Lean's two array programs are rejected.
   - contrib's `SortedMap` is rejected.
   - These are the first work items, before any speed claim.

## 5. The proposed real-programs suite

Fifteen programs. Each makes one claim that a machine checks. The time
criterion is always against `min(Koka, Lean)` on the same machine and
input, in the same interleaved rounds.

| # | program | source | Idris fact it exploits | claim (checked) |
|---|---|---|---|---|
| 1 | rbtree | Perceus / Beans | uniqueness inferred over the call graph | ≤ 1.05 cells per insert; 0 failed uniqueness tests; time ≤ Koka |
| 2 | rbidx | this stream | erased indices (`!idr.erased`); colour as the tag; coverage | 40 B/node; cells ≤ rbtree's; time < Koka's rbtree |
| 2b | rbtree-split | rbtree with `NodeRed`/`NodeBlack` | closed finite field → tag (the new packing rule) | the compiler's split of #1 equals the hand split: same cells per insert, same bytes per node |
| 3 | linrb | gate experiment 4 | `!idr.lin` on a unique call chain | 0 inc, 0 dec test, 0 count test on the tree; 1 cell per insert; time < Koka (1.04 s) |
| 3b | linrb-shared | gate experiment 4 | call-site uniqueness | `unsupported` naming the call site (or a correct tested build); never an internal error |
| 4 | fbip-rb | FP² / Koka sample | uniqueness; reuse across `Tree` and `Zipper` cells of the same size | ≤ 1.05 cells per insert; runs at `ulimit -s 8192`; time ≤ Koka fip |
| 5 | tmap-std and tmap-fip | FP² §3 | uniqueness; totality; defunctionalized CPS | both 0 cells per map and a flat stack; tmap-std within 1.1x of tmap-fip; ≤ Koka |
| 6 | msort-fip | FP² §4.2 | uniqueness; equal-size reuse across three types | 0 cells after the input list; ≤ Koka fip |
| 7 | rbtree-ck | Perceus / Beans | none: the sharing control | ≤ 4.9 cells per insert (Koka's and C's); time ≤ Koka; output identical |
| 8 | deriv | Perceus / Beans | closed terms static; compile-time evaluation; specialization on the literal | cells ≤ Koka's; time < MLton |
| 9 | nqueens | Perceus | borrowing; unboxed `Int` fields (the control for shared tails) | time ≤ Koka; frees ≤ C's |
| 10 | cfold | Perceus / Beans | uniqueness after the last borrowed use | cells ≤ C's; time ≤ Koka; depth 2^19 under an 8 MiB stack |
| 11 | binarytrees | Benchmarks Game / Beans | purity + non-escape → region | time ≤ Lean and MLton; O(1) frees per checked tree |
| 12 | qsort | Beans (IOArray form + pure `Fin` form) | unboxed `Bits32`; `Fin n` bounds; unique array → in place | compiles; within 1.1x of C in both forms |
| 13 | unionfind | Beans | record of two `Int`s unboxed in the array; `Fin` indices | compiles; within 1.5x of C |
| 14 | sortedmap | contrib `Data.SortedMap` | monomorphised `Ord` dictionary (a closed instance) | compiles; within 1.5x of #1 |
| 15 | idiom-binarytrees | binarytrees with `Nat` and ranges | Nat as a word where its range is proved (decision-nat) | within 1.2x of #11; no worse than Chez |

- Programs 1 to 6 are the static-reuse claims, the reason this compiler
  exists.
- 7 to 10 are the controls that reuse must not break. They are also where
  we already win, so they catch regressions.
- 11 to 15 are the representation and coverage claims.
- Programs 2b, 5, 6, 14 and 15 are new. 5's sources exist (§3); 2b is a
  ten-line edit of rbtree; 6 is a port of FP² §4.2; 14 and 15 exist in
  scratch (`idiom/`).

## 6. What bench/ needs to run it routinely

1. **An `ours` column in the gate's suite.**
   - `bench/gate/run.sh suite` builds Chez, MLton, C, Koka and Lean
     (`lib.sh` `build_chez` … `build_lean`), but never this compiler. Only
     the hand-lowered prototypes of experiments 2 to 4 stand for it.
   - Add `build_ours` (`tools/compile.sh Main.idr prog`, under
     `flock -s build/.tree.lock`).
   - Add a verdict per program: time against `min(Koka, Lean)`.
   - `bench/run.sh` already has "this compiler", but no Koka or Lean. The
     simplest merge is `bench/run.sh --suite gate`, sourcing `gate/lib.sh`'s
     builders.
2. **Runtime counters, not gdb.**
   - Add a stats variant of the runtime archive: counters for
     - cells allocated and freed;
     - takes found exclusive and found shared;
     - incs, decs, and tokens freed unused;
     - maximum stack depth.
   - Compile it separately, so timing builds carry no counter.
   - Print it at exit as `IDRIS_RT_LIVE` does today (runtime/io.cc).
   - `idris-mlir-cc --runtime=<archive>` already selects an archive
     (idris-mlir-cc.cc:112). A `--directive rt-stats` in `tools/compile.sh`
     would pass it.
   - Today these counts need gdb on out-of-line entries, which misses
     whatever LTO inlines and takes minutes. Callgrind cannot run our
     binaries (snmalloc does not initialise under valgrind).
   - The gate's own prototype has exactly this switch (`IDR_GATE_STATS`,
     bench/gate/README.md).
3. **Static counts next to the dynamic ones.** `idris-mlir-cc --stats`
   exists (idris-mlir-cc.cc:517). Record:
   - `numReuses` and `numIncs` (Passes.td:396-399 at bd274ba);
   - the stack cells (`numCells`, Passes.td:282).

   A claim like "0 count tests on linrb" is then checked statically and
   dynamically.
4. **A `claim` file per program**, in the style of `bench/<name>/input`
   and `rejected`. It holds the checked properties as data, for example:

   ```
   cells-per-op <= 1.05
   failed-takes = 0
   stack 8192
   rejects linrb-shared
   ```

   The runner evaluates it against the counters, so each claim is written
   once, not re-encoded in a script. This is AGENTS.md's "expressive
   check", at the benchmark level.
5. **CPU time and interleaving.**
   - The machine is shared, and wall-clock best-of-5 (`tools/measure.c`)
     swings 2x under load.
   - Report user + sys from `wait4`'s rusage, which `measure.c` already
     calls.
   - Interleave the compilers within each round, as `cpu.sh` does.
6. **One C compiler.** The gate builds C with GCC -O2; `bench/run.sh` uses
   clang for x86-64-v3 since `01fb73a`. The C column should mean the same
   thing in both.
7. **A toolchain consistency check before measuring.**
   - Today's failure mode was two halves of the compiler built from
     different trees:
     - the frontend at 00:46 and `idris-mlir-cc` at 02:27 disagree on
       `idr.ctor`'s syntax;
     - `idris-mlir-cc` at 21:15 and the runtime at 01:52 disagree on
       `llvm.global.annotations`.
   - The runner should record both binaries' build times and the commit,
     and refuse to report when they are from different builds.

## Open questions

1. Why does rbidx reuse nothing (no reset in the binary and 6.0 cells per
   insert)? Is it the `Almost`/`AnyRB` register sums hiding the matched
   box's death? To answer, dump `idr-rc` on rbidx with a working tree.
2. Why do fbip-rb's 11 `idr.reuse` sites (22:27 dump) reach runtime with
   null tokens? Is it the same D1/D3, or the zipper being passed to
   `balanceRed` as a borrowed parameter?
3. cfold: we allocate fewer cells than Koka and are 1.46x slower. Where does
   the time go? The deep recursion's frames, counts on the `Val` path, or
   `max`?
4. The idiomatic binarytrees is superlinear (6.6 s at depth 12, 172 s at
   depth 14). Is that Nat alone (decision-nat.md), or also the missing CSE
   that upstream does on CExp? We consume TT, so upstream's CSE never runs
   for us, and an MLIR `cse` over pure calls would recover it.
5. Should the finite-field packing rule split constructors, or pack fields
   into a word?
   - Splitting multiplies the constructors, and so the match arms. That is
     free for a match already on the tag, but code grows for functions
     that ignore the colour.
   - rbtree-split (#2b) against a packed-word variant would decide it.
