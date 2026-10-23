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
||| member closes over and one; and so is every hole a request holds
||| (`holeWithin`).
|||
||| Where a held value is written is decided here, once: at its place's
||| position for lists of one value where it can be its list's one value
||| (`canBeAlone`), at the position for lists of several where it can be
||| one of two or more (`canBeAmong`), and every list an instance gives has
||| each value written where it stands (`aloneWritten`, `amongWritten`). A
||| list of several packs to a chain of pairs (`pairChain`), one for each
||| length up to the held count (`chainListed`), each a measure above its
||| values (`chainMeasured`), so no packing draws an arc nothing bounds.
|||
||| The two decisions run; every proof is erased and total.
module IdrisMLIR.Proof.Held

import Libraries.Data.List.Finite

import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template

import Control.Relation
import Data.List
import Data.List.Elem
import Data.List.Quantifiers
import Data.List1
import Data.Nat

%default total

-- A chain's step that holds one more value is this module's own.
%hide IdrisMLIR.Proof.Growth.Holds

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
predBelow (S m) = lteSuccRight reflexive

-- What a chain holds is at most what it started with, a value for each
-- path it held one for, and every value a member brought.
0 heldBelow : (n : Nat) -> (s : List HeldStep) -> LTE (heldAfter n s) (n + length (heldPaths s) + sumOf (owns s))
heldBelow n [] = lteToEq (sym (trans (plusZeroRightNeutral (n + 0)) (plusZeroRightNeutral n))) reflexive
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

||| A hole a request holds is numbered below the values its chain holds, and
||| its token weighs one more than its number: within the same count, so a
||| hole in a member's place, or a member's hole renumbered after the ones
||| an arm holds already, is a token the held count covers
||| (`Proof.Bound.AtHeldHole`, `Proof.Bound.Renumbered`).
export
0 holeWithin : {s : List HeldStep} -> {n, l, m : Nat} -> {ps : List (List1 Nat)} ->
               NoDup (heldPaths s) -> All (\p => Elem p ps) (heldPaths s) -> Answered s ->
               All (\o => LTE o m) (owns s) -> LTE n l -> LT i (heldAfter n s) ->
               LTE (S i) (l + length ps * S m)
holeWithin once inside answered small start below = transitive below (heldWithin once inside answered small start)

------------------------------------------------------------------------------
-- Where a held value is written
------------------------------------------------------------------------------

-- Each place a dictionary is has two held positions: the values of its
-- lists of one value, each held as itself, and the values of its lists of
-- two or more, which pairs hold. A place that gives a list writes each
-- value of it at the positions it can stand at in the lists it describes;
-- what follows says which, and that every list an instance gives has each
-- of its values written where it stands.

||| How many values one way of writing a value of a list stands for: one,
||| or two or more.
public export
data Brings = OneValue | SeveralValues

||| A value can be its list's one value: no other value of its list is
||| there for certain (`firm`), and the way it is written brings one.
public export
data Alone : (firm, others : Nat) -> Brings -> Type where
  NoneBeside : Alone Z others OneValue

||| A value can be one of two or more: another value of its list is there
||| for certain, another can be there (`others`), or the way it is written
||| brings several.
public export
data Among : (firm, others : Nat) -> Brings -> Type where
  BesideFirm : Among (S firm) others b
  BesideOther : Among firm (S others) b
  OfSeveral : Among firm others SeveralValues

notAloneFirm : Alone (S firm) others b -> Void
notAloneFirm NoneBeside impossible

notAloneSeveral : Alone firm others SeveralValues -> Void
notAloneSeveral NoneBeside impossible

notAmong : Among Z Z OneValue -> Void
notAmong BesideFirm impossible
notAmong BesideOther impossible
notAmong OfSeveral impossible

||| Whether a value can be its list's one value: where the value of a list
||| of one is written is decided here, once.
export
canBeAlone : (firm, others : Nat) -> (b : Brings) -> Decided (Alone firm others b)
canBeAlone Z others OneValue = Yes NoneBeside
canBeAlone Z others SeveralValues = No notAloneSeveral
canBeAlone (S firm) others b = No notAloneFirm

||| Whether a value can be one of two or more: where the values of a list
||| of several are written is decided here, once.
export
canBeAmong : (firm, others : Nat) -> (b : Brings) -> Decided (Among firm others b)
canBeAmong (S firm) others b = Yes BesideFirm
canBeAmong Z (S others) b = Yes BesideOther
canBeAmong Z Z SeveralValues = Yes OfSeveral
canBeAmong Z Z OneValue = No notAmong

||| What one item of a list given to a dictionary is to its instances: one
||| value of a type the walk knows, there in every instance; a dictionary's
||| values packed as one, there where that dictionary holds any; or each
||| value a dictionary or a member holds, as many as it holds.
public export
data ItemKind = AlwaysOne | AtMostOne | AnyNumber

||| How many values an item gives at an instance.
public export
data Gives : ItemKind -> Nat -> Type where
  GivesOne : Gives AlwaysOne 1
  GivesNone : Gives AtMostOne 0
  GivesIt : Gives AtMostOne 1
  GivesMany : (k : Nat) -> Gives AnyNumber k

||| What each item of a list gives at one instance, in order.
public export
data HeldInstance : List ItemKind -> List Nat -> Type where
  NothingGiven : HeldInstance [] []
  ItemGiving : Gives k c -> HeldInstance ks cs -> HeldInstance (k :: ks) (c :: cs)

||| How many values the items give together.
public export
heldGiven : List Nat -> Nat
heldGiven [] = 0
heldGiven (c :: cs) = c + heldGiven cs

||| How many items are there in every instance.
public export
alwaysIn : List ItemKind -> Nat
alwaysIn [] = 0
alwaysIn (AlwaysOne :: ks) = S (alwaysIn ks)
alwaysIn (AtMostOne :: ks) = alwaysIn ks
alwaysIn (AnyNumber :: ks) = alwaysIn ks

||| How the values an item gives are written: one value by the way that
||| brings one, two or more by the way that brings several.
public export
bringing : Nat -> Brings
bringing (S (S _)) = SeveralValues
bringing (S Z) = OneValue
bringing Z = OneValue

0 predEq : S a = S b -> a = b
predEq Refl = Refl

-- Three counts that add up to one, the middle one at least one: it is the
-- one, and the others are none.
0 oneOfThree : (x, c, y : Nat) -> x + (c + y) = 1 -> LTE 1 c -> (x = 0, c = 1, y = 0)
oneOfThree Z (S Z) Z Refl _ = (Refl, Refl, Refl)
oneOfThree Z (S Z) (S y) Refl _ impossible
oneOfThree Z (S (S c)) y Refl _ impossible
oneOfThree Z Z y _ one = void (succNotLTEzero one)
oneOfThree (S x) Z y _ one = void (succNotLTEzero one)
oneOfThree (S x) (S c) y eq _ = void (SIsNotZ (trans (plusSuccRightSucc x (c + y)) (predEq eq)))

-- Items that give nothing at an instance hold none there in every one.
0 noneGiven : HeldInstance ks cs -> heldGiven cs = 0 -> alwaysIn ks = 0
noneGiven NothingGiven _ = Refl
noneGiven (ItemGiving GivesOne _) eq = void (SIsNotZ eq)
noneGiven (ItemGiving GivesNone rest) eq = noneGiven rest eq
noneGiven (ItemGiving GivesIt _) eq = void (SIsNotZ eq)
noneGiven (ItemGiving (GivesMany Z) rest) eq = noneGiven rest eq
noneGiven (ItemGiving (GivesMany (S _)) _) eq = void (SIsNotZ eq)

-- Items that give something are at least one item.
0 nonEmptyGiven : HeldInstance ks cs -> LTE 1 (heldGiven cs) -> (n : Nat ** length ks = S n)
nonEmptyGiven NothingGiven one = void (succNotLTEzero one)
nonEmptyGiven (ItemGiving {ks = rest} _ _) _ = (length rest ** Refl)

-- Items around one item, giving one value or more besides the one it
-- gives, are at least one item.
0 someOther : {after : List ItemKind} -> HeldInstance before cb -> HeldInstance after ca ->
              LTE 2 (heldGiven cb + S (heldGiven ca)) -> (n : Nat ** length before + length after = S n)
someOther NothingGiven ia two = nonEmptyGiven ia (fromLteSucc two)
someOther (ItemGiving {ks = rest} _ _) ia _ = (length rest + length after ** Refl)

||| A list an instance gives one value, given by one of its items: that
||| value is written where a list's one value is. No other item is there
||| in every instance, since each of those gives a value, and the way it
||| is written brings one.
export
0 aloneWritten : {before, after : List ItemKind} -> {cb, ca : List Nat} -> {c : Nat} ->
                 HeldInstance before cb -> Gives k c -> HeldInstance after ca ->
                 heldGiven cb + (c + heldGiven ca) = 1 -> LTE 1 c ->
                 Alone (alwaysIn before + alwaysIn after) (length before + length after) (bringing c)
aloneWritten ib g ia givenOne one = case oneOfThree (heldGiven cb) c (heldGiven ca) givenOne one of
  (none, Refl, none') => rewrite noneGiven ib none in rewrite noneGiven ia none' in NoneBeside

||| A list an instance gives two values or more: each value one of its
||| items gives is written where the values of a list of several are. An
||| item that gives several brings several; one that gives one has
||| another item beside it that gives the rest.
export
0 amongWritten : {before, after : List ItemKind} -> {cb, ca : List Nat} -> {c : Nat} ->
                 HeldInstance before cb -> Gives k c -> HeldInstance after ca ->
                 LTE 2 (heldGiven cb + (c + heldGiven ca)) -> LTE 1 c ->
                 Among (alwaysIn before + alwaysIn after) (length before + length after) (bringing c)
amongWritten {c = Z} ib g ia two one = void (succNotLTEzero one)
amongWritten {c = S Z} ib g ia two one = case someOther ib ia two of
  (n ** many) => rewrite many in BesideOther
amongWritten {c = S (S c')} ib g ia two one = OfSeveral

------------------------------------------------------------------------------
-- The pairs that hold a list of several
------------------------------------------------------------------------------

||| The one value a list of n + 1 held values packs to, over the held
||| position of their values (`Var 0 0`), at a pair's address: n pairs,
||| each but the last value first in one with the rest after it. A list of
||| one value is held as itself.
public export
pairChain : Address -> Nat -> Template
pairChain a Z = Var 0 0
pairChain a (S n) = Head (Just a) [Var 0 0, pairChain a n]

||| The values a list of two up to m + 1 held values packs to, one for
||| each length, the longest first.
public export
pairChainsUpTo : Address -> Nat -> List Template
pairChainsUpTo a Z = []
pairChainsUpTo a (S m) = pairChain a (S m) :: pairChainsUpTo a m

||| A chain of n pairs is n high: each pair one above the rest.
export
0 pairChainHeight : (a : Address) -> (n : Nat) -> height (pairChain a n) = n
pairChainHeight a Z = Refl
pairChainHeight a (S n) = cong S (trans (maximumZeroNLeft (height (pairChain a n))) (pairChainHeight a n))

0 lteSuccCases : {k, m : Nat} -> LTE k (S m) -> Either (k = S m) (LTE k m)
lteSuccCases {k = Z} _ = Right LTEZero
lteSuccCases {k = S k'} {m = Z} (LTESucc LTEZero) = Left Refl
lteSuccCases {k = S k'} {m = S m'} (LTESucc le) = case lteSuccCases le of
  Left eq => Left (cong S eq)
  Right le' => Right (LTESucc le')

||| A list of k + 1 held values, two or more and at most m + 1, packs to a
||| value written for its length: a dictionary's values held in pairs,
||| packed as one, is one of the chains its holder's pairs are given.
export
0 chainListed : (a : Address) -> {k, m : Nat} -> LTE 1 k -> LTE k m -> Elem (pairChain a k) (pairChainsUpTo a m)
chainListed a {m = Z} one le = void (succNotLTEzero (transitive one le))
chainListed a {m = S m'} one le = case lteSuccCases le of
  Left Refl => Here
  Right le' => There (chainListed a one le')

||| Each length has its own chain: chains of two depths differ, so a
||| length is written once.
export
0 chainsApart : {a : Address} -> {n, n' : Nat} -> Not (n = n') -> Not (pairChain a n = pairChain a n')
chainsApart other same = other (trans (sym (pairChainHeight a n)) (trans (cong height same) (pairChainHeight a n')))

||| As many chains as lengths.
export
0 chainsCounted : (a : Address) -> (m : Nat) -> length (pairChainsUpTo a m) = m
chainsCounted a Z = Refl
chainsCounted a (S m) = cong S (chainsCounted a m)

||| A finite weight: what an arc of it adds is a measure.
public export
data MeasuredWeight : Weight -> Type where
  MeasuredBy : MeasuredWeight (Finite gain loss)

||| A measured weight draws a measured arc.
export
0 measuredArc : MeasuredWeight w -> (lab : Label ** (labelOf w = Just lab, IsFinite lab))
measuredArc (MeasuredBy {gain} {loss}) = (Measured gain loss ** (Refl, ItIsFinite))

0 allJoin : {0 p : x -> Type} -> All p xs -> All p ys -> All p (xs ++ ys)
allJoin [] rest = rest
allJoin (q :: qs) rest = q :: allJoin qs rest

-- Every occurrence of a chain's marker is under pairs alone: finite.
0 chainOccurrences : (e : Nat) -> (n : Nat) -> All (\x => MeasuredWeight (snd x)) (occurrences e (pairChain a n))
chainOccurrences e Z = [MeasuredBy]
chainOccurrences e (S n) = MeasuredBy :: allJoin (chainOccurrences (S e) n) []

0 joinMeasured : MeasuredWeight v -> MeasuredWeight w -> MeasuredWeight (join v w)
joinMeasured (MeasuredBy {gain = g} {loss = l}) (MeasuredBy {gain = g'} {loss = l'}) with (g + l' <= g' + l)
  _ | True = MeasuredBy
  _ | False = MeasuredBy

0 insertMeasured : {i : Nat} -> {acc : List (Nat, Weight)} -> MeasuredWeight w ->
                   All (\x => MeasuredWeight (snd x)) acc -> All (\x => MeasuredWeight (snd x)) (insertJoin i w acc)
insertMeasured {acc = []} mw [] = [mw]
insertMeasured {acc = (j, v) :: rest} mw (mv :: ms) with (i == j)
  _ | True = joinMeasured mv mw :: ms
  _ | False with (i < j)
    _ | True = mw :: mv :: ms
    _ | False = mv :: insertMeasured mw ms

0 joinAllMeasured : {acc, xs : List (Nat, Weight)} -> All (\x => MeasuredWeight (snd x)) acc ->
                    All (\x => MeasuredWeight (snd x)) xs -> All (\x => MeasuredWeight (snd x)) (joinAll acc xs)
joinAllMeasured {xs = []} ma [] = ma
joinAllMeasured {xs = (i, w) :: rest} ma (mw :: ms) = joinAllMeasured (insertMeasured mw ma) ms

0 settledMeasured : {xs : List (Nat, Weight)} -> All (\x => MeasuredWeight (snd x)) xs ->
                    All (\x => MeasuredWeight (snd x)) (map Template.settledEntry xs)
settledMeasured {xs = []} [] = []
settledMeasured {xs = (i, w) :: rest} (MeasuredBy :: ms) = MeasuredBy :: settledMeasured ms

||| Every weight a pair chain draws is measured: packing held values raises
||| their height by the pairs above them, never by what nothing bounds, so
||| an arc a packing draws is never one no potential meets.
export
0 chainMeasured : (a : Address) -> (n : Nat) -> All (\x => MeasuredWeight (snd x)) (weights (pairChain a n))
chainMeasured a n = settledMeasured (joinAllMeasured [] (chainOccurrences 0 n))
