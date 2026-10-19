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

-- Two lines, compared as Ints and as Strings, each by the implementation
-- its record holds: "3" and "03" are one Int and two strings.
main : IO ()
main = do
  x <- getLine
  y <- getLine
  printLn (same (viaUnit found) (the Int (cast x)) (cast y))
  printLn (same (viaUnit found) x y)
