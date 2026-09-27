module Main

import Prelude

-- rule: SEM-LAZY-1, ELIM-G-8
partial
pick : Int -> Lazy Int -> Lazy Int -> Int
pick 0 a _ = a
pick _ _ b = b

partial
main : IO ()
main = do
  c <- getChar
  -- The unchosen branch would crash; it is never forced.
  putStrLn (prim__cast_IntString (pick 0 (prim__cast_CharInt c) (prim__div_Int 1 0)))
