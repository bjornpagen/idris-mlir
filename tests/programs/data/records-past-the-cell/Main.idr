module Main

import Prelude

-- A cell's header counts its object slots in 8 bits, and a record is
-- unboxed, spread over the cell that holds it: R's two S of 128 strings
-- would put 257 counted references in the cell of N. idr-defunctionalize
-- makes R a box, so N holds one reference to it, and then S, so R's own
-- cell holds two. The last string is read back, and every cell is freed.
data S = MkS String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String

data R = MkR S S

data T = E | N R T

half : String -> S
half s = MkS s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s

mk : String -> R
mk s = MkR (half s) (half (s ++ "!"))

build : Int -> String -> T
build k s = if k <= 0 then E else N (mk s) (build (k - 1) s)

count : T -> Int
count E = 0
count (N _ t) = 1 + count t

lastOf : T -> String
lastOf E = ""
lastOf (N (MkR _ (MkS _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ x)) _) = x

main : IO ()
main = do
  c <- getChar
  let t = build (ord c - 48) (the String (cast c))
  printLn (count t + count t)
  putStrLn (lastOf t)
