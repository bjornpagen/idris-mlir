-- Debug.Trace is a module of base, so the package makes it trusted.
-- Its trace runs the IO where the value is demanded.
module Main

import Prelude
import Debug.Trace

main : IO ()
main = putStrLn (trace "traced" "hi")
