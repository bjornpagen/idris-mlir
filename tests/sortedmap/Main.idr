module Main

-- Data.SortedMap keeps the ordering of its keys in the map's constructors
-- (`Empty : Ord k => ...`): a dictionary held in a field, which the compiler
-- holds as a compile-time value of the map's data instance. Two maps, keyed
-- by String and by Int, one of them in a record: insert, lookup, delete,
-- toList, folds, and the keys in order.

import Prelude
import Data.List
import Data.String
import Data.SortedMap

record Table where
  constructor MkTable
  name : String
  entries : SortedMap Int Int

counts : List String -> SortedMap String Int
counts = foldl (\m, w => insertWith (+) w 1 m) empty

squares : Int -> SortedMap Int Int
squares 0 = empty
squares n = insert n (n * n) (squares (n - 1))

main : IO ()
main = do
  let m = counts (words "the quick brown fox jumps over the lazy dog the end")
  traverse_ (\(k, v) => putStrLn (k ++ " " ++ show v)) (SortedMap.toList m)
  putStrLn (show (lookup "the" m))
  putStrLn (show (lookup "cat" m))
  let m' = delete "the" (delete "fox" m)
  putStrLn (unwords (keys m'))
  putStrLn (show (foldl (+) 0 m'))
  let t = MkTable "squares" (squares 10)
  putStrLn (t.name ++ " " ++ show (lookup 7 t.entries) ++ " " ++ show (lookup 11 t.entries))
  putStrLn (show (SortedMap.toList (delete 5 t.entries)))
  putStrLn (show (foldr (\v, acc => v + acc) 0 t.entries))
  putStrLn (show (keys (insert 0 0 (fromList [(12, 144), (11, 121)]))))
  putStrLn (show (values (update (map (* 2)) 3 t.entries)))
