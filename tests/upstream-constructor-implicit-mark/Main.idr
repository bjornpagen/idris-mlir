module Main

-- Definitions whose clauses leave a constructor's implicit argument to the
-- elaborator: `x` of `C1` and of `C2`, which the pattern of the
-- constructor's field fixes. The pinned Idris keeps no mark of it in the
-- checked clause, splits it first in their case trees, finds `A` and `B`
-- unmatched, and cannot see that `All IsF [A]` is empty, so it reports
-- `v1` and `v3` not covering and refuses the module.
-- The fork carries upstream/53-constructor-implicit-mark/pull-request.diff,
-- with upstream/52-relevant-implicit-split's order; when a re-sync brings
-- upstream's fix, this test goes with the report (upstream/README.md).

import Prelude

%default total

-- As base's Data.List.Quantifiers.All, with the same quantities.
data All : (0 p : a -> Type) -> List a -> Type where
  Nil : All p []
  (::) : {0 xs : List a} -> p x -> All p xs -> All p (x :: xs)

data W = A | F Integer | B

data IsF : W -> Type where
  ItIsF : IsF (F w)

-- `x` relevant, in a definition that runs.
data T1 : Type where
  C1 : {x : W} -> All IsF [x] -> T1

v1 : T1 -> Integer
v1 (C1 (ItIsF :: [])) = 1

-- `x` erased, in a definition at quantity 0, which computes in a type.
data T2 : Type where
  C2 : {0 x : W} -> All IsF [x] -> T2

0 v3 : T2 -> Integer
v3 (C2 (ItIsF :: [])) = 3

v3Three : v3 (C2 (ItIsF {w = 7} :: [])) = 3
v3Three = Refl

-- An implicit the clause writes is still a match, at either quantity:
-- `C3 {x = B}` takes the second clause.
data T3 : Type where
  C3 : {x : W} -> T3

w3 : T3 -> Integer
w3 (C3 {x = A}) = 1
w3 _ = 2

data T4 : Type where
  C4 : {0 x : W} -> T4

0 w4 : T4 -> Integer
w4 (C4 {x = A}) = 1
w4 _ = 2

w4B : w4 (C4 {x = B}) = 2
w4B = Refl

main : IO ()
main = do
  printLn (v1 (C1 (ItIsF {w = 5} :: [])), w3 (C3 {x = B}))
  -- Each of C3's implicits: A takes the first clause, the others the second.
  printLn (w3 (C3 {x = A}), w3 (C3 {x = F 3}))
