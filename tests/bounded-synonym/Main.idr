module Main

import Prelude
import Data.List1

-- Vector1 a is a synonym for List1 (Nat, a), a non-empty list of numbered
-- elements. A table is a List (Nat, Vector1 a), so its type reaches List1
-- and Pair at (Nat, a) only through the synonym.

Vector1 : Type -> Type
Vector1 a = List1 (Nat, a)

weight : List (Nat, Vector1 a) -> Nat
weight [] = 0
weight ((n, v) :: rest) = n + length (forget v) + weight rest

describe : Show a => List (Nat, Vector1 a) -> String
describe [] = ""
describe ((n, (k, x) ::: _) :: rest) = show n ++ ":" ++ show k ++ "=" ++ show x ++ ";" ++ describe rest

main : IO ()
main = do
  let t : List (Nat, Vector1 String) = [(1, (0, "a") ::: [(1, "b")]), (2, singleton (0, "c"))]
  putStrLn (describe t)
  printLn (weight t)
