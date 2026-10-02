-- exit: 0
-- stdout: 3\n6\n
module Main

-- Recursive data built and consumed at compile time: a list and mutually
-- recursive types. Nothing of them exists at runtime.

import Prelude

data L : Type where
  Nil : L
  Cons : Int -> L -> L

len : L -> Int
len Nil = 0
len (Cons _ xs) = prim__add_Int 1 (len xs)

total' : L -> Int
total' Nil = 0
total' (Cons x xs) = prim__add_Int x (total' xs)

main : IO ()
main = do
  let xs = Cons 1 (Cons 2 (Cons 3 Nil))
  putStrLn (prim__cast_IntString (len xs))
  putStrLn (prim__cast_IntString (total' xs))
