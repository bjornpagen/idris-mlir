module Main

-- An indexed data type at runtime: its index is compile-time information,
-- so a value is only its constructor's tag, also when the input chooses it.

import Prelude

data Tagged : Int -> Type where
  Zero : Tagged 0
  One : Tagged 1

name : Tagged n -> String
name Zero = "zero"
name One = "one"

-- A tag whose index is erased, so which one it is can be data.
data Some : Type where
  MkSome : {0 n : Int} -> Tagged n -> Some

nameOf : Some -> String
nameOf (MkSome t) = name t

main : IO ()
main = do
  putStrLn (name One)
  putStrLn (name Zero)
  c <- getChar
  putStrLn (nameOf (if c == '1' then MkSome One else MkSome Zero))
