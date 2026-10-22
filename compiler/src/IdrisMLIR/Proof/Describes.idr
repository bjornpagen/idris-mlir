-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the growth graph draws for each site of its model, and the proof
||| that a graph so drawn describes the model (`Proof.Bound.Describes`)
||| under any feasible potential.
|||
||| The graph is drawn from the model, never beside it: the frontend reads
||| the program's sites (`Frontend.Growth.Graph`), numbers their positions,
||| and draws each site's arcs and K here. A site draws an arc from every
||| position its writer reads a parameter at, as heavy as the most that
||| parameter's occurrences carry (`weights`); a field of a dictionary an
||| arc from that field's position of every implementation its record can
||| be (`fieldRoots`); and a held dictionary, or an applied family that
||| gives one, an arc from every position of every implementation it can be
||| (`heldRoots`). A part under a computation draws Stuck arcs, which no
||| feasible potential satisfies (`measuredOnly`), so it needs no other
||| covering. The order of the arcs is the order the check reads them in:
||| each site's own, then each site's from held dictionaries and fields.
module IdrisMLIR.Proof.Describes

import IdrisMLIR.Proof.Bound
import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template

import Data.DPair
import Data.Nat
import Data.So

%default total

------------------------------------------------------------------------------
-- Where a part is read
------------------------------------------------------------------------------

||| Where a part of a site's template is read: what an arc from a held
||| dictionary's implementation into the site weighs there, and how many
||| levels down the part is.
public export
record Depth where
  constructor MkDepth
  arcWeight : Weight
  depth : Nat

||| A site's template, where it lands.
public export
atTop : Depth
atTop = MkDepth (Finite 1 0) 0

||| A head's child.
public export
underHead : Depth -> Depth
underHead at = MkDepth (plus at.arcWeight (Finite 1 0)) (S at.depth)

||| A child of a recursion or of an applied or computing family: a level
||| down, and what an arc carries there unbounded.
public export
underComputation : Depth -> Depth
underComputation at = MkDepth Stuck (S at.depth)

||| How high K stands for a part h high to stay within it here.
public export
above : Depth -> Nat -> Nat
above at h = h + at.depth

||| What an arc from a field's position into the site weighs where the field
||| is read: the field's value sits where the field does, a level above the
||| arguments of a held dictionary read there.
public export
fieldWeight : Depth -> Weight
fieldWeight at = plus at.arcWeight (Finite 0 1)

------------------------------------------------------------------------------
-- What a template's fields and held dictionaries carry
------------------------------------------------------------------------------

||| What a template's fields and held dictionaries carry: each field's
||| position, an implementation's field k, with the weight of its arc; each
||| implementation a held dictionary or an applied family can be, with the
||| weight of the arcs from its positions; and what K must stand above.
public export
record Carried where
  constructor MkCarried
  fields : List ((Address, Nat), Weight)
  held : List (Address, Weight)
  needs : List Nat

public export
noneCarried : Carried
noneCarried = MkCarried [] [] []

public export
alsoCarried : Carried -> Carried -> Carried
alsoCarried x y = MkCarried (x.fields ++ y.fields) (x.held ++ y.held) (x.needs ++ y.needs)

||| Each implementation a template can be, with the weight of the arcs from
||| its positions here.
public export
heldRoots : (Template -> List Address) -> Depth -> Template -> List (Address, Weight)
heldRoots rts at t = map (\j => (j, at.arcWeight)) (rts t)

||| Field k of each implementation a record can be, with the weight of the
||| arc from its position here.
public export
fieldRoots : (Template -> List Address) -> Depth -> Nat -> Template -> List ((Address, Nat), Weight)
fieldRoots rts at k rec = map (\j => ((j, k), fieldWeight at)) (rts rec)

mutual
  ||| Every field's and held dictionary's value in a template read here: a
  ||| held dictionary is a head over its implementation's arguments, a
  ||| level down, and so is what an applied family gives; a field is what
  ||| its position holds, whatever its record writes.
  public export
  carriedAt : (Template -> List Address) -> Depth -> Template -> Carried
  carriedAt rts at (Field k rec) = MkCarried (fieldRoots rts at k rec) [] []
  carriedAt rts at t@(Held _ _) = MkCarried [] (heldRoots rts at t) [above at 1]
  carriedAt rts at t@(Applied _ _ ts) =
    alsoCarried (MkCarried [] (heldRoots rts at t) []) (carriedAll rts (underComputation at) ts)
  carriedAt rts at (Head _ ts) = carriedAll rts (underHead at) ts
  carriedAt rts at (Opaque _ ts) = carriedAll rts (underComputation at) ts
  carriedAt rts at (Computing _ _ ts) = carriedAll rts (underComputation at) ts
  carriedAt rts at (Choice _ ts) = carriedAll rts at ts
  carriedAt rts at (Var _ _) = noneCarried
  carriedAt rts at (Leaf _) = noneCarried
  carriedAt rts at (Token _) = noneCarried
  carriedAt rts at (Formal _ _) = noneCarried

  public export
  carriedAll : (Template -> List Address) -> Depth -> List Template -> Carried
  carriedAll rts at [] = noneCarried
  carriedAll rts at (t :: ts) = alsoCarried (carriedAt rts at t) (carriedAll rts at ts)

------------------------------------------------------------------------------
-- What a site draws
------------------------------------------------------------------------------

||| The positions the writer reads parameter i at.
public export
writersOf : Nat -> List (Nat, Fin n) -> List (Fin n)
writersOf i [] = []
writersOf i ((j, p) :: ws) = if i == j then p :: writersOf i ws else writersOf i ws

||| An arc into a target from each of some positions, at a label; none
||| for no label.
public export
arcsInto : Fin n -> Maybe Label -> List (Fin n) -> List (Arc n)
arcsInto t Nothing ps = []
arcsInto t (Just lab) ps = map (\p => MkArc p t lab) ps

||| The arcs of parameters with their weights, each from the positions the
||| writer reads it at.
public export
varArcs : Fin n -> List (Nat, Fin n) -> List (Nat, Weight) -> List (Arc n)
varArcs t ws [] = []
varArcs t ws ((i, w) :: rest) = arcsInto t (labelOf w) (writersOf i ws) ++ varArcs t ws rest

||| The arcs of implementations with their weights, each from every
||| position of its nodes.
public export
heldArcs : Fin n -> (Address -> List (Fin n)) -> List (Address, Weight) -> List (Arc n)
heldArcs t ps [] = []
heldArcs t ps ((j, w) :: rest) = arcsInto t (labelOf w) (ps j) ++ heldArcs t ps rest

||| The arcs of fields with their weights, each from its position.
public export
fieldArcs : Fin n -> (Address -> Nat -> List (Fin n)) -> List ((Address, Nat), Weight) -> List (Arc n)
fieldArcs t fps [] = []
fieldArcs t fps (((j, k), w) :: rest) = arcsInto t (labelOf w) (fps j k) ++ fieldArcs t fps rest

||| A site's own arcs, from its parameters.
public export
ownArcs : Site n -> List (Arc n)
ownArcs s = varArcs s.target s.writers (weights s.template)

||| A site's arcs from what its held dictionaries can be, then from its
||| fields' positions.
public export
projectedArcs : (Address -> List (Fin n)) -> (Address -> Nat -> List (Fin n)) -> Site n -> List (Arc n)
projectedArcs ps fps s =
  heldArcs s.target ps (carriedAt s.roots atTop s.template).held ++
  fieldArcs s.target fps (carriedAt s.roots atTop s.template).fields

||| What K stands above for a template: its own height, and what its held
||| dictionaries need.
public export
needsOf : (Template -> List Address) -> Template -> List Nat
needsOf rts t = height t :: (carriedAt rts atTop t).needs

||| A list for each element, joined.
public export
allOf : (a -> List b) -> List a -> List b
allOf f [] = []
allOf f (x :: xs) = f x ++ allOf f xs

||| The most of some numbers and a floor.
public export
topOf : Nat -> List Nat -> Nat
topOf b [] = b
topOf b (k :: ks) = maximum k (topOf b ks)

public export
ownTagged : (Site n, tag) -> List (Arc n, tag)
ownTagged (s, x) = map (\a => (a, x)) (ownArcs s)

public export
projectedTagged : (Address -> List (Fin n)) -> (Address -> Nat -> List (Fin n)) -> (Site n, tag) -> List (Arc n, tag)
projectedTagged ps fps (s, x) = map (\a => (a, x)) (projectedArcs ps fps s)

public export
siteNeeds : (Site n, tag) -> List Nat
siteNeeds (s, x) = needsOf s.roots s.template

||| Every site's arcs, each with what tags it: each site's own, then each
||| site's from held dictionaries and fields.
public export
drawn : (Address -> List (Fin n)) -> (Address -> Nat -> List (Fin n)) -> List (Site n, tag) -> List (Arc n, tag)
drawn ps fps ss = allOf ownTagged ss ++ allOf (projectedTagged ps fps) ss

||| The graph drawn from some sites over n positions with their caps: K
||| above what every site needs and above `beyond`, what the templates
||| written at capped positions need, which no site of the model holds.
public export
graphOf : {n : Nat} -> (Address -> List (Fin n)) -> (Address -> Nat -> List (Fin n)) -> (beyond : Nat) ->
          Vect n (Maybe Nat) -> List (Site n, tag) -> Graph
graphOf ps fps beyond caps ss = MkGraph n (map fst (drawn ps fps ss)) (topOf beyond (allOf siteNeeds ss)) caps

||| The model the graph is drawn from.
public export
modelOf : {n : Nat} -> (ps : Address -> List (Fin n)) -> (fps : Address -> Nat -> List (Fin n)) ->
          (Fin n -> Maybe (Head, Nat)) -> (beyond : Nat) -> (caps : Vect n (Maybe Nat)) -> (ss : List (Site n, tag)) ->
          Model (graphOf ps fps beyond caps ss)
modelOf ps fps positionOf beyond caps ss = MkModel (map fst ss) fps positionOf ps

||| The sites that land at uncapped positions, with the erased evidence of
||| each, and those that land at capped ones: a capped position's cap is
||| its bound, so no site into it is drawn.
public export
uncappedOnly : (caps : Vect n (Maybe Nat)) -> List (Site n, tag) ->
               (Subset (List (Site n, tag)) (\ss => All (\x => index (fst x).target caps = Nothing) ss), List (Site n, tag))
uncappedOnly caps [] = (Element [] [], [])
uncappedOnly caps (x :: xs) with (index (fst x).target caps) proof here
  _ | Nothing = let (Element kept evidence, capped) = uncappedOnly caps xs in (Element (x :: kept) (here :: evidence), capped)
  _ | Just _ = let (kept, capped) = uncappedOnly caps xs in (kept, x :: capped)

------------------------------------------------------------------------------
-- Lists
------------------------------------------------------------------------------

0 elemAppendLeft : Elem x xs -> Elem x (xs ++ ys)
elemAppendLeft Here = Here
elemAppendLeft (There e) = There (elemAppendLeft e)

0 elemAppendRight : (xs : List a) -> Elem x ys -> Elem x (xs ++ ys)
elemAppendRight [] e = e
elemAppendRight (_ :: xs) e = There (elemAppendRight xs e)

0 appendElem : (xs : List a) -> Elem x (xs ++ ys) -> Either (Elem x xs) (Elem x ys)
appendElem [] e = Right e
appendElem (_ :: xs) Here = Left Here
appendElem (_ :: xs) (There e) = case appendElem xs e of
  Left l => Left (There l)
  Right r => Right r

0 allOfHas : (f : a -> List b) -> {xs : List a} -> Elem x xs -> Elem y (f x) -> Elem y (allOf f xs)
allOfHas f Here ey = elemAppendLeft ey
allOfHas f {xs = z :: zs} (There ex) ey = elemAppendRight (f z) (allOfHas f ex ey)

0 writersOfHas : {i : Nat} -> {ws : List (Nat, Fin n)} -> Elem (i, p) ws -> Elem p (writersOf i ws)
writersOfHas Here = rewrite soToEq (equalSelf i) in Here
writersOfHas {ws = (j, q) :: rest} (There el) with (i == j)
  _ | True = There (writersOfHas el)
  _ | False = writersOfHas el

0 varArcsHas : {t : Fin n} -> {ws : List (Nat, Fin n)} -> {vs : List (Nat, Weight)} ->
               Elem (i, w) vs -> Elem (i, p) ws -> labelOf w = Just lab -> Elem (MkArc p t lab) (varArcs t ws vs)
varArcsHas Here wp eq =
  elemAppendLeft (rewrite eq in elemMap (\q => MkArc q t lab) (writersOfHas wp))
varArcsHas {vs = (j, v) :: rest} (There el) wp eq =
  elemAppendRight (arcsInto t (labelOf v) (writersOf j ws)) (varArcsHas el wp eq)

0 heldArcsHas : {t : Fin n} -> {ps : Address -> List (Fin n)} -> {hs : List (Address, Weight)} ->
                Elem (j, w) hs -> Elem p (ps j) -> labelOf w = Just lab -> Elem (MkArc p t lab) (heldArcs t ps hs)
heldArcsHas Here inJ eq = elemAppendLeft (rewrite eq in elemMap (\q => MkArc q t lab) inJ)
heldArcsHas {hs = (j', v) :: rest} (There el) inJ eq = elemAppendRight (arcsInto t (labelOf v) (ps j')) (heldArcsHas el inJ eq)

0 fieldArcsHas : {t : Fin n} -> {fps : Address -> Nat -> List (Fin n)} -> {fs : List ((Address, Nat), Weight)} ->
                 Elem ((j, k), w) fs -> Elem p (fps j k) -> labelOf w = Just lab -> Elem (MkArc p t lab) (fieldArcs t fps fs)
fieldArcsHas Here inF eq = elemAppendLeft (rewrite eq in elemMap (\q => MkArc q t lab) inF)
fieldArcsHas {fs = ((j', k'), v) :: rest} (There el) inF eq =
  elemAppendRight (arcsInto t (labelOf v) (fps j' k')) (fieldArcsHas el inF eq)

0 aboveAll : (b : Nat) -> (ks : List Nat) -> Elem k ks -> LTE k (topOf b ks)
aboveAll b (j :: js) Here = maximumLeftUpperBound j (topOf b js)
aboveAll b (j :: js) (There el) = transitive (aboveAll b js el) (maximumRightUpperBound j (topOf b js))

0 bothTrue : (a, b : Bool) -> (a && b) = True -> (a = True, b = True)
bothTrue True True _ = (Refl, Refl)
bothTrue True False eq = absurd eq
bothTrue False _ eq = absurd eq

------------------------------------------------------------------------------
-- Templates
------------------------------------------------------------------------------

mutual
  -- A template whose every instance writes no higher than itself holds no
  -- marker, field or held dictionary, and no family applied.
  0 selfBoundedIs : (t : Template) -> selfBounded t = True -> Unmarked t
  selfBoundedIs (Head a ts) eq = UnmarkedHead (allSelfBoundedAre ts eq)
  selfBoundedIs (Opaque a ts) eq = UnmarkedOpaque (allSelfBoundedAre ts eq)
  selfBoundedIs (Choice c ts) eq = UnmarkedChoice (allSelfBoundedAre ts eq)
  selfBoundedIs (Leaf _) _ = UnmarkedLeaf
  selfBoundedIs (Token _) _ = UnmarkedToken
  selfBoundedIs (Formal _ _) _ = UnmarkedFormal
  selfBoundedIs (Var _ _) eq = absurd eq
  selfBoundedIs (Applied _ _ _) eq = absurd eq
  selfBoundedIs (Computing _ _ _) eq = absurd eq
  selfBoundedIs (Field _ _) eq = absurd eq
  selfBoundedIs (Held _ _) eq = absurd eq

  0 allSelfBoundedAre : (ts : List Template) -> allSelfBounded ts = True -> AllUnmarked ts
  allSelfBoundedAre [] _ = []
  allSelfBoundedAre (t :: ts) eq = case bothTrue (selfBounded t) (allSelfBounded ts) eq of
    (here, rest) => selfBoundedIs t here :: allSelfBoundedAre ts rest

mutual
  -- What a recursion computes from its markers is Stuck, every one.
  0 stuckOnly : (t : Template) -> Elem (i, w) (stuck t) -> w = Stuck
  stuckOnly (Var _ _) Here = Refl
  stuckOnly (Var _ _) (There e) = absurd e
  stuckOnly (Field _ _) el = absurd el
  stuckOnly (Head _ ts) el = stuckOnlyIn ts el
  stuckOnly (Opaque _ ts) el = stuckOnlyIn ts el
  stuckOnly (Choice _ ts) el = stuckOnlyIn ts el
  stuckOnly (Applied _ _ ts) Here = Refl
  stuckOnly (Applied _ _ ts) (There el) = stuckOnlyIn ts el
  stuckOnly (Computing _ _ ts) Here = Refl
  stuckOnly (Computing _ _ ts) (There el) = stuckOnlyIn ts el
  stuckOnly (Leaf _) el = absurd el
  stuckOnly (Token _) el = absurd el
  stuckOnly (Held _ _) el = absurd el
  stuckOnly (Formal _ _) el = absurd el

  0 stuckOnlyIn : (ts : List Template) -> Elem (i, w) (stuckIn ts) -> w = Stuck
  stuckOnlyIn [] el = absurd el
  stuckOnlyIn (t :: ts) el = case appendElem (stuck t) el of
    Left here => stuckOnly t here
    Right rest => stuckOnlyIn ts rest

------------------------------------------------------------------------------
-- Weights
------------------------------------------------------------------------------

0 overStuck : Dominates w Stuck -> w = Stuck
overStuck OverAll = Refl

0 headOver : {d : Nat} -> Dominates w (Finite (S d) 0) -> Dominates (plus w (Finite 1 0)) (Finite (S (S d)) 0)
headOver dom = overAs (cong S (plusCommutative d 1)) Refl (plusOver dom (dominatesSelf (Finite 1 0)))

-- A field's arc, a level above a held dictionary's arguments.
0 fieldOver : {d : Nat} -> Dominates w (Finite (S d) 0) -> Dominates (plus w (Finite 0 1)) (Finite d 0)
fieldOver dom = overPred (overAs (plusZeroRightNeutral (S d)) Refl (plusOver dom (dominatesSelf (Finite 0 1))))

------------------------------------------------------------------------------
-- What the graph holds of a site
------------------------------------------------------------------------------

-- Parameter i reaches the site's target from each position the writer
-- reads it at, with arcs as heavy as w.
0 ArcsAt : (g : Graph) -> Site g.size -> Nat -> Weight -> Type
ArcsAt g s i w = (p : Fin g.size) -> Elem (i, p) s.writers -> (lab : Label) -> labelOf w = Just lab ->
                 Elem (MkArc p s.target lab) g.arcs

-- Parameter i is drawn from at least as heavily as w0 says.
0 DrawnOver : (g : Graph) -> Site g.size -> Nat -> Weight -> Type
DrawnOver g s i w0 = (w : Weight ** (Dominates w w0, ArcsAt g s i w))

0 drawnCarries : {g : Graph} -> {s : Site g.size} -> {pot : Vect g.size Nat} -> Feasible g pot ->
                 DrawnOver g s i (Finite e d) -> Elem (i, p) s.writers -> Carries g p d e s.target
drawnCarries fe (w ** (dom, arcs)) wa = case dom of
  OverAll => void (measuredOnly fe (arcs _ wa Unmeasured Refl))
  Over {g = gain} {l = loss} le => MkCarries (arcs _ wa (Measured gain loss) Refl) le

0 stuckRefuted : {g : Graph} -> {s : Site g.size} -> {pot : Vect g.size Nat} -> Feasible g pot ->
                 DrawnOver g s i Stuck -> Elem (i, p) s.writers -> Void
stuckRefuted fe (w ** (dom, arcs)) wa = case overStuck dom of
  Refl => measuredOnly fe (arcs _ wa Unmeasured Refl)

-- An arc from what a held dictionary, an applied family or a field can
-- be, as heavy as the part sits deep less the depth of what it carries.
0 rootCarries : {g : Graph} -> {pot : Vect g.size Nat} -> Feasible g pot -> Dominates w (Finite e 0) ->
                ((lab : Label) -> labelOf w = Just lab -> Elem (MkArc p t lab) g.arcs) -> Carries g p 0 e t
rootCarries fe OverAll arc = void (measuredOnly fe (arc Unmeasured Refl))
rootCarries fe (Over {g = gain} {l = loss} le) arc = MkCarries (arc (Measured gain loss) Refl) le

-- An applied family's own marker, by whether its arguments are closed.
0 appliedCarries : {g : Graph} -> {s : Site g.size} -> {pot : Vect g.size Nat} -> Feasible g pot ->
                   (e, d : Nat) -> (ts : List Template) -> (closed : Bool) -> allSelfBounded ts = closed ->
                   DrawnOver g s j (if closed then Finite (e + tallest ts) d else Stuck) ->
                   Elem (j, p) s.writers ->
                   (Carries g p d (e + tallest ts) s.target, AllUnmarked ts)
appliedCarries fe e d ts True sb drawn wa = (drawnCarries fe drawn wa, allSelfBoundedAre ts sb)
appliedCarries fe e d ts False sb drawn wa = void (stuckRefuted fe drawn wa)

-- What a site's carried parts draw, as the graph holds it.
record Drawing (g : Graph) (m : Model g) (s : Site g.size) (whole : Carried) where
  constructor MkDrawing
  0 projections : (a : Arc g.size) -> Elem a (heldArcs s.target m.positionsOf whole.held) -> Elem a g.arcs
  0 fielded : (a : Arc g.size) -> Elem a (fieldArcs s.target m.fieldPositions whole.fields) -> Elem a g.arcs
  0 needed : (k : Nat) -> Elem k whole.needs -> LTE k g.constant

-- What a part carries is among what the whole site carries.
record Part (c : Carried) (whole : Carried) where
  constructor MkPart
  0 partFields : (x : ((Address, Nat), Weight)) -> Elem x c.fields -> Elem x whole.fields
  0 partHeld : (x : (Address, Weight)) -> Elem x c.held -> Elem x whole.held
  0 partNeeds : (k : Nat) -> Elem k c.needs -> Elem k whole.needs

-- A list's first template carries a part of what the list does.
0 firstPart : (rts : Template -> List Address) -> (at : Depth) -> (t : Template) -> (ts : List Template) ->
              Part (carriedAll rts at (t :: ts)) whole -> Part (carriedAt rts at t) whole
firstPart rts at t ts p =
  MkPart (\a, el => p.partFields a (elemAppendLeft el))
         (\a, el => p.partHeld a (elemAppendLeft el))
         (\k, el => p.partNeeds k (elemAppendLeft el))

-- And the rest of the list.
0 restPart : (rts : Template -> List Address) -> (at : Depth) -> (t : Template) -> (ts : List Template) ->
             Part (carriedAll rts at (t :: ts)) whole -> Part (carriedAll rts at ts) whole
restPart rts at t ts p =
  MkPart (\a, el => p.partFields a (elemAppendRight (carriedAt rts at t).fields el))
         (\a, el => p.partHeld a (elemAppendRight (carriedAt rts at t).held el))
         (\k, el => p.partNeeds k (elemAppendRight (carriedAt rts at t).needs el))

-- The arcs from what a held dictionary or an applied family can be.
0 rootsCarried : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> Feasible g pot ->
                 {s : Site g.size} -> {whole : Carried} -> Drawing g m s whole ->
                 (at : Depth) -> Dominates at.arcWeight (Finite (S at.depth) 0) -> (t : Template) ->
                 ((x : (Address, Weight)) -> Elem x (heldRoots s.roots at t) -> Elem x whole.held) ->
                 (j : Address) -> Elem j (s.roots t) -> (p' : Fin g.size) -> Elem p' (m.positionsOf j) ->
                 Carries g p' 0 (S at.depth) s.target
rootsCarried fe dr at aw t held j el p' inJ =
  rootCarries fe aw (\lab, eq => dr.projections _ (heldArcsHas (held _ (elemMap (\x => (x, at.arcWeight)) el)) inJ eq))

-- The arcs from a field's position of each implementation its record can
-- be.
0 fieldsCarried : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> Feasible g pot ->
                  {s : Site g.size} -> {whole : Carried} -> Drawing g m s whole ->
                  (at : Depth) -> Dominates at.arcWeight (Finite (S at.depth) 0) -> (k : Nat) -> (rec : Template) ->
                  ((x : ((Address, Nat), Weight)) -> Elem x (fieldRoots s.roots at k rec) -> Elem x whole.fields) ->
                  (j : Address) -> Elem j (s.roots rec) -> (p : Fin g.size) -> Elem p (m.fieldPositions j k) ->
                  Carries g p 0 at.depth s.target
fieldsCarried fe dr at aw k rec fields j el p inField =
  rootCarries fe (fieldOver aw)
    (\lab, eq => dr.fielded _ (fieldArcsHas (fields _ (elemMap (\x => ((x, k), fieldWeight at)) el)) inField eq))

------------------------------------------------------------------------------
-- Covering a site
------------------------------------------------------------------------------

-- How a part's markers are read: as deep as they occur, or under a
-- computation, where every one is Stuck.
data Reading = AtDepth | UnderComputation

-- Every occurrence a part answers for is drawn from at least as heavily as
-- it is read: at its depth, or Stuck under a computation.
0 Answered : (g : Graph) -> Site g.size -> Reading -> (e : Nat) -> Template -> Type
Answered g s AtDepth e t = (i : Nat) -> (w : Weight) -> Elem (i, w) (occurrences e t) -> DrawnOver g s i w
Answered g s UnderComputation e t = (i : Nat) -> (w : Weight) -> Elem (i, w) (stuck t) -> DrawnOver g s i Stuck

0 AnsweredIn : (g : Graph) -> Site g.size -> Reading -> (e : Nat) -> List Template -> Type
AnsweredIn g s AtDepth e ts = (i : Nat) -> (w : Weight) -> Elem (i, w) (occurrencesIn e ts) -> DrawnOver g s i w
AnsweredIn g s UnderComputation e ts = (i : Nat) -> (w : Weight) -> Elem (i, w) (stuckIn ts) -> DrawnOver g s i Stuck

0 headAnswered : (r : Reading) -> Answered g s r e (Head a ts) -> AnsweredIn g s r (S e) ts
headAnswered AtDepth ans = ans
headAnswered UnderComputation ans = ans

0 choiceAnswered : (r : Reading) -> Answered g s r e (Choice c ts) -> AnsweredIn g s r e ts
choiceAnswered AtDepth ans = ans
choiceAnswered UnderComputation ans = ans

0 opaqueAnswered : (r : Reading) -> Answered g s r e (Opaque a ts) -> AnsweredIn g s UnderComputation e' ts
opaqueAnswered AtDepth ans = \i, w, el => case stuckOnlyIn ts el of Refl => ans i Stuck el
opaqueAnswered UnderComputation ans = ans

0 firstAnswered : (r : Reading) -> AnsweredIn g s r e (t :: ts) -> Answered g s r e t
firstAnswered AtDepth ans = \i, w, el => ans i w (elemAppendLeft el)
firstAnswered UnderComputation ans = \i, w, el => ans i w (elemAppendLeft el)

0 restAnswered : (r : Reading) -> AnsweredIn g s r e (t :: ts) -> AnsweredIn g s r e ts
restAnswered {t} {e} AtDepth ans = \i, w, el => ans i w (elemAppendRight (occurrences e t) el)
restAnswered {t} UnderComputation ans = \i, w, el => ans i w (elemAppendRight (stuck t) el)

mutual
  -- The graph covers a part of a site's template read at a depth, by
  -- induction on the part: each marker by its arcs or, where they are
  -- Stuck, by the feasible potential none satisfies.
  0 coverAt : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> Feasible g pot ->
              {s : Site g.size} -> {whole : Carried} -> Drawing g m s whole ->
              (r : Reading) -> (at : Depth) -> Dominates at.arcWeight (Finite (S at.depth) 0) ->
              (t : Template) -> Answered g s r at.depth t -> Part (carriedAt s.roots at t) whole ->
              CoveredAt m s at.depth t
  coverAt fe dr AtDepth at aw (Var j d) ans part =
    CVar (\p, wa => drawnCarries fe (ans j (Finite at.depth d) Here) wa)
  coverAt fe dr UnderComputation at aw (Var j d) ans part =
    CVar (\p, wa => void (stuckRefuted fe (ans j Stuck Here) wa))
  coverAt fe dr r at aw (Head a ts) ans part =
    CHead (coverAll fe dr r (underHead at) (headOver aw) ts (headAnswered r ans) part)
  coverAt fe dr r at aw (Opaque a ts) ans part =
    COpaque (coverAll fe dr UnderComputation (underComputation at) OverAll ts (opaqueAnswered r ans) part)
  coverAt fe dr r at aw (Choice c ls) ans part =
    CChoice (coverAll fe dr r at aw ls (choiceAnswered r ans) part)
  coverAt fe dr r at aw (Leaf h) ans part = CLeaf
  coverAt fe dr r at aw (Token h) ans part = CToken
  coverAt fe dr r at aw (Formal j k) ans part = CFormal
  coverAt fe dr AtDepth at aw (Applied j d ts) ans part =
    CApplied (\p, wa => appliedCarries fe at.depth d ts (allSelfBounded ts) Refl (ans j (appliedWeight at.depth d ts) Here) wa)
             (rootsCarried fe dr at aw (Applied j d ts) (\x, el => part.partHeld x (elemAppendLeft el)))
  coverAt fe dr UnderComputation at aw (Applied j d ts) ans part =
    CApplied (\p, wa => void (stuckRefuted fe (ans j Stuck Here) wa))
             (rootsCarried fe dr at aw (Applied j d ts) (\x, el => part.partHeld x (elemAppendLeft el)))
  coverAt fe dr AtDepth at aw (Computing j d ts) ans part =
    CComputing (\p, wa => stuckRefuted fe (ans j Stuck Here) wa)
  coverAt fe dr UnderComputation at aw (Computing j d ts) ans part =
    CComputing (\p, wa => stuckRefuted fe (ans j Stuck Here) wa)
  coverAt fe dr r at aw (Held c q) ans part =
    CHeld (rootsCarried fe dr at aw (Held c q) (\x, el => part.partHeld x el))
          (dr.needed _ (part.partNeeds _ Here))
  coverAt fe dr r at aw (Field k rec) ans part =
    CField (fieldsCarried fe dr at aw k rec (\x, el => part.partFields x el))

  0 coverAll : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> Feasible g pot ->
               {s : Site g.size} -> {whole : Carried} -> Drawing g m s whole ->
               (r : Reading) -> (at : Depth) -> Dominates at.arcWeight (Finite (S at.depth) 0) ->
               (ts : List Template) -> AnsweredIn g s r at.depth ts -> Part (carriedAll s.roots at ts) whole ->
               AllCovered m s at.depth ts
  coverAll fe dr r at aw [] ans part = []
  coverAll {s} fe dr r at aw (t :: ts) ans part =
    coverAt fe dr r at aw t (firstAnswered r ans) (firstPart s.roots at t ts part) ::
    coverAll fe dr r at aw ts (restAnswered r ans) (restPart s.roots at t ts part)

-- The graph covers a site whose arcs and needs it holds.
0 covering : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> Feasible g pot -> (s : Site g.size) ->
             ((a : Arc g.size) -> Elem a (ownArcs s) -> Elem a g.arcs) ->
             ((a : Arc g.size) -> Elem a (projectedArcs m.positionsOf m.fieldPositions s) -> Elem a g.arcs) ->
             ((k : Nat) -> Elem k (needsOf s.roots s.template) -> LTE k g.constant) ->
             CoveredAt m s 0 s.template
covering {m} fe s own projected need =
  coverAt {whole = carriedAt s.roots atTop s.template} fe
          (MkDrawing (\a, el => projected a (elemAppendLeft el))
                     (\a, el => projected a (elemAppendRight (heldArcs s.target m.positionsOf (carriedAt s.roots atTop s.template).held) el))
                     (\k, el => need k (There el)))
          AtDepth atTop (dominatesSelf (Finite 1 0)) s.template
          (\i, w, el => case weightsCover s.template el of
             (v ** (inW, dom)) => (v ** (dom, \p, wa, lab, leq => own _ (varArcsHas inW wa leq))))
          (MkPart (\x, el => el) (\x, el => el) (\k, el => el))

||| A graph drawn from a model's sites describes the model under any
||| feasible potential: every site lands at an uncapped position, K stands
||| above its template, and the graph covers every part of it, each Stuck
||| arc being one no feasible potential satisfies.
export
0 describes : {n : Nat} -> (ps : Address -> List (Fin n)) -> (fps : Address -> Nat -> List (Fin n)) ->
              (positionOf : Fin n -> Maybe (Head, Nat)) -> (beyond : Nat) -> (caps : Vect n (Maybe Nat)) ->
              (ss : List (Site n, tag)) -> All (\x => index (fst x).target caps = Nothing) ss ->
              {pot : Vect n Nat} -> Feasible (graphOf ps fps beyond caps ss) pot ->
              Describes (modelOf ps fps positionOf beyond caps ss)
describes ps fps positionOf beyond caps ss uncapped fe = sitesCovered ss uncapped (\y, el => el)
  where
    -- What a site of the graph needs, K stands above.
    0 needed : (s : Site n) -> (x : tag) -> Elem (s, x) ss -> (k : Nat) -> Elem k (needsOf s.roots s.template) ->
               LTE k (topOf beyond (allOf siteNeeds ss))
    needed s x here k el = aboveAll beyond (allOf siteNeeds ss) (allOfHas siteNeeds here el)

    0 sitesCovered : (rest : List (Site n, tag)) -> All (\x => index (fst x).target caps = Nothing) rest ->
                     ((y : (Site n, tag)) -> Elem y rest -> Elem y ss) ->
                     All (Covers (graphOf ps fps beyond caps ss) (modelOf ps fps positionOf beyond caps ss)) (map fst rest)
    sitesCovered [] [] _ = []
    sitesCovered ((s, x) :: rest) (u :: us) sub =
      MkCovers u (needed s x (sub (s, x) Here) (height s.template) Here)
               (covering fe s
                  (\a, el => elemMap fst (elemAppendLeft (allOfHas ownTagged (sub (s, x) Here) (elemMap (\a' => (a', x)) el))))
                  (\a, el => elemMap fst (elemAppendRight (allOf ownTagged ss)
                                           (allOfHas (projectedTagged ps fps) (sub (s, x) Here) (elemMap (\a' => (a', x)) el))))
                  (needed s x (sub (s, x) Here)))
      :: sitesCovered rest us (\y, el => sub y (There el))
