module Main

-- rule: SEM-CRASH-2, PROF-FN-5, LOW-CRASH-2
-- A definition with missing cases runs until an input it does not cover,
-- then crashes; the output before the crash is written.

import Builtin
import IdrisMLIR.IO

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
