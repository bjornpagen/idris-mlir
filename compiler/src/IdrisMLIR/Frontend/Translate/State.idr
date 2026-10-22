-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The translation's state: the data and function instances registered so
||| far, and the function instances waiting to be translated.
module IdrisMLIR.Frontend.Translate.State

import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Proof.Forms
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.DPair
import Data.Fin
import Data.List1
import Data.SnocList
import Data.SortedMap
import Data.SortedSet

%default total

||| The runtime values an implementation closes over (`DictParam`,
||| `Closed.Static`): their types, in the order of the markers that stand
||| for them in its compile-time form (`Closed.holeMarker`), and the one
||| parameter that holds them: the value itself, or, for more than one, a
||| pair of the first and the rest (`Closed.packedType`).
public export
record Holes where
  constructor MkHoles
  types : List1 ClosedTerm
  binder : Binder

||| Parameter classification after instantiation (`Instances.classify`). A
||| type parameter and an implementation (a value of an interface's type,
||| such as an interface constraint) are compile-time values: they key the
||| instance and are not parameters at runtime. An implementation may close
||| over runtime values (`{vars : _} -> Show (Term vars)` at the scope a term
||| has): which implementation it is stays a compile-time value, the values
||| replaced by markers, and the parameter holds the values (`Holes`). An
||| implementation the call chooses at run time among those the program
||| fixes is a choice (`ChoiceParam`): a runtime value of the closed sum of
||| the implementations of its interface type (`Choices`), with its binder
||| and that type; a call given one is a dispatch on it, never an instance
||| at it. A parameter of quantity 0 is no parameter at runtime and keys
||| nothing: absent, or, when it occurs as an index of an inductive family
||| in a runtime parameter's type or the result and nowhere a
||| representation depends on it, an index parameter of the instance, of
||| its sort, whose level is the number of index parameters before it, so
||| that the instance's types name it (`!idr.data<#Vect[v0]>`). Any other
||| binds as its binder says, with its closed Idris type, which tells a
||| function-typed value's erased arguments from its runtime ones; when the
||| rest of the type depends on its value, the shape of its argument keys
||| the instance too. An erased shape of the array language that a value
||| array's type needs is its form, the spine with every extent erased: it
||| keys the instance, since a tensor's rank is its type. The kinds stay
||| positional, one per parameter of the definition's type, as the case
||| tree's scope has one variable per parameter.
public export
data PKind = TypeParam ClosedTerm
           | DictParam ClosedTerm (Maybe Holes)
           | ChoiceParam Binder ClosedTerm
           | ErasedParam
           | IndexParam Sort
           | FormParam ClosedTerm
           | ValueParam Binder (Maybe ClosedTerm) ClosedTerm

||| How a static argument keys its instance, as classify's PKind: a type
||| (TypeParam), a type family (TypeParam too: a type parameter whose kind
||| is a function into a universe, `tm : Scope -> Type` or a functor's `f`,
||| whose value is a type constructor applied to fewer arguments than it
||| takes, or a lambda), an implementation (DictParam), a form (FormParam),
||| a shape (ValueParam). A family and an implementation are the kinds whose
||| value's head splits the definition it is given to (`Root`).
public export
data Static = AType | AFamily | ADictionary | AForm | AShape

-- The kinds in one order, so that a table can be keyed by kind.
kindOrder : Static -> Nat
kindOrder AType = 0
kindOrder AFamily = 1
kindOrder ADictionary = 2
kindOrder AForm = 3
kindOrder AShape = 4

export
Eq Static where
  x == y = kindOrder x == kindOrder y

export
Ord Static where
  compare x y = compare (kindOrder x) (kindOrder y)

||| The kinds a request's static argument is read at: every kind but a
||| family's. A family keys its instance as any type does (`TypeParam`),
||| and its value reads as a type, whose root is the type constructor it
||| applies when it has one, so a request is never read as a family.
public export
data Requested : Static -> Type where
  ReadAsType : Requested AType
  ReadAsDictionary : Requested ADictionary
  ReadAsForm : Requested AForm
  ReadAsShape : Requested AShape

||| The compile-time value that keys an instance at a parameter, with the
||| kind the growth check reads it at: a type, an implementation, a form,
||| a value's shape; nothing for a parameter that keys nothing. The one
||| reading of a request's parameter as a static argument.
export
staticKindOf : PKind -> Maybe (Subset Static Requested, ClosedTerm)
staticKindOf (TypeParam t) = Just (Element AType ReadAsType, t)
staticKindOf (DictParam t _) = Just (Element ADictionary ReadAsDictionary, t)
-- A choice keys nothing: which implementation runs is the value's, and the
-- interface type it is a choice of follows from the static arguments
-- before it, which key the dispatch.
staticKindOf (ChoiceParam _ _) = Nothing
staticKindOf ErasedParam = Nothing
staticKindOf (IndexParam _) = Nothing
staticKindOf (FormParam f) = Just (Element AForm ReadAsForm, f)
staticKindOf (ValueParam _ shape _) = (Element AShape ReadAsShape,) <$> shape

||| An instance's telescope: the sorts of its index parameters, in order,
||| the levels `0 .. p-1` of its body's scope.
export
telescopeOf : List PKind -> List Sort
telescopeOf [] = []
telescopeOf (IndexParam s :: ks) = s :: telescopeOf ks
telescopeOf (_ :: ks) = telescopeOf ks

||| A full name, printed so that different names print differently: Idris's
||| `show` prints only the display part of a `DN` and leaves out the index of
||| a case or with block. It is a print, for a message that names a
||| definition; no table is keyed by it, since a definition is its address
||| (`definitionAddress`), and it is no part of what the program is called,
||| which `Keys` prints.
export
nameKey : Name -> String
nameKey (NS ns n) = let k = nameKey n in if any isOpChar (unpack k) then show ns ++ ".(" ++ k ++ ")" else show ns ++ "." ++ k
nameKey (DN str n) = str.text ++ "{" ++ nameKey n ++ "}"
nameKey (CaseBlock outer i) = "case block " ++ show i ++ " in " ++ nameKey outer
nameKey (WithBlock outer i) = "with block " ++ show i ++ " in " ++ nameKey outer
nameKey n = show n

||| A definition's identity: its address in the context (`Walk.addressOf`);
||| nothing for a name the context does not hold, which no table keeps.
||| For a site that needs the address alone; one that needs the definition
||| too resolves it once (`Walk.resolve`).
export
definitionAddress : Context -> Name -> Maybe Address
definitionAddress ctx n = addressOf <$> placementIn ctx n

||| A definition as the growth check splits it (`Growth`): its address,
||| the implementation (or interface constructor) at the root of each
||| implementation it is given that has one, and the type constructor at
||| the head of each type family it is given that one heads (`tm : Scope ->
||| Type` at `Term`), by the parameter's index, ascending. A method is
||| requested as its projection at the dictionary, so two calls of it at
||| implementations of different heads are two nodes: it is keyed by the
||| implementation that runs. A definition whose kinds depend on what its
||| family is (an index of `Term` keys nothing that a marker would key) is
||| two nodes at two type constructors, each with its own positions.
public export
record Node where
  constructor MkNode
  definition : Address
  heads : List (Nat, Address)

export
Eq Node where
  x == y = x.definition == y.definition && x.heads == y.heads

export
Ord Node where
  compare x y = compare (x.definition, x.heads) (y.definition, y.heads)

||| A static position of the checked graph: a node and one of its
||| definition's parameters, by position.
public export
Position : Type
Position = (Node, Nat)

||| The index of the context an address is (`Walk.addressOf`'s inverse): the
||| index whose eight bytes, the low byte first, it is.
export
addressIndex : Address -> Int
addressIndex a = cast (bytes a)
  where
    bytes : Vect k (Fin 256) -> Integer
    bytes [] = 0
    bytes (b :: bs) = cast (finToNat b) + 256 * bytes bs

||| The name a definition's address stands for (`addressOf`'s inverse): the
||| context's entry at that index, for a message to print (`toFullNames`);
||| nothing for bytes no entry of the context has.
export
nameAt : Context -> Address -> Maybe Name
nameAt ctx a = let i = addressIndex a in
               if i < nextEntry ctx then Just (Resolved i) else Nothing

||| The definition at an address, as the context holds it; nothing at bytes
||| no entry of the context has. The one reading of a definition by its
||| address.
export
definitionAt : {auto c : Ref Ctxt Defs} -> Address -> Core (Maybe GlobalDef)
definitionAt a = do
  defs <- get Ctxt
  case nameAt (gamma defs) a of
    Just n => lookupCtxtExact n (gamma defs)
    Nothing => pure Nothing

||| A static argument as the growth check reads it (`Template.closedHeight`):
||| its height, and the definition at its root that splits the node of a
||| request it is given to, the implementation of a dictionary or the type
||| constructor at the head of a family, if it has one.
public export
record StaticReading where
  constructor MkStaticReading
  height : Nat
  head : Maybe Address

||| A function instance requested: its identity, its definition, its
||| parameters as the call that requested it classified them, so that it is
||| translated at the same values, its key, the call that requested it,
||| where and in whose definition, for a message to print, its link, which
||| is its identity, its node, and the height of each static argument by
||| its parameter's index, ascending, which the worklist checks against the
||| growth check's bounds at the node's positions (`Finite`). The node's
||| heads and the heights are the arguments' readings, found when the
||| instance is requested (`Instances.request`).
public export
record Request where
  constructor MkRequest
  inst : FnId
  name : Name
  kinds : List PKind
  key : InstanceKey
  site : FC
  owner : Shown
  link : Link Form
  node : Node
  heights : List (Nat, Nat)

||| One argument of a constructor, as a data instance has it. Idris does not
||| put the data type's parameters first (`(::) : {0 len} -> {0 elem} ->
||| ...`), so every argument says what it is: a parameter, whose value the
||| instance gives; an argument of quantity 0, which is no field; or
||| runtime field `i`, counting the runtime fields from 0, with its binder
||| and its Idris type at the instance. An implementation the constructor
||| holds (`Empty : Ord k => ...`) is a field like any other, its value a
||| choice (`Choices`): each construction site gives the one it fixes.
public export
data ArgKind = Param ClosedTerm
             | ErasedArg
             | Field Nat Binder ClosedTerm

||| The binder of a runtime field.
export
fieldBinder : ArgKind -> Maybe Binder
fieldBinder (Field _ b _) = Just b
fieldBinder _ = Nothing

||| What a constructor instance needs for case trees: its arguments, its
||| full name, and the constructor as Core has it, indexed by its runtime
||| fields.
public export
record ConLayout where
  constructor MkConLayout
  args : List ArgKind
  name : Name
  con : (k ** Con k)

||| The constructor of a member of a choice: one with no field, for an
||| implementation that closes over no runtime value, or one whose one
||| field holds the values it closes over (`Holes`).
public export
data MemberCon = Bare (Con 0) | Holding Holes (Con 1)

||| An implementation the program fixes as a value of its interface type,
||| one constructor of that type's choice (`Choices`): its form, the
||| runtime values it closes over replaced by markers (`Closed.holeMarker`),
||| which keys the instance of every callee a dispatch calls at it, and its
||| constructor.
public export
record ChoiceMember where
  constructor MkChoiceMember
  form : ClosedTerm
  con : MemberCon

||| The closed sum of the implementations of one interface type that the
||| program fixes as runtime values: its family, the interface type, and
||| its members in the order the translation found them, each the next
||| constructor. It only grows, and a dispatch on it is built once the
||| translation has found every member (`Choices.dispatchers`).
public export
record Choice where
  constructor MkChoice
  family : FamilyId
  type : ClosedTerm
  members : SnocList ChoiceMember

||| A call given a choice (`ChoiceParam`), as one function: its identity,
||| symbol and key, the callee and its kinds as the call classified them,
||| the choice's family and the position of the parameter that takes it,
||| where and in whose definition it was made, and for each member the
||| instance of the callee at that member that its arm calls, by the
||| member's position.
public export
record Dispatch where
  constructor MkDispatch
  inst : FnId
  symbol : String
  key : InstanceKey
  callee : Name
  kinds : List PKind
  family : FamilyId
  at : Nat
  ||| How many choices the kinds hold after this one: each arm is a call
  ||| of the callee with one fewer (`Choices.calleeAt`).
  rest : Nat
  site : FC
  owner : String
  arms : SortedMap Nat FnId

export
data TState : Type where

||| What a type constructor's values are, as numbers go.
public export
data Natness = NotNat     -- not Nat-like
             | Numeral    -- Nat-like (Idris's ZERO/SUCC), but a constructor takes an erased argument (Fin's FS)
             | Chain      -- Nat-like, every constructor argument at run time: a shape is a chain of S

||| What the argument at a position of a type constructor is to a data
||| instance of it, decided once per position (`Types.tyConFacts`):
|||
||| - `Keyed`: a type parameter a value represents, which keys the instance
|||   whole, its own indices erased;
||| - `Formed`: a parameter of the shape type that a value array's shape
|||   reads, which keys the instance by its form, the rank kept and the
|||   extents erased, since a tensor's rank is its type;
||| - `Held`: an index whose kind is a universe and that the values hold,
|||   which keys nothing but the growth check watches;
||| - `Index`: compile-time information alone.
|||
||| The key keeps the `Keyed` and `Formed` arguments, and the growth check
||| watches every position but an `Index`, reading a `Formed` one as the
||| key's form, so that what the key holds and what the check bounds are
||| read off one role.
public export
data Role = Keyed | Formed | Held | Index

public export
Eq Role where
  Keyed == Keyed = True
  Formed == Formed = True
  Held == Held = True
  Index == Index = True
  _ == _ = False

||| What a definition takes at an argument position: no value at run time
||| (quantity 0), or a value, at Idris's quantity. Whether an erased
||| position is an index the IR keeps is a fact of each instance, read
||| where its type constructors' roles are known (`IndexParam`), not of
||| the definition.
public export
data ArgumentAt = NoValue | RuntimeValue Uses

||| What the translation reads of a type constructor's definition: its
||| parameters, the role of the argument at each position (`Role`), the
||| first first, and what its values are as numbers go.
public export
record TyConFacts where
  constructor MkTyConFacts
  params : List Nat
  roles : List Role
  natness : Natness

||| The role of the argument at a position: past the type constructor's
||| arguments, none is there to key anything.
public export
roleAt : Nat -> List Role -> Role
roleAt j rs = fromMaybe Index (getAt j rs)

||| The positions whose role the test picks, in order.
public export
positionsOf : (Role -> Bool) -> List Role -> List Nat
positionsOf p rs = map fst (filter (p . snd) (zip [0 .. length rs] rs))

||| Does the key hold the argument at a position of this role?
public export
inKey : Role -> Bool
inKey Keyed = True
inKey Formed = True
inKey Held = False
inKey Index = False

||| Does the growth check watch the argument at a position of this role?
public export
watched : Role -> Bool
watched Index = False
watched _ = True

||| What a module the session loaded is to the program: where its code
||| comes from, as the registry classifies it by the package Idris loaded
||| it from; its source file, when the project has one; and its name as a
||| location prints it. Facts of the module, which nothing the program
||| does changes.
public export
record LoadedModule where
  constructor MkLoadedModule
  origin : Origin
  source : Maybe String
  printed : Shown

||| The modules the session loaded, each with what it is to the program,
||| read once when the session has loaded the program (`Errors.modulesOf`).
public export
Modules : Type
Modules = SortedMap ModuleIdent LoadedModule

public export
record TS where
  constructor MkTS
  ||| The family instances registered, each by its link, its identity
  ||| minted once, the next one `nextFamily`; each family by its identity;
  ||| and the families in the order they were registered.
  familyIds : SortedMap (Link Form) FamilyId
  nextFamily : Nat
  families : SortedMap FamilyId Family
  familyOrder : SnocList FamilyId
  cons : SortedMap ConId ConLayout
  fns : SortedMap FnId TFn
  ||| The instances in the order they were first requested, the root first:
  ||| the order the worklist first takes them in, first in, first out
  ||| (`Finite`), and so the order of the program's functions. An instance
  ||| translated again keeps its place.
  fnOrder : SnocList FnId
  ||| The function instances requested, each by its link, its identity
  ||| minted once, in request order, the next one `nextInstance`: a number,
  ||| never text, and never part of what the program is called.
  fnIds : SortedMap (Link Form) FnId
  nextInstance : Nat
  ||| The instances requested since the worklist last took them, in the
  ||| order requested (`Finite.requestedUnder`).
  requested : SnocList Request
  ||| Where a refusal at no location of its own is: the main module, at
  ||| main once it is found (`Errors.siteAt`).
  moduleFC : NonEmptyFC
  ||| The definitions whose component of Idris's call graph has been
  ||| checked (`Recursion`), by address, each with what Idris proved of its
  ||| loops; the components are numbered as they are checked, the next one
  ||| `nextComponent`.
  loops : SortedMap Address Termination
  nextComponent : Nat
  ||| The instances made, by their identity, the link (`Keys.instanceKey`):
  ||| each with its symbol and its key.
  named : SortedMap (Link Form) (String, InstanceKey)
  ||| Each key made, with the identity it stands for: two identities on
  ||| one key are a print that drops what it claims to keep, or a
  ||| collision of the hash bits a lossy key carries, found here.
  keyLinks : SortedMap InstanceKey (Link Form)
  ||| What each case, with and nested block is called, `<parent>.case<k>`,
  ||| by its address, and every definition whose blocks are named, by its
  ||| own origin (`Keys`). A block's name depends only on the definitions,
  ||| so each is found once.
  blockNames : SortedMap Address String
  ||| The choices registered, each by the link of its interface type (the
  ||| interface at the arguments a family of it would be keyed by), its
  ||| family minted once from `nextFamily`; and each by its family.
  choiceIds : SortedMap (Link Form) FamilyId
  choices : SortedMap FamilyId Choice
  ||| The dispatches made, each by its identity, and the dispatches on each
  ||| choice, by its family, which a new member is joined with.
  dispatches : SortedMap FnId Dispatch
  dispatchesOn : SortedMap FamilyId (List FnId)
  ||| The request chain of the instance being translated: its own request,
  ||| the one that requested it, back to the root, which its block names
  ||| and its exits read; the worklist sets it (`Finite.worklist`).
  chain : List Request
  ||| The type constructors of the interfaces the program loaded, by full
  ||| name: Idris's own table of them, read once, since nothing the
  ||| translation does declares one. An implementation is a value of one
  ||| of these types, or of a pair of or a function to such values
  ||| (`Types.implementationType`).
  interfaces : SortedSet Name
  ||| The program's rejections so far, in the order they were found: a
  ||| check or an instance that is rejected does not stop the others
  ||| (`Errors.noting`), so that one run reports every independent one.
  rejected : SnocList Rejection
  ||| The definitions the checks of what the program reaches rejected, and
  ||| the user definitions that refer to them, by address: the translation
  ||| leaves them out, since what it would find there is the same
  ||| rejection again, or something the checks exist to keep from it.
  refused : SortedSet Address
  ||| The escape hatches and holes the source of a user module spells, each
  ||| rejected where it is written: by the module and the name Idris gives
  ||| what the source spells, the name a definition the program reaches
  ||| through them has, so a reach is compared with a spelling as names, not
  ||| as text.
  spelled : SortedSet (ModuleIdent, Name)
  ||| Every module the session loaded, with what it is to the program
  ||| (`LoadedModule`), read once before the checks and never changed:
  ||| every location a term of the program has is in one of them
  ||| (`Errors.toLoc`).
  modules : Modules
  ||| What the translation reads of each type constructor's definition
  ||| (`Types.tyConFacts`), by address, found once each.
  tyCons : SortedMap Address TyConFacts
  ||| What each definition takes at each binder of its type in normal form
  ||| (`Closed.argumentsOf`), by address, read once each.
  argumentsTaken : SortedMap Address (List ArgumentAt)
  ||| Each static argument a request has given, read (`StaticReading`), by its
  ||| kind and as a link writes it (`Keys.write`), which tells two
  ||| arguments apart as Idris's `==` does: an argument reads the same in
  ||| every request that gives it, so it is read once (`Instances.request`).
  readings : SortedMap (Static, Written Form) StaticReading
  ||| Each static position's height bound, written by the growth check
  ||| (`Growth.checkGrowth`) once, before the translation: a request whose
  ||| static argument is higher, or whose position has none, is the
  ||| check's unsoundness, which the worklist reports (`Finite`).
  bounds : SortedMap Position Nat
  ||| The same bounds as sizes of written arguments, per definition: the
  ||| universe the worklist descends in (`Proof.Requests.Bounds`).
  ||| Nothing is within it until the growth check writes it.
  sizes : Bounds

export
initState : Modules -> SortedSet Name -> NonEmptyFC -> TS
initState loaded ifaces fc = MkTS
  { familyIds = empty, nextFamily = 0, families = empty, familyOrder = [<]
  , cons = empty, fns = empty, fnOrder = [<], fnIds = empty, nextInstance = 0, requested = [<], moduleFC = fc
  , nextComponent = 0
  , loops = empty, named = empty, keyLinks = empty, blockNames = empty
  , choiceIds = empty, choices = empty, dispatches = empty, dispatchesOn = empty
  , chain = [], interfaces = ifaces, rejected = [<], refused = empty
  , spelled = empty, modules = loaded, tyCons = empty, argumentsTaken = empty, readings = empty, bounds = empty
  , sizes = MkBounds (const []) 0 0 0 }

||| A family registered, by its identity.
export
familyOf : FamilyId -> TS -> Maybe Family
familyOf f st = lookup f st.families

||| What a translation has found that outlives what found it, put back in
||| a state: the rejections and what they refused, and what it found of
||| definitions' arguments, type constructors, static arguments, blocks and the call
||| graph's components, facts of the program's definitions that
||| nothing the translation does changes. An instance its translation
||| rejects leaves the state as it was before it but for these
||| (`Finite.worklist`), and the translation starts with them
||| (`translating`). The modules were read before any of it, and are the
||| same in both.
export
keepFound : (from : TS) -> TS -> TS
keepFound from = { rejected := from.rejected, refused := from.refused
                 , tyCons := from.tyCons, argumentsTaken := from.argumentsTaken, readings := from.readings
                 , loops := from.loops
                 , nextComponent := from.nextComponent
                 , blockNames := from.blockNames }

||| The state the translation starts from: nothing of the phases before it
||| but the modules, the interfaces, what they found that outlives them
||| (`keepFound`), and the growth check's bounds.
export
translating : TS -> TS
translating st = keepFound st ({ bounds := st.bounds, sizes := st.sizes }
                                 (initState st.modules st.interfaces st.moduleFC))
