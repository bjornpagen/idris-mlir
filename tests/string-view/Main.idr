module Main

import Prelude
import Data.String

-- base's `strM` views a string as empty or as its first character and the
-- rest. Its body gives the second view the string's own index by
-- `believe_me`, which the runtime's head and tail make good, so its calls
-- are that view, the runtime's; `letters` matches on it, and base's `trim`
-- and `parseInteger` see their strings through it.

covering
letters : String -> List Char
letters s with (strM s)
  letters "" | StrNil = []
  letters (strCons c cs) | StrCons c cs = c :: letters cs

main : IO ()
main = do
  printLn (letters "abc")
  printLn (letters "")
  putStrLn ("[" ++ trim "  ab c  " ++ "]")
  printLn (the (Maybe Integer) (parseInteger " -12 "))
  printLn (the (Maybe Integer) (parseInteger "1x"))
