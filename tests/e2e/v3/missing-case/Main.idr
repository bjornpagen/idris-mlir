module Main

-- rule: SEM-CRASH-2, PROF-FN-5, LOW-CRASH-2
-- A definition with missing cases runs until an input it does not cover,
-- then crashes; the output before the crash is written. On Chez the crash
-- message ("ERROR: ...", SEM-DEV-1) goes to stdout through Chez's own port,
-- which is flushed at exit before the Prelude's C stdio: it comes first.

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
