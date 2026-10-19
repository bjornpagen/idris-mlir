module Main
import Prelude

-- The refused program without the %transform.
slow : Int -> Int
slow x = prim__add_Int x 0

fast : Int -> Int
fast x = x

main : IO ()
main = printLn (slow 3)
