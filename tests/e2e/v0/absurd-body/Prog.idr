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

public export
main : Int
main = get (A 5)
