module Main

-- A sum of 70,000 constructors, more than a tag of 16 bits tells apart:
-- its values keep their constructors on both sides of 65,536, a match
-- tells each from the others, and the constructors with fields keep them.
-- The run script writes the constructors where the line `-- CONSTRUCTORS`
-- is, C0 to C69999, C65535 with an Int and C65536 with a String, so their
-- number is said once.

import Prelude

data Many : Type where
-- CONSTRUCTORS

name : Many -> String
name C0 = "C0"
name (C65535 x) = "C65535 " ++ show x
name (C65536 s) = "C65536 " ++ s
name C69999 = "C69999"
name _ = "another"

-- A constructor chosen by a character read at run time, so no value is
-- known before.
pick : String -> Char -> Many
pick w 'a' = C0
pick w 'b' = C65535 (cast (length w))
pick w 'c' = C65536 w
pick w 'd' = C69999
pick w _ = C1

main : IO ()
main = do
  w <- getLine
  traverse_ (putStrLn . name . pick w) (unpack w)
