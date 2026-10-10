-- expect: runtime closure, line 25
-- message: an implementation chosen at runtime: (Main.MkSize (Prelude.Types.S [__]))
module Main

import Prelude

-- As runtime-closure-shape-auto-implicit, with the implementation built of
-- the shaped argument given to a constructor's constraint, which holds a
-- compile-time value.

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
