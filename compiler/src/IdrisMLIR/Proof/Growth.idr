-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The graph the growth check decides, and the certificates its answers
||| carry.
|||
||| A position is a static argument of a definition. An arc says how far a
||| value written at its target can stand above the value at its source: a
||| weight `Finite gain loss` raises it by at most gain - loss, and `Stuck`
||| by nothing anyone can bound. A cap's one arc leaves the origin, which
||| holds 0.
|||
||| The check answers with one of three certificates, each a type only a
||| true answer inhabits:
||| - a cycle of positions, its finite arcs chained by index, whose gains
|||   exceed its losses: a static argument grows each round;
||| - a Stuck arc: a type-level recursion nothing bounds;
||| - a potential every arc satisfies: a bound on every position.
||| The check builds each from the machine's comparisons of naturals, and the
||| proofs that they mean what the type says are erased, so a certificate
||| costs its comparisons. Every inequality adds a weight's loss to the other
||| side, so it is one of naturals.
module IdrisMLIR.Proof.Growth

import public Data.Fin
import public Data.List
import public Data.List.Elem
import public Data.List.Quantifiers
import Data.Nat
import Data.So
import public Data.Vect

%default total

------------------------------------------------------------------------------
-- Deciding at run time
------------------------------------------------------------------------------

||| A decision as the frontend makes it at run time: the evidence that it
||| holds, which the frontend reads, or the erased evidence that it does
||| not.
public export
data Decision : Type -> Type where
  Holds : p -> Decision p
  Fails : (0 _ : Not p) -> Decision p

-- The machine compares naturals as integers, at a cost that does not grow
-- with them; these read its answer as a proof. Each recurses on the
-- numbers, so a decision uses them only where the proof is erased.

||| `<=` on naturals, as the machine compares them, is `LTE`.
export
lteSo : {b, a : Nat} -> So (b <= a) -> LTE b a
lteSo {b = Z} _ = LTEZero
lteSo {b = S b} {a = S a} so = LTESucc (lteSo so)
lteSo {b = S _} {a = Z} so = absurd so

export
notLteSo : {b, a : Nat} -> So (not (b <= a)) -> Not (LTE b a)
notLteSo {b = Z} {a = Z} so _ = absurd so
notLteSo {b = Z} {a = S _} so _ = absurd so
notLteSo {b = S b} {a = S a} so (LTESucc le) = notLteSo so le
notLteSo {b = S _} {a = Z} _ le = absurd le

||| `<` on naturals, as the machine compares them, is `LT`.
export
ltSo : {b, a : Nat} -> So (b < a) -> LT b a
ltSo so = ltOpReflectsLT b a so

export
notLtSo : {b, a : Nat} -> So (not (b < a)) -> Not (LT b a)
notLtSo {b = Z} {a = S _} so _ = absurd so
notLtSo {b = S b} {a = S a} so (LTESucc lt) = notLtSo so lt
notLtSo {a = Z} _ lt = absurd lt

||| Equal naturals, as the machine compares them.
export
equalSo : {m, n : Nat} -> So (m == n) -> m = n
equalSo {m = Z} {n = Z} _ = Refl
equalSo {m = S m} {n = S n} so = cong S (equalSo so)
equalSo {m = Z} {n = S _} so = absurd so
equalSo {m = S _} {n = Z} so = absurd so

||| A natural compares equal to itself.
export
equalSelf : (m : Nat) -> So (m == m)
equalSelf Z = Oh
equalSelf (S m) = equalSelf m

||| Two positions, as the machine compares them: a `Fin` is the number it
||| is, at run time as in proofs.
export
samePosition : (x, y : Fin n) -> Decision (x = y)
samePosition x y = case choose (finToNat x == finToNat y) of
  Left so => Holds (irrelevantEq (injective {f = finToNat} (equalSo so)))
  Right no => Fails (\Refl => soNotToNotSo no (equalSelf (finToNat x)))

------------------------------------------------------------------------------
-- Weights
------------------------------------------------------------------------------

||| What an arc raises a value by: Absent where there is no arc, gain - loss,
||| or Stuck, by nothing anyone can bound. A finite weight is two naturals,
||| so that every comparison of two is one of naturals, by cross-addition.
public export
data Weight = Absent | Finite Nat Nat | Stuck

||| Composition along a path: Absent absorbs, Stuck absorbs Finite, Finite adds.
public export
plus : Weight -> Weight -> Weight
plus Absent _ = Absent
plus _ Absent = Absent
plus Stuck _ = Stuck
plus _ Stuck = Stuck
plus (Finite g l) (Finite g' l') = Finite (g + g') (l + l')

||| The maximum, Absent < Finite < Stuck, Finite by cross-addition.
public export
join : Weight -> Weight -> Weight
join Absent w = w
join w Absent = w
join Stuck _ = Stuck
join _ Stuck = Stuck
join (Finite g l) (Finite g' l') = if g + l' <= g' + l then Finite g' l' else Finite g l

------------------------------------------------------------------------------
-- The graph
------------------------------------------------------------------------------

||| A weight an arc can carry: an absent label is no arc.
public export
data Present : Weight -> Type where
  Measured : Present (Finite g l)
  Unmeasured : Present Stuck

export
0 presentNotAbsent : Present Absent -> Void
presentNotAbsent Measured impossible
presentNotAbsent Unmeasured impossible

||| An arc from a position, or from the origin (`Nothing`, a cap's one arc),
||| to a position.
public export
record Arc (n : Nat) where
  constructor MkArc
  from : Maybe (Fin n)
  to : Fin n
  weight : Weight
  0 present : Present weight

||| The positions `Fin size`, the arcs between them, the tallest constant K
||| of any template, and each position's cap, where its type inspects its
||| value to a fixed depth.
public export
record Graph where
  constructor MkGraph
  size : Nat
  arcs : List (Arc size)
  constant : Nat
  caps : Vect size (Maybe Nat)

||| The arc at an index: the one meaning of an index, which every
||| certificate states its arcs by.
public export
arc : (g : Graph) -> Fin (length g.arcs) -> Arc g.size
arc g = index' g.arcs

public export
weights : (g : Graph) -> List (Fin (length g.arcs)) -> List Weight
weights g = map (\a => (arc g a).weight)

------------------------------------------------------------------------------
-- Reading many arcs in one pass
------------------------------------------------------------------------------

||| The arcs at a list of indices, each with its equality to `arc g a`.
namespace At
  public export
  data At : (g : Graph) -> List (Fin (length g.arcs)) -> Type where
    Nil : At g []
    (::) : (x : Arc g.size) -> (0 _ : x = arc g a) -> At g as -> At g (a :: as)

0 dropSucc : {0 x : a} -> {0 rest : List a} -> (ys : List a) -> (k : Nat) ->
             drop k ys = x :: rest -> drop (S k) ys = rest
dropSucc (y :: ys) Z eq = cong (\l => case l of { (_ :: t) => t; [] => [] }) eq
dropSucc (y :: ys) (S k) eq = dropSucc ys k eq
dropSucc [] Z eq = absurd eq
dropSucc [] (S k) eq = absurd eq

0 dropIndex : (ys : List a) -> (i : Fin (length ys)) -> (rest ** drop (finToNat i) ys = index' ys i :: rest)
dropIndex (y :: ys) FZ = (ys ** Refl)
dropIndex (y :: ys) (FS i) = dropIndex ys i

0 dropNil : (n : Nat) -> drop n (the (List a) []) = []
dropNil Z = Refl
dropNil (S _) = Refl

0 dropDrop : (d, k : Nat) -> (ys : List a) -> drop d (drop k ys) = drop (d + k) ys
dropDrop d Z ys = rewrite plusZeroRightNeutral d in Refl
dropDrop d (S k) [] = rewrite plusCommutative d (S k) in dropNil d
dropDrop d (S k) (y :: ys) = rewrite sym (plusSuccRightSucc d k) in dropDrop d k ys

||| The arcs at `as`, read through a cursor over `g.arcs`: an index at or
||| after the cursor is reached by stepping on, one behind it by starting
||| over, so a list in increasing order costs one pass.
export
lookUp : (g : Graph) -> (as : List (Fin (length g.arcs))) -> At g as
lookUp g as = go 0 g.arcs Refl as
  where
    0 headIs : {0 x : Arc g.size} -> {0 rest : List (Arc g.size)} -> (a : Fin (length g.arcs)) ->
               drop (finToNat a) g.arcs = x :: rest -> x = arc g a
    headIs a d = let (r ** e) = dropIndex g.arcs a in fst (consInjective (trans (sym d) e))

    0 notEnded : (a : Fin (length g.arcs)) -> Not (drop (finToNat a) g.arcs = [])
    notEnded a d = let (r ** e) = dropIndex g.arcs a in absurd (trans (sym d) e)

    -- The cursor at k, moved to j. Essential: an index behind the cursor
    -- (a list not in increasing order) is reached again from the start.
    seek : (k : Nat) -> (cur : List (Arc g.size)) -> (0 _ : drop k g.arcs = cur) -> (j : Nat) ->
           (cur' : List (Arc g.size) ** drop j g.arcs = cur')
    seek k cur dk j = case choose (k <= j) of
      Left le => (drop (minus j k) cur ** irrelevantEq (rewrite sym dk in rewrite dropDrop (minus j k) k g.arcs in
                                                       rewrite plusMinusLte k j (lteSo le) in Refl))
      Right _ => (drop j g.arcs ** Refl)

    mutual
      go : (k : Nat) -> (cur : List (Arc g.size)) -> (0 _ : drop k g.arcs = cur) ->
           (as : List (Fin (length g.arcs))) -> At g as
      go k cur dk [] = []
      go k cur dk (a :: as) = let (cur' ** d') = seek k cur dk (finToNat a) in at a cur' d' as

      at : (a : Fin (length g.arcs)) -> (cur' : List (Arc g.size)) -> (0 _ : drop (finToNat a) g.arcs = cur') ->
           (as : List (Fin (length g.arcs))) -> At g (a :: as)
      at a [] d as = void (notEnded a d)
      at a (x :: rest) d as =
        (::) x (headIs {x} {rest} a d) (go (S (finToNat a)) rest (dropSucc {x} {rest} g.arcs (finToNat a) d) as)

------------------------------------------------------------------------------
-- A positive cycle
------------------------------------------------------------------------------

||| Arcs that chain from `here` around to `first`: each leaves the position
||| the one before entered, and the last enters `first`. Indexed by the
||| positions after `here`, in order, and by the arcs.
public export
data Ring : (g : Graph) -> (first, here : Fin g.size) -> List (Fin g.size) -> List (Fin (length g.arcs)) -> Type where
  Last : (0 _ : (arc g a).from = Just here) -> (0 _ : (arc g a).to = first) -> Ring g first here [] [a]
  Next : (0 _ : (arc g a).from = Just here) -> (0 _ : (arc g a).to = next) ->
         Ring g first next ps as -> Ring g first here (next :: ps) (a :: as)

public export
data IsFinite : Weight -> Type where
  ItIsFinite : IsFinite (Finite g l)

public export
gainOf : Weight -> Nat
gainOf (Finite g _) = g
gainOf _ = 0

public export
lossOf : Weight -> Nat
lossOf (Finite _ l) = l
lossOf _ = 0

||| What a list of weights adds: the gains of its finite weights.
public export
gains : List Weight -> Nat
gains [] = 0
gains (w :: ws) = gainOf w + gains ws

||| What a list of weights takes away: the losses of its finite weights.
public export
losses : List Weight -> Nat
losses [] = 0
losses (w :: ws) = lossOf w + losses ws

||| A cycle from p back to p, of finite arcs, whose gains exceed their
||| losses. A Stuck arc is never on one: it is a `StuckArc` of its own.
public export
data Positive : (g : Graph) -> List (Fin g.size) -> List (Fin (length g.arcs)) -> Type where
  Sums : (0 _ : Ring g p p ps as) -> (0 _ : All IsFinite (weights g as)) ->
         (0 _ : LT (losses (weights g as)) (gains (weights g as))) -> Positive g (p :: ps) as

------------------------------------------------------------------------------
-- A Stuck arc
------------------------------------------------------------------------------

public export
data StuckArc : (g : Graph) -> Fin (length g.arcs) -> Type where
  ItIsStuck : (0 _ : (arc g a).weight = Stuck) -> StuckArc g a

------------------------------------------------------------------------------
-- A feasible potential
------------------------------------------------------------------------------

||| A potential at an arc's end, the origin's 0.
public export
potentialAt : Vect n Nat -> Maybe (Fin n) -> Nat
potentialAt pot = maybe 0 (\q => index q pot)

||| One arc satisfied: the potential at its source, raised by its weight, is
||| at most the potential at its target. Only a Finite arc has the
||| constructor, so a feasible graph has no Stuck arc.
public export
data Satisfies : Vect n Nat -> Arc n -> Type where
  MkSatisfies : (0 _ : LTE (potentialAt pot q + gain) (index p pot + loss)) ->
                Satisfies pot (MkArc q p (Finite gain loss) pr)

public export
data Feasible : (g : Graph) -> Vect g.size Nat -> Type where
  MkFeasible : All (Satisfies pot) g.arcs -> Feasible g pot

||| The bound a feasible potential gives a position: K above its potential,
||| and no more than its cap.
public export
bound : (g : Graph) -> Vect g.size Nat -> Fin g.size -> Nat
bound g pot p = maybe (g.constant + index p pot) (min (g.constant + index p pot)) (index p g.caps)

------------------------------------------------------------------------------
-- Every arc, in one pass
------------------------------------------------------------------------------

||| A count that has a run of one or more still to go before n is below n.
export
0 runBelow : (k : Nat) -> k + S rest = n -> LT k n
runBelow k eq = rewrite sym eq in rewrite sym (plusSuccRightSucc k rest) in LTESucc (lteAddRight k)

||| A count made a `Fin` is still its number.
export
0 finToNatLT : (x : Nat) -> {0 n : Nat} -> {0 prf : LT x n} -> finToNat (natToFinLT x {prf}) = x
finToNatLT Z {prf = LTESucc _} = Refl
finToNatLT (S x) {prf = LTESucc _} = cong S (finToNatLT x)

||| The positions k, k + 1, ... of xs's elements, in a list of length n, in
||| one pass: `natToFinLT` is the identity at run time.
public export
indicesFrom : (k : Nat) -> (xs : List a) -> {0 n : Nat} -> (0 _ : k + length xs = n) -> List (Fin n)
indicesFrom k [] _ = []
indicesFrom k (_ :: xs) eq = natToFinLT k {prf = runBelow k eq} :: indicesFrom (S k) xs (trans (plusSuccRightSucc k (length xs)) eq)

||| A list's positions, in order.
public export
indices : (xs : List a) -> List (Fin (length xs))
indices xs = indicesFrom 0 xs Refl

public export
everyArc : (g : Graph) -> List (Fin (length g.arcs))
everyArc g = indices g.arcs

0 indexDrop : {0 x : a} -> {0 rest : List a} -> (ys : List a) -> (k : Nat) -> {0 prf : LT k (length ys)} ->
              drop k ys = x :: rest -> index' ys (natToFinLT k {prf}) = x
indexDrop (y :: ys) Z {prf = LTESucc _} eq = cong (\l => case l of { (h :: _) => h; [] => y }) eq
indexDrop (y :: ys) (S k) {prf = LTESucc _} eq = indexDrop ys k eq

0 mapIndicesFrom : (ys : List a) -> (k : Nat) -> (xs : List a) -> (eq : k + length xs = length ys) ->
                   drop k ys = xs -> map (index' ys) (indicesFrom k xs eq) = xs
mapIndicesFrom ys k [] eq d = Refl
mapIndicesFrom ys k (x :: xs) eq d =
  cong2 (::) (indexDrop {x} {rest = xs} ys k d) (mapIndicesFrom ys (S k) xs _ (dropSucc {x} {rest = xs} ys k d))

0 mapIndices : (xs : List a) -> map (index' xs) (indices xs) = xs
mapIndices xs = mapIndicesFrom xs 0 xs Refl Refl

||| A potential that satisfies every arc, by index, is feasible: the form
||| `heaviest` returns on `everyArc g`.
export
everyFits : {g : Graph} -> {0 pot : Vect g.size Nat} -> All (Satisfies pot) (map (arc g) (everyArc g)) -> Feasible g pot
everyFits fs = MkFeasible (replace {p = All (Satisfies pot)} (mapIndices g.arcs) fs)
