module Main

-- `cast` from String reads the whole string as an optional sign and a
-- literal of the target type as Idris writes it; any other string is 0.
-- Every number type reads an integer literal, in any base and with
-- underscores, an integer type modulo its width; Double also reads a
-- decimal literal, a double's text as `show` writes it, and IEEE 754's
-- inf, infinity and nan, in any case. The lines of stdin are cast at run
-- time, the constants at the end by the compiler, through the same runtime.
-- Each line: the string, then it as an Int, a Bits8, an Integer and a
-- Double, NaN and the infinities by name. Chez reads a string as a Scheme
-- number and truncates it to an integer (chez-differs).

import Prelude

double : Double -> String
double d =
  if d /= d then "NaN"
  else if d > 1.0e308 then "+infinity"
  else if d < -1.0e308 then "-infinity"
  else show d

casts : String -> String
casts s =
  s ++ ": " ++ show (the Int (cast s)) ++ " " ++ show (the Bits8 (cast s)) ++ " "
    ++ show (the Integer (cast s)) ++ " " ++ double (cast s)

partial
readLines : IO ()
readLines = do
  l <- getLine
  if l == "end"
     then pure ()
     else do
       putStrLn (casts l)
       readLines

partial
main : IO ()
main = do
  readLines
  putStrLn (casts "-1_0")
  putStrLn (casts "0x_1")
  putStrLn (casts "2.5e-3")
