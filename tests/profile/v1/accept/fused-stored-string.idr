-- exit: 0
-- stdout: \0303\0277!\n
module Main

-- The string built at runtime is stored in a constructor and taken out
-- again, but `idr.field` of a known `idr.con` folds, so
-- `putStrLn (strCons c "!")` reaches output fusion and becomes put_char
-- then put_str; no string is built at runtime. On empty stdin the Prelude's
-- getChar returns character 255, so the program writes U+00FF in UTF-8
-- (C3 BF), then "!\n".

import Prelude

data Box : Type where
  MkBox : String -> Box

unbox : Box -> String
unbox (MkBox s) = s

main : IO ()
main = do
  c <- getChar
  putStrLn (unbox (MkBox (prim__strCons c "!")))
