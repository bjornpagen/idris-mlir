module Main

-- Named implementations chosen statically in each branch.

import Prelude

interface Semi a where
  op : a -> a -> a

[plus] Semi Int where
  op = prim__add_Int

[times] Semi Int where
  op = prim__mul_Int

combine : Int -> Int
combine 0 = op @{plus} 6 7
combine _ = op @{times} 6 7

main : IO ()
main = do
  putStrLn (prim__cast_IntString (combine 0))
  putStrLn (prim__cast_IntString (combine 1))
