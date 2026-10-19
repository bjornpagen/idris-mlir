module Main

-- The program runs the main Idris resolves in the main file, the one
-- visible there: Helper's main is private to it, so it is not seen.

import Prelude
import Helper

main : IO ()
main = putStrLn "main"
