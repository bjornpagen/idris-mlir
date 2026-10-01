-- expect: dependent field, line 6
module Main
import Prelude

data Box : Type where
  MkBox : Type -> Box

size : Box -> Int
size (MkBox _) = 1

main : IO ()
main = printLn (size (MkBox Int))
