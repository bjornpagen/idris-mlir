module Main

-- Readings of the monotonic clock, printed only as whether each is not
-- earlier than the one before, since a reading is the host's: two, then a
-- hundred thousand in a row. The two collector clocks are optional in
-- base, and no collector runs: each gives Nothing.

import Prelude
import System.Clock

-- Whether the next n readings are each not earlier than the one before.
ordered : Clock Monotonic -> Int -> IO Bool
ordered before n =
  if n <= 0
     then pure True
     else do
       after <- clockTime Monotonic
       if after >= before then ordered after (n - 1) else pure False

main : IO ()
main = do
  a <- clockTime Monotonic
  b <- clockTime Monotonic
  putStrLn ("monotonic, not earlier: " ++ show (b >= a))
  c <- clockTime Monotonic
  putStrLn ("monotonic over 100000 readings: " ++ show !(ordered c 100000))
  gcCpu <- clockTime GCCPU
  putStrLn (show GCCPU ++ ": " ++ maybe "Nothing" (const "a reading") gcCpu)
  gcReal <- clockTime GCReal
  putStrLn (show GCReal ++ ": " ++ maybe "Nothing" (const "a reading") gcReal)
