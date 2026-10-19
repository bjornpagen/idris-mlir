module Main

-- traverse_ over IO is the Prelude's foldr, which returns the IORes of its
-- recursive call rebuilt from its fields. Record eta makes that rebuilt
-- value the call's own, so the call is a tail call and the fold a loop:
-- it runs in constant stack over 200000 elements, where the harness gives
-- a program a 1 MiB stack. The list is built by a tail-recursive loop, so
-- the fold is what is tested.

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
  traverse_ (\x => if x `mod` 50000 == 0 then printLn x else pure ()) (build n [])
