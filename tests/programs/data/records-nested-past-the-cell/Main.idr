module Main

import Prelude

-- Records nested three deep: H holds 16 M, M holds 16 L, and L holds 15
-- strings, so H spreads 3840 counted references over the cell of N.
-- idr-defunctionalize boxes the widest first: H, whose own cell then holds
-- 3840, then M, whose cell of 240 fits; L stays unboxed inside it. The
-- last string of the last L is read back from the first N.
data L = MkL String String String String String String String String String String String String String String String

data M = MkM L L L L L L L L L L L L L L L L

data H = MkH M M M M M M M M M M M M M M M M

data T = E | N H T

leaf : String -> L
leaf s = MkL s s s s s s s s s s s s s s s

mid : String -> String -> M
mid s e = MkM (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf e)

high : String -> H
high s = MkH (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s (s ++ "?"))

build : Int -> String -> T
build k s = if k <= 0 then E else N (high s) (build (k - 1) s)

count : T -> Int
count E = 0
count (N _ t) = 1 + count t

deepest : T -> String
deepest E = ""
deepest (N (MkH _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ (MkM _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ (MkL _ _ _ _ _ _ _ _ _ _ _ _ _ _ x))) _) = x

main : IO ()
main = do
  c <- getChar
  let t = build (ord c - 48) (the String (cast c))
  printLn (count t + count t)
  putStrLn (deepest t)
