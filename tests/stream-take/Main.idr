module Main

-- Codata: an infinite Stream is a suspension, forced by name, and taken
-- apart only as far as it is forced: `take` forces the first n elements,
-- n read at run time, none when n is 0.

import Prelude

main : IO ()
main = do
  line <- getLine
  let n = the Nat (cast (the Int (cast line)))
  printLn (sum (take n (countFrom (the Int 1) (+ 1))))
