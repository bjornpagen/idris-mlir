module Main

-- Named implementations chosen statically in each branch, whether the
-- branch is known at compile time or chosen by a byte of the input.

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
  c <- getChar
  putStrLn (prim__cast_IntString (combine (prim__sub_Int (prim__cast_CharInt c) 48)))
