module Main

import Prelude

-- Lists built by recursion and summed: their cells are made and freed by
-- the runtime the program links. The second's elements are k * 2^60, so
-- its sums leave the small range (2^62) for the runtime's large bigs.
build : Integer -> Nat -> List Integer
build scale Z = []
build scale (S k) = cast (S k) * scale :: build scale k

main : IO ()
main = do
  printLn (sum (build 1 7))
  printLn (sum (build 1152921504606846976 7))
