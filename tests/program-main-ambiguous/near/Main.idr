module Main

-- The refused program with Helper's main not exported: one main is
-- visible in the main file, and it is the program's.

import Prelude
import Helper

main : IO ()
main = putStrLn "main"
