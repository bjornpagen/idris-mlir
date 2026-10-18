module Main

-- A family whose value is a definition given fewer arguments than it
-- takes: the key holds F, and beta at the instance gives F its argument,
-- so T's argument is what F's body makes of x, twenty heads above it. The
-- family is read as its meaning, F's body over its argument, so the bound
-- on T's argument covers it.
T : (0 t : Type) -> Nat -> Nat
T t n = n + 1

W : (0 m : Type -> Type) -> (0 x : Type) -> Nat -> Nat
W m x n = T (m x) n

F : Type -> Type
F a = List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List a)))))))))))))))))))

main : IO ()
main = printLn (W F Int 3)
