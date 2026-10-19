module Main

import Prelude

-- The type of viaFun depends on n (through Res), so each call's instance
-- knows the shape of its argument: `S _` for `S k`. What the shape does not
-- say is a runtime value, and the implementation built of it, `MkSize n`,
-- closes over that value: which implementation it is stays known at
-- compile time, and only `n` is passed at runtime, as with
-- `Show (Term names)` and its scope (implementation-runtime-scope). Held
-- in a constructor's dictionary field it would have to be one
-- implementation for the whole program, which is refused
-- (runtime-closure-shape-constructor-field).

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
