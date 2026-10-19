module Main

-- A definition with missing cases runs until an input it does not cover,
-- then crashes; the output before the crash is written, and the crash is
-- named on stderr.

import Builtin
import Prelude

partial
name : Int -> String
name 1 = "one"
name 2 = "two"

partial
main : IO ()
main = do
  c <- getChar
  putStrLn (name (prim__sub_Int (prim__cast_CharInt c) 48))
  d <- getChar
  putStrLn (name (prim__sub_Int (prim__cast_CharInt d) 48))
  putStrLn "not reached"
