# The memory gate

The four experiments of [docs/plan.md](../../docs/plan.md) section 4.4,
which decide whether the memory design of section 4 is built: reference
counting Lean's way, with guaranteed reuse where quantities promise it, a
heap per core, and move-or-mark where values cross cores. They run before
every other milestone (plan section 10); if the gate fails, the memory
decision is reopened with the numbers.

Nothing here has been timed yet: the tables below are empty until a run
fills them in.

## Running it

```
bench/gate/toolchains.sh              # once: Lean, Koka and Go into .toolchain/
bench/gate/run.sh                     # all four experiments
bench/gate/run.sh suite lowered       # or some of them: suite, lowered, threads, linear
```

For the Makefile, a `gate` target is `bench/gate/run.sh $(ARGS)`, as
`bench` is `bench/run.sh $(ARGS)`.

- **Measurement.** Every program is timed `RUNS` times (default 5). The best
  wall-clock time is kept, and the largest peak RSS of the runs, measured
  by [tools/measure.c](tools/measure.c) through `wait4` (the container has
  no `time(1)`). Stacks are unlimited, since some programs recurse a
  million deep.
- **Outputs.** Every output must be byte-for-byte the reference output: the
  Idris program's on Chez, or else C's, or Go's for experiment 3.
- **Results** go to `$GATE_OUT/results` (default `build/gate/results`):
  - one Markdown table per experiment (`suite.md`, `lowered.md`,
    `threads.md`, `linear.md`), in the shape of the tables below;
  - every measurement in `results.tsv`;
  - every criterion's verdict in `verdicts.txt`, one line each: `pass`,
    `FAIL`, or `n/a` when something could not be measured.
- **Exit status:** 0 when everything checked passed; 1 when a criterion
  failed, an output differed or a program failed; 2 when nothing failed but
  something was missing (a toolchain), so the gate is incomplete.
- **Environment:**
  - `GATE_OUT`: where builds and results go;
  - `RUNS`: runs per measurement; `CHEZ_RUNS` for the Chez baseline alone,
    whose runs are the longest;
  - `GATE_SMALL=1`: small inputs, to check the scripts and the outputs in
    minutes (its times mean nothing);
  - `SNMALLOC_SRC`: snmalloc's `src/` (default `third_party/snmalloc/src`);
  - `CXX`: the runtime prototype's compiler (default: `clang++` of
    `.toolchain/llvm` if present, else the pinned `g++`);
  - `CLIFF`: experiment 4's slowdown threshold (default 1.2).
- `bench/gate/lower.sh NAME [VARIANT]` builds one lowered program alone.

### Toolchains

| | Version | From | Notes |
| --- | --- | --- | --- |
| Idris 2, Chez backend | the pinned revision | `.toolchain/idris2` (`make bootstrap`) | the baseline |
| MLton | 20210117 | `.toolchain/mlton` (the Debian package) | `-default-type int64`, as `bench/` |
| C | the pinned GCC | `.toolchain/gcc` | `-O2`, as `bench/` |
| Koka | 3.2.9 | GitHub release, `toolchains.sh` | `-O2 --stack=128M`, as the Perceus benchmarks; C by the system `gcc` (the release's libraries are gcc's), `-march=haswell` |
| Lean 4 | 4.34.1 | GitHub release, `toolchains.sh` | `lean -c`, then `leanc -O3 -DNDEBUG`, as Lean's benchmarks |
| Go | 1.24.13 | Ubuntu 24.04 packages, `toolchains.sh` | default settings |
| MLIR and LLVM | the pinned revision | `.toolchain/llvm` | `mlir-opt`, `mlir-translate`, `opt`, `llc` |
| snmalloc | `e9f7b2e` (0.7.5-15) | `third_party/snmalloc` | 8-byte size-class steps (plan 5.6) |

- `toolchains.sh` checks every download against a pinned SHA-256 and
  unpacks it into a temporary directory first, so an interrupted run leaves
  nothing half installed. It keeps a toolchain whose `provenance.json`
  names the pinned version.
- Lean's release unpacks to 3.3 GB, 2.9 GB of it compiled libraries that
  only `import Lean`, `Std` or `Lake` need; the script leaves those out
  (1.4 GB remain).
- Lean and Koka are the official release binaries, pinned by version and
  checksum, rather than builds from source as plan 10.1's stream K
  planned.

## Experiment 1: the suite

Eight allocation benchmarks, each in five languages, in
[suite/](suite/)`<name>/`: `Main.idr`, `<name>.sml`, `<name>.c`, `<name>.kk`
and `<name>.lean` (with `_` for `-` except in Koka).

| program | from | input | what it stresses |
| --- | --- | --- | --- |
| `rbtree` | Perceus `rbtree.kk`; Lean `rbmap.lean` | 4 200 000 keys | red-black tree insertion into an unshared tree: full reuse |
| `rbtree-ck` | Perceus `rbtree-ck.kk`; Lean `rbmap_checkpoint.lean` | 4 200 000, every 5th tree kept | the same with sharing: path copying |
| `deriv` | Perceus `deriv.kk`; Lean `deriv.lean` | 10 derivatives of x^x | symbolic terms with shared subterms |
| `nqueens` | Perceus `nqueens.kk` | 13 | lists of lists sharing their tails |
| `cfold` | Perceus `cfold.kk`; Lean `const_fold.lean` | depth 20 | building, reassociating and folding a large term; recursion 2^19 deep |
| `binarytrees` | Benchmarks Game; Lean `binarytrees.st.lean` | 21 | allocate, walk, free; one long-lived tree |
| `qsort` | Lean `qsort.lean` | 400 | arrays updated in place |
| `unionfind` | Lean `unionfind.lean` | 3 000 000 | arrays of records, path compression |

The Koka and Lean versions are the published ones (Koka's
`test/bench/koka`, Lean's `tests/compile_bench`), changed only so that
every version reads its input from stdin and prints the same text:

- `rbtree-ck` prints Lean's list length before the count, in every
  language. Lean's keys run from n-1 to 0 and the others' from n to 1,
  which print the same for n a multiple of 10.
- `deriv` does not print Koka's final `done`.
- `cfold` prints both values on one line, as Lean's.
- `binarytrees` runs on one core in every language (Perceus's version uses
  tasks; the parallel one is experiment 3's `ptrees`). The loop passes its
  counter as the seed of `make'`, so no compiler can hoist the tree out of
  the loop.
- `qsort` also prints the sum of the sorted arrays' middle elements, and
  its check returns a Bool instead of throwing.
- `qsort` and `unionfind` in Koka are new: Koka has no mutable array type,
  so they update a vector in a local variable, in place while it is
  unshared, as Lean's pure arrays are.
- `nqueens` in Lean is new (Lean has none).

The other languages:

- **Idris** uses the stock Prelude and base only, and runs on the Chez
  backend. The sources stay within what milestone 1 compiles: `Int`
  everywhere (no `Integer` or `Nat`, which are M2), no closures that must
  exist at runtime, and base's array primitives (`Data.IOArray.Prims`) for
  `qsort` and `unionfind`, since `Data.IOArray` boxes every element in a
  `Just`.
- **SML** follows the Counting Immutable Beans SML versions (`rbmap.sml`,
  `rbmap_checkpoint.sml`, `deriv.sml`, `const_fold.sml`, `qsort.sml`,
  `binarytrees.st.sml`) where there is one.
- **C** is what a C programmer writes: in-place updates where the
  functional version can reuse every cell (`rbtree`, `cfold`), reference
  counts where cells are shared (`rbtree-ck` copies on write, `deriv`,
  `nqueens`), malloc and free for `binarytrees`, plain arrays of values for
  `qsort` and `unionfind`. It is the floor, not a criterion.

Results (best of 5, seconds, peak RSS in MiB):

| benchmark | input | Idris Chez | MLton | C | Koka | Lean | outputs |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| rbtree | 4200000 | | | | | | |
| rbtree-ck | 4200000 | | | | | | |
| deriv | 10 | | | | | | |
| nqueens | 13 | | | | | | |
| cfold | 20 | | | | | | |
| binarytrees | 21 | | | | | | |
| qsort | 400 | | | | | | |
| unionfind | 3000000 | | | | | | |

## Experiment 2: hand-lowered code

`rbtree`, `deriv` and `binarytrees`, written by hand in
[lowered/](lowered/) as the code `idr-lower` will emit after M1: `func`,
`arith`, `cf` and `llvm` operations, as `idr-lower` emits today, before the
standard conversions. Each file says what Lean's passes decide for its
program.

- **Cells** (plan 4.3). An 8-byte header: a 32-bit count, then the kind, the
  constructor tag, the number of pointer fields and the size in words.
  Pointer fields come first. A nullary constructor is the immediate
  `tag << 1 | 1`. The header is one 64-bit store.
- **Counts.** `idr.dup` and `idr.drop` are inlined fast paths: plain
  arithmetic while the count is positive and below `INT32_MAX` (above 1 for
  a drop), nothing for a persistent cell (count 0), and a call into the
  runtime for shared (negative, atomic) counts, for the count that sticks
  at `INT32_MAX`, and for freeing. ([lowered/prelude.mlir](lowered/prelude.mlir)
  holds them, as `Lower/Runtime.mlir.inc` holds today's helpers.)
- **Borrowing.** `check`, `count`, `d`, `lookup` and the folds borrow their
  argument, so walking it counts nothing; `d` duplicates a subterm only
  where it passes it to a function that owns its argument.
- **Reset and reuse with hot and cold paths.** The sources bind at quantity
  omega, so reuse is Lean's best effort: a reset tests the count. At 1, the
  cell becomes a token and its fields move to locals. Otherwise the fields
  are duplicated, the cell dropped, and the token is null. A reuse stores
  only the fields that change, or allocates when the token is null.
- **Freeing is iterative**, in the runtime, through a free list that runs
  through the dying cells' headers (Lean's `lean_del_core`).
- **Closed terms are static cells** with count 0 in read-only data
  (`deriv`'s `Val 0`, `Var "x"`, `x^x`).

**The runtime prototype**, [foreign/idr/bench/gate/](../../foreign/idr/bench/gate/)
(C++ lives only under `foreign/idr`): one allocation and one free entry per
size class over `snmalloc::alloc<S>`, the counts' slow paths, the iterative
free, move-or-mark, threads, channels, and its statistics. It is restricted
C++ as the real runtime will be (no exceptions, no RTTI, no standard
containers). Build switches:

| variant | defines | used for |
| --- | --- | --- |
| `plain` | none | every timing |
| `stats` | `IDR_GATE_STATS` | counts cells, frees, atomic count operations, cells marked and moved; prints them at exit |
| `flush`, `home`, `flush-home` | `IDR_GATE_FLUSH`, `IDR_GATE_HOME` | experiment 3's pipeline variants |

**Lowering** ([lower.sh](lower.sh), `lower` in [lib.sh](lib.sh)) concatenates
the prelude and the program, then runs idris-mlir-cc's last steps with the
pinned tools, with plan 5.7's settings from milestone 1:
`mlir-opt` (canonicalize, cse, convert-scf-to-cf, convert-to-llvm,
reconcile-unrealized-casts), `mlir-translate`, `opt` (internalize every
symbol but `idr_main`, then O3, for `x86-64-v3`) and `llc` (O3, PIC,
64-byte alignment as OPT-PIPE-4). `$CXX` links the object with the runtime.

- **Not yet whole-program LTO.** The program and the runtime are separate
  objects, so each allocation and each cold count operation is a call; plan
  5.7 inlines them. This handicaps the prototype. Lean's and Koka's
  allocators are called the same way.
- The stats build's `live` (cells allocated minus freed) must be 0 at exit:
  the hand-lowered counts free everything, which the runner checks.
- **Lean 4.34.1 reuses less than the Beans paper describes.** In the C it
  emits for `rbtree` (Lean's own `rbmap.lean`), `ins` tests uniqueness 15
  times, but on most branches it frees the reset cell (`lean_del_object`)
  and allocates a new one instead of updating it in place: each rebuilt
  node costs a free, an allocation and the stores of all its fields, where
  an update in place costs only the changed stores. The criterion takes
  the better of Lean and Koka, so this does not make it easier.

**Pass** (plan 4.4), for each of the three programs:

- faster than MLton: t(prototype) < t(MLton);
- within 1.2x of Lean's or Koka's generated C, read strictly:
  t(prototype) <= 1.2 x min(t(Lean), t(Koka));
- peak memory at most MLton's.

| program | input | prototype | MLton | Lean | Koka | MLton / prototype | prototype / best of Lean, Koka | live | verdict |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| rbtree | 4200000 | | | | | | | | |
| deriv | 10 | | | | | | | | |
| binarytrees | 21 | | | | | | | | |

## Experiment 3: threads

Three programs on the prototype with move-or-mark (plan 4.3, 7.4), each
with a Go version in [threads/](threads/)`<name>/`. The lowered programs
share the trees of experiment 2 (`bintree.mlir`, `rbmap.mlir`).

| program | what it does | what crosses cores | input |
| --- | --- | --- | --- |
| `ptrees` | parallel binarytrees: each depth's trees split into 8 work items that idle cores take, as futures | only scalars | 21 |
| `shmap` | a red-black map of n keys built on core 0 and read by every core, which each inserts a few keys into its own version | the map, marked shared once | n = 1 000 000, 1 000 000 lookups per core |
| `pipe` | producer and consumer pairs (cores 0 to 1, 2 to 3): trees built on one core, checked and dropped on the other | every tree, moved | 20 000 trees of depth 10 per pair |

- **Move-or-mark** (`idr_send`): one walk over the value crossing. A cell
  with count 1 is moved: nothing is written, it stays non-atomic, and its
  cells are freed remotely into the producer's heap. A cell with a higher
  count is marked shared, with everything it reaches.
- **The counter of atomic operations** is the stats build's `atomic-rc`:
  every atomic read-modify-write on a count. The runtime performs one only
  on a count that is negative, that is, on a cell marked shared.
- **Variants of the pipeline** (plan 5.6 and 12.2 item 8): `flush` sends the
  allocator's batched remote frees at the end of every consumer turn;
  `home` sends each dead root back to its producer, which drops the tree
  locally; `flush-home` does both. They are measured and reported, with no
  criterion.
- **Not measured:** 12.2 item 7, marking a future's captures at spawn
  against a handshake at steal time. No program here captures a heap value
  in a future.

**Pass** (plan 4.4):

- atomics only on genuinely shared data: `ptrees` and `pipe` have
  `atomic-rc` = 0 and `marked` = 0; `shmap` marks exactly the map's n cells;
- each program no slower than Go's: t(prototype) <= t(Go).

| program | input | prototype | Go | Go / prototype | atomic-rc | marked | moved | verdict |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| ptrees | 21 | | | | | | | |
| shmap | 1000000 1000000 | | | | | | | |
| pipe | 20000 10 | | | | | | | |

| pipeline variant | time, peak RSS |
| --- | ---: |
| plain | |
| flush | |
| home | |
| flush-home | |

## Experiment 4: the linear red-black tree

[linear/linrb/Main.idr](linear/linrb/Main.idr) inserts with every tree bound
at quantity 1. The algorithm is Lean's `rbmap`; its `isRed` tests are
matches inside `ins` that rebuild the node they matched, which a unique
cell makes free. It is an Idris program that typechecks and runs on Chez.

- **Static reuse:** `lowered/linrb-static.mlir` + `linrb.mlir`, as the
  compiler will emit it under `MEM-LIN-1`: a reset is the cell itself (no
  count test), a reuse stores the fields that change (no null test), and
  no dup is emitted anywhere.
- **Dynamic reuse:** `lowered/linrb-dynamic.mlir` + `linrb.mlir`, Lean's
  best effort: the same program, with a count test at every reset.
- **The cliff:** `linrb.kk` and `linrb.lean` are the same program in Koka
  and Lean (with `balance1` and `balance2` `@[inline]` in Lean, as in its
  `rbmap.lean`). [linear/linrb-shared/](linear/linrb-shared/) changes one
  call site: the build loop keeps the tree it passes to insert for one more
  step (`mkMap n1 (insert n1 v t) t`). Idris accepts that (a shared value
  may be passed to a quantity-1 parameter); `MEM-LIN-1` must reject it in
  M1. Koka and Lean compile it without a word, and every insert copies its
  path.
- **Lean reuses less to begin with.** In the C that Lean 4.34.1 emits for
  `ins`, the red-node branches free the cell they reset
  (`lean_del_object`) and allocate a new one, even when the tree is
  unique. So Lean copies part of each path in the unique version too, which
  narrows the cliff this experiment can show in Lean. An earlier form of
  the program, with the red tests in separate mutually recursive functions,
  reused even less in Lean (they are not inlined), and was dropped for
  this one in every language.

**Pass** (plan 4.4):

- the guaranteed form is at least as fast as the dynamic one:
  t(static) <= t(dynamic);
- the broken call site shows the cliff in Koka and Lean: a slowdown of at
  least `CLIFF` (1.2x), and no warning or error about the source in the
  compiler's output.

The runner also checks that both lowerings allocate exactly one cell per
insert (full reuse) and free every cell.

| version | unique | shared | shared / unique | verdict |
| --- | ---: | ---: | ---: | --- |
| Idris Chez (baseline) | | | | |
| prototype, static reuse | | rejected by `MEM-LIN-1` in M1 | | |
| prototype, dynamic reuse | | | | |
| Koka | | | | |
| Lean | | | | |

In the compiler, M1's exit criteria then require that `linrb` compiles with
zero dups and full reuse, and that `linrb-shared` is rejected with
`MEM-LIN-1` at its changed call site.

## Layout

| path | contents |
| --- | --- |
| `toolchains.sh` | fetches Lean, Koka and Go |
| `run.sh` | runs the experiments |
| `lib.sh` | paths, inputs, builds, measurement, lowering |
| `lower.sh` | lowers and links one program of `lowered/` |
| `tools/measure.c` | time and peak RSS of one run |
| `suite/` | experiment 1 |
| `lowered/` | the hand-lowered programs of experiments 2 to 4 |
| `threads/` | the Go versions of experiment 3 |
| `linear/` | experiment 4's sources |
| `../../foreign/idr/bench/gate/` | the runtime prototype |
