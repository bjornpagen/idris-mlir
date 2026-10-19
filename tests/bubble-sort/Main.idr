module Main

-- Bubble sort on a list the program never shares: every pass takes each
-- cell apart and builds the next list in the same cells. Idris lifts the
-- `if` into a function of its own, a case block, which calls `bubble`
-- back; once it is part of `bubble` again, the cell `bubble` takes apart is
-- the one its result is built in.

import Prelude

data L = N | C Int L

build : Int -> Int -> L
build s 0 = N
build s n = C ((s * 7919 + n * 104729) `mod` 1000) (build s (n - 1))

bubble : Int -> (1 xs : L) -> L
bubble x N = C x N
bubble x (C y ys) = if x > y then C y (bubble x ys) else C x (bubble y ys)

pass : (1 xs : L) -> L
pass N = N
pass (C x xs) = bubble x xs

sortN : Int -> (1 xs : L) -> L
sortN 0 xs = xs
sortN k xs = sortN (k - 1) (pass xs)

-- A digest of the sorted list that depends on its order.
digest : L -> Int
digest N = 0
digest (C x xs) = (x + 31 * digest xs) `mod` 1000000007

sorted : L -> Bool
sorted (C x (C y ys)) = x <= y && sorted (C y ys)
sorted _ = True

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
  let xs = sortN n (build n n)
  printLn (sorted xs, digest xs)
