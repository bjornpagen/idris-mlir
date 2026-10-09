module Main

-- Integer's shifts and bits on values read at run time, which compile-time
-- evaluation cannot see, so the runtime computes every one. A case is three
-- lines: what to compute, the Integer, and the amount. `shl` and `shr` are
-- the primitives on any amount: a left shift multiplies by 2^amount, a right
-- shift is the floor of the quotient by it, and a negative amount shifts the
-- other way. `bits` is base's Data.Bits at a Nat index.

import Prelude
import Data.Bits

bits : Integer -> Nat -> String
bits x i =
  show (shiftL x i) ++ " " ++ show (shiftR x i) ++ " " ++ show (testBit x i)
    ++ " " ++ show (the Integer (bit i)) ++ " " ++ show (setBit x i)
    ++ " " ++ show (clearBit x i) ++ " " ++ show (complement x)

answer : String -> Integer -> Integer -> String
answer op x s =
  if op == "shl" then show (prim__shl_Integer x s)
  else if op == "shr" then show (prim__shr_Integer x s)
  else bits x (integerToNat s)

cases : IO ()
cases = do
  op <- getLine
  if op == ""
     then pure ()
     else do
       x <- getLine
       s <- getLine
       putStrLn (answer op (cast x) (cast s))
       cases

main : IO ()
main = cases
