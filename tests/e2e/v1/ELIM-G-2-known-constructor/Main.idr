module Main

import IdrisMLIR.IO

data Opt : Type where
  None : Opt
  Some : (Int -> Int) -> Opt

apply : Opt -> Int -> Int
apply None x = x
apply (Some f) x = f x

-- The number comes from stdin, so that the call is not evaluated at compile
-- time (ELIM-G-12).
partial
main : IO ()
main = do
  c <- getChar
  putStrLn (prim__cast_IntString (apply (Some (prim__add_Int 10)) (prim__sub_Int (prim__cast_CharInt c) 48)))
