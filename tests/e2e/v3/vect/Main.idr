module Main

-- rule: SEM-IDX-1, FE-TR-7, PROF-LIB-3, SEM-REC-2
-- Length-indexed vectors from the base library: an inductive family whose
-- index exists at compile time only (Brady, McBride and McKinna,
-- "Inductive families need not store their indices"). A Vect is built
-- during specialization, like a list, with its elements computed at
-- runtime; indexing takes a Fin whose bound is proved (natToFinLT's proof
-- is matched in the compile-time tree and erased); reverse goes through
-- `rewrite`, which is the identity at runtime.

import Prelude
import Data.Vect

dot : Num a => Vect n a -> Vect n a -> a
dot xs ys = sum (zipWith (*) xs ys)

mulV : Vect m (Vect n Double) -> Vect n Double -> Vect m Double
mulV rows v = map (dot v) rows

mat : Vect 3 (Vect 3 Double)
mat = [[2, 0, 1], [1, 3, 0], [0, 1, 4]]

norm2 : Vect n Double -> Double
norm2 v = dot v v

main : IO ()
main = do
  c <- getChar
  let x = the Double (cast (ord c - 48))
  let v = [x, 1.0, x / 2.0]
  printLn (dot v v)
  printLn (mulV mat v)
  printLn (head (reverse v), index 1 v, last v)
  printLn (norm2 (mulV mat (mulV mat v)))
  printLn (toList (replicate 3 x))
  printLn (foldr (+) 0 (map (* 2) v))
