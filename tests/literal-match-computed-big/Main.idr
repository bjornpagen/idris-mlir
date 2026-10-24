module Main

import Prelude

-- A match on an Integer past the small range (-2^62 to 2^62 - 1) that the
-- compiler computes is decided where it is compiled, by the runtime's
-- comparison of the big with each key, the test the match makes when it
-- runs. pick is called once and holds no call, so its match lands in
-- main, on 10^20 * 3: a big the compiler computes, which the match takes
-- at the hold the product gives it, one its count frees, where no
-- constant stands. The key 3 is in the small range and the scrutinee past
-- it, which the comparison tells apart by the scrutinee's sign; the key
-- 3 * 10^20 is taken. The default divides by the byte the run reads,
-- behind a guard; so once the match is decided no guard is left in main,
-- and nothing of main computes on constants alone, the product gone with
-- the match, since the case it takes reads nothing of its scrutinee. The
-- byte read is 0, so the default would end the run by its guard: the run
-- writes 7.

partial
pick : Integer -> Int -> Int
pick 300000000000000000000 _ = 7
pick 3 _ = 8
pick _ d = prim__div_Int 100 d

partial
main : IO ()
main = do
  c <- getChar
  putStrLn (prim__cast_IntString (pick (prim__mul_Integer 100000000000000000000 3) (prim__cast_CharInt c)))
