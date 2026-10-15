-- expect: idris, line 12
module Main

-- An interface body holds signatures and default definitions. A data
-- declaration there is refused where it is written, not dropped and then
-- missed at its first use.

import Prelude

interface Describe a where
  describe : a -> String
  data Colour = Red | Green

paint : Colour
paint = Red

main : IO ()
main = putStrLn "unreached"
