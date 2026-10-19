module Main

import Prelude
import System.Concurrency

-- The refused program without the mutex.
guarded : IO ()
guarded = do
  putStrLn "a mutex"

main : IO ()
main = guarded
