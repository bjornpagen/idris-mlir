module Prog

-- `never` matches on an empty type, so its whole body is impossible; it is
-- still called from a branch that is never taken.
public export
data Never : Type where

public export
data T = A Int | B Never

public export
never : Never -> Int
never n impossible

public export
get : T -> Int
get (A k) = k
get (B n) = never n

-- A loop on an Int, which Idris does not prove terminating. Idris's
-- evaluator reduces it all the same (Oracle.idr), and so does compile-time
-- evaluation; mlir.check reads the module as emitted, before either.
public export
countdown : Int -> Int
countdown 0 = 5
countdown n = countdown (prim__sub_Int n 1)

public export
main : Int
main = get (A (countdown 100000))
