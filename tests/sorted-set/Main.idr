module Main

-- Data.SortedSet wraps a SortedMap of units, so its ordering is the map's
-- dictionary field, reached through one more data type. Sets of Int and of
-- String: fromList, insert, contains, delete, union, intersection,
-- difference, and the elements in order; the empty set's; and the set of
-- 2000 numbers drawn from -250 to 249, repeats among them, whose elements
-- are strictly increasing and hold every number drawn, a property shown
-- failing beside it on a list out of order and a number never drawn.

import Prelude
import Data.SortedSet

gen : Int -> Int -> List Int -> List Int
gen 0 _ acc = acc
gen k x acc =
  let x' = (x * 1103515245 + 12345) `mod` 2147483648
  in gen (k - 1) x' ((x' `mod` 500) - 250 :: acc)

increasing : List Int -> Bool
increasing (x :: y :: rest) = x < y && increasing (y :: rest)
increasing _ = True

main : IO ()
main = do
  let a = fromList [5, 3, 9, 1, 3]
  let b = insert 4 (insert 9 empty)
  putStrLn (show (SortedSet.toList a))
  putStrLn (show (contains 3 a) ++ " " ++ show (contains 4 a))
  putStrLn (show (SortedSet.toList (delete 9 a)))
  putStrLn (show (SortedSet.toList (union a b)))
  putStrLn (show (SortedSet.toList (intersection a b)))
  putStrLn (show (SortedSet.toList (difference a b)))
  let names = fromList ["pear", "apple", "fig"]
  putStrLn (show (SortedSet.toList (insert "banana" names)))
  putStrLn (show (leftMost names) ++ " " ++ show (rightMost names))
  let none = the (SortedSet Int) empty
  putStrLn (show (SortedSet.toList none) ++ " " ++ show (leftMost none) ++ " " ++ show (contains 0 none))
  putStrLn (show (SortedSet.toList (delete 100 a)) ++ " " ++ show (SortedSet.toList (difference a a)))
  let xs = gen 2000 1 []
  let s = fromList xs
  let elems = SortedSet.toList s
  putStrLn (show (increasing elems) ++ " " ++ show (all (\x => contains x s) xs) ++ " " ++ show (length elems))
  putStrLn (show (increasing [2, 1]) ++ " " ++ show (all (\x => contains x s) [251]))
  putStrLn (show (leftMost s) ++ " " ++ show (rightMost s))
