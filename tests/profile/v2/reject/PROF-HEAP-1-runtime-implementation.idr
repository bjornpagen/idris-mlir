-- expect: PROF-HEAP-1 line 20
-- message: an implementation chosen at runtime
module Main

import Prelude

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
main = putStrLn (prim__cast_IntString (combine 0))
