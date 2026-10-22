-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The emission monad: the operations of the region being written, fresh
||| SSA names, and the functions the lambdas and delays of the function
||| being written become.
module IdrisMLIR.Emit.Monad

import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.List1
import Data.SnocList
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
  ||| its lambdas and delays become: its identity, its symbol, its Idris
  ||| definition (where their code is from, and the function a crash in
  ||| them names), and what Idris proved of its loops, which they take.
  owner : FnId
  ownerSymbol : String
  definition : Shown
  termination : Termination
  ||| Those functions, each with its symbol, in the order their bodies were
  ||| finished, which is also the ordinal each symbol carries.
  lifted : SnocList (String, Statement)
  liftedCount : Nat
  ||| The next number a binder of the definition is given, its parameters
  ||| first: with the definition's symbol, a binder's identity.
  nextBinder : Nat

||| The state before the function `f` of the program is written.
export
initial : TFn -> ES
initial f = MkES 0 [<] f.id f.symbol (shown f.key.origin) f.termination [<] 0 f.arity

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

namespace Held
  ||| Who frees what a value of a type that holds references holds, and
  ||| what is known of its sharing where the ops' own result types know it:
  ||| its count, with nothing known; its count, and nothing else reaches
  ||| what it reaches (a constructor's fresh value, and a field taken or
  ||| read at a linear position from such a value); or nobody, a literal's
  ||| static data, which lives for the run. The frontend writes no weaker
  ||| grade than an op's inference gives, and no stronger one.
  public export
  data Held = Counted | Exclusive | Static

||| What is known of which constructor a value of a family is: nothing
||| more than its type says, or one of those listed, as inside a region of
||| a match on it, where its type says so and a field read of it is total.
public export
data Refinement = AnyConstructor | OneOf (List1 Nat)

||| A value: its SSA name, its type, how often it may be used, how it is
||| held, and which constructors it is known to be. Its MLIR type is these
||| together (`Index.valueType`).
public export
record Val where
  constructor MkVal
  name : String
  type : Ty
  uses : Uses
  hold : Held
  refinement : Refinement

||| A value known to be no more than its type says.
export
val : String -> Ty -> Uses -> Held -> Val
val n t u h = MkVal n t u h AnyConstructor

||| What a variable in scope stands for: one SSA value; or Idris's world,
||| which is no value of the module, since after the frontend IO is ordered
||| by effects alone.
public export
data InScope = Whole Val | World

||| The variable a context binds a value to: its name, the quantity it
||| holds the value at, which is its binder's, never demoted, and its
||| identity, the definition's symbol and its number there.
public export
record Binding where
  constructor MkBinding
  name : Shown
  held : Uses
  definition : String
  number : Nat

||| A binder of the definition being written, numbered: the variable a
||| context binds its value to.
export
binding : Shown -> Uses -> E Binding
binding name q = do
  st <- get
  put ({ nextBinder $= S } st)
  pure (MkBinding name q st.ownerSymbol st.nextBinder)

||| Where a value stands in its function: as its result (`InTail`); as the
||| last field computed of a constructor that is its result or another such
||| field (`InContext`), where a call of the function itself is a loop with
||| a destination; or anywhere else. A call carries what this gives it.
public export
data Position = InTail | InContext | Elsewhere

||| What a context wants of the value a term gives: the type it expects, if
||| it knows it, the variable it binds the value to, if it binds one, and
||| where the value stands.
public export
record Wanted where
  constructor MkWanted
  type : Maybe Ty
  binder : Maybe Binding
  position : Position

||| A context that expects a value of a type, if it knows it, binds it to
||| no variable, and uses it before its function returns: an operand's.
export
expecting : Maybe Ty -> Wanted
expecting t = MkWanted t Nothing Elsewhere

||| Where an op that makes a value bound to `binder` stands: at the name of
||| the variable, when the variable holds it as it is made, so that MLIR
||| names the SSA value after the Idris variable (an op's result has the
||| op's location, the one place MLIR keeps a result's name); else at `l`.
||| A value made at other uses than its variable's is cast into it by an op
||| of its own, which stands at the name.
export
madeAt : Maybe Binding -> Loc -> Uses -> Location
madeAt (Just b) l u = case (b.held, u) of
  (Once, Once) => Binder b.name l b.definition b.number
  (Many, Many) => Binder b.name l b.definition b.number
  _ => At l
madeAt Nothing l u = At l
