-- expect: polymorphism, line 14
module Main

import Prelude
import Array

-- Each call of deeper gives its array one more axis, so the ranks its
-- instances must take are unbounded: an array's rank is its type's, and
-- the chain of requests from main grows at it at each step. The program is
-- refused, naming that growth, rather than compiled to an array of a rank
-- only the run knows.
deeper : Array s Int -> Nat -> Int
deeper x Z = sum x
deeper x (S k) = deeper (tabulate (shape x :< 2) (\(i :< _) => x !! i)) k

main : IO ()
main = do
  line <- getLine
  printLn (deeper (tabulate [<2] (\_ => 1)) (integerToNat (cast line)))
