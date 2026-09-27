module Prog

-- rule: FE-TR-1, SEM-EVAL-3, SEM-Q-1, SEM-Q-2, ELIM-ERASE-2, CORE-INV-5, FE-TR-2
-- A proof argument and a linear argument: neither has a runtime cost.
public export
data LTE : Int -> Int -> Type where
  Ok : LTE a b

public export
clamp : (x : Int) -> (hi : Int) -> (0 _ : LTE x hi) -> Int
clamp x hi _ = x

public export
linearId : (1 x : Int) -> Int
linearId x = x

-- A recursive function's result is known only at runtime once it recurses
-- (ELIM-G-12 unfolds a call with constant arguments once), so clamp and
-- linearId are residual functions with their erased and linear parameters.
public export
countdown : Int -> Int
countdown 0 = 7
countdown n = countdown (prim__sub_Int n 1)

public export
main : Int
main = linearId (clamp (countdown 3) 9 Ok)
