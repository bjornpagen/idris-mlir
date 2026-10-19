module Main

-- One Ord Int reaches the map's constructors written two ways: named
-- directly by `fromList`'s caller, and as the first of the constraints
-- (Ord k, Semigroup v) that Monoid (SortedMap k v) takes as one pair, which
-- `neutral` takes apart with `fst`. Both are one implementation, which the
-- map's constructors hold: implementations are compared by what they
-- reduce to, not as written.

import Prelude
import Data.SortedMap

main : IO ()
main = do
  line <- getLine
  let n = the Int (cast line)
  let m = the (SortedMap Int String) neutral
  printLn (keys (insert n "x" m))
  printLn (keys (the (SortedMap Int String) (fromList [(n, "y")])))
  printLn (keys (insert (n + 1) "z" (fromList [(n, "y")])))
