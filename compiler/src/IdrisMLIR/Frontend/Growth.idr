-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The growth check, the phase between what the program reaches and its
||| translation. It decides, on the graph of the program's static positions
||| (`Growth.Graph`), whether every static argument the program can request
||| stays within a bound. Admitted, the check's potential bounds each
||| position, and the translation's worklist descends within those bounds,
||| so it ends by construction. Refused, a static argument grows on every
||| round of a cycle, or passes through a type-level recursion nothing
||| bounds: there is then no bound for the translation to stay within, so
||| the program is not translated, and each cause is reported once, at the
||| user's definition that holds it, or else where the program reaches it.
module IdrisMLIR.Frontend.Growth

import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Frontend.Growth.Check
import IdrisMLIR.Frontend.Growth.Graph
import IdrisMLIR.Frontend.Growth.Heads
import IdrisMLIR.Frontend.Growth.Indexed
import IdrisMLIR.Frontend.Growth.Sites
import IdrisMLIR.Frontend.Growth.Template
import IdrisMLIR.Frontend.Translate.Definitions
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Loc
import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Spec.Core.Rules

import Control.Relation
import Data.DPair
import Data.Fin
import Data.List
import Data.List1
import Data.Maybe
import Data.Nat
import Data.SortedMap
import Data.String
import Data.Vect

%default total

------------------------------------------------------------------------------
-- The bounds
------------------------------------------------------------------------------

||| What the bounds read of each position, held so that a position is read
||| in as many steps as a tree over the positions is deep
||| (`Indexed.indexed`), each tree made once: the spot it was met at, its
||| potential, its cap.
record Tables (b : Built) (pot : Vect b.graph.size Nat) where
  constructor MkTables
  spotsHeld : Indexed b.position
  potentialsHeld : Indexed pot
  capsHeld : Indexed b.graph.caps

tablesOf : (b : Built) -> (pot : Vect b.graph.size Nat) -> Tables b pot
tablesOf b pot = MkTables (indexed b.position) (indexed pot) (indexed b.graph.caps)

||| A position as the bounds read it: the spot it was met at and its bound
||| under the potential (`bound`), each with the evidence that it is the
||| graph's there.
record ReadAt (b : Built) (pot : Vect b.graph.size Nat) (f : Fin b.graph.size) where
  constructor MkReadAt
  spotRead : Spot
  0 isSpot : spotRead = index f b.position
  boundRead : Nat
  0 isBound : boundRead = bound b.graph pot f

readAt : {b : Built} -> Tables b pot -> (f : Fin b.graph.size) -> ReadAt b pot f
readAt ts f =
  let Element spot isSpot = entryAt f ts.spotsHeld
      Element p isPotential = entryAt f ts.potentialsHeld
      Element cap isCap = entryAt f ts.capsHeld in
  MkReadAt spot isSpot (capped b.graph.constant p cap) (cong2 (capped b.graph.constant) isPotential isCap)

||| Each node's position's bound under the potential the check found
||| (`bound`), in one pass over the places positions were first met at,
||| each position once: what the worklist checks an instance of a
||| definition's static arguments against. A member at a use is checked
||| by its link alone, and a field's, a choice's and the held values'
||| positions bound what reads of them write, never a request.
boundsOf : (b : Built) -> Tables b pot -> SortedMap Position Nat
boundsOf b ts = foldl at empty b.firsts
  where
    at : SortedMap Position Nat -> Fin b.graph.size -> SortedMap Position Nat
    at acc f = let r = readAt ts f in case r.spotRead of
      OfParameter (OfNode node) i => insert (node, i) r.boundRead acc
      OfParameter OfApplication _ => acc
      OfField _ _ => acc
      OfChoice _ => acc
      OfHeld _ => acc

||| The height of parameter i in a list of heights, as the universe pads
||| them (`Proof.Requests.padded`): 0 past the list's end, which keys
||| nothing.
public export
parameterHeight : List Nat -> Nat -> Nat
parameterHeight [] _ = 0
parameterHeight (h :: _) Z = h
parameterHeight (_ :: hs) (S i) = parameterHeight hs i

-- A list of heights with parameter i's raised to at least x.
raiseList : Nat -> Nat -> List Nat -> List Nat
raiseList Z x [] = [x]
raiseList Z x (h :: hs) = maximum h x :: hs
raiseList (S i) x [] = 0 :: raiseList i x []
raiseList (S i) x (h :: hs) = h :: raiseList i x hs

0 raisedHere : (i, x : Nat) -> (hs : List Nat) -> LTE x (parameterHeight (raiseList i x hs) i)
raisedHere Z x [] = lteRefl
raisedHere Z x (h :: hs) = maximumRightUpperBound h x
raisedHere (S i) x [] = raisedHere i x []
raisedHere (S i) x (h :: hs) = raisedHere i x hs

0 raisedKeeps : (i, x : Nat) -> (hs : List Nat) -> (j : Nat) -> LTE (parameterHeight hs j) (parameterHeight (raiseList i x hs) j)
raisedKeeps i x [] j = LTEZero
raisedKeeps Z x (h :: hs) Z = maximumLeftUpperBound h x
raisedKeeps Z x (h :: hs) (S j) = lteRefl
raisedKeeps (S i) x (h :: hs) Z = lteRefl
raisedKeeps (S i) x (h :: hs) (S j) = raisedKeeps i x hs j

||| What the universe heads a request at a holder of positions by: a
||| node's definition, or the application at a use.
public export
headOf : Holder -> Head
headOf (OfNode node) = ADefinition node.definition
headOf OfApplication = AnApplication

-- The heights an entry gives, if it is the head's; else what the rest
-- gives.
heightsHere : Decided p -> List Nat -> List Nat -> List Nat
heightsHere (Yes _) hs later = hs
heightsHere (No _) hs later = later

||| The heights a table gives a head by parameter: its entry's, none where
||| it has none.
public export
heightsIn : List (Head, List Nat) -> Head -> List Nat
heightsIn [] g = []
heightsIn ((h, hs) :: rest) g = heightsHere (decideHead g h) hs (heightsIn rest g)

-- An entry raised, if it is the head's; else the rest raised.
raiseHere : Decided p -> Head -> List Nat -> Nat -> Nat -> Lazy (List (Head, List Nat)) -> List (Head, List Nat) ->
            List (Head, List Nat)
raiseHere (Yes _) h hs i x raisedRest rest = (h, raiseList i x hs) :: rest
raiseHere (No _) h hs i x raisedRest rest = (h, hs) :: Force raisedRest

-- A table with a head's parameter i raised to at least x.
raiseAt : Head -> Nat -> Nat -> List (Head, List Nat) -> List (Head, List Nat)
raiseAt g i x [] = [(g, raiseList i x [])]
raiseAt g i x ((h, hs) :: rest) = raiseHere (decideHead g h) h hs i x (raiseAt g i x rest) rest

0 lookView : (d : Decided (g = h)) -> (hs, hs', later, later' : List Nat) ->
             Either (g = h, heightsHere d hs later = hs, heightsHere d hs' later' = hs')
                    (Not (g = h), heightsHere d hs later = later, heightsHere d hs' later' = later')
lookView (Yes same) hs hs' later later' = Left (same, Refl, Refl)
lookView (No other) hs hs' later later' = Right (other, Refl, Refl)

0 raiseView : (d : Decided (g = h)) -> (hs : List Nat) -> (i, x : Nat) -> (r : Lazy (List (Head, List Nat))) ->
              (rest : List (Head, List Nat)) ->
              Either (g = h, raiseHere d h hs i x r rest = (h, raiseList i x hs) :: rest)
                     (Not (g = h), raiseHere d h hs i x r rest = (h, hs) :: Force r)
raiseView (Yes same) hs i x r rest = Left (same, Refl)
raiseView (No other) hs i x r rest = Right (other, Refl)

0 lteToEq : b = c -> LTE a b -> LTE a c
lteToEq Refl le = le

0 lteOfEq : a = b -> LTE b c -> LTE a c
lteOfEq Refl le = le

-- The parameter a table is raised at is at least that high there.
0 heightsRaised : (g : Head) -> (i, x : Nat) -> (table : List (Head, List Nat)) ->
                  LTE x (parameterHeight (heightsIn (raiseAt g i x table) g) i)
heightsRaised g i x [] = case lookView (decideHead g g) (raiseList i x []) (raiseList i x []) [] [] of
  Left (_, found, _) => lteToEq (sym (cong (\l => parameterHeight l i) found)) (raisedHere i x [])
  Right (other, _, _) => void (other Refl)
heightsRaised g i x ((h, hs) :: rest) =
  case raiseView (decideHead g h) hs i x (raiseAt g i x rest) rest of
    Left (same, raised) =>
      case lookView (decideHead g h) (raiseList i x hs) hs (heightsIn rest g) (heightsIn rest g) of
        Left (_, found, _) =>
          lteToEq (sym (trans (cong (\tb => parameterHeight (heightsIn tb g) i) raised) (cong (\l => parameterHeight l i) found)))
                  (raisedHere i x hs)
        Right (other, _, _) => void (other same)
    Right (other, raised) =>
      case lookView (decideHead g h) hs hs (heightsIn (raiseAt g i x rest) g) (heightsIn rest g) of
        Left (same, _, _) => void (other same)
        Right (_, found, _) =>
          lteToEq (sym (trans (cong (\tb => parameterHeight (heightsIn tb g) i) raised) (cong (\l => parameterHeight l i) found)))
                  (heightsRaised g i x rest)

-- Raising a table lowers no head's height anywhere.
0 heightsKeep : (g, k : Head) -> (i, x, j : Nat) -> (table : List (Head, List Nat)) ->
                LTE (parameterHeight (heightsIn table k) j) (parameterHeight (heightsIn (raiseAt g i x table) k) j)
heightsKeep g k i x j [] = LTEZero
heightsKeep g k i x j ((h, hs) :: rest) =
  case raiseView (decideHead g h) hs i x (raiseAt g i x rest) rest of
    Left (_, raised) =>
      case lookView (decideHead k h) hs (raiseList i x hs) (heightsIn rest k) (heightsIn rest k) of
        Left (_, before, after) =>
          lteOfEq (cong (\l => parameterHeight l j) before)
            (lteToEq (sym (trans (cong (\tb => parameterHeight (heightsIn tb k) j) raised) (cong (\l => parameterHeight l j) after)))
                     (raisedKeeps i x hs j))
        Right (_, before, after) =>
          lteOfEq (cong (\l => parameterHeight l j) before)
            (lteToEq (sym (trans (cong (\tb => parameterHeight (heightsIn tb k) j) raised) (cong (\l => parameterHeight l j) after)))
                     lteRefl)
    Right (_, raised) =>
      case lookView (decideHead k h) hs hs (heightsIn rest k) (heightsIn (raiseAt g i x rest) k) of
        Left (_, before, after) =>
          lteOfEq (cong (\l => parameterHeight l j) before)
            (lteToEq (sym (trans (cong (\tb => parameterHeight (heightsIn tb k) j) raised) (cong (\l => parameterHeight l j) after)))
                     lteRefl)
        Right (_, before, after) =>
          lteOfEq (cong (\l => parameterHeight l j) before)
            (lteToEq (sym (trans (cong (\tb => parameterHeight (heightsIn tb k) j) raised) (cong (\l => parameterHeight l j) after)))
                     (heightsKeep g k i x j rest))

||| A position's bound placed within a table of heights: a parameter's
||| position within its head's height at that parameter; any other
||| position, which no request lands at, has nothing to place.
public export
0 PlacedIn : List (Head, List Nat) -> Nat -> Spot -> Type
PlacedIn table h (OfParameter holder i) = LTE h (parameterHeight (heightsIn table (headOf holder)) i)
PlacedIn table h _ = ()

0 keepPlaced : {g : Head} -> {i, x : Nat} -> {table : List (Head, List Nat)} ->
               (spot : Spot) -> PlacedIn table h spot -> PlacedIn (raiseAt g i x table) h spot
keepPlaced (OfParameter holder j) le = transitive le (heightsKeep g (headOf holder) i x j table)
keepPlaced (OfField _ _) u = u
keepPlaced (OfChoice _) u = u
keepPlaced (OfHeld _) u = u

-- A table raised where a position is a parameter's: that position placed,
-- every position placed before kept.
record Raised (table : List (Head, List Nat)) (h : Nat) (spot : Spot) where
  constructor MkRaised
  raised : List (Head, List Nat)
  0 here : PlacedIn raised h spot
  0 kept : (spot' : Spot) -> (h' : Nat) -> PlacedIn table h' spot' -> PlacedIn raised h' spot'

raiseFor : (spot : Spot) -> (h : Nat) -> (table : List (Head, List Nat)) -> Raised table h spot
raiseFor (OfParameter holder i) h table =
  MkRaised (raiseAt (headOf holder) i h table) (heightsRaised (headOf holder) i h table)
           (\spot', h', placed => keepPlaced {g = headOf holder} {i} {x = h} {table} spot' placed)
raiseFor (OfField _ _) h table = MkRaised table () (\_, _, placed => placed)
raiseFor (OfChoice _) h table = MkRaised table () (\_, _, placed => placed)
raiseFor (OfHeld _) h table = MkRaised table () (\_, _, placed => placed)

||| Each head's heights by parameter over some positions: the largest bound
||| of each of its parameters over the positions it holds, a node's in its
||| definition's, the application's in the application's; with the evidence
||| that each of the positions is within its parameter's height there.
record Placing (b : Built) (pot : Vect b.graph.size Nat) (fs : List (Fin b.graph.size)) where
  constructor MkPlacing
  table : List (Head, List Nat)
  0 placed : All (\f => PlacedIn table (bound b.graph pot f) (index f b.position)) fs

0 keptAll : (r : Raised table h spot) -> All (\f => PlacedIn table (bound g pot f) (index f position)) fs ->
            All (\f => PlacedIn r.raised (bound g pot f) (index f position)) fs
keptAll r [] = []
keptAll r (p :: ps) = r.kept _ _ p :: keptAll r ps

-- A position placed as it was read, placed as the graph holds it.
0 placedAsHeld : {b : Built} -> {pot : Vect b.graph.size Nat} -> {f : Fin b.graph.size} -> {h : Nat} -> {spot : Spot} ->
                 (r : Raised table h spot) -> spot = index f b.position -> h = bound b.graph pot f ->
                 PlacedIn r.raised (bound b.graph pot f) (index f b.position)
placedAsHeld r isSpot isBound =
  replace {p = \x => PlacedIn r.raised x (index f b.position)} isBound (replace {p = PlacedIn r.raised h} isSpot r.here)

-- The positions placed one at a time, the last first, each read through
-- the tables.
heightsFrom : (b : Built) -> (pot : Vect b.graph.size Nat) -> Tables b pot -> (fs : List (Fin b.graph.size)) -> Placing b pot fs
heightsFrom b pot ts [] = MkPlacing [] []
heightsFrom b pot ts (f :: fs) =
  let MkPlacing table placed = heightsFrom b pot ts fs
      MkReadAt spot isSpot h isBound = readAt ts f
      r = raiseFor spot h table in
  MkPlacing r.raised (placedAsHeld r isSpot isBound :: keptAll r placed)

||| Each head's heights by parameter, over every position first met.
heightsOf : (b : Built) -> (pot : Vect b.graph.size Nat) -> Tables b pot -> Placing b pot b.firsts
heightsOf b pot ts = heightsFrom b pot ts b.firsts

||| Every position is within its parameter's height in the universe: a
||| request whose argument lands at a parameter's position, and is within
||| that position's bound, is within the height the universe gives the
||| parameter of the request's head.
export
0 positionWithin : (placing : Placing b pot b.firsts) -> Elem f b.firsts -> index f b.position = OfParameter holder i ->
                   LTE (bound b.graph pot f) (parameterHeight (heightsIn placing.table (headOf holder)) i)
positionWithin placing el spotted = replace {p = PlacedIn placing.table (bound b.graph pot f)} spotted (indexAll el placing.placed)

||| The universe the worklist descends in, read from the bounds alone: each
||| head's heights (`heightsOf`), with the graph's arity, heaviest token
||| and breadth, the base of the tower its keys' measures stay within. No
||| size is computed: the worklist decides each link's sizes against these
||| heights (`Proof.Requests.within`).
sizesOf : (b : Built) -> Placing b pot b.firsts -> Bounds
sizesOf b placing = MkBounds (heightsIn placing.table) b.arity b.heaviest b.breadth

------------------------------------------------------------------------------
-- Names and places
------------------------------------------------------------------------------

||| The definition at an address of the graph, and its name as a message
||| prints it. Every address of the graph is a definition's (`addressOf`).
graphDefinition : {auto c : Ref Ctxt Defs} -> FC -> Address -> Front (GlobalDef, String)
graphDefinition fc a = do
  Just def <- core (definitionAt a)
    | Nothing => internal fc "the growth graph names an address no definition has"
  pure (def, nameKey !(fullNames (fullname def)))

||| A definition's i-th parameter, by the name its source gives it
||| (`parameterNames`), or its number past the binders its type shows: a
||| type may show its binders only once normalised.
parameter : {auto c : Ref Ctxt Defs} -> Nat -> GlobalDef -> Front String
parameter j def = maybe ("number " ++ show (S j)) show . getAt j <$> parameterNames def

||| Where a refusal is reported: a definition's location, and the name the
||| message is owned by.
record Place where
  constructor MkPlace
  at : FC
  owner : String

placeOf : GlobalDef -> Place
placeOf def = MkPlace (location def) (show (fullname def))

||| A definition of the program's own source, with where it is; nothing for
||| a library's or a generated one.
userDefinition : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 FC -> Address -> Front (Maybe (Loc, GlobalDef))
userDefinition fc a = do
  (def, _) <- graphDefinition fc a
  loc <- toLoc (location def)
  pure (case loc.origin of
          User => Just (loc, def)
          _ => Nothing)

||| The candidate whose definition comes first in the source, by file and
||| then line, the first on a tie.
earliest : (t, Loc, GlobalDef) -> List (t, Loc, GlobalDef) -> (t, Loc, GlobalDef)
earliest best [] = best
earliest best@(_, m, _) (x@(_, l, _) :: xs) =
  earliest (if place l < place m then x else best) xs
  where
    -- A definition's file and line, a file or line it has none of first.
    place : Loc -> (Maybe String, Maybe Int)
    place l = (locFile l, (.startLine) <$> locSpan l)

||| A dictionary's place, as a message names it: a parameter of what holds
||| it, by the parameter's name and the holder's, or argument i of the
||| application at a use; an implementation's field, by the
||| implementation's name; a choice, by its interface's name, as the
||| polymorphic functions', or as one whose type only an instance shows; or
||| a dictionary a definition's text binds, by the definition's name.
placeText : {auto c : Ref Ctxt Defs} -> FC -> HeldBy -> Front String
placeText fc (ByParameter (OfNode node) i) = do
  (def, name) <- graphDefinition fc node.definition
  (++ " of " ++ name) <$> parameter i def
placeText fc (ByParameter OfApplication i) =
  pure ("argument " ++ show (S i) ++ " of the application of a polymorphic function at its use")
placeText fc (ByField j k) = (\name => "field " ++ show k ++ " of " ++ name) . snd <$> graphDefinition fc j
placeText fc (ByChoice (InterfaceHead j)) =
  (\name => "the implementations of " ++ name ++ " the running program chooses") . snd <$> graphDefinition fc j
placeText fc (ByChoice ArrowHead) = pure "the polymorphic functions the running program chooses"
placeText fc (ByChoice UnshownHead) =
  pure "the members the running program chooses of a choice whose type only an instance shows"
placeText fc (ByBinding node _) = (\name => "a dictionary bound in " ++ name) . snd <$> graphDefinition fc node.definition

||| What holds a position, as a message names it: a node's definition, by
||| its name; the application at a use, which no name is; an
||| implementation's field or a choice, as its place is named; or the
||| values a dictionary's place holds, by that place.
holderText : {auto c : Ref Ctxt Defs} -> FC -> Spot -> Front String
holderText fc (OfParameter (OfNode node) _) = snd <$> graphDefinition fc node.definition
holderText fc (OfParameter OfApplication _) = pure "the application of a polymorphic function at its use"
holderText fc (OfField j k) = placeText fc (ByField j k)
holderText fc (OfChoice k) = placeText fc (ByChoice k)
holderText fc (OfHeld v) = (\place => "the values " ++ place ++ " holds") <$> placeText fc v.heldBy

||| The definition of the program's own source that holds a position, with
||| where it is: nothing for a library's or a generated one, or for the
||| application at a use, or a choice, which no definition is.
userHolder : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             FC -> Spot -> Front (Maybe (Loc, GlobalDef))
userHolder fc (OfParameter (OfNode node) _) = userDefinition fc node.definition
userHolder fc (OfParameter OfApplication _) = pure Nothing
userHolder fc (OfField j _) = userDefinition fc j
userHolder fc (OfChoice _) = pure Nothing
userHolder fc (OfHeld _) = pure Nothing

||| The first user definition among a node's reachers on the walk from
||| main, nearest first; nothing when main is reached with none.
reacher : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          FC -> (reachers : List Node) -> Front (Maybe GlobalDef)
reacher fc [] = pure Nothing
reacher fc (p :: ps) = case !(userDefinition fc p.definition) of
  Just (_, def) => pure (Just def)
  Nothing => reacher fc ps

||| Where a refusal is reported, and which of its candidates is there. Each
||| candidate is what holds one of the cause's positions. Of the user
||| definitions among them, the one first in the source is the place, at the
||| first candidate it is on. With none, the cause is reported where the
||| program reaches it, at the first candidate: at the first user definition
||| among the reachers of the cause's first node, or at main.
located : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          FC -> Name -> Built -> (first : Spot) -> List1 (t, Spot) -> Front (t, Place)
located fc main b first candidates = do
  users <- traverse (\(v, h) => map (\(loc, def) => (v, loc, def)) <$> userHolder fc h)
                    (forget candidates)
  case catMaybes users of
    u :: us => let (v, _, def) = earliest u us in pure (v, placeOf def)
    [] => do
      above <- reacher fc (reachersOf first)
      pure (fst (head candidates), maybe (MkPlace fc (show main)) placeOf above)
  where
    -- The application at a use, a field and a choice are reached through
    -- no node of their own.
    reachersOf : Spot -> List Node
    reachersOf (OfParameter (OfNode node) _) = fromMaybe [] (lookup node b.reachers)
    reachersOf _ = []

------------------------------------------------------------------------------
-- The causes
------------------------------------------------------------------------------

||| An arc's source position as its writer reads it: parameter i of the
||| writer, which the writer's text binds; position i of anything else,
||| which the writer's text does not bind: of an implementation an applied
||| family gives (the projection rule); an implementation's field k, which
||| a field read takes its value from; a choice, which a member read takes
||| its value from; or the values a dictionary holds, whose types a pair
||| that packs them reads.
data Source = Binds Nat | Projects Nat | ReadsField Nat | ReadsChoice ChoiceHead | ReadsHeld

||| A position as what holds it reads it, its own.
ownSource : Spot -> Source
ownSource (OfParameter _ i) = Binds i
ownSource (OfField _ k) = ReadsField k
ownSource (OfChoice k) = ReadsChoice k
ownSource (OfHeld _) = ReadsHeld

sourceFor : (writer : Address) -> Spot -> Source
sourceFor writer (OfParameter (OfNode node) i) = if sameAddress node.definition writer then Binds i else Projects i
sourceFor writer (OfParameter OfApplication i) = Projects i
sourceFor writer spot = ownSource spot

||| An arc's source as a site's writer reads it: in the walk of a member's
||| application, a position of the application the use gives is the
||| writer's parameter past its own (`Sites.Parameters`).
sourceOf : Site -> Spot -> Source
sourceOf site spot@(OfParameter OfApplication i) = case site.params of
  UseFrom from => Binds (from + i)
  OwnOnly => sourceFor site.writer spot
sourceOf site spot = sourceFor site.writer spot

||| Parameter i of what holds a position, as a message names it: the
||| writer's binder; the implementation's binder and the implementation; or
||| the application's argument.
subjectAt : {auto c : Ref Ctxt Defs} -> FC -> Source -> Spot -> Front String
subjectAt fc source (OfParameter (OfNode node) i) = do
  (def, name) <- graphDefinition fc node.definition
  case source of
    Binds _ => parameter i def
    -- A node's parameter its writer does not bind is projected.
    _ => (++ " of " ++ name) <$> parameter i def
subjectAt fc _ (OfParameter OfApplication i) =
  pure ("argument " ++ show (S i) ++ " of the application of a polymorphic function at its use")
subjectAt fc _ spot@(OfField _ _) = holderText fc spot
subjectAt fc _ spot@(OfChoice _) = holderText fc spot
subjectAt fc _ spot@(OfHeld _) = holderText fc spot

||| Does a position belong to a data type, which grows through its fields
||| where a function grows through its calls?
ofDataType : {auto c : Ref Ctxt Defs} -> FC -> Spot -> Front Bool
ofDataType fc (OfParameter (OfNode node) _) = do
  (def, _) <- graphDefinition fc node.definition
  pure (case def.definition of
          TCon {} => True
          _ => False)
ofDataType fc _ = pure False

||| The parts of a template that carry an arc's source into it: its
||| variable when the writer binds it, an applied family that gives an
||| implementation when it is projected, a read of that field when it is a
||| field's position, a member read from that choice's position when it is
||| a choice's: the choice's own, the unshown head's, which every member is
||| read from, and every one for a member whose head is unshown; and, for
||| the values a dictionary holds, each held type a packing writes, every
||| one of whose variables is read there.
carries : Source -> Template -> Bool
carries (Binds i) (Template.Var j _) = i == j
carries (Projects _) (Template.Applied _ _ _) = True
carries (ReadsField k) (Template.Field k' _) = k == k'
carries (ReadsChoice UnshownHead) (Template.Member _) = True
carries (ReadsChoice _) (Template.Member UnshownHead) = True
carries (ReadsChoice k) (Template.Member k') = k == k'
carries ReadsHeld (Template.Var _ _) = True
carries _ _ = False

mutual
  ||| Every part of a template, itself first, in preorder (a `Choice` visits
  ||| what it matched on before its leaves, a field its record).
  parts : Template -> List Template
  parts t@(Template.Head _ ts) = t :: partsOf ts
  parts t@(Template.Choice m ls) = t :: parts m ++ partsOf ls
  parts t@(Template.Opaque _ ts) = t :: partsOf ts
  parts t@(Template.Applied _ _ ts) = t :: partsOf ts
  parts t@(Template.Field _ r) = t :: parts r
  parts t = [t]

  partsOf : List Template -> List Template
  partsOf [] = []
  partsOf (t :: ts) = parts t ++ partsOf ts

||| What an opaque arc passes its source through: a type-level recursion,
||| or a family the writer is given, applied (`Template.Applied`), which
||| every instance beta-reduces. Two cases the problem has: a definition's
||| own unfolding, and a value's.
data Computation = Recursion Address | Family Nat

||| The first type-level computation, in preorder, that holds a part the
||| test picks: in its arguments, or for an applied family, as the family.
computationThrough : (Template -> Bool) -> Template -> Maybe Computation
computationThrough carried t = head' (mapMaybe holding (parts t))
  where
    holding : Template -> Maybe Computation
    holding (Template.Opaque r ts) = if any carried (partsOf ts) then Just (Recursion r) else Nothing
    holding (Template.Applied j d ts) =
      if carried (Template.Var j d) || any carried (partsOf ts) then Just (Family j) else Nothing
    holding _ = Nothing

||| A cycle's arcs, each with the position it leaves, in order: the ring its
||| certificate holds, at least one arc.
around : (g : Graph) -> {0 first, here : Fin g.size} -> (as : List (Fin (length g.arcs))) -> (0 _ : Ring g first here as) ->
         List1 (Fin g.size, Fin (length g.arcs))
around g (a :: as) _ = ((arc g a).from, a) ::: map (\b => ((arc g b).from, b)) as
around g [] (Last _ _) impossible
around g [] (Next _ _ _) impossible

||| Every rotation of a cycle, the i-th starting at its i-th pair.
rotations : List1 a -> List1 (List1 a)
rotations (x ::: xs) = from [] x xs
  where
    from : List a -> a -> List a -> List1 (List1 a)
    from before y [] = (y ::: before) ::: []
    from before y (z :: zs) = (y ::: ((z :: zs) ++ before)) ::: forget (from (before ++ [y]) z zs)

||| A cycle whose static argument grows on every round, reported at its
||| place, by the arc that leaves the definition there (the first arc, when
||| the place is off the cycle): what made that arc and to whom it passes
||| the argument, by how much a round grows it, and the rest of the round
||| back to it.
refuseCycle : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              FC -> Name -> (b : Built) -> List1 (Fin b.graph.size, Fin (length b.graph.arcs)) ->
              (growth : Nat) -> Front ()
refuseCycle fc main b ring growth = do
  (round, place) <- located fc main b (spotOf (fst (head ring)))
                            (map (\r => (r, spotOf (fst (head r)))) (rotations ring))
  let (source, a) = head round
  let spot = index source b.position
  sourceName <- holderText fc spot
  target <- holderText fc (spotOf (arc b.graph a).to)
  path <- case tail round of
    [] => pure ""
    rest => do
      names <- traverse (\(p, _) => holderText fc (spotOf p)) rest
      pure (" through " ++ joinBy " -> " (names ++ [sourceName]))
  let grows = ", growing it by " ++ show growth ++ " each round" ++ path ++
              ", and nothing bounds how far it grows"
  text <- case index a b.wrote of
    FromArgument site argument => do
      (_, within) <- graphDefinition fc site.within
      x <- subjectAt fc (sourceOf site spot) spot
      shown <- showArgument argument.shown
      -- Essential: a data type grows through its fields, a function
      -- through its calls.
      pure (if !(ofDataType fc spot)
              then sourceName ++ " holds " ++ target ++ " at " ++ shown ++ " in " ++
                   within ++ ", growing " ++ x ++ " by " ++ show growth ++ " each level" ++ path ++
                   ", and nothing bounds how deep its values nest"
              else within ++ " passes " ++ x ++ " as " ++ shown ++ " to " ++ target ++ grows)
    -- A leading arc: the implementation whose parameter it is, the arc's
    -- source, places it in the method function its field holds, the arc's
    -- target.
    ThroughMethod => do
      x <- subjectAt fc (ownSource spot) spot
      pure (sourceName ++ " passes " ++ x ++ " to its method " ++ target ++ grows)
    -- An implementation's field: its template places the implementation's
    -- parameter, the arc's source, in the field's value, the arc's target.
    InField _ k _ => do
      x <- subjectAt fc (ownSource spot) spot
      pure (sourceName ++ " places " ++ x ++ " in its field " ++ show k ++ grows)
    -- A pair that packs held values: a held dictionary wrapped into
    -- another, so that each call wraps it deeper.
    PacksHeld _ => do
      x <- subjectAt fc (ownSource spot) spot
      pure (target ++ " packs " ++ x ++ " as one held value" ++ grows)
  reject place.at place.owner Polymorphism text
  where
    spotOf : Fin b.graph.size -> Spot
    spotOf p = index p b.position

||| What wrote an arc nothing bounds: an argument's template, or an
||| implementation's field's.
data UnmeasuredBy = ArgumentWrote Sites.Site Argument | FieldWrote Address Template

0 unmeasuredInfinite : IsFinite Unmeasured -> Void
unmeasuredInfinite ItIsFinite impossible

0 stuckLabel : StuckArc g a -> (arc g a).label = Unmeasured
stuckLabel (ItIsStuck stuck) = stuck

||| What wrote an arc nothing bounds. A leading arc's template and a held
||| packing's are measured wherever they are drawn
||| (`Proof.Describes.measuredDrawn`), which the graph carries for each of
||| its arcs, so neither wrote one.
unmeasuredBy : (b : Built) -> (a : Fin (length b.graph.arcs)) -> (0 _ : (arc b.graph a).label = Unmeasured) -> UnmeasuredBy
unmeasuredBy b a stuck with (index a b.wrote) proof wrote
  _ | FromArgument site argument = ArgumentWrote site argument
  _ | InField j _ t = FieldWrote j t
  _ | ThroughMethod = void (unmeasuredInfinite (replace {p = IsFinite} stuck (b.methodsMeasured a wrote)))
  _ | PacksHeld held = void (unmeasuredInfinite (replace {p = IsFinite} stuck (b.packingsMeasured a held wrote)))

||| A type-level recursion stuck on a static argument, which nothing bounds,
||| reported at its place: what passes the argument, through which
||| recursion, to whom.
refuseOpaque : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               FC -> Name -> (b : Built) -> (a : Fin (length b.graph.arcs)) -> (0 _ : StuckArc b.graph a) -> Front ()
refuseOpaque fc main b a stuck = do
  let MkArc src to _ = arc b.graph a
  let spot = index src b.position
  let target = index to b.position
  -- A field's writer is the implementation, which writes it in its own
  -- text.
  let (writer, home, written, source) = the (Address, Address, Template, Source) $
        case unmeasuredBy b a (stuckLabel stuck) of
          ArgumentWrote site argument => (site.writer, site.within, argument.template, sourceOf site spot)
          FieldWrote j t => (j, j, t, sourceFor j spot)
  ((), place) <- located fc main b spot (((), spot) ::: [((), target)])
  let Just computation = computationThrough (carries source) written
    | Nothing => internal fc "an opaque arc whose template holds no type-level computation"
  through <- case computation of
    Recursion r => ("the type-level recursion " ++) . snd <$> graphDefinition fc r
    Family j => do
      (writerDef, _) <- graphDefinition fc writer
      ("its type family " ++) <$> parameter j writerDef
  targetName <- holderText fc target
  (_, homeName) <- graphDefinition fc home
  x <- subjectAt fc source spot
  reject place.at place.owner Polymorphism
         (homeName ++ " passes " ++ x ++ " through " ++ through ++ " to " ++ targetName ++
          ", and nothing bounds what it computes")

||| A cause of growth, refused once as rule `polymorphism`. A cycle's growth
||| a round is what its certificate sums: every arc on it is finite, and its
||| gains exceed its losses.
refuse : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         FC -> Name -> (b : Built) -> Cause b.graph -> Front ()
refuse fc main b (Cycle as (Sums ring _ _)) =
  refuseCycle fc main b (around b.graph as ring)
              (minus (gains (labels b.graph as)) (losses (labels b.graph as)))
refuse fc main b (Unbounded a stuck) = refuseOpaque fc main b a stuck

------------------------------------------------------------------------------
-- The phase
------------------------------------------------------------------------------

||| The growth check, between what the program reaches and its
||| translation: the graph of its static positions, built and checked.
||| Admitted, it writes each position's bound and each definition's
||| sizes, which the translation's worklist descends within. Refused, it
||| reports each cause of a type grown without bound once, and the
||| program is not translated: with no potential there is no bound to
||| translate within. Not admitted always leaves a rejection recorded,
||| or throws.
export
checkGrowth : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> FC -> (main : Name) -> Core Bool
checkGrowth fc main = do
  Just b <- noting (build main)
    | Nothing => pure False
  case check b.graph of
    Bounded pot _ => do
      let ts = tablesOf b pot
      updateState { bounds := boundsOf b ts, sizes := sizesOf b (heightsOf b pot ts) }
      pure True
    Grows causes => do
      for_ (forget causes) $ \cause => noted (refuse fc main b cause)
      pure False
