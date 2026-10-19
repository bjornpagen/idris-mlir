module Main

import Prelude

-- `putStrLn "first"; let q = ...; ...` is `putStrLn "first" >> (let q = ...
-- in Delay ...)`: q, which divides by the digit on stdin, is computed after
-- "first" is written, not when the action after `>>` is built, so a digit
-- of 0 crashes after "first" and any other prints both lines.
partial
main : IO ()
main = do
  c <- getChar
  putStrLn "first"
  let q = prim__div_Int 10 (prim__sub_Int (prim__cast_CharInt c) 48)
  putStrLn (prim__cast_IntString q)
