-- expect: PROF-ESC-1 line 9
module Main

data Same : Int -> Int -> Type where
  Yes : Same x x

-- The escape hatch is only in an erased argument; it is still rejected.
0 lie : Same 1 2
lie = prim__believe_me (Same 1 1) (Same 1 2) Yes

use : (0 _ : Same 1 2) -> Int
use _ = 7

main : Int
main = use lie
