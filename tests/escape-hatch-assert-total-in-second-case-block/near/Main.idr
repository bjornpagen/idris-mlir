module Main

import Prelude

-- The refused program without assert_total, which the recursion on the
-- list's tail never needed: count adds 1 per list cell and one more for
-- the end of the list when n is 0, 2 otherwise.
count : List Int -> Int -> Int
count xs n = (case n of
                0 => 1
                _ => 2) + (case xs of
                             [] => 0
                             (_ :: rest) => count rest n)

main : IO ()
main = do
  line <- getLine
  printLn (count [1, 2, 3] (cast line))
