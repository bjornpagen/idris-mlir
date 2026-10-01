-- expect: pragma, line 7
module Main
import Prelude

%default total

%inline
one : Int
one = 1

main : IO ()
main = printLn one
