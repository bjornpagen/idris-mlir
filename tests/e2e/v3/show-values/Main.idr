module Main

-- rule: ELIM-G-14, ELIM-G-15, IDR-DBL-3, LOW-DBL-4
-- The Prelude's show for constructors, which parenthesizes a number that
-- starts with '-': the first character of a number shown at runtime is its
-- sign or its leading digit. Checked directly with strHead across sizes and
-- integer types, and through show on Maybe, Either and pairs.

import Prelude
import IdrisMLIR.IO

partial
firstOf : String -> Char
firstOf s = prim__strHead s

-- One output channel: on Chez the Prelude's and IdrisMLIR.IO's output go
-- through different buffers.
say : String -> IO ()
say = IdrisMLIR.IO.putStrLn

char : Char -> IO ()
char = IdrisMLIR.IO.putChar

partial
main : IO ()
main = do
  c <- getChar
  let n = the Int (cast (ord c) - 48)
  say (show (Just n))
  say (show (Just (negate n)))
  say (show (the (Either Int Int) (Right (0 - n)), (n, negate n)))
  say (show (Just (Just (negate n))))
  char (firstOf (show (n * 123456789)))
  char (firstOf (show (n * 0)))
  char (firstOf (show (n + 2)))
  char (firstOf (show (n * 10 + 3)))
  char (firstOf (show (n * 1000000000000000000)))
  char (firstOf (show (negate n * 1000)))
  char (firstOf (show (the Bits8 (cast (n * 30)))))
  char (firstOf (show (the Int8 (cast (n * 30)))))
  char (firstOf (show (the Bits64 (cast (negate n)))))
  char '\n'
  -- A Double's first character is the printer's own (LOW-DBL-4).
  let x = the Double (cast n)
  say (show (Just (x / 2.0)))
  say (show (Just (negate x / 2.0)))
  say (show (Just (negate (x - x))))
  say (show (Just ((x - x) / (x - x))))
  say (show (Just (negate x / 0.0)))
  say (show (Just (x * 1.4285714285714285e22)))
  say (show (Just (x * 5.0e-324)))
