module Main

-- Covering but not terminating: accepted, compiled, never run.
covering
spin : Int -> Int
spin x = spin x

main : Int
main = spin 0
