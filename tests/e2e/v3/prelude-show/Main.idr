module Main

-- rule: FE-TR-6, SEM-REC-2, ELIM-G-20, ELIM-G-15
-- The Prelude's Show on composite values whose parts are computed at
-- runtime: tuples of three or more (the implementation for the inner pair
-- is a solved metavariable in the elaborated term), lists (shown by a
-- recursion with a string accumulator, which follows the list),
-- Maybe, Either and Ordering, nested in one another (a list inside a pair:
-- the function that shows a list is passed its Show implementation as an
-- explicit argument, recognized by its type, FE-TR-6).

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
  printLn (n, [n, 2], [(n, 1.5)])
