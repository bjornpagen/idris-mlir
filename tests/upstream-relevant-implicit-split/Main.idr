module Main

-- Definitions that run, whose clauses leave a relevant list index, `ws`, to
-- the elaborator: the patterns of the explicit argument fix it. The pinned
-- Idris splits `ws` first in the coverage check's case tree, finds `A :: _`
-- and `B :: _` unmatched, and cannot see that `All IsF (A :: _)` is empty,
-- so it reports each not covering and refuses the module. The fork's
-- coverage check splits `ws` after the patterns that fix it. The tree each
-- definition keeps is the program that runs, and it splits `ws` as before:
-- `sumF` reads at run time the `w` that only `ws` holds, and `fp4` passes on
-- its tail.
-- The fork carries upstream/52-relevant-implicit-split/pull-request.diff;
-- when a re-sync brings upstream's fix, this test goes with the report
-- (upstream/README.md).

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

-- `ws` relevant, bound in the type.
fp4 : {ws : List W} -> All IsF ws -> All Pr ws
fp4 [] = []
fp4 (ItIsF :: fs) = M1 :: fp4 fs

-- `w` is erased in `ItIsF`; the right-hand side reads it from `ws`.
sumF : {ws : List W} -> All IsF ws -> Integer
sumF [] = 0
sumF (ItIsF {w} :: fs) = w + sumF fs

-- A case block and a with block, whose environment holds `ws`.
cb : {ws : List W} -> All IsF ws -> Nat
cb xs = case xs of
  [] => 0
  (ItIsF :: _) => 1

wb : {ws : List W} -> All IsF ws -> Bool -> Nat
wb xs b with (b)
  wb [] b | True = 0
  wb (ItIsF :: _) b | True = 1
  wb _ b | False = 2

-- A later argument's type computes on the index the clauses leave out, so
-- the case tree has to split the index before that argument.
Rel : Type -> Type
Rel a = a -> a -> Type

Lift : Rel a -> a -> Rel a
Lift r x = \y, z => Either (r y z) (r x y)

Lifted : Rel a -> List a -> Rel a
Lifted r [] = r
Lifted r (x :: xs) = Lift (Lifted r xs) x

New : Rel a -> List a -> a -> Type
New r xs x = All (\y => Not (r y x)) xs

namespace Bad
  public export
  data Bad : Rel a -> List a -> Type where
    Nil : Bad r []
    (::) : New r xs x -> Bad r xs -> Bad r (x :: xs)

liftedBad : {0 r : Rel a} -> Bad r xs -> New r xs y -> Lifted r xs y z -> r y z
liftedBad [] [] l = l
liftedBad (nx :: bxs) (ny :: nys) (Left l) = liftedBad bxs nys l
liftedBad (nx :: bxs) (ny :: nys) (Right l) = absurd (ny (liftedBad bxs nx l))

-- The proofs `fp4` builds, counted.
count : {ws : List W} -> All Pr ws -> Nat
count [] = 0
count (_ :: ps) = S (count ps)

-- Its tree reduces in a type.
sumTwo : sumF (ItIsF {w = 1} :: ItIsF {w = 2} :: []) = 3
sumTwo = Refl

main : IO ()
main = do
  let xs = the (All IsF [F 40, F 1, F 1]) [ItIsF, ItIsF, ItIsF]
  printLn (sumF xs)
  printLn (count (fp4 xs))
  printLn (cb xs)
  printLn (wb xs True)
  printLn (wb xs False)
  printLn (cb [])
