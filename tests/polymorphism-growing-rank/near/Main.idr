module Main
import Prelude
import Array

-- The refused program with the shape kept: each round doubles the
-- elements of an array of the same rank and extents, so the sum after k
-- rounds is 2 * 2^k.
deeper : Array s Int -> Nat -> Int
deeper x Z = sum x
deeper x (S k) = deeper (tabulate (shape x) (\i => (x !! i) * 2)) k

main : IO ()
main = do
  line <- getLine
  printLn (deeper (tabulate [<2] (\_ => 1)) (integerToNat (cast line)))
