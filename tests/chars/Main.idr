module Main

import Prelude

-- The Char primitives. A cast to Char of an Int that is no Unicode scalar
-- value (a surrogate, one past U+10FFFF, a negative) is the character 0.
-- The constants cross each end of the surrogates (55295 and 55296, 57343
-- and 57344) and the last scalar value, U+10FFFF. getChar reads one byte:
-- the first of the two bytes of the 'é' on stdin, 195. Plus 55200 it is a
-- surrogate, which casts to 0; so is every byte from 0x60 on, and none
-- below it (0x5F plus 55200 is 55295). The end of input reads as 255.
main : IO ()
main = do
  putStrLn (prim__cast_IntString (prim__cast_CharInt 'λ'))
  putStrLn (prim__cast_IntString (prim__lt_Char 'a' 'b'))
  putStrLn (prim__cast_IntString (prim__cast_CharInt (prim__cast_IntChar 55296)))
  putStrLn (prim__cast_IntString (prim__cast_CharInt (prim__cast_IntChar 1114112)))
  putStrLn (prim__cast_IntString (prim__cast_CharInt (prim__cast_IntChar (-5))))
  putStrLn (prim__cast_IntString (prim__cast_CharInt (prim__cast_IntChar 1114111)))
  putStrLn (prim__cast_IntString (prim__cast_CharInt (prim__cast_IntChar 57343)))
  putStrLn (prim__cast_IntString (prim__cast_CharInt (prim__cast_IntChar 57344)))
  putStrLn (prim__cast_IntString (prim__cast_CharInt (prim__cast_IntChar 55295)))
  putStr (prim__cast_CharString (prim__cast_IntChar 955))
  putChar (prim__cast_Bits8Char (prim__cast_IntBits8 65))
  putStrLn ""
  c <- getChar
  putStrLn (prim__cast_IntString (prim__cast_CharInt (prim__cast_IntChar (prim__add_Int (prim__cast_CharInt c) 55200))))
  putStrLn (prim__cast_Bits8String (prim__cast_CharBits8 c))
