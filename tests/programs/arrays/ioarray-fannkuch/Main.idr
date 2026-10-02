module Main

-- fannkuch-redux (the Benchmarks Game): every permutation of 0..n-1, the
-- number of prefix reversals that brings 0 to the front, the largest such
-- count and an alternating checksum. The permutation, its working copy and
-- the counters are arrays (base's IOArray), updated in place as the game's
-- programs do.

import Prelude
import Data.IOArray

get : IOArray Int -> Int -> IO Int
get arr i = do
  Just v <- readArray arr i
    | Nothing => pure 0
  pure v

set : IOArray Int -> Int -> Int -> IO ()
set arr i v = ignore (writeArray arr i v)

-- perm1[i] := i.
iota : IOArray Int -> Int -> Int -> IO ()
iota arr n i = if i >= n then pure () else do set arr i i; iota arr n (i + 1)

copy : IOArray Int -> IOArray Int -> Int -> Int -> IO ()
copy from to n i =
  if i >= n then pure ()
  else do v <- get from i
          set to i v
          copy from to n (i + 1)

-- Reverses perm[i..j].
rev : IOArray Int -> Int -> Int -> IO ()
rev p i j =
  if i >= j then pure ()
  else do a <- get p i
          b <- get p j
          set p i b
          set p j a
          rev p (i + 1) (j - 1)

-- The number of prefix reversals (each of perm[0..perm[0]]) that brings 0
-- to the front.
flips : IOArray Int -> Int -> IO Int
flips p k = do
  h <- get p 0
  if h == 0
     then pure k
     else do rev p 0 h
             flips p (k + 1)

-- Rotates perm1[0..r] left by one.
rotate : IOArray Int -> Int -> IO ()
rotate p r = do
  p0 <- get p 0
  shift 0
  set p r p0
  where
    shift : Int -> IO ()
    shift i =
      if i >= r then pure ()
      else do v <- get p (i + 1)
              set p i v
              shift (i + 1)

-- The next permutation's r, or nothing when they are exhausted.
next : Int -> IOArray Int -> IOArray Int -> Int -> IO (Maybe Int)
next n perm1 count r =
  if r == n
     then pure Nothing
     else do rotate perm1 r
             c <- get count r
             set count r (c - 1)
             if c > 1 then pure (Just r) else next n perm1 count (r + 1)

-- count[i] := i + 1 for i below r.
fill : IOArray Int -> Int -> IO ()
fill count r = if r == 1 then pure () else do set count (r - 1) r; fill count (r - 1)

loop : Int -> IOArray Int -> IOArray Int -> IOArray Int -> Int -> Int -> Int -> Int -> IO (Int, Int)
loop n perm1 perm count r idx checksum maxf = do
  fill count r
  copy perm1 perm n 0
  f <- flips perm 0
  let checksum' = if idx `mod` 2 == 0 then checksum + f else checksum - f
  let maxf' = max maxf f
  Just r' <- next n perm1 count 1
    | Nothing => pure (checksum', maxf')
  loop n perm1 perm count r' (idx + 1) checksum' maxf'

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
  perm1 <- newArray n
  perm <- newArray n
  count <- newArray n
  iota perm1 n 0
  (checksum, maxf) <- loop n perm1 perm count n 0 0 0
  printLn checksum
  putStrLn ("Pfannkuchen(" ++ show n ++ ") = " ++ show maxf)
