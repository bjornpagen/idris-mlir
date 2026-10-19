module Main

import Prelude

-- A cell's header counts its object slots in 8 bits, and a record is
-- unboxed, spread over the cell that holds it, so a cell can hold more
-- counted references than its header counts: then the cell's count is a
-- word after its header, and no record is boxed to make it fit. Two such
-- cells, each in a list as long as the input digit says (none for 0): R's
-- two S of 128 strings put 257 counted references in the cell of NF; H
-- holds 16 M, M holds 16 L, and L holds 15 strings, so H spreads 3840 over
-- the cell of NN. Each list's last string is read back from its first
-- cell, and every cell is freed.

data S = MkS String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String String

data R = MkR S S

data TF = EF | NF R TF

half : String -> S
half s = MkS s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s

mk : String -> R
mk s = MkR (half s) (half (s ++ "!"))

buildF : Int -> String -> TF
buildF k s = if k <= 0 then EF else NF (mk s) (buildF (k - 1) s)

countF : TF -> Int
countF EF = 0
countF (NF _ t) = 1 + countF t

lastOf : TF -> String
lastOf EF = ""
lastOf (NF (MkR _ (MkS _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ x)) _) = x

data L = MkL String String String String String String String String String String String String String String String

data M = MkM L L L L L L L L L L L L L L L L

data H = MkH M M M M M M M M M M M M M M M M

data TN = EN | NN H TN

leaf : String -> L
leaf s = MkL s s s s s s s s s s s s s s s

mid : String -> String -> M
mid s e = MkM (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf s) (leaf e)

high : String -> H
high s = MkH (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s s) (mid s (s ++ "?"))

buildN : Int -> String -> TN
buildN k s = if k <= 0 then EN else NN (high s) (buildN (k - 1) s)

countN : TN -> Int
countN EN = 0
countN (NN _ t) = 1 + countN t

deepest : TN -> String
deepest EN = ""
deepest (NN (MkH _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ (MkM _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ (MkL _ _ _ _ _ _ _ _ _ _ _ _ _ _ x))) _) = x

main : IO ()
main = do
  c <- getChar
  let k = ord c - 48
  let s = the String (cast c)
  let flat = buildF k s
  printLn (countF flat + countF flat)
  putStrLn (lastOf flat)
  let nested = buildN k s
  printLn (countN nested + countN nested)
  putStrLn (deepest nested)
