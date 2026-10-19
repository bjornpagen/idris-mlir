-- expect: polymorphism, line 11
-- message: growing it by 1 each round
module Main
import Prelude
import Array

-- deeper's shape is erased, but its array's type needs the shape's form,
-- so the form keys deeper's instances: each round passes `e :< 1` back,
-- one axis longer, and the ranks the instances must take are unbounded.
-- near/ passes the extents back unchanged, one instance.
deeper : Extents s -> Array s Int -> Nat -> Int
deeper e a Z = cast (volume e)
deeper e a (S k) = deeper (e :< 1) (tabulate (e :< 1) (\_ => 0)) k

main : IO ()
main = do
  line <- getLine
  printLn (deeper [<2] (tabulate [<2] (\_ => 1)) (cast line))
