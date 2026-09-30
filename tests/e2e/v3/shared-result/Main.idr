module Main

import Prelude

-- `mk 40` is total and closed, so it is evaluated: a tree of 2^41 - 1
-- nodes with 41 distinct ones, since each level is the same subtree twice.
-- The result keeps that sharing from the evaluation to the executable, so
-- the compilation takes the time of 41 nodes; a copy of the tree would
-- never finish.
data T = L | N T T

mk : Nat -> T
mk Z = L
mk (S k) = let t = mk k in N t t

depth : T -> Int
depth L = 0
depth (N l _) = 1 + depth l

main : IO ()
main = do
  c <- getChar
  printLn (depth (if c == 'a' then L else mk 40))
