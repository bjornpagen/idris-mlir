-- expect: escape hatch, line 11
module Main

import Prelude

-- Two case blocks of one definition, whose names print alike: the escape
-- hatch in the second is the user's as much as one in the first.
count : List Int -> Int -> Int
count xs n = (case n of
                0 => 1
                _ => 2) + (case xs of
                             [] => 0
                             (_ :: rest) => assert_total (count rest n))

main : IO ()
main = printLn (count [1, 2, 3] 0)
