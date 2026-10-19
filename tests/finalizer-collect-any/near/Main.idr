module Main

import Prelude

-- The refused program without the finalizer.
register : IO ()
register = do
  putStrLn "registered"

main : IO ()
main = register
