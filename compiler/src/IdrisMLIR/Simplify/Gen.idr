||| The code-generation monad of `Simplify`: Kovács's `Gen` (closure-free
||| two-level type theory, ICFP 2024). Evaluation emits first-order bindings
||| into the current block; `block` runs a computation in a fresh block and
||| closes it into `Code`. A computation that reaches a point Idris proved
||| impossible stops, and the nearest block becomes `Absurd`.
module IdrisMLIR.Simplify.Gen

import IdrisMLIR.Code
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Rule
import IdrisMLIR.Simplify.Value
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.List
import Data.SnocList
import Data.SortedMap

%default total

------------------------------------------------------------------------------
-- Keys
------------------------------------------------------------------------------

||| The key of a specialization (ELIM-G-3): the function, and the shapes of
||| its arguments and of the eliminations applied to its result (ELIM-G-5).
public export
record Key where
  constructor MkKey
  fn : FnId
  args : List (SVal ())
  elims : List (Elim ())

export
Eq Key where
  a == b = a.fn == b.fn && a.args == b.args && cmpElims a.elims b.elims == EQ

export
Ord Key where
  compare a b = compare a.fn b.fn <+> compare a.args b.args <+> cmpElims a.elims b.elims

||| A key with no static argument and no elimination: the function itself.
export
trivial : Key -> Bool
trivial k = all isDyn k.args && null k.elims
  where
    isDyn : SVal () -> Bool
    isDyn (Dyn _ _) = True
    isDyn _ = False

export covering
showKey : Key -> String
showKey k = show k.fn ++ "(" ++ joinBy "; " (map showShape k.args) ++ ")" ++ showElims k.elims
  where
    joinBy : String -> List String -> String
    joinBy sep [] = ""
    joinBy sep [x] = x
    joinBy sep (x :: xs) = x ++ sep ++ joinBy sep xs

------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------

||| One pending binding of the current block.
public export
record Stmt where
  constructor MkStmt
  loc : Loc
  var : VarId
  quantity : Quantity
  type : VTy
  op : Op Code

||| The full-Core program, indexed.
public export
record SourceIndex where
  constructor MkSourceIndex
  fns : SortedMap FnId TFn
  datas : SortedMap DataId Data
  cons : SortedMap ConId Con

public export
record St where
  constructor MkSt
  src : SourceIndex
  next : Nat                      -- the variable supply
  lets : SnocList Stmt            -- the current block
  memo : SortedMap Key FnId       -- specializations, made or being made
  made : SortedMap FnId Nat       -- specializations per function (ELIM-G-3)
  stack : List Key                -- specializations being made, innermost first
  done : SnocList CFn
  raising : Maybe FnId            -- in the prefix of this raised function (ELIM-G-5)
  moved : SnocList (FnId, Loc, Op ())   -- what those prefixes run (PROF-HEAP-5)
  effects : Nat                   -- effects emitted so far, in evaluation order
  ||| Where each raised function runs, and whether an effect was emitted
  ||| between building its action and running it (PROF-HEAP-5).
  runs : SnocList (FnId, Loc, Bool)
  unfolding : List FnId           -- String functions being unfolded (ELIM-G-10)

||| Why evaluation stopped: a user error, or a point Idris proved impossible.
public export
data Stop = Fail Diag | Dead Loc | Crashed Loc St

public export
M : Type -> Type
M = StateT St (Either Stop)

export
initial : SourceIndex -> St
initial src = MkSt src 0 [<] empty empty [] [<] Nothing [<] 0 [<] []

export
fail : Rule -> Loc -> String -> M a
fail r l msg = lift (Left (Fail (MkDiag r "Simplify" l msg)))

||| Reached a point that cannot be reached (FE-TR-4, SEM-DATA-2).
export
dead : Loc -> M a
dead l = lift (Left (Dead l))

export
freshVar : M VarId
freshVar = do
  st <- get
  put ({ next $= S } st)
  pure (MkVarId st.next)

------------------------------------------------------------------------------
-- Let-insertion
------------------------------------------------------------------------------

||| Binds an operation in the current block and returns its variable. In the
||| prefix of a raised function the operation is recorded: it moves from
||| where an action is built to where it runs (ELIM-G-5, PROF-HEAP-5).
export
bind : Loc -> VTy -> Op Code -> M Atom
bind l t o = do
  x <- freshVar
  modify { lets $= (:< MkStmt l x (defaultQuantity t) t o) }
  st <- get
  case st.raising of
    Just owner => put ({ moved $= (:< (owner, l, map (const ()) o)) } st)
    Nothing => pure ()
  pure (AVar x)

||| A crash (SEM-CRASH-2): bound with its cause, at quantity ω so that it is
||| emitted, and then evaluation of the block stops.
export
crash : Loc -> String -> M a
crash l m = do
  x <- freshVar
  modify { lets $= (:< MkStmt l x QW ErasedT (OCrash m)) }
  st <- get
  case st.raising of
    Just owner => put ({ moved $= (:< (owner, l, OCrash m)) } st)
    Nothing => pure ()
  st <- get
  lift (Left (Crashed l st))

||| Counts an effect: an IO primitive, or a call that is passed the world.
export
effect : M ()
effect = modify { effects $= S }

close : List Stmt -> Code -> Code
close [] c = c
close (s :: ss) c = Bind s.loc s.var s.quantity s.type s.op (close ss c)

||| Runs a computation in a fresh block: its code and the type of its result,
||| or `Absurd` without a type if it cannot return. Everything it did is
||| undone when it cannot: that code never runs.
export
block : Loc -> M (Atom, VTy) -> M (Maybe VTy, Code)
block l act = do
  st <- get
  case runStateT ({ lets := [<] } st) act of
    Right (st', (a, t)) => do
      put ({ lets := st.lets } st')
      pure (Just t, close (st'.lets <>> []) (Ret l a))
    Left (Dead at) => pure (Nothing, Absurd at)
    -- The code up to a crash runs; nothing after it does.
    Left (Crashed at st') => do
      put ({ lets := st.lets } st')
      pure (Nothing, close (st'.lets <>> []) (Absurd at))
    Left err => lift (Left err)

||| Consuming a static value runs the action it describes: its code is not
||| part of the prefix it was built in.
export
leavePrefix : M a -> M a
leavePrefix act = do
  saved <- gets raising
  modify { raising := Nothing }
  x <- act
  modify { raising := saved }
  pure x

||| Runs a computation as the prefix of a raised function, or not.
export
withPrefix : Maybe FnId -> M a -> M a
withPrefix p act = do
  saved <- gets raising
  modify { raising := p }
  x <- act
  modify { raising := saved }
  pure x
