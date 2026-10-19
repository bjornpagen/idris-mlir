-- expect: dependent field, line 7
-- message: Main.MkBox
module Main
import Prelude

data Box : Type where
  MkBox : Type -> Box

size : Box -> Int
size (MkBox _) = 1

main : IO ()
main = printLn (size (MkBox Int))
