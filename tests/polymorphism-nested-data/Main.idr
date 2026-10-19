-- expect: polymorphism, line 13
-- message: growing a by 1 each level
module Main

import Prelude

-- A nested data type: each N holds a T of pairs of what it holds itself,
-- so the instances a value meets are T Int, T (Int, Int), T ((Int, Int),
-- (Int, Int)), ..., as deep as the value, which only the run knows. N's
-- field holds T at (a, a), a constructor above a, so a grows by one at
-- each level, and the program is refused at T's declaration, naming that
-- field, rather than compiled to a uniform form or left to grow without end.
data T a = L a | N (T (a, a))

isLeaf : T a -> Bool
isLeaf (L _) = True
isLeaf (N _) = False

main : IO ()
main = printLn (isLeaf (the (T Int) (N (L (1, 2)))))
