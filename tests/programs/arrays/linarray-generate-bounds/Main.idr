module Main

-- New arrays generated from a frozen one read at each index, as imap does.
-- Where every index of the new array is within the frozen one, which one
-- test on entry decides, the loop reads it as an input and computes on the
-- target's lanes; the second array is one element longer than the frozen
-- one, so its loop reads it with its bounds check and ends the program at
-- the first index outside it, after the output before it.

import Prelude
import Linear.Notation
import Linear.Array

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
  printLn (freeze (mkArray n (the Int 3)) (\a => freeze (imap (\i, x => x + i) a) Linear.Array.sum))
  putStrLn "one longer:"
  printLn (freeze (mkArray n (the Int 3)) (\a => freeze (generate (n + 1) (\i => iread a i * 2)) Linear.Array.sum))
