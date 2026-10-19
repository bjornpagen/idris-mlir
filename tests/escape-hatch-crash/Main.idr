-- expect: escape hatch, line 7
module Main
import Prelude

partial
stop : Int -> Int
stop x = prim__crash Int "no"

partial
main : IO ()
main = printLn (stop 5)
