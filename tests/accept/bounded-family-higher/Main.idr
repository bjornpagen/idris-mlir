module Main

-- A family whose value applies its own family argument to a closed type,
-- given a definition with fewer arguments than it takes: beta at the
-- instance makes F Int, twenty heads above Int. Each family is read as its
-- meaning, and an argument applied to closed arguments as many as it takes
-- is no higher than its value above them, so the bound on T's argument
-- covers it.
T : (0 t : Type) -> Nat -> Nat
T t n = n + 1

W : (0 m : (Type -> Type) -> Type) -> (0 f : Type -> Type) -> Nat -> Nat
W m f n = T (m f) n

F : Type -> Type
F a = List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List (List a)))))))))))))))))))

main : IO ()
main = printLn (W (\g => g Int) F 3)
