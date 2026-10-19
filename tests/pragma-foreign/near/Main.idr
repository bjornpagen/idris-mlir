module Main

import Prelude

puts : String -> PrimIO Int
puts s = toPrim (do putStrLn s; pure 0)

main : IO ()
main = putStrLn "hello"
