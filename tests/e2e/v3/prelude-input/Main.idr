module Main

-- A program that uses only the Prelude, reading input with its getChar:
-- bytes, not UTF-8 scalar values, and 255 at the end of input, as the
-- reference's C getchar gives them.

import Prelude

echo : Int -> IO ()
echo 0 = pure ()
echo k = do
  c <- getChar
  printLn (ord c)
  echo (k - 1)

main : IO ()
main = echo 6
