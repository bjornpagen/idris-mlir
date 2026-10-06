module Main

-- Every run-time export of Builtin that user code may write, each used
-- (covers): the constructors of the pairs, dependent pairs and Unit,
-- their projections, laziness, the literal interfaces' methods and
-- default implementations and transport along an equality, each line
-- printed so that Chez checks what it computes. The rest, assert_total,
-- assert_smaller, assert_linear, believe_me and idris_crash, are what
-- Idris marks %unsafe: escape hatches, which user code may not write.

import Prelude

data Box : Nat -> Type where
  MkBox : Int -> Box n

unbox : Box n -> Int
unbox (MkBox x) = x

-- `rewrite` elaborates to rewrite__impl. Applied to all its arguments,
-- it and replace are the identity on the last, so each is also applied
-- to all but the last, which keeps the definition.
rewriteBox : (0 prf : x = y) -> Box y -> Box x
rewriteBox prf b = rewrite prf in b

rewriteBox' : (0 prf : x = y) -> (1 _ : Box y) -> Box x
rewriteBox' prf = rewrite__impl Box prf

transport : (0 prf : a = b) -> (1 _ : a) -> b
transport prf = replace {p = id} prf

sumLPair : LPair Int Int -> Int
sumLPair (a # b) = a + b

resValue : Res Int (const String) -> (Int, String)
resValue (n # s) = (n, s)

dependent : DPair Int (const String)
dependent = MkDPair 7 "seven"

lazyInt : Lazy Int
lazyInt = delay (6 * 7)

main : IO ()
main = do
  printLn (MkPair (the Int 1) "one")
  printLn (fst (the (Int, String) (2, "two")), snd (the (Int, String) (3, "three")))
  printLn (swap (the (Int, Char) (4, 'f')))
  printLn (MkUnit == ())
  printLn (fst dependent, snd dependent)
  printLn (dependent .fst, dependent .snd)
  printLn (sumLPair (5 # 6))
  printLn (resValue (8 # "eight"))
  printLn (force lazyInt)
  printLn (the Char (fromChar @{defaultChar} 'c'))
  printLn (the Double (fromDouble @{defaultDouble} 2.5))
  printLn (the String (fromString @{defaultString} "literal"))
  printLn (unbox (rewriteBox (the (3 = 3) Refl) (MkBox 9)))
  printLn (unbox (rewriteBox' (the (4 = 4) Refl) (MkBox 19)))
  printLn (transport (the (Int = Int) Refl) 10)
