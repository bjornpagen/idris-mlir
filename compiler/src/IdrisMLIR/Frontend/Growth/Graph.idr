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
||| looked up once numbered; that is where a position becomes a `Fin`. The
||| numbering comes before anything that lands is read: what lands at each
||| position is a table by number (`LandingTable`), which every site's
||| reading reads, through a tree over it made once (`Indexed`), and every
||| proof of what lands there reads too.
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
import IdrisMLIR.Frontend.Growth.Indexed
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Definitions
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Readings
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
import Decidable.Equality

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
||| arc); field k of the definition that gives a dictionary, as it was
||| read, whose template it is, with the definitions of the recursions it
||| holds; or the values
||| a dictionary's place holds, the arc's source, written on as their
||| packing says: into the pairs that hold a list of several, at most the
||| held count of them (`heldPackings`), or into the list another place is
||| given, as they are or as the one value a list of several packs to
||| (`heldWritings`).
public export
data Wrote = FromArgument Sites.Site Argument
           | ThroughMethod
           | InField GlobalDef Nat TemplateRead
           | PacksHeld Packing

||| What made an arc, with the template the arc is drawn from: a leading
||| arc passes its parameter on unchanged, so it draws a marker, and a held
||| packing draws the chain its packing names. An argument's and a field's
||| template is any that holds the recursions its reading holds, in their
||| order, whose definitions the reading gives (`recursionAt`). So each
||| leading arc and each packing is measured wherever it is drawn
||| (`Proof.Describes.measuredDrawn`).
public export
data DrawnBy : Wrote -> Template -> Type where
  ArgumentDraws : (0 _ : recursions t = recursions a.template) -> DrawnBy (FromArgument s a) t
  FieldDraws : (0 _ : recursions t = recursions f.template) -> DrawnBy (InField j k f) t
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

-- A chain of pairs holds no recursion: pairs and a marker under them.
0 chainUnrecursive : (a : Address) -> (n : Nat) -> recursions (pairChain a n) = []
chainUnrecursive a Z = Refl
chainUnrecursive a (S n) = rewrite chainUnrecursive a n in Refl

0 listedUnrecursive : (a : Address) -> (m : Nat) -> Elem t (pairChainsUpTo a m) -> recursions t = []
listedUnrecursive a Z el = absurd el
listedUnrecursive a (S m) Here = chainUnrecursive a (S m)
listedUnrecursive a (S m) (There el) = listedUnrecursive a m el

-- The template a packing writes holds no recursion.
0 packingUnrecursive : (k : Packing) -> recursions (packingTemplate k) = []
packingUnrecursive AsTheyAre = Refl
packingUnrecursive (Chained a m chain listed) = listedUnrecursive a m listed

-- A template a leading arc or a held packing draws holds no recursion.
0 markerNone : DrawnBy ThroughMethod t -> Elem r (recursions t) -> Void
markerNone (MarkerDraws p) el = absurd el

0 packedNone : DrawnBy (PacksHeld k) t -> Elem r (recursions t) -> Void
packedNone (ChainDraws k) el = absurd (replace {p = Elem r} (packingUnrecursive k) el)

0 argumentRecursions : DrawnBy (FromArgument s x) t -> recursions t = recursions x.template
argumentRecursions (ArgumentDraws same) = same

0 fieldRecursions : DrawnBy (InField j k f) t -> recursions t = recursions f.template
fieldRecursions (FieldDraws same) = same

||| The definition of a recursion of the template an arc is drawn from, as
||| what made the arc read it: an argument's and a field's reading give
||| one for each recursion, in the order the drawn template holds them; a
||| leading arc's marker and a held packing's chain hold none.
export
recursionAt : (wrote : Wrote) -> (0 _ : DrawnBy wrote t) -> Elem r (recursions t) -> RecursionDef r
recursionAt (FromArgument _ x) drawn el = indexAll (replace {p = Elem r} (argumentRecursions drawn) el) x.recursionsRead
recursionAt (InField _ _ f) drawn el = indexAll (replace {p = Elem r} (fieldRecursions drawn) el) f.recursionsRead
recursionAt ThroughMethod drawn el = void (markerNone drawn el)
recursionAt (PacksHeld _) drawn el = void (packedNone drawn el)

||| A site's writers list every parameter its template weighs with an arc,
||| with the position its writer reads it at: the positions its own arcs
||| are drawn from (`Proof.Describes.ownArcs`).
public export
0 WritersListed : {n : Nat} -> Bound.Site n -> Type
WritersListed {n} s = (i : Nat) -> (w : Weight) -> Elem (i, w) (weights s.template) -> (lab : Label) -> labelOf w = Just lab ->
                      (p : Fin n ** Elem (i, p) s.writers)

||| What has landed at each numbered position: nothing yet, or what every
||| writing there landed as, joined. Positions are numbered before anything
||| that lands is read, so what lands where is read off this table by
||| number, and what the table holds at a number is a fact a proof reads.
public export
LandingTable : Nat -> Type
LandingTable n = Vect n (Maybe Landing)

||| What a site's landing at its writer's parameters says of the table: a
||| parameter read as closed values no higher than k is read at positions
||| where closed values no higher than k landed.
public export
0 ReadsTable : {n : Nat} -> LandingTable n -> List (Nat, Fin n) -> (Nat -> Landing) -> Type
ReadsTable t ws c = (i, k : Nat) -> c i = Closed k -> (p : Fin n) -> Elem (i, p) ws ->
                    (k' : Nat ** (Vect.index p t = Just (Closed k'), LTE k' k))

||| What the table says of a site's template: where only closed values no
||| higher than k land at its target, it is unmarked and no higher than k.
public export
0 TargetBounded : {n : Nat} -> LandingTable n -> Bound.Site n -> Type
TargetBounded t s = (k : Nat) -> Vect.index s.target t = Just (Closed k) -> (Unmarked s.template, LTE (height s.template) k)

||| How a site's template was read off what its writer wrote: the template
||| written there read where what lands at each of the writer's parameters
||| says (`withClosedFamilies` at `atParameter`), its writers listing every
||| family that reading landed closed, which the template no longer names,
||| with the position its writer reads it at; its roots read at the same
||| landing, which root a use of the writer's parameter applied only where
||| values not all closed land, whatever the use is applied to
||| (`Heads.appliedRootsOf`), and keep, read there, what a field's record
||| roots as written (`Heads.recordRootsOf`); and that landing read off the
||| table at the positions its writers list. A held position's packing
||| chain applies no family, so reading it anywhere leaves it as written,
||| and it roots nothing.
public export
record SiteLanding {n : Nat} (t : LandingTable n) (s : Bound.Site n) where
  constructor MkSiteLanding
  atParameter : Nat -> Landing
  written : Template
  0 readOff : s.template = withClosedFamilies atParameter written
  0 landedListed : (i : Nat) -> Elem i (readLanded atParameter written).landed -> (p : Fin n ** Elem (i, p) s.writers)
  0 appliedRoots : AppliedRoots atParameter s.roots
  0 recordRoots : RecordRoots atParameter s.roots
  0 readsTable : ReadsTable t s.writers atParameter

||| What a message reads of what each position of a list of places is
||| named by (`Heads.SpotRead`), in the places' order, each indexed by its
||| position, so none is another's.
public export
data SpotsRead : Vect n Spot -> Type where
  NothingPlaced : SpotsRead []
  PlacedThen : SpotRead s -> SpotsRead ss -> SpotsRead (s :: ss)

||| What a message reads of the position at a place.
export
readAtPlace : (f : Fin n) -> SpotsRead ss -> SpotRead (Vect.index f ss)
readAtPlace FZ (PlacedThen r _) = r
readAtPlace (FS f) (PlacedThen _ rs) = readAtPlace f rs

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
  ||| What a message reads of what the position met at each place is
  ||| named by, as the writing that met it there read it: the definitions
  ||| a position's key names, carried beside it, numbered with it.
  positionRead : SpotsRead position
  ||| The places where a position was first met: the positions the arcs
  ||| join, each once.
  firsts : List (Fin graph.size)
  ||| Each arc as its site drew it, with what made the site: whether the
  ||| site's writer binds the arc's source, and what passes the source on,
  ||| the computation that made it so where the arc is Unmeasured.
  drawing : Vect (length graph.arcs) (Drawn graph.size, Wrote)
  ||| Each arc as drawn is the graph's arc at its index.
  0 drawnAs : (a : Fin (length graph.arcs)) -> arcOf (Vect.index a drawing) = arc graph a
  ||| What made each arc holds of the template it was drawn from: an
  ||| argument's or a field's reading gives the definition of each
  ||| recursion the template holds (`recursionAt`).
  0 drawnBy : (a : Fin (length graph.arcs)) -> DrawnBy (snd (Vect.index a drawing)) (fst (Vect.index a drawing)).drawnFrom
  ||| The most children of any template's node.
  arity : Nat
  ||| The definitions of the nodes above each on the walk from main, as
  ||| the walk read them: the node that first reached it, the one that
  ||| first reached that, and so on up to main.
  reachers : SortedMap Node (List GlobalDef)
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
  0 methodsMeasured : (a : Fin (length graph.arcs)) -> snd (Vect.index a drawing) = ThroughMethod ->
                      IsFinite (arc graph a).label
  ||| A held packing's arc is measured: its template is a chain of pairs or
  ||| a marker.
  0 packingsMeasured : (a : Fin (length graph.arcs)) -> (p : Packing) -> snd (Vect.index a drawing) = PacksHeld p ->
                       IsFinite (arc graph a).label
  ||| Each site's own arcs, from the positions its writer reads its
  ||| parameters at, are the graph's: the graph is drawn from the sites.
  0 ownDrawn : (s : Bound.Site graph.size) -> Elem s model.sites -> (a : Arc graph.size) -> Elem a (ownArcs s) ->
               Elem a graph.arcs
  ||| Each site's writers list every parameter its template weighs with an
  ||| arc, with the position its writer reads it at.
  0 writersListed : (s : Bound.Site graph.size) -> Elem s model.sites -> WritersListed s
  ||| What landed at each position, the table every site's landing reads.
  0 landings : LandingTable graph.size
  ||| A position only closed values land at is uncapped: a capped one holds
  ||| every value of its cap's height.
  0 uncappedLanded : (p : Fin graph.size) -> (k : Nat) -> Vect.index p landings = Just (Closed k) ->
                     Vect.index p graph.caps = Nothing
  ||| How each site was read off what its writer wrote: where its writer's
  ||| parameters land, read off the table, every family the reading landed
  ||| closed among its writers, and its roots read at the same landing.
  0 landedSites : (s : Bound.Site graph.size) -> Elem s model.sites -> SiteLanding landings s
  ||| Each site's template is bounded by what lands at its target.
  0 targetsBounded : (s : Bound.Site graph.size) -> Elem s model.sites -> TargetBounded landings s

------------------------------------------------------------------------------
-- The definitions
------------------------------------------------------------------------------

-- What the definitions' walk found: each definition it entered, by its
-- address, as the boundary read it, with its sites read with no family
-- headed; each definition's families, by its address; the represented
-- arguments of every data type it entered, as positions, each with what
-- a message reads of the data type, as the walk read it; every
-- implementation's fields, by its address; and one more than the most
-- parameters, constructors or constructor arguments of any definition it
-- entered.
record Entered where
  constructor MkEntered
  sites : SortedMap Address (Defined, List Sites.Site)
  families : SortedMap Address (List Nat)
  datas : List (spot : Spot ** SpotRead spot)
  fields : SortedMap Address Fields
  breadth : Nat

-- What a level of the walk has found for the next: nothing yet, or the
-- definitions found, once one was entered into the walk since the level
-- began (`w0`), which leaves fewer to enter.
data Pending : (w0, w : Walked) -> Type where
  Idle : Pending w0 w
  Queued : (0 _ : Smaller w w0) -> SnocList Defined -> Pending w0 w

queued : Pending w0 w -> SnocList Defined
queued Idle = [<]
queued (Queued _ next) = next

-- The arguments each constructor of a type takes, in the type's order:
-- what a link's argument index runs below.
arities : List ConstructorAt -> List Nat
arities [] = []
arities (con :: cons) = con.arity :: arities cons

-- What a definition's kind gives the walk: the counts its links' indices run
-- below, and how its reading (its sites and families) and its represented
-- arguments are read. The one switch on the kind, and the problem's: a
-- type constructor alone has constructors, whose fields are sites of the
-- type's, and arguments that are positions of the data it describes; every
-- other definition writes its signature and case tree. A type
-- constructor's constructors are those the boundary read with its facts;
-- one declared without them has none whose fields write anything.
kindOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         Address -> Defined -> (List Nat, Front (NodeReading, List Nat))
kindOf a d = case (d.matched, definition d.def, d.nature.asTypeConstructor) of
  (Just m, _, _) => ([length m.args], plain)
  (Nothing, TCon n _ _ _ _ _ _, ATypeConstructor facts) => case facts.constructors of
    NoneDeclared => ([n, 0], typed facts [])
    DeclaredAs cons => (n :: length cons :: arities cons, typed facts cons)
  _ => ([], plain)
  where
    plain : Front (NodeReading, List Nat)
    plain = (, []) <$> readingOf a d

    typed : TyConFacts -> List ConstructorAt -> Front (NodeReading, List Nat)
    typed facts cons = do
      let js = represented facts
      fs <- fieldSites a d cons js
      rd <- readingOf a d
      pure ({ sites $= (fs ++) } rd, js)

-- The definition a site enters, as the boundary read it, when it names
-- one: a call or a build. A dispatch reaches the method functions of the
-- implementations its dictionary can be, which the walk enters where each
-- implementation is written, since its body applies them; an application
-- at a use, and a choice, are no definition; a dictionary rebuilt is the
-- writer's own, entered already; and a binding's place is the writer's.
callee : Reach -> Maybe Defined
callee (Calls _ d) = Just d
callee (Builds _ d) = Just d
callee (Dispatches _ _ _) = Nothing
callee Applies = Nothing
callee (Makes _ _) = Nothing
callee (Repacks _ _) = Nothing
callee (Keeps _ _) = Nothing

-- A data type's represented argument j, as a position of its node with
-- no heads, named by the data type, as the walk read it.
dataPosition : Address -> Defined -> Nat -> (spot : Spot ** SpotRead spot)
dataPosition a d j = (OfParameter (OfNode (MkNode a [])) j ** ParameterSpot (NodeParameter d.def))

-- A definition entered: itself as the boundary read it, with its sites,
-- by its address, its families, its represented arguments as positions
-- of its node with no heads, and its fields, with the definitions its
-- sites name, as their sites hold them, to enter next.
keep : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
       Address -> Defined -> Front (NodeReading, List Nat) -> Entered -> Front (Entered, List Defined)
keep a d reading r = do
  (rd, js) <- reading
  fs <- fieldsOf d
  let ss = rd.sites
  pure ( { sites $= insert a (d, ss)
         , families $= insert a rd.families
         , datas $= (map (dataPosition a d) js ++)
         , fields $= maybe id (insert a) fs } r
       , mapMaybe (callee . (.reach)) ss )

-- Walks the definitions reachable from main, breadth first, each entered
-- into the walk (`Walk`) once: the walk is the set of those, and the next
-- level is not empty only if one was entered in this one, so each level
-- starts with fewer definitions left to enter than the last. Each is
-- walked as the boundary read it, main as the reading holds it and every
-- other as the site that names it holds it, so none is looked up. A
-- definition the checks refused is entered and measured, since it is
-- still requested, but has no sites and reaches nothing: the translation
-- leaves it out, and what only it reaches. Its fields are left out too,
-- so that no dispatch reaches a method function through it, and it has
-- no family to be read at.
level : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
        SortedSet Address -> (w0 : Walked) -> (0 acc : SizeAccessible w0) -> (w : Walked) -> (0 _ : NoMore w w0) ->
        Entered -> List Defined -> Pending w0 w -> Front Entered
level refused w0 acc@(Access rec) w p r [] Idle = pure r
level refused w0 acc@(Access rec) w p r [] (Queued lt next) =
  level refused w (rec w lt) w (noMore w) r (next <>> []) Idle
level refused w0 acc@(Access rec) w p r (d :: rest) pending = do
  -- What tells definitions apart is their place in the context, as the
  -- boundary read each.
  let a = addressOf d.placement
  -- Entered already: walked once.
  let Just (Element w1 q) = enter d.placement w
    | Nothing => level refused w0 acc w p r rest pending
  let (counts, reading) = kindOf a d
  let measured = { breadth $= \b => foldl (\m, k => max m (S k)) b counts } r
  (r', next) <- if contains a refused then pure (the Entered ({ sites $= insert a (d, []) } measured), the (List Defined) []) else keep a d reading measured
  level refused w0 acc w1 (thenNoMore (fewer q) p) r' rest (Queued (fewerThen q p) (queued pending <>< next))

-- The definitions' walk from main, as the reading holds it.
definitions : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> (main : Defined) -> Front Entered
definitions main = do
  refused <- (.refused) <$> getState
  level refused start (sizeAccessible start) start (noMore start) (MkEntered empty empty [] empty 0) [main] Idle

------------------------------------------------------------------------------
-- The universe of nodes, and novelty
------------------------------------------------------------------------------

-- Two visits, as the machine compares their parts: the definition's
-- address by its bytes, then each head by its parameter, its root's
-- address and the paths it held. The evidence is erased, so each equality
-- is rebuilt from the parts' by rewriting, never matched.
decideVisit : (x, y : Visit) -> Decided (x = y)
decideVisit (MkVisit d hs) (MkVisit d' hs') = case decideAddress d d' of
  Proof.Growth.No ne => Proof.Growth.No (\Refl => ne Refl)
  Proof.Growth.Yes defs => case sameList decideHead hs hs' of
    Proof.Growth.No ne => Proof.Growth.No (\Refl => ne Refl)
    Proof.Growth.Yes heads => Proof.Growth.Yes (rewrite defs in rewrite heads in Refl)
  where
    decideHeaded : (h, h' : Headed) -> Decided (h = h')
    decideHeaded (MkHeaded a s) (MkHeaded b s') = case decideAddress a b of
      Proof.Growth.No ne => Proof.Growth.No (\Refl => ne Refl)
      Proof.Growth.Yes roots => case sameList samePath s s' of
        Proof.Growth.No ne => Proof.Growth.No (\Refl => ne Refl)
        Proof.Growth.Yes paths => Proof.Growth.Yes (rewrite roots in rewrite paths in Refl)

    decideHead : (h, h' : (Nat, Headed)) -> Decided (h = h')
    decideHead (i, a) (j, b) = case sameNat i j of
      Proof.Growth.No ne => Proof.Growth.No (\Refl => ne Refl)
      Proof.Growth.Yes params => case decideHeaded a b of
        Proof.Growth.No ne => Proof.Growth.No (\Refl => ne Refl)
        Proof.Growth.Yes headed => Proof.Growth.Yes (rewrite params in rewrite headed in Refl)

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
-- node's reachers, the definitions along the path its visit was entered
-- below, as the walk read them: the node that first reached it, nearest
-- first, back to main.
record Found where
  constructor MkFound
  entered : SortedSet Visit
  done : SnocList (Visit, List (Sites.Site, Reached Defined))
  reachers : SortedMap Node (List GlobalDef)

-- Where the walk over nodes stops, either a broken invariant of the
-- graph's own construction that would lose a visit's arcs if the visit
-- were skipped: a visit outside the universe, split at a head where no
-- site writes one, or holding a path no site re-packs; or a visit at
-- heads the flow did not give, with no reading, met as main or where a
-- site enters it.
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

-- No more paths than the program has, as the machine compares their
-- counts.
fewerPaths : (held, ps : List (List1 Nat)) -> Bool
fewerPaths held ps = length held <= length ps

-- Every head's paths among the program's, and no more of them than it
-- has: the erased evidence, or nothing.
withinPaths : (ps : List (List1 Nat)) -> (hs : List (Nat, Headed)) -> Maybe (Subset () (\_ => All (\e => HeldAmong ps (snd e)) hs))
withinPaths ps [] = Just (Element () [])
withinPaths ps ((_, h) :: hs) = case (amongAll ps h.held, choose (fewerPaths h.held ps), withinPaths ps hs) of
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
  -- Enters a visit new to its path from main, `above` the definitions of
  -- the visit and of its path, nearest first, as the walk read them: its
  -- sites' callees are walked below it, each new to the longer path,
  -- which leaves less room.
  visit : (0 names : Listed Address) -> (ps : List (List1 Nat)) -> (b : Nat) ->
          (out : Visit -> Either Stray (List (Sites.Site, Reached Defined))) -> (x : Visit) -> (path : List Visit) ->
          (above : List GlobalDef) ->
          (0 nd : NoDup (x :: path)) -> (0 inU : All (\y => Elem y (Visits names ps b b)) (x :: path)) ->
          (0 acc : Accessible LT (Room names ps b (x :: path))) -> Found -> Either Stray Found
  visit names ps b out x path above nd inU acc found = case out x of
    Left stray => Left stray
    Right edges =>
      under names ps b out x path above nd inU acc (mapMaybe (\(_, e) => calleeVisit e) edges)
            ({ done $= (:< (x, edges)) } found)
    where
      -- The application at a use is no node, nor is a choice, nor a
      -- rebuilt constructor's fields, nor a binding's place, and the walk
      -- enters nothing there: what each holds, the sites into it bound. A
      -- callee is entered with the definition its node is read at.
      calleeVisit : Reached Defined -> Maybe (Visit, GlobalDef)
      calleeVisit (MkReached (Entering c d) _ _) = Just (c, d.def)
      calleeVisit (MkReached Applying _ _) = Nothing
      calleeVisit (MkReached (Making _ _) _ _) = Nothing
      calleeVisit (MkReached (Filling _ _) _ _) = Nothing
      calleeVisit (Kept _ _) = Nothing

  under : (0 names : Listed Address) -> (ps : List (List1 Nat)) -> (b : Nat) ->
          (out : Visit -> Either Stray (List (Sites.Site, Reached Defined))) -> (x : Visit) -> (path : List Visit) ->
          (above : List GlobalDef) ->
          (0 nd : NoDup (x :: path)) -> (0 inU : All (\y => Elem y (Visits names ps b b)) (x :: path)) ->
          (0 acc : Accessible LT (Room names ps b (x :: path))) -> List (Visit, GlobalDef) -> Found -> Either Stray Found
  under names ps b out x path above nd inU acc [] found = Right found
  under names ps b out x path above nd inU acc@(Access rec) ((c, cd) :: cs) found =
    if contains c found.entered then under names ps b out x path above nd inU acc cs found else
    case inside names ps b c of
      -- Outside the universe: a head where no site writes one, so that the
      -- visit's arcs would be lost if it were skipped.
      Nothing => Left (Outside c)
      Just (In cIn) => case novel c (x :: path) of
        -- On its own path: entered already, so the set holds it.
        Nothing => under names ps b out x path above nd inU acc cs found
        Just (New notIn) =>
          let found' = { entered $= insert c, reachers $= insert (visitNode c) above } found in
          case visit names ps b out c (x :: path) (cd :: above) (notIn :: nd) (cIn :: inU)
                 (rec _ (room (notIn :: nd) (cIn :: inU))) found' of
            Left bad => Left bad
            Right after => under names ps b out x path above nd inU acc cs after

-- The walk from a root, the root's definition as the reading holds it.
nodesFrom : (0 names : Listed Address) -> (ps : List (List1 Nat)) -> (b : Nat) ->
            (out : Visit -> Either Stray (List (Sites.Site, Reached Defined))) -> Visit -> GlobalDef -> Either Stray Found
nodesFrom names ps b out root rootDef = case inside names ps b root of
  Nothing => Left (Outside root)
  Just (In rIn) => visit names ps b out root [] [rootDef] ((\case _ impossible) :: []) [rIn] (sizeAccessible _)
                     (MkFound (insert root empty) [<] empty)

-- The walk over the real listing, named through an alias on a right-hand
-- side: a lower-case global written in a type is bound as a new implicit.
nodesFromMain : (ps : List (List1 Nat)) -> (b : Nat) -> (out : Visit -> Either Stray (List (Sites.Site, Reached Defined))) -> Visit ->
                GlobalDef -> Either Stray Found
nodesFromMain ps b out root rootDef = let 0 names = addresses in nodesFrom names ps b out root rootDef

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
joinLanding (Closed a) (Closed b) = Closed (maximum a b)
joinLanding _ _ = Open

-- A join of closed values joined two closed landings, as high as the
-- taller.
0 joinedClosed : (a, b : Landing) -> joinLanding a b = Closed k ->
                 (x : Nat ** y : Nat ** (a = Closed x, b = Closed y, k = maximum x y))
joinedClosed (Closed x) (Closed y) Refl = (x ** y ** (Refl, Refl, Refl))
joinedClosed (Closed _) Open Refl impossible
joinedClosed (Closed _) Computed Refl impossible
joinedClosed (Closed _) (Evaluable _) Refl impossible
joinedClosed Open (Closed _) Refl impossible
joinedClosed Open Open Refl impossible
joinedClosed Open Computed Refl impossible
joinedClosed Open (Evaluable _) Refl impossible
joinedClosed Computed _ Refl impossible
joinedClosed (Evaluable _) (Closed _) Refl impossible
joinedClosed (Evaluable _) Open Refl impossible
joinedClosed (Evaluable _) Computed Refl impossible
joinedClosed (Evaluable _) (Evaluable _) Refl impossible

-- What an argument that is no choice of implementation lands as: a closed
-- value that computes (`beta`), which is its term; any other that
-- computes; a closed one no higher than its height; or one whose height
-- an arc carries.
valueLanding : Template.Beta -> Bool -> Maybe ClosedTerm -> Template -> Landing
valueLanding Computes True (Just tm) _ = Evaluable [tm]
valueLanding Computes True Nothing _ = Computed
valueLanding Computes False _ _ = Computed
valueLanding Inert True _ t = Closed (height t)
valueLanding Inert False _ _ = Open

-- What an argument is, landing, by its root: a choice of implementation
-- made at run time, or a function that gives one at each use (a rank-2
-- dictionary), which an application of it does not beta-reduce but gives
-- one of its members of, so it lands as a value no closed reading bounds;
-- any other as its value does.
landingBy : Root -> Template.Beta -> Bool -> Maybe ClosedTerm -> Template -> Landing
landingBy (Readings.Chosen _) _ _ _ _ = Open
landingBy (Readings.Gives _) _ _ _ _ = Open
landingBy (Rooted _) b sb tm t = valueLanding b sb tm t
landingBy (Parameter _ _) b sb tm t = valueLanding b sb tm t
landingBy Unrooted b sb tm t = valueLanding b sb tm t

-- What an argument is, landing (`landingBy`).
landingOf : Argument -> Landing
landingOf x = landingBy x.root (beta x.template) (selfBounded x.template) x.term x.template

-- A value landing closed is a template no marker holds, as high as it
-- lands.
0 valueClosed : (b : Template.Beta) -> (sb : Bool) -> (tm : Maybe ClosedTerm) -> (t : Template) -> valueLanding b sb tm t = Closed k ->
                (sb = True, height t = k)
valueClosed Inert True _ t Refl = (Refl, Refl)
valueClosed Inert False _ _ Refl impossible
valueClosed Computes True (Just _) _ Refl impossible
valueClosed Computes True Nothing _ Refl impossible
valueClosed Computes False _ _ Refl impossible

-- An argument landing closed is a template no marker holds, as high as it
-- lands.
0 closedBy : (r : Root) -> (b : Template.Beta) -> (sb : Bool) -> (tm : Maybe ClosedTerm) -> (t : Template) ->
             landingBy r b sb tm t = Closed k -> (sb = True, height t = k)
closedBy (Readings.Chosen _) _ _ _ _ Refl impossible
closedBy (Readings.Gives _) _ _ _ _ Refl impossible
closedBy (Rooted _) b sb tm t eq = valueClosed b sb tm t eq
closedBy (Parameter _ _) b sb tm t eq = valueClosed b sb tm t eq
closedBy Unrooted b sb tm t eq = valueClosed b sb tm t eq

-- The walked edges' one traversal, which every reading of what they place
-- shares: each argument placed, in the walk's order, with the node whose
-- site wrote it, the site, and what it reaches. A binding's place is
-- given no argument.
eachPlaced : (r -> Node -> Sites.Site -> Callee Defined -> Placed -> r) -> r -> List (Node, List (Sites.Site, Reached Defined)) -> r
eachPlaced f = foldl (\acc, (w, edges) => foldl (\acc', (s, e) => case e of
                                                   MkReached callee placed _ => foldl (\acc'', pl => f acc'' w s callee pl) acc' placed
                                                   Kept _ _ => acc')
                                                acc edges)

-- What a dispatch through implementation J's method field k reached: the
-- method function, as the walk read its node, J as it was read, and where
-- that field places J's parameters among the method function's.
record Lead where
  constructor MkLead
  methodRead : GlobalDef
  jRead : GlobalDef
  placing : List (Nat, Nat)

-- Each method function's node a dispatch reached through implementation
-- J's method field k, with what it reached there, once however many
-- dispatches reach it.
Leads : Type
Leads = SortedMap (Node, Address, Nat) Lead

leadsOf : List (Node, List (Sites.Site, Reached Defined)) -> Leads
leadsOf walked = foldl (\m, (_, edges) => foldl lead m edges) empty walked
  where
    lead : Leads -> (Sites.Site, Reached Defined) -> Leads
    lead m (_, MkReached (Entering callee d) _ (Dispatched j jRead k leading)) =
      insert (visitNode callee, j, k) (MkLead d.def jRead leading) m
    -- Essential: a call, a build, an application and a binding place no
    -- implementation's parameters, and a dispatch reaches a method
    -- function's node.
    lead m _ = m

------------------------------------------------------------------------------
-- The table of landings
------------------------------------------------------------------------------

0 sameJust : Just x = Just y -> x = y
sameJust Refl = Refl

0 noneNotJust : Nothing = Just x -> Void
noneNotJust Refl impossible

-- A landing joined into what landed at its position before.
landInto : Landing -> Maybe Landing -> Maybe Landing
landInto l Nothing = Just l
landInto l (Just m) = Just (joinLanding l m)

||| What an entry of the table says of a landing joined into it: where the
||| entry is closed values no higher than k, so is the landing.
0 BoundedBy : Landing -> Maybe Landing -> Type
BoundedBy l m = (k : Nat) -> m = Just (Closed k) -> (k' : Nat ** (l = Closed k', LTE k' k))

-- A landing joined in is bounded by what it was joined into.
0 landsInto : (l : Landing) -> (old : Maybe Landing) -> (m : Landing ** (landInto l old = Just m, BoundedBy l (Just m)))
landsInto l Nothing = (l ** (Refl, \k, eq => (k ** (sameJust eq, reflexive))))
landsInto l (Just m0) = (joinLanding l m0 ** (Refl, \k, eq => case joinedClosed l m0 (sameJust eq) of
                                                  (x ** y ** (Refl, _, Refl)) => (x ** (Refl, maximumLeftUpperBound x y))))

-- A landing stays bounded by an entry another is joined into.
0 joinedOver : (l, l' : Landing) -> (m : Landing) -> BoundedBy l (Just m) -> BoundedBy l (landInto l' (Just m))
joinedOver l l' m bounded k eq = case joinedClosed l' m (sameJust eq) of
  (x ** y ** (_, Refl, Refl)) => case bounded y Refl of
    (k' ** (same, le)) => (k' ** (same, transitive le (maximumRightUpperBound x y)))

-- A closed join holds closed values no higher than its height on both
-- sides: what is joined in, and what was there.
0 intoClosed : (l : Landing) -> (old : Maybe Landing) -> landInto l old = Just (Closed k) ->
               ((x : Nat ** (l = Closed x, LTE x k)), (m : Landing) -> old = Just m -> (y : Nat ** (m = Closed y, LTE y k)))
intoClosed {k} l Nothing eq = ((k ** (sameJust eq, reflexive)), \m, none => void (noneNotJust none))
intoClosed l (Just m0) eq = case joinedClosed l m0 (sameJust eq) of
  (x ** y ** (Refl, Refl, Refl)) =>
    ((x ** (Refl, maximumLeftUpperBound x y)), \m, same => (y ** (sym (sameJust same), maximumRightUpperBound x y)))

||| A position's number with the place it was first met at, which the
||| number counts to: the number a table is indexed by, and the place
||| landings are ordered by, read without counting the number out again.
record PlacedNumber (n : Nat) where
  constructor MkPlacedNumber
  number : Fin n
  place : Nat
  0 counts : finToNat number = place

||| What a writing lands as, at its position.
record LandingAt (n : Nat) where
  constructor MkLandingAt
  at : PlacedNumber n
  landing : Landing

-- The place a landing is at.
landedPlace : {0 n : Nat} -> LandingAt n -> Nat
landedPlace x = x.at.place

------------------------------------------------------------------------------
-- The landings ordered by place
------------------------------------------------------------------------------

-- What comparing two places says of them.
0 orderedFirst : (a, b : Nat) -> compareNat a b === LT -> LTE a b
orderedFirst Z b _ = LTEZero
orderedFirst (S a) Z Refl impossible
orderedFirst (S a) (S b) eq = LTESucc (orderedFirst a b eq)

0 takenFirst : (a, b : Nat) -> compareNat a b === EQ -> LTE a b
takenFirst Z Z _ = LTEZero
takenFirst Z (S b) Refl impossible
takenFirst (S a) Z Refl impossible
takenFirst (S a) (S b) eq = LTESucc (takenFirst a b eq)

0 takenSecond : (a, b : Nat) -> compareNat a b === GT -> LTE b a
takenSecond Z Z Refl impossible
takenSecond Z (S b) Refl impossible
takenSecond (S a) Z _ = LTEZero
takenSecond (S a) (S b) eq = LTESucc (takenSecond a b eq)

-- Landings ascending by place from `lo`: each placed no lower than the one
-- before it, the first no lower than `lo`.
data Ascending : {0 n : Nat} -> Nat -> List (LandingAt n) -> Type where
  Ended : Ascending lo []
  Rising : {0 x : LandingAt n} -> {0 xs : List (LandingAt n)} ->
           LTE lo (landedPlace x) -> Ascending (landedPlace x) xs -> Ascending lo (x :: xs)

mutual
  -- Two runs ascending by place merged into one, the first run's landing
  -- first where two are placed alike, so that the landings at one place
  -- stay in the order they were written in.
  mergePlaced : {0 n : Nat} -> List (LandingAt n) -> List (LandingAt n) -> List (LandingAt n)
  mergePlaced [] ys = ys
  mergePlaced (x :: xs) ys = mergeInto x xs ys

  -- A run's first landing and the rest of it merged into another run.
  mergeInto : {0 n : Nat} -> LandingAt n -> List (LandingAt n) -> List (LandingAt n) -> List (LandingAt n)
  mergeInto x xs [] = x :: xs
  mergeInto x xs (y :: ys) = mergeStep (compareNat (landedPlace x) (landedPlace y)) x xs y ys

  -- The lower of two first landings taken, the first run's on a tie.
  mergeStep : {0 n : Nat} -> Ordering -> LandingAt n -> List (LandingAt n) -> LandingAt n -> List (LandingAt n) ->
              List (LandingAt n)
  mergeStep LT x xs y ys = x :: mergePlaced xs (y :: ys)
  mergeStep EQ x xs y ys = x :: mergePlaced xs (y :: ys)
  mergeStep GT x xs y ys = y :: mergeInto x xs ys

-- Each landing a run of its own.
singles : List a -> List (List a)
singles [] = []
singles (x :: xs) = [x] :: singles xs

-- Runs merged two by two, in order.
pairedRuns : {0 n : Nat} -> List (List (LandingAt n)) -> List (List (LandingAt n))
pairedRuns [] = []
pairedRuns [r] = [r]
pairedRuns (r :: r' :: rs) = mergePlaced r r' :: pairedRuns rs

0 pairedNoLonger : (rs : List (List (LandingAt n))) -> LTE (length (pairedRuns rs)) (length rs)
pairedNoLonger [] = LTEZero
pairedNoLonger [r] = LTESucc LTEZero
pairedNoLonger (r :: r' :: rs) = lteSuccRight (LTESucc (pairedNoLonger rs))

-- Merging two by two leaves fewer runs, where there were two or more.
0 pairedShorter : (r, r' : List (LandingAt n)) -> (rs : List (List (LandingAt n))) ->
                  LT (length (pairedRuns (r :: r' :: rs))) (length (r :: r' :: rs))
pairedShorter r r' rs = LTESucc (LTESucc (pairedNoLonger rs))

-- Runs merged two by two until one is left: each round leaves fewer, the
-- measure it recurses on.
mergeAll : {0 n : Nat} -> (rs : List (List (LandingAt n))) -> (0 _ : Accessible LT (length rs)) -> List (LandingAt n)
mergeAll [] _ = []
mergeAll [r] _ = r
mergeAll (r :: r' :: rs) (Access more) = mergeAll (pairedRuns (r :: r' :: rs)) (more _ (pairedShorter r r' rs))

||| The landings ordered by place, those placed alike in the order they
||| were written in: a merge sort, its comparisons of places the machine's.
byPlace : {0 n : Nat} -> List (LandingAt n) -> List (LandingAt n)
byPlace xs = mergeAll (singles xs) (wellFounded _)

-- A run ascending from a place ascends from any lower one.
0 ascendingLower : LTE lo lo' -> Ascending lo' xs -> Ascending lo xs
ascendingLower le Ended = Ended
ascendingLower le (Rising here rest) = Rising (transitive le here) rest

mutual
  -- Two runs ascending from a place merge into one that does.
  0 mergeAscending : (xs, ys : List (LandingAt n)) -> Ascending lo xs -> Ascending lo ys -> Ascending lo (mergePlaced xs ys)
  mergeAscending [] ys _ ay = ay
  mergeAscending (x :: xs) ys (Rising lx axs) ay = intoAscending x xs ys lx axs ay

  0 intoAscending : (x : LandingAt n) -> (xs, ys : List (LandingAt n)) -> LTE lo (landedPlace x) ->
                    Ascending (landedPlace x) xs -> Ascending lo ys -> Ascending lo (mergeInto x xs ys)
  intoAscending x xs [] lx axs Ended = Rising lx axs
  intoAscending x xs (y :: ys) lx axs (Rising ly ays) =
    stepAscending x xs y ys (compareNat (landedPlace x) (landedPlace y)) Refl lx axs ly ays

  0 stepAscending : (x : LandingAt n) -> (xs : List (LandingAt n)) -> (y : LandingAt n) -> (ys : List (LandingAt n)) ->
                    (o : Ordering) -> compareNat (landedPlace x) (landedPlace y) = o ->
                    LTE lo (landedPlace x) -> Ascending (landedPlace x) xs -> LTE lo (landedPlace y) ->
                    Ascending (landedPlace y) ys -> Ascending lo (mergeStep o x xs y ys)
  stepAscending x xs y ys LT lt lx axs ly ays =
    Rising lx (mergeAscending xs (y :: ys) axs (Rising (orderedFirst _ _ lt) ays))
  stepAscending x xs y ys EQ eq lx axs ly ays =
    Rising lx (mergeAscending xs (y :: ys) axs (Rising (takenFirst _ _ eq) ays))
  stepAscending x xs y ys GT gt lx axs ly ays =
    Rising ly (intoAscending x xs ys (takenSecond _ _ gt) axs ays)

mutual
  -- A landing of the first run is in the merge.
  0 mergeKeepsLeft : (xs, ys : List (LandingAt n)) -> Elem z xs -> Elem z (mergePlaced xs ys)
  mergeKeepsLeft [] ys e = absurd e
  mergeKeepsLeft (x :: xs) ys Here = intoKeepsHead x xs ys
  mergeKeepsLeft (x :: xs) ys (There e) = intoKeepsTail x xs ys e

  0 intoKeepsHead : (x : LandingAt n) -> (xs, ys : List (LandingAt n)) -> Elem x (mergeInto x xs ys)
  intoKeepsHead x xs [] = Here
  intoKeepsHead x xs (y :: ys) = stepKeepsHead x xs y ys (compareNat (landedPlace x) (landedPlace y))

  0 stepKeepsHead : (x : LandingAt n) -> (xs : List (LandingAt n)) -> (y : LandingAt n) -> (ys : List (LandingAt n)) ->
                    (o : Ordering) -> Elem x (mergeStep o x xs y ys)
  stepKeepsHead x xs y ys LT = Here
  stepKeepsHead x xs y ys EQ = Here
  stepKeepsHead x xs y ys GT = There (intoKeepsHead x xs ys)

  0 intoKeepsTail : (x : LandingAt n) -> (xs, ys : List (LandingAt n)) -> Elem z xs -> Elem z (mergeInto x xs ys)
  intoKeepsTail x xs [] e = There e
  intoKeepsTail x xs (y :: ys) e = stepKeepsTail x xs y ys (compareNat (landedPlace x) (landedPlace y)) e

  0 stepKeepsTail : (x : LandingAt n) -> (xs : List (LandingAt n)) -> (y : LandingAt n) -> (ys : List (LandingAt n)) ->
                    (o : Ordering) -> Elem z xs -> Elem z (mergeStep o x xs y ys)
  stepKeepsTail x xs y ys LT e = There (mergeKeepsLeft xs (y :: ys) e)
  stepKeepsTail x xs y ys EQ e = There (mergeKeepsLeft xs (y :: ys) e)
  stepKeepsTail x xs y ys GT e = There (intoKeepsTail x xs ys e)

mutual
  -- A landing of the second run is in the merge.
  0 mergeKeepsRight : (xs, ys : List (LandingAt n)) -> Elem z ys -> Elem z (mergePlaced xs ys)
  mergeKeepsRight [] ys e = e
  mergeKeepsRight (x :: xs) ys e = intoKeepsRight x xs ys e

  0 intoKeepsRight : (x : LandingAt n) -> (xs, ys : List (LandingAt n)) -> Elem z ys -> Elem z (mergeInto x xs ys)
  intoKeepsRight x xs [] e = absurd e
  intoKeepsRight x xs (y :: ys) e = stepKeepsRight x xs y ys (compareNat (landedPlace x) (landedPlace y)) e

  0 stepKeepsRight : (x : LandingAt n) -> (xs : List (LandingAt n)) -> (y : LandingAt n) -> (ys : List (LandingAt n)) ->
                     (o : Ordering) -> Elem z (y :: ys) -> Elem z (mergeStep o x xs y ys)
  stepKeepsRight x xs y ys LT e = There (mergeKeepsRight xs (y :: ys) e)
  stepKeepsRight x xs y ys EQ e = There (mergeKeepsRight xs (y :: ys) e)
  stepKeepsRight x xs y ys GT Here = Here
  stepKeepsRight x xs y ys GT (There e) = There (intoKeepsRight x xs ys e)

0 singlesKeep : (xs : List a) -> Elem z xs -> Any (Elem z) (singles xs)
singlesKeep (x :: xs) Here = Here Here
singlesKeep (x :: xs) (There e) = There (singlesKeep xs e)

0 pairedKeeps : (rs : List (List (LandingAt n))) -> Any (Elem z) rs -> Any (Elem z) (pairedRuns rs)
pairedKeeps [] (Here _) impossible
pairedKeeps [] (There _) impossible
pairedKeeps [r] e = e
pairedKeeps (r :: r' :: rs) (Here e) = Here (mergeKeepsLeft r r' e)
pairedKeeps (r :: r' :: rs) (There (Here e)) = Here (mergeKeepsRight r r' e)
pairedKeeps (r :: r' :: rs) (There (There e)) = There (pairedKeeps rs e)

0 allKeeps : (rs : List (List (LandingAt n))) -> (acc : Accessible LT (length rs)) -> Any (Elem z) rs -> Elem z (mergeAll rs acc)
allKeeps [] _ (Here _) impossible
allKeeps [] _ (There _) impossible
allKeeps [r] _ (Here e) = e
allKeeps [r] _ (There (Here _)) impossible
allKeeps [r] _ (There (There _)) impossible
allKeeps (r :: r' :: rs) (Access more) e =
  allKeeps (pairedRuns (r :: r' :: rs)) (more _ (pairedShorter r r' rs)) (pairedKeeps (r :: r' :: rs) e)

0 singlesAscending : (xs : List (LandingAt n)) -> All (Ascending 0) (singles xs)
singlesAscending [] = []
singlesAscending (x :: xs) = Rising LTEZero Ended :: singlesAscending xs

0 pairedAscending : (rs : List (List (LandingAt n))) -> All (Ascending 0) rs -> All (Ascending 0) (pairedRuns rs)
pairedAscending [] [] = []
pairedAscending [r] [a] = [a]
pairedAscending (r :: r' :: rs) (a :: a' :: as) = mergeAscending r r' a a' :: pairedAscending rs as

0 allAscending : (rs : List (List (LandingAt n))) -> (acc : Accessible LT (length rs)) -> All (Ascending 0) rs ->
                 Ascending 0 (mergeAll rs acc)
allAscending [] _ [] = Ended
allAscending [r] _ [a] = a
allAscending (r :: r' :: rs) (Access more) as =
  allAscending (pairedRuns (r :: r' :: rs)) (more _ (pairedShorter r r' rs)) (pairedAscending (r :: r' :: rs) as)

-- The landings by place ascend from the first place, and lose none.
0 byPlaceAscending : (xs : List (LandingAt n)) -> Ascending 0 (byPlace xs)
byPlaceAscending xs = allAscending (singles xs) _ (singlesAscending xs)

0 byPlaceKeeps : (xs : List (LandingAt n)) -> Elem z xs -> Elem z (byPlace xs)
byPlaceKeeps xs e = allKeeps (singles xs) _ (singlesKeep xs e)

------------------------------------------------------------------------------
-- The table, made once
------------------------------------------------------------------------------

mutual
  -- The landings at the front of a list placed at c, as written.
  frontAt : {0 n : Nat} -> Nat -> List (LandingAt n) -> List Landing
  frontAt c [] = []
  frontAt c (x :: xs) = frontIf (landedPlace x == c) c x xs

  frontIf : {0 n : Nat} -> Bool -> Nat -> LandingAt n -> List (LandingAt n) -> List Landing
  frontIf True c x xs = x.landing :: frontAt c xs
  frontIf False c x xs = []

mutual
  -- The landings past those at the front placed at c.
  pastAt : {0 n : Nat} -> Nat -> List (LandingAt n) -> List (LandingAt n)
  pastAt c [] = []
  pastAt c (x :: xs) = pastIf (landedPlace x == c) c x xs

  pastIf : {0 n : Nat} -> Bool -> Nat -> LandingAt n -> List (LandingAt n) -> List (LandingAt n)
  pastIf True c x xs = pastAt c xs
  pastIf False c x xs = x :: xs

-- What some landings land as, joined, the first outermost.
joinedAll : List Landing -> Maybe Landing
joinedAll [] = Nothing
joinedAll (l :: ls) = landInto l (joinedAll ls)

-- The table from place c on, k places of it: at each, what the landings
-- at the front placed there land as, joined, the rest passed on. They
-- ascend by place from c, so each place's are at the front at its turn.
sweep : {0 n : Nat} -> (c, k : Nat) -> List (LandingAt n) -> Vect k (Maybe Landing)
sweep c Z _ = []
sweep c (S k) xs = joinedAll (frontAt c xs) :: sweep (S c) k (pastAt c xs)

||| Each landing joined in at its position, the table made once: the
||| landings grouped by ordering them by place (`byPlace`), and each
||| place's joined where the sweep meets it, in the order they were written
||| in, so no landing rebuilds the table.
landedTable : {n : Nat} -> List (LandingAt n) -> LandingTable n
landedTable xs = sweep 0 n (byPlace xs)

-- A place compared with itself, and with another.
0 sameAt : (a : Nat) -> (a == a) = True
sameAt Z = Refl
sameAt (S a) = sameAt a

0 equalAt : (a, b : Nat) -> (a == b) = True -> a = b
equalAt Z Z _ = Refl
equalAt Z (S b) Refl impossible
equalAt (S a) Z Refl impossible
equalAt (S a) (S b) eq = cong S (equalAt a b eq)

0 equalFrom : {b : Nat} -> a = b -> (a == b) = True
equalFrom Refl = sameAt b

0 unS : the Nat (S a) = S b -> a = b
unS Refl = Refl

0 bothWays : LTE a b -> LTE b a -> a = b
bothWays LTEZero LTEZero = Refl
bothWays (LTESucc p) (LTESucc q) = cong S (bothWays p q)

-- A place past c that is not c is above it.
0 pastPlace : {a, c : Nat} -> LTE c a -> Not (a = c) -> LTE (S c) a
pastPlace {a = Z} LTEZero ne = void (ne Refl)
pastPlace {a = S a'} LTEZero ne = LTESucc LTEZero
pastPlace (LTESucc p) ne = LTESucc (pastPlace p (\same => ne (cong S same)))

-- A place some places past c is not c.
0 pastSelf : (c, m : Nat) -> Not (c + S m = c)
pastSelf Z m Refl impossible
pastSelf (S c) m eq = pastSelf c m (unS eq)

-- Every landing of a run ascending from a place is placed no lower.
0 ascendingBelow : Ascending lo xs -> Elem y xs -> LTE lo (landedPlace y)
ascendingBelow (Rising here _) Here = here
ascendingBelow (Rising here rest) (There e) = transitive here (ascendingBelow rest e)

mutual
  -- A landing placed at c, among landings ascending from c, is at the
  -- front.
  0 frontHere : (c : Nat) -> (xs : List (LandingAt n)) -> Ascending c xs -> {0 y : LandingAt n} -> Elem y xs ->
                landedPlace y = c -> Elem y.landing (frontAt c xs)
  frontHere c [] Ended e at = absurd e
  frontHere c (x :: xs) (Rising lx axs) e at = frontIfHere c x xs (landedPlace x == c) Refl lx axs e at

  0 frontIfHere : (c : Nat) -> (x : LandingAt n) -> (xs : List (LandingAt n)) -> (b : Bool) -> (landedPlace x == c) = b ->
                  LTE c (landedPlace x) -> Ascending (landedPlace x) xs -> {0 y : LandingAt n} -> Elem y (x :: xs) ->
                  landedPlace y = c -> Elem y.landing (frontIf b c x xs)
  frontIfHere c x xs True eq lx axs Here at = Here
  frontIfHere c x xs True eq lx axs (There e) at =
    There (frontHere c xs (replace {p = \k => Ascending k xs} (equalAt (landedPlace x) c eq) axs) e at)
  frontIfHere c x xs False ne lx axs Here at = absurd (trans (sym (equalFrom at)) ne)
  frontIfHere c x xs False ne lx axs (There e) at =
    absurd (trans (sym (equalFrom (bothWays (replace {p = LTE (landedPlace x)} at (ascendingBelow axs e)) lx))) ne)

mutual
  -- A landing not placed at c is past the front placed there.
  0 pastKeeps : (c : Nat) -> (xs : List (LandingAt n)) -> {0 y : LandingAt n} -> Elem y xs -> Not (landedPlace y = c) ->
                Elem y (pastAt c xs)
  pastKeeps c [] e _ = absurd e
  pastKeeps c (x :: xs) e off = pastIfKeeps c x xs (landedPlace x == c) Refl e off

  0 pastIfKeeps : (c : Nat) -> (x : LandingAt n) -> (xs : List (LandingAt n)) -> (b : Bool) -> (landedPlace x == c) = b ->
                  {0 y : LandingAt n} -> Elem y (x :: xs) -> Not (landedPlace y = c) -> Elem y (pastIf b c x xs)
  pastIfKeeps c x xs True eq Here off = void (off (equalAt (landedPlace x) c eq))
  pastIfKeeps c x xs True eq (There e) off = pastKeeps c xs e off
  pastIfKeeps c x xs False _ e off = e

mutual
  -- Past the front placed at c, what is left ascends from past c.
  0 pastAscending : (c : Nat) -> (xs : List (LandingAt n)) -> Ascending c xs -> Ascending (S c) (pastAt c xs)
  pastAscending c [] Ended = Ended
  pastAscending c (x :: xs) (Rising lx axs) = pastIfAscending c x xs (landedPlace x == c) Refl lx axs

  0 pastIfAscending : (c : Nat) -> (x : LandingAt n) -> (xs : List (LandingAt n)) -> (b : Bool) -> (landedPlace x == c) = b ->
                      LTE c (landedPlace x) -> Ascending (landedPlace x) xs -> Ascending (S c) (pastIf b c x xs)
  pastIfAscending c x xs True eq lx axs =
    pastAscending c xs (replace {p = \k => Ascending k xs} (equalAt (landedPlace x) c eq) axs)
  pastIfAscending c x xs False ne lx axs = Rising (pastPlace lx (\same => absurd (trans (sym (equalFrom same)) ne))) axs

-- What landings joined hold bounds each of them.
0 joinedBounds : (ls : List Landing) -> Elem l ls -> (m : Landing ** (joinedAll ls = Just m, BoundedBy l (Just m)))
joinedBounds (l :: ls) Here = landsInto l (joinedAll ls)
joinedBounds {l} (l' :: ls) (There e) = case joinedBounds ls e of
  (m ** (eq, bounded)) => (joinLanding l' m ** (cong (landInto l') eq, joinedOver l l' m bounded))

-- A landing, among landings ascending from c, placed q places past c, is
-- bounded by what the table from c holds there.
0 sweepBounds : (c, k : Nat) -> (xs : List (LandingAt n)) -> Ascending c xs -> {0 y : LandingAt n} -> Elem y xs ->
                (q : Fin k) -> landedPlace y = c + finToNat q ->
                (m : Landing ** (Vect.index q (sweep c k xs) = Just m, BoundedBy y.landing (Just m)))
sweepBounds c Z xs asc e q at = absurd q
sweepBounds c (S k) xs asc e FZ at = joinedBounds (frontAt c xs) (frontHere c xs asc e (trans at (plusZeroRightNeutral c)))
sweepBounds c (S k) xs asc e (FS q) at =
  sweepBounds (S c) k (pastAt c xs) (pastAscending c xs asc)
              (pastKeeps c xs e (\same => pastSelf c (finToNat q) (trans (sym at) same)))
              q (trans at (sym (plusSuccRightSucc c (finToNat q))))

-- Every landing joined into the table is bounded by its position's entry,
-- which something landed in.
0 landedBounds : {n : Nat} -> (xs : List (LandingAt n)) -> {0 y : LandingAt n} -> Elem y xs ->
                 (m : Landing ** (Vect.index y.at.number (landedTable xs) = Just m, BoundedBy y.landing (Just m)))
landedBounds {y} xs e = sweepBounds 0 n (byPlace xs) (byPlaceAscending xs) (byPlaceKeeps xs e) y.at.number (sym y.at.counts)

-- Joining Open in leaves no closed value.
0 openNotClosed : (m : Landing) -> Not (joinLanding Open m = Closed k)
openNotClosed (Closed _) Refl impossible
openNotClosed Open Refl impossible
openNotClosed Computed Refl impossible
openNotClosed (Evaluable _) Refl impossible

||| Where values no writing states land as well, so nothing there is
||| closed: at a capped position, every value of the cap's height.
openedTable : Vect n (Maybe Nat) -> LandingTable n -> LandingTable n
openedTable [] [] = []
openedTable (Nothing :: caps) (l :: ls) = l :: openedTable caps ls
openedTable (Just _ :: caps) (l :: ls) = landInto Open l :: openedTable caps ls

-- Where only closed values land in the opened table, the position is
-- uncapped and they landed there before.
0 openedClosed : (caps : Vect n (Maybe Nat)) -> (t : LandingTable n) -> (p : Fin n) ->
                 Vect.index p (openedTable caps t) = Just (Closed k) -> (Vect.index p caps = Nothing, Vect.index p t = Just (Closed k))
openedClosed [] [] p _ = absurd p
openedClosed (Nothing :: caps) (l :: ls) FZ eq = (Refl, eq)
openedClosed (Just _ :: caps) (Nothing :: ls) FZ Refl impossible
openedClosed (Just _ :: caps) (Just m :: ls) FZ eq = void (openNotClosed m (sameJust eq))
openedClosed (Nothing :: caps) (l :: ls) (FS p) eq = openedClosed caps ls p eq
openedClosed (Just _ :: caps) (l :: ls) (FS p) eq = openedClosed caps ls p eq

0 computedNotClosed : Not (Just Computed = Just (Closed k))
computedNotClosed Refl impossible

-- An entry marked as computing where its position is among those that
-- compute, else kept.
markedIf : Bool -> Maybe Landing -> Maybe Landing
markedIf True _ = Just Computed
markedIf False l = l

-- The entries from position c on, each marked where its number is among
-- those that compute.
markedFrom : Nat -> SortedSet Nat -> Vect k (Maybe Landing) -> Vect k (Maybe Landing)
markedFrom c s [] = []
markedFrom c s (l :: ls) = markedIf (contains c s) l :: markedFrom (S c) s ls

||| A value that computes, at each of some positions: their numbers made a
||| set once, and the table walked once, each position marked where its
||| number is in the set, so no position costs a walk to it.
computedAt : List (Fin n) -> LandingTable n -> LandingTable n
computedAt xs t = markedFrom 0 (SortedSet.fromList (map finToNat xs)) t

-- A mark leaves no closed value that was not there.
0 markedClosed : (b : Bool) -> markedIf b l = Just (Closed k) -> l = Just (Closed k)
markedClosed True eq = void (computedNotClosed eq)
markedClosed False eq = eq

0 markedFromClosed : (c : Nat) -> (s : SortedSet Nat) -> (t : Vect j (Maybe Landing)) -> (p : Fin j) ->
                     Vect.index p (markedFrom c s t) = Just (Closed k) -> Vect.index p t = Just (Closed k)
markedFromClosed c s [] p eq = absurd p
markedFromClosed c s (l :: ls) FZ eq = markedClosed (contains c s) eq
markedFromClosed c s (l :: ls) (FS p) eq = markedFromClosed (S c) s ls p eq

-- Where only closed values land after, they landed there before.
0 computedClosed : (xs : List (Fin n)) -> (t : LandingTable n) -> (p : Fin n) ->
                   Vect.index p (computedAt xs t) = Just (Closed k) -> Vect.index p t = Just (Closed k)
computedClosed xs t p eq = markedFromClosed 0 (SortedSet.fromList (map finToNat xs)) t p eq

-- A parameter read at a position nothing landed at reads no closed value.
readIf : Bool -> Landing -> Maybe Landing -> Maybe Landing
readIf True l rest = landInto l rest
readIf False _ rest = rest

-- What the held table gives at a position is the table's entry there.
0 heldEntry : {0 t : LandingTable n} -> {0 e : Maybe Landing} -> (held : Indexed t) -> (q : Fin n) ->
              (entryAt q held).fst = e -> Vect.index q t = e
heldEntry held q same = trans (sym (entryAt q held).snd) same

||| What lands where a writer reads parameter i, off the table held as a
||| tree (`Indexed`), so that a position costs the tree's depth rather than
||| a walk to it: what landed at each position its writers list i at,
||| joined, a position nothing landed at no closed value; nothing where
||| none is listed.
landedAt : {0 t : LandingTable n} -> Indexed t -> List (Nat, Fin n) -> Nat -> Maybe Landing
landedAt held [] i = Nothing
landedAt held ((j, p) :: ws) i = readIf (j == i) (fromMaybe Open (entryAt p held).fst) (landedAt held ws i)

||| What lands where a writer reads each parameter, off the held table;
||| nothing listed is no closed value.
readLanding : {0 t : LandingTable n} -> Indexed t -> List (Nat, Fin n) -> Nat -> Landing
readLanding held ws i = fromMaybe Open (landedAt held ws i)

-- A landing read as closed values was read so off a closed entry.
0 fromMaybeClosed : (m : Maybe Landing) -> fromMaybe Open m = Closed x -> m = Just (Closed x)
fromMaybeClosed Nothing Refl impossible
fromMaybeClosed (Just l) eq = cong Just eq

-- A landing joined into anything is something.
0 landedJust : (l : Landing) -> (old : Maybe Landing) -> (m : Landing ** landInto l old = Just m)
landedJust l Nothing = (l ** Refl)
landedJust l (Just o) = (joinLanding l o ** Refl)

-- A parameter its writers list here is read.
0 listedHere : {0 t : LandingTable n} -> (held : Indexed t) -> (ws : List (Nat, Fin n)) -> (i : Nat) -> (p : Fin n) ->
               (b : Bool) -> b = True ->
               (m : Landing ** readIf b (fromMaybe Open (entryAt p held).fst) (landedAt held ws i) = Just m)
listedHere held ws i p True _ = landedJust (fromMaybe Open (entryAt p held).fst) (landedAt held ws i)
listedHere held ws i p False no = absurd no

-- A parameter read below is read here too.
0 listedLater : {0 t : LandingTable n} -> (held : Indexed t) -> (ws : List (Nat, Fin n)) -> (i : Nat) -> (q : Fin n) ->
                (b : Bool) -> (m : Landing ** landedAt held ws i = Just m) ->
                (m : Landing ** readIf b (fromMaybe Open (entryAt q held).fst) (landedAt held ws i) = Just m)
listedLater held ws i q True _ = landedJust (fromMaybe Open (entryAt q held).fst) (landedAt held ws i)
listedLater held ws i q False later = later

-- A parameter its writers list is read.
0 listedRead : {0 t : LandingTable n} -> (held : Indexed t) -> (ws : List (Nat, Fin n)) -> Elem (i, p) ws ->
               (m : Landing ** landedAt held ws i = Just m)
listedRead held ((i, p) :: ws) Here = listedHere held ws i p (i == i) (soToEq (equalSelf i))
listedRead {i} held ((j, q) :: ws) (There el) = listedLater held ws i q (j == i) (listedRead held ws el)

mutual
  -- What a site reads off the table: a parameter read as closed values no
  -- higher than k is read at positions where closed values no higher than
  -- k landed.
  0 tableRead : {0 t : LandingTable n} -> (held : Indexed t) -> (ws : List (Nat, Fin n)) -> (i : Nat) ->
                landedAt held ws i = Just (Closed k) ->
                Elem (i, p) ws -> (k' : Nat ** (Vect.index p t = Just (Closed k'), LTE k' k))
  tableRead held [] i eq el = absurd el
  tableRead held ((j, q) :: ws) i eq el = tableReadAt held j q ws i (j == i) Refl eq el

  0 tableReadAt : {0 t : LandingTable n} -> (held : Indexed t) -> (j : Nat) -> (q : Fin n) -> (ws : List (Nat, Fin n)) ->
                  (i : Nat) -> (b : Bool) -> (j == i) = b ->
                  readIf b (fromMaybe Open (entryAt q held).fst) (landedAt held ws i) = Just (Closed k) ->
                  Elem (i, p) ((j, q) :: ws) -> (k' : Nat ** (Vect.index p t = Just (Closed k'), LTE k' k))
  -- At `Here` the parameter read is the entry's own, j.
  tableReadAt held j q ws _ True _ eq Here = case intoClosed (fromMaybe Open (entryAt q held).fst) (landedAt held ws j) eq of
    ((x ** (here, le)), _) => (x ** (heldEntry held q (fromMaybeClosed (entryAt q held).fst here), le))
  tableReadAt held j q ws i True _ eq (There el) = case intoClosed (fromMaybe Open (entryAt q held).fst) (landedAt held ws i) eq of
    (_, rest) => case listedRead held ws el of
      (m ** later) => case rest m later of
        (y ** (Refl, le)) => case tableRead held ws i later el of
          (k' ** (atP, le')) => (k' ** (atP, transitive le' le))
  tableReadAt held j q ws _ False same eq Here = absurd (trans (sym (soToEq (equalSelf j))) same)
  tableReadAt held j q ws i False _ eq (There el) = tableRead held ws i eq el

||| A site's landing read off the held table reads the table.
0 landingReads : {0 t : LandingTable n} -> (held : Indexed t) -> (ws : List (Nat, Fin n)) -> ReadsTable t ws (readLanding held ws)
landingReads held ws i k read p el = tableRead held ws i (fromMaybeClosed (landedAt held ws i) read) el

-- Where each numbered position carries a family's value on, keyed by the
-- source's number and by the target's: from each position of the writer
-- whose family an argument passes on or applies (`familiesIn`), into the
-- argument's position; and from each position of an implementation J,
-- into the method function's position its leading placement gives, from
-- every walked node of J, which can only carry more. A position the
-- numbering never met has no number, and nothing computing to carry.
record Carrying (n : Nat) where
  constructor MkCarrying
  onward : SortedMap Nat (List (Fin n))
  back : SortedMap Nat (List (Fin n))

carried : {0 n : Nat} -> SortedMap Spot (PlacedNumber n) -> SortedMap Address (List Node) -> Leads ->
          List (Node, List (Sites.Site, Reached Defined)) -> Carrying n
carried number nodes leads walked =
  let cs = eachPlaced (\acc, w, s, callee, pl =>
                         foldl (\acc', i => carry (spotAt w s.params i) (landsAt callee pl.parameter) acc') acc (familiesIn pl.argument.template))
                      (MkCarrying empty empty) walked in
  foldl (\acc, ((callee, j, _), l) =>
           foldl (\acc', (p, q) => foldl (\acc'', x => carry (OfParameter (OfNode x) p) (OfParameter (OfNode callee) q) acc'') acc'
                                          (fromMaybe [] (lookup j nodes)))
                 acc l.placing)
        cs (SortedMap.toList leads)
  where
    add : Fin n -> Fin n -> SortedMap Nat (List (Fin n)) -> SortedMap Nat (List (Fin n))
    add a b m = insert (finToNat a) (b :: fromMaybe [] (lookup (finToNat a) m)) m

    carry : Spot -> Spot -> Carrying n -> Carrying n
    carry p q cs = case (lookup p number, lookup q number) of
      (Just a, Just b) => MkCarrying (add a.number b.number cs.onward) (add b.number a.number cs.back)
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
applying : {0 n : Nat} -> SortedMap Spot (PlacedNumber n) -> List (Node, List (Sites.Site, Reached Defined)) -> List (Fin n)
applying number =
  eachPlaced (\acc, w, s, _, pl => mapMaybe (\i => (.number) <$> lookup (spotAt w s.params i) number)
                                            ((pl.argument.template :: heldTemplates pl.argument) >>= applyingIn) ++ acc) []

-- Every position reachable from the queue along the carries, each once,
-- with those found before: a walk that visits each position once, its
-- marks a tree made once (`Indexed.Marks`), so a visit costs the tree's
-- depth and a first one leaves fewer unvisited, the measure it recurses
-- on; nothing counts its steps.
spread : (next : Fin n -> List (Fin n)) -> (marks : Marks n left) -> (0 acc : Accessible LT left) ->
         (found : List (Fin n)) -> List (Fin n) -> List (Fin n)
spread next marks _ found [] = found
spread next marks (Access rec) found (x :: xs) = case visitMark x marks of
  SeenBefore => spread next marks (Access rec) found xs
  FirstSeen marks' fewer => spread next marks' (rec _ fewer) (x :: found) (next x ++ xs)

-- A landing that computes, which carries on.
computes : Maybe Landing -> Bool
computes (Just Computed) = True
computes (Just (Evaluable _)) = True
computes _ = False

-- The positions, from i on, of a table's last entries where a value that
-- computes lands, ascending, in one pass: each position's number is the
-- counter, made a `Fin` by `natToFinLT`, the identity at run time, where
-- base's `findIndices` maps `FS` over every position found after each.
computingFrom : (i : Nat) -> Vect r (Maybe Landing) -> (0 _ : i + r = n) -> List (Fin n)
computingFrom i [] _ = []
computingFrom i (l :: ls) eq =
  let rest = computingFrom (S i) ls (trans (plusSuccRightSucc i _) eq) in
  if computes l then natToFinLT i {prf = runBelow i eq} :: rest else rest

-- Where a computing value is carried on to from where one lands: every
-- position that carries a family's value on from there, since a family
-- whose value can be one there may compute when it is applied, wherever
-- the value was written. Only a position an applied family's reading
-- reads, or one that carries on to it, is asked, so the carrying runs over
-- those alone: a type's marker passed on carries no family, and nothing
-- applies it. With no computing value written there is nothing to carry.
carriedTo : {n : Nat} -> SortedMap Spot (PlacedNumber n) -> SortedMap Address (List Node) -> Leads ->
            List (Node, List (Sites.Site, Reached Defined)) -> LandingTable n -> List (Fin n)
carriedTo number nodes leads walked t = case computingFrom 0 t Refl of
  [] => []
  seeds@(_ :: _) =>
    let cs = carried number nodes leads walked
        asked = spread (\x => fromMaybe [] (lookup (finToNat x) cs.back)) (noneVisited n) (wellFounded _) []
                       (applying number walked)
        askedSet = SortedSet.fromList (map finToNat asked)
        onward = \x => filter (\y => contains (finToNat y) askedSet) (fromMaybe [] (lookup (finToNat x) cs.onward)) in
    -- What a computing value is carried on to: a position it lands at as
    -- written keeps its landing (an evaluable one its values).
    spread onward (noneVisited n) (wellFounded _) [] (filter (\x => contains (finToNat x) askedSet) seeds >>= onward)

-- A table with a computing value carried on from where one lands.
carriedFrom : {n : Nat} -> SortedMap Spot (PlacedNumber n) -> SortedMap Address (List Node) -> Leads ->
              List (Node, List (Sites.Site, Reached Defined)) -> LandingTable n -> LandingTable n
carriedFrom number nodes leads walked t = computedAt (carriedTo number nodes leads walked t) t

||| What lands at every numbered position: what each writing lands as,
||| joined at its position (`landedTable`), what lands at a capped one
||| besides (`openedTable`), and a computing value carried on
||| (`carriedTo`).
tableOf : {n : Nat} -> SortedMap Spot (PlacedNumber n) -> Vect n (Maybe Nat) -> SortedMap Address (List Node) -> Leads ->
          List (Node, List (Sites.Site, Reached Defined)) -> List (LandingAt n) -> LandingTable n
tableOf number caps nodes leads walked written = carriedFrom number nodes leads walked (openedTable caps (landedTable written))

-- Every landing written is bounded by what the table holds at its
-- position.
0 tableBounds : {n : Nat} -> (number : SortedMap Spot (PlacedNumber n)) -> (caps : Vect n (Maybe Nat)) ->
                (nodes : SortedMap Address (List Node)) -> (leads : Leads) -> (walked : List (Node, List (Sites.Site, Reached Defined))) ->
                (written : List (LandingAt n)) -> {0 y : LandingAt n} -> Elem y written ->
                BoundedBy y.landing (Vect.index y.at.number (tableOf number caps nodes leads walked written))
tableBounds {y} number caps nodes leads walked written el k eq =
  case landedBounds written el of
    (m ** (atP, bounded)) =>
      bounded k (trans (sym atP)
                       (snd (openedClosed caps (landedTable written) y.at.number
                               (computedClosed (carriedTo number nodes leads walked (openedTable caps (landedTable written)))
                                               (openedTable caps (landedTable written)) y.at.number eq))))

-- A position only closed values land at in the table is uncapped.
0 tableUncapped : {n : Nat} -> (number : SortedMap Spot (PlacedNumber n)) -> (caps : Vect n (Maybe Nat)) ->
                  (nodes : SortedMap Address (List Node)) -> (leads : Leads) -> (walked : List (Node, List (Sites.Site, Reached Defined))) ->
                  (written : List (LandingAt n)) ->
                  (p : Fin n) -> Vect.index p (tableOf number caps nodes leads walked written) = Just (Closed k) ->
                  Vect.index p caps = Nothing
tableUncapped number caps nodes leads walked written p eq =
  fst (openedClosed caps (landedTable written) p
         (computedClosed (carriedTo number nodes leads walked (openedTable caps (landedTable written)))
                         (openedTable caps (landedTable written)) p eq))

-- Where a writing's writer is read: at a walked node, its parameters as
-- its site reads them, where the node's families land and the flow roots
-- its dictionaries; or, for the values a dictionary's place holds written
-- on, at the held position they come from, whose template applies no
-- family and holds no dictionary of its own.
data WriterAt = AtNode Node Parameters | AtHeld

-- What a writing lands as at its position: an argument as its landing
-- reads it (`landingOf`); a leading arc's marker, a field's template, a
-- held value and a held packing's chain as values no closed reading
-- bounds, since each writes what its writer's own writers gave it.
landedBy : Wrote -> Landing
landedBy (FromArgument _ x) = landingOf x
landedBy ThroughMethod = Open
landedBy (InField _ _ _) = Open
landedBy (PacksHeld _) = Open

-- What a writing's landing says of its template: landing closed values no
-- higher than k, it is a template no marker holds, k high.
0 LandsAs : Wrote -> Template -> Type
LandsAs wr t = (k : Nat) -> landedBy wr = Closed k -> (selfBounded t = True, height t = k)

-- An argument lands as its template says. The site is given: what an
-- argument lands as is the argument's alone, so no type names the site.
0 argumentLands : (s : Sites.Site) -> (x : Argument) -> LandsAs (FromArgument s x) x.template
argumentLands s x k eq = closedBy x.root (beta x.template) (selfBounded x.template) x.term x.template eq

0 openNotClosedLanding : Open = Closed k -> Void
openNotClosedLanding Refl impossible

-- A writing that lands as values no closed reading bounds, as a leading
-- arc's marker, a field's template and a held value do, says nothing of
-- its template: no closed value lands. What wrote it and its template are
-- given, since such a landing names neither.
0 openLands : (wr : Wrote) -> landedBy wr = Open -> (t : Template) -> LandsAs wr t
openLands wr landed t k closed = void (openNotClosedLanding (trans (sym landed) closed))

-- What one template wrote, before its writer's families are read where
-- they land: where its writer reads each of its parameters, with what a
-- message reads of what each such position is named by, the template as
-- written, where its writer is (`WriterAt`), the position it lands at,
-- with what a message reads of it, and what wrote it, with the template
-- it draws and what its landing says of the template. What lands at a
-- position is read off these, every writing the model holds among them
-- (`tableOf`), and only then is each read where its writer is
-- (`siteRead`), so no writing lands unseen by the landing it is read at.
-- What a message reads of each position is numbered with the positions
-- (`slotsRead`), so no message looks up a definition a position names.
record Written where
  constructor MkWritten
  reads : Nat -> Spot
  readsRead : (i : Nat) -> SpotRead (reads i)
  template : Template
  writer : WriterAt
  target : Spot
  targetRead : SpotRead target
  wrote : Wrote
  0 draws : DrawnBy wrote template
  0 landsAs : LandsAs wrote template

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
drawnRead c {t} (ArgumentDraws same) = ArgumentDraws (trans (landedRecursions c t) same)
drawnRead c {t} (FieldDraws same) = FieldDraws (trans (landedRecursions c t) same)
drawnRead c (MarkerDraws p) = MarkerDraws p
drawnRead c (ChainDraws k) = replace {p = DrawnBy (PacksHeld k)} (sym (packingRead c k)) (ChainDraws k)

-- A node's families, by index, as its definition's walk found them: what
-- `roots` reads no implementation off where it is applied.
familiesOf : SortedMap Address (List Nat) -> Node -> List Nat
familiesOf families w = fromMaybe [] (lookup w.definition families)

-- The roots a writing's template gives where its writer is: at a node, as
-- the flow found its dictionaries there, a use of one applied only where
-- values not all closed land at it (`Heads.roots`); at a held position,
-- none.
rootsAt : Flow -> SortedMap Address (List Nat) -> (Nat -> Landing) -> WriterAt -> Template -> List Address
rootsAt fl families c (AtNode w ps) = roots fl (familiesOf families w) w ps c
rootsAt fl families c AtHeld = const []

-- What those roots say of a use of the writer's parameter applied.
0 rootsApplied : (fl : Flow) -> (families : SortedMap Address (List Nat)) -> (c : Nat -> Landing) -> (wr : WriterAt) ->
                 AppliedRoots c (rootsAt fl families c wr)
rootsApplied fl families c (AtNode w ps) = appliedRootsOf fl (familiesOf families w) w ps c
rootsApplied fl families c AtHeld = \i, d, ts, j, el => absurd el

-- What those roots say of a field's record.
0 rootsRecorded : (fl : Flow) -> (families : SortedMap Address (List Nat)) -> (c : Nat -> Landing) -> (wr : WriterAt) ->
                  RecordRoots c (rootsAt fl families c wr)
rootsRecorded fl families c (AtNode w ps) = recordRootsOf fl (familiesOf families w) w ps c
rootsRecorded fl families c AtHeld = \r, j, el => absurd el

-- Every walked edge's arguments, each at the callee parameter `reaches`
-- placed it at, the latest first, as the check has always read them.
writings : List (Node, List (Sites.Site, Reached Defined)) -> List Written
writings =
  eachPlaced (\acc, w, s, callee, pl =>
                MkWritten (spotAt w s.params) (writerSpotRead s.writerDef w s.params) pl.argument.template (AtNode w s.params)
                          (landsAt callee pl.parameter) (calleeSpotRead callee pl.parameter)
                          (FromArgument s pl.argument) (ArgumentDraws Refl) (argumentLands s pl.argument) :: acc) []

-- What a dispatch that reached M through implementation J's method field
-- writes at M's leading parameters. The parameters of M its `leading`
-- placement names hold J's own, which the writers of J gave it, so each
-- walked node of J whose heads agree with M's there writes its own
-- parameter p, unchanged, at M's q. J's own call of M passes its method
-- dictionaries as run-time values, with no roots, and reaches another node
-- of M, so without these M's leading positions would have no writer.
leadingWritings : SortedMap Address (List Node) -> Leads -> List Written
leadingWritings nodes leads =
  SortedMap.toList leads >>= \((m, j, _), l) =>
    [ MkWritten (spotAt jn OwnOnly) (writerSpotRead l.jRead jn OwnOnly) (Template.Var p 0) (AtNode jn OwnOnly)
                (OfParameter (OfNode m) q) (ParameterSpot (NodeParameter l.methodRead)) ThroughMethod (MarkerDraws p)
                (openLands ThroughMethod Refl (Template.Var p 0))
    | jn <- fromMaybe [] (lookup j nodes), agrees m l.placing jn, (p, q) <- l.placing ]
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
-- them (`siteRead`), into that field's position. A field read anywhere
-- takes its value from there, so a nested field read is arcs between
-- these positions.
fieldWritings : SortedMap Address (List Node) -> SortedMap Address Fields -> List Written
fieldWritings nodes fs =
  SortedMap.toList fs >>= \(j, fields) =>
    [ MkWritten (spotAt jn OwnOnly) (writerSpotRead fields.givenBy jn OwnOnly) t.template (AtNode jn OwnOnly)
                (OfField j k) (FieldSpot (FieldOf fields.givenBy)) (InField fields.givenBy k t) (FieldDraws Refl)
                (openLands (InField fields.givenBy k t) Refl t.template)
    | jn <- fromMaybe [] (lookup j nodes), (k, t) <- numbered 0 (map (fst . fieldRead) fields.inOrder) ]
  where
    numbered : Nat -> List TemplateRead -> List (Nat, TemplateRead)
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
      Makes _ _ => { member $= max (longest s.arguments) } c
      Repacks _ path => { paths $= insert path } c
      Calls _ _ => { packed $= max (longest s.arguments) } c
      Builds _ _ => { packed $= max (longest s.arguments) } c
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
heldPackings : (count : Nat) -> Maybe Pairing -> List (place : HeldBy ** PlaceRead place) -> List Written
heldPackings count Nothing _ = []
heldPackings count (Just pg) places = case pred count of
    -- Essential: a list of fewer than two values is held as itself, in no
    -- pair.
    Z => []
    S n => places >>= written n
  where
    -- At the pair's first, one value; at its rest, one value or the rest
    -- of a list of 3 up to n + 2 values, in pairs. Each of the pair's
    -- definitions is the pairing's, as it was read.
    written : Nat -> (place : HeldBy ** PlaceRead place) -> List Written
    written n (place ** placeRead) =
      [ MkWritten (const (OfHeld (MkHeldValues place InPairs))) (\_ => HeldSpot placeRead) (packingTemplate k) AtHeld
                  (OfParameter (OfNode (MkNode h [])) j) (ParameterSpot (NodeParameter hRead)) (PacksHeld k) (ChainDraws k)
                  (openLands (PacksHeld k) Refl (packingTemplate k))
      | (h, hRead) <- [(pg.pairAddress, pg.pairDefined.def), (pg.firstAddress, pg.firstDefined.def),
                       (pg.secondAddress, pg.secondDefined.def)]
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
-- template reads its variables, with what a message reads of each such
-- position, the template, where its writer is (`WriterAt`), how many
-- values it brings (`Proof.Held.Brings`), and what wrote it, with the
-- template it draws and what its landing says of it.
record Contribution where
  constructor MkContribution
  reads : Nat -> Spot
  readsRead : (i : Nat) -> SpotRead (reads i)
  template : Template
  writer : WriterAt
  brings : Brings
  wrote : Wrote
  0 draws : DrawnBy wrote template
  0 landsAs : LandsAs wrote template

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
-- that unshown head, every choice (`Heads.membersAt`). Each with what a
-- message reads of its head.
choicePlaces : List (c : ChoiceHead ** HeadRead c) -> ChoiceHead -> List (c : ChoiceHead ** HeadRead c)
choicePlaces given UnshownHead = given
choicePlaces given k = filter (\c => c.fst == k || c.fst == UnshownHead) given

-- The choices some member of which is given values to hold, each once,
-- with what a message reads of its head, as the place that made the
-- member read it.
heldChoices : List (Node, List (Sites.Site, Reached Defined)) -> List (c : ChoiceHead ** HeadRead c)
heldChoices walked = Data.SortedMap.values (eachPlaced (\acc, _, _, callee, pl => case (callee, pl.argument.holds) of
                                                            (Making k named, _ :: _) => insert k (k ** named) acc
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
heldWritings : (count : Nat) -> Maybe Pairing -> List (c : ChoiceHead ** HeadRead c) ->
               List (Node, List (Sites.Site, Reached Defined)) -> List Written
heldWritings count pg choices walked =
  eachPlaced (\acc, w, s, callee, pl =>
                (pl.argument.holds >>= \l => listAt w s (calleePlace callee pl.parameter).fst (calleeRead callee pl.parameter)
                                                    (forget l)) ++ acc) [] walked
    ++ (walked >>= \(w, edges) => edges >>= \(s, e) => kept w s e)
  where
    fromHeld : (place : HeldBy) -> PlaceRead place -> Packed -> Packing -> Brings -> Contribution
    fromHeld place placeRead p k b =
      MkContribution (const (OfHeld (MkHeldValues place p))) (\_ => HeldSpot placeRead) (packingTemplate k) AtHeld b
                     (PacksHeld k) (ChainDraws k) (openLands (PacksHeld k) Refl (packingTemplate k))

    -- The place a dictionary of the writer's that holds values as one is
    -- at, at the writer's node, with what a message reads of it, the
    -- writer as its site read it.
    ownPlace : Node -> Sites.Site -> OwnHolder -> (place : HeldBy ** PlaceRead place)
    ownPlace w s (OwnParameter i) = ((writerPlace w s.params i).fst ** writerRead s.writerDef w s.params i)
    ownPlace w s (OwnBinding b) = (ByBinding w b ** BoundIn s.writerDef)

    -- A value of a list written from the held positions of a place, with
    -- what a message reads of the place.
    fromOwn : (place : HeldBy ** PlaceRead place) -> Packed -> Packing -> Brings -> Contribution
    fromOwn (place ** placeRead) = fromHeld place placeRead

    contributions : Node -> Sites.Site -> HeldItem -> List Contribution
    contributions w s (OfType xs) =
      [ MkContribution (spotAt w s.params) (writerSpotRead s.writerDef w s.params) x.template (AtNode w s.params) OneValue
                       (FromArgument s x) (ArgumentDraws Refl) (argumentLands s x)
      | x <- forget xs ]
    contributions w s (PackedBy h) =
      fromOwn (ownPlace w s h) AsItself AsTheyAre OneValue ::
        map (\k => fromOwn (ownPlace w s h) InPairs k OneValue) (packedHeld pg count)
    contributions w s (EachOf i) =
      [ fromHeld (writerPlace w s.params i).fst (writerRead s.writerDef w s.params i) AsItself AsTheyAre OneValue
      , fromHeld (writerPlace w s.params i).fst (writerRead s.writerDef w s.params i) InPairs AsTheyAre SeveralValues ]
    contributions w s (MembersOf k) =
      choicePlaces choices k >>= \(c ** named) =>
        [ fromHeld (ByChoice c) (ChoiceOfHead named) AsItself AsTheyAre OneValue
        , fromHeld (ByChoice c) (ChoiceOfHead named) InPairs AsTheyAre SeveralValues ]

    -- How many of the values a list is always given are other than one
    -- value of it.
    besides : HeldItem -> Nat -> Nat
    besides e n = case itemKind e of
      AlwaysOne => pred n
      AtMostOne => n
      AnyNumber => n

    listAt : Node -> Sites.Site -> (place : HeldBy) -> PlaceRead place -> List HeldItem -> List Written
    listAt w s place placeRead es =
      es >>= \e => contributions w s e >>= \c =>
        map (\p => MkWritten c.reads c.readsRead c.template c.writer (OfHeld (MkHeldValues place p)) (HeldSpot placeRead)
                             c.wrote c.draws c.landsAs)
            (landing (besides e (alwaysIn (map itemKind es))) (pred (length es)) c.brings)

    -- The list a dictionary the writer binds closes over, written at its
    -- binding's place at the writer's node.
    kept : Node -> Sites.Site -> Reached Defined -> List Written
    kept w s (Kept b items) = listAt w s (ByBinding w b) (BoundIn s.writerDef) (forget items)
    kept w s (MkReached _ _ _) = []

-- A place whose lists of several values a writing lands at, with what a
-- message reads of it; nothing for a writing that lands at any other
-- position, which no pair reads.
pairedAt : (target : Spot) -> SpotRead target -> Maybe (place : HeldBy ** PlaceRead place)
pairedAt (OfHeld (MkHeldValues place InPairs)) (HeldSpot placeRead) = Just (place ** placeRead)
pairedAt (OfHeld (MkHeldValues _ AsItself)) _ = Nothing
pairedAt (OfParameter _ _) _ = Nothing
pairedAt (OfField _ _) _ = Nothing
pairedAt (OfChoice _) _ = Nothing

-- The places whose lists of several values some place writes, each once,
-- with what a message reads of each: the pairs that hold those lists read
-- their positions.
pairedPlaces : List Written -> List (place : HeldBy ** PlaceRead place)
pairedPlaces ws = values (foldl (\acc, x => maybe acc (\pr => insert pr.fst pr acc) (pairedAt x.target x.targetRead))
                                empty ws)

-- Whether a parameter is among some, as the machine compares naturals.
amongParameters : (i : Nat) -> (is : List Nat) -> Decided (Elem i is)
amongParameters i [] = No (\el => absurd el)
amongParameters i (j :: js) = case sameNat i j of
  Proof.Growth.Yes same => Yes (rewrite same in Here)
  Proof.Growth.No other => case amongParameters i js of
    Yes el => Yes (There el)
    No out => No (\el => case el of
                           Here => other Refl
                           There e => out e)

-- The parameters of a list not already among some, each once: every one
-- of the list is among those, or kept.
unseen : (seen : List Nat) -> (is : List Nat) ->
         Subset (List Nat) (\ks => {i : Nat} -> Elem i is -> Either (Elem i seen) (Elem i ks))
unseen seen [] = Element [] (\el => absurd el)
unseen seen (i :: is) = case amongParameters i seen of
  Yes here => let (Element ks covered) = unseen seen is in
              Element ks (\el => case el of
                                   Here => Left here
                                   There e => covered e)
  No _ => let (Element ks covered) = unseen (i :: seen) is in
          Element (i :: ks) (\el => case el of
                                       Here => Right Here
                                       There e => case covered e of
                                         Left Here => Right Here
                                         Left (There inSeen) => Left inSeen
                                         Right kept => Right (There kept))

0 inFront : Elem x xs -> Elem x (xs ++ ys)
inFront Here = Here
inFront (There el) = There (inFront el)

0 behind : (xs : List a) -> Elem x ys -> Elem x (xs ++ ys)
behind [] el = el
behind (_ :: xs) el = There (behind xs el)

0 splitElem : (xs : List a) -> Elem x (xs ++ ys) -> Either (Elem x xs) (Elem x ys)
splitElem [] el = Right el
splitElem (_ :: xs) Here = Left Here
splitElem (_ :: xs) (There el) = case splitElem xs el of
  Left here => Left (There here)
  Right later => Right later

------------------------------------------------------------------------------
-- What a template names
------------------------------------------------------------------------------

mutual
  -- Every parameter of the writer's a template names, wherever: a reading
  -- of it at a node weighs or lands closed none other, whatever lands
  -- where, so its writer's positions for these are numbered before
  -- anything that lands is read.
  namedIn : Template -> List Nat
  namedIn (Var i _) = [i]
  namedIn (Applied i _ ts) = i :: namedAll ts
  namedIn (Computing i _ ts) = i :: namedAll ts
  namedIn (Head _ ts) = namedAll ts
  namedIn (Opaque _ ts) = namedAll ts
  namedIn (Choice s ts) = namedIn s ++ namedAll ts
  namedIn (Field _ r) = namedIn r
  namedIn (Leaf _) = []
  namedIn (Token _) = []
  namedIn (Member _) = []
  namedIn (Formal _ _) = []

  namedAll : List Template -> List Nat
  namedAll [] = []
  namedAll (t :: ts) = namedIn t ++ namedAll ts

mutual
  -- An occurrence names its parameter.
  0 occursNamed : (e : Nat) -> (t : Template) -> Elem (i, w) (occurrences e t) -> Elem i (namedIn t)
  occursNamed e (Var j d) Here = Here
  occursNamed e (Var j d) (There el) = absurd el
  occursNamed e (Head _ ts) el = occursNamedAll (S e) ts el
  occursNamed e (Opaque _ ts) el = stuckNamedAll ts el
  occursNamed e (Applied j d ts) Here = Here
  occursNamed e (Applied j d ts) (There el) = There (stuckNamedAll ts el)
  occursNamed e (Computing j d ts) Here = Here
  occursNamed e (Computing j d ts) (There el) = There (stuckNamedAll ts el)
  occursNamed e (Choice s ts) el = behind (namedIn s) (occursNamedAll e ts el)
  occursNamed e (Field _ _) el = absurd el
  occursNamed e (Leaf _) el = absurd el
  occursNamed e (Token _) el = absurd el
  occursNamed e (Member _) el = absurd el
  occursNamed e (Formal _ _) el = absurd el

  0 occursNamedAll : (e : Nat) -> (ts : List Template) -> Elem (i, w) (occurrencesIn e ts) -> Elem i (namedAll ts)
  occursNamedAll e [] el = absurd el
  occursNamedAll e (t :: ts) el = case splitElem (occurrences e t) el of
    Left here => inFront (occursNamed e t here)
    Right later => behind (namedIn t) (occursNamedAll e ts later)

  0 stuckNamed : (t : Template) -> Elem (i, w) (stuck t) -> Elem i (namedIn t)
  stuckNamed (Var j d) Here = Here
  stuckNamed (Var j d) (There el) = absurd el
  stuckNamed (Head _ ts) el = stuckNamedAll ts el
  stuckNamed (Opaque _ ts) el = stuckNamedAll ts el
  stuckNamed (Applied j d ts) Here = Here
  stuckNamed (Applied j d ts) (There el) = There (stuckNamedAll ts el)
  stuckNamed (Computing j d ts) Here = Here
  stuckNamed (Computing j d ts) (There el) = There (stuckNamedAll ts el)
  stuckNamed (Choice s ts) el = behind (namedIn s) (stuckNamedAll ts el)
  stuckNamed (Field _ _) el = absurd el
  stuckNamed (Leaf _) el = absurd el
  stuckNamed (Token _) el = absurd el
  stuckNamed (Member _) el = absurd el
  stuckNamed (Formal _ _) el = absurd el

  0 stuckNamedAll : (ts : List Template) -> Elem (i, w) (stuckIn ts) -> Elem i (namedAll ts)
  stuckNamedAll [] el = absurd el
  stuckNamedAll (t :: ts) el = case splitElem (stuck t) el of
    Left here => inFront (stuckNamed t here)
    Right later => behind (namedIn t) (stuckNamedAll ts later)

-- An entry of a list a weight was joined into is the weight's or was
-- there before.
0 insertJoinFrom : (i : Nat) -> (w : Weight) -> (m : List (Nat, Weight)) -> Elem (k, u) (insertJoin i w m) ->
                   Either (k = i) (v : Weight ** Elem (k, v) m)
insertJoinFrom i w [] Here = Left Refl
insertJoinFrom i w [] (There el) = absurd el
insertJoinFrom i w ((j, v) :: rest) el with (i == j)
  _ | True = case el of
    Here => Right (v ** Here)
    There later => Right (_ ** There later)
  _ | False with (i < j)
    _ | True = case el of
      Here => Left Refl
      There Here => Right (v ** Here)
      There (There later) => Right (_ ** There later)
    _ | False = case el of
      Here => Right (v ** Here)
      There later => case insertJoinFrom i w rest later of
        Left same => Left same
        Right (v' ** before) => Right (v' ** There before)

-- An entry of weights joined in is one of them, or was there before.
0 joinAllFrom : (acc, xs : List (Nat, Weight)) -> Elem (k, u) (joinAll acc xs) ->
                Either (v : Weight ** Elem (k, v) acc) (v : Weight ** Elem (k, v) xs)
joinAllFrom acc [] el = Left (_ ** el)
joinAllFrom acc ((i, w) :: xs) el = case joinAllFrom (insertJoin i w acc) xs el of
  Right (v ** later) => Right (v ** There later)
  Left (v ** joined) => case insertJoinFrom i w acc joined of
    Left Refl => Right (w ** Here)
    Right before => Left before

-- An entry settled is the entry's parameter.
0 settledFrom : (m : List (Nat, Weight)) -> Elem (i, w) (map Template.settledEntry m) -> (v : Weight ** Elem (i, v) m)
settledFrom [] el = absurd el
settledFrom ((j, u) :: rest) Here = (u ** Here)
settledFrom (_ :: rest) (There el) = case settledFrom rest el of
  (v ** later) => (v ** There later)

-- A parameter a template's weights list, it names.
0 weightsNamed : (t : Template) -> Elem (i, w) (weights t) -> Elem i (namedIn t)
weightsNamed t el = case settledFrom (joinAll [] (occurrences 0 t)) el of
  (v ** joined) => case joinAllFrom [] (occurrences 0 t) joined of
    Left (_ ** none) => absurd none
    Right (u ** occurs) => occursNamed 0 t occurs

-- k heads above a head name what its arguments name.
0 raisedNamed : (k : Nat) -> (ts : List Template) -> Elem i (namedIn (raise k (Head Nothing ts))) -> Elem i (namedAll ts)
raisedNamed Z ts el = el
raisedNamed (S k) ts el = case splitElem (namedIn (raise k (Head Nothing ts))) el of
  Left here => raisedNamed k ts here
  Right none => absurd none

-- A family applied, read as its landing says, names it or what its
-- arguments name.
0 landedAsNamed : (l : Landing) -> (b : Template.Beta) -> (j, d : Nat) -> (ts : List Template) ->
                  Elem i (namedIn (landedAs l b j d ts).template) -> Either (i = j) (Elem i (namedAll ts))
landedAsNamed Computed b j d ts Here = Left Refl
landedAsNamed Computed b j d ts (There el) = Right el
landedAsNamed (Evaluable _) b j d ts Here = Left Refl
landedAsNamed (Evaluable _) b j d ts (There el) = Right el
landedAsNamed (Closed _) Computes j d ts Here = Left Refl
landedAsNamed (Closed _) Computes j d ts (There el) = Right el
landedAsNamed Open Computes j d ts Here = Left Refl
landedAsNamed Open Computes j d ts (There el) = Right el
landedAsNamed (Closed k) Inert j d ts el = Right (raisedNamed k ts el)
landedAsNamed Open Inert j d ts Here = Left Refl
landedAsNamed Open Inert j d ts (There el) = Right el

-- What a family applied, read as its landing says, lands closed is the
-- family.
0 landedAsLanded : (l : Landing) -> (b : Template.Beta) -> (j, d : Nat) -> (ts : List Template) ->
                   Elem i (landedAs l b j d ts).landed -> i = j
landedAsLanded (Closed k) Inert j d ts Here = Refl
landedAsLanded (Closed k) Inert j d ts (There el) = absurd el
landedAsLanded (Closed _) Computes _ _ _ el = absurd el
landedAsLanded Open Inert _ _ _ el = absurd el
landedAsLanded Open Computes _ _ _ el = absurd el
landedAsLanded Computed _ _ _ _ el = absurd el
landedAsLanded (Evaluable _) _ _ _ _ el = absurd el

mutual
  -- A template read at a node names nothing it did not.
  0 landedNamed : (c : Nat -> Landing) -> (t : Template) -> Elem i (namedIn (readLanded c t).template) -> Elem i (namedIn t)
  landedNamed c (Applied j d ts) el =
    case landedAsNamed (c j) (argumentsBeta c (allWithClosed c ts)) j d (allWithClosed c ts) el of
      Left Refl => Here
      Right later => There (allLandedNamed c ts later)
  landedNamed c (Computing j d ts) Here = Here
  landedNamed c (Computing j d ts) (There el) = There (allLandedNamed c ts el)
  landedNamed c (Head a ts) el = allLandedNamed c ts el
  landedNamed c (Opaque a ts) el = allLandedNamed c ts el
  landedNamed c (Choice s ts) el = case splitElem (namedIn (readLanded c s).template) el of
    Left here => inFront (landedNamed c s here)
    Right later => behind (namedIn s) (allLandedNamed c ts later)
  landedNamed c (Field k r) el = landedNamed c r el
  landedNamed c (Var j d) el = el
  landedNamed c (Leaf h) el = el
  landedNamed c (Token k) el = el
  landedNamed c (Member k) el = el
  landedNamed c (Formal j k) el = el

  0 allLandedNamed : (c : Nat -> Landing) -> (ts : List Template) -> Elem i (namedAll (allWithClosed c ts)) -> Elem i (namedAll ts)
  allLandedNamed c [] el = el
  allLandedNamed c (t :: ts) el = case splitElem (namedIn (readLanded c t).template) el of
    Left here => inFront (landedNamed c t here)
    Right later => behind (namedIn t) (allLandedNamed c ts later)

mutual
  -- A family a template's reading at a node lands closed, the template
  -- names.
  0 landedFamiliesNamed : (c : Nat -> Landing) -> (t : Template) -> Elem i (readLanded c t).landed -> Elem i (namedIn t)
  landedFamiliesNamed c (Applied j d ts) el =
    case splitElem (landedAs (c j) (argumentsBeta c (allWithClosed c ts)) j d (allWithClosed c ts)).landed el of
      Left here => case landedAsLanded (c j) (argumentsBeta c (allWithClosed c ts)) j d (allWithClosed c ts) here of
        Refl => Here
      Right later => There (allFamiliesNamed c ts later)
  landedFamiliesNamed c (Computing j d ts) el = There (allFamiliesNamed c ts el)
  landedFamiliesNamed c (Head a ts) el = allFamiliesNamed c ts el
  landedFamiliesNamed c (Opaque a ts) el = allFamiliesNamed c ts el
  landedFamiliesNamed c (Choice s ts) el = case splitElem (readLanded c s).landed el of
    Left here => inFront (landedFamiliesNamed c s here)
    Right later => behind (namedIn s) (allFamiliesNamed c ts later)
  landedFamiliesNamed c (Field k r) el = landedFamiliesNamed c r el
  landedFamiliesNamed c (Var _ _) el = absurd el
  landedFamiliesNamed c (Leaf _) el = absurd el
  landedFamiliesNamed c (Token _) el = absurd el
  landedFamiliesNamed c (Member _) el = absurd el
  landedFamiliesNamed c (Formal _ _) el = absurd el

  0 allFamiliesNamed : (c : Nat -> Landing) -> (ts : List Template) -> Elem i (readAllLanded c ts).allLanded -> Elem i (namedAll ts)
  allFamiliesNamed c [] el = absurd el
  allFamiliesNamed c (t :: ts) el = case splitElem (readLanded c t).landed el of
    Left here => inFront (landedFamiliesNamed c t here)
    Right later => behind (namedIn t) (allFamiliesNamed c ts later)

-- Two booleans whose conjunction holds.
0 bothHold : (a, b : Bool) -> (a && b) = True -> (a = True, b = True)
bothHold True True _ = (Refl, Refl)
bothHold True False eq = absurd eq
bothHold False _ eq = absurd eq

mutual
  ||| What an argument's closed landing gives `Proof.Bound.Lands`: a
  ||| self-bounded template (`landingOf`'s `Closed`) read at a node is
  ||| unmarked and as high as it was. Its leaves hold no applied family; a
  ||| choice's scrutinee may, which the reading reads, but neither
  ||| unmarkedness nor height reads a scrutinee.
  export
  0 closedSelfBounded : (c : Nat -> Landing) -> (t : Template) -> selfBounded t = True ->
                        (Unmarked (withClosedFamilies c t), height (withClosedFamilies c t) = height t)
  closedSelfBounded c (Head a ts) sb = case allClosedSelfBounded c ts sb of
    (um, high) => (UnmarkedHead um, cong S high)
  closedSelfBounded c (Opaque a ts) sb = case allClosedSelfBounded c ts sb of
    (um, high) => (UnmarkedOpaque um, cong S high)
  closedSelfBounded c (Choice x ts) sb = case allClosedSelfBounded c ts sb of
    (um, high) => (UnmarkedChoice um, high)
  closedSelfBounded c (Leaf h) _ = (UnmarkedLeaf, Refl)
  closedSelfBounded c (Token k) _ = (UnmarkedToken, Refl)
  closedSelfBounded c (Formal j k) _ = (UnmarkedFormal, Refl)
  closedSelfBounded c (Var _ _) sb = absurd sb
  closedSelfBounded c (Applied _ _ _) sb = absurd sb
  closedSelfBounded c (Computing _ _ _) sb = absurd sb
  closedSelfBounded c (Field _ _) sb = absurd sb
  closedSelfBounded c (Member _) sb = absurd sb

  export
  0 allClosedSelfBounded : (c : Nat -> Landing) -> (ts : List Template) -> allSelfBounded ts = True ->
                           (AllUnmarked (allWithClosed c ts), tallest (allWithClosed c ts) = tallest ts)
  allClosedSelfBounded c [] _ = ([], Refl)
  allClosedSelfBounded c (t :: ts) sb = case bothHold (selfBounded t) (allSelfBounded ts) sb of
    (here, rest) => case (closedSelfBounded c t here, allClosedSelfBounded c ts rest) of
      ((um, high), (ums, highs)) => (um :: ums, cong2 maximum high highs)

------------------------------------------------------------------------------
-- Numbering, and the sites
------------------------------------------------------------------------------

-- The parameters a writing's template names, each once.
namedOf : Written -> List Nat
namedOf x = (unseen [] (namedIn x.template)).fst

-- Every parameter a writing's template names is among them.
0 namedCovered : (x : Written) -> Elem i (namedIn x.template) -> Elem i (namedOf x)
namedCovered x el = case (unseen [] (namedIn x.template)).snd el of
  Left none => absurd none
  Right kept => kept

-- The places a writing meets positions at: where it lands, then where its
-- writer reads each parameter its template names.
slotsOf : Written -> List Spot
slotsOf x = x.target :: map x.reads (namedOf x)

-- The places some writings meet positions at, in order.
allSlots : List Written -> List Spot
allSlots [] = []
allSlots (x :: xs) = slotsOf x ++ allSlots xs

-- What a message reads of each position a writer reads some parameters
-- at, in order.
readsAt : (reads : Nat -> Spot) -> ((i : Nat) -> SpotRead (reads i)) -> (is : List Nat) -> All SpotRead (map reads is)
readsAt reads readsRead [] = []
readsAt reads readsRead (i :: is) = readsRead i :: readsAt reads readsRead is

-- What a message reads of each position a writing meets, as the writing
-- read it, at its places (`slotsOf`).
slotsRead : (x : Written) -> All SpotRead (slotsOf x)
slotsRead x = x.targetRead :: readsAt x.reads x.readsRead (namedOf x)

-- What is read of one list of places, then of another.
readsThen : {0 xs, ys : List Spot} -> All SpotRead xs -> All SpotRead ys -> All SpotRead (xs ++ ys)
readsThen [] later = later
readsThen (r :: rs) later = r :: readsThen rs later

-- What a message reads of each position some writings meet, at their
-- places, in order (`allSlots`).
allSlotsRead : (xs : List Written) -> All SpotRead (allSlots xs)
allSlotsRead [] = []
allSlotsRead (x :: xs) = readsThen (slotsRead x) (allSlotsRead xs)

-- A position met with what a message reads of it, as a position.
placedSpot : (spot : Spot ** SpotRead spot) -> Spot
placedSpot (spot ** _) = spot

-- What a message reads of each of some positions met with it.
spotsRead : (ps : List (spot : Spot ** SpotRead spot)) -> All SpotRead (map Graph.placedSpot ps)
spotsRead [] = []
spotsRead ((_ ** r) :: ps) = r :: spotsRead ps

-- What is read at each place, numbered as the places are (`Vect.fromList`).
readAtEach : {0 xs : List Spot} -> All SpotRead xs -> SpotsRead (Vect.fromList xs)
readAtEach [] = NothingPlaced
readAtEach (r :: rs) = PlacedThen r (readAtEach rs)

-- The numbering at place `place` of `n`, with `rest` still to meet: where
-- each position met so far was first met, and those first meetings in
-- order, each with the position it numbers, so that what a number stands
-- for is read off the meeting rather than looked up again. A position is
-- numbered by the place it is first met at, so meeting it again finds
-- that number, and no number is looked for that was not given.
record Meeting (n : Nat) (rest : List Spot) where
  constructor MkMeeting
  place : Nat
  0 left : place + length rest = n
  seen : SortedMap Spot (PlacedNumber n)
  firsts : SnocList (Fin n, Spot)

-- Position x, met at the next place: the number it was first met at, or,
-- met for the first time, this place's, each with the place it counts to.
-- The place is a counter carried with its bound (`left`), and
-- `natToFinLT` makes it a number at no cost: base's identity pass makes it
-- the identity on the stock host, and idris-mlir writes it as a numeral.
meet : {0 n : Nat} -> {0 rest : List Spot} -> (x : Spot) -> Meeting n (x :: rest) -> (PlacedNumber n, Meeting n rest)
meet x (MkMeeting j left seen firsts) =
  let 0 next = trans (plusSuccRightSucc j (length rest)) left in
  case lookup x seen of
    Just f => (f, MkMeeting (S j) next seen firsts)
    -- Essential: a position's first meeting is the one that numbers it.
    Nothing => let f = MkPlacedNumber (natToFinLT j {prf = runBelow j left}) j (finToNatLT j {prf = runBelow j left}) in
               (f, MkMeeting (S j) next (insert x f seen) (firsts :< (f.number, x)))

-- Positions met at the next places, in order.
meetAll : {0 n : Nat} -> {0 rest : List Spot} -> (xs : List Spot) -> Meeting n (xs ++ rest) -> (List (Fin n), Meeting n rest)
meetAll [] m = ([], m)
meetAll (x :: xs) m = let (f, m') = meet x m
                          (fs, m'') = meetAll xs m' in
                      (f.number :: fs, m'')

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
  (Element ((i, p.number) :: ws) (listedOn listed), m'')

-- A writing with its positions numbered, before anything that lands is
-- read: the position it lands at, with the place it counts to, and where
-- its writer reads each parameter its template names, every one of them
-- listed.
record Numbered (n : Nat) where
  constructor MkNumbered
  written : Written
  lands : PlacedNumber n
  writers : List (Nat, Fin n)
  0 named : {i : Nat} -> Elem i (namedIn written.template) -> (p : Fin n ** Elem (i, p) writers)

-- A writing numbered at its places: where it lands, then where its writer
-- reads each parameter its template names.
numberedMet : {0 n : Nat} -> {0 rest : List Spot} -> (x : Written) -> Meeting n (slotsOf x ++ rest) -> (Numbered n, Meeting n rest)
numberedMet x m =
  let (t, m') = meet x.target m
      (Element ws listed, m'') = meetEach (namedOf x) x.reads m' in
  (MkNumbered x t ws (\el => listed (namedCovered x el)), m'')

-- The position a numbered writing lands at.
(.target) : {0 n : Nat} -> Numbered n -> Fin n
(.target) x = x.lands.number

-- Writings numbered, in order, each at its places.
numberedAll : {0 n : Nat} -> {0 rest : List Spot} -> (xs : List Written) -> Meeting n (allSlots xs ++ rest) ->
              (List (Numbered n), Meeting n rest)
numberedAll [] m = ([], m)
numberedAll (x :: xs) m =
  let (here, m') = numberedMet x (replace {p = Meeting n} (sym (appendAssociative (slotsOf x) (allSlots xs) rest)) m)
      (later, m'') = numberedAll xs m' in
  (here :: later, m'')

-- What a numbered writing lands as, at its position.
landedPair : Numbered n -> LandingAt n
landedPair x = MkLandingAt x.lands (landedBy x.written.wrote)

||| A site of the model with what made it, whose maker's evidence holds of
||| the site's template (`DrawnBy`).
public export
SiteDrawn : (Bound.Site n, Wrote) -> Type
SiteDrawn x = DrawnBy (snd x) (fst x).template

-- What a site read keeps of how it was made: what made it holds of its
-- template, its writers list every parameter its template weighs with an
-- arc, how it was read off what its writer wrote and the table, and its
-- template bounded by what lands at its target.
0 SiteMet : {n : Nat} -> LandingTable n -> (Bound.Site n, Wrote) -> Type
SiteMet {n} t x = (SiteDrawn x, WritersListed {n} (fst x), SiteLanding t (fst x), TargetBounded t (fst x))

-- A numbered writing read where its writer is, as a site of the model: its
-- template read where the table, held as a tree, says each of its writer's
-- parameters lands (`readLanding`), its roots read at the same landing
-- (`rootsAt`); its writers every parameter its template names, so every
-- one its reading weighs or lands closed; and, its own landing bounded by
-- what lands at its target, its template bounded there too.
siteRead : {n : Nat} -> Flow -> SortedMap Address (List Nat) -> {0 t : LandingTable n} -> (held : Indexed t) -> (x : Numbered n) ->
           (0 _ : BoundedBy (landedBy x.written.wrote) (Vect.index x.target t)) -> Subset (Bound.Site n, Wrote) (SiteMet t)
siteRead fl families held x bounded =
  -- Local definitions, never let bindings: the site's evidence states the
  -- landing and the roots themselves, and a let-bound name does not unfold
  -- in a type, where a definition does.
  let c : Nat -> Landing
      c = readLanding held x.writers
      rts : Template -> List Address
      rts = rootsAt fl families c x.written.writer in
  Element (Bound.MkSite x.target (withClosedFamilies c x.written.template) x.writers rts, x.written.wrote)
          (drawnRead c x.written.draws,
           \i, w, inW, lab, drawn => x.named (landedNamed c x.written.template (weightsNamed (withClosedFamilies c x.written.template) inW)),
           MkSiteLanding c x.written.template Refl
                         (\i, el => x.named (landedFamiliesNamed c x.written.template el))
                         (rootsApplied fl families c x.written.writer)
                         (rootsRecorded fl families c x.written.writer)
                         (landingReads held x.writers),
           \k, atTarget => case bounded k atTarget of
             (k' ** (closed, le)) => case x.written.landsAs k' closed of
               (sb, high) => case closedSelfBounded c x.written.template sb of
                 (um, kept) => (um, replace {p = \h => LTE h k} (sym (trans kept high)) le))

-- Numbered writings read as sites, in order, each bounded by the table at
-- its target.
sitesRead : {n : Nat} -> Flow -> SortedMap Address (List Nat) -> {0 t : LandingTable n} -> (held : Indexed t) -> (xs : List (Numbered n)) ->
            (0 _ : {x : Numbered n} -> Elem x xs -> BoundedBy (landedBy x.written.wrote) (Vect.index x.target t)) ->
            Subset (List (Bound.Site n, Wrote)) (All (SiteMet t))
sitesRead fl families held [] _ = Element [] []
sitesRead fl families held (x :: xs) bounds =
  let (Element here made) = siteRead fl families held x (bounds Here)
      (Element later madeLater) = sitesRead fl families held xs (\el => bounds (There el)) in
  Element (here :: later) (made :: madeLater)

0 allFirst : All p (x :: xs) -> p x
allFirst (px :: _) = px

0 allRest : All p (x :: xs) -> All p xs
allRest (_ :: pxs) = pxs

-- The sites that land at uncapped positions, with the evidence of each and
-- of what made each, and those that land at capped ones: a capped
-- position's cap is its bound, so no site into it is drawn.
uncappedDrawn : (caps : Vect n (Maybe Nat)) -> (ss : List (Bound.Site n, Wrote)) -> (0 _ : All (SiteMet t) ss) ->
                (Subset (List (Bound.Site n, Wrote))
                        (\ks => (All (\x => Vect.index (fst x).target caps = Nothing) ks, All (SiteMet t) ks)),
                 List (Bound.Site n, Wrote))
uncappedDrawn caps [] _ = (Element [] ([], []), [])
uncappedDrawn caps (x :: xs) made with (Vect.index (fst x).target caps) proof here
  _ | Nothing = let (Element kept evidence, capped) = uncappedDrawn caps xs (allRest made) in
                (Element (x :: kept) (here :: fst evidence, allFirst made :: snd evidence), capped)
  _ | Just _ = let (kept, capped) = uncappedDrawn caps xs (allRest made) in (kept, x :: capped)

-- A site of the model is one of the kept sites, whose writers list every
-- parameter its template weighs with an arc.
0 listedAmong : {ks : List (Bound.Site n, Wrote)} -> All (SiteMet t) ks -> Elem s (map Builtin.fst ks) -> WritersListed s
listedAmong {ks = []} [] el = absurd el
listedAmong {ks = (_, _) :: _} (made :: _) Here = fst (snd made)
listedAmong {ks = _ :: _} (_ :: made) (There el) = listedAmong made el

-- A site of the model is one of the kept sites, read as its writing was.
0 landedAmong : {ks : List (Bound.Site n, Wrote)} -> All (SiteMet t) ks -> Elem s (map Builtin.fst ks) -> SiteLanding t s
landedAmong {ks = []} [] el = absurd el
landedAmong {ks = (_, _) :: _} (made :: _) Here = fst (snd (snd made))
landedAmong {ks = _ :: _} (_ :: made) (There el) = landedAmong made el

-- A site of the model is one of the kept sites, bounded by what lands at
-- its target.
0 boundedAmong : {ks : List (Bound.Site n, Wrote)} -> All (SiteMet t) ks -> Elem s (map Builtin.fst ks) -> TargetBounded t s
boundedAmong {ks = []} [] el = absurd el
boundedAmong {ks = (_, _) :: _} (made :: _) Here = snd (snd (snd made))
boundedAmong {ks = _ :: _} (_ :: made) (There el) = boundedAmong made el

------------------------------------------------------------------------------
-- Positions, caps and the numbering
------------------------------------------------------------------------------

-- Things by the definition they are of.
byDefinition : (a -> Address) -> List a -> SortedMap Address (List a)
byDefinition key = foldr (\x => insertWith (++) (key x) [x]) empty

-- Each position a walked site places an argument at that is a parameter
-- of a callee the walk entered, once, with the callee's definition, its
-- parameter there, and the definition its node is read at: the positions
-- a cap can be asked of. The application's positions are no definition's,
-- and a field's, a choice's and a held one no parameter's, so none of them
-- is capped.
enteredTargets : List (Node, List (Sites.Site, Reached Defined)) -> SortedMap Spot (Address, Nat, Defined)
enteredTargets = eachPlaced entering empty
  where
    entering : SortedMap Spot (Address, Nat, Defined) -> Node -> Sites.Site -> Callee Defined -> Placed ->
               SortedMap Spot (Address, Nat, Defined)
    entering acc _ _ callee@(Entering v d) pl = insert (landsAt callee pl.parameter) (v.definition, pl.parameter, d) acc
    entering acc _ _ Applying _ = acc
    entering acc _ _ (Making _ _) _ = acc
    entering acc _ _ (Filling _ _) _ = acc

-- Each of those positions that is capped, with its cap. A cap is asked
-- once per definition and parameter, since a definition's nodes share its
-- type.
capsOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         SortedMap Spot (Address, Nat, Defined) -> Front (SortedMap Spot Nat)
capsOf targets = snd <$> foldlM ask (empty, empty) (SortedMap.toList targets)
  where
    ask : (SortedMap (Address, Nat) (Maybe Nat), SortedMap Spot Nat) -> (Spot, Address, Nat, Defined) ->
          Front (SortedMap (Address, Nat) (Maybe Nat), SortedMap Spot Nat)
    ask (memo, capped) (p, a, j, d) = do
      cap <- maybe (capOf d j) pure (lookup (a, j) memo)
      pure (insert (a, j) cap memo, maybe capped (\k => insert p k capped) cap)

-- Each arc as drawn, with what made it, in the arcs' order.
drawnVect : (arcs : List (Drawn n, Wrote)) -> Vect (length (map Describes.arcOf arcs)) (Drawn n, Wrote)
drawnVect [] = []
drawnVect (x :: arcs) = x :: drawnVect arcs

-- The arc at an index, as drawn, is one of the arcs drawn.
0 drawnAmong : (arcs : List (Drawn n, Wrote)) -> (a : Fin (length (map Describes.arcOf arcs))) ->
               Elem (Vect.index a (drawnVect arcs)) arcs
drawnAmong [] FZ impossible
drawnAmong [] (FS _) impossible
drawnAmong (x :: arcs) FZ = Here
drawnAmong (x :: arcs) (FS a) = There (drawnAmong arcs a)

-- The arc at an index, as drawn, is the arc there.
0 drawnIndexed : (arcs : List (Drawn n, Wrote)) -> (a : Fin (length (map Describes.arcOf arcs))) ->
                 arcOf (Vect.index a (drawnVect arcs)) = index' (map Describes.arcOf arcs) a
drawnIndexed [] FZ impossible
drawnIndexed [] (FS _) impossible
drawnIndexed (x :: arcs) FZ = Refl
drawnIndexed (x :: arcs) (FS a) = drawnIndexed arcs a

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
-- definition the definitions' walk entered it at and the sites it writes
-- there. A node with no family headed is read as the definitions' walk
-- read it. The flow's sets hold every type constructor that heads a
-- family in the split, since a site the split reads at a node is the
-- definitions' walk's with each head in place of the marker it stands
-- for, whose flow equation already carries that head: so these are every
-- node the walk can meet, which the walk checks (`Unheaded`).
readings : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           Flow -> Entered -> Front (SortedMap Node (Defined, List Sites.Site))
readings fl r = foldlM family plain (SortedMap.toList r.sites)
  where
    plain : SortedMap Node (Defined, List Sites.Site)
    plain = SortedMap.fromList (map (\(a, entry) => (MkNode a [], entry)) (SortedMap.toList r.sites))

    headed : Address -> Defined -> SortedMap Node (Defined, List Sites.Site) -> List (Nat, Address) ->
             Front (SortedMap Node (Defined, List Sites.Site))
    headed a d m hs = (\ss => insert (MkNode a hs) (d, ss) m) <$> sitesOf a d hs

    -- Each way of heading a definition's families, read at its
    -- definition: a definition the checks refused was entered with none.
    family : SortedMap Node (Defined, List Sites.Site) -> (Address, Defined, List Sites.Site) ->
             Front (SortedMap Node (Defined, List Sites.Site))
    family m (a, d, _) = foldlM (headed a d) m (familyHeads fl a (fromMaybe [] (lookup a r.families)))

-- A visit's reading: the definition its node is read at, and the sites it
-- writes there.
visitReading : SortedMap Address (List Nat) -> SortedMap Node (Defined, List Sites.Site) -> Visit ->
               Either Stray (Defined, List Sites.Site)
visitReading families reads x = case SortedMap.lookup (readAt families (visitNode x)) reads of
  Just found => Right found
  Nothing => Left (Unheaded x)

-- What a site reaches, each callee it enters given the definition its
-- node is read at, read where the walk reads the callee's sites: so a
-- reader of an entered callee's parameters has its definition at hand,
-- and looks nothing up by address.
enteredBy : SortedMap Address (List Nat) -> SortedMap Node (Defined, List Sites.Site) -> Reached () ->
            Either Stray (Reached Defined)
enteredBy families reads (MkReached (Entering c ()) placed via) =
  (\(d, _) => MkReached (Entering c d) placed via) <$> visitReading families reads c
enteredBy families reads (MkReached Applying placed via) = Right (MkReached Applying placed via)
enteredBy families reads (MkReached (Making k named) placed via) = Right (MkReached (Making k named) placed via)
enteredBy families reads (MkReached (Filling con def) placed via) = Right (MkReached (Filling con def) placed via)
enteredBy families reads (Kept b items) = Right (Kept b items)

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
||| evaluated. What lands at a position is read off the walk's own
||| numbering (`landingAt`), what the writings as written land as.
evaluated : {auto c : Ref Ctxt Defs} -> (landingAt : Spot -> Landing) ->
            List (Node, List (Sites.Site, Reached Defined)) -> Front (List (Node, List (Sites.Site, Reached Defined)))
evaluated landingAt = traverse (\(w, edges) => (w,) <$> traverse (\(st, e) => (st,) <$> reachedAt w st e) edges)
  where
    -- One closed reading of an argument at a choice of values: nothing
    -- when the reading still holds a marker or applies a family.
    readingAt : Argument -> ClosedTerm -> List (Nat, ClosedTerm) -> Front (Maybe Argument)
    readingAt x tm given = do
      read <- readArgument x.stands x.position x.kind x.memberOf !(normaliseClosed (givenFamilies given tm)) x.shown
      pure (if selfBounded read.template then Just read else Nothing)

    evaluate : Node -> Sites.Site -> Argument -> Front (List Argument)
    evaluate w st x = case (x.term, applyingIn x.template) of
      (Just tm, fs@(_ :: _)) => case traverse (\i => (i,) <$> evaluable (landingAt (spotAt w st.params i))) (nub fs) of
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

    reachedAt : Node -> Sites.Site -> Reached Defined -> Front (Reached Defined)
    reachedAt w st (MkReached callee placed via) = do
      placed' <- traverse (\pl => do
                             holds <- traverse (traverse (heldAt w st)) pl.argument.holds
                             reads <- evaluate w st pl.argument
                             pure (map (\x => the Placed ({ argument := { holds := holds } x } pl)) reads))
                          placed
      pure (MkReached callee (concat placed') via)
    reachedAt w st (Kept b items) = Kept b <$> traverse (heldAt w st) items

||| The growth graph of the program from main, as the reading holds it:
||| every static position its reachable nodes have, numbered, with the arcs
||| between them, the caps, K, and the sizes the worklist's universe needs.
||| It throws only an internal error, a broken invariant of its own
||| construction or of a contract it reads, at main's definition.
export
build : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> (main : Defined) -> Front Built
build main = do
  -- main is where an internal error of the graph is located, and its node,
  -- with no heads, is where the walk over nodes starts.
  let fc = location main.def
  let root = addressOf main.placement
  entered <- definitions main
  -- Lists are joined by bind, which is linear: base's `concat` and
  -- `concatMap` on a list fold `++` from the left, so every join copies
  -- what came before, the square of the length in all.
  let fl = flow entered.fields (values entered.sites >>= snd)
  reads <- readings fl entered
  let readSites = map snd (values reads)
  -- The most values one list of held values holds, and every stuck path a
  -- chain of held dispatches can hold, read off every reading's sites
  -- once; and the pair that holds such lists.
  let counted = countedIn readSites
  let count = heldCount counted
  pairing <- pairingOf
  -- Every visit's node has its reading (`readings`): one without would
  -- lose the arcs its sites write. Each callee a site enters is given the
  -- definition its node is read at there.
  let out : Visit -> Either Stray (List (Sites.Site, Reached Defined))
      out x = visitReading entered.families reads x >>= \(_, ss) =>
                traverse (\(s, r) => (s,) <$> enteredBy entered.families reads r) [(s, r) | s <- ss, r <- reaches fl x s]
  let Right found = nodesFromMain (SortedSet.toList counted.paths) (headBound entered.fields readSites) out
                                  (MkVisit root []) main.def
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
  let writtenBy : List (Node, List (Sites.Site, Reached Defined)) -> List Written -> List Written
      writtenBy ws args =
        let held = heldWritings count pairing (heldChoices ws) ws in
        fixed ++ heldPackings count pairing (pairedPlaces held) ++ held ++ args
  -- A capped position takes no arc: its cap, which the graph holds and a
  -- feasible potential meets, stands for every value of its height, so no
  -- listed site targets it. A cap is asked of the positions the arguments
  -- name; a position only a data type's arguments give is a type
  -- argument, which no cap applies to.
  let args0 = writings walked0
  capped <- capsOf (enteredTargets walked0)
  -- What lands at each position is joined from every writing there, and a
  -- capped position holds every value of its cap's height: the writings
  -- as written are numbered at their places, and what lands is read off
  -- that numbering, by the spot a writer reads. Each value whose
  -- definition a type below states is a local definition, never a let
  -- binding: a let-bound name does not unfold in a type, where a
  -- definition does.
  let written0 = writtenBy walked0 args0
  let slots0 : List Spot
      slots0 = allSlots written0
  let (numbered0, met0) = numberedAll {rest = []} written0
                                      (replace {p = Meeting (length slots0)} (sym (appendNilRightNeutral slots0))
                                               (MkMeeting 0 Refl empty [<]))
  let table0 = tableOf met0.seen (map (\p => lookup p capped) (Vect.fromList slots0)) nodes leads walked0 (map landedPair numbered0)
  let held0 = indexed table0
  let landing0 = \spot => maybe Open (\p => fromMaybe Open (entryAt p.number held0).fst) (lookup spot met0.seen)
  -- What a family given only closed values computes, evaluated at each.
  walked <- evaluated landing0 walked0
  let written = writtenBy walked (writings walked)
  -- The places positions are met at: where each writing lands and where
  -- its writer reads each parameter its template names, then every
  -- represented argument of a reachable data type. Every place an argument
  -- lands is a writing's. A position is numbered at the place it is first
  -- met, before anything that lands is read, so what lands where is a
  -- table by number, and no site looks a position up; what a message
  -- reads of each position is numbered with it, as the writing or the
  -- walk that met it there read it, so no message looks up a definition
  -- a position names.
  let dataSpots : List Spot
      dataSpots = map Graph.placedSpot entered.datas
  let slots : List Spot
      slots = allSlots written ++ dataSpots
  let position : Vect (length slots) Spot
      position = Vect.fromList slots
  let positionRead : SpotsRead position
      positionRead = readAtEach (readsThen (allSlotsRead written) (spotsRead entered.datas))
  let start : Meeting (length slots) (allSlots written ++ dataSpots)
      start = MkMeeting 0 Refl empty [<]
  let (numbered, met) = numberedAll {rest = dataSpots} written start
  let (_, done) = meetAll {rest = []} dataSpots
                          (replace {p = Meeting (length slots)} (sym (appendNilRightNeutral dataSpots)) met)
  let firstMet = done.firsts <>> []
  let firsts = map fst firstMet
  let caps = map (\p => lookup p capped) position
  -- What lands at each position, and each writing read where its writer
  -- is over it.
  let landed : List (LandingAt (length slots))
      landed = map landedPair numbered
  let table : LandingTable (length slots)
      table = tableOf done.seen caps nodes leads walked landed
  let (Element sites sitesDrawn) = sitesRead fl entered.families (indexed table) numbered
                                             (\el => tableBounds done.seen caps nodes leads walked landed (elemMap landedPair el))
  -- Each definition's positions, each field's and each choice's, read off
  -- the first meetings themselves, each with the position it numbers.
  let byDefinitionAt = the (SortedMap Address (List (Fin (length slots))))
                           (foldr (\(f, spot) => case spot of
                                                    OfParameter (OfNode node) _ => insertWith (++) node.definition [f]
                                                    _ => id)
                                  empty firstMet)
  let byFieldAt = the (SortedMap (Address, Nat) (List (Fin (length slots))))
                      (foldr (\(f, spot) => case spot of
                                               OfField j k => insertWith (++) (j, k) [f]
                                               _ => id)
                             empty firstMet)
  let byChoiceAt = the (SortedMap ChoiceHead (List (Fin (length slots))))
                       (foldr (\(f, spot) => case spot of
                                                OfChoice k => insertWith (++) k [f]
                                                _ => id)
                              empty firstMet)
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
  let arcs : List (Drawn (length slots), Wrote)
      arcs = drawn positionsOf fieldPositionsOf choicePositionsOf kept
  -- A field's template is written into the values of every field read,
  -- and so into requests, as an argument's is.
  pure (MkBuilt (graphOf positionsOf fieldPositionsOf choicePositionsOf beyond caps kept) position positionRead firsts
                (drawnVect arcs) (drawnIndexed arcs)
                (\a => case drawnFromSite {ps = positionsOf} {fps = fieldPositionsOf} {cps = choicePositionsOf} {ss = kept}
                                          (drawnAmong arcs a) of
                         ((st, x) ** (el, (fromSite, tagged))) =>
                           replace {p = \w => DrawnBy w (fst (Vect.index a (drawnVect arcs))).drawnFrom} (sym tagged)
                                   (replace {p = DrawnBy x} (sym fromSite) (fst (indexAll el (snd keptEvidence)))))
                (foldl (\m, x => max m (Template.arity (fst x).template)) 0 sites) found.reachers entered.breadth
                (foldl (\m, x => max m (Template.heaviest (fst x).template)) count sites)
                (modelOf positionsOf fieldPositionsOf choicePositionsOf positionOf count beyond caps kept)
                (\pot, fe => describes positionsOf fieldPositionsOf choicePositionsOf positionOf count beyond caps kept
                                       (fst keptEvidence) fe)
                (\a, leading => replace {p = IsFinite} (cong (.label) (drawnIndexed arcs a))
                                   (measuredDrawn {ps = positionsOf} {fps = fieldPositionsOf} {cps = choicePositionsOf} {ss = kept}
                                      (\x => x = ThroughMethod)
                                      (\st, x, el, same => methodMeasured (replace {p = \w => DrawnBy w st.template} same
                                                                                    (fst (indexAll el (snd keptEvidence)))))
                                      (drawnAmong arcs a) leading))
                (\a, k, packs => replace {p = IsFinite} (cong (.label) (drawnIndexed arcs a))
                                    (measuredDrawn {ps = positionsOf} {fps = fieldPositionsOf} {cps = choicePositionsOf} {ss = kept}
                                       (\x => x = PacksHeld k)
                                       (\st, x, el, same => packedMeasured (replace {p = \w => DrawnBy w st.template} same
                                                                                     (fst (indexAll el (snd keptEvidence)))))
                                       (drawnAmong arcs a) packs))
                (\st, el => ownDrawnOf {ps = positionsOf} {fps = fieldPositionsOf} {cps = choicePositionsOf} {positionOf}
                                       {held = count} {beyond} {caps} {ss = kept} el)
                (\st, el => listedAmong (snd keptEvidence) el)
                table
                (\q, k, atQ => tableUncapped done.seen caps nodes leads walked landed q atQ)
                (\st, el => landedAmong (snd keptEvidence) el)
                (\st, el => boundedAmong (snd keptEvidence) el))
