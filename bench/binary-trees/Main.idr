module Main

-- Binary trees (the Benchmarks Game, after Hans Boehm's GCBench), on one
-- core: allocate, walk and free many perfect trees while one long-lived
-- tree stays alive. Lean's `binarytrees.st.lean` (Counting Immutable
-- Beans); Perceus's `binarytrees.kk` is the same program with tasks. The
-- extra argument of make' keeps the two subtrees distinct, as in Lean's
-- version; the loop passes its counter there, so no tree can be hoisted out
-- of the loop.

import Prelude

data Tree = Tip | Node Tree Tree

make' : Int -> Int -> Tree
make' n d =
  if d == 0 then Node Tip Tip
  else Node (make' n (d - 1)) (make' (n + 1) (d - 1))

make : Int -> Tree
make d = make' d d

check : Tree -> Int
check Tip = 0
check (Node l r) = 1 + check l + check r

-- Builds and checks i trees of depth d, adding their checks to t.
sumT : Int -> Int -> Int -> Int
sumT d i t = if i == 0 then t else sumT d (i - 1) (t + check (make' i d))

pow2 : Int -> Int
pow2 k = if k == 0 then 1 else 2 * pow2 (k - 1)

out : String -> Int -> Int -> IO ()
out s depth c = putStrLn (s ++ " of depth " ++ show depth ++ "\t check: " ++ show c)

depths : Int -> Int -> Int -> IO ()
depths minN maxN d =
  if d > maxN then pure ()
  else do
    let n = pow2 (maxN - d + minN)
    out (show n ++ "\t trees") d (sumT d n 0)
    depths minN maxN (d + 2)

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
  let minN = 4
  let maxN = max (minN + 2) n
  let stretchN = maxN + 1
  out "stretch tree" stretchN (check (make stretchN))
  let long = make maxN
  depths minN maxN minN
  out "long lived tree" maxN (check long)
