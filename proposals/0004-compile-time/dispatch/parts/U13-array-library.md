# U13 — The typed array library, its linear vector, and the programs over them

## Permitted outcome
1. Mandatory. `libs/mlir-array` exists as an installable package
   (`mlir-array.ipkg`, `depends = base, mlir-linear`) with exactly the
   modules `Array.Core`, `Array` and `Linear.Vec`, whose exported surface
   is C19's, name for name and type for type, and nothing more.
2. Mandatory. `libs/mlir-linear` keeps `Linear.List`, `Linear.Nat`,
   `Linear.Notation` and `Linear.String.Iterator` unchanged; its growable
   array module and its two Scheme-spec primitives are deleted, and its
   `.ipkg` lists the four modules left and a brief that no longer names
   arrays.
3. Mandatory. `compiler/idris/src/Libraries/Data/Table.idr` is a growable
   table on base's `Data.IOArray`, mutated in the world's order, with the
   API C19 fixes; it imports nothing of `libs/`.
4. Mandatory. The five bench programs (`bench/fannkuch-linear/Main.idr`,
   `bench/spectral-norm-linear/Main.idr`, `bench/qsort/Main.idr`,
   `bench/k-nucleotide/Main.idr`, `bench/unionfind/Main.idr`) are ported
   to `Array` and `Array.Core`; each prints byte for byte what it prints
   today for its committed input.
5. Mandatory. Every library module and every ported bench program
   typechecks with the pinned Idris in a private build directory
   (Acceptance gives the commands).
6. Mandatory. The handoff lists the seams below (files no lane owns that
   the cutover still needs changed), each with its exact edit.

Consumer adaptations this lane makes: the five bench programs and the
fork's table, both within the writes below. No other consumer is adapted
here.

## Owner / exclusive writes
- `libs`, all of it:
  - new: `libs/mlir-array/mlir-array.ipkg`, `libs/mlir-array/Array.idr`,
    `libs/mlir-array/Array/Core.idr`, `libs/mlir-array/Linear/Vec.idr`;
  - changed: `libs/mlir-linear/mlir-linear.ipkg`;
  - deleted: `libs/mlir-linear/Linear/Array.idr`;
  - unchanged: `libs/mlir-linear/Linear/List.idr`, `Linear/Nat.idr`,
    `Linear/Notation.idr`, `Linear/String/Iterator.idr`.
- `compiler/idris/src/Libraries/Data/Table.idr` (rewritten).
- `bench/fannkuch-linear/Main.idr`, `bench/spectral-norm-linear/Main.idr`,
  `bench/qsort/Main.idr`, `bench/k-nucleotide/Main.idr`,
  `bench/unionfind/Main.idr` (ported).

**Excluded:**
- `compiler/src/IdrisMLIR/Registry/Libraries.idr` (the trust row for
  `mlir-array`), `Registry/Recognized.idr`, `Registry/Primitives.idr` (the
  recognition of the generating set, the deletion of the old array
  entries) and every frontend file: U14.
- `tests/programs/arrays/*`, `tests/programs/linear/*`,
  `tests/reject/*`, every `packages` file under `tests/`: U18.
- `bench/run.sh`, `bench/report.sh`, `bench/README.md`: U18.
- `Makefile`, `tools/self.sh`, `AGENTS.md`, `README.md`, `HANDOFF.md`:
  the coordinator.
- Owned by no lane in ownership.json, needed by this cutover; reported as
  seams with the exact edit (Implement, "Seams"), never written here:
  `compiler/idris/idris-compiler.ipkg`, `compiler/idris/src/Core/Context.idr`,
  `compiler/idris/src/Core/Context/Context.idr`,
  `compiler/idris/src/Core/Core.idr`, `compiler/idris/README.md`, and the
  `packages` files `bench/fannkuch-linear/packages`,
  `bench/spectral-norm-linear/packages`, `bench/qsort/packages`,
  `bench/k-nucleotide/packages`, `bench/unionfind/packages`.

## Read first
- `proposals/0004-compile-time/contracts.md`: C19 (this lane's, the
  authority over everything below) and C20 (how the frontend trusts and
  recognizes the library). Until `contracts.md` exists, read
  `contracts/C19-array-library.md`.
- `proposals/0003-typed-apl/README.md`: §3 (lines 269-608), above all
  §3.1-§3.5 (283-458) and §3.8 (513-588); §4.1 (611-648, what each
  primitive means); §6 (896-955, the meaning of every fold is its left fold
  in index order); §13 (1463-1483); §15 (1506-1529); §17 stage 1
  (1619-1654); §19 D1-D19 and D37-D38 (1791-1922); §21 items 1 and 4
  (2028-2049).
- `proposals/0004-compile-time/README.md`: §2.9's in-place row (line 467);
  §4 stage 1's in-place fact (759-764).
- `AGENTS.md`: the paragraph on `libs/` and trusted libraries
  (`unsafePerformIO`, a forged world) and the rules "Indexed vectors do
  not imply contiguous storage" and "A linear binder does not imply unique
  heap ownership".
- `libs/mlir-linear/Linear/Array.idr:1-291`, the library this lane
  replaces: its growth rule (`grown`, 163-173), its push and reserve
  (182-219), its crash idiom (40-50), its `unsafePerformIO` write idiom
  (134-144). `libs/mlir-linear/mlir-linear.ipkg:1-13`;
  `Linear/Notation.idr:26-41` (`!*`, `MkBang`).
- `compiler/idris/src/Libraries/Data/Table.idr:1-44` and its only callers:
  `compiler/idris/src/Core/Context.idr:47-60, 92-116`;
  `Core/Context/Context.idr:342-344, 392-401`; `Core/Core.idr:1062-1077`
  (`threadRef`, the table's only user of it).
- Base, unmodified: `third_party/Idris2/libs/base/Data/IOArray.idr:1-81`;
  `Data/IOArray/Prims.idr:1-13`; `Data/IORef.idr`; `Data/Fin.idr:55-58,
  130-132, 185-205` (`finToNat`, `shift`, `natToFinLT`, `natToFinLt`);
  `Data/Fin/Split.idr:28-31` (`splitSum`); `Data/Fin/Properties.idr:16-18`
  (`elemSmallerThanBound`); `Data/Nat.idr:115-130, 239-306,
  451-470, 565-567, 639-640` (the lemmas the library's proofs use);
  `Data/Zippable.idr:9-60`; `Data/Buffer.idr` (`getBits8`);
  `third_party/Idris2/libs/prelude/Prelude/Interfaces.idr:265-315,
  408-409` (`Foldable`; `sum = concat @{Additive}`, a `foldMap`).
- `compiler/src/IdrisMLIR/Registry/Libraries.idr:87-104` (trust follows the
  package a TTC lives in) and `Registry/Recognized.idr:225-229`
  (`idris_crash` in a trusted library).
- `Makefile:159-173` (`install` installs in list order) and `220-238`
  (`SHIPPED`, today a wildcard).
- The five bench programs, whole, with their `input`/`input-from` files.
- `proposals/0004-compile-time/array-drafts.json`, entry 0 ("LIBRARY and
  FORK PORT"): an earlier draft. What still holds is folded into C19;
  its `Linear.Ref`, its table on a linear vector and its fork edits are
  superseded by 0003 D37 and D38.

## Fixed decisions
- Packages. `mlir-array` depends on `base` and `mlir-linear` (D1), and
  needs `mlir-linear` installed first. `mlir-linear` depends on `base`.
  Neither declares a `%foreign` or an `%extern` beyond the string
  iterator's three, which stay (D37): the library is plain Idris over
  base's `Data.IOArray.Prims`, so Idris's Chez backend, which the host
  build runs on, needs no meaning of ours.
- Modules and names are C19's. `Array.Core` holds the shape types, the
  two array types with their private representation, and every function
  that opens that representation: the generating set, the linear half and
  the world bridge, each recognized by its qualified name
  `Array.Core.<name>`. `Array` re-exports `Array.Core` (`import public`)
  and adds only code over it. `Linear.Vec` is code over `Array.Core`'s
  linear half. The module boundary is the invariant: only `Array.Core`
  can name the constructors, so no vocabulary function can bypass the
  generating set.
- The private representation, in `Array.Core` only:
  `data Cells : (0 s : Shape) -> Type -> Type` with
  `None : (0 empty : count s = 0) -> Cells s a` and
  `Slots : ArrayData a -> Cells s a` (the `count s` elements, row-major);
  `MkArray : Extents s -> Cells s a -> Array s a` and
  `MkLArray : Extents s -> Cells s a -> LArray s a`. An empty array holds
  the proof of its emptiness, so an access, which holds an `Index s`,
  refutes `None` with that proof (`void`), never with a runtime test. The
  extents are held once, in the value; the backing's length is never read.
- An `LArray` write updates the backing in place inside `unsafePerformIO`,
  the idiom of the deleted module (`Array.idr:142-144`): right on every
  backend because no old version of an `LArray` is ever read again. An
  `Array` is never written after it is built.
- `freeze` gives the backing as an `Array` with no copy; `thaw` copies;
  `grow` and `update` build a fresh backing; `withArray` and `tabulateIO`
  allocate one.
- `withArray`, `thaw` and `withVec` take their continuation at quantity 1
  and return its `!* b` (Linear Haskell's `alloc`), not 0003 §3.8's
  `((1 _ : LArray s a) -> Ur b) -> b`: with that sketch no program can
  hold two linear arrays at once (a nested `withArray` gives `b` where
  `!* b` is due, and an unrestricted continuation cannot capture a linear
  array). C19 records the reason; I2 is unchanged.
- Coordinates. A coordinate is a `Fin` (D4). The checked conversion from a
  natural is `checkIndex : (n : Nat) -> Nat -> Maybe (Fin n)`, one
  comparison through `choose (i < n)` and `natToFinLt` under the erased
  proof; base's `natToFin` is not used, because its `Dec` carries its
  `LTE` proof at run time, a recursion on every backend. `(!?)` takes
  `SnocList Integer` (0003 §3.2) and is `Nothing` for a negative
  coordinate, a wrong rank or a coordinate past its extent.
- Folds. Every fold of the library means its left fold in index order
  (0003 §6, D15): `Foldable`'s `foldl` and `foldMap` are left folds in
  row-major order, so `sum` adds from the left; `foldr` is the right fold
  over the same order.
- `Linear.Vec`. A vector is `MkVec : (size : Nat) -> (0 fits : LTE size
  cap) -> (1 cells : LArray [<cap] a) -> Vec a`, `cap` erased: the
  capacity is the extent of the array, read with `lshape`, held once (D37).
  It grows by `grow` to `max need (max 4 (2 * cap))` slots, the deleted
  module's rule (`Array.idr:168-173`) and 0003 §3.8's doubling, so `n`
  pushes copy fewer than `2n` elements. A coordinate outside `[0, size)`
  consumes the vector, then ends the program with `assert_total
  (idris_crash "array index out of bounds")`, base's own idiom for a
  crash in total code (`Data/Buffer.idr:321`).
- The fork's table is `Table a = IORef (IOArray a)`: one cell holding
  base's array, whose length (`max`) is the capacity and whose unwritten
  slots read `Nothing`. It holds no count of its own: the context's
  `nextEntry` is the high-water mark already, and a slot past it was never
  written, so it reads empty (D38: mutation in program order of a table
  the world orders). Claiming slot `i` past the capacity replaces the
  backing by `newArrayCopy` at `max (i + 1) (max 4 (2 * cap))`; claiming
  `n` slots copies fewer than `2n` entries.
- Bench ports keep each program's algorithm, input and output. A
  coordinate the program computes is checked with `checkIndex` where it
  is used, and the program states what a failed check means (it never
  fails for these programs' inputs); a loop over an array's extent counts
  in `Nat`. spectral-norm-linear writes each product as `tabulate` over
  rows of `sum (tabulate ...)` over columns, 0003 §3.2's form for a
  product. k-nucleotide copies its sequence out of the `Buffer` once with
  `tabulateIO`.

## Inputs
- C20: the frontend admits every module of the installed package
  `mlir-array` as a trusted library (the `InHouse` row, as `mlir-linear`
  is), recognizes the names C19 lists by their qualified names and never
  translates `Array.Core`'s constructors; `Data.Fin.natToFinLT` and
  `Data.Fin.finToNat` cost nothing (Fin and Nat are one representation).
  This lane writes against that text; nothing it writes reads the
  frontend's source.

## Outputs
- C19, the array library surface: the files
  `libs/mlir-array/mlir-array.ipkg`, `Array/Core.idr`, `Array.idr`,
  `Linear/Vec.idr`; the qualified names and types of every export; the
  meaning of each recognized function; invariants I1-I6; the fork's
  `Libraries.Data.Table` API. Consumers: U14 (trust, recognition, type
  mapping to tensors), U15 (the tensor types it emits for `Array` and
  `LArray`), U18 (the ported and new tests and bench runs), U12 and U08
  (the invariant that no `LArray` exists unrestricted, on which 0003 D33
  rests).

## Implement
**`libs/mlir-linear/mlir-linear.ipkg`.** Modules `Linear.List`,
`Linear.Nat`, `Linear.Notation`, `Linear.String.Iterator`. Brief: "Linear
data and a linear string iterator for idris-mlir, in Idris over base's
primitives and a few of the compiler's own". Delete the array module's
file.

**`libs/mlir-array/mlir-array.ipkg`.** As C19 gives it, byte for byte.

**`Array/Core.idr`.** In this order, each with a doc comment that says
why it is as it is:
1. `Shape`, `count`, the namespaces `Extents`, `Index`, `Cell` with
   constructors `Lin` and `(:<)` (so `[<m, n]` is a value of each, by
   Idris's snoc-list syntax), `volume` and `volumeIsCount` (the runtime
   product of the extents, proved equal to `count s`), `Scalar`, `Vector`,
   `Matrix`, the fixity `export infixl 10 !!`.
2. The private `Cells`, `Array`, `LArray` and the private helpers every
   recognized body shares: `Indices s`, either the erased proof that
   `count s = 0` or the first index in row-major order with the list of
   the rest, made by `enumerate : (e : Extents s) -> Indices s` by
   recursion on the extents (the proof from the extents, never from a
   list's length); `offset : Extents s -> Index s -> Int` (row-major);
   `occupied : Index s -> (0 _ : count s = 0) -> Void`, which refutes
   `None` at an access; and the read and write of a backing at an offset
   in `PrimIO`. Every function that builds an array enumerates the
   result's extents: `None` from the proof, else `Slots` allocated with
   the first index's element as base's fill, then each later index
   written once.
3. The generating set and the linear half, each the Idris meaning C19
   states, in plain Idris over the helpers: `shape`, `tabulate`, `(!!)`,
   `foldLast`, `scanLast`, `nest`, `merge`, `reshape`, `take`, `drop`,
   `(++)`, `pad`, `update`, `withArray`, `read`, `write`, `freeze`,
   `thaw`, `lshape`, `grow`, `tabulateIO`. `tabulate` and `tabulateIO`
   apply their function once per index in row-major order and never when
   `count s = 0`; the first application's result is the fill base's
   `prim__newArray` needs.
Where an `Array (f ++ c)` or `Array (f :< n + m)` needs a lemma, prove it
in this module at quantity 0. Concatenation of shapes is Prelude's
`SnocList.(++)`; where the array `(++)` and it meet in one signature,
qualify `Prelude.(++)` for the shape.

**`Array.idr`.** `module Array`, `import public Array.Core`. `scalar`,
`fill`, `reduce`, `checkIndex`, `(!?)` with `export infixl 10 !?`, and the
instances `Functor (Array s)` (`map f x = tabulate (shape x) (\i => f (x
!! i))`), `Foldable (Array s)` (`foldl` by `foldLast` over the array
reshaped to `[<volume (shape x)]` from `scalar z`, read at `Lin`;
`foldMap f` the left fold with `<+>`; `toList` and `foldr` over the same
order; `null` by `volume`), `Zippable (Array s)` (`zipWith` by `tabulate`
over the first argument's shape; the other methods their defaults or by
`tabulate`). Nothing here opens a constructor.

**`Linear/Vec.idr`.** `module Linear.Vec`, importing `Array` (which
re-exports `Array.Core`), `Data.Nat`, `Data.So` and `Linear.Notation`;
Array.Core's `read`, `write` and `freeze` are written qualified
(`Core.read`) wherever Vec's own names would make a reference ambiguous. The exports are C19's. `push` at
`size < cap` writes slot `size`; at `size = cap` it grows by `extra cap =
S (minus (max 4 (2 * cap)) (S cap))` slots filled with the pushed value,
so slot `size` already holds it. `reserve v k x` grows to `max (size + k)
(max 4 (2 * cap))` when `k > cap - size`. Every `LTE` the record needs is
erased and built from `ltOpReflectsLT`, `lteAddRight`,
`plusSuccRightSucc` and transitivity; no `Dec` is computed at run time.
`freeze` gives `(size ** take size cells)` frozen.

**`compiler/idris/src/Libraries/Data/Table.idr`.** The module C19 gives:
`Table a = IORef (IOArray a)`; `newTable`, `lookupSlot`, `claimSlot`,
`setSlot`, each `HasIO io =>`. Its doc comment keeps today's statement of
the growth bound and says why the table holds no count. Imports
`Data.IOArray` and `Data.IORef` only.

**The bench programs.** One port each, keeping comments' substance
(rewritten where they name the old module):
- `fannkuch-linear`: the three arrays are `withArray [<n] 0` threaded at
  quantity 1 (`perm1`, `perm`, `count`), loops over `Nat` with
  `checkIndex n` at each access; `discard` is `freeze` and the dropped
  `MkBang`; the result leaves through the continuations' `!*`.
- `qsort`: an `LArray [<i] Bits32` per size `i` made by `withArray`,
  swaps by `read`/`write`, indices `Nat`.
- `unionfind`: an `LArray [<n] NodeData`; a node id is an `Int` field, so
  a lookup tests `n < 0` and then `checkIndex cap (cast n)`, which together
  are the program's own range test of today.
- `spectral-norm-linear`: `Vector n Double` values; `mulAv t n v =
  tabulate [<n] (\[<i] => sum (tabulate [<n] (\[<j] => aAt t i j * v !!
  [<j])))`, `sum` the `Foldable` left fold; the dot products are `sum
  (zipWith (*) u v)`; the starting vectors are `fill`.
- `k-nucleotide`: `codes <- tabulateIO [<n] (\[<i] => getBits8 seq (cast
  (finToNat i)))` once, after reading; the slot table is `withArray [<cap]
  (MkSlot 0 0)` threaded through `roll` and frozen for `found`; hashes and
  probes go through `checkIndex cap`.
Every port computes its sizes as `Nat` from the input `Int` with `cast`.

**Seams** (the handoff reports each; this lane writes none of them):
1. `compiler/idris/src/Core/Context/Context.idr`: delete lines 342-344
   (the `Arr` label: no user remains) and make line 401
   `content : Table ContextEntry`.
2. `compiler/idris/src/Core/Context.idr`: line 53 `aref <- coreLift
   (newTable s)`; line 99 `coreLift (claimSlot idx (content ctxt))`;
   line 109 `entryAt ctxt idx = coreLift (lookupSlot idx (content ctxt))`;
   line 115 `= coreLift (setSlot idx entry (content ctxt))`.
3. `compiler/idris/src/Core/Core.idr`: delete `threadRef` with its doc
   comment (1062-1077); the table was its only user.
4. `compiler/idris/idris-compiler.ipkg:6`: delete `depends = mlir-linear`
   (D38). `compiler/idris/README.md`: the paragraph that says the fork
   depends on `mlir-linear` for its tables, and `-p mlir-linear` in its
   program line, go.
5. `bench/{fannkuch-linear,spectral-norm-linear,qsort,k-nucleotide,unionfind}/packages`:
   `mlir-linear mlir-array` (Idris's `-p` adds no dependency of the
   package it names).
6. `Makefile:222`: `SHIPPED` lists `$(ROOT)/libs/mlir-linear
   $(ROOT)/libs/mlir-array` in that order (the wildcard sorts
   `mlir-array` first, whose install then fails on a fresh prefix); the
   fork's stamp no longer needs `$(HOST_LIBS_STAMP)` (`Makefile:186`) and
   the comments at 76, 178 and 231 name the new users; `tools/self.sh:44`
   drops `-p mlir-linear`. `AGENTS.md` and `README.md` name `mlir-array`
   beside `mlir-linear` where they list `libs/`.

## Delete
- `libs/mlir-linear/Linear/Array.idr` whole: the module `Linear.Array`,
  its `Array` with a runtime `Int` size beside a backing, its frozen
  `IArray` with `iread`, `isize`, `ifoldl`, `imap`, and its loops
  `generate`, `foldl`, `sum`, `map`, `zipWith` over it.
- Its two Scheme-spec primitives, `prim__arraySize` and `prim__index`, and
  the library loops `prim__generate` and `prim__foldl`.
- `mkArray` and every other way to get a linear array unrestricted.
- `Linear.Array` from `mlir-linear.ipkg`'s module list and the word
  "arrays" from its brief.
- In `Libraries/Data/Table.idr`: the import of `Linear.Array`, the table
  as a linear value threaded through a reference, and `reserve (mkArray 0
  Nothing) n Nothing`.
- In the five bench programs: every import of `Linear.Array`, every
  `mkArray`, `IArray`, `iread`, `ifoldl`, `generate` and the `Int`
  coordinates handed to the old untyped `read` and `write`.

## NOT TO DO
- Do not write any frontend file, registry entry or trust row (U14), any
  test or test `packages` file (U18), `bench/run.sh` or `bench/README.md`
  (U18), the `Makefile` or `tools/` (coordinator), or any unowned fork
  file or bench `packages` file: report them.
- Do not add a module, function or instance C19 does not list: no
  `Traversable`, `Show`, `Eq` or numeric hints, no `accumulate`, `iota`,
  `imap`, `ifoldl`, `transpose` or other §3.5 vocabulary (later stages
  bring each with the proof that uses it), no `Linear.Ref`, no
  `freezeBuffer`.
- Do not declare a `%foreign` or `%extern` in either package, and do not
  keep a Scheme spec "for the Chez column".
- Do not make `Linear.Vec`, the table or any port depend on a runtime
  `Dec` or `LTE` proof; proofs are erased.
- Do not put the fork's table on `LArray`, `Linear.Vec` or any linear
  value, and do not keep `threadRef`'s shape for it.
- Do not change a bench program's algorithm, sizes, input or printed
  text, and do not add a bench program.
- Do not edit `third_party/Idris2` or base.

## Tempting partial solutions
- Keeping `Linear.Array` as a deprecated module beside `mlir-array` so old
  programs still build. Rejected: Delete review finds the file; one array
  library, a hard cutover.
- A table that keeps its pure linear API (`newTable : Int -> Table a`) over
  an `IOArray` inside `unsafePerformIO`, so the fork's callers need no
  edit. Rejected: `newTable` would again give a mutable object
  unrestricted, the hole D38 closes; Acceptance requires every table
  operation in `HasIO`.
- `Cells` with an untyped empty case reached by `idris_crash
  "unreachable"`. Rejected: the representation must carry the emptiness
  proof (Fixed decisions); review finds no crash call in `Array.Core`.
- An `LArray` that stores its element count or capacity beside its
  extents, or a `Vec` that stores its capacity. Rejected: the extents are
  the one length (D37); review finds one length field per type.
- `checkIndex` through base's `natToFin`, or a port that indexes with
  `natToFin` or `integerToFin`. Rejected: a runtime `Dec` proof per access;
  review of the ports and of `Array.idr`.
- Porting a bench program to `Data.IOArray` or to `Linear.Vec` to avoid
  typed coordinates. Rejected: Acceptance requires `Array.Core`'s
  `LArray` with `Index` coordinates in the four linear programs.
- A `freezeBuffer` specific to `Data.Buffer` for k-nucleotide. Rejected:
  `tabulateIO` is the one world-ordered constructor C19 lists.
- Leaving the five bench `packages` files or the fork's callers for
  someone to notice. Rejected: Stop and return requires each seam in the
  handoff with its exact edit.

## Acceptance
- Source review: `libs/mlir-array` holds exactly `mlir-array.ipkg`,
  `Array.idr`, `Array/Core.idr`, `Linear/Vec.idr`; every export is C19's
  and C19's every name is exported, with its exact type; `Array.Core`
  alone names `MkArray`, `MkLArray`, `None`, `Slots`; neither package has
  a `%foreign`, and `mlir-linear`'s only `%extern`s are the iterator's
  three.
- Deletion review: no file under `libs/`, `bench/` or `compiler/idris/`
  imports the deleted module or names anything `## Delete` lists.
- `Libraries/Data/Table.idr` imports only `Data.IOArray` and `Data.IORef`;
  `newTable`, `lookupSlot`, `claimSlot`, `setSlot` have C19's types.
- Typechecks, each clean (`IDRIS2` is `.toolchain/idris2/bin/idris2`,
  `PRELUDE` the pinned prefix `.toolchain/idris2`, `HOST` the libdir of
  `build/idris2-host`):
  - `cd libs/mlir-linear && IDRIS2_PREFIX=$PRELUDE $IDRIS2 --build-dir
    /tmp/U13-build/linear --typecheck mlir-linear.ipkg`;
  - `cd libs/mlir-array && IDRIS2_PREFIX=$PRELUDE IDRIS2_PACKAGE_PATH=$HOST
    $IDRIS2 --build-dir /tmp/U13-build/array --typecheck mlir-array.ipkg`
    (against the installed `mlir-linear`, whose `Linear.Notation` this
    lane leaves unchanged);
  - each bench program: `cd bench/<name> && IDRIS2_PREFIX=$PRELUDE
    IDRIS2_PACKAGE_PATH=$HOST:/tmp/U13-prefix $IDRIS2 --build-dir
    /tmp/U13-build/<name> -p mlir-linear -p mlir-array --check Main.idr`,
    with `mlir-array` installed by the same `$IDRIS2 --install` into the
    private prefix `/tmp/U13-prefix` (never into a shared prefix);
  - the table alone: `cd compiler/idris && IDRIS2_PREFIX=$PRELUDE $IDRIS2
    --source-dir src --build-dir /tmp/U13-build/fork --check
    src/Libraries/Data/Table.idr`.
  The whole fork does not typecheck until seams 1-3 land; that failure is
  expected and reported, never worked around.
- Each port's printed output for its committed input cannot be run here:
  the handoff lists the five programs for the owner's machine (`bench/run.sh`
  prints each against its reference program's output).

## Stop and return
Return when items 1-6 of the permitted outcome hold and every typecheck
above has been run: the handoff of the common obligations, with the six
seams of Implement, each with its exact edit and why no lane can make it
today, and the C20 needs (the `mlir-array` trust row; recognition of
every C19 name; zero-cost `natToFinLT` and `finToNat`). If a C19 type
cannot be written in the pinned Idris as given, report the elaboration
error and the nearest type that checks, and keep porting everything else.
