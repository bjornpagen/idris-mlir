module Main

-- The Prelude's getLine: a line without its end, cut at the first carriage
-- return, the empty string at the end of input; a byte that is not UTF-8
-- is read as U+FFFD, as the reference decodes it.

import Prelude

lines : Int -> IO ()
lines n = do
  l <- getLine
  if l == ""
     then printLn n
     else do
       putStrLn (show (length l) ++ ":" ++ l)
       lines (n + 1)

main : IO ()
main = lines 0
