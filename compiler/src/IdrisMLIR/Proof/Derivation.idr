-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What a request carries so that the worklist need not test it, and the
||| proof that it places the request in the universe of requests.
|||
||| A static argument of a request lands at a position of the growth graph.
||| Its reading there is a value of V (`Proof.Bound.InV`) because a site of
||| the model into the position writes it (`SiteWrites`): what the instance
||| that requests writes where the site's template reads. Its written key
||| weighs at most what `sizeWithin` lets a key as high as the reading
||| weigh, at the universe's arity and heaviest token (`ArgumentDerivation`,
||| which `Template.keyedWithin` gives from the argument's instance reading,
||| whose template is never smaller than the key its link writes). Where the universe
||| bounds the parameter at least as high as the position's bound
||| (`ArgumentWithin`), Theorem 1 (`Proof.Bound.bounded`) and the growth of
||| `sizeWithin` (`Proof.Sizes.sizeWithinMono`) place the argument within
||| it, and a link all of whose arguments are placed, no longer than the
||| breadth, is in the universe (`derivedInside`): the membership the
||| worklist's test of each request gives it.
|||
||| Every way the translation requests an instance gives its arguments
||| through sites of the model (`sitePlaced`). A held dispatch's arm is one
||| (`HeldArmWritten`): the implementation given at the dispatched
||| parameter, its field the running program chose fixed to a member, is
||| written by a site whose template reads that field as a member of the
||| choice (`Member`), which the place that made the member wrote at the
||| choice's positions, its holes renumbered as the arm holds them.
|||
||| Every proof is erased and total, and nothing here runs.
module IdrisMLIR.Proof.Derivation

import IdrisMLIR.Proof.Bound
import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Sizes
import IdrisMLIR.Proof.Template

import Control.Relation
import Data.List.Elem
import Data.Nat

%default total

------------------------------------------------------------------------------
-- What a site writes
------------------------------------------------------------------------------

||| A site of the model into a position, and what the instance that requests
||| writes where the site's template reads: the value the position is given.
public export
0 SiteWrites : {g : Graph} -> Model g -> Fin g.size -> Template -> Type
SiteWrites {g} m p w = (s : Site g.size ** (Elem s m.sites, s.target = p, Writes m s s.template w))

||| What a site of the model writes at a position is a value of V there.
export
0 siteGives : {g : Graph} -> {m : Model g} -> {p : Fin g.size} -> SiteWrites m p w -> InV m p w
siteGives (s ** (el, at, wr)) = replace {p = \q => InV m q w} at (Reduced s el wr)

------------------------------------------------------------------------------
-- What a request carries
------------------------------------------------------------------------------

||| One keyed argument of a request, derived: the position of the growth
||| graph it lands at, its reading there, a value of V, and its written key,
||| weighing `keySize`, no heavier than `sizeWithin` lets a key as high as
||| the reading weigh at the universe's arity and heaviest token.
public export
record ArgumentDerivation {g : Graph} (m : Model g) (b : Bounds) (keySize : Nat) where
  constructor MkArgumentDerivation
  0 position : Fin g.size
  0 reading : Template
  0 inV : InV m position reading
  0 keyed : LTE keySize (sizeWithin b.arity (height reading) b.heaviest)

||| An argument of a link placed within its parameter's height h in the
||| universe: one that keys nothing weighs nothing; a keyed one is derived,
||| and the bound of the position it lands at is within h.
public export
data ArgumentWithin : {0 form : Type} -> {g : Graph} -> Model g -> Vect g.size Nat -> Bounds ->
                      Maybe (Written form) -> Nat -> Type where
  KeysNothing : {0 form : Type} -> {0 g : Graph} -> {0 m : Model g} -> {0 pot : Vect g.size Nat} -> {0 b : Bounds} ->
                {0 h : Nat} -> ArgumentWithin {form} m pot b Nothing h
  Keyed : {0 form : Type} -> {0 g : Graph} -> {0 m : Model g} -> {0 pot : Vect g.size Nat} -> {0 b : Bounds} ->
          {0 h : Nat} -> {0 w : Written form} ->
          (0 d : ArgumentDerivation m b w.size) -> (0 _ : LTE (bound g pot d.position) h) ->
          ArgumentWithin m pot b (Just w) h

||| Every argument of a link placed within its parameter's height, the
||| heights padded with 0 past their end as the universe pads them
||| (`Proof.Requests.padded`).
public export
data ArgumentsWithin : {0 form : Type} -> {g : Graph} -> Model g -> Vect g.size Nat -> Bounds ->
                       List (Maybe (Written form)) -> List Nat -> Type where
  NoArguments : {0 form : Type} -> {0 g : Graph} -> {0 m : Model g} -> {0 pot : Vect g.size Nat} -> {0 b : Bounds} ->
                {0 hs : List Nat} -> ArgumentsWithin {form} m pot b [] hs
  AtHeight : {0 form : Type} -> {0 g : Graph} -> {0 m : Model g} -> {0 pot : Vect g.size Nat} -> {0 b : Bounds} ->
             {0 a : Maybe (Written form)} -> {0 as : List (Maybe (Written form))} -> {0 h : Nat} -> {0 hs : List Nat} ->
             ArgumentWithin m pot b a h -> ArgumentsWithin m pot b as hs ->
             ArgumentsWithin m pot b (a :: as) (h :: hs)
  PastHeights : {0 form : Type} -> {0 g : Graph} -> {0 m : Model g} -> {0 pot : Vect g.size Nat} -> {0 b : Bounds} ->
                {0 a : Maybe (Written form)} -> {0 as : List (Maybe (Written form))} ->
                ArgumentWithin m pot b a 0 -> ArgumentsWithin m pot b as [] ->
                ArgumentsWithin m pot b (a :: as) []

||| What a request carries for the worklist, none of it paid for: the growth
||| check's graph, its model and potential, that the potential is feasible
||| and the graph describes the model, and the request's link no longer than
||| the breadth, every argument of it placed within its height.
public export
record RequestDerivation {0 form : Type} (b : Bounds) (l : Link form) where
  constructor MkRequestDerivation
  0 graph : Graph
  0 model : Model graph
  0 potential : Vect graph.size Nat
  0 described : Describes model
  0 feasible : Feasible graph potential
  0 short : LTE (length l.arguments) b.breadth
  0 placed : ArgumentsWithin model potential b l.arguments (b.heightAt l.head)

------------------------------------------------------------------------------
-- The universe, derived
------------------------------------------------------------------------------

-- An argument placed within its parameter's height weighs within what
-- `sizeWithin` gives that height: its reading is within its position's
-- bound (Theorem 1), and that bound within the height.
0 argumentSized : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> {b : Bounds} ->
                  Describes m -> Feasible g pot -> ArgumentWithin m pot b a h ->
                  LTE (argumentSize a) (sizeWithin b.arity h b.heaviest)
argumentSized ds fe KeysNothing = LTEZero
argumentSized ds fe (Keyed d under) =
  transitive d.keyed
    (sizeWithinMono {a = b.arity} {a' = b.arity} {h = height d.reading} {h' = h} {e = b.heaviest} {e' = b.heaviest}
                    reflexive (transitive (bounded ds fe d.inV) under) reflexive)

-- Every argument of a link placed within its height weighs within what
-- `sizeWithin` gives its height, the heights padded as the universe pads
-- them.
0 argumentsSized : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> {b : Bounds} ->
                   Describes m -> Feasible g pot -> (as : List (Maybe (Written form))) -> (hs : List Nat) ->
                   ArgumentsWithin m pot b as hs ->
                   Pointwise (map argumentSize as)
                             (map (\h => sizeWithin b.arity h b.heaviest) (padded (length as) hs))
argumentsSized ds fe [] hs NoArguments = []
argumentsSized ds fe (a :: as) (h :: hs) (AtHeight x rest) = argumentSized ds fe x :: argumentsSized ds fe as hs rest
argumentsSized ds fe (a :: as) [] (PastHeights x rest) = argumentSized ds fe x :: argumentsSized ds fe as [] rest

||| A link all of whose arguments are placed within their heights, no
||| longer than the breadth, is in the universe: what the worklist's test of
||| a request gives it.
export
0 derivedInside : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} ->
                  (forms : Listed form) -> (names : Listed Address) -> (b : Bounds) -> (l : Link form) ->
                  Describes m -> Feasible g pot -> LTE (length l.arguments) b.breadth ->
                  ArgumentsWithin m pot b l.arguments (b.heightAt l.head) -> InUniverse forms names b l
derivedInside forms names b l ds fe short args =
  let sized = argumentsSized ds fe l.arguments (b.heightAt l.head) args in
  MkIn short sized (inUniverse forms names b l short sized)

||| A derived request is in the universe.
export
0 requestInside : {0 form : Type} -> {b : Bounds} -> {l : Link form} ->
                  (forms : Listed form) -> (names : Listed Address) -> RequestDerivation b l -> InUniverse forms names b l
requestInside forms names r = derivedInside forms names b l r.described r.feasible r.short r.placed

------------------------------------------------------------------------------
-- Placing an argument by its site
------------------------------------------------------------------------------

||| A keyed argument a site of the model writes at its position, its key no
||| heavier than its reading lets it weigh, and its position's bound within
||| its parameter's height: placed. Every kind of request places its
||| arguments so, by the sites its kind has.
export
0 sitePlaced : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> {b : Bounds} -> {0 w : Written form} ->
               (p : Fin g.size) -> (v : Template) -> SiteWrites m p v ->
               LTE w.size (sizeWithin b.arity (height v) b.heaviest) -> LTE (bound g pot p) h ->
               ArgumentWithin m pot b (Just w) h
sitePlaced p v written keyed under = Keyed (MkArgumentDerivation p v (siteGives written) keyed) under

------------------------------------------------------------------------------
-- A held dispatch
------------------------------------------------------------------------------

||| What the sites of a held dispatch give each arm it requests. The arm is
||| the callee's instance given, at the dispatched parameter, the
||| implementation with the field the running program chose fixed to a
||| member of that field's choice, of head k: read there, `argument`, at the
||| arm's position there, `arm`; the member as the arm holds it, `member`,
||| its holes renumbered after the ones the arm holds already. Wherever the
||| place that made the member wrote it, at one of the choice's positions,
||| as it made it (`made'`), a site into the arm's position writes the
||| arm's argument: the site's template reads the field as a member of the
||| choice (`Member k`), which `Writes.AtMember` reads from that position up
||| to the renumbering, none past the held count (`Proof.Held.holeWithin`),
||| and every other part as the implementation is written.
public export
0 HeldArmWritten : {g : Graph} -> Model g -> ChoiceHead -> (arm : Fin g.size) -> (member, argument : Template) -> Type
HeldArmWritten {g} m k arm member argument =
  (made : Fin g.size) -> Elem made (m.choicePositions k) -> (made' : Template) -> InV m made made' ->
  Renumbered m.heldCount made' member -> SiteWrites m arm argument

||| A held dispatch's arm, placed: the member, as it was made, is a value of
||| V where it was made, its sites then write the arm's argument, and that
||| is placed as every other request's is.
export
0 heldArmPlaced : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> {b : Bounds} -> {0 w : Written form} ->
                  (k : ChoiceHead) -> (arm : Fin g.size) -> (member, argument : Template) ->
                  HeldArmWritten m k arm member argument ->
                  (made : Fin g.size) -> Elem made (m.choicePositions k) -> (made' : Template) -> InV m made made' ->
                  Renumbered m.heldCount made' member ->
                  LTE w.size (sizeWithin b.arity (height argument) b.heaviest) -> LTE (bound g pot arm) h ->
                  ArgumentWithin m pot b (Just w) h
heldArmPlaced k arm member argument held made madeAt made' memberIn again keyed under =
  sitePlaced arm argument (held made madeAt made' memberIn again) keyed under
