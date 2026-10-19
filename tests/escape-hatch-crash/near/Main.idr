module Main
import Prelude

-- The refused program with a value where it crashed.
stop : Int -> Int
stop x = x - 5

main : IO ()
main = printLn (stop 5)
