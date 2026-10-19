module Main

import Prelude

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

-- The implementation in scope where `found` is used, returned when it is
-- applied to ().
found : Eq a => () -> Eq a
found @{e} _ = e

main : IO ()
main = printLn (same (viaUnit found) (the Int 3) 3)
