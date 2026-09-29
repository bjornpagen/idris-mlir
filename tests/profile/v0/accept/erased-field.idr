-- exit: 9
module Main

-- A quantity-0 field may have any type.
data Tagged : Type where
  MkTagged : (0 t : Type) -> Int -> Tagged

get : Tagged -> Int
get (MkTagged _ n) = n

main : Int
main = get (MkTagged Integer 9)
