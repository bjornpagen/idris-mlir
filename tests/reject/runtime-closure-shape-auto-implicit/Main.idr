-- expect: runtime closure, line 23
-- message: an implementation chosen at runtime: (Main.MkSize (Prelude.Types.S [__]))
module Main

import Prelude

-- The type of viaFun depends on n (through Res), so each call's instance
-- knows the shape of its argument: `S _` for `S k`. What the shape does not
-- say is a runtime value, so building an implementation of it, a
-- compile-time value, is an implementation chosen at runtime.

Res : Nat -> Type
Res Z = String
Res (S _) = Nat

interface Size where
  constructor MkSize
  size : Nat

pick : Size => Nat
pick = size

viaFun : (n : Nat) -> Res n -> Nat
viaFun n x = pick @{MkSize n}

main : IO ()
main = do
  line <- getLine
  printLn (viaFun (S (cast line)) 5)
