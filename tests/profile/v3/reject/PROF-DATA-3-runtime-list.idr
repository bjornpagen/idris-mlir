-- expect: PROF-DATA-3 line 18
module Main

-- A list is recursive data, a box: one whose length depends on a runtime
-- value would need the heap. (One of known shape with runtime elements
-- needs nothing: calls on it are specialized on its shape, ELIM-SPEC-1.)

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

main : IO ()
main = do
  c <- getChar
  putStrLn (prim__cast_IntString (len (build (prim__cast_CharInt c))))
