-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The emission monad: the operations of the region being written, fresh
||| SSA names, and the functions the lambdas and delays of the function
||| being written become.
module IdrisMLIR.Emit.Monad

import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.SnocList
import Data.SortedMap
import Data.Vect

%default total

public export
record ES where
  constructor MkES
  ||| The next SSA number of the function being written.
  next : Nat
  ||| The operations of the region being written.
  ops : SnocList Statement
  ||| The function of the program being written, which owns the functions
  ||| its lambdas and delays become, and its Idris definition, where their
  ||| code is from.
  owner : FnId
  definition : Shown
  ||| Those functions, each with its symbol, in the order their bodies were
  ||| finished, and the key of each by its symbol, the name MLIR is given,
  ||| so that two contents on one name are found: one function per key.
  lifted : SnocList (String, Statement)
  keys : SortedMap String String

||| The state before the function `owner` of the program, from the
||| definition `definition`, is written.
export
initial : FnId -> Shown -> ES
initial owner definition = MkES 0 [<] owner definition [<] empty

public export
E : Type -> Type
E = StateT ES (Either String)

||| What `Emit` cannot write is a bug of the frontend.
export
internal : String -> E a
internal msg = lift (Left msg)

export
fresh : E String
fresh = do
  st <- get
  put ({ next $= S } st)
  pure ("%" ++ show st.next)

export
append : Statement -> E ()
append s = modify { ops $= (:< s) }

||| The operations `act` appends, apart from the current region's.
export
collect : E a -> E (a, List Statement)
collect act = do
  saved <- gets (.ops)
  modify { ops := [<] }
  x <- act
  inner <- gets (.ops)
  modify { ops := saved }
  pure (x, inner <>> [])

||| Whether a value of type `t`, used as `q` says, is held linearly
||| (`!idr.lin<T>`): used exactly once, unless it is the world, which is
||| linear by its own type and held as itself.
public export
linear : Quantity -> Ty -> Bool
linear One WorldT = False
linear One _ = True
linear Many _ = False

||| A value: its SSA name, its type, and how often it may be used.
public export
record Val where
  constructor MkVal
  name : String
  type : Ty
  use : Quantity

||| What a variable in scope stands for: one SSA value, or a constructor a
||| match took apart, which a use builds again from its fields as the region
||| holds them. A match uses a linear scrutinee, so a variable naming it
||| inside a case region names the constructor of the fields the region
||| bound. A constructor taken apart is no SSA value: its key, which no
||| operation defines, is what `matched` (Bodies) renames by.
public export
data InScope : Type where
  Whole : Val -> InScope
  Taken : {k : Nat} -> Con k -> Vect k InScope -> String -> InScope

||| The variable a context binds a value to: its name, and the quantity it
||| holds the value at.
public export
record Binding where
  constructor MkBinding
  name : Shown
  held : Quantity

||| What a context wants of the value a term gives: the type it expects, if
||| it knows it, and the variable it binds the value to, if it binds one.
public export
record Wanted where
  constructor MkWanted
  type : Maybe Ty
  binder : Maybe Binding

||| A context that expects a value of a type, if it knows it, and binds it
||| to no variable: an operand's, a region's, a function's.
export
expecting : Maybe Ty -> Wanted
expecting t = MkWanted t Nothing

||| Where an op that makes a value of type `t`, held as `u`, stands: at the
||| name of the variable the value is bound to, when the variable holds it
||| as it is made, so that MLIR names the SSA value after the Idris
||| variable (an op's result has the op's location, the one place MLIR keeps
||| a result's name); else at `l`. A value made at another quantity than
||| its variable's is entered or used into it by an op of its own, which
||| stands at the name.
export
madeAt : Maybe Binding -> Loc -> Ty -> Quantity -> Location
madeAt (Just b) l t u = if linear u t == linear b.held t then Named b.name l else At l
madeAt Nothing l t u = At l
