module Main

import Prelude
import Prog

-- The string and the index, a line each. The guard fails outside
-- 0 <= i < length s, the length in characters, not bytes.
partial
main : IO ()
main = do
  s <- getLine
  i <- getLine
  printLn (charAt s (cast i))
