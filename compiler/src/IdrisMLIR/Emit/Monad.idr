-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The emission monad: the operations of the region being written, fresh
||| binder numbers, which name the values they bind, and the functions the
||| lambdas and delays of the function being written become.
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
initial f = MkES 0 [<] f.callee.fn f.callee.symbol (shown f.key.origin) f.termination [<] 0 f.arity

||| What Emit cannot write, a bug of the frontend: at `site`, a value of
||| type `given` where the slot taking it has type `expected`, the two apart
||| by more than a cast or a reindex fits. `what` says, for the message,
||| what the value is.
public export
record Unfit where
  constructor MkUnfit
  site : Loc
  what : String
  given : Ty
  expected : Ty

||| What was given where what was expected; the site is the message's own.
export
Show Unfit where
  show u = u.what ++ " of type " ++ show u.given ++ " where " ++ show u.expected ++ " is expected"

public export
E : Type -> Type
E = StateT ES (Either Unfit)

||| A value Emit cannot fit into the slot taking it (`Unfit`).
export
unfit : Unfit -> E a
unfit u = lift (Left u)

||| The next binder's number in the function: a statement's or a block
||| argument's, each value it binds named by it (`Bound`).
export
fresh : E Nat
fresh = do
  st <- get
  put ({ next $= S } st)
  pure st.next

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

||| What is known of which constructor a value of a family is: nothing
||| more than its type says, or one of those listed, as inside a region of
||| a match on it, where its type says so and a field read of it is total.
public export
data Refinement = AnyConstructor | OneOf (List1 Nat)

||| A value: its identity, its type, how often it may be used, how it is
||| held, the grade's hold (who frees what it holds, and what is known of
||| its sharing), and which constructors it is known to be. Its MLIR type
||| is these together (`Index.valueType`). The frontend writes no weaker
||| hold than an op's inference gives, and no stronger one.
public export
record Val where
  constructor MkVal
  name : ValueId
  type : Ty
  uses : Uses
  hold : Hold
  refinement : Refinement

||| A value known to be no more than its type says.
export
val : ValueId -> Ty -> Uses -> Hold -> Val
val n t u h = MkVal n t u h AnyConstructor

||| Idris's world as a value the fold passes along: no value of the
||| module, so it is bound to none, and its type keeps it out of every op.
export
worldVal : Val
worldVal = val Unbound WorldT Once made

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

||| What a context wants of the value a term gives: the type it expects, if
||| it knows it, and the variable it binds the value to, if it binds one.
public export
record Wanted where
  constructor MkWanted
  type : Maybe Ty
  binder : Maybe Binding

||| A context that expects a value of a type, if it knows it, and binds it
||| to no variable.
export
expecting : Maybe Ty -> Wanted
expecting t = MkWanted t Nothing

||| An op at a place no variable names.
unbound : Place -> Location
unbound (Spanned l) = At l
unbound (Lowered d l) = Named d l

||| Where an op that makes a value bound to `binder` stands, at the place
||| `p`: at the name of the variable, when the variable holds it as it is
||| made, so that MLIR names the SSA value after the Idris variable (an
||| op's result has the op's location, the one place MLIR keeps a result's
||| name); else at the place, a span, or the library definition the
||| registry lowered there. A value made at other uses than its variable's
||| is cast into it by an op of its own, which stands at the name.
export
madeAtPlace : Maybe Binding -> Place -> Uses -> Location
madeAtPlace (Just b) p u = case (b.held, u) of
  (Once, Once) => Binder b.name p b.definition b.number
  (Many, Many) => Binder b.name p b.definition b.number
  _ => unbound p
madeAtPlace Nothing p u = unbound p

||| Where an op that makes a value bound to `binder` stands at the span
||| `l`, as `madeAtPlace` says.
export
madeAt : Maybe Binding -> Loc -> Uses -> Location
madeAt binder l = madeAtPlace binder (Spanned l)

||| The place of an op at `l`: where the registry lowered the library
||| definition `stands` names, if it lowered one there.
export
placeOf : Maybe Shown -> Loc -> Place
placeOf Nothing l = Spanned l
placeOf (Just d) l = Lowered d l
