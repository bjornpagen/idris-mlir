module Main

import Prelude

-- The implementation describe is given is chosen by a covering function,
-- which Idris does not prove ends, so no compile-time reduction runs it:
-- the choice is made when the program runs, between the two
-- implementations the program fixes, and describe runs the method of the
-- one chosen.

interface Name a where
  name : a -> String

[nameA] Name Int where
  name _ = "A"

[nameB] Name Int where
  name _ = "B"

covering
loopy : Int -> Int
loopy n = if n >= 3 then n else loopy (n + 1)

covering
chosen : Name Int
chosen = if loopy 0 == 3 then nameA else nameB

describe : Name Int => Int -> String
describe x = name x ++ "!"

covering
main : IO ()
main = putStrLn (describe @{chosen} 1)
