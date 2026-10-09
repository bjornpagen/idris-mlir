module Main

-- An array whose elements are arrays: a table of rows, each an array of
-- its own. The element type holds an array, but nothing an array holds
-- can reach that array again, so it is no knot, and it compiles.

import Prelude
import Data.IOArray

get : IOArray Int -> Int -> IO Int
get a j = do
  Just v <- readArray a j
    | Nothing => pure (-1)
  pure v

fillRow : IOArray Int -> Int -> Int -> Int -> IO ()
fillRow a r n j =
  if j >= n
     then pure ()
     else do ignore (writeArray a j (r * 10 + j))
             fillRow a r n (j + 1)

fillTable : IOArray (IOArray Int) -> Int -> Int -> IO ()
fillTable t n i =
  if i >= n
     then pure ()
     else do a <- newArray n
             fillRow a i n 0
             ignore (writeArray t i a)
             fillTable t n (i + 1)

-- The sum of the table's diagonal, each element read through its row.
diagonal : IOArray (IOArray Int) -> Int -> Int -> Int -> IO Int
diagonal t n i acc =
  if i >= n
     then pure acc
     else do Just a <- readArray t i
               | Nothing => pure (-1)
             v <- get a i
             diagonal t n (i + 1) (acc + v)

main : IO ()
main = do
  c <- getChar
  let n : Int = cast (ord c - ord '0')
  table <- newArray n
  fillTable table n 0
  Just lastRow <- readArray table (n - 1)
    | Nothing => putStrLn "no row"
  printLn !(get lastRow 0)
  printLn !(diagonal table n 0 0)
