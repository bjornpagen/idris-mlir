module Main

import Prelude

-- An Integer computed from a value known only at runtime exists at runtime,
-- as a small big or a bignum on the heap.
count : Int -> Integer
count n = prim__cast_IntInteger n

partial
main : IO ()
main = do
  c <- getChar
  putStrLn (prim__cast_IntegerString (count (prim__cast_CharInt c)))
