-- expect: runtime closure, line 19
-- message: an implementation chosen at runtime
module Main

import Prelude

-- The type of viaFun depends on n (through Res), so each call's instance
-- knows the shape of its argument: `S _` for `S k`. What the shape does not
-- say is a runtime value, so passing n on as an auto-implicit argument, a
-- compile-time value, is an implementation chosen at runtime.

Res : Nat -> Type
Res Z = String
Res (S _) = Nat

pick : {auto v : Nat} -> Nat
pick {v} = v

viaFun : (n : Nat) -> Res n -> Nat
viaFun n x = pick {v = n}

main : IO ()
main = do
  line <- getLine
  printLn (viaFun (S (cast line)) 5)
