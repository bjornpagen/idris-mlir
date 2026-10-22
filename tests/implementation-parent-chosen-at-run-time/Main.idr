module Main

-- An implementation whose parent implementation is chosen at run time, and
-- a function that takes it apart down to its parent's method: the parent
-- is a closed sum of the two the program gives, and the call dispatches on
-- it.

import Prelude
import Data.String

interface Named a where
  constructor MkNamed
  nameOf : a -> String

interface Named a => Shown a where
  constructor MkShown
  shownOf : a -> String

shownWith : Bool -> Shown String
shownWith loud = MkShown @{if loud then MkNamed toUpper else MkNamed id} (\s => s)

nested : Shown a => a -> String
nested @{MkShown @{MkNamed nm} _} x = nm x

main : IO ()
main = do
  line <- getLine
  putStrLn (nested @{shownWith (line == "loud")} "hello")
