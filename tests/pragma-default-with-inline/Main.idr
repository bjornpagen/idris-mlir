-- expect: pragma, line 8
-- message: %inline
module Main
import Prelude

%default total

%inline
one : Int
one = 1

main : IO ()
main = printLn one
