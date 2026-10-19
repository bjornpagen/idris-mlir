-- expect: escape hatch, line 7
-- message: Data/Evil.idr:7:
-- A totality assertion in a user module named like a module of base: it is
-- the user's escape hatch, not a trusted library's. The line is
-- Data/Evil.idr's, which the message pins.
module Main

import Prelude
import Data.Evil

main : IO ()
main = do
  line <- getLine
  printLn (count (cast line))
