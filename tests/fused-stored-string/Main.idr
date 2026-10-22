module Main

-- The string built at runtime is stored in a constructor and taken out
-- again, but `idr.data.field` of a known `idr.data.con` folds, so
-- `putStrLn (strCons c "!")` reaches output fusion and becomes put_char
-- then put_str; no string is built at runtime. getChar reads a byte as the
-- character of that number, which is written in UTF-8: one byte below
-- 0x80, two from it on. On empty stdin the Prelude's getChar returns
-- character 255, so the program writes U+00FF in UTF-8 (C3 BF), then "!\n".

import Prelude

data Box : Type where
  MkBox : String -> Box

unbox : Box -> String
unbox (MkBox s) = s

main : IO ()
main = do
  c <- getChar
  putStrLn (unbox (MkBox (prim__strCons c "!")))
