module Main

-- traverse_ over IO is the Prelude's foldr of (*>), which builds the whole
-- action before any of it runs: the fold of the rest is held two closures
-- deep in the action of each element, inside the closure (<*>) makes,
-- inside the bind that runs it, and both branches of the if build it. The
-- fold is still written top down, through the destination of the closure
-- that holds the rest, across the if's join, so building it runs in
-- constant stack (mlir.expect); running what it built is a chain of tail
-- calls. The list is built by a tail-recursive loop, so the fold is what
-- is tested.

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
