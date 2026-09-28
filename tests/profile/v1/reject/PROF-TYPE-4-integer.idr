-- expect: PROF-TYPE-4 line 8
module Main

import Prelude

-- An Integer computed from a value known only at runtime would have to
-- exist at runtime.
count : Int -> Integer
count n = prim__cast_IntInteger n

partial
main : IO ()
main = do
  c <- getChar
  putStrLn (prim__cast_IntegerString (count (prim__cast_CharInt c)))
