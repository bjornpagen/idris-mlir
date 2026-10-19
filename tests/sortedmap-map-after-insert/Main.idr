module Main

-- `map` over a SortedMap, and `keySet`, which is one, match the map at the
-- type `Data.SortedMap.Dependent.map` takes, its value family solved by
-- unification (`\_ => v`); `insert` builds it at the type the record's
-- field writes, `const v`. One type is one data instance, so the match sees
-- the constructors `insert` built: on the map built in any order, on one
-- whose key was inserted twice (the second value kept), and on the empty
-- map.

import Prelude
import Data.SortedMap
import Data.SortedSet

main : IO ()
main = do
  let m = insert 3 "three" (insert 1 "one" (insert 2 "two" (the (SortedMap Int String) empty)))
  putStrLn (show (SortedSet.toList (keySet m)))
  putStrLn (show (SortedMap.toList (map (++ "!") m)))
  putStrLn (show (SortedSet.toList (keySet (the (SortedMap Int String) empty))))
  let m' = insert 2 "zwei" (insert 2 "two" (insert 3 "three" (insert 1 "one" (the (SortedMap Int String) empty))))
  putStrLn (show (SortedMap.toList (map (++ "!") m')))
  putStrLn (show (SortedMap.toList (map (++ "!") (the (SortedMap Int String) empty))))
