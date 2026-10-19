module Main
import Prelude

data Same : Int -> Int -> Type where
  Yes : Same x x

-- The refused program with a true proof in the erased argument, which
-- needs no escape hatch.
0 truth : Same 1 1
truth = Yes

use : (0 _ : Same 1 1) -> Int
use _ = 7

main : IO ()
main = printLn (use truth)
