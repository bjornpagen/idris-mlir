module Main

-- Erased definitions whose clauses leave an argument to the elaborator: the
-- list `ws`, which the patterns of the explicit argument fix. The pinned
-- Idris splits it first in their case trees, finds `A :: _` and `B :: _`
-- unmatched, and cannot see that `All IsF (A :: _)` is empty, so it reports
-- `fp` and `fp3` not covering and refuses the module.
-- The stock Idris still has the bug; the type checker fixes it as its own
-- code (a checked clause marks the arguments it leaves to unification, and
-- a case tree splits them after what it writes), and this test checks
-- that fix.

import Prelude

%default total

-- As base's Data.List.Quantifiers.All, with the same quantities.
data All : (0 p : a -> Type) -> List a -> Type where
  Nil : All p []
  (::) : {0 xs : List a} -> p x -> All p xs -> All p (x :: xs)

data W = A | F Integer | B

data IsF : W -> Type where
  ItIsF : IsF (F w)

data Pr : W -> Type where
  M1 : Pr (F w)
  M2 : Pr B

-- `ws` an unbound implicit, at quantity 0.
0 fp : All IsF ws -> All Pr ws
fp [] = []
fp (ItIsF :: fs) = M1 :: fp fs

-- `ws` bound in the type, at quantity ω.
0 fp3 : {ws : List W} -> All IsF ws -> All Pr ws
fp3 [] = []
fp3 (ItIsF :: fs) = M1 :: fp3 fs

-- Both compute in types.
fpTwo : fp (ItIsF {w = 1} :: ItIsF {w = 2} :: []) = M1 :: M1 :: []
fpTwo = Refl

fp3Two : fp3 (ItIsF {w = 1} :: ItIsF {w = 2} :: []) = M1 :: M1 :: []
fp3Two = Refl

-- A pattern the clause writes on an erased argument is still a match: `g 5`
-- takes the second clause.
0 g : (0 n : Nat) -> Nat
g Z = 1
g _ = 2

gFive : g 5 = 2
gFive = Refl

gZero : g Z = 1
gZero = Refl

fpNone : fp [] = []
fpNone = Refl

-- A case on a variable, here in a type: the alternative's pattern is the
-- clause's own, although it sits in the as-pattern that names the variable.
0 Pick : Bool -> Type
Pick b = if b then Nat else String

pickFalse : Pick False = String
pickFalse = Refl

pickTrue : Pick True = Nat
pickTrue = Refl

main : IO ()
main = putStrLn "covering"
