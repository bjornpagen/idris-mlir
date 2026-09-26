module Main

import IdrisMLIR.IO

-- rule: FE-TR-1
-- TTC drops the types of lets; they are inferred from the values.
main : IO ()
main = do
  let n = prim__add_Int 1 2
  let s = "three"
  let c = 'x'
  putStrLn (prim__strAppend s (prim__strAppend " " (prim__cast_IntString n)))
  putChar c
  putStrLn ""
