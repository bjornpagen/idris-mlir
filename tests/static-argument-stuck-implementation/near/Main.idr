module Main

import Prelude

-- The refused program choosing by a total function, which reduces at
-- compile time: chosen is nameA.

interface Name a where
  name : a -> String

[nameA] Name Int where
  name _ = "A"

[nameB] Name Int where
  name _ = "B"

loopy : Nat -> Nat
loopy Z = 3
loopy (S k) = loopy k

chosen : Name Int
chosen = if loopy 2 == 3 then nameA else nameB

describe : Name Int => Int -> String
describe x = name x ++ "!"

main : IO ()
main = putStrLn (describe @{chosen} 1)
