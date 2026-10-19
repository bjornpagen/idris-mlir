module Main

-- A word that does not lie in the buffer ends the program, explicitly, at
-- the access, after the output before it; a word that does lie in it is
-- read. The offset is the digit on stdin, so no fold decides which: a
-- two-byte word of a four-byte buffer lies in it at 0, 1 and 2, not at 3,
-- nor at 207, the offset the end of input gives (getChar's 255, less '0').

import Prelude
import Data.Buffer

main : IO ()
main = do
  c <- getChar
  let at = ord c - ord '0'
  Just buf <- newBuffer 4
    | Nothing => putStrLn "no buffer"
  putStrLn "before"
  printLn !(getBits16 buf at)
  putStrLn "after"
