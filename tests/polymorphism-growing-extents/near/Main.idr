module Main
import Prelude
import Array

-- The refused program with the rank kept: each round rebuilds the array at
-- the same extents, doubled, and the result is its sum.
deeper : Extents s -> Array s Int -> Nat -> Int
deeper e a Z = sum a
deeper e a (S k) = deeper e (tabulate e (\i => (a !! i) * 2)) k

main : IO ()
main = do
  line <- getLine
  printLn (deeper [<2] (tabulate [<2] (\_ => 1)) (cast line))
