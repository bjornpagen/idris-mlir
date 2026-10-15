-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Why the translation's worklist ends, and the worklist itself, which
||| recurses on the proof.
|||
||| The translation requests a function instance for each call it meets,
||| at the compile-time arguments the call fixes (`Instances.request`), and
||| translates each one requested once. The requests an instance made are
||| judged once it is translated, against its request chain (the instance,
||| the one that requested it, back to the root), by the one relation
||| `Proof.Requests.admit` decides: a request of a definition that grows
||| against an earlier instance of it on the chain, smaller at no static
||| argument and larger at one, rejects the instance that made it. A static
||| argument is written out over the context's names and finitely many
||| forms of term (`Keys.write`): that writing, the request's link, is its
||| identity, and its size is the number of nodes it has and the magnitude
||| of each literal, so that finitely many arguments share a size and the
||| relation is almost full (`Proof.Requests.afRequested`, which rests on
||| Dickson's lemma): every chain is finite.
|||
||| The worklist takes the instances a generation at a time, first in,
||| first out. Each instance of the next generation extends the chain of
||| one of this generation by a request new to it, so the generations
||| descend under a well-founded relation (`Proof.Generations`): the
||| worklist recurses on its accessibility proof, and within a generation
||| on the instances still to take. No bound exists in advance, since the
||| types between two instances of a definition grow by whatever the
||| program computes at the type level; the proof is what the recursion
||| descends on.
|||
||| A pass is void when a dictionary field it took as never built is built
||| after it was matched (`Dictionaries`); the next pass starts over knowing
||| the field. That the passes are finitely many is the one statement this
||| module takes on trust, at the call that starts the next pass
||| (`translateFrom`).
module IdrisMLIR.Frontend.Finite

import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Ids
import IdrisMLIR.Proof.AlmostFull
import IdrisMLIR.Proof.Forms
import IdrisMLIR.Proof.Generations
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Syntax.Idr
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Relation
import Control.WellFounded
import Data.DPair
import Data.Fin
import Data.List
import Data.List.Elem
import Data.List.Quantifiers
import Data.So
import Data.SortedMap
import Data.SortedSet
import Data.Vect
import Decidable.Equality

%default total

------------------------------------------------------------------------------
-- Chains
------------------------------------------------------------------------------

||| A request as its chain compares it: its link, its identity.
requestLink : Request -> Link Form
requestLink r = r.link

||| An earlier instance a chain cannot hold together with a later one.
Older : Rel Request
Older = Via requestLink

||| Every chain of instances the relation admits ends: extending it by an
||| instance new to it is well founded. The function worklist and the data
||| instances being built both recurse on it.
export
0 chainsEnd : (link : e -> Link Form) -> (chain : List e) -> Bad (Via link) chain ->
              Accessible (Extends (Via link)) chain
chainsEnd = chainAccessible forms

||| A pending instance: its request, and the chain of requests that led to
||| it, its requester first.
public export
record Item where
  constructor MkItem
  request : Request
  above : List Request

||| An item's own chain, itself first.
public export
chainOf : Item -> List Request
chainOf it = it.request :: it.above

||| The requests an instance made, judged: each one under the instance's
||| chain, and new to it.
Under : List Request -> List Item -> Type
Under c new = All (\k => (k.above = c, New Older c k.request)) new

||| The requests an instance made, as items, with the erased evidence that
||| each is under its chain and new to it.
record Judged (chain : List Request) where
  constructor MkJudged
  items : List Item
  0 under : Under chain items

------------------------------------------------------------------------------
-- Judging requests
------------------------------------------------------------------------------

||| What a refused request says: exactly what the chain saw, a request of a
||| definition larger at a parameter and smaller at none than an earlier
||| request of it on the same chain, which the compiler cannot bound in
||| general; the call, the parameter that grew, and the two keys. The
||| parameter is named as the definition's type names it, by position.
refusal : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          (earlier, later : Request) -> Nat -> Core a
refusal earlier r i = do
  def <- lookupDef r.site r.owner r.name
  reject r.site r.owner Polymorphism
         ("polymorphic recursion: " ++ r.base ++ " requests itself with its argument " ++
          parameter i (type def) ++ " larger than an earlier request of it on the same chain (" ++
          keyText r.key ++ " after " ++ keyText earlier.key ++
          "), and no analysis bounds how far a chain that grows so goes")
  where
    parameter : Nat -> TT vs -> String
    parameter Z (Bind _ x (Pi {}) _) = show x
    parameter (S k) (Bind _ _ (Pi {}) sc) = parameter k sc
    parameter j _ = "number " ++ show (S j)

||| The requests made since the worklist last took them, judged against the
||| chain of the instance that made them: each one new to it is an item
||| under it; one that grows rejects the instance; one already on it is
||| no new instance. The state keeps none of them after.
requestedUnder : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 (earlier : List Request) -> Core (Judged earlier)
requestedUnder earlier = do
  st <- get TState
  put TState ({ requested := [<] } st)
  judge (st.requested <>> [])
  where
    judge : List Request -> Core (Judged earlier)
    judge [] = pure (MkJudged [] [])
    judge (r :: rs) = case admit requestLink earlier r of
      Admitted new => do
        MkJudged rest under <- judge rs
        pure (MkJudged (MkItem r earlier :: rest) ((Refl, new) :: under))
      Refused x _ (Grown _ g) => refusal x r (position g)
      Refused x _ (Arity _ _) =>
        internal r.site ("a definition requested at two numbers of arguments: " ++ r.base)
      -- What is left is a request of an instance already on the chain,
      -- which was requested before and so is seen: a new request is none.
      Refused _ _ (Again _) =>
        internal r.site ("an instance requested again as new on its own chain: " ++ r.inst.name)

------------------------------------------------------------------------------
-- The worklist
------------------------------------------------------------------------------

elemAny : {0 p : a -> Type} -> Elem x xs -> p x -> Any p xs
elemAny Here px = Here px
elemAny (There e) px = There (elemAny e px)

anyNonEmpty : Any p xs -> NonEmpty xs
anyNonEmpty (Here _) = IsNonEmpty
anyNonEmpty (There _) = IsNonEmpty

allReverse : {0 p : a -> Type} -> (xs : List a) -> All p xs -> All p (reverse xs)
allReverse xs ps = go [] xs [] ps
  where
    go : (acc, ys : List a) -> All p acc -> All p ys -> All p (reverseOnto acc ys)
    go acc [] pacc [] = pacc
    go acc (y :: ys) pacc (py :: pys) = go (y :: acc) ys (py :: pacc) pys

allMap : {0 p : b -> Type} -> (f : a -> b) -> (xs : List a) -> All (p . f) xs -> All p (map f xs)
allMap f [] [] = []
allMap f (x :: xs) (px :: pxs) = px :: allMap f xs pxs

-- Each item of a generation has its chain in the generation.
inGeneration : (items : List Item) -> All (\it => Elem (chainOf it) (map Finite.chainOf items)) items
inGeneration [] = []
inGeneration (it :: items) =
  Here :: mapProperty There (inGeneration items)

-- A request judged under a chain extends it.
extends : (k : Item) -> k.above = c -> New Older c k.request -> Extends Older (chainOf k) c
extends (MkItem r above) eq new = rewrite eq in Extend new

-- The requests of an instance of the generation are below the generation.
belowGeneration : {0 gen : List (List Request)} -> (new : List Item) -> Elem c gen -> Under c new ->
                  All (\k => Any (Extends Older (chainOf k)) gen) new
belowGeneration [] _ [] = []
belowGeneration (k :: ks) here ((eq, fresh) :: under) =
  elemAny here (extends k eq fresh) :: belowGeneration ks here under

-- The first generation, the root's requests, is accessible: each chain is
-- a request alone.
0 firstGeneration : (roots : List Item) -> Under [] roots ->
                    All (Accessible (Extends Older)) (map Finite.chainOf roots)
firstGeneration [] [] = []
firstGeneration (MkItem r above :: roots) ((eq, _) :: under) =
  rewrite eq in chainsEnd requestLink [r] ([] :: [])
    :: firstGeneration roots under

||| One pass: the generation and the proof that the generations from it
||| end, the items of it still to take, each one's chain in it, and the
||| next generation so far, newest first, each one's chain extending a
||| chain of the generation by a request new to it. An instance its
||| translation or the judgment of its requests rejects is recorded and
||| leaves the state as it was before it, the instances it requested
||| included, but for the rejections and what they refused, and what it
||| found of definitions: what it would have reached is reported once it is
||| fixed, and every rejection the translation reports is independent.
pass : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
       (translate : Request -> Core ()) ->
       (0 gen : List (List Request)) -> (0 _ : Accessible (Follows (Extends Older)) gen) ->
       (todo : List Item) -> (0 _ : All (\it => Elem (chainOf it) gen) todo) ->
       (next : List Item) -> (0 _ : All (\it => Any (Extends Older (chainOf it)) gen) next) ->
       Core ()
pass translate gen acc (it :: todo) (here :: there) next below = do
  update TState { chain := chainOf it }
  before <- get TState
  Nothing <- noting (do translate it.request; requestedUnder (chainOf it))
    | Just (MkJudged new under) =>
        pass translate gen acc todo there (reverse new ++ next)
             (allReverse new (belowGeneration new here under) ++ below)
  after <- get TState
  put TState ({ rejected := after.rejected, refused := after.refused, places := after.places
              , tyCons := after.tyCons, loops := after.loops, blockNames := after.blockNames } before)
  pass translate gen acc todo there next below
pass translate gen (Access more) [] [] [] [] = pure ()
pass translate gen (Access more) [] [] (k :: ks) below =
  pass translate (map chainOf (reverse (k :: ks)))
       (more (map chainOf (reverse (k :: ks)))
             (MkFollows (anyNonEmpty (head below))
                        (allMap chainOf (reverse (k :: ks)) (allReverse (k :: ks) below))))
       (reverse (k :: ks)) (inGeneration (reverse (k :: ks))) [] []

||| A dictionary field the pass matched before any construction site gave
||| it, which one has given since, and which was not known when the pass
||| began (a field known then is never taken as unbuilt): what voids a
||| pass, and what the next pass knows that it did not.
learnt : (known : SortedSet (ConId, Nat)) -> (st : TS) -> Maybe (ConId, Nat)
learnt known st = find (\k => contains k (keySet st.dicts) && not (contains k known)) (Prelude.toList st.assumed)

||| The program's instances from its root, in as many passes as the
||| dictionary fields matched before they were built need. A pass starts
||| from the state the last one left (`nextPass`) and requests the root
||| (`root`); each instance requested is then translated in turn
||| (`translate`), its chain the state's while it is, a generation at a
||| time. A pass that a construction site voids still goes on to the end:
||| an assumption it made only left alternatives out, so all it translates
||| is in the program, and every construction site it finds is one the
||| next pass starts from, not only the first.
|||
||| Each pass ends (the worklist above). That the passes end is the one
||| statement this module takes on trust, at the one call that starts the
||| next pass: TRUST POINT (the passes are finitely many): every pass after
||| the first knows every field the pass before it knew and one it did not
||| (`learnt`), and the fields a pass can learn are finitely many, so that
||| call is made finitely often. The fields a pass can learn are fields of
||| the data instances the requests reach when every alternative a pass took
||| as unreachable is translated, a tree whose chains are finite
||| (`chainsEnd`) and whose branching is finite, since an instance's
||| requests are its body's calls; but that tree is not one the types
||| state, and no list of the fields exists before the program is
||| translated. The statement is the call's termination, and no type of
||| fields is claimed well founded.
export
translateFrom : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                (root : Core (Maybe FnId)) -> (translate : Request -> Core ()) -> Core (Maybe FnId)
translateFrom root translate = do
  update TState nextPass
  known <- (\st => keySet st.dicts) <$> get TState
  passes known
  where
    passes : SortedSet (ConId, Nat) -> Core (Maybe FnId)
    passes known = do
      Just inst <- root
        | Nothing => pure Nothing
      MkJudged roots under <- requestedUnder []
      pass translate (map chainOf roots) (generations (map chainOf roots) (firstGeneration roots under))
           roots (inGeneration roots) [] []
      st <- get TState
      let Just _ = learnt known st
        | Nothing => pure (Just inst)
      update TState nextPass
      assert_total (passes (union known (keySet st.dicts)))
