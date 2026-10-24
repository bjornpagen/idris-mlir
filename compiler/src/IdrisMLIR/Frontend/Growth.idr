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
import IdrisMLIR.Frontend.Translate.Readings
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Loc
import IdrisMLIR.Proof.Describes
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
import Data.SortedSet
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

readAt : {b : Built} -> {0 pot : Vect b.graph.size Nat} -> Tables b pot -> (f : Fin b.graph.size) -> ReadAt b pot f
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
boundsOf : (b : Built) -> {0 pot : Vect b.graph.size Nat} -> Tables b pot -> SortedMap Position Nat
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

-- A height is within itself.
0 withinSelf : {n : Nat} -> LTE n n
withinSelf = reflexive

0 raisedHere : (i, x : Nat) -> (hs : List Nat) -> LTE x (parameterHeight (raiseList i x hs) i)
raisedHere Z x [] = withinSelf
raisedHere Z x (h :: hs) = maximumRightUpperBound h x
raisedHere (S i) x [] = raisedHere i x []
raisedHere (S i) x (h :: hs) = raisedHere i x hs

0 raisedKeeps : (i, x : Nat) -> (hs : List Nat) -> (j : Nat) -> LTE (parameterHeight hs j) (parameterHeight (raiseList i x hs) j)
raisedKeeps i x [] j = LTEZero
raisedKeeps Z x (h :: hs) Z = maximumLeftUpperBound h x
raisedKeeps Z x (h :: hs) (S j) = withinSelf
raisedKeeps (S i) x (h :: hs) Z = withinSelf
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
                     withinSelf)
    Right (_, raised) =>
      case lookView (decideHead k h) hs hs (heightsIn rest k) (heightsIn (raiseAt g i x rest) k) of
        Left (_, before, after) =>
          lteOfEq (cong (\l => parameterHeight l j) before)
            (lteToEq (sym (trans (cong (\tb => parameterHeight (heightsIn tb k) j) raised) (cong (\l => parameterHeight l j) after)))
                     withinSelf)
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

0 keptAll : {0 g : Graph} -> {0 pot : Vect g.size Nat} -> {0 position : Vect g.size Spot} -> {0 fs : List (Fin g.size)} ->
            (r : Raised table h spot) -> All (\f => PlacedIn table (bound g pot f) (index f position)) fs ->
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
  let rest = heightsFrom b pot ts fs
      here = readAt ts f
      r = raiseFor here.spotRead here.boundRead rest.table in
  MkPlacing r.raised (placedAsHeld r here.isSpot here.isBound :: keptAll r rest.placed)

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
sizesOf : (b : Built) -> {0 pot : Vect b.graph.size Nat} -> Placing b pot b.firsts -> Bounds
sizesOf b placing = MkBounds (heightsIn placing.table) b.arity b.heaviest b.breadth

------------------------------------------------------------------------------
-- Names and places
------------------------------------------------------------------------------

||| A definition's name as a message prints it.
definitionName : {auto c : Ref Ctxt Defs} -> GlobalDef -> Front String
definitionName def = nameKey <$> fullNames (fullname def)

||| An interface's name, as the type that heads its choice names it, as a
||| message prints it.
interfaceName : {auto c : Ref Ctxt Defs} -> Name -> Front String
interfaceName n = nameKey <$> fullNames n

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
userDefinition : {auto s : Ref TState TS} -> GlobalDef -> Front (Maybe (Loc, GlobalDef))
userDefinition def = do
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

||| A dictionary's place, as a message names it, by the definitions the
||| walk read with it (`PlaceRead`): a parameter of what holds it, by the
||| parameter's name and the holder's, or argument i of the application at
||| a use; an implementation's field, by the implementation's name; a
||| choice, by its interface's name, as the polymorphic functions', or as
||| one whose type only an instance shows; or a dictionary a definition's
||| text binds, by the definition's name.
placeText : {auto c : Ref Ctxt Defs} -> (place : HeldBy) -> PlaceRead place -> Front String
placeText (ByParameter (OfNode _) i) (NodeParameter def) = do
  name <- definitionName def
  (++ " of " ++ name) <$> parameter i def
placeText (ByParameter OfApplication i) ApplicationParameter =
  pure ("argument " ++ show (S i) ++ " of the application of a polymorphic function at its use")
placeText (ByField _ k) (FieldOf def) = (\name => "field " ++ show k ++ " of " ++ name) <$> definitionName def
placeText (ByChoice (InterfaceHead _)) (ChoiceOfHead (InterfaceNamed n)) =
  (\name => "the implementations of " ++ name ++ " the running program chooses") <$> interfaceName n
placeText (ByChoice ArrowHead) (ChoiceOfHead ArrowRead) = pure "the polymorphic functions the running program chooses"
placeText (ByChoice UnshownHead) (ChoiceOfHead UnshownRead) =
  pure "the members the running program chooses of a choice whose type only an instance shows"
placeText (ByBinding _ _) (BoundIn def) = (\name => "a dictionary bound in " ++ name) <$> definitionName def

||| What holds a position, as a message names it: a node's definition, by
||| its name; the application at a use, which no name is; an
||| implementation's field or a choice, as its place is named; or the
||| values a dictionary's place holds, by that place.
holderText : {auto c : Ref Ctxt Defs} -> (spot : Spot) -> SpotRead spot -> Front String
holderText (OfParameter (OfNode _) _) (ParameterSpot (NodeParameter def)) = definitionName def
holderText (OfParameter OfApplication _) (ParameterSpot ApplicationParameter) =
  pure "the application of a polymorphic function at its use"
holderText (OfField j k) (FieldSpot r) = placeText (ByField j k) r
holderText (OfChoice k) (ChoiceSpot r) = placeText (ByChoice k) r
holderText (OfHeld (MkHeldValues place _)) (HeldSpot r) =
  (\text => "the values " ++ text ++ " holds") <$> placeText place r

||| The definition of the program's own source that holds a position, with
||| where it is: nothing for a library's or a generated one, or for the
||| application at a use, or a choice, which no definition is.
userHolder : {auto s : Ref TState TS} -> (spot : Spot) -> SpotRead spot -> Front (Maybe (Loc, GlobalDef))
userHolder (OfParameter (OfNode _) _) (ParameterSpot (NodeParameter def)) = userDefinition def
userHolder (OfParameter OfApplication _) (ParameterSpot ApplicationParameter) = pure Nothing
userHolder (OfField _ _) (FieldSpot (FieldOf def)) = userDefinition def
userHolder (OfChoice _) _ = pure Nothing
userHolder (OfHeld _) _ = pure Nothing

||| The first user definition among a node's reachers on the walk from
||| main, nearest first, as the walk read them; nothing when main is
||| reached with none.
reacher : {auto s : Ref TState TS} -> (reachers : List GlobalDef) -> Front (Maybe GlobalDef)
reacher [] = pure Nothing
reacher (d :: ds) = case !(userDefinition d) of
  Just (_, def) => pure (Just def)
  Nothing => reacher ds

||| Where a refusal is reported, and which of its candidates is there. Each
||| candidate is what holds one of the cause's positions. Of the user
||| definitions among them, the one first in the source is the place, at the
||| first candidate it is on. With none, the cause is reported where the
||| program reaches it, at the first candidate: at the first user definition
||| among the reachers of the cause's first node, or at main.
located : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          FC -> Name -> (b : Built) -> (first : Fin b.graph.size) -> List1 (t, Fin b.graph.size) -> Front (t, Place)
located fc main b first candidates = do
  users <- traverse (\(v, p) => map (\(loc, def) => (v, loc, def)) <$>
                                 userHolder (index p b.position) (readAtPlace p b.positionRead))
                    (forget candidates)
  case catMaybes users of
    u :: us => let (v, _, def) = earliest u us in pure (v, placeOf def)
    [] => do
      above <- reacher (reachersOf (index first b.position))
      pure (fst (head candidates), maybe (MkPlace fc (show main)) placeOf above)
  where
    -- The application at a use, a field and a choice are reached through
    -- no node of their own, and main is reached through none.
    reachersOf : Spot -> List GlobalDef
    reachersOf (OfParameter (OfNode node) _) = fromMaybe [] (lookup node b.reachers)
    reachersOf _ = []

------------------------------------------------------------------------------
-- The causes
------------------------------------------------------------------------------

||| Parameter i of what holds an arc's source, as a message names it, by
||| whether the arc's writer binds it: the writer's binder; or one its text
||| does not bind, an implementation's, named with the implementation; or
||| the application's argument.
subjectAt : {auto c : Ref Ctxt Defs} -> ArcSource -> (spot : Spot) -> SpotRead spot -> Front String
subjectAt WriterBinds (OfParameter (OfNode _) i) (ParameterSpot (NodeParameter def)) = parameter i def
subjectAt WriterProjects (OfParameter (OfNode _) i) (ParameterSpot (NodeParameter def)) = do
  name <- definitionName def
  (++ " of " ++ name) <$> parameter i def
subjectAt _ (OfParameter OfApplication i) (ParameterSpot ApplicationParameter) =
  pure ("argument " ++ show (S i) ++ " of the application of a polymorphic function at its use")
subjectAt _ spot@(OfField _ _) r = holderText spot r
subjectAt _ spot@(OfChoice _) r = holderText spot r
subjectAt _ spot@(OfHeld _) r = holderText spot r

||| Does a position belong to a data type, which grows through its fields
||| where a function grows through its calls?
ofDataType : (spot : Spot) -> SpotRead spot -> Bool
ofDataType (OfParameter (OfNode _) _) (ParameterSpot (NodeParameter def)) = case def.definition of
  TCon {} => True
  _ => False
ofDataType (OfParameter OfApplication _) _ = False
ofDataType (OfField _ _) _ = False
ofDataType (OfChoice _) _ = False
ofDataType (OfHeld _) _ = False

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
  (round, place) <- located fc main b (fst (head ring)) (map (\r => (r, fst (head r))) (rotations ring))
  let (source, a) = head round
  sourceName <- holderAt source
  target <- holderAt (arc b.graph a).to
  path <- case tail round of
    [] => pure ""
    rest => do
      names <- traverse (\(p, _) => holderAt p) rest
      pure (" through " ++ joinBy " -> " (names ++ [sourceName]))
  let grows = ", growing it by " ++ show growth ++ " each round" ++ path ++
              ", and nothing bounds how far it grows"
  let (asDrawn, wrote) = index a b.drawing
  x <- subjectAt asDrawn.sourceRead (index source b.position) (readAtPlace source b.positionRead)
  text <- case wrote of
    FromArgument entry argument => do
      within <- definitionName entry.site.within
      shown <- showArgument argument.shown
      -- Essential: a data type grows through its fields, a function
      -- through its calls.
      pure (if ofDataType (index source b.position) (readAtPlace source b.positionRead)
              then sourceName ++ " holds " ++ target ++ " at " ++ shown ++ " in " ++
                   within ++ ", growing " ++ x ++ " by " ++ show growth ++ " each level" ++ path ++
                   ", and nothing bounds how deep its values nest"
              else within ++ " passes " ++ x ++ " as " ++ shown ++ " to " ++ target ++ grows)
    -- A leading arc: the implementation whose parameter it is, the arc's
    -- source, places it in the method function its field holds, the arc's
    -- target.
    ThroughMethod => pure (sourceName ++ " passes " ++ x ++ " to its method " ++ target ++ grows)
    -- An implementation's field: its template places the implementation's
    -- parameter, the arc's source, in the field's value, the arc's target.
    InField _ k _ => pure (sourceName ++ " places " ++ x ++ " in its field " ++ show k ++ grows)
    -- A pair that packs held values: a held dictionary wrapped into
    -- another, so that each call wraps it deeper.
    PacksHeld _ => pure (target ++ " packs " ++ x ++ " as one held value" ++ grows)
  reject place.at place.owner Polymorphism text
  where
    -- What holds a position of the graph, as a message names it, by what
    -- the walk read with the position.
    holderAt : Fin b.graph.size -> Front String
    holderAt p = holderText (index p b.position) (readAtPlace p b.positionRead)

||| What wrote an arc nothing bounds: a site's argument, or a field of the
||| definition that gives a dictionary, as it was read.
data UnmeasuredBy = ArgumentWrote State.Site | FieldWrote GlobalDef

0 unmeasuredInfinite : IsFinite Unmeasured -> Void
unmeasuredInfinite ItIsFinite impossible

0 stuckLabel : StuckArc g a -> (arc g a).label = Unmeasured
stuckLabel (ItIsStuck stuck) = stuck

||| What wrote an arc nothing bounds. A leading arc's template and a held
||| packing's are measured wherever they are drawn
||| (`Proof.Describes.measuredDrawn`), which the graph carries for each of
||| its arcs, so neither wrote one.
unmeasuredBy : (b : Built) -> (a : Fin (length b.graph.arcs)) -> (0 _ : (arc b.graph a).label = Unmeasured) -> UnmeasuredBy
unmeasuredBy b a stuck with (snd (index a b.drawing)) proof wrote
  _ | FromArgument entry _ = ArgumentWrote entry.site
  _ | InField j _ _ = FieldWrote j
  _ | ThroughMethod = void (unmeasuredInfinite (replace {p = IsFinite} stuck (b.methodsMeasured a wrote)))
  _ | PacksHeld held = void (unmeasuredInfinite (replace {p = IsFinite} stuck (b.packingsMeasured a held wrote)))

||| A type-level computation a static argument passes through, which
||| nothing bounds, reported at its place: what passes the argument,
||| through which computation, to whom. The arc was drawn with that
||| computation (`Proof.Describes.throughOf`), where its weight was made: a
||| recursion by its place among the drawn template's, whose definition
||| what made the arc read (`Graph.recursionAt`).
refuseOpaque : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               FC -> Name -> (b : Built) -> (a : Fin (length b.graph.arcs)) -> (0 _ : StuckArc b.graph a) -> Front ()
refuseOpaque fc main b a stuck = do
  let MkArc src to _ = arc b.graph a
  -- A field's writer is the definition that gives the dictionary, which
  -- writes it in its own text.
  let (writer, home) = the (GlobalDef, GlobalDef) $ case unmeasuredBy b a (stuckLabel stuck) of
        ArgumentWrote site => (site.writerDef, site.within)
        FieldWrote j => (j, j)
  ((), place) <- located fc main b src (((), src) ::: [((), to)])
  through <- case throughOf (fst (index a b.drawing)) (trans (cong (.label) (b.drawnAs a)) (stuckLabel stuck)) of
    StuckRecursion el =>
      ("the type-level recursion " ++) <$> definitionName (recursionAt (snd (index a b.drawing)) (b.drawnBy a) el).def
    AppliedFamily j => ("its type family " ++) <$> parameter j writer
  targetName <- holderText (index to b.position) (readAtPlace to b.positionRead)
  homeName <- definitionName home
  x <- subjectAt (fst (index a b.drawing)).sourceRead (index src b.position) (readAtPlace src b.positionRead)
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
-- A cycle of calls a dictionary measures
------------------------------------------------------------------------------

-- A cycle of calls through an implementation's dictionary in which a
-- method's type argument grows while the dictionary strictly shrinks (a
-- monad transformer over itself: the outer `StateT`'s bind calls the inner
-- one's at `(s, a)` through the dictionary it was given) is a finite
-- nesting the program fixes. A turn that dispatches through the writer's
-- own dictionary runs a method whose leading dictionaries are that
-- dictionary's arguments, strictly smaller, and no other call of the cycle
-- passes one on larger, so a walk through the cycle makes no more such
-- dispatches than the dictionary it entered with is high. The graph's
-- positions cannot say so, since the type argument and the dictionary are
-- two of them, joined only by the calls both are passed at: the cycle is
-- measured by its calls (`Graph.measureEdges`), each node of it by one
-- dictionary parameter, which every call of the component passes on as it
-- is or strictly smaller. With the arcs on a shrinking call drawn from a
-- source past every position instead, so that they constrain nothing, no
-- cycle of the component may gain: then a walk through it gains no more
-- than its arcs gain together (T) between two shrinking calls, and no
-- more than that at each, so a value entering it grows by no more than
-- (2H + 1) T, H the most its dictionaries can be high (`bound`, read with
-- the shrinking arcs detached). Every arc into the component carries that
-- allowance, and so does an arc from the source to each of its positions,
-- for a value the component starts itself, so the potential the check
-- finds over that graph bounds the program; the dictionaries' own bounds
-- must come out as they were, or they would hang on the growth they
-- measure.

||| A position by the spot it was first met at.
positionsBySpot : (b : Built) -> SortedMap Spot (Fin b.graph.size)
positionsBySpot b = foldl (\m, f => insert (index f b.position) f m) SortedMap.empty b.firsts

||| Some values, each with its number from k.
numberedFrom : Nat -> List a -> List (Nat, a)
numberedFrom k [] = []
numberedFrom k (x :: xs) = (k, x) :: numberedFrom (S k) xs

||| The component each position is in, by number.
componentOf : List (List (Fin n)) -> SortedMap Nat Nat
componentOf cs = foldl (\m, (k, ps) => foldl (\m', p => insert (finToNat p) k m') m ps) SortedMap.empty (numberedFrom 0 cs)

||| An arc inside a component, on a call the walk drew between two nodes:
||| the call's ends, what it passes on of its writer's dictionaries, and
||| the arc's number, gain and loss.
record OnCall where
  constructor MkOnCall
  writer : Node
  callee : Node
  edges : List MeasureEdge
  arcNumber : Nat
  gain : Nat
  loss : Nat

||| An arc as a call the walk drew passes a value at, with what the call
||| passes on of its writer's dictionaries; none for an arc nothing
||| measures (an Unmeasured one, one no call between nodes drew, one on a
||| call that passes on no dictionary).
onCall : (b : Built) -> Fin (length b.graph.arcs) -> Maybe OnCall
onCall b a = case (arc b.graph a, snd (index a b.drawing)) of
  (MkArc f t (Measured gn ls), FromArgument en _) => case (index f b.position, index t b.position) of
    (OfParameter (OfNode w) _, OfParameter (OfNode c) _) => case lookup (w, finToNat en.number, c) b.measures of
      Just es@(_ :: _) => Just (MkOnCall w c es (finToNat a) gn ls)
      _ => Nothing
    _ => Nothing
  _ => Nothing

||| The dictionary parameter each node of a component's calls is measured
||| by: the least among those every call it writes or is called at passes
||| on at its end; none where a node has none.
measuring : List OnCall -> Maybe (SortedMap Node Nat)
measuring calls = SortedMap.fromList <$> traverse (\n => (n,) <$> chosen n) (nub (calls >>= \c => [c.writer, c.callee]))
  where
    -- What a call passes on at a node's end of it: its writer's parameters
    -- where the node writes it, its callee's where the node is called, both
    -- where it calls itself.
    atEnd : Node -> OnCall -> Maybe (List Nat)
    atEnd n c = case (c.writer == n, c.callee == n) of
      (True, True) => Just (filter (\p => elem p (map (.calleeParameter) c.edges)) (map (.writerParameter) c.edges))
      (True, False) => Just (map (.writerParameter) c.edges)
      (False, True) => Just (map (.calleeParameter) c.edges)
      (False, False) => Nothing

    chosen : Node -> Maybe Nat
    chosen n = case mapMaybe (atEnd n) calls of
      [] => Nothing
      p :: ps => case foldl (\acc, q => filter (\x => elem x q) acc) p ps of
        [] => Nothing
        x :: xs => Just (foldl min x xs)

||| How a call passes on the dictionary its ends are measured by: strictly
||| smaller where any of its passings that match the measure shrinks it;
||| none where none matches.
shrinkOn : SortedMap Node Nat -> OnCall -> Maybe Shrink
shrinkOn mu c = do
  i <- lookup c.writer mu
  j <- lookup c.callee mu
  case filter (\e => e.writerParameter == i && e.calleeParameter == j) c.edges of
    [] => Nothing
    es => Just (if any (\e => case e.shrink of { Strictly => True; Equally => False }) es then Strictly else Equally)

||| One growing component a dictionary measures: its positions, the
||| positions of its nodes' measuring dictionaries, the arcs on a call that
||| shrinks the dictionary, and what its arcs gain together.
record Measured (n : Nat) where
  constructor MkMeasured
  members : List (Fin n)
  measures : List (Fin n)
  shrinking : List Nat
  gained : Nat

||| A growing component, measured, where every arc inside it is on a call
||| that passes on its writer's measuring dictionary as it is or strictly
||| smaller, the measuring dictionaries being positions of the graph.
measuredOf : (b : Built) -> SortedMap Spot (Fin b.graph.size) -> List (Fin b.graph.size) -> Maybe (Measured b.graph.size)
measuredOf b spots members = do
  let inside = SortedSet.fromList (map finToNat members)
  let inner = filter (\a => contains (finToNat (arc b.graph a).from) inside && contains (finToNat (arc b.graph a).to) inside)
                     (everyArc b.graph)
  calls <- traverse (onCall b) inner
  mu <- measuring calls
  shrinks <- traverse (shrinkOn mu) calls
  measures <- traverse (\(n, p) => lookup (OfParameter (OfNode n) p) spots) (SortedMap.toList mu)
  pure (MkMeasured members measures
                   (mapMaybe (\(c, sh) => case sh of
                                           Strictly => Just c.arcNumber
                                           Equally => Nothing) (zip calls shrinks))
                   (foldl (\t, c => t + minus c.gain c.loss) 0 calls))

||| The graph with a source past every position, the shrinking arcs drawn
||| from it instead, so that they constrain nothing, and each measured
||| component's allowance (none, to read the dictionaries' bounds): every
||| arc into it raised by it, and an arc from the source to each of its
||| positions that gives it that much.
detached : (g : Graph) -> SortedSet Nat -> List (List (Fin g.size), Nat) -> Graph
detached g shrinking adm = MkGraph (S g.size) (zipWith arcAt (everyArc g) g.arcs ++ sourced) g.constant (snoc g.caps Nothing)
  where
    tagged : SortedMap Nat (Nat, Nat)
    tagged = foldl (\m, (k, (ms, al)) => foldl (\m', p => insert (finToNat p) (k, al) m') m ms) SortedMap.empty (numberedFrom 0 adm)

    into : Fin g.size -> Fin g.size -> Nat
    into f t = case (lookup (finToNat t) tagged, lookup (finToNat f) tagged) of
      (Just (k, al), Just (k', _)) => if k == k' then 0 else al
      (Just (_, al), Nothing) => al
      _ => 0

    arcAt : Fin (length g.arcs) -> Arc g.size -> Arc (S g.size)
    arcAt a (MkArc f t lab) =
      if contains (finToNat a) shrinking then MkArc last (weaken t) (Measured 0 0) else case lab of
        Measured gn ls => MkArc (weaken f) (weaken t) (Measured (gn + into f t) ls)
        Unmeasured => MkArc (weaken f) (weaken t) Unmeasured

    sourced : List (Arc (S g.size))
    sourced = adm >>= \(ms, al) => map (\p => MkArc last (weaken p) (Measured al 0)) ms

||| An arc of the graph Unmeasured, with the evidence.
stuckIn : (g : Graph) -> (a : Fin (length g.arcs)) -> Maybe (StuckArc g a)
stuckIn g a with ((arc g a).label) proof p
  _ | Unmeasured = Just (ItIsStuck p)
  _ | Measured _ _ = Nothing

||| The program's growth where dictionaries measure it, given the graph's
||| components the check settled: every cycle of a growing component that a
||| dictionary measures admitted, the potential
||| over the graph with their allowances, which bounds every position; or,
||| where something still grows, the causes to report: each one the graph
||| gave of a component not measured, or whose shrinking arcs leave a
||| cycle that gains, and each Unbounded arc no growing component reaches
||| any more.
measuredPotential : (b : Built) -> (found : List (List (Fin b.graph.size))) -> List1 (Cause b.graph) ->
                    Either (List1 (Cause b.graph)) (Vect b.graph.size Nat)
measuredPotential b found causes =
  let comps = componentOf found
      spots = positionsBySpot b
      componentAt = \p => lookup (finToNat p) comps
      growing = nub (mapMaybe (\c => case c of
                                       Cycle _ _ => componentAt (causeSource c)
                                       Unbounded _ _ => Nothing) (forget causes))
      admitted = mapMaybe (\k => (k,) <$> (getAt k found >>= measuredOf b spots)) growing in
  case admitted of
    [] => Left causes
    _ => kept componentAt admitted (SortedSet.fromList (admitted >>= \(_, m) => m.shrinking))
  where
    -- What still grows with the shrinking arcs detached: the causes the
    -- graph gave of every component not admitted, or one that still gains,
    -- and each Unbounded arc no growing component reaches now.
    reported : (Fin b.graph.size -> Maybe Nat) -> List Nat -> (s : SortedSet Nat) -> List1 (Cause (detached b.graph s [])) ->
               List1 (Cause b.graph)
    reported componentAt admitted s still =
      let gaining = mapMaybe (\c => strengthen (causeSource c) >>= componentAt) (forget still)
          remaining = filter (\c => case c of
                                      Cycle _ _ => maybe True (\k => not (elem k admitted) || elem k gaining) (componentAt (causeSource c))
                                      Unbounded _ _ => True) (forget causes)
          known = mapMaybe (\c => case c of { Unbounded a _ => Just (finToNat a); _ => Nothing }) (forget causes)
          exposed = mapMaybe (\c => case c of
                                      Unbounded a _ => if elem (finToNat a) known then Nothing else do
                                                         a' <- natToFin (finToNat a) (length b.graph.arcs)
                                                         (\st => Unbounded a' st) <$> stuckIn b.graph a'
                                      Cycle _ _ => Nothing) (forget still) in
      fromMaybe causes (fromList (remaining ++ exposed))

    -- The measured components' allowances over the graph with their
    -- shrinking arcs detached, where nothing grows there: the potential
    -- over the graph with them, its dictionaries' bounds as they were.
    allowed : List (Nat, Measured b.graph.size) -> (s : SortedSet Nat) -> Vect (detached b.graph s []).size Nat ->
              Either (List1 (Cause b.graph)) (Vect b.graph.size Nat)
    allowed admitted s pot =
      let allowance = \m => (2 * foldl (\h, p => max h (bound (detached b.graph s []) pot (weaken p))) 0 m.measures + 1) * m.gained in
      case check (detached b.graph s (map (\(_, m) => (m.members, allowance m)) admitted)) of
        Grows _ => Left causes
        Bounded pot' _ =>
          if all (\(_, m) => all (\p => index (weaken p) pot' == index (weaken p) pot) m.measures) admitted
            then Right (init pot')
            else Left causes

    -- The graph with the measured components' shrinking arcs detached.
    kept : (Fin b.graph.size -> Maybe Nat) -> List (Nat, Measured b.graph.size) -> (s : SortedSet Nat) ->
           Either (List1 (Cause b.graph)) (Vect b.graph.size Nat)
    kept componentAt admitted s = case check (detached b.graph s []) of
      Grows still => Left (reported componentAt (map fst admitted) s still)
      Bounded pot _ => allowed admitted s pot

------------------------------------------------------------------------------
-- The phase
------------------------------------------------------------------------------

||| The growth check, between what the program reaches and its
||| translation: the graph of its static positions from main, as the
||| reading holds it, built and checked. Admitted, it writes each
||| position's bound and each definition's sizes, which the translation's
||| worklist descends within. Refused, it reports each cause of a type
||| grown without bound once, and the program is not translated: with no
||| potential there is no bound to translate within. Not admitted always
||| leaves a rejection recorded, or throws.
export
checkGrowth : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> FC -> (mainRead : Defined) -> Core Bool
checkGrowth fc mainRead = do
  let main = fullname mainRead.def
  Just b <- noting (build mainRead)
    | Nothing => pure False
  let (verdict, found) = checkSettled b.graph
  case verdict of
    Bounded pot _ => admit b pot
    Grows causes => case measuredPotential b found causes of
      Right pot => admit b pot
      Left reported => do
        for_ (forget reported) $ \cause => noted (refuse fc main b cause)
        pure False
  where
    admit : (b : Built) -> Vect b.graph.size Nat -> Core Bool
    admit b pot = do
      let ts = tablesOf b pot
      updateState { bounds := boundsOf b ts, sizes := sizesOf b (heightsOf b pot ts),
                    growth := siteTable b }
      pure True
