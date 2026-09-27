-- expect: PROF-DATA-3 line 19
module Main

-- rule: SEM-REC-1
-- A list is recursive data: it exists at compile time only, and one whose
-- length depends on a runtime value would need the heap. (A choice among
-- lists of known shapes needs nothing: ELIM-G-20.)

import IdrisMLIR.IO

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
