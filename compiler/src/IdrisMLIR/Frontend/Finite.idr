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
||| The worklist takes the instances a generation at a time, first in,
||| first out. Each instance of the next generation extends the chain of
||| one of this generation by a fresh request, so the generations descend
||| under a well-founded relation (`Proof.Generations`): the worklist
||| recurses on its accessibility proof, and within a generation on the
||| instances still to take.
|||
||| An instance that matched a dictionary field before any construction
||| site gave it took the field as never built (`Dictionaries`), and waits
||| on it. When the worklist has taken every instance, the waiting
||| instances whose field a construction site has since given are taken
||| again, knowing it, in a round of their own, and with what they then
||| request. Each round learns a field no round before it learnt, a field
||| of a data instance within the bounds, so the rounds too recurse on the
||| room left in a finite universe.
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

||| The dictionary fields the rounds have room to learn.
0 Learnable : Bounds -> List DictField
Learnable b = FieldUniverse forms addresses b

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
||| it, its requester first, which the messages read (`Dictionaries.chooser`).
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
  Holds inside => pure inside
  Fails _ => unsound fc what ("has " ++ show (length l.arguments) ++ " arguments weighing " ++ show (sizes l) ++
                              ", outside the heights " ++ show (b.heightAt l.definition) ++ " (arity " ++ show b.arity ++
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
      -- The node is split by the heads the request's values have, and the
      -- graph decided which of a node's parameters are positions at those
      -- heads (`Sites.sitesOf`), as `classify` decided the request's.
      traverse_ (\(j, h) => heightWithin r.site what bounds (r.node, j) h) r.heights
      inside <- sizedWithin r.site what b r.link
      case elemLink r.link (links earlier) of
        -- A broken invariant: a request is recorded only for an instance not
        -- yet seen (`Instances.request`), one link is one instance (`named`,
        -- `Keys.instanceKey`), and every instance on a chain was seen when it
        -- was requested and stays seen (a rejected instance
        -- restores the state from before it), so a recorded request is new
        -- to its chain.
        Holds _ => internal r.site ("an instance requested again as new on its own chain: " ++ r.inst.name)
        Fails new => do
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

||| An instance that matched dictionary fields no construction site had
||| given (`TS.assumed`), with them: it translated their alternatives as
||| unreachable, and waits for a construction site of one.
0 Waiting : Bounds -> Type
Waiting b = (Subset Item (Resumable b), SortedSet DictField)

||| An instance translated waits on the fields it took as never built; one
||| that took none waits on nothing, and is not kept.
waitOn : Subset Item (Resumable b) -> SortedSet DictField -> SnocList (Waiting b) -> SnocList (Waiting b)
waitOn it fields waiting = case Prelude.toList fields of
  [] => waiting
  _ => waiting :< (it, fields)

||| The waiting instances a construction site has woken, in the order they
||| were translated, each with a field it took as never built that a site
||| has since given, and the dictionary given, and the instances still
||| waiting.
wake : SortedMap DictField Dictionary -> SnocList (Waiting b) ->
       (SnocList (Subset Item (Resumable b), (DictField, Dictionary)), SnocList (Waiting b))
wake dicts [<] = ([<], [<])
wake dicts (ws :< w@(it, fields)) =
  let (woken, still) = wake dicts ws in
  case given (Prelude.toList fields) of
    Just g => (woken :< (it, g), still)
    Nothing => (woken, still :< w)
  where
    -- The first of the fields a site has given, with its dictionary.
    given : List DictField -> Maybe (DictField, Dictionary)
    given [] = Nothing
    given (k :: ks) = maybe (given ks) (\d => Just (k, d)) (lookup k dicts)

||| One round: the generation and the proof that the generations from it
||| end, the items of it still to take, each with the erased evidence that
||| its chain is in it, the next generation so far, newest first, each
||| with the erased evidence that its chain extends a chain of the
||| generation by a request new to it, and the instances waiting on a
||| dictionary field, in the order they were translated. An instance its
||| translation rejects is recorded and leaves the state as it was before
||| it, the instances it requested included, but for the rejections and
||| what they refused, and what it found of definitions: what it would have
||| reached is reported once it is fixed, and every rejection the
||| translation reports is independent. It still waits on the fields it
||| took as never built: given one, it is rejected for what it then finds.
worklist : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           (translate : Request -> Front ()) -> (b : Bounds) -> SortedMap Position Nat ->
           (0 gen : List (List Request)) -> (0 acc : Accessible (Follows (Fresh b)) gen) ->
           (todo : List (Subset Item (Member gen))) -> (next : List (Subset Item (Below b gen))) ->
           SnocList (Waiting b) -> Core (SnocList (Waiting b))
worklist translate b bounds gen acc@(Access _) (Element it here :: todo) next waiting = do
  update TState { chain := chainOf it, assumed := empty }
  before <- get TState
  result <- noting (do translate it.request; core (requestedUnder b bounds (chainOf it)))
  after <- get TState
  let waiting' = waitOn (Element it (resumes acc here)) after.assumed waiting
  case result of
    Just new => worklist translate b bounds gen acc todo (pushBelow here new next) waiting'
    Nothing => do
      put TState (keepFound after before)
      worklist translate b bounds gen acc todo next waiting'
worklist translate b bounds gen (Access more) [] [] waiting = pure waiting
worklist translate b bounds gen (Access more) [] next@(Element _ below :: _) waiting =
  let items := reverse next in
  worklist translate b bounds (chains items) (more (chains items) (MkFollows (anyNonEmpty below) (belowAll items)))
           (placed (chains items) items Whole) [] waiting

||| A dictionary field given, as a message names it.
fieldText : (DictField, Dictionary) -> String
fieldText ((_, c, i), d) =
  "the dictionary field " ++ show i ++ " of constructor " ++ show c ++ ", given in " ++ show d.chooser

||| The field a round learnt, in the universe of fields: the link of its
||| data instance within the bounds, and its constructor's and argument's
||| indices below the bounds' breadth.
fieldIn : (b : Bounds) -> (DictField, Dictionary) -> Core (Subset DictField (\f => Elem f (Learnable b)))
fieldIn b given@(f, d) = do
  let Holds inside = inFields forms addresses b f
    | Fails _ => unsound d.site (fieldText given) ("lies outside the bounds, or beyond their breadth " ++ show b.breadth)
  pure (Element f inside.member)

||| The program's instances from its root, in as many rounds as the
||| dictionary fields matched before they were built need. The first round
||| requests the root (`root`) and translates each instance requested in
||| turn (`translate`), its chain the state's while it is, a generation at a
||| time; each round after it takes again the instances waiting on a field
||| that a construction site has since given, and what they then request.
||| A round's assumptions only left alternatives out, so all it translates
||| is in the program, and every construction site it finds is one the next
||| round knows. An instance taken again keeps its place among the program's
||| functions (`TS.fnOrder`); one it requests anew is placed when it is.
|||
||| Each round ends (the worklist above), and so do the rounds: each learns
||| a field no round before it learnt, a field of a data instance within
||| the bounds at indices below their breadth, so the fields learnt are
||| distinct members of a finite universe (`Learnable`), and the rounds
||| recurse on the room left in it. When no waiting instance's field is
||| given, every instance translated took as never built only fields no
||| construction site gives.
export
translateFrom : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                (root : Core (Maybe FnId)) -> (translate : Request -> Front ()) -> Core (Maybe FnId)
translateFrom root translate = do
  update TState translating
  start <- get TState
  Just inst <- root
    | Nothing => pure Nothing
  roots <- requestedUnder start.sizes start.bounds []
  rounds start.sizes start.bounds [] [] [] (wellFounded _) (rooted start.sizes roots) [<]
  pure (Just inst)
  where
    rounds : (b : Bounds) -> SortedMap Position Nat ->
             (fields : List DictField) -> (0 _ : NoDup fields) -> (0 _ : All (\f => Elem f (Learnable b)) fields) ->
             (0 _ : Accessible LT (minus (length (Learnable b)) (length fields))) ->
             List (Subset Item (Resumable b)) -> SnocList (Waiting b) -> Core ()
    rounds b bounds fields nd inside (Access more) items waiting = do
      waiting' <- worklist translate b bounds (chains items) (generations (chains items) (resumable items))
                       (placed (chains items) items Whole) [] waiting
      st <- get TState
      let (woken, still) = wake st.dicts waiting'
      let (it, k) :: rest = woken <>> []
        | [] => pure ()
      Element f here <- fieldIn b k
      case isElem f fields of
        -- A broken invariant: a woken instance took the field as never
        -- built in this round or one waiting since, and every field learnt
        -- before was given then, which woke every instance waiting on it,
        -- and is known to every instance translated after.
        Yes _ => internal (snd k).site ("a dictionary field learnt twice: " ++ fieldText k)
        No new =>
          rounds b bounds (f :: fields) (new :: nd) (here :: inside) (more _ (room (new :: nd) (here :: inside)))
                 (it :: map fst rest) still
