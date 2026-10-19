module Main

import Prelude

-- The refused program with N holding a T of what it holds itself, not of
-- pairs of it: one instance, T Int, however deep a value nests.
data T a = L a | N (T a)

isLeaf : T a -> Bool
isLeaf (L _) = True
isLeaf (N _) = False

depth : T a -> Nat
depth (L _) = 0
depth (N t) = S (depth t)

nest : Nat -> T Int
nest Z = L 1
nest (S k) = N (nest k)

main : IO ()
main = do
  line <- getLine
  let t = nest (integerToNat (cast line))
  printLn (isLeaf t, depth t)
