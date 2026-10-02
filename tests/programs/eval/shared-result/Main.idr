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

-- The walk goes left or right by the input, so the tree is needed at
-- runtime: evaluation cannot fold it away.
walk : Char -> T -> Int
walk c L = 0
walk c (N l r) = 1 + walk c (if c == 'a' then l else r)

main : IO ()
main = do
  c <- getChar
  printLn (walk c (mk 40))
