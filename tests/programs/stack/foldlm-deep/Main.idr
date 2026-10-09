module Main

-- foldlM over a list of a million numbers. The Prelude's foldlM folds the
-- list into a chain of binds nested to the left, ((pure 0 >>= f 1) >>= f
-- 2) >>= ..., and running a bind runs the action it binds first, as a call
-- whose result the rest needs: a million calls deep.

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
  s <- foldlM (\acc, x => do
                 when (x `mod` 250000 == 0) (printLn x)
                 pure (acc + x)) 0 (build n [])
  printLn s
