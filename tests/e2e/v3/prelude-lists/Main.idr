module Main

-- rule: SEM-REC-2, SEM-REC-1, FE-TR-6, ELIM-G-19
-- The Prelude's lists and Foldable, the ordinary way: literals and ranges
-- whose elements are computed at runtime, sum and product (through the
-- named Additive and Multiplicative monoids), folds with lambdas, map,
-- filter, reverse, length, all, any and elem. Every list is built during
-- specialization; its elements run at runtime.

import Prelude

main : IO ()
main = do
  c <- getChar
  let n = the Int (cast (ord c) - 48)
  printLn (sum [1, 2, n])
  printLn (product [1, 2, n, 4])
  printLn (sum (map (* n) [1 .. 10]))
  printLn (the Double (sum [0.5, cast n, 1.25]))
  printLn (foldl (\acc, x => acc * 10 + x) 0 [n, 2, n])
  printLn (foldr (\x, acc => x - acc) 0 (reverse [1, n, 3]))
  printLn (length [1, n, 3])
  printLn (all (> n) [7, 8, 9], any (== n) [1, 5])
  printLn (n * sum (filter (> 2) [1, 2, 3, 4]))
  printLn (elem n [1, 5, 9])
  printLn (sum [x * y | x <- [1 .. 3], y <- [n, 10]])
