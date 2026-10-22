module Main

-- A value moved along an equality is the value itself: `replace` and
-- `rewrite__impl`, which `rewrite` elaborates to, are compiled from their
-- bodies, each a match on the erased proof that the two sides are equal,
-- whose one alternative gives back the value.

import Prelude
import Data.Nat

data Box : Nat -> Type where
  MkBox : Int -> Box n

unbox : Box n -> Int
unbox (MkBox x) = x

-- `rewrite` elaborates to `rewrite__impl`.
commuted : {0 m, n : Nat} -> Box (m + n) -> Box (n + m)
commuted b = rewrite plusCommutative n m in b

-- `replace`, written directly.
padded : {0 n : Nat} -> Box n -> Box (n + 0)
padded b = replace {p = Box} (sym (plusZeroRightNeutral n)) b

main : IO ()
main = do
  c <- getChar
  let b = MkBox {n = 2 + 3} (cast (ord c))
  printLn (unbox (commuted {m = 2} {n = 3} b))
  printLn (unbox (padded (commuted {m = 2} {n = 3} b)))
