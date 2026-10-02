-- expect: runtime closure, line 20
-- message: an implementation chosen at runtime
module Main

import Prelude

-- As runtime-closure-shape-auto-implicit, with the shaped argument given to
-- a constructor's auto-implicit field, which holds a compile-time value.

Res : Nat -> Type
Res Z = String
Res (S _) = Nat

data Box : Type where
  MkBox : {auto v : Nat} -> Box

unbox : Box -> Nat
unbox (MkBox {v}) = v

viaCon : (n : Nat) -> Res n -> Box
viaCon n x = MkBox {v = n}

main : IO ()
main = do
  line <- getLine
  printLn (unbox (viaCon (S (cast line)) 5))
