-- expect: escape hatch, line 12
module Main
import Prelude

data Same : Int -> Int -> Type where
  Yes : Same x x

use : (0 _ : Same 1 1) -> Int
use _ = 7

main : IO ()
main = printLn (use ?proof)
