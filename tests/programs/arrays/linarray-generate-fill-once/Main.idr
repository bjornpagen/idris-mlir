module Main

-- generate's function applied through an array shared unrestricted, which
-- Linear.Array allows: each application reads a counter in it and writes
-- the counter plus one, so the elements and the counter say how often the
-- function ran, and in which order. The library applies it once at each
-- index, at 0 first, as the fill that is element 0, and at 0 even when the
-- array is empty; this compiler's loop runs it at the indices from 1 on.

import Prelude
import Linear.Notation
import Linear.Array

bump : Array Int -> Int -> Int
bump a i = case read a 0 of
  (s # a1) => freeze (write a1 0 (s + 1)) (\_ => s * 10 + i)

showInts : IArray Int -> Int -> String
showInts a i = if i >= isize a then "" else show (iread a i) ++ " " ++ showInts a (i + 1)

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  n <- readInt
  let a = mkArray 1 (the Int 100)
  putStrLn (freeze (generate n (\i => bump a i)) (\v => showInts v 0))
  putStrLn (freeze (generate (n - n) (\i => bump a i)) (\v => showInts v 0))
  printLn (freeze a (\fa => iread fa 0))
