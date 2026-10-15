-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The emission monad: the operations of the region being written, fresh
||| SSA names, and the functions the lambdas and delays of the function
||| being written become.
module IdrisMLIR.Emit.Monad

import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Types

import Control.Monad.State
import Data.SnocList
import Data.SortedMap

%default total

public export
record ES where
  constructor MkES
  ||| The next SSA number of the function being written.
  next : Nat
  ||| The operations of the region being written.
  ops : SnocList Statement
  ||| The symbol of the function of the program being written, which owns
  ||| the functions its lambdas and delays become, and its Idris
  ||| definition, where their code is from.
  owner : String
  definition : Shown
  ||| Those functions, in the order their bodies were finished, and the key
  ||| of each by its symbol: one function per key.
  lifted : SnocList Statement
  keys : SortedMap String String

||| The state before the function of the program named `owner`, from the
||| definition `definition`, is written.
export
initial : String -> Shown -> ES
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

mutual
  ||| How a value in scope is held: as the one SSA value its name names, or
  ||| as a constructor a match took apart, which a reference builds again
  ||| from its fields as the region holds them. A match uses a linear
  ||| scrutinee, so a variable naming it inside a case region names the
  ||| constructor of the fields the region bound. Taken apart, a value's
  ||| `name` is a key no operation defines, which `matched` (Bodies) renames
  ||| by.
  public export
  data Parts = Whole | Taken ConId (List Val)

  ||| A value in scope: its SSA name, its type, how often it may be used,
  ||| and how it is held.
  public export
  record Val where
    constructor MkVal
    name : String
    type : Ty
    use : Quantity
    parts : Parts

export
val : String -> Ty -> Quantity -> Val
val name type use = MkVal name type use Whole

||| What the newest operation of the region defines, if it defines anything.
export
newest : E (Maybe String)
newest = gets (\st => case st.ops of
  _ :< s => s.result
  [<] => Nothing)

||| The value a binder names: if the newest operation defines `v`, and did
||| not already when `newest` read `before`, it is at the binder's name over
||| its own span, so the printer names the SSA value after the Idris
||| variable. An op's result has the op's location, the one place MLIR keeps
||| a result's name. A `let` of a variable or of a block argument defines no
||| new value, and the value keeps the location it has.
export
atBinder : Shown -> Maybe String -> Val -> E ()
atBinder name before v = when (before /= Just v.name) (modify { ops $= rename })
  where
    spanOf : Location -> Loc
    spanOf (At l) = l
    spanOf (Named _ l) = l
    rename : SnocList Statement -> SnocList Statement
    rename (rest :< s) =
      if s.result == Just v.name then rest :< MkStatement s.result s.op (Named name (spanOf s.at))
                                     else rest :< s
    rename [<] = [<]
