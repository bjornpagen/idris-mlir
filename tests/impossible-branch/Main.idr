module Main

import Prelude
import Prog

-- The kind is the input's: 'S' is Small, anything else Large.
main : IO ()
main = do
  c <- getChar
  putStrLn (prim__cast_IntString (sizeOf (if c == 'S' then Small else Large)))
