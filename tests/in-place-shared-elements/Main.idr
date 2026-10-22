module Main

import Prelude
import Linear.Notation
import Linear.List

-- A linear list's promise is of its own cells alone: reverse turns a list
-- around in its own cells however its elements are shared. Here every
-- element is one value, `Just k` read once, held by every cell, and the
-- spine is fresh, so reverse is passed it exclusive and rebuilds it in
-- place. The elements are summed after the turn, the last element first.

rep : Int -> Maybe Int -> LList (Maybe Int) -@ LList (Maybe Int)
rep n x acc = if n <= 0 then acc else rep (n - 1) x (x :: acc)

sumJust : Int -> LList (Maybe Int) -@ !* Int
sumJust acc [] = MkBang acc
sumJust acc (Nothing :: xs) = sumJust acc xs
sumJust acc (Just v :: xs) = sumJust (acc + v) xs

main : IO ()
main = do
  c <- getChar
  let n = cast (ord c - ord '0')
  let MkBang total = sumJust 0 (reverse (rep n (Just (n * 10)) []))
  printLn total
