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
  cons : SortedMap ConId ConLayout
  fns : SortedMap FnId TFn
  fnOrder : SnocList FnId
  seen : SortedSet FnId
  queue : Queue Pending
  moduleFC : FC
  ||| Instances per definition, which only an assertion bounds.
  perName : SortedMap String Nat
  ||| The definitions whose component of the call graph has been checked
  ||| (`Recursion`), by `nameKey`, each with whether every loop through it
  ||| terminates.
  loops : SortedMap String Bool
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
initState ifaces fc = MkTS empty [<] empty empty empty [<] empty emptyQueue fc empty empty empty empty empty empty False Nothing empty ifaces [<] empty empty empty empty

||| The state a pass of the translation starts from: nothing of the last
||| pass but the dictionaries it found, the interfaces, the rejections and
||| what they refused, and what it found of modules, type constructors and
||| the call graph's components (`places`, `tyCons`, `loops`). A void pass's rejections
||| stay: the first one found is the one the program is refused with,
||| whichever pass found it.
export
nextPass : TS -> TS
nextPass st = { dicts := st.dicts, rejected := st.rejected, refused := st.refused, places := st.places
               , tyCons := st.tyCons, loops := st.loops }
                (initState st.interfaces st.moduleFC)
