module Main

-- A buffer is a sized block of bytes. Wider values are the machine's own
-- load and store of those bytes, so this program's text is Chez's.

import Prelude
import Data.Buffer
import Data.List

covering
main : IO ()
main = do
  Nothing <- newBuffer (-1)
    | Just _ => putStrLn "negative size allocated"
  putStrLn "negative"
  Just buf <- newBuffer 32
    | Nothing => putStrLn "no buffer"
  printLn !(rawSize buf)
  printLn !(getBits8 buf 0)
  setBits16 buf 1 0x0102
  printLn !(getBits16 buf 1)
  setBits32 buf 3 0x04030201
  printLn !(getBits32 buf 3)
  setBits64 buf 8 0x0807060504030201
  printLn !(getBits64 buf 8)
  setInt8 buf 0 (-1)
  printLn !(getInt8 buf 0)
  setInt16 buf 2 (-2)
  printLn !(getInt16 buf 2)
  setInt32 buf 4 (-3)
  printLn !(getInt32 buf 4)
  setInt64 buf 16 (-4)
  printLn !(getInt64 buf 16)
  setInt buf 20 (-5)
  printLn !(getInt buf 20)
  setDouble buf 1 1.0
  printLn !(getDouble buf 1)
  setBool buf 0 True
  printLn !(getBool buf 0)
  setBool buf 0 False
  printLn !(getBool buf 0)
  printLn (stringByteLength "café")
  printLn (stringByteLength (pack [chr 97, chr 0, chr 98]))
  setString buf 0 "hi"
  putStrLn !(getString buf 0 2)
  printLn (stringByteLength !(getString buf 32 0))
  setBits8 buf 0 255
  putStrLn !(getString buf 0 1)
  setBits8 buf 0 1
  setBits8 buf 1 2
  setBits8 buf 2 3
  setBits8 buf 3 4
  copyData buf 0 4 buf 2
  copied <- bufferData' buf
  printLn (take 6 copied)
  copyData buf 0 0 buf 32
  Just grown <- resizeBuffer buf 40
    | Nothing => putStrLn "no resize"
  printLn !(rawSize grown)
  Just shrunk <- resizeBuffer buf 4
    | Nothing => putStrLn "no resize"
  printLn !(rawSize shrunk)
  printLn !(bufferData' shrunk)
  Just (left, right) <- splitBuffer buf 2
    | Nothing => putStrLn "no split"
  printLn !(rawSize left)
  printLn !(rawSize right)
  Just joined <- concatBuffers [left, right]
    | Nothing => putStrLn "no concat"
  printLn !(rawSize joined)
  printLn !(bufferData' joined)
  empty <- emptyBuffer
  printLn !(rawSize empty)
