module Main

import Prelude
import System.Signal

-- The refused program without the signal: the alternative it took when
-- the signal was not collected.
watch : IO ()
watch = do
  putStrLn "not collected"

main : IO ()
main = watch
