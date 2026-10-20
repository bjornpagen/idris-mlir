-- expect: runtime closure, line 27
-- message: Main.choose
module Main

import Prelude

-- Which implementation op runs is chosen by the input: a set of
-- implementations at one site that only the run decides, refused, naming
-- the choice. near/ makes the same choice between two calls, each of one
-- implementation the program fixes.

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
