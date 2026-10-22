-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| How many values a chain of held dispatches holds, and the bound the
||| growth graph's held count stands for.
|||
||| A held dispatch re-packs a dictionary parameter with one more value
||| held (`HeldAt`, at the stuck path of fields it held it for); a held arm
||| puts a member in for a held value, which reduces, so the value goes and
||| the values the member closes over come (`PutIn`). A chain of such steps,
||| oldest first, holds `heldAfter n` values starting from n. The
||| translation carries two facts of every chain (`HeldChain`): it holds
||| each stuck path at most once, which `heldHere`'s request carries
||| (`heldOnce`), and every member it puts in answers a value held before
||| it, which each held arm carries (`putAnswers`). From them the count is
||| bounded by the program alone (`heldWithin`): at most the longest list
||| a site packs, and per stuck path the program has, the most values a
||| member closes over and one.
|||
||| Every proof is erased and total, and nothing here runs.
module IdrisMLIR.Proof.Held

import Libraries.Data.List.Finite

import Control.Relation
import Data.List
import Data.List.Elem
import Data.List.Quantifiers
import Data.List1
import Data.Nat

%default total

||| One step of a chain of held dispatches: a value held for a stuck path
||| of fields, or a member put in for a held value, closing over `own`
||| values.
public export
data HeldStep = HeldAt (List1 Nat) | PutIn Nat

||| How many values a chain holds after its steps, oldest first, from n: a
||| value held is one more; a member put in takes the value it answers and
||| brings the values it closes over.
public export
heldAfter : Nat -> List HeldStep -> Nat
heldAfter n [] = n
heldAfter n (HeldAt _ :: s) = heldAfter (S n) s
heldAfter n (PutIn own :: s) = heldAfter (pred n + own) s

||| The stuck paths a chain holds values for, in order.
public export
heldPaths : List HeldStep -> List (List1 Nat)
heldPaths [] = []
heldPaths (HeldAt p :: s) = p :: heldPaths s
heldPaths (PutIn _ :: s) = heldPaths s

||| How many values each member a chain puts in closes over, in order.
public export
owns : List HeldStep -> List Nat
owns [] = []
owns (HeldAt _ :: s) = owns s
owns (PutIn own :: s) = own :: owns s

||| Every member a chain puts in answers a value held before it and not yet
||| answered, k of them so far.
public export
data AnsweredFrom : Nat -> List HeldStep -> Type where
  NothingLeft : AnsweredFrom k []
  Holds : AnsweredFrom (S k) s -> AnsweredFrom k (HeldAt p :: s)
  Answers : AnsweredFrom k s -> AnsweredFrom (S k) (PutIn own :: s)

||| Every member a chain puts in answers a value it held before.
public export
0 Answered : List HeldStep -> Type
Answered s = AnsweredFrom 0 s

||| What the translation carries of every chain of held dispatches: each
||| stuck path held at most once, and every member put in answering a
||| value held before it.
public export
record HeldChain (s : List HeldStep) where
  constructor MkHeldChain
  0 once : NoDup (heldPaths s)
  0 answered : Answered s

||| A chain holds each stuck path at most once: what `heldHere`'s request
||| carries.
export
0 heldOnce : HeldChain s -> NoDup (heldPaths s)
heldOnce c = c.once

||| Every member a chain puts in answers a value it held: what each held
||| arm carries.
export
0 putAnswers : HeldChain s -> Answered s
putAnswers c = c.answered

------------------------------------------------------------------------------
-- The bound
------------------------------------------------------------------------------

0 sumOf : List Nat -> Nat
sumOf [] = 0
sumOf (o :: os) = o + sumOf os

0 lteToEq : b = c -> LTE a b -> LTE a c
lteToEq Refl le = le

0 lteOfEq : a = b -> LTE b c -> LTE a c
lteOfEq Refl le = le

0 shuffle : (p, w, l, o : Nat) -> (p + w) + l + o = (p + l) + (w + o)
shuffle p w l o =
  rewrite sym (plusAssociative p w l) in
  rewrite plusCommutative w l in
  rewrite plusAssociative p l w in
  rewrite sym (plusAssociative (p + l) w o) in
  Refl

0 predBelow : (m : Nat) -> LTE (pred m) m
predBelow Z = LTEZero
predBelow (S m) = lteSuccRight lteRefl

-- What a chain holds is at most what it started with, a value for each
-- path it held one for, and every value a member brought.
0 heldBelow : (n : Nat) -> (s : List HeldStep) -> LTE (heldAfter n s) (n + length (heldPaths s) + sumOf (owns s))
heldBelow n [] = lteToEq (sym (trans (plusZeroRightNeutral (n + 0)) (plusZeroRightNeutral n))) lteRefl
heldBelow n (HeldAt p :: s) =
  lteToEq (cong (\x => x + sumOf (owns s)) (plusSuccRightSucc n (length (heldPaths s)))) (heldBelow (S n) s)
heldBelow n (PutIn own :: s) =
  transitive (heldBelow (pred n + own) s)
    (lteOfEq (shuffle (pred n) own (length (heldPaths s)) (sumOf (owns s)))
       (plusLteMonotoneRight (own + sumOf (owns s)) (pred n + length (heldPaths s)) (n + length (heldPaths s))
          (plusLteMonotoneRight (length (heldPaths s)) (pred n) n (predBelow n))))

-- A chain puts in no more members than values it held, and the k it held
-- before.
0 answeredCount : AnsweredFrom k s -> LTE (length (owns s)) (k + length (heldPaths s))
answeredCount NothingLeft = LTEZero
answeredCount {k} (Holds {s} rest) = lteToEq (plusSuccRightSucc k (length (heldPaths s))) (answeredCount rest)
answeredCount (Answers rest) = LTESucc (answeredCount rest)

-- Values each at most M sum to at most M a value.
0 sumBelow : (os : List Nat) -> All (\o => LTE o m) os -> LTE (sumOf os) (length os * m)
sumBelow [] [] = LTEZero
sumBelow (o :: os) (le :: les) = plusLteMonotone le (sumBelow os les)

||| A chain holds at most L, the most it started with, and for each stuck
||| path of the program's P one value and the most values M a member closes
||| over: so a count of L + |P| (M + 1) bounds every chain the translation
||| makes, whatever its length.
export
0 heldWithin : {s : List HeldStep} -> {n, l, m : Nat} -> {ps : List (List1 Nat)} ->
               NoDup (heldPaths s) -> All (\p => Elem p ps) (heldPaths s) -> Answered s ->
               All (\o => LTE o m) (owns s) -> LTE n l ->
               LTE (heldAfter n s) (l + length ps * S m)
heldWithin {s} {n} {l} {m} {ps} once inside answered small start =
  let paths = pigeonhole once (\y, e => indexAll e inside)
      puts = answeredCount answered
      brought = transitive (sumBelow (owns s) small) (multRightMonotone m puts) in
  rewrite multRightSuccPlus (length ps) m in
  rewrite plusAssociative l (length ps) (length ps * m) in
  transitive (heldBelow n s)
             (plusLteMonotone (plusLteMonotone start paths) (transitive brought (multRightMonotone m paths)))
  where
    multRightMonotone : (c : Nat) -> LTE a b -> LTE (a * c) (b * c)
    multRightMonotone c LTEZero = LTEZero
    multRightMonotone c (LTESucc le) = plusLteMonotoneLeft c _ _ (multRightMonotone c le)
