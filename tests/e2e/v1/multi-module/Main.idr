module Main

import Prelude
-- rule: FE-TTC-2, PROF-PROG-4 (every module is loaded from TTC under -o)
import Greeting
import Counter

main : IO ()
main = do
  greet "world"
  putStrLn (prim__cast_IntString (count 5))
