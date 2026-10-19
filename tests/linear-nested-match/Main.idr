-- Nested patterns on a linear value: when the inner match fails, the
-- second clause names the field that match already used.
module Main
import Prelude

data T : Type where
  L : T
  N : (1 l : T) -> Int -> T

data C = MkC Int

sz : (1 t : T) -> Int -> C
sz L acc = MkC acc
sz (N l k) acc = sz l (acc + k)

-- nested patterns on a linear binder: the second clause names l after the first matched it
g : (1 t : T) -> T
g (N (N l k) j) = N l (k + j)
g (N l j) = N l j
g L = L

build : Int -> T
build n = if n <= 0 then L else N (build (n - 1)) n

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

-- n read: 0 is the leaf alone, and 1 and 2 reach each clause first.
main : IO ()
main = do
  n <- readInt
  let MkC c = sz (g (build n)) 0
  printLn c
