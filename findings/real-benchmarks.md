# Real benchmarks: beating Lean and Koka on their own programs

The memory gate (`bench/gate`) this note and `memory-gate*.md` describe is
folded into `bench/` (2026-10-01): its programs are `bench/<name>/` with
their C, SML, Koka and Lean versions in `bench/c`, `bench/sml`,
`bench/koka` and `bench/lean`, measured by `bench/run.sh`; its hand-lowered
prototypes and thread experiments are gone, built for real since.

Stream "real-benchmarks". The programs this stream wrote are quoted in full
in `real-benchmarks-programs.md`. The scripts, raw result files, builds and
IR dumps are in `scratchpad/research/real-benchmarks/`:
- `cpu.sh` does interleaved CPU timing;
- `dyn2.sh` counts runtime entries through gdb;
- `cg.sh` counts callgrind calls for Koka, Lean and C;
- the raw results are in `results-*.tsv` and `results-*.txt`, all of them
  in `results-all.tsv`.

This file builds on:
- `uniqueness-pipeline.md`: the reuse-placement defects D1 to D4, and
  uniqueness inference;
- `representation.md`: R1 to R14;
- `decision-nat.md`.

It adds three things: numbers against Koka and Lean on their own programs,
what each program needs, and the suite that should gate the work.

## The questions

1. On the Perceus and Counting Immutable Beans programs, where do we stand
   against Koka, Lean, MLton, C and Chez at HEAD? I measure time, memory,
   and allocation and reuse per operation.
2. For each program: what does it stress, which Idris fact could make us
   win, and what is missing?
3. What do FP²'s fully-in-place (fip) programs add?
4. Which 10 to 15 programs should form the real-programs suite, each with a
   checked claim? What does `bench/` need to run the suite routinely?

## What "at HEAD" means here

Other agents rebuilt the shared tree several times while I measured, so
"HEAD" moved under me. Three builds were measured:

| label | built | tree | what it covers |
|---|---|---|---|
| **new** | 02:38 UTC | `bd274ba` + 4 uncommitted files | rbtree, rbtree-ck, cfold, nqueens, rbidx, linrb, linrb-shared, lincase, lincase2, qsort and unionfind (both rejected) |
| **new** | 02:59 UTC | `6f9a9af` + 6 uncommitted files | deriv, binarytrees, fbip-rb, tmap-fip, tmap-std and the idiomatic variants. In the 02:38 build, `idris-mlir-cc` crashed on these (SIGILL, status 132) |
| **old** | 00:50 UTC | `061b98d` | C++ side from 21:15, frontend from 00:46 |

- The "new" builds already contain `bd274ba`'s change: `idr.reset` is gone,
  and a take moves the fields at the box's death point.
- The "old" binaries are measured in the same interleaved rounds, so they
  show what that change did.
- HEAD was `6451a70` when I finished (03:20).

Between 01:50 and 02:37 no consistent toolchain existed:
- the frontend and `idris-mlir-cc` came from different builds, and
  disagreed on the syntax of `idr.ctor … tag 0 ()`;
- `idris-mlir-cc` and the runtime archive disagreed on
  `llvm.global.annotations`;
- the committed frontend did not typecheck at `de2fc32` or `bd274ba`
  (`Frontend/Translate/Terms.idr:241` and `Frontend/Main.idr:330`), as I
  checked with a build in scratch.

`results-build*.txt` records each build's tree, and §6 item 7 proposes the
guard this needs.

## The answer in one page

**Allocation: the uniqueness facts now pay off, and we match Koka and C.**
Cells allocated per insert, or per map for tmap. Lower is better:

| program | ours, old | **ours, new** | Koka | Lean | C |
|---|---:|---:|---:|---:|---:|
| rbtree (n = 20 000) | 18.7 | **1.00** | 1.01 | 21.3 | 1.00 |
| rbtree-ck | 19.1 | **4.86** | 4.89 | 21.5 | 4.86 |
| linrb (quantity-1 tree) | does not compile | **1.00** | 1.01 | 14.9 | – |
| linrb-shared | does not compile | 19.3 (correct) | 19.6 | – | – |
| fbip-rb (FP²) | 20.3 | **1.00** | 1.01 (fip) | – | – |
| tmap-fip and tmap-std (per map) | – | **0** | 0 | – | – |
| rbidx (typed rbtree) | 6.0 | **17.8** (regression) | – | – | – |

- **rbtree:** at `061b98d`, 89% of our runtime uniqueness tests found the
  cell shared, and we copied the path as Lean does. At the new build we
  allocate exactly one cell per insert, as Koka and C do.
- **rbtree-ck:** our 97 292 cells equal C's 97 294, and Koka allocates 97 967.
- **linrb:** compiles now. linrb-shared is compiled correctly, not
  rejected, and pays the same cliff as Koka.
- **rbidx has regressed,** and the cause is found (§2.2): `idr-stack`
  puts a rebuilt cell on the stack, and a stack cell cannot be reused.

**Time.** CPU seconds, best of the interleaved rounds of one run, on a
machine with load 8 to 10 (§1). The ratio is ours ÷ the better of Koka and
Lean in the same run:

| program | ours, new | ours, old | Koka | Lean | MLton | C | Chez | ratio |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| rbtree | 2.11 | 5.02 | **1.14** | 3.40 | 9.21 | 1.94 | 4.55 | **1.84** (lose) |
| rbtree-ck | 4.43 | 7.18 | **3.03** | 6.35 | 13.82 | 4.64 | 17.07 | **1.46** (lose) |
| linrb | 2.06 | – | **1.13** | 3.45 | – | – | 4.87 | **1.82** (lose) |
| linrb-shared | 4.16 | – | 4.31 | 4.08 | – | – | – | 1.02 |
| fbip-rb | **1.25** | 1.96 | 1.43 (fip); 1.14 (std) | – | – | 2.00 | 3.85 | 0.88 against fip, 1.09 against std |
| tmap-fip (n = 10^6) | **1.57** | – | 1.82 | – | – | – | 25.1 | 0.86 |
| tmap-std (n = 10^6) | 1.75 | – | **1.47** | – | – | – | – | 1.19 (lose) |
| cfold | 0.36 | 0.42 | **0.28** | 0.40 | 0.60 | 0.64 | 1.01 | **1.31** (lose) |
| deriv | 1.80 | 1.91 | **1.54** | 3.13 | 1.85 | 4.25 | 6.31 | 1.17 (lose; noisy) |
| nqueens | **1.03** | 1.02 | 1.21 | 3.20 | 1.46 | 1.45 | 18.03 | 0.85 (win) |
| binarytrees | **8.01** | 8.17 | 17.12 | 9.70 | 10.23 | 26.66 | 65.45 | 0.83 (win) |
| rbidx | 4.48 | 2.37 | 1.64 (rbtree) | 3.45 | – | – | 3.95 | 2.74 (regression) |
| qsort | rejected | rejected | 36.97 | 2.85 | 1.97 | **1.42** | 18.83 | n/a |
| unionfind | rejected | rejected | 3.82 | 2.97 | 0.43 | **0.17** | 3.88 | n/a |

- **What the new build won.** Reuse took rbtree from 5.02 s to 2.11 s,
  rbtree-ck from 7.18 to 4.43 and fbip-rb from 1.96 to 1.25.
  - We now beat Lean on every program we compile.
  - We beat C on rbtree-ck (malloc'd copy-on-write), on nqueens and on
    binarytrees, and we tie C on rbtree.
  - We beat Koka on the fip programs (fbip-rb and tmap-fip), on nqueens
    and on binarytrees.
- **Why rbtree still loses to Koka, though allocation is equal.** The
  remaining 1.8x is not reuse. Two differences are measured, and which one
  dominates is not established:
  1. **Cell size:** 48 bytes per node against Koka's 33 (193 MiB against
     132 MiB for 4.2M nodes).
  2. **Recursion shape:** Koka's `ins` is tail-recursive modulo cons (its
     profile shows `kk_rbtree__trmc_ins`) and builds the path top down.
     Ours recurses and returns through every level.

  fbip-rb, the same insert written as a loop over a zipper, runs in 1.25 s
  with the same cells. That is within 1.09x of Koka, which points at the
  recursion shape.
- **We cannot compile** Lean's two array programs (rejected with
  `unsupported`, as AGENTS.md asks).
- **Idiomatic Idris got fast.** These use Nat, Integer and ranges instead
  of `Int` (§2.9). Against Chez:

  | variant | before | now | Chez |
  |---|---:|---:|---:|
  | binarytrees at depth 12 | 6.6 s | **0.01 s** | 0.14 s |
  | deriv with `Integer` | 13.2 s, 3.5 GB | **2.08 s**, 425 MB | 5.16 s |

  The Nat work landed between the two builds.

## 1. How it was measured

- **Machine:** 4 cores of a Xeon at 2.80 GHz, shared with six other agents'
  builds. The load average was 7.4 to 10 during every run.
- **Time:**
  - `cpu.sh` reports CPU time (user + sys, from `wait4`'s rusage).
  - It interleaves every compiler in each round and keeps each one's best.
  - The stack is unlimited and `LEAN_STACK_SIZE_KB` is 4 GiB, as in the gate.
  - Every output is checked by md5 against the reference. All of them
    agreed.
- **Which run each row of the table comes from:**
  - the focused runs (`t-*`, 5 to 9 rounds, 03:25 to 03:40) for rbtree,
    fbip-rb, linrb, cfold, rbtree-ck, deriv and nqueens;
  - `results-head3.tsv` (3 rounds) for tmap, linrb-shared and binarytrees;
  - `results-head2.tsv` (3 rounds) for the old column, rbidx, qsort and
    unionfind.
- **Noise is large, and it is not uniform across compilers.**
  - Koka's deriv ranged over 1.54 to 4.13 s in today's runs, and Lean's
    rbtree-ck over 5.5 to 12.5 s. Koka's rbtree-ck was 2.11 s wall on the
    quiet machine of the gate's first run (bench/gate/README.md).
  - Memory-bound programs suffer most from the other agents' builds.
  - Trust a ratio within one run, and trust the allocation counts, which
    do not depend on load.
  - `results-q.tsv` is a quieter run (23:22, older binaries). Its ratios are
    rbtree 2.9x Koka at 18.7 cells per insert, and cfold 1.49x Koka.
- **Our allocation counts:** gdb breakpoint hit counts on the out-of-line
  runtime entries (`dyn2.sh`).
  - `idris_rt_cell` counts cells allocated, `rt::freeCell` cells freed,
    `idris_rt_free_cell` tokens freed without reuse, and `idris_rt_dec` the
    out-of-line decrements.
  - For the old binaries, the not-exclusive outcome of `idris_rt_reset` is
    counted as well: that function existed until `bd274ba`.
  - Each count is printed with its number of static call sites, because an
    entry that LTO inlines counts nothing. That is why binarytrees and
    nqueens have no allocation count.
- **Why not callgrind on ours:** snmalloc aborts under valgrind ("Failed
  to initialise snmalloc").
- **Koka, Lean and C counts:** callgrind (`cg.sh`).
  - Koka: `mi_theap_wmalloc_small` and `mi_free_small_nonnull`, minus the
    150 allocations of its start-up.
  - Lean: `mi_malloc_small`, minus the 10 143 of its start-up.
  - C: `malloc` and `free`.
- **C** is the gate's: GCC -O2 (bench/gate/README.md). `bench/run.sh` has
  used clang for x86-64-v3 since `01fb73a`.
- **Every one of our programs ends with `idris-rt: live cells 0`**
  (`IDRIS_RT_LIVE=1`), in both builds.

### Allocation counts, all programs (small inputs)

| program (input) | ours, old | ours, new | Koka | Lean | C | notes on ours, new |
|---|---:|---:|---:|---:|---:|---|
| rbtree (20 000) | 374 648 | **20 000** | 20 079 | 426 446 | 20 002 | no out-of-line dec; no token freed unused |
| rbtree-ck (20 000) | 381 014 | **97 292** | 97 817 | 430 435 | 97 294 | |
| linrb (20 000) | – | **20 000** | 20 109 | 298 407 | – | |
| linrb-shared (20 000) | – | 386 469 | 392 842 | – | – | 119 221 decs; correct output |
| fbip-rb (20 000) | 406 450 | **20 000** | 20 134 (fip) | – | – | |
| tmap-fip and tmap-std (10 000 leaves, 100 maps) | – | **19 999** | 20 050 | – | – | only the build: 0 per map |
| rbidx (20 000) | 119 240 | 356 488 | – | – | – | 217 268 out-of-line releases |
| cfold (14) | 46 147 | 46 147 | 49 258 | 46 143 | 32 769 | 31 134 tokens freed unused (old: 20 756) |
| deriv (5) | 2 327 | 2 327 | 2 940 | 2 683 | 3 687 | closed terms are static cells |
| nqueens (8) | 4 112 frees | 4 112 frees | 4 155 | 4 100 | 4 115 | allocation inlined |
| binarytrees (12) | inlined | inlined | 676 094 | 334 528 | 674 480 | |

## 2. The programs, one by one

For each program: what it stresses, where we stand, the **Idris fact** (what
we know that Koka and Lean do not, or know only dynamically), and what is
missing.

### 2.1 rbtree (Perceus `rbtree.kk`, Lean `rbmap.lean`)

- **Stresses:** n inserts into a tree nobody shares. Every cell on the
  insertion path can be updated in place, so the ideal is one allocation
  per insert: the new leaf.
- **Now:**
  - 1.00 cell per insert, as Koka and C;
  - 2.11 s: 1.84x Koka, 1.09x C, 0.62x Lean;
  - 48 bytes per node against Koka's 33.
  - At `061b98d` it was 18.7 cells per insert, and 89% of the uniqueness
    tests failed. That was D1 of uniqueness-pipeline.md, which the new
    build fixed.
- **Idris facts:**
  1. **Uniqueness of the tree.** `makeTree` passes `t` to `insert` once and
     never again. The source binds at quantity ω, so Idris proves nothing;
     the compiler must infer uniqueness over the call graph
     (uniqueness-pipeline.md steps 1 and 2).
     - What this buys now is removing the per-take count test, not the
       allocations. The test is inlined, so its cost is not measured here.
     - Koka keeps the test, so this is the step that goes *past* Koka.
  2. **`Color` and `Bool` are closed finite types.** A `Node` field of type
     `Color` has two values, yet the cell spends a word on each. Two fixes:
     - put two-valued fields into the constructor tag (`Node Red …` becomes
       `NodeRed …`, which rbidx does by hand);
     - or pack them into one word.

     Either way the cell drops to 40 bytes. §4, point 2, has the rule this
     needs.
     - **Measured (2026-09-30):** the tags were already one byte each; the
       48 came from placing the non-counted components in source order
       (`Color` at 24, the key aligned to 32, `Bool` at 40). A cell now
       places them most aligned first, and the node is 40 bytes with no
       change to the types. Koka's 33 needs the tag-in-header move or a
       packed word.
  3. **The recursion shape.** `ins` is not tail-recursive. Koka compiles it
     with TRMC (`kk_rbtree__trmc_ins`): its path is written top down,
     without a stack frame per level.
     - fbip-rb is the same insert as a loop and runs 1.7x faster with the
       same cells. That was the evidence that the shape, and not
       allocation, was the remaining gap.
     - **Measured, idr-trmc (2026-09-30):** `ins` returns a constructor
       around its own result in 12 of its tails (two clones), which now
       build the constructor first and pass the pending field as a
       destination to a clone that returns nothing; idr-tail-loops makes
       the clone a loop. rbtree went from 1.71–1.78 s to 1.36–1.39 s user
       on the same container (n = 4.2M), against Koka's 1.05 s. The tails
       that rebalance (`balanceLeft (ins l k v) …`) inspect the result and
       stay calls, as in Koka. The rest of the gap is the cell size, point
       2, and the count test, point 1.
- **Claim for the suite:**
  - at most 1.05 cells per insert;
  - no failed uniqueness test;
  - no count test on the build path;
  - time at most Koka's.

### 2.2 rbidx: rbtree with its invariants in its type

The program is in real-benchmarks-programs.md.

- **Stresses:** the same workload.
  - The colour is the constructor.
  - The black height is an erased index.
  - A red node's children are black by type.
  - The balance functions have no `Leaf` case and no mixed-height cases:
    the checker rejects them when they are written.
- **Old:**
  - 2.37 s with no reuse at all: 6.0 cells per insert and 43 bytes per node;
  - 2.1x faster than our old rbtree;
  - faster than Lean's rbtree.
- **New: a regression**, to 4.48 s and 17.8 cells per insert. The dump of
  `idr-rc` (`dump/rbidx/build/exec/prog.dump/06-idr-rc.mlir`) shows the
  cause. In `insAny`'s `TB` case:

  ```mlir
  %4:8 = idr.take %arg2 @RB::@TB : ... -> (!idr.token, ...)
  idr.dec %4#0 : !idr.token                       // the TB cell is freed
  %5 = idr.con @RB::@TB(%0, %0, %0, %4#4, %4#5, %4#6, %4#7) {idr.stack}
  %6 = func.call @Main.insB$spec$1(%0, %5, %arg3)
  ```

  `insAny (TB l x vx r) k v = unAny (insB (TB l x vx r) k v)` rebuilds the
  node it matched. Three things then go wrong:
  - `idr-stack` puts the rebuilt `TB` in the stack frame, because the cell
    itself does not escape `insB`; only its fields do.
  - The reuse pass leaves stack cells alone
    (`ResetReuse.cc`: "A box that is … built in the stack frame
    (`idr.stack`) is left alone").
  - So `insB` cannot reuse the cell it matches, and allocates, on every
    black node of the path.

  The pass order causes this: `idr-stack` (step 5) decides before `idr-rc`
  (step 6) can pair the token with the rebuild.
- **The representation fix:** after a match, rebuilding the same
  constructor from exactly the bound fields *is* the scrutinee.
  - A canonicalization `idr.con @C(fields bound by case @C of x) → x`
    removes the take, the free, the stack cell and the allocation at once.
  - real-benchmarks-programs.md proposed the same rewrite for the linear
    case.
  - It is a fact of the match, not of ownership, so it belongs before
    `idr-stack`.
- **Also here:** `idr.field %anyRB[@MkAny, 1]; idr.inc; idr.dec %anyRB`
  appears 27 times. It reads a field out of a dying register sum
  (`AnyRB`, `Almost`) instead of moving it. That is D2's pattern on
  `!idr.data`: IdrOps.td's `idr.take` already covers unboxed sums ("taking
  it apart changes no count").
- **Idris facts:**
  - the indices at quantity 0 (`!idr.erased`), so the height costs nothing;
  - the colour as the tag;
  - coverage, which leaves out the impossible cases;
  - the wrappers are `idr.data`, which live in registers.
- **Claim:**
  - at most rbtree's cells, which is 1.00 per insert;
  - 40 bytes per node;
  - time strictly below Koka's rbtree;
  - "the type is the representation", measured.

### 2.3 linrb and linrb-shared (gate experiment 4)

- **Stresses:** the same insert, with every tree bound at quantity 1.
  - The shared variant keeps one tree for one more step. Idris accepts
    that, because a shared value may be passed to a quantity-1 parameter.
- **Old:** neither compiled. `idr-simplify`'s verifier rejected Emit's
  module with "'idr.match' op uses a linear value that is already used on
  the same path".
- **New:** both compile, and so do both reproducers of
  real-benchmarks-programs.md (`lincase` prints 65 and `lincase2` 55,
  as on Chez).
  - linrb allocates 1.00 cell per insert, runs in 2.06 s (1.82x Koka's
    linrb) and never calls `idris_rt_dec` out of line.
  - linrb-shared is compiled *correctly*: it copies the path, at 19.3 cells
    per insert against Koka's 19.6. Its 4.16 s is 2.0x linrb in the same run,
    the same cliff Koka shows (4.31 s against 1.80 s, 2.4x).
- **Idris fact:** `!idr.lin`. A quantity-1 parameter is used once, so a
  take on it needs no test, *if every caller passes a unique value*.
  - That is a fact about the call sites, not about the binder (AGENTS.md:
    "a linear binder does not imply unique heap ownership").
  - linrb-shared is the test that the compiler respects the condition.
- **Missing:**
  - linrb's time equals rbtree's (2.06 against 2.11), so quantity 1 buys
    nothing yet;
  - the untested take for a linear parameter whose callers are all unique;
  - a report that names linrb-shared's call site as the one that costs
    the copy. The gate wanted a rejection; compiling it correctly is also
    sound, and the report is what makes the cliff visible, which Koka and
    Lean do not do.
- **Claim:**
  - linrb: no inc, no dec test and no count test on the tree; one cell per
    insert; time below Koka's linrb;
  - linrb-shared: correct output, and a compile-time report naming its call
    site. Or `unsupported` naming the call site; never an internal error.

### 2.4 fbip-rb (FP², Koka's `samples/basic/rbtree-fbip.kk`)

- **Stresses:** insertion that walks down building a zipper out of the
  cells it takes apart, then rebuilds the tree in them.
  - Every constructor built has the size of one just matched: `Node`,
    `NodeR` and `NodeL` all have five fields.
  - With unique cells, only the new leaf's node is allocated.
  - Koka checks this statically (`fip`/`fbip`).
- **New:** 1.00 cell per insert and 1.25 s.
  - That beats Koka's own fip version (1.43 s), C (2.00 s) and Chez (3.85 s).
  - It is within 1.09x of Koka's std rbtree (1.14 s).
  - It runs under an 8 MiB stack at n = 10^6.
- **Old:** 1.96 s, with 20.3 cells per insert.
- **Idris facts:**
  - uniqueness, inferred as for rbtree;
  - reuse across types: a `Tree` cell becomes a `Zipper` cell of the same
    size, and our pass pairs by size.

  No annotation is needed: we get from the ordinary program what FP² asks
  the programmer to prove.
- **Claim:**
  - at most 1.05 cells per insert;
  - an 8 MiB stack at n = 4.2M;
  - time at most Koka fip's, and within 1.1x of Koka std's.
  - It is also the target for rbtree: TRMC on rbtree should reach it.

### 2.5 tmap-fip and tmap-std (FP² §3)

Both were written for this stream, in Idris and Koka (sources in
real-benchmarks-programs.md). Each does 100 maps of `(+1)` over a balanced
tree of n leaves, then a sum.

- **New:**
  - both allocate only the initial tree (2n−1 cells), so 0 cells per map,
    as Koka does;
  - both run under an 8 MiB stack at n = 10^6. The tree is balanced, so this
    is not yet a stack test; a degenerate tree would be.
  - At n = 10^6:

    | | fip | std |
    |---|---:|---:|
    | ours | **1.57 s** | 1.75 s |
    | Koka | 1.82 s | **1.47 s** |
    | Chez | 25.1 s | – |

- **The claim this pair carries:** tmap-std should compile to what tmap-fip
  is.
  - FP² §3.1 shows that the fip version *is* the defunctionalized CPS form
    of the std version: the zipper constructors are the closures of
    `tmap(l, f, fn(l') …)`.
  - We already defunctionalize (`Defunctionalize.cc`), and TRMC is in
    architecture.md.
  - FP²'s side condition (each zipper constructor fits a cell the recursion
    just freed) is size arithmetic over known constructors, so it is
    decidable at compile time.
  - Idris facts: uniqueness for the reuse; totality, so that the
    transformed loop computes the same function.
  - Today our std is 1.11x our fip, and 1.19x Koka's std.

### 2.6 rbtree-ck (Perceus `rbtree-ck.kk`, Lean `rbmap_checkpoint.lean`)

- **Stresses:** the same inserts, keeping every fifth tree. The tree is
  unique again once the checkpoint list has its copy.
- **New:**
  - 4.86 cells per insert, the same as C and fewer than Koka (4.89);
  - 4.43 s: 1.46x Koka (3.03 s), 0.95x C and about 0.7x Lean.
  - In the three-round run, where Koka's best was 5.08 s, we beat Koka.
    The noise is that large.
- **Idris facts:** none that prove uniqueness, which is the point. This is
  the **control**:
  - whatever makes rbtree static must leave rbtree-ck correct;
  - the runtime tests must stay exactly where cells are shared. That is
    Perceus's dynamic reuse, which uniqueness-pipeline.md §7 keeps next to
    static reuse.
- **Claim:**
  - at most C's cells per insert;
  - the same output;
  - time at most Koka's;
  - `live cells 0`.

### 2.7 deriv, nqueens and cfold (Perceus / Beans)

These three are sharing-dominated. Ours and old differ little on them.

**deriv**
- **Stresses:** shared subterms. We allocate the fewest cells of anyone
  (2 327 against Koka's 2 940 and C's 3 687), because closed terms are
  static cells.
- **Time:** 1.80 s, 1.17x Koka's best (1.54 s). Koka ranged from 1.54 to
  4.13 s over today's runs; ours from 1.79 to 1.85.
- **Idris facts:**
  - every closed call of total code is evaluated at compile time;
  - specialization on the literal `"x"` would turn `x == y` in `d x (Var y)`
    into a compare with a constant. This is not traced.
- **Claim:** cells at most Koka's; time below MLton's.

**nqueens**
- **Stresses:** lists of lists that share their tails; nothing can be
  reused.
- **Time:** 1.03 s, which beats Koka (1.21 s) and C (1.45 s). It also uses
  the least memory (94 MiB).
- **Idris facts:** `safe` borrows its list, and `Int` elements are unboxed
  in the cons cell.
- **Claim (control):** time at most Koka's; frees at most C's.

**cfold**
- **Stresses:** a term of depth 20, reassociated and folded; `reassoc`
  recurses 2^19 deep.
  - `e` is read by `eval e`, then consumed by `reassoc e`. After the
    borrow ends it is unique, and every `Add`/`Mul` cell can be reused.
- **Time:** 0.36 s, 1.31x Koka and 0.90x Lean. We allocate 46 147 cells,
  fewer than Koka's 49 258.
- **Where the reuse goes:** 31 134 tokens are freed unused, up from 20 756.
  Two thirds of the cells taken apart are not rebuilt in place, because
  `Add e1 e2` becomes `Val (a+b)`, a smaller constructor. So the loss to
  Koka is not allocation. It is conjecture that it is the 2^19-deep
  recursion's frames, where Koka's TRMC applies to `appendAdd`'s spine.
- **Idris facts:**
  - `eval` borrows, so `e` is unique when `reassoc` starts;
  - `Expr` is closed, so a token of a larger cell may hold a smaller
    constructor if the size classes allow it.
- **Claim:**
  - cells at most C's;
  - time at most Koka's;
  - depth 2^19 under an 8 MiB stack. The frames are FP² §2.5's evaluation
    contexts ("Stack Safe FIP"); TRMC or a zipper bounds them.

### 2.8 binarytrees (Benchmarks Game; Lean `binarytrees.st.lean`)

- **Stresses:** allocate, walk and free a tree many times, beside one
  long-lived tree.
- **Time:** 8.01 s. That is 0.83x Lean, 0.78x MLton, 0.47x Koka and 0.30x
  C (glibc malloc). It uses 110 MiB, the least.
- **Why:** allocation and free are both inlined, as a snmalloc free-list
  pop and push (runtime/alloc.cc:1-6).
- **Idris facts:** in `check (make' i d)` the tree is built and consumed at
  once; no reference survives `check`, and both functions are total and
  pure. So the tree could live in a region freed in one step. Fusing
  `check ∘ make'` would also be legal, but it would defeat the benchmark.
- **Claim:**
  - ahead of Lean and MLton;
  - O(1) frees per checked tree, measured with runtime counters (§6).

### 2.9 qsort and unionfind (Lean `qsort.lean`, `unionfind.lean`)

- **Stresses:**
  - qsort updates `Bits32` arrays in place;
  - unionfind keeps an array of two-`Int` records and compresses paths.
  - Both use base's `Data.IOArray.Prims`, because `Data.IOArray` boxes
    every element in a `Just`.
- **Both are rejected**, in the old and the new build:
  - qsort: `Main.mkRandomArray: unsupported (escape hatch): %extern
    Data.IOArray.Prims.prim__newArray`;
  - unionfind: `unsupported (program): imports System, which is neither a
    user module nor a trusted module`, for `exitWith`.
  - The field:

    | | qsort | unionfind |
    |---|---:|---:|
    | C | 1.42 s | 0.17 s |
    | MLton | 1.97 s | 0.43 s |
    | Lean | 2.85 s | 2.97 s |
    | Koka | 36.97 s | 3.82 s |

    Koka's vector is copied: it has no mutable array.
- **Idris facts:**
  - elements of closed scalar type are unboxed: `Bits32` as `i32`, and
    `NodeData` as two inline `i64`;
  - in-bounds indices can be `Fin n`, so no bounds check
    (representation.md R5);
  - a uniquely threaded pure array is updated in place, through the
    tensor → bufferization path (mutable-buffers.md,
    decision-linear-libraries.md).
- **Missing:** registry meanings for the array primitives and for
  `System.exitWith`.
- **Claim:**
  - qsort within 1.1x of C, both in its IOArray form and in a pure `Fin`
    form;
  - unionfind within 1.5x of C, which is 17x ahead of Lean.

### 2.10 Idiomatic variants

The same workloads, written as an Idris programmer writes them: Nat,
Integer, ranges, `sum`/`map`, and contrib's `SortedMap`.

| variant | ours, old | ours, new | Chez, same run |
|---|---:|---:|---:|
| binarytrees with Nat and ranges, depth 12 | 6.6 s | **0.010 s** | 0.137 s |
| … at depth 21 | – | 10.8 s, 366 MiB | 11.6 s |
| deriv with `Integer` | 13.2 s, 3.5 GB | **2.08 s**, 425 MiB | 5.16 s |
| cfold with Integer and Nat | 0.35 s | 0.37 s | 1.03 s |
| nqueens with Nat and `length` | 25.0 s | 23.5 s | 92.3 s |
| binarytrees with a depth-indexed `PTree d` | 8.7 s | 5.6 s | 13.3 s |
| rbtree via `Data.SortedMap` | rejected | rejected | – |

- **The Nat work fixed the collapse:** binarytrees and deriv.
- **What remains:**
  - idiomatic nqueens is still 23x our `Int` version;
  - idiomatic binarytrees at depth 21 is 1.35x the `Int` one, with 3.3x
    its memory;
  - contrib's `SortedMap` is rejected: `unsupported (runtime closure): an
    implementation chosen at runtime` in `Data.SortedMap.Dependent.insert`.
- **Why the suite needs idiomatic programs:** the `Int` versions flatter us.

## 3. FP²'s fully-in-place programs

FP² (Lorenzen, Leijen and Swierstra, ICFP 2023) §6, Fig. 10 benchmarks
five programs: rbtree, ftree, msort, qsort and tmap. Each does 100
iterations over structures of 100 000 elements. The paper finds three
things:
- fip is faster than std;
- std-reuse (Koka's default) is close to fip;
- both are near C++.

We now have two of the five:
- **fbip-rb** (§2.4): we beat Koka's fip version.
- **tmap** (§2.5): we beat Koka's fip version, and lose 1.19x to its std
  version.

The other three are not ported yet:
- **msort and qsort (§4.2)** are in-place list sorts through a partition
  type (`Sub`/`One`/`End`, `Cons2`/`Nil2`) that holds n elements in the n
  cells of the input list. They test reuse across *three* types of equal
  cell size.
- **ftree (§4.3)** and **splay trees (§1)** need FP²'s unboxed tuples and
  "atoms" (§1.2): nullary constructors that give a reuse credit. We should
  derive those from the constructor sizes rather than ask for them.

## 4. What the measurements say about the design

1. **Reuse placement was the whole gap on the reuse benchmarks, and the new
   build closed it.** Allocation now equals Koka's and C's on rbtree,
   rbtree-ck, linrb, fbip-rb and tmap.
   - What is left is not allocation. rbtree's 1.84x against Koka comes
     from cell size and recursion shape, and fbip-rb's 1.25 s shows the
     shape is worth about 1.7x.
   - So the next levers are:
     - TRMC (architecture.md);
     - finite-field packing (point 2 below);
     - static uniqueness, which removes the per-take test that Koka keeps,
       and is the step that goes past Koka (uniqueness-pipeline.md).
2. **Cell size: Idris knows the finite types, and representation.md has no
   rule for them.**
   - The rule: a field whose type is closed and finite after
     monomorphisation (an enum like `Color` or `Bool`, or `Fin k` for
     small k) is packed. There are two ways to pack it:
     - split the constructor by the field's value (`Node Red …` becomes
       `NodeRed …`), so the field becomes part of the tag the match
       already reads;
     - or pack it with its siblings into one word.
   - It is sound because the value set is closed, and R3's head-shape
     verifier covers the tag space.
   - It lives in the layout attribute (R2/R3), never in a discardable
     attribute.
   - rbtree's cell would go from 48 to 40 bytes.
3. **Rebuilding what was just matched must be the identity.** rbidx's
   regression (§2.2) is a missing canonicalization, not a missing analysis.
   `idr.con @C(the fields case @C bound from x)` is `x`. It removes a take,
   a free, a stack cell and an allocation per black node.
   - It is the same rewrite real-benchmarks-programs.md proposed for
     linear scrutinees.
   - It belongs before `idr-stack`, whose choice otherwise pre-empts reuse.
   - More generally: `idr-stack` (step 5) runs before `idr-rc` (step 6), so
     a cell that could be reused may be put on the stack first. When a
     cell is both stackable and a reuse target, reuse should win.
4. **Where we win on sharing-dominated programs, we win on allocation
   cost, not on facts.** In deriv, nqueens and binarytrees:
   - allocation is inlined;
   - frees are iterative;
   - closed terms are static.

   None of linearity, erasure, indices or totality is used yet. The suite
   separates these cases by naming each program's fact.

## 5. The proposed real-programs suite

Fifteen programs, each with one claim that a machine checks. Time is always
against `min(Koka, Lean)` in the same interleaved run. Allocation is
checked against a fixed number.

| # | program | source | Idris fact it exploits | claim (checked) | today |
|---|---|---|---|---|---|
| 1 | rbtree | Perceus / Beans | uniqueness inferred over the call graph | ≤ 1.05 cells per insert; 0 failed takes; 0 count tests on the path; time ≤ Koka | cells ✓; time 1.84x |
| 2 | rbidx | this stream | erased indices (`!idr.erased`); colour as the tag; coverage | ≤ rbtree's cells; 40 B/node; time < Koka's rbtree | regressed (§2.2) |
| 2b | rbtree-split | rbtree with the colour moved into the constructor (`NodeRed`/`NodeBlack`) | a closed finite field packed into the tag (§4, point 2) | the compiler's packing of #1 equals the hand split: same cells, same bytes per node | new |
| 3 | linrb | gate experiment 4 | `!idr.lin` with unique callers | 0 inc, 0 dec test, 0 count test on the tree; 1 cell per insert; time < Koka | cells ✓; time 1.82x |
| 3b | linrb-shared | gate experiment 4 | call-site uniqueness | correct output and a report naming the call site (or `unsupported`); never an internal error | correct, no report |
| 4 | fbip-rb | FP² / Koka sample | uniqueness; reuse across `Tree` and `Zipper` cells of the same size | ≤ 1.05 cells per insert; 8 MiB stack at n = 4.2M; time ≤ Koka fip | ✓ (0.88x) |
| 5 | tmap-std and tmap-fip | FP² §3 | uniqueness; totality; defunctionalized CPS | 0 cells per map; flat stack on a degenerate tree; std within 1.05x of fip; ≤ Koka | cells ✓; std 1.19x Koka std |
| 6 | msort-fip | FP² §4.2 | uniqueness; reuse across three types of equal size | 0 cells after the input list; ≤ Koka fip | to port |
| 7 | rbtree-ck | Perceus / Beans | none: the sharing control | ≤ C's cells per insert (4.86); output identical; time ≤ Koka | cells ✓; time 1.46x (noisy) |
| 8 | deriv | Perceus / Beans | static closed terms; compile-time evaluation; specialization on the literal | cells ≤ Koka's; time < MLton | cells ✓; time ≈ MLton |
| 9 | nqueens | Perceus | borrowing; unboxed `Int` fields; the control for shared tails | time ≤ Koka; frees ≤ C's | ✓ |
| 10 | cfold | Perceus / Beans | uniqueness after the last borrowed use | cells ≤ C's; time ≤ Koka; depth 2^19 under an 8 MiB stack | 1.31x; cells 1.4x C |
| 11 | binarytrees | Benchmarks Game / Beans | purity and non-escape, so a region | time ≤ Lean and MLton; O(1) frees per checked tree | time ✓ |
| 12 | qsort | Beans (IOArray form and pure `Fin` form) | unboxed `Bits32`; `Fin n` bounds; a unique array is updated in place | compiles; within 1.1x of C in both forms | rejected |
| 13 | unionfind | Beans | a record of two `Int`s unboxed in the array; `Fin` indices | compiles; within 1.5x of C | rejected |
| 14 | sortedmap | contrib `Data.SortedMap` | monomorphised `Ord` dictionary (a closed instance) | compiles; within 1.5x of #1 | rejected |
| 15 | idiom-nqueens | nqueens with Nat, `length` and ranges | Nat as a word where its range is proved (decision-nat) | within 1.5x of #9 | 23x |

- **Programs 1 to 6** are the static-reuse and representation claims, the
  reason this compiler exists.
- **Programs 7 to 11** are controls that must not regress. We already win
  most of them.
- **Programs 12 to 15** are coverage: what an Idris programmer writes has to
  compile and be fast.
- **New programs:**
  - 2b is a ten-line edit of rbtree;
  - 5 exists (`src/tmap-*`, `src/kk/`);
  - 6 is a port of FP² §4.2;
  - 14 and 15 exist in scratch (`idiom/`).
  - 5 also needs a degenerate-tree input for the stack claim, because a
    balanced tree only recurses to depth 20.

## 6. What bench/ needs to run it routinely

1. **An `ours` column in the gate's suite.**
   - `bench/gate/run.sh suite` builds Chez, MLton, C, Koka and Lean
     (`lib.sh` `build_chez` … `build_lean`), but never this compiler. Only
     the hand-lowered prototypes of experiments 2 to 4 stand in for it.
   - Add `build_ours`: `tools/compile.sh Main.idr prog`, under
     `flock -s build/.tree.lock`.
   - Add a verdict per program: the time against `min(Koka, Lean)`.
   - `bench/run.sh` already has "this compiler", but no Koka or Lean. The
     simplest merge is `bench/run.sh --suite gate`, sourcing `gate/lib.sh`'s
     builders.
2. **Runtime counters, instead of gdb.**
   - Add a stats variant of the runtime archive, counting:
     - cells allocated and freed;
     - takes found exclusive and found shared;
     - incs and decs;
     - tokens freed unused;
     - maximum stack depth.
   - Compile it separately, so the timing builds carry no counter, and
     print the counts at exit as `IDRIS_RT_LIVE` does (runtime/io.cc).
   - `idris-mlir-cc --runtime=<archive>` already selects an archive
     (idris-mlir-cc.cc:112); a `--directive rt-stats` in `tools/compile.sh`
     would pass it.
   - Today the counts need gdb on out-of-line entries: it misses what LTO
     inlines, and takes minutes at n = 20 000. Callgrind cannot run our
     binaries at all.
   - The gate's prototype had exactly this switch (`IDR_GATE_STATS`).
3. **Static counts next to the dynamic ones.** `idris-mlir-cc --stats`
   exists (idris-mlir-cc.cc:517). Record:
   - `numReuses` and `numIncs` (Passes.td:396-399 at `bd274ba`);
   - `numCells`, the stack cells (Passes.td:282).

   With both, a claim like "linrb: 0 count tests on the tree" is checked
   statically and dynamically.
4. **A `claim` file per program**, beside `bench/<name>/input` and
   `rejected`. It holds the properties as data, for example:

   ```
   cells-per-op <= 1.05
   failed-takes = 0
   stack 8192
   ```

   The runner evaluates them against the counters. The claim is then
   written once, not re-encoded in a script. This is AGENTS.md's
   "expressive check", at the benchmark level.
5. **CPU time and interleaving.**
   - The machine is shared, and wall-clock best-of-5 (`tools/measure.c`)
     swings 2x or more under load.
   - Report user + sys from `wait4`'s rusage, which `measure.c` already
     calls.
   - Interleave the compilers within each round, as `cpu.sh` does.
   - Take the best of at least 5 rounds; for memory-bound programs, give
     the spread too.
   - Time criteria only mean something on a quiet machine. Allocation
     criteria mean something on any machine, so gate on those first.
6. **One C compiler.** The gate uses GCC -O2 and `bench/run.sh` uses clang
   x86-64-v3; the C column should mean the same thing in both.
7. **A toolchain-consistency check before measuring.**
   - Today's failure was two halves of the compiler built from different
     trees. For 45 minutes every program failed with an internal error
     that says nothing about the program.
   - The runner should record the commit, the dirty-file count, and the
     build times of the frontend, `idris-mlir-cc` and the runtime archive.
     It should refuse to report when those come from different builds.
   - The coordinator killed one unlocked `make build` during this stream.
     It was not mine: this stream only ran `tools/compile.sh` and read-only
     tools under `flock -s`.

## Open questions

1. **rbtree against Koka at equal allocation.** Which part of the remaining
   1.84x is cell size (48 against 33 bytes) and which is the recursion
   shape (TRMC)? Two measurements would answer it: rbtree-split (#2b), and
   rbtree with TRMC applied to `ins`.
2. **The per-take test.** With static uniqueness it goes away. How much is
   it worth on rbtree? It is inlined, so measuring it needs the stats
   runtime or a build without the test.
3. **cfold.** We allocate fewer cells than Koka and still run 1.31x
   slower. Is it the 2^19-deep recursion, or the counts on the `Val` path?
4. **Stack against reuse.** Should `idr-stack` run after reuse pairing, or
   leave a cell that a later match will take? The canonicalization of §4, point 3,
   fixes rbidx either way, but the ordering question is general.
5. **linrb-shared.** Should it be rejected (the gate's plan), or compiled
   with a report of the call site? Both are sound. The report keeps Idris's
   acceptance of the program; the rejection is simpler to test.
