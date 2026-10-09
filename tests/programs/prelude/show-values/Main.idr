module Main

-- The Prelude's show for constructors, which parenthesizes a number that
-- starts with '-': the first character of a number shown at runtime is its
-- sign or its leading digit. Checked directly with strHead across sizes and
-- integer types, and through show on Maybe, Either and pairs.

import Prelude

partial
firstOf : String -> Char
firstOf s = prim__strHead s

partial
main : IO ()
main = do
  c <- getChar
  let n = the Int (cast (ord c) - 48)
  putStrLn (show (Just n))
  putStrLn (show (Just (negate n)))
  putStrLn (show (the (Either Int Int) (Right (0 - n)), (n, negate n)))
  putStrLn (show (Just (Just (negate n))))
  putChar (firstOf (show (n * 123456789)))
  putChar (firstOf (show (n * 0)))
  putChar (firstOf (show (n + 2)))
  putChar (firstOf (show (n * 10 + 3)))
  putChar (firstOf (show (n * 1000000000000000000)))
  putChar (firstOf (show (negate n * 1000)))
  putChar (firstOf (show (the Bits8 (cast (n * 30)))))
  putChar (firstOf (show (the Int8 (cast (n * 30)))))
  putChar (firstOf (show (the Bits64 (cast (negate n)))))
  putChar '\n'
  -- A Double's first character is the printer's own. The fixtures
  -- double-infinities-nan and double-subnormals show the infinities, NaN
  -- and subnormals.
  let x = the Double (cast n)
  putStrLn (show (Just (x / 2.0)))
  putStrLn (show (Just (negate x / 2.0)))
  putStrLn (show (Just (negate (x - x))))
  putStrLn (show (Just (x * 1.4285714285714285e22)))
