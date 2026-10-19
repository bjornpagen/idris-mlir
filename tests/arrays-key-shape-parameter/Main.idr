module Main

-- A data type over a shape its field's array has: Grid's shape is a
-- parameter whose rank its key holds, so `Grid [<2, 3]` and `Grid [<4, 5]`
-- are one instance of two axes, its field a tensor of two axes; Holder,
-- whose field is a Grid, holds the rank of its own shape so too, and a
-- Grid of one axis is another instance.

import Prelude
import Array

data Grid : Shape -> Type where
  MkGrid : Array s Int -> Grid s

data Holder : Shape -> Type where
  Hold : Int -> Grid s -> Holder s

corner : Grid [<2, 3] -> Int
corner (MkGrid a) = a !! [<0, 0]

cornerOf45 : Grid [<4, 5] -> Int
cornerOf45 (MkGrid a) = a !! [<3, 4]

end : Grid [<4] -> Int
end (MkGrid a) = a !! [<3]

held : Holder [<2, 3] -> Int
held (Hold k g) = k + corner g

main : IO ()
main = do
  line <- getLine
  let k = the Int (cast line)
  printLn (held (Hold 1 (MkGrid (tabulate [<2, 3] (\_ => k)))))
  printLn (cornerOf45 (MkGrid (tabulate [<4, 5] (\[<i, j] => k + cast (finToNat i + finToNat j)))))
  printLn (end (MkGrid (tabulate [<4] (\[<i] => k * cast (finToNat i)))))
