-- expect: PROF-ESC-1 line 11
module Main

data Same : Int -> Int -> Type where
  Yes : Same x x

use : (0 _ : Same 1 1) -> Int
use _ = 7

main : Int
main = use ?proof
