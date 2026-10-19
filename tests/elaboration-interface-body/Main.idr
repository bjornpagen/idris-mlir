-- expect: elaboration, line 11
module Main

-- An interface body holds signatures and default definitions. A data
-- declaration there is refused where it is written, not dropped.

import Prelude

interface Describe a where
  describe : a -> String
  data Colour = Red | Green

main : IO ()
main = putStrLn "main"
