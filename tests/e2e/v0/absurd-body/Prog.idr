module Prog

-- rule: CORE-INV-6, FE-TR-4, SEM-DATA-2, IDR-MATCH-2
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

-- A loop longer than compile-time evaluation runs (ELIM-G-16), so its
-- result is known only at runtime and the code below is not folded away.
public export
countdown : Int -> Int
countdown 0 = 5
countdown n = countdown (prim__sub_Int n 1)

public export
main : Int
main = get (A (countdown 100000))
