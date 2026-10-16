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
||| module does not prove, so `translateFrom`, which starts each pass, is
||| `covering`, and its comment states the gap.
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

||| The chains of items, in order.
0 chains : List (Subset Item p) -> List (List Request)
chains [] = []
chains (Element it _ :: items) = chainOf it :: chains items

||| A request judged under a chain: an item under it, and new to it.
Under : List Request -> Item -> Type
Under c k = (k.above = c, New Older c k.request)

||| The requests an instance made, judged: each one an item with the erased
||| evidence that it is under the instance's chain and new to it.
Judged : List Request -> Type
Judged chain = List (Subset Item (Under chain))

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
  def <- lookupDef r.site (show r.owner) r.name
  reject r.site (show r.owner) Polymorphism
         ("polymorphic recursion: " ++ nameKey !(toFullNames r.name) ++ " requests itself with its argument " ++
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
    judge [] = pure []
    judge (r :: rs) = case admit requestLink earlier r of
      Admitted new => do
        rest <- judge rs
        pure (Element (MkItem r earlier) (Refl, new) :: rest)
      Refused x _ _ (GrownAt i) _ => refusal x r i
      -- A broken invariant: a request of a definition has one argument per
      -- parameter of its case tree (every call classifies `length params`
      -- of the definition's `PMDef`, and the root, `main`, has none), so
      -- two links of one definition have one length.
      Refused _ _ _ OtherArity _ => do
        internal r.site ("a definition requested at two numbers of arguments: " ++
                         nameKey !(toFullNames r.name))
      -- A broken invariant: a request is recorded only for an instance not
      -- yet seen (`Instances.request`), one link is one instance (`named`,
      -- `Keys.instanceKey`), and every instance on a chain was seen when it
      -- was requested and stays seen for the pass (a rejected instance
      -- restores the state from before it), so a recorded request is new
      -- to its chain.
      Refused _ _ _ Repeated _ =>
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

||| An item of a generation: its chain is one of the generation's.
Member : List (List Request) -> Item -> Type
Member gen it = Elem (chainOf it) gen

||| An item of the next generation: its chain extends one of the
||| generation's by a request new to it.
Below : List (List Request) -> Item -> Type
Below gen it = Any (Extends Older (chainOf it)) gen

-- The chains `rest` end the generation `gen`.
data Ends : (rest, gen : List (List Request)) -> Type where
  Whole : Ends gen gen
  Past : Ends (c :: rest) gen -> Ends rest gen

0 endsElem : Ends rest gen -> Elem c rest -> Elem c gen
endsElem Whole e = e
endsElem (Past ends) e = endsElem ends (There e)

-- The items that end a generation, each with its place in it.
placed : (0 gen : List (List Request)) -> (rest : List (Subset Item p)) -> (0 _ : Ends (chains rest) gen) ->
         List (Subset Item (Member gen))
placed gen [] _ = []
placed gen (Element it _ :: rest) ends = Element it (endsElem ends Here) :: placed gen rest (Past ends)

-- A request judged under a chain extends it.
extends : (k : Item) -> k.above = c -> New Older c k.request -> Extends Older (chainOf k) c
extends (MkItem r above) eq new = rewrite eq in Extend new

-- The requests an item of the generation made, below the generation,
-- before the next generation so far, the newest first.
pushBelow : {0 gen : List (List Request)} -> (0 _ : Elem c gen) ->
            Judged c -> List (Subset Item (Below gen)) -> List (Subset Item (Below gen))
pushBelow here [] next = next
pushBelow here (Element k under :: new) next =
  pushBelow here new (Element k (elemAny here (extends k (fst under) (snd under))) :: next)

-- Each chain of the next generation is below one of the generation's.
0 belowAll : (next : List (Subset Item (Below gen))) -> All (\c => Any (Extends Older c) gen) (chains next)
belowAll [] = []
belowAll (Element _ below :: next) = below :: belowAll next

-- The first generation, the root's requests, is accessible: each chain is
-- a request alone.
0 firstGeneration : (roots : Judged []) -> All (Accessible (Extends Older)) (chains roots)
firstGeneration [] = []
firstGeneration (Element (MkItem r above) under :: roots) =
  rewrite fst under in chainsEnd requestLink [r] ([] :: [])
    :: firstGeneration roots

||| One pass: the generation and the proof that the generations from it
||| end, the items of it still to take, each with the erased evidence that
||| its chain is in it, and the next generation so far, newest first, each
||| with the erased evidence that its chain extends a chain of the
||| generation by a request new to it. An instance its
||| translation or the judgment of its requests rejects is recorded and
||| leaves the state as it was before it, the instances it requested
||| included, but for the rejections and what they refused, and what it
||| found of definitions: what it would have reached is reported once it is
||| fixed, and every rejection the translation reports is independent.
pass : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
       (translate : Request -> Core ()) ->
       (0 gen : List (List Request)) -> (0 _ : Accessible (Follows (Extends Older)) gen) ->
       (todo : List (Subset Item (Member gen))) -> (next : List (Subset Item (Below gen))) ->
       Core ()
pass translate gen acc@(Access _) (Element it here :: todo) next = do
  update TState { chain := chainOf it }
  before <- get TState
  Nothing <- noting (do translate it.request; requestedUnder (chainOf it))
    | Just new => pass translate gen acc todo (pushBelow here new next)
  after <- get TState
  put TState ({ rejected := after.rejected, refused := after.refused, places := after.places
              , tyCons := after.tyCons, loops := after.loops, blockNames := after.blockNames } before)
  pass translate gen acc todo next
pass translate gen (Access more) [] [] = pure ()
pass translate gen (Access more) [] next@(Element _ below :: _) =
  let items := reverse next in
  pass translate (chains items) (more (chains items) (MkFollows (anyNonEmpty below) (belowAll items)))
       (placed (chains items) items Whole) []

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
||| statement this module does not prove, so `translateFrom` is `covering`,
||| checked for coverage alone, and asserts nothing: TRUST POINT (the
||| passes are finitely many): every pass after the first knows every field
||| the pass before it knew and one it did not (`learnt`), and a field once
||| given an implementation keeps it (a second is a refusal), so each pass
||| translates every alternative the pass before it did, the same way, and
||| more. The passes are therefore no more than the fields any pass can
||| learn. A field is a constructor of a data instance, by its position
||| among the instance's constructors (`ConId.index`), and one of that
||| constructor's argument positions, so a data instance has finitely many.
||| The instances any pass registers are those of the request tree under
||| the assignment the passes converge to: its chains are those the
||| relation admits, finite (`chainsEnd`), and it branches finitely, an
||| instance's requests being its body's call sites, one request each once
||| every field it matches holds its one implementation; such a tree is
||| finite (the fan theorem, on the inductive bar `afRequested` gives), and
||| so are its fields. What no type here states is that tree: it is the
||| request tree under the assignment the passes compute, so neither it nor
||| the list of its fields exists before the passes end, and the measure,
||| its fields not yet known, is no value the recursion can descend on; with
||| such a list, `roomAfter` (`Libraries.Data.List.Finite`) would be the
||| descent.
export
covering
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
      roots <- requestedUnder []
      pass translate (chains roots) (generations (chains roots) (firstGeneration roots))
           (placed (chains roots) roots Whole) []
      st <- get TState
      let Just _ = learnt known st
        | Nothing => pure (Just inst)
      update TState nextPass
      passes (union known (keySet st.dicts))
