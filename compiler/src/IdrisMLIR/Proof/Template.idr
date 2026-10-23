-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What a definition writes at a static argument, as the growth check and
||| its proof read it: a tree of heads whose leaves are the writer's
||| markers, the closed parts, and what a type computes from a marker.
|||
||| The readers of checked terms into templates are the frontend's
||| (`Frontend.Growth.Template`); the type and its measures are here, so
||| that the growth theorem (`Proof.Bound`) is stated over the type the
||| readers produce, with nothing of Idris's compiler in scope.
module IdrisMLIR.Proof.Template

import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Requests

import Data.List
import Data.List.Elem
import Data.List.Quantifiers
import Data.Nat
import Data.So

%default total

||| A choice as the growth graph holds it, program-wide: by the head of the
||| type it is a choice of, an implementation's type by the type
||| constructor it applies (an interface, or the pair that holds two), a
||| polymorphic function's by the arrow; or, where the type a site reads
||| shows no head (the writer's variable, a definition its markers leave
||| stuck), as one whose head only an instance shows. The translation keys
||| a choice by the whole type; a site writes that type over its writer's
||| markers, which each instance puts values in for, and a head, where the
||| site's type shows one, is the one part of it no value put in changes.
||| So every member the translation adds to a choice lands at the position
||| of that choice's head, or at the unshown one, and every dispatch on it
||| reads both; a dispatch whose own head is unshown reads every choice's.
public export
data ChoiceHead = InterfaceHead Address | ArrowHead | UnshownHead

public export
Eq ChoiceHead where
  InterfaceHead a == InterfaceHead b = a == b
  ArrowHead == ArrowHead = True
  UnshownHead == UnshownHead = True
  _ == _ = False

public export
Ord ChoiceHead where
  compare (InterfaceHead a) (InterfaceHead b) = compare a b
  compare (InterfaceHead _) _ = LT
  compare ArrowHead (InterfaceHead _) = GT
  compare ArrowHead ArrowHead = EQ
  compare ArrowHead UnshownHead = LT
  compare UnshownHead UnshownHead = EQ
  compare UnshownHead _ = GT

public export
data Template
  = ||| The writer's parameter i, bound by its pattern at depth d (0:
    ||| unmatched).
    Var Nat Nat
  | ||| A head: a type or data constructor, an implementation, an
    ||| interface's constructor (`Just`), a binder or a primitive type
    ||| former (`Nothing`).
    Head (Maybe Address) (List Template)
  | ||| A closed part of that height: a `Nat` literal's run (n successors:
    ||| n + 1), a primitive type, a bound variable, an erased placeholder
    ||| (1).
    Leaf Nat
  | ||| Any other literal, or a hole marker: height 1, carrying its key
    ||| token's weight for `Bounds.heaviest`.
    Token Nat
  | ||| One of its leaves at every instance, behind what it matched on: a
    ||| stuck non-recursive definition, unfolded; a definition given fewer
    ||| arguments than its parameters, as written and walked over the
    ||| arguments it lacks; one stuck on an argument of a family's value, as
    ||| written and as what beta computes; a projection of a record no
    ||| constructor yet, as written and as its field; a structural
    ||| recursion, its other leaves and its argument raised by them.
    Choice Template (List Template)
  | ||| A recursive definition, stuck on what its arguments hold.
    Opaque Address (List Template)
  | ||| The writer's family `Var i d` applied, which every instance
    ||| beta-reduces.
    Applied Nat Nat (List Template)
  | ||| The writer's family `Var i d` applied where its value, or an
    ||| argument, computes from what it is given: what beta makes there
    ||| nothing bounds.
    Computing Nat Nat (List Template)
  | ||| Argument j of a family's value, taking a arguments of its own: what
    ||| beta substitutes, a leaf of height 1 until it does. Nothing matches
    ||| one, so it has no depth.
    Formal Nat Nat
  | ||| Field k (a method or a superclass) of a dictionary not yet a
    ||| constructor.
    Field Nat Template
  | ||| A member of the choice of that head, which the running program
    ||| chooses: whatever a place that makes a member of it wrote at the
    ||| choice's positions (`Model.choicePositions`).
    Member ChoiceHead

mutual
  ||| The tallest of some templates; 0 for none.
  public export
  tallest : List Template -> Nat
  tallest [] = 0
  tallest (t :: ts) = maximum (height t) (tallest ts)

  ||| A template's height: a marker, a field and a member of a choice are 0
  ||| (what they stand for is weighed by their arcs), a leaf its own, a
  ||| token and an argument of a family's value 1 (the key's bound
  ||| variable), a head, a recursion and an applied family one above their
  ||| tallest child, a choice its tallest leaf.
  public export
  height : Template -> Nat
  height (Var _ _) = 0
  height (Field _ _) = 0
  height (Member _) = 0
  height (Leaf h) = h
  height (Token _) = 1
  height (Formal _ _) = 1
  height (Head _ ts) = S (tallest ts)
  height (Opaque _ ts) = S (tallest ts)
  height (Applied _ _ ts) = S (tallest ts)
  height (Computing _ _ ts) = S (tallest ts)
  height (Choice _ ts) = tallest ts

||| `c` levels of a head above a template: an applied family read where
||| only closed values no higher than c land at it.
public export
raise : Nat -> Template -> Template
raise Z t = t
raise (S c) t = Head Nothing [raise c t]

mutual
  public export
  widest : List Template -> Nat
  widest [] = 0
  widest (t :: ts) = maximum (arity t) (widest ts)

  ||| The most children of any node, a choice's leaves' own.
  public export
  arity : Template -> Nat
  arity (Head _ ts) = maximum (length ts) (widest ts)
  arity (Opaque _ ts) = maximum (length ts) (widest ts)
  arity (Applied _ _ ts) = maximum (S (length ts)) (widest ts)
  arity (Computing _ _ ts) = maximum (S (length ts)) (widest ts)
  arity (Choice _ ts) = widest ts
  arity (Field _ s) = arity s
  arity (Var _ _) = 0
  arity (Leaf _) = 0
  arity (Token _) = 0
  arity (Member _) = 0
  arity (Formal _ _) = 0

mutual
  public export
  heaviestOf : List Template -> Nat
  heaviestOf [] = 0
  heaviestOf (t :: ts) = maximum (heaviest t) (heaviestOf ts)

  ||| The heaviest literal or hole token a template holds, a choice's
  ||| leaves' included and its scrutinee skipped; 0 for none.
  public export
  heaviest : Template -> Nat
  heaviest (Token k) = k
  heaviest (Head _ ts) = heaviestOf ts
  heaviest (Opaque _ ts) = heaviestOf ts
  heaviest (Applied _ _ ts) = heaviestOf ts
  heaviest (Computing _ _ ts) = heaviestOf ts
  heaviest (Choice _ ts) = heaviestOf ts
  heaviest (Field _ s) = heaviest s
  heaviest (Var _ _) = 0
  heaviest (Leaf _) = 0
  heaviest (Member _) = 0
  heaviest (Formal _ _) = 0

------------------------------------------------------------------------------
-- The recursions a template holds
------------------------------------------------------------------------------

mutual
  ||| Every recursion a template holds (`Opaque`), in order, a choice's
  ||| scrutinee's and a field's record's among them: a reading gives, beside
  ||| its template, the definition of each.
  public export
  recursions : Template -> List Address
  recursions (Opaque a ts) = a :: recursionsIn ts
  recursions (Head _ ts) = recursionsIn ts
  recursions (Applied _ _ ts) = recursionsIn ts
  recursions (Computing _ _ ts) = recursionsIn ts
  recursions (Choice s ts) = recursions s ++ recursionsIn ts
  recursions (Field _ s) = recursions s
  recursions (Var _ _) = []
  recursions (Leaf _) = []
  recursions (Token _) = []
  recursions (Formal _ _) = []
  recursions (Member _) = []

  ||| Every recursion some templates hold, in order.
  public export
  recursionsIn : List Template -> List Address
  recursionsIn [] = []
  recursionsIn (t :: ts) = recursions t ++ recursionsIn ts

||| The recursions a template holds, where there is one.
public export
maybeRecursions : Maybe Template -> List Address
maybeRecursions Nothing = []
maybeRecursions (Just t) = recursions t

||| Two lists of templates hold the first's recursions, then the second's.
export
0 recursionsJoined : (xs, ys : List Template) -> recursionsIn (xs ++ ys) = recursionsIn xs ++ recursionsIn ys
recursionsJoined [] ys = Refl
recursionsJoined (x :: xs) ys =
  rewrite recursionsJoined xs ys in appendAssociative (recursions x) (recursionsIn xs) (recursionsIn ys)

||| Heads raised above a template hold its recursions and no other.
export
0 recursionsRaised : (c : Nat) -> (t : Template) -> recursions (raise c t) = recursions t
recursionsRaised Z t = Refl
recursionsRaised (S c) t = rewrite recursionsRaised c t in appendNilRightNeutral (recursions t)

------------------------------------------------------------------------------
-- The definitions a template names by address
------------------------------------------------------------------------------

||| A node's head before what its children name: a head that is a
||| definition names it, a binder or a primitive type former nothing.
public export
headNamed : Maybe Address -> List Address -> List Address
headNamed Nothing hs = hs
headNamed (Just a) hs = a :: hs

||| What a member of a choice names: an implementation's choice its
||| interface; the arrow, and the head only an instance shows, nothing.
public export
memberHead : ChoiceHead -> List Address
memberHead (InterfaceHead a) = [a]
memberHead ArrowHead = []
memberHead UnshownHead = []

mutual
  ||| Every definition a template names by address but a recursion's own
  ||| (`recursions`), in order, a choice's scrutinee's and a field's record's
  ||| among them: each head a definition is, and each choice's interface a
  ||| member names. A site's reading gives, beside its template, the
  ||| definition of each, as it met it, so no reader of the template finds
  ||| one again by its address.
  public export
  namedHeads : Template -> List Address
  namedHeads (Head h ts) = headNamed h (namedHeadsIn ts)
  namedHeads (Opaque _ ts) = namedHeadsIn ts
  namedHeads (Applied _ _ ts) = namedHeadsIn ts
  namedHeads (Computing _ _ ts) = namedHeadsIn ts
  namedHeads (Choice s ts) = namedHeads s ++ namedHeadsIn ts
  namedHeads (Field _ s) = namedHeads s
  namedHeads (Member k) = memberHead k
  namedHeads (Var _ _) = []
  namedHeads (Leaf _) = []
  namedHeads (Token _) = []
  namedHeads (Formal _ _) = []

  ||| Every definition some templates name by address, in order.
  public export
  namedHeadsIn : List Template -> List Address
  namedHeadsIn [] = []
  namedHeadsIn (t :: ts) = namedHeads t ++ namedHeadsIn ts

||| The definitions a template names, where there is one.
public export
maybeNamedHeads : Maybe Template -> List Address
maybeNamedHeads Nothing = []
maybeNamedHeads (Just t) = namedHeads t

||| Two lists of templates name the first's definitions, then the second's.
export
0 headsJoined : (xs, ys : List Template) -> namedHeadsIn (xs ++ ys) = namedHeadsIn xs ++ namedHeadsIn ys
headsJoined [] ys = Refl
headsJoined (x :: xs) ys =
  rewrite headsJoined xs ys in appendAssociative (namedHeads x) (namedHeadsIn xs) (namedHeadsIn ys)

||| Heads raised above a template name what it names and nothing else: a
||| raised head is no definition.
export
0 headsRaised : (c : Nat) -> (t : Template) -> namedHeads (raise c t) = namedHeads t
headsRaised Z t = Refl
headsRaised (S c) t = rewrite headsRaised c t in appendNilRightNeutral (namedHeads t)

||| What holds of each of two lists, the first's first.
public export
allJoined : All p xs -> All p ys -> All p (xs ++ ys)
allJoined [] qs = qs
allJoined (q :: ps) qs = q :: allJoined ps qs

||| What holds of each of a list joined before another, of the first.
public export
allBefore : (xs : List a) -> All p (xs ++ ys) -> All p xs
allBefore [] _ = []
allBefore (_ :: xs) (q :: qs) = q :: allBefore xs qs

||| What holds of each of a list joined after another, of the second.
public export
allAfter : (xs : List a) -> All p (xs ++ ys) -> All p ys
allAfter [] qs = qs
allAfter (_ :: xs) (_ :: qs) = allAfter xs qs

||| A list's element, at its place in the list joined before another.
public export
elemBefore : Elem x xs -> Elem x (xs ++ ys)
elemBefore Here = Here
elemBefore (There e) = There (elemBefore e)

||| A list's element, at its place in the list joined after another.
public export
elemAfter : (xs : List a) -> Elem x ys -> Elem x (xs ++ ys)
elemAfter [] e = e
elemAfter (_ :: xs) e = There (elemAfter xs e)

||| Where a part's recursions sit among those of the template a site
||| writes, the whole: each is one of the whole's, at its place there. A
||| recursion that passes an occurrence on is named by that place
||| (`StuckRecursion`), and the site's reading gives a definition for each
||| of the whole's recursions, by place.
public export
record InWhole (rs : List Address) (whole : Template) where
  constructor MkInWhole
  toWhole : {0 a : Address} -> Elem a rs -> Elem a (recursions whole)

||| A template is its own whole.
public export
asWhole : InWhole (recursions t) t
asWhole = MkInWhole (\el => el)

||| A recursion's place in the whole.
public export
placedHere : InWhole (a :: rs) whole -> Elem a (recursions whole)
placedHere w = w.toWhole Here

||| The recursions a recursion's arguments hold, in the whole.
public export
placedUnder : InWhole (a :: rs) whole -> InWhole rs whole
placedUnder w = MkInWhole (\el => w.toWhole (There el))

||| The recursions of a list's first part, in the whole.
public export
placedFirst : InWhole (xs ++ ys) whole -> InWhole xs whole
placedFirst w = MkInWhole (\el => w.toWhole (elemBefore el))

||| The recursions of a list's rest, after those of its first part, in the
||| whole.
public export
placedRest : (xs : List Address) -> InWhole (xs ++ ys) whole -> InWhole ys whole
placedRest xs w = MkInWhole (\el => w.toWhole (elemAfter xs el))

------------------------------------------------------------------------------
-- What a template carries
------------------------------------------------------------------------------

mutual
  ||| Is what every instance writes at a template no higher than the
  ||| template: it holds no marker, field or member of a choice, whose
  ||| values are their arcs', and no family applied? A choice's value is one of its
  ||| leaves, and an argument of a family's value is the writer's to no
  ||| instance: what beta makes of it, the reading's `beta` says.
  public export
  selfBounded : Template -> Bool
  selfBounded (Head _ ts) = allSelfBounded ts
  selfBounded (Opaque _ ts) = allSelfBounded ts
  selfBounded (Choice _ ts) = allSelfBounded ts
  selfBounded (Leaf _) = True
  selfBounded (Token _) = True
  selfBounded (Var _ _) = False
  selfBounded (Applied _ _ _) = False
  selfBounded (Computing _ _ _) = False
  selfBounded (Field _ _) = False
  selfBounded (Member _) = False
  selfBounded (Formal _ _) = True

  public export
  allSelfBounded : List Template -> Bool
  allSelfBounded [] = True
  allSelfBounded (t :: ts) = selfBounded t && allSelfBounded ts

||| What an applied family's own marker weighs, e heads deep, by whether
||| its arguments are closed: their height above the marker's own value,
||| or Stuck. The test is written once, here, so that the weight and what
||| passes it on (`appliedPassage`) split on one function, which a proof
||| unifies with both.
public export
appliedAt : (closed : Bool) -> (e, d : Nat) -> List Template -> Weight
appliedAt True e d ts = Finite (e + tallest ts) d
appliedAt False e d ts = Stuck

||| How much an applied family grows its own marker, e heads deep. Beta of
||| a family no higher than k, applied to arguments no higher than h, is no
||| higher than k + h when the family is inert: with closed arguments h is
||| their height, the marker's own value raised by a constant; with an
||| argument that holds a marker it is a sum of two heights, which no
||| weight states.
public export
appliedWeight : (e, d : Nat) -> List Template -> Weight
appliedWeight e d ts = appliedAt (allSelfBounded ts) e d ts

mutual
  ||| Each occurrence of a writer's parameter in a template read e heads
  ||| deep, with what it carries: `Var i d`, e - d; an applied family's own
  ||| marker, its closed arguments' height above that; every marker under a
  ||| recursion or an applied family's argument, and a computing family's
  ||| own, Stuck. A field writes what its position holds, which an arc from
  ||| there carries, whatever its record is, and so does a member of a
  ||| choice; a choice's scrutinee is carried by its caps; so none of them
  ||| is a part the template's height carries.
  public export
  occurrences : (e : Nat) -> Template -> List (Nat, Weight)
  occurrences e (Var j d) = [(j, Finite e d)]
  occurrences e (Head _ ts) = occurrencesIn (S e) ts
  occurrences e (Opaque _ ts) = stuckIn ts
  occurrences e (Applied j d ts) = (j, appliedWeight e d ts) :: stuckIn ts
  occurrences e (Computing j _ ts) = (j, Stuck) :: stuckIn ts
  occurrences e (Choice _ ts) = occurrencesIn e ts
  occurrences e (Field _ _) = []
  occurrences e (Leaf _) = []
  occurrences e (Token _) = []
  occurrences e (Member _) = []
  occurrences e (Formal _ _) = []

  public export
  occurrencesIn : (e : Nat) -> List Template -> List (Nat, Weight)
  occurrencesIn e [] = []
  occurrencesIn e (t :: ts) = occurrences e t ++ occurrencesIn e ts

  ||| Every marker below, as Stuck: what a recursion computes from a marker
  ||| has no depth bound. A field's record is no part of what it writes.
  public export
  stuck : Template -> List (Nat, Weight)
  stuck (Var j _) = [(j, Stuck)]
  stuck (Field _ _) = []
  stuck (Head _ ts) = stuckIn ts
  stuck (Opaque _ ts) = stuckIn ts
  stuck (Applied j _ ts) = (j, Stuck) :: stuckIn ts
  stuck (Computing j _ ts) = (j, Stuck) :: stuckIn ts
  stuck (Choice _ ts) = stuckIn ts
  stuck (Leaf _) = []
  stuck (Token _) = []
  stuck (Member _) = []
  stuck (Formal _ _) = []

  public export
  stuckIn : List Template -> List (Nat, Weight)
  stuckIn [] = []
  stuckIn (t :: ts) = stuck t ++ stuckIn ts

||| A weight joined into a list of them by parameter, each parameter once
||| and ascending, as the parameters' positions are numbered.
public export
insertJoin : Nat -> Weight -> List (Nat, Weight) -> List (Nat, Weight)
insertJoin i w [] = [(i, w)]
insertJoin i w ((j, v) :: rest) =
  if i == j then (j, join v w) :: rest
  else if i < j then (i, w) :: (j, v) :: rest
  else (j, v) :: insertJoin i w rest

||| Weights joined in, one at a time.
public export
joinAll : (acc : List (Nat, Weight)) -> List (Nat, Weight) -> List (Nat, Weight)
joinAll acc [] = acc
joinAll acc ((i, w) :: xs) = joinAll (insertJoin i w acc) xs

public export
settledEntry : (Nat, Weight) -> (Nat, Weight)
settledEntry (i, w) = (i, settled w)

||| Every parameter a template grows, each once and ascending, with how
||| much: the most its occurrences carry, written with one side 0. A
||| parameter that does not occur is not listed.
public export
weights : Template -> List (Nat, Weight)
weights t = map settledEntry (joinAll [] (occurrences 0 t))

------------------------------------------------------------------------------
-- What passes an occurrence on
------------------------------------------------------------------------------

||| A type-level computation a value passes through, which nothing bounds,
||| in the template a site writes: a recursive definition stuck on what its
||| arguments hold (`Opaque`), named by its place among the template's
||| recursions, the place the site's reading gives its definition at; or a
||| family the writer is given, applied (`Applied`, `Computing`), which
||| every instance beta-reduces. Two cases the problem has: a definition's
||| own unfolding, and a value's.
public export
data Computation : Template -> Type where
  StuckRecursion : {0 t : Template} -> {0 a : Address} -> Elem a (recursions t) -> Computation t
  AppliedFamily : {0 t : Template} -> Nat -> Computation t

||| What passes an occurrence on to where it is written, in the template a
||| site writes, indexed by the weight it is drawn at: heads alone, which
||| raise it by the finite weight they measure; or a computation of the
||| template's, where its weight is Stuck. So a Stuck weight always says
||| what computation made it so, and a finite one never names one.
public export
data Passage : Template -> Weight -> Type where
  ByHeads : {0 t : Template} -> (gain, loss : Nat) -> Passage t (Finite gain loss)
  ByComputation : {0 t : Template} -> Computation t -> Passage t Stuck

||| What passes on each of a list of weights by parameter: the list itself,
||| each weight with its passage, so it cannot disagree with the weights
||| it is indexed by.
public export
data Passages : Template -> List (Nat, Weight) -> Type where
  NonePassed : {0 t : Template} -> Passages t []
  PassedOn : {0 t : Template} -> {0 w : Weight} -> {0 xs : List (Nat, Weight)} -> (i : Nat) -> Passage t w -> Passages t xs ->
             Passages t ((i, w) :: xs)

||| The label of the arc a passage draws.
public export
passageLabel : Passage t w -> Label
passageLabel (ByHeads gain loss) = Measured gain loss
passageLabel (ByComputation _) = Unmeasured

||| A passage draws the arc of the weight it passes on.
export
0 passageLabelled : (p : Passage t w) -> labelOf w = Just (passageLabel p)
passageLabelled (ByHeads _ _) = Refl
passageLabelled (ByComputation _) = Refl

||| What passes on a weight raised by a finite one (`plus`).
export
plusPassage : Passage t w -> (gain, loss : Nat) -> Passage t (plus w (Finite gain loss))
plusPassage (ByHeads g l) gain loss = ByHeads (g + gain) (l + loss)
plusPassage (ByComputation c) _ _ = ByComputation c

-- One list's passages before another's.
alsoPassedOn : {0 xs, ys : List (Nat, Weight)} -> Passages t xs -> Passages t ys -> Passages t (xs ++ ys)
alsoPassedOn NonePassed qs = qs
alsoPassedOn (PassedOn i p ps) qs = PassedOn i p (alsoPassedOn ps qs)

-- What passes on an applied family's own marker: heads above its
-- arguments where they are closed, and otherwise the family, where what
-- beta makes of them is a sum of two heights. It splits on the weight's
-- own test (`appliedAt`).
appliedPassage : {0 whole : Template} -> (j, e, d : Nat) -> (ts : List Template) -> Passage whole (appliedWeight e d ts)
appliedPassage {whole} j e d ts = atClosed (allSelfBounded ts)
  where
    atClosed : (closed : Bool) -> Passage whole (appliedAt closed e d ts)
    atClosed True = ByHeads (e + tallest ts) d
    atClosed False = ByComputation (AppliedFamily j)

mutual
  ||| What passes on each occurrence of a part of a site's template read e
  ||| heads deep (`occurrences`), where the occurrence's weight is made:
  ||| heads alone for a marker, and for an applied family's own marker where
  ||| its arguments are closed; the family itself for its own marker
  ||| otherwise, and for a computing family's; and for every other marker
  ||| under a computation, the outermost computation it is under, a
  ||| recursion by its place in the whole.
  export
  passagesOf : (e : Nat) -> (t : Template) -> InWhole (recursions t) whole -> Passages whole (occurrences e t)
  passagesOf e (Var j d) w = PassedOn j (ByHeads e d) NonePassed
  passagesOf e (Head _ ts) w = passagesIn (S e) ts w
  passagesOf e (Opaque r ts) w = passedThroughAll (StuckRecursion (placedHere w)) ts
  passagesOf e (Applied j d ts) w = PassedOn j (appliedPassage j e d ts) (passedThroughAll (AppliedFamily j) ts)
  passagesOf e (Computing j _ ts) w = PassedOn j (ByComputation (AppliedFamily j)) (passedThroughAll (AppliedFamily j) ts)
  passagesOf e (Choice s ts) w = passagesIn e ts (placedRest (recursions s) w)
  passagesOf e (Field _ _) w = NonePassed
  passagesOf e (Leaf _) w = NonePassed
  passagesOf e (Token _) w = NonePassed
  passagesOf e (Member _) w = NonePassed
  passagesOf e (Formal _ _) w = NonePassed

  export
  passagesIn : (e : Nat) -> (ts : List Template) -> InWhole (recursionsIn ts) whole -> Passages whole (occurrencesIn e ts)
  passagesIn e [] w = NonePassed
  passagesIn e (t :: ts) w = alsoPassedOn (passagesOf e t (placedFirst w)) (passagesIn e ts (placedRest (recursions t) w))

  ||| What passes on each marker under a computation (`stuck`): that
  ||| computation, the outermost one the marker is under, but for an
  ||| applied or computing family's own marker, which its family passes on.
  export
  passedThrough : Computation whole -> (t : Template) -> Passages whole (stuck t)
  passedThrough c (Var j _) = PassedOn j (ByComputation c) NonePassed
  passedThrough c (Field _ _) = NonePassed
  passedThrough c (Head _ ts) = passedThroughAll c ts
  passedThrough c (Opaque _ ts) = passedThroughAll c ts
  passedThrough c (Applied j _ ts) = PassedOn j (ByComputation (AppliedFamily j)) (passedThroughAll c ts)
  passedThrough c (Computing j _ ts) = PassedOn j (ByComputation (AppliedFamily j)) (passedThroughAll c ts)
  passedThrough c (Choice _ ts) = passedThroughAll c ts
  passedThrough c (Leaf _) = NonePassed
  passedThrough c (Token _) = NonePassed
  passedThrough c (Member _) = NonePassed
  passedThrough c (Formal _ _) = NonePassed

  export
  passedThroughAll : Computation whole -> (ts : List Template) -> Passages whole (stuckIn ts)
  passedThroughAll c [] = NonePassed
  passedThroughAll c (t :: ts) = alsoPassedOn (passedThrough c t) (passedThroughAll c ts)

-- What passes on a weight joined into another (`join`): the first Stuck
-- one's computation, or the finite weight the join keeps.
joinPassage : {0 v, w : Weight} -> Passage t v -> Passage t w -> Passage t (join v w)
joinPassage (ByComputation c) (ByComputation _) = ByComputation c
joinPassage (ByComputation c) (ByHeads _ _) = ByComputation c
joinPassage (ByHeads _ _) (ByComputation c) = ByComputation c
joinPassage (ByHeads g l) (ByHeads g' l') with (g + l' <= g' + l)
  _ | True = ByHeads g' l'
  _ | False = ByHeads g l

-- What passes on a weight joined into a list of them (`insertJoin`).
insertPassage : {0 w : Weight} -> {0 acc : List (Nat, Weight)} -> (i : Nat) -> Passage t w -> Passages t acc ->
                Passages t (insertJoin i w acc)
insertPassage i p NonePassed = PassedOn i p NonePassed
insertPassage i p (PassedOn j q qs) with (i == j)
  _ | True = PassedOn j (joinPassage q p) qs
  _ | False with (i < j)
    _ | True = PassedOn i p (PassedOn j q qs)
    _ | False = PassedOn j q (insertPassage i p qs)

-- What passes on weights joined in, one at a time (`joinAll`).
joinPassages : {0 acc, xs : List (Nat, Weight)} -> Passages t acc -> Passages t xs -> Passages t (joinAll acc xs)
joinPassages ps NonePassed = ps
joinPassages ps (PassedOn i q qs) = joinPassages (insertPassage i q ps) qs

-- What passes on a weight written with one side 0 (`settled`).
settledPassage : {0 w : Weight} -> Passage t w -> Passage t (settled w)
settledPassage (ByHeads g l) = ByHeads (minus g l) (minus l g)
settledPassage (ByComputation c) = ByComputation c

settledPassages : {0 xs : List (Nat, Weight)} -> Passages t xs -> Passages t (map Template.settledEntry xs)
settledPassages NonePassed = NonePassed
settledPassages (PassedOn i p ps) = PassedOn i (settledPassage p) (settledPassages ps)

||| What passes on each parameter a template grows (`weights`), at the
||| weight its occurrences join to: where that is Stuck, the computation
||| of its first Stuck occurrence, a recursion by its place among the
||| template's. It is the weights themselves, computed with what passes
||| each on, so the graph draws a parameter's arcs from it and knows, where
||| an arc is Unmeasured, what made it so.
export
weightPassages : (t : Template) -> Passages t (weights t)
weightPassages t = settledPassages (joinPassages NonePassed (passagesOf 0 t asWhole))

------------------------------------------------------------------------------
-- Every occurrence is listed
------------------------------------------------------------------------------

||| Parameter i listed with a weight that dominates w.
public export
0 Joined : Nat -> Weight -> List (Nat, Weight) -> Type
Joined i w m = (v : Weight ** (Elem (i, v) m, Dominates v w))

0 insertJoinNew : (i : Nat) -> (w : Weight) -> (m : List (Nat, Weight)) -> Joined i w (insertJoin i w m)
insertJoinNew i w [] = (w ** (Here, dominatesSelf w))
insertJoinNew i w ((j, v) :: rest) with (i == j) proof same
  _ | True = rewrite equalSo {m = i} {n = j} (the (So (i == j)) (rewrite same in Oh)) in
             (join v w ** (Here, joinOverRight v w))
  _ | False with (i < j)
    _ | True = (w ** (Here, dominatesSelf w))
    _ | False = let (u ** (el, dom)) = insertJoinNew i w rest in (u ** (There el, dom))

0 insertJoinKeep : (i : Nat) -> (w : Weight) -> (m : List (Nat, Weight)) -> Joined k u m -> Joined k u (insertJoin i w m)
insertJoinKeep i w [] (_ ** (el, _)) = absurd el
insertJoinKeep i w ((j, v) :: rest) (u' ** (el, dom)) with (i == j)
  _ | True = case el of
    Here => (join v w ** (Here, dominatesThrough (joinOverLeft v w) dom))
    There el' => (u' ** (There el', dom))
  _ | False with (i < j)
    _ | True = (u' ** (There el, dom))
    _ | False = case el of
      Here => (u' ** (Here, dom))
      There el' => let (x ** (el'', dom')) = insertJoinKeep i w rest (u' ** (el', dom)) in (x ** (There el'', dom'))

0 joinAllKeep : (acc, xs : List (Nat, Weight)) -> Joined k u acc -> Joined k u (joinAll acc xs)
joinAllKeep acc [] j = j
joinAllKeep acc ((i, w) :: xs) j = joinAllKeep (insertJoin i w acc) xs (insertJoinKeep i w acc j)

0 joinAllCover : (acc, xs : List (Nat, Weight)) -> Elem (i, w) xs -> Joined i w (joinAll acc xs)
joinAllCover acc ((i, w) :: xs) Here = joinAllKeep (insertJoin i w acc) xs (insertJoinNew i w acc)
joinAllCover acc ((j, v) :: xs) (There el) = joinAllCover (insertJoin j v acc) xs el

||| Every occurrence of a parameter in a template is listed among its
||| weights with one that dominates what the occurrence carries.
export
0 weightsCover : (t : Template) -> Elem (i, w) (occurrences 0 t) -> Joined i w (weights t)
weightsCover t el = case joinAllCover [] (occurrences 0 t) el of
  (v ** (here, dom)) => (settled v ** (elemMap settledEntry here, settledOver dom))
