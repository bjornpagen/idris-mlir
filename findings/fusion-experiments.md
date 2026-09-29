# Fusion: experiments and raw notes

Evidence for `findings/fusion.md`. The scratch directory is
`scratchpad/research/fusion/` (the session scratchpad):
- one directory per Idris program, each built with
  `tools/compile.sh [-p base] --directive dump-mlir Main.idr prog`;
- `chez/<name>/`: the same source through the pinned Idris's Chez backend;
- `ref/`: MLton and C versions of the same pipelines;
- `mlir/`: hand-written upstream-MLIR experiments run with the pinned
  `mlir-opt`;
- `timeit.py`: best-of-N wall time, exit status, RSS and first output line.

Every run was under `timeout`, and every compile took the shared tree lock.
"Segfault" means exit status -11 (SIGSEGV), a stack overflow with the default
8 MiB stack.

## X1. Eight pipelines through today's compiler

Each program reads `n` from stdin with the usual `readInt` loop, then runs the
following.

| name | the pipeline (Idris source) |
|---|---|
| `summap` | `sum (map f [1 .. n])`, where `f x = x * x + 1` |
| `chain` | `foldl (\acc, x => acc + x) 0 (map (* 3) (filter (\x => x `mod` 3 == 1) [1 .. n]))` |
| `lenzip` | `length (zip [1 .. n] (map (* 2) [1 .. n]))`, with `-p base` for `Data.Zippable` |
| `compr` | `sum [x * y \| x <- [1 .. n], y <- [1 .. 100], (x + y) `mod` 7 == 0]` |
| `trav` | `traverse_ printLn (map (\x => x * 7 + 1) [1 .. n])` |
| `userpipe` | user-written `total' 0 (bump (upto 1 n))`: an unfold, a map and a foldl, as first-order recursions |
| `vstat` | a tail loop whose body computes `foldl (+) 0.0 (zipWith (*) (map (* k) v) (map (+ 1.0) w))` on two `Vect 4 Double` literals |
| `vdyn` | the same chain over `Vect m Double` with runtime `m`, built by `build : (m : Nat) -> Double -> Vect m Double` |

### Where each intermediate lives (dump `05-idr-rc.mlir` and `07-idr-lower.mlir`)

The allocation sites are the calls to `@idris_rt_cell` after idr-lower, counted
per function:

```
summap   takeUntil$spec$1 case block (2), takeUntil$spec$2 case block (2), mapImpl$spec$1 (1)
chain    + filter$spec$1's case block (1)
lenzip   takeUntil (2+2), mapImpl (1), Data.Zippable.zipWith (1)
compr    takeUntil (2+2+2), listBindOnto$spec$1 (1), reverseOnto (1)
trav     takeUntil (2+2), mapImpl (1)
userpipe case block of upto (1), bump (1: the reuse fallback)
vstat    the case block of loop (3), Data.Vect zipWith (1)
vdyn     Main.build (1), Functor map for Vect (2), zipWith (1)
```

What the simplified IR (`01-idr-simplify.mlir`) shows:

- **`[1 .. n]` is a Stream followed by `takeUntil`.** The range elaborates
  through the Prelude's `Range` for `Integral`,
  `rangeFromTo x y = case compare x y of LT => assert_total $ takeUntil (>= y) (countFrom x (+1)) ...`
  (`third_party/Idris2/libs/prelude/Prelude/Types.idr:1122-1126`).
  - `countFrom[Int]` returns an unboxed `Stream` constructor: the head, and a
    tail closure `countFrom[Int]$lam53` that captures `(i, step)`.
  - `takeUntil[Int]$spec$1` forces the thunk (`idr.apply %arg2()`), then
    recurses in a case block.
  - The Stream costs no cell, because it is unboxed. The list that
    `takeUntil` builds costs one cell per element: `x :: takeUntil p xs` is
    non-tail.
- **`map` is `mapImpl`, non-tail** (`Types.idr:591-593`). Idris's own
  `%transform "tailRecMap" mapImpl = List.mapTR` (`:608`) is ignored, as all
  21 `%transform`s are (facts-ledger item 9). So is `tailRecFilter` (`:642`).
- **The folds are already loops.** `foldl`'s specialized lambda
  (`foldl[...]$lam71$spec$1`) is a self tail call, and after idr-tail-loops it
  is an `scf.while`. The same holds for `total'` in `userpipe`.
- **`traverse_` is a `foldr` over IO that is one canonicalization away from a
  loop.** After raising, its body is:

  ```
  %3 = idr.io.put_int signed %arg2, %arg1
  %4 = idr.io.put_str %0, %3
  %5 = func.call @...foldr...$lam17$raise$3(%arg3, %4)
  %6 = idr.field %5[@MkIORes, 0]
  %7 = idr.field %5[@MkIORes, 1]
  %8 = idr.con @PrimIO.IORes[Builtin.Unit]::@MkIORes(%6, %7)
  idr.yield %8
  ```

  `%8` is `%5`: a single-constructor record rebuilt from its own fields. No
  pattern in `lib/Dialect/Canonicalize/` performs this eta step (grep for
  eta/rebuild finds none). Without it the call is not in tail position, so the
  IO fold is a non-tail recursion.
- **The list comprehension is the list monad.** It goes through
  `listBindOnto f xs (y :: ys) = listBindOnto f (reverseOnto xs (f y)) ys`
  (`Types.idr:672-674`). The result is accumulated in reverse, then reversed.
  The inner `[1 .. 100]` is closed, so compile-time evaluation made it a
  static constant list (`%4 = idr.constant #idr.con<...List...>`). The outer
  range is built at runtime.
- **`userpipe`** has the same shapes: `upto` is an unfold whose `if` became a
  case block, called with the constant `True`/`False` (the contify issue of
  architecture.md §3.1). `bump` is a non-tail map with
  `idr.take`/`idr.reuse`, so it reuses `upto`'s cells when they are
  exclusive at runtime. `total'` is an `scf.while`.
- **`vstat` builds five cells per iteration for two `Vect 4` literals.** Two
  of them are marked `idr.stack`. `zipWith`'s clone rebuilds cells by reuse,
  and `foldl`'s clone walks them.

### Why `vstat` overflows although `loop` is a tail recursion

`loop i acc = if i <= 0 then acc else ... loop (i - 1) (acc + step ...)`.
- The `if` is a case block, so `loop` → `case block 4911 in loop` → `loop` is
  mutual recursion. It is not a self tail call, and idr-tail-loops does not
  make it a loop.
- LLVM inlines `loop` into the case block. The resulting self call is
  `%45 = call fastcc double @"Main.case$32$block$32$4911$32$in$32$loop"(...)`,
  with no `tail` (`vstat.ll:223`). The block's frame holds the two stack
  cells, `%4 = alloca [3 x i64]` and `%5 = alloca [3 x i64]`
  (`vstat.ll:101-102`). Their addresses are passed to `zipWith`, so the call
  cannot be a tail call.
- Result: a segfault at n = 100,000. So stack cells, and case blocks that
  are not continuations, turn a tail loop into stack growth. This is not
  fusion's problem, but fusion's loops must not regress into it.

### Times (seconds, best of 3)

Measured with `timeit.py`. "segv" is a stack overflow.

| pipeline | n | idris-mlir | Chez | MLton | clang -O2 |
|---|---:|---:|---:|---:|---:|
| summap | 2e5 | 0.042 | 0.319 | 0.058 | 0.002 |
| summap | 1e7 | segv (from 4e5) | 3.551 (640 MB) | `Overflow` exception at 2.66 s (776 MB) | 0.001 (closed form) |
| chain | 2e5 | 0.051 | 0.249 | 0.041 | 0.004 |
| chain | 1e7 | segv (from 4e5) | 3.153 (640 MB) | 2.779 (624 MB) | 0.032 |
| lenzip | 5e4 | 0.041 | 0.225 | 0.043 | 0.001 |
| lenzip | 1e7 | segv (from 1e5) | 8.143 (1253 MB) | 4.183 (1539 MB) | 0.002 |
| compr | 2e4 | 0.122 | 0.731 | 0.338 | 0.013 |
| compr | 1e5 | 0.385 | 1.603 | n/a | n/a |
| compr | 1e6 | segv | 11.581 (580 MB) | timeout at 1e7 | 0.293 |
| trav (to /dev/null) | 1e5 | 0.035 | 0.458 | n/a | 0.082 |
| trav (to /dev/null) | 1e7 | segv (from 1e6) | 35.7 | n/a | 4.217 (musl `printf`) |
| userpipe | 2e5 | 0.036 | 0.300 | n/a | n/a |
| userpipe | 1e7 | segv (from 4e5) | 2.876 (607 MB) | n/a | 0.001 (as summap) |
| vstat | 5e4 | 0.025 | 0.206 | n/a | 0.002 |
| vstat | 1e7 | segv (from 1e5) | 2.268 | n/a | 0.057 |
| vdyn | 5e4 | 0.024 | 0.224 | n/a | <0.001 |
| vdyn | 1e7 | segv (from 1e5) | 16.120 (2079 MB) | n/a | 0.030 |

Notes on the table:
- Small-n times are dominated by process start. Repeated runs of `summap` at
  2e5 ranged from 0.018 s to 0.042 s.
- MLton's `summap` raises `Overflow`, because SML's `int` traps where Idris's
  `Int` wraps. The other MLton columns are correct.
- **Every backend builds every intermediate list.** The RSS columns show
  it: Chez 580 MB to 2 GB, MLton 624 MB to 1.5 GB at 1e7. MLton never
  overflows its stack, because it grows stacks on the heap. We overflow
  between 5e4 and 4e5 elements.

## X2. What upstream MLIR fuses, at the pin (`mlir/`)

The pinned `mlir-opt` is `.toolchain/llvm/bin/mlir-opt`. Programs were lowered
with `one-shot-bufferize` → `convert-linalg-to-loops` or `lower-affine` →
`convert-to-llvm` → `mlir-translate`, linked with a C `main`
(`.toolchain/llvm-musl/bin/clang -O2`), and run.

### e1: generator → map → sum as three `linalg.generic`s (`e1-range-map-sum.mlir`)

The input is a generator (`outs` only, value `linalg.index 0 + 1`), an
elementwise map, and a reduction into `tensor<i64>`.

After `--linalg-fuse-elementwise-ops --canonicalize`:
- 2 generics remain. The map is fused into the generator:
  `%8 = arith.muli %7, %7` sits inside the generic that computes
  `linalg.index`.
- **The fused generator is not fused into the reduction.** The reduction's
  only input is the generator, and the generator has no inputs. So the
  fused op would have no operand that defines the loop's extent, and
  `areElementwiseOpsFusable` refuses (`ElementwiseOpFusion.cpp:183-209`,
  "each loop dimension has at least one input that defines it").
- Bufferized as is, this is an n-element buffer.

### e1 tile-and-fuse: a miscompile with the default control function

`transform.structured.fuse %reduction tile_sizes [8]` (`e1-tf.mlir`) produced
this loop:

```
%2 = scf.for %arg1 = %c0 to %arg0 step %c8 iter_args(%arg2 = %1) -> (tensor<i64>) {
  ...
  %5 = linalg.fill ins(%c0_i64 : i64) outs(%arg2 : tensor<i64>) -> tensor<i64>
  %6 = linalg.generic {... ["reduction"]} ins(%4 ...) outs(%5 : tensor<i64>) ...
  scf.yield %6
```

- The init `linalg.fill` of the accumulator was fused into the loop through
  the `iter_args` destination, so every tile resets the sum.
- Run at n = 100: **38818**, where the answer is **338450** (the unfused and
  elementwise-fused versions print 338450). 38818 is the sum over the last
  tile, 97..100.
- The default `fusionControlFn` fuses every producer, destinations included
  (`TileUsingInterface.h:302-309`). The destination walk is
  `getUntiledProducerFromSliceSource` (`TileUsingInterface.cpp:1314-1346`).
- **Safe variants:**
  - with the init as `arith.constant dense<0> : tensor<i64>` (not a
    TilingInterface op), the result is correct (`e1b-tf.mlir`), but the full
    n-element buffer is still allocated: the fused producer writes slices of
    the untiled `tensor.empty(%n)`;
  - adding `transform.apply_patterns.tensor.fold_tensor_empty` makes the
    empty per tile. With tile size 1 (`e1d`), plus `promote-buffers-to-stack`
    and `buffer-loop-hoisting`, LLVM turns it into a closed form (no loop).
    That is correct, but it takes five passes to get a loop.
- If the design ever relied on `transform.structured.fuse` along a reduction
  dimension, AGENTS.md requires an `upstream/` report. The design below does
  not use it.

### e2: affine loop fusion on the bufferized form

- **e2** (`e2-affine.mlir`): a producer `affine.for` storing to
  `memref<?xi64>`, and a consumer with `iter_args`. Nothing fused. The pass
  skips loop nests that return values, in both roles
  (`LoopFusion.cpp:890-893` and `:931-934`, "TODO: support loop nests that
  return values").
- **e2b**: the same with the accumulator in a rank-0 `memref.alloca`. Still
  nothing fused. `-debug-only=affine-fusion` shows a valid slice at depth 1,
  then "Checking whether fusion is profitable" and no fusion. With the
  symbolic extent `%n` the cost model (`isFusionProfitable`,
  `LoopFusion.cpp:500`, used when `!maximalFusion`, `:1049`) declines.
- **e2c** (static extent 1000): fused, and the 1000-element buffer
  disappeared (`affine-scalrep`).
- **e2b with `--affine-loop-fusion="maximal=true"`**: fused, and the
  n-element buffer disappeared. One `affine.for` is left, with a rank-0
  accumulator.

### e3: the all-upstream route for `sum (map f [1 .. n])`

The pipeline:

```
mlir-opt e1-range-map-sum.mlir --linalg-fuse-elementwise-ops --canonicalize \
  --one-shot-bufferize=bufferize-function-boundaries --canonicalize \
  --convert-linalg-to-affine-loops --affine-loop-fusion=maximal=true \
  --affine-scalrep --canonicalize
```

gives:

```
%alloc = memref.alloc() {alignment = 64 : i64} : memref<i64>
affine.store %c0_i64, %alloc[] : memref<i64>
affine.for %arg1 = 0 to %arg0 {
  %1 = arith.index_cast %arg1 : index to i64
  %2 = arith.addi %1, %c1_i64 : i64
  %3 = arith.muli %2, %2 : i64
  %4 = arith.addi %3, %c1_i64 : i64
  %5 = affine.load %alloc[] : memref<i64>
  %6 = arith.addi %5, %4 : i64
  affine.store %6, %alloc[] : memref<i64>
}
```

- There is no n-element buffer. The rank-0 buffer goes to the stack with
  `promote-buffers-to-stack`.
- Linked and run at n = 1e8 it takes 0.0000 s: LLVM closed the sum, as it
  does for the C loop.

### e4: a static `Vect 4 Double` chain (`e4-vect4.mlir`)

The chain is `map (* k)`, `map (+ 1)`, `zipWith (*)`, and `foldl (+) 0.0`
into `tensor<f64>`.
- `linalg-fuse-elementwise-ops` leaves 1 generic.
- `transform.structured.vectorize_children_and_apply_patterns` gives
  `vector.transfer_read` of both inputs, `arith.addf`/`arith.mulf` on
  `vector<4xf64>`, and one `vector.contract` (a dot product).
- Lowered to LLVM, this is
  `call double @llvm.vector.reduce.fadd.v4f64(double %53, <4 x double> %58)`
  with no `reassoc`: LLVM's ordered reduction, the same order as `foldl`.

### e5: `filter` as a mask (`e5-filter-mask.mlir`)

`foldl (+) 0 (map (* 3) (filter p [1 .. n]))` is written as:
- a generator;
- a `keep : tensor<?xi1>` generic;
- a map;
- a reduction with two inputs whose body is `select keep (acc + x) acc`.

The e3 pipeline gives one `affine.for` with no n-element buffer. Linked, it
prints 20000100000 at n = 2e5, the right answer. At n = 1e8 it takes 0.231 s;
the C loop takes 0.249 s.

### e6: `length (zip ...)` as a shape query (`e6-lenzip.mlir`)

The program has:
- two generators;
- `tensor.extract_slice` of both to `min(n, m)`;
- a two-result zip generic;
- `tensor.dim` of the result.

`--canonicalize --resolve-ranked-shaped-type-result-dims --canonicalize`
leaves:

```
%0 = arith.minui %arg0, %arg1 : index
return %0 : index
```

No loop and no buffer remain.

### Other upstream facts read at the pin

- `scf.while` → `scf.for` uplift (`populateUpliftWhileToForPatterns`)
  requires a before region that holds exactly one `arith.cmpi`
  (`UpliftWhileToFor.cpp:34-41`), with predicate `slt` or `sgt` (`:93-94`)
  and an `addi` step (`:156`, `:166`). idr-tail-loops puts the whole body in
  the before region, so nothing it emits matches.
- Other `scf` fusion is sibling-only: `scf-parallel-loop-fusion`
  (`SCF/Transforms/Passes.td:43`). There is no producer-consumer fusion of
  `scf.for` or `scf.while`, and no raising of `scf` to `affine` or `linalg`.
  The only raise pass is `affine-raise-from-memref`
  (`Affine/Transforms/Passes.td:398`).
- One-Shot Module Bufferize skips function-boundary analysis for recursive
  functions (memory-theory.md §6.10, `OneShotModuleBufferize.cpp:518-523`).
  So recursion must become loops before bufferization.

## X3. Literature, what was read here

- **Kovács 2024** (`kovacs-2024-closure-free/paper.pdf`):
  - §4.1 (p. 18): a pull stream is a *meta-level* state machine,
    `Pull : (S : MetaTy) → IsSOP S ⇒ Gen S → (S → Gen (Step S A)) → Pull A`,
    with `Step = Stop | Skip S | Yield A S`.
  - §4.2 (pp. 19-20): running a stream = `foldr` that tabulates the
    transition function into mutually tail-recursive functions. `foldl` is
    derived with no closures, whereas GHC needs arity analysis (Breitner
    2014).
  - §4.3 (p. 21): `concatMap` with a dependent state gives guaranteed
    fusion.
  - Related work (p. 25): strymonas's fusion is "not guaranteed for all
    combinations" (zip of two concatMaps), and is complete only in Kobayashi
    and Kiselyov 2024.
- **Kovács 2022** (`paper.tex:593-618`, §2.4 "Fusion"):
  - fusion is a binding-time improvement: foldr/build is a Böhm-Berarducci
    encoding under the lift, and stream fusion is a terminal encoding of
    colists;
  - "converting back to lists from colists is not necessarily total";
  - in GHC, fusion "relies on rewrite rules and inlining annotations which
    have to be carefully tuned and ordered, and it is possible to get
    pessimized code via failed fusion".
- **Henriksen 2017** (`henriksen-2017-futhark/paper.pdf`):
  - §4 (p. 7): producer-consumer fusion by "T2 graph reductions (i.e., a SOAC
    is fused if it is the source of only one dependency edge and the target is
    a compatible SOAC)", then horizontal fusion;
  - rules F1–F7 (Fig. 9, p. 8);
  - filter is "not in the scope of this paper";
  - "if an array is indexed explicitly in a target SOAC, then its producer
    SOAC will not be fused";
  - in-place updates restrict only moving a SOAC past a consumption point.
- **Mitchell 2010** (`mitchell-2010-rethinking-supercompilation/paper.pdf`):
  - §2.3 (p. 4): `map g (map f zs)` fuses with no knowledge of `map` or its
    rules;
  - p. 9: GHC's rules "match specific function names in the source program,
    meaning that redefining map locally would inhibit the fusion", and there
    is no rule for `(!!)`;
  - the termination machinery is bags and a whistle (§2.6);
  - Table 1: compile times up to 2.4 s, on programs of at most 148 lines.
- **Sørensen, Glück, Jones 1996** (`paper.pdf`):
  - p. 2: Wadler restricts deforestation to "treeless" definitions so that
    it terminates and does not lose efficiency;
  - p. 14: "rewriting to a non-linear right hand side can cause function call
    duplication … In Wadler's deforestation this is avoided by considering
    only linear terms", and a transformed term "might be more terminating
    than the one at the left hand side if b loops".
- **FP²** (`lorenzen-2023-fp2`):
  - §2, p. 6: `smap` over a splay tree is `fbip`, not `fip`, because its
    recursive calls are not tail calls;
  - §3 (p. 8): any map over a polynomial datatype can be made fully in place
    by a Schorr-Waite traversal derived via defunctionalized zippers.
- **MLton**:
  - `docs/mlton/doc/guide/src/SSASimplify.adoc` lists 23 optimization
    passes, and none fuses or deforests;
  - `GarbageCollection.adoc`: copying, mark-compact and generational
    collection, switched at runtime.
- **Idris 2's laziness**:
  - the Chez backend's `defaultLaziness` is
    `(lambda () expr)` / `(expr)`, call-by-name with no memoization.
    `weakMemoLaziness` applies only under a directive
    (`third_party/Idris2/src/Compiler/Scheme/Common.idr:318-331`; the choice is made at `Chez.idr:498`);
  - idris-mlir's frontend compiles `Delay` as a closure
    (`compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr:126`).
- **Linear lists**: `data LList : Type -> Type where Nil : LList a;
  (::) : a -@ LList a -@ LList a` (`libs/linear/Data/Linear/LList.idr:11-13`).
  The Prelude's `List` has unrestricted fields.

## X4. Incidental

- A program that fails Idris's type checker (`Undefined name zip`) also
  printed `Error: Main:18:12--18:14:mlir backend: internal error: a reference
  to Main.lz`: the backend still ran on the failed definition. A user sees two
  errors, the second an internal one.
