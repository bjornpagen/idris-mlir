module Main

-- The record of ioref-record-in-place, rebuilt through base's modifyIORef:
-- its read and its write are the same read and write, wherever the
-- inliner leaves them, so the read moves the record out of the cell
-- (mlir.expect: moves-out), and the rebuild may take its cell.

import Prelude
import Data.IORef

record State where
  constructor MkState
  f1 : Int
  f2 : Int
  f3 : Int
  f4 : Int
  f5 : Int
  f6 : Int
  f7 : Int
  f8 : Int
  f9 : Int
  f10 : Int
  f11 : Int
  f12 : Int
  f13 : Int
  f14 : Int
  f15 : Int
  f16 : Int
  f17 : Int
  f18 : Int
  f19 : Int
  f20 : Int
  f21 : Int
  f22 : Int
  f23 : Int
  f24 : Int
  f25 : Int
  f26 : Int
  f27 : Int
  f28 : Int
  f29 : Int
  f30 : Int
  f31 : Int
  f32 : Int

initial : State
initial = MkState 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32

||| The sum of every field.
fieldSum : State -> Int
fieldSum s =
  s.f1 + s.f2 + s.f3 + s.f4 + s.f5 + s.f6 + s.f7 + s.f8
  + s.f9 + s.f10 + s.f11 + s.f12 + s.f13 + s.f14 + s.f15 + s.f16
  + s.f17 + s.f18 + s.f19 + s.f20 + s.f21 + s.f22 + s.f23 + s.f24
  + s.f25 + s.f26 + s.f27 + s.f28 + s.f29 + s.f30 + s.f31 + s.f32

loop : IORef State -> Int -> IO ()
loop ref n =
  if n <= 0 then pure ()
  else do modifyIORef ref (\s => { f1 := s.f1 + 1 } s)
          loop ref (n - 1)

main : IO ()
main = do
  ref <- newIORef initial
  loop ref 1000000
  s <- readIORef ref
  printLn s.f1
  printLn (fieldSum s)
