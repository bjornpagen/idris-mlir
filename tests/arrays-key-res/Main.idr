module Main

-- A read of a linear array gives the element and the array back in a
-- `Res` (Builtin.DPair.(#)): its second component is a linear array, a
-- tensor of the rank the instance of `Res` keys. The array is written
-- once, read twice and frozen; the sum of the reads is printed.

import Prelude
import Array
import Linear.Notation

main : IO ()
main = do
  line <- getLine
  let k = the Int (cast line)
  let MkBang x = withArray [<2, 3] k (\a =>
        let a = LArray.write a [<1, 2] (k + 1)
            x # a = LArray.read a [<0, 0]
            y # a = LArray.read a [<1, 2]
            MkBang _ = LArray.freeze a
        in MkBang (x + y))
  printLn x
