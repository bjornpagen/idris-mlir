module Main

-- The refused program with zip' defined.

import Prelude

zip' : List a -> List b -> List (a, b)
zip' (x :: xs) (y :: ys) = (x, y) :: zip' xs ys
zip' _ _ = []

lz : List (Int, Int)
lz = zip' [1, 2] [3, 4]

main : IO ()
main = printLn lz
