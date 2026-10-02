-- expect: escape hatch, line 8
module Main

import Prelude

-- assert_linear tells Idris's usage checker that a function uses its
-- argument once, unchecked: an escape hatch, like believe_me.
twice : (1 x : Int) -> Int
twice x = assert_linear (\y => y + y) x

main : IO ()
main = printLn (twice 21)
