-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Which implementations a dictionary can be, and which type constructors
||| head a family, so that the growth graph can split each definition by
||| the implementations its dictionary arguments hold and the type
||| constructors its families are, as the translation's requests are keyed
||| by them.
|||
||| Without the split, every call of a definition that takes a dictionary
||| meets in one node, and a dispatch from that node reaches the methods of
||| every implementation any caller passed: a mapping over `EitherT e IO`
||| and one over `IO` share `(<$>)`, and `EitherT`'s `map` then seems to
||| call itself at a bigger type, though its `(<$>)` only ever runs `IO`'s.
||| Split, a node is a definition and the implementation at the root of each
||| dictionary argument, and the cycle no instance has is gone.
|||
||| The roots come from Core, as `dictionaryRoot` computed them for each
||| site's dictionary argument and each implementation's field. What Core
||| cannot root here is the writer's own dictionary parameter, whose root is
||| whatever its caller passed. In the split, that is the head of the
||| writer's node: so the merge above cannot be represented. One fact still
||| needs the whole program, what a dictionary held in a field or matched
||| out of a value can be, and the flow answers it: the least sets of
||| implementations reaching each parameter and field, over the unsplit
||| definitions.
|||
||| The flow and the split read a dictionary the same way, through one
||| function, and differ only in how the writer's own parameter reads: the
||| flow's set at its slot, or the node's head there. A dictionary parameter
||| with no head holds a function that gives an implementation at each use
||| (a rank-2 dictionary, `Gives`): a callee given it is given it as
||| written and keyed by nothing, and a dispatch through it reads the
||| flow's set, so it reaches every member's method.
|||
||| A family (a type parameter whose kind is a function into a universe:
||| `tm : Scope -> Type`, a functor's `f`) splits its definition the same
||| way, by the type constructor at its value's head, so that a definition
||| whose kinds depend on what its family is (`Env tm vars` over `Term`,
||| whose index erases what a marker would keep) is read once per head
||| (`Sites.sitesOf`). A family's root is only ever its type root, never
||| read off a template: a lambda heads nothing.
|||
||| Everything here is pure: the sites and the implementations' fields come
||| in as data, made where Core is.
module IdrisMLIR.Frontend.Growth.Heads

import IdrisMLIR.Frontend.Finite
import IdrisMLIR.Frontend.Growth.Implementations
import IdrisMLIR.Frontend.Growth.Sites
import IdrisMLIR.Frontend.Growth.Template
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template

import Libraries.Data.List.Finite

import Control.Relation
import Control.WellFounded
import Data.Fin
import Data.List
import Data.List.Elem
import Data.List1
import Data.List.Quantifiers
import Data.Nat
import Data.So
import Data.SortedMap
import Data.SortedSet
import Data.Vect
import Decidable.Equality

%default total

------------------------------------------------------------------------------
-- Slots
------------------------------------------------------------------------------

-- Where a dictionary can flow: parameter j of a definition or constructor
-- (kind 0), or field k of an implementation or constructor (kind 1). The
-- index is written as an address too, so that a slot is a triple of finite
-- types and every pair of the solution lies in one finite type, whose
-- listing the fork supplies. There is no numbering pass, so no lookup of a
-- slot can miss. An index is a parameter or field count's, far below 2^63,
-- so distinct indices are distinct addresses.
Slot : Type
Slot = (Fin 2, Address, Address)

-- One fact of the solution: this implementation reaches this slot.
Entry : Type
Entry = (Slot, Address)

parameterSlot : Address -> Nat -> Slot
parameterSlot a j = (0, a, bytes 8 (cast j))

fieldSlot : Address -> Nat -> Slot
fieldSlot a k = (1, a, bytes 8 (cast k))

-- Novelty compares an address by its bytes' numbers (`decideAddress`), a
-- step per byte. Equality decided by matching `Fin` constructors walks
-- each byte's whole value.
sameBytes : (a, b : Address) -> Dec (a = b)
sameBytes a b = case decideAddress a b of
  Proof.Growth.Yes Refl => Yes Refl
  Proof.Growth.No ne => No (\eq => void (ne eq))

sameKind : (i, j : Fin 2) -> Dec (i = j)
sameKind FZ FZ = Yes Refl
sameKind (FS FZ) (FS FZ) = Yes Refl
sameKind FZ (FS _) = No absurd
sameKind (FS _) FZ = No absurd

-- Any order decides. The definition comes first: the self compile's flow
-- holds 1,723 entries over 661 slots (measured on the prototype), so two
-- entries of the seen list almost always differ there.
same : (x, y : Entry) -> Dec (x = y)
same ((k, d, i), h) ((k', d', i'), h') =
  case sameBytes d d' of
    No ne => No (\Refl => ne Refl)
    Yes Refl => case sameBytes h h' of
      No ne => No (\Refl => ne Refl)
      Yes Refl => case sameBytes i i' of
        No ne => No (\Refl => ne Refl)
        Yes Refl => case sameKind k k' of
          No ne => No (\Refl => ne Refl)
          Yes Refl => Yes Refl

-- Named, so that base's list search decides by `same` and no other
-- equality on entries is ever chosen.
[bytewise] DecEq Entry where
  decEq = same

isNew : (x : Entry) -> (seen : List Entry) -> Dec (Elem x seen)
isNew = isElem @{bytewise}

------------------------------------------------------------------------------
-- Reading a dictionary
------------------------------------------------------------------------------

-- The solution so far, as each slot's set: a view of the seen list, rebuilt
-- from it, never a second state.
View : Type
View = SortedMap Slot (SortedSet Address)

at : View -> Slot -> SortedSet Address
at v s = fromMaybe empty (lookup s v)

viewOf : List Entry -> View
viewOf = foldl (\v, (s, a) => insert s (insert a (at v s)) v) empty

-- How the writer's own parameters read, the one place the flow and the
-- split differ: parameter i's marker, and the marker applied. A dictionary
-- parameter applied is a function that gives an implementation at each use
-- (a rank-2 dictionary), so it gives what the parameter can be; a family
-- applied is beta of its value, which no implementation is, so reading the
-- type constructors that head it would draw arcs from positions no value
-- of it comes from. The flow and the split read Core's root first, which
-- roots an applied marker as its parameter (`Template.rootOf`), and their
-- readings give an applied marker nothing of its own (`markersOnly`); the
-- growth theorem's model reads a template alone (`roots`), so it reads it.
record Own where
  constructor MkOwn
  ofMarker : Nat -> SortedSet Address
  ofApplied : Nat -> SortedSet Address

-- A reading whose applied markers give nothing: where Core's root answers
-- for every applied marker.
markersOnly : (Nat -> SortedSet Address) -> Own
markersOnly reading = MkOwn reading (const empty)

mutual
  -- The roots a template's structure gives, where Core named none. A head
  -- written in it is never read as a root: a root is only ever Core's (the
  -- second component of a pair has its own root, not the pair's
  -- constructor). A field of a dictionary is the field's slot for each root
  -- of the dictionary: only the field's own equation writes that slot, so
  -- for a field that names an implementation the slot is that one, and a
  -- field that is one of the implementation's own variables brings in what
  -- its writers gave it. So a projection of the writer's dictionary goes
  -- through the writer's head, never through every implementation that
  -- reaches the projection's target.
  byTemplate : View -> Own -> Template -> SortedSet Address
  byTemplate v own (Var i Z) = own.ofMarker i
  byTemplate v own (Var _ (S _)) = empty
  byTemplate v own (Field k s) =
    foldl (\acc, j => union acc (at v (fieldSlot j k))) empty (Prelude.toList (byTemplate v own s))
  byTemplate v own (Held c p) = at v (parameterSlot c p)
  byTemplate v own (Choice _ leaves) = byLeaves v own leaves
  byTemplate v own (Head _ _) = empty
  byTemplate v own (Leaf _) = empty
  byTemplate v own (Token _) = empty
  byTemplate v own (Formal _ _) = empty
  byTemplate v own (Opaque _ _) = empty
  byTemplate v own (Applied i Z _) = own.ofApplied i
  -- A part matched out of a value is a runtime part, which a pattern binds
  -- and nothing applies as a dictionary.
  byTemplate v own (Applied _ (S _) _) = empty
  -- Met in the graph's field values, whose records are parts of a
  -- template read at a node (`withClosedFamilies`).
  byTemplate v own (Computing _ _ _) = empty

  byLeaves : View -> Own -> List Template -> SortedSet Address
  byLeaves v own [] = empty
  byLeaves v own (t :: ts) = union (byTemplate v own t) (byLeaves v own ts)

-- A dictionary with the root Core gave it. A parameter matched deeper, or
-- no root (a projection of what no constructor builds), says nothing of
-- its own, and the template decides.
byRoot : View -> Own -> Root -> Template -> SortedSet Address
byRoot v own (Rooted j) _ = singleton j
byRoot v own (Members js) _ = fromList (forget js)
byRoot v own (Gives js) _ = fromList (forget js)
byRoot v own (Parameter i Z) _ = own.ofMarker i
byRoot v own (Parameter _ (S _)) t = byTemplate v own t
byRoot v own Unrooted t = byTemplate v own t

-- A family by its type root: the type constructor there, or the writer's
-- own family there. A family no type constructor heads splits nothing.
byFamily : Own -> Root -> SortedSet Address
byFamily own (Rooted j) = singleton j
byFamily own (Members _) = empty
byFamily own (Gives _) = empty
byFamily own (Parameter i Z) = own.ofMarker i
byFamily own (Parameter _ (S _)) = empty
byFamily own Unrooted = empty

-- How an argument splits the definition it lands at: a dictionary by the
-- implementations it can be, a family by the type constructors that can
-- head it. Any other kind splits nothing.
data Splitting = ByImplementation | ByTypeConstructor

splitting : Static -> Maybe Splitting
splitting ADictionary = Just ByImplementation
splitting AFamily = Just ByTypeConstructor
splitting AType = Nothing
splitting AForm = Nothing
splitting AShape = Nothing

-- What an argument that splits can be, written in a writer whose own
-- parameters read as `own`.
byArgument : View -> Own -> Splitting -> Argument -> SortedSet Address
byArgument v own ByImplementation x = byRoot v own x.root x.template
byArgument v own ByTypeConstructor x = byFamily own x.root

-- What an argument keys its callee by, at the call: what it can be, but
-- nothing for a function that gives an implementation at each use
-- (`Gives`), which the callee is given as written, one instance of it
-- taking every member.
keyedBy : View -> Own -> Splitting -> Argument -> SortedSet Address
keyedBy v own how x = case (how, x.root) of
  (ByImplementation, Gives _) => empty
  _ => byArgument v own how x

-- The arguments a site passes that split their callee, each with how.
splitters : Site -> List (Splitting, Argument)
splitters s = mapMaybe (\x => (, x) <$> splitting x.kind) s.arguments

-- The method function an implementation's field k is, with where the
-- method's own arguments and the implementation's parameters land among
-- its parameters. A plain field (a superclass dictionary, or one of an
-- interface constructor's own variables) has none, so a dispatch through
-- it reaches nothing.
methodAt : SortedMap Address Fields -> Address -> Nat -> Maybe (Address, List Nat, List (Nat, Nat))
methodAt fs j k = case fieldAt fs j k of
  Just (Method m _ own leading) => Just (m, own, leading)
  _ => Nothing

||| An argument of a site and the callee parameter it lands at.
public export
record Placed where
  constructor MkPlaced
  argument : Argument
  parameter : Nat

-- A call's and a build's arguments are the callee's parameters themselves.
atOwnPositions : List Argument -> List Placed
atOwnPositions = map (\x => MkPlaced x x.position)

-- A dispatch's arguments are the method's own, which a method function
-- does not take first: its own implicit type variables come before the
-- implementation's parameters. The field's wrapper places each one, by
-- the argument's position among the method's own.
placedAt : List Nat -> Argument -> List Nat
placedAt own x = Prelude.toList (head' (drop x.position own))

placedBy : List Nat -> List Argument -> List Placed
placedBy own xs = xs >>= \x => map (MkPlaced x) (placedAt own x)

------------------------------------------------------------------------------
-- The flow
------------------------------------------------------------------------------

-- What the flow asks of each site and field, read once. `Into` says the
-- slot holds every root of this dictionary, written in this definition:
-- an implementation's field, at the field. `Passes` says the callee's
-- parameter holds what this argument can be, written in this definition:
-- a call's dictionary or family. `Through` says the function of method k
-- of this dictionary, written in this definition, holds what these
-- arguments give, at the parameters the method's field places them at.
data Equation = Into Slot Address Root Template
              | Passes Slot Address Splitting Argument
              | Through Address Root Template Nat (List (Splitting, Argument))

-- Writing `J u` reaches J's parameters through the call of J, and J's
-- method functions' leading parameters through J's own calls of them,
-- which pass its parameters: no equation of its own.
equations : SortedMap Address Fields -> List Site -> List Equation
equations fs ss = (ss >>= fromSite) ++ (Data.SortedMap.toList fs >>= fromFields)
  where
    argument : Address -> Address -> (Splitting, Argument) -> Equation
    argument t w (how, x) = Passes (parameterSlot t x.position) w how x

    fromSite : Site -> List Equation
    fromSite s = case s.reach of
      Calls t => map (argument t s.writer) (splitters s)
      Builds _ => []
      Dispatches t r k => [Through s.writer r t k (splitters s)]
      -- The application keys no definition's slot: what it applies is its
      -- own.
      Applies => []

    numbered : Address -> Nat -> List Field -> List Equation
    numbered j k [] = []
    numbered j k (field :: rest) = let (t, r) = fieldRead field in Into (fieldSlot j k) j r t :: numbered j (S k) rest

    fromFields : (Address, Fields) -> List Equation
    fromFields (j, fields) = numbered j 0 fields

-- Every entry the equations give under the solution so far. A set, since
-- the sites give each entry many times, and each is searched for in the
-- seen list once. Lists are joined by bind, which is linear: base's
-- `concatMap` on a list folds `++` from the left, quadratic in the length.
candidates : SortedMap Address Fields -> View -> List Equation -> SortedSet Entry
candidates fs v eqs = fromList (eqs >>= yield)
  where
    own : Address -> Own
    own w = markersOnly (\i => at v (parameterSlot w i))

    into : Slot -> SortedSet Address -> List Entry
    into s js = map (s,) (Prelude.toList js)

    yield : Equation -> List Entry
    yield (Into s w r t) = into s (byRoot v (own w) r t)
    yield (Passes s w how x) = into s (byArgument v (own w) how x)
    yield (Through w r t k xs) = do
      j <- Prelude.toList (byRoot v (own w) r t)
      case methodAt fs j k of
        Nothing => []
        Just (m, own', _) => do
          (how, x) <- xs
          p <- placedAt own' x
          into (parameterSlot m p) (byArgument v (own w) how x)

-- Whether a round grew the seen list: if it did, the room left in the
-- listing is below the round's start, and otherwise it is the start.
data Change : (left, start : Nat) -> Type where
  Grew : (0 _ : LT left start) -> Change left start
  Kept : (0 _ : left = start) -> Change left start

-- The seen list after a round's candidates, and whether it grew.
record Drained (0 u : List Entry) (0 room0 : Nat) where
  constructor MkDrained
  seen : List Entry
  0 nd : NoDup seen
  change : Change (minus (length u) (length seen)) room0

0 inside : ((x : Entry) -> Elem x u) -> (xs : List Entry) -> All (\y => Elem y u) xs
inside complete [] = []
inside complete (x :: xs) = complete x :: inside complete xs

-- A drain from one more kept entry, whose start has less room, is a drain
-- that grew.
grown : Drained u r' -> (0 _ : LT r' r) -> Drained u r
grown (MkDrained seen nd (Grew below)) lt = MkDrained seen nd (Grew (transitive below (lteSuccLeft lt)))
grown (MkDrained seen nd (Kept same)) lt = MkDrained seen nd (Grew (rewrite same in lt))

-- Keeps each candidate the seen list does not hold yet, and leaves less
-- room for each one kept.
drain : {0 u : List Entry} -> (0 complete : (x : Entry) -> Elem x u) ->
        (seen : List Entry) -> (0 nd : NoDup seen) -> (candidates : List Entry) ->
        Drained u (minus (length u) (length seen))
drain complete seen nd [] = MkDrained seen nd (Kept Refl)
drain complete seen nd (x :: xs) = case isNew x seen of
  Yes _ => drain complete seen nd xs
  No out => grown (drain complete (x :: seen) (out :: nd) xs) (room (out :: nd) (inside complete (x :: seen)))

-- Rounds until one adds nothing. Each round that adds an entry leaves less
-- room in the finite listing, so the rounds end by the pigeonhole; nothing
-- counts them.
round : {0 u : List Entry} -> (0 complete : (x : Entry) -> Elem x u) ->
        SortedMap Address Fields -> List Equation ->
        (seen : List Entry) -> (0 nd : NoDup seen) ->
        (0 acc : Accessible LT (minus (length u) (length seen))) -> List Entry
round complete fs eqs seen nd (Access rec) =
  case drain complete seen nd (Prelude.toList (candidates fs (viewOf seen) eqs)) of
    MkDrained seen' nd' (Grew below) => round complete fs eqs seen' nd' (rec _ below)
    MkDrained seen' _ (Kept _) => seen'

-- The listing is a variable here: written out, the checker would reduce
-- it, and it holds 2 * 256^24 entries.
solve : {0 u : List Entry} -> (0 complete : (x : Entry) -> Elem x u) ->
        SortedMap Address Fields -> List Equation -> List Entry
solve complete fs eqs = round complete fs eqs [] [] (wellFounded _)

||| The implementations each dictionary parameter and field of the program
||| can hold, over the unsplit definitions: the least sets closed under the
||| program's sites, given every implementation's and dictionary
||| constructor's fields.
export
record Flow where
  constructor MkFlow
  implementations : SortedMap Address Fields
  solution : View

export
flow : SortedMap Address Fields -> List Site -> Flow
flow fs ss = MkFlow fs (viewOf (solve {u = values} complete fs (equations fs ss)))

||| What the flow found can reach a definition's parameter: the
||| implementations a dictionary there can be, the type constructors that
||| can head a family there. Sorted and without duplicates.
export
reaching : Flow -> Address -> Nat -> List Address
reaching fl a j = Prelude.toList (at fl.solution (parameterSlot a j))

------------------------------------------------------------------------------
-- The split
------------------------------------------------------------------------------

-- What keys a callee given the writer's own dictionary or family
-- parameter i: its node's head there. A parameter with no head held no
-- rooted dictionary, and no family a type constructor heads, in any
-- request of the node, and is passed on as it was given, so it keys
-- nothing: the flow's set would invent heads no request has.
headAt : Node -> Own
headAt w = markersOnly (\i => maybe empty singleton (lookup i w.heads))

-- What a use of the writer's own dictionary parameter i can be: its node's
-- head there. One with no head holds a function that gives an
-- implementation at each use (a rank-2 dictionary), whose members are the
-- implementations the flow found reach the parameter: every use of it
-- matches on it and runs the member's method, so a dispatch through it
-- reaches each of them.
dictionaryAt : Flow -> Node -> Nat -> SortedSet Address
dictionaryAt fl w i = maybe (at fl.solution (parameterSlot w.definition i)) singleton (lookup i w.heads)

||| The implementations a template alone can be, written in the writer's
||| node, where Core gave no root, the writer's families by index: a
||| dictionary parameter, and one applied, by what it can be
||| (`dictionaryAt`); a family applied, nothing. Sorted and without
||| duplicates.
export
roots : Flow -> (families : List Nat) -> (writer : Node) -> Template -> List Address
roots fl families w t = Prelude.toList (byTemplate fl.solution (MkOwn (dictionaryAt fl w) dictionaryApplied) t)
  where
    dictionaryApplied : Nat -> SortedSet Address
    dictionaryApplied i = if elem i families then empty else dictionaryAt fl w i

-- A callee's dictionary parameters with roots, by index, so ascending.
Choices : Type
Choices = SortedMap Nat (SortedSet Address)

-- A dictionary with no root is no choice: the request that reaches the
-- callee holds no head at that parameter. The case is the program's (a
-- function that gives an implementation at each use keys nothing, and a
-- projection of a value no constructor builds is rooted by no
-- implementation), not the representation's.
choice : Nat -> SortedSet Address -> Choices -> Choices
choice i js cs = if null js then cs else insert i js cs

-- One list of heads for each way of choosing a root at each parameter,
-- ascending by index.
combinations : Choices -> List (List (Nat, Address))
combinations cs = go (Data.SortedMap.toList cs)
  where
    go : List (Nat, SortedSet Address) -> List (List (Nat, Address))
    go [] = [[]]
    go ((i, js) :: rest) = let tails = go rest in
                           [(i, j) :: hs | j <- Prelude.toList js, hs <- tails]

||| What a position of the graph is a parameter of: a node, or the
||| application of a compile-time form at a use (`Translate.State.AtUse`),
||| which no definition is, whose positions every use shares: the form's
||| type (0), the form (1), and the use's static arguments (2 on).
public export
data Holder = OfNode Node | OfApplication

export
Eq Holder where
  OfNode x == OfNode y = x == y
  OfApplication == OfApplication = True
  _ == _ = False

export
Ord Holder where
  compare (OfNode x) (OfNode y) = compare x y
  compare OfApplication OfApplication = EQ
  compare OfApplication (OfNode _) = LT
  compare (OfNode _) OfApplication = GT

||| A static position of the graph: a parameter of what holds it.
public export
Spot : Type
Spot = (Holder, Nat)

||| How a site reached its callee: called or built, its target the callee;
||| or dispatched through implementation J's method field k, whose leading
||| placement puts J's parameters among the method function's.
public export
data Via : Type where
  Called : Via
  Dispatched : (j : Address) -> (k : Nat) -> (leading : List (Nat, Nat)) -> Via

||| What a site reaches from a node: a callee node, or the application at
||| a use, with each of the site's arguments placed at the parameter it
||| lands at, and how it got there.
public export
record Reached where
  constructor MkReached
  callee : Holder
  placed : List Placed
  via : Via

||| Each callee node a site reaches from the writer's node. A callee is split
||| by the roots of its dictionary and family arguments, one node for each
||| combination.
export
reaches : Flow -> (writer : Node) -> Site -> List Reached
reaches fl w s = from s.reach
  where
    rootsAt : Root -> Template -> SortedSet Address
    rootsAt = byRoot fl.solution (markersOnly (dictionaryAt fl w))

    -- The dictionaries and families among the placed arguments, at their
    -- parameters.
    passed : List Placed -> Choices -> Choices
    passed placed cs = foldl add cs placed
      where
        add : Choices -> Placed -> Choices
        add acc (MkPlaced x p) = case splitting x.kind of
          Just how => choice p (keyedBy fl.solution (headAt w) how x) acc
          Nothing => acc

    -- J's method function k. The parameters J's land at take what every
    -- write of J gave them, through J's own call of the function: only the
    -- dispatched dictionary's root is Core's, not the arguments J was
    -- written at.
    through : Nat -> Address -> List Reached
    through k j = case methodAt fl.implementations j k of
      Nothing => []
      Just (m, own, leading) =>
        let fromJ = foldl (\acc, (_, q) => choice q (at fl.solution (parameterSlot m q)) acc) (the Choices empty) leading
            placed = placedBy own s.arguments in
        map (\hs => MkReached (OfNode (MkNode m hs)) placed (Dispatched j k leading)) (combinations (passed placed fromJ))

    from : Reach -> List Reached
    from (Calls t) = let placed = atOwnPositions s.arguments in
                     map (\hs => MkReached (OfNode (MkNode t hs)) placed Called) (combinations (passed placed empty))
    from (Builds t) = [MkReached (OfNode (MkNode t [])) (atOwnPositions s.arguments) Called]
    from (Dispatches t r k) = Prelude.toList (rootsAt r t) >>= through k
    -- Every use's application is one, split by nothing: what it applies is
    -- bounded at its positions alone.
    from Applies = [MkReached OfApplication (atOwnPositions s.arguments) Called]
