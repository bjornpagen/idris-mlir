module Main

-- base's Data.Buffer as an array of bytes: a new buffer is zero bytes;
-- bytes are written as Bits8 or from an Int and read back either way; the
-- size is the array's length.

import Prelude
import Data.Buffer

fill : Buffer -> Int -> IO ()
fill buf i =
  if i >= 16 then pure ()
  else do
    setBits8 buf i (cast (i * 17))
    fill buf (i + 1)

total' : Buffer -> Int -> Int -> IO Int
total' buf i acc =
  if i >= 16 then pure acc
  else do
    b <- getBits8 buf i
    total' buf (i + 1) (acc + cast b)

main : IO ()
main = do
  Just buf <- newBuffer 16
    | Nothing => putStrLn "no buffer"
  size <- rawSize buf
  printLn size
  z <- getBits8 buf 5
  printLn z
  fill buf 0
  t <- total' buf 0 0
  printLn t
  last <- getBits8 buf 15
  printLn last
  setByte buf 2 200
  printLn !(bufferData buf)
  Just empty <- newBuffer 0
    | Nothing => putStrLn "no buffer"
  printLn !(rawSize empty)
