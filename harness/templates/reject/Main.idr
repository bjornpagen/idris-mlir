-- expect: pragma, line 5
module Main
import Prelude

%inline
f : Int -> Int
f x = x + 1

main : IO ()
main = printLn (f 1)
