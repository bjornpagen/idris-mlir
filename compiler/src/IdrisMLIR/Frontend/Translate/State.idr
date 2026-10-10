||| The translation's state: the data and function instances registered so
||| far, and the function instances waiting to be translated.
module IdrisMLIR.Frontend.Translate.State

import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.SnocList
import Data.SortedMap
import Data.SortedSet

%default covering

||| Parameter classification after instantiation (`Instances.classify`). A
||| type parameter and an implementation (a value of an interface's type,
||| such as an interface constraint) are compile-time values: they key the
||| instance and are erased at runtime. Any other parameter binds as its binder says;
||| when the rest of the type depends on its value, the shape of its
||| argument keys the instance too.
public export
data PKind = TypeParam ClosedTerm | DictParam ClosedTerm | ValueParam Binder (Maybe ClosedTerm)

||| What a parameter binds at runtime: nothing for a compile-time value.
export
runtimeBinder : PKind -> Binder
runtimeBinder (ValueParam b _) = b
runtimeBinder _ = Gone

||| The compile-time value that keys an instance at this parameter, if any.
export
staticOf : PKind -> Maybe ClosedTerm
staticOf (TypeParam t) = Just t
staticOf (DictParam t) = Just t
staticOf (ValueParam _ shape) = shape

||| How a function instance came to be: its definition (with the full name
||| as `nameKey` prints it), the instance whose translation requested it
||| first, and its parameters as that call classified them.
public export
record Request where
  constructor MkRequest
  name : Name
  base : String
  parent : Maybe FnId
  kinds : List PKind

||| A function instance waiting to be translated.
public export
record Pending where
  constructor MkPending
  name : Name
  inst : FnId
  ||| The parameters as the call that requested the instance classified
  ||| them, so that the instance is translated at the same values.
  kinds : List PKind

||| What a constructor instance needs for case trees.
public export
record ConLayout where
  constructor MkConLayout
  params : List ClosedTerm   -- the data instance's type arguments
  ||| For each argument of the constructor, in order: the position of the
  ||| data type's parameter it is, or `Nothing` for a field. Idris does not
  ||| put the parameters first (`(::) : {0 len} -> {0 elem} -> ...`).
  layout : List (Maybe Nat)
  ||| The fields that hold an implementation (`Empty : Ord k => ...`), by
  ||| their position among the fields, with the field's type: compile-time
  ||| values, erased from the representation (`Dictionaries`).
  dicts : List (Nat, ClosedTerm)
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
  idrisName : Shown
  cons : List Con
  loc : Loc

public export
record TS where
  constructor MkTS
  datas : SortedMap DataId Decl
  dataOrder : SnocList DataId
  ||| The instances being registered, which a field may refer to.
  building : SortedSet DataId
  cons : SortedMap ConId ConLayout
  fns : SortedMap FnId TFn
  fnOrder : SnocList FnId
  seen : SortedSet FnId
  queue : List Pending
  moduleFC : FC
  ||| Instances per definition, which only an assertion bounds.
  perName : SortedMap String Nat
  ||| The definitions whose component of the call graph has been checked
  ||| for polymorphic recursion.
  checked : SortedSet String
  ||| Who owns each instance name: names are injective, and
  ||| a printed form that two instances share is told apart here.
  owners : SortedMap String (List (Name, List (Maybe ClosedTerm)))
  ||| The instances of each definition by their arguments, up to the names
  ||| of binders: `(x : a) -> b` and `a -> b` are one type.
  named : SortedMap String (List (List (Maybe ClosedTerm), String))
  ||| The implementation each dictionary field holds, by constructor and
  ||| position among the fields; the one part of the state a pass hands to
  ||| the next (`nextPass`).
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

export
initState : SortedSet Name -> FC -> TS
initState ifaces fc = MkTS empty [<] empty empty empty [<] empty [] fc empty empty empty empty empty empty False Nothing empty ifaces

||| The state a pass of the translation starts from: nothing of the last
||| pass but the dictionaries it found, and the interfaces.
export
nextPass : TS -> TS
nextPass st = { dicts := st.dicts } (initState st.interfaces st.moduleFC)
