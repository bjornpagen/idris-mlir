module Main

import Prelude
import Linear.Notation
import Linear.List

-- A definition of no argument whose value is a linear list, referred to
-- twice and passed each time to a function that rebuilds it. Each
-- reference evaluates the definition's body, which builds its cells
-- anew, so each call is passed a list nothing else holds, and both
-- rebuilds are in place; neither may write cells the other reads.

bump : LList (!* Int) -@ LList (!* Int)
bump [] = []
bump (MkBang x :: xs) = MkBang (x + 1) :: bump xs

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc + x) xs

base : LList (!* Int)
base = MkBang 1 :: MkBang 2 :: MkBang 3 :: []

main : IO ()
main = do
  c <- getChar
  let k = cast (ord c - ord '0')
  let MkBang first = sumL 0 (bump base)
  let MkBang second = sumL k (bump base)
  printLn (first, second)
