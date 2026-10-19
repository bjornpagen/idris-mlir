module Main

-- A growable linear vector of records, written in a loop where a test
-- against the size guards each write (unionfind's shape), so one path
-- writes the vector and the other gives it back as it is: the array of
-- records, a field of the vector's data type, is used once on each path,
-- threaded at quantity 1. The sums of the two fields after the vector is
-- frozen.

import Prelude
import Data.So
import Linear.Notation
import Array
import Linear.Vec

record P where
  constructor MkP
  x : Int
  y : Int

-- The vector with `e` at `i`; as it was past the end.
writeAt : {k : Nat} -> (1 _ : Vec k P) -> Nat -> P -> Vec k P
writeAt s i e = case choose (i < k) of
  Left inside => Vec.write s (natToFinLt i @{inside}) e
  Right _ => s

-- Record i is (i, 1), for every i from the first given to the size.
go : {k : Nat} -> (1 _ : Vec k P) -> Nat -> Vec k P
go s i = case choose (i < k) of
  Left _ => go (writeAt s i (MkP (cast i) 1)) (S i)
  Right _ => s

main : IO ()
main = do
  line <- getLine
  let c = the Int (cast line)
  let MkBang (sx, sy) = withVec (cast c) (MkP 0 0) (\v =>
        let MkBang f = Vec.freeze (go v 0)
        in MkBang (sum (map (.x) f), sum (map (.y) f)))
  printLn sx
  printLn sy
