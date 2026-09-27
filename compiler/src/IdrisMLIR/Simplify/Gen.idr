||| The code-generation monad of `Simplify`: Kovács's `Gen` (closure-free
||| two-level type theory, ICFP 2024). Evaluation emits first-order statements
||| into the current block; `block` runs a computation in a fresh block and
||| closes it into `Code`, where a match followed by more statements becomes
||| a join point. A computation that reaches a point Idris proved impossible
||| stops, and the nearest block becomes `Absurd`; one that crashes, or whose
||| match cannot return, ends its block with that code.
|||
||| The state also holds the path of the driver (ELIM-G-19): the calls being
||| unfolded and the specializations being made, innermost first, with their
||| configurations. The whistle compares a call with them.
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

%default covering

------------------------------------------------------------------------------
-- Configurations and keys
------------------------------------------------------------------------------

||| A call as the driver sees it: the function, its arguments and the
||| eliminations applied to its result, each with its literals
||| (ELIM-G-19). A specialization is keyed by one (ELIM-G-3), whose runtime
||| leaves are its parameters and whose literals it fixes.
public export
record Config where
  constructor MkConfig
  fn : FnId
  args : List (SVal Leaf)
  elims : List (Elim Leaf)

export covering
Eq Config where
  a == b = a.fn == b.fn && a.args == b.args && cmpElims a.elims b.elims == EQ

export covering
Ord Config where
  compare a b = compare a.fn b.fn <+> compare a.args b.args <+> cmpElims a.elims b.elims

||| Does `a` embed in `b` (ELIM-G-19)?
export covering
embedsIn : Config -> Config -> Bool
embedsIn a b = a.fn == b.fn && embedsAll a.args b.args &&
               length a.elims == length b.elims &&
               embedsAll (applied a.elims) (applied b.elims)

||| The most specific generalization of two configurations of one call.
export covering
generalize : Config -> Config -> Maybe Config
generalize a b = MkConfig a.fn <$> msgAll a.args b.args <*> msgElims a.elims b.elims

||| A key with no static argument, literal or elimination: the function
||| itself.
export covering
trivial : Config -> Bool
trivial k = all isDyn k.args && null k.elims
  where
    isDyn : SVal Leaf -> Bool
    isDyn (Dyn _ Nothing) = True
    isDyn _ = False

export covering
showConfig : Config -> String
showConfig k = show k.fn ++ "(" ++ joinBy "; " (map showShape k.args) ++ ")" ++ showElims k.elims
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

||| A call in progress on the driver's path.
public export
data Frame = Unfolding Nat Config   -- being unfolded, with its identity
           | Specializing Config     -- its specialization being made

||| The driver's budget (ELIM-G-19), a bound on compile time and code size,
||| not a termination argument: the unfoldings that emit code allowed in one
||| residual body, and the unfoldings allowed in a row without emitting code,
||| a compile-time evaluation such as `fib 15`.
export
budget : Nat
budget = 20000

public export
record St where
  constructor MkSt
  src : SourceIndex
  next : Nat                      -- the supply of variables and join points
  lets : SnocList Stmt            -- the current block
  memo : SortedMap Config FnId    -- specializations, made or being made
  made : SortedMap FnId Nat       -- specializations per function (ELIM-G-3)
  done : SnocList (CFn Pure)
  path : List Frame               -- the driver's path, innermost first
  frames : Nat                    -- the supply of frame identities
  left : Nat                      -- unfoldings that emit code left in this body
  quiet : Nat                     -- unfoldings since code was last emitted
  raising : Maybe FnId            -- in the prefix of this raised function (ELIM-G-5)
  moved : SnocList (FnId, Loc, Moved)   -- what those prefixes run (PROF-HEAP-5)
  effects : Nat                   -- effects emitted so far, in evaluation order
  ||| Where each raised function runs, and whether an effect was emitted
  ||| between building its action and running it (PROF-HEAP-5).
  runs : SnocList (FnId, Loc, Bool)
  ||| The innermost location in the user's code that evaluation is under: a
  ||| diagnostic inside library code is reported there (DIAG-LOC-1).
  site : Maybe Loc

||| Why evaluation stopped: a user error; a point Idris proved impossible;
||| the end of the block, with the code that ends it (a crash, or a match
||| none of whose alternatives returns); or the whistle, which generalizes
||| the unfolding it names (ELIM-G-19).
public export
data Stop = Fail Diag | Dead Loc | Ends St (Code Pure) | Generalize Nat Config

public export
M : Type -> Type
M = StateT St (Either Stop)

export
initial : SourceIndex -> St
initial src = MkSt src 0 [<] empty empty [<] [] 0 budget 0 Nothing [<] 0 [<] Nothing

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

freshJoin : M JoinId
freshJoin = do
  st <- get
  put ({ next $= S } st)
  pure (MkJoinId st.next)

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

||| Emits statements into the current block.
export
replay : List Stmt -> M ()
replay p = modify { lets $= (<>< p), quiet := 0 }

||| Binds an operation in the current block and returns its variable.
export
bind : Loc -> VTy -> Op -> M Atom
bind l t o = do
  x <- freshVar
  replay [SLet l (MkParam x (defaultQuantity t) t) o]
  remember l (MovedOp o)
  pure (AVar x)

freshParams : List VTy -> M (List Param)
freshParams = traverse (\t => (\x => MkParam x (defaultQuantity t) t) <$> freshVar)

||| A match whose alternatives are finished blocks, and the variables that
||| hold its values in the rest of the block.
export
emitCase : Loc -> List VTy -> Atom -> List (Branch (Code Pure)) -> Maybe (Code Pure) -> M (List Atom)
emitCase l ts x bs d = do
  ps <- freshParams ts
  replay [SMatch l ps x bs d]
  pure (map (AVar . (.var)) ps)

||| A literal match whose alternatives are finished blocks.
export
emitCaseLit : Loc -> List VTy -> Atom -> List (Lit, Code Pure) -> Code Pure -> M (List Atom)
emitCaseLit l ts x as d = do
  ps <- freshParams ts
  replay [SMatchLit l ps x as d]
  pure (map (AVar . (.var)) ps)

||| Ends the current block with code that does not return to it.
export
ends : Code Pure -> M a
ends c = do
  st <- get
  lift (Left (Ends st c))

||| A crash (SEM-CRASH-2): evaluation of the block stops.
export
crash : Loc -> String -> M a
crash l m = do
  remember l MovedCrash
  ends (Crash l m)

||| Counts an effect: an IO primitive, or a call that is passed the world.
export
effect : M ()
effect = modify { effects $= S }

||| A match whose alternatives continue at a join point with its values.
continued : Loc -> List Param -> Code Pure -> Code Pure -> M (Code Pure)
continued l ps m rest = do
  j <- freshJoin
  pure (Join l j ps rest (returnTo j m))

||| Returns exactly the values of these parameters?
returns : List Param -> List Atom -> Bool
returns ps as = as == map (AVar . (.var)) ps

||| Closes statements around the end of a block. A match followed by more
||| statements continues at a join point that its alternatives jump to; a
||| match at the end of a block whose values the block returns is the end of
||| the block itself.
export
close : List Stmt -> Code Pure -> M (Code Pure)
close [] c = pure c
close (SLet l p o :: ss) c = Let l [p] o <$> close ss c
close [SMatch l ps x bs d] end@(Ret _ as) =
  if returns ps as then pure (Case l x bs d) else continued l ps (Case l x bs d) end
close [SMatchLit l ps x as d] end@(Ret _ out) =
  if returns ps out then pure (CaseLit l x as d) else continued l ps (CaseLit l x as d) end
close (SMatch l ps x bs d :: ss) c = close ss c >>= continued l ps (Case l x bs d)
close (SMatchLit l ps x as d :: ss) c = close ss c >>= continued l ps (CaseLit l x as d)

||| Runs a computation in a fresh block and returns its value with the
||| statements it made, or the code of a block that does not return a value.
||| Everything a block that cannot be reached did is undone: that code never
||| runs.
export
blockV : Loc -> M a -> M (Either (Code Pure) (List Stmt, a))
blockV l act = do
  st <- get
  case runStateT ({ lets := [<] } st) act of
    Right (st', x) => do
      put ({ lets := st.lets } st')
      pure (Right (st'.lets <>> [], x))
    Left (Dead at) => pure (Left (Absurd at))
    -- The code up to the end runs; nothing after it does.
    Left (Ends st' c) => do
      put ({ lets := st.lets, path := st.path, raising := st.raising, site := st.site } st')
      Left <$> close (st'.lets <>> []) c
    Left err => lift (Left err)

||| Runs a computation in a fresh block that returns atoms.
export
block : Loc -> M (List Atom) -> M (Code Pure)
block l act = do
  r <- blockV l act
  case r of
    Left c => pure c
    Right (p, as) => close p (Ret l as)

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

------------------------------------------------------------------------------
-- The driver's path (ELIM-G-19)
------------------------------------------------------------------------------

||| The configuration of a frame.
export
frameConfig : Frame -> Config
frameConfig (Unfolding _ c) = c
frameConfig (Specializing c) = c

||| The innermost frame whose configuration embeds in this one.
export covering
whistle : Config -> List Frame -> Maybe Frame
whistle c = find (\f => embedsIn (frameConfig f) c)

||| How many times a call unfolded only for a literal its body matches on may
||| repeat on one path (ELIM-G-19).
export
literalDepth : Nat
literalDepth = 4

||| The unfoldings of a function on the path, innermost first.
export
unfoldingsOf : FnId -> List Frame -> List (Nat, Config)
unfoldingsOf f = mapMaybe pick
  where
    pick : Frame -> Maybe (Nat, Config)
    pick (Unfolding i c) = if c.fn == f then Just (i, c) else Nothing
    pick _ = Nothing

||| The outermost unfolding of a function on the path.
export
outermost : FnId -> List Frame -> Maybe (Nat, Config)
outermost f = foldl pick Nothing
  where
    pick : Maybe (Nat, Config) -> Frame -> Maybe (Nat, Config)
    pick acc (Unfolding i c) = if c.fn == f then Just (i, c) else acc
    pick acc _ = acc

||| Is the budget of this residual body spent (ELIM-G-19)?
export
spent : St -> Bool
spent st = st.left == 0 || st.quiet >= budget

||| Runs an unfolding as a frame of the path. If the whistle generalizes
||| it, everything it did is undone and `otherwise` runs with the
||| generalized configuration instead. An unfolding that emitted no code
||| costs the body's budget nothing.
export
unfolding : Config -> M a -> (Config -> M a) -> M a
unfolding c act otherwise = do
  st <- get
  let i = st.frames
  case runStateT ({ frames $= S, path $= (Unfolding i c ::), left $= (`minus` 1), quiet $= S } st) act of
    Right (st', x) =>
      put ({ path := st.path, left := if st'.next == st.next then st.left else st'.left } st') $> x
    Left (Generalize j g) => if i == j then otherwise g else lift (Left (Generalize j g))
    Left (Ends st' code) => lift (Left (Ends ({ path := st.path } st') code))
    Left other => lift (Left other)

||| Runs the making of a specialization's body: the path of specializations
||| being made, and a fresh budget.
export
specializing : Config -> M a -> M a
specializing c act = do
  st <- get
  put ({ path := Specializing c :: filter isSpec st.path, left := budget, quiet := 0 } st)
  x <- act
  modify { path := st.path, left := st.left, quiet := st.quiet }
  pure x
  where
    isSpec : Frame -> Bool
    isSpec (Specializing _) = True
    isSpec _ = False
