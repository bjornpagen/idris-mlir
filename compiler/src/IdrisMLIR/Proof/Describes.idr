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
||| be (`fieldRoots`); a member of a choice an arc from each position its
||| members are read from; and an applied family that gives an
||| implementation, an arc from every position of every implementation it
||| can be (`heldRoots`). A part under a computation draws Stuck arcs, which
||| no feasible potential satisfies (`measuredOnly`), so it needs no other
||| covering. The order of the arcs is the order the check reads them in:
||| each site's own, then each site's from what applied families give,
||| fields and choices.
|||
||| Each arc is drawn with what its weight was made from (`Drawn`): whether
||| the site's writer binds its source, and what passes the source on,
||| heads or, where the arc is Unmeasured, the computation that made it so
||| (`Proof.Template.Passage`). The arcs alone are the ones the proof reads
||| (`ownArcs`, `projectedArcs`), shown to be the drawing's.
module IdrisMLIR.Proof.Describes

import IdrisMLIR.Proof.Bound
import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Held
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template

import Data.Nat
import Data.So

%default total

-- A chain of held dispatches' answers are Proof.Held's; what a site's
-- part answers for is this module's own.
%hide IdrisMLIR.Proof.Held.Answered

------------------------------------------------------------------------------
-- Where a part is read
------------------------------------------------------------------------------

||| Where a part of a site's template is read: what an arc from an
||| implementation an applied family gives into the site weighs there, with
||| what passes it on (its passage, which alone is held at run time), and
||| how many levels down the part is.
public export
record Depth where
  constructor MkDepth
  0 arcWeight : Weight
  passage : Passage arcWeight
  depth : Nat

||| A site's template, where it lands.
public export
atTop : Depth
atTop = MkDepth (Finite 1 0) (ByHeads 1 0) 0

||| A head's child.
public export
underHead : Depth -> Depth
underHead at = MkDepth (plus at.arcWeight (Finite 1 0)) (plusPassage at.passage 1 0) (S at.depth)

-- What passes on what a computation's child carries: the outermost
-- computation it is under.
export
enterComputation : Computation -> Passage w -> Passage Stuck
enterComputation c (ByHeads _ _) = ByComputation c
enterComputation c (ByComputation outer) = ByComputation outer

||| A child of a computation, a recursion or an applied or computing
||| family: a level down, and what an arc carries there unbounded, passed
||| on by the outermost computation it is under.
public export
underComputation : Computation -> Depth -> Depth
underComputation c at = MkDepth Stuck (enterComputation c at.passage) (S at.depth)

||| What an arc from a field's position, or a choice's, into the site
||| weighs where the field or the member is read: the value sits where it
||| is read, a level above the arguments of an implementation an applied
||| family gives there.
public export
0 fieldWeight : Depth -> Weight
fieldWeight at = plus at.arcWeight (Finite 0 1)

||| A weight with what passes it on: the passage alone is held at run
||| time, and it says the weight.
public export
record Weighed where
  constructor MkWeighed
  0 atWeight : Weight
  passage : Passage atWeight

||| What an arc from an implementation an applied family gives weighs where
||| the family is read, with what passes it on.
public export
weighedAt : Depth -> Weighed
weighedAt at = MkWeighed at.arcWeight at.passage

||| What an arc from a field's or a choice's position weighs where the
||| field or the member is read (`fieldWeight`), with what passes it on.
public export
fieldWeighed : Depth -> Weighed
fieldWeighed at = MkWeighed (fieldWeight at) (plusPassage at.passage 0 1)

------------------------------------------------------------------------------
-- What a template's fields, members and applied families carry
------------------------------------------------------------------------------

||| What a template's fields, choices and applied families carry: each
||| field's position, an implementation's field k, with the weight of its
||| arc; each implementation an applied family can give, with the weight of
||| the arcs from its positions; each choice a member is read from, with the
||| weight of the arc from its position; each weight with what passes it on.
public export
record Carried where
  constructor MkCarried
  fields : List ((Address, Nat), Weighed)
  held : List (Address, Weighed)
  choices : List (ChoiceHead, Weighed)

public export
noneCarried : Carried
noneCarried = MkCarried [] [] []

public export
alsoCarried : Carried -> Carried -> Carried
alsoCarried x y = MkCarried (x.fields ++ y.fields) (x.held ++ y.held) (x.choices ++ y.choices)

||| Each implementation a template can be, with the weight of the arcs from
||| its positions here.
public export
heldRoots : (Template -> List Address) -> Depth -> Template -> List (Address, Weighed)
heldRoots rts at t = map (\j => (j, weighedAt at)) (rts t)

||| Field k of each implementation a record can be, with the weight of the
||| arc from its position here.
public export
fieldRoots : (Template -> List Address) -> Depth -> Nat -> Template -> List ((Address, Nat), Weighed)
fieldRoots rts at k rec = map (\j => ((j, k), fieldWeighed at)) (rts rec)

mutual
  ||| Every field's, member's and applied family's value in a template read
  ||| here: what an applied family gives is a head over its
  ||| implementation's arguments, a level down; a field is what its
  ||| position holds, whatever its record writes; a member is what a
  ||| position its members are read from holds.
  public export
  carriedAt : (Template -> List Address) -> Depth -> Template -> Carried
  carriedAt rts at (Field k rec) = MkCarried (fieldRoots rts at k rec) [] []
  carriedAt rts at (Member k) = MkCarried [] [] [(k, fieldWeighed at)]
  carriedAt rts at t@(Applied j _ ts) =
    alsoCarried (MkCarried [] (heldRoots rts at t) []) (carriedAll rts (underComputation (AppliedFamily j) at) ts)
  carriedAt rts at (Head _ ts) = carriedAll rts (underHead at) ts
  carriedAt rts at (Opaque r ts) = carriedAll rts (underComputation (StuckRecursion r) at) ts
  carriedAt rts at (Computing j _ ts) = carriedAll rts (underComputation (AppliedFamily j) at) ts
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
0 heldArcs : Fin n -> (Address -> List (Fin n)) -> List (Address, Weighed) -> List (Arc n)
heldArcs t ps [] = []
heldArcs t ps ((j, c) :: rest) = arcsInto t (labelOf c.atWeight) (ps j) ++ heldArcs t ps rest

||| The arcs of fields with their weights, each from its position.
public export
0 fieldArcs : Fin n -> (Address -> Nat -> List (Fin n)) -> List ((Address, Nat), Weighed) -> List (Arc n)
fieldArcs t fps [] = []
fieldArcs t fps (((j, k), c) :: rest) = arcsInto t (labelOf c.atWeight) (fps j k) ++ fieldArcs t fps rest

||| The arcs of choices with their weights, each from its position.
public export
0 choiceArcs : Fin n -> (ChoiceHead -> List (Fin n)) -> List (ChoiceHead, Weighed) -> List (Arc n)
choiceArcs t cps [] = []
choiceArcs t cps ((k, c) :: rest) = arcsInto t (labelOf c.atWeight) (cps k) ++ choiceArcs t cps rest

||| A site's own arcs, from its parameters.
public export
ownArcs : Site n -> List (Arc n)
ownArcs s = varArcs s.target s.writers (weights s.template)

||| A site's arcs from what its applied families can give, then from its
||| fields' positions, then from its choices'.
public export
0 projectedArcs : (Address -> List (Fin n)) -> (Address -> Nat -> List (Fin n)) -> (ChoiceHead -> List (Fin n)) ->
                  Site n -> List (Arc n)
projectedArcs ps fps cps s =
  heldArcs s.target ps (carriedAt s.roots atTop s.template).held ++
  fieldArcs s.target fps (carriedAt s.roots atTop s.template).fields ++
  choiceArcs s.target cps (carriedAt s.roots atTop s.template).choices

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

------------------------------------------------------------------------------
-- The arcs as drawn
------------------------------------------------------------------------------

||| Whether the writer of the site that draws an arc binds the arc's
||| source: its own parameter, which its text binds; or a position its text
||| does not bind, projected: an implementation's an applied family gives,
||| an implementation's field a field read takes, or a choice's a member is
||| read from.
public export
data ArcSource = WriterBinds | WriterProjects

||| An arc as a site draws it: whether the writer binds its source, and
||| what passes the source on to the target, the weight the arc is drawn
||| at: heads alone, which its label measures, or, where it is Unmeasured,
||| the computation that made it so.
public export
record Drawn (n : Nat) where
  constructor MkDrawn
  drawnArc : Arc n
  sourceRead : ArcSource
  weighing : Weighed
  0 labelled : labelOf weighing.atWeight = Just drawnArc.label

||| Arcs into a target from each of some positions, their source read as
||| given, each at the weight given with what passes it on.
public export
drawnInto : Fin n -> ArcSource -> Weighed -> List (Fin n) -> List (Drawn n)
drawnInto t src c [] = []
drawnInto t src c (q :: qs) =
  MkDrawn (MkArc q t (passageLabel c.passage)) src c (passageLabelled c.passage) :: drawnInto t src c qs

||| A site's parameters' arcs, each from the positions the writer reads it
||| at, at the weight its occurrences join to with what passes it on.
public export
varDrawn : Fin n -> List (Nat, Fin n) -> Passages vs -> List (Drawn n)
varDrawn t ws NonePassed = []
varDrawn t ws (PassedOn i p rest) = drawnInto t WriterBinds (MkWeighed _ p) (writersOf i ws) ++ varDrawn t ws rest

||| The arcs of implementations an applied family gives, as drawn.
public export
heldDrawn : Fin n -> (Address -> List (Fin n)) -> List (Address, Weighed) -> List (Drawn n)
heldDrawn t ps [] = []
heldDrawn t ps ((j, c) :: rest) = drawnInto t WriterProjects c (ps j) ++ heldDrawn t ps rest

||| The arcs of fields, as drawn.
public export
fieldDrawn : Fin n -> (Address -> Nat -> List (Fin n)) -> List ((Address, Nat), Weighed) -> List (Drawn n)
fieldDrawn t fps [] = []
fieldDrawn t fps (((j, k), c) :: rest) = drawnInto t WriterProjects c (fps j k) ++ fieldDrawn t fps rest

||| The arcs of choices, as drawn.
public export
choiceDrawn : Fin n -> (ChoiceHead -> List (Fin n)) -> List (ChoiceHead, Weighed) -> List (Drawn n)
choiceDrawn t cps [] = []
choiceDrawn t cps ((k, c) :: rest) = drawnInto t WriterProjects c (cps k) ++ choiceDrawn t cps rest

||| What a template's applied families, fields and choices carry, drawn.
public export
carriedDrawn : Fin n -> (Address -> List (Fin n)) -> (Address -> Nat -> List (Fin n)) -> (ChoiceHead -> List (Fin n)) ->
               Carried -> List (Drawn n)
carriedDrawn t ps fps cps c = heldDrawn t ps c.held ++ fieldDrawn t fps c.fields ++ choiceDrawn t cps c.choices

||| A site's own arcs as drawn: its arcs (`ownArcs`), drawn from what passes
||| on each parameter its template weighs.
public export
drawnOwn : Site n -> List (Drawn n)
drawnOwn s = varDrawn s.target s.writers (weightPassages s.template)

||| A site's projected arcs as drawn (`projectedArcs`), what its template
||| carries read once.
public export
drawnProjected : (Address -> List (Fin n)) -> (Address -> Nat -> List (Fin n)) -> (ChoiceHead -> List (Fin n)) ->
                 Site n -> List (Drawn n)
drawnProjected ps fps cps s = carriedDrawn s.target ps fps cps (carriedAt s.roots atTop s.template)

-- A weight drawn as Unmeasured is Stuck.
0 unmeasuredStuck : (w : Weight) -> labelOf w = Just Unmeasured -> w = Stuck
unmeasuredStuck Absent Refl impossible
unmeasuredStuck (Finite _ _) Refl impossible
unmeasuredStuck Stuck _ = Refl

-- What passes a Stuck weight on is a computation.
passedBy : {0 w : Weight} -> Passage w -> (0 _ : w = Stuck) -> Computation
passedBy (ByComputation c) _ = c
passedBy (ByHeads _ _) Refl impossible

||| The computation that passed on an arc nothing bounds: drawn
||| Unmeasured, its weight is Stuck, and what passes a Stuck weight on is
||| a computation.
export
throughOf : (d : Drawn n) -> (0 _ : d.drawnArc.label = Unmeasured) -> Computation
throughOf d unmeasured =
  passedBy d.weighing.passage (unmeasuredStuck d.weighing.atWeight (trans d.labelled (cong Just unmeasured)))

public export
ownTagged : (Site n, tag) -> List (Drawn n, tag)
ownTagged (s, x) = map (\d => (d, x)) (drawnOwn s)

public export
projectedTagged : (Address -> List (Fin n)) -> (Address -> Nat -> List (Fin n)) -> (ChoiceHead -> List (Fin n)) ->
                  (Site n, tag) -> List (Drawn n, tag)
projectedTagged ps fps cps (s, x) = map (\d => (d, x)) (drawnProjected ps fps cps s)

||| What K stands above for a site: its template's own height.
public export
siteNeeds : (Site n, tag) -> List Nat
siteNeeds (s, x) = [height s.template]

||| Every site's arcs as drawn, each with what tags it: each site's own,
||| then each site's from what applied families give, fields and choices.
public export
drawn : (Address -> List (Fin n)) -> (Address -> Nat -> List (Fin n)) -> (ChoiceHead -> List (Fin n)) ->
        List (Site n, tag) -> List (Drawn n, tag)
drawn ps fps cps ss = allOf ownTagged ss ++ allOf (projectedTagged ps fps cps) ss

||| A tagged drawn arc's arc.
public export
arcOf : (Drawn n, tag) -> Arc n
arcOf e = (fst e).drawnArc

||| The graph drawn from some sites over n positions with their caps: K
||| above every site's template and above `beyond`, the templates written
||| at capped positions, which no site of the model holds.
public export
graphOf : {n : Nat} -> (Address -> List (Fin n)) -> (Address -> Nat -> List (Fin n)) -> (ChoiceHead -> List (Fin n)) ->
          (beyond : Nat) -> Vect n (Maybe Nat) -> List (Site n, tag) -> Graph
graphOf ps fps cps beyond caps ss = MkGraph n (map arcOf (drawn ps fps cps ss)) (topOf beyond (allOf siteNeeds ss)) caps

||| The model the graph is drawn from, with the program's held count.
public export
modelOf : {n : Nat} -> (ps : Address -> List (Fin n)) -> (fps : Address -> Nat -> List (Fin n)) ->
          (cps : ChoiceHead -> List (Fin n)) -> (Fin n -> Maybe (Head, Nat)) -> (held : Nat) -> (beyond : Nat) ->
          (caps : Vect n (Maybe Nat)) -> (ss : List (Site n, tag)) ->
          Model (graphOf ps fps cps beyond caps ss)
modelOf ps fps cps positionOf held beyond caps ss = MkModel (map fst ss) fps cps positionOf ps held

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

-- Arcs into a target at a label a weight has are drawn from each of the
-- positions given: stated once at the label's equation for the four kinds
-- of arc below, where the label is a variable the equation fixes, so no
-- rewrite waits on a list of arcs not yet known.
0 arcsIntoHas : {t : Fin n} -> (l : Maybe Label) -> l = Just lab -> Elem p ps -> Elem (MkArc p t lab) (arcsInto t l ps)
arcsIntoHas _ Refl el = elemMap (\q => MkArc q t lab) el

||| A parameter listed with a weight that has a label, read at a position,
||| draws an arc from there at that label.
export
0 varArcsHas : {t : Fin n} -> {ws : List (Nat, Fin n)} -> {vs : List (Nat, Weight)} ->
               Elem (i, w) vs -> Elem (i, p) ws -> labelOf w = Just lab -> Elem (MkArc p t lab) (varArcs t ws vs)
varArcsHas Here wp eq = elemAppendLeft (arcsIntoHas (labelOf w) eq (writersOfHas wp))
varArcsHas {vs = (j, v) :: rest} (There el) wp eq =
  elemAppendRight (arcsInto t (labelOf v) (writersOf j ws)) (varArcsHas el wp eq)

0 heldArcsHas : {t : Fin n} -> {ps : Address -> List (Fin n)} -> {hs : List (Address, Weighed)} ->
                Elem (j, c) hs -> Elem p (ps j) -> labelOf c.atWeight = Just lab -> Elem (MkArc p t lab) (heldArcs t ps hs)
heldArcsHas Here inJ eq = elemAppendLeft (arcsIntoHas (labelOf c.atWeight) eq inJ)
heldArcsHas {hs = (j', c') :: rest} (There el) inJ eq =
  elemAppendRight (arcsInto t (labelOf c'.atWeight) (ps j')) (heldArcsHas el inJ eq)

0 fieldArcsHas : {t : Fin n} -> {fps : Address -> Nat -> List (Fin n)} -> {fs : List ((Address, Nat), Weighed)} ->
                 Elem ((j, k), c) fs -> Elem p (fps j k) -> labelOf c.atWeight = Just lab -> Elem (MkArc p t lab) (fieldArcs t fps fs)
fieldArcsHas Here inF eq = elemAppendLeft (arcsIntoHas (labelOf c.atWeight) eq inF)
fieldArcsHas {fs = ((j', k'), c') :: rest} (There el) inF eq =
  elemAppendRight (arcsInto t (labelOf c'.atWeight) (fps j' k')) (fieldArcsHas el inF eq)

0 choiceArcsHas : {t : Fin n} -> {cps : ChoiceHead -> List (Fin n)} -> {cs : List (ChoiceHead, Weighed)} ->
                  Elem (k, c) cs -> Elem p (cps k) -> labelOf c.atWeight = Just lab -> Elem (MkArc p t lab) (choiceArcs t cps cs)
choiceArcsHas Here inC eq = elemAppendLeft (arcsIntoHas (labelOf c.atWeight) eq inC)
choiceArcsHas {cs = (k', c') :: rest} (There el) inC eq =
  elemAppendRight (arcsInto t (labelOf c'.atWeight) (cps k')) (choiceArcsHas el inC eq)

------------------------------------------------------------------------------
-- The drawing's arcs are the arcs
------------------------------------------------------------------------------

0 bothAppended : {0 xs, xs', ys, ys' : List (Arc n)} -> xs = xs' -> ys = ys' -> xs ++ ys = xs' ++ ys'
bothAppended Refl Refl = Refl

0 arcsAppend : (xs, ys : List (Drawn n)) -> map (.drawnArc) (xs ++ ys) = map (.drawnArc) xs ++ map (.drawnArc) ys
arcsAppend [] ys = Refl
arcsAppend (x :: xs) ys = cong (\r => x.drawnArc :: r) (arcsAppend xs ys)

0 drawnIntoMapped : (t : Fin n) -> (src : ArcSource) -> (c : Weighed) -> (qs : List (Fin n)) ->
                    map (.drawnArc) (drawnInto t src c qs) = map (\q => MkArc q t (passageLabel c.passage)) qs
drawnIntoMapped t src c [] = Refl
drawnIntoMapped t src c (q :: qs) = cong (\r => MkArc q t (passageLabel c.passage) :: r) (drawnIntoMapped t src c qs)

-- Arcs drawn at a weight are the arcs at its label.
0 drawnIntoArcs : (t : Fin n) -> (src : ArcSource) -> (c : Weighed) -> (qs : List (Fin n)) ->
                  map (.drawnArc) (drawnInto t src c qs) = arcsInto t (labelOf c.atWeight) qs
drawnIntoArcs t src c qs = rewrite passageLabelled c.passage in drawnIntoMapped t src c qs

0 varDrawnArcs : (t : Fin n) -> (ws : List (Nat, Fin n)) -> {0 vs : List (Nat, Weight)} -> (pv : Passages vs) ->
                 map (.drawnArc) (varDrawn t ws pv) = varArcs t ws vs
varDrawnArcs t ws NonePassed = Refl
varDrawnArcs t ws (PassedOn i p rest) =
  trans (arcsAppend (drawnInto t WriterBinds (MkWeighed _ p) (writersOf i ws)) (varDrawn t ws rest))
        (bothAppended (drawnIntoArcs t WriterBinds (MkWeighed _ p) (writersOf i ws)) (varDrawnArcs t ws rest))

0 heldDrawnArcs : (t : Fin n) -> (ps : Address -> List (Fin n)) -> (hs : List (Address, Weighed)) ->
                  map (.drawnArc) (heldDrawn t ps hs) = heldArcs t ps hs
heldDrawnArcs t ps [] = Refl
heldDrawnArcs t ps ((j, c) :: rest) =
  trans (arcsAppend (drawnInto t WriterProjects c (ps j)) (heldDrawn t ps rest))
        (bothAppended (drawnIntoArcs t WriterProjects c (ps j)) (heldDrawnArcs t ps rest))

0 fieldDrawnArcs : (t : Fin n) -> (fps : Address -> Nat -> List (Fin n)) -> (fs : List ((Address, Nat), Weighed)) ->
                   map (.drawnArc) (fieldDrawn t fps fs) = fieldArcs t fps fs
fieldDrawnArcs t fps [] = Refl
fieldDrawnArcs t fps (((j, k), c) :: rest) =
  trans (arcsAppend (drawnInto t WriterProjects c (fps j k)) (fieldDrawn t fps rest))
        (bothAppended (drawnIntoArcs t WriterProjects c (fps j k)) (fieldDrawnArcs t fps rest))

0 choiceDrawnArcs : (t : Fin n) -> (cps : ChoiceHead -> List (Fin n)) -> (cs : List (ChoiceHead, Weighed)) ->
                    map (.drawnArc) (choiceDrawn t cps cs) = choiceArcs t cps cs
choiceDrawnArcs t cps [] = Refl
choiceDrawnArcs t cps ((k, c) :: rest) =
  trans (arcsAppend (drawnInto t WriterProjects c (cps k)) (choiceDrawn t cps rest))
        (bothAppended (drawnIntoArcs t WriterProjects c (cps k)) (choiceDrawnArcs t cps rest))

0 carriedDrawnArcs : (t : Fin n) -> (ps : Address -> List (Fin n)) -> (fps : Address -> Nat -> List (Fin n)) ->
                     (cps : ChoiceHead -> List (Fin n)) -> (c : Carried) ->
                     map (.drawnArc) (carriedDrawn t ps fps cps c) =
                     heldArcs t ps c.held ++ fieldArcs t fps c.fields ++ choiceArcs t cps c.choices
carriedDrawnArcs t ps fps cps c =
  trans (arcsAppend (heldDrawn t ps c.held) (fieldDrawn t fps c.fields ++ choiceDrawn t cps c.choices))
        (bothAppended (heldDrawnArcs t ps c.held)
                    (trans (arcsAppend (fieldDrawn t fps c.fields) (choiceDrawn t cps c.choices))
                           (bothAppended (fieldDrawnArcs t fps c.fields) (choiceDrawnArcs t cps c.choices))))

||| A site's own arcs are its own arcs as drawn.
export
0 ownDrawnArcs : (s : Site n) -> map (.drawnArc) (drawnOwn s) = ownArcs s
ownDrawnArcs s = varDrawnArcs s.target s.writers (weightPassages s.template)

||| A site's projected arcs are its projected arcs as drawn.
export
0 projectedDrawnArcs : (ps : Address -> List (Fin n)) -> (fps : Address -> Nat -> List (Fin n)) ->
                       (cps : ChoiceHead -> List (Fin n)) -> (s : Site n) ->
                       map (.drawnArc) (drawnProjected ps fps cps s) = projectedArcs ps fps cps s
projectedDrawnArcs ps fps cps s = carriedDrawnArcs s.target ps fps cps (carriedAt s.roots atTop s.template)

-- An arc of a drawing is a drawn arc's.
0 drawnHas : {ds : List (Drawn n)} -> Elem a (map (.drawnArc) ds) -> (d : Drawn n ** (Elem d ds, d.drawnArc = a))
drawnHas {ds = []} el = absurd el
drawnHas {ds = d :: _} Here = (d ** (Here, Refl))
drawnHas {ds = _ :: _} (There el) = let (d ** (inD, same)) = drawnHas el in (d ** (There inD, same))

-- An own arc of a site the graph is drawn from is the graph's.
0 ownInGraph : {ps : Address -> List (Fin n)} -> {fps : Address -> Nat -> List (Fin n)} ->
               {cps : ChoiceHead -> List (Fin n)} -> {ss : List (Site n, tag)} -> {s : Site n} -> {x : tag} ->
               Elem (s, x) ss -> Elem a (ownArcs s) -> Elem a (map Describes.arcOf (drawn ps fps cps ss))
ownInGraph {a} inSs el = case drawnHas (replace {p = Elem a} (sym (ownDrawnArcs s)) el) of
  (d ** (inD, same)) =>
    replace {p = \b => Elem b (map arcOf (drawn ps fps cps ss))} same
            (elemMap arcOf (elemAppendLeft (allOfHas ownTagged inSs (elemMap (\d' => (d', x)) inD))))

-- A projected arc of a site the graph is drawn from is the graph's.
0 projectedInGraph : {ps : Address -> List (Fin n)} -> {fps : Address -> Nat -> List (Fin n)} ->
                     {cps : ChoiceHead -> List (Fin n)} -> {ss : List (Site n, tag)} -> {s : Site n} -> {x : tag} ->
                     Elem (s, x) ss -> Elem a (projectedArcs ps fps cps s) -> Elem a (map Describes.arcOf (drawn ps fps cps ss))
projectedInGraph {a} inSs el = case drawnHas (replace {p = Elem a} (sym (projectedDrawnArcs ps fps cps s)) el) of
  (d ** (inD, same)) =>
    replace {p = \b => Elem b (map arcOf (drawn ps fps cps ss))} same
            (elemMap arcOf (elemAppendRight (allOf ownTagged ss)
                                            (allOfHas (projectedTagged ps fps cps) inSs (elemMap (\d' => (d', x)) inD))))

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
  -- marker, field or member of a choice, and no family applied.
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
  selfBoundedIs (Member _) eq = absurd eq

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
  stuckOnly (Member _) el = absurd el
  stuckOnly (Formal _ _) el = absurd el

  0 stuckOnlyIn : (ts : List Template) -> Elem (i, w) (stuckIn ts) -> w = Stuck
  stuckOnlyIn [] el = absurd el
  stuckOnlyIn (t :: ts) el = case appendElem (stuck t) el of
    Left here => stuckOnly t here
    Right rest => stuckOnlyIn ts rest

------------------------------------------------------------------------------
-- Weights
------------------------------------------------------------------------------

||| Only Stuck dominates Stuck.
export
0 overStuck : Dominates w Stuck -> w = Stuck
overStuck OverAll = Refl

0 headOver : {d : Nat} -> Dominates w (Finite (S d) 0) -> Dominates (plus w (Finite 1 0)) (Finite (S (S d)) 0)
headOver dom = overAs (cong S (plusCommutative d 1)) Refl (plusOver dom (dominatesSelf (Finite 1 0)))

-- A field's or a member's arc, a level above an implementation's arguments.
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

0 drawnCarries : {g : Graph} -> {s : Site g.size} -> {pot : Vect g.size Nat} -> {0 p : Fin g.size} -> Feasible g pot ->
                 DrawnOver g s i (Finite e d) -> Elem (i, p) s.writers -> Carries g p d e s.target
drawnCarries fe (w ** (dom, arcs)) wa = case dom of
  OverAll => void (measuredOnly fe (arcs _ wa Unmeasured Refl))
  Over {g = gain} {l = loss} le => MkCarries (arcs _ wa (Measured gain loss) Refl) le

0 stuckRefuted : {g : Graph} -> {s : Site g.size} -> {pot : Vect g.size Nat} -> {0 p : Fin g.size} -> Feasible g pot ->
                 DrawnOver g s i Stuck -> Elem (i, p) s.writers -> Void
stuckRefuted fe (w ** (dom, arcs)) wa = case overStuck dom of
  Refl => measuredOnly fe (arcs _ wa Unmeasured Refl)

||| A parameter a site's template weighs Stuck is read at no position of
||| its writer's, in a feasible graph that holds the site's own arcs: the
||| arc from such a position is Unmeasured, which no potential meets.
export
0 stuckUnread : {g : Graph} -> {pot : Vect g.size Nat} -> {0 p : Fin g.size} -> Feasible g pot -> (s : Site g.size) ->
                ((a : Arc g.size) -> Elem a (ownArcs s) -> Elem a g.arcs) ->
                Elem (i, Stuck) (weights s.template) -> Elem (i, p) s.writers -> Void
stuckUnread fe s own inW wa = measuredOnly fe (own _ (varArcsHas inW wa Refl))

-- An arc from what an applied family, a field or a member can
-- be, as heavy as the part sits deep less the depth of what it carries.
0 rootCarries : {g : Graph} -> {pot : Vect g.size Nat} -> {0 p, t : Fin g.size} -> Feasible g pot -> Dominates w (Finite e 0) ->
                ((lab : Label) -> labelOf w = Just lab -> Elem (MkArc p t lab) g.arcs) -> Carries g p 0 e t
rootCarries fe OverAll arc = void (measuredOnly fe (arc Unmeasured Refl))
rootCarries fe (Over {g = gain} {l = loss} le) arc = MkCarries (arc (Measured gain loss) Refl) le

-- An applied family's own marker, by whether its arguments are closed.
-- The weight is the family's own (`appliedWeight`), split on the test it
-- is written with: a test written again here would be a case function of
-- its own, which no proof unifies with the weight's.
0 appliedCarries : {g : Graph} -> {s : Site g.size} -> {pot : Vect g.size Nat} -> {0 p : Fin g.size} -> Feasible g pot ->
                   (e, d : Nat) -> (ts : List Template) -> DrawnOver g s j (appliedWeight e d ts) ->
                   Elem (j, p) s.writers ->
                   (Carries g p d (e + tallest ts) s.target, AllUnmarked ts)
appliedCarries fe e d ts drawn wa with (allSelfBounded ts) proof closed
  _ | True = (drawnCarries fe drawn wa, allSelfBoundedAre ts closed)
  _ | False = void (stuckRefuted fe drawn wa)

-- What a site's carried parts draw, as the graph holds it.
record Drawing (g : Graph) (m : Model g) (s : Site g.size) (whole : Carried) where
  constructor MkDrawing
  0 projections : (a : Arc g.size) -> Elem a (heldArcs s.target m.positionsOf whole.held) -> Elem a g.arcs
  0 fielded : (a : Arc g.size) -> Elem a (fieldArcs s.target m.fieldPositions whole.fields) -> Elem a g.arcs
  0 chosen : (a : Arc g.size) -> Elem a (choiceArcs s.target m.choicePositions whole.choices) -> Elem a g.arcs

-- What a part carries is among what the whole site carries.
record Part (c : Carried) (whole : Carried) where
  constructor MkPart
  0 partFields : (x : ((Address, Nat), Weighed)) -> Elem x c.fields -> Elem x whole.fields
  0 partHeld : (x : (Address, Weighed)) -> Elem x c.held -> Elem x whole.held
  0 partChoices : (x : (ChoiceHead, Weighed)) -> Elem x c.choices -> Elem x whole.choices

-- A list's first template carries a part of what the list does.
0 firstPart : (rts : Template -> List Address) -> (at : Depth) -> (t : Template) -> (ts : List Template) ->
              Part (carriedAll rts at (t :: ts)) whole -> Part (carriedAt rts at t) whole
firstPart rts at t ts p =
  MkPart (\a, el => p.partFields a (elemAppendLeft el))
         (\a, el => p.partHeld a (elemAppendLeft el))
         (\a, el => p.partChoices a (elemAppendLeft el))

-- And the rest of the list.
0 restPart : (rts : Template -> List Address) -> (at : Depth) -> (t : Template) -> (ts : List Template) ->
             Part (carriedAll rts at (t :: ts)) whole -> Part (carriedAll rts at ts) whole
restPart rts at t ts p =
  MkPart (\a, el => p.partFields a (elemAppendRight (carriedAt rts at t).fields el))
         (\a, el => p.partHeld a (elemAppendRight (carriedAt rts at t).held el))
         (\a, el => p.partChoices a (elemAppendRight (carriedAt rts at t).choices el))

-- The arcs from what an applied family can give.
0 rootsCarried : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> Feasible g pot ->
                 {s : Site g.size} -> {whole : Carried} -> Drawing g m s whole ->
                 (at : Depth) -> Dominates at.arcWeight (Finite (S at.depth) 0) -> (t : Template) ->
                 ((x : (Address, Weighed)) -> Elem x (heldRoots s.roots at t) -> Elem x whole.held) ->
                 (j : Address) -> Elem j (s.roots t) -> (p' : Fin g.size) -> Elem p' (m.positionsOf j) ->
                 Carries g p' 0 (S at.depth) s.target
rootsCarried fe dr at aw t held j el p' inJ =
  rootCarries fe aw (\lab, eq => dr.projections _ (heldArcsHas (held _ (elemMap (\x => (x, weighedAt at)) el)) inJ eq))

-- The arcs from a field's position of each implementation its record can
-- be.
0 fieldsCarried : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> Feasible g pot ->
                  {s : Site g.size} -> {whole : Carried} -> Drawing g m s whole ->
                  (at : Depth) -> Dominates at.arcWeight (Finite (S at.depth) 0) -> (k : Nat) -> (rec : Template) ->
                  ((x : ((Address, Nat), Weighed)) -> Elem x (fieldRoots s.roots at k rec) -> Elem x whole.fields) ->
                  (j : Address) -> Elem j (s.roots rec) -> (p : Fin g.size) -> Elem p (m.fieldPositions j k) ->
                  Carries g p 0 at.depth s.target
fieldsCarried fe dr at aw k rec fields j el p inField =
  rootCarries fe (fieldOver aw)
    (\lab, eq => dr.fielded _ (fieldArcsHas (fields _ (elemMap (\x => ((x, k), fieldWeighed at)) el)) inField eq))

-- The arcs from the position of the choice a member is read from.
0 choicesCarried : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> Feasible g pot ->
                   {s : Site g.size} -> {whole : Carried} -> Drawing g m s whole ->
                   (at : Depth) -> Dominates at.arcWeight (Finite (S at.depth) 0) -> (k : ChoiceHead) ->
                   ((x : (ChoiceHead, Weighed)) -> Elem x [(k, fieldWeighed at)] -> Elem x whole.choices) ->
                   (p : Fin g.size) -> Elem p (m.choicePositions k) -> Carries g p 0 at.depth s.target
choicesCarried fe dr at aw k chosen p inChoice =
  rootCarries fe (fieldOver aw) (\lab, eq => dr.chosen _ (choiceArcsHas (chosen _ Here) inChoice eq))

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

-- What a recursion's arguments answer for is Stuck, whatever their depth:
-- the depth is stated as theirs, a level down, so the part's own fixes it.
0 opaqueAnswered : (r : Reading) -> Answered g s r e (Opaque a ts) -> AnsweredIn g s UnderComputation (S e) ts
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
    COpaque (coverAll fe dr UnderComputation (underComputation (StuckRecursion a) at) OverAll ts (opaqueAnswered r ans) part)
  coverAt fe dr r at aw (Choice c ls) ans part =
    CChoice (coverAll fe dr r at aw ls (choiceAnswered r ans) part)
  coverAt fe dr r at aw (Leaf h) ans part = CLeaf
  coverAt fe dr r at aw (Token h) ans part = CToken
  coverAt fe dr r at aw (Formal j k) ans part = CFormal
  coverAt fe dr AtDepth at aw (Applied j d ts) ans part =
    CApplied (\p, wa => appliedCarries fe at.depth d ts (ans j (appliedWeight at.depth d ts) Here) wa)
             (rootsCarried fe dr at aw (Applied j d ts) (\x, el => part.partHeld x (elemAppendLeft el)))
  coverAt fe dr UnderComputation at aw (Applied j d ts) ans part =
    CApplied (\p, wa => void (stuckRefuted fe (ans j Stuck Here) wa))
             (rootsCarried fe dr at aw (Applied j d ts) (\x, el => part.partHeld x (elemAppendLeft el)))
  coverAt fe dr AtDepth at aw (Computing j d ts) ans part =
    CComputing (\p, wa => stuckRefuted fe (ans j Stuck Here) wa)
  coverAt fe dr UnderComputation at aw (Computing j d ts) ans part =
    CComputing (\p, wa => stuckRefuted fe (ans j Stuck Here) wa)
  coverAt fe dr r at aw (Member k) ans part =
    CMember (choicesCarried fe dr at aw k (\x, el => part.partChoices x el))
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

-- The graph covers a site whose arcs it holds.
0 siteCovered : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> Feasible g pot -> (s : Site g.size) ->
                ((a : Arc g.size) -> Elem a (ownArcs s) -> Elem a g.arcs) ->
                ((a : Arc g.size) -> Elem a (projectedArcs m.positionsOf m.fieldPositions m.choicePositions s) -> Elem a g.arcs) ->
                CoveredAt m s 0 s.template
siteCovered {m} fe s own projected =
  coverAt {whole = carriedAt s.roots atTop s.template} fe
          (MkDrawing (\a, el => projected a (elemAppendLeft el))
                     (\a, el => projected a (elemAppendRight (heldArcs s.target m.positionsOf (carriedAt s.roots atTop s.template).held)
                                                              (elemAppendLeft el)))
                     (\a, el => projected a (elemAppendRight (heldArcs s.target m.positionsOf (carriedAt s.roots atTop s.template).held)
                                                              (elemAppendRight (fieldArcs s.target m.fieldPositions
                                                                                          (carriedAt s.roots atTop s.template).fields)
                                                                               el))))
          AtDepth atTop (dominatesSelf (Finite 1 0)) s.template
          (\i, w, el => case weightsCover s.template el of
             (v ** (inW, dom)) => (v ** (dom, \p, wa, lab, leq => own _ (varArcsHas inW wa leq))))
          (MkPart (\x, el => el) (\x, el => el) (\x, el => el))

------------------------------------------------------------------------------
-- Sites that draw measured arcs only
------------------------------------------------------------------------------

||| A template that draws measured arcs only, wherever it is written: every
||| weight of its parameters is measured, and it carries no field, member
||| of a choice or applied family, whose arcs its roots and the positions
||| would draw.
public export
record DrawsMeasured (t : Template) where
  constructor MkDrawsMeasured
  0 weighed : All (\x => MeasuredWeight (snd x)) (weights t)
  0 noFields : (rts : Template -> List Address) -> (at : Depth) -> (carriedAt rts at t).fields = []
  0 noHeld : (rts : Template -> List Address) -> (at : Depth) -> (carriedAt rts at t).held = []
  0 noChoices : (rts : Template -> List Address) -> (at : Depth) -> (carriedAt rts at t).choices = []

-- An arc into a target at a label has that label.
0 intoLabel : {l : Maybe Label} -> {ps : List (Fin n)} -> Elem a (arcsInto t l ps) -> l = Just a.label
intoLabel {l = Nothing} el = absurd el
intoLabel {l = Just lab} {ps = []} el = absurd el
intoLabel {l = Just lab} {ps = p :: rest} Here = Refl
intoLabel {l = Just lab} {ps = p :: rest} (There el) = intoLabel el

-- An arc of a parameter has the label of that parameter's weight.
0 varArcsLabel : {vs : List (Nat, Weight)} -> Elem a (varArcs t ws vs) ->
                 (iw : (Nat, Weight) ** (Elem iw vs, labelOf (snd iw) = Just a.label))
varArcsLabel {vs = []} el = absurd el
varArcsLabel {vs = (i, w) :: rest} el = case appendElem (arcsInto t (labelOf w) (writersOf i ws)) el of
  Left here => ((i, w) ** (Here, intoLabel here))
  Right there => let (iw ** (inner, lab)) = varArcsLabel there in (iw ** (There inner, lab))

0 justSame : Just x = Just y -> x = y
justSame Refl = Refl

-- A site's own arc, where every weight of its template is measured, is
-- finite.
0 ownMeasured : (s : Site n) -> DrawsMeasured s.template -> Elem a (ownArcs s) -> IsFinite a.label
ownMeasured s m el = case varArcsLabel el of
  (iw ** (inW, lab)) => case measuredArc (indexAll inW m.weighed) of
    (l ** (drawnAs, finite)) => rewrite sym (justSame (trans (sym drawnAs) lab)) in finite

-- A site whose template carries nothing projects no arc.
0 noneProjected : (s : Site n) -> DrawsMeasured s.template -> Elem a (projectedArcs ps fps cps s) -> Void
noneProjected s m el =
  let held = m.noHeld s.roots atTop
      fields = m.noFields s.roots atTop
      choices = m.noChoices s.roots atTop in
  case appendElem (heldArcs s.target ps (carriedAt s.roots atTop s.template).held) el of
    Left inHeld => absurd (replace {p = \hs => Elem a (heldArcs s.target ps hs)} held inHeld)
    Right rest => case appendElem (fieldArcs s.target fps (carriedAt s.roots atTop s.template).fields) rest of
      Left inFields => absurd (replace {p = \fs => Elem a (fieldArcs s.target fps fs)} fields inFields)
      Right inChoices => absurd (replace {p = \cs => Elem a (choiceArcs s.target cps cs)} choices inChoices)

-- A tagged drawn arc is one tagging a list of them: it is one of them,
-- and its tag the list's.
0 untagged : {bs : List (Drawn n)} -> Elem e (map (\c => (c, y)) bs) -> (snd e = y, Elem (fst e) bs)
untagged {bs = []} el = absurd el
untagged {bs = c :: cs} Here = (Refl, Here)
untagged {bs = c :: cs} (There el) = let (same, inner) = untagged el in (same, There inner)

-- A drawn arc of every site's list comes from one of the sites.
0 fromSome : (f : (Site n, tag) -> List (Drawn n, tag)) -> (ss : List (Site n, tag)) -> Elem e (allOf f ss) ->
             (y : (Site n, tag) ** (Elem y ss, Elem e (f y)))
fromSome f [] el = absurd el
fromSome f (y :: ys) el = case appendElem (f y) el of
  Left here => (y ** (Here, here))
  Right there => let (z ** (inZ, at)) = fromSome f ys there in (z ** (There inZ, at))

||| An arc drawn from sites, with its tag, where every site whose tag
||| satisfies a property has a template that draws measured arcs only: an
||| arc whose tag satisfies it is finite. A site draws its own arcs and
||| what its carried parts project, each tagged as the site is, and such a
||| site projects none. The arc's tag is the site's, and the property is
||| carried across that equation to the site's tag.
export
0 measuredDrawn : {ps : Address -> List (Fin n)} -> {fps : Address -> Nat -> List (Fin n)} ->
                  {cps : ChoiceHead -> List (Fin n)} -> {ss : List (Site n, tag)} -> (p : tag -> Type) ->
                  ((s : Site n) -> (x : tag) -> Elem (s, x) ss -> p x -> DrawsMeasured s.template) ->
                  Elem e (drawn ps fps cps ss) -> p (snd e) -> IsFinite (fst e).drawnArc.label
measuredDrawn p measured el px = case appendElem (allOf ownTagged ss) el of
  Left own => case fromSome ownTagged ss own of
    ((s, y) ** (inSs, tagged)) => case untagged tagged of
      (same, inOwn) =>
        ownMeasured s (measured s y inSs (replace {p} same px))
                    (replace {p = Elem (fst e).drawnArc} (ownDrawnArcs s) (elemMap (.drawnArc) inOwn))
  Right projected => case fromSome (projectedTagged ps fps cps) ss projected of
    ((s, y) ** (inSs, tagged)) => case untagged tagged of
      (same, inProjected) =>
        void (noneProjected s (measured s y inSs (replace {p} same px))
                            (replace {p = Elem (fst e).drawnArc} (projectedDrawnArcs ps fps cps s)
                                     (elemMap (.drawnArc) inProjected)))

||| A marker alone draws measured arcs only: a held value written as
||| itself, a leading arc's parameter passed on unchanged.
export
0 markerMeasured : (i, d : Nat) -> DrawsMeasured (Var i d)
markerMeasured i d = MkDrawsMeasured [MeasuredBy] (\_, _ => Refl) (\_, _ => Refl) (\_, _ => Refl)

-- A chain of pairs carries nothing: pairs and a marker under them.
0 chainCarriesNothing : (pa : Address) -> (n : Nat) -> (rts : Template -> List Address) -> (at : Depth) ->
                        ( (carriedAt rts at (pairChain pa n)).fields = []
                        , (carriedAt rts at (pairChain pa n)).held = []
                        , (carriedAt rts at (pairChain pa n)).choices = [] )
chainCarriesNothing pa Z rts at = (Refl, Refl, Refl)
chainCarriesNothing pa (S n) rts at =
  let (f, h, c) = chainCarriesNothing pa n rts (underHead at) in
  (cong (\l => l ++ []) f, cong (\l => l ++ []) h, cong (\l => l ++ []) c)

||| A chain of pairs that packs held values draws measured arcs only
||| (`Proof.Held.chainMeasured`).
export
0 chainDrawsMeasured : (pa : Address) -> (n : Nat) -> DrawsMeasured (pairChain pa n)
chainDrawsMeasured pa n =
  MkDrawsMeasured (chainMeasured pa n)
             (\rts, at => fst (chainCarriesNothing pa n rts at))
             (\rts, at => fst (snd (chainCarriesNothing pa n rts at)))
             (\rts, at => snd (snd (chainCarriesNothing pa n rts at)))

0 listedChain : (pa : Address) -> (m : Nat) -> Elem t (pairChainsUpTo pa m) -> (n : Nat ** t = pairChain pa n)
listedChain pa Z el = absurd el
listedChain pa (S m) Here = (S m ** Refl)
listedChain pa (S m) (There el) = listedChain pa m el

||| Every chain a holder's pairs are given draws measured arcs only: what
||| a writing of held values in pairs writes (`Graph.packingTemplate`).
export
0 listedMeasured : (pa : Address) -> (m : Nat) -> Elem t (pairChainsUpTo pa m) -> DrawsMeasured t
listedMeasured pa m el = case listedChain pa m el of
  (n ** Refl) => chainDrawsMeasured pa n

-- A site of a model drawn from tagged sites is one of them, with its tag.
0 taggedSite : {ss : List (Site n, tag)} -> Elem s (map Builtin.fst ss) -> (x : tag ** Elem (s, x) ss)
taggedSite {ss = []} el = absurd el
taggedSite {ss = (s', x) :: rest} Here = (x ** Here)
taggedSite {ss = y :: rest} (There el) = let (x ** inner) = taggedSite el in (x ** There inner)

||| A graph drawn from a model's sites holds each site's own arcs, the arcs
||| from the positions its writer reads its parameters at.
export
0 ownDrawnOf : {n : Nat} -> {ps : Address -> List (Fin n)} -> {fps : Address -> Nat -> List (Fin n)} ->
               {cps : ChoiceHead -> List (Fin n)} -> {positionOf : Fin n -> Maybe (Head, Nat)} -> {held : Nat} ->
               {beyond : Nat} -> {caps : Vect n (Maybe Nat)} -> {ss : List (Site n, tag)} -> {0 s : Site n} ->
               Elem s (modelOf ps fps cps positionOf held beyond caps ss).sites ->
               (a : Arc n) -> Elem a (ownArcs s) -> Elem a (graphOf ps fps cps beyond caps ss).arcs
ownDrawnOf inModel a el = case taggedSite inModel of
  (x ** inSs) => ownInGraph {ps} {fps} {cps} {ss} inSs el

-- A site's template's height is among what K stands above. The site is
-- matched here, so the list it heads is its own, a height alone.
0 heightNeeded : {ss : List (Site n, tag)} -> Elem (s, x) ss -> Elem (height s.template) (allOf Describes.siteNeeds ss)
heightNeeded Here = Here
heightNeeded {ss = y :: _} (There el) = elemAppendRight (siteNeeds y) (heightNeeded el)

||| A graph drawn from a model's sites describes the model under any
||| feasible potential: every site lands at an uncapped position, K stands
||| above its template, and the graph covers every part of it, each Stuck
||| arc being one no feasible potential satisfies.
export
0 describes : {n : Nat} -> (ps : Address -> List (Fin n)) -> (fps : Address -> Nat -> List (Fin n)) ->
              (cps : ChoiceHead -> List (Fin n)) -> (positionOf : Fin n -> Maybe (Head, Nat)) -> (held : Nat) ->
              (beyond : Nat) -> (caps : Vect n (Maybe Nat)) ->
              (ss : List (Site n, tag)) -> All (\x => index (fst x).target caps = Nothing) ss ->
              {pot : Vect n Nat} -> Feasible (graphOf ps fps cps beyond caps ss) pot ->
              Describes (modelOf ps fps cps positionOf held beyond caps ss)
describes ps fps cps positionOf held beyond caps ss uncapped fe = sitesCovered ss uncapped (\y, el => el)
  where
    -- K stands above every site's template.
    0 needed : (s : Site n) -> (x : tag) -> Elem (s, x) ss ->
               LTE (height s.template) (topOf beyond (allOf Describes.siteNeeds ss))
    needed s x here = aboveAll beyond (allOf siteNeeds ss) (heightNeeded here)

    0 sitesCovered : (rest : List (Site n, tag)) -> All (\x => index (fst x).target caps = Nothing) rest ->
                     ((y : (Site n, tag)) -> Elem y rest -> Elem y ss) ->
                     All (Covers (graphOf ps fps cps beyond caps ss) (modelOf ps fps cps positionOf held beyond caps ss)) (map Builtin.fst rest)
    sitesCovered [] [] _ = []
    sitesCovered ((s, x) :: rest) (u :: us) sub =
      MkCovers u (needed s x (sub (s, x) Here))
               (siteCovered fe s
                  (\a, el => ownInGraph {ps} {fps} {cps} {ss} (sub (s, x) Here) el)
                  (\a, el => projectedInGraph {ps} {fps} {cps} {ss} (sub (s, x) Here) el))
      :: sitesCovered rest us (\y, el => sub y (There el))
