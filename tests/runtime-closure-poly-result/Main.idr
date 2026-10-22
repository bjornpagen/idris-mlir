module Main

-- A function whose result is a polymorphic function, each clause a lambda:
-- chosen by a constant, applied at a Char, and chosen at run time, applied
-- at an Int.

import Prelude

pick : Bool -> ({0 a : Type} -> a -> List a)
pick True = \x => [x]
pick False = \_ => []

main : IO ()
main = do
  line <- getLine
  printLn (pick True 'a')
  printLn (pick (line == "y") (the Int 7))
