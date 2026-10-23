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
||| needs the whole program, what a dictionary held in a field, chosen when
||| the program runs, or given at a use can be, and the flow answers it:
||| the least sets of implementations reaching each parameter, field,
||| choice and position of the application at a use, over the unsplit
||| definitions.
|||
||| The flow and the split read a dictionary the same way, through one
||| function, and differ only in how the writer's own parameter reads: the
||| flow's set at its slot, or the node's head there. A dictionary parameter
||| with no head holds a function that gives an implementation at each use
||| (a rank-2 dictionary, `Gives`): a callee given it is given it as
||| written and keyed by nothing, and a dispatch through it reads the
||| flow's set, so it reaches every member's method. So what reaches a slot
||| is a heading, an implementation or no head (`Heading`): a set of
||| implementations alone could not say that a callee keyed by it is also
||| reached at no head, which a choice whose members are partly computed
||| by a definition needs.
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
import IdrisMLIR.Frontend.Translate.Place
import IdrisMLIR.Frontend.Translate.Readings
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template

import Core.Context
import Core.TT
import Libraries.Data.List.Finite

import Control.Relation
import Control.WellFounded
import Data.DPair
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

-- What splits a node here is an argument's kind (`splitting` below), not
-- the head a request's root names.
%hide IdrisMLIR.Frontend.Translate.Readings.splitting

------------------------------------------------------------------------------
-- Slots
------------------------------------------------------------------------------

-- Where a dictionary can flow: parameter j of a definition or constructor
-- (kind 0), field k of an implementation or constructor (kind 1), the
-- choice of a head (kind 2: an interface's by its address, the arrow's at
-- no address and index 1, the one whose head only an instance shows at no
-- address and index 2), or position j of the application at a use (kind
-- 3, which no definition is, at no address). The index is written as an
-- address too, so that a slot is a triple of finite types and every pair
-- of the solution lies in one finite type, whose listing the checker
-- supplies. There is no numbering pass, so no lookup of a slot can miss.
-- An index is a parameter or field count's, far below 2^63, so distinct
-- indices are distinct addresses.
Slot : Type
Slot = (Fin 4, Address, Address)

-- What a dictionary that reaches a slot keys a callee it is given to by:
-- the implementation at its root, or no head, where nothing roots it (a
-- function that gives an implementation at each use, a member a
-- definition computes by matching, a lambda). A callee given it is split
-- by each heading that reaches its parameter, no head among them, so a
-- choice whose members are rooted at some implementations and computed by
-- a definition reaches every instance a dispatch on it requests, the one
-- at no head included. What a dispatch through a dictionary with no head
-- reaches is what its definition's leaves give, which reach the slot
-- beside it. A dictionary the running program chooses keys nothing of its
-- own, since each use dispatches on it and its members reach beside it;
-- but a constructor that holds it holds it as it is, and a match that
-- takes that constructor apart there is stuck (`Translate.Cases.heldHere`),
-- so it reaches a slot as what it is (`Unsettled`), which splits no
-- callee.
data Heading = HeadedBy Address | Headless | Unsettled

Eq Heading where
  HeadedBy a == HeadedBy b = a == b
  Headless == Headless = True
  Unsettled == Unsettled = True
  _ == _ = False

Ord Heading where
  compare Headless Headless = EQ
  compare Headless _ = LT
  compare (HeadedBy _) Headless = GT
  compare (HeadedBy a) (HeadedBy b) = compare a b
  compare (HeadedBy _) Unsettled = LT
  compare Unsettled Unsettled = EQ
  compare Unsettled _ = GT

-- Every heading is listed: no head, the running program's, and each
-- address's.
Finite Heading where
  values = Headless :: Unsettled :: map HeadedBy (values {a = Address})
  complete Headless = Here
  complete Unsettled = There Here
  complete (HeadedBy addr) = There (There (elemMap HeadedBy (complete {a = Address} addr)))

-- One fact of the solution: this heading reaches this slot.
Entry : Type
Entry = (Slot, Heading)

parameterSlot : Address -> Nat -> Slot
parameterSlot a j = (0, a, bytes 8 (cast j))

fieldSlot : Address -> Nat -> Slot
fieldSlot a k = (1, a, bytes 8 (cast k))

choiceSlot : ChoiceHead -> Slot
choiceSlot (InterfaceHead a) = (2, a, bytes 8 0)
choiceSlot ArrowHead = (2, bytes 8 0, bytes 8 1)
choiceSlot UnshownHead = (2, bytes 8 0, bytes 8 2)

applicationSlot : Nat -> Slot
applicationSlot j = (3, bytes 8 0, bytes 8 (cast j))

-- Where a writer whose parameters a site reads as `ps` takes parameter i
-- from: its own slot, or, in the walk of a member's application, the
-- application's position the use gives there.
ownSlot : Address -> Parameters -> Nat -> Slot
ownSlot w ps i = case parameterOf ps i of
  WritersOwn j => parameterSlot w j
  UsesPosition j => applicationSlot j

-- Novelty compares an address by its bytes' numbers (`decideAddress`), a
-- step per byte. Equality decided by matching `Fin` constructors walks
-- each byte's whole value.
sameBytes : (a, b : Address) -> Dec (a = b)
sameBytes a b = case decideAddress a b of
  -- `Dec` holds its proof at run time: the erased equality is carried
  -- there by `replace`, whose rule is erased.
  Proof.Growth.Yes same => Yes (replace {p = \z => a = z} same Refl)
  Proof.Growth.No ne => No (\eq => void (ne eq))

sameKind : (i, j : Fin 4) -> Dec (i = j)
sameKind = decEq

sameHeading : (x, y : Heading) -> Dec (x = y)
sameHeading Headless Headless = Yes Refl
sameHeading Unsettled Unsettled = Yes Refl
sameHeading (HeadedBy a) (HeadedBy b) = case sameBytes a b of
  Yes Refl => Yes Refl
  No ne => No (\Refl => ne Refl)
sameHeading Headless (HeadedBy _) = No (\case Refl impossible)
sameHeading (HeadedBy _) Headless = No (\case Refl impossible)
sameHeading Headless Unsettled = No (\case Refl impossible)
sameHeading Unsettled Headless = No (\case Refl impossible)
sameHeading Unsettled (HeadedBy _) = No (\case Refl impossible)
sameHeading (HeadedBy _) Unsettled = No (\case Refl impossible)

-- Any order decides. The definition comes first: the self compile's flow
-- holds 1,723 entries over 661 slots (measured on the prototype), so two
-- entries of the seen list almost always differ there.
same : (x, y : Entry) -> Dec (x = y)
same ((k, d, i), h) ((k', d', i'), h') =
  case sameBytes d d' of
    No ne => No (\Refl => ne Refl)
    Yes Refl => case sameHeading h h' of
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
View = SortedMap Slot (SortedSet Heading)

at : View -> Slot -> SortedSet Heading
at v s = fromMaybe empty (lookup s v)

viewOf : List Entry -> View
viewOf = foldl (\v, (s, a) => insert s (insert a (at v s)) v) empty

-- The implementations among some headings, ascending: what a dispatch
-- through the dictionaries reaches, a heading of no head, and one the
-- running program chooses, reaching nothing of its own.
headsIn : SortedSet Heading -> List Address
headsIn hs = mapMaybe headed (Prelude.toList hs)
  where
    headed : Heading -> Maybe Address
    headed (HeadedBy a) = Just a
    headed Headless = Nothing
    headed Unsettled = Nothing

-- What a template's reading reaches: no heading of its own, which a part
-- no root is read off of a dictionary the running program chooses gives,
-- and a use of the writer's parameter applied that only a family, closed
-- values or a computing one reach; or the headings a set holds. No heading
-- is its own case, never an empty set, so that a reading that reaches
-- nothing is known by its shape, which the growth proof reads
-- (`appliedRootsOf`, `recordRootsOf`): a set's contents are base's to
-- know, and base states nothing of them a proof could read.
data Headings = NoHeading | ReachedBy (SortedSet Heading)

-- What two readings reach together.
joined : Headings -> Headings -> Headings
joined NoHeading h = h
joined (ReachedBy hs) NoHeading = ReachedBy hs
joined (ReachedBy hs) (ReachedBy hs') = ReachedBy (union hs hs')

-- What a reading reaches, as the set a reader that asks a set reads.
asSet : Headings -> SortedSet Heading
asSet NoHeading = empty
asSet (ReachedBy hs) = hs

-- The implementations a reading reaches, ascending.
headsOf : Headings -> List Address
headsOf NoHeading = []
headsOf (ReachedBy hs) = headsIn hs

-- What reaches a slot a match takes apart: a dictionary the running
-- program chose, held as it is, which makes the match stuck there; or
-- only dictionaries the program fixes. The view a walk down a dictionary
-- matches on.
data Reaching = ChosenReaches | FixedOnly

-- What reaches a slot, read off its set: the set's own membership test,
-- once, as the view.
reachingAt : View -> Slot -> Reaching
reachingAt v s = asReaching (contains Unsettled (at v s))
  where
    asReaching : Bool -> Reaching
    asReaching True = ChosenReaches
    asReaching False = FixedOnly

-- Every choice's members: what reaches the slots of kind 2.
everyMember : View -> SortedSet Heading
everyMember v = foldl anyChoice empty (Data.SortedMap.toList v)
  where
    anyChoice : SortedSet Heading -> (Slot, SortedSet Heading) -> SortedSet Heading
    anyChoice acc ((FS (FS FZ), _, _), hs) = union acc hs
    anyChoice acc _ = acc

-- What a member of a choice can be: at a head its type shows, the members
-- made there and those made where only an instance shows the head, which
-- may be that head; at an unshown head, every choice's members.
membersAt : View -> ChoiceHead -> SortedSet Heading
membersAt v UnshownHead = everyMember v
membersAt v k = union (at v (choiceSlot k)) (at v (choiceSlot UnshownHead))

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
  ofMarker : Nat -> SortedSet Heading
  ofApplied : Nat -> Headings

-- A reading whose applied markers give nothing: where Core's root answers
-- for every applied marker.
markersOnly : (Nat -> SortedSet Heading) -> Own
markersOnly reading = MkOwn reading (const NoHeading)

-- Whose template a part no root is read off belongs to, which decides
-- what it keys a callee by: a dictionary the running program chooses,
-- whose members, read off its choice, key the instances a dispatch on it
-- requests, so the part keys nothing of its own; or one nothing roots,
-- which a callee is given at no head. A fact of the template's structure,
-- never of the solution so far, so the flow's equations stay monotone.
data Unread = OfChosen | OfRootless

-- What a part no root is read off keys a callee by.
unread : Unread -> Headings
unread OfChosen = NoHeading
unread OfRootless = ReachedBy (singleton Headless)

-- Field k of each implementation a dictionary reaches: no heading where
-- the dictionary reaches none.
fieldsReached : View -> Nat -> Headings -> Headings
fieldsReached v k NoHeading = NoHeading
fieldsReached v k (ReachedBy hs) = ReachedBy (foldl (\acc, j => union acc (at v (fieldSlot j k))) empty (headsIn hs))

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
  -- reaches the projection's target. A dictionary with no head has no
  -- fields of its own: the implementations its leaves give, which reach
  -- beside it, hold them. Any other part has no root read off it
  -- (`Unread`).
  byTemplate : View -> Own -> Unread -> Template -> Headings
  byTemplate v own u (Var i Z) = ReachedBy (own.ofMarker i)
  byTemplate v own u (Field k s) = fieldsReached v k (byTemplate v own OfChosen s)
  byTemplate v own u (Member k) = ReachedBy (membersAt v k)
  byTemplate v own u (Choice _ leaves) = byLeaves v own u leaves
  byTemplate v own u (Applied i Z _) = own.ofApplied i
  byTemplate v own u (Head _ _) = unread u
  byTemplate v own u (Leaf _) = unread u
  byTemplate v own u (Token _) = unread u
  byTemplate v own u (Formal _ _) = unread u
  byTemplate v own u (Opaque _ _) = unread u
  -- A part matched out of a value is a runtime part, which a pattern binds
  -- and nothing applies as a dictionary.
  byTemplate v own u (Var _ (S _)) = unread u
  byTemplate v own u (Applied _ (S _) _) = unread u
  -- Met in a template read at a node (`withClosedFamilies`): a use of the
  -- writer's parameter applied where what beta makes of it computes. A
  -- dictionary applied gives one of the implementations the parameter can
  -- be whatever its arguments compute, so it reads as the use applied
  -- does, and a field's record read there roots what the record as
  -- written roots.
  byTemplate v own u (Computing i Z _) = own.ofApplied i
  byTemplate v own u (Computing _ (S _) _) = unread u

  byLeaves : View -> Own -> Unread -> List Template -> Headings
  byLeaves v own u [] = NoHeading
  byLeaves v own u (t :: ts) = joined (byTemplate v own u t) (byLeaves v own u ts)

-- What an instance that fixes a dictionary its site leaves to the running
-- program keys a callee by: the definition its one right-hand side builds
-- it with, or no head, where it gives what its leaves give; nothing where
-- no instance fixes it. A request at that instance is keyed by its root
-- there, so the callee is split by it.
fixedKey : Settling -> SortedSet Heading
fixedKey AtRunTimeAlways = empty
fixedKey (FixedAt (BuiltBy j)) = singleton (HeadedBy j)
fixedKey (FixedAt (GivenBy _)) = singleton Headless

-- And what a dispatch through it reaches there: what keys a callee, and
-- what its leaves give, which reach beside it.
fixedReach : Settling -> SortedSet Heading
fixedReach (FixedAt (GivenBy js)) = insert Headless (fromList (map HeadedBy js))
fixedReach s = fixedKey s

-- A dictionary with the root Core gave it. A parameter matched deeper, or
-- no root (a projection of what no constructor builds), says nothing of
-- its own, and the template decides, a part of it no root is read off at
-- no head. A function that gives an implementation at each use, or a
-- definition that computes one by matching, is given as written, at no
-- head, and a dispatch through it reaches what its leaves give.
byRoot : View -> Own -> Root -> Template -> SortedSet Heading
byRoot v own (Rooted j) _ = singleton (HeadedBy j)
-- What the running program chooses, its template says: its choice, which
-- the reader put in (`asGiven`); what an instance that fixes it after all
-- makes of it; and, at every other instance, itself, held as it is.
byRoot v own (Chosen s) t = insert Unsettled (union (asSet (byTemplate v own OfChosen t)) (fixedReach s))
byRoot v own (Gives js) _ = insert Headless (fromList (map HeadedBy (forget js)))
byRoot v own (Parameter i Z) _ = own.ofMarker i
byRoot v own (Parameter _ (S _)) t = asSet (byTemplate v own OfRootless t)
byRoot v own Unrooted t = asSet (byTemplate v own OfRootless t)

-- A family by its type root: the type constructor there, or the writer's
-- own family there. A family no type constructor heads (a lambda, a value
-- the program computes) is given at no head.
byFamily : Own -> Root -> SortedSet Heading
byFamily own (Rooted j) = singleton (HeadedBy j)
byFamily own (Parameter i Z) = own.ofMarker i
byFamily own (Chosen _) = singleton Headless
byFamily own (Gives _) = singleton Headless
byFamily own (Parameter _ (S _)) = singleton Headless
byFamily own Unrooted = singleton Headless

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
byArgument : View -> Own -> Splitting -> Argument -> SortedSet Heading
byArgument v own ByImplementation x = byRoot v own x.root x.template
byArgument v own ByTypeConstructor x = byFamily own x.root

-- What an argument keys its callee by, at the call: what it can be, but
-- no head alone for a function that gives an implementation at each use
-- (`Gives`), which the callee is given as written, one instance of it
-- taking every member; and for one the running program chooses, its
-- choice's members and what an instance that fixes it is keyed by there.
keyedBy : View -> Own -> Splitting -> Argument -> SortedSet Heading
keyedBy v own how x = case (how, x.root) of
  (ByImplementation, Gives _) => singleton Headless
  (ByImplementation, Chosen s) => union (asSet (byTemplate v own OfChosen x.template)) (fixedKey s)
  _ => byArgument v own how x

-- The arguments a site passes that split their callee, each with how.
splitters : Site -> List (Splitting, Argument)
splitters s = mapMaybe (\x => (, x) <$> splitting x.kind) s.arguments

-- What the program's dictionaries hold, read once: each definition that
-- gives one, with what it holds, and each method function by the
-- implementation field it is.
record Dictionaries where
  constructor MkDictionaries
  holding : SortedMap Address Fields
  methods : SortedMap Address (Address, Nat)

dictionariesOf : SortedMap Address Fields -> Dictionaries
dictionariesOf fs = MkDictionaries fs (foldl (\m, (j, f) => numbered j 0 f.inOrder m) empty (Data.SortedMap.toList fs))
  where
    numbered : Address -> Nat -> List Field -> SortedMap Address (Address, Nat) -> SortedMap Address (Address, Nat)
    numbered j k [] m = m
    numbered j k (Method fn _ _ _ :: rest) m = numbered j (S k) rest (insert fn (j, k) m)
    numbered j k (Dictionary _ _ _ _ :: rest) m = numbered j (S k) rest m
    numbered j k (Plain _ _ :: rest) m = numbered j (S k) rest m

-- The method function an implementation's field k is, with where the
-- method's own arguments and the implementation's parameters land among
-- its parameters, and the implementation as it was read. Any other field
-- (a superclass dictionary, or one of an interface constructor's own
-- variables) has none.
methodAt : Dictionaries -> Address -> Nat -> Maybe (Address, List Nat, List (Nat, Nat), GlobalDef)
methodAt ds j k = case lookup j ds.holding of
  Just f => case fieldIn f k of
    Just (Method m _ own leading) => Just (m, own, leading, f.givenBy)
    _ => Nothing
  Nothing => Nothing

-- The method fields a dispatch through field k of j runs: that field when
-- it is a method's; and through any other field, each method function its
-- slot holds as a value, as the implementation field it is, which is what
-- a constructor rebuilt from an implementation holds there
-- (`Sites.Repacks`). A dictionary a field holds, and a function that is no
-- implementation's field, run no method of their own: a dispatch on the
-- dictionary is a dispatch of its own, and the function's body is code
-- where it is written.
runs : Dictionaries -> View -> Address -> Nat -> List (Address, Nat)
runs ds v j k = case fieldAt ds.holding j k of
  Just (Method _ _ _ _) => [(j, k)]
  _ => mapMaybe (\m => lookup m ds.methods) (headsIn (at v (fieldSlot j k)))

------------------------------------------------------------------------------
-- Rebuilt dictionaries
------------------------------------------------------------------------------

-- One level of a path of fields taken down a dictionary: what the part
-- there is rooted at, what that holds, the field the path takes, the head
-- of the choice that field's type is, a dictionary's, and that type over
-- the constructor's arguments, which a match that finds the field stuck
-- holds it at, with the definitions of the recursions it holds.
record Level where
  constructor MkLevel
  rootedAt : Address
  holds : Fields
  taken : Nat
  choiceOf : ChoiceHead
  heldType : TemplateRead

-- The head of the choice field k is, and its type, where it is a
-- dictionary, the one kind of field a match takes apart.
heldDictionary : Fields -> Nat -> Maybe (ChoiceHead, TemplateRead)
heldDictionary f k = case head' (drop k f.inOrder) of
  Just (Dictionary _ _ h ty) => Just (h, ty)
  _ => Nothing

-- One way a path of fields can be taken down a dictionary, from its root,
-- to a field the running program may have chosen, so that a match there
-- is stuck (`reachingAt`): a level for each field of the path, the
-- dictionary's first. Each level's root is one of those its part can be,
-- given the roots the dictionary can be at the first.
Chain : Type
Chain = List1 Level

chains : Dictionaries -> View -> (roots : List Address) -> (k : Nat) -> (rest : List Nat) -> List Chain
chains ds v [] k rest = []
chains ds v (j :: js) k rest = here ++ chains ds v js k rest
  where
    down : Level -> List Nat -> List Chain
    down l [] = case reachingAt v (fieldSlot j k) of
      ChosenReaches => [l ::: []]
      FixedOnly => []
    down l (k' :: ks) = map (\c => l ::: forget c) (chains ds v (headsIn (at v (fieldSlot j k))) k' ks)

    -- A root that holds no dictionary at the field is no way down: a
    -- match there takes apart nothing the program fixes.
    here : List Chain
    here = case lookup j ds.holding of
      Nothing => []
      Just f => maybe [] (\(h, ty) => down (MkLevel j f k h ty) rest) (heldDictionary f k)

-- A dictionary rebuilt down a chain, as an arm of the dispatch
-- `Translate.Cases.heldHere` requests holds it
-- (`Translate.Choices.heldMember`): each level the constructor its root is
-- built with, applied to that level's fields, each read off the part
-- there (`Field`), but the one the path takes, which is the next level
-- rebuilt, and at the last level a member of the field's choice
-- (`Member`), which the place that made the member wrote at the choice's
-- positions. With what each rebuilt constructor's fields then hold, by
-- constructor, by its address and as it was read, and field. The part is
-- the dictionary's marker or a field of it, so none of these holds a
-- recursion.
record Rebuilt where
  constructor MkRebuilt
  template : Template
  0 unrecursive : recursions template = []
  fillings : List Filled

-- A rebuilt constructor's field: the constructor, by its address and as
-- it was read, the field, and what it holds there, which holds no
-- recursion.
record Filled where
  constructor MkFilled
  con : Address
  conRead : GlobalDef
  field : Nat
  template : Template
  0 unrecursive : recursions template = []

-- A template that holds no recursion.
Unrecursive : Type
Unrecursive = Subset Template (\t => recursions t = [])

-- The templates of some that hold no recursion.
unrecursiveTemplates : List Unrecursive -> List Template
unrecursiveTemplates [] = []
unrecursiveTemplates (Element t _ :: cs) = t :: unrecursiveTemplates cs

-- Templates that each hold no recursion hold none together.
0 noneIn : (cs : List Unrecursive) -> recursionsIn (unrecursiveTemplates cs) = []
noneIn [] = Refl
noneIn (Element t none :: cs) = rewrite none in noneIn cs

-- A level's fields read off its part, the one the path takes the next
-- level rebuilt, or at the last a member of its choice.
cellsFrom : (part : Unrecursive) -> Level -> Maybe Rebuilt -> (c : Nat) -> List Field -> List Unrecursive
cellsFrom part l inner c [] = []
cellsFrom part l inner c (_ :: fs) =
  (if c == l.taken then onward inner else Element (Template.Field c part.fst) part.snd) :: cellsFrom part l inner (S c) fs
  where
    onward : Maybe Rebuilt -> Unrecursive
    onward (Just r) = Element r.template r.unrecursive
    onward Nothing = Element (Template.Member l.choiceOf) Refl

-- A constructor's fields as rebuilt, by number.
filled : Address -> GlobalDef -> (c : Nat) -> List Unrecursive -> List Filled
filled con def c [] = []
filled con def c (Element t none :: ts) = MkFilled con def c t none :: filled con def (S c) ts

mutual
  rebuilt : (part : Unrecursive) -> Level -> List Level -> Rebuilt
  rebuilt part l ls =
    let inner = deeper part l ls
        cells = cellsFrom part l inner 0 l.holds.inOrder in
    MkRebuilt (Template.Head (Just l.holds.builtBy) (unrecursiveTemplates cells)) (noneIn cells)
              (filled l.holds.builtBy l.holds.builtAs 0 cells ++ further inner)

  further : Maybe Rebuilt -> List Filled
  further (Just r) = r.fillings
  further Nothing = []

  deeper : Unrecursive -> Level -> List Level -> Maybe Rebuilt
  deeper part l [] = Nothing
  deeper part l (n :: ns) = Just (rebuilt (Element (Template.Field l.taken part.fst) part.snd) n ns)

-- The last level of a chain and the part it takes apart: the dictionary
-- itself at the first, and below it the field each level above takes, as
-- the rebuilt dictionary reads it (`deeper`).
lastOf : Unrecursive -> Level -> List Level -> (Unrecursive, Level)
lastOf part l [] = (part, l)
lastOf part l (n :: ns) = lastOf (Element (Template.Field l.taken part.fst) part.snd) n ns

-- A constructor's field type over its arguments (`Var c 0` its argument
-- c), read over the part a level takes apart: each argument the part's
-- field, as the rebuilt dictionary's other fields are read (`cellsFrom`).
-- An argument applied as a family is the part's field applied, which is
-- how a reading reads a dictionary's field applied (`markedOf`); and a
-- recursion stuck on an argument is stuck on the part's field, as one
-- stuck on any value its writer holds is, with the arc any such recursion
-- draws.
mutual
  overPart : Template -> Template -> Template
  overPart part (Template.Var c _) = Template.Field c part
  overPart part (Template.Head a ts) = Template.Head a (overParts part ts)
  overPart part (Template.Opaque a ts) = Template.Opaque a (overParts part ts)
  overPart part (Template.Choice m ls) = Template.Choice (overPart part m) (overParts part ls)
  overPart part (Template.Field k r) = Template.Field k (overPart part r)
  overPart part (Template.Leaf h) = Template.Leaf h
  overPart part (Template.Token k) = Template.Token k
  overPart part (Template.Formal j a) = Template.Formal j a
  overPart part (Template.Member k) = Template.Member k
  overPart part (Template.Applied c _ ts) = markedOf (Template.Field c part) (overParts part ts)
  overPart part (Template.Computing c _ ts) = markedOf (Template.Field c part) (overParts part ts)

  overParts : Template -> List Template -> List Template
  overParts part [] = []
  overParts part (t :: ts) = overPart part t :: overParts part ts

-- A type over a part that holds no recursion holds the type's own
-- recursions: each argument becomes a field of the part, and every other
-- node is kept.
mutual
  0 overPartKeeps : (part : Template) -> recursions part = [] -> (t : Template) -> recursions (overPart part t) = recursions t
  overPartKeeps part none (Template.Var c _) = none
  overPartKeeps part none (Template.Head a ts) = overPartsKeep part none ts
  overPartKeeps part none (Template.Opaque a ts) = rewrite overPartsKeep part none ts in Refl
  overPartKeeps part none (Template.Choice m ls) = rewrite overPartKeeps part none m in rewrite overPartsKeep part none ls in Refl
  overPartKeeps part none (Template.Field k r) = overPartKeeps part none r
  overPartKeeps part none (Template.Leaf h) = Refl
  overPartKeeps part none (Template.Token k) = Refl
  overPartKeeps part none (Template.Formal j a) = Refl
  overPartKeeps part none (Template.Member k) = Refl
  overPartKeeps part none (Template.Applied c _ ts) = appliedOverPart part none c ts
  overPartKeeps part none (Template.Computing c _ ts) = appliedOverPart part none c ts

  0 overPartsKeep : (part : Template) -> recursions part = [] -> (ts : List Template) -> recursionsIn (overParts part ts) = recursionsIn ts
  overPartsKeep part none [] = Refl
  overPartsKeep part none (t :: ts) = rewrite overPartKeeps part none t in rewrite overPartsKeep part none ts in Refl

  0 appliedOverPart : (part : Template) -> recursions part = [] -> (c : Nat) -> (ts : List Template) ->
                      recursions (markedOf (Template.Field c part) (overParts part ts)) = recursionsIn ts
  appliedOverPart part none c ts = trans (markedHolds (Template.Field c part) (overParts part ts) none) (overPartsKeep part none ts)

-- What each rebuilt constructor's fields hold in the flow: what the
-- level's root holds there, and where the path goes on, the constructor
-- the next level is rebuilt with. The field the last level takes holds a
-- member of its choice in each arm (`membersAt`), never the stuck value
-- the root may hold there.
mutual
  rebuiltEntries : View -> Level -> List Level -> List Entry
  rebuiltEntries v l [] = copied v l Nothing 0 l.holds.inOrder
  rebuiltEntries v l (n :: ns) = copied v l (Just n.holds.builtBy) 0 l.holds.inOrder ++ rebuiltEntries v n ns

  copied : View -> Level -> (next : Maybe Address) -> (c : Nat) -> List Field -> List Entry
  copied v l next c [] = []
  copied v l next c (_ :: fs) = map (fieldSlot l.holds.builtBy c,) (Prelude.toList (there next)) ++ copied v l next (S c) fs
    where
      own : SortedSet Heading
      own = at v (fieldSlot l.rootedAt c)

      there : Maybe Address -> SortedSet Heading
      there (Just con) = if c == l.taken then singleton (HeadedBy con) else own
      there Nothing = if c == l.taken then membersAt v l.choiceOf else own

-- Heads with the one at parameter i, ascending as a visit holds them.
headedAt : Nat -> a -> List (Nat, a) -> List (Nat, a)
headedAt i con [] = [(i, con)]
headedAt i con ((j, a) :: hs) = case compare i j of
  LT => (i, con) :: (j, a) :: hs
  EQ => (i, con) :: hs
  GT => (j, a) :: headedAt i con hs

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

-- What the flow asks of each site and field, read once, each with the
-- writer whose text holds it and how it reads its parameters. `Into` says
-- the slot holds every root of this dictionary: an implementation's field,
-- at the field. `Passes` says the slot holds what this argument can be: a
-- call's dictionary or family, at the callee's parameter; a use's, at the
-- application's position; a member a site makes of a choice, at the
-- choice, so that a dispatch on it reaches the instance of its callee at
-- each member, keyed by the member's heading, and, at a member no
-- implementation roots, what that member's leaves give. `Through` says
-- the function of method k of this dictionary holds what these arguments
-- give, at the parameters the method's field places them at. `Rebuilds`
-- says the constructors the writer's dictionary parameter is rebuilt
-- with, down a path of fields a match finds stuck, hold what the parts
-- there held (`rebuiltEntries`).
data Equation = Into Slot Address Parameters Root Template
              | Passes Slot Address Parameters Splitting Argument
              | Through Address Parameters Root Template Nat (List (Splitting, Argument))
              | Rebuilds Address Parameters Nat (List1 Nat)

-- Writing `J u` reaches J's parameters through the call of J, and J's
-- method functions' leading parameters through J's own calls of them,
-- which pass its parameters: no equation of its own.
equations : SortedMap Address Fields -> List Site -> List Equation
equations fs ss = (ss >>= fromSite) ++ (Data.SortedMap.toList fs >>= fromFields)
  where
    passes : (Nat -> Slot) -> Site -> (Splitting, Argument) -> Equation
    passes slot s (how, x) = Passes (slot x.position) s.writer s.params how x

    fromSite : Site -> List Equation
    fromSite s = case s.reach of
      Calls t _ => map (passes (parameterSlot t) s) (splitters s)
      Builds _ _ => []
      Dispatches t r k => [Through s.writer s.params r t k (splitters s)]
      Applies => map (passes applicationSlot s) (splitters s)
      Makes k@(InterfaceHead _) _ => map (passes (const (choiceSlot k)) s) (splitters s)
      -- A member whose head only an instance shows may be an
      -- implementation's.
      Makes UnshownHead _ => map (passes (const (choiceSlot UnshownHead)) s) (splitters s)
      -- A polymorphic function is given as it is, keying nothing, and a
      -- use of it applies each member at the use's own types.
      Makes ArrowHead _ => []
      Repacks x path => [Rebuilds s.writer s.params x.position path]
      -- What a dictionary the writer binds closes over flows nowhere: it
      -- is held at the binding's place alone.
      Keeps _ _ => []

    numbered : Address -> Nat -> List Field -> List Equation
    numbered j k [] = []
    numbered j k (field :: rest) =
      let (t, r) = fieldRead field in Into (fieldSlot j k) j OwnOnly r t.template :: numbered j (S k) rest

    fromFields : (Address, Fields) -> List Equation
    fromFields (j, fields) = numbered j 0 fields.inOrder

-- The entries a dictionary rebuilt down a chain gives (`rebuiltEntries`).
chainEntries : View -> Chain -> List Entry
chainEntries v (l ::: ls) = rebuiltEntries v l ls

-- Every entry the equations give under the solution so far. A set, since
-- the sites give each entry many times, and each is searched for in the
-- seen list once. Lists are joined by bind, which is linear: base's
-- `concatMap` on a list folds `++` from the left, quadratic in the length.
candidates : Dictionaries -> View -> List Equation -> SortedSet Entry
candidates ds v eqs = fromList (eqs >>= yield)
  where
    own : Address -> Parameters -> Own
    own w ps = markersOnly (\i => at v (ownSlot w ps i))

    into : Slot -> SortedSet Heading -> List Entry
    into s hs = map (s,) (Prelude.toList hs)

    yield : Equation -> List Entry
    yield (Into s w ps r t) = into s (byRoot v (own w ps) r t)
    yield (Passes s w ps how x) = into s (byArgument v (own w ps) how x)
    -- A dispatch through a dictionary with no head runs what its leaves
    -- give, which reach beside it.
    yield (Through w ps r t k xs) = do
      j <- headsIn (byRoot v (own w ps) r t)
      (j', k') <- runs ds v j k
      case methodAt ds j' k' of
        Nothing => []
        Just (m, own', _, _) => do
          (how, x) <- xs
          p <- placedAt own' x
          into (parameterSlot m p) (byArgument v (own w ps) how x)
    yield (Rebuilds w ps i (k ::: ks)) =
      chains ds v (headsIn (at v (ownSlot w ps i))) k ks >>= chainEntries v

-- Whether a round grew the seen list: if it did, the room left in the
-- listing is below the round's start, and otherwise it is the start.
data Change : (left, start : Nat) -> Type where
  Grew : (0 _ : LT left start) -> Change left start
  Stayed : (0 _ : left = start) -> Change left start

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
grown (MkDrained seen nd (Stayed same)) lt = MkDrained seen nd (Grew (rewrite same in lt))

-- Keeps each candidate the seen list does not hold yet, and leaves less
-- room for each one kept.
drain : {0 u : List Entry} -> (0 complete : (x : Entry) -> Elem x u) ->
        (seen : List Entry) -> (0 nd : NoDup seen) -> (candidates : List Entry) ->
        Drained u (minus (length u) (length seen))
drain complete seen nd [] = MkDrained seen nd (Stayed Refl)
drain complete seen nd (x :: xs) = case isNew x seen of
  Yes _ => drain complete seen nd xs
  No out => grown (drain complete (x :: seen) (out :: nd) xs) (room (out :: nd) (inside complete (x :: seen)))

-- Rounds until one adds nothing. Each round that adds an entry leaves less
-- room in the finite listing, so the rounds end by the pigeonhole; nothing
-- counts them.
round : {0 u : List Entry} -> (0 complete : (x : Entry) -> Elem x u) ->
        Dictionaries -> List Equation ->
        (seen : List Entry) -> (0 nd : NoDup seen) ->
        (0 acc : Accessible LT (minus (length u) (length seen))) -> List Entry
round complete ds eqs seen nd (Access rec) =
  case drain complete seen nd (Prelude.toList (candidates ds (viewOf seen) eqs)) of
    MkDrained seen' nd' (Grew below) => round complete ds eqs seen' nd' (rec _ below)
    MkDrained seen' _ (Stayed _) => seen'

-- The listing is a variable here: written out, the checker would reduce
-- it, and it holds 4 * 256^24 entries.
solve : {0 u : List Entry} -> (0 complete : (x : Entry) -> Elem x u) ->
        Dictionaries -> List Equation -> List Entry
solve complete ds eqs = round complete ds eqs [] [] (wellFounded _)

||| The implementations each dictionary parameter and field of the program
||| can hold, over the unsplit definitions: the least sets closed under the
||| program's sites, given every implementation's and dictionary
||| constructor's fields.
export
record Flow where
  constructor MkFlow
  dictionaries : Dictionaries
  solution : View

export
flow : SortedMap Address Fields -> List Site -> Flow
flow fs ss = let ds = dictionariesOf fs in MkFlow ds (viewOf (solve {u = values} complete ds (equations fs ss)))

||| What the flow found can reach a definition's parameter: the
||| implementations a dictionary there can be, the type constructors that
||| can head a family there. Sorted and without duplicates.
export
reaching : Flow -> Address -> Nat -> List Address
reaching fl a j = headsIn (at fl.solution (parameterSlot a j))

------------------------------------------------------------------------------
-- The split
------------------------------------------------------------------------------

-- What keys a callee given the writer's parameter i: its node's head
-- there. A parameter with no head held no rooted dictionary, and no family
-- a type constructor heads, in any request of the node, and is passed on
-- as it was given, so it keys nothing: the flow's set would invent heads
-- no request has. A position of the application that the walk of a
-- member's application reads is no node's, and splits nothing: every
-- instance of the application at a use is keyed by what that use gives
-- there, so it keys a callee by everything the flow found reaches it.
headAt : Flow -> Node -> Parameters -> Own
headAt fl w ps = markersOnly (\i => case parameterOf ps i of
  WritersOwn j => maybe empty (singleton . HeadedBy) (lookup j w.heads)
  UsesPosition j => at fl.solution (applicationSlot j))

-- What a use of the writer's dictionary parameter i can be: its node's
-- head there. One with no head holds a function that gives an
-- implementation at each use (a rank-2 dictionary), whose members are the
-- implementations the flow found reach the parameter: every use of it
-- matches on it and runs the member's method, so a dispatch through it
-- reaches each of them. A position of the application is what the flow
-- found reaches it.
dictionaryAt : Flow -> Node -> Parameters -> Nat -> SortedSet Heading
dictionaryAt fl w ps i = case parameterOf ps i of
  WritersOwn j => maybe (at fl.solution (parameterSlot w.definition j)) (singleton . HeadedBy) (lookup j w.heads)
  UsesPosition j => at fl.solution (applicationSlot j)

-- What a use of a function that gives an implementation reaches, by what
-- lands at its parameter. Essential: such a use is a member the flow found
-- only where values not all closed land there, whatever its arguments
-- compute. Where only closed values land, the graph reads it as heads
-- above its arguments, beta of a value landed there, a part of that value
-- and no member; where a value that computes lands, as computing, which
-- nothing an instance writes reaches.
appliedWhere : Landing -> Lazy (SortedSet Heading) -> Headings
appliedWhere Open hs = ReachedBy hs
appliedWhere (Closed _) _ = NoHeading
appliedWhere Computed _ = NoHeading
appliedWhere (Evaluable _) _ = NoHeading

-- What a use of a parameter reaches: nothing at a family, which no
-- member is, and otherwise what its landing gives. The test is written
-- once, as a function of its own: an `if` is a case function of its own
-- wherever it is written, so a proof could not unify the one here with
-- one in its own statement.
unlessFamily : (family : Bool) -> Headings -> Headings
unlessFamily True _ = NoHeading
unlessFamily False h = h

-- What a use of the writer's parameter i, applied, reaches at a node: a
-- family applied, nothing, since beta applies it and no implementation
-- is; a dictionary, what it can be where values not all closed land at
-- it.
usedApplied : Flow -> (families : List Nat) -> Node -> Parameters -> (landing : Nat -> Landing) -> Nat -> Headings
usedApplied fl families w ps landing i =
  unlessFamily (elem i families) (appliedWhere (landing i) (dictionaryAt fl w ps i))

-- How the growth theorem's model reads the writer's own parameters at a
-- node: a dictionary parameter by what it can be, and one applied as its
-- landing says.
ownAt : Flow -> (families : List Nat) -> Node -> Parameters -> (landing : Nat -> Landing) -> Own
ownAt fl families w ps landing = MkOwn (dictionaryAt fl w ps) (usedApplied fl families w ps landing)

||| The implementations a template alone can be, written in the writer's
||| node as `ps` reads its parameters, where Core gave no root, the
||| writer's families by index and what lands at each parameter: a
||| dictionary parameter by what it can be (`dictionaryAt`); one applied by
||| what it can be only where values not all closed land at it, the one
||| landing at which the graph reads a use of it applied as no closed
||| value's part (`Template.withClosedFamilies`), whatever its arguments
||| compute; a family applied, nothing. Sorted and
||| without duplicates.
export
roots : Flow -> (families : List Nat) -> (writer : Node) -> Parameters -> (landing : Nat -> Landing) -> Template ->
        List Address
roots fl families w ps landing t = headsOf (byTemplate fl.solution (ownAt fl families w ps landing) OfChosen t)

------------------------------------------------------------------------------
-- What the roots say, for the growth proof
------------------------------------------------------------------------------

||| What the roots a site reads off a template say of a use of the writer's
||| parameter i applied, at a node where `c` says what lands at each
||| parameter: where a root reaches it, values not all closed land at i,
||| and the root is read off i alone, whatever i is applied to.
public export
0 AppliedRoots : (Nat -> Landing) -> (Template -> List Address) -> Type
AppliedRoots c rs = (i, d : Nat) -> (ts : List Template) -> (j : Address) -> Elem j (rs (Applied i d ts)) ->
                    ((k : Nat) -> Not (c i = Closed k), (ts' : List Template) -> Elem j (rs (Applied i d ts')))

-- A reading that reaches nothing either way reaches nothing.
0 eitherNothing : (b : Bool) -> {0 h : Headings} -> h = NoHeading -> unlessFamily b h = NoHeading
eitherNothing True _ = Refl
eitherNothing False none = none

-- A use of the writer's parameter where no value that can be a member
-- lands reaches nothing.
0 nothingAt : (fl : Flow) -> (families : List Nat) -> (w : Node) -> (ps : Parameters) -> (c : Nat -> Landing) ->
              (i : Nat) -> (l : Landing) -> c i = l -> appliedWhere l (dictionaryAt fl w ps i) = NoHeading ->
              usedApplied fl families w ps c i = NoHeading
nothingAt fl families w ps c i l landed none =
  trans (cong (\x => unlessFamily (elem i families) (appliedWhere x (dictionaryAt fl w ps i))) landed)
        (eitherNothing (elem i families) none)

||| The roots of a use of the writer's parameter applied, as `roots` reads
||| them at a node: where only closed values land, the use reads as no
||| member, so a root reaching it rules a closed landing out; and a use
||| is read off the parameter alone, whatever it is applied to.
export
0 appliedRootsOf : (fl : Flow) -> (families : List Nat) -> (w : Node) -> (ps : Parameters) -> (c : Nat -> Landing) ->
                   AppliedRoots c (roots fl families w ps c)
appliedRootsOf fl families w ps c i Z ts j el =
  (\k, closed => absurd (replace {p = \h => Elem j (headsOf h)} (nothingAt fl families w ps c i (Closed k) closed Refl) el),
   \ts' => el)
appliedRootsOf fl families w ps c i (S d) ts j el = absurd el

||| What the roots a site reads off a template say of a field's record, at
||| a node where `c` says what lands at each parameter: every root the
||| record reaches as written, it reaches read where the node's families
||| land.
public export
0 RecordRoots : (Nat -> Landing) -> (Template -> List Address) -> Type
RecordRoots c rs = (r : Template) -> (j : Address) -> Elem j (rs r) -> Elem j (rs (withClosedFamilies c r))

-- k heads above a head reach what the head does.
0 raisedReaches : (k : Nat) -> byTemplate v own u (raise k (Head a ts)) = unread u
raisedReaches Z = Refl
raisedReaches (S k) = Refl

mutual
  -- Reading a template at a node keeps what it reaches.
  0 readReaches : (fl : Flow) -> (families : List Nat) -> (w : Node) -> (ps : Parameters) -> (c : Nat -> Landing) ->
                  (t : Template) ->
                  byTemplate fl.solution (ownAt fl families w ps c) OfChosen (withClosedFamilies c t) =
                  byTemplate fl.solution (ownAt fl families w ps c) OfChosen t
  readReaches fl families w ps c (Var i d) = Refl
  readReaches fl families w ps c (Leaf h) = Refl
  readReaches fl families w ps c (Token k) = Refl
  readReaches fl families w ps c (Formal j k) = Refl
  readReaches fl families w ps c (Member k) = Refl
  readReaches fl families w ps c (Head a ts) = Refl
  readReaches fl families w ps c (Opaque a ts) = Refl
  readReaches fl families w ps c (Computing i Z ts) = Refl
  readReaches fl families w ps c (Computing i (S d) ts) = Refl
  readReaches fl families w ps c (Field k r) = cong (fieldsReached fl.solution k) (readReaches fl families w ps c r)
  readReaches fl families w ps c (Choice s ls) = leavesReach fl families w ps c ls
  readReaches fl families w ps c (Applied i d ts) =
    appliedReaches fl families w ps c i d ts (c i) Refl (argumentsBeta c (allWithClosed c ts))

  0 leavesReach : (fl : Flow) -> (families : List Nat) -> (w : Node) -> (ps : Parameters) -> (c : Nat -> Landing) ->
                  (ls : List Template) ->
                  byLeaves fl.solution (ownAt fl families w ps c) OfChosen (allWithClosed c ls) =
                  byLeaves fl.solution (ownAt fl families w ps c) OfChosen ls
  leavesReach fl families w ps c [] = Refl
  leavesReach fl families w ps c (t :: ts) =
    cong2 joined (readReaches fl families w ps c t) (leavesReach fl families w ps c ts)

  -- A use of the writer's parameter applied, read as what lands at its
  -- position and what beta makes of its arguments say: computing or not,
  -- a use applied reads as the parameter, and only heads above its
  -- arguments, where closed values land, read as no member, as the use
  -- does where they land.
  0 appliedReaches : (fl : Flow) -> (families : List Nat) -> (w : Node) -> (ps : Parameters) -> (c : Nat -> Landing) ->
                     (i, d : Nat) -> (ts : List Template) -> (l : Landing) -> c i = l -> (b : Beta) ->
                     byTemplate fl.solution (ownAt fl families w ps c) OfChosen (landedAs l b i d (allWithClosed c ts)).template =
                     byTemplate fl.solution (ownAt fl families w ps c) OfChosen (Applied i d ts)
  appliedReaches fl families w ps c i (S d) ts Computed _ b = Refl
  appliedReaches fl families w ps c i (S d) ts (Evaluable _) _ b = Refl
  appliedReaches fl families w ps c i (S d) ts (Closed k) _ Computes = Refl
  appliedReaches fl families w ps c i (S d) ts Open _ Computes = Refl
  appliedReaches fl families w ps c i (S d) ts (Closed k) _ Inert = raisedReaches k
  appliedReaches fl families w ps c i (S d) ts Open _ Inert = Refl
  appliedReaches fl families w ps c i Z ts Computed _ b = Refl
  appliedReaches fl families w ps c i Z ts (Evaluable _) _ b = Refl
  appliedReaches fl families w ps c i Z ts (Closed k) _ Computes = Refl
  appliedReaches fl families w ps c i Z ts Open _ Computes = Refl
  appliedReaches fl families w ps c i Z ts Open _ Inert = Refl
  appliedReaches fl families w ps c i Z ts (Closed k) landed Inert =
    trans (raisedReaches k) (sym (nothingAt fl families w ps c i (Closed k) landed Refl))

||| The roots a field's record reaches, as `roots` reads them at a node,
||| are kept by reading the record there (`withClosedFamilies`).
export
0 recordRootsOf : (fl : Flow) -> (families : List Nat) -> (w : Node) -> (ps : Parameters) -> (c : Nat -> Landing) ->
                  RecordRoots c (roots fl families w ps c)
recordRootsOf fl families w ps c r j el =
  replace {p = \h => Elem j (headsOf h)} (sym (readReaches fl families w ps c r)) el

------------------------------------------------------------------------------
-- Visits
------------------------------------------------------------------------------

||| What heads a dictionary or family parameter of a visit: the definition
||| at its root, as the translation's node holds it (`Node`), and the stuck
||| paths of fields its chain of held dispatches held a value for, newest
||| first. At each of those paths the dictionary holds the member a held
||| arm put in, which reduces (`Cases.heldHere`), so a match there is not
||| stuck again. A family, and a dictionary no re-pack rebuilt, held none.
public export
record Headed where
  constructor MkHeaded
  root : Address
  held : List (List1 Nat)

export
Eq Headed where
  x == y = x.root == y.root && x.held == y.held

export
Ord Headed where
  compare x y = compare (x.root, x.held) (y.root, y.held)

||| What the walk over nodes visits: a definition and the head of each
||| dictionary and family parameter it is split at, by index, ascending.
||| Its node (`visitNode`) is what the translation splits a request by, and
||| what a position belongs to; a visit also holds what each chain of held
||| dispatches settled, so that a dictionary a re-pack rebuilt is told apart
||| from one whose path is still chosen, which the node, holding only the
||| root, cannot tell.
public export
record Visit where
  constructor MkVisit
  definition : Address
  heads : List (Nat, Headed)

export
Eq Visit where
  x == y = x.definition == y.definition && x.heads == y.heads

export
Ord Visit where
  compare x y = compare (x.definition, x.heads) (y.definition, y.heads)

||| The node a visit is of: its definition, split at each head's root.
export
visitNode : Visit -> Node
visitNode v = MkNode v.definition (map rootAt v.heads)
  where
    rootAt : (Nat, Headed) -> (Nat, Address)
    rootAt (i, h) = (i, h.root)

||| Two paths of fields are one when their fields are, as the machine
||| compares them.
export
samePath : (p, q : List1 Nat) -> Decided (p = q)
samePath (k ::: ks) (k' ::: ks') = case sameNat k k' of
  Proof.Growth.No ne => Proof.Growth.No (\Refl => ne Refl)
  Proof.Growth.Yes firsts => case sameList sameNat ks ks' of
    Proof.Growth.No ne => Proof.Growth.No (\Refl => ne Refl)
    Proof.Growth.Yes rests => Proof.Growth.Yes (rewrite firsts in rewrite rests in Refl)

||| Whether a path of fields is among some, as the machine compares them.
export
pathAmong : (p : List1 Nat) -> (ps : List (List1 Nat)) -> Decided (Elem p ps)
pathAmong p [] = Proof.Growth.No (\case _ impossible)
pathAmong p (q :: qs) = case samePath p q of
  Proof.Growth.Yes same => Proof.Growth.Yes (rewrite same in Here)
  Proof.Growth.No ne => case pathAmong p qs of
    Proof.Growth.Yes e => Proof.Growth.Yes (There e)
    Proof.Growth.No out => Proof.Growth.No (\case Here => ne Refl; There e => out e)

||| A dictionary rebuilt down a stuck path its chain has not held, at the
||| root its rebuilt constructor is: a chain holds each stuck path at most
||| once, so the path goes in only beside the evidence that it was not
||| there.
rebuiltHead : (root : Address) -> (path : List1 Nat) -> (held : List (List1 Nat)) -> (0 _ : Not (Elem path held)) ->
              Headed
rebuiltHead root path held _ = MkHeaded root (path :: held)

-- A callee's dictionary and family parameters, by index, so ascending,
-- each with the heads it can be keyed by there: an implementation with
-- what its chain held, or none.
Choices : Type
Choices = SortedMap Nat (List (Maybe Headed))

-- What some headings key a callee by: each implementation, and no head. A
-- dictionary the running program chooses keys nothing of its own, since
-- its members, which reach beside it, key the callee.
keyings : SortedSet Heading -> List (Maybe Address)
keyings hs = mapMaybe keying (Prelude.toList hs)
  where
    keying : Heading -> Maybe (Maybe Address)
    keying (HeadedBy a) = Just (Just a)
    keying Headless = Just Nothing
    keying Unsettled = Nothing

-- A parameter with its headings, each implementation holding the stuck
-- paths the argument carries (`reaches`). One that nothing keys is keyed
-- at no head alone, as one only `Headless` reaches is: the request that
-- reaches the callee holds no head there. The case is the program's (a
-- function that gives an implementation at each use keys nothing, and a
-- projection of a value no constructor builds is rooted by no
-- implementation), not the representation's.
choice : Nat -> SortedSet Heading -> (held : List (List1 Nat)) -> Choices -> Choices
choice i hs held cs = case keyings hs of
  [] => cs
  ks => insert i (map (map (\a => MkHeaded a held)) ks) cs

-- One list of heads for each way of choosing a head at each parameter,
-- ascending by index: a parameter at no head has none in it.
combinations : Choices -> List (List (Nat, Headed))
combinations cs = go (Data.SortedMap.toList cs)
  where
    headed : Nat -> Maybe Headed -> List (Nat, Headed) -> List (Nat, Headed)
    headed i (Just j) hs = (i, j) :: hs
    headed i Nothing hs = hs

    go : List (Nat, List (Maybe Headed)) -> List (List (Nat, Headed))
    go [] = [[]]
    go ((i, js) :: rest) = let tails = go rest in
                           [headed i h hs | h <- js, hs <- tails]

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

||| A dictionary's place, whose values a held position bounds: a parameter
||| of what holds it, a field of an implementation or of a rebuilt
||| constructor, a choice, where its members are, or the place in a
||| writer's text, at the writer's node, where a `let` or a lambda's
||| argument binds a dictionary that closes over values
||| (`Place.BoundPlace`). Each holds the lists its givers give it
||| (`Sites.HeldItem`), a binding the one list of what it closes over. A
||| field holds what its dictionary holds, which its dictionary's place
||| bounds, so no list is given at one; it is where a rebuilt constructor's
||| field lands.
public export
data HeldBy = ByParameter Holder Nat | ByField Address Nat | ByChoice ChoiceHead | ByBinding Node BoundPlace

export
Eq HeldBy where
  ByParameter h i == ByParameter h' i' = h == h' && i == i'
  ByField j k == ByField j' k' = j == j' && k == k'
  ByChoice k == ByChoice k' = k == k'
  ByBinding w b == ByBinding w' b' = w == w' && b == b'
  _ == _ = False

export
Ord HeldBy where
  compare (ByParameter h i) (ByParameter h' i') = compare (h, i) (h', i')
  compare (ByParameter _ _) _ = LT
  compare _ (ByParameter _ _) = GT
  compare (ByField j k) (ByField j' k') = compare (j, k) (j', k')
  compare (ByField _ _) _ = LT
  compare _ (ByField _ _) = GT
  compare (ByChoice k) (ByChoice k') = compare k k'
  compare (ByChoice _) _ = LT
  compare _ (ByChoice _) = GT
  compare (ByBinding w b) (ByBinding w' b') = compare (w, b) (w', b')

||| How the values of one list a dictionary holds are held
||| (`Closed.packedType`): one value, held as itself, in no pair; or two or
||| more, each but the last in a pair with those after it. A list of one
||| value given on as it is stays one value of the same type, where a list
||| of several becomes one value as high as its pairs.
public export
data Packed = AsItself | InPairs

export
Eq Packed where
  AsItself == AsItself = True
  InPairs == InPairs = True
  _ == _ = False

export
Ord Packed where
  compare AsItself AsItself = EQ
  compare AsItself InPairs = LT
  compare InPairs AsItself = GT
  compare InPairs InPairs = EQ

||| What a held position bounds: the values one dictionary's place holds,
||| in its lists of one value or in its lists of several. A held position
||| belongs to a dictionary's place, and no place is a held position, so
||| values held inside held values have no position of their own: a
||| dictionary another holds, a bound one among them, is one value of the
||| other's list, of the type its own values pack to.
public export
record HeldValues where
  constructor MkHeldValues
  heldBy : HeldBy
  packed : Packed

export
Eq HeldValues where
  MkHeldValues b p == MkHeldValues b' p' = b == b' && p == p'

export
Ord HeldValues where
  compare (MkHeldValues b p) (MkHeldValues b' p') = compare (b, p) (b', p')

||| A static position of the graph: a parameter of what holds it; field k
||| of an implementation, which the field's template over the
||| implementation's parameters writes, and a field read takes its value
||| from; a choice, by its head, which every place that makes a member of
||| it writes, and every dispatch on it reads (`Model.choicePositions`); or
||| the values a dictionary's place holds as one, which every place that
||| gives it a list writes and every pair that holds such a list reads
||| (`Graph.heldPackings`).
public export
data Spot = OfParameter Holder Nat | OfField Address Nat | OfChoice ChoiceHead | OfHeld HeldValues

export
Eq Spot where
  OfParameter h i == OfParameter h' i' = h == h' && i == i'
  OfField j k == OfField j' k' = j == j' && k == k'
  OfChoice k == OfChoice k' = k == k'
  OfHeld v == OfHeld v' = v == v'
  _ == _ = False

export
Ord Spot where
  compare (OfParameter h i) (OfParameter h' i') = compare (h, i) (h', i')
  compare (OfParameter _ _) _ = LT
  compare _ (OfParameter _ _) = GT
  compare (OfField j k) (OfField j' k') = compare (j, k) (j', k')
  compare (OfField _ _) _ = LT
  compare _ (OfField _ _) = GT
  compare (OfChoice k) (OfChoice k') = compare k k'
  compare (OfChoice _) (OfHeld _) = LT
  compare (OfHeld _) (OfChoice _) = GT
  compare (OfHeld v) (OfHeld v') = compare v v'

||| A dictionary's place that is a position of the graph itself, its held
||| positions belonging to it: a parameter, a field or a choice. A
||| dictionary a writer's text binds is no position: every use reads its
||| form where it is written, and its place holds only what it closes over.
public export
data Positioned : HeldBy -> Type where
  ParameterPlace : Positioned (ByParameter h i)
  FieldPlace : Positioned (ByField j k)
  ChoicePlace : Positioned (ByChoice k)

||| A dictionary's place as a position of the graph: the position its
||| held positions belong to.
export
valueSpot : (place : HeldBy) -> (0 _ : Positioned place) -> Spot
valueSpot (ByParameter h i) _ = OfParameter h i
valueSpot (ByField j k) _ = OfField j k
valueSpot (ByChoice k) _ = OfChoice k
valueSpot (ByBinding _ _) ParameterPlace impossible
valueSpot (ByBinding _ _) FieldPlace impossible
valueSpot (ByBinding _ _) ChoicePlace impossible

||| What a message reads of what a dictionary's place is named by, beside
||| the place, which stays a key: the definition a node's parameter is of,
||| as the walk read it; nothing of the application at a use, which no
||| definition is; the implementation or rebuilt constructor a field is of,
||| as it was read; what is read of a choice's head (`HeadRead`); and the
||| definition whose text binds a dictionary, as it was read. It is
||| indexed by the place, so it is never another place's, and a message
||| reads every definition it names here, never by address.
public export
data PlaceRead : HeldBy -> Type where
  NodeParameter : GlobalDef -> PlaceRead (ByParameter (OfNode node) i)
  ApplicationParameter : PlaceRead (ByParameter OfApplication i)
  FieldOf : GlobalDef -> PlaceRead (ByField j k)
  ChoiceOfHead : HeadRead k -> PlaceRead (ByChoice k)
  BoundIn : GlobalDef -> PlaceRead (ByBinding node b)

||| What a message reads of what a position is named by, indexed by the
||| position: a parameter's, a field's and a choice's is their place's
||| (`valueSpot`), and the values a dictionary's place holds are named by
||| that place.
public export
data SpotRead : Spot -> Type where
  ParameterSpot : PlaceRead (ByParameter h i) -> SpotRead (OfParameter h i)
  FieldSpot : PlaceRead (ByField j k) -> SpotRead (OfField j k)
  ChoiceSpot : PlaceRead (ByChoice k) -> SpotRead (OfChoice k)
  HeldSpot : PlaceRead b -> SpotRead (OfHeld (MkHeldValues b p))

-- What is read of a dictionary's place that is a position of the graph is
-- what is read of that position.
placedRead : (place : HeldBy) -> (0 positioned : Positioned place) -> PlaceRead place -> SpotRead (valueSpot place positioned)
placedRead (ByParameter h i) _ r = ParameterSpot r
placedRead (ByField j k) _ r = FieldSpot r
placedRead (ByChoice k) _ r = ChoiceSpot r
placedRead (ByBinding _ _) ParameterPlace _ impossible
placedRead (ByBinding _ _) FieldPlace _ impossible
placedRead (ByBinding _ _) ChoicePlace _ impossible

-- Where a writer's parameter is, as a site's `Parameters` read it
-- (`parameterOf`): the writer's node's own, or a position of the
-- application.
placeOfParameter : Node -> ParameterOf -> Subset HeldBy Positioned
placeOfParameter w (WritersOwn j) = Element (ByParameter (OfNode w) j) ParameterPlace
placeOfParameter w (UsesPosition j) = Element (ByParameter OfApplication j) ParameterPlace

-- What is read of that place, the writer read as `writer`.
parameterRead : (writer : GlobalDef) -> (w : Node) -> (p : ParameterOf) -> PlaceRead (placeOfParameter w p).fst
parameterRead writer w (WritersOwn j) = NodeParameter writer
parameterRead writer w (UsesPosition j) = ApplicationParameter

||| Where parameter i of a writer is, at its node, as `ps` reads it: the
||| node's own, or a position of the application.
export
writerPlace : Node -> Parameters -> Nat -> Subset HeldBy Positioned
writerPlace w ps i = placeOfParameter w (parameterOf ps i)

||| What a message reads of the place of a writer's parameter i
||| (`writerPlace`), the writer as it was read.
export
writerRead : (writer : GlobalDef) -> (w : Node) -> (ps : Parameters) -> (i : Nat) -> PlaceRead (writerPlace w ps i).fst
writerRead writer w ps i = parameterRead writer w (parameterOf ps i)

||| The position of parameter i of a writer at its node (`writerPlace`).
export
spotAt : Node -> Parameters -> Nat -> Spot
spotAt w ps i = valueSpot (writerPlace w ps i).fst (writerPlace w ps i).snd

||| What a message reads of that position (`spotAt`), the writer as it was
||| read.
export
writerSpotRead : (writer : GlobalDef) -> (w : Node) -> (ps : Parameters) -> (i : Nat) -> SpotRead (spotAt w ps i)
writerSpotRead writer w ps i = placedRead (writerPlace w ps i).fst (writerPlace w ps i).snd (writerRead writer w ps i)

||| How a site reached its callee: called or built, its target the callee;
||| or dispatched through implementation J's method field k, J as it was
||| read, whose leading placement puts J's parameters among the method
||| function's.
public export
data Via : Type where
  Called : Via
  Dispatched : (j : Address) -> (jRead : GlobalDef) -> (k : Nat) -> (leading : List (Nat, Nat)) -> Via

||| What a site reaches from a visit: a callee's visit, which the walk
||| enters, with what the walk knows of the callee (`e`): nothing where a
||| site's reading finds it (`reaches`), and the definition its node is
||| read at once the walk has read that node (`Graph`); the application at
||| a use; a choice it makes a member of, with what a message reads of its
||| head; or the fields of a constructor a dictionary is rebuilt with, by
||| its address and as it was read, which no definition's node holds, each
||| a field's position. A dictionary the writer binds is no callee
||| (`Reached`).
public export
data Callee : Type -> Type where
  Entering : Visit -> e -> Callee e
  Applying : Callee e
  Making : (k : ChoiceHead) -> HeadRead k -> Callee e
  Filling : Address -> GlobalDef -> Callee e

||| The place an argument placed at a callee's parameter i is at: that
||| parameter of the visit's node or of the application; at a choice, its
||| one place, where every member is whatever it is placed at; at a rebuilt
||| constructor, its field i. What a dictionary there holds is held there.
export
calleePlace : Callee e -> Nat -> Subset HeldBy Positioned
calleePlace (Entering v _) i = Element (ByParameter (OfNode (visitNode v)) i) ParameterPlace
calleePlace Applying i = Element (ByParameter OfApplication i) ParameterPlace
calleePlace (Making k _) _ = Element (ByChoice k) ChoicePlace
calleePlace (Filling con _) i = Element (ByField con i) FieldPlace

||| What a message reads of that place (`calleePlace`): what the walk read
||| of the callee where it entered it, and what the site read of a choice's
||| head or a rebuilt constructor.
export
calleeRead : (c : Callee Defined) -> (i : Nat) -> PlaceRead (calleePlace c i).fst
calleeRead (Entering v d) i = NodeParameter d.def
calleeRead Applying i = ApplicationParameter
calleeRead (Making k named) i = ChoiceOfHead named
calleeRead (Filling con def) i = FieldOf def

||| Where an argument placed at a callee's parameter i lands (`calleePlace`).
export
landsAt : Callee e -> Nat -> Spot
landsAt c i = valueSpot (calleePlace c i).fst (calleePlace c i).snd

||| What a message reads of that position (`landsAt`).
export
calleeSpotRead : (c : Callee Defined) -> (i : Nat) -> SpotRead (landsAt c i)
calleeSpotRead c i = placedRead (calleePlace c i).fst (calleePlace c i).snd (calleeRead c i)

||| What a site reaches from a node: a callee, with what the walk knows of
||| it (`Callee`), each of the site's arguments placed at the parameter it
||| lands at, and how it got there; or, where the writer binds a
||| dictionary that closes over values, the place it is bound at, which
||| holds the list of them as one at the writer's node (`ByBinding`), and
||| which no argument is placed at.
public export
data Reached : Type -> Type where
  MkReached : (callee : Callee e) -> (placed : List Placed) -> (via : Via) -> Reached e
  Kept : BoundPlace -> List1 HeldItem -> Reached e

||| Each callee a site reaches from the writer's visit. A callee is split by
||| the roots of its dictionary and family arguments, one visit for each
||| combination; the writer's own dictionary given as it is keeps what its
||| chain held.
export
reaches : Flow -> (writer : Visit) -> Site -> List (Reached ())
reaches fl v s = from s.reach
  where
    -- The writer's node, whose heads key what the writer's text gives.
    w : Node
    w = visitNode v

    rootsAt : Root -> Template -> SortedSet Heading
    rootsAt = byRoot fl.solution (markersOnly (dictionaryAt fl w s.params))

    -- The stuck paths the writer's chain held a value for at its parameter
    -- i, as the site reads it: none at a position of the application, whose
    -- every use gives its own.
    heldAt : Nat -> List (List1 Nat)
    heldAt i = case parameterOf s.params i of
      WritersOwn j => maybe [] (.held) (lookup j v.heads)
      UsesPosition _ => []

    -- What an argument carries to the head it keys its callee by: the
    -- writer's own dictionary parameter, given as it is, is the dictionary
    -- the writer's chain rebuilt, with the paths it held; any other is a
    -- dictionary of its own, or a family, and held none.
    carried : Splitting -> Argument -> List (List1 Nat)
    carried ByImplementation x = case x.template of
      Var i Z => heldAt i
      _ => []
    carried ByTypeConstructor _ = []

    -- The dictionaries and families among the placed arguments, at their
    -- parameters.
    passed : List Placed -> Choices -> Choices
    passed placed cs = foldl add cs placed
      where
        add : Choices -> Placed -> Choices
        add acc (MkPlaced x p) = case splitting x.kind of
          Just how => choice p (keyedBy fl.solution (headAt fl w s.params) how x) (carried how x) acc
          Nothing => acc

    -- J's method function k. The parameters J's land at take what every
    -- write of J gave them, through J's own call of the function: only the
    -- dispatched dictionary's root is Core's, not the arguments J was
    -- written at.
    method : Nat -> Address -> List (Reached ())
    method k j = case methodAt fl.dictionaries j k of
      Nothing => []
      Just (m, own, leading, jRead) =>
        let fromJ = foldl (\acc, (_, q) => choice q (at fl.solution (parameterSlot m q)) [] acc) (the Choices empty) leading
            placed = placedBy own s.arguments in
        map (\hs => MkReached (Entering (MkVisit m hs) ()) placed (Dispatched j jRead k leading)) (combinations (passed placed fromJ))

    -- A dispatch through field k of j: each method field it runs (`runs`).
    through : Nat -> Address -> List (Reached ())
    through k j = runs fl.dictionaries fl.solution j k >>= \(j', k') => method k' j'

    -- A field of a rebuilt constructor, as what the dictionary's argument
    -- writes there: the field holds what its dictionary holds, no list of
    -- its own.
    filling : Argument -> Filled -> Reached ()
    filling x f =
      MkReached (Filling f.con f.conRead)
                [MkPlaced ({ position := f.field, template := f.template, recursionsRead := noRecursions {t = f.template} f.unrecursive
                           , root := Unrooted, term := Nothing, writtenAs := NoTerm, holds := [] } x) f.field]
                Called

    -- The field the last level takes, as a value held (`Cases.heldHere`):
    -- its type over that level's part (`overPart`), which holds the type's
    -- recursions.
    stuckField : Argument -> (Unrecursive, Level) -> Argument
    stuckField x (part, l) =
      { position := 0, kind := AType, template := overPart part.fst l.heldType.template
      , recursionsRead := replace {p = All RecursionDef} (sym (overPartKeeps part.fst part.snd l.heldType.template)) l.heldType.recursionsRead
      , root := Unrooted, term := Nothing, memberOf := Nothing, writtenAs := NoTerm, holds := [] } x

    -- The writer again, its dictionary parameter, whose argument is `x`,
    -- rebuilt down a chain to the stuck path `path`, which the writer's
    -- chain has not held: at its visit with the dictionary's head the
    -- constructor the chain's root is built with, which is the rebuilt
    -- dictionary's root, holding that path after those held before, and
    -- every other static parameter as it is; and the rebuilt constructors'
    -- fields, which no other site writes. The rebuilt dictionary holds the
    -- values its writer was given, each as itself, and the stuck field
    -- after them; and, in each arm of the dispatch on that field, those
    -- values and then the values the member put in its place holds
    -- (`Choices.heldMember`).
    rebuiltAt : Argument -> (path : List1 Nat) -> (held : List (List1 Nat)) -> (0 _ : Not (Elem path held)) -> Chain ->
                List (Reached ())
    rebuiltAt x path held fresh (l ::: ls) =
      let r = rebuilt (Element (Template.Var x.position 0) Refl) l ls
          final = lastOf (Element (Template.Var x.position 0) Refl) l ls
          lists = [ EachOf x.position ::: [OfType (stuckField x final ::: [])]
                  , EachOf x.position ::: [MembersOf (snd final).choiceOf] ]
          dictionary = MkPlaced ({ template := r.template, recursionsRead := noRecursions {t = r.template} r.unrecursive, root := Unrooted
                                 , term := Nothing, writtenAs := NoTerm, holds := lists } x) x.position
          settled = rebuiltHead l.holds.builtBy path held fresh
          target = MkVisit v.definition (headedAt x.position settled v.heads) in
      MkReached (Entering target ()) (atOwnPositions s.arguments ++ [dictionary]) Called ::
        map (filling x) r.fillings

    from : Reach -> List (Reached ())
    from (Calls t _) = let placed = atOwnPositions s.arguments in
                       map (\hs => MkReached (Entering (MkVisit t hs) ()) placed Called) (combinations (passed placed empty))
    from (Builds t _) = [MkReached (Entering (MkVisit t []) ()) (atOwnPositions s.arguments) Called]
    -- A dispatch through a dictionary with no head runs what its leaves
    -- give, which reach beside it.
    from (Dispatches t r k) = headsIn (rootsAt r t) >>= through k
    -- Every use's application is one, split by nothing: what it applies is
    -- bounded at its positions alone.
    from Applies = [MkReached Applying (atOwnPositions s.arguments) Called]
    from (Makes k named) = [MkReached (Making k named) (atOwnPositions s.arguments) Called]
    -- A binding's list is held at its place, at the writer's node.
    from (Keeps b items) = [Kept b items]
    -- Where a match finds a field of the dictionary stuck: one request for
    -- each chain to a field the running program may have chosen, none
    -- where every root holds that field fixed, as no translation then
    -- rebuilds it.
    from (Repacks x path) = case pathAmong path (heldAt x.position) of
      -- Essential: at a path the writer's chain held a value for, the
      -- dictionary holds the member a held arm put in, which reduces, so
      -- no match there is stuck, and a chain holds each stuck path once.
      Proof.Growth.Yes _ => []
      Proof.Growth.No fresh =>
        chains fl.dictionaries fl.solution (headsIn (dictionaryAt fl w s.params x.position)) path.head path.tail
          >>= rebuiltAt x path (heldAt x.position) fresh
