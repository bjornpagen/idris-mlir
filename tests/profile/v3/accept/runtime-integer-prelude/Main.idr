module Main

-- An Integer made from a runtime Int exists at runtime; the cast is the
-- Prelude's.

import Prelude

main : IO ()
main = do
  c <- getChar
  printLn (the Integer (cast (ord c)))
