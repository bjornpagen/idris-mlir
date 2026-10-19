module Main

-- A frozen linear array leaves its continuation as the field of `!*`
-- (MkBang). The instance of `!*` over a vector of three keys the vector's
-- rank, so its field is a tensor of one axis, whatever the extent.

import Prelude
import Array
import Linear.Notation

main : IO ()
main = do
  line <- getLine
  let k = the Int (cast line)
  let MkBang v = withArray [<3] k (\a => LArray.freeze (LArray.write a [<2] (k * 10)))
  printLn (v !! [<0] + v !! [<1] + v !! [<2])
