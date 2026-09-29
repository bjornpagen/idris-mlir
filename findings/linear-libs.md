# The linear libraries as the proving ground

Stream: linear-libs. I read every module of `third_party/Idris2/libs/linear`,
contrib's `Data/Linear/Array.idr`, and the mutable and linear APIs in base,
contrib and papers. I ran 25 programs on the stock Chez backend and through
`tools/compile.sh`. For the programs that compiled, I read the IR after
`idr-rc` and the machine code, and counted runtime calls with gdb
breakpoints. Then I took the array half through upstream
`one-shot-bufferize` with the pinned `mlir-opt`.

Everything is under
`scratchpad/research/linear-libs/`:
- `p*/` are programs over the libraries;
- `q*/` are user copies that avoid a rejection;
- `h*/` are holes;
- `mlir/e*.mlir` are the bufferization experiments.

This builds on facts-ledger.md, which proposes a `!idr.uniq` type and
inferring it with a call-graph fixpoint, and on review-external-2.md
("linearity is not uniqueness"). I don't repeat their arguments; I test
them against the libraries.

## The questions

1. Which of Idris 2's linear and mutable libraries can prove the compiler's
   uniqueness and linearity work? For each one: its API, how it is
   implemented, and whether its uniqueness is guaranteed by types or only
   by convention.
2. What happens when we compile them today? This means the exact
   rejection, or else the IR, the machine code and the counts.
3. Which 8–12 programs make a benchmark suite, and what should each one
   reach?
4. What does the compiler need to accept them? That covers trust, arrays,
   `%World` in LIO, and code built on `believe_me`.
5. What are the smallest dialect and runtime additions that carry the
   weight? (Per the standing order: the global maximum first, then the
   path to it.)

## Answers in brief

- **No linear library compiles today.** They fail for five independent
  reasons. Two of them are compiler bugs, and neither is a principled
  limit:
  - a constructor typed with `-@` is rejected under a misleading reason;
  - a user module named `Data.*` is trusted.
- **Only two places guarantee uniqueness by types.** These are the world
  token (`%World`, which is linear in `PrimIO`) and the linear pure data
  (`LList`, `LVect`, `LNat`, `Copies`). Everything with mutation promises
  uniqueness by convention only:
  - `LinArray` leaks: I demonstrated it on Chez, where it prints
    `Just 42` twice;
  - `LIO`'s `use` is whatever the wrapper of an action claims;
  - `System.Concurrency.Linear` uses `assert_linear`;
  - `Data.String.Iterator` relies on a private constructor.
- **Where our compiler accepts a copy of the library's code, reuse already
  works, but with a runtime test.** Two things break it:
  - an Idris `if` inside the rebuilt constructor. Reuse is lost across the
    case block, so bubble sort on a linear list allocates n+n² cells and
    runs 2.6x slower than Chez;
  - non-tail recursion. `lmap` over 400k cells overflows the 8 MB stack,
    where Chez succeeds.
- **For arrays, upstream One-Shot Bufferize already proves what we want.**
  Linear Idris threading gives one SSA chain per tensor, so every write
  bufferizes in place. The machine code is C's: 1 allocation, loads and
  stores, unrolled. The analysis result can be the check itself: a write
  placed out of place is a broken promise, so reject. One upstream gap
  remains. Recursive functions are skipped by the module analysis
  (`OneShotModuleBufferize.cpp:511-526`), and ownership-based deallocation
  then clones the whole array on every base case. For quicksort that is
  O(n²) silent copying.
- **Everything the libraries need is framed in MLIR's own implementations
  (§4.0):**
  - `tensor` + One-Shot Bufferize + ownership-based deallocation for
    linear arrays;
  - `memref` + `mem2reg` for IOArray, IORef and ST;
  - `IntegerRangeAnalysis` for bounds checks;
  - `DataFlowSolver` for the uniqueness of cells.

  Scalar arrays need no new idr op at all. idr adds the facts (in
  types), transfer functions for its own ops, and the rejection.

## 1. Catalog

"Types" means the uniqueness follows from Idris types plus the fact that
the creation pattern is the only constructor. "Convention" means the code
or API can break it without a type error.

### libs/linear (package `linear`, 961 lines)

| module | API | implementation | uniqueness |
|---|---|---|---|
| `Data.Linear.Notation` | `-@` (`a -@ b = (1 _ : a) -> b`, :8-9), linear `id`, `.`, `!*`/`MkBang`, `unrestricted` | pure | n/a: `!*` is the unrestricted modality, a single-field data type |
| `Data.Linear.Bifunctor` | `bimap`, `mapFst`, `mapSnd` on `LPair` | pure | n/a |
| `Data.Linear.Copies` | `Copies n x` (n linear copies of x), `splitAt`, `++`, `unzip`, `pure`, `<*>`, `<$>`, `zip`, `extract`, `pair` | pure; `pure` needs `{1 n : Nat}` | types |
| `Data.Linear.Interface` | `Consumable` (`consume : a -@ ()`), `seq`, `Duplicable` (`duplicate : (1 v : a) -> 2 \`Copies\` v`), `Comonoid`; instances for Void, (), Bool, `!*`, Int | pure, except **`Consumable Int = believe_me (\ 0 i : Int => ())`** (:32-34, "We can cheat") | n/a |
| `Data.Linear.LList` | `LList` (`(::) : a -@ LList a -@ LList a`), `length`, `Consumable`, `Duplicable`. **No map, fold or reverse** | pure | types (linear spine and elements) |
| `Data.Linear.LMaybe`, `LEither` | `LMaybe` with `<$>`; `LEither`; `Consumable`/`Duplicable` | pure | types |
| `Data.Linear.LNat` | `Zero`/`Succ : LNat -@ LNat`, `0 toNat`, `add`, `mult` (needs `Copies`), `square` | pure; no `%builtin Natural`, so not Nat-like: a unary list at runtime | types |
| `Data.Linear.LVect` | `LVect n a`, `lookup`/`insertAt` (with proofs), `<$>`, `pure`, `<*>`, `zip`, `unzip`, `splitAt`, `++`, `lfoldr`, `lfoldl` (motive `0 p : Nat -> Type`), `reverse = lfoldl ... (::) []`, `map`/`foldl` with `Copies` of the function, `replicate`, `>>=`, `copiesToVect` | pure | types |
| `Data.Linear.List.LQuantifiers` | `LAll p xs` | pure | types |
| `Control.Linear.LIO` | `LinearBind` (`bindL`), `Usage = None \| Linear \| Unrestricted`, a `fromInteger` hack, `L io {use} a` (a free monad: `Pure0`/`Pure1`/`PureW`/`Action`/`Bind`, :38-53), `ContType` and `RunCont` computed from `Usage`, `runK`, `run`, Functor/Applicative/Monad, `%inline` `>>=`, `>>`, `pure0`, `pure1`, `bang`, `HasLinearIO (L io)`, `die1` | pure over IO. **`import System`** (:4) is only for `die1`. `runK` recurses at `Bind`'s existential `a` | **convention**: `Action : (1 _ : io a) -> L io {use} a` lets the wrapper choose `use`, and the comment at :47-48 says "the type makes an assertion". The world inside IO is types |
| `System.Concurrency.Linear` | `fork1`, `concurrently`, `concurrently1`, `par1`, `par` | threads and channels from base (`%foreign "scheme:..."`); **`assert_linear`** twice (:49-52, "temporarily bypasses the linearity checker") | convention |
| `System.Concurrency.Session` | `Session`, `Dual`, `Channel s` (two `Threads.Channel`s over `Union` types), `recv`, `send`, `end`, `makeChannel`, `fork` | channels; `rewrite` proofs; runtime `prj` check with `die1` | the protocol is by types; the channel's single use is convention (the `MkChannel` fields are unrestricted) |

### contrib, base and papers

| module | API | implementation | uniqueness |
|---|---|---|---|
| `Data.Linear.Array` (contrib) | `Array` (`read`, `size`, both consuming `(1 _ : arr t)`); `MArray` (`newArray : Int -> (1 _ : (1 _ : arr t) -> a) -> a`, `write`/`mread`/`msize` returning `Res _ (const (arr t))`); `IArray`, `LinArray`, `toIArray`, `copyArray` | **`unsafePerformIO`** over `Data.IOArray` in every method (:40-52) | **convention, and it leaks.** `a` in `newArray` is unrestricted, so `newArray n (\a => a)` returns the array itself as an ω value. Program `h1` updates an alias and reads the "old" array: Chez prints `Just 42` twice. Brady (QTT paper, protocols.tex:19-27) conditions the promise on "if this is the only way of constructing an Array". Linear Haskell closes the gap by returning `Ur b` from the continuation |
| `Data.IOArray`, `Data.IOArray.Prims` (base) | `IOArray elem` = `MkIOArray maxSize (ArrayData (Maybe elem))`; `newArray`, `readArray`/`writeArray` (bounds-checked, returning Maybe/Bool), `newArrayCopy`, `toList`, `fromList` | `%extern prim__newArray : Int -> a -> PrimIO (ArrayData a)`, `prim__arrayGet`, `prim__arraySet` (Prims.idr:11-13; "undefined otherwise" out of bounds) | none: shared and mutable, ordered by the world |
| `Data.IOMatrix` (contrib) | `new`, `read`, `write` on `w*h` | the same three primitives | none |
| `Data.Buffer` (base) | `newBuffer`, get/set of Bits8..64, Int8..64, Int, Double, String, Bool, Nat, Integer; `copyData`, `resizeBuffer`, `concatBuffers`, `splitBuffer`, `bufferData` | `%foreign "scheme:blodwen-..."`/`"RefC:..."` for each; "these primitives are unsafe... We really need a safe wrapper!" (:7-9) | none |
| `Data.IORef` (base) | `newIORef`, `readIORef`, `writeIORef`, `modifyIORef`, `atomically` | `%extern prim__newIORef/readIORef/writeIORef` over `Mut`; imports `System.Concurrency` for `atomically` | none |
| `Control.Monad.ST` (base) | `ST s`, `STRef s`, `runST : (forall s . ST s a) -> a`, `newSTRef`, `readSTRef`, `writeSTRef`, `modifySTRef` | `MkST (IO a)`, `runST` via **`unsafePerformIO`** with `s = ()` | the escape of refs is prevented by types (rank-2 `s`); refs are shared |
| `Data.Ref` (base) | `Ref m r` over IORef and STRef | the above | none |
| `Control.App` (base) | `App`/`App1` with `(1 x : %World)` results, `Cont1Type`, `new1` (a State over an IORef), `app`, `app1` | `PrimApp`, IORef | the world is by types; `App1 {u}` is by types like `L` |
| `Data.String.Iterator` (contrib) | `withString : (str : String) -> ((1 it : StringIterator str) -> a) -> a`, `uncons`, `foldl`, `unpack`, `withIteratorString` | `%foreign "scheme:blodwen-string-iterator-*"`; `fromString` is private | convention (a private constructor), and the index is only "checked up to definitional equality" (:11-18). The continuation's `a` can again return `it` |
| papers `Data.Linear.{Inverse,Diff,Communications}` | `Inverse a = a -@ ()`, `divide`, contexts; session channels as `parameters` | pure; the channel primitives are *parameters* | types, but no runtime primitives exist |

The pattern is consistent. In these libraries, every uniqueness that could
license mutation rests on a creation continuation. None of them stops the
continuation from returning the resource. Where a library needs more than
QTT can express, it uses `believe_me`, `assert_linear` or `unsafePerformIO`.
This is Marshall, Vollmer and Orchard's point (ESOP 2022, §2, pp. 348–350):
"any linear value could have previously been a non-linear one that was
duplicated any number of times before being specialised (via dereliction)
to a linear type."

## 2. What happens today

Each program was run on Chez (`idris2 -p P -o chezprog`) and through
`tools/compile.sh -p P --directive dump-mlir`. Input `3` gives n = 400,000
for lists and n = 4,000 for sorts.

### The library programs: all rejected

| program | Chez | our compiler (verbatim) |
|---|---|---|
| p1 LinArray fill+sum | `239999400000`, 0.27 s | `unsupported (escape hatch): %extern Data.IOArray.Prims.prim__arraySet (reached through Main.main)` |
| p4 LinArray bubble sort | `4000002026488`, 1.05 s | the same (`prim__arraySet`) |
| p2 LList reverse (`!*` elements) | ok, 0.44 s (n = 1M) | `Main.lsum: unsupported (compiled module): constructor :: binds an unexpected number of arguments` |
| p5 LList map | ok | the same |
| p11 LNat add | `4004` | `Main.toInt: unsupported (compiled module): constructor Succ binds an unexpected number of arguments` |
| p6 LVect reverse (library `reverse`) | `10323` | `Data.Linear.LVect.lfoldl: unsupported (polymorphism): polymorphic recursion: Data.Linear.LVect.lfoldl calls Data.Linear.LVect.lfoldl with a type or an implementation that is not its own, unchanged` |
| p3 LIO with a linear counter | `400000` | `main: unsupported (program): loads System.File.Meta, which is neither a user module nor a trusted module` |
| q7 LIO copied as a user module (no `System`) | `400000` | `LIOCopy.runK: unsupported (polymorphism): polymorphic recursion: LIOCopy.runK calls LIOCopy.runK ...` |
| p12 `seq` on an Int (`Consumable Int`) | `5` | `Main.drop1: unsupported (escape hatch): the escape hatch Builtin.believe_me (reached through Main.main -> Main.drop1)` |
| p7 ST loop | ok | `main: unsupported (program): loads System.Concurrency, which is neither ...` |
| p8 IOArray fill+sum | ok | `unsupported (escape hatch): %extern Data.IOArray.Prims.prim__newArray` |
| p9 Buffer | ok | `unsupported (escape hatch): %foreign Data.Buffer.prim__newBuffer` |
| p10 String.Iterator foldl | ok | `unsupported (escape hatch): %foreign Data.String.Iterator.uncons` |

One more fact from writing these programs: **a linear `Int` cannot reach
Prelude arithmetic.** `lsum acc (x :: xs) = lsum (acc + x) xs` fails in
Idris ("Trying to use linear name x in non-linear context"). Consuming it
needs `Consumable Int`, which is `believe_me`. So idiomatic linear
numeric data is `LList (!* Int)`. Our compiler already represents `!* Int`
as an unboxed `idr.data` with one `i64` field (q8: the cons cell is
`(!idr.lin<!idr.data<@...!*[Int]>>, !idr.lin<!idr.box<...>>)`), so it costs
nothing.

### The rejections, and the fix for each

**R1: `-@` in a constructor type (a bug with a misleading name).** q3 is
q1 with `(::) : Int -@ LL -@ LL` in place of explicit `(1 _ : ...)`
binders. q1 compiles and q3 is rejected. The constructor's type is walked
unnormalised:
- `paramLayout` (Translate/Types.idr:90-105) walks it;
- `walk` (:305-316) walks it;
- `constructor` (:319-329) calls both.

After the implicit `{a}`, the type is `App (-@) ...`, not a `Pi`, so the
walk stops at one field while the case tree binds three. The mismatch
then surfaces at every match (Cases.idr:173-174) as `compiled module`.
This blocks `LList`, `LVect`, `LNat`, `Copies`, `LMaybe`, `LEither` and
`LAll`, which is all the linear data.

The representation fix is not "normalise in walk". Read the constructor's
fields once from its normalised type, where each `Pi` binder carries its
`RigCount`, which is exactly what fills `!idr.lin`. Then check that count
against Idris's own `DCon ... arity` at registration, as an internal
error. That makes a wrong layout impossible to carry into matches. The
fix also matters for quantities: without it, the linearity of `LList`'s
fields would be lost even if the walk survived.

**R2: trust decided by namespace, not package.** `moduleOrigin` (Registry/Libraries.idr:76-85) makes any
`Data.*`/`Control.*` module "base". The comment at :17-19 admits it. So
libs/linear's `Data.Linear.*` and `Control.Linear.LIO` are *already*
trusted by accident, and so is a user module. In h2, a user module
`Data.Evil` with `%inline` and `assert_total` compiles. The same module
named `Evil.Evil` is rejected with `unsupported (pragma): the pragma
%inline`. An `unsafePerformIO` in `Data.Evil` passes the profile check
too (`checkReachable` skips `firstForbidden` for trusted code,
Profile.idr:216). Translation catches it later
(`PrimIO.unsafeCreateWorld: unsupported (world): %MkWorld`). That is
defence in depth by accident.

The representation fix: `Origin` comes from the package whose TTC holds
the module (`<prefix>/idris2-0.8.0/<pkg>-0.8.0/...`), and namespace is
only the area within the package. Then `Lib` gains a `Linear` row, and
nothing is trusted because of its name.

**R3: loading is checked per module, not per reached definition.**
Main.idr:319-336 rejects any loaded module that is neither trusted nor
user-sourced. That happens even when nothing in it is reachable:
- LIO loads `System` only for `die1`;
- `Data.IORef` loads `System.Concurrency` only for `atomically`.

`checkReachable` (Profile.idr:165-226) already rejects every reached
`%foreign`, `%extern`, `believe_me` and hole with a named reason. The
module check adds nothing but false rejections. Drop it for modules that
only a trusted library imports.

**R4: polymorphic recursion keyed on type-level functions.** For
`staticPositions` (Recursion.idr:94-110), an erased `Nat -> Type` is a
static argument. `lfoldl` passes `p . S` for `p`, which makes it
"polymorphic recursion" (:118-133). Every instance of `p` here has the
same representation: `p n` is `LVect n a`, and indices are erased from
instance keys (Types.idr:275-283). Two keys with the same representation
are the same instance. So the check should compare the *representation*
of the static arguments (the image of `p` with indices erased), not
their terms. `runK` (R5) is genuine polymorphic recursion. `lfoldl` is
not.

**R5: LIO's `runK`.** `runK (Bind act next) k = runK act (\x => runK (next x) k)`
calls itself at `Bind`'s existential type `a`. That type is known only
from the value, so no type-keyed monomorphisation can name the instance.
If R3 and R4 were fixed, conjecture: the next rejection would be
`dependent field`. `Bind`'s continuation has type
`ContType io u_act u_k a b`, which is computed from the `u_act` field,
and `None` has a different runtime arity (the erased argument). §4.3 has
the design.

**R6: primitives.** Any array, ref, buffer or iterator program is
rejected at its `%extern`/`%foreign` (Registry/Primitives.idr lists only
putStr, putChar and getChar). That is correct: they have no runtime
meaning yet.

### What compiles: user copies of the same programs

| program | cells allocated (gdb hit counts) | reuse | machine code | time vs Chez |
|---|---|---|---|---|
| q1/q4/q8 build, then `rev` with an accumulator, then sum (n = 100,000) | `idris_rt_cell` 100,000 (all in `build`), `freeCell` 100,000 (all in `lsum`), `release` 0 | `rev`: `idr.take` then `idr.reuse` (05-idr-rc.mlir), 0 cells | the `rev` loop at `main+0x1ef..0x3cc`: `testl %ecx,%ecx; js` (static-cell bit) and `cmpl $0x1,(%rax); jne` (count test), then two field stores. No calls on the unique path. The slow path does inc, dec and `idris_rt_cell` | 60 ms vs 496 ms (n = 1M) |
| q5 `lmap (\x => x*2+1)` (non-tail) | 100,000 (build only) | take and reuse in `lmap$spec$1`; the closure is specialized away | recursion depth n. **Segfaults at n = 400,000 with an 8 MB stack**; runs with `ulimit -s unlimited`. Chez succeeds | 94 ms vs 444 ms (unlimited stack) |
| q6 bubble sort on a linear list, `bubble x (y :: ys) = if x > y then y :: bubble x ys else x :: bubble y ys` | **n = 100: 10,100 = n + n·passes** | **none.** `bubble` takes the cell and `idr.dec`s its token. The rebuild is in `case block 838 in bubble`, the function Idris lifted the `if` into, which the inliner does not inline (it has two call sites, one per `match_lit` arm over `extui(cmpi)`) | `Main.bubble`: `freeCell` of the matched cell, then `idris_rt_cell` after the recursive call. LLVM does inline the case block, too late for reuse | **403 ms vs 157 ms: 2.6x slower than Chez** |

Two findings follow.

First, even the best case (`rev`) tests the count at runtime. That is
review-external-2's point, now seen in the machine code. In q1 the
test is not idle. The Nil passed to `rev` is the static constant,
`lin.enter`ed twice (`%6`, `%9` in the root), which is legal because
"Idris lets any value fill a quantity-1 binder" (IdrOps.td:1030-1033).

Second, reuse is frame-limited in a way the source cannot see. An Idris
`if` or `case` in the right-hand side becomes a separate function. For
the benchmark, any sort, insert or partition over linear data has an
`if` in exactly the place where the cell is rebuilt.

## 3. A benchmark suite for linearity and uniqueness

Ranked by how directly each program tests "Idris proved it unique, so it
runs in place, or it is rejected", then by how many Idris facts it
exercises. Each target is a property that `idr-expect` states once, not
an op sequence:
- existing: `no-heap-allocation=@f`, `reuses-in-place=@f`,
  `counts-nothing=@f`;
- proposed: `arrays-in-place` (§5), `untested-reuse=@f` (needs `!idr.uniq`),
  `constant-stack=@f`.

Each program is also diffed against Chez and timed against it, and
against C where an array is involved.

1. **llist-reverse** (`Data.Linear.LList`, `rev xs acc` over `LList (!* Int)`).
   - Target: `rev` makes 0 allocations and has no count or static test
     (`untested-reuse=@rev`, `counts-nothing=@rev`). The loop is two
     loads and two stores.
   - Today: library rejected (R1). A user copy reuses, with a runtime
     test.
2. **linarray-fill-sum** (contrib `LinArray`: `newArray n`, a `write` loop,
   an `mread` loop, `toIArray`).
   - Target: 1 allocation and 1 free. The fill loop is a store per
     element and the sum loop is a vectorized reduction.
     `writeArray`'s own bounds check is removed by integer range
     analysis (`i < n = tensor.dim`). Same code as C.
   - Today: rejected (R6).
3. **linarray-bubble** (contrib `LinArray`, get/set swaps).
   - Target: 1 allocation. The inner loop is loads, a compare and two
     stores. The e3 bubble below is exactly this.
   - Today: rejected (R6). Chez: 1.05 s at n = 4,000.
4. **llist-bubble** (q6: bubble sort on `LList (!* Int)` with `if`).
   - Target: n allocations in total, 0 per pass (`reuses-in-place=@bubble`),
     no count test.
   - Today: n + n² cells, 2.6x slower than Chez.
   - It is the canary for reuse across Idris case blocks.
5. **llist-map** (`lmap` over `LList (!* Int)`, non-tail).
   - Target: 0 allocations and constant stack. Tail recursion modulo
     cons through the reused cell: destination passing, where the cell
     taken apart is the destination.
   - Today: reuses, but the stack grows with n and segfaults at 400k.
6. **lvect-reverse** (`Data.Linear.LVect.reverse` = `lfoldl (::) []` on a
   runtime-length vector).
   - Target: 0 allocations, the index erased, the motive `p` never in the
     instance key.
   - Today: rejected (R4, and R1 next).
7. **lio-resource** (p3: `Control.Linear.LIO`, a linear counter ticked n
   times).
   - Target: the `L` tree is never built (no `Bind`/`Pure1`/`Action`
     cells), the counter lives in a register, and the loop is identical
     to a plain `Int` loop (`no-heap-allocation=@loop`, `no-closures`).
   - Today: R3, then R5.
8. **lnat-add / copies** (`Data.Linear.LNat.add`, `mult` with `Copies`).
   - Target: `add` reuses the first operand's `Succ` cells (0
     allocations), and `Copies` proofs are erased.
   - Today: rejected (R1).
9. **linarray-escape** (h1; a negative test).
   - Target: rejected with `unsupported (uniqueness)`, naming the
     read of the escaped array. It must never compile to value semantics
     that differ from Chez's aliasing.
   - Today: rejected, but for R6, not for the reason.
10. **ioarray-fill-sum** (`Data.IOArray` in IO; shared mutable).
    - Target: 1 allocation, a store loop, no counts in the loop. The
      array is a counted object only across calls.
    - Today: rejected (R6).
11. **st-counter** (`Control.Monad.ST`, an `STRef` updated n times in
    `runST`).
    - Target: the ref becomes a register (`memref.alloca` plus
      `mem2reg`), with 0 allocations.
    - Today: R3, then R6.
12. **string-iterator-fold** (`Data.String.Iterator.foldl`).
    - Target: the iterator is a byte offset in a register, with 0
      allocations per character.
    - Today: rejected (R6).

`System.Concurrency.Session` is out of scope (threads). It should stay a
profile test that expects a named rejection.

## 4. What the compiler needs

### 4.0 The frame: MLIR does the work, idr states the facts

Per the user's direction, every need below is met by an upstream MLIR
implementation where one exists. idr contributes only what MLIR cannot
know:
- the Idris facts, which live in types (quantity 1 as `!idr.lin`);
- the transfer functions of our own ops;
- the rejection that turns an analysis result into a named rule.

| need | MLIR implementation | what idr adds |
|---|---|---|
| in-place update of a linear array | `tensor` ops plus One-Shot Bufferize's analysis (`AnalysisState::isInPlace`) | emit the array as `tensor<?xE>` threaded through `!idr.lin`, so the def-use chain is single; reject any out-of-place decision (`arrays-in-place`) |
| freeing arrays | `ownership-based-buffer-deallocation` / `buffer-deallocation-pipeline`, `drop-equivalent-buffer-results` | nothing for scalar arrays; runtime `_mlir_memref_to_llvm_alloc/free` so an array that escapes into a cell is also counted |
| shared mutable arrays, refs | `memref`; `mem2reg` over `memref.alloca` | the backend-contract primitives, lowered to memref ops |
| bounds checks | `IntegerRangeAnalysis` / `-int-range-optimizations`, `ValueBoundsOpInterface` on `tensor.dim` | nothing: Idris's own check `pos >= max arr` becomes `arith.cmpi` against `tensor.dim` |
| vectorization, fusion | LLVM's loop vectorizer today; `linalg` once loops are raised (the raising has no upstream pass, so it comes later) | later: a raising pattern, only if the payoff is measured |
| uniqueness of cells (lists, trees) | `DataFlowSolver` with an interprocedural `SparseForwardDataFlowAnalysis`. `visitCallableOperation` already joins a callee's argument lattices over all known call sites (SparseAnalysis.h:249-258), which is exactly "every caller passes an unshared value". `DeadCodeAnalysis` supplies the executable call edges | a lattice (`unique` < `shared`) and transfer functions for `idr.con`, `idr.reuse`, `idr.take`, `idr.inc`, `idr.lin.*`; the result written into types (`!idr.uniq`), where the verifier checks it. Borrow.cc's home-grown fixpoint is the pattern this should replace, not copy |
| reuse across Idris case blocks (q6) | the inliner (MLIR's `Inliner` with our cost model), `idr-specialize` | nothing new, if case blocks are specialized per constant and inlined before `idr-rc` |

So the first step for arrays needs **no new idr op**. Arrays of scalars
and of unboxed data without counted slots are built from upstream `tensor`
and `memref` ops alone. An array of counted elements (boxes, strings)
needs the old slot released on overwrite, which no upstream op expresses.
Until that is designed, it is an explicit
`unsupported (type): an array of counted elements`. §5's `idr.array.set`
is the fallback for then, not a first step.

### 4.1 Trusting libs/linear

- **Coverage.** Most of libs/linear is pure Idris in the fragment the
  compiler already handles (first-order data, recursion,
  interfaces). Trusting it, in the sense of Libraries.idr (importable,
  pragmas unlexed, definitions admitted), matches AGENTS.md's rule that
  only vetted library code is trusted. Nothing in it gives a primitive an
  Idris meaning.
- **What stays rejected, with its reason**:
  - `Consumable Int` (`believe_me`);
  - `System.Concurrency.*` (`%foreign` threads, `assert_linear`);
  - `die1`, but only if reached.
- **What it takes**:
  1. R2, trust by package: a `Linear` row in the table, keyed by the TTC's
     package directory, never by namespace.
  2. R3: reachability decides, not loading.
  3. R1 and R4, which are bugs whatever is trusted.
  4. For `Consumable Int`, optionally a registry entry of category 2
     (Registry/Recognized.idr: "faster or stricter, never different").
     It says that `Data.Linear.Interface.consume` at `Int` drops its
     argument, validated by the shape `(1 _ : Int) -> ()`. Dropping a
     linear value is already legal in `idr` ("A linear value is used at
     most once, and may be dropped instead", IdrOps.td `idr.dec`), so the
     verifier checks the replacement. The `believe_me` exists only to get
     past Idris's usage checker, not ours.
- **Pragmas.** Trusted libraries' `%inline` and `%default total` stay
  unlexed as today. LIO's `%inline` on `>>=` matters for R5.

### 4.2 Arrays: the global maximum first

**The global maximum.** An Idris program over linear arrays compiles to
the code a C programmer would write:
- one allocation;
- loops of loads and stores, vectorized where independent;
- no count traffic and no copies;
- bounds checks gone wherever Idris or the loop proves the index in
  range.

The compiler *proves* each in-place update with MLIR's own analysis, fed
by Idris's linearity. Where that analysis would copy an array the types
promised unique, the program is rejected with a named reason.

- **The same guarantee for every array family.** Shared mutable arrays
  (IOArray, Buffer), refs (IORef, STRef) and immutable arrays (IArray)
  get it on the representation natural to each.
- **Arrays of any element type.**
  - Scalars are dense.
  - Unboxed sums are structure-of-arrays.
  - Counted elements are pointers, released when their slot is
    overwritten or when the array dies.
- **Boundaries.** Arrays cross function boundaries, recursion, closures
  and cells.
- **Whole-array operations.** Map, fold and fill are raised to `linalg`,
  so fusion, tiling and vectorization come from upstream.

**MLIR used as MLIR.** Each array family's representation is a builtin
type, chosen by the Idris side from the Idris type:

| Idris | idr-level type | why |
|---|---|---|
| `LinArray t`, `IArray t` (contrib), and later a linear `Vect`-backed array | `tensor<?xE>` | value semantics; linear threading gives one SSA def-use chain per array, which is what One-Shot Bufferize wants (Bufferization.md "Destination-Passing Style": "works best if there is a single SSA use-def chain") |
| `IOArray`, `ArrayData`, `IOMatrix`, `Buffer` | `memref<?xE>` (for `Buffer`, `memref<?xi8>` plus `memref.view` for typed access) | shared mutable semantics, which is what Chez gives; memory effects order accesses, and the world orders IO |
| `IORef a`, `STRef s a` | `memref<E>` (0-d); `memref.alloca` when idr-stack proves it does not escape | `mem2reg` promotes it (`PromotableAllocationOpInterface` on memref allocations, MemRefMemorySlot.cpp:81), so `runST` loops become register loops |

Evidence, with the pinned `mlir-opt` on upstream dialects only
(`mlir/e*.mlir`):
- **e1** fill+sum: `scf.for` over a `tensor<?xi64>` with `tensor.insert`,
  then `tensor.extract`.
  - `test-analysis-only`: every tensor operand is `true` (in place).
  - After `one-shot-bufferize` and `buffer-deallocation-pipeline`: one
    `memref.alloc`, stores, loads, one `memref.dealloc`.
- **e3/e3b** bubble sort, where each swap is two `tensor.extract` and two
  `tensor.insert` on one chain.
  - 0 out-of-place operands.
  - The x86 inner loop is loads, a compare and two stores, unrolled by
    two, with no calls.
  - With the function private and called
    (`-canonicalize -drop-equivalent-buffer-results` before
    deallocation), `@bubble` becomes `(memref) -> ()`: one alloc and one
    dealloc in `main`, and no copy.
  - As a public function it returns a `bufferization.clone` of its
    argument. That is the ABI rule "a function must not return a MemRef
    with the same allocated base buffer as one of its arguments"
    (OwnershipBasedBufferDeallocation.md:55-76). Every function of ours
    except the root is private, so this does not apply to us.
- **e4** (h1, the escape): reading `%old` after `tensor.insert` into it.
  The analysis marks the insert `false` with the conflict triple
  `C_0[DEF] / C_0[CONFL-WRITE] / C_0[READ]`. Bufferization allocates and
  copies. That copy gives value semantics, which is correct Idris
  but *differs from Chez* (value semantics would print `Just 42`, then `Nothing`; Chez prints `Just 42` twice). So the conflict
  must become a rejection, and the analysis already gives us the three
  locations to name.
- **e2/e5, the upstream gap**:
  - The setup: a self-recursive function that threads the tensor.
  - e2 is a tail call; e5 is two non-tail calls in quicksort's shape.
  - The analysis says in place (0 `false`). But OneShotModuleBufferize
    analyzes recursive functions' bodies only, "All function boundary
    analyses are skipped" (OneShotModuleBufferize.cpp:511-526, a TODO).
  - So the result is not known to be equivalent to the argument, and
    `drop-equivalent-buffer-results` cannot fire.
  - `ownership-based-buffer-deallocation` then inserts
    `%6 = bufferization.clone %2` on the base-case path of `@rec`, plus
    pointer-compare deallocs and a `dealloc_helper` call with five small
    allocs in the caller.
  - For quicksort that is **a whole-array copy at every leaf: O(n²),
    silent.**
  - This is an upstream limitation that we would work around. By
    AGENTS.md it needs `upstream/one-shot-module-recursive-equivalence/`
    with e5 as the reproducer. The fix to propose upstream: an optimistic
    fixpoint over each recursive SCC. Assume every tensor result is
    equivalent to its tied argument, analyze the bodies, and retract
    until stable.

**Where the uniqueness type lives.** For arrays, no new wrapper type is
needed. The tensor SSA chain *is* the uniqueness proof, and One-Shot's
`AnalysisState::isInPlace` checks it (Bufferization.md, "Modular").
The idr contribution is:
1. Emit `LinArray` operations on a tensor carried as `!idr.lin<tensor<?xE>>`,
   so Idris's quantity 1 reaches the IR, and `idr.lin.use` it at each
   tensor op.
2. After the analysis, require every tensor OpOperand to be in place, and
   after deallocation, no `bufferization.clone`/`memref.copy` of an array
   buffer. Otherwise reject with `unsupported (uniqueness)` and the
   conflict triple mapped to Idris locations. This is the README's
   promise (in place or rejected with a named rule), with the analysis
   done by upstream.

For cells (lists, trees), which are not tensors, facts-ledger's
`!idr.uniq` remains the right type.

### The path, in order

1. **R1–R4** (frontend). Without them, the linear data never reaches MLIR.
2. **Runtime meaning of the backend contract.** Add entries of category 1
   (Registry/Primitives.idr) for `prim__newArray`, `prim__arrayGet` and
   `prim__arraySet` (Prims.idr:11-13) and for the three IORef
   primitives. Their shapes come from base. They lower to
   `memref.alloc`/`memref.load`/`memref.store` and 0-d memrefs.
   - Allocation is counted: `finalize-memref-to-llvm{use-generic-functions}`
     calls `_mlir_memref_to_llvm_alloc/free` (MemRefToLLVM.cpp:65-89),
     which the runtime defines, so an array is a counted cell that
     `idr.inc`/`idr.dec` understand.
   - This compiles benchmarks 10 and 11 and `Data.IOArray` as Chez
     means it.
3. **Recognize `Data.Linear.Array` at tensor level.** Add category 2
   entries, validated by shape:
   - `newArray n k` is `tensor.empty` plus fill;
   - `write` is Idris's bounds check plus `tensor.insert`;
   - `mread` is the bounds check plus `tensor.extract`;
   - `msize` and `size` are `tensor.dim`;
   - `toIArray` and `read` are the same tensor, used ω.

   This is "stricter, never different", because an escape is rejected
   rather than given value semantics. `IOArray`'s `Maybe elem` slots
   become a `tensor<?xi1>` initialised-bitmap next to a `tensor<?xE>`:
   the structure-of-arrays split, decided by the Idris side.
4. **Ordering.** Form loops before bufferization. `idr-tail-loops` runs
   after `idr-rc` today; array code needs `scf.for`/`scf.while` before
   `one-shot-bufferize`. Then run
   `one-shot-bufferize{bufferize-function-boundaries}`, `canonicalize`,
   `drop-equivalent-buffer-results`, then the check, then
   `buffer-deallocation-pipeline`, and only then `idr-rc` for cells.
   The two ownership systems meet where an array is stored in a cell: the
   cell holds one count of the array object, through a
   `to_buffer`/`to_tensor restrict` boundary.
5. **Bounds checks**, from `-int-range-optimizations` and
   `ValueBoundsOpInterface` on `tensor.dim`: `writeArray`'s
   `pos >= max arr` folds when the loop runs over `[0, dim)`.
6. **Raising to linalg.** A loop over `[0, dim)` that extracts at `i`
   and inserts at `i` along one iter_arg is a `linalg.generic`; a fill is
   `linalg.fill`; a fold is `linalg.reduce`. Then fusion and vectorization
   are upstream's.
7. **Upstream fix** for recursive SCCs (e5). Until it lands, the check in
   step 3 rejects non-tail-recursive array code explicitly, and never
   copies silently.

### 4.3 `%World` in LIO

LIO never touches `%World`. Its `Action` holds an `IO a`, which is
`MkIO` over a `(1 x : %World) -> IORes a` closure, and `bindL = io_bind`
threads the world as in any IO program. The world is already
`!idr.world`, linear by rule, admitted from PrimIO
(Libraries.idr:93-97). What LIO needs:
- R3, because `die1` is never reached;
- a representation for `L` that makes `runK` monomorphic.

The representation-first answer has two parts.
1. **Refine constructors by a finite field.** `Bind`'s `{u_act : Usage}`
   is a three-valued runtime field, and the type of its continuation
   (`ContType io u_act u_k a b`) is computed from it. Split `Bind` into
   `Bind_None | Bind_Linear | Bind_Unrestricted` at the Idris side, so
   each field has a closed type and `None`'s continuation has its erased
   argument absent. A field whose type depends on a finite field is a sum
   not yet written out. `Pure0`/`Pure1`/`PureW` already show the pattern
   in the library itself.
2. **Treat the existential `a` of `Bind` as a key, not a type argument.**
   `idr-specialize` already clones on known constructors and closures.
   `runK` applied to `Bind act next`, where the construction site is
   known, is specialized with that site's `a`. Only a truly dynamic `L`
   tree would need a uniform representation for `a`, and that can stay
   an explicit `unsupported (polymorphism)`.

With both, `run (loop n c)` specializes to world-threaded straight-line
code: benchmark 7's target of no `L` cells. Uniqueness of a resource
returned with `use = 1` stays convention. The compiler should give it
`!idr.lin`, never `!idr.uniq`, unless a recognized creator made it.

### 4.4 Code built on `believe_me` against our verifier

The escape hatches in these libraries are few, and each has a meaning
that the idr verifier can check once it is written as idr:

| hatch | where | runtime meaning | as idr |
|---|---|---|---|
| `Consumable Int = believe_me (\0 i => ())` | Interface.idr:33-34 | drop an Int | drop a `!idr.lin<i64>`; the verifier allows "at most once" (Dialect.cc:397-420) |
| `assert_linear f x` (`= believe_me id`) | Builtin.idr:198-199; Concurrency/Linear.idr:212-214 | `f x` | `lin.use x` then `f`: sound for linearity. It must **drop uniqueness**: after `lin.use`, a `!idr.uniq` value may only continue as shared, since `f` may duplicate it |
| `unsafePerformIO` in LinArray, ST | Array.idr:40-52; ST.idr:131-134 | allocation and mutation that are invisible when unique | replaced by recognition (§4.2 step 3) and `mem2reg`; never admitted as world use |
| `assert_smaller` in IOArray, Iterator | IOArray.idr:69; Iterator.idr:79 | totality only | already trusted in trusted code (Libraries.idr:112-113) |

The rule: a `believe_me` is admitted only through a registry entry that
states its idr meaning. The verifier then re-checks that meaning after
every pass. `believe_me` itself stays rejected, as today.

## 5. Sketch: the smallest additions that carry the weight

Each item below names what it carries and which pass consumes it.

**Types.** No new array type: `tensor<?xE>` (value arrays) and
`memref<?xE>`/`memref<E>` (mutable arrays and refs) are the types.
- Counted idr types (`!idr.box`, `!idr.str`, `!idr.big`, `!idr.fn`)
  implement `MemRefElementTypeInterface`
  (BuiltinTypeInterfaces.td:162-165), so arrays of them can bufferize.
  Tensor already accepts non-builtin elements (BuiltinTypes.cpp:433-439).
- `!idr.lin<tensor<...>>` needs nothing new: quantity 1 on the array
  handle is what makes the chain single.
- For cells, add facts-ledger's `!idr.uniq<!idr.box<@T>>` (made only by
  `idr.con`/`idr.reuse`/a `!idr.uniq` parameter; never `idr.inc`'d;
  `idr.take`/`idr.reset` of it untested). It is computed by an MLIR
  `DataFlowSolver` analysis (§4.0), not by a hand-written fixpoint, and
  written into the types, where the verifier re-checks it after every
  pass. One more op,
  `idr.uniq.share : !idr.uniq<T> -> T`, is the only way out: Marshall
  §3's "forget uniqueness" direction, with no inverse.

**Ops.** None in the first step (§4.0): scalar and unboxed arrays use
upstream `tensor`, `memref` and `bufferization` ops only. Later, one op for
counted elements, if they are ever admitted:
- **`idr.array.set`.** It is destination-style (`DestinationStyleOpInterface`,
  `BufferizableOpInterface`) and takes `(%t : tensor<?x!idr.box<@T>>, %i : index, %v : !idr.box<@T>) -> tensor<...>`.
  - It exists because overwriting a counted slot must release the old
    element, and `tensor.insert` cannot say so.
  - It bufferizes to `%old = memref.load`, `idr.dec %old`,
    `memref.store %v`.
  - Scalar and unboxed arrays use upstream `tensor.insert` and
    `tensor.extract` unchanged.
- **External models, not new ops.** `BufferizableOpInterface` models for
  `idr.match`/`idr.yield` (region branches, as `scf.if` has) and for a
  tensor stored in an `idr.con` field (a `to_buffer` boundary).
- **Primitive and recognizer entries** in the frontend registry
  (§4.2 steps 2–3). These are data, not ops.

**Runtime.**
- **An array cell kind** (`IDRIS_RT_KIND_ARRAY_SCALAR`/`_OBJ`): the
  header, a length word, then aligned data.
  - The header's 8-bit `objs` cannot count slots (review-external.md), so
    the kind says "every slot is an object" and the length bounds the
    walk.
  - `_mlir_memref_to_llvm_alloc`/`_free` are the runtime's, so
    `memref.dealloc`, `idr.dec` and a cell's release are one mechanism.
    For `_OBJ`, free releases each slot.
- **`idris_rt_inc_n`** already exists (idris_rt.h:151). It gives the
  n-fold reference of `prim__newArray n x`'s shared initial element.
- **`IORef`**: a 0-d memref with a header, so an escaping ref is counted
  and a non-escaping one is an `alloca`.

**Verifier and expect rules.** One new property, `arrays-in-place`:
- no tensor OpOperand is decided out of place;
- no `bufferization.clone`/`memref.copy` of an array buffer remains after
  deallocation.

Together they are the rejecting check, stated once. With it and the
existing `no-heap-allocation`/`reuses-in-place`/`counts-nothing`, every
benchmark in §3 is a property, not an op sequence.

**Ownership contract, as types.**
- A tensor used once (because `!idr.lin`) is written in place, and the
  analysis proves it; a tensor used more than once is rejected if it is
  ever written.
- A memref array is shared and counted, and its writes are effects.
- A cell of type `!idr.uniq` is reset without a test.
- Nothing can move a shared value back into a unique type.

## Open questions

- **Case blocks and reuse (q6).** Should the fix be to inline Idris case
  blocks before `idr-rc`, or to pass the reuse token into the callee,
  FP²-style reuse credits (Lorenzen, Leijen and Swierstra, ICFP 2023)?
  Or to specialize the case block per `Bool` constant, so each clone has
  one call site?
  - The second survives any inliner budget.
  - The third fixes the doubled call that `match_lit (extui ...)` creates.
  - Unverified: why `idr-specialize` does not already clone on the
    constant Bool.
- **The segfault on deep non-tail recursion (q5).** It is a crash where
  Chez returns a result. Is it the benchmark's job (tail recursion modulo
  cons), or the runtime's (a guard page plus a named `crash`)? Both, I
  think. A silent SIGSEGV is the worst of the three outcomes.
- **Pipeline order.** Does moving loop formation before `idr-rc` (§4.2
  step 4) conflict with the owned-stage verifier's loop special cases
  (`Verify.cc:211-233`)? mlir-ownership-types.md's `!idr.own` sketch
  would dissolve that special case too.
- **`LinArray`'s `Maybe` slots.** Could compile-time evaluation or affine
  analysis prove that a fill loop writes every slot, so the initialised
  bitmap disappears? Conjecture: only for loops over `[0, dim)`.
- **Upstream.** Should the missing case in OneShotModuleBufferize for
  recursive SCCs be filed now, with e5, before any of this is built?
  AGENTS.md requires it in the same change as any workaround.
- **Uniqueness beyond the continuation.** h1 shows the continuation
  pattern is not enough. Should the compiler refuse to recognize
  contrib's `newArray` unless the continuation's result type provably
  contains no `LinArray` (a type walk on the instance)? That would be a
  static, representation-level fix, rather than rejecting only after
  bufferization.
