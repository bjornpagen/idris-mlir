module Main

-- rule: ELIM-G-20, PROF-HEAP-1, PROF-HEAP-2, PROF-PRIM-4, SEM-REC-1
-- A match on a runtime value whose alternatives yield different static
-- values is a choice: a runtime tag and the atoms of every alternative.
-- A function, a Lazy value, a string and a list chosen at runtime are each
-- used through their tag, without the heap.

import IdrisMLIR.IO

data Op : Type where
  Inc : (Int -> Int) -> Op
  Dbl : (Int -> Int) -> Op

pick : Char -> Op
pick 'a' = Inc (prim__add_Int 1)
pick _ = Dbl (prim__mul_Int 2)

data Later : Type where
  Soon : Lazy Int -> Later
  Never : Lazy Int -> Later

later : Char -> Later
later 'a' = Soon 1
later _ = Never 2

word : Char -> String
word 'a' = "one"
word _ = "three"

data L : Type where
  Nil : L
  Cons : Int -> L -> L

len : L -> Int
len Nil = 0
len (Cons _ xs) = prim__add_Int 1 (len xs)

list : Int -> L
list 0 = Nil
list n = Cons n (Cons n Nil)

main : IO ()
main = do
  c <- getChar
  d <- getChar
  case pick c of
    Inc f => putStrLn (prim__cast_IntString (f 5))
    Dbl g => putStrLn (prim__cast_IntString (g 5))
  case pick d of
    Inc f => putStrLn (prim__cast_IntString (f 5))
    Dbl g => putStrLn (prim__cast_IntString (g 5))
  case later d of
    Soon x => putStrLn (prim__cast_IntString x)
    Never y => putStrLn (prim__cast_IntString y)
  putStrLn (prim__cast_IntString (prim__strLength (word c)))
  putStrLn (prim__cast_IntString (prim__strLength (word d)))
  putStrLn (prim__cast_IntString (len (list (prim__sub_Int (prim__cast_CharInt c) 97))))
  putStrLn (prim__cast_IntString (len (list (prim__cast_CharInt d))))
