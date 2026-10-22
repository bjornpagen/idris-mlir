-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The graph the growth check decides, built from the program.
|||
||| A position is a static parameter of a node, a definition split by the
||| implementations its dictionary parameters are, or of the application of
||| a compile-time form at a use, which no definition is; a field of an
||| implementation, which the field's template writes over the
||| implementation's parameters and a field read takes its value from, so
||| a field read inside a field is arcs like any other; a choice, by its
||| head, which every place that makes a member of it writes and every
||| dispatch on it reads, program-wide, a dispatch on a choice of a head
||| also reading the members made where only an instance shows the head,
||| and one whose own head is unshown every choice's; or the values one of
||| these places, where a dictionary is, or the place in a writer's text
||| where a dictionary that closes over values is bound, holds as one, in
||| its lists of one value or in its lists of several (`Heads.HeldValues`),
||| which every place that gives it a list writes, a binding the list of
||| what it closes over, and every pair that holds a list of several reads,
||| at most the held count of them, a constant derived from the program
||| (`heldCount`); a dictionary held by another is one value of the other's
||| list, written from its own place's held positions. The walk over
||| definitions reads what each reachable one writes (its sites), and the
||| walk over nodes follows those sites from main to the nodes they reach,
||| visiting a node once for each set of stuck paths the chains of held
||| dispatches that reach it hold (`Heads.Visit`), its sites written at
||| the node's positions.
||| Every argument a site writes lands at a position of its callee: it is a
||| site of the growth theorem's model (`Proof.Bound.Site`), and the graph
||| is drawn from the model (`Proof.Describes`), which proves that it
||| describes it. A position whose type inspects only so much of its value
||| is capped instead: its cap is its bound, and no site into it is drawn.
||| Each position is numbered where the graph first meets it, at the place
||| of that meeting among every place it meets one, so no position is
||| looked up once numbered; that is where a position becomes a `Fin`.
module IdrisMLIR.Frontend.Growth.Graph

import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Frontend.Growth.Template
import IdrisMLIR.Frontend.Growth.Sites
import IdrisMLIR.Frontend.Growth.Implementations
import IdrisMLIR.Frontend.Growth.Heads
import IdrisMLIR.Frontend.Growth.Fields
import IdrisMLIR.Frontend.Growth.Caps
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Frontend.Finite
import IdrisMLIR.Proof.Bound
import IdrisMLIR.Proof.Describes
import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Held
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template
import Libraries.Data.List.Finite

import Control.WellFounded
import Data.DPair
import Data.Fin
import Data.List
import Data.List.Elem
import Data.List1
import Data.List.Quantifiers
import Data.Nat
import Data.So
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.Vect

%default total

||| How the values a dictionary's place holds are written on: as they are,
||| or as one of the chains of pairs a list of two up to `upTo + 1` values
||| packs to (`Proof.Held.pairChainsUpTo`), with the evidence it is one of
||| them. A writing of held values on writes the chain its packing names
||| and nothing else (`packingTemplate`).
public export
data Packing : Type where
  AsTheyAre : Packing
  Chained : (pairAt : Address) -> (upTo : Nat) -> (chain : Template) ->
            (0 listed : Elem chain (pairChainsUpTo pairAt upTo)) -> Packing

||| The template a packing writes.
public export
packingTemplate : Packing -> Template
packingTemplate AsTheyAre = Template.Var 0 0
packingTemplate (Chained _ _ chain _) = chain

||| The packings of a list of several held values, one for each length up
||| to the held count, each with the evidence it is one of the chains.
chainsUpTo : (pairAt : Address) -> (upTo : Nat) -> List Packing
chainsUpTo a m = go (pairChainsUpTo a m) (\e => e)
  where
    go : (ts : List Template) -> (0 inside : {t : Template} -> Elem t ts -> Elem t (pairChainsUpTo a m)) -> List Packing
    go [] _ = []
    go (t :: ts) inside = Chained a m t (inside Here) :: go ts (\e => inside (There e))

||| What made an arc: the site and the argument whose template gave it, a
||| value of a list a dictionary argument holds among them; an
||| implementation's method field, which placed the implementation's
||| parameter, the arc's source, among the method function's (a leading
||| arc); an implementation's field k, whose template it is; or the values
||| a dictionary's place holds, the arc's source, written on as their
||| packing says: into the pairs that hold a list of several, at most the
||| held count of them (`heldPackings`), or into the list another place is
||| given, as they are or as the one value a list of several packs to
||| (`heldWritings`).
public export
data Wrote = FromArgument Sites.Site Argument
           | ThroughMethod
           | InField Address Nat Template
           | PacksHeld Packing

||| What made an arc, with the template the arc is drawn from: a leading
||| arc passes its parameter on unchanged, so it draws a marker, and a held
||| packing draws the chain its packing names. An argument's and a field's
||| template is any. So each leading arc and each packing is measured
||| wherever it is drawn (`Proof.Describes.measuredDrawn`).
public export
data DrawnBy : Wrote -> Template -> Type where
  ArgumentDraws : DrawnBy (FromArgument s a) t
  FieldDraws : DrawnBy (InField j k f) t
  MarkerDraws : (p : Nat) -> DrawnBy ThroughMethod (Template.Var p 0)
  ChainDraws : (k : Packing) -> DrawnBy (PacksHeld k) (packingTemplate k)

-- The template a packing writes draws measured arcs only: a marker, or one
-- of the chains a list of several values packs to.
0 packingMeasured : (k : Packing) -> DrawsMeasured (packingTemplate k)
packingMeasured AsTheyAre = markerMeasured 0 0
packingMeasured (Chained a m chain listed) = listedMeasured a m listed

-- A leading arc's template draws measured arcs only.
0 methodMeasured : DrawnBy ThroughMethod t -> DrawsMeasured t
methodMeasured (MarkerDraws p) = markerMeasured p 0

-- A held packing's template draws measured arcs only.
0 packedMeasured : DrawnBy (PacksHeld k) t -> DrawsMeasured t
packedMeasured (ChainDraws k) = packingMeasured k

||| A site's writers list every parameter its template weighs with an arc,
||| with the position its writer reads it at: the positions its own arcs
||| are drawn from (`Proof.Describes.ownArcs`).
public export
0 WritersListed : {n : Nat} -> Bound.Site n -> Type
WritersListed {n} s = (i : Nat) -> (w : Weight) -> Elem (i, w) (weights s.template) -> (lab : Label) -> labelOf w = Just lab ->
                      (p : Fin n ** Elem (i, p) s.writers)

||| How a site's template was read off what its writer wrote: at a walked
||| node, the template written there read where the node's families land
||| (`withClosedFamilies` at `c`, what lands at each of the writer's
||| parameters), its writers listing every family that reading landed
||| closed, which the template no longer names, with the position its
||| writer reads it at, and its roots read there, which root a use of the
||| writer's parameter applied only where values not all closed land and
||| whatever the use is applied to (`Heads.appliedRootsOf`); or, at a held
||| position, a packing's chain as written, which applies no family.
public export
data SiteLanding : {n : Nat} -> Bound.Site n -> Type where
  LandedAtNode : {0 s : Bound.Site n} -> (c : Nat -> Landing) -> (written : Template) ->
                 s.template = withClosedFamilies c written ->
                 ((i : Nat) -> Elem i (readLanded c written).landed -> (p : Fin n ** Elem (i, p) s.writers)) ->
                 AppliedRoots c s.roots ->
                 SiteLanding s
  HeldAsWritten : SiteLanding s

||| The graph, and what its numbers stand for: the position met at each
||| place, the places where a position was first met, what made each arc,
||| and the sizes the worklist's universe needs beside the bounds.
public export
record Built where
  constructor MkBuilt
  graph : Graph
  ||| The position met at each place: a position is numbered at the place
  ||| it is first met (`firsts`), and a later meeting of it is a place no
  ||| arc or site names.
  position : Vect graph.size Spot
  ||| The places where a position was first met: the positions the arcs
  ||| join, each once.
  firsts : List (Fin graph.size)
  ||| What made each arc.
  wrote : Vect (length graph.arcs) Wrote
  ||| The most children of any template's node.
  arity : Nat
  ||| The nodes above each on the walk from main: the node that first
  ||| reached it, the one that first reached that, and so on up to main.
  reachers : SortedMap Node (List Node)
  ||| Above every reachable definition's parameter count and data type's
  ||| constructor and field counts.
  breadth : Nat
  ||| The heaviest literal or hole token any template or key holds: a key's
  ||| hole markers number the values it holds, at most the held count.
  heaviest : Nat
  ||| The growth theorem's model the graph is drawn from.
  0 model : Model graph
  ||| The graph describes its model under any feasible potential.
  0 described : (pot : Vect graph.size Nat) -> Feasible graph pot -> Describes model
  ||| A leading arc is measured: its template is a marker.
  0 methodsMeasured : (a : Fin (length graph.arcs)) -> Vect.index a wrote = ThroughMethod -> IsFinite (arc graph a).label
  ||| A held packing's arc is measured: its template is a chain of pairs or
  ||| a marker.
  0 packingsMeasured : (a : Fin (length graph.arcs)) -> (p : Packing) -> Vect.index a wrote = PacksHeld p ->
                       IsFinite (arc graph a).label
  ||| Each site's own arcs, from the positions its writer reads its
  ||| parameters at, are the graph's: the graph is drawn from the sites.
  0 ownDrawn : (s : Bound.Site graph.size) -> Elem s model.sites -> (a : Arc graph.size) -> Elem a (ownArcs s) ->
               Elem a graph.arcs
  ||| Each site's writers list every parameter its template weighs with an
  ||| arc, with the position its writer reads it at.
  0 writersListed : (s : Bound.Site graph.size) -> Elem s model.sites -> WritersListed s
  ||| How each site was read off what its writer wrote: where its node's
  ||| families land, every family the reading landed closed among its
  ||| writers, and its roots read at the same landing.
  0 landedSites : (s : Bound.Site graph.size) -> Elem s model.sites -> SiteLanding s

------------------------------------------------------------------------------
-- The definitions
------------------------------------------------------------------------------

-- What the definitions' walk found: each definition's sites, by its
-- address, read with no family headed; each definition's families, by
-- its address; the represented arguments of every data type it entered,
-- as positions; every implementation's fields, by its address; and one
-- more than the most parameters, constructors or constructor arguments
-- of any definition it entered.
record Entered where
  constructor MkEntered
  sites : SortedMap Address (List Sites.Site)
  families : SortedMap Address (List Nat)
  datas : List Spot
  fields : SortedMap Address Fields
  breadth : Nat

-- What a level of the walk has found for the next: nothing yet, or the
-- definitions found, once one was entered into the walk since the level
-- began (`w0`), which leaves fewer to enter.
data Pending : (w0, w : Walked) -> Type where
  Idle : Pending w0 w
  Queued : (0 _ : Smaller w w0) -> SnocList Name -> Pending w0 w

queued : Pending w0 w -> SnocList Name
queued Idle = [<]
queued (Queued _ next) = next

-- The arguments of a constructor a type lists: what a link's argument index
-- runs below. A name the context holds as no constructor has none to count.
constructorArity : Name -> Front (List Nat)
constructorArity n = do
  Just d <- defined n
    | Nothing => pure []
  pure $ case definition d.def of
    DCon _ k _ => [k]
    _ => []

-- What a definition's kind gives the walk: the counts its links' indices run
-- below, and how its reading (its sites and families) and its represented
-- arguments are read. The one switch on the kind, and the problem's: a
-- type constructor alone has constructors, whose fields are sites of the
-- type's, and arguments that are positions of the data it describes; every
-- other definition writes its signature and case tree.
kindOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         Address -> Defined -> Front (List Nat, Front (Reading, List Nat))
kindOf a d = case (d.matched, definition d.def) of
  (Just m, _) => pure ([length m.args], plain)
  (Nothing, TCon n _ _ _ _ cons _) => do
    let cs = fromMaybe [] cons
    arities <- traverse constructorArity cs
    pure (n :: length cs :: (arities >>= id), do
            js <- represented d
            fs <- fieldSites a d.def cs js
            rd <- readingOf a d
            pure ({ sites $= (fs ++) } rd, js))
  _ => pure ([], plain)
  where
    plain : Front (Reading, List Nat)
    plain = (, []) <$> readingOf a d

-- The definition a site enters, when it names one: a call or a build. A
-- dispatch reaches the method functions of the implementations its
-- dictionary can be, which the walk enters where each implementation is
-- written, since its body applies them; an application at a use, and a
-- choice, are no definition; a dictionary rebuilt is the writer's own,
-- entered already; and a binding's place is the writer's.
callee : Reach -> Maybe Address
callee (Calls b) = Just b
callee (Builds b) = Just b
callee (Dispatches _ _ _) = Nothing
callee Applies = Nothing
callee (Makes _) = Nothing
callee (Repacks _ _) = Nothing
callee (Keeps _ _) = Nothing

-- A definition entered: its sites by its address, its families, its
-- represented arguments as positions of its node with no heads, and its
-- fields, with the definitions its sites name, to enter next. A name that
-- no definition of the context has is no place, and is not entered.
keep : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
       Address -> Defined -> Front (Reading, List Nat) -> Entered -> Front (Entered, List Name)
keep a d reading r = do
  (rd, js) <- reading
  fs <- fieldsOf d
  defs <- getDefs
  let ss = rd.sites
  pure ( { sites $= insert a ss
         , families $= insert a rd.families
         , datas $= (map (OfParameter (OfNode (MkNode a []))) js ++)
         , fields $= maybe id (insert a) fs } r
       , mapMaybe (nameAt (gamma defs)) (mapMaybe (callee . (.reach)) ss) )

-- Walks the definitions reachable from main, breadth first, each entered
-- into the walk (`Walk`) once: the walk is the set of those, and the next
-- level is not empty only if one was entered in this one, so each level
-- starts with fewer definitions left to enter than the last. A definition
-- the checks refused is entered and measured, since it is still requested,
-- but has no sites and reaches nothing: the translation leaves it out, and
-- what only it reaches. Its fields are left out too, so that no dispatch
-- reaches a method function through it, and it has no family to be read
-- at.
level : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
        SortedSet Address -> (w0 : Walked) -> (0 acc : SizeAccessible w0) -> (w : Walked) -> (0 _ : NoMore w w0) ->
        Entered -> List Name -> Pending w0 w -> Front Entered
level refused w0 acc@(Access rec) w p r [] Idle = pure r
level refused w0 acc@(Access rec) w p r [] (Queued lt next) =
  level refused w (rec w lt) w (noMore w) r (next <>> []) Idle
level refused w0 acc@(Access rec) w p r (n :: rest) pending = do
  -- What tells definitions apart is their place in the context, as the
  -- boundary read each; a name no definition has is never entered.
  Just d <- defined n
    | Nothing => level refused w0 acc w p r rest pending
  let a = addressOf d.placement
  -- Entered already: walked once.
  let Just (Element w1 q) = enter d.placement w
    | Nothing => level refused w0 acc w p r rest pending
  (counts, reading) <- kindOf a d
  let measured = { breadth $= \b => foldl (\m, k => max m (S k)) b counts } r
  (r', next) <- if contains a refused then pure (the Entered ({ sites $= insert a [] } measured), the (List Name) []) else keep a d reading measured
  level refused w0 acc w1 (thenNoMore (fewer q) p) r' rest (Queued (fewerThen q p) (queued pending <>< next))

definitions : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Name -> Front Entered
definitions main = do
  refused <- (.refused) <$> getState
  level refused start (sizeAccessible start) start (noMore start) (MkEntered empty empty [] empty 0) [main] Idle

------------------------------------------------------------------------------
-- The universe of nodes, and novelty
------------------------------------------------------------------------------

-- Two visits, as the machine compares their parts: the definition's
-- address by its bytes, then each head by its parameter, its root's
-- address and the paths it held.
decideVisit : (x, y : Visit) -> Decided (x = y)
decideVisit (MkVisit d hs) (MkVisit d' hs') = case decideAddress d d' of
  Proof.Growth.No ne => Proof.Growth.No (\Refl => ne Refl)
  Proof.Growth.Yes Refl => case sameList decideHead hs hs' of
    Proof.Growth.No ne => Proof.Growth.No (\Refl => ne Refl)
    Proof.Growth.Yes Refl => Proof.Growth.Yes Refl
  where
    decideHeaded : (h, h' : Headed) -> Decided (h = h')
    decideHeaded (MkHeaded a s) (MkHeaded b s') = case decideAddress a b of
      Proof.Growth.No ne => Proof.Growth.No (\Refl => ne Refl)
      Proof.Growth.Yes Refl => case sameList samePath s s' of
        Proof.Growth.No ne => Proof.Growth.No (\Refl => ne Refl)
        Proof.Growth.Yes Refl => Proof.Growth.Yes Refl

    decideHead : (h, h' : (Nat, Headed)) -> Decided (h = h')
    decideHead (i, a) (j, b) = case sameNat i j of
      Proof.Growth.No ne => Proof.Growth.No (\Refl => ne Refl)
      Proof.Growth.Yes Refl => case decideHeaded a b of
        Proof.Growth.No ne => Proof.Growth.No (\Refl => ne Refl)
        Proof.Growth.Yes Refl => Proof.Growth.Yes Refl

-- A visit not yet in a list, with the erased proof.
data IsNew : Visit -> List Visit -> Type where
  New : (0 _ : Not (Elem x xs)) -> IsNew x xs

-- Whether a visit is new to a list: its proof, or nothing when it is there.
novel : (x : Visit) -> (xs : List Visit) -> Maybe (IsNew x xs)
novel x [] = Just (New (\case _ impossible))
novel x (y :: ys) = case decideVisit x y of
  Proof.Growth.Yes _ => Nothing
  Proof.Growth.No no => case novel x ys of
    Nothing => Nothing
    Just (New notIn) => Just (New (\case Here => no Refl; There e => notIn e))

conses : List a -> List (List a) -> List (List a)
conses [] _ = []
conses (x :: xs) rest = map (x ::) rest ++ conses xs rest

0 elemAppendLeft : Elem x xs -> Elem x (xs ++ ys)
elemAppendLeft Here = Here
elemAppendLeft (There e) = There (elemAppendLeft e)

0 elemAppendRight : (xs : List a) -> Elem x ys -> Elem x (xs ++ ys)
elemAppendRight [] e = e
elemAppendRight (_ :: xs) e = There (elemAppendRight xs e)

0 consesComplete : (xs : List a) -> (rest : List (List a)) -> Elem x xs -> Elem r rest -> Elem (x :: r) (conses xs rest)
consesComplete (y :: _) rest Here er = elemAppendLeft (elemMap (y ::) er)
consesComplete (y :: ys) rest (There ex) er = elemAppendRight (map (y ::) rest) (consesComplete ys rest ex er)

upTo : (k : Nat) -> List a -> List (List a)
upTo Z _ = [[]]
upTo (S k) xs = [] :: conses xs (upTo k xs)

0 upToComplete : (xs : List a) -> (k : Nat) -> (ys : List a) -> All (\y => Elem y xs) ys ->
                 LTE (length ys) k -> Elem ys (upTo k xs)
upToComplete xs Z [] _ _ = Here
upToComplete xs (S k) [] _ _ = Here
upToComplete xs Z (_ :: _) _ le = absurd le
upToComplete xs (S k) (y :: ys) (e :: es) (LTESucc le) =
  There (consesComplete xs (upTo k xs) e (upToComplete xs k ys es le))

below : (p : Nat) -> List Nat
below Z = []
below (S p) = p :: below p

0 belowComplete : (p : Nat) -> LT i p -> Elem i (below p)
belowComplete (S p) (LTESucc le) = case isLT i p of
  Yes lt => There (belowComplete p lt)
  No ge => rewrite antisymmetric le (notLTImpliesGTE ge) in Here

flatMap : (a -> List b) -> List a -> List b
flatMap f [] = []
flatMap f (x :: xs) = f x ++ flatMap f xs

pairs : List Nat -> List a -> List (Nat, a)
pairs is as = flatMap (\i => map (i,) as) is

0 pairsComplete : (is : List Nat) -> (as : List a) -> Elem i is -> Elem x as -> Elem (i, x) (pairs is as)
pairsComplete (i :: is) as Here ex = elemAppendLeft (elemMap (i,) ex)
pairsComplete (j :: is) as (There ei) ex = elemAppendRight (map (j,) as) (pairsComplete is as ei ex)

0 flatMapComplete : (f : a -> List b) -> (xs : List a) -> Elem x xs -> Elem y (f x) -> Elem y (flatMap f xs)
flatMapComplete f (x :: xs) Here ey = elemAppendLeft ey
flatMapComplete f (z :: xs) (There ex) ey = elemAppendRight (f z) (flatMapComplete f xs ex ey)

-- Every head a parameter can have: a definition at its root, holding at
-- most as many stuck paths as the program has, each one of the program's
-- (erased).
0 Headeds : Listed Address -> List (List1 Nat) -> List Headed
Headeds names ps = flatMap (\a => map (MkHeaded a) (upTo (length ps) ps)) names.values

-- Every visit of at most h heads, each at a parameter below p (erased).
0 Visits : Listed Address -> List (List1 Nat) -> (h, p : Nat) -> List Visit
Visits names ps h p = flatMap (\d => map (MkVisit d) (upTo h (pairs (below p) (Headeds names ps)))) names.values

-- A head among those: each path it holds one of the program's, and no
-- more of them than the program has (erased).
0 HeldAmong : List (List1 Nat) -> Headed -> Type
HeldAmong ps h = (All (\q => Elem q ps) h.held, LTE (length h.held) (length ps))

0 headedIn : (names : Listed Address) -> (ps : List (List1 Nat)) -> (h : Headed) -> HeldAmong ps h -> Elem h (Headeds names ps)
headedIn names ps (MkHeaded a s) (inPs, short) =
  flatMapComplete (\a' => map (MkHeaded a') (upTo (length ps) ps)) names.values (names.complete a)
    (elemMap (MkHeaded a) (upToComplete ps (length ps) s inPs short))

0 headsIn : (names : Listed Address) -> (ps : List (List1 Nat)) -> (p : Nat) -> (hs : List (Nat, Headed)) ->
            All (\e => LT (fst e) p) hs -> All (\e => HeldAmong ps (snd e)) hs ->
            All (\y => Elem y (pairs (below p) (Headeds names ps))) hs
headsIn names ps p [] [] [] = []
headsIn names ps p ((i, h) :: hs) (lt :: lts) (w :: ws) =
  pairsComplete (below p) (Headeds names ps) (belowComplete p lt) (headedIn names ps h w) :: headsIn names ps p hs lts ws

0 visitIn : (names : Listed Address) -> (ps : List (List1 Nat)) -> (h, p : Nat) -> (x : Visit) ->
            LTE (length x.heads) h -> All (\e => LT (fst e) p) x.heads -> All (\e => HeldAmong ps (snd e)) x.heads ->
            Elem x (Visits names ps h p)
visitIn names ps h p (MkVisit d hs) le lts ws =
  flatMapComplete (\d' => map (MkVisit d') (upTo h (pairs (below p) (Headeds names ps)))) names.values
    (names.complete d)
    (elemMap (MkVisit d) (upToComplete (pairs (below p) (Headeds names ps)) h hs (headsIn names ps p hs lts ws) le))

------------------------------------------------------------------------------
-- The nodes
------------------------------------------------------------------------------

-- The room the universe leaves a path (erased).
0 Room : Listed Address -> List (List1 Nat) -> Nat -> List Visit -> Nat
Room names ps b path = minus (length (Visits names ps b b)) (length path)

-- What the walk has found: every visit entered, once (a run-time set, no
-- proof: skipping needs none), each with what its sites reach, and each
-- node's reachers, the path its visit was entered below: the node that
-- first reached it, nearest first, back to main.
record Found where
  constructor MkFound
  entered : SortedSet Visit
  done : SnocList (Visit, List (Sites.Site, Reached))
  reachers : SortedMap Node (List Node)

-- Where the walk over nodes stops, either a broken invariant of the
-- graph's own construction that would lose a visit's arcs if the visit
-- were skipped: a visit outside the universe, split at a head where no
-- site writes one, or holding a path no site re-packs; or a visit at
-- heads the flow did not give, with no reading.
data Stray = Outside Visit | Unheaded Visit

-- A visit of the universe, with its erased membership.
data Inside : Listed Address -> List (List1 Nat) -> Nat -> Visit -> Type where
  In : {0 names : Listed Address} -> {0 ps : List (List1 Nat)} -> {0 b : Nat} -> {0 x : Visit} ->
       (0 _ : Elem x (Visits names ps b b)) -> Inside names ps b x

-- Every head at a parameter below b, as the machine compares them.
lowHeads : Nat -> List (Nat, a) -> Bool
lowHeads b [] = True
lowHeads b ((i, _) :: hs) = i < b && lowHeads b hs

0 lowHeadsSo : (b : Nat) -> (hs : List (Nat, a)) -> So (lowHeads b hs) -> All (\e => LT (fst e) b) hs
lowHeadsSo b [] _ = []
lowHeadsSo b ((i, _) :: hs) so = let (lt, rest) = soAnd so in Proof.Growth.ltSo lt :: lowHeadsSo b hs rest

-- Every path of a list among the program's, as the machine compares
-- them: the erased evidence, or nothing.
amongAll : (ps : List (List1 Nat)) -> (qs : List (List1 Nat)) -> Maybe (Subset () (\_ => All (\q => Elem q ps) qs))
amongAll ps [] = Just (Element () [])
amongAll ps (q :: qs) = case (pathAmong q ps, amongAll ps qs) of
  (Proof.Growth.Yes e, Just (Element () es)) => Just (Element () (e :: es))
  _ => Nothing

-- Every head's paths among the program's, and no more of them than it
-- has: the erased evidence, or nothing.
withinPaths : (ps : List (List1 Nat)) -> (hs : List (Nat, Headed)) -> Maybe (Subset () (\_ => All (\e => HeldAmong ps (snd e)) hs))
withinPaths ps [] = Just (Element () [])
withinPaths ps ((_, h) :: hs) = case (amongAll ps h.held, choose (length h.held <= length ps), withinPaths ps hs) of
  (Just (Element () inPs), Left short, Just (Element () rest)) => Just (Element () ((inPs, Proof.Growth.lteSo short) :: rest))
  _ => Nothing

-- A visit's evidence of being in the universe, or nothing: the machine's
-- comparisons, read as the erased membership, with no proof built at run
-- time. Each path a head holds is searched for among the program's few.
inside : (0 names : Listed Address) -> (ps : List (List1 Nat)) -> (b : Nat) -> (x : Visit) -> Maybe (Inside names ps b x)
inside names ps b x = case (choose (length x.heads <= b), choose (lowHeads b x.heads), withinPaths ps x.heads) of
  (Left short, Left low, Just (Element () held)) =>
    Just (In (visitIn names ps b b x (Proof.Growth.lteSo short) (lowHeadsSo b x.heads low) held))
  _ => Nothing

-- The walk is depth first, and a visit's newness is decided against its
-- own path from main, which is no longer than the walk is deep: one
-- novelty test per visit entered, so O(visits x depth), where a global
-- list with proofs costs a comparison per pair, about 87 million at the
-- self compile's 13,218 nodes (measured). A visit met again off its path
-- is skipped by the run-time set, which needs no proof.
mutual
  -- Enters a visit new to its path from main: its sites' callees are
  -- walked below it, each new to the longer path, which leaves less room.
  visit : (0 names : Listed Address) -> (ps : List (List1 Nat)) -> (b : Nat) ->
          (out : Visit -> Maybe (List (Sites.Site, Reached))) -> (x : Visit) -> (path : List Visit) ->
          (0 nd : NoDup (x :: path)) -> (0 inU : All (\y => Elem y (Visits names ps b b)) (x :: path)) ->
          (0 acc : Accessible LT (Room names ps b (x :: path))) -> Found -> Either Stray Found
  visit names ps b out x path nd inU acc found = case out x of
    Nothing => Left (Unheaded x)
    Just edges =>
      under names ps b out x path nd inU acc (mapMaybe (\(_, e) => calleeVisit e) edges)
            ({ done $= (:< (x, edges)) } found)
    where
      -- The application at a use is no node, nor is a choice, nor a
      -- rebuilt constructor's fields, nor a binding's place, and the walk
      -- enters nothing there: what each holds, the sites into it bound.
      calleeVisit : Reached -> Maybe Visit
      calleeVisit (MkReached (Entering c) _ _) = Just c
      calleeVisit (MkReached Applying _ _) = Nothing
      calleeVisit (MkReached (Making _) _ _) = Nothing
      calleeVisit (MkReached (Filling _) _ _) = Nothing
      calleeVisit (Kept _ _) = Nothing

  under : (0 names : Listed Address) -> (ps : List (List1 Nat)) -> (b : Nat) ->
          (out : Visit -> Maybe (List (Sites.Site, Reached))) -> (x : Visit) -> (path : List Visit) ->
          (0 nd : NoDup (x :: path)) -> (0 inU : All (\y => Elem y (Visits names ps b b)) (x :: path)) ->
          (0 acc : Accessible LT (Room names ps b (x :: path))) -> List Visit -> Found -> Either Stray Found
  under names ps b out x path nd inU acc [] found = Right found
  under names ps b out x path nd inU acc@(Access rec) (c :: cs) found =
    if contains c found.entered then under names ps b out x path nd inU acc cs found else
    case inside names ps b c of
      -- Outside the universe: a head where no site writes one, so that the
      -- visit's arcs would be lost if it were skipped.
      Nothing => Left (Outside c)
      Just (In cIn) => case novel c (x :: path) of
        -- On its own path: entered already, so the set holds it.
        Nothing => under names ps b out x path nd inU acc cs found
        Just (New notIn) =>
          let found' = { entered $= insert c, reachers $= insert (visitNode c) (map visitNode (x :: path)) } found in
          case visit names ps b out c (x :: path) (notIn :: nd) (cIn :: inU)
                 (rec _ (room (notIn :: nd) (cIn :: inU))) found' of
            Left bad => Left bad
            Right after => under names ps b out x path nd inU acc cs after

nodesFrom : (0 names : Listed Address) -> (ps : List (List1 Nat)) -> (b : Nat) ->
            (out : Visit -> Maybe (List (Sites.Site, Reached))) -> Visit -> Either Stray Found
nodesFrom names ps b out root = case inside names ps b root of
  Nothing => Left (Outside root)
  Just (In rIn) => visit names ps b out root [] ((\case _ impossible) :: []) [rIn] (sizeAccessible _)
                     (MkFound (insert root empty) [<] empty)

-- The walk over the real listing, named through an alias on a right-hand
-- side: a lower-case global written in a type is bound as a new implicit.
nodesFromMain : (ps : List (List1 Nat)) -> (b : Nat) -> (out : Visit -> Maybe (List (Sites.Site, Reached))) -> Visit ->
                Either Stray Found
nodesFromMain ps b out root = let 0 names = addresses in nodesFrom names ps b out root

-- The bound on a node's heads, b. A head sits at a dictionary parameter of
-- its definition, by index, where a site's argument lands: a call's
-- argument j at j; a dispatch's own argument at the parameter of the
-- method function that its field's `own` placement names; and the
-- implementation's parameters at those its `leading` placement names. So
-- every index is at most the largest of these, and below one more; an
-- ascending list of distinct indices below it is no longer than it. It is
-- one fold over every node's reading and every implementation's fields: a
-- list of every index, joined first by `concatMap`, which folds `++` from
-- the left, would be copied again at each join.
headBound : SortedMap Address Fields -> List (List Sites.Site) -> Nat
headBound fs ss = S (foldl (\m, f => foldl placedIn m f.inOrder) (foldl (foldl written) 0 ss) (values fs))
  where
    written : Nat -> Sites.Site -> Nat
    written m s = foldl (\m', x => max m' x.position) m s.arguments

    placedIn : Nat -> Implementations.Field -> Nat
    placedIn m (Method _ _ own leading) = foldl max (foldl (\m', (_, q) => max m' q) m leading) own
    placedIn m (Dictionary _ _ _ _) = m
    placedIn m (Plain _ _) = m

------------------------------------------------------------------------------
-- The arcs
------------------------------------------------------------------------------

-- What lands at one position twice: a value that computes, closed values
-- no higher than the taller height, closed values some of which compute,
-- or values not all closed. A closed inert value's term is not kept, so
-- with closed computing ones beside it the position is evaluated at none.
joinLanding : Landing -> Landing -> Landing
joinLanding Computed _ = Computed
joinLanding _ Computed = Computed
joinLanding (Evaluable a) (Evaluable b) = Evaluable (a ++ b)
joinLanding (Evaluable _) _ = Computed
joinLanding _ (Evaluable _) = Computed
joinLanding (Closed a) (Closed b) = Closed (max a b)
joinLanding _ _ = Open

-- What an argument is, landing: a choice of implementation made at run
-- time, or a function that gives one at each use (a rank-2 dictionary),
-- which an application of it does not beta-reduce but gives one of its
-- members of, so it lands as a value no closed reading bounds; a closed
-- value that computes (`beta`), which is its term; any other that
-- computes; a closed one no higher than its height; or one whose height
-- an arc carries.
landingOf : Argument -> Landing
landingOf x = case x.root of
  Template.Chosen _ => Open
  Template.Gives _ => Open
  _ => case (beta x.template, selfBounded x.template, x.term) of
    (Computes, True, Just tm) => Evaluable [tm]
    (Computes, _, _) => Computed
    (Inert, True, _) => Closed (height x.template)
    (Inert, False, _) => Open

-- The walked edges' one traversal, which every reading of what they place
-- shares: each argument placed, in the walk's order, with the node whose
-- site wrote it, the site, and what it reaches. A binding's place is
-- given no argument.
eachPlaced : (r -> Node -> Sites.Site -> Callee -> Placed -> r) -> r -> List (Node, List (Sites.Site, Reached)) -> r
eachPlaced f = foldl (\acc, (w, edges) => foldl (\acc', (s, e) => case e of
                                                   MkReached callee placed _ => foldl (\acc'', pl => f acc'' w s callee pl) acc' placed
                                                   Kept _ _ => acc')
                                                acc edges)

-- Each method function's node a dispatch reached through implementation
-- J's method field k, with where that field places J's parameters among
-- the method function's, once however many dispatches reach it.
Leads : Type
Leads = SortedMap (Node, Address, Nat) (List (Nat, Nat))

leadsOf : List (Node, List (Sites.Site, Reached)) -> Leads
leadsOf walked = foldl (\m, (_, edges) => foldl lead m edges) empty walked
  where
    lead : Leads -> (Sites.Site, Reached) -> Leads
    lead m (_, MkReached (Entering callee) _ (Dispatched j k leading)) = insert (visitNode callee, j, k) leading m
    -- Essential: a call, a build, an application and a binding place no
    -- implementation's parameters, and a dispatch reaches a method
    -- function's node.
    lead m _ = m

-- A value landing at a position, with what landed there before.
put : Spot -> Landing -> SortedMap Spot Landing -> SortedMap Spot Landing
put p l m = insert p (maybe l (joinLanding l) (lookup p m)) m

-- Where values no writing states land as well, so nothing there is
-- closed: at a capped position, every value of the cap's height.
opened : List Spot -> SortedMap Spot Landing -> SortedMap Spot Landing
opened ps m = foldl (\acc, p => put p Open acc) m ps

-- Where each numbered position carries a family's value on, keyed by the
-- source's number and by the target's: from each position of the writer
-- whose family an argument passes on or applies (`familiesIn`), into the
-- argument's position; and from each position of an implementation J,
-- into the method function's position its leading placement gives, from
-- every walked node of J, which can only carry more. A position where
-- nothing lands has no number, and nothing computing to carry.
record Carrying (n : Nat) where
  constructor MkCarrying
  onward : SortedMap Nat (List (Fin n))
  back : SortedMap Nat (List (Fin n))

carried : {0 n : Nat} -> SortedMap Spot (Fin n) -> SortedMap Address (List Node) -> Leads ->
          List (Node, List (Sites.Site, Reached)) -> Carrying n
carried number nodes leads walked =
  let cs = eachPlaced (\acc, w, s, callee, pl =>
                         foldl (\acc', i => carry (spotAt w s.params i) (landsAt callee pl.parameter) acc') acc (familiesIn pl.argument.template))
                      (MkCarrying empty empty) walked in
  foldl (\acc, ((callee, j, _), pqs) =>
           foldl (\acc', (p, q) => foldl (\acc'', x => carry (OfParameter (OfNode x) p) (OfParameter (OfNode callee) q) acc'') acc'
                                          (fromMaybe [] (lookup j nodes)))
                 acc pqs)
        cs (SortedMap.toList leads)
  where
    add : Fin n -> Fin n -> SortedMap Nat (List (Fin n)) -> SortedMap Nat (List (Fin n))
    add a b m = insert (finToNat a) (b :: fromMaybe [] (lookup (finToNat a) m)) m

    carry : Spot -> Spot -> Carrying n -> Carrying n
    carry p q cs = case (lookup p number, lookup q number) of
      (Just a, Just b) => MkCarrying (add a b cs.onward) (add b a cs.back)
      _ => cs

-- The templates of the values of a type an argument's lists hold, each
-- reading of each.
heldTemplates : Argument -> List Template
heldTemplates x = x.holds >>= \l => forget l >>= typed
  where
    typed : HeldItem -> List Template
    typed (OfType xs) = map (.template) (forget xs)
    typed (PackedBy _) = []
    typed (EachOf _) = []
    typed (MembersOf _) = []

-- The numbered positions an applied family's reading reads the landing
-- of (`applyingIn`), at the nodes whose sites apply it, in an argument or
-- in a value of a type its lists hold.
applying : {0 n : Nat} -> SortedMap Spot (Fin n) -> List (Node, List (Sites.Site, Reached)) -> List (Fin n)
applying number =
  eachPlaced (\acc, w, s, _, pl => mapMaybe (\i => lookup (spotAt w s.params i) number)
                                            ((pl.argument.template :: heldTemplates pl.argument) >>= applyingIn) ++ acc) []

-- How many positions a walk has not visited.
unvisited : Vect n Bool -> Nat
unvisited [] = 0
unvisited (b :: bs) = (if b then 0 else 1) + unvisited bs

-- A position marked visited.
mark : Fin n -> Vect n Bool -> Vect n Bool
mark FZ (_ :: bs) = True :: bs
mark (FS x) (b :: bs) = b :: mark x bs

-- Visiting a position not visited leaves one fewer.
0 visitLeaves : (x : Fin n) -> (vis : Vect n Bool) -> Vect.index x vis = False -> LT (unvisited (mark x vis)) (unvisited vis)
visitLeaves FZ (False :: bs) _ = reflexive
visitLeaves FZ (True :: bs) eq = absurd eq
visitLeaves (FS x) (False :: bs) eq = LTESucc (visitLeaves x bs eq)
visitLeaves (FS x) (True :: bs) eq = visitLeaves x bs eq

-- A flag, with what it is.
flag : (b : Bool) -> Either (b = True) (b = False)
flag True = Left Refl
flag False = Right Refl

-- Every position reachable from the queue along the carries, each once,
-- with those found before: a walk that visits each position once, so each
-- visit leaves fewer unvisited, the measure it recurses on; nothing counts
-- its steps.
spread : (next : Fin n -> List (Fin n)) -> (vis : Vect n Bool) -> (0 acc : Accessible LT (unvisited vis)) ->
         (found : List (Fin n)) -> List (Fin n) -> List (Fin n)
spread next vis _ found [] = found
spread next vis (Access rec) found (x :: xs) = case flag (Vect.index x vis) of
  Left _ => spread next vis (Access rec) found xs
  Right fresh => spread next (mark x vis) (rec _ (visitLeaves x vis fresh)) (x :: found) (next x ++ xs)

-- What lands at every position, from what lands where it is written
-- (`landedAt`, `opened`), with a computing value carried on to every
-- position that carries a family's value on from where one lands: a
-- family whose value can be one there may compute when it is applied,
-- wherever the value was written. Only a position an applied family's
-- reading reads, or one that carries on to it, is asked, so the carrying
-- runs over those alone: a type's marker passed on carries no family, and
-- nothing applies it. With no computing value written there is nothing to
-- carry.
landings : SortedMap Address (List Node) -> Leads -> List (Node, List (Sites.Site, Reached)) ->
           SortedMap Spot Landing -> SortedMap Spot Landing
landings nodes leads walked at =
  let ps = keys at
      number = SortedMap.fromList (zip ps (indices ps))
      seeds = mapMaybe (\(p, l) => case l of
                                      Computed => lookup p number
                                      Evaluable _ => lookup p number
                                      _ => Nothing) (SortedMap.toList at) in
  case seeds of
    [] => at
    _ :: _ =>
      let cs = carried number nodes leads walked
          asked = spread (\x => fromMaybe [] (lookup (finToNat x) cs.back)) (replicate (length ps) False) (wellFounded _) []
                         (applying number walked)
          askedSet = SortedSet.fromList (map finToNat asked)
          onward = \x => filter (\y => contains (finToNat y) askedSet) (fromMaybe [] (lookup (finToNat x) cs.onward))
          -- What a computing value is carried on to: a position it lands
          -- at as written keeps its landing (an evaluable one its values).
          found = spread onward (replicate (length ps) False) (wellFounded _) []
                         (filter (\x => contains (finToNat x) askedSet) seeds >>= onward)
          byNumber = Vect.fromList ps in
      foldl (\m, x => insert (Vect.index x byNumber) Computed m) at found

-- At node w, what lands at each parameter as `ps` reads it (`Landing`);
-- nothing landed is no closed value.
closedAt : SortedMap Spot Landing -> Node -> Parameters -> Nat -> Landing
closedAt ls w ps i = fromMaybe Open (lookup (spotAt w ps i) ls)

-- Where a writing's writer is read: at a walked node, its parameters as
-- its site reads them, where the node's families land and the flow roots
-- its dictionaries; or, for the values a dictionary's place holds written
-- on, at the held position they come from, whose template applies no
-- family and holds no dictionary of its own.
data WriterAt = AtNode Node Parameters | AtHeld

-- What one template wrote, before its writer's families are read where
-- they land: where its writer reads each of its parameters, the template
-- as written, where its writer is (`WriterAt`), the position it lands at,
-- and what wrote it, with the template it draws. What lands at a position
-- is read off these, every writing the model holds among them
-- (`landedAt`), and only then is each read where its writer is
-- (`readAtWriter`), so no writing lands unseen by the landing it is read
-- at.
record Written where
  constructor MkWritten
  reads : Nat -> Spot
  template : Template
  writer : WriterAt
  target : Spot
  wrote : Wrote
  0 draws : DrawnBy wrote template

-- What a writing lands as at its position: an argument as its landing
-- reads it (`landingOf`); a leading arc's marker, a field's template, a
-- held value and a held packing's chain as values no closed reading
-- bounds, since each writes what its writer's own writers gave it.
landedBy : Wrote -> Landing
landedBy (FromArgument _ x) = landingOf x
landedBy ThroughMethod = Open
landedBy (InField _ _ _) = Open
landedBy (PacksHeld _) = Open

-- What lands at each position, joined from every writing there: a
-- position is closed only where every writing there is an argument whose
-- own landing is closed.
landedAt : List Written -> SortedMap Spot Landing
landedAt xs = foldl (\m, x => put x.target (landedBy x.wrote) m) empty xs

-- The positions some writings land at, each once.
targetsOf : List Written -> List Spot
targetsOf xs = SortedSet.toList (foldl (\acc, x => insert x.target acc) empty xs)

-- Where a writing's template was read, with the families that reading
-- landed closed and the roots read with it: at a walked node, the
-- template written there read where the node's families land
-- (`readLanded`), its roots read at the same landing (`Heads.roots`); or,
-- at a held position, a packing's chain as written, which lands none.
data ReadAt : Template -> List Nat -> (Template -> List Address) -> Type where
  ReadAtNode : (c : Nat -> Landing) -> (written : Template) -> AppliedRoots c rts ->
               ReadAt (readLanded c written).template (readLanded c written).landed rts
  ReadAsHeld : ReadAt t [] rts

-- What the graph draws for one template, read where its writer is
-- (`readAtWriter`): where its writer reads each of its parameters (a walked
-- node's position, as the site reads its parameters; for values a
-- dictionary holds written on, the held position they come from), the
-- template, read where a node's families hold what lands at them
-- (`withClosedFamilies`), the roots the flow gives its dictionaries there,
-- the position it lands at, and what wrote it, with the template it draws;
-- and the families its reading landed closed, with where it was read.
record Writing where
  constructor MkWriting
  reads : Nat -> Spot
  template : Template
  roots : Template -> List Address
  target : Spot
  wrote : Wrote
  0 draws : DrawnBy wrote template
  landed : List Nat
  0 readAt : ReadAt template landed roots

-- A pair's chain applies no family, so reading it where a node's
-- families land leaves it as it is.
0 chainRead : (c : Nat -> Landing) -> (a : Address) -> (n : Nat) -> withClosedFamilies c (pairChain a n) = pairChain a n
chainRead c a Z = Refl
chainRead c a (S n) = cong (\u => Template.Head (Just a) [Template.Var 0 0, u]) (chainRead c a n)

0 chainsRead : (c : Nat -> Landing) -> (a : Address) -> (m : Nat) -> Elem t (pairChainsUpTo a m) ->
               withClosedFamilies c t = t
chainsRead c a Z el = absurd el
chainsRead c a (S m) Here = chainRead c a (S m)
chainsRead c a (S m) (There el) = chainsRead c a m el

0 packingRead : (c : Nat -> Landing) -> (k : Packing) -> withClosedFamilies c (packingTemplate k) = packingTemplate k
packingRead c AsTheyAre = Refl
packingRead c (Chained a m _ listed) = chainsRead c a m listed

-- What made a writing holds of its template read where its writer's
-- families land: an argument's and a field's template is any, and a
-- leading arc's marker and a held packing's chain apply no family.
0 drawnRead : (c : Nat -> Landing) -> DrawnBy w t -> DrawnBy w (withClosedFamilies c t)
drawnRead c ArgumentDraws = ArgumentDraws
drawnRead c FieldDraws = FieldDraws
drawnRead c (MarkerDraws p) = MarkerDraws p
drawnRead c (ChainDraws k) = replace {p = DrawnBy (PacksHeld k)} (sym (packingRead c k)) (ChainDraws k)

-- A node's families, by index, as its definition's walk found them: what
-- `roots` reads no implementation off where it is applied.
familiesOf : SortedMap Address (List Nat) -> Node -> List Nat
familiesOf families w = fromMaybe [] (lookup w.definition families)

-- A writing at a node, its template read once where the node's families
-- land (`readLanded`): the template the graph draws and the families that
-- reading landed closed are the one reading's, and its roots are read at
-- the same landing.
landedWriting : (Nat -> Spot) -> (rts : Template -> List Address) -> Spot -> (wr : Wrote) -> (c : Nat -> Landing) ->
                (0 _ : AppliedRoots c rts) -> (t : Template) -> (0 _ : DrawnBy wr t) -> Writing
landedWriting rs rts tgt wr c applied t made = fromReading (readLanded c t) (ReadAtNode c t applied) (drawnRead c made)
  where
    fromReading : (r : LandedReading) -> (0 _ : ReadAt r.template r.landed rts) -> (0 _ : DrawnBy wr r.template) -> Writing
    fromReading r at drawn = MkWriting rs r.template rts tgt wr drawn r.landed at

-- A writing read where its writer is: at a node, its template read where
-- the node's families land, and its dictionaries rooted as the flow found
-- them there, a use of one only where the template still applies it
-- (`Heads.roots`); at a held position, as written, rooting nothing.
readAtWriter : Flow -> SortedMap Address (List Nat) -> SortedMap Spot Landing -> Written -> Writing
readAtWriter fl families ls (MkWritten rs t (AtNode w ps) tgt wr made) =
  let c = closedAt ls w ps in
  landedWriting rs (roots fl (familiesOf families w) w ps c) tgt wr c (appliedRootsOf fl (familiesOf families w) w ps c) t made
readAtWriter fl families ls (MkWritten rs t AtHeld tgt wr made) = MkWriting rs t (const []) tgt wr made [] ReadAsHeld

-- Every walked edge's arguments, each at the callee parameter `reaches`
-- placed it at, the latest first, as the check has always read them.
writings : List (Node, List (Sites.Site, Reached)) -> List Written
writings =
  eachPlaced (\acc, w, s, callee, pl =>
                MkWritten (spotAt w s.params) pl.argument.template (AtNode w s.params) (landsAt callee pl.parameter)
                          (FromArgument s pl.argument) ArgumentDraws :: acc) []

-- What a dispatch that reached M through implementation J's method field
-- writes at M's leading parameters. The parameters of M its `leading`
-- placement names hold J's own, which the writers of J gave it, so each
-- walked node of J whose heads agree with M's there writes its own
-- parameter p, unchanged, at M's q. J's own call of M passes its method
-- dictionaries as run-time values, with no roots, and reaches another node
-- of M, so without these M's leading positions would have no writer.
leadingWritings : SortedMap Address (List Node) -> Leads -> List Written
leadingWritings nodes leads =
  SortedMap.toList leads >>= \((m, j, _), leading) =>
    [ MkWritten (spotAt jn OwnOnly) (Template.Var p 0) (AtNode jn OwnOnly) (OfParameter (OfNode m) q) ThroughMethod (MarkerDraws p)
    | jn <- fromMaybe [] (lookup j nodes), agrees m leading jn, (p, q) <- leading ]
  where
    -- Two heads at a parameter agree: none on either side, or one
    -- implementation on both. A dictionary without a root has no head.
    agreesAt : Node -> Node -> (Nat, Nat) -> Bool
    agreesAt m jn (p, q) = case sameMaybe decideAddress (lookup p jn.heads) (lookup q m.heads) of
      Proof.Growth.Yes _ => True
      Proof.Growth.No _ => False

    agrees : Node -> List (Nat, Nat) -> Node -> Bool
    agrees m leading jn = all (agreesAt m jn) leading

-- What each implementation's fields write at their positions: at each
-- walked node of the implementation, each field's template over the
-- node's parameters, read where the node's families hold what lands at
-- them (`readAtWriter`), into that field's position. A field read
-- anywhere takes its value from there, so a nested field read is arcs
-- between these positions.
fieldWritings : SortedMap Address (List Node) -> SortedMap Address Fields -> List Written
fieldWritings nodes fs =
  SortedMap.toList fs >>= \(j, fields) =>
    [ MkWritten (spotAt jn OwnOnly) t (AtNode jn OwnOnly) (OfField j k) (InField j k t) FieldDraws
    | jn <- fromMaybe [] (lookup j nodes), (k, t) <- numbered 0 (map (fst . fieldRead) fields.inOrder) ]
  where
    numbered : Nat -> List Template -> List (Nat, Template)
    numbered k [] = []
    numbered k (t :: ts) = (k, t) :: numbered (S k) ts

------------------------------------------------------------------------------
-- Held values
------------------------------------------------------------------------------

-- What the held count is read off, from every reading's sites, once: the
-- most values a place gives a dictionary or a binding keeps, the most a
-- member closes over, and each distinct path at which a match finds a
-- field of its writer's dictionary stuck, which are also every path a
-- chain of held dispatches can hold (`Heads.Headed`).
record Counted where
  constructor MkCounted
  packed : Nat
  member : Nat
  paths : SortedSet (List1 Nat)

countedIn : List (List Sites.Site) -> Counted
countedIn = foldl (foldl counted) (MkCounted 0 0 empty)
  where
    -- The longest list an argument of a site holds.
    longest : List Argument -> Nat
    longest = foldl (\m, x => foldl (\m', l => max m' (length (forget l))) m x.holds) 0

    counted : Counted -> Sites.Site -> Counted
    counted c s = case s.reach of
      Makes _ => { member $= max (longest s.arguments) } c
      Repacks _ path => { paths $= insert path } c
      Calls _ => { packed $= max (longest s.arguments) } c
      Builds _ => { packed $= max (longest s.arguments) } c
      Dispatches _ _ _ => { packed $= max (longest s.arguments) } c
      Applies => { packed $= max (longest s.arguments) } c
      Keeps _ items => { packed $= max (length (forget items)) } c

||| The most values one list of held values holds (`Closed.packedType`), a
||| constant of the graph derived from the program: the most a place that
||| gives a dictionary a list gives, or a binding keeps, a dictionary of
||| the writer's that holds values held as one value among them; and, for
||| each distinct path at which a match finds a field of its writer's
||| dictionary stuck, one more for the field, held after the list's values,
||| and the most values a member closes over, which a dispatch on the
||| field's choice puts in its place. A request that passes a dictionary on
||| as it was given gives no new list. It rests on two facts of the
||| translation: a chain of requests holds each path at most once, and
||| every member a dispatch puts in reduces, so no match finds that path
||| stuck again below it.
heldCount : Counted -> Nat
heldCount found = foldl (\h, _ => h + S found.member) found.packed (SortedSet.toList found.paths)

-- The one value a dictionary's list of several values packs to, over the
-- held position of those values, at each length the list can have: from
-- two values up to the held count, one pair fewer than values
-- (`chainsUpTo`). With no pair in the context, no list is in pairs.
packedHeld : Maybe Pairing -> (count : Nat) -> List Packing
packedHeld Nothing _ = []
packedHeld (Just pg) count = chainsUpTo pg.pairAddress (pred count)

||| What every pair that holds a list of several values is given
||| (`Closed.packedType`, `Closed.unpacked`), written from each place's
||| held position of its lists of several, since no writer's site knows
||| the list: at the pair's first and at a projection's, one value; at its
||| rest, the rest of a list, from one value up to the held count less
||| one, each but the last in a pair with what follows it. Every value
||| such a list holds is bounded at that position, so the rest of every
||| list no longer than the count is one of these: each pair's position is
||| bounded by the count above the values' heights, and no arc leaves a
||| pair's position for a held one, so none of these is on a cycle.
heldPackings : (count : Nat) -> Maybe Pairing -> List HeldBy -> List Written
heldPackings count Nothing _ = []
heldPackings count (Just pg) places = case pred count of
    -- Essential: a list of fewer than two values is held as itself, in no
    -- pair.
    Z => []
    S n => places >>= written n
  where
    -- At the pair's first, one value; at its rest, one value or the rest
    -- of a list of 3 up to n + 2 values, in pairs.
    written : Nat -> HeldBy -> List Written
    written n place =
      [ MkWritten (const (OfHeld (MkHeldValues place InPairs))) (packingTemplate k) AtHeld
                  (OfParameter (OfNode (MkNode h [])) j) (PacksHeld k) (ChainDraws k)
      | h <- [pg.pairAddress, pg.firstAddress, pg.secondAddress]
      , (j, k) <- (0, AsTheyAre) :: map (1,) (AsTheyAre :: chainsUpTo pg.pairAddress n) ]

-- What a value of a list is to its instances (`Proof.Held.ItemKind`): a
-- value of a type the walk knows is one value in every list it describes;
-- a dictionary's values packed as one are one value where it holds any;
-- the values a dictionary or a member holds, each as itself, are as many
-- as it holds.
itemKind : HeldItem -> ItemKind
itemKind (OfType _) = AlwaysOne
itemKind (PackedBy _) = AtMostOne
itemKind (EachOf _) = AnyNumber
itemKind (MembersOf _) = AnyNumber

-- One way a value of a list is written at a held position: where its
-- template reads its variables, the template, where its writer is
-- (`WriterAt`), how many values it brings (`Proof.Held.Brings`), and what
-- wrote it, with the template it draws.
record Contribution where
  constructor MkContribution
  reads : Nat -> Spot
  template : Template
  writer : WriterAt
  brings : Brings
  wrote : Wrote
  0 draws : DrawnBy wrote template

-- The held positions a way of writing a value lands at, where `firm`
-- other values of its list are always there and `others` are there in
-- all, as the two decisions of where a held value is written say: the
-- position of the lists of one value where it can be its list's one
-- value (`canBeAlone`), and that of the lists of several where it can be
-- one of two or more (`canBeAmong`).
landing : (firm, others : Nat) -> Brings -> List Packed
landing firm others b = alone (canBeAlone firm others b) ++ among (canBeAmong firm others b)
  where
    alone : Decided (Alone firm others b) -> List Packed
    alone (Proof.Growth.Yes _) = [AsItself]
    alone (Proof.Growth.No _) = []

    among : Decided (Among firm others b) -> List Packed
    among (Proof.Growth.Yes _) = [InPairs]
    among (Proof.Growth.No _) = []

-- The choices given lists that a member of choice k is read from: its
-- own, and the one whose head only an instance shows, which may be k; at
-- that unshown head, every choice (`Heads.membersAt`).
choicePlaces : List ChoiceHead -> ChoiceHead -> List ChoiceHead
choicePlaces given UnshownHead = given
choicePlaces given k = filter (\c => c == k || c == UnshownHead) given

-- The choices some member of which is given values to hold.
heldChoices : List (Node, List (Sites.Site, Reached)) -> List ChoiceHead
heldChoices walked = SortedSet.toList (eachPlaced (\acc, _, _, callee, pl => case (callee, pl.argument.holds) of
                                                     (Making k, _ :: _) => insert k acc
                                                     _ => acc)
                                                  empty walked)

||| What every place that gives a dictionary a list of values writes at the
||| held positions of the place the dictionary lands at (`calleePlace`):
||| each value of each list, at the position of that place's lists of one
||| value where it can be the list's one value, and at that of its lists
||| of several where it can be one of two or more (`landing`). A value of
||| a type the walk knows is its template over the writer's parameters, as
||| any argument's is. A dictionary parameter of the writer's held as one
||| value is read from its place's held positions: from its lists of one
||| value as it is, held as itself, and from its lists of several as the
||| pairs of each length hold them (`packedHeld`), the arcs whose gain a
||| recursion that wraps a dictionary deeper at each call adds up round
||| its cycle; and so is a dictionary the writer binds, from its binding's
||| place, which the list of what it closes over is written at, as a
||| given list is. The values a dictionary parameter holds, each as
||| itself, and those a member holds, come from their places' held
||| positions as they are.
heldWritings : (count : Nat) -> Maybe Pairing -> List ChoiceHead -> List (Node, List (Sites.Site, Reached)) -> List Written
heldWritings count pg choices walked =
  eachPlaced (\acc, w, s, callee, pl =>
                (pl.argument.holds >>= \l => listAt w s (calleePlace callee pl.parameter).fst (forget l)) ++ acc) [] walked
    ++ (walked >>= \(w, edges) => edges >>= \(s, e) => kept w s e)
  where
    fromHeld : HeldBy -> Packed -> Packing -> Brings -> Contribution
    fromHeld place p k b =
      MkContribution (const (OfHeld (MkHeldValues place p))) (packingTemplate k) AtHeld b (PacksHeld k) (ChainDraws k)

    -- The place a dictionary of the writer's that holds values as one is
    -- at, at the writer's node.
    ownPlace : Node -> Sites.Site -> OwnHolder -> HeldBy
    ownPlace w s (OwnParameter i) = (writerPlace w s.params i).fst
    ownPlace w s (OwnBinding b) = ByBinding w b

    contributions : Node -> Sites.Site -> HeldItem -> List Contribution
    contributions w s (OfType xs) =
      [ MkContribution (spotAt w s.params) x.template (AtNode w s.params) OneValue (FromArgument s x) ArgumentDraws
      | x <- forget xs ]
    contributions w s (PackedBy h) =
      fromHeld (ownPlace w s h) AsItself AsTheyAre OneValue ::
        map (\k => fromHeld (ownPlace w s h) InPairs k OneValue) (packedHeld pg count)
    contributions w s (EachOf i) =
      [ fromHeld (writerPlace w s.params i).fst AsItself AsTheyAre OneValue
      , fromHeld (writerPlace w s.params i).fst InPairs AsTheyAre SeveralValues ]
    contributions w s (MembersOf k) =
      choicePlaces choices k >>= \c =>
        [ fromHeld (ByChoice c) AsItself AsTheyAre OneValue
        , fromHeld (ByChoice c) InPairs AsTheyAre SeveralValues ]

    -- How many of the values a list is always given are other than one
    -- value of it.
    besides : HeldItem -> Nat -> Nat
    besides e n = case itemKind e of
      AlwaysOne => pred n
      AtMostOne => n
      AnyNumber => n

    listAt : Node -> Sites.Site -> HeldBy -> List HeldItem -> List Written
    listAt w s place es =
      es >>= \e => contributions w s e >>= \c =>
        map (\p => MkWritten c.reads c.template c.writer (OfHeld (MkHeldValues place p)) c.wrote c.draws)
            (landing (besides e (alwaysIn (map itemKind es))) (pred (length es)) c.brings)

    -- The list a dictionary the writer binds closes over, written at its
    -- binding's place at the writer's node.
    kept : Node -> Sites.Site -> Reached -> List Written
    kept w s (Kept b items) = listAt w s (ByBinding w b) (forget items)
    kept w s (MkReached _ _ _) = []

-- The places whose lists of several values some place writes: the pairs
-- that hold those lists read their positions.
pairedPlaces : List Written -> List HeldBy
pairedPlaces ws = SortedSet.toList (foldl (\acc, x => case x.target of
                                             OfHeld (MkHeldValues place InPairs) => insert place acc
                                             _ => acc)
                                          empty ws)

-- A parameter kept where its weight is an arc's.
keptWhere : Maybe Label -> Nat -> List Nat -> List Nat
keptWhere (Just _) i is = i :: is
keptWhere Nothing _ is = is

-- The parameters some weights draw an arc from, in order: those whose
-- weight is an arc's (`labelOf`).
weighed : List (Nat, Weight) -> List Nat
weighed [] = []
weighed ((i, w) :: rest) = keptWhere (labelOf w) i (weighed rest)

0 keptHere : (l : Maybe Label) -> l = Just lab -> Elem i (keptWhere l i is)
keptHere (Just _) _ = Here
keptHere Nothing Refl impossible

0 keptBelow : (l : Maybe Label) -> Elem j is -> Elem j (keptWhere l i is)
keptBelow (Just _) el = There el
keptBelow Nothing el = el

-- A parameter weighed with an arc is one its weights draw an arc from.
0 weighedHas : (ws : List (Nat, Weight)) -> Elem (i, w) ws -> labelOf w = Just lab -> Elem i (weighed ws)
weighedHas [] el _ = absurd el
weighedHas ((_, v) :: _) Here drawn = keptHere (labelOf v) drawn
weighedHas ((_, v) :: rest) (There el) drawn = keptBelow (labelOf v) (weighedHas rest el drawn)

-- Whether a parameter is among some, as the machine compares naturals.
amongParameters : (i : Nat) -> (is : List Nat) -> Decided (Elem i is)
amongParameters i [] = No (\el => absurd el)
amongParameters i (j :: js) = case choose (i == j) of
  Left so => Yes (rewrite equalSo so in Here)
  Right no => case amongParameters i js of
    Yes el => Yes (There el)
    No out => No (\el => case el of
                           Here => soNotToNotSo no (equalSelf i)
                           There e => out e)

-- The parameters of a list not already among some, each once: every one
-- of the list is among those, or kept.
unweighed : (seen : List Nat) -> (is : List Nat) ->
            Subset (List Nat) (\ks => {i : Nat} -> Elem i is -> Either (Elem i seen) (Elem i ks))
unweighed seen [] = Element [] (\el => absurd el)
unweighed seen (i :: is) = case amongParameters i seen of
  Yes here => let (Element ks covered) = unweighed seen is in
              Element ks (\el => case el of
                                   Here => Left here
                                   There e => covered e)
  No _ => let (Element ks covered) = unweighed (i :: seen) is in
          Element (i :: ks) (\el => case el of
                                       Here => Right Here
                                       There e => case covered e of
                                         Left Here => Right Here
                                         Left (There inSeen) => Left inSeen
                                         Right kept => Right (There kept))

-- The parameters some weights draw an arc from, then those a reading
-- landed closed that they draw none from, each once.
sourcesFrom : List Nat -> List Nat -> List Nat
sourcesFrom ws landed = ws ++ (unweighed ws landed).fst

-- The writer's parameters a writing reads at positions: those its
-- template holds with a weight that is an arc, each once, whose arcs the
-- graph draws from there, then each family its reading landed closed that
-- the template no longer weighs, from which no arc is drawn, but where
-- what an instance writes at the rewritten node comes from.
sourcesOf : Writing -> List Nat
sourcesOf x = sourcesFrom (weighed (weights x.template)) x.landed

0 inFront : Elem x xs -> Elem x (xs ++ ys)
inFront Here = Here
inFront (There el) = There (inFront el)

0 behind : (xs : List a) -> Elem x ys -> Elem x (xs ++ ys)
behind [] el = el
behind (_ :: xs) el = There (behind xs el)

-- Every family a writing's reading landed closed is among the parameters
-- it reads at positions: weighed with an arc, or kept after them.
0 landedSources : (x : Writing) -> Elem i x.landed -> Elem i (sourcesOf x)
landedSources x el = case (unweighed (weighed (weights x.template)) x.landed).snd el of
  Left inW => inFront inW
  Right kept => behind (weighed (weights x.template)) kept

-- Where a writing's writer reads parameter i.
readsAt : Writing -> Nat -> Spot
readsAt x i = x.reads i

-- The places a writing meets positions at: where it lands, then where its
-- writer reads each parameter it draws from.
slotsOf : Writing -> List Spot
slotsOf x = x.target :: map (readsAt x) (sourcesOf x)

-- The places some writings meet positions at, in order.
allSlots : List Writing -> List Spot
allSlots [] = []
allSlots (x :: xs) = slotsOf x ++ allSlots xs

-- The numbering at place `place` of `n`, with `rest` still to meet: where
-- each position met so far was first met, and those first meetings in
-- order. A position is numbered by the place it is first met at, so
-- meeting it again finds that number, and no number is looked for that
-- was not given.
record Meeting (n : Nat) (rest : List Spot) where
  constructor MkMeeting
  place : Nat
  0 left : place + length rest = n
  seen : SortedMap Spot (Fin n)
  firsts : SnocList (Fin n)

-- Position x, met at the next place: the number it was first met at, or,
-- met for the first time, this place's.
meet : {0 n : Nat} -> {0 rest : List Spot} -> (x : Spot) -> Meeting n (x :: rest) -> (Fin n, Meeting n rest)
meet x (MkMeeting j left seen firsts) =
  let 0 next = trans (plusSuccRightSucc j (length rest)) left in
  case lookup x seen of
    Just f => (f, MkMeeting (S j) next seen firsts)
    -- Essential: a position's first meeting is the one that numbers it.
    Nothing => let f = natToFinLT j {prf = runBelow j left} in
               (f, MkMeeting (S j) next (insert x f seen) (firsts :< f))

-- Positions met at the next places, in order.
meetAll : {0 n : Nat} -> {0 rest : List Spot} -> (xs : List Spot) -> Meeting n (xs ++ rest) -> (List (Fin n), Meeting n rest)
meetAll [] m = ([], m)
meetAll (x :: xs) m = let (f, m') = meet x m
                          (fs, m'') = meetAll xs m' in
                      (f :: fs, m'')

-- Parameter i listed with the position met for it, and every parameter
-- listed before.
0 listedOn : {0 is : List Nat} -> {0 ws : List (Nat, Fin n)} ->
             ({k : Nat} -> Elem k is -> (q : Fin n ** Elem (k, q) ws)) ->
             Elem j (i :: is) -> (q : Fin n ** Elem (j, q) ((i, p) :: ws))
listedOn {p} _ Here = (p ** Here)
listedOn listed (There el) = case listed el of
  (q ** inWs) => (q ** There inWs)

-- The positions met at the next places for some parameters, where the
-- writer reads each, each paired with its parameter: every parameter is
-- listed with the position met for it.
meetEach : {0 n : Nat} -> {0 rest : List Spot} -> (is : List Nat) -> (reads : Nat -> Spot) ->
           Meeting n (map reads is ++ rest) ->
           (Subset (List (Nat, Fin n)) (\ws => {k : Nat} -> Elem k is -> (q : Fin n ** Elem (k, q) ws)), Meeting n rest)
meetEach [] reads m = (Element [] (\el => absurd el), m)
meetEach (i :: is) reads m =
  let (p, m') = meet (reads i) m
      (Element ws listed, m'') = meetEach is reads m' in
  (Element ((i, p) :: ws) (listedOn listed), m'')

||| A site of the model with what made it, whose maker's evidence holds of
||| the site's template (`DrawnBy`).
public export
SiteDrawn : (Bound.Site n, Wrote) -> Type
SiteDrawn x = DrawnBy (snd x) (fst x).template

-- What a site met keeps of how it was made: what made it holds of its
-- template, its writers list every parameter its template weighs with an
-- arc, and how it was read off what its writer wrote.
0 SiteMet : {n : Nat} -> (Bound.Site n, Wrote) -> Type
SiteMet {n} x = (SiteDrawn x, WritersListed {n} (fst x), SiteLanding {n} (fst x))

-- How a site met from a writing was read: as the writing's template was,
-- each family its reading landed closed listed among the site's writers,
-- its roots the writing's.
0 siteLanded : {0 n : Nat} -> {s : Bound.Site n} -> (t : Template) -> s.template = t -> ReadAt t landed s.roots ->
               ((i : Nat) -> Elem i landed -> (p : Fin n ** Elem (i, p) s.writers)) -> SiteLanding s
siteLanded _ same (ReadAtNode c written applied) listed = LandedAtNode c written same listed applied
siteLanded _ same ReadAsHeld _ = HeldAsWritten

-- A writing as a site of the model, its positions met at its places: where
-- it lands, then where its writer reads each parameter it reads at a
-- position; the site's template is the writing's, so its maker's evidence
-- holds of it, and how it was read; and its writers are each such
-- parameter paired with the position met for it, so they list every one
-- its template weighs with an arc and every one its reading landed closed.
siteMet : {0 n : Nat} -> {0 rest : List Spot} -> (x : Writing) ->
          Meeting n (slotsOf x ++ rest) -> (Subset (Bound.Site n, Wrote) SiteMet, Meeting n rest)
siteMet x m =
  let (t, m') = meet x.target m
      (Element ws listed, m'') = meetEach (sourcesOf x) (readsAt x) m' in
  (Element (Bound.MkSite t x.template ws x.roots, x.wrote)
           (x.draws,
            \i, w, inW, lab, drawn => listed (inFront (weighedHas (weights x.template) inW drawn)),
            siteLanded x.template Refl x.readAt (\i, el => listed (landedSources x el))), m'')

-- Writings as sites of the model, in order, each met at its places.
sitesMet : {0 n : Nat} -> {0 rest : List Spot} -> (xs : List Writing) ->
           Meeting n (allSlots xs ++ rest) -> (Subset (List (Bound.Site n, Wrote)) (All SiteMet), Meeting n rest)
sitesMet [] m = (Element [] [], m)
sitesMet (x :: xs) m =
  let (Element here madeHere, m') = siteMet x (replace {p = Meeting n} (sym (appendAssociative (slotsOf x) (allSlots xs) rest)) m)
      (Element later madeLater, m'') = sitesMet xs m' in
  (Element (here :: later) (madeHere :: madeLater), m'')

0 allFirst : All p (x :: xs) -> p x
allFirst (px :: _) = px

0 allRest : All p (x :: xs) -> All p xs
allRest (_ :: pxs) = pxs

-- The sites that land at uncapped positions, with the evidence of each and
-- of what made each, and those that land at capped ones: a capped
-- position's cap is its bound, so no site into it is drawn.
uncappedDrawn : (caps : Vect n (Maybe Nat)) -> (ss : List (Bound.Site n, Wrote)) -> (0 _ : All SiteMet ss) ->
                (Subset (List (Bound.Site n, Wrote))
                        (\ks => (All (\x => Vect.index (fst x).target caps = Nothing) ks, All SiteMet ks)),
                 List (Bound.Site n, Wrote))
uncappedDrawn caps [] _ = (Element [] ([], []), [])
uncappedDrawn caps (x :: xs) made with (Vect.index (fst x).target caps) proof here
  _ | Nothing = let (Element kept evidence, capped) = uncappedDrawn caps xs (allRest made) in
                (Element (x :: kept) (here :: fst evidence, allFirst made :: snd evidence), capped)
  _ | Just _ = let (kept, capped) = uncappedDrawn caps xs (allRest made) in (kept, x :: capped)

-- A site of the model is one of the kept sites, whose writers list every
-- parameter its template weighs with an arc.
0 listedAmong : {ks : List (Bound.Site n, Wrote)} -> All SiteMet ks -> Elem s (map Builtin.fst ks) -> WritersListed s
listedAmong {ks = []} [] el = absurd el
listedAmong {ks = (_, _) :: _} (made :: _) Here = fst (snd made)
listedAmong {ks = _ :: _} (_ :: made) (There el) = listedAmong made el

-- A site of the model is one of the kept sites, read as its writing was.
0 landedAmong : {ks : List (Bound.Site n, Wrote)} -> All SiteMet ks -> Elem s (map Builtin.fst ks) -> SiteLanding s
landedAmong {ks = []} [] el = absurd el
landedAmong {ks = (_, _) :: _} (made :: _) Here = snd (snd made)
landedAmong {ks = _ :: _} (_ :: made) (There el) = landedAmong made el

------------------------------------------------------------------------------
-- Positions, caps and the numbering
------------------------------------------------------------------------------

-- Things by the definition they are of.
byDefinition : (a -> Address) -> List a -> SortedMap Address (List a)
byDefinition key = foldr (\x => insertWith (++) (key x) [x]) empty

-- Each of the positions that is capped, with its cap. A cap is asked once
-- per definition and parameter, since a definition's nodes share its type;
-- the application's positions are no definition's, and a field's, a
-- choice's and a held one no parameter's, so none of them is capped.
capsOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         List Spot -> Front (SortedMap Spot Nat)
capsOf named = snd <$> foldlM ask (empty, empty) named
  where
    ask : (SortedMap (Address, Nat) (Maybe Nat), SortedMap Spot Nat) -> Spot ->
          Front (SortedMap (Address, Nat) (Maybe Nat), SortedMap Spot Nat)
    ask acc (OfParameter OfApplication _) = pure acc
    ask acc (OfField _ _) = pure acc
    ask acc (OfChoice _) = pure acc
    ask acc (OfHeld _) = pure acc
    ask (memo, capped) p@(OfParameter (OfNode n) j) = do
      cap <- maybe (capOf n.definition j) pure (lookup (n.definition, j) memo)
      pure (insert (n.definition, j) cap memo, maybe capped (\k => insert p k capped) cap)

-- What made each arc, in the arcs' order.
wrotes : (arcs : List (Arc n, Wrote)) -> Vect (length (map Builtin.fst arcs)) Wrote
wrotes [] = []
wrotes ((_, w) :: arcs) = w :: wrotes arcs

-- The arc at an index, with what made it, is one of the arcs.
0 taggedAt : (arcs : List (Arc n, Wrote)) -> (a : Fin (length (map Builtin.fst arcs))) ->
             Elem (index' (map Builtin.fst arcs) a, Vect.index a (wrotes arcs)) arcs
taggedAt [] FZ impossible
taggedAt [] (FS _) impossible
taggedAt ((x, w) :: arcs) FZ = Here
taggedAt ((x, w) :: arcs) (FS a) = There (taggedAt arcs a)

-- What a node is read at: its definition, and the heads of its families
-- alone. Its dictionaries' heads change no reading: a dictionary stays its
-- marker, whose root the node's head gives (`Heads`).
readAt : SortedMap Address (List Nat) -> Node -> Node
readAt families x = MkNode x.definition (filter (\(i, _) => elem i (fromMaybe [] (lookup x.definition families))) x.heads)

-- Every way of heading at least one of a definition's families, ascending
-- by index: at each, one of the type constructors the flow found can head
-- it, or none. Heading none is the definitions' walk's own reading.
familyHeads : Flow -> Address -> List Nat -> List (List (Nat, Address))
familyHeads fl a [] = []
familyHeads fl a (i :: is) =
  let rest = familyHeads fl a is in rest ++ [(i, h) :: hs | h <- reaching fl a i, hs <- [] :: rest]

-- Every node a walk from main can meet, by what it is read at, with the
-- sites it writes there. A node with no family headed is read as the
-- definitions' walk read it. The flow's sets hold every type constructor
-- that heads a family in the split, since a site the split reads at a
-- node is the definitions' walk's with each head in place of the marker
-- it stands for, whose flow equation already carries that head: so these
-- are every node the walk can meet, which the walk checks (`Unheaded`).
readings : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           Flow -> Entered -> Front (SortedMap Node (List Sites.Site))
readings fl r = foldlM family plain (SortedMap.toList r.families)
  where
    plain : SortedMap Node (List Sites.Site)
    plain = SortedMap.fromList (map (\(a, ss) => (MkNode a [], ss)) (SortedMap.toList r.sites))

    headed : Address -> SortedMap Node (List Sites.Site) -> List (Nat, Address) -> Front (SortedMap Node (List Sites.Site))
    headed a m hs = (\ss => insert (MkNode a hs) ss m) <$> sitesOf a hs

    family : SortedMap Node (List Sites.Site) -> (Address, List Nat) -> Front (SortedMap Node (List Sites.Site))
    family m (a, fams) = foldlM (headed a) m (familyHeads fl a fams)

-- A definition's name, for an internal error to print; its address when
-- the context has no entry there.
nameOf : {auto c : Ref Ctxt Defs} -> Address -> Front String
nameOf a = do
  defs <- getDefs
  case nameAt (gamma defs) a of
    Just n => show <$> fullNames n
    Nothing => pure (show a)

-- A term with the writer's family markers given values: each `markerAt i
-- []` whose parameter the list names is that value.
mutual
  givenFamilies : List (Nat, ClosedTerm) -> TT vs -> TT vs
  givenFamilies ms tm@(Ref _ _ n) = case Template.markerOf n of
    Just (i, []) => maybe tm embedClosed (lookup i ms)
    _ => tm
  givenFamilies ms (App fc f a) = App fc (givenFamilies ms f) (givenFamilies ms a)
  givenFamilies ms (Bind fc x b sc) = Bind fc x (givenIn ms b) (givenFamilies ms sc)
  givenFamilies ms (TDelayed fc r t) = TDelayed fc r (givenFamilies ms t)
  givenFamilies ms (TDelay fc r t a) = TDelay fc r (givenFamilies ms t) (givenFamilies ms a)
  givenFamilies ms (TForce fc r t) = TForce fc r (givenFamilies ms t)
  givenFamilies ms (As fc u a p) = As fc u (givenFamilies ms a) (givenFamilies ms p)
  givenFamilies ms tm = tm

  givenIn : List (Nat, ClosedTerm) -> TTBinder (TT vs) -> TTBinder (TT vs)
  givenIn ms (Lam fc rig info ty) = Lam fc rig info (givenFamilies ms ty)
  givenIn ms (Let fc rig v ty) = Let fc rig (givenFamilies ms v) (givenFamilies ms ty)
  givenIn ms (Pi fc rig info ty) = Pi fc rig info (givenFamilies ms ty)
  givenIn ms (PVar fc rig info ty) = PVar fc rig info (givenFamilies ms ty)
  givenIn ms (PLet fc rig v ty) = PLet fc rig (givenFamilies ms v) (givenFamilies ms ty)
  givenIn ms (PVTy fc rig ty) = PVTy fc rig (givenFamilies ms ty)

-- Every choice of one value for each family, from the values each takes.
choices : List (Nat, List ClosedTerm) -> List (List (Nat, ClosedTerm))
choices [] = [[]]
choices ((i, vs) :: rest) = [(i, v) :: c | v <- vs, c <- choices rest]

-- The values a family's position takes when they are closed values only,
-- some computing (`Evaluable`).
evaluable : Landing -> Maybe (List ClosedTerm)
evaluable (Evaluable vs) = Just vs
evaluable _ = Nothing

||| The walk's arguments, each one that applies only families given closed
||| values (`Evaluable`) evaluated: its term with each such family given
||| each value that lands at it, normalised and read again at its kind, one
||| argument for each choice of values, so that what the family computes is
||| a closed type whose height is a constant of the graph, as a closed
||| argument's is, and no arc out of a position that is only ever given
||| closed values is unmeasured. An argument that applies a family given
||| any other value, or whose evaluation is no closed template, stays as
||| written: the arc it draws is the one the check refuses. A value of a
||| type an argument's lists hold, or a binding's list, is evaluated as an
||| argument is, and the argument's every reading holds the lists so
||| evaluated.
evaluated : {auto c : Ref Ctxt Defs} -> SortedMap Spot Landing ->
            List (Node, List (Sites.Site, Reached)) -> Front (List (Node, List (Sites.Site, Reached)))
evaluated ls = traverse (\(w, edges) => (w,) <$> traverse (\(st, e) => (st,) <$> reachedAt w st e) edges)
  where
    -- One closed reading of an argument at a choice of values: nothing
    -- when the reading still holds a marker or applies a family.
    readingAt : Argument -> ClosedTerm -> List (Nat, ClosedTerm) -> Front (Maybe Argument)
    readingAt x tm given = do
      read <- readArgument x.stands x.position x.kind x.memberOf !(normaliseClosed (givenFamilies given tm)) x.shown
      pure (if selfBounded read.template then Just read else Nothing)

    evaluate : Node -> Sites.Site -> Argument -> Front (List Argument)
    evaluate w st x = case (x.term, applyingIn x.template) of
      (Just tm, fs@(_ :: _)) => case traverse (\i => (i,) <$> evaluable (closedAt ls w st.params i)) (nub fs) of
        Nothing => pure [x]
        Just values => do
          reads <- traverse (readingAt x tm) (choices values)
          pure (fromMaybe [x] (sequence reads))
      _ => pure [x]

    -- A value of a type a list holds, each of its readings evaluated. A
    -- reading no choice of values gives stays as it was written, as an
    -- argument's does where its families are given no closed values.
    heldAt : Node -> Sites.Site -> HeldItem -> Front HeldItem
    heldAt w st (OfType xs) = do
      reads <- traverse (evaluate w st) xs
      pure (OfType (case concat (forget reads) of
                      [] => xs
                      y :: ys => y ::: ys))
    heldAt w st item = pure item

    reachedAt : Node -> Sites.Site -> Reached -> Front Reached
    reachedAt w st (MkReached callee placed via) = do
      placed' <- traverse (\pl => do
                             holds <- traverse (traverse (heldAt w st)) pl.argument.holds
                             reads <- evaluate w st pl.argument
                             pure (map (\x => the Placed ({ argument := { holds := holds } x } pl)) reads))
                          placed
      pure (MkReached callee (concat placed') via)
    reachedAt w st (Kept b items) = Kept b <$> traverse (heldAt w st) items

||| The growth graph of the program from main: every static position its
||| reachable nodes have, numbered, with the arcs between them, the caps,
||| K, and the sizes the worklist's universe needs. It throws only an
||| internal error, a broken invariant of its own construction or of a
||| contract it reads, at main's definition.
export
build : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> (main : Name) -> Front Built
build main = do
  -- main is where an internal error of the graph is located, and its node,
  -- with no heads, is where the walk over nodes starts.
  Just mainRead <- defined main
    | Nothing => internal EmptyFC "the growth graph's main has no definition"
  let fc = location mainRead.def
  let root = addressOf mainRead.placement
  entered <- definitions main
  -- Lists are joined by bind, which is linear: base's `concat` and
  -- `concatMap` on a list fold `++` from the left, so every join copies
  -- what came before, the square of the length in all.
  let fl = flow entered.fields (values entered.sites >>= id)
  reads <- readings fl entered
  -- The most values one list of held values holds, and every stuck path a
  -- chain of held dispatches can hold, read off every reading's sites
  -- once; and the pair that holds such lists.
  let counted = countedIn (values reads)
  let count = heldCount counted
  pairing <- pairingOf
  -- Every visit's node has its reading (`readings`): one without would
  -- lose the arcs its sites write.
  let out : Visit -> Maybe (List (Sites.Site, Reached))
      out x = (\ss => [(s, r) | s <- ss, r <- reaches fl x s]) <$> SortedMap.lookup (readAt entered.families (visitNode x)) reads
  let Right found = nodesFromMain (SortedSet.toList counted.paths) (headBound entered.fields (values reads)) out
                                  (MkVisit root [])
    | Left (Outside x) => do
        n <- nameOf x.definition
        internal fc ("the growth graph met a node split at a parameter no site writes, or holding a path no site re-packs: " ++ n)
    | Left (Unheaded x) => do
        n <- nameOf x.definition
        internal fc ("the growth graph met a node at heads its flow did not give: " ++ n)
  -- Each visit's sites write at its node's positions, which bound every
  -- request the translation keys by that node, whatever chain reached it.
  let walked0 = map (\(v, edges) => (visitNode v, edges)) (found.done <>> [])
  -- Each node once, though the walk visits a node once for each set of
  -- paths its chains held.
  let nodes = byDefinition (the (Node -> Address) (.definition)) (SortedSet.toList (SortedSet.fromList (map fst walked0)))
  let leads = leadsOf walked0
  -- What a walk's writings write, before any writer's families are read
  -- where they land: what the dispatches write at the method functions'
  -- leading parameters, what the walked implementations' fields write at
  -- their positions, what the pairs that hold lists of several values are
  -- given, what each list of values a dictionary is given writes at its
  -- place's held positions, and what the walked sites' arguments write,
  -- the latest first: the order the check reads the arcs in.
  let fixed = leadingWritings nodes leads ++ fieldWritings nodes entered.fields
  let writtenBy : List (Node, List (Sites.Site, Reached)) -> List Written -> List Written
      writtenBy ws args =
        let held = heldWritings count pairing (heldChoices ws) ws in
        fixed ++ heldPackings count pairing (pairedPlaces held) ++ held ++ args
  -- A capped position takes no arc: its cap, which the graph holds and a
  -- feasible potential meets, stands for every value of its height, so no
  -- listed site targets it. A cap is asked of the positions the arguments
  -- name; a position only a data type's arguments give is a type
  -- argument, which no cap applies to.
  let args0 = writings walked0
  capped <- capsOf (targetsOf args0)
  -- What lands at each position is joined from every writing there, and a
  -- capped position holds every value of its cap's height.
  let lands0 = landings nodes leads walked0 (opened (keys capped) (landedAt (writtenBy walked0 args0)))
  -- What a family given only closed values computes, evaluated at each.
  walked <- evaluated lands0 walked0
  let written = writtenBy walked (writings walked)
  let lands = landings nodes leads walked (opened (keys capped) (landedAt written))
  -- Each writing read where its writer is, over what lands where.
  let every = map (readAtWriter fl entered.families lands) written
  -- The places positions are met at: where each writing lands and where
  -- its writer reads each parameter it draws from, then every represented
  -- argument of a reachable data type. Every place an argument lands is a
  -- writing's. A position is numbered at the place it is first met, and
  -- each site is built as its places are met, so no site looks a position
  -- up.
  let slots = allSlots every ++ entered.datas
  let position = Vect.fromList slots
  let start : Meeting (length slots) (allSlots every ++ entered.datas)
      start = MkMeeting 0 Refl empty [<]
  let (Element sites sitesDrawn, met) = sitesMet {rest = entered.datas} every start
  let (_, done) = meetAll {rest = []} entered.datas
                          (replace {p = Meeting (length slots)} (sym (appendNilRightNeutral entered.datas)) met)
  let firsts = done.firsts <>> []
  let caps = map (\p => lookup p capped) position
  -- Each definition's positions, each field's and each choice's, read off
  -- the first meetings themselves.
  let byDefinitionAt = the (SortedMap Address (List (Fin (length slots))))
                           (foldr (\f => case Vect.index f position of
                                           OfParameter (OfNode node) _ => insertWith (++) node.definition [f]
                                           _ => id)
                                  empty firsts)
  let byFieldAt = the (SortedMap (Address, Nat) (List (Fin (length slots))))
                      (foldr (\f => case Vect.index f position of
                                      OfField j k => insertWith (++) (j, k) [f]
                                      _ => id)
                             empty firsts)
  let byChoiceAt = the (SortedMap ChoiceHead (List (Fin (length slots))))
                       (foldr (\f => case Vect.index f position of
                                       OfChoice k => insertWith (++) k [f]
                                       _ => id)
                              empty firsts)
  let positionsOf : Address -> List (Fin (length slots))
      positionsOf a = fromMaybe [] (lookup a byDefinitionAt)
  let fieldPositionsOf : Address -> Nat -> List (Fin (length slots))
      fieldPositionsOf j k = fromMaybe [] (lookup (j, k) byFieldAt)
  -- A member of a choice is read from its head's position and from the
  -- unshown head's, whose members may be of that head; a member whose
  -- head is unshown, from every choice's. Each list is a choice's one
  -- position, so the join is short.
  let choicePositionsOf : ChoiceHead -> List (Fin (length slots))
      choicePositionsOf UnshownHead = values byChoiceAt >>= id
      choicePositionsOf k = fromMaybe [] (lookup k byChoiceAt) ++ fromMaybe [] (lookup UnshownHead byChoiceAt)
  let positionOf : Fin (length slots) -> Maybe (Head, Nat)
      positionOf f = case Vect.index f position of
                       OfParameter (OfNode node) i => Just (ADefinition node.definition, i)
                       OfParameter OfApplication i => Just (AnApplication, i)
                       OfField _ _ => Nothing
                       OfChoice _ => Nothing
                       OfHeld _ => Nothing
  let (Element kept keptEvidence, cappedSites) = uncappedDrawn caps sites sitesDrawn
  -- K stands above every template, a capped position's among them, though
  -- no site into one is drawn.
  let beyond = topOf 0 (allOf siteNeeds cappedSites)
  let arcs = drawn positionsOf fieldPositionsOf choicePositionsOf kept
  -- A field's template is written into the values of every field read,
  -- and so into requests, as an argument's is.
  pure (MkBuilt (graphOf positionsOf fieldPositionsOf choicePositionsOf beyond caps kept) position firsts (wrotes arcs)
                (foldl (\m, x => max m (Template.arity x.template)) 0 every) found.reachers entered.breadth
                (foldl (\m, x => max m (Template.heaviest x.template)) count every)
                (modelOf positionsOf fieldPositionsOf choicePositionsOf positionOf count beyond caps kept)
                (\pot, fe => describes positionsOf fieldPositionsOf choicePositionsOf positionOf count beyond caps kept
                                       (fst keptEvidence) fe)
                (\a, through => measuredDrawn {ps = positionsOf} {fps = fieldPositionsOf} {cps = choicePositionsOf} {ss = kept}
                                  (\x => x = ThroughMethod)
                                  (\st, x, el, same => methodMeasured (replace {p = \w => DrawnBy w st.template} same
                                                                                (fst (indexAll el (snd keptEvidence)))))
                                  (taggedAt arcs a) through)
                (\a, k, packs => measuredDrawn {ps = positionsOf} {fps = fieldPositionsOf} {cps = choicePositionsOf} {ss = kept}
                                    (\x => x = PacksHeld k)
                                    (\st, x, el, same => packedMeasured (replace {p = \w => DrawnBy w st.template} same
                                                                                  (fst (indexAll el (snd keptEvidence)))))
                                    (taggedAt arcs a) packs)
                (\st, el => ownDrawnOf {ps = positionsOf} {fps = fieldPositionsOf} {cps = choicePositionsOf} {positionOf}
                                       {held = count} {beyond} {caps} {ss = kept} el)
                (\st, el => listedAmong (snd keptEvidence) el)
                (\st, el => landedAmong (snd keptEvidence) el))
