module Main

-- Two readings of the monotonic clock, printed only as whether the second
-- is not earlier than the first, since a reading is the host's. The two
-- collector clocks are optional in base, and no collector runs: each
-- gives Nothing.

import Prelude
import System.Clock

main : IO ()
main = do
  a <- clockTime Monotonic
  b <- clockTime Monotonic
  putStrLn ("monotonic, not earlier: " ++ show (b >= a))
  gcCpu <- clockTime GCCPU
  putStrLn (show GCCPU ++ ": " ++ maybe "Nothing" (const "a reading") gcCpu)
  gcReal <- clockTime GCReal
  putStrLn (show GCReal ++ ": " ++ maybe "Nothing" (const "a reading") gcReal)
