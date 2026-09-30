||| The emission monad: the operations of the region being written, the
||| functions lifted so far, and fresh SSA names.
module IdrisMLIR.Emit.Monad

import IdrisMLIR.Emit.Attributes
import IdrisMLIR.Ids
import IdrisMLIR.MLIR
import IdrisMLIR.Types

import Control.Monad.State
import Data.SnocList

%default total

||| The function being written: its symbol (which names the functions
||| lifted from it), its Idris name and what the functions lifted from it
||| state as it does.
public export
record Owner where
  constructor MkOwner
  symbol : String
  idrisName : Shown
  inherited : List FnAttr

public export
record ES where
  constructor MkES
  ||| The next SSA number of the function being written.
  next : Nat
  ||| The operations of the region being written.
  ops : SnocList Op
  ||| The functions lifted so far from the function being written.
  lifted : SnocList Op

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
append : Op -> E ()
append o = modify { ops $= (:< o) }

||| The operations `act` appends, apart from the current region's.
export
collect : E a -> E (a, List Op)
collect act = do
  saved <- gets (.ops)
  modify { ops := [<] }
  x <- act
  inner <- gets (.ops)
  modify { ops := saved }
  pure (x, inner <>> [])

||| How the contract holds a value: as itself, or linear (`!idr.lin`), to be
||| used exactly once.
public export
data Mode = Plain | Linear

||| How a value used as `Use` says is held. The world is linear by its own
||| type, so it is held as itself.
export
modeOf : Use -> Ty -> Mode
modeOf Once WorldT = Plain
modeOf Once _ = Linear
modeOf Many _ = Plain

||| How the value a binder binds is held: the erased value, which is never
||| used, as itself.
export
binderMode : Binder -> Mode
binderMode Gone = Plain
binderMode (Held u t) = modeOf u t

||| A value in scope: its SSA name, its type and how it is held; or, with
||| `rebuild`, a constructor a match took apart, which a reference builds
||| again from its fields as the region holds them. A match uses a linear
||| scrutinee, so a variable naming it inside a case region names the
||| constructor of the fields the region bound; its `name` is then a key no
||| operation defines, which `matched` (Bodies) renames by.
public export
record Val where
  constructor MkVal
  name : String
  type : Ty
  mode : Mode
  rebuild : Maybe (ConId, List Val)

export
val : String -> Ty -> Mode -> Val
val name type mode = MkVal name type mode Nothing
