module Main

import Prelude

-- Which implementation op runs is chosen by the input, among the two the
-- program fixes: the choice is a value, one of the two, and the use of op
-- runs the method of the one chosen.

interface Semi a where
  op : a -> a -> a

[plus] Semi Int where
  op = prim__add_Int

[times] Semi Int where
  op = prim__mul_Int

choose : Int -> Semi Int
choose 0 = plus
choose _ = times

combine : Int -> Int
combine k =
  op @{choose k} 6 7

main : IO ()
main = do
  line <- getLine
  putStrLn (prim__cast_IntString (combine (cast line)))
