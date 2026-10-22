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
||| parameter's occurrences carry (`weights`); a field of a dictionary draws
||| its record's parameters as deep as the record's field templates hold
||| its arguments (`fieldPlaced`); and a held dictionary, or an applied
||| family that gives one, an arc from every position of every
||| implementation it can be (`heldRoots`). A part under a computation draws
||| Stuck arcs, which no feasible potential satisfies (`measuredOnly`), so
||| it needs no other covering. The order of the arcs is the order the
||| check reads them in: each site's own, then each site's from held
||| dictionaries.
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
||| dictionary's implementation into the site weighs there, and how deep
||| the bound measures the part, `depth` levels down less `lift` (a field's
||| record sits above the field by as much as the field holds its
||| arguments deep).
public export
record Depth where
  constructor MkDepth
  arcWeight : Weight
  depth : Nat
  lift : Nat

||| A site's template, where it lands.
public export
atTop : Depth
atTop = MkDepth (Finite 1 0) 0 0

||| A head's child.
public export
underHead : Depth -> Depth
underHead at = MkDepth (plus at.arcWeight (Finite 1 0)) (S at.depth) at.lift

||| A child of a recursion or of an applied or computing family: a level
||| down, and what an arc carries there unbounded.
public export
underComputation : Depth -> Depth
underComputation at = MkDepth Stuck (S at.depth) at.lift

||| How high K stands for a part h high to stay within it here.
public export
above : Depth -> Nat -> Nat
above at h = minus (h + at.depth) at.lift

||| Where a field's record sits, from where the field is read: a level below
||| for the record's head, and above that by as much as the field templates
||| of its roots hold its arguments deep, their reach; what an arc from a
||| held dictionary of the record weighs there, by `deep`. A reach of
||| nowhere needs nothing of the record: it is placed as if held at its own
||| depth.
public export
recordAt : Depth -> (deep : Weight) -> Reach -> Depth
recordAt at deep Nowhere = MkDepth (plus at.arcWeight (plus deep (Finite 0 1))) (S at.depth) (at.lift + 2)
recordAt at deep (Deepest dg dl) = MkDepth (plus at.arcWeight (plus deep (Finite 0 1))) (at.depth + S dg) (at.lift + (dl + 2))

||| A reach as the weight of an arc: nowhere is no arc.
public export
reachWeight : Reach -> Weight
reachWeight Nowhere = Absent
reachWeight (Deepest g l) = Finite g l

------------------------------------------------------------------------------
-- What a template's fields and held dictionaries carry
------------------------------------------------------------------------------

||| What a template's fields carry once their records are built, and its
||| held dictionaries: each parameter of the writer's a record holds, with
||| the weight of its arc; each implementation a held dictionary or an
||| applied family can be, with the weight of the arcs from its positions;
||| and what K must stand above.
public export
record Carried where
  constructor MkCarried
  arcs : List (Nat, Weight)
  held : List (Address, Weight)
  needs : List Nat

public export
noneCarried : Carried
noneCarried = MkCarried [] [] []

public export
alsoCarried : Carried -> Carried -> Carried
alsoCarried x y = MkCarried (x.arcs ++ y.arcs) (x.held ++ y.held) (x.needs ++ y.needs)

||| The values a function gives, those it gives one of.
public export
keepJust : (a -> Maybe b) -> List a -> List b
keepJust f [] = []
keepJust f (x :: xs) = case f x of
  Nothing => keepJust f xs
  Just y => y :: keepJust f xs

||| The field templates of field k of each implementation a record can be.
public export
fieldTemplates : (Address -> Nat -> Maybe Template) -> (Template -> List Address) -> Nat -> Template -> List Template
fieldTemplates fs rts k rec = keepJust (\j => fs j k) (rts rec)

||| How much a field's record's arcs weigh beside where the record sits:
||| the reach the bound reads, and what the field templates hold besides
||| (an applied family, a recursion), which no reach of an argument takes
||| in.
public export
deepOf : List Template -> Weight
deepOf fts = join (reachWeight (reachAll 0 fts)) (foldr join Absent (map holding fts))

||| A record's parameter, its arc weighed past where the record sits.
public export
prefixed : Weight -> (Nat, Weight) -> (Nat, Weight)
prefixed pre (i, w) = (i, plus pre w)

||| Each implementation a template can be, with the weight of the arcs from
||| its positions here.
public export
heldRoots : (Template -> List Address) -> Depth -> Template -> List (Address, Weight)
heldRoots rts at t = map (\j => (j, at.arcWeight)) (rts t)

mutual
  ||| Every field's and held dictionary's value in a template read here: a
  ||| held dictionary is a head over its implementation's arguments, a
  ||| level down, and so is what an applied family gives. A field of a
  ||| field is reached through the outer one's record.
  public export
  carriedAt : (Address -> Nat -> Maybe Template) -> (Template -> List Address) -> Depth -> Template -> Carried
  carriedAt fs rts at (Field k rec) = fieldValue fs rts at k rec
  carriedAt fs rts at t@(Held _ _) = MkCarried [] (heldRoots rts at t) [above at 1]
  carriedAt fs rts at t@(Applied _ _ ts) =
    alsoCarried (MkCarried [] (heldRoots rts at t) []) (carriedAll fs rts (underComputation at) ts)
  carriedAt fs rts at (Head _ ts) = carriedAll fs rts (underHead at) ts
  carriedAt fs rts at (Opaque _ ts) = carriedAll fs rts (underComputation at) ts
  carriedAt fs rts at (Computing _ _ ts) = carriedAll fs rts (underComputation at) ts
  carriedAt fs rts at (Choice _ ts) = carriedAll fs rts at ts
  carriedAt fs rts at (Var _ _) = noneCarried
  carriedAt fs rts at (Leaf _) = noneCarried
  carriedAt fs rts at (Token _) = noneCarried
  carriedAt fs rts at (Formal _ _) = noneCarried

  public export
  carriedAll : (Address -> Nat -> Maybe Template) -> (Template -> List Address) -> Depth -> List Template -> Carried
  carriedAll fs rts at [] = noneCarried
  carriedAll fs rts at (t :: ts) = alsoCarried (carriedAt fs rts at t) (carriedAll fs rts at ts)

  ||| A field's value, field k of the record `rec`: the field template of
  ||| each implementation `rec` can be, over `rec`'s arguments.
  public export
  fieldValue : (Address -> Nat -> Maybe Template) -> (Template -> List Address) -> Depth -> (k : Nat) -> Template -> Carried
  fieldValue fs rts at k rec =
    let fts = fieldTemplates fs rts k rec in fieldPlaced fs rts at rec fts (reachAll 0 fts) (deepOf fts)

  ||| A field's value with its record placed as deep as the field templates
  ||| hold its arguments: each parameter of the record's carried that much
  ||| deeper than the record writes it, its fields and held dictionaries
  ||| likewise, and K above the record there and above the field templates'
  ||| closed parts where the field is read.
  public export
  fieldPlaced : (Address -> Nat -> Maybe Template) -> (Template -> List Address) -> Depth -> (rec : Template) ->
                (fts : List Template) -> Reach -> (deep : Weight) -> Carried
  fieldPlaced fs rts at rec fts reach deep =
    alsoCarried (MkCarried (map (prefixed (plus at.arcWeight (plus deep (Finite 0 2)))) (weights rec)) []
                           [above (recordAt at deep reach) (height rec)])
                (alsoCarried (MkCarried [] [] (map (\t => above at (height t)) fts))
                             (carriedAt fs rts (recordAt at deep reach) rec))

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

||| A site's own arcs: its parameters', then its records'.
public export
ownArcs : (Address -> Nat -> Maybe Template) -> Site n -> List (Arc n)
ownArcs fs s =
  varArcs s.target s.writers (weights s.template) ++
  varArcs s.target s.writers (carriedAt fs s.roots atTop s.template).arcs

||| A site's arcs from what its held dictionaries can be.
public export
projectedArcs : (Address -> Nat -> Maybe Template) -> (Address -> List (Fin n)) -> Site n -> List (Arc n)
projectedArcs fs ps s = heldArcs s.target ps (carriedAt fs s.roots atTop s.template).held

||| What K stands above for a template: its own height, and what its
||| fields and held dictionaries need.
public export
needsOf : (Address -> Nat -> Maybe Template) -> (Template -> List Address) -> Template -> List Nat
needsOf fs rts t = height t :: (carriedAt fs rts atTop t).needs

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
ownTagged : (Address -> Nat -> Maybe Template) -> (Site n, tag) -> List (Arc n, tag)
ownTagged fs (s, x) = map (\a => (a, x)) (ownArcs fs s)

public export
projectedTagged : (Address -> Nat -> Maybe Template) -> (Address -> List (Fin n)) -> (Site n, tag) -> List (Arc n, tag)
projectedTagged fs ps (s, x) = map (\a => (a, x)) (projectedArcs fs ps s)

public export
siteNeeds : (Address -> Nat -> Maybe Template) -> (Site n, tag) -> List Nat
siteNeeds fs (s, x) = needsOf fs s.roots s.template

||| Every site's arcs, each with what tags it: each site's own, then each
||| site's from held dictionaries.
public export
drawn : (Address -> Nat -> Maybe Template) -> (Address -> List (Fin n)) -> List (Site n, tag) -> List (Arc n, tag)
drawn fs ps ss = allOf (ownTagged fs) ss ++ allOf (projectedTagged fs ps) ss

||| The graph drawn from some sites over n positions with their caps: K
||| above what every site needs and above `beyond`, what the templates
||| written at capped positions need, which no site of the model holds.
public export
graphOf : {n : Nat} -> (Address -> Nat -> Maybe Template) -> (Address -> List (Fin n)) -> (beyond : Nat) ->
          Vect n (Maybe Nat) -> List (Site n, tag) -> Graph
graphOf fs ps beyond caps ss = MkGraph n (map fst (drawn fs ps ss)) (topOf beyond (allOf (siteNeeds fs) ss)) caps

||| The model the graph is drawn from.
public export
modelOf : {n : Nat} -> (fs : Address -> Nat -> Maybe Template) -> (ps : Address -> List (Fin n)) ->
          (Fin n -> (Address, Nat)) -> (beyond : Nat) -> (caps : Vect n (Maybe Nat)) -> (ss : List (Site n, tag)) ->
          Model (graphOf fs ps beyond caps ss)
modelOf fs ps positionOf beyond caps ss = MkModel (map fst ss) fs positionOf ps

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

0 keepJustHas : {f : a -> Maybe b} -> {xs : List a} -> Elem x xs -> f x = Just y -> Elem y (keepJust f xs)
keepJustHas Here eq = rewrite eq in Here
keepJustHas {xs = z :: rest} (There el) eq with (f z)
  _ | Nothing = keepJustHas el eq
  _ | Just w = There (keepJustHas el eq)

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

0 aboveAll : (b : Nat) -> (ks : List Nat) -> Elem k ks -> LTE k (topOf b ks)
aboveAll b (j :: js) Here = maximumLeftUpperBound j (topOf b js)
aboveAll b (j :: js) (There el) = transitive (aboveAll b js el) (maximumRightUpperBound j (topOf b js))

-- K above a need written as a difference stands above what it differs
-- from, with the difference's lower side added.
0 minusWithin : (x, l, k : Nat) -> LTE (minus x l) k -> LTE x (k + l)
minusWithin Z l k _ = LTEZero
minusWithin (S x) Z k le = rewrite plusZeroRightNeutral k in le
minusWithin (S x) (S l) k le = rewrite sym (plusSuccRightSucc k l) in LTESucc (minusWithin x l k le)

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
  stuckOnly (Field _ s) el = stuckOnly s el
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

0 plusStuck : Dominates pre (Finite a b) -> plus pre Stuck = Stuck
plusStuck OverAll = Refl
plusStuck (Over _) = Refl

||| A weight read at a depth less a lift: a Finite one that much deeper,
||| any other as it is.
public export
shiftBy : Nat -> Nat -> Weight -> Weight
shiftBy e0 l (Finite a b) = Finite (e0 + a) (b + l)
shiftBy e0 l w = w

-- A parameter's weight read past a prefix that stands for where its
-- context sits.
0 prefixedOver : {e0, l : Nat} -> Dominates pre (Finite e0 l) -> Dominates w w0 -> Dominates (plus pre w) (shiftBy e0 l w0)
prefixedOver pd OverAll = rewrite plusStuck pd in OverAll
prefixedOver pd OverAbsent = OverAbsent
prefixedOver pd (Over {e} {d} le) = overAs Refl (plusCommutative l d) (plusOver pd (Over le))

-- A site's own parameters, read where it lands.
0 topOver : Dominates w w0 -> Dominates w (shiftBy 0 0 w0)
topOver OverAll = OverAll
topOver OverAbsent = OverAbsent
topOver (Over {e} {d} le) = overAs Refl (sym (plusZeroRightNeutral d)) (Over le)

0 headOver : {d, l : Nat} -> Dominates w (Finite (S d) l) -> Dominates (plus w (Finite 1 0)) (Finite (S (S d)) l)
headOver dom = overAs (cong S (plusCommutative d 1)) (plusZeroRightNeutral l) (plusOver dom (dominatesSelf (Finite 1 0)))

-- One more than a depth and a reach, either way round.
0 depthPast : (d, dg : Nat) -> S d + (dg + 0) = d + S dg
depthPast d dg = trans (cong (\x => S (d + x)) (plusZeroRightNeutral dg)) (plusSuccRightSucc d dg)

0 piOver : {d, l, dg, dl : Nat} -> Dominates aw (Finite (S d) l) -> Dominates deep (Finite dg dl) ->
           Dominates (plus aw (plus deep (Finite 0 2))) (Finite (d + S dg) (l + (dl + 2)))
piOver awd dd = overAs (depthPast d dg) Refl (plusOver awd (plusOver dd (dominatesSelf (Finite 0 2))))

0 recordOver : {d, l, dg, dl : Nat} -> Dominates aw (Finite (S d) l) -> Dominates deep (Finite dg dl) ->
               Dominates (plus aw (plus deep (Finite 0 1))) (Finite (S (d + S dg)) (l + (dl + 2)))
recordOver awd dd =
  overAs (cong S (depthPast d dg)) (trans (plusSuccRightSucc l (dl + 1)) (cong (l +) (plusSuccRightSucc dl 1)))
         (overSucc (plusOver awd (plusOver dd (dominatesSelf (Finite 0 1)))))

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
                 DrawnOver g s i (Finite e (d + l)) -> Elem (i, p) s.writers -> Carries g p d (e, l) s.target
drawnCarries fe (w ** (dom, arcs)) wa = case dom of
  OverAll => void (measuredOnly fe (arcs _ wa Unmeasured Refl))
  Over {g = gain} {l = loss} le => MkCarries (arcs _ wa (Measured gain loss) Refl) le

0 stuckRefuted : {g : Graph} -> {s : Site g.size} -> {pot : Vect g.size Nat} -> Feasible g pot ->
                 DrawnOver g s i Stuck -> Elem (i, p) s.writers -> Void
stuckRefuted fe (w ** (dom, arcs)) wa = case overStuck dom of
  Refl => measuredOnly fe (arcs _ wa Unmeasured Refl)

0 heldCarries : {g : Graph} -> {pot : Vect g.size Nat} -> Feasible g pot -> Dominates w (Finite (S e) l) ->
                ((lab : Label) -> labelOf w = Just lab -> Elem (MkArc p t lab) g.arcs) -> Carries g p 0 (S e, l) t
heldCarries fe OverAll arc = void (measuredOnly fe (arc Unmeasured Refl))
heldCarries fe (Over {g = gain} {l = loss} le) arc = MkCarries (arc (Measured gain loss) Refl) le

-- An applied family's own marker, by whether its arguments are closed.
0 appliedCarries : {g : Graph} -> {s : Site g.size} -> {pot : Vect g.size Nat} -> Feasible g pot ->
                   (e0, e, d : Nat) -> (ts : List Template) -> (closed : Bool) -> allSelfBounded ts = closed ->
                   DrawnOver g s j (shiftBy e0 l (if closed then Finite (e + tallest ts) d else Stuck)) ->
                   Elem (j, p) s.writers ->
                   (Carries g p d ((e0 + e) + tallest ts, l) s.target, AllUnmarked ts)
appliedCarries fe e0 e d ts True sb drawn wa =
  (rewrite sym (plusAssociative e0 e (tallest ts)) in drawnCarries fe drawn wa, allSelfBoundedAre ts sb)
appliedCarries fe e0 e d ts False sb drawn wa = void (stuckRefuted fe drawn wa)

-- What a site's carried parts draw, as the graph holds it.
record Drawing (g : Graph) (m : Model g) (s : Site g.size) (whole : Carried) where
  constructor MkDrawing
  0 records : (a : Arc g.size) -> Elem a (varArcs s.target s.writers whole.arcs) -> Elem a g.arcs
  0 projections : (a : Arc g.size) -> Elem a (heldArcs s.target m.positionsOf whole.held) -> Elem a g.arcs
  0 needed : (k : Nat) -> Elem k whole.needs -> LTE k g.constant

-- What a part carries is among what the whole site carries.
record Part (c : Carried) (whole : Carried) where
  constructor MkPart
  0 partArcs : (x : (Nat, Weight)) -> Elem x c.arcs -> Elem x whole.arcs
  0 partHeld : (x : (Address, Weight)) -> Elem x c.held -> Elem x whole.held
  0 partNeeds : (k : Nat) -> Elem k c.needs -> Elem k whole.needs

-- A list's first template carries a part of what the list does.
0 firstPart : (fs : Address -> Nat -> Maybe Template) -> (rts : Template -> List Address) -> (at : Depth) ->
              (t : Template) -> (ts : List Template) ->
              Part (carriedAll fs rts at (t :: ts)) whole -> Part (carriedAt fs rts at t) whole
firstPart fs rts at t ts p =
  MkPart (\a, el => p.partArcs a (elemAppendLeft el))
         (\a, el => p.partHeld a (elemAppendLeft el))
         (\k, el => p.partNeeds k (elemAppendLeft el))

-- And the rest of the list.
0 restPart : (fs : Address -> Nat -> Maybe Template) -> (rts : Template -> List Address) -> (at : Depth) ->
             (t : Template) -> (ts : List Template) ->
             Part (carriedAll fs rts at (t :: ts)) whole -> Part (carriedAll fs rts at ts) whole
restPart fs rts at t ts p =
  MkPart (\a, el => p.partArcs a (elemAppendRight (carriedAt fs rts at t).arcs el))
         (\a, el => p.partHeld a (elemAppendRight (carriedAt fs rts at t).held el))
         (\k, el => p.partNeeds k (elemAppendRight (carriedAt fs rts at t).needs el))

-- A field's record, where it is placed, carries a part of what the field
-- does.
0 recordPart : (fs : Address -> Nat -> Maybe Template) -> (rts : Template -> List Address) -> (at : Depth) ->
               (rec : Template) -> (fts : List Template) -> (reach : Reach) -> (deep : Weight) ->
               Part (fieldPlaced fs rts at rec fts reach deep) whole -> Part (carriedAt fs rts (recordAt at deep reach) rec) whole
recordPart fs rts at rec fts reach deep p =
  MkPart (\a, el => p.partArcs a (elemAppendRight (map (prefixed (plus at.arcWeight (plus deep (Finite 0 2)))) (weights rec)) el))
         (\a, el => p.partHeld a el)
         (\k, el => p.partNeeds k (There (elemAppendRight (map (\t => above at (height t)) fts) el)))

-- The arcs from what a held dictionary or an applied family can be.
0 rootsCarried : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> Feasible g pot ->
                 {s : Site g.size} -> {whole : Carried} -> Drawing g m s whole ->
                 (at : Depth) -> Dominates at.arcWeight (Finite (S at.depth) at.lift) -> (t : Template) ->
                 ((x : (Address, Weight)) -> Elem x (heldRoots s.roots at t) -> Elem x whole.held) ->
                 (j : Address) -> Elem j (s.roots t) -> (p' : Fin g.size) -> Elem p' (m.positionsOf j) ->
                 Carries g p' 0 (S at.depth, at.lift) s.target
rootsCarried fe dr at aw t held j el p' inJ =
  heldCarries fe aw (\lab, eq => dr.projections _ (heldArcsHas (held _ (elemMap (\x => (x, at.arcWeight)) el)) inJ eq))

------------------------------------------------------------------------------
-- Covering a site
------------------------------------------------------------------------------

-- How a part's markers are read: as deep as they occur, or under a
-- computation, where every one is Stuck.
data Reading = AtDepth | UnderComputation

-- Every occurrence a part answers for is drawn from at least as heavily as
-- it is read: at its depth less the lift in a context that sits e0 deep,
-- or Stuck under a computation.
0 Answered : (g : Graph) -> Site g.size -> Reading -> (e0, e, l : Nat) -> Template -> Type
Answered g s AtDepth e0 e l t = (i : Nat) -> (w : Weight) -> Elem (i, w) (occurrences e t) -> DrawnOver g s i (shiftBy e0 l w)
Answered g s UnderComputation e0 e l t = (i : Nat) -> (w : Weight) -> Elem (i, w) (stuck t) -> DrawnOver g s i Stuck

0 AnsweredIn : (g : Graph) -> Site g.size -> Reading -> (e0, e, l : Nat) -> List Template -> Type
AnsweredIn g s AtDepth e0 e l ts = (i : Nat) -> (w : Weight) -> Elem (i, w) (occurrencesIn e ts) -> DrawnOver g s i (shiftBy e0 l w)
AnsweredIn g s UnderComputation e0 e l ts = (i : Nat) -> (w : Weight) -> Elem (i, w) (stuckIn ts) -> DrawnOver g s i Stuck

0 headAnswered : (r : Reading) -> Answered g s r e0 e l (Head a ts) -> AnsweredIn g s r e0 (S e) l ts
headAnswered AtDepth ans = ans
headAnswered UnderComputation ans = ans

0 choiceAnswered : (r : Reading) -> Answered g s r e0 e l (Choice c ts) -> AnsweredIn g s r e0 e l ts
choiceAnswered AtDepth ans = ans
choiceAnswered UnderComputation ans = ans

0 opaqueAnswered : (r : Reading) -> Answered g s r e0 e l (Opaque a ts) -> AnsweredIn g s UnderComputation e0' e' l' ts
opaqueAnswered AtDepth ans = \i, w, el => case stuckOnlyIn ts el of Refl => ans i Stuck el
opaqueAnswered UnderComputation ans = ans

0 firstAnswered : (r : Reading) -> AnsweredIn g s r e0 e l (t :: ts) -> Answered g s r e0 e l t
firstAnswered AtDepth ans = \i, w, el => ans i w (elemAppendLeft el)
firstAnswered UnderComputation ans = \i, w, el => ans i w (elemAppendLeft el)

0 restAnswered : (r : Reading) -> AnsweredIn g s r e0 e l (t :: ts) -> AnsweredIn g s r e0 e l ts
restAnswered {t} {e} AtDepth ans = \i, w, el => ans i w (elemAppendRight (occurrences e t) el)
restAnswered {t} UnderComputation ans = \i, w, el => ans i w (elemAppendRight (stuck t) el)

mutual
  -- The graph covers a part of a site's template read at a depth, by
  -- induction on the part: each marker by its arcs or, where they are
  -- Stuck, by the feasible potential none satisfies.
  0 coverAt : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> Feasible g pot ->
              {s : Site g.size} -> {whole : Carried} -> Drawing g m s whole ->
              (r : Reading) -> (e0, e : Nat) -> (at : Depth) -> at.depth = e0 + e ->
              Dominates at.arcWeight (Finite (S at.depth) at.lift) ->
              (t : Template) -> Answered g s r e0 e at.lift t -> Part (carriedAt m.fields s.roots at t) whole ->
              CoveredAt m s (at.depth, at.lift) t
  coverAt fe dr AtDepth e0 e at deq aw (Var j d) ans part =
    rewrite deq in CVar (\p, wa => drawnCarries fe (ans j (Finite e d) Here) wa)
  coverAt fe dr UnderComputation e0 e at deq aw (Var j d) ans part =
    CVar (\p, wa => void (stuckRefuted fe (ans j Stuck Here) wa))
  coverAt fe dr r e0 e at deq aw (Head a ts) ans part =
    CHead (coverAll fe dr r e0 (S e) (underHead at) (trans (cong S deq) (plusSuccRightSucc e0 e)) (headOver aw)
                    ts (headAnswered r ans) part)
  coverAt fe dr r e0 e at deq aw (Opaque a ts) ans part =
    COpaque (coverAll fe dr UnderComputation e0 (S e) (underComputation at) (trans (cong S deq) (plusSuccRightSucc e0 e))
                      OverAll ts (opaqueAnswered r ans) part)
  coverAt fe dr r e0 e at deq aw (Choice c ls) ans part =
    CChoice (coverAll fe dr r e0 e at deq aw ls (choiceAnswered r ans) part)
  coverAt fe dr r e0 e at deq aw (Leaf h) ans part = CLeaf
  coverAt fe dr r e0 e at deq aw (Token h) ans part = CToken
  coverAt fe dr r e0 e at deq aw (Formal j k) ans part = CFormal
  coverAt {s} fe dr AtDepth e0 e at deq aw (Applied j d ts) ans part =
    CApplied (\p, wa => rewrite deq in
                appliedCarries fe e0 e d ts (allSelfBounded ts) Refl (ans j (appliedWeight e d ts) Here) wa)
             (rootsCarried fe dr at aw (Applied j d ts) (\x, el => part.partHeld x (elemAppendLeft el)))
  coverAt {s} fe dr UnderComputation e0 e at deq aw (Applied j d ts) ans part =
    CApplied (\p, wa => void (stuckRefuted fe (ans j Stuck Here) wa))
             (rootsCarried fe dr at aw (Applied j d ts) (\x, el => part.partHeld x (elemAppendLeft el)))
  coverAt fe dr AtDepth e0 e at deq aw (Computing j d ts) ans part =
    CComputing (\p, wa => stuckRefuted fe (ans j Stuck Here) wa)
  coverAt fe dr UnderComputation e0 e at deq aw (Computing j d ts) ans part =
    CComputing (\p, wa => stuckRefuted fe (ans j Stuck Here) wa)
  coverAt fe dr r e0 e at deq aw (Held c q) ans part =
    CHeld (rootsCarried fe dr at aw (Held c q) (\x, el => part.partHeld x el))
          (minusWithin (1 + at.depth) at.lift _ (dr.needed _ (part.partNeeds _ Here)))
  coverAt {m} {s} fe dr r e0 e at deq aw (Field k rec) ans part =
    fieldCovered fe dr r e0 e at deq aw k rec (reachAll 0 (fieldTemplates m.fields s.roots k rec)) Refl ans part

  0 coverAll : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> Feasible g pot ->
               {s : Site g.size} -> {whole : Carried} -> Drawing g m s whole ->
               (r : Reading) -> (e0, e : Nat) -> (at : Depth) -> at.depth = e0 + e ->
               Dominates at.arcWeight (Finite (S at.depth) at.lift) ->
               (ts : List Template) -> AnsweredIn g s r e0 e at.lift ts -> Part (carriedAll m.fields s.roots at ts) whole ->
               AllCovered m s (at.depth, at.lift) ts
  coverAll fe dr r e0 e at deq aw [] ans part = []
  coverAll {m} {s} fe dr r e0 e at deq aw (t :: ts) ans part =
    coverAt fe dr r e0 e at deq aw t (firstAnswered r ans) (firstPart m.fields s.roots at t ts part) ::
    coverAll fe dr r e0 e at deq aw ts (restAnswered r ans) (restPart m.fields s.roots at t ts part)

  -- A field: closed where its field templates reach nowhere; otherwise its
  -- field templates within K and their reach, and its record covered as
  -- deep as they hold its arguments.
  0 fieldCovered : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> Feasible g pot ->
                   {s : Site g.size} -> {whole : Carried} -> Drawing g m s whole ->
                   (r : Reading) -> (e0, e : Nat) -> (at : Depth) -> at.depth = e0 + e ->
                   Dominates at.arcWeight (Finite (S at.depth) at.lift) ->
                   (k : Nat) -> (rec : Template) -> (reach : Reach) ->
                   reachAll 0 (fieldTemplates m.fields s.roots k rec) = reach ->
                   Answered g s r e0 e at.lift (Field k rec) ->
                   Part (fieldPlaced m.fields s.roots at rec (fieldTemplates m.fields s.roots k rec) reach
                                     (deepOf (fieldTemplates m.fields s.roots k rec))) whole ->
                   CoveredAt m s (at.depth, at.lift) (Field k rec)
  fieldCovered {m} fe dr r e0 e at deq aw k rec Nowhere eq ans part =
    CClosedField (\j, el, ft, found =>
      ( reachNowhere (keepJustHas {f = \j' => m.fields j' k} el found) eq
      , minusWithin (height ft + at.depth) at.lift _
          (dr.needed _ (part.partNeeds _ (There (elemAppendLeft (elemMap (\t => above at (height t))
                                                                       (keepJustHas {f = \j' => m.fields j' k} el found))))))))
  fieldCovered {m} {s} fe dr AtDepth e0 e at deq aw k rec (Deepest dg dl) eq ans part =
    CField dg dl (fieldWithin {m} {s} dr at k rec dg dl eq part)
      (coverAt fe dr AtDepth (at.depth + S dg) 0 (recordAt at (deepOf (fieldTemplates m.fields s.roots k rec)) (Deepest dg dl))
               (sym (plusZeroRightNeutral _)) (recordOver aw (deepOver {m} {s} k rec dg dl eq)) rec
               (\i, w0, el => case weightsCover rec el of
                  (w ** (inW, dom)) =>
                    ( plus (plus at.arcWeight (plus (deepOf (fieldTemplates m.fields s.roots k rec)) (Finite 0 2))) w
                    ** ( prefixedOver (piOver aw (deepOver {m} {s} k rec dg dl eq)) dom
                       , \p, wa, lab, leq => dr.records _ (varArcsHas (part.partArcs _ (elemAppendLeft (elemMap
                           (prefixed (plus at.arcWeight (plus (deepOf (fieldTemplates m.fields s.roots k rec)) (Finite 0 2))))
                           inW))) wa leq) ) ))
               (recordPart m.fields s.roots at rec (fieldTemplates m.fields s.roots k rec) (Deepest dg dl)
                           (deepOf (fieldTemplates m.fields s.roots k rec)) part))
      (minusWithin (height rec + (at.depth + S dg)) (at.lift + (dl + 2)) _ (dr.needed _ (part.partNeeds _ Here)))
  fieldCovered {m} {s} fe dr UnderComputation e0 e at deq aw k rec (Deepest dg dl) eq ans part =
    CField dg dl (fieldWithin {m} {s} dr at k rec dg dl eq part)
      (coverAt fe dr UnderComputation (at.depth + S dg) 0
               (recordAt at (deepOf (fieldTemplates m.fields s.roots k rec)) (Deepest dg dl))
               (sym (plusZeroRightNeutral _)) (recordOver aw (deepOver {m} {s} k rec dg dl eq)) rec ans
               (recordPart m.fields s.roots at rec (fieldTemplates m.fields s.roots k rec) (Deepest dg dl)
                           (deepOf (fieldTemplates m.fields s.roots k rec)) part))
      (minusWithin (height rec + (at.depth + S dg)) (at.lift + (dl + 2)) _ (dr.needed _ (part.partNeeds _ Here)))

  -- What a field's record weighs past where it sits dominates the reach.
  0 deepOver : {g : Graph} -> {m : Model g} -> {s : Site g.size} -> (k : Nat) -> (rec : Template) -> (dg, dl : Nat) ->
               reachAll 0 (fieldTemplates m.fields s.roots k rec) = Deepest dg dl ->
               Dominates (deepOf (fieldTemplates m.fields s.roots k rec)) (Finite dg dl)
  deepOver k rec dg dl eq =
    rewrite eq in joinOverLeft (Finite dg dl) (foldr join Absent (map holding (fieldTemplates m.fields s.roots k rec)))

  -- Each field template within K where the field is read, and holding the
  -- record's arguments no deeper than the reach.
  0 fieldWithin : {g : Graph} -> {m : Model g} -> {s : Site g.size} -> {whole : Carried} -> Drawing g m s whole ->
                  (at : Depth) -> (k : Nat) -> (rec : Template) -> (dg, dl : Nat) ->
                  reachAll 0 (fieldTemplates m.fields s.roots k rec) = Deepest dg dl ->
                  Part (fieldPlaced m.fields s.roots at rec (fieldTemplates m.fields s.roots k rec) (Deepest dg dl)
                                    (deepOf (fieldTemplates m.fields s.roots k rec))) whole ->
                  (j : Address) -> Elem j (s.roots rec) -> (ft : Template) -> m.fields j k = Just ft ->
                  FieldWithin g dg dl (at.depth, at.lift) ft
  fieldWithin {m} dr at k rec dg dl eq part j el ft found =
    MkFieldWithin
      (minusWithin (height ft + at.depth) at.lift _
         (dr.needed _ (part.partNeeds _ (There (elemAppendLeft (elemMap (\t => above at (height t))
                                                                      (keepJustHas {f = \j' => m.fields j' k} el found)))))))
      (\q, dq, eq', occ => reachHolds (keepJustHas {f = \j' => m.fields j' k} el found) occ eq)

-- The graph covers a site whose arcs and needs it holds.
0 covering : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> Feasible g pot -> (s : Site g.size) ->
             ((a : Arc g.size) -> Elem a (ownArcs m.fields s) -> Elem a g.arcs) ->
             ((a : Arc g.size) -> Elem a (projectedArcs m.fields m.positionsOf s) -> Elem a g.arcs) ->
             ((k : Nat) -> Elem k (needsOf m.fields s.roots s.template) -> LTE k g.constant) ->
             CoveredAt m s (0, 0) s.template
covering fe s own projected need =
  coverAt fe (MkDrawing (\a, el => own a (elemAppendRight (varArcs s.target s.writers (weights s.template)) el))
                        projected (\k, el => need k (There el)))
          AtDepth 0 0 atTop Refl (dominatesSelf (Finite 1 0)) s.template
          (\i, w0, el => case weightsCover s.template el of
             (w ** (inW, dom)) => (w ** (topOver dom, \p, wa, lab, leq => own _ (elemAppendLeft (varArcsHas inW wa leq)))))
          (MkPart (\x, el => el) (\x, el => el) (\k, el => el))

||| A graph drawn from a model's sites describes the model under any
||| feasible potential: every site lands at an uncapped position, K stands
||| above its template, and the graph covers every part of it, each Stuck
||| arc being one no feasible potential satisfies.
export
0 describes : {n : Nat} -> (fs : Address -> Nat -> Maybe Template) -> (ps : Address -> List (Fin n)) ->
              (positionOf : Fin n -> (Address, Nat)) -> (beyond : Nat) -> (caps : Vect n (Maybe Nat)) ->
              (ss : List (Site n, tag)) -> All (\x => index (fst x).target caps = Nothing) ss ->
              {pot : Vect n Nat} -> Feasible (graphOf fs ps beyond caps ss) pot ->
              Describes (modelOf fs ps positionOf beyond caps ss)
describes fs ps positionOf beyond caps ss uncapped fe = sitesCovered ss uncapped (\y, el => el)
  where
    -- What a site of the graph needs, K stands above.
    0 needed : (s : Site n) -> (x : tag) -> Elem (s, x) ss -> (k : Nat) -> Elem k (needsOf fs s.roots s.template) ->
               LTE k (topOf beyond (allOf (siteNeeds fs) ss))
    needed s x here k el = aboveAll beyond (allOf (siteNeeds fs) ss) (allOfHas (siteNeeds fs) here el)

    0 sitesCovered : (rest : List (Site n, tag)) -> All (\x => index (fst x).target caps = Nothing) rest ->
                     ((y : (Site n, tag)) -> Elem y rest -> Elem y ss) ->
                     All (Covers (graphOf fs ps beyond caps ss) (modelOf fs ps positionOf beyond caps ss)) (map fst rest)
    sitesCovered [] [] _ = []
    sitesCovered ((s, x) :: rest) (u :: us) sub =
      MkCovers u (needed s x (sub (s, x) Here) (height s.template) Here)
               (covering fe s
                  (\a, el => elemMap fst (elemAppendLeft (allOfHas (ownTagged fs) (sub (s, x) Here) (elemMap (\a' => (a', x)) el))))
                  (\a, el => elemMap fst (elemAppendRight (allOf (ownTagged fs) ss)
                                           (allOfHas (projectedTagged fs ps) (sub (s, x) Here) (elemMap (\a' => (a', x)) el))))
                  (needed s x (sub (s, x) Here)))
      :: sitesCovered rest us (\y, el => sub y (There el))
