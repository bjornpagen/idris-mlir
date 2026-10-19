module Main

import Prelude

Res : Nat -> Type
Res Z = String
Res (S _) = Nat

interface Size where
  constructor MkSize
  size : Nat

data Box : Type where
  MkBox : Nat -> Box

unbox : Box -> Nat
unbox (MkBox n) = size @{MkSize n}

viaCon : (n : Nat) -> Res n -> Box
viaCon n x = MkBox n

main : IO ()
main = do
  line <- getLine
  printLn (unbox (viaCon (S (cast line)) 5))
