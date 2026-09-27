-- expect: PROF-HEAP-3 line 22
-- message: a string is built at runtime here and is not written directly by putStr
module Main

-- rule: DIAG-ONE-1
-- `report` cannot be raised (PROF-HEAP-5), but PROF-HEAP-5 is decided once
-- specialization is finished, so the PROF-HEAP-3 error found during it is
-- the one reported.

import IdrisMLIR.IO

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
