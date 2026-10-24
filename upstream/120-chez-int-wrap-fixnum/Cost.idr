module Cost

-- The cost of a fixed-width integer step on Chez, against a natural's: a
-- loop of ten million steps of each, with the process's CPU time per
-- step. Every Int and Bits64 step ends in the support's wrap to its
-- width; a Nat step is the host's integer operation alone.

import Data.Bits
import System.Clock

cpu : IO Integer
cpu = do t <- clockTime Process; pure (seconds t * 1000000000 + nanoseconds t)

timed : String -> Lazy Integer -> IO ()
timed name v = do
  t0 <- cpu
  let r = force v
  t1 <- cpu
  let tenths = (t1 - t0) `div` 1000000
  putStrLn (name ++ ": " ++ show (tenths `div` 10) ++ "." ++ show (tenths `mod` 10) ++ " ns a step (" ++ show r ++ ")")

natLoop : Nat -> Nat -> Nat -> Nat
natLoop Z acc k = acc
natLoop (S n) acc k = natLoop n (acc + k * 3) (S k)

intLoop : Nat -> Int -> Int -> Int
intLoop Z acc k = acc
intLoop (S n) acc k = intLoop n (acc + k * 3) (k + 1)

andLoop : Nat -> Int -> Int -> Int
andLoop Z acc k = acc
andLoop (S n) acc k = andLoop n (acc + (k .&. 1023)) (k + 1)

bitsLoop : Nat -> Bits64 -> Bits64 -> Bits64
bitsLoop Z acc k = acc
bitsLoop (S n) acc k = bitsLoop n (acc + k * 3) (k + 1)

main : IO ()
main = do
  let n = 10000000
  timed "Nat add and multiply" (natToInteger (natLoop n 0 0))
  timed "Int add and multiply" (cast (intLoop n 0 0))
  timed "Int and, add" (cast (andLoop n 0 0))
  timed "Bits64 add and multiply" (cast (bitsLoop n 0 0))
