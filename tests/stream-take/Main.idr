module Main

-- Codata: an infinite Stream is a suspension, forced by name, and taken
-- apart only as far as it is forced: `take` forces the first ten elements.

import Prelude

main : IO ()
main = printLn (sum (take 10 (countFrom (the Int 1) (+ 1))))
