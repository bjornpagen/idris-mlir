module Main

import Prelude
import Prog

main : IO ()
main = do
  c <- getChar
  printLn !(readPast (cast (ord c - ord '0')))
