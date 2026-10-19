-- expect: program, line 1
-- message: Helper.main
module Main

-- Helper exports a main of its own, so two are visible in the main file,
-- and which one is the program's is ambiguous: the program is refused,
-- naming both.

import Prelude
import Helper

main : IO ()
main = putStrLn "main"
