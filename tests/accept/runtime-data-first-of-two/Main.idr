module Main

-- A list whose length is known only at runtime, and an Integer made from a
-- runtime value inside `count`: both live on the heap, and are freed.

import Prelude

data L : Type where
  Nil : L
  Cons : Int -> L -> L

len : L -> Int
len Nil = 0
len (Cons _ xs) = prim__add_Int 1 (len xs)

build : Int -> L
build 0 = Nil
build n = Cons n (build (prim__sub_Int n 1))

partial
count : Int -> Int
count 0 = 0
count n = prim__add_Int (prim__cast_IntegerInt (prim__div_Integer (prim__cast_IntInteger n) 3))
                        (count (prim__sub_Int n 1))

partial
main : IO ()
main = do
  c <- getChar
  putStrLn (prim__cast_IntString (len (build (prim__cast_CharInt c))))
  putStrLn (prim__cast_IntString (count (prim__cast_CharInt c)))
