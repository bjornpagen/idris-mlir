-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| How wide a node and how heavy a token a value a position receives can
||| have: Theorem 2, beside the heights' Theorem 1 (`Proof.Bound`).
|||
||| A literal a primitive computes at an instance can measure more than any
||| template's: `prim__mul_Int x x` at an instance whose x is a thousand is
||| a million, and a text appended to itself is twice as long. Each
||| computation grows the most its arguments measure by at most one
||| `grown` step (`Proof.Bound.AtComputed`), and nests a level below the
||| node it stands for, a builtin's call standing two high in the site
||| beside the constant it computes. So a node at depth δ of a value at a
||| position whose bound is X stands for at most X - δ computations
||| nested, and measures (a token its weight, a node its children) at most
||| the tower of that many steps over the base: the most any template's
||| node or token, the held count or an implementation's argument count
||| measures (`Light`, `Based`). The proof follows Lemma 1's: a marker,
||| a field and a member are carried by arcs whose weight is what the
||| depth gives up, and a family applied is carried as deep as its
||| arguments are high, which pays for every argument its meaning puts
||| deeper (`instLight`). The universe of requests bounds each parameter's
||| key by that tower at its height (`Proof.Requests.weightAt`), which is
||| never computed.
|||
||| Every proof is erased and total, and nothing here runs.
module IdrisMLIR.Proof.Weights

import IdrisMLIR.Proof.Bound
import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template

import Control.Relation
import Data.Fin
import Data.List
import Data.List.Elem
import Data.List.Quantifiers
import Data.Nat
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Light values
------------------------------------------------------------------------------

mutual
  ||| A template every node of which, at depth δ below it, measures at most
  ||| the tower of r - δ computations over w: a token its weight, a node its
  ||| children; a choice and a field are no node of their own.
  public export
  data Light : (w, r : Nat) -> Template -> Type where
    LightVar : Light w r (Var i d)
    LightHead : LTE (length ts) (steps r w) -> AllLight w (pred r) ts -> Light w r (Head a ts)
    LightOpaque : LTE (length ts) (steps r w) -> AllLight w (pred r) ts -> Light w r (Opaque a ts)
    LightApplied : LTE (S (length ts)) (steps r w) -> AllLight w (pred r) ts -> Light w r (Applied i d ts)
    LightComputing : LTE (S (length ts)) (steps r w) -> AllLight w (pred r) ts -> Light w r (Computing i d ts)
    LightChoice : AllLight w r ts -> Light w r (Choice c ts)
    LightField : Light w r t -> Light w r (Field k t)
    LightLeaf : Light w r (Leaf h)
    LightToken : LTE k (steps r w) -> Light w r (Token k)
    LightFormal : Light w r (Formal j k)
    LightMember : Light w r (Member k)

  public export
  data AllLight : (w, r : Nat) -> List Template -> Type where
    NoneLight : AllLight w r []
    EachLight : Light w r t -> AllLight w r ts -> AllLight w r (t :: ts)

||| What Theorem 2 reads of the model: a base of at least one, above every
||| site's template's widest node and heaviest token, the held count, and
||| the arguments of an implementation a member given at a use holds.
public export
record Based {g : Graph} (m : Model g) (w : Nat) where
  constructor MkBased
  0 one : LTE 1 w
  0 wide : (s : Site g.size) -> Elem s m.sites -> LTE (arity s.template) w
  0 heavy : (s : Site g.size) -> Elem s m.sites -> LTE (heaviest s.template) w
  0 held : LTE m.heldCount w
  0 given : {j : Address} -> {as : List Template} -> Arguments m j 0 as -> LTE (length as) w

------------------------------------------------------------------------------
-- The arithmetic
------------------------------------------------------------------------------

-- Base states only that `maximum` is above both arguments.
0 maxLub : {a, c : Nat} -> LTE a b -> LTE c b -> LTE (maximum a c) b
maxLub {a = Z} _ lc = lc
maxLub {a = S _} {c = Z} la _ = la
maxLub {a = S a} {c = S c} (LTESucc la) (LTESucc lc) = LTESucc (maxLub la lc)

0 maxLeft : {a, c, b : Nat} -> LTE (maximum a c) b -> LTE a b
maxLeft le = transitive (maximumLeftUpperBound a c) le

0 maxRight : {a, c, b : Nat} -> LTE (maximum a c) b -> LTE c b
maxRight le = transitive (maximumRightUpperBound a c) le

0 predBelow : (r : Nat) -> LTE (pred r) r
predBelow Z = LTEZero
predBelow (S r) = lteSuccRight reflexive

0 predMono : LTE a b -> LTE (pred a) (pred b)
predMono LTEZero = LTEZero
predMono (LTESucc le) = le

0 succPred : LTE 1 y -> S (pred y) = y
succPred (LTESucc _) = Refl

-- What fits below x with e beside it fits below x less e.
0 underMinus : {b, e, x : Nat} -> LTE (b + e) x -> LTE b (minus x e)
underMinus {e = Z} le = rewrite minusZeroRight x in replace {p = \z => LTE z x} (plusZeroRightNeutral b) le
underMinus {e = S e} {x = Z} le = void (succNotLTEzero (replace {p = \z => LTE z Z} (sym (plusSuccRightSucc b e)) le))
underMinus {e = S e} {x = S x} le =
  underMinus {e} {x} (fromLteSucc (replace {p = \z => LTE z (S x)} (sym (plusSuccRightSucc b e)) le))

-- A value b + e within x + d: b less d within x less e.
0 minusShift : {b, e, x, d : Nat} -> LTE (b + e) (x + d) -> LTE (minus b d) (minus x e)
minusShift {d = Z} le = rewrite minusZeroRight b in underMinus (replace {p = LTE (b + e)} (plusZeroRightNeutral x) le)
minusShift {d = S d} {b = Z} le = LTEZero
minusShift {d = S d} {b = S b} le =
  minusShift {d} {b} (fromLteSucc (replace {p = LTE (S (b + e))} (sym (plusSuccRightSucc x d)) le))

-- One deeper is one less.
0 minusSucc : (x, e : Nat) -> minus x (S e) = pred (minus x e)
minusSucc Z e = Refl
minusSucc (S x) Z = minusZeroRight x
minusSucc (S x) (S e) = minusSucc x e

0 minusSuccPred : (r, d : Nat) -> minus r (S d) = minus (pred r) d
minusSuccPred Z d = Refl
minusSuccPred (S r) d = Refl

0 minusBelow : (k, d : Nat) -> LTE (minus k d) k
minusBelow Z d = LTEZero
minusBelow (S k) Z = reflexive
minusBelow (S k) (S d) = lteSuccRight (minusBelow k d)

0 minusDeeper : (x, e : Nat) -> LTE (minus x (S e)) (minus x e)
minusDeeper x e = rewrite minusSucc x e in predBelow (minus x e)

0 plusMinusWithin : {q, r : Nat} -> LTE q r -> LTE (q + minus r q) r
plusMinusWithin qr = rewrite plusCommutative q (minus r q) in rewrite plusMinusLte q r qr in reflexive

0 cancelRight : (c : Nat) -> {a, b : Nat} -> LTE (a + c) (b + c) -> LTE a b
cancelRight Z le = replace {p = \z => LTE z b} (plusZeroRightNeutral a) (replace {p = LTE (a + 0)} (plusZeroRightNeutral b) le)
cancelRight (S c) le =
  cancelRight c (fromLteSucc (replace {p = \z => LTE z (S (b + c))} (sym (plusSuccRightSucc a c))
                                (replace {p = LTE (a + S c)} (sym (plusSuccRightSucc b c)) le)))

0 swapGain : (q, d, gain : Nat) -> q + (d + gain) = (q + gain) + d
swapGain q d gain = trans (cong (q +) (plusCommutative d gain)) (plusAssociative q gain d)

0 swapLoss : (pp, loss, d : Nat) -> (pp + loss) + d = (pp + d) + loss
swapLoss pp loss d = trans (sym (plusAssociative pp loss d)) (trans (cong (pp +) (plusCommutative loss d)) (plusAssociative pp d loss))

-- An arc that carries a part d deep to e deep, satisfied by the potential:
-- the source's potential with e beside it within the target's with d.
0 arcCarry : {e, loss, d, gain, q, pp : Nat} -> LTE (e + loss) (d + gain) -> LTE (q + gain) (pp + loss) -> LTE (q + e) (pp + d)
arcCarry el qg =
  cancelRight loss $
    transitive (replace {p = \z => LTE z (q + (d + gain))} (plusAssociative q e loss) (plusLteMonotoneLeft q _ _ el)) $
      replace {p = \z => LTE z ((pp + d) + loss)} (sym (swapGain q d gain)) $
        replace {p = LTE ((q + gain) + d)} (swapLoss pp loss d) $
          plusLteMonotoneRight d _ _ qg

-- A source's bound, carried as the arc carries.
0 boundCarry : {b, k, q, e, pp, d : Nat} -> LTE b (k + q) -> LTE (q + e) (pp + d) -> LTE (b + e) ((k + pp) + d)
boundCarry bq qe =
  transitive (plusLteMonotoneRight e _ _ bq) $
    replace {p = \z => LTE z ((k + pp) + d)} (plusAssociative k q e) $
      replace {p = LTE (k + (q + e))} (plusAssociative k pp d) $
        plusLteMonotoneLeft k _ _ qe

-- A field's, a member's or an argument's source, carried with nothing
-- matched: its bound within the target's budget there.
0 fieldRoom : {b, k, q, e, pp : Nat} -> LTE b (k + q) -> LTE (q + e) (pp + 0) -> LTE b (minus (k + pp) e)
fieldRoom bq qe = underMinus (replace {p = LTE (b + e)} (plusZeroRightNeutral (k + pp)) (boundCarry bq qe))

0 shuffle : (r, q, e : Nat) -> (r + q) + e = r + (e + q)
shuffle r q e = trans (sym (plusAssociative r q e)) (cong (r +) (plusCommutative q e))

-- A part d deep of a value, with arguments q high beside it, carried e
-- deep: what the arc pays for both.
0 shiftedPlus : {r, e, q, x, d : Nat} -> LTE (r + (e + q)) (x + d) -> LTE (q + e) x -> LTE ((minus r d + q) + e) x
shiftedPlus {d = Z} big _ =
  rewrite minusZeroRight r in
  replace {p = \z => LTE z x} (sym (shuffle r q e)) (replace {p = LTE (r + (e + q))} (plusZeroRightNeutral x) big)
shiftedPlus {d = S d} {r = Z} _ qe = qe
shiftedPlus {d = S d} {r = S r} big qe =
  shiftedPlus {d} {r} (fromLteSucc (replace {p = LTE (S (r + (e + q)))} (sym (plusSuccRightSucc x d)) big)) qe

0 rearrange : (q, hb, e : Nat) -> (q + hb) + e = hb + (e + q)
rearrange q hb e = trans (cong (+ e) (plusCommutative q hb)) (trans (sym (plusAssociative hb q e)) (cong (hb +) (plusCommutative q e)))

0 swapIn : (k, y, e : Nat) -> (k + y) + e = y + (k + e)
swapIn k y e = trans (cong (+ e) (plusCommutative k y)) (sym (plusAssociative y k e))

-- A family's value landed k high at arguments S (k + e) deep: the value's
-- and the arguments' budgets beside each other fit the node's.
0 landedRoom : {k, e, x : Nat} -> LTE (S (k + e)) x -> LTE ((k + minus x (S (k + e))) + e) x
landedRoom le =
  replace {p = \z => LTE ((k + minus x (S (k + e))) + e) z} (plusMinusLte (S (k + e)) x le) $
    replace {p = \z => LTE z (minus x (S (k + e)) + S (k + e))} (sym (swapIn k (minus x (S (k + e))) e)) $
      plusLteMonotoneLeft (minus x (S (k + e))) (k + e) (S (k + e)) (lteSuccRight reflexive)

0 landedSpace : {k, e, x, hb : Nat} -> LTE (S (k + e)) x -> LTE hb k -> LTE ((minus x (S (k + e)) + hb) + e) x
landedSpace le hk =
  transitive (plusLteMonotoneRight e _ _ (plusLteMonotoneLeft (minus x (S (k + e))) _ _ hk)) $
    replace {p = \z => LTE ((minus x (S (k + e)) + k) + e) z} (plusMinusLte (S (k + e)) x le) $
      replace {p = \z => LTE z (minus x (S (k + e)) + S (k + e))} (plusAssociative (minus x (S (k + e))) k e) $
        plusLteMonotoneLeft (minus x (S (k + e))) (k + e) (S (k + e)) (lteSuccRight reflexive)

-- A builtin's call stands at least two high, so the budget where it
-- stands is one computation above its arguments'.
0 computedBudget : {h, e, x : Nat} -> LTE (h + e) x -> LTE 2 h -> S (minus x (S e)) = minus x e
computedBudget hp two = trans (cong S (minusSucc x e)) (succPred (transitive (lteSuccLeft two) (underMinus hp)))

------------------------------------------------------------------------------
-- Lists and templates
------------------------------------------------------------------------------

0 widestAt : Elem t ts -> LTE (arity t) (widest ts)
widestAt Here = maximumLeftUpperBound _ _
widestAt (There el) = transitive (widestAt el) (maximumRightUpperBound _ _)

0 heaviestAt : Elem t ts -> LTE (heaviest t) (heaviestOf ts)
heaviestAt Here = maximumLeftUpperBound _ _
heaviestAt (There el) = transitive (heaviestAt el) (maximumRightUpperBound _ _)

0 allWriteLength : AllWrite m s ts ws -> length ws = length ts
allWriteLength [] = Refl
allWriteLength (_ :: xs) = cong S (allWriteLength xs)

0 allInstLength : AllInstantiate ws ts us -> length us = length ts
allInstLength [] = Refl
allInstLength (_ :: xs) = cong S (allInstLength xs)

0 allRereadLength : AllReread ts us -> length us = length ts
allRereadLength NoneReread = Refl
allRereadLength (EachReread _ xs) = cong S (allRereadLength xs)

0 allRenumberedLength : AllRenumbered c ts us -> length us = length ts
allRenumberedLength NoneRenumbered = Refl
allRenumberedLength (EachRenumbered _ xs) = cong S (allRenumberedLength xs)

0 lengthInit : (ws : List Template) -> LTE (length ws) (length (ws ++ [x]))
lengthInit [] = LTEZero
lengthInit (_ :: ws) = LTESucc (lengthInit ws)

-- c levels of a head above a template are no narrower and no lighter.
0 raiseWide : (k : Nat) -> (t : Template) -> LTE (arity t) (arity (raise k t))
raiseWide Z t = reflexive
raiseWide (S k) t = transitive (raiseWide k t) (transitive (maximumLeftUpperBound _ _) (maximumRightUpperBound 1 _))

0 raiseHeavy : (k : Nat) -> (t : Template) -> LTE (heaviest t) (heaviest (raise k t))
raiseHeavy Z t = reflexive
raiseHeavy (S k) t = transitive (raiseHeavy k t) (maximumLeftUpperBound _ _)

------------------------------------------------------------------------------
-- What lightness survives
------------------------------------------------------------------------------

0 allLightAt : Elem t ts -> AllLight w r ts -> Light w r t
allLightAt Here (EachLight t _) = t
allLightAt (There el) (EachLight _ ts) = allLightAt el ts

0 allLightIndex : AllLight w r ts -> (j : Fin (length ts)) -> Light w r (index' ts j)
allLightIndex (EachLight t _) FZ = t
allLightIndex (EachLight _ ts) (FS j) = allLightIndex ts j
allLightIndex NoneLight j = absurd j

0 allLightInit : (ws : List Template) -> AllLight w r (ws ++ [x]) -> AllLight w r ws
allLightInit [] _ = NoneLight
allLightInit (_ :: ws) (EachLight t ts) = EachLight t (allLightInit ws ts)

mutual
  ||| What is light under a budget is light under any larger one.
  export
  0 lightMore : LTE r r' -> Light w r t -> Light w r' t
  lightMore le LightVar = LightVar
  lightMore le (LightHead n ts) = LightHead (transitive n (stepsMono le)) (allLightMore (predMono le) ts)
  lightMore le (LightOpaque n ts) = LightOpaque (transitive n (stepsMono le)) (allLightMore (predMono le) ts)
  lightMore le (LightApplied n ts) = LightApplied (transitive n (stepsMono le)) (allLightMore (predMono le) ts)
  lightMore le (LightComputing n ts) = LightComputing (transitive n (stepsMono le)) (allLightMore (predMono le) ts)
  lightMore le (LightChoice ts) = LightChoice (allLightMore le ts)
  lightMore le (LightField t) = LightField (lightMore le t)
  lightMore le LightLeaf = LightLeaf
  lightMore le (LightToken k) = LightToken (transitive k (stepsMono le))
  lightMore le LightFormal = LightFormal
  lightMore le LightMember = LightMember

  export
  0 allLightMore : LTE r r' -> AllLight w r ts -> AllLight w r' ts
  allLightMore le NoneLight = NoneLight
  allLightMore le (EachLight t ts) = EachLight (lightMore le t) (allLightMore le ts)

mutual
  ||| A light value's widest node is within its budget's tower.
  export
  0 lightWide : Light w r t -> LTE (arity t) (steps r w)
  lightWide LightVar = LTEZero
  lightWide (LightHead n ts) = maxLub n (transitive (allWide ts) (stepsMono (predBelow _)))
  lightWide (LightOpaque n ts) = maxLub n (transitive (allWide ts) (stepsMono (predBelow _)))
  lightWide (LightApplied n ts) = maxLub n (transitive (allWide ts) (stepsMono (predBelow _)))
  lightWide (LightComputing n ts) = maxLub n (transitive (allWide ts) (stepsMono (predBelow _)))
  lightWide (LightChoice ts) = allWide ts
  lightWide (LightField t) = lightWide t
  lightWide LightLeaf = LTEZero
  lightWide (LightToken _) = LTEZero
  lightWide LightFormal = LTEZero
  lightWide LightMember = LTEZero

  0 allWide : AllLight w r ts -> LTE (widest ts) (steps r w)
  allWide NoneLight = LTEZero
  allWide (EachLight t ts) = maxLub (lightWide t) (allWide ts)

mutual
  ||| A light value's heaviest token is within its budget's tower.
  export
  0 lightHeavy : Light w r t -> LTE (heaviest t) (steps r w)
  lightHeavy LightVar = LTEZero
  lightHeavy (LightHead _ ts) = transitive (allHeavy ts) (stepsMono (predBelow _))
  lightHeavy (LightOpaque _ ts) = transitive (allHeavy ts) (stepsMono (predBelow _))
  lightHeavy (LightApplied _ ts) = transitive (allHeavy ts) (stepsMono (predBelow _))
  lightHeavy (LightComputing _ ts) = transitive (allHeavy ts) (stepsMono (predBelow _))
  lightHeavy (LightChoice ts) = allHeavy ts
  lightHeavy (LightField t) = lightHeavy t
  lightHeavy LightLeaf = LTEZero
  lightHeavy (LightToken k) = k
  lightHeavy LightFormal = LTEZero
  lightHeavy LightMember = LTEZero

  0 allHeavy : AllLight w r ts -> LTE (heaviestOf ts) (steps r w)
  allHeavy NoneLight = LTEZero
  allHeavy (EachLight t ts) = maxLub (lightHeavy t) (allHeavy ts)

-- What a light literal measures is within its budget's tower.
0 lightMeasure : Light w r t -> LTE (measureOf t) (steps r w)
lightMeasure (LightHead n _) = n
lightMeasure (LightToken k) = k
lightMeasure LightVar = LTEZero
lightMeasure (LightOpaque _ _) = LTEZero
lightMeasure (LightApplied _ _) = LTEZero
lightMeasure (LightComputing _ _) = LTEZero
lightMeasure (LightChoice _) = LTEZero
lightMeasure (LightField _) = LTEZero
lightMeasure LightLeaf = LTEZero
lightMeasure LightFormal = LTEZero
lightMeasure LightMember = LTEZero

0 allMeasures : AllLight w r ts -> LTE (measuresOf ts) (steps r w)
allMeasures NoneLight = LTEZero
allMeasures (EachLight t ts) = maxLub (lightMeasure t) (allMeasures ts)

-- A part of a leaf is a leaf.
0 leafParts : Sub d (Leaf h) u -> Light w r u
leafParts Self = LightLeaf
leafParts (Peel s) = leafParts s

||| A part d deep of a light value is light under its budget less d.
export
0 subLight : Light w r v -> Sub d v u -> Light w (minus r d) u
subLight {r} l Self = rewrite minusZeroRight r in l
subLight {r} {d = S d} (LightHead _ ts) (Child el s) = rewrite minusSuccPred r d in subLight (allLightAt el ts) s
subLight LightLeaf (Peel s) = leafParts (Peel s)

||| A part of a light value at any depth is light under its budget.
export
0 withinLight : Light w r v -> Within v u -> Light w r u
withinLight l Itself = l
withinLight {r} (LightHead _ ts) (InChild el wi) = lightMore (predBelow r) (withinLight (allLightAt el ts) wi)
withinLight (LightChoice ts) (InChoice el wi) = withinLight (allLightAt el ts) wi

-- A run read node by node has nodes of one child at most, and no token.
0 runLight : LTE 1 w -> RunRead h t -> Light w r t
runLight one RunReadZero = LightHead LTEZero NoneLight
runLight one (RunReadSucc x) = LightHead (transitive one (stepsAbove _ _)) (EachLight (runLight one x) NoneLight)
runLight one RunReadLeaf = LightLeaf

mutual
  ||| Another reading of a light value is light.
  export
  0 rereadLight : LTE 1 w -> Light w r u -> Reread u v -> Light w r v
  rereadLight one l RereadSame = l
  rereadLight one l RereadFormal = LightFormal
  rereadLight one (LightHead n ts) (RereadHead xs) = LightHead (rewrite allRereadLength xs in n) (allRereadLight one ts xs)
  rereadLight one (LightOpaque n ts) (RereadOpaque xs) = LightOpaque (rewrite allRereadLength xs in n) (allRereadLight one ts xs)
  rereadLight one l (RereadAsLeaf _) = LightLeaf
  rereadLight one l (RereadAsRun x) = runLight one x

  0 allRereadLight : LTE 1 w -> AllLight w r ts -> AllReread ts us -> AllLight w r us
  allRereadLight one NoneLight NoneReread = NoneLight
  allRereadLight one (EachLight t ts) (EachReread x xs) = EachLight (rereadLight one t x) (allRereadLight one ts xs)

mutual
  ||| A light value with its holes renumbered within the base is light.
  export
  0 renumberedLight : LTE c w -> Light w r v -> Renumbered c v u -> Light w r u
  renumberedLight cw l (TokenRenumbered le) = LightToken (transitive le (transitive cw (stepsAbove _ _)))
  renumberedLight cw (LightHead n ts) (HeadRenumbered xs) =
    LightHead (rewrite allRenumberedLength xs in n) (allRenumberedLight cw ts xs)
  renumberedLight cw (LightOpaque n ts) (OpaqueRenumbered xs) =
    LightOpaque (rewrite allRenumberedLength xs in n) (allRenumberedLight cw ts xs)
  renumberedLight cw (LightApplied n ts) (AppliedRenumbered xs) =
    LightApplied (rewrite allRenumberedLength xs in n) (allRenumberedLight cw ts xs)
  renumberedLight cw (LightComputing n ts) (ComputingRenumbered xs) =
    LightComputing (rewrite allRenumberedLength xs in n) (allRenumberedLight cw ts xs)
  renumberedLight cw (LightChoice ts) (ChoiceRenumbered _ xs) = LightChoice (allRenumberedLight cw ts xs)
  renumberedLight cw (LightField t) (FieldRenumbered x) = LightField (renumberedLight cw t x)
  renumberedLight cw l AsItWas = l

  0 allRenumberedLight : LTE c w -> AllLight w r ts -> AllRenumbered c ts us -> AllLight w r us
  allRenumberedLight cw NoneLight NoneRenumbered = NoneLight
  allRenumberedLight cw (EachLight t ts) (EachRenumbered x xs) = EachLight (renumberedLight cw t x) (allRenumberedLight cw ts xs)

mutual
  -- A value no node of which has more than one child and which holds no
  -- token, as a capped position's are, is light under any budget.
  0 narrowLight : LTE 1 w -> (t : Template) -> LTE (arity t) 1 -> LTE (heaviest t) 0 -> Light w r t
  narrowLight one (Var _ _) _ _ = LightVar
  narrowLight one (Head a ts) wide heavy =
    LightHead (transitive (maxLeft wide) (transitive one (stepsAbove _ _))) (narrowAll one ts (maxRight wide) heavy)
  narrowLight one (Opaque a ts) wide heavy =
    LightOpaque (transitive (maxLeft wide) (transitive one (stepsAbove _ _))) (narrowAll one ts (maxRight wide) heavy)
  narrowLight one (Applied i d ts) wide heavy =
    LightApplied (transitive (maxLeft wide) (transitive one (stepsAbove _ _))) (narrowAll one ts (maxRight wide) heavy)
  narrowLight one (Computing i d ts) wide heavy =
    LightComputing (transitive (maxLeft wide) (transitive one (stepsAbove _ _))) (narrowAll one ts (maxRight wide) heavy)
  narrowLight one (Choice c ts) wide heavy = LightChoice (narrowAll one ts wide heavy)
  narrowLight one (Field k t) wide heavy = LightField (narrowLight one t wide heavy)
  narrowLight one (Leaf _) _ _ = LightLeaf
  narrowLight one (Token k) _ heavy = LightToken (transitive heavy LTEZero)
  narrowLight one (Formal _ _) _ _ = LightFormal
  narrowLight one (Member _) _ _ = LightMember

  0 narrowAll : LTE 1 w -> (ts : List Template) -> LTE (widest ts) 1 -> LTE (heaviestOf ts) 0 -> AllLight w r ts
  narrowAll one [] _ _ = NoneLight
  narrowAll one (t :: ts) wide heavy =
    EachLight (narrowLight one t (maxLeft wide) (maxLeft heavy)) (narrowAll one ts (maxRight wide) (maxRight heavy))

0 speltLight : All (\c => c = Leaf 1) cs -> AllLight w r cs
speltLight [] = NoneLight
speltLight (Refl :: rest) = EachLight LightLeaf (speltLight rest)

-- A constant measuring within a budget's tower is light under it.
0 constantLight : ConstantForm u -> LTE (measureOf u) (steps r w) -> Light w r u
constantLight CountedForm le = LightToken le
constantLight LeafForm _ = LightLeaf
constantLight (SpeltForm leaves) le = LightHead le (speltLight leaves)

||| What a value loses with its last argument is light where it was.
export
0 dropsLastLight : Light w r v -> DropsLast v u -> Light w r u
dropsLastLight (LightHead n kids) (LastOfHead {ws}) = LightHead (transitive (lengthInit ws) n) (allLightInit ws kids)
dropsLastLight {r} (LightHead _ (EachLight l _)) OnlyApplied = lightMore (predBelow r) l

------------------------------------------------------------------------------
-- Beta
------------------------------------------------------------------------------

mutual
  ||| Beta's lightness: a family's meaning light under b, with its arguments
  ||| light under q and no higher than q, makes a value light under any r
  ||| with room for both side by side and for the arguments placed as deep
  ||| as the meaning reaches.
  export
  0 instLight : Instantiates ws t u -> Light w b t -> AllLight w q ws -> LTE (tallest ws) q ->
                LTE (b + q) r -> LTE (q + height t) r -> Light w r u
  instLight {q} (IFormal j) _ wsl _ _ space = lightMore (transitive (lteAddRight q) space) (allLightIndex wsl j)
  instLight {ws} {b} {q} {r} (IApplied {as} {body} j wb inner) (LightHead _ (EachLight _ asl)) wsl tw room space =
    let qr = transitive (lteAddRight q) space
        hb = transitive (withinHeight wb) (transitive (tallestIndex ws j) tw) in
    instLight inner (withinLight (allLightIndex wsl j) wb)
              (allLightMore (transitive (predBelow b) (underMinus room)) asl)
              (transitive (transitive (maximumRightUpperBound 1 (tallest as)) (lteSuccRight reflexive))
                          (underMinus (replace {p = \z => LTE z r} (plusCommutative q _) space)))
              (plusMinusWithin qr)
              (transitive (plusLteMonotoneLeft (minus r q) _ _ hb) (rewrite plusMinusLte q r qr in reflexive))
  instLight {b} {q} {r} (IHead xs) (LightHead n kids) wsl tw room space =
    LightHead (rewrite allInstLength xs in transitive n (stepsMono (transitive (lteAddRight b) room)))
              (allInstLight xs kids wsl tw (predRoom room space) (predSpace space))
  instLight {b} {q} {r} (IOpaque xs) (LightOpaque n kids) wsl tw room space =
    LightOpaque (rewrite allInstLength xs in transitive n (stepsMono (transitive (lteAddRight b) room)))
                (allInstLight xs kids wsl tw (predRoom room space) (predSpace space))
  instLight ILeaf _ _ _ _ _ = LightLeaf
  instLight {b} IToken (LightToken k) _ _ room _ = LightToken (transitive k (stepsMono (transitive (lteAddRight b) room)))
  instLight {q} (IChosen el x) (LightChoice ls) wsl tw room space =
    instLight x (allLightAt el ls) wsl tw room (transitive (plusLteMonotoneLeft q _ _ (tallestAbove el)) space)

  0 allInstLight : AllInstantiate ws ts us -> AllLight w b ts -> AllLight w q ws -> LTE (tallest ws) q ->
                   LTE (b + q) r -> LTE (q + tallest ts) r -> AllLight w r us
  allInstLight [] NoneLight _ _ _ _ = NoneLight
  allInstLight {q} (x :: xs) (EachLight t ts) wsl tw room space =
    EachLight (instLight x t wsl tw room (transitive (plusLteMonotoneLeft q _ _ (maximumLeftUpperBound _ _)) space))
              (allInstLight xs ts wsl tw room (transitive (plusLteMonotoneLeft q _ _ (maximumRightUpperBound _ _)) space))

  -- A node's children: one level less of budget, of room and of space.
  0 predSpace : {q, x, r : Nat} -> LTE (q + S x) r -> LTE (q + x) (pred r)
  predSpace space = predMono (replace {p = \z => LTE z r} (sym (plusSuccRightSucc q x)) space)

  0 predRoom : {b, q, x, r : Nat} -> LTE (b + q) r -> LTE (q + S x) r -> LTE (pred b + q) (pred r)
  predRoom {b = Z} room space = transitive (lteAddRight q) (predSpace space)
  predRoom {b = S b} room space = predMono room

------------------------------------------------------------------------------
-- What an unmarked template writes
------------------------------------------------------------------------------

mutual
  -- What an instance writes at an unmarked template is light under the
  -- template's own height: every computation in it stands in the template.
  0 unmarkedLight : Based m w -> Unmarked t -> Writes m s t u -> LTE (arity t) w -> LTE (heaviest t) w ->
                    Light w (height t) u
  unmarkedLight ms um (AtVar _ _ _ _) _ _ = absurd um
  unmarkedLight ms um (AtHead xs) wide heavy =
    LightHead (rewrite allWriteLength xs in transitive (maxLeft wide) (stepsAbove _ _))
              (unmarkedAllLight ms (unmarkedHead um) xs (maxRight wide) heavy)
  unmarkedLight ms um (AtOpaque xs) wide heavy =
    LightHead (rewrite allWriteLength xs in transitive (maxLeft wide) (stepsAbove _ _))
              (unmarkedAllLight ms (unmarkedOpaque um) xs (maxRight wide) heavy)
  unmarkedLight ms um AtLeaf _ _ = LightLeaf
  unmarkedLight ms um (AtRunRead run) _ _ = runLight ms.one run
  unmarkedLight ms um (AtComputed {ts} {ws} xs form meas) wide heavy = case unmarkedChoice um of
    (UnmarkedHead us :: _) =>
      constantLight form
        (transitive meas
           (transitive (grownMono (allMeasures (unmarkedAllLight ms us xs (maxRight (maxLeft wide)) (maxLeft heavy))))
                       (stepsMono (maximumLeftUpperBound (S (tallest ts)) _))))
  unmarkedLight ms um (AtRun _ _) _ _ = LightLeaf
  unmarkedLight ms um (AtCut _ _) _ _ = LightLeaf
  unmarkedLight ms um AtToken _ heavy = LightToken (transitive heavy (stepsAbove _ _))
  unmarkedLight ms um AtFormal _ _ = LightFormal
  unmarkedLight ms um (Chosen el x) wide heavy =
    lightMore (tallestAbove el)
      (unmarkedLight ms (unmarkedAt el (unmarkedChoice um)) x (transitive (widestAt el) wide) (transitive (heaviestAt el) heavy))
  unmarkedLight ms um (AtContracted {ts} el x dropped) wide heavy =
    lightMore (transitive (tallestAbove el) (lteSuccRight reflexive))
      (dropsLastLight (unmarkedLight ms (unmarkedAt el (unmarkedHead um)) x
                                     (transitive (widestAt el) (maxRight wide)) (transitive (heaviestAt el) heavy))
                      dropped)
  unmarkedLight ms um (Beta _ _ _ _ _ _) _ _ = absurd um
  unmarkedLight ms um (GivenPart _ _ _ _) _ _ = absurd um
  unmarkedLight ms um (MemberOf _ _) _ _ = absurd um
  unmarkedLight ms um (Landed {k} {ts} {ws} l iv sub wb xs inst) wide heavy =
    let hb = transitive (withinHeight wb) (landedPart l iv sub) in
    instLight inst
      (lightMore (minusBelow k _) (withinLight (subLight (landedLight ms l iv) sub) wb))
      (unmarkedAllLight ms (unmarkedHead (unmarkedRaise k um)) xs
                        (maxRight (transitive (raiseWide k (Head Nothing ts)) wide))
                        (transitive (raiseHeavy k (Head Nothing ts)) heavy))
      (unmarkedAll (unmarkedHead (unmarkedRaise k um)) xs)
      (rewrite raisedHeight k (Head Nothing ts) in plusLteMonotoneLeft k _ _ (lteSuccRight reflexive))
      (rewrite raisedHeight k (Head Nothing ts) in
         transitive (plusLteMonotoneLeft (tallest ts) _ _ hb)
                    (rewrite plusCommutative (tallest ts) k in plusLteMonotoneLeft k _ _ (lteSuccRight reflexive)))
  unmarkedLight ms um (LandedMember {k} {ts} l iv sub wm) wide heavy =
    lightMore (rewrite raisedHeight k (Head Nothing ts) in lteAddRight k)
      (lightMore (minusBelow k _) (withinLight (subLight (landedLight ms l iv) sub) wm))
  unmarkedLight ms um (AtField _ _ _) _ _ = absurd um
  unmarkedLight ms um (AtMember _ _ _) _ _ = absurd um
  unmarkedLight ms um (AtHeldHole _ _ _ _) _ _ = absurd um

  0 unmarkedAllLight : Based m w -> AllUnmarked ts -> AllWrite m s ts ws -> LTE (widest ts) w -> LTE (heaviestOf ts) w ->
                       AllLight w (tallest ts) ws
  unmarkedAllLight ms [] [] _ _ = NoneLight
  unmarkedAllLight ms (um :: ums) (x :: xs) wide heavy =
    EachLight (lightMore (maximumLeftUpperBound _ _) (unmarkedLight ms um x (maxLeft wide) (maxLeft heavy)))
              (allLightMore (maximumRightUpperBound _ _) (unmarkedAllLight ms ums xs (maxRight wide) (maxRight heavy)))

  -- What lands where only closed values no higher than k land is light
  -- under k.
  0 landedLight : {g : Graph} -> {m : Model g} -> {p : Fin g.size} -> {v : Template} ->
                  Based m w -> Lands g m p k -> InV m p v -> Light w k v
  landedLight ms l (Capped cap _ _ _) = absurd (trans (sym cap) l.uncapped)
  landedLight ms l (Reduced s el wr) = case l.under s el Refl of
    (um, le) => lightMore le (unmarkedLight ms um wr (ms.wide s el) (ms.heavy s el))

------------------------------------------------------------------------------
-- Theorem 2
------------------------------------------------------------------------------

mutual
  ||| Theorem 2: under a feasible potential, every value a position can
  ||| receive is light under the position's bound: no node wider, and no
  ||| token heavier, than the tower of that many computations over the
  ||| base, one fewer for each level down.
  export
  0 lightBounded : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> {p : Fin g.size} -> {v : Template} ->
                   Based m w -> Describes m -> Feasible g pot -> InV m p v -> Light w (bound g pot p) v
  lightBounded {v} ms ds fe (Capped _ _ narrow light) = narrowLight ms.one v narrow light
  lightBounded {g} {pot} {v} {w} ms ds fe (Reduced s el wr) =
    let cov = indexAll el ds in
    rewrite boundUncapped {g} {pot} {p = s.target} cov.uncapped in
      replace {p = \r => Light w r v} (minusZeroRight (g.constant + index s.target pot))
        (lightAt ms ds fe wr cov.covered (ms.wide s el) (ms.heavy s el)
                 (replace {p = \z => LTE z (g.constant + index s.target pot)} (sym (plusZeroRightNeutral _))
                          (transitive cov.constant (lteAddRight _))))

  -- By induction on what an instance writes, as Lemma 1: a part of a
  -- site's template e deep, no wider and no heavier than the base, writes
  -- what is light under the target's budget less e.
  0 lightAt : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> {s : Site g.size} -> {t, u : Template} -> {e : Nat} ->
              Based m w -> Describes m -> Feasible g pot -> Writes m s t u -> CoveredAt m s e t ->
              LTE (arity t) w -> LTE (heaviest t) w ->
              LTE (height t + e) (g.constant + index s.target pot) ->
              Light w (minus (g.constant + index s.target pot) e) u
  lightAt {g} {pot} ms ds fe (AtVar {p} wa iv sub again) cov _ _ _ = case coveredVar cov p wa of
    MkCarries arc wt =>
      lightMore (minusShift (boundCarry (boundBelow g pot p) (arcCarry wt (arcHolds fe arc))))
                (rereadLight ms.one (subLight (lightBounded ms ds fe iv) sub) again)
  lightAt {g} {pot} {s} {e} ms ds fe (AtHead {ts} xs) cov wide heavy hp =
    LightHead (rewrite allWriteLength xs in transitive (maxLeft wide) (stepsAbove _ _))
              (rewrite sym (minusSucc (g.constant + index s.target pot) e) in
                 allLightWritten ms ds fe xs (coveredHead cov) (maxRight wide) heavy
                   (replace {p = \z => LTE z (g.constant + index s.target pot)} (plusSuccRightSucc (tallest ts) e) hp))
  lightAt {g} {pot} {s} {e} ms ds fe (AtOpaque {ts} xs) cov wide heavy hp =
    LightHead (rewrite allWriteLength xs in transitive (maxLeft wide) (stepsAbove _ _))
              (rewrite sym (minusSucc (g.constant + index s.target pot) e) in
                 allLightWritten ms ds fe xs (coveredOpaque cov) (maxRight wide) heavy
                   (replace {p = \z => LTE z (g.constant + index s.target pot)} (plusSuccRightSucc (tallest ts) e) hp))
  lightAt ms ds fe AtLeaf _ _ _ _ = LightLeaf
  lightAt ms ds fe (AtRunRead run) _ _ _ _ = runLight ms.one run
  lightAt {g} {pot} {s} {e} {w} ms ds fe (AtComputed {ts} {ws} xs form meas) cov wide heavy hp = case coveredChoice cov of
    (c :: _) =>
      constantLight form
        (transitive meas
           (replace {p = \y => LTE (grown (measuresOf ws)) (steps y w)} (computedBudget hp (computedTall ts))
              (grownMono (allMeasures
                 (allLightWritten ms ds fe xs (coveredHead c) (maxRight (maxLeft wide)) (maxLeft heavy)
                    (replace {p = \z => LTE z (g.constant + index s.target pot)} (plusSuccRightSucc (tallest ts) e)
                             (transitive (plusLteMonotoneRight e _ _ (maximumLeftUpperBound (S (tallest ts)) _)) hp)))))))
  lightAt ms ds fe (AtRun _ _) _ _ _ _ = LightLeaf
  lightAt ms ds fe (AtCut _ _) _ _ _ _ = LightLeaf
  lightAt ms ds fe AtToken _ _ heavy _ = LightToken (transitive heavy (stepsAbove _ _))
  lightAt ms ds fe AtFormal _ _ _ _ = LightFormal
  lightAt ms ds fe (Chosen el x) cov wide heavy hp =
    lightAt ms ds fe x (coveredIn el (coveredChoice cov)) (transitive (widestAt el) wide) (transitive (heaviestAt el) heavy)
            (transitive (plusLteMonotoneRight _ _ _ (tallestAbove el)) hp)
  lightAt {g} {pot} {s} {e} ms ds fe (AtContracted {ts} el x dropped) cov wide heavy hp =
    dropsLastLight
      (lightMore (minusDeeper (g.constant + index s.target pot) e)
         (lightAt ms ds fe x (coveredIn el (coveredHead cov)) (transitive (widestAt el) (maxRight wide))
                  (transitive (heaviestAt el) heavy)
                  (transitive (plusLteMonotoneRight (S e) _ _ (tallestAbove el))
                              (replace {p = \z => LTE z (g.constant + index s.target pot)} (plusSuccRightSucc (tallest ts) e) hp))))
      dropped
  lightAt {g} {pot} {s} {e} ms ds fe (Beta {p} {ts} {ws} wa iv sub wb xs inst) cov wide heavy hp = case coveredApplied cov of
    (writes, _) => case writes p wa of
      (MkCarries arc wt, us) =>
        let qe = lteSuccLeft hp
            carried = carry (partBelow (bounded ds fe iv) sub) wt (arcHolds fe arc) in
        instLight inst
          (withinLight (subLight (lightBounded ms ds fe iv) sub) wb)
          (unmarkedAllLight ms us xs (maxRight wide) heavy)
          (unmarkedAll us xs)
          (underMinus (shiftedPlus (boundCarry (boundBelow g pot p) (arcCarry wt (arcHolds fe arc))) qe))
          (underMinus (replace {p = \z => LTE z (g.constant + index s.target pot)} (sym (rearrange (tallest ts) _ e))
                         (transitive (plusLteMonotoneRight (e + tallest ts) _ _ (withinHeight wb)) carried)))
  lightAt {g} {pot} {s} {e} ms ds fe (GivenPart {p} {ts} wa iv sub wm) cov wide heavy hp = case coveredApplied cov of
    (writes, _) => case writes p wa of
      (MkCarries arc wt, _) =>
        lightMore (underMinus (transitive (plusLteMonotoneRight e _ _ (lteAddRight _))
                                          (shiftedPlus (boundCarry (boundBelow g pot p) (arcCarry wt (arcHolds fe arc)))
                                                       (lteSuccLeft hp))))
                  (withinLight (subLight (lightBounded ms ds fe iv) sub) wm)
  lightAt {g} {pot} {s} {e} ms ds fe (MemberOf el args) cov _ _ _ = case coveredApplied cov of
    (_, arcs) =>
      LightHead (transitive (ms.given args) (stepsAbove _ _))
                (rewrite sym (minusSucc (g.constant + index s.target pot) e) in argumentsLight ms ds fe args (arcs _ el))
  lightAt {g} {pot} {s} {e} ms ds fe (Landed {k} {ts} {ws} l iv sub wb xs inst) cov wide heavy hp =
    let deep = replace {p = \z => LTE z (g.constant + index s.target pot)} (raisedAt k ts e) hp
        fits = transitive (lteAddRight (S (k + e))) (replace {p = \z => LTE z (g.constant + index s.target pot)}
                                                             (plusCommutative (tallest ts) (S (k + e))) deep)
        hb = transitive (withinHeight wb) (landedPart l iv sub) in
    instLight inst
      (lightMore (minusBelow k _) (withinLight (subLight (landedLight ms l iv) sub) wb))
      (allLightWritten ms ds fe xs (coveredHead (coveredRaise k cov))
                       (maxRight (transitive (raiseWide k (Head Nothing ts)) wide))
                       (transitive (raiseHeavy k (Head Nothing ts)) heavy) deep)
      (underMinus (allWrittenAt ds fe xs (coveredHead (coveredRaise k cov)) deep))
      (underMinus (landedRoom fits))
      (underMinus (landedSpace fits hb))
  lightAt {g} {pot} {s} {e} ms ds fe (LandedMember {k} {ts} l iv sub wm) cov _ _ hp =
    lightMore (underMinus (transitive (plusLteMonotoneRight e _ _ (lteAddRight k))
                                      (replace {p = \z => LTE (z + e) (g.constant + index s.target pot)}
                                               (raisedHeight k (Head Nothing ts)) hp)))
              (lightMore (minusBelow k _) (withinLight (subLight (landedLight ms l iv) sub) wm))
  lightAt {g} {pot} ms ds fe (AtField {p} el inField iv) cov _ _ _ = case coveredField cov _ el p inField of
    MkCarries arc wt => lightMore (fieldRoom (boundBelow g pot p) (arcCarry wt (arcHolds fe arc))) (lightBounded ms ds fe iv)
  lightAt {g} {pot} ms ds fe (AtMember {p} inChoice iv again) cov _ _ _ = case coveredMember cov p inChoice of
    MkCarries arc wt =>
      renumberedLight ms.held (lightMore (fieldRoom (boundBelow g pot p) (arcCarry wt (arcHolds fe arc))) (lightBounded ms ds fe iv))
                      again
  lightAt ms ds fe (AtHeldHole _ _ _ within) _ _ _ _ = LightToken (transitive within (transitive ms.held (stepsAbove _ _)))

  -- A head's children, one deeper.
  0 allLightWritten : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> {s : Site g.size} -> {e : Nat} ->
                      Based m w -> Describes m -> Feasible g pot -> AllWrite m s ts ws -> AllCovered m s (S e) ts ->
                      LTE (widest ts) w -> LTE (heaviestOf ts) w ->
                      LTE (tallest ts + S e) (g.constant + index s.target pot) ->
                      AllLight w (minus (g.constant + index s.target pot) (S e)) ws
  allLightWritten ms ds fe [] [] _ _ _ = NoneLight
  allLightWritten {e} ms ds fe (x :: xs) (c :: cs) wide heavy hp =
    EachLight (lightAt ms ds fe x c (maxLeft wide) (maxLeft heavy)
                       (transitive (plusLteMonotoneRight (S e) _ _ (maximumLeftUpperBound _ _)) hp))
              (allLightWritten ms ds fe xs cs (maxRight wide) (maxRight heavy)
                               (transitive (plusLteMonotoneRight (S e) _ _ (maximumRightUpperBound _ _)) hp))

  -- The arguments of an implementation an applied function gives, one
  -- deeper than it, each carried from the position that received it.
  0 argumentsLight : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> {s : Site g.size} -> {e : Nat} ->
                     Based m w -> Describes m -> Feasible g pot -> Arguments m j q as ->
                     ((p' : Fin g.size) -> Elem p' (m.positionsOf j) -> Carries g p' 0 (S e) s.target) ->
                     AllLight w (minus (g.constant + index s.target pot) (S e)) as
  argumentsLight ms ds fe Ended arcs = NoneLight
  argumentsLight {g} {pot} ms ds fe (Given p' inJ _ iv rest) arcs =
    EachLight (case arcs p' inJ of
                 MkCarries arc wt => lightMore (fieldRoom (boundBelow g pot p') (arcCarry wt (arcHolds fe arc))) (lightBounded ms ds fe iv))
              (argumentsLight ms ds fe rest arcs)

||| What Theorem 2 gives a value of V at a position: no node wider and no
||| token heavier than the tower of the position's bound over the base.
export
0 measuredWithin : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> {p : Fin g.size} -> {v : Template} ->
                   Based m w -> Describes m -> Feasible g pot -> InV m p v ->
                   (LTE (arity v) (steps (bound g pot p) w), LTE (heaviest v) (steps (bound g pot p) w))
measuredWithin ms ds fe iv = (lightWide (lightBounded ms ds fe iv), lightHeavy (lightBounded ms ds fe iv))
