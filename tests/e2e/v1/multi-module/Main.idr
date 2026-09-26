module Main

import IdrisMLIR.IO
-- rule: FE-TTC-2 (every module is loaded from TTC under -o)
import Greeting
import Counter

main : IO ()
main = do
  greet "world"
  putStrLn (prim__cast_IntString (count 5))
