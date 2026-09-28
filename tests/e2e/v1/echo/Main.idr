module Main

import Prelude

-- Reads and writes alternate in the world chain. The Prelude's getChar reads
-- one byte and returns character 255 at the end of input; its putChar
-- agrees with the reference only on ASCII, so the input
-- is ASCII.
echo : IO ()
echo = do
  c <- getChar
  case prim__eq_Char c '\255' of
    1 => pure ()
    _ => do
      putChar c
      echo

main : IO ()
main = echo
