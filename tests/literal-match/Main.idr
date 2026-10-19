module Main

import Prelude
import Prog

-- classify, loaded from its TTC, of the byte on stdin (255 at the end of
-- input) and of one less: each literal matches itself alone, and its
-- neighbours and -1 take the default. The two results are one line, its
-- only use output, which output fusion writes as it goes: nothing is
-- allocated.
main : IO ()
main = do
  c <- getChar
  let x = prim__cast_CharInt c
  putStrLn (prim__strAppend (prim__cast_IntString (classify x))
             (prim__strAppend " " (prim__cast_IntString (classify (prim__sub_Int x 1)))))
