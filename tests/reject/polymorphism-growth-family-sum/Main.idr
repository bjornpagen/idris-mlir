-- expect: polymorphism, line 15
-- message: Main.W passes m through its type family m to Main.T, and nothing bounds what it computes
module Main

import Prelude

-- A family whose value applies its family argument to what holds its
-- other argument: beta makes g (List x), which stands as high as g's
-- value and x together. That is a sum of two heights, which no height of
-- the value bounds and no arc states, as with a family applied to what
-- holds a marker. W applies the family, and the program is refused at T,
-- though its instances are finite: a sum of two arguments' heights is no
-- weight the check states (a known limit).

T : (0 t : Type) -> Nat -> Nat
T t n = n + 1

W : (0 m : (Type -> Type) -> Type -> Type) -> Nat -> Nat
W m n = T (m (\y => List (List (List (List (List (List (List (List (List (List y)))))))))) (List (List (List (List (List (List (List (List (List (List Int))))))))))) n

main : IO ()
main = printLn (W (\g, x => g (List x)) 3)
