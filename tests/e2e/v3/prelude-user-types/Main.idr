module Main

-- rule: ELIM-EVAL-1, ELIM-G-6, FE-TR-6, SEM-REC-2, PROF-PROG-4
-- User types with the Prelude's interfaces: Show with showPrec, showCon
-- and showArg; Eq; Ord through compare; Semigroup and Monoid (concat);
-- Functor on a recursive tree, summed through Num. Chars and strings are
-- shown with the Prelude's escapes, whose string primitives on literals
-- fold at compile time, and `show` on a literal Char, a closed call, is
-- evaluated at compile time.

import Prelude

data Shape = Circle Double | Rect Double Double

Show Shape where
  showPrec d (Circle r) = showCon d "Circle" (showArg r)
  showPrec d (Rect w h) = showCon d "Rect" (showArg w ++ showArg h)

Eq Shape where
  Circle a == Circle b = a == b
  Rect a b == Rect c d = a == c && b == d
  _ == _ = False

area : Shape -> Double
area (Circle r) = pi * r * r
area (Rect w h) = w * h

Ord Shape where
  compare a b = compare (area a) (area b)

record V2 where
  constructor MkV2
  x, y : Double

Semigroup V2 where
  MkV2 a b <+> MkV2 c d = MkV2 (a + c) (b + d)

Monoid V2 where
  neutral = MkV2 0 0

Show V2 where
  show (MkV2 a b) = "<" ++ show a ++ ", " ++ show b ++ ">"

data Tree a = Leaf a | Node (Tree a) (Tree a)

Functor Tree where
  map f (Leaf x) = Leaf (f x)
  map f (Node l r) = Node (map f l) (map f r)

sumTree : Num a => Tree a -> a
sumTree (Leaf x) = x
sumTree (Node l r) = sumTree l + sumTree r

main : IO ()
main = do
  c <- getChar
  let n = the Int (cast (ord c) - 48)
  let s = if n > 3 then Circle (cast n) else Rect 2 (cast n)
  printLn s
  printLn (s == Circle 5, s < Rect 10 10, max s (Rect 1 1))
  printLn (MkV2 1 2 <+> MkV2 (cast n) 0.5 <+> neutral)
  printLn (concat [MkV2 1 1, MkV2 (cast n) 2])
  printLn (sumTree (map (* n) (Node (Leaf 1) (Node (Leaf 2) (Leaf 3)))))
  printLn 'x'
  printLn 'y'
  printLn "hi\n"
  printLn (Prelude.String.length "hello", pack ['a', 'b'], unpack "xy")
  putStrLn (show n ++ " items")
