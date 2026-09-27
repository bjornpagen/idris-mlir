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
import Data.Maybe
import Data.SnocList
import Data.SortedMap

%default total

------------------------------------------------------------------------------
-- Keys
------------------------------------------------------------------------------

||| The key of a specialization (ELIM-G-3): the function, and the shapes of
||| its arguments and of the eliminations applied to its result (ELIM-G-5).
||| `lits` is empty, or, for a specialization on literal values (ELIM-G-17),
||| the literal of each atom, in order.
public export
record Key where
  constructor MkKey
  fn : FnId
  args : List (SVal ())
  elims : List (Elim ())
  lits : List (Maybe Lit)

-- Literals are ordered by how they print, which tells them apart.
litKey : Maybe Lit -> String
litKey = maybe "_" show

export
Eq Key where
  a == b = a.fn == b.fn && a.args == b.args && cmpElims a.elims b.elims == EQ &&
           map litKey a.lits == map litKey b.lits

export
Ord Key where
  compare a b = compare a.fn b.fn <+> compare a.args b.args <+> cmpElims a.elims b.elims <+>
                compare (map litKey a.lits) (map litKey b.lits)

||| A key with no static argument and no elimination: the function itself.
export
trivial : Key -> Bool
trivial k = all isDyn k.args && null k.elims && all isNothing k.lits
  where
    isDyn : SVal () -> Bool
    isDyn (Dyn _ _) = True
    isDyn _ = False

export covering
showKey : Key -> String
showKey k = show k.fn ++ "(" ++ joinBy "; " (map showShape k.args) ++ ")" ++ showElims k.elims ++
            (if all isNothing k.lits then "" else " at " ++ joinBy ", " (map litKey k.lits))
  where
    joinBy : String -> List String -> String
    joinBy sep [] = ""
    joinBy sep [x] = x
    joinBy sep (x :: xs) = x ++ sep ++ joinBy sep xs

------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------

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
  done : SnocList (CFn Pure)
  raising : Maybe FnId            -- in the prefix of this raised function (ELIM-G-5)
  moved : SnocList (FnId, Loc, Moved)   -- what those prefixes run (PROF-HEAP-5)
  effects : Nat                   -- effects emitted so far, in evaluation order
  ||| Where each raised function runs, and whether an effect was emitted
  ||| between building its action and running it (PROF-HEAP-5).
  runs : SnocList (FnId, Loc, Bool)
  unfolding : List FnId           -- String functions being unfolded (ELIM-G-10)
  ||| While a call is evaluated at compile time (ELIM-G-16): the unfoldings
  ||| it may still make.
  fuel : Maybe Nat
  ||| The innermost location in the user's code that evaluation is under: a
  ||| diagnostic inside library code is reported there (DIAG-LOC-1).
  site : Maybe Loc
  ||| Call-pattern specializations made per function (ELIM-G-18).
  patterns : SortedMap FnId Nat

||| Why evaluation stopped: a user error, a point Idris proved impossible, a
||| crash, or a compile-time evaluation given up (ELIM-G-16).
public export
data Stop = Fail Diag | Dead Loc | Crashed Loc String St | Abandoned

public export
M : Type -> Type
M = StateT St (Either Stop)

export
initial : SourceIndex -> St
initial src = MkSt src 0 [<] empty empty [] [<] Nothing [<] 0 [<] [] Nothing Nothing empty

export
fail : Rule -> Loc -> String -> M a
fail r l msg = do
  site <- gets site
  case site of
    Just s => if inLibrary l
                then lift (Left (Fail (MkDiag r "Simplify" s (msg ++ " (in " ++ show l ++ ")"))))
                else lift (Left (Fail (MkDiag r "Simplify" l msg)))
    Nothing => lift (Left (Fail (MkDiag r "Simplify" l msg)))

||| Runs a computation under a location: if it is in the user's code, it is
||| where library code reached from here reports (DIAG-LOC-1).
export
atSite : Loc -> M a -> M a
atSite l act =
  if inLibrary l || not (known l) then act else do
    saved <- gets site
    modify { site := Just l }
    x <- act
    modify { site := saved }
    pure x

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

||| Records an operation of the prefix of a raised function: it moves from
||| where an action is built to where it runs (ELIM-G-5, PROF-HEAP-5).
remember : Loc -> Moved -> M ()
remember l m = do
  st <- get
  case st.raising of
    Just owner => put ({ moved $= (:< (owner, l, m)) } st)
    Nothing => pure ()

||| Binds an operation in the current block and returns its variable.
export
bind : Loc -> VTy -> Op -> M Atom
bind l t o = do
  x <- freshVar
  modify { lets $= (:< SLet l (MkParam x (defaultQuantity t) t) o) }
  remember l (MovedOp o)
  pure (AVar x)

||| A match whose alternatives are finished blocks, and the variable that
||| holds its value in the rest of the block.
export
emitCase : Loc -> VTy -> Atom -> List (Branch (Code Pure)) -> Maybe (Code Pure) -> M Atom
emitCase l t x bs d = do
  y <- freshVar
  modify { lets $= (:< SMatch l (MkParam y (defaultQuantity t) t) x bs d) }
  pure (AVar y)

||| A literal match whose alternatives are finished blocks.
export
emitCaseLit : Loc -> VTy -> Atom -> List (Lit, Code Pure) -> Code Pure -> M Atom
emitCaseLit l t x as d = do
  y <- freshVar
  modify { lets $= (:< SMatchLit l (MkParam y (defaultQuantity t) t) x as d) }
  pure (AVar y)

||| A crash (SEM-CRASH-2): evaluation of the block stops.
export
crash : Loc -> String -> M a
crash l m = do
  remember l MovedCrash
  st <- get
  lift (Left (Crashed l m st))

||| Counts an effect: an IO primitive, or a call that is passed the world.
export
effect : M ()
effect = modify { effects $= S }

freshJoin : M JoinId
freshJoin = do
  st <- get
  put ({ next $= S } st)
  pure (MkJoinId st.next)

||| A match whose alternatives continue at a join point with its value.
continued : Loc -> Param -> Code Pure -> Code Pure -> M (Code Pure)
continued l p m rest = do
  j <- freshJoin
  pure (Join l j [p] rest (returnTo j m))

||| Closes statements around the end of a block. A match followed by more
||| statements continues at a join point that its alternatives jump to; a
||| match at the end of a block whose value the block returns is the end of
||| the block itself.
close : List Stmt -> Code Pure -> M (Code Pure)
close [] c = pure c
close (SLet l p o :: ss) c = Let l [p] o <$> close ss c
close [SMatch l p x bs d] (Ret r [AVar y]) =
  if y == p.var then pure (Case l x bs d) else continued l p (Case l x bs d) (Ret r [AVar y])
close [SMatchLit l p x as d] (Ret r [AVar y]) =
  if y == p.var then pure (CaseLit l x as d) else continued l p (CaseLit l x as d) (Ret r [AVar y])
close (SMatch l p x bs d :: ss) c = close ss c >>= continued l p (Case l x bs d)
close (SMatchLit l p x as d :: ss) c = close ss c >>= continued l p (CaseLit l x as d)

||| Runs a computation in a fresh block: its code and the type of its result,
||| or code that cannot return, without a type. Everything it did is undone
||| when it cannot return: that code never runs.
export
block : Loc -> M (Atom, VTy) -> M (Maybe VTy, Code Pure)
block l act = do
  st <- get
  case runStateT ({ lets := [<] } st) act of
    Right (st', (a, t)) => do
      put ({ lets := st.lets } st')
      (Just t,) <$> close (st'.lets <>> []) (Ret l [a])
    Left (Dead at) => pure (Nothing, Absurd at)
    -- The code up to a crash runs; nothing after it does.
    Left (Crashed at m st') => do
      put ({ lets := st.lets } st')
      (Nothing,) <$> close (st'.lets <>> []) (Crash at m)
    Left err => lift (Left err)

||| Runs a computation in a fresh block and returns its value with the
||| statements it made, or the code of a block that cannot return. The value
||| is reified later, where it is used (ELIM-G-14).
export
blockV : Loc -> M a -> M (Either (Code Pure) (List Stmt, a))
blockV l act = do
  st <- get
  case runStateT ({ lets := [<] } st) act of
    Right (st', x) => do
      put ({ lets := st.lets } st')
      pure (Right (st'.lets <>> [], x))
    Left (Dead at) => pure (Left (Absurd at))
    Left (Crashed at m st') => do
      put ({ lets := st.lets } st')
      Left <$> close (st'.lets <>> []) (Crash at m)
    Left err => lift (Left err)

||| Emits statements made by `blockV` into the current block.
export
replay : List Stmt -> M ()
replay p = modify { lets $= (<>< p) }

||| Runs a computation, or reports the user error that stopped it with the
||| state as it was (ELIM-G-17).
export
attempt : M a -> M (Either Diag a)
attempt act = do
  st <- get
  case runStateT st act of
    Right (st', x) => put st' $> Right x
    Left (Fail d) => pure (Left d)
    Left other => lift (Left other)

||| Evaluates a computation at compile time (ELIM-G-16): its result, if it
||| finishes within `n` unfoldings with a result that satisfies `ok` and
||| leaves no code, effect or specialization behind; otherwise nothing, and
||| the state is as it was.
export
evaluate : Nat -> (a -> Bool) -> M a -> M (Maybe a)
evaluate n ok act = do
  st <- get
  case runStateT ({ lets := [<], fuel := Just n } st) act of
      Right (st', x) =>
        if ok x && null st'.lets && st'.effects == st.effects && length st'.done == length st.done
           && size st'.memo == size st.memo && length st'.moved == length st.moved
          then do
            put ({ lets := st.lets, fuel := Nothing } st')
            pure (Just x)
          else pure Nothing
      Left _ => pure Nothing
  where
    size : SortedMap Key FnId -> Nat
    size = length . SortedMap.toList

||| Gives up a compile-time evaluation (ELIM-G-16): it ran out of fuel or
||| would leave code behind.
export
abandon : M a
abandon = lift (Left Abandoned)

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
