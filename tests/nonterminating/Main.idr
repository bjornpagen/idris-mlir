module Main
import Prelude

-- Covering but not terminating: accepted, compiled, never run.
covering
spin : Int -> Int
spin x = spin x

main : IO ()
main = printLn (spin 0)
