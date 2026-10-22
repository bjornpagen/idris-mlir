-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Lemma 2, constructively: on finite arcs, a cycle whose gains exceed its
||| losses, or a potential every arc satisfies.
|||
||| Bellman-Ford on heaviest walks. A walk starts at a position with the
||| start potential's value there and follows the listed arcs, its weight
||| kept as what it gains and what it loses. After k
||| rounds each position holds the weight of a walk of at most k arcs that
||| ends there, with the walk, and no walk of at most k arcs ends there
||| heavier: a round reads only the round before, so this holds by
||| induction on the walk.
|||
||| After each round the arcs are checked. If none relaxes, the values are
||| the potential. If one still relaxes after as many rounds as there are
||| arcs, the walk it extends is one arc too long, so two of its arcs enter
||| one position, and between them lies a cycle. Had that cycle gained no
||| more than it lost, cutting it out would leave a walk short enough for
||| the values to dominate and no lighter, which the relaxing arc says it is
||| not. So the cycle rises. The rounds are counted, every check is the
||| machine's comparison, and every proof is erased.
module IdrisMLIR.Frontend.Growth.Potential

import IdrisMLIR.Proof.Growth
import Libraries.Data.List.Finite
import Data.List
import Data.Nat
import Data.So
import Decidable.Equality

%default total

------------------------------------------------------------------------------
-- Arithmetic, all on Nat: each weight's loss is moved to the other side

0 swapRight : (a, b, c : Nat) -> (a + b) + c = (a + c) + b
swapRight a b c = rewrite sym (plusAssociative a b c) in
                  rewrite plusCommutative b c in
                  plusAssociative a c b

-- A walk extended by an arc that fits the next round's values.
0 extends : {r, o, f, g, n, l : Nat} -> LTE r (o + f) -> LTE (o + g) (n + l) -> LTE (r + g) (n + (f + l))
extends rf gl =
  let s1 = plusLteMonotoneRight g r (o + f) rf
      s2 = plusLteMonotoneRight f (o + g) (n + l) gl
      s1' = replace {p = \x => LTE (r + g) x} (swapRight o f g) s1
      s2' = replace {p = \x => LTE ((o + g) + f) x} (sym (plusAssociative n l f)) s2
      s2'' = replace {p = \x => LTE ((o + g) + f) (n + x)} (plusCommutative l f) s2'
  in transitive s1' s2''

-- The value a relaxed arc gives is exact for the walk it extends.
0 relaxedExact : {s, g, l, f, r : Nat} -> s + f = r -> LTE l (s + g) -> (minus (s + g) l) + (f + l) = r + g
relaxedExact sf lg =
  rewrite plusCommutative f l in
  rewrite plusAssociative (minus (s + g) l) l f in
  rewrite plusMinusLte l (s + g) lg in
  rewrite swapRight s g f in
  cong (+ g) sf

-- An arc that relaxes, read on the walk it extends.
0 relaxes : {vu, vv, ru, fu, g, l : Nat} -> vu + fu = ru -> LT (vv + l) (vu + g) -> LT (vv + (fu + l)) (ru + g)
relaxes {vu} {vv} {ru} {fu} {g} {l} e lt =
  let s = plusLteMonotoneRight fu (S (vv + l)) (vu + g) lt
      s' = replace {p = \x => LTE (S (vv + l) + fu) x} (trans (swapRight vu g fu) (cong (+ g) e)) s
      0 e2 : (S (vv + l) + fu = S (vv + (fu + l)))
      e2 = cong S (trans (sym (plusAssociative vv l fu)) (cong (vv +) (plusCommutative l fu)))
  in replace {p = \x => LTE x (ru + g)} e2 s'

-- A cycle that does not rise, cut out of a walk that relaxes, leaves a walk
-- the values dominate and that rises no less: no such cycle.
0 noCycle : {rb, fb, gc, lc, ga, la, d : Nat} ->
            LTE gc lc -> LTE (rb + ga) (d + (fb + la)) -> LT (d + (fb + (lc + la))) (rb + (gc + ga)) -> Void
noCycle cl dom lt =
  let 0 up : LTE (rb + (gc + ga)) ((rb + ga) + lc)
      up = rewrite plusCommutative gc ga in
           rewrite plusAssociative rb ga gc in
           plusLteMonotoneLeft (rb + ga) gc lc cl
      over = plusLteMonotoneRight lc (rb + ga) (d + (fb + la)) dom
      0 eq : ((d + (fb + la)) + lc = d + (fb + (lc + la)))
      eq = rewrite sym (plusAssociative d (fb + la) lc) in
           rewrite sym (plusAssociative fb la lc) in
           rewrite plusCommutative la lc in Refl
  in succNotLTEpred (transitive lt (transitive up (replace {p = LTE ((rb + ga) + lc)} eq over)))

-- Cutting a non-empty cycle out of a walk of one arc too many.
0 shorter : {k, c, a, r : Nat} -> k + (c + a) = S r -> LTE 1 c -> LTE (k + a) r
shorter {c = S c'} e _ =
  let 0 e' : (S (k + (c' + a)) = S r)
      e' = trans (plusSuccRightSucc k (c' + a)) e
  in replace {p = \x => LTE (k + a) x} (injective e')
       (rewrite plusAssociative k c' a in
        rewrite plusCommutative k c' in
        rewrite sym (plusAssociative c' k a) in lteAddRight' c' (k + a))
  where
    lteAddRight' : (m, n : Nat) -> LTE n (m + n)
    lteAddRight' m n = rewrite plusCommutative m n in lteAddRight n

0 below : {v, l, s : Nat} -> LT (v + l) s -> LTE l s
below lt = lteSuccLeft (transitive (LTESucc (rewrite plusCommutative v l in lteAddRight l)) lt)

0 underMinus : {v, l, s : Nat} -> LT (v + l) s -> LTE v (minus s l)
underMinus {v} {l} {s} lt =
  let m = minusLteMonotone {p = l} (lteSuccLeft lt) in
  replace {p = \x => LTE x (minus s l)} (trans (cong (\y => minus y l) (plusCommutative v l)) (minusPlus l)) m

------------------------------------------------------------------------------
-- A table of one value per position

-- The cells at the positions `at` names, one value each, of type `p` at its
-- position. The family `p` is a parameter, the same in the tail; only the
-- positions move. So a function of every position (`mapTable`, `column`) is
-- the same function at every cell, one call each, and a field's type is `p`
-- at a position, never a family the tail rewrote, which an erased argument
-- would leave undecided. The constructors stay at the module's top level: a
-- name private to a nested namespace is hidden from the rest of its own
-- module.
data Cells : {n : Nat} -> (p : Fin n -> Type) -> (m : Nat) -> (at : Fin m -> Fin n) -> Type where
  Nil : Cells p 0 at
  (::) : p (at FZ) -> Cells p m (\i => at (FS i)) -> Cells p (S m) at

||| One value per position: the entry at i has type `p i`.
Table : {n : Nat} -> (p : Fin n -> Type) -> Type
Table {n} p = Cells p n (\i => i)

entry : (i : Fin m) -> Cells p m at -> p (at i)
entry FZ (x :: _) = x
entry (FS i) (_ :: xs) = entry i xs

put : (i : Fin m) -> p (at i) -> Cells p m at -> Cells p m at
put FZ y (_ :: xs) = y :: xs
put (FS i) y (x :: xs) = x :: put i y xs

-- The position is an explicit erased argument of `f`: an implicit one would
-- be abstracted again at each cell, a closure per level.
mapTable : {0 p, q : Fin n -> Type} -> ((0 i : Fin n) -> p i -> q i) -> Cells p m at -> Cells q m at
mapTable f [] = []
mapTable f (x :: xs) = f _ x :: mapTable f xs

column : {0 p : Fin n -> Type} -> ((0 i : Fin n) -> p i -> Nat) -> Cells p m at -> Vect m Nat
column f [] = []
column f (b :: bs) = f _ b :: column f bs

0 entryPut : (i : Fin m) -> (y : p (at i)) -> (t : Cells p m at) -> entry i (put i y t) = y
entryPut FZ y (_ :: _) = Refl
entryPut (FS i) y (_ :: xs) = entryPut i y xs

0 entryPutOther : (i, j : Fin m) -> Not (i = j) -> (y : p (at j)) -> (t : Cells p m at) -> entry i (put j y t) = entry i t
entryPutOther FZ FZ ne _ (_ :: _) = absurd (ne Refl)
entryPutOther FZ (FS _) _ _ (_ :: _) = Refl
entryPutOther (FS _) FZ _ _ (_ :: _) = Refl
entryPutOther (FS i) (FS j) ne y (_ :: xs) = entryPutOther i j (\e => ne (cong FS e)) y xs

0 entryMap : {0 p, q : Fin n -> Type} -> (f : (0 i : Fin n) -> p i -> q i) -> (i : Fin m) -> (t : Cells p m at) ->
             entry i (mapTable f t) = f _ (entry i t)
entryMap f FZ (_ :: _) = Refl
entryMap f (FS i) (_ :: xs) = entryMap f i xs

0 indexColumn : {0 p : Fin n -> Type} -> (f : (0 i : Fin n) -> p i -> Nat) -> (i : Fin m) -> (t : Cells p m at) ->
                index i (column f t) = f _ (entry i t)
indexColumn f FZ (_ :: _) = Refl
indexColumn f (FS i) (_ :: bs) = indexColumn f i bs

------------------------------------------------------------------------------
-- Walks and paths

||| A walk through the listed arcs, from the start potential's implicit arc
||| into its first position, to the position it ends at.
data Walk : (g : Graph) -> (inner : List (Fin (length g.arcs))) -> (start : Vect g.size Nat) -> Fin g.size -> Type where
  Start : (v : Fin g.size) -> Walk g inner start v
  Extend : (u : Fin g.size) -> Walk g inner start u -> (a : Fin (length g.arcs)) -> (v : Fin g.size) -> (0 _ : Elem a inner) ->
           (0 _ : (arc g a).from = u) -> (0 _ : (arc g a).to = v) -> (0 _ : IsFinite (arc g a).label) -> Walk g inner start v

steps : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 start : Vect g.size Nat} -> {0 v : Fin g.size} -> Walk g inner start v -> Nat
steps (Start _) = 0
steps (Extend _ w _ _ _ _ _ _) = S (steps w)

rise : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} -> {0 v : Fin g.size} -> Walk g inner start v -> Nat
rise (Start v) = index v start
rise (Extend _ w a _ _ _ _ _) = rise w + gainOf (arc g a).label

fall : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 start : Vect g.size Nat} -> {0 v : Fin g.size} -> Walk g inner start v -> Nat
fall (Start v) = 0
fall (Extend _ w a _ _ _ _ _) = fall w + lossOf (arc g a).label

||| A path through the listed arcs, from x to y.
data Path : (g : Graph) -> (inner : List (Fin (length g.arcs))) -> (x, y : Fin g.size) -> Type where
  Stay : Path g inner x x
  Step : (a : Fin (length g.arcs)) -> (t : Fin g.size) -> (0 _ : Elem a inner) -> (0 _ : (arc g a).from = x) ->
         (0 _ : (arc g a).to = t) -> (0 _ : IsFinite (arc g a).label) -> Path g inner t y -> Path g inner x y

targets : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 x, y : Fin g.size} -> Path g inner x y -> List (Fin g.size)
targets Stay = []
targets (Step _ t _ _ _ _ p) = t :: targets p

arcsOf : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 x, y : Fin g.size} -> Path g inner x y -> List (Fin (length g.arcs))
arcsOf Stay = []
arcsOf (Step a _ _ _ _ _ p) = a :: arcsOf p

append : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 start : Vect g.size Nat} -> {x : Fin g.size} -> {0 y : Fin g.size} ->
         Walk g inner start x -> Path g inner x y -> Walk g inner start y
append w Stay = w
append {x} w (Step a t e l q f p) = append (Extend x w a t e l q f) p

0 appendSteps : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 start : Vect g.size Nat} -> {x : Fin g.size} -> {0 y : Fin g.size} ->
                (w : Walk g inner start x) -> (p : Path g inner x y) -> steps (append w p) = steps w + length (targets p)
appendSteps w Stay = sym (plusZeroRightNeutral _)
appendSteps {x} w (Step a t e l q f p) = trans (appendSteps (Extend x w a t e l q f) p) (plusSuccRightSucc _ _)

0 appendRise : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} -> {x : Fin g.size} -> {0 y : Fin g.size} ->
               (w : Walk g inner start x) -> (p : Path g inner x y) -> rise (append w p) = rise w + gains (labels g (arcsOf p))
appendRise w Stay = sym (plusZeroRightNeutral _)
appendRise {x} w (Step a t e l q f p) = trans (appendRise (Extend x w a t e l q f) p) (sym (plusAssociative _ _ _))

0 appendFall : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 start : Vect g.size Nat} -> {x : Fin g.size} -> {0 y : Fin g.size} ->
               (w : Walk g inner start x) -> (p : Path g inner x y) -> fall (append w p) = fall w + losses (labels g (arcsOf p))
appendFall w Stay = sym (plusZeroRightNeutral _)
appendFall {x} w (Step a t e l q f p) = trans (appendFall (Extend x w a t e l q f) p) (sym (plusAssociative _ _ _))

0 gainsAppend : (ws, vs : List Label) -> gains (ws ++ vs) = gains ws + gains vs
gainsAppend [] vs = Refl
gainsAppend (w :: ws) vs = rewrite gainsAppend ws vs in plusAssociative _ _ _

0 lossesAppend : (ws, vs : List Label) -> losses (ws ++ vs) = losses ws + losses vs
lossesAppend [] vs = Refl
lossesAppend (w :: ws) vs = rewrite lossesAppend ws vs in plusAssociative _ _ _

0 pathFinite : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 x, y : Fin g.size} -> (p : Path g inner x y) -> All IsFinite (labels g (arcsOf p))
pathFinite Stay = []
pathFinite (Step _ _ _ _ _ f p) = f :: pathFinite p

-- The targets of the listed arcs: a walk's positions after its first lie
-- among them, so the pigeonhole runs over as many positions as there are
-- listed arcs.
universe : (g : Graph) -> List (Fin (length g.arcs)) -> List (Fin g.size)
universe g inner = map (\a => (arc g a).to) inner

0 targetsIn : {g : Graph} -> {inner : List (Fin (length g.arcs))} -> {0 x, y, z : Fin g.size} -> (p : Path g inner x y) ->
              Elem z (targets p) -> Elem z (universe g inner)
targetsIn Stay e = absurd e
targetsIn (Step a t i _ q _ _) Here = rewrite sym q in elemMap (\b => (arc g b).to) i
targetsIn (Step _ _ _ _ _ _ p) (There e) = targetsIn p e

------------------------------------------------------------------------------
-- The cycle's certificate

0 ringOf : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 here, first : Fin g.size} -> (p : Path g inner here first) -> NonEmpty (targets p) ->
           Ring g first here (arcsOf p)
ringOf Stay ne = absurd ne
ringOf (Step a t _ l q _ Stay) _ = Last l q
ringOf (Step a t _ l q _ p@(Step _ _ _ _ _ _ _)) _ = Next l q (ringOf p IsNonEmpty)

-- A path cut where it first enters z.
record Cut (g : Graph) (inner : List (Fin (length g.arcs))) (x, y, z : Fin g.size) (p : Path g inner x y) where
  constructor MkCut
  upTo : Path g inner x z
  rest : Path g inner z y
  0 arcsSplit : arcsOf p = arcsOf upTo ++ arcsOf rest
  0 targetsSplit : length (targets p) = length (targets upTo) + length (targets rest)
  0 nonEmpty : NonEmpty (targets upTo)

cut : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 x, y, z : Fin g.size} -> (p : Path g inner x y) -> Elem z (targets p) -> Cut g inner x y z p
cut Stay e = absurd e
cut (Step a t i l q f p) Here = MkCut (Step a t i l q f Stay) p Refl Refl IsNonEmpty
cut (Step a t i l q f p) (There e) =
  let MkCut u r as ts _ = cut p e in
  MkCut (Step a t i l q f u) r (cong (a ::) as) (cong S ts) IsNonEmpty

------------------------------------------------------------------------------
-- The values after k rounds

||| A position's value after k rounds, with a walk of at most k arcs that
||| ends there and weighs exactly that.
record Best (g : Graph) (inner : List (Fin (length g.arcs))) (start : Vect g.size Nat) (k : Nat) (v : Fin g.size) where
  constructor MkBest
  value : Nat
  walk : Walk g inner start v
  0 within : LTE (steps walk) k
  0 exact : value + fall walk = rise walk

Values : (g : Graph) -> List (Fin (length g.arcs)) -> Vect g.size Nat -> Nat -> Type
Values g inner start k = Table {n = g.size} (Best g inner start k)

||| No walk of at most k arcs ends anywhere heavier than the values say.
0 Dominates : {g : Graph} -> {inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} ->
              (k : Nat) -> Values g inner start k -> Type
Dominates k t = {v : Fin g.size} -> (w : Walk g inner start v) -> LTE (steps w) k -> LTE (rise w) ((entry v t).value + fall w)

0 startAt : {0 m, n : Nat} -> {0 at : Fin (S m) -> Fin n} -> (k : Nat) -> (eq : k + S m = n) -> ((i : Fin (S m)) -> finToNat (at i) = k + finToNat i) ->
            natToFinLT k {prf = runBelow {rest = m} k eq} = at FZ
startAt k eq here = injective {f = finToNat} (trans (finToNatLT k) (trans (sym (plusZeroRightNeutral k)) (sym (here FZ))))

-- The values after 0 rounds at the positions `at` names, from the k-th on:
-- each the start potential's value there, with the empty walk. Each
-- position is the counter k, made a `Fin` by `natToFinLT`, the identity at
-- run time, so the table costs one pass over `start`.
startCells : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 start : Vect g.size Nat} -> {m : Nat} ->
             {0 at : Fin m -> Fin g.size} -> (k : Nat) -> (vs : Vect m Nat) -> (0 _ : k + m = g.size) ->
             (0 here : (i : Fin m) -> finToNat (at i) = k + finToNat i) -> (0 val : (i : Fin m) -> index i vs = index (at i) start) ->
             Cells (Best g inner start 0) m at
startCells k [] _ _ _ = []
startCells {m = S m} k (v :: vs) eq here val =
  replace {p = Best g inner start 0} (startAt k eq here)
          (MkBest v (Start (natToFinLT k {prf = runBelow {rest = m} k eq})) LTEZero
                  (rewrite startAt k eq here in trans (plusZeroRightNeutral v) (val FZ)))
    :: startCells (S k) vs (trans (plusSuccRightSucc k m) eq)
                  (\i => trans (here (FS i)) (sym (plusSuccRightSucc k (finToNat i)))) (\i => val (FS i))

initial : (g : Graph) -> (inner : List (Fin (length g.arcs))) -> (start : Vect g.size Nat) -> Values g inner start 0
initial g inner start = startCells 0 start Refl (\i => Refl) (\i => Refl)

0 startEntry : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 start : Vect g.size Nat} -> {m : Nat} ->
               {0 at : Fin m -> Fin g.size} -> (k : Nat) -> (vs : Vect m Nat) -> (eq : k + m = g.size) ->
               (here : (i : Fin m) -> finToNat (at i) = k + finToNat i) -> (val : (i : Fin m) -> index i vs = index (at i) start) ->
               (i : Fin m) -> (entry i (startCells {g} {inner} {start} {at} k vs eq here val)).value = index i vs
startEntry {m = S m} k (v :: vs) eq here val FZ = Refl
startEntry {m = S m} k (v :: vs) eq here val (FS i) =
  startEntry (S k) vs (trans (plusSuccRightSucc k m) eq)
             (\j => trans (here (FS j)) (sym (plusSuccRightSucc k (finToNat j)))) (\j => val (FS j)) i

0 initialEntry : {g : Graph} -> {inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} -> (v : Fin g.size) ->
                 (entry v (initial g inner start)).value = index v start
initialEntry v = startEntry 0 start Refl (\i => Refl) (\i => Refl) v

-- Only `Start` has no arc, and it weighs what `start` holds.
0 dominatesInitial : {g : Graph} -> {inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} ->
                     Dominates {g} {inner} {start} 0 (initial g inner start)
dominatesInitial (Start v) _ =
  rewrite initialEntry {g} {inner} {start} v in lteAddRight _
dominatesInitial (Extend _ _ _ _ _ _ _ _) le = absurd le

weaken : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 start : Vect g.size Nat} -> {0 k : Nat} -> {0 v : Fin g.size} ->
         Best g inner start k v -> Best g inner start (S k) v
weaken b = MkBest b.value b.walk (lteSuccRight b.within) b.exact

-- The round before, read at the next round's index. Here and in `values`
-- the family is written as a lambda, the form an instance key gives it, so
-- that this request of `mapTable` and the one its recursion makes agree.
lift : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 start : Vect g.size Nat} -> {0 k : Nat} ->
       Values g inner start k -> Values g inner start (S k)
lift = mapTable {p = \v => Best g inner start k v} {q = \v => Best g inner start (S k) v} (\_ => weaken)

0 liftValue : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 start : Vect g.size Nat} -> {0 k : Nat} ->
              (old : Values g inner start k) -> (i : Fin g.size) -> (entry i (lift old)).value = (entry i old).value
liftValue old i = cong (.value) (entryMap {p = Best g inner start k} {q = Best g inner start (S k)} (\_ => weaken) i old)

values : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 start : Vect g.size Nat} -> {0 k : Nat} ->
         Values g inner start k -> Vect g.size Nat
values = column {p = \v => Best g inner start k v} (\_, b => b.value)

0 startColumn : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 start : Vect g.size Nat} -> {m : Nat} ->
                {0 at : Fin m -> Fin g.size} -> (k : Nat) -> (vs : Vect m Nat) -> (eq : k + m = g.size) ->
                (here : (i : Fin m) -> finToNat (at i) = k + finToNat i) -> (val : (i : Fin m) -> index i vs = index (at i) start) ->
                column {p = Best g inner start 0} (\_, b => b.value) (startCells {g} {inner} {start} {at} k vs eq here val) = vs
startColumn {m = 0} k [] eq here val = Refl
startColumn {m = S m} k (v :: vs) eq here val =
  cong2 (::) Refl
        (startColumn (S k) vs (trans (plusSuccRightSucc k m) eq)
                     (\j => trans (here (FS j)) (sym (plusSuccRightSucc k (finToNat j)))) (\j => val (FS j)))

-- What `heaviest` returns when `start` already satisfies every listed arc:
-- the first check settles on the values after 0 rounds, which are `start`.
0 initialValues : {g : Graph} -> {inner : List (Fin (length g.arcs))} -> (start : Vect g.size Nat) ->
                  values (initial g inner start) = start
initialValues start = startColumn {at = \i => i} 0 start Refl (\i => Refl) (\i => Refl)

------------------------------------------------------------------------------
-- One arc

||| A finite arc, looked up.
public export
record Entry (g : Graph) (a : Fin (length g.arcs)) where
  constructor MkEntry
  src : Fin g.size
  dst : Fin g.size
  up : Nat
  down : Nat
  0 is : arc g a = MkArc src dst (Measured up down)

||| The listed arcs, looked up once: one finite entry per listed arc.
public export
Looked : (g : Graph) -> List (Fin (length g.arcs)) -> Type
Looked g = All (Entry g)

0 notFiniteStuck : IsFinite Unmeasured -> Void
notFiniteStuck ItIsFinite impossible

-- The precondition makes every listed arc finite, so an Unmeasured label
-- met here is `void` of it.
look : (g : Graph) -> (as : List (Fin (length g.arcs))) -> (0 _ : All IsFinite (labels g as)) -> Looked g as
look g as fin = entries as (lookUp g as) fin
  where
    entries : (as : List (Fin (length g.arcs))) -> At g as -> (0 _ : All IsFinite (labels g as)) -> Looked g as
    entries [] [] _ = []
    entries (a :: as) ((::) (MkArc q p (Measured gn ls)) eq xs) fs = MkEntry q p gn ls (sym eq) :: entries as xs (All.tail fs)
    entries (a :: as) ((::) (MkArc q p Unmeasured) eq xs) fs =
      void (notFiniteStuck (replace {p = IsFinite} (cong (.label) (sym eq)) (All.head fs)))

0 arcFinite : {g : Graph} -> {a : Fin (length g.arcs)} -> {0 q, p : Fin g.size} -> {0 gn, ls : Nat} ->
              arc g a = MkArc q p (Measured gn ls) -> IsFinite (arc g a).label
arcFinite eq = rewrite eq in ItIsFinite

-- The candidate an arc from a position gives: its source's walk, one arc on.
extendBest : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} -> {0 k : Nat} ->
             (old : Values g inner start k) -> (a : Fin (length g.arcs)) -> (0 _ : Elem a inner) -> (u, p : Fin g.size) -> (gn, ls : Nat) ->
             (0 eq : arc g a = MkArc u p (Measured gn ls)) -> (0 _ : LTE ls ((entry u old).value + gn)) ->
             Best g inner start (S k) p
extendBest old a e u p gn ls eq le =
  MkBest (minus ((entry u old).value + gn) ls)
         (Extend u (entry u old).walk a p e (cong (.from) eq) (cong (.to) eq) (arcFinite {g} {a} eq))
         (LTESucc (entry u old).within)
         (rewrite eq in relaxedExact (entry u old).exact le)

||| Relax one finite arc into `acc`, from the values of the round before.
relax : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} -> {0 k : Nat} ->
        (old : Values g inner start k) -> (a : Fin (length g.arcs)) -> (0 _ : Elem a inner) -> Entry g a ->
        Values g inner start (S k) -> Values g inner start (S k)
relax old a e (MkEntry u p gn ls eq) acc with (choose ((entry p acc).value + ls < (entry u old).value + gn))
  _ | Right _ = acc
  _ | Left lt = put p (extendBest old a e u p gn ls eq (below (ltSo lt))) acc

0 raisesPut : {0 p : Fin n -> Type} -> (val : {0 i : Fin n} -> p i -> Nat) -> (j : Fin n) -> (y : p j) -> (t : Table {n} p) ->
              LTE (val (entry j t)) (val y) -> (i : Fin n) -> LTE (val (entry i t)) (val (entry i (put j y t)))
raisesPut val j y t le i with (decEq i j)
  raisesPut val i y t le i | Yes Refl = rewrite entryPut i y t in le
  _ | No ne = rewrite entryPutOther i j ne y t in reflexive

0 relaxRaises : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} -> {0 k : Nat} ->
                (old : Values g inner start k) -> (a : Fin (length g.arcs)) -> (0 e : Elem a inner) -> (x : Entry g a) ->
                (acc : Values g inner start (S k)) -> (i : Fin g.size) ->
                LTE (entry i acc).value (entry i (relax old a e x acc)).value
relaxRaises old a e (MkEntry u p gn ls eq) acc i with (choose ((entry p acc).value + ls < (entry u old).value + gn))
  _ | Right _ = reflexive
  _ | Left lt = raisesPut {p = Best g inner start (S k)} (\b => b.value) p _ acc (underMinus (ltSo lt)) i

0 atPut : {0 p : Fin n -> Type} -> (val : {0 i : Fin n} -> p i -> Nat) -> (j : Fin n) -> (y : p j) -> (t : Table {n} p) ->
          LTE z (val y + d) -> LTE z (val (entry j (put j y t)) + d)
atPut val j y t le = rewrite entryPut j y t in le

0 relaxFits : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} -> {0 k : Nat} ->
              (old : Values g inner start k) -> (a : Fin (length g.arcs)) -> (0 e : Elem a inner) -> (x : Entry g a) ->
              (acc : Values g inner start (S k)) ->
              LTE ((entry x.src old).value + x.up) ((entry x.dst (relax old a e x acc)).value + x.down)
relaxFits old a e (MkEntry u p gn ls eq) acc with (choose ((entry p acc).value + ls < (entry u old).value + gn))
  _ | Right nlt = notLTImpliesGTE (notLtSo nlt)
  _ | Left lt = atPut {p = Best g inner start (S k)} {z = (entry u old).value + gn} {d = ls} (\b => b.value) p
                  (extendBest old a e u p gn ls eq (below (ltSo lt))) acc
                  (rewrite plusMinusLte ls ((entry u old).value + gn) (below (ltSo lt)) in reflexive)

------------------------------------------------------------------------------
-- One round

||| Relax every looked-up arc, in order, from the values of the round before.
relaxAll : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} -> {0 k : Nat} ->
           (old : Values g inner start k) -> (as : List (Fin (length g.arcs))) -> Looked g as ->
           (0 sub : {b : Fin (length g.arcs)} -> Elem b as -> Elem b inner) ->
           Values g inner start (S k) -> Values g inner start (S k)
relaxAll old [] [] sub acc = acc
relaxAll old (a :: as) (x :: xs) sub acc = relaxAll old as xs (\e => sub (There e)) (relax old a (sub Here) x acc)

0 relaxAllRaises : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} -> {0 k : Nat} ->
                   (old : Values g inner start k) -> (as : List (Fin (length g.arcs))) -> (xs : Looked g as) ->
                   (0 sub : {b : Fin (length g.arcs)} -> Elem b as -> Elem b inner) ->
                   (acc : Values g inner start (S k)) -> (i : Fin g.size) ->
                   LTE (entry i acc).value (entry i (relaxAll old as xs sub acc)).value
relaxAllRaises old [] [] sub acc i = reflexive
relaxAllRaises old (a :: as) (x :: xs) sub acc i =
  transitive (relaxRaises old a (sub Here) x acc i) (relaxAllRaises old as xs (\e => sub (There e)) _ i)

0 relaxAllFits : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} -> {0 k : Nat} ->
                 (old : Values g inner start k) -> (as : List (Fin (length g.arcs))) -> (xs : Looked g as) ->
                 (0 sub : {b : Fin (length g.arcs)} -> Elem b as -> Elem b inner) ->
                 (acc : Values g inner start (S k)) -> {b : Fin (length g.arcs)} -> Elem b as ->
                 IsFinite (arc g b).label ->
                 LTE ((entry (arc g b).from old).value + gainOf (arc g b).label)
                     ((entry (arc g b).to (relaxAll old as xs sub acc)).value + lossOf (arc g b).label)
relaxAllFits old (a :: as) (x@(MkEntry q p gn ls eq) :: xs) sub acc Here _ =
  rewrite eq in
  transitive (relaxFits old a (sub Here) x acc)
             (plusLteMonotoneRight ls _ _ (relaxAllRaises old as xs (\e => sub (There e)) _ p))
relaxAllFits old (a :: as) (x :: xs) sub acc (There e) f =
  relaxAllFits old as xs (\e' => sub (There e')) _ e f

||| One round: every listed arc relaxed from the values of the round before.
round : {g : Graph} -> {inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} -> {0 k : Nat} ->
        Looked g inner -> Values g inner start k -> Values g inner start (S k)
round xs old = relaxAll old inner xs (\e => e) (lift old)

0 roundRaises : {g : Graph} -> {inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} -> {0 k : Nat} ->
                (xs : Looked g inner) -> (old : Values g inner start k) -> (i : Fin g.size) ->
                LTE (entry i old).value (entry i (round xs old)).value
roundRaises xs old i = rewrite sym (liftValue old i) in relaxAllRaises old inner xs (\e => e) (lift old) i

-- The values after a round dominate every walk one arc longer: a walk's
-- last arc fits the new values, and what it extends is dominated by the
-- old ones, which the round only raises.
0 roundDominates : {g : Graph} -> {inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} -> {k : Nat} ->
                   (xs : Looked g inner) -> (old : Values g inner start k) -> Dominates k old -> Dominates (S k) (round xs old)
roundDominates xs old dom (Start v) _ =
  transitive (dom (Start v) LTEZero) (plusLteMonotoneRight 0 _ _ (roundRaises xs old v))
roundDominates xs old dom (Extend u w a v e l q f) (LTESucc le) =
  let fits = relaxAllFits old inner xs (\e => e) (lift old) e f
      fits' = replace {p = \x => LTE ((entry x old).value + gainOf (arc g a).label) ((entry (arc g a).to (round xs old)).value + lossOf (arc g a).label)} l fits
  in rewrite sym q in extends (dom w le) fits'

------------------------------------------------------------------------------
-- The check after a round: an arc that still relaxes, or a potential

data Settled : {g : Graph} -> {inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} -> {k : Nat} ->
               Values g inner start k -> List (Fin (length g.arcs)) -> Type where
  Relaxes : {0 g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 start : Vect g.size Nat} -> {0 k : Nat} ->
            {0 t : Values g inner start k} -> {0 as : List (Fin (length g.arcs))} ->
            (a : Fin (length g.arcs)) -> (0 _ : Elem a as) -> (x : Entry g a) ->
            (0 _ : LT ((entry x.dst t).value + x.down) ((entry x.src t).value + x.up)) -> Settled t as
  Settles : {0 g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 start : Vect g.size Nat} -> {0 k : Nat} ->
            {0 t : Values g inner start k} -> {0 as : List (Fin (length g.arcs))} ->
            All (Satisfies (values t)) (map (arc g) as) -> Settled t as

-- One comparison per arc: the first that fails is the arc that relaxes,
-- and if none does, the comparisons are the potential's evidence.
settle : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {0 start : Vect g.size Nat} -> {0 k : Nat} ->
         (t : Values g inner start k) -> (as : List (Fin (length g.arcs))) -> Looked g as -> Settled t as
settle t [] [] = Settles []
settle t (a :: as) (x :: xs) = case choose ((entry x.dst t).value + x.down < (entry x.src t).value + x.up) of
  Left lt => Relaxes a Here x (ltSo lt)
  Right nlt => case settle t as xs of
    Relaxes b e y r => Relaxes b (There e) y r
    Settles fs => Settles (satisfied x (notLTImpliesGTE (notLtSo nlt)) :: fs)
  where
    satisfied : (x : Entry g a) -> (0 _ : LTE ((entry x.src t).value + x.up) ((entry x.dst t).value + x.down)) -> Satisfies (values t) (arc g a)
    satisfied (MkEntry q p gn ls eq) le =
      rewrite eq in MkSatisfies (rewrite indexColumn {p = Best g inner start k} (\_, b => b.value) q t in
                                 rewrite indexColumn {p = Best g inner start k} (\_, b => b.value) p t in le)

------------------------------------------------------------------------------
-- The cycle a walk one arc too long holds

0 tooLong : {g : Graph} -> {inner : List (Fin (length g.arcs))} -> (ts : List (Fin g.size)) -> NoDup ts ->
            ((t : Fin g.size) -> Elem t ts -> Elem t (universe g inner)) -> length ts = S (length inner) -> Void
tooLong ts nd sub len =
  let le = pigeonhole nd sub
      le' = replace {p = \x => LTE x (length (universe g inner))} len le
      le'' = replace {p = \x => LTE (S (length inner)) x} (lengthMap inner) le'
  in succNotLTEpred le''

find : (x : Fin n) -> (ts : List (Fin n)) -> Decision (Elem x ts)
find x [] = Fails (\case _ impossible)
find x (t :: ts) = case samePosition x t of
  Yes eq => Holds (rewrite eq in Here)
  No ne => case find x ts of
    Holds e => Holds (There e)
    Fails ne' => Fails (\case Here => ne Refl; There e => ne' e)

record Split (g : Graph) (inner : List (Fin (length g.arcs))) (start : Vect g.size Nat) (v : Fin g.size) (r, f : Nat) where
  constructor MkSplit
  at : Fin g.size
  before : Walk g inner start at
  cycle : Path g inner at at
  rest : Path g inner at v
  0 nonEmpty : NonEmpty (targets cycle)
  0 short : LTE (steps before + length (targets rest)) (length inner)
  0 riseIs : rise before + (gains (labels g (arcsOf cycle)) + gains (labels g (arcsOf rest))) = r
  0 fallIs : fall before + (losses (labels g (arcsOf cycle)) + losses (labels g (arcsOf rest))) = f

0 splitSums : {g : Graph} -> (sum : List Label -> Nat) -> ((ws, vs : List Label) -> sum (ws ++ vs) = sum ws + sum vs) ->
              (as, bs, cs : List (Fin (length g.arcs))) -> as = bs ++ cs ->
              sum (labels g as) = sum (labels g bs) + sum (labels g cs)
splitSums sum app as bs cs eq = rewrite eq in rewrite mapAppend (\a => (arc g a).label) bs cs in app _ _

0 nonEmptyLength : {xs : List a} -> NonEmpty xs -> LTE 1 (length xs)
nonEmptyLength {xs = _ :: _} IsNonEmpty = LTESucc LTEZero

-- The suffix re-enters x: cut it there, and what lies between is the cycle.
found : {g : Graph} -> {inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} -> {0 v : Fin g.size} ->
        (x : Fin g.size) -> (pre : Walk g inner start x) -> (suf : Path g inner x v) -> Elem x (targets suf) ->
        (0 count : steps pre + length (targets suf) = S (length inner)) ->
        Split g inner start v (rise pre + gains (labels g (arcsOf suf))) (fall pre + losses (labels g (arcsOf suf)))
found x pre suf el count =
  let MkCut up rest as ts ne = cut suf el in
  MkSplit x pre up rest ne
    (shorter (replace {p = \z => steps pre + z = S (length inner)} ts count) (nonEmptyLength ne))
    (cong (rise pre +) (sym (splitSums gains gainsAppend _ _ _ as)))
    (cong (fall pre +) (sym (splitSums losses lossesAppend _ _ _ as)))

-- Peel the walk's arcs onto a suffix whose targets are distinct, until the
-- position the walk has reached is among them. The suffix cannot outgrow
-- the listed arcs' targets first (`tooLong`), so the walk's start is never
-- reached.
peel : {g : Graph} -> {inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} -> {0 v : Fin g.size} ->
       (x : Fin g.size) -> (pre : Walk g inner start x) -> (suf : Path g inner x v) ->
       (0 nd : NoDup (targets suf)) -> (0 count : steps pre + length (targets suf) = S (length inner)) ->
       Split g inner start v (rise pre + gains (labels g (arcsOf suf))) (fall pre + losses (labels g (arcsOf suf)))
peel x (Start x) suf nd count = void (tooLong (targets suf) nd (\t, e => targetsIn suf e) count)
peel x (Extend u w a x e l q f) suf nd count = case find x (targets suf) of
  Holds el => found x (Extend u w a x e l q f) suf el count
  Fails nel =>
    rewrite sym (plusAssociative (rise w) (gainOf (arc g a).label) (gains (labels g (arcsOf suf)))) in
    rewrite sym (plusAssociative (fall w) (lossOf (arc g a).label) (losses (labels g (arcsOf suf)))) in
    peel u w (Step a x e l q f suf) (nel :: nd) (trans (sym (plusSuccRightSucc _ _)) count)

------------------------------------------------------------------------------
-- Lemma 2

0 elemLength : Elem a xs -> LTE 1 (length xs)
elemLength Here = LTESucc LTEZero
elemLength (There _) = LTESucc LTEZero

0 exactly : {s, r : Nat} -> LTE s (S r) -> Not (LTE s r) -> s = S r
exactly le nle = antisymmetric le (notLTEImpliesGT nle)

extendWalk : {g : Graph} -> {0 inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} -> {0 k : Nat} ->
             (t : Values g inner start k) -> (a : Fin (length g.arcs)) -> (0 _ : Elem a inner) -> (u, p : Fin g.size) ->
             (0 eq : arc g a = MkArc u p (Measured gn ls)) -> Walk g inner start p
extendWalk t a e u p eq = Extend u (entry u t).walk a p e (cong (.from) eq) (cong (.to) eq) (arcFinite {g} {a} eq)

||| The arc that still relaxes after as many rounds as there are listed
||| arcs closes a walk one arc too long, and the cycle that walk holds
||| rises: a cycle that did not would leave a shorter walk the values
||| dominate and that rises no less.
climb : {g : Graph} -> {inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} -> {0 k : Nat} ->
        (0 _ : k = length inner) -> (t : Values g inner start k) -> (0 dom : Dominates k t) ->
        (a : Fin (length g.arcs)) -> (0 _ : Elem a inner) -> (x : Entry g a) ->
        (0 _ : LT ((entry x.dst t).value + x.down) ((entry x.src t).value + x.up)) ->
        (as ** Positive g as)
climb kIs t dom a e (MkEntry u p gn ls eq) rel =
  let 0 relW : LT ((entry p t).value + fall (extendWalk t a e u p eq)) (rise (extendWalk t a e u p eq))
      relW = rewrite eq in relaxes (entry u t).exact rel
  in case choose (steps (extendWalk t a e u p eq) <= length inner) of
    Left le => void (succNotLTEpred (transitive relW (dom (extendWalk t a e u p eq) (rewrite kIs in lteSo le))))
    Right nle =>
      let MkSplit x before cyc rest ne short riseIs fallIs =
            peel p (extendWalk t a e u p eq) Stay []
                 (trans (plusZeroRightNeutral _) (exactly (rewrite sym kIs in LTESucc (entry u t).within) (notLteSo nle))) in
      case choose (losses (labels g (arcsOf cyc)) < gains (labels g (arcsOf cyc))) of
        Left lt => (arcsOf cyc ** Sums (ringOf cyc ne) (pathFinite cyc) (ltSo lt))
        Right nlt =>
          void (noCycle {rb = rise before} {fb = fall before} {d = (entry p t).value}
                        {gc = gains (labels g (arcsOf cyc))} {lc = losses (labels g (arcsOf cyc))}
                        {ga = gains (labels g (arcsOf rest))} {la = losses (labels g (arcsOf rest))}
                        (notLTImpliesGTE (notLtSo nlt))
                        (rewrite sym (appendRise before rest) in rewrite sym (appendFall before rest) in
                         dom (append before rest) (rewrite kIs in rewrite appendSteps before rest in short))
                        (rewrite riseIs in rewrite fallIs in
                         rewrite plusZeroRightNeutral (rise (extendWalk t a e u p eq)) in
                         rewrite plusZeroRightNeutral (fall (extendWalk t a e u p eq)) in relW))

||| A potential the listed arcs fit, nowhere below the start: Bellman-Ford
||| only raises values.
public export
record Fitted (g : Graph) (inner : List (Fin (length g.arcs))) (start : Vect g.size Nat) where
  constructor MkFitted
  pot : Vect g.size Nat
  fits : All (Satisfies pot) (map (arc g) inner)
  0 above : Below start pot

-- Structural on the rounds left, with k + left = length inner; every value
-- no lower than the start's.
loop : {g : Graph} -> {inner : List (Fin (length g.arcs))} -> {start : Vect g.size Nat} ->
       Looked g inner -> (left : Nat) -> (0 k : Nat) -> (t : Values g inner start k) -> (0 _ : Dominates k t) ->
       (0 _ : (i : Fin g.size) -> LTE (index i start) (entry i t).value) ->
       (0 _ : k + left = length inner) ->
       Either (as ** Positive g as) (Fitted g inner start)
loop xs left k t dom above count = case settle t inner xs of
  Settles fs =>
    Right (MkFitted (values t) fs
                    (belowAt (\i => rewrite indexColumn {p = Best g inner start k} (\_, b => b.value) i t in above i)))
  Relaxes a e x rel => case left of
    S left' => loop xs left' (S k) (round xs t) (roundDominates xs t dom) (\i => transitive (above i) (roundRaises xs t i))
                    (trans (plusSuccRightSucc k left') count)
    Z => Left (climb (trans (sym (plusZeroRightNeutral k)) count) t dom a e x rel)

||| Lemma 2 on arcs already looked up, by Bellman-Ford on heaviest walks:
||| from `start`, as many rounds as there are listed arcs, each followed by
||| the check; a check that passes is the potential, and an arc that still
||| relaxes after the last round closes a cycle that rises.
export
heaviestOver : {g : Graph} -> {inner : List (Fin (length g.arcs))} -> Looked g inner -> (start : Vect g.size Nat) ->
               Either (as ** Positive g as) (Fitted g inner start)
heaviestOver xs start =
  loop xs (length inner) 0 (initial g inner start) dominatesInitial
       (\i => rewrite initialEntry {g} {inner} {start} i in reflexive) Refl

||| Lemma 2: `heaviestOver` on the listed arcs, each looked up once.
export
heaviest : (g : Graph) -> (inner : List (Fin (length g.arcs))) -> (0 _ : All IsFinite (labels g inner)) ->
           (start : Vect g.size Nat) ->
           Either (as ** Positive g as) (Fitted g inner start)
heaviest g inner fin start = heaviestOver (look g inner fin) start
