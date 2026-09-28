module Main

-- A dictionary with a superclass and a field of a value type: the field is
-- read where the dictionary is matched, and no dictionary survives.

import Prelude

interface Semi a where
  op : a -> a -> a

Semi Int where
  op = prim__add_Int

interface Semi a => Mon a where
  unit : a

Mon Int where
  unit = 0

fold3 : Mon a => a -> a -> a -> a
fold3 x y z = op x (op y (op z unit))

main : IO ()
main = putStrLn (prim__cast_IntString (fold3 1 2 39))
