module Main

import IdrisMLIR.IO
import Greeting
import Counter

main : IO ()
main = do
  greet "world"
  putStrLn (prim__cast_IntString (count 5))
