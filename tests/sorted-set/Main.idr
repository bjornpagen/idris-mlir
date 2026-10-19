module Main

-- Data.SortedSet wraps a SortedMap of units, so its ordering is the map's
-- dictionary field, reached through one more data type. Sets of Int and of
-- String: fromList, insert, contains, delete, union, intersection,
-- difference, and the elements in order.

import Prelude
import Data.SortedSet

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
