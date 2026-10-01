-- expect: pragma, line 5
module Main
import Prelude

%inline
one : Int
one = 1

main : IO ()
main = printLn one
