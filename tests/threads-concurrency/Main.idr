-- expect: threads, line 11
-- message: System.Concurrency.makeMutex
module Main

import Prelude
import System.Concurrency

-- A mutex is for threads, and threads are outside the language: there is
-- no scheduler, and the counting heap has no shared mutable state. The
-- definition that makes one is refused.
guarded : IO ()
guarded = do
  m <- makeMutex
  putStrLn "a mutex"

main : IO ()
main = guarded
