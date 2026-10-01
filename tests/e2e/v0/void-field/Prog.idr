module Prog

public export
data Never : Type where

public export
data T = A Int | B Never

public export
get : T -> Int
get (A n) = n
get (B _) = 0

public export
result : Int
result = get (A 3)
