module Main

import Prelude

partial
pick : Int -> Lazy Int -> Lazy Int -> Int
pick 0 a _ = a
pick _ _ b = b

-- The selector is the input's character less 'A'. On each line one branch
-- divides by zero at some selector, 0 on the first line and 1 on the
-- second, and pick never chooses it there: the unchosen branch is never
-- forced, and the chosen one is.
partial
main : IO ()
main = do
  c <- getChar
  let sel = prim__sub_Int (prim__cast_CharInt c) 65
  putStrLn (prim__cast_IntString (pick sel (prim__cast_CharInt c) (prim__div_Int 100 sel)))
  putStrLn (prim__cast_IntString (pick sel (prim__div_Int 100 (prim__sub_Int sel 1)) (prim__cast_CharInt c)))
