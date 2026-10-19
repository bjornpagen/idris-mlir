module Main

-- The refused program without the assertion in Data.Evil.

import Prelude
import Data.Evil

main : IO ()
main = do
  line <- getLine
  printLn (count (cast line))
