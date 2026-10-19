module Main
import Prelude

-- A quantity-0 field may have any type.
data Tagged : Type where
  MkTagged : (0 t : Type) -> Int -> Tagged

get : Tagged -> Int
get (MkTagged _ n) = n

-- Fields erased at a data type, a function type, Type itself and an empty
-- type, beside Ints across the word's range.
main : IO ()
main = do
  printLn (get (MkTagged Integer 9))
  printLn (map get [ MkTagged (Int -> Int) (-1), MkTagged Type 0
                   , MkTagged Void 9223372036854775807, MkTagged (List Nat) (-9223372036854775808) ])
