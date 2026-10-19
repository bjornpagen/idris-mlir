-- Debug.Trace is a module of base, so the package makes it trusted.
-- Its trace runs the IO where the value is demanded: after the output
-- before it and before the line the value is written in, and never in a
-- branch that is not taken. The branch is chosen by the input, so no fold
-- decides it.
module Main

import Prelude
import Debug.Trace

main : IO ()
main = do
  putStrLn "first"
  putStrLn (trace "traced" "hi")
  line <- getLine
  putStrLn (if line == "" then trace "empty" "none" else trace ("read " ++ line) line)
  putStrLn "last"
