module Main
import Prelude

data Same : Int -> Int -> Type where
  Yes : Same x x

use : (0 _ : Same 1 1) -> Int
use _ = 7

-- The refused program with the proof given.
main : IO ()
main = printLn (use Yes)
