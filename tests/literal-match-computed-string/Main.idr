module Main

import Prelude

-- A match on a string the compiler computes is decided where it is
-- compiled, by the runtime's comparison of the string with each key, the
-- test the match makes when it runs. pick is called once and holds no
-- call, so its match lands in main, on "a" ++ "b": a string the compiler
-- computes, which the match takes at the hold the append gives it, one
-- its count frees, where no constant stands. The case "ab" is taken. The
-- default divides by the byte the run reads, behind a guard; so once the
-- match is decided no guard is left in main, and nothing of main computes
-- on constants alone, the append gone with the match, since the case it
-- takes reads nothing of its scrutinee. The byte read is 0, so the default
-- would end the run by its guard: the run writes 7.

partial
pick : String -> Int -> Int
pick "ab" _ = 7
pick "ba" _ = 8
pick _ d = prim__div_Int 100 d

partial
main : IO ()
main = do
  c <- getChar
  putStrLn (prim__cast_IntString (pick (prim__strAppend "a" "b") (prim__cast_CharInt c)))
