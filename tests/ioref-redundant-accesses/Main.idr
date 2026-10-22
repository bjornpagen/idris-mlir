module Main

-- Accesses of an IORef that another access makes redundant: a read right
-- after a write of the same IORef is the value written, and a write right
-- after another overwrites what nothing read (mlir.expect: neither is left
-- before references are counted). Beside them, the same IORef under two
-- names, and a call between that writes or reads it, where neither access
-- is redundant: what the program prints is what each access means. Every
-- value written is computed from n, which is read, so that none is a
-- constant a fold could answer the read with.

import Prelude
import Data.IORef

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

||| Written through `a`, then through `b`, then read through `a`: when `a`
||| and `b` are one IORef, the read gives the second write.
throughTwo : IORef Int -> IORef Int -> Int -> IO Int
throughTwo a b n = do
  writeIORef a n
  writeIORef b (n + 1)
  readIORef a

||| Written through `a`, read through `b`, written through `a` again: when
||| `a` and `b` are one IORef, the read gives the first write, which stays.
readBetween : IORef Int -> IORef Int -> Int -> IO Int
readBetween a b n = do
  writeIORef a n
  seen <- readIORef b
  writeIORef a (n + 2)
  pure seen

||| Written, `act` run, read: what `act` wrote, if it wrote `r`.
around : IORef Int -> Int -> (Int -> IO ()) -> IO Int
around r n act = do
  writeIORef r n
  act (n * 2)
  readIORef r

||| Written, `look` run, written again: what `look` reads of `r` is the
||| first write.
overLook : IORef Int -> Int -> IO Int -> IO Int
overLook r n look = do
  writeIORef r n
  seen <- look
  writeIORef r (n + 4)
  pure seen

main : IO ()
main = do
  n <- readInt
  ref <- newIORef 0
  writeIORef ref n
  writeIORef ref (n * 3)
  x <- readIORef ref
  printLn x
  y <- throughTwo ref ref n
  printLn y
  other <- newIORef 100
  v <- throughTwo ref other n
  printLn v
  w <- readIORef other
  printLn w
  z <- readBetween ref ref (n + 5)
  printLn z
  u <- readIORef ref
  printLn u
  s <- around ref n (\k => writeIORef ref k)
  printLn s
  t <- around ref n (\_ => pure ())
  printLn t
  q <- overLook ref n (readIORef ref)
  printLn q
  p <- readIORef ref
  printLn p
