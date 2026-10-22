-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Why the translation's worklist ends, and the worklist itself, which
||| recurses on the proof.
|||
||| The translation requests a function instance for each call it meets,
||| at the compile-time arguments the call fixes (`Instances.request`), and
||| translates each one requested once. The growth check, before the
||| translation, gave every static position of the program a bound on how
||| high its arguments grow (`TS.bounds`), and every definition a bound on
||| how much its requests' arguments weigh written (`TS.sizes`): the links
||| within those bounds are finitely many (`Proof.Requests.Universe`). The
||| requests an instance made are judged once it is translated, against
||| its request chain (the instance, the one that requested it, back to the
||| root): each static argument against its position's bound, the link
||| against the sizes, and the link against the chain's, to which it must
||| be new. A request outside the bounds is the growth check's error, never
||| the program's: an internal error, not a refusal and not a hang.
|||
||| A chain is then a list of distinct links of a finite universe, so it
||| has room for fewer at each extension, and every chain ends
||| (`extensionsEnd`).
||| The worklist is semi-naive over the instance table: it takes the
||| instances a generation at a time, first in, first out, each generation
||| the instances the one before it derived that the table did not hold
||| (`Instances.request` records only a link the table lacks, an
||| instance's identity being its content). Each instance of the next
||| generation extends the chain of one of this generation by a fresh
||| request, so the generations descend under a well-founded relation
||| (`Proof.Generations`): the worklist recurses on its accessibility
||| proof, and within a generation on the instances still to take. A
||| choice's members and its dispatches are joined as they are found
||| (`Choices`), so nothing waits for a later round.
module IdrisMLIR.Frontend.Finite

import Core.Context
import Core.Core
import Core.TT
import Libraries.Data.List.Finite

import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Ids
import IdrisMLIR.Proof.Forms
import IdrisMLIR.Proof.Generations
import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Relation
import Control.WellFounded
import Data.DPair
import Data.Fin
import Data.List
import Data.List.Elem
import Data.List.Quantifiers
import Data.Maybe
import Data.Nat
import Data.So
import Data.SortedMap
import Data.SortedSet
import Data.Vect
import Decidable.Equality

%default total

------------------------------------------------------------------------------
-- Room
------------------------------------------------------------------------------

||| The links within the bounds: the universe the worklist has room in.
||| Named here, on a right-hand side, so that a type names it by this
||| upper-case name: a lower-case global in a type is bound as an implicit.
0 Bounded : Bounds -> List (Link Form)
Bounded b = Universe forms addresses b

||| A link within the bounds, with the evidence (`Proof.Requests.within`),
||| named as `Bounded` is.
public export
0 Inside : Bounds -> Link Form -> Type
Inside b l = InUniverse forms addresses b l

-- One fewer is left once one more is kept: n - (k + 1) < n - k for k < n.
0 lessLeft : (n, k : Nat) -> LT k n -> LT (minus n (S k)) (minus n k)
lessLeft (S n) Z _ = rewrite minusZeroRight n in reflexive {rel = LTE}
lessLeft (S n) (S k) (LTESucc lt) = lessLeft n k lt

||| A new member leaves less room: a list without duplicates whose values
||| are all in `u` is no longer than `u` (the fork's `pigeonhole`), so one
||| more value, not yet in it, leaves fewer of `u`'s places.
export 0 room : {u : List a} -> NoDup (x :: taken) -> All (\y => Elem y u) (x :: taken) ->
                LT (minus (length u) (length (x :: taken))) (minus (length u) (length taken))
room nd inside = lessLeft (length u) (length taken) (pigeonhole nd (\y, e => indexAll e inside))

------------------------------------------------------------------------------
-- Chains
------------------------------------------------------------------------------

||| A request as its chain compares it: its link, its identity.
requestLink : Request -> Link Form
requestLink r = r.link

||| A chain's links.
links : List Request -> List (Link Form)
links = map requestLink

||| A chain extended by one more, its key new to the chain's and a member of
||| a universe: the step every chain the translation makes takes, a chain of
||| requests (`Fresh`) and a chain of data instances being registered
||| (`Types.Descending`) alike.
public export
data Extends : (u : List k) -> (keyOf : a -> k) -> (longer, path : List a) -> Type where
  Extend : {0 u : List k} -> {0 keyOf : a -> k} -> {0 x : a} -> {0 path : List a} ->
           (0 _ : Not (Elem (keyOf x) (map keyOf path))) -> (0 _ : Elem (keyOf x) u) ->
           Extends u keyOf (x :: path) path

||| Every chain of distinct keys in a finite universe ends: each extension
||| leaves less room in it.
export
0 extensionsEnd : (u : List k) -> (keyOf : a -> k) -> (path : List a) -> NoDup (map keyOf path) ->
                  All (\y => Elem y u) (map keyOf path) ->
                  Accessible LT (minus (length u) (length (map keyOf path))) ->
                  Accessible (Extends u keyOf) path
extensionsEnd u keyOf path nd inside (Access more) = Access next
  where
    next : (longer : List a) -> Extends u keyOf longer path -> Accessible (Extends u keyOf) longer
    next (x :: _) (Extend new here) =
      extensionsEnd u keyOf (x :: path) (new :: nd) (here :: inside) (more _ (room (new :: nd) (here :: inside)))

||| A chain of requests extended by a request whose link is new to it and
||| lies within the bounds.
0 Fresh : Bounds -> (longer, path : List Request) -> Type
Fresh b = Extends (Bounded b) requestLink

||| A pending instance: its request, and the chain of requests that led to
||| it, its requester first, which its translation reads (`TS.chain`).
record Item where
  constructor MkItem
  request : Request
  above : List Request

||| An item's own chain, itself first.
chainOf : Item -> List Request
chainOf it = it.request :: it.above

||| The chains of items, in order.
0 chains : List (Subset Item p) -> List (List Request)
chains [] = []
chains (Element it _ :: items) = chainOf it :: chains items

||| A request judged under a chain: an item whose chain above it is that
||| one, its link new to the chain and within the bounds.
data Under : Bounds -> List Request -> Item -> Type where
  MkUnder : {0 r : Request} -> (0 _ : Not (Elem r.link (links c))) -> (0 _ : Elem r.link (Bounded b)) ->
            Under b c (MkItem r c)

||| The requests an instance made, judged: each one an item with the erased
||| evidence that it is under the instance's chain.
Judged : Bounds -> List Request -> Type
Judged b chain = List (Subset Item (Under b chain))

------------------------------------------------------------------------------
-- Judging requests
------------------------------------------------------------------------------

||| The growth check missed a way the program grows: `what` lies outside
||| the bounds it gave. The compiler's error, never the program's.
unsound : FC -> (what : String) -> (why : String) -> Core a
unsound fc what why = internal fc ("the growth check is unsound: " ++ what ++ " " ++ why)

||| A static argument of `what` at a position, `height` high, checked
||| against the growth check's bound there. The bound is the growth
||| check's, which no request or registration carries a proof of: a
||| position with none, or an argument above it, is the check's error, and
||| is reported.
export
heightWithin : FC -> (what : String) -> SortedMap Position Nat -> Position -> (height : Nat) -> Core ()
heightWithin fc what bounds (node, j) h = do
  let Just top = lookup (node, j) bounds
    | Nothing => unsound fc what ("has no bound at its argument " ++ show (S j))
  when (h > top) $
    unsound fc what ("is " ++ show h ++ " high at its argument " ++ show (S j) ++ ", above its bound " ++ show top)

||| The link of `what` within the bounds' sizes, with the evidence; one
||| outside them is the growth check's error.
export
sizedWithin : FC -> (what : String) -> (b : Bounds) -> (l : Link Form) -> Core (Inside b l)
sizedWithin fc what b l = case within forms addresses b l of
  -- Its fields are erased, so the evidence costs nothing to hold.
  Yes inside => pure (MkIn inside.short inside.sized inside.member)
  No _ => unsound fc what ("has " ++ show (length l.arguments) ++ " arguments weighing " ++ show (sizes l) ++
                              ", outside the heights " ++ show (b.heightAt l.head) ++ " of " ++ show l.head ++
                              " (arity " ++ show b.arity ++
                              ", heaviest " ++ show b.heaviest ++ ") and the breadth " ++ show b.breadth ++ " of its bounds")

||| The requests made since the worklist last took them, judged against the
||| chain of the instance that made them: each static argument no higher
||| than its position's bound, the link within the bounds' sizes, and new
||| to the chain. The state keeps none of them after.
requestedUnder : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 (b : Bounds) -> SortedMap Position Nat -> (earlier : List Request) -> Core (Judged b earlier)
requestedUnder b bounds earlier = do
  st <- get TState
  put TState ({ requested := [<] } st)
  judge (st.requested <>> [])
  where
    judge : List Request -> Core (Judged b earlier)
    judge [] = pure []
    judge (r :: rs) = do
      let what = keyText r.key ++ ", requested in " ++ show r.owner ++ ","
      -- An instance of a definition is checked at its node's positions,
      -- the node split by the heads the request's values have, whose
      -- parameters the graph decided are positions at those heads
      -- (`Sites.sitesOf`), as `classify` decided the request's; a member at
      -- a use is no node, has no positions, and is checked by its link.
      traverse_ (\(p, h) => heightWithin r.site what bounds p h) r.positions
      inside <- sizedWithin r.site what b r.link
      case elemLink r.link (links earlier) of
        -- A broken invariant: a request is recorded only for an instance not
        -- yet seen (`Instances.request`), one link is one instance (`named`,
        -- `Keys.instanceKey`), and every instance on a chain was seen when it
        -- was requested and stays seen (a rejected instance
        -- restores the state from before it), so a recorded request is new
        -- to its chain.
        Yes _ => internal r.site ("an instance requested again as new on its own chain: " ++ keyText r.key)
        No new => do
          rest <- judge rs
          pure (Element (MkItem r earlier) (MkUnder new inside.member) :: rest)

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
||| generation's by a fresh request.
0 Below : Bounds -> List (List Request) -> Item -> Type
Below b gen it = Any (Fresh b (chainOf it)) gen

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
0 extends : (k : Item) -> Under b c k -> Fresh b (chainOf k) c
extends (MkItem r c) (MkUnder new here) = Extend new here

-- The requests an item of the generation made, below the generation,
-- before the next generation so far, the newest first.
pushBelow : {0 gen : List (List Request)} -> (0 _ : Elem c gen) ->
            Judged b c -> List (Subset Item (Below b gen)) -> List (Subset Item (Below b gen))
pushBelow here [] next = next
pushBelow here (Element k under :: new) next =
  pushBelow here new (Element k (elemAny here (extends k under)) :: next)

-- Each chain of the next generation is below one of the generation's.
0 belowAll : (next : List (Subset Item (Below b gen))) -> All (\c => Any (Fresh b c) gen) (chains next)
belowAll [] = []
belowAll (Element _ below :: next) = below :: belowAll next

||| An item the worklist can take again in a later round: its chain is
||| accessible under fresh extension, so what it requests ends.
0 Resumable : Bounds -> Item -> Type
Resumable b it = Accessible (Fresh b) (chainOf it)

||| An item of a generation the worklist takes is one it can take again.
0 resumes : Accessible (Follows (Fresh b)) gen -> Member gen it -> Resumable b it
resumes acc here = elemAccessible acc here

-- The chains of items the worklist can take again are accessible.
0 resumable : (items : List (Subset Item (Resumable b))) -> All (Accessible (Fresh b)) (chains items)
resumable [] = []
resumable (Element _ acc :: items) = acc :: resumable items

||| The root's requests, each its chain alone, a link of the universe: the
||| first round's items.
rooted : (0 b : Bounds) -> Judged b [] -> List (Subset Item (Resumable b))
rooted b [] = []
rooted b (Element it under :: roots) = Element it (alone b under) :: rooted b roots
  where
    0 alone : (b : Bounds) -> Under b [] x -> Resumable b x
    alone b (MkUnder {r} _ here) = extensionsEnd (Bounded b) requestLink [r] (absurd :: []) [here] (wellFounded _)

||| One round: the generation and the proof that the generations from it
||| end, the items of it still to take, each with the erased evidence that
||| its chain is in it, and the next generation so far, newest first, each
||| with the erased evidence that its chain extends a chain of the
||| generation by a request new to it. An instance its translation rejects
||| is recorded and leaves the state as it was before it, the instances it
||| requested included, but for the rejections and what they refused, and
||| what it found of definitions: what it would have reached is reported
||| once it is fixed, and every rejection the translation reports is
||| independent.
worklist : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           (translate : Request -> Front ()) -> (b : Bounds) -> SortedMap Position Nat ->
           (0 gen : List (List Request)) -> (0 acc : Accessible (Follows (Fresh b)) gen) ->
           (todo : List (Subset Item (Member gen))) -> (next : List (Subset Item (Below b gen))) -> Core ()
worklist translate b bounds gen acc@(Access _) (Element it here :: todo) next = do
  update TState { chain := chainOf it }
  before <- get TState
  result <- noting (do translate it.request; core (requestedUnder b bounds (chainOf it)))
  after <- get TState
  case result of
    Just new => worklist translate b bounds gen acc todo (pushBelow here new next)
    Nothing => do
      put TState (keepFound after before)
      worklist translate b bounds gen acc todo next
worklist translate b bounds gen (Access more) [] [] = pure ()
worklist translate b bounds gen (Access more) [] next@(Element _ below :: _) =
  let items := reverse next in
  worklist translate b bounds (chains items) (more (chains items) (MkFollows (anyNonEmpty below) (belowAll items)))
           (placed (chains items) items Whole) []

||| The program's instances from its root: the root is requested (`root`),
||| and each instance requested is translated in turn (`translate`), its
||| chain the state's while it is, a generation at a time, until a
||| generation derives no instance the table lacks.
export
translateFrom : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                (root : Core (Maybe FnId)) -> (translate : Request -> Front ()) -> Core (Maybe FnId)
translateFrom root translate = do
  update TState translating
  start <- get TState
  Just inst <- root
    | Nothing => pure Nothing
  roots <- requestedUnder start.sizes start.bounds []
  let items = rooted start.sizes roots
  worklist translate start.sizes start.bounds (chains items) (generations (chains items) (resumable items))
           (placed (chains items) items Whole) []
  pure (Just inst)
