<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Why array programs are refused

Status (2026-10-19, arrays lane): §4.A is built. Every type constructor's
argument has one role (Keyed, Formed, Held, Index; Translate/State.idr),
the data keys hold a shape's form, and R1, R2, R3, R6 and R7 are the
program tests arrays-key-*, R4 and R5 the reject tests
polymorphism-growing-extents and polymorphism-tower-of-ranks. Group A
compiles and runs; what the programs met after the frontend is in
audits/bugs.md. Groups B and C are upstream patches 56 and 57.

The investigation was run against HEAD 6f774119 with `build/dev` as built at
04:16 on 2026-10-19. The reproducers below were compiled with
`tools/compile.sh -p mlir-linear -p mlir-array` from scratch directories
under `/private/tmp/arr`. The proposed fix (§4) was not built: building a
patched frontend copy was not permitted in this session, so the claim that
it makes the eight programs compile is a reading, not a run.

The 13 failing tests have three independent causes:

| Group | Tests | Cause | Kind |
| --- | --- | --- | --- |
| A | linarray-bubble, linarray-fill-sum, linarray-map-fold-traverse, linarray-push-pop, linarray-read-past-size, linarray-reserve, linarray-write-past-size, vec-pop-then-push | A data instance key erases a value array's shape whole, so the rank is lost before the field's type is read | Frontend bug: a wrong refusal |
| B | linarray-combinators, linarray-lanes-exact, linarray-lanes-wide, determinism-threads-linarray-lanes | Nothing is vectorized, because `idr-narrow` cannot bound `linalg.index`; and `mlir.expect` names a step the pipeline no longer has | A missed optimization plus a stale test |
| C | linarray-rows-crash-order | Upstream CSE merges a nested `linalg.index` into the outer one | Upstream bug: silent miscompile |

## 1. The refusal (group A)

### Where it is made

The refusal comes from `shapeDims` (compiler/src/IdrisMLIR/Frontend/Translate/Types.idr:394-400):

```idris
shapeDims fc owner shape = do
  shape' <- normaliseClosed shape
  let Just extents = shapeSpine shape'
    | Nothing => reject fc owner Polymorphism ("a shape whose rank no analysis fixes: " ++ !(showTT shape'))
```

`heldTypeIn` (Types.idr:745-756) calls it for a type whose head has the
`valueArray` hook (`Array`, `LArray`): the tensor's rank is the length of
the shape's snoc spine (`shapeSpine`, Translate/Shapes.idr:63). "A shape
whose rank no analysis fixes" means the shape term is not a `Lin`/`:<`
spine. The rule is `Polymorphism`, which IdrBase.td:185 files under
`Idr_Megamorphic`. The same message is spelled a second time for function
form parameters (Translate/Instances.idr:287-288). That copy does not fire
here.

The owner is the constructor (`Linear.Notation.MkBang`, `Builtin.DPair.(#)`,
`Prelude.Types.Just`, ...). The call path is
`dataInstanceIn` → `constructor` → `walk` (Types.idr:860-870), which reads
each field type under the constructor's name.

### What `[__]` is

`[__]` is how the fork prints `Erased` (compiler/idris/src/Core/TT/Term.idr:671).
The shape is not `[<__]` (a rank-1 form whose extent is erased). The whole
shape argument is `Erased`.

### Why it fires

Data instances are keyed with their indices erased (Types.idr:791-794):

```idris
args <- traverse (\(i, a) => if elem i keep
                                then eraseIndices owner !(canonicalTypeArg a)
                                else pure (Erased EmptyFC Placeholder)) ...
```

`eraseIndices` (Types.idr:514-540) recurses into every type argument,
lambda bodies of families included. At each type constructor it keeps only
the `typeParams` positions and replaces every other argument with `Erased`.

`Array` and `LArray` are declared `(0 s : Shape) -> Type -> Type`
(libs/mlir-array/Array/Core.idr). `Shape` is `SnocList Nat`, a value kind,
so `typeParams` excludes position 0: it is treated as an index. So
`Maybe (Array [<3] Int)` is keyed as `Maybe (Array __ Int)`. When the
instance is registered, `Just`'s field type is `Array __ Int`, and
`shapeDims` sees `Erased` where a spine should be.

The function side already knows a third kind of argument. `keyingOf`
(Instances.idr:213-232) decides `Formed` for an erased shape that a value
array's type needs, and keys the instance by `shapeForm` (Shapes.idr:75),
which keeps the spine and erases the extents. The data side has only two
kinds (keep, or erase whole), so the rank, which is part of the
representation (`tensor<?xi64>` against `tensor<?x?xi64>`), is destroyed
before the one reader that needs it.

### Is the refusal right?

No. Every refused program fixes its ranks. In the reproducers below the
rank is a literal or a fixed spine, and in R1 and R3 even the extents are
static. The construct that is actually refused is "a value array inside a
type argument" (`!*`, `Res`, `Maybe`, `DPair`, and `IORes` and `Pair` in
bench), or "a data type over a shape its field's array has". That is
bounded by construction. It is a gap in the key representation, not a
megamorphic construct.

### Reproducers (all run; each refused with exit 3)

R1, `!*` of an array (`Linear.Notation.MkBang`):

```idris
module Main
import Prelude
import Array
import Linear.Notation

main : IO ()
main = do
  let MkBang v = withArray [<3] (the Int 7) (\a => LArray.freeze a)
  printLn (v !! [<0])
```

```
idris-mlir: unsupported (polymorphism): Linear.Notation.MkBang: a shape whose rank no analysis fixes: [__]
```

R2, `Res` of a linear array (`Builtin.DPair.(#)`, the result of `LArray.read`):

```idris
main : IO ()
main = do
  let MkBang x = withArray [<3] (the Int 7) (\a => let x # a = LArray.read a [<0] in let MkBang _ = LArray.freeze a in MkBang x)
  printLn x
```

```
idris-mlir: unsupported (polymorphism): Builtin.DPair.(#): a shape whose rank no analysis fixes: [__]
```

R3 shows that linearity plays no part:

```idris
box : Maybe (Vector 3 Int)
box = Just (tabulate [<3] (\[<i] => cast (finToNat i)))

main : IO ()
main = case box of
  Just v => printLn (v !! [<1])
  Nothing => pure ()
```

```
idris-mlir: unsupported (polymorphism): Prelude.Types.Just: a shape whose rank no analysis fixes: [__]
```

R7, a dependent pair of a vector, where the shape sits under the family's lambda:

```idris
ramp : Nat -> (n ** Vector n Int)
ramp k = (k ** tabulate [<k] (\[<i] => cast (finToNat i)))

main : IO ()
main = let (n ** v) = ramp 4 in printLn (sum v)
```

```
idris-mlir: unsupported (polymorphism): Builtin.DPair.MkDPair: a shape whose rank no analysis fixes: [__]
```

R6, a data type over a shape parameter. This is the second face of the same
gap: `typeParams` drops `Grid`'s `s` (kind `Shape`), so `Grid [<2, 3]` is
keyed as `Grid __`:

```idris
data Grid : Shape -> Type where
  MkGrid : Array s Int -> Grid s

corner : Grid [<2, 3] -> Int
corner (MkGrid a) = a !! [<0, 0]

main : IO ()
main = printLn (corner (MkGrid (tabulate [<2, 3] (\_ => 7))))
```

```
Main.idr:9:3: error: unsupported (polymorphism): Main.MkGrid: a shape whose rank no analysis fixes: [__]
```

The fix must keep refusing the genuinely unbounded cases. Two run today:

R4 is refused by the growth check, through the function's form parameter:

```idris
deeper : Extents s -> Array s Int -> Nat -> Int
deeper e a Z = cast (volume e)
deeper e a (S k) = deeper (e :< 1) (tabulate (e :< 1) (\_ => 0)) k
```

```
Main.idr:8:1: error: unsupported (polymorphism): Main.deeper: Main.deeper passes s as (Prelude.Basics.(:<) Prelude.Types.Nat s (Prelude.Types.S Prelude.Types.Z)) to Main.deeper, growing it by 1 each round, and nothing bounds how far it grows
```

R5 is refused by `shapeDims`, rightly: a `Tower`'s values hold arrays of
every rank, and the field's shape is the type's own erased index:

```idris
data Tower : Shape -> Type where
  Top : Tower s
  Floor : Array s Int -> Tower (s :< 1) -> Tower s
```

```
Main.idr:10:3: error: unsupported (polymorphism): Main.Floor: a shape whose rank no analysis fixes: [__]
```

No test in `tests/` states either R4 or R5. A `grep` for the message over
`tests/` finds nothing, so the refusal has no reject test.

The bench programs that audits/repo-tests.md §2 lists (fannkuch-linear,
k-nucleotide, qsort, spectral-norm-linear, unionfind) have the same cause.
Their refusals also name `PrimIO.MkIORes` (an `IO (Array ...)` from
`tabulateIO`) and `Builtin.MkPair`.

## 2. Each failing test

**Group A.** These tests are all `Linear.Vec` / `LArray` programs:
linarray-bubble, linarray-fill-sum, linarray-map-fold-traverse,
linarray-push-pop, linarray-read-past-size, linarray-reserve,
linarray-write-past-size and vec-pop-then-push. Each compiles with exit 3
on `MkBang` and/or `(#)`, as §1 describes. The sources are
`Vec.freeze : ... -> !* (Vector n a)` and `LArray.read`/`LArray.shape :
... -> Res _ (const (LArray s a))`. `Vec`'s own field
(`LArray [<cap] a`, with `cap` erased) is fine: there the shape is a spine
with an erased extent. linarray-map-fold-traverse reports only `(#)`.

**Group B.** linarray-combinators, linarray-lanes-exact and
linarray-lanes-wide compile and every case runs as expected. They fail
their `mlir.expect` checks:

1. "no module dumped after eliminate-empty-tensors". The pipeline has had
   no such step since bfdcac70 (2026-10-15), when idr-bufferize took over
   empty-tensor elimination (Pipeline.cpp:117-120: "It eliminates empty
   tensors itself"). The line survived the rewrite in d346040c.
   `structured-loops` holds at the next top-level step: `idr-expect` on
   linarray-combinators' `0_10_idr-bufferize.mlir` passes, and on
   `0_9_symbol-dce.mlir` it fails, because the tabulates are still
   unlowered there. So this is a stale test line.
2. "expected vectorized: no loop computes on vectors" (and, for
   lanes-wide, "narrowed-lanes"). With `--remarks-filter=idr-lanes`, all
   29 loops the schedule tries report "the loop stays scalar: its body is
   not one the vectorizer takes". After `idr-lower`, the bodies still
   compute on bigs: the index goes through `idris_rt_small_word`,
   `idris_rt_big_cmp`, `idris_rt_big_pred`, `idris_rt_big_add` and
   `idris_rt_big_to_int` calls, which come from `at i = cast (finToNat i)`.
   `idr-narrow` runs after `idr-structure-loops`. Inside a
   `linalg.generic` the index is `linalg.index`, and upstream gives
   `linalg.index` no `InferIntRangeInterface`, so the range analysis
   cannot prove the natural made from it (`idr.big.small`) small. The
   upstream analysis bounds an `scf.for` induction variable but not a
   `linalg.index` (run with the pinned `mlir-opt --int-range-optimizations`):

   ```mlir
   // linalg body: `cmpi sge (index_castui %i), 0` stays.
   // scf.for body: the same compare folds to `true`.
   ```

**determinism-threads-linarray-lanes.** Its module is identical under one
thread and under many. It fails only on "idr-narrow-lanes said nothing",
because no loop is vectorized and `idr-narrow-lanes` acts only on
vectorized loops. Same cause as group B, item 2.

**Group C: linarray-rows-crash-order, a silent miscompile.** The `one-row`
case prints -16 where -9 is expected. `column-zero` crashes in `mod` where
no crash is expected, and `div-first` crashes in `mod` where the crash
should be in `div`. The module is right after `idr-structure-loops`. In
`Main.main.delay.2bff1ee2bcdd7307`, the function-nested CSE that runs right
after `idr-bufferize` (dump `0_10_9_cse`) replaces the inner generic's
`linalg.index 0` (column `j`) with the outer generic's (row `i`): the count
of `linalg.index` ops drops from 3 to 2 at that dump. So `j` reads as `i`,
and every value follows. With n=1 and m=4, the sum is
4·(100 div −20 + 100 mod −11) = −16. With n=2 and m=1, row 1 reads j=1,
and the `mod` divisor 1·10+1−11 is 0.

This reproduces upstream alone, with the pinned `mlir-opt --cse`:

```mlir
func.func @nested(%n: index, %m: index) -> tensor<?xindex> {
  %e = tensor.empty(%n) : tensor<?xindex>
  %r = linalg.generic {indexing_maps = [affine_map<(d0) -> (d0)>], iterator_types = ["parallel"]} outs(%e : tensor<?xindex>) {
  ^bb0(%out: index):
    %i = linalg.index 0 : index
    %ie = tensor.empty(%m) : tensor<?xindex>
    %inner = linalg.generic {indexing_maps = [affine_map<(d0) -> (d0)>], iterator_types = ["parallel"]} outs(%ie : tensor<?xindex>) {
    ^bb1(%o: index):
      %j = linalg.index 0 : index
      linalg.yield %j : index
    } -> tensor<?xindex>
    %c0 = arith.constant 0 : index
    %x = tensor.extract %inner[%c0] : tensor<?xindex>
    %s = arith.addi %i, %x : index
    linalg.yield %s : index
  } -> tensor<?xindex>
  return %r : tensor<?xindex>
}
```

After `--cse`, the inner body is `linalg.yield %2` (the outer index).
`linalg.index` is `Pure`, but its value depends on the immediately
enclosing structured op. Upstream CSE (lib/Transforms/Utils/CSE.cpp:314-321)
shares one scope across every nested region that is not
`IsolatedFromAbove`.

There is also a latent conflict. The test's comment says a crashing step
keeps the row loop ordered, but `StructureLoops/Forms.cpp:5-6` makes a
region that only computes and crashes parallel, and the row tabulate is
structured as a parallel `linalg.generic`. Today nothing reorders it,
because convert-linalg-to-loops runs the rows in order and the vectorizer
declines the body. Once group B is fixed, the vectorizer could take crashing
bodies and tile the rows, which would change which crash comes first. That
needs one ruling, stated in Forms.cpp and in the test.

## 3. Since when

- **Group A has never worked.** Shape-indexed arrays (libs/mlir-array,
  `valueArray`, `shapeDims`, `FormParam`) arrived in c7aa7b62 (2026-10-14).
  That commit taught the function keys about forms and left
  `eraseIndices`, which is older (written for `Vect`), erasing every
  non-type-parameter argument whole. Its `Array`/`LArray` were already
  `(0 s : Shape)`. bfdcac70 made them `[external]` without changing that.
  c7aa7b62, d06ed15c and 2c042728 were integrated on the typecheck machine
  ("nothing is built or run"). The tests were ported from the old
  `Linear.Array` (`Array a`, no shape: `git show c7aa7b62^:libs/mlir-linear/Linear/Array.idr`)
  without being run. The first run on record is the audit of 66fc1401
  (2026-10-18; audits/done-programs-1.md C, audits/SUMMARY.md §5.4 item 19),
  which saw the refusal and did not root-cause it. Before c7aa7b62 these
  programs compiled against the unshaped library, so they "worked" only in
  that earlier form.
- **Group B since c7aa7b62.** `idr-structure-loops` has run before
  `idr-narrow` at every revision since (Pipeline.cpp:
  c7aa7b62 56/82, bfdcac70 75/100, d06ed15c 81/106, 2c042728 118/140,
  HEAD 117/139). The stale step name dates from bfdcac70.
- **Group C since c7aa7b62**, which first structured a tabulate in a
  tabulate's body into nested `linalg.generic`s, with CSE run over them
  after bufferization.

## 4. The fix, representation first

### A. A third key kind: a shape's form

The bad state is a data instance key that holds a value array type
without its rank. One argument kind is missing on the data side, though
the function side already has it as `Formed`. The proposal:

1. **One role per argument position of a type constructor.** In
   `TyConFacts` (Types.idr:406-428, State.idr), replace `typeParams : List Nat`
   by a role per position: `data Role = Keyed | Formed | Index`.
   - The base case of `Formed` is a value array's shape position, read
     from the `valueArray` hook.
   - Otherwise, a position is `Formed` when its kind is the shape type and
     some constructor's runtime field puts the binder into a value array's
     shape. This is the test `keyingOf` already applies to a function's
     binder (`isShapeType`, `formNeeded`); run the same function on
     constructor types, so that one rule decides both.
   - `typeParams` becomes the `Keyed` positions, and `represented`
     (Types.idr:262) includes the `Formed` ones.
   - This makes two existing branches into one rule. Nothing is added as an
     `if valueArray` special case in `eraseIndices`.
2. **Key with the form.** `eraseIndices` (Types.idr:528-540) dispatches on
   the role: a `Keyed` argument recurses, a `Formed` argument becomes its
   form, and an `Index` argument becomes `Erased`. `dataInstanceIn`
   (Types.idr:791-797) keeps `Formed` positions in `args` and `statics`.
   `walk` then passes the form as a `Param`, so `MkGrid`'s field reads
   `Array [<_, _] Int`.
3. **Parse the form once, at the boundary.** Generalise `ShapeView` and
   `shapeForm` (Shapes.idr:40-80) from `ClosedTerm` to `TT vs`, because
   R7's shape sits under the family's lambda. Add one function
   `formOf : FC -> String -> TT vs -> Core form` that refuses
   `Polymorphism` with the one message. It is called where a key is built
   (`eraseIndices`/`dataInstanceIn`), by `classify` (Instances.idr:287),
   and by `shapeDims` (Types.idr:398), and the second copy of the message
   string goes. The check moves to the key boundary: a key whose form
   position holds no form is never built. After that, `shapeDims` sees a
   non-spine only where the program really fixes no rank (R5).
4. **The growth check reads the same role.** `Sites.eraseIn`/`erasedAt`
   (Growth/Sites.idr:357-380) turn every unrepresented position into
   `Leaf 1`. A `Formed` position must be read as its form template instead
   (spine kept, extents `Leaf 1`). Otherwise `boundsHold` (Types.idr:675)
   finds a key higher than the bound the check computed, and raises the
   internal error "the growth check is unsound", not a refusal. Because
   both sides read one role, the key's height and the check's bound cannot
   drift apart.
5. **`outsideIndices` treats `Formed` as an index** (its extents are
   indices). So `Tower`'s field stays a `Polymorphism` refusal at `formOf`,
   not a `DependentField` one.

Per obligation:

| Obligation | Outcome |
| --- | --- |
| A key that drops a rank | Made unrepresentable: a `Formed` position holds a form, or there is no key |
| The rank check | Moved to the key boundary (`formOf`), one copy |
| The two-kind data keys and the function-only `Formed` | Unified into one per-position role |
| The duplicated refusal message | Deleted |
| The genuinely unbounded cases (R4, R5) | Stay refused: essential, the problem has them |

**Scope.** In compiler/src/IdrisMLIR/Frontend/: Translate/Types.idr
(`TyConFacts`, `typeParams`/`representedOf`, `eraseIndices`,
`dataInstanceIn`, `shapeDims`), Translate/State.idr, Translate/Shapes.idr,
Translate/Instances.idr (`keyingOf` shares the rule) and Growth/Sites.idr.
That is about five files and no C++.

**Tests.** Accept: R1, R2, R3, R6, R7 and the eight group-A programs.
Reject: R5, asserting `polymorphism` and the site. Neither R4 nor R5 is in
the tree today.

**Risk.**
- Instance keys that hold a value array change, so their hashed names
  change.
- The growth bound must cover form heights, or the result is `unsound`
  internal errors. This is item 4: test R1-R7 under the growth check.
- Every consumer of `typeParams` (`outsideIndices`, `paramLayout`,
  `represents`) must treat `Formed` deliberately, not as `Keyed`.
- Once these programs compile, they reach the passes for the first time.
  Expect later bugs: rc over `!*`/`Res` of tensors, bufferization of a
  tensor in a constructor field.

### B. Vectorization

- **Stale test line.** In the `mlir.expect` of linarray-combinators,
  linarray-lanes-exact and linarray-lanes-wide, the step
  `eliminate-empty-tensors` becomes `idr-bufferize`. This was checked on
  the dump. It is a test edit, not made here.
- **Ranges.** Use the MLIR mechanism that is missing: `linalg.index`
  implements `InferIntRangeInterface`, giving `[0, range − 1]` where the
  enclosing op's static loop range is known, and `[0, signed max − 1]`
  otherwise (a dimension is a non-negative index). Then `idr-narrow` proves
  index-derived naturals small, the bodies become word arithmetic, and the
  vectorizer takes them. This is an upstream patch under
  `upstream/<bug>/llvm-project.patch`, with its `tests/upstream-<bug>` and
  a `PINS.md` entry. The upstream test goes in
  `mlir/test/Dialect/Linalg` (int-range). Moving `idr-narrow` before
  structuring is the alternative, but it leaves the gap in place for
  every later pass, so it is not recommended.
- **Scope.** One upstream patch, then three `mlir.expect` lines and
  determinism-threads-linarray-lanes go green with no code of ours
  changing.

### C. CSE of nested `linalg.index`: upstream bug, upstream patch

The reproducer above is the report. Per AGENTS.md, the patch lives in
`upstream/<bug>/llvm-project.patch`, with `tests/upstream-<bug>` and a
`PINS.md` entry, and no workaround goes into `idr-structure-loops`.

Patch direction: CSE must not replace an op by an equivalent op in an
enclosing region when the op's value is that of its enclosing op. Two
candidates:
- Linalg declares this of `linalg.index` through a trait or interface that
  CSE checks (equivalent only with the same parent op).
- CSE opens a fresh scope at the regions of ops that bind such implicit
  values, as it already does for `IsolatedFromAbove`.

The upstream test goes in `mlir/test/Transforms/cse.mlir`. Until it lands,
linarray-rows-crash-order is a silent miscompile (wrong numbers, reads past
`v`), so fixing it comes before A and B. The ruling on crash order
(Forms.cpp against the test) is separate, and is needed before B lets the
vectorizer tile crashing bodies.
