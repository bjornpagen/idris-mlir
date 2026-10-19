module Main
import Prelude

f : Int -> Int
f x = x + 1

main : IO ()
main = printLn (f 1)
