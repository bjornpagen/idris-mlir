<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Strengthening the suite: the rejects lane

Scope: every test of kind reject, and the program tests named `bounded-*`
(the growth check's accepted side). No compiler, harness or other lane's
file was edited, with one exception the change forces:
`tests/rules-covered/without-fixture` loses its `static argument` line,
because that rule now has a fixture and rules-covered refuses a rule with
both.

## What every refusal checks now

- **The discriminating pair.** Every one of the 45 reject tests holds
  `near/`, its nearest accepted neighbour in the vocabulary lane's form:
  the refused program with the one refused construct changed, compiled,
  held to its `cases/`, and checked as every compilation is. Each
  transcript gains the four `near:` lines. So each rule is pinned from both
  sides. A refusal that grows to cover the neighbour fails the test, and so
  does a neighbour that the rule silently lets through, while the refused
  program stays refused.
- **Rule and line, never wording.** Every `-- message:` header now names a
  thing the refusal must name, and holds no prose. Prose messages were
  replaced by the name of the value or site: "an IORef of" became
  `Main.Node`, "where Lib.Meters is opaque to the program" became
  `Lib.Meters`, "holds two implementations" became `Main.backward`, "which
  rebuilds it in place" became `Main.bump`, "an implementation chosen at
  runtime" became `Main.choose` or `Main.MkSize`, and "growing it by 1 each
  round, and nothing bounds how far it grows" became the growing term
  (`(Prelude.Types.S n)`, `(Builtin.Pair a a)`, `(Main.quoted a sh)`,
  `Prelude.Basics.(:<)`). Two `runtime-closure` messages were dropped
  because the value has no stable name: Idris prints it as a case block,
  or as an implementation with its source span. Names were added where a
  refusal had no check of what it names: `Builtin.assert_linear`,
  `Builtin.assert_total`, `prim__believe_me`, `prim__crash`, `?which`,
  `?proof`, `%inline`, `%transform`, `%foreign`, `%extern`,
  `Language.JSON`, `PrimIO.unsafePerformIO`, `Main.Box`, `Main.MkBox`,
  `Main.Node`, `zip'`.
- **The file of the line.** The header can state a line but not the file
  it is in. The two fixtures whose refusal is in `Data/Evil.idr` now pin
  the file through the message (`Data/Evil.idr:7:`, `Data/Evil.idr:6:`).
  A refusal moved to the same line of `Main.idr` now fails.
- **Runtime choices where the rule is about them.** Where the refusal
  separates a choice the whole program fixes from one the run makes, the
  pair now reads its input, so the accepted side is tested on a choice
  only the run knows: runtime-closure-implementation (0, 1, -1),
  runtime-closure-index-function (0, 1, 3), the constructor-field pair
  (scope: b, empty line, two words; shape: 0, 4, 1000000), the
  polymorphism pairs (counts 0, 1, large: growing-rank to 61 rounds, which
  makes 2^62; growing-shape and growth-mutual to 1000000 rounds;
  growth-dictionary to 1000; nested-data to depth 1000), and
  uniqueness-shared-rebuild ('0', '1', '3', '9').
- **Edges where the neighbour has them.** deprecated-get-byte's neighbour
  writes the input as a Bits8 and reads it back with getBits8: 0, 1, 127,
  128, 255, 256 (0), 257 (1), -1 (255), -128 (128). getBits8 is the
  replacement the refusal names. dictionary-field-opaque-type's neighbour
  checks both orders and that equal keys merge (5, 1, 0, -3).
  escape-hatch-hole-at-runtime's neighbour takes both branches (1, 5, 0,
  -1). escape-hatch-assert-total-in-user-data-module covers 0, 1, 3, -5
  and 1000.

## New tests

| test | rule, line | what it states |
| --- | --- | --- |
| `pragma-foreign` | pragma, 12, names `%foreign` | a user `%foreign "C:puts,libc"` declaration is refused where it is written, though unreached, and never ignored (AGENTS, GAPS-1); near/ defines `puts` in Idris |
| `pragma-extern` | pragma, 11, names `%extern` | the same for a user `%extern` |
| `static-argument-stuck-implementation` | static argument, 13, names `Main.chosen` | an implementation chosen by a `covering` function, which Idris does not prove ends, is refused at the method that needs it; near/ chooses by a total function and prints `A!`. This was `owed` in without-fixture (0002 §9's program, with a user method, so the site is in user code) |
| `bounded-family-match` | accepted | a matching type family, recursive (G) or not (H), passed as a family parameter and applied at one closed type: one instance of T, so it must compile and print 4 and 5. It fails on bug B1 below |

GAPS-1 assumed a reached `%foreign` is refused by `escape hatch`, and an
unreached one is accepted. Neither holds: `%foreign` and `%extern` in user
code are refused by `pragma` wherever they are written. A reached one gets
two refusals, `pragma` and `escape hatch`. The reject kind states one
rule, so the two pragma fixtures are unreached. This is the stronger
"never ignored" case.

## Deleted or moved

- **polymorphism-growth-family-recursion: deleted.** It refused a program
  with one instance: W is called once, at a closed type, and G is total. It
  pinned the growth check's incompleteness, which is the reason the
  cleanup lane deleted polymorphism-growth-family-sum. Its nearest
  neighbour (G without its recursion) is refused too, which is bug B1. The
  program now lives on as the accepted `bounded-family-match`, which fails
  on B1 until B1 is fixed.
- **bounded-grow-shrink: moved into polymorphism-growth-mutual's pair.**
  The refused program now carries the accumulator. Its neighbour is
  grow-shrink (grow by one constructor, shrink by one), and the input is
  the count: 5 + 11k for k = 0, 1, 3, 1000000. That gives one fact one
  place, and it gains runtime counts.

## The bounded-* programs

| test | now checks |
| --- | --- |
| bounded-capped | the count is the input (0, 1, 3, 100000): three instances whatever the count, values r + 2k |
| bounded-dictionary-root | the depth is the input (0, 1, 2, 5), for both roots |
| bounded-grow-once | the entry is the input (0..4, -1); a `Con` with no pair added, so every alternative of describe runs |
| bounded-method | adds a term nested as deep as the input (0..3) through the same implementations. It fails on bug B4 |
| bounded-method-own | the list is the input (three, one, empty) |
| bounded-field | adds a tree as deep as the input (0, 1, 2). It fails on 5.12 |
| bounded-family-applied, -head, -higher, -partial, -scope, bounded-synonym | unchanged. Their contract is that a static bound covers a type-level argument, and no input reaches it. A family's refused side is `bounded-family-match`'s bug, and the growth generator of SUMMARY §4.4 replaces them. bounded-synonym still fails on 5.12 |

## Runs (arm64 macOS, build/dev as found)

- Baseline (reject and bounded-* only): 52/56. The 4 failures were
  bounded-field and bounded-method-own (5.38), bounded-synonym (5.12) and
  cycle-ioref-knot (5.29).
- After: 47/58 (45 rejects and 13 bounded). Every failure is a compiler
  bug:

| test | fails on | evidence |
| --- | --- | --- |
| cycle-ioref-knot | 5.29, and near: 5.10 | line 16 reported, header 18; near: `live cells 1` (IORef program) |
| cycle-array-knot | near: 5.10 | `live cells 1` (IOArray program) |
| deprecated-get-byte | near: 5.10 (Buffer) | `live cells 1` on every case; buffer-bytes fails the same way |
| dictionary-field-opaque-type | near: **B2** | `live cells 3` / `4` |
| escape-hatch-hole-at-runtime | near: **B3** | `live cells 1` on the Left cases (0, -1) |
| polymorphism-growing-rank | near: **B5** | compile exit 134, an assertion |
| bounded-family-match | **B1** | `unsupported (polymorphism)` at T |
| bounded-method | **B4** | `live cells 1` on every case |
| bounded-field, bounded-synonym | 5.12 | `'llvm.call' op operand type mismatch` |
| bounded-method-own | 5.38 | `File name too long` from the harness's tree printer |

- `make check`: rules-covered passes, with the new fixtures found and the
  owed line gone. The 6 failures (dialect-text, driver-shape,
  emit-dialects, facts-in-types, zones, file-size) are other lanes'
  planted witnesses in progress, and file-size.

## Compiler bugs found

- **B1. A matching type family passed as a family parameter is refused as
  unbounded polymorphism**, even when it is not recursive and is applied
  once at a closed type. Reproducer:

  ```idris
  G : Type -> Type
  G (List a) = a
  G a = a
  T : (0 t : Type) -> Nat -> Nat
  T t n = n + 1
  W : (0 m : Type -> Type) -> Nat -> Nat
  W m n = T (m (List Int)) n
  main : IO ()
  main = printLn (W (\y => G y) 3)
  ```

  - Expected: compiles and prints 4. `T (G (List Int)) 3`, written
    directly, compiles.
  - Got: `unsupported (polymorphism): Main.T: Main.W passes m through its
    type family m to Main.T, and nothing bounds what it computes`.
  - This goes against AGENTS (a set the whole program fixes compiles). The
    bounded-family-* tests pass only for families that do not match on
    their argument.
- **B2. Two SortedMaps of different key types in one program leak 3 or 4
  cells.** Reproducer: a `data K = MkK Int` with `Eq` and `Ord`, `n` from
  `getLine`, `fromList [(MkK n, "n"), (MkK 1, "1")]` and
  `fromList [(n, "n"), (1, "1")]` at `SortedMap Int`, both keys printed.
  - Expected: `live cells 0`.
  - Got: `live cells 3` (input 5).
  - Each map alone, with the same runtime keys, gives 0.
- **B3. `traverse` in Either over a list leaks a cell when it returns
  Left.** Reproducer:
  `printLn (the (Either Int (List Int)) (traverse (\x => if x > 0 then Right x else Left x) [cast line]))`.
  - Expected: `Left 0`, `live cells 0`.
  - Got: `Left 0`, then `live cells 1`; input 1 gives
    `Right [1]`, `live cells 0`.
- **B4. bounded-method leaks a cell** when one program writes a constant
  term and a runtime-built one (`nest k`) through the same `Out`
  implementations.
  - Expected: `live cells 0`.
  - Got: `live cells 1` for every k.
  - Either line alone gives 0.
- **B5. idris-mlir aborts on a shape-polymorphic recursion over
  mlir-array arrays.** Reproducer (packages mlir-linear mlir-array):

  ```idris
  double : Array s Int -> Nat -> Array s Int
  double x Z = x
  double x (S k) = double (tabulate (shape x) (\i => (x !! i) * 2)) k
  main = do line <- getLine
            printLn (sum (double (tabulate [<2] (\_ => 1)) (integerToNat (cast line))))
  ```

  - Expected: compiles; prints 2^(k+1).
  - Got: exit 134, `Assertion failed: (isa<To>(Val) && "cast<Ty>() argument
    of incompatible type!")` in
    `ViewLikeOpInterface::getViewSource` on a `memref.cast`, from
    `idr::ownership::readFrom` / `isStatic` / `Inference::visitCall`.
  - The same expression without the recursion hits 5.8 (`consumes a view,
    which holds no reference`).

Observed, not new: words in a `for` lambda reached 5.9 (idr-rc-exclusive's
`!idr.own` yield). The hole neighbour now builds its list without
`words`, because `words` is not what the pair is about.

## Cases a rule promises that the reject kind cannot state

- **idr-knots' third placement ("or else at the program").** It is
  reachable when the program's own code makes no array and builds no
  value of a type on the cycle. Example: `data Node = MkNode (IORef (Maybe
  Node))`, `r <- newIORef (the (Maybe Node) (head' []))`, read back. The
  refusal is `cycle` with location `-` (no file, no line), and the header
  has no form for "no line". The same is true of a `static argument`
  reached through a library projection (`show @{chosen}`: location `-`).
  The harness needs a header for a refusal at no source line, or the
  compiler needs the program's location there. That decision is the
  harness owner's.
- **`match`** stays `owed`. Every program that matches an erased argument
  between alternatives tried here is refused by Idris first ("Can't match
  on ... (Erased argument)"), so `elaboration` refuses it.

## For the orchestrator

- Three accepted programs of other lanes are now near-duplicates of a
  pair's `near/`: main-private-in-import (program-main-ambiguous's near/),
  and partly implementation-runtime-scope, implementation-shape-value and
  sortedmap-opaque-key. One fact, one place: their owners may fold them.
- `tests/rules-covered/without-fixture`: the `static argument` line was
  removed, and nothing else was changed.
- `proposals/0003-self-host/checker/` mentions the deleted
  bounded-grow-shrink, in historical dispatch records only.
