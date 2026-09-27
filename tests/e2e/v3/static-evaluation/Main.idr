module Main

-- rule: ELIM-G-19, ELIM-G-2, PROF-PRIM-4, SEM-BIG-1
-- Calls whose arguments are all known are evaluated during specialization,
-- and constructors of known values stay known: the conditions below are
-- decided at compile time, so the string match in `firstIs`, which could
-- not run at runtime, is never reached. This is the shape of the Prelude's
-- `show` for numbers.

import Builtin
import IdrisMLIR.IO

data Bool = False | True

data Prec = Open | PrefixMinus

rank : Prec -> Integer
rank Open = 0
rank PrefixMinus = 5

atLeast : Prec -> Prec -> Bool
atLeast a b = case prim__lte_Integer (rank b) (rank a) of
  0 => False
  _ => True

and : Bool -> Lazy Bool -> Bool
and True b = b
and False _ = False

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
showNum : Prec -> Int -> String
showNum d n = let s = prim__cast_IntString n in parens (and (atLeast d PrefixMinus) (firstIs '-' s)) s

partial
main : IO ()
main = do
  c <- getChar
  d <- getChar
  let n = prim__sub_Int 48 (prim__cast_CharInt d)
  putStrLn (showNum Open n)
