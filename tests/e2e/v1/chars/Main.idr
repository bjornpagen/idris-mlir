module Main

import Prelude

-- rule: SEM-CHAR-1, SEM-CHAR-2, SEM-CHAR-3, PROF-PRIM-3, IDR-CHAR-1, LOW-CHAR-1
-- The Prelude's putChar agrees with the reference only on ASCII (SEM-IO-2),
-- so 'λ' is written as a string. Its getChar reads one byte (SEM-IO-7): the
-- first of the two bytes of the 'é' on stdin, 195.
main : IO ()
main = do
  putStrLn (prim__cast_IntString (prim__cast_CharInt 'λ'))
  putStrLn (prim__cast_IntString (prim__lt_Char 'a' 'b'))
  putStrLn (prim__cast_IntString (prim__cast_CharInt (prim__cast_IntChar 55296)))
  putStrLn (prim__cast_IntString (prim__cast_CharInt (prim__cast_IntChar 1114112)))
  putStrLn (prim__cast_IntString (prim__cast_CharInt (prim__cast_IntChar (-5))))
  putStr (prim__cast_CharString (prim__cast_IntChar 955))
  putChar (prim__cast_Bits8Char (prim__cast_IntBits8 65))
  putStrLn ""
  c <- getChar
  putStrLn (prim__cast_IntString (prim__cast_CharInt (prim__cast_IntChar (prim__add_Int (prim__cast_CharInt c) 55200))))
  putStrLn (prim__cast_Bits8String (prim__cast_CharBits8 c))
