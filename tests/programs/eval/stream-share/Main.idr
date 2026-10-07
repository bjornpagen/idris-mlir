module Main

import Prelude

-- The tail is the stream itself. A finite prefix forces each cell once
-- when the suspension keeps its value.

zipWith : (a -> b -> c) -> Stream a -> Stream b -> Stream c
zipWith f (x :: xs) (y :: ys) = f x y :: zipWith f xs ys

fibs : Stream Nat
fibs = the Nat 0 :: the Nat 1 :: zipWith (+) fibs (tail fibs)

main : IO ()
main = printLn (sum (take 30 fibs))
