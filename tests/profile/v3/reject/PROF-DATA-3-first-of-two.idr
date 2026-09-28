-- expect: PROF-DATA-3 line 29
module Main

-- rule: DIAG-ONE-1, SEM-REC-1, PROF-TYPE-4
-- Two violations, and only the first is reported. `build` makes a list
-- whose length is known only at runtime (PROF-DATA-3, as
-- PROF-DATA-3-runtime-list), and `count` computes with an Integer made from
-- a runtime value (PROF-TYPE-4, as PROF-TYPE-4-integer). Neither function is
-- inlined, since both are recursive, and nothing of either reaches `main`
-- but an Int; both are checked by idr-check-profile, where "first" is in op
-- order (docs/cutover.md 3.9), and `build` comes before `count` in the
-- module, as `main` calls it first. The error is reported at the user
-- definition that holds the op, `build`.
-- Unverified until idris-mlir-cc exists: the line is predicted from the
-- emitted module, where the ops of `build` carry its definition's location,
-- and from op order being the module's order (main, len, build, count).

import Prelude

data L : Type where
  Nil : L
  Cons : Int -> L -> L

len : L -> Int
len Nil = 0
len (Cons _ xs) = prim__add_Int 1 (len xs)

-- The first violation: a runtime list.
build : Int -> L
build 0 = Nil
build n = Cons n (build (prim__sub_Int n 1))

-- The second: an Integer at runtime, which never leaves `count`.
partial
count : Int -> Int
count 0 = 0
count n = prim__add_Int (prim__cast_IntegerInt (prim__div_Integer (prim__cast_IntInteger n) 3))
                        (count (prim__sub_Int n 1))

partial
main : IO ()
main = do
  c <- getChar
  putStrLn (prim__cast_IntString (len (build (prim__cast_CharInt c))))
  putStrLn (prim__cast_IntString (count (prim__cast_CharInt c)))
