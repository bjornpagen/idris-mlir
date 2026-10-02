-- expect: program, line 6
-- packages: base
module Main

import Prelude
import Debug.Trace

main : IO ()
main = putStrLn "hi"
