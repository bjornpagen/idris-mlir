module Main

import Prelude

-- rule: SEM-IO-4, SEM-CRASH-1
-- The divisor is the digit on stdin, 0, known only at runtime.
partial
main : IO ()
main = do
  putStrLn "first"
  c <- getChar
  putStrLn (prim__cast_IntString (prim__div_Int 10 (prim__sub_Int (prim__cast_CharInt c) 48)))
