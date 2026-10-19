-- expect: pragma, line 8
module Main
import Prelude

main : IO ()
main = printLn (the Int 0)

%inline
unused : Int
unused = 1
