-- expect: polymorphism, line 13
-- message: a shape whose rank no analysis fixes
module Main
import Prelude
import Array

-- A tower's floors hold arrays of every rank: a Floor of shape s holds an
-- array of s and a tower of s :< 1. A tensor's rank is its type, so the
-- floors would need a type each, without bound. near/ keeps every floor at
-- the tower's own shape.
data Tower : Shape -> Type where
  Top : Tower s
  Floor : Array s Int -> Tower (s :< 1) -> Tower s

base : Tower s -> Int
base Top = 0
base (Floor a _) = 1

main : IO ()
main = do
  line <- getLine
  printLn (base (Floor (tabulate [<2] (\_ => cast line)) Top))
