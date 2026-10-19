module Main

-- The refused program with one implementation: both maps are built with
-- backward, so the map type holds one Ord, and both list their keys in
-- backward's order.

import Prelude
import Data.SortedMap

cmp : Int -> Int -> Ordering
cmp = compare

[forward] Ord Int where
  compare = cmp

[backward] Ord Int where
  compare x y = cmp y x

main : IO ()
main = do
  let up = insert 1 "one" (insert 2 "two" (empty @{backward}))
  putStrLn (show (keys up))
  let down = insert 1 "one" (insert 2 "two" (empty @{backward}))
  putStrLn (show (keys down))
