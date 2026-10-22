-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The graph the growth check decides, and the certificates its answers
||| carry.
|||
||| A position is a static argument of a definition. An arc says how far a
||| value written at its target can stand above the value at its source: a
||| label `Measured gain loss` raises it by at most gain - loss, and
||| `Unmeasured` by nothing anyone can bound. A capped position's type looks
||| only so deep: its cap is the most its values can be, which a potential
||| meets by standing no more than K below it.
|||
||| The check answers with one of three certificates, each a type only a
||| true answer inhabits:
||| - a cycle, its finite arcs chained by index, whose gains exceed its
|||   losses: a static argument grows each round;
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

||| A decision whose evidence the frontend reads at run time (a place in a
||| list it cuts at): the evidence that it holds, or the erased evidence
||| that it does not.
public export
data Decision : Type -> Type where
  Holds : p -> Decision p
  Fails : (0 _ : Not p) -> Decision p

||| A decision whose evidence only proofs read: the erased evidence that it
||| holds, or the erased evidence that it does not. Deciding one costs its
||| comparisons alone; no proof of it is built at run time.
public export
data Decided : Type -> Type where
  Yes : (0 _ : p) -> Decided p
  No : (0 _ : Not p) -> Decided p

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
samePosition : (x, y : Fin n) -> Decided (x = y)
samePosition x y = case choose (finToNat x == finToNat y) of
  Left so => Yes (injective {f = finToNat} (equalSo so))
  Right no => No (\Refl => soNotToNotSo no (equalSelf (finToNat x)))

------------------------------------------------------------------------------
-- Weights
------------------------------------------------------------------------------

||| What a template carries a value up by: Absent where it carries none,
||| gain - loss, or Stuck, by nothing anyone can bound. A finite weight is
||| two naturals, so that every comparison of two is one of naturals, by
||| cross-addition. A graph's arcs are labelled (`Label`), never Absent.
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

||| What an arc raises a value by: gain - loss, or nothing anyone can bound.
||| A weight Absent is no arc, so a label has no such case.
public export
data Label = Measured Nat Nat | Unmeasured

||| An arc from a position to a position.
public export
record Arc (n : Nat) where
  constructor MkArc
  from : Fin n
  to : Fin n
  label : Label

||| The positions `Fin size`, the arcs between them, the tallest constant K
||| of any template, and each position's cap, where its type inspects its
||| value to a fixed depth: the one place a cap is held.
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
labels : (g : Graph) -> List (Fin (length g.arcs)) -> List Label
labels g = map (\a => (arc g a).label)

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
||| the one before entered, and the last enters `first`. One list, of the
||| arcs: each position on the ring is the source of the arc that leaves it.
public export
data Ring : (g : Graph) -> (first, here : Fin g.size) -> List (Fin (length g.arcs)) -> Type where
  Last : (0 _ : (arc g a).from = here) -> (0 _ : (arc g a).to = first) -> Ring g first here [a]
  Next : {0 next : Fin g.size} -> (0 _ : (arc g a).from = here) -> (0 _ : (arc g a).to = next) ->
         Ring g first next as -> Ring g first here (a :: as)

public export
data IsFinite : Label -> Type where
  ItIsFinite : IsFinite (Measured g l)

public export
gainOf : Label -> Nat
gainOf (Measured g _) = g
gainOf Unmeasured = 0

public export
lossOf : Label -> Nat
lossOf (Measured _ l) = l
lossOf Unmeasured = 0

||| What a list of labels adds: the gains of its finite ones.
public export
gains : List Label -> Nat
gains [] = 0
gains (w :: ws) = gainOf w + gains ws

||| What a list of labels takes away: the losses of its finite ones.
public export
losses : List Label -> Nat
losses [] = 0
losses (w :: ws) = lossOf w + losses ws

||| A cycle of finite arcs from a position back to it, whose gains exceed
||| their losses. An Unmeasured arc is never on one: it is a `StuckArc` of
||| its own.
public export
data Positive : (g : Graph) -> List (Fin (length g.arcs)) -> Type where
  Sums : {0 p : Fin g.size} -> (0 _ : Ring g p p as) -> (0 _ : All IsFinite (labels g as)) ->
         (0 _ : LT (losses (labels g as)) (gains (labels g as))) -> Positive g as

------------------------------------------------------------------------------
-- A Stuck arc
------------------------------------------------------------------------------

||| A ring's first arc leaves where the ring starts.
export
0 ringStart : Ring g first here (a :: as) -> (arc g a).from = here
ringStart (Last l _) = l
ringStart (Next l _ _) = l

public export
data StuckArc : (g : Graph) -> Fin (length g.arcs) -> Type where
  ItIsStuck : (0 _ : (arc g a).label = Unmeasured) -> StuckArc g a

------------------------------------------------------------------------------
-- A feasible potential
------------------------------------------------------------------------------

||| One arc satisfied: the potential at its source, raised by its label, is
||| at most the potential at its target. Only a Measured arc has the
||| constructor, so a feasible graph has no Unmeasured arc.
public export
data Satisfies : Vect n Nat -> Arc n -> Type where
  MkSatisfies : (0 _ : LTE (index q pot + gain) (index p pot + loss)) ->
                Satisfies pot (MkArc q p (Measured gain loss))

||| A position's cap met: none, or one no more than K above its potential.
public export
data CapHolds : (constant : Nat) -> Maybe Nat -> Nat -> Type where
  Uncapped : CapHolds k Nothing v
  Within : (0 _ : LTE c (k + v)) -> CapHolds k (Just c) v

namespace CapsHold
  ||| Every position's cap met, position by position.
  public export
  data CapsHold : (constant : Nat) -> Vect n (Maybe Nat) -> Vect n Nat -> Type where
    Nil : CapsHold k [] []
    (::) : CapHolds k c v -> CapsHold k cs vs -> CapsHold k (c :: cs) (v :: vs)

||| A potential every arc satisfies and every cap meets.
public export
data Feasible : (g : Graph) -> Vect g.size Nat -> Type where
  MkFeasible : All (Satisfies pot) g.arcs -> (0 _ : CapsHold g.constant g.caps pot) -> Feasible g pot

||| The cap a position meets.
export
0 capAt : CapsHold k cs vs -> (p : Fin n) -> index p cs = Just c -> LTE c (k + index p vs)
capAt (Within le :: _) FZ Refl = le
capAt (Uncapped :: _) FZ eq = absurd eq
capAt (_ :: hs) (FS p) eq = capAt hs p eq

-- The cap at the first position, and those after it.
0 firstCap : CapsHold k (c :: cs) (v :: vs) -> CapHolds k c v
firstCap (h :: _) = h

0 laterCaps : CapsHold k (c :: cs) (v :: vs) -> CapsHold k cs vs
laterCaps (_ :: hs) = hs

||| Whether every cap holds under a potential, position by position: the
||| machine's comparison at each capped position, its evidence erased.
export
capsHold : (k : Nat) -> (cs : Vect n (Maybe Nat)) -> (vs : Vect n Nat) -> Decided (CapsHold k cs vs)
capsHold k [] [] = Yes []
capsHold k (c :: cs) (v :: vs) = case capHolds c of
  No no => No (\hs => no (firstCap hs))
  Yes h => case capsHold k cs vs of
    No no => No (\hs => no (laterCaps hs))
    Yes hs => Yes (h :: hs)
  where
    capHolds : (c : Maybe Nat) -> Decided (CapHolds k c v)
    capHolds Nothing = Yes Uncapped
    capHolds (Just c) = case choose (c <= k + v) of
      Left le => Yes (Within (lteSo le))
      Right nle => No (\(Within le) => notLteSo nle le)

namespace Below
  ||| One vector nowhere above another.
  public export
  data Below : Vect n Nat -> Vect n Nat -> Type where
    Nil : Below [] []
    (::) : (0 _ : LTE a b) -> Below as bs -> Below (a :: as) (b :: bs)

||| A vector below another at every position is below it.
export
0 belowAt : {n : Nat} -> {lo, hi : Vect n Nat} -> ((i : Fin n) -> LTE (index i lo) (index i hi)) -> Below lo hi
belowAt {lo = []} {hi = []} f = []
belowAt {lo = _ :: _} {hi = _ :: _} f = f FZ :: belowAt (\i => f (FS i))

||| Caps met under a potential are met under one no lower.
export
0 capsAbove : CapsHold k cs lo -> Below lo hi -> CapsHold k cs hi
capsAbove [] [] = []
capsAbove (Uncapped :: hs) (_ :: bs) = Uncapped :: capsAbove hs bs
capsAbove (Within le :: hs) (b :: bs) = Within (transitive le (plusLteMonotoneLeft k _ _ b)) :: capsAbove hs bs

||| The least potential a cap asks of its position: the cap less K.
public export
floorOf : (constant : Nat) -> Maybe Nat -> Nat
floorOf k Nothing = 0
floorOf k (Just c) = minus c k

||| Every cap holds at its floor.
export
0 floorsHold : (k : Nat) -> (cs : Vect n (Maybe Nat)) -> CapsHold k cs (map (floorOf k) cs)
floorsHold k [] = []
floorsHold k (Nothing :: cs) = Uncapped :: floorsHold k cs
floorsHold k (Just c :: cs) = Within (atFloor k c) :: floorsHold k cs
  where
    atFloor : (k, c : Nat) -> LTE c (k + minus c k)
    atFloor Z c = rewrite minusZeroRight c in reflexive
    atFloor (S k) Z = LTEZero
    atFloor (S k) (S c) = LTESucc (atFloor k c)

||| A position's bound from its potential and its cap: K above the
||| potential, and no more than the cap.
public export
capped : (constant, potential : Nat) -> (cap : Maybe Nat) -> Nat
capped k pi cap = maybe (k + pi) (min (k + pi)) cap

||| The bound a feasible potential gives a position.
public export
bound : (g : Graph) -> Vect g.size Nat -> Fin g.size -> Nat
bound g pot p = capped g.constant (index p pot) (index p g.caps)

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

||| A potential that satisfies every arc, by index, and meets every cap is
||| feasible: the form `heaviest` returns on `everyArc g`.
export
everyFits : {g : Graph} -> {0 pot : Vect g.size Nat} -> All (Satisfies pot) (map (arc g) (everyArc g)) ->
            (0 _ : CapsHold g.constant g.caps pot) -> Feasible g pot
everyFits fs caps = MkFeasible (replace {p = All (Satisfies pot)} (mapIndices g.arcs) fs) caps
