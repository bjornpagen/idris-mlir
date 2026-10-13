||| The emission monad: the operations of the region being written, and
||| fresh SSA names.
module IdrisMLIR.Emit.Monad

import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Types

import Control.Monad.State
import Data.SnocList

%default total

public export
record ES where
  constructor MkES
  ||| The next SSA number of the function being written.
  next : Nat
  ||| The operations of the region being written.
  ops : SnocList Statement

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

||| A value in scope: its SSA name, its type and how often it may be used;
||| or, with `rebuild`, a constructor a match took apart, which a reference
||| builds again from its fields as the region holds them. A match uses a
||| linear scrutinee, so a variable naming it inside a case region names the
||| constructor of the fields the region bound; its `name` is then a key no
||| operation defines, which `matched` (Bodies) renames by.
public export
record Val where
  constructor MkVal
  name : String
  type : Ty
  use : Quantity
  rebuild : Maybe (ConId, List Val)

export
val : String -> Ty -> Quantity -> Val
val name type use = MkVal name type use Nothing

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
