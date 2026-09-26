module Prog

-- rule: SEM-EVAL-3, SEM-Q-1, SEM-Q-2, ELIM-ERASE-2, CORE-INV-5, FE-TR-2
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

public export
main : Int
main = linearId (clamp 7 9 Ok)
