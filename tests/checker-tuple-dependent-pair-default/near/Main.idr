module Main

-- The refused program with `j` in scope, a Nat. Both readings of
-- `(j ** Tag j)` now elaborate where the expected type is not known: the
-- type `DPair Nat (\j => Tag j)` and the pair `MkDPair j (Tag j)`. The
-- pair leaves its motive, the `p` of `DPair Nat p`, unsolved, and the type
-- leaves nothing open, so the type is taken, the one that adds no
-- constraint.

import Prelude

%default total

data Tag : Nat -> Type where
  MkTag : (n : Nat) -> Tag n

interface Reading t where
  which : (0 _ : t) -> String

Reading Type where
  which _ = "the dependent pair type"

Reading (n : Nat ** Type) where
  which _ = "the dependent pair"

bound : (j : Nat) -> String
bound j = which (j ** Tag j)

main : IO ()
main = putStrLn (bound 2)
