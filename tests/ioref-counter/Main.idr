module Main

-- A counter in an IORef: base's newIORef, modifyIORef, readIORef and
-- writeIORef, the one cell of an array of rank 0 read and written in the
-- world's order. The sum of 1 to 100000, then a value written over it.

import Prelude
import Data.IORef

count : IORef Int -> Int -> IO ()
count ref n =
  if n <= 0 then pure ()
  else do modifyIORef ref (+ n)
          count ref (n - 1)

main : IO ()
main = do
  ref <- newIORef 0
  count ref 100000
  readIORef ref >>= printLn
  writeIORef ref 7
  readIORef ref >>= printLn
