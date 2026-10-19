module Main

-- A vector inside a `Maybe`: the instance of `Maybe` over a vector of
-- three keys its rank, so `Just`'s field is a tensor of one axis. Linearity
-- plays no part.

import Prelude
import Array

box : Int -> Maybe (Vector 3 Int)
box k = if k < 0 then Nothing else Just (tabulate [<3] (\[<i] => k + cast (finToNat i)))

main : IO ()
main = do
  line <- getLine
  case box (cast line) of
    Just v => printLn (v !! [<1] + v !! [<2])
    Nothing => putStrLn "none"
