||| The translation's state: the data and function instances registered so
||| far, and the function instances waiting to be translated.
module IdrisMLIR.Frontend.Translate.State

import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Term

import Data.SnocList
import Data.SortedMap
import Data.SortedSet

%default covering

||| A function instance waiting to be translated.
public export
record Pending where
  constructor MkPending
  name : Name
  inst : FnId
  ||| The compile-time arguments, by position.
  statics : List (Maybe ClosedTerm)
  ||| The instances that requested this one, innermost first, with the size
  ||| of their keys, to catch polymorphic recursion.
  path : List (String, String)

||| What a constructor instance needs for case trees.
public export
record ConLayout where
  constructor MkConLayout
  params : List ClosedTerm   -- the data instance's type arguments
  ||| For each argument of the constructor, in order: the position of the
  ||| data type's parameter it is, or `Nothing` for a field. Idris does not
  ||| put the parameters first (`(::) : {0 len} -> {0 elem} -> ...`).
  layout : List (Maybe Nat)
  con : Con

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
  nextLabel : Nat
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
  current : List (String, String)     -- the path of the instance being translated
  perName : SortedMap String Nat      -- instances per definition
  ||| Who owns each instance name: names are injective, and
  ||| a printed form that two instances share is told apart here.
  owners : SortedMap String (List (Name, List (Maybe ClosedTerm)))
  ||| The instances of each definition by their arguments, up to the names
  ||| of binders: `(x : a) -> b` and `a -> b` are one type.
  named : SortedMap String (List (List (Maybe ClosedTerm), String))

export
initState : FC -> TS
initState fc = MkTS 0 empty [<] empty empty empty [<] empty [] fc [] empty empty empty

||| A fresh program point for a lambda or `Delay`.
export
label : {auto s : Ref TState TS} -> Core Label
label = do
  st <- get TState
  put TState ({ nextLabel $= S } st)
  pure (MkLabel st.nextLabel)
