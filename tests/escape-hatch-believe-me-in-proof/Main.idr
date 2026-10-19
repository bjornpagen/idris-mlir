-- expect: escape hatch, line 10
module Main
import Prelude

data Same : Int -> Int -> Type where
  Yes : Same x x

-- The escape hatch is only in an erased argument; it is still rejected.
0 lie : Same 1 2
lie = prim__believe_me (Same 1 1) (Same 1 2) Yes

use : (0 _ : Same 1 2) -> Int
use _ = 7

main : IO ()
main = printLn (use lie)
