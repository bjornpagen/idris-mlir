module Main

-- Red-black tree insertion with checkpoints: every fifth tree is kept in a
-- list, so the trees share most of their cells and an insert may not update
-- a shared path in place. Perceus's `rbtree-ck.kk` (from Lean's
-- `rbmap_checkpoint.lean`, Counting Immutable Beans). Prints the number of
-- trees kept and the count of True values in the last one.

import Prelude

data Color = Red | Black

data Tree = Leaf | Node Color Tree Int Bool Tree

fold : (Int -> Bool -> Int -> Int) -> Tree -> Int -> Int
fold _ Leaf acc = acc
fold f (Node _ l k v r) acc = fold f r (f k v (fold f l acc))

balance1 : Int -> Bool -> Tree -> Tree -> Tree
balance1 kv vv t (Node _ (Node Red l kx vx r1) ky vy r2) =
  Node Red (Node Black l kx vx r1) ky vy (Node Black r2 kv vv t)
balance1 kv vv t (Node _ l1 ky vy (Node Red l2 kx vx r)) =
  Node Red (Node Black l1 ky vy l2) kx vx (Node Black r kv vv t)
balance1 kv vv t (Node _ l ky vy r) =
  Node Black (Node Red l ky vy r) kv vv t
balance1 _ _ _ Leaf = Leaf

balance2 : Tree -> Int -> Bool -> Tree -> Tree
balance2 t kv vv (Node _ (Node Red l kx1 vx1 r1) ky vy r2) =
  Node Red (Node Black t kv vv l) kx1 vx1 (Node Black r1 ky vy r2)
balance2 t kv vv (Node _ l1 ky vy (Node Red l2 kx2 vx2 r2)) =
  Node Red (Node Black t kv vv l1) ky vy (Node Black l2 kx2 vx2 r2)
balance2 t kv vv (Node _ l ky vy r) =
  Node Black t kv vv (Node Red l ky vy r)
balance2 _ _ _ Leaf = Leaf

isRed : Tree -> Bool
isRed (Node Red _ _ _ _) = True
isRed _ = False

ins : Tree -> Int -> Bool -> Tree
ins Leaf kx vx = Node Red Leaf kx vx Leaf
ins (Node Red l ky vy r) kx vx =
  if kx < ky then Node Red (ins l kx vx) ky vy r
  else if kx == ky then Node Red l kx vx r
  else Node Red l ky vy (ins r kx vx)
ins (Node Black l ky vy r) kx vx =
  if kx < ky
    then (if isRed l then balance1 ky vy r (ins l kx vx)
                     else Node Black (ins l kx vx) ky vy r)
  else if kx == ky then Node Black l kx vx r
  else if isRed r then balance2 l ky vy (ins r kx vx)
  else Node Black l ky vy (ins r kx vx)

setBlack : Tree -> Tree
setBlack (Node _ l k v r) = Node Black l k v r
setBlack t = t

insert : Tree -> Int -> Bool -> Tree
insert t k v = if isRed t then setBlack (ins t k v) else ins t k v

makeTreeAux : Int -> Int -> Tree -> List Tree -> List Tree
makeTreeAux freq n t acc =
  if n <= 0 then t :: acc
  else let t' = insert t n (n `mod` 10 == 0) in
       makeTreeAux freq (n - 1) t' (if n `mod` freq == 0 then t' :: acc else acc)

makeTree : Int -> Int -> List Tree
makeTree freq n = makeTreeAux freq n Leaf []

-- The number of non-empty trees in the list (Lean's `myLen`).
myLen : List Tree -> Int -> Int
myLen (Node _ _ _ _ _ :: xs) r = myLen xs (r + 1)
myLen (_ :: xs) r = myLen xs r
myLen [] r = r

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

-- The number of True values in the first tree of the list.
countFirst : List Tree -> Int
countFirst (t :: _) = fold (\_, v, r => if v then r + 1 else r) t 0
countFirst [] = 0

main : IO ()
main = do
  n <- readInt
  let trees = makeTree 5 n
  putStrLn (show (myLen trees 0) ++ " " ++ show (countFirst trees))
