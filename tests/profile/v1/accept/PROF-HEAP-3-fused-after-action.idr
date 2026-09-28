-- exit: 0
-- stdout: ready\n0\n\0303\0277!\n
module Main

-- rule: PROF-HEAP-3, PROF-HEAP-1, ELIM-G-7, OPT-SAFE-1
-- Was the reject fixture PROF-HEAP-3-reported-before-heap-5, and is an
-- accept since the cutover (PROF-GEN-4): `idr.field` of a known
-- `idr.con` folds and output fusion writes `strCons c "!"` as put_char then
-- put_str, and `report`'s action becomes a direct call once inlining and
-- defunctionalization remove IO's closures, with PROF-HEAP-5 (arity
-- raising) withdrawn. DIAG-ONE-1, which this fixture tested, has its own
-- test: v3/reject/PROF-DATA-3-first-of-two.
-- On empty stdin getChar returns character 255 (SEM-IO-7): `report 255`
-- writes 100 div 255 = 0, then U+00FF in UTF-8 (C3 BF) and "!".

import Prelude

partial
report : Int -> IO ()
report d = let q = prim__div_Int 100 d in putStrLn (prim__cast_IntString q)

data Box : Type where
  MkBox : String -> Box

unbox : Box -> String
unbox (MkBox s) = s

partial
main : IO ()
main = do
  c <- getChar
  let action = report (prim__cast_CharInt c)
  putStrLn "ready"
  action
  putStrLn (unbox (MkBox (prim__strCons c "!")))
