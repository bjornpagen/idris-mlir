-- expect: pragma, line 9
-- message: %inline
module Main
import Prelude

main : IO ()
main = printLn (the Int 0)

%inline
unused : Int
unused = 1
