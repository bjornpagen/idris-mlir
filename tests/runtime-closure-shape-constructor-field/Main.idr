module Main

import Prelude

-- As implementation-shape-value, with the implementation built of the
-- shaped argument given to a constructor's constraint: the cell holds
-- which implementation it was given, MkSize with the Nat it was built of,
-- and unbox runs that one's size.

Res : Nat -> Type
Res Z = String
Res (S _) = Nat

interface Size where
  constructor MkSize
  size : Nat

data Box : Type where
  MkBox : Size => Box

unbox : Box -> Nat
unbox (MkBox @{s}) = size @{s}

viaCon : (n : Nat) -> Res n -> Box
viaCon n x = MkBox @{MkSize n}

main : IO ()
main = do
  line <- getLine
  printLn (unbox (viaCon (S (cast line)) 5))
