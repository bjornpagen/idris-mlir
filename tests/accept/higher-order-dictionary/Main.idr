module Main

-- A dictionary built by a function: the implementation of Eq Int is what
-- a function-valued argument returns when applied to (), and a record
-- holds it. The record holds one implementation, the one that application
-- gives, so the program is accepted and compares by it.

record HasEq a where
  constructor MkHasEq
  eqOf : Eq a

viaUnit : (() -> Eq a) -> HasEq a
viaUnit f = MkHasEq (f ())

same : HasEq a -> a -> a -> Bool
same d x y = (==) @{eqOf d} x y

main : IO ()
main = printLn (same (viaUnit (\_ => %search)) (the Int 3) 3)
