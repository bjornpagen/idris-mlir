-- expect: polymorphism, line 11
-- names: Main.T[Int]; Main.T[Builtin.Pair Int Int]
module Main

-- A nested data type: each N holds a T of pairs of what it holds itself,
-- so the instances a value meets are T Int, T (Int, Int), T ((Int, Int),
-- (Int, Int)), ..., as deep as the value, which only the run knows. The
-- instance T Int needs T (Int, Int) for N's field, which needs a larger
-- one again, and the program is refused at N, naming both instances,
-- rather than compiled to a uniform form or left to grow without end.
data T a = L a | N (T (a, a))

depth : T a -> Nat
depth (L _) = 0
depth (N t) = S (depth t)

main : IO ()
main = printLn (depth (the (T Int) (N (L (1, 2)))))
