-- expect: polymorphism, line 13
-- message: Prelude.Basics.(:<)
module Main
import Prelude
import Array

-- Each call of deeper gives its array one more axis, so the ranks its
-- instances must take are unbounded: an array's rank is its type's, and
-- deeper passes its own shape back to itself as s :< 2, one axis longer at
-- each round. The program is refused, naming that growth, rather than
-- compiled to an array of a rank only the run knows. near/ passes the
-- same shape back, doubled, so deeper has one instance.
deeper : Array s Int -> Nat -> Int
deeper x Z = sum x
deeper x (S k) = deeper (tabulate (shape x :< 2) (\(i :< _) => x !! i)) k

main : IO ()
main = do
  line <- getLine
  printLn (deeper (tabulate [<2] (\_ => 1)) (integerToNat (cast line)))
