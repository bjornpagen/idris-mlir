module Main
import Prelude
import Array

-- The refused program with every floor at the tower's own shape: the sum
-- of the floors' sums.
data Tower : Shape -> Type where
  Top : Tower s
  Floor : Array s Int -> Tower s -> Tower s

held : Tower s -> Int
held Top = 0
held (Floor a t) = sum a + held t

main : IO ()
main = do
  line <- getLine
  let k = the Int (cast line)
  printLn (held (Floor (tabulate [<2] (\_ => k)) (Floor (tabulate [<2] (\_ => 1)) Top)))
