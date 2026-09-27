module Main

-- Red-black tree insertion: n keys go into a tree that is never shared,
-- then a fold counts the entries whose value is True. Perceus's `rbtree.kk`
-- (adapted there from Lean's `rbmap.lean`, Counting Immutable Beans).
-- Every insert can reuse the cells of the path it rebuilds.

import Prelude

data Color = Red | Black

data Tree = Leaf | Node Color Tree Int Bool Tree

isRed : Tree -> Bool
isRed (Node Red _ _ _ _) = True
isRed _ = False

balanceLeft : Tree -> Int -> Bool -> Tree -> Tree
balanceLeft (Node _ (Node Red lx kx vx rx) ky vy ry) k v r =
  Node Red (Node Black lx kx vx rx) ky vy (Node Black ry k v r)
balanceLeft (Node _ ly ky vy (Node Red lx kx vx rx)) k v r =
  Node Red (Node Black ly ky vy lx) kx vx (Node Black rx k v r)
balanceLeft (Node _ lx kx vx rx) k v r =
  Node Black (Node Red lx kx vx rx) k v r
balanceLeft Leaf _ _ _ = Leaf

balanceRight : Tree -> Int -> Bool -> Tree -> Tree
balanceRight l k v (Node _ (Node Red lx kx vx rx) ky vy ry) =
  Node Red (Node Black l k v lx) kx vx (Node Black rx ky vy ry)
balanceRight l k v (Node _ lx kx vx (Node Red ly ky vy ry)) =
  Node Red (Node Black l k v lx) kx vx (Node Black ly ky vy ry)
balanceRight l k v (Node _ lx kx vx rx) =
  Node Black l k v (Node Red lx kx vx rx)
balanceRight _ _ _ Leaf = Leaf

ins : Tree -> Int -> Bool -> Tree
ins (Node Red l kx vx r) k v =
  if k < kx then Node Red (ins l k v) kx vx r
  else if k > kx then Node Red l kx vx (ins r k v)
  else Node Red l k v r
ins (Node Black l kx vx r) k v =
  if k < kx
    then (if isRed l then balanceLeft (ins l k v) kx vx r
                     else Node Black (ins l k v) kx vx r)
  else if k > kx
    then (if isRed r then balanceRight l kx vx (ins r k v)
                     else Node Black l kx vx (ins r k v))
  else Node Black l k v r
ins Leaf k v = Node Red Leaf k v Leaf

setBlack : Tree -> Tree
setBlack (Node _ l k v r) = Node Black l k v r
setBlack t = t

insert : Tree -> Int -> Bool -> Tree
insert t k v = setBlack (ins t k v)

fold : (Int -> Bool -> Int -> Int) -> Tree -> Int -> Int
fold f (Node _ l k v r) b = fold f r (f k v (fold f l b))
fold _ Leaf b = b

makeTree : Int -> Tree -> Tree
makeTree n t =
  if n <= 0 then t
  else let n1 = n - 1 in makeTree n1 (insert t n1 (n1 `mod` 10 == 0))

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
  let t = makeTree n Leaf
  printLn (fold (\_, v, r => if v then r + 1 else r) t 0)
