module Main

import Prelude

-- A map in IO over a million elements: each level runs its action, then
-- the level under it, then gives back a cell holding the two results. The
-- cell is built before the level under it runs, with its tail the place
-- that level fills, so the actions run in order in a loop that grows no
-- stack. Every 250,000th element writes a line, which shows the order.

mapIO : (Int -> IO Int) -> List Int -> IO (List Int)
mapIO f [] = pure []
mapIO f (x :: xs) = do
  y <- f x
  ys <- mapIO f xs
  pure (y :: ys)

double : Int -> IO Int
double x = do
  when (x `mod` 250000 == 0) (putStrLn (show x))
  pure (x * 2)

upTo : Int -> List Int -> List Int
upTo n acc = if n <= 0 then acc else upTo (n - 1) (n :: acc)

countSum : Int -> Int -> List Int -> (Int, Int)
countSum c s [] = (c, s)
countSum c s (x :: xs) = countSum (c + 1) (s + x) xs

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
  ys <- mapIO double (upTo n [])
  printLn (countSum 0 0 ys)
