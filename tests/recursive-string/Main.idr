module Main

-- `digits` recurses on a runtime value, so the string it returns is not
-- known at compile time, but its only use is output, so idr-specialize
-- makes a clone of `digits` that writes at each tail, where output fusion
-- takes the append apart: no string is built at runtime. The clone writes
-- the leading digits before the levels around them end, which is what the
-- program means only because `digits` ends: it recurses on a list of steps
-- left, and divides by subtracting at most as many times, each a list
-- Idris sees shrink. On empty stdin the Prelude's getChar returns
-- character 255.

import Prelude

-- Thirty steps, a list Idris sees shrink: enough for a byte's digits and
-- for the subtractions of a division of one.
fuel : List ()
fuel =
  [(), (), (), (), (), (), (), (), (), (), (), (), (), (), (), (), (), (), (), (), (), (), (), (), (), (), (), (), (), ()]

-- n divided by 10, by subtraction: the quotient so far and what is left.
quot10 : List () -> Int -> Int -> (Int, Int)
quot10 [] q r = (q, r)
quot10 (_ :: steps) q r = case prim__lt_Int r 10 of
  0 => quot10 steps (prim__add_Int q 1) (prim__sub_Int r 10)
  _ => (q, r)

digits : List () -> Int -> String
digits [] n = prim__cast_IntString n
digits (_ :: steps) n = case prim__lt_Int n 10 of
  0 => let qr = quot10 fuel 0 n in
       prim__strAppend (digits steps (fst qr)) (prim__cast_IntString (snd qr))
  _ => prim__cast_IntString n

main : IO ()
main = do
  c <- getChar
  putStrLn (digits fuel (prim__cast_CharInt c))
