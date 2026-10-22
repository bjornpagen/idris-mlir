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
import IdrisMLIR.Frontend.Growth.Sites
import IdrisMLIR.Frontend.Growth.Template
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Loc
import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Spec.Core.Rules

import Data.Fin
import Data.List
import Data.List1
import Data.Maybe
import Data.SortedMap
import Data.String
import Data.Vect

%default total

------------------------------------------------------------------------------
-- The bounds
------------------------------------------------------------------------------

||| What the potential the check found bounds: each node's position, which
||| the worklist checks an instance of a definition's static arguments
||| against, and the application's, by parameter, which bound a member at
||| a use's link (`Translate.State.AtUse`).
record Limits where
  constructor MkLimits
  atNodes : SortedMap Position Nat
  atApplication : SortedMap Nat Nat

||| Each position's bound under the potential the check found (`bound`), in
||| one pass over the places positions were first met at, each position
||| once. A field's position bounds what field reads write, never a
||| request, so no request's position is one.
boundsOf : (b : Built) -> Vect b.graph.size Nat -> Limits
boundsOf b pot = foldl at (MkLimits empty empty) b.firsts
  where
    at : Limits -> Fin b.graph.size -> Limits
    at acc f =
      let h = capped b.graph.constant (index f pot) (index f b.graph.caps) in
      case index f b.position of
        OfParameter (OfNode node) i => { atNodes $= insert (node, i) h } acc
        OfParameter OfApplication i => { atApplication $= insert i h } acc
        OfField _ _ => acc

||| Heights by parameter from `next` on, from the height of each parameter
||| that has one, ascending: a parameter with none is 0, which keys nothing.
byParameter : (next : Nat) -> List (Nat, Nat) -> List Nat
byParameter next [] = []
byParameter next ((j, h) :: rest) = replicate (minus j next) 0 ++ h :: byParameter (S j) rest

||| Each definition's heights by parameter: the largest bound of each of its
||| parameters over the nodes it is split into.
heights : SortedMap Position Nat -> SortedMap Address (List Nat)
heights bs =
  let largest = fromListWith max [((node.definition, j), h) | ((node, j), h) <- SortedMap.toList bs] in
  map (byParameter 0) (fromListWith (\new, old => old ++ new)
                               [(a, the (List (Nat, Nat)) [(j, h)]) | ((a, j), h) <- SortedMap.toList largest])

||| The universe the worklist descends in, read from the bounds alone, the
||| one reading of each: each definition's heights (`heights`), and the
||| application's, its positions' bounds by parameter, with the graph's
||| arity, heaviest token and breadth. No size is computed: the worklist
||| decides each link's sizes against these heights
||| (`Proof.Requests.within`).
sizesOf : Built -> Limits -> Bounds
sizesOf b bs =
  let table = heights bs.atNodes
      application = byParameter 0 (SortedMap.toList bs.atApplication)
      heightAt : Head -> List Nat
      heightAt (ADefinition a) = fromMaybe [] (lookup a table)
      heightAt AnApplication = application
  in MkBounds heightAt b.arity b.heaviest b.breadth

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

||| What holds a position, as a message names it: a node's definition, by
||| its name; the application at a use, which no name is; or an
||| implementation's field, by the implementation's name.
holderText : {auto c : Ref Ctxt Defs} -> FC -> Spot -> Front String
holderText fc (OfParameter (OfNode node) _) = snd <$> graphDefinition fc node.definition
holderText fc (OfParameter OfApplication _) = pure "the application of a polymorphic function at its use"
holderText fc (OfField j k) = (\name => "field " ++ show k ++ " of " ++ name) . snd <$> graphDefinition fc j

||| The definition of the program's own source that holds a position, with
||| where it is: nothing for a library's or a generated one, or for the
||| application at a use, which no definition is.
userHolder : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             FC -> Spot -> Front (Maybe (Loc, GlobalDef))
userHolder fc (OfParameter (OfNode node) _) = userDefinition fc node.definition
userHolder fc (OfParameter OfApplication _) = pure Nothing
userHolder fc (OfField j _) = userDefinition fc j

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
    -- The application at a use, and a field, are reached through no node
    -- of their own.
    reachersOf : Spot -> List Node
    reachersOf (OfParameter (OfNode node) _) = fromMaybe [] (lookup node b.reachers)
    reachersOf _ = []

------------------------------------------------------------------------------
-- The causes
------------------------------------------------------------------------------

||| An arc's source position as its writer reads it: a parameter of the
||| writer, which the writer's text binds; a position of anything else,
||| which the writer's text does not bind: of the implementation that built
||| a dictionary the site takes out of a value (the projection rule); or an
||| implementation's field, which a field read takes its value from.
data Source = Binds | Projects | ReadsField

sourceFor : (writer : Address) -> Spot -> Source
sourceFor writer (OfParameter (OfNode node) _) = if sameAddress node.definition writer then Binds else Projects
sourceFor writer (OfParameter OfApplication _) = Projects
sourceFor writer (OfField _ _) = ReadsField

sourceOf : Site -> Spot -> Source
sourceOf site = sourceFor site.writer

||| Parameter i of what holds a position, as a message names it: the
||| writer's binder; the implementation's binder and the implementation; or
||| the application's argument.
subjectAt : {auto c : Ref Ctxt Defs} -> FC -> Source -> Spot -> Front String
subjectAt fc source (OfParameter (OfNode node) i) = do
  (def, name) <- graphDefinition fc node.definition
  case source of
    Binds => parameter i def
    -- A node's parameter its writer does not bind is projected.
    _ => (++ " of " ++ name) <$> parameter i def
subjectAt fc _ (OfParameter OfApplication i) =
  pure ("argument " ++ show (S i) ++ " of the application of a polymorphic function at its use")
subjectAt fc _ spot@(OfField _ _) = holderText fc spot

||| Does a position belong to a data type, which grows through its fields
||| where a function grows through its calls?
ofDataType : {auto c : Ref Ctxt Defs} -> FC -> Spot -> Front Bool
ofDataType fc (OfParameter (OfNode node) _) = do
  (def, _) <- graphDefinition fc node.definition
  pure (case def.definition of
          TCon {} => True
          _ => False)
ofDataType fc _ = pure False

||| The parts of a template that carry an arc's source, parameter i or
||| field i, into it: its variable when the writer binds it, a held
||| dictionary when it is projected, a read of that field when it is a
||| field's position.
carries : Source -> Nat -> Template -> Bool
carries Binds i (Template.Var j _) = i == j
carries Projects _ (Template.Held _ _) = True
carries ReadsField k (Template.Field k' _) = k == k'
carries _ _ _ = False

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
      x <- subjectAt fc Binds spot
      pure (sourceName ++ " passes " ++ x ++ " to its method " ++ target ++ grows)
    -- An implementation's field: its template places the implementation's
    -- parameter, the arc's source, in the field's value, the arc's target.
    InField _ k _ => do
      x <- subjectAt fc Binds spot
      pure (sourceName ++ " places " ++ x ++ " in its field " ++ show k ++ grows)
  reject place.at place.owner Polymorphism text
  where
    spotOf : Fin b.graph.size -> Spot
    spotOf p = index p b.position

||| A type-level recursion stuck on a static argument, which nothing bounds,
||| reported at its place: what passes the argument, through which
||| recursion, to whom.
refuseOpaque : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               FC -> Name -> (b : Built) -> Fin (length b.graph.arcs) -> Front ()
refuseOpaque fc main b a = do
  let MkArc src to _ = arc b.graph a
  let spot = index src b.position
  let target = index to b.position
  -- Essential while an arc's label is not tied to what made it: a leading
  -- arc is Measured, so only an argument's or a field's template is
  -- Unmeasured; a field's writer is the implementation, which writes it
  -- in its own text.
  (writer, home, written, source) <- the (Front (Address, Address, Template, Source)) $
    case index a b.wrote of
      FromArgument site argument => pure (site.writer, site.within, argument.template, sourceOf site spot)
      InField j _ t => pure (j, j, t, sourceFor j spot)
      ThroughMethod => internal fc "an arc no argument wrote as a type-level recursion"
  ((), place) <- located fc main b spot (((), spot) ::: [((), target)])
  let Just computation = computationThrough (carries source (parameterOf spot)) written
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
  where
    -- What an arc's source is to its writer's template: the parameter it
    -- reads, or the field it takes its value from.
    parameterOf : Spot -> Nat
    parameterOf (OfParameter _ i) = i
    parameterOf (OfField _ k) = k

||| A cause of growth, refused once as rule `polymorphism`. A cycle's growth
||| a round is what its certificate sums: every arc on it is finite, and its
||| gains exceed its losses.
refuse : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         FC -> Name -> (b : Built) -> Cause b.graph -> Front ()
refuse fc main b (Cycle as (Sums ring _ _)) =
  refuseCycle fc main b (around b.graph as ring)
              (minus (gains (labels b.graph as)) (losses (labels b.graph as)))
refuse fc main b (Unbounded a _) = refuseOpaque fc main b a

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
      let bs = boundsOf b pot
      updateState { bounds := bs.atNodes, sizes := sizesOf b bs }
      pure True
    Grows causes => do
      for_ (forget causes) $ \cause => noted (refuse fc main b cause)
      pure False
