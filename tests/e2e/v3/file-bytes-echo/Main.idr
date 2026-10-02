module Main

-- Bytes through System.File: standard input read into a buffer a chunk at
-- a time with readBufferData, every chunk written back with
-- writeBufferData, byte for byte, bytes from 128 on included; the end of
-- input is where a read gives 0 bytes, and fEOF reports it afterwards.

import Prelude
import Data.Buffer
import System.File

copy : Buffer -> Int -> IO Int
copy buf done = do
  Right got <- readBufferData stdin buf 0 7
    | Left _ => pure done
  if got == 0
     then pure done
     else do
       Right () <- writeBufferData stdout buf 0 got
         | Left _ => pure done
       copy buf (done + got)

main : IO ()
main = do
  Just buf <- newBuffer 7
    | Nothing => putStrLn "no buffer"
  before <- fEOF stdin
  done <- copy buf 0
  after <- fEOF stdin
  putStrLn ""
  printLn (before, done, after)
