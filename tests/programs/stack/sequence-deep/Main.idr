module Main

-- sequence_ over a list of a million actions. It is the Prelude's foldr of
-- (*>), which builds the whole action before any of it runs: the fold of
-- the rest is the argument of (*>), not a call in tail position, so the
-- building goes a million calls deep, on Chez as here. Running what it
-- built takes constant stack.

import Prelude

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

build : Int -> List Int -> List Int
build 0 acc = acc
build n acc = build (n - 1) (n :: acc)

main : IO ()
main = do
  n <- readInt
  sequence_ (map (\x => when (x `mod` 250000 == 0) (printLn x)) (build n []))
