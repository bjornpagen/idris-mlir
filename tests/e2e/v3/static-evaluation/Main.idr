module Main

-- rule: ELIM-G-19, ELIM-G-2, PROF-PRIM-4, SEM-BIG-1
-- Calls whose arguments are all known are evaluated during specialization,
-- and constructors of known values stay known: the conditions below are
-- decided at compile time, so the string match in `firstIs`, which could
-- not run at runtime, is never reached. This is the shape of the Prelude's
-- `show` for numbers: `Level` is its `Prec` cut down to `Open` and
-- `PrefixMinus`, here `Low` and `High`, and `both` is its `&&`.

import Builtin
import Prelude

data Level = Low | High

rank : Level -> Integer
rank Low = 0
rank High = 5

atLeast : Level -> Level -> Bool
atLeast a b = case prim__lte_Integer (rank b) (rank a) of
  0 => False
  _ => True

both : Bool -> Lazy Bool -> Bool
both True b = b
both False _ = False

partial
firstIs : Char -> String -> Bool
firstIs c "" = False
firstIs c s = case prim__eq_Char (prim__strHead s) c of
  0 => False
  _ => True

parens : Bool -> String -> String
parens False s = s
parens True s = prim__strAppend "(" (prim__strAppend s ")")

partial
showNum : Level -> Int -> String
showNum d n = let s = prim__cast_IntString n in parens (both (atLeast d High) (firstIs '-' s)) s

partial
main : IO ()
main = do
  c <- getChar
  d <- getChar
  let n = prim__sub_Int 48 (prim__cast_CharInt d)
  putStrLn (showNum Low n)
