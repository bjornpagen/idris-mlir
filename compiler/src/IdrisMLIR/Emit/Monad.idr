||| The emission monad: the operations of the region being written, and
||| fresh SSA names.
module IdrisMLIR.Emit.Monad

import IdrisMLIR.Ids
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

||| Whether a value of type `t`, used as `u` says, is held linearly
||| (`!idr.lin<T>`): used exactly once, unless it is the world, which is
||| linear by its own type and held as itself.
public export
linear : Use -> Ty -> Bool
linear Once WorldT = False
linear Once _ = True
linear Many _ = False

||| How often the value a binder binds is used; the erased value is never
||| used, and is held as itself.
public export
binderUse : Binder -> Use
binderUse Gone = Many
binderUse (Held u _) = u

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
  use : Use
  rebuild : Maybe (ConId, List Val)

export
val : String -> Ty -> Use -> Val
val name type use = MkVal name type use Nothing
