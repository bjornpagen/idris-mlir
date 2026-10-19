module Main

-- A definition at quantity 0 whose clauses write a constant or a type on an
-- erased argument. The pinned Idris takes such a pattern as a variable in
-- the definition's case tree, as in a definition that runs, where an erased
-- argument cannot be matched: it reports `h _` unreachable, reduces `h 5`
-- to 1, and refuses `hFive` and `five` below.
-- The fork carries upstream/53-constructor-implicit-mark/pull-request.diff,
-- which fixes upstream/54-erased-constant-pattern; when a re-sync brings
-- upstream's fix, this test goes with the reports (upstream/README.md).

import Prelude

%default total

0 h : (0 n : Integer) -> Integer
h 0 = 1
h _ = 2

hFive : h 5 = 2
hFive = Refl

-- A value whose type holds `h 5`, which only `Two` can be.
data Count : Integer -> Type where
  Two : Count 2

five : Count (h 5)
five = Two

describe : Count n -> String
describe Two = "2"

-- A type, and a constant on an erased field.
0 tp : (0 t : Type) -> Integer
tp Integer = 1
tp _ = 2

tpString : tp String = 2
tpString = Refl

data P : Type where
  MkP : (0 n : Integer) -> P

0 pv : P -> Integer
pv (MkP 0) = 1
pv (MkP _) = 2

pvFive : pv (MkP 5) = 2
pvFive = Refl

-- A type a constructor's implicit takes by unification is no match:
-- `(::)`'s element type is Integer here, and `len` covers every list.
0 len : List Integer -> Nat
len [] = 0
len (_ :: xs) = S (len xs)

lenTwo : len [1, 2] = 2
lenTwo = Refl

-- The same inside a pattern unification fixed: `All`'s implicit `x` is
-- found to be the pair the clause writes, and the types in it are no match.
data All : (0 p : a -> Type) -> List a -> Type where
  Nil : All p []
  (::) : {0 xs : List a} -> p x -> All p xs -> All p (x :: xs)

data Pos : Nat -> Type where
  IsPos : Pos (S n)

0 heads : (hs : List (Nat, Bool)) -> All (\e => Pos (fst e)) hs -> List Nat
heads [] [] = []
heads ((i, a) :: hs) (_ :: ps) = i :: heads hs ps

headsTwo : heads [(1, True), (2, False)] [IsPos, IsPos] = [1, 2]
headsTwo = Refl

main : IO ()
main = putStrLn (describe five)
