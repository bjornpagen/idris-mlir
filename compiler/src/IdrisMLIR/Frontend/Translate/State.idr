-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The translation's state: the data and function instances registered so
||| far, and the function instances waiting to be translated.
module IdrisMLIR.Frontend.Translate.State

import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.SnocList
import Data.SortedMap
import Data.SortedSet

%default covering

||| The runtime values an implementation closes over (`DictParam`,
||| `Closed.Static`): their types, in the order of the markers that stand
||| for them in its compile-time form (`Closed.holeMarker`), and the one
||| parameter that holds them: the value itself, or, for more than one, a
||| pair of the first and the rest (`Closed.packedType`).
public export
record Holes where
  constructor MkHoles
  types : List ClosedTerm
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

||| What a parameter binds at runtime, if it is a parameter at runtime.
export
runtimeBinder : PKind -> Maybe Binder
runtimeBinder (ValueParam b _ _) = Just b
runtimeBinder (DictParam _ (Just h)) = Just h.binder
runtimeBinder _ = Nothing

||| The compile-time value that keys an instance at this parameter, if any.
export
staticOf : PKind -> Maybe ClosedTerm
staticOf (TypeParam t) = Just t
staticOf (DictParam t _) = Just t
staticOf ErasedParam = Nothing
staticOf (FormParam f) = Just f
staticOf (ValueParam _ shape _) = shape

||| A full name, printed so that different names print differently: Idris's
||| `show` prints only the display part of a `DN` and leaves out the index of
||| a case or with block. The translation's own maps are keyed by it; it is
||| no part of what the program is called, which `Keys` prints.
export
nameKey : Name -> String
nameKey (NS ns n) = show (NS ns (UN (Basic (nameKey n))))
nameKey (DN str n) = str ++ "{" ++ nameKey n ++ "}"
nameKey (CaseBlock outer i) = "case block " ++ show i ++ " in " ++ outer
nameKey (WithBlock outer i) = "with block " ++ show i ++ " in " ++ outer
nameKey n = show n

||| How a function instance came to be: its definition (with the full name
||| as `nameKey` prints it), the instance whose translation requested it
||| first, its parameters as that call classified them, and its key, which
||| a refusal of the chain names.
public export
record Request where
  constructor MkRequest
  name : Name
  base : String
  parent : Maybe FnId
  kinds : List PKind
  key : InstanceKey

||| Instances waiting to be translated, first in first out: the front in
||| order and the back as requested. Requesting is constant time, and
||| taking the next is amortised constant, since the back is reversed into
||| the front only when the front is empty. A list appended at its end
||| would copy every waiting instance at every request.
public export
record Queue a where
  constructor MkQueue
  front : List a
  back : SnocList a

export
emptyQueue : Queue a
emptyQueue = MkQueue [] [<]

export
enqueue : a -> Queue a -> Queue a
enqueue x q = { back $= (:< x) } q

export
dequeue : Queue a -> Maybe (a, Queue a)
dequeue (MkQueue (x :: xs) b) = Just (x, MkQueue xs b)
dequeue (MkQueue [] b) = case b <>> [] of
  [] => Nothing
  (x :: xs) => Just (x, MkQueue xs [<])

||| A function instance waiting to be translated.
public export
record Pending where
  constructor MkPending
  name : Name
  inst : FnId
  ||| What the instance is an instance of, as the request found it.
  key : InstanceKey
  ||| The parameters as the call that requested the instance classified
  ||| them, so that the instance is translated at the same values.
  kinds : List PKind

||| One argument of a constructor, as a data instance has it. Idris does not
||| put the data type's parameters first (`(::) : {0 len} -> {0 elem} ->
||| ...`), so every argument says what it is: a parameter, whose value the
||| instance gives; an argument of quantity 0, which is no field; an
||| implementation (`Empty : Ord k => ...`), a compile-time value of the
||| instance (`Dictionaries`), with its type; or runtime field `i`, counting
||| the runtime fields from 0, with its binder and its Idris type at
||| the instance.
public export
data ArgKind = Param ClosedTerm
             | ErasedArg
             | DictArg ClosedTerm
             | Field Nat Binder ClosedTerm

||| The binder of a runtime field.
export
fieldBinder : ArgKind -> Maybe Binder
fieldBinder (Field _ b _) = Just b
fieldBinder _ = Nothing

||| What a constructor instance needs for case trees: its arguments, its
||| full name, and the constructor as Core has it, whose fields are the
||| runtime ones.
public export
record ConLayout where
  constructor MkConLayout
  args : List ArgKind
  name : Name
  con : Con

||| The one implementation a dictionary field holds in the whole program,
||| and the user definition that chose it: the one the first construction
||| site's instance was requested for, through the library's instances.
public export
record Dictionary where
  constructor MkDictionary
  impl : ClosedTerm
  chooser : String
  site : FC

export
data TState : Type where

||| A data instance as it is registered. Its representation is decided once
||| every instance is known (`assemble`): a box exactly when its
||| containment is recursive.
public export
record Decl where
  constructor MkDecl
  id : DataId
  key : InstanceKey
  cons : List Con
  loc : Loc
  ||| The promise its type's values keep, which the registry names.
  promise : Maybe Promise

||| What the translation reads of a type constructor's definition: its
||| parameters, the type parameters among them that a value represents, and
||| whether it is `Nat`-like.
public export
record TyConFacts where
  constructor MkTyConFacts
  params : List Nat
  typeParams : List Nat
  natLike : Bool

public export
record TS where
  constructor MkTS
  datas : SortedMap DataId Decl
  dataOrder : SnocList DataId
  ||| The instances being registered, which a field may refer to.
  building : SortedSet DataId
  ||| The instances a field referred to while they were being registered:
  ||| each is declared, whatever its shape, since its values contain
  ||| themselves.
  reentered : SortedSet DataId
  ||| The instances with one constructor and one runtime field, by the
  ||| binder of that field, whose type is the type of their values: they
  ||| are not declared, and their constructor is the identity. The binder
  ||| keeps the field's quantity, which a binder of the instance's type
  ||| takes through its own (`coreBinder`).
  newtypes : SortedMap DataId Binder
  cons : SortedMap ConId ConLayout
  fns : SortedMap FnId TFn
  fnOrder : SnocList FnId
  seen : SortedSet FnId
  queue : Queue Pending
  moduleFC : FC
  ||| The definitions whose component of the call graph has been checked
  ||| (`Recursion`), by `nameKey`, each with whether every loop through it
  ||| terminates.
  loops : SortedMap String Bool
  ||| The instances of each definition by their arguments, up to the names
  ||| of binders (`(x : a) -> b` and `a -> b` are one type), bucketed by a
  ||| hash of the arguments: each with its identity and its key.
  named : SortedMap String (List (List (Maybe ClosedTerm), (String, InstanceKey)))
  ||| Each symbol made, with the identity it names: the definition, by
  ||| `nameKey`, and its arguments. A symbol is a function of its key, so
  ||| two identities on one are a broken invariant, found here.
  symbols : SortedMap String (String, List (Maybe ClosedTerm))
  ||| What each case, with and nested block is called, `<parent>.case<k>`,
  ||| by `nameKey`, and every definition whose blocks are named, by its own
  ||| origin (`Keys`). A block's name depends only on the definitions, so
  ||| each is found once and kept from pass to pass.
  blockNames : SortedMap String String
  ||| The implementation each dictionary field holds, by constructor and
  ||| position among its arguments; the one part of the state a pass hands
  ||| to the next (`nextPass`).
  dicts : SortedMap (ConId, Nat) Dictionary
  ||| The dictionary fields matched in this pass before any construction
  ||| site gave their implementation: their alternatives were translated as
  ||| unreachable, which a construction site seen later contradicts.
  assumed : SortedSet (ConId, Nat)
  ||| A construction site contradicted an assumption: the pass is void, and
  ||| the translation starts over with what it learnt.
  restart : Bool
  ||| The instance being translated.
  current : Maybe FnId
  ||| How each instance came to be: the chain back to the user definition
  ||| it serves, and to the instances of its own definition it comes from.
  requesters : SortedMap FnId Request
  ||| The type constructors of the interfaces the program loaded, by full
  ||| name: Idris's own table of them, read once, since nothing the
  ||| translation does declares one. An implementation is a value of one
  ||| of these types, or of a pair of or a function to such values
  ||| (`Types.implementationType`).
  interfaces : SortedSet Name
  ||| The program's rejections so far, in the order they were found: a
  ||| check or an instance that is rejected does not stop the others
  ||| (`Errors.noting`), so that one run reports every independent one.
  rejected : SnocList Error
  ||| The definitions the checks of what the program reaches rejected, and
  ||| the user definitions that refer to them, by `nameKey`: the translation
  ||| leaves them out, since what it would find there is the same
  ||| rejection again, or something the checks exist to keep from it.
  refused : SortedSet String
  ||| The escape hatches and holes the source of a user module spells, by
  ||| module and name, each rejected where it is written.
  spelled : SortedSet (String, String)
  ||| Where each module a location names comes from and its source file, by
  ||| the module's name: facts of the module, found once each
  ||| (`Errors.toLoc`), which no pass and no rejection changes.
  places : SortedMap String (Origin, String)
  ||| What the translation reads of each type constructor's definition
  ||| (`Types.tyConFacts`), by `nameKey`, found once each.
  tyCons : SortedMap String TyConFacts

export
initState : SortedSet Name -> FC -> TS
initState ifaces fc = MkTS empty [<] empty empty empty empty empty [<] empty emptyQueue fc empty empty empty empty empty empty False Nothing empty ifaces [<] empty empty empty empty

||| The state a pass of the translation starts from: nothing of the last
||| pass but the dictionaries it found, the interfaces, the rejections and
||| what they refused, and what it found of modules, type constructors,
||| blocks and the call graph's components (`places`, `tyCons`,
||| `blockNames`, `loops`). A void pass's rejections stay: the first one
||| found is the one the program is refused with, whichever pass found it.
export
nextPass : TS -> TS
nextPass st = { dicts := st.dicts, rejected := st.rejected, refused := st.refused, places := st.places
               , tyCons := st.tyCons, loops := st.loops, blockNames := st.blockNames }
                (initState st.interfaces st.moduleFC)
