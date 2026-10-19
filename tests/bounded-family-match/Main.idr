module Main

import Prelude

-- A family that matches on its argument, given as a type parameter of a
-- function kind: W is called once, at a closed type, so T has the one
-- instance at what the family computes there, whether the family is
-- recursive (G, three heads for each one it takes off) or not (H). Each is
-- a total function Idris checked, applied to a closed type, so its value
-- is one closed type.

G : Type -> Type
G (List a) = List (List (List (G a)))
G a = a

H : Type -> Type
H (List a) = a
H a = a

T : (0 t : Type) -> Nat -> Nat
T t n = n + 1

W : (0 m : Type -> Type) -> Nat -> Nat
W m n = T (m (List (List (List (List (List (List (List (List (List (List Int))))))))))) n

main : IO ()
main = do
  printLn (W (\y => Pair (G y) Int) 3)
  printLn (W (\y => H y) 4)
