-- expect: PROF-DATA-5 line 6
module Main

import IdrisMLIR.IO

data Tagged : Int -> Type where
  Zero : Tagged 0
  One : Tagged 1

name : Tagged n -> String
name Zero = "zero"
name One = "one"

main : IO ()
main = putStrLn (name One)
