module Main

import Prelude

-- The refused program with Box indexed by a Nat: its type reduces on the
-- argument's shape, a constructor each call's instance knows, where an Int
-- has no shape the instance could take.
Box : Nat -> Type
Box Z = Int
Box (S _) = Char

unbox : (n : Nat) -> Box n -> Int
unbox Z x = x
unbox (S _) c = ord c

main : IO ()
main = do
  putStrLn (prim__cast_IntString (unbox 0 5))
  putStrLn (prim__cast_IntString (unbox 1 'c'))
