module Main

-- ../linrb with one call site changed: the build loop keeps the tree it
-- passes to insert for one more step (docs/plan.md 4.4, experiment 4).
-- Idris accepts this, since a shared value may be passed to a quantity-1
-- parameter; MEM-LIN-1 must reject it at that call ("the value is used
-- again after the call"). Koka and Lean compile the same change silently,
-- and every insert copies the path it would have updated in place.
import Prelude

data Color = Red | Black

data Tree : Type where
  Leaf : Tree
  Node : Color -> (1 l : Tree) -> Int -> Bool -> (1 r : Tree) -> Tree

-- balance1 kv vv t n: the black node with key kv, after an insert into its
-- red left subtree gave n.
balance1 : Int -> Bool -> (1 t : Tree) -> (1 n : Tree) -> Tree
balance1 kv vv t (Node _ (Node Red l kx vx r1) ky vy r2) =
  Node Red (Node Black l kx vx r1) ky vy (Node Black r2 kv vv t)
balance1 kv vv t (Node _ l1 ky vy (Node Red l2 kx vx r)) =
  Node Red (Node Black l1 ky vy l2) kx vx (Node Black r kv vv t)
balance1 kv vv t (Node _ l ky vy r) =
  Node Black (Node Red l ky vy r) kv vv t
balance1 kv vv t Leaf = Node Black Leaf kv vv t

-- balance2 t kv vv n: the same, for the right subtree.
balance2 : (1 t : Tree) -> Int -> Bool -> (1 n : Tree) -> Tree
balance2 t kv vv (Node _ (Node Red l kx1 vx1 r1) ky vy r2) =
  Node Red (Node Black t kv vv l) kx1 vx1 (Node Black r1 ky vy r2)
balance2 t kv vv (Node _ l1 ky vy (Node Red l2 kx2 vx2 r2)) =
  Node Red (Node Black t kv vv l1) ky vy (Node Black l2 kx2 vx2 r2)
balance2 t kv vv (Node _ l ky vy r) =
  Node Black t kv vv (Node Red l ky vy r)
balance2 t kv vv Leaf = Node Black t kv vv Leaf

-- The isRed tests of Lean's ins are matches on the child, which rebuild
-- the node they matched: free for a unique cell.
ins : Int -> Bool -> (1 t : Tree) -> Tree
ins kx vx Leaf = Node Red Leaf kx vx Leaf
ins kx vx (Node Red a ky vy b) =
  if kx < ky then Node Red (ins kx vx a) ky vy b
  else if kx == ky then Node Red a kx vx b
  else Node Red a ky vy (ins kx vx b)
ins kx vx (Node Black a ky vy b) =
  if kx < ky
    then case a of
           Node Red l k v r => balance1 ky vy b (ins kx vx (Node Red l k v r))
           a' => Node Black (ins kx vx a') ky vy b
  else if kx == ky then Node Black a kx vx b
  else case b of
         Node Red l k v r => balance2 a ky vy (ins kx vx (Node Red l k v r))
         b' => Node Black a ky vy (ins kx vx b')

setBlack : (1 t : Tree) -> Tree
setBlack (Node _ l k v r) = Node Black l k v r
setBlack Leaf = Leaf

insert : Int -> Bool -> (1 t : Tree) -> Tree
insert k v t = setBlack (ins k v t)

-- An Int that a function consuming a tree returns: its field is
-- unrestricted, so a match on it gives an ordinary Int. Not recursive, so
-- it is a register, not a cell (plan section 3).
data Count = MkCount Int

-- Counts the True values, consuming the tree.
count : (1 t : Tree) -> Int -> Count
count Leaf acc = MkCount acc
count (Node _ l _ v r) acc =
  let MkCount c = count l acc in
  count r (if v then c + 1 else c)

isRed : Tree -> Bool
isRed (Node Red _ _ _ _) = True
isRed _ = False

-- Uses the kept tree, so that no compiler can drop the parameter. The root
-- of a tree that insert built is black, so this is t.
keep : Tree -> (1 t : Tree) -> Tree
keep prev t = if isRed prev then setBlack t else t

-- The changed call site: t is still used after insert, as prev.
mkMap : Int -> Tree -> Tree -> Tree
mkMap n t prev =
  if n <= 0 then keep prev t
  else let n1 = n - 1 in mkMap n1 (insert n1 (n1 `mod` 10 == 0) t) t

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  n <- readInt
  let MkCount c = count (mkMap n Leaf Leaf) 0
  printLn c
