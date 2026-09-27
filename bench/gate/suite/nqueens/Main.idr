module Main

-- All solutions of the n-queens problem, as lists of lists that share their
-- tails. Perceus's `nqueens.kk`. Prints the number of solutions.

import Prelude

safe : Int -> Int -> List Int -> Bool
safe queen diag (q :: qs) =
  queen /= q && queen /= q + diag && queen /= q - diag && safe queen (diag + 1) qs
safe _ _ [] = True

appendSafe : Int -> List Int -> List (List Int) -> List (List Int)
appendSafe queen xs xss =
  if queen <= 0 then xss
  else if safe queen 1 xs then appendSafe (queen - 1) xs ((queen :: xs) :: xss)
  else appendSafe (queen - 1) xs xss

extend : Int -> List (List Int) -> List (List Int) -> List (List Int)
extend queen acc (xs :: rest) = extend queen (appendSafe queen xs acc) rest
extend _ acc [] = acc

findSolutions : Int -> Int -> List (List Int)
findSolutions n queen =
  if queen == 0 then [[]] else extend n [] (findSolutions n (queen - 1))

-- The length of a list, as an Int (the Prelude's `length` is a Nat).
len : List a -> Int -> Int
len (_ :: xs) r = len xs (r + 1)
len [] r = r

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
  printLn (len (findSolutions n n) 0)
