-- expect: polymorphism, line 17
-- message: Main.W passes m through its type family m to Main.T, and nothing bounds what it computes
module Main

import Prelude

-- A family whose value is stuck on its argument in a type-level recursion:
-- G makes three heads of each one it takes off, so what beta makes of the
-- value grows with what the family is applied to, and no height of the
-- value bounds it. W applies the family, and the program is refused at T,
-- whose argument nothing bounds.

G : Type -> Type
G (List a) = List (List (List (G a)))
G a = a

T : (0 t : Type) -> Nat -> Nat
T t n = n + 1

W : (0 m : Type -> Type) -> Nat -> Nat
W m n = T (m (List (List (List (List (List (List (List (List (List (List Int))))))))))) n

main : IO ()
main = printLn (W (\y => Pair (G y) Int) 3)
