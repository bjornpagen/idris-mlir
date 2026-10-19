module Main

-- for_ over IO is traverse_ flipped, the Prelude's foldr of (*>): each
-- element's action runs, then the fold of the rest, in tail position. A
-- million elements, where the harness gives a program a 1 MiB stack; the
-- list is built by a tail-recursive loop, so what is tested is for_.

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
  for_ (build n []) $ \x => when (x `mod` 250000 == 0) (printLn x)
