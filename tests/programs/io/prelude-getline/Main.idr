module Main

-- The Prelude's getLine: a line without its end, the '\n' or the "\r\n"
-- it ends with, so a '\r' anywhere else stays in the line; the rest of the
-- input when no '\n' is left, and the empty string at the end of input; a
-- byte that is not UTF-8 is read as U+FFFD. Upstream's C support, which
-- both stock backends call, cuts a line at its first '\r' (chez-differs).

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
