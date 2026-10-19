module Main

import Prelude

prim__shout : String -> PrimIO ()
prim__shout s = toPrim (putStrLn s)

main : IO ()
main = putStrLn "hello"
