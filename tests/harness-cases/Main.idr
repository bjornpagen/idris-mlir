module Main

-- The program the harness's cases are checked on: it prints 100 divided
-- by the number on its stdin, which crashes on 0, and then exits with
-- status 7 when that number is 7.

import Prelude
import System

partial
main : IO ()
main = do
  line <- getLine
  let n = the Int (cast line)
  printLn (prim__div_Int 100 n)
  if n == 7 then exitWith (ExitFailure 7) else pure ()
