-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The graph the growth check decides, built from the program.
|||
||| A position is a static parameter of a node: a definition split by the
||| implementations its dictionary parameters are. The walk over definitions
||| reads what each reachable one writes (its sites), and the walk over nodes
||| follows those sites from main to the nodes they reach. Every argument a
||| site writes lands at a position of its callee, and carries an arc from
||| each position of the writer whose variable it holds, weighed by how much
||| deeper it sits there than it was matched; a field of a dictionary, once
||| its record is built, is carried by the record's variables as deep as the
||| field holds the record's arguments, and a dictionary held in a value by
||| every position of the implementation that built it. A position whose
||| type inspects only so much of its value is capped instead: its one arc
||| comes from nowhere, at the cap. The positions are numbered once, here,
||| which is where a position becomes a `Fin`.
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
import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template
import Libraries.Data.List.Finite

import Control.WellFounded
import Data.DPair
import Data.Fin
import Data.List
import Data.List.Elem
import Data.List.Quantifiers
import Data.Nat
import Data.So
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.Vect

%default total

||| What made an arc: the site and the argument whose template gave it, or
||| an implementation's method field, which placed the implementation's
||| parameter, the arc's source, among the method function's (a leading
||| arc).
public export
data Wrote = FromArgument Site Argument
           | FromField

||| The graph, and what its numbers stand for: the position each `Fin` is,
||| what made each arc, and the sizes the worklist's universe needs beside
||| the bounds.
public export
record Built where
  constructor MkBuilt
  graph : Graph
  ||| What each `Fin` is.
  position : Vect graph.size Position
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
  ||| The heaviest literal or hole token any template holds.
  heaviest : Nat

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
  sites : SortedMap Address (List Site)
  families : SortedMap Address (List Nat)
  datas : List Position
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
constructorArity : {auto c : Ref Ctxt Defs} -> Name -> Front (List Nat)
constructorArity n = do
  defs <- getDefs
  pure $ case definition <$> !(lookupExact n (gamma defs)) of
    Just (DCon _ k _) => [k]
    _ => []

-- What a definition's kind gives the walk: the counts its links' indices run
-- below, and how its reading (its sites and families) and its represented
-- arguments are read. The one switch on the kind, and the problem's: a
-- type constructor alone has constructors, whose fields are sites of the
-- type's, and arguments that are positions of the data it describes; every
-- other definition writes its signature and case tree.
kindOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         Address -> GlobalDef -> Front (List Nat, Front (Reading, List Nat))
kindOf a def = case definition def of
  TCon n _ _ _ _ cons _ => do
    let cs = fromMaybe [] cons
    arities <- traverse constructorArity cs
    pure (n :: length cs :: (arities >>= id), do
            js <- represented def
            fs <- fieldSites a def cs js
            rd <- readingOf a def
            pure ({ sites $= (fs ++) } rd, js))
  PMDef _ params _ => pure ([length params], plain)
  _ => pure ([], plain)
  where
    plain : Front (Reading, List Nat)
    plain = (, []) <$> readingOf a def

-- The definition a site enters, when it names one: a call or a build. A
-- dispatch reaches the method functions of the implementations its
-- dictionary can be, which the walk enters where each implementation is
-- written, since its body applies them.
callee : Reach -> Maybe Address
callee (Calls b) = Just b
callee (Builds b) = Just b
callee (Dispatches _ _ _) = Nothing

-- A definition entered: its sites by its address, its families, its
-- represented arguments as positions of its node with no heads, and its
-- fields, with the definitions its sites name, to enter next. A name that
-- no definition of the context has is no place, and is not entered.
keep : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
       Address -> GlobalDef -> Front (Reading, List Nat) -> Entered -> Front (Entered, List Name)
keep a def reading r = do
  (rd, js) <- reading
  fs <- fieldsOf def
  defs <- getDefs
  let ss = rd.sites
  pure ( { sites $= insert a ss
         , families $= insert a rd.families
         , datas $= (map (\j => (MkNode a [], j)) js ++)
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
  -- What tells definitions apart is their place in the context; a name no
  -- definition has is never entered.
  Just (placement, def) <- core (resolve n)
    | Nothing => level refused w0 acc w p r rest pending
  let a = addressOf placement
  -- Entered already: walked once.
  let Just (Element w1 q) = enter placement w
    | Nothing => level refused w0 acc w p r rest pending
  (counts, reading) <- kindOf a def
  let measured = { breadth $= \b => foldl (\m, k => max m (S k)) b counts } r
  (r', next) <- if contains a refused then pure (the Entered ({ sites $= insert a [] } measured), the (List Name) []) else keep a def reading measured
  level refused w0 acc w1 (thenNoMore (fewer q) p) r' rest (Queued (fewerThen q p) (queued pending <>< next))

definitions : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Name -> Front Entered
definitions main = do
  refused <- (.refused) <$> getState
  level refused start (sizeAccessible start) start (noMore start) (MkEntered empty empty [] empty 0) [main] Idle

------------------------------------------------------------------------------
-- The universe of nodes, and novelty
------------------------------------------------------------------------------

-- Two nodes, as the machine compares their parts: the definition's
-- address by its bytes, then each head by its parameter and its address.
decideNode : (x, y : Node) -> Decided (x = y)
decideNode (MkNode d hs) (MkNode d' hs') = case decideAddress d d' of
  Proof.Growth.No ne => Proof.Growth.No (\Refl => ne Refl)
  Proof.Growth.Yes Refl => case sameList decideHead hs hs' of
    Proof.Growth.No ne => Proof.Growth.No (\Refl => ne Refl)
    Proof.Growth.Yes Refl => Proof.Growth.Yes Refl
  where
    decideHead : (h, h' : (Nat, Address)) -> Decided (h = h')
    decideHead (i, a) (j, b) = case sameNat i j of
      Proof.Growth.No ne => Proof.Growth.No (\Refl => ne Refl)
      Proof.Growth.Yes Refl => case decideAddress a b of
        Proof.Growth.No ne => Proof.Growth.No (\Refl => ne Refl)
        Proof.Growth.Yes Refl => Proof.Growth.Yes Refl

-- A node not yet in a list, with the erased proof.
data IsNew : Node -> List Node -> Type where
  New : (0 _ : Not (Elem x xs)) -> IsNew x xs

-- Whether a node is new to a list: its proof, or nothing when it is there.
novel : (x : Node) -> (xs : List Node) -> Maybe (IsNew x xs)
novel x [] = Just (New (\case _ impossible))
novel x (y :: ys) = case decideNode x y of
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

pairs : List Nat -> List Address -> List (Nat, Address)
pairs is as = flatMap (\i => map (i,) as) is

0 pairsComplete : (is : List Nat) -> (as : List Address) -> Elem i is -> Elem a as -> Elem (i, a) (pairs is as)
pairsComplete (i :: is) as Here ea = elemAppendLeft (elemMap (i,) ea)
pairsComplete (j :: is) as (There ei) ea = elemAppendRight (map (j,) as) (pairsComplete is as ei ea)

-- Every node of at most h heads, each at a parameter below p (erased).
0 Nodes : Listed Address -> (h, p : Nat) -> List Node
Nodes names h p = flatMap (\d => map (MkNode d) (upTo h (pairs (below p) names.values))) names.values

0 flatMapComplete : (f : a -> List b) -> (xs : List a) -> Elem x xs -> Elem y (f x) -> Elem y (flatMap f xs)
flatMapComplete f (x :: xs) Here ey = elemAppendLeft ey
flatMapComplete f (z :: xs) (There ex) ey = elemAppendRight (f z) (flatMapComplete f xs ex ey)

0 headsIn : (names : Listed Address) -> (p : Nat) -> (hs : List (Nat, Address)) -> All (\e => LT (fst e) p) hs ->
            All (\y => Elem y (pairs (below p) names.values)) hs
headsIn names p [] [] = []
headsIn names p ((i, a) :: hs) (lt :: lts) =
  pairsComplete (below p) names.values (belowComplete p lt) (names.complete a) :: headsIn names p hs lts

0 nodeIn : (names : Listed Address) -> (h, p : Nat) -> (x : Node) -> LTE (length x.heads) h ->
           All (\e => LT (fst e) p) x.heads -> Elem x (Nodes names h p)
nodeIn names h p (MkNode d hs) le lts =
  flatMapComplete (\d => map (MkNode d) (upTo h (pairs (below p) names.values))) names.values
    (names.complete d)
    (elemMap (MkNode d) (upToComplete (pairs (below p) names.values) h hs (headsIn names p hs lts) le))

------------------------------------------------------------------------------
-- The nodes
------------------------------------------------------------------------------

-- The room the universe leaves a path (erased).
0 Room : Listed Address -> Nat -> List Node -> Nat
Room names b path = minus (length (Nodes names b b)) (length path)

-- What the walk has found: every node entered, once (a run-time set, no
-- proof: skipping needs none), each with what its sites reach, and each
-- one's reachers, the path it was entered below: the node that first
-- reached it, nearest first, back to main.
record Found where
  constructor MkFound
  entered : SortedSet Node
  done : SnocList (Node, List (Site, Reached))
  reachers : SortedMap Node (List Node)

-- Where the walk over nodes stops, either a broken invariant of the
-- graph's own construction that would lose a node's arcs if the node were
-- skipped: a node outside the universe, split at a head where no site
-- writes one; or a node at heads the flow did not give, with no reading.
data Stray = Outside Node | Unread Node

-- A node of the universe, with its erased membership.
data Inside : Listed Address -> Nat -> Node -> Type where
  In : {0 names : Listed Address} -> {0 b : Nat} -> {0 x : Node} ->
       (0 _ : Elem x (Nodes names b b)) -> Inside names b x

-- Every head at a parameter below b, as the machine compares them.
lowHeads : Nat -> List (Nat, Address) -> Bool
lowHeads b [] = True
lowHeads b ((i, _) :: hs) = i < b && lowHeads b hs

0 lowHeadsSo : (b : Nat) -> (hs : List (Nat, Address)) -> So (lowHeads b hs) -> All (\e => LT (fst e) b) hs
lowHeadsSo b [] _ = []
lowHeadsSo b ((i, _) :: hs) so = let (lt, rest) = soAnd so in Proof.Growth.ltSo lt :: lowHeadsSo b hs rest

-- A node's evidence of being in the universe, or nothing: the machine's
-- comparisons of naturals, read as the erased membership, with no search
-- and no proof built at run time.
inside : (0 names : Listed Address) -> (b : Nat) -> (x : Node) -> Maybe (Inside names b x)
inside names b x = case (choose (length x.heads <= b), choose (lowHeads b x.heads)) of
  (Left short, Left low) => Just (In (nodeIn names b b x (Proof.Growth.lteSo short) (lowHeadsSo b x.heads low)))
  _ => Nothing

-- The walk is depth first, and a node's newness is decided against its own
-- path from main, which is no longer than the walk is deep: one novelty
-- test per node entered, so O(nodes x depth), where a global list with
-- proofs costs a comparison per pair, about 87 million at the self
-- compile's 13,218 nodes (measured). A node met again off its path is
-- skipped by the run-time set, which needs no proof.
mutual
  -- Enters a node new to its path from main: its sites' callees are walked
  -- below it, each new to the longer path, which leaves less room.
  visit : (0 names : Listed Address) -> (b : Nat) -> (out : Node -> Maybe (List (Site, Reached))) ->
          (x : Node) -> (path : List Node) ->
          (0 nd : NoDup (x :: path)) -> (0 inU : All (\y => Elem y (Nodes names b b)) (x :: path)) ->
          (0 acc : Accessible LT (Room names b (x :: path))) -> Found -> Either Stray Found
  visit names b out x path nd inU acc found = case out x of
    Nothing => Left (Unread x)
    Just edges =>
      under names b out x path nd inU acc (map (\(_, e) => e.callee) edges) ({ done $= (:< (x, edges)) } found)

  under : (0 names : Listed Address) -> (b : Nat) -> (out : Node -> Maybe (List (Site, Reached))) ->
          (x : Node) -> (path : List Node) ->
          (0 nd : NoDup (x :: path)) -> (0 inU : All (\y => Elem y (Nodes names b b)) (x :: path)) ->
          (0 acc : Accessible LT (Room names b (x :: path))) -> List Node -> Found -> Either Stray Found
  under names b out x path nd inU acc [] found = Right found
  under names b out x path nd inU acc@(Access rec) (c :: cs) found =
    if contains c found.entered then under names b out x path nd inU acc cs found else
    case inside names b c of
      -- Outside the universe: a head where no site writes one, so that the
      -- node's arcs would be lost if it were skipped.
      Nothing => Left (Outside c)
      Just (In cIn) => case novel c (x :: path) of
        -- On its own path: entered already, so the set holds it.
        Nothing => under names b out x path nd inU acc cs found
        Just (New notIn) =>
          let found' = { entered $= insert c, reachers $= insert c (x :: path) } found in
          case visit names b out c (x :: path) (notIn :: nd) (cIn :: inU)
                 (rec _ (room (notIn :: nd) (cIn :: inU))) found' of
            Left bad => Left bad
            Right after => under names b out x path nd inU acc cs after

nodesFrom : (0 names : Listed Address) -> (b : Nat) -> (out : Node -> Maybe (List (Site, Reached))) -> Node ->
            Either Stray Found
nodesFrom names b out root = case inside names b root of
  Nothing => Left (Outside root)
  Just (In rIn) => visit names b out root [] ((\case _ impossible) :: []) [rIn] (sizeAccessible _)
                     (MkFound (insert root empty) [<] empty)

-- The walk over the real listing, named through an alias on a right-hand
-- side: a lower-case global written in a type is bound as a new implicit.
nodesFromMain : (b : Nat) -> (out : Node -> Maybe (List (Site, Reached))) -> Node -> Either Stray Found
nodesFromMain b out root = let 0 names = addresses in nodesFrom names b out root

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
headBound : SortedMap Address Fields -> List (List Site) -> Nat
headBound fs ss = S (foldl (foldl placedIn) (foldl (foldl written) 0 ss) (values fs))
  where
    written : Nat -> Site -> Nat
    written m s = foldl (\m', x => max m' x.position) m s.arguments

    placedIn : Nat -> Implementations.Field -> Nat
    placedIn m (Method _ _ own leading) = foldl max (foldl (\m', (_, q) => max m' q) m leading) own
    placedIn m (Plain _ _) = m

------------------------------------------------------------------------------
-- The arcs
------------------------------------------------------------------------------

-- An arc between positions, before they are numbered, with what made it.
record Drawn where
  constructor MkDrawn
  from : Position
  to : Position
  label : Label
  wrote : Wrote

-- An argument's arc from a position of its writer: the one match on a
-- weight a template gives, where an Absent weight is no arc. Essential:
-- a template carries a parameter or does not, and only what it carries is
-- an arc.
place : (from, to : Position) -> Site -> Argument -> Weight -> Maybe Drawn
place q p s x Absent = Nothing
place q p s x (Finite g l) = Just (MkDrawn q p (Measured g l) (FromArgument s x))
place q p s x Stuck = Just (MkDrawn q p Unmeasured (FromArgument s x))

-- A held dictionary's write (the projection rule): an arc from every
-- position of every node of the root J that built it into the position
-- the argument is written at, at its weight. J's positions are known only
-- once every arc is placed.
record Projection where
  constructor MkProjection
  root : Address
  to : Position
  weight : Weight
  site : Site
  argument : Argument

-- What the walked edges' arguments write, before the positions are
-- numbered: the arcs drawn, the projection writes, and K, A and L.
record Raw where
  constructor MkRaw
  drawn : List Drawn
  projections : List Graph.Projection
  constant : Nat
  arity : Nat
  heaviest : Nat

-- What a field adds to K: a Finite field's gain, its depth plus one. A
-- Stuck one's arcs are causes of their own, and bound nothing.
gain : Weight -> Maybe Nat
gain (Finite g _) = Just g
gain Absent = Nothing
gain Stuck = Nothing

-- What a template's fields carry once their records are built (a key
-- holds a projection reduced when its record is a constructor, as
-- `implementationOf` and a type's normal form reduce it): the arcs from the
-- writer's parameters, the held dictionaries' roots with their weights,
-- and what they add to K.
record Carried where
  constructor MkCarried
  arcs : List (Nat, Weight)
  held : List (Address, Weight)
  constant : Nat

none : Carried
none = MkCarried [] [] 0

both : Carried -> Carried -> Carried
both x y = MkCarried (x.arcs ++ y.arcs) (x.held ++ y.held) (max x.constant y.constant)

-- The template of field k of a dictionary rooted at an implementation or
-- a constructor, over its parameters.
fieldTemplate : SortedMap Address Fields -> Nat -> Address -> Maybe Template
fieldTemplate fs k r = fst . fieldRead <$> fieldAt fs r k

-- How deep a field's template holds a parameter of its dictionary: the
-- most, over its variables, or Absent for a closed field.
holding : Template -> Weight
holding t = foldr join Absent (map snd (weights t))

mutual
  -- A field's value, field k of the record s at the depth weight d (one
  -- more than the heads above it): the field's
  -- template over the record's arguments, so a parameter of the record's
  -- root that the field holds D deep lies D - 1 below where the record's
  -- own parts lie, under the record's head (one below a constructor's
  -- field, which is a part of it). So each variable of s is carried D - 1
  -- deeper than s writes it, its fields likewise, and K covers the
  -- field's closed parts. A record no implementation or constructor roots
  -- has no field to reduce to: the key keeps the projection as written.
  fieldValue : SortedMap Address Fields -> Flow -> Node -> (d : Weight) -> (k : Nat) -> Template -> Carried
  fieldValue fs fl w d k s =
    let ts = mapMaybe (fieldTemplate fs k) (roots fl w s)
        deep = foldr join Absent (map holding ts)
        here = plus d (plus deep (Finite 0 2))
        own = MkCarried (map (\(i, wt) => (i, plus here wt)) (weights s)) [] 0
        closed = maybe 0 (\e => minus e 1 + foldl max 0 (map height ts)) (gain d) in
    both own (both ({ constant $= max closed } none) (carriedAt fs fl w (plus d (plus deep (Finite 0 1))) s))

  -- Every field's and held dictionary's value in a template, at the depth
  -- weight its root's position gives a field: Finite e+1 at e heads deep,
  -- Stuck under an Opaque or an applied family. A field of a field is
  -- reached through the outer one's record.
  carriedAt : SortedMap Address Fields -> Flow -> Node -> Weight -> Template -> Carried
  carriedAt fs fl w d (Template.Field k s) = fieldValue fs fl w d k s
  carriedAt fs fl w d t@(Held _ _) =
    MkCarried [] (map (, d) (roots fl w t)) (fromMaybe 0 (gain d))
  carriedAt fs fl w d (Head _ ts) = carriedAll fs fl w (plus d (Finite 1 0)) ts
  carriedAt fs fl w d (Opaque _ ts) = carriedAll fs fl w Growth.Stuck ts
  carriedAt fs fl w d (Applied _ _ ts) = carriedAll fs fl w Growth.Stuck ts
  carriedAt fs fl w d (Computing _ _ ts) = carriedAll fs fl w Growth.Stuck ts
  carriedAt fs fl w d (Choice _ ts) = carriedAll fs fl w d ts
  carriedAt fs fl w d (Var _ _) = none
  carriedAt fs fl w d (Leaf _) = none
  carriedAt fs fl w d (Template.Token _) = none
  carriedAt fs fl w d (Formal _ _) = none

  carriedAll : SortedMap Address Fields -> Flow -> Node -> Weight -> List Template -> Carried
  carriedAll fs fl w d [] = none
  carriedAll fs fl w d (t :: ts) = both (carriedAt fs fl w d t) (carriedAll fs fl w d ts)

-- What lands at one position twice: a value that computes, closed values
-- no higher than the taller height, closed values some of which compute,
-- or values not all closed. A closed inert value's term is not kept, so
-- with closed computing ones beside it the position is evaluated at none.
landed : Landing -> Landing -> Landing
landed Computed _ = Computed
landed _ Computed = Computed
landed (Evaluable a) (Evaluable b) = Evaluable (a ++ b)
landed (Evaluable _) _ = Computed
landed _ (Evaluable _) = Computed
landed (Closed a) (Closed b) = Closed (max a b)
landed _ _ = Open

-- What an argument is, landing: a choice of implementation made at run
-- time (a rank-2 dictionary, a computed one), which an application of it
-- does not beta-reduce but gives one of its members of, so it lands as a
-- value no closed reading bounds; a closed value that computes (`beta`),
-- which is its term; any other that computes; a closed one no higher than
-- its height; or one whose height an arc carries.
landingOf : Argument -> Landing
landingOf x = case x.root of
  Members _ => Open
  _ => case (beta x.template, selfBounded x.template, x.term) of
    (Computes, True, Just tm) => Evaluable [tm]
    (Computes, _, _) => Computed
    (Inert, True, _) => Closed (height x.template)
    (Inert, False, _) => Open

-- The walked edges' one traversal, which every reading of what they place
-- shares: each argument placed, in the walk's order, with the node whose
-- site wrote it, the site, and the callee node it lands at.
eachPlaced : (r -> Node -> Site -> Node -> Placed -> r) -> r -> List (Node, List (Site, Reached)) -> r
eachPlaced f = foldl (\acc, (w, edges) => foldl (\acc', (s, e) => foldl (\acc'', pl => f acc'' w s e.callee pl) acc' e.placed)
                                                acc edges)

-- Each method function's node a dispatch reached through implementation
-- J's method field k, with where that field places J's parameters among
-- the method function's, once however many dispatches reach it.
Leads : Type
Leads = SortedMap (Node, Address, Nat) (List (Nat, Nat))

leadsOf : List (Node, List (Site, Reached)) -> Leads
leadsOf walked = foldl (\m, (_, edges) => foldl lead m edges) empty walked
  where
    lead : Leads -> (Site, Reached) -> Leads
    lead m (_, e) = case e.via of
      Dispatched j k leading => insert (e.callee, j, k) leading m
      -- Essential: a call or a build places no implementation's parameters.
      Called => m

-- The positions of the method functions' nodes that leading placements
-- fill.
leadingPositions : Leads -> List Position
leadingPositions leads = SortedMap.toList leads >>= \((m, _, _), pqs) => map (\(_, q) => (m, q)) pqs

-- A value landing at a position, with what landed there before.
put : Position -> Landing -> SortedMap Position Landing -> SortedMap Position Landing
put p l m = insert p (maybe l (landed l) (lookup p m)) m

-- What lands at each position an argument is placed at, as written there:
-- its keys are the positions the arguments name.
written : List (Node, List (Site, Reached)) -> SortedMap Position Landing
written = eachPlaced (\m, _, _, callee, pl => put (callee, pl.parameter) (landingOf pl.argument) m) empty

-- Where a writer no template states lands as well, so nothing there is
-- closed: at a leading arc's position, what J's own writers gave J; at a
-- capped position, every value of the cap's height.
opened : List Position -> SortedMap Position Landing -> SortedMap Position Landing
opened ps m = foldl (\acc, p => put p Open acc) m ps

-- Where each numbered position carries a family's value on, keyed by the
-- source's number and by the target's: from each position of the writer
-- whose family an argument passes on or applies (`familiesIn`), into the
-- argument's position; and from each position of an implementation J,
-- into the method function's position its leading placement gives, from
-- every walked node of J, which can only carry more. A position where
-- nothing lands has no number, and nothing computing to carry.
record Carries (n : Nat) where
  constructor MkCarries
  onward : SortedMap Nat (List (Fin n))
  back : SortedMap Nat (List (Fin n))

carried : {0 n : Nat} -> SortedMap Position (Fin n) -> SortedMap Address (List Node) -> Leads ->
          List (Node, List (Site, Reached)) -> Carries n
carried number nodes leads walked =
  let cs = eachPlaced (\acc, w, _, callee, pl =>
                         foldl (\acc', i => carry (w, i) (callee, pl.parameter) acc') acc (familiesIn pl.argument.template))
                      (MkCarries empty empty) walked in
  foldl (\acc, ((callee, j, _), pqs) =>
           foldl (\acc', (p, q) => foldl (\acc'', x => carry (x, p) (callee, q) acc'') acc' (fromMaybe [] (lookup j nodes)))
                 acc pqs)
        cs (SortedMap.toList leads)
  where
    add : Fin n -> Fin n -> SortedMap Nat (List (Fin n)) -> SortedMap Nat (List (Fin n))
    add a b m = insert (finToNat a) (b :: fromMaybe [] (lookup (finToNat a) m)) m

    carry : Position -> Position -> Carries n -> Carries n
    carry p q cs = case (lookup p number, lookup q number) of
      (Just a, Just b) => MkCarries (add a b cs.onward) (add b a cs.back)
      _ => cs

-- The numbered positions an applied family's reading reads the landing
-- of (`applyingIn`), at the nodes whose sites apply it.
applying : {0 n : Nat} -> SortedMap Position (Fin n) -> List (Node, List (Site, Reached)) -> List (Fin n)
applying number = eachPlaced (\acc, w, _, _, pl => mapMaybe (\i => lookup (w, i) number) (applyingIn pl.argument.template) ++ acc) []

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
-- (`written`, `opened`), with a computing value carried on to every
-- position that carries a family's value on from where one lands: a
-- family whose value can be one there may compute when it is applied,
-- wherever the value was written. Only a position an applied family's
-- reading reads, or one that carries on to it, is asked, so the carrying
-- runs over those alone: a type's marker passed on carries no family, and
-- nothing applies it. With no computing value written there is nothing to
-- carry.
landings : SortedMap Address (List Node) -> Leads -> List (Node, List (Site, Reached)) ->
           SortedMap Position Landing -> SortedMap Position Landing
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

-- At node w, what lands at each parameter (`Landing`); nothing landed is
-- no closed value.
closedAt : SortedMap Position Landing -> Node -> Nat -> Landing
closedAt ls w i = fromMaybe Open (lookup (w, i) ls)

-- An argument written by a site of node w, landing at `at` in the callee,
-- read where w's families hold what lands at them (`withClosedFamilies`).
-- Every variable of it gets the arc `weights` gives it, the largest e - d
-- over its occurrences, so that every occurrence is carried by an arc at
-- least that heavy; every field's value is carried by its record's variables
-- (`fieldValue`), and a held dictionary by every position of the
-- implementation that built it (the projection rule). K covers its height
-- and every field's closed parts, A its widest node and L its heaviest
-- token, whatever the callee: a capped target's template still counts.
argument : SortedMap Address Fields -> Flow -> SortedMap Position Landing -> Node -> Site -> Position -> Argument -> Raw -> Raw
argument fs fl ls w s at arg r =
  let t = withClosedFamilies (closedAt ls w) arg.template
      c = carriedAt fs fl w (Finite 1 0) t in
  { drawn $= (mapMaybe (\(i, wt) => place (w, i) at s arg wt) (weights t) ++
              mapMaybe (\(i, wt) => place (w, i) at s arg wt) c.arcs ++)
  , projections $= (map (\(root, wt) => MkProjection root at wt s arg) c.held ++)
  , constant $= \k => max (max k (height t)) c.constant
  , arity $= max (Template.arity t)
  , heaviest $= max (Template.heaviest t) } r

-- The leading arcs of a dispatch that reached M through implementation
-- J's method field. The parameters of M its `leading` placement names
-- hold J's own, which the writers of J gave it, so each walked node of J
-- whose heads agree with M's there feeds M's position q from its own
-- position p, unchanged. J's own call of M passes its method dictionaries
-- as run-time values, with no roots, and reaches another node of M, so
-- without these M's leading positions would have no arc into them.
leadingArcs : SortedMap Address (List Node) -> (m : Node) -> (j : Address) -> List (Nat, Nat) -> List Drawn
leadingArcs nodes m j leading =
  [ MkDrawn (jn, p) (m, q) (Measured 0 0) FromField
  | jn <- fromMaybe [] (lookup j nodes), agrees jn, (p, q) <- leading ]
  where
    -- Two heads at a parameter agree: none on either side, or one
    -- implementation on both. A dictionary without a root has no head.
    agreesAt : Node -> (Nat, Nat) -> Bool
    agreesAt jn (p, q) = case sameMaybe decideAddress (lookup p jn.heads) (lookup q m.heads) of
      Proof.Growth.Yes _ => True
      Proof.Growth.No _ => False

    agrees : Node -> Bool
    agrees jn = all (agreesAt jn) leading

-- Every walked edge's arguments, each at the callee parameter `reaches`
-- placed it at, and the leading arcs of every method function's node a
-- dispatch reached.
raw : SortedMap Address Fields -> Flow -> SortedMap Position Landing -> SortedMap Address (List Node) -> Leads ->
      List (Node, List (Site, Reached)) -> Raw
raw fs fl ls nodes leads walked =
  let r = eachPlaced (\acc, w, s, callee, pl => argument fs fl ls w s (callee, pl.parameter) pl.argument acc)
                     (MkRaw [] [] 0 0 0) walked in
  { drawn $= ((SortedMap.toList leads >>= \((m, j, _), leading) => leadingArcs nodes m j leading) ++) } r

------------------------------------------------------------------------------
-- Positions, caps and the numbering
------------------------------------------------------------------------------

-- Things by the definition they are of.
byDefinition : (a -> Address) -> List a -> SortedMap Address (List a)
byDefinition key = foldr (\x => insertWith (++) (key x) [x]) empty

-- An arc's ends.
ends : Drawn -> List Position
ends pl = [pl.to, pl.from]

-- Each of the positions that is capped, with its cap. A cap is asked once
-- per definition and parameter, since a definition's nodes share its type.
capsOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         List Position -> Front (SortedMap Position Nat)
capsOf named = snd <$> foldlM ask (empty, empty) named
  where
    ask : (SortedMap (Address, Nat) (Maybe Nat), SortedMap Position Nat) -> Position ->
          Front (SortedMap (Address, Nat) (Maybe Nat), SortedMap Position Nat)
    ask (memo, capped) p@(n, j) = do
      cap <- maybe (capOf n.definition j) pure (lookup (n.definition, j) memo)
      pure (insert (n.definition, j) cap memo, maybe capped (\k => insert p k capped) cap)

-- An arc with its ends numbered; nothing when an end has no number.
numbered : SortedMap Position (Fin n) -> Drawn -> Maybe (Arc n, Wrote)
numbered index pl = do
  to <- lookup pl.to index
  from <- lookup pl.from index
  pure (MkArc from to pl.label, pl.wrote)

-- What made each arc, in the arcs' order.
wrotes : (arcs : List (Arc n, Wrote)) -> Vect (length (map Builtin.fst arcs)) Wrote
wrotes arcs = rewrite lengthMap {f = Builtin.fst} arcs in
              rewrite sym (lengthMap {f = Builtin.snd} arcs) in
              Vect.fromList (map snd arcs)

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
-- are every node the walk can meet, which the walk checks (`Unread`).
readings : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           Flow -> Entered -> Front (SortedMap Node (List Site))
readings fl r = foldlM family plain (SortedMap.toList r.families)
  where
    plain : SortedMap Node (List Site)
    plain = SortedMap.fromList (map (\(a, ss) => (MkNode a [], ss)) (SortedMap.toList r.sites))

    headed : Address -> SortedMap Node (List Site) -> List (Nat, Address) -> Front (SortedMap Node (List Site))
    headed a m hs = (\ss => insert (MkNode a hs) ss m) <$> sitesOf a hs

    family : SortedMap Node (List Site) -> (Address, List Nat) -> Front (SortedMap Node (List Site))
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
-- 0` whose parameter the list names is that value.
mutual
  givenFamilies : List (Nat, ClosedTerm) -> TT vs -> TT vs
  givenFamilies ms tm@(Ref _ _ n) = case Template.markerOf n of
    Just (i, Z) => maybe tm embedClosed (lookup i ms)
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
||| written: the arc it draws is the one the check refuses.
evaluated : {auto c : Ref Ctxt Defs} -> SortedMap Position Landing ->
            List (Node, List (Site, Reached)) -> Front (List (Node, List (Site, Reached)))
evaluated ls = traverse (\(w, edges) => (w,) <$> traverse (\(st, e) => (st,) <$> reachedAt w e) edges)
  where
    -- One closed reading of an argument at a choice of values: nothing
    -- when the reading still holds a marker or applies a family.
    readingAt : Argument -> ClosedTerm -> List (Nat, ClosedTerm) -> Front (Maybe Argument)
    readingAt x tm given = do
      read <- readArgument x.position x.kind !(normaliseClosed (givenFamilies given tm)) x.shown
      pure (if selfBounded read.template then Just read else Nothing)

    evaluate : Node -> Argument -> Front (List Argument)
    evaluate w x = case (x.term, applyingIn x.template) of
      (Just tm, fs@(_ :: _)) => case traverse (\i => (i,) <$> evaluable (closedAt ls w i)) (nub fs) of
        Nothing => pure [x]
        Just values => do
          reads <- traverse (readingAt x tm) (choices values)
          pure (fromMaybe [x] (sequence reads))
      _ => pure [x]

    reachedAt : Node -> Reached -> Front Reached
    reachedAt w e = do
      placed <- traverse (\pl => map (\x => the Placed ({ argument := x } pl)) <$> evaluate w pl.argument) e.placed
      pure ({ placed := concat placed } e)

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
  Just (placement, mainDef) <- core (resolve main)
    | Nothing => internal EmptyFC "the growth graph's main has no definition"
  let fc = location mainDef
  let root = addressOf placement
  entered <- definitions main
  -- Lists are joined by bind, which is linear: base's `concat` and
  -- `concatMap` on a list fold `++` from the left, so every join copies
  -- what came before, the square of the length in all.
  let fl = flow entered.fields (values entered.sites >>= id)
  reads <- readings fl entered
  -- Every node met has its reading (`readings`): one without would lose
  -- the arcs its sites write.
  let out : Node -> Maybe (List (Site, Reached))
      out x = (\ss => [(s, r) | s <- ss, r <- reaches fl x s]) <$> SortedMap.lookup (readAt entered.families x) reads
  let Right found = nodesFromMain (headBound entered.fields (values reads)) out (MkNode root [])
    | Left (Outside x) => do
        n <- nameOf x.definition
        internal fc ("the growth graph met a node split at a parameter no site writes: " ++ n)
    | Left (Unread x) => do
        n <- nameOf x.definition
        internal fc ("the growth graph met a node at heads its flow did not give: " ++ n)
  let walked0 = found.done <>> []
  let nodes = byDefinition (.definition) (map fst walked0)
  let leads = leadsOf walked0
  -- The positions the arguments name, with what lands at each.
  let placed0 = written walked0
  -- A capped position takes no arc: its cap, which the graph holds and a
  -- feasible potential meets, stands for every value of its height, so no
  -- listed site targets it. A position only a data type's arguments give
  -- is a type argument, which no cap applies to.
  capped <- capsOf (keys placed0)
  let lands0 = landings nodes leads walked0 (opened (leadingPositions leads ++ keys capped) placed0)
  -- What a family given only closed values computes, evaluated at each.
  walked <- evaluated lands0 walked0
  let placed = written walked
  let lands = landings nodes leads walked (opened (leadingPositions leads ++ keys capped) placed)
  let r = raw entered.fields fl lands nodes leads walked
  -- The positions: every place an argument lands, every end of an arc, and
  -- every represented argument of a reachable data type.
  let positions = SortedSet.fromList (keys placed ++ (r.drawn >>= ends) ++ entered.datas)
  let byPosition = byDefinition (\p => (fst p).definition) (Prelude.toList positions)
  let projected = r.projections >>= \pr => mapMaybe (\q => place q pr.to pr.site pr.argument pr.weight)
                                                     (fromMaybe [] (lookup pr.root byPosition))
  let arcs = filter (\pl => isNothing (lookup pl.to capped)) (r.drawn ++ projected)
  -- The one numbering: the positions in order, each once, and each arc's
  -- ends looked up in it.
  let ps = Prelude.toList positions
  let position = Vect.fromList ps
  let index = SortedMap.fromList (zip ps (indices ps))
  -- Every end was made a position above, so a miss is a broken invariant
  -- of this function; it stays because a map's lookup gives no evidence of
  -- membership.
  let Just numberedArcs = traverse (numbered index) arcs
    | Nothing => internal fc "the growth graph lost a position it numbered"
  pure (MkBuilt (MkGraph (length ps) (map fst numberedArcs) r.constant (map (\p => lookup p capped) position))
                position (wrotes numberedArcs) r.arity found.reachers entered.breadth r.heaviest)
