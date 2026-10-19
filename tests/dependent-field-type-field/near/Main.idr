module Main
import Prelude

-- The refused program with the type field erased: a field of quantity 0
-- has no runtime value, so its representation depends on nothing.
data Box : Type where
  MkBox : (0 _ : Type) -> Box

size : Box -> Int
size (MkBox _) = 1

main : IO ()
main = printLn (size (MkBox Int))
