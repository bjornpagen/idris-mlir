module Main

-- rule: FE-TR-6, SEM-REC-2, ELIM-G-14, ELIM-G-15
-- The Prelude's Show on composite values whose parts are computed at
-- runtime: tuples of three or more (the implementation for the inner pair
-- is a solved metavariable in the elaborated term), lists (shown by a
-- recursion with a string accumulator, which follows the list),
-- Maybe, Either and Ordering.

import Prelude

main : IO ()
main = do
  c <- getChar
  let n = the Int (cast (ord c) - 48)
  printLn (Just n, the (Either Int Int) (Left n))
  printLn (max n 3, min n 3, compare n 3)
  printLn (n `div` (-2), n `mod` (-2), abs (negate n))
  printLn (sqrt (cast n), floor (cast n / 2.0), pow (cast n) 2.0)
  printLn [n, 2, 3]
  printLn (map (* n) [1 .. 5])
  printLn [Just n, Nothing]
  printLn (the (List Double) [cast n, 0.5])
  printLn (Just [n - 10, n])
