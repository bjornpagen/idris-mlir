-- exit: 0
-- stdout: one\nzero\n
module Main

-- An indexed data type at runtime: its index is compile-time information,
-- so a value is only its constructor's tag.

import Prelude

data Tagged : Int -> Type where
  Zero : Tagged 0
  One : Tagged 1

name : Tagged n -> String
name Zero = "zero"
name One = "one"

main : IO ()
main = do
  putStrLn (name One)
  putStrLn (name Zero)
