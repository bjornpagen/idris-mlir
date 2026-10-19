module Main

-- One type written up to eta in two places: `build` makes its box at
-- `Box Nat (Q b)`, and the pair holds it at `Box Nat (\a => Q b a)`, under
-- the pair's own lambda over `b`. Q's arguments are indices, which keys
-- erase; erased under that lambda, the expanded family is `\a => Q _ _`,
-- no longer `Q _`. Both are one data instance, so `describe`'s match on
-- the box the pair holds sees the constructor `build` made, and its
-- `Ord` field.

import Prelude

data Q : Nat -> Nat -> Type where
  MkQ : Int -> Q b a

data Box : (k : Type) -> (v : k -> Type) -> Type where
  Empty : Ord k => Box k v
  Full : Ord k => (x : k) -> v x -> Box k v

build : (b : Nat) -> Box Nat (Q b)
build b = Full 1 (MkQ 10)

buildAt : (b : Nat) -> Nat -> Int -> Box Nat (Q b)
buildAt b x v = Full x (MkQ v)

pack : (b : Nat ** Box Nat (\a => Q b a))
pack = (3 ** build 3)

describe : (b : Nat ** Box Nat (\a => Q b a)) -> String
describe (_ ** Empty) = "empty"
describe (b ** Full x (MkQ v)) = "full " ++ show b ++ " " ++ show x ++ " " ++ show v ++ " " ++ show (compare x 2)

-- Every constructor at every outcome of the comparison, each box built at
-- `Box Nat (Q b)` and held at the eta-expanded family.
others : List (b : Nat ** Box Nat (\a => Q b a))
others = [(0 ** Empty), (5 ** buildAt 5 2 (-7)), (1 ** buildAt 1 3 0)]

main : IO ()
main = do
  putStrLn (describe pack)
  traverse_ (putStrLn . describe) others
