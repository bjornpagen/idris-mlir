<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane: the Benchmarks Game's meteor-contest

## What was added

`bench/meteor-contest/`, in the flat layout:

- `Main.idr`: this compiler's program. It uses the stock Prelude and base
  (`Data.Bits`, `Data.List`) and no packages.
- `main.c`: the C reference. It runs the same algorithm in the same order
  of work.
- `input`: `2098`. This is the game's measured argument, the number of
  solutions to find, and that number is all of them.

Nothing else was created or deleted. No test, helper or other lane's file
was touched.

## The program

This is the game's specification, implemented in full:

- The board has 50 cells in 10 rows of 5, with odd rows set half a cell to
  the right.
- There are ten pieces of five cells each.
- The program finds every way to fill the board, counted up to the limit
  read from stdin.
- It prints `N solutions found`, a blank line, and then the smallest and
  the largest solution. "Smallest" and "largest" read each solution as 50
  digits in cell order (the piece at each cell). Each board is printed in
  the game's pretty format: each digit followed by a space, odd rows
  indented by one space, and a blank line after the board.

The pieces come from the game's C entry, as paths in its twelve directions:

```
{E,E,E,SE} {SE,E,NE,E} {E,E,SE,SW} {E,E,SW,SE} {SE,E,NE,S}
{E,E,SW,E} {E,SE,SE,NE} {E,SE,SE,W} {E,SE,E,E} {E,E,E,SW}
```

Here E=0, ESE=1 and so on clockwise up to ENE=11. A rotation adds 2 to a
direction, and a flip maps d to (12 - d) mod 12. The directions are
applied as axial-coordinate steps, so a step off the board is seen
directly rather than through offset tables.

The algorithm, the same in both languages:

1. Place every piece under all 12 orientations from every start cell. Each
   placement is a 50-bit mask, filed under its lowest cell. This gives
   2596 placements.
2. Search depth-first. Find the lowest empty cell by stepping on from the
   last one filled.
3. At that cell, try each placement in that cell's list (ordered by piece,
   then by the order the placements were made) whose piece is unused and
   whose mask fits.
4. Stop once the count reaches the limit.

No piece has a symmetry: a C check found no repeated mask among a piece's
placements. So each solution is found exactly once, and the count is the
game's 2098, which includes both 180-degree twins.

### Verification

- **Against the game's published output.** At 2098, the C output and the
  Idris output are both byte-identical to the game's reference output
  (`meteor-output.txt`). That file gives `2098 solutions found`, the
  smallest board starting `0 0 0 0 1 / 2 2 2 0 1`, and the largest
  starting `9 9 9 9 8 / 9 6 6 8 5`. The smallest is the 50-digit string
  `00001222012661126155865558633348893448934747977799` that the game's
  description prints.
- **At other limits.** The Idris and C outputs are byte-identical at
  limits 0, 1, 2, 7, 100, 1000, 2098 and 5000. At limit 0 both print only
  the header line and a blank line.
- **Through the benchmark runner.** `bench/run.sh --runs 1 meteor-contest`
  printed "Outputs agree":

  | | seconds |
  | --- | ---: |
  | this compiler | 0.806 |
  | Idris on Chez | 2.147 |
  | clang -O2 | 0.529 |
  | compile time | 4.4 |

  Clang over this compiler comes out at 0.66x. The machine was loaded by
  other lanes. Unloaded, separate timings ranged from 3x to 4x of C
  (0.9 to 1.2 s against 0.28 to 0.37 s), so these numbers are only
  indicative.
- **The compiled build.** It was compiled with `tools/compile.sh
  --num-threads=2` on a scratch copy, so no `build/` directory was left in
  the benchmark directory.

### For the orchestrator (outside this lane's scope)

`bench/README.md` still says "`meteor-contest` is not here either..." and
that the piece shapes are unknown. That paragraph is now false and should
go. The Benchmarks Game table needs a row like this:

> meteor-contest | 2098 | the retired program; no C entry followed: ours
> is a first-empty-cell search over each cell's placements, without the
> game's C entry's island pruning

## Compiler bugs found

These came up while writing the program. Each one was worked around inside
the language, and the program in the tree compiles and runs correctly. All
were reproduced with the build in `build/dev`. Each reproducer reads its
argument from stdin. Compiler code was not touched.

### 1. idr-rc-exclusive: solver and commit disagree on a returned record

A record with a refcounted field (`String` or `List`) is threaded through a
recursive search and returned from a branch. The commit then fails:

```
'idr.yield' op idr-rc-exclusive: gives a value of '!idr.own<!idr.data<"Main.Found", plain [@MkFound(i64, !idr.str)] ...>>' where the solver proved '!idr.excl<...>'
```

`foreign/idr/lib/Transforms/Ownership/Commit.cpp:47` calls this "a bug
here, never a program to compile".

Reproducer:

```idris
module Main
import Prelude

data Found = MkFound Int String

countOf : Found -> Int
countOf (MkFound n _) = n

note : Found -> Found
note (MkFound n s) = MkFound (n + 1) s

mutual
  solve : Int -> Int -> List Int -> Found -> Found
  solve limit depth here found =
    if depth == 0 then note found
    else try limit depth here here found

  try : Int -> Int -> List Int -> List Int -> Found -> Found
  try limit depth here [] found = found
  try limit depth here (x :: more) found =
    if countOf found >= limit then found
    else
      let found' = if x > 0 then solve limit (depth - 1) here found else found in
      try limit depth here more found'

main : IO ()
main = do
  limit <- map cast getLine
  let MkFound n s = solve limit 3 [1, 2, 0] (MkFound 0 "")
  printLn n
  putStrLn s
```

What decides whether it compiles:

- It compiles if the field is an `Int`, or if `limit` is a literal.
- In the full program the same failure appears with one self-recursive
  function and a literal limit, as soon as a freshly built `String` or
  `List Int` is stored into the record.
- A two-constructor `Found` (`None | Some ...`) that the compiler keeps
  `plain` still fails.

**Workaround in the program:** a solution is kept as `Key`, five `Int`s
holding ten digits each (two rows of the board), so the search state holds
no heap value.

### 2. `idr.cell.init` builds an exclusive value of a shared field

```
'idr.cell.init' op builds an exclusive value of a field that may be shared
```

Reproducer:

```idris
data Place = MkPlace Int Int
same : Place -> Place -> Bool
same (MkPlace p m) (MkPlace p' m') = p == p' && m == m'
keep : Int -> List Place -> (Int, Place) -> List Place
keep cell acc (lo, pl) = if lo == cell && not (any (same pl) acc) then acc ++ [pl] else acc
main = do
  n <- map cast getLine
  printLn (length (foldl (keep 0) [] [(0, MkPlace n 1), (0, MkPlace 2 n), (1, MkPlace n 1)]))
```

A pair's field is used both in a closure (`same pl`) and in a new cell
(`[pl]`). It compiles once the `any` check or the pair is removed.

In the full program the same pattern gave bug 1's message instead, with no
location. **Workaround:** the program has no de-duplication at all. It is
not needed, because no piece has a symmetry.

### 3. `||` / `&&` chain over a plain record's fields: llvm.call type mismatch

```
'llvm.call' op operand type mismatch: expected operand type 'i64', but provided '!llvm.ptr' for operand number 0
```

Reproducer:

```idris
data Key = MkKey Int Int Int Int Int
before : Key -> Key -> Bool
before (MkKey a0 a1 a2 a3 a4) (MkKey b0 b1 b2 b3 b4) =
  a0 < b0 || a0 == b0 && (a1 < b1 || a1 == b1 && (a2 < b2 || a2 == b2 && (a3 < b3 || a3 == b3 && a4 < b4)))
data Found = None | Some Int Key Key
note : Int -> Found -> Found
note x None = let k = MkKey x 0 0 0 0 in Some 1 k k
note x (Some n best worst) =
  let k = MkKey x 0 0 0 0 in
  Some (n + 1) (if before k best then k else best) (if before worst k then k else worst)
loop : Int -> Found -> Found
loop x found = if x <= 0 then found else loop (x - 1) (note (x `mod` 7) found)
main = do
  n <- map cast getLine
  case loop n None of
    None => putStrLn "none"
    Some c (MkKey a _ _ _ _) (MkKey b _ _ _ _) => printLn [c, a, b]
```

With two fields and no `Found` it compiles. **Workaround in the program:**
`before` is written as nested `if`s on the first word that differs.

### 4. A recursive IO loop over an IORef crashes at run time (miscompile)

The program prints the right answer and then dies with SIGSEGV or SIGBUS.
lldb shows a jump to a stack address on the program's thread
(`EXC_BAD_ACCESS`, pc at `0x16fdfd8c0`, `udf`).

Reproducer:

```idris
import Data.IORef
walk : Int -> IORef Int -> List Int -> IO ()
walk limit count [] = pure ()
walk limit count (x :: more) = do
  n <- readIORef count
  if n >= limit then pure ()
    else do
      if x > 0 then modifyIORef count (+ 1) else pure ()
      walk limit count more
main = do
  limit <- map cast getLine
  c <- newIORef 0
  walk limit c [1, 2, 0]
  readIORef c >>= printLn
```

It exits with 139 for both `0` and `5` on stdin, and still crashes with a
literal limit or with `modifyIORef count (+ x)` in place of the `if`. A
single `newIORef`, `modifyIORef` and `readIORef` in `main` runs fine.

This is a silent miscompile (wrong code, no refusal), so it is the most
serious of the four. The program does not use IORef.

## For a future generator or harness

Nothing was deleted, so there is no coverage lost. The four reproducers
above are what a test of the compiler should pin down once each bug is
fixed:

- bug 1: the exclusivity commit holds for a record returned from
  recursive branches;
- bug 2: a cell is built from a shared field;
- bug 3: lazy boolean chains over a plain record's fields;
- bug 4: an IO loop over an IORef runs and exits 0.

They are not committed as tests here, because this lane's scope is
`bench/meteor-contest/` only.
