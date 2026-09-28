-- expect: PROF-PRIM-2 line 21
module Main

-- rule: DIAG-ONE-1, PROF-TYPE-4
-- Two violations: `count` makes an Integer from a runtime value, which
-- idr-check-profile rejects with PROF-TYPE-4 on the optimized module, and
-- `shift`, defined and used after it, uses a primitive the frontend rejects
-- (PROF-PRIM-2). Frontend errors come first (docs/cutover.md 3.9): the
-- frontend rejects the program before idris-mlir-cc sees it, so PROF-PRIM-2
-- is the only error reported, though `count` comes first in the file and
-- in main.

import Prelude

partial
count : Int -> Int
count 0 = 0
count n = prim__add_Int (prim__cast_IntegerInt (prim__div_Integer (prim__cast_IntInteger n) 3))
                        (count (prim__sub_Int n 1))

shift : Int -> Int
shift x = prim__shl_Int x 3

partial
main : IO ()
main = do
  c <- getChar
  putStrLn (prim__cast_IntString (count (prim__cast_CharInt c)))
  putStrLn (prim__cast_IntString (shift (prim__cast_CharInt c)))
