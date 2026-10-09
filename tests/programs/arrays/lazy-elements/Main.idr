module Main

-- An array of suspensions: each element is written as a suspended
-- computation, read back and forced twice, giving its value both times.

import Prelude
import Data.IOArray

square : Int -> Int
square x = x * x

fill : IOArray (Lazy Int) -> Int -> Int -> IO ()
fill arr n i =
  if i >= n
     then pure ()
     else do ignore (writeArray arr i (Delay (square (i + n))))
             fill arr n (i + 1)

showTwice : IOArray (Lazy Int) -> Int -> Int -> IO ()
showTwice arr n i =
  if i >= n
     then pure ()
     else do Just v <- readArray arr i
               | Nothing => putStrLn "missing"
             printLn (force v)
             printLn (force v)
             showTwice arr n (i + 1)

main : IO ()
main = do
  c <- getChar
  let n : Int = cast (ord c - ord '0')
  arr <- newArray n
  fill arr n 0
  showTwice arr n 0
