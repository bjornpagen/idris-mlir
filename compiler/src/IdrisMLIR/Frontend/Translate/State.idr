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
||| replaced by markers, and the parameter holds the values (`Holes`). A
||| parameter of quantity 0 is no parameter at runtime and keys nothing. Any
||| other binds as its binder says, with its closed Idris type, which tells
||| a function-typed value's erased arguments from its runtime ones; when
||| the rest of the type depends on its value, the shape of its argument
||| keys the instance too. An erased shape of the array language that a
||| value array's type needs is its form, the spine with every extent
||| erased: it keys the instance, since a tensor's rank is its type. The
||| kinds stay positional, one per parameter of the definition's type, as
||| the case tree's scope has one variable per parameter.
public export
data PKind = TypeParam ClosedTerm
           | DictParam ClosedTerm (Maybe Holes)
           | ErasedParam
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
staticKindOf ErasedParam = Nothing
staticKindOf (FormParam f) = Just (Element AForm ReadAsForm, f)
staticKindOf (ValueParam _ shape _) = (Element AShape ReadAsShape,) <$> shape

||| A full name, printed so that different names print differently: Idris's
||| `show` prints only the display part of a `DN` and leaves out the index of
||| a case or with block. It is a print, for a message that names a
||| definition; no table is keyed by it, since a definition is its address
||| (`definitionAddress`), and it is no part of what the program is called,
||| which `Keys` prints.
export
nameKey : Name -> String
nameKey (NS ns n) = show (NS ns (UN (Basic (nameKey n))))
nameKey (DN str n) = str ++ "{" ++ nameKey n ++ "}"
nameKey (CaseBlock outer i) = "case block " ++ show i ++ " in " ++ outer
nameKey (WithBlock outer i) = "with block " ++ show i ++ " in " ++ outer
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

||| A dictionary field: the link of its data instance (`Keys.instanceKey`),
||| its constructor's index among the type's constructors, and its
||| argument's among the constructor's. Built where the constructor's
||| layout is (`Types`), so every reader holds the one key.
public export
DictField : Type
DictField = (Link Form, Nat, Nat)

||| One argument of a constructor, as a data instance has it. Idris does not
||| put the data type's parameters first (`(::) : {0 len} -> {0 elem} ->
||| ...`), so every argument says what it is: a parameter, whose value the
||| instance gives; an argument of quantity 0, which is no field; an
||| implementation (`Empty : Ord k => ...`), a compile-time value of the
||| instance (`Dictionaries`), with its field's key and its type; or
||| runtime field `i`, counting the runtime fields from 0, with its binder
||| and its Idris type at the instance.
public export
data ArgKind = Param ClosedTerm
             | ErasedArg
             | DictArg DictField ClosedTerm
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

||| The one implementation a dictionary field holds in the whole program,
||| and the user definition that chose it, as a refusal prints it: the one
||| the first construction site's instance was requested for, through the
||| library's instances.
public export
record Dictionary where
  constructor MkDictionary
  impl : ClosedTerm
  chooser : Shown
  site : FC

export
data TState : Type where

||| What a type constructor's values are, as numbers go.
public export
data Natness = NotNat     -- not Nat-like
             | Numeral    -- Nat-like (Idris's ZERO/SUCC), but a constructor takes an erased argument (Fin's FS)
             | Chain      -- Nat-like, every constructor argument at run time: a shape is a chain of S

||| What the translation reads of a type constructor's definition: its
||| parameters, the type parameters among them that a value represents, what
||| its values are as numbers go, and the arguments its values hold, which
||| the growth check watches (`Types.represented`).
public export
record TyConFacts where
  constructor MkTyConFacts
  params : List Nat
  typeParams : List Nat
  natness : Natness
  represented : List Nat

||| A data instance as registered: declared, a sum of its constructors; or a
||| newtype, one constructor of one runtime field, not declared, its
||| constructor the identity, by the binder of that field, whose type is the
||| type of its values. The binder keeps the field's quantity, which a
||| binder of the instance's type takes through its own (`coreBinder`).
public export
data Registered = Declared IdrisMLIR.Term.Data | Newtype Binder

public export
record TS where
  constructor MkTS
  ||| The data instances registered, each declared or a newtype.
  instances : SortedMap DataId Registered
  ||| The declared instances in the order they were registered.
  dataOrder : SnocList DataId
  ||| The instances a field referred to while they were being registered:
  ||| each is declared, whatever its shape, since its values contain
  ||| themselves.
  reentered : SortedSet DataId
  cons : SortedMap ConId ConLayout
  fns : SortedMap FnId TFn
  ||| The instances in the order they were first requested, the root first:
  ||| the order the worklist first takes them in, first in, first out
  ||| (`Finite`), and so the order of the program's functions. An instance
  ||| translated again keeps its place.
  fnOrder : SnocList FnId
  seen : SortedSet FnId
  ||| The instances requested since the worklist last took them, in the
  ||| order requested (`Finite.requestedUnder`).
  requested : SnocList Request
  ||| Where a refusal at no location of its own is: the main module, at
  ||| main once it is found (`Errors.siteAt`).
  moduleFC : NonEmptyFC
  ||| The refusal being unwound to `Errors.noting`, which records it: Idris's
  ||| own `Error` cannot carry a `Refusal`, so the one in flight is here.
  inFlight : Maybe Refusal
  ||| The definitions whose component of the call graph has been checked
  ||| (`Recursion`), by address, each with whether every loop through it
  ||| terminates.
  loops : SortedMap Address Bool
  ||| The instances made, by their identity, the link (`Keys.instanceKey`):
  ||| each with its symbol and its key.
  named : SortedMap (Link Form) (String, InstanceKey)
  ||| Each symbol made, with the identity it names. A symbol is a function
  ||| of its key, so two identities on one are a broken invariant, found
  ||| here.
  symbols : SortedMap String (Link Form)
  ||| What each case, with and nested block is called, `<parent>.case<k>`,
  ||| by its address, and every definition whose blocks are named, by its
  ||| own origin (`Keys`). A block's name depends only on the definitions,
  ||| so each is found once.
  blockNames : SortedMap Address String
  ||| The implementation each dictionary field holds, by its key.
  dicts : SortedMap DictField Dictionary
  ||| The dictionary fields the instance being translated matched before
  ||| any construction site gave their implementation: it translated their
  ||| alternatives as unreachable, and is translated again once a
  ||| construction site gives one (`Finite`), which keeps them per instance.
  assumed : SortedSet DictField
  ||| The request chain of the instance being translated: its own request,
  ||| the one that requested it, back to the root. It leads back to the user
  ||| definition a library instance serves (`Dictionaries.chooser`); the
  ||| worklist sets it (`Finite.worklist`).
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
  ||| The escape hatches and holes the source of a user module spells, by
  ||| module and the name as spelt, each rejected where it is written.
  spelled : SortedSet (ModuleIdent, String)
  ||| Where each module a location names comes from and its source file
  ||| when the project has it, by the module: facts of the module, found
  ||| once each (`Errors.toLoc`), which no rejection changes.
  places : SortedMap ModuleIdent (Origin, Maybe String)
  ||| What the translation reads of each type constructor's definition
  ||| (`Types.tyConFacts`), by address, found once each.
  tyCons : SortedMap Address TyConFacts
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
initState : SortedSet Name -> NonEmptyFC -> TS
initState ifaces fc = MkTS
  { instances = empty, dataOrder = [<], reentered = empty
  , cons = empty, fns = empty, fnOrder = [<], seen = empty, requested = [<], moduleFC = fc, inFlight = Nothing
  , loops = empty, named = empty, symbols = empty, blockNames = empty, dicts = empty
  , assumed = empty, chain = [], interfaces = ifaces, rejected = [<], refused = empty
  , spelled = empty, places = empty, tyCons = empty, readings = empty, bounds = empty
  , sizes = MkBounds (const []) 0 0 0 }

||| The declaration of a data instance registered as a sum.
export
declared : DataId -> TS -> Maybe IdrisMLIR.Term.Data
declared inst st = case lookup inst st.instances of
  Just (Declared d) => Just d
  _ => Nothing

||| The field binder of a data instance registered as a newtype.
export
newtypeOf : DataId -> TS -> Maybe Binder
newtypeOf inst st = case lookup inst st.instances of
  Just (Newtype b) => Just b
  _ => Nothing

||| What a translation has found that outlives what found it, put back in
||| a state: the rejections and what they refused (no refusal is in flight
||| once one is recorded), and what it found of
||| modules, type constructors, static arguments, blocks and the call
||| graph's components, facts of the program's definitions that
||| nothing the translation does changes. An instance its translation
||| rejects leaves the state as it was before it but for these
||| (`Finite.worklist`), and the translation starts with them
||| (`translating`).
export
keepFound : (from : TS) -> TS -> TS
keepFound from = { rejected := from.rejected, inFlight := Nothing, refused := from.refused, places := from.places
                 , tyCons := from.tyCons, readings := from.readings, loops := from.loops
                 , blockNames := from.blockNames }

||| The state the translation starts from: nothing of the phases before it
||| but the dictionaries, the interfaces, what they found that outlives
||| them (`keepFound`), and the growth check's bounds.
export
translating : TS -> TS
translating st = keepFound st ({ dicts := st.dicts, bounds := st.bounds, sizes := st.sizes }
                                 (initState st.interfaces st.moduleFC))
