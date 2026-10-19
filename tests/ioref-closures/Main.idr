module Main

-- An IORef of functions: each step writes back the function it read,
-- composed with one more increment, and the last is applied. What a read
-- of the IORef may give is every function made into it or written over
-- it, so the closures in it become one sum that its reads and writes
-- share.

import Prelude
import Data.IORef

compose : IORef (Int -> Int) -> Int -> IO ()
compose ref n =
  if n <= 0 then pure ()
  else do modifyIORef ref (\f => f . (+ 1))
          compose ref (n - 1)

main : IO ()
main = do
  ref <- newIORef id
  compose ref 1000
  f <- readIORef ref
  printLn (f 0)
  printLn (f 5)
