module Main

import Prelude

-- A string built from a runtime number, matched: the match compares its
-- bytes at runtime, and the string is freed after it. The alternatives
-- share prefixes ("9" of "97", "25" of "255") and lengths ("97" and "98"),
-- so only the whole of the bytes decides.
main : IO ()
main = do
  c <- getChar
  case prim__cast_IntString (prim__cast_CharInt c) of
    "97" => putStrLn "a"
    "9" => putStrLn "tab"
    "98" => putStrLn "b"
    "255" => putStrLn "end"
    "25" => putStrLn "end of medium"
    "0" => putStrLn "nul"
    _ => putStrLn "other"
