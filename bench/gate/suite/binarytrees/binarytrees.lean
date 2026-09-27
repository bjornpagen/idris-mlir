/-
Binary trees on one core: Lean's binarytrees.st.lean (tests/compile_bench
in the Lean 4 repository; Counting Immutable Beans), reading n from stdin,
with the depth loop written out (no Std import) and the loop counter passed
as make's seed, as every version here does.
-/

inductive Tree
  | nil
  | node (l r : Tree)
instance : Inhabited Tree := ⟨.nil⟩

-- This function has an extra argument to suppress the
-- common sub-expression elimination optimization
partial def make' (n d : UInt32) : Tree :=
  if d = 0 then .node .nil .nil
  else .node (make' n (d - 1)) (make' (n + 1) (d - 1))

-- build a tree
def make (d : UInt32) := make' d d

def check : Tree → UInt32
  | .nil => 0
  | .node l r => 1 + check l + check r

def minN := 4

def out (s : String) (n : Nat) (t : UInt32) : IO Unit :=
  IO.println s!"{s} of depth {n}\t check: {t}"

-- allocate and check lots of trees
partial def sumT (d i t : UInt32) : UInt32 :=
  if i = 0 then t
  else
    let a := check (make' i d)
    sumT d (i-1) (t + a)

partial def depths (maxN d : Nat) : IO Unit := do
  if d ≤ maxN then
    let n := 2 ^ (maxN - d + minN)
    out s!"{n}\t trees" d (sumT (.ofNat d) (.ofNat n) 0)
    depths maxN (d + 2)

def readNat : IO Nat := do
  let line ← (← IO.getStdin).getLine
  pure <| (line.toList.takeWhile Char.isDigit).foldl (fun acc c => acc * 10 + (c.toNat - '0'.toNat)) 0

def main : IO Unit := do
  let n ← readNat
  let maxN := Nat.max (minN + 2) n
  let stretchN := maxN + 1

  -- stretch memory tree
  let c := check (make $ UInt32.ofNat stretchN)
  out "stretch tree" stretchN c

  -- allocate a long lived tree
  let long := make $ UInt32.ofNat maxN

  -- allocate, walk, and deallocate many bottom-up binary trees
  depths maxN minN

  -- confirm the long-lived binary tree still exists
  out "long lived tree" maxN (check long)
