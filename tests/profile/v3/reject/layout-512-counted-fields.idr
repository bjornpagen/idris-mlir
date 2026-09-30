-- expect: layout, line 8
module Main

import Prelude

-- A cell's header counts its object slots in 8 bits: a record of 512
-- strings, each a counted reference, does not fit, and says so.
data R = MkR String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String

data T = E | N R T

mk : String -> R
mk s = MkR s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s

build : Int -> String -> T
build k s = if k <= 0 then E else N (mk s) (build (k - 1) s)

count : T -> Int
count E = 0
count (N _ t) = 1 + count t

main : IO ()
main = do
  c <- getChar
  let t = build (ord c - 48) (the String (cast c))
  printLn (count t + count t)
