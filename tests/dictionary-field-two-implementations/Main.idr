module Main

-- Data.SortedMap holds its Ord in the map's constructors: one map type
-- built with two implementations holds, in each map, which one built it,
-- and each map lists its keys in that one's order.

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
  let up = insert 1 "one" (insert 2 "two" (empty @{forward}))
  putStrLn (show (keys up))
  let down = insert 1 "one" (insert 2 "two" (empty @{backward}))
  putStrLn (show (keys down))
