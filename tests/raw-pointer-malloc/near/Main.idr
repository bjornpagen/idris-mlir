module Main

import Prelude
import System.FFI

-- The refused program without the allocation.
scratch : IO ()
scratch = do
  putStrLn "allocated"

main : IO ()
main = scratch
