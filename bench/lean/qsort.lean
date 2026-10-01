/-
Quicksort of arrays of 32-bit words: Lean's qsort.lean (tests/compile_bench
in the Lean 4 repository; Counting Immutable Beans), reading n from stdin,
with the check returning a Bool and the checksum of the middle elements that
every version here prints.
-/
abbrev Elem := UInt32

def badRand (seed : Elem) : Elem :=
seed * 1664525 + 1013904223

def mkRandomArray : Nat → Elem → Array Elem → Array Elem
| 0,   _,    as => as
| i+1, seed, as => mkRandomArray i (badRand seed) (as.push seed)

partial def checkSorted (a : Array Elem) (i : Nat) : Bool :=
  if i < a.size - 1 then
    if a[i]! <= a[i+1]! then checkSorted a (i+1) else false
  else
    true

-- copied from stdlib, but with `UInt32` indices instead of `Nat` (which is more comparable to the other versions)
abbrev Idx := UInt32

macro:max "↑" x:term:max : term => `(UInt32.toNat $x)

@[specialize] private partial def partitionAux {α : Type} [Inhabited α] (lt : α → α → Bool) (hi : Idx) (pivot : α) : Array α → Idx → Idx → Idx × Array α
| as, i, j =>
  if j < hi then
    if lt (as[j.toNat]!) pivot then
      let as := as.swapIfInBounds ↑i ↑j;
      partitionAux lt hi pivot as (i+1) (j+1)
    else
      partitionAux lt hi pivot as i (j+1)
  else
    let as := as.swapIfInBounds ↑i ↑hi;
    (i, as)

@[inline] def partition {α : Type} [Inhabited α] (as : Array α) (lt : α → α → Bool) (lo hi : Idx) : Idx × Array α :=
let mid : Idx := (lo + hi) / 2;
let as  := if lt (as[mid.toNat]!) (as[lo.toNat]!) then as.swapIfInBounds ↑lo ↑mid else as;
let as  := if lt (as[hi.toNat]!)  (as[lo.toNat]!) then as.swapIfInBounds ↑lo ↑hi  else as;
let as  := if lt (as[mid.toNat]!) (as[hi.toNat]!) then as.swapIfInBounds ↑mid ↑hi else as;
let pivot := as[hi.toNat]!;
partitionAux lt hi pivot as lo lo

@[specialize] partial def qsortAux {α : Type} [Inhabited α] (lt : α → α → Bool) : Array α → Idx → Idx → Array α
| as, low, high =>
  if low < high then
    let p   := partition as lt low high;
    -- TODO: fix `partial` support in the equation compiler, it breaks if we use `let (mid, as) := partition as lt low high`
    let mid := p.1;
    let as  := p.2;
    let as  := qsortAux lt as low mid;
    qsortAux lt as (mid+1) high
  else as

@[inline] def qsort {α : Type} [Inhabited α] (as : Array α) (lt : α → α → Bool) : Array α :=
qsortAux lt as 0 (UInt32.ofNat (as.size - 1))

-- Sorts arrays of every size i < n; returns the sum of their middle
-- elements, or none if one is not sorted.
partial def sizes (n i acc : Nat) : Option Nat :=
  if i >= n then some acc
  else
    let xs := mkRandomArray i (UInt32.ofNat i) Array.empty
    let xs := qsort xs (fun a b => a < b)
    if !checkSorted xs 0 then none
    else sizes n (i+1) (acc + (if i > 0 then xs[i/2]!.toNat else 0))

partial def reps (n k acc : Nat) : Option Nat :=
  if k >= n then some acc
  else match sizes n 0 0 with
    | some s => reps n (k+1) (acc + s)
    | none => none

def readNat : IO Nat := do
  let line ← (← IO.getStdin).getLine
  pure <| (line.toList.takeWhile Char.isDigit).foldl (fun acc c => acc * 10 + (c.toNat - '0'.toNat)) 0

def main : IO Unit := do
  let n ← readNat
  match reps n 0 0 with
  | some s => IO.println (toString s)
  | none => IO.println "array is not sorted"
