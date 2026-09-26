-- expect: PROF-DATA-3 line 6
module Main

data L : Type where
  Nil : L
  Cons : Int -> L -> L

len : L -> Int
len Nil = 0
len (Cons _ xs) = prim__add_Int 1 (len xs)

main : Int
main = len (Cons 1 Nil)
