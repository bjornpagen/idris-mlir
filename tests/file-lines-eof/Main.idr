module Main

-- Lines until the end of input, as C reads them: fEOF is set only once a
-- read met the end, so an input that ends in a newline yields one empty
-- line after its last, and one that does not ends on its last line.

import Prelude
import System.File

lines : Int -> IO ()
lines n = do
  ended <- fEOF stdin
  if ended
     then printLn n
     else do
       l <- getLine
       putStrLn (show (length l) ++ ":" ++ l)
       lines (n + 1)

main : IO ()
main = lines 0
