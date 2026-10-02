module Main

-- An Int written as a byte must be one: 256 ends the program, as Chez's
-- bytevector-u8-set! refuses it.

import Prelude
import Data.Buffer

main : IO ()
main = do
  Just buf <- newBuffer 4
    | Nothing => putStrLn "no buffer"
  putStrLn "before"
  setByte buf 1 256
  putStrLn "after"
