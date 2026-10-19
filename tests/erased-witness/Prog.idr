module Prog

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

-- A loop on an Int, which Idris does not prove terminating: a closed call
-- of it runs at run time.
public export
countdown : Int -> Int
countdown 0 = 7
countdown n = countdown (prim__sub_Int n 1)

public export
result : Int
result = linearId (clamp (countdown 100000) 9 Ok)
