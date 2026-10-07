module Main

-- A word that does not lie in the buffer ends the program, as Chez's
-- bytevector access does.

import Prelude
import Data.Buffer

main : IO ()
main = do
  Just buf <- newBuffer 4
    | Nothing => putStrLn "no buffer"
  putStrLn "before"
  printLn !(getBits16 buf 3)
  putStrLn "after"
