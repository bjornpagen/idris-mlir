module Main

import Prelude

interface Semi a where
  op : a -> a -> a

[plus] Semi Int where
  op = prim__add_Int

[times] Semi Int where
  op = prim__mul_Int

combine : Int -> Int
combine k =
  if k == 0 then op @{plus} 6 7 else op @{times} 6 7

main : IO ()
main = do
  line <- getLine
  putStrLn (prim__cast_IntString (combine (cast line)))
