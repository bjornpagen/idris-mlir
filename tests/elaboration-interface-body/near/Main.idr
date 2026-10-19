module Main

-- The refused program with the data declaration outside the interface.

import Prelude

interface Describe a where
  describe : a -> String

data Colour = Red | Green

main : IO ()
main = putStrLn "main"
