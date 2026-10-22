module Main

import Prelude
import Linear.Notation
import Linear.List

-- A linear list rebuilt in place by a partial function, twice over: the
-- first call's result is the second's argument. The case the partial
-- function has no clause for crashes, and a crash gives its caller
-- nothing, so it shares nothing either: what the call gives back is the
-- list it rebuilt, exclusive, and the second call may rebuild it in place
-- too. A list of n gives back each element plus two.

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

partial
bump1 : LList (!* Int) -@ LList (!* Int)
bump1 (MkBang x :: xs) = MkBang (x + 1) :: bumpRest xs
  where
    bumpRest : LList (!* Int) -@ LList (!* Int)
    bumpRest [] = []
    bumpRest (MkBang y :: ys) = MkBang (y + 1) :: bumpRest ys

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc + x) xs

partial
main : IO ()
main = do
  c <- getChar
  let n = cast (ord c - ord '0')
  if n <= 0
    then putStrLn "no list"
    else do
      let MkBang total = sumL 0 (bump1 (bump1 (build n [])))
      printLn total
