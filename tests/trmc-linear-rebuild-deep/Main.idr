module Main

import Prelude
import Linear.Notation
import Linear.List

-- A linear list a million cells long, each rebuilt by a self call under
-- the cell: the loop takes each cell apart and rebuilds it in place,
-- passing the pending tail as the place the next level fills, so it grows
-- no stack and allocates no cell of the list.

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

bump : LList (!* Int) -@ LList (!* Int)
bump [] = []
bump (MkBang x :: xs) = MkBang (x + 1) :: bump xs

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc + x) xs

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
  let MkBang s = sumL 0 (bump (build n []))
  printLn s
