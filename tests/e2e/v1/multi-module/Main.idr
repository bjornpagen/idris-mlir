module Main

import Prelude
import Greeting
import Counter

main : IO ()
main = do
  greet "world"
  putStrLn (prim__cast_IntString (count 5))
