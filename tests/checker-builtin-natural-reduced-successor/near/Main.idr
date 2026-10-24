module Main

-- The refused program without its `%builtin`: a successor whose type is
-- written through a definition, `Fun N`, is a constructor like any other,
-- and the run prints the naturals the type counts.

import Prelude

Fun : Type -> Type
Fun a = a -> a

data N : Type where
  Zero : N
  Succ : Fun N

toNat : N -> Nat
toNat Zero = Z
toNat (Succ k) = S (toNat k)

main : IO ()
main = do
  printLn (toNat Zero)
  printLn (toNat (Succ (Succ (Succ Zero))))
