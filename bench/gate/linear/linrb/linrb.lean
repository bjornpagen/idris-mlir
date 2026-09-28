/-
The linear red-black tree of Main.idr here (experiment 4), in Lean: the
same program, with Lean's reset/reuse testing at runtime whether a matched
cell is unique. linrb_shared.lean differs at one call site. balance1 and
balance2 are @[inline], as in Lean's rbmap.lean.
-/

inductive Color
  | red | black

inductive Tree where
  | leaf
  | node : Color → Tree → Nat → Bool → Tree → Tree

instance : Inhabited Tree := ⟨.leaf⟩

@[inline]
def balance1 : Nat → Bool → Tree → Tree → Tree
  | kv, vv, t, .node _ (.node .red l kx vx r₁) ky vy r₂ => .node .red (.node .black l kx vx r₁) ky vy (.node .black r₂ kv vv t)
  | kv, vv, t, .node _ l₁ ky vy (.node .red l₂ kx vx r) => .node .red (.node .black l₁ ky vy l₂) kx vx (.node .black r kv vv t)
  | kv, vv, t, .node _ l ky vy r                       => .node .black (.node .red l ky vy r) kv vv t
  | kv, vv, t, .leaf                                   => .node .black .leaf kv vv t

@[inline]
def balance2 : Tree → Nat → Bool → Tree → Tree
  | t, kv, vv, .node _ (.node .red l kx₁ vx₁ r₁) ky vy r₂  => .node .red (.node .black t kv vv l) kx₁ vx₁ (.node .black r₁ ky vy r₂)
  | t, kv, vv, .node _ l₁ ky vy (.node .red l₂ kx₂ vx₂ r₂) => .node .red (.node .black t kv vv l₁) ky vy (.node .black l₂ kx₂ vx₂ r₂)
  | t, kv, vv, .node _ l ky vy r                           => .node .black t kv vv (.node .red l ky vy r)
  | t, kv, vv, .leaf                                       => .node .black t kv vv .leaf

-- The isRed tests of Lean's ins are matches on the child, which rebuild
-- the node they matched: free for a unique cell.
partial def ins (kx : Nat) (vx : Bool) : Tree → Tree
  | .leaf => .node .red .leaf kx vx .leaf
  | .node .red a ky vy b =>
    if kx < ky then .node .red (ins kx vx a) ky vy b
    else if kx = ky then .node .red a kx vx b
    else .node .red a ky vy (ins kx vx b)
  | .node .black a ky vy b =>
    if kx < ky then
      match a with
      | .node .red l k v r => balance1 ky vy b (ins kx vx (.node .red l k v r))
      | a                  => .node .black (ins kx vx a) ky vy b
    else if kx = ky then .node .black a kx vx b
    else
      match b with
      | .node .red l k v r => balance2 a ky vy (ins kx vx (.node .red l k v r))
      | b                  => .node .black a ky vy (ins kx vx b)

def setBlack : Tree → Tree
  | .node _ l k v r => .node .black l k v r
  | .leaf           => .leaf

def insert (k : Nat) (v : Bool) (t : Tree) : Tree :=
  setBlack (ins k v t)

-- Counts the True values, consuming the tree.
def count : Tree → Nat → Nat
  | .leaf,           acc => acc
  | .node _ l _ v r, acc => let c := count l acc; count r (if v then c + 1 else c)

def mkMap : Nat → Tree → Tree
  | 0,   t => t
  | n+1, t => mkMap n (insert n (n % 10 = 0) t)

def readNat : IO Nat := do
  let line ← (← IO.getStdin).getLine
  pure <| (line.toList.takeWhile Char.isDigit).foldl (fun acc c => acc * 10 + (c.toNat - '0'.toNat)) 0

def main : IO Unit := do
  let n ← readNat
  IO.println (toString (count (mkMap n .leaf) 0))
