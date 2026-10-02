module Main

-- A generate whose function is a fold over a frozen array, which this
-- compiler makes one loop over rows and columns, the fold's step calling a
-- function that reads and bumps a counter in an array shared unrestricted,
-- which Linear.Array allows. In the program's order the counter's values
-- go to row 0, then row 1, and so on, each row's sum saying which values
-- it saw, and row 0 is the fill, whose fold runs once: the loop runs the
-- rows from 1 on, row by row, since a step that calls is no body the
-- vectorizer takes.

import Prelude
import Linear.Notation
import Linear.Array

bumpN : Array Int -> Int -> Int -> Int
bumpN a k acc =
  if k <= 0 then acc
  else case read a 0 of
         (s # a1) => freeze (write a1 0 (s + 1)) (\_ => bumpN a (k - 1) (acc * 3 + s))

rows : Array Int -> Int -> Int -> IArray Int -> Array Int
rows a k n v = generate n (\i => ifoldl (\acc, j, x => acc + bumpN a k (x + i * 100 + j)) 0 v)

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
  k <- readInt
  n <- readInt
  m <- readInt
  let a = mkArray 1 (the Int 0)
  putStrLn (freeze (generate m (\c => c * 7)) (\v => freeze (rows a k n v) (\r => showInts r 0)))
  printLn (freeze a (\fa => iread fa 0))
