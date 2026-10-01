module Main

-- fannkuch-redux (the Benchmarks Game): every permutation of 1..n, the
-- number of prefix reversals that brings 1 to the front, the largest such
-- count and an alternating checksum. Permutations are lists, as an Idris
-- programmer writes them first.

import Prelude
import Data.List

-- Reverse the first h elements, where h is the head.
flip1 : List Int -> List Int
flip1 [] = []
flip1 p@(h :: _) = let (a, b) = splitAt (cast h) p in reverse a ++ b

flips : List Int -> Int -> Int
flips [] k = k
flips (1 :: _) k = k
flips p k = flips (flip1 p) (k + 1)

-- Rotate the first r + 1 elements left by one.
rotate : Int -> List Int -> List Int
rotate r xs = case splitAt (cast (r + 1)) xs of
  (p0 :: rest, t) => rest ++ (p0 :: t)
  (_, _) => xs

setAt : Int -> Int -> List Int -> List Int
setAt _ _ [] = []
setAt 0 v (_ :: xs) = v :: xs
setAt i v (x :: xs) = x :: setAt (i - 1) v xs

getAt : Int -> List Int -> Int
getAt _ [] = 0
getAt 0 (x :: _) = x
getAt i (_ :: xs) = getAt (i - 1) xs

-- count[i] := i + 1 for i below r.
fill : List Int -> Int -> List Int
fill count r = if r == 1 then count else fill (setAt (r - 1) r count) (r - 1)

-- The next permutation, or nothing when they are exhausted.
next : Int -> List Int -> List Int -> Int -> Maybe (List Int, List Int, Int)
next n perm count r =
  if r == n then Nothing
  else let perm' = rotate r perm
           c = getAt r count - 1
           count' = setAt r c count
       in if c > 0 then Just (perm', count', r) else next n perm' count' (r + 1)

loop : Int -> List Int -> List Int -> Int -> Int -> Int -> Int -> (Int, Int)
loop n perm count r idx checksum maxf =
  let count' = fill count r
      f = flips perm 0
      checksum' = if idx `mod` 2 == 0 then checksum + f else checksum - f
      maxf' = max maxf f
  in case next n perm count' 1 of
       Nothing => (checksum', maxf')
       Just (perm', count'', r') => loop n perm' count'' r' (idx + 1) checksum' maxf'

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
  let (checksum, maxf) = loop n [1 .. n] (replicate (cast n) 0) n 0 0 0
  printLn checksum
  putStrLn ("Pfannkuchen(" ++ show n ++ ") = " ++ show maxf)
