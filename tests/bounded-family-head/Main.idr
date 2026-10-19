module Main

import Prelude

-- A family whose value is a type constructor: the node is split by it, and
-- the applied family reads as the constructor applied.
T : (0 t : Type) -> Nat -> Nat
T t n = n + 1

W : (0 m : Type -> Type) -> (0 x : Type) -> Nat -> Nat
W m x n = T (m x) n

main : IO ()
main = printLn (W List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (Int))))))))))))))))))))))))))))))) 3)
