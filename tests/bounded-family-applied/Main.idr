module Main

import Prelude

-- A type parameter of a function kind applied in a static argument: at an
-- instance the lambda is beta-reduced, so the key holds the lambda's body
-- around the argument.
T : (0 t : Type) -> Nat -> Nat
T t n = n + 1

W : (0 m : Type -> Type) -> (0 x : Type) -> Nat -> Nat
W m x n = T (m x) n

main : IO ()
main = printLn (W (\y => List (List (List (List (List y))))) (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (Int))))))))))))))))))))))))))))))) 3)

