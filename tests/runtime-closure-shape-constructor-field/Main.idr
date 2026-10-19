-- expect: runtime closure, line 27
-- message: Main.MkSize
module Main

import Prelude

-- As implementation-shape-value, with the
-- implementation built of the shaped argument given to a constructor's
-- constraint, which holds one compile-time implementation for the whole
-- program, not a value passed at runtime. near/ holds the Nat and builds
-- the implementation where it is used.

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
