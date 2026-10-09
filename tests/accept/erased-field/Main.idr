module Main
import Prelude

-- A quantity-0 field may have any type.
data Tagged : Type where
  MkTagged : (0 t : Type) -> Int -> Tagged

get : Tagged -> Int
get (MkTagged _ n) = n

main : IO ()
main = printLn (get (MkTagged Integer 9))
