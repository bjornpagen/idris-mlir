-- expect: PROF-DATA-3 line 18
module Main

-- rule: SEM-REC-1
-- A list is recursive data: it exists at compile time only, and one chosen
-- by a runtime value would need the heap.

import IdrisMLIR.IO

data L : Type where
  Nil : L
  Cons : Int -> L -> L

len : L -> Int
len Nil = 0
len (Cons _ xs) = prim__add_Int 1 (len xs)

pick : Int -> L
pick 0 = Nil
pick _ = Cons 1 Nil

partial
main : IO ()
main = do
  c <- getChar
  putStrLn (prim__cast_IntString (len (pick (prim__cast_CharInt c))))
