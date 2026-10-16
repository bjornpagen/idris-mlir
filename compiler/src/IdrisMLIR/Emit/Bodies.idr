-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Function bodies: the algebra of the fold that writes a term, its
||| matches as regions, its lambdas and delays as functions of their own
||| (Emit.Closures) and its arrays as the array ops (Emit.Tensors).
module IdrisMLIR.Emit.Bodies

import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Dialect.UB as UB
import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Closures
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Emit.Operations
import IdrisMLIR.Emit.Tensors
import IdrisMLIR.Emit.Types
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.Fin
import Data.List
import Data.Maybe
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.String
import Data.Vect

%default total

||| What the fold makes of a term in scope `nv`: given the values of its
||| variables and the type its context expects, if known, it appends the
||| term's operations and returns its value, or `Nothing` when the term
||| never returns (its region then ends in `ub.unreachable`).
public export
Em : Nat -> Type
Em nv = (Fin nv -> Val) -> Maybe Ty -> E (Maybe Val)

||| The values of a binder's variables, over those outside.
bind : {k : Nat} -> Vect k Val -> (Fin nv -> Val) -> Fin (Under k nv) -> Val
bind vs env v = case splitUnder {k} v of
  Left i => index i vs
  Right x => env x

mutual
  ||| The most times one run of a term uses the variable `v`: along a path
  ||| the uses add, across a match's alternatives the most of any counts, a
  ||| match uses its scrutinee once (its regions name what stands for it),
  ||| and a use in a region that runs once per index counts as many.
  export
  mostUses : Fin n -> Term n -> Nat
  mostUses v (Var _ x) = if v == x then 1 else 0
  mostUses v (Literal _ _) = 0
  mostUses v (PrimApp _ _ _ as) = allUses v as
  mostUses v (Effect _ _ _ as _) = allUses v as
  mostUses v (Call _ _ _ as) = allUses v as
  mostUses v (ConApp _ _ as) = allUses v as
  mostUses v (Let _ _ _ x b) = mostUses v x + mostUses (FS v) b
  mostUses v (Case _ x alts d) = if v == x then 1 else max (altUses v alts) (defaultUses v d)
  mostUses v (CaseLit _ x alts d) = if v == x then 1 else max (litUses v alts) (mostUses v d)
  mostUses v (CaseNat _ x z _ s) = (if v == x then 1 else 0) + max (mostUses v z) (mostUses (FS v) s)
  mostUses v (Lam _ _ _ body) = mostUses (FS v) body
  mostUses v (App _ f x) = mostUses v f + mostUses v x
  mostUses v (Suspend _ body) = mostUses v body
  mostUses v (Resume _ e) = mostUses v e
  mostUses v (Unreachable _) = 0
  mostUses v (Crash _ _) = 0
  mostUses v (NewWorld _) = 0
  mostUses v (SystemOs _) = 0
  mostUses v (Tensor _ _ _ as) = allUses v as
  mostUses v (Tabulate {k} _ _ es body) = vectUses v es + many (mostUses (Free {k} v) body)
  mostUses v (TabulateIO {k} _ _ es w body _ _) =
    vectUses v es + mostUses v w + many (mostUses (Free {k = S k} v) body)
  mostUses v (Reduce _ _ _ _ _ z x body) = mostUses v z + mostUses v x + many (mostUses (Free {k = 2} v) body)
  mostUses v (Tie _ x ds) = mostUses v x + dimUses v ds

  allUses : Fin n -> List (Term n) -> Nat
  allUses v [] = 0
  allUses v (t :: ts) = mostUses v t + allUses v ts

  vectUses : Fin n -> Vect k (Term n) -> Nat
  vectUses v [] = 0
  vectUses v (t :: ts) = mostUses v t + vectUses v ts

  defaultUses : Fin n -> Maybe (Term n) -> Nat
  defaultUses v Nothing = 0
  defaultUses v (Just t) = mostUses v t

  dimUses : Fin n -> List (Maybe (Term n)) -> Nat
  dimUses v [] = 0
  dimUses v (d :: ds) = defaultUses v d + dimUses v ds

  altUses : Fin n -> List (Alt n) -> Nat
  altUses v [] = 0
  altUses v (MkAlt {k} _ _ body :: alts) = max (mostUses (Free {k} v) body) (altUses v alts)

  litUses : Fin n -> List (Lit, Term n) -> Nat
  litUses v [] = 0
  litUses v ((_, t) :: alts) = max (mostUses v t) (litUses v alts)

  many : Nat -> Nat
  many Z = Z
  many (S _) = 2

||| How a binder of quantity `q` holds its value, which its scope uses at
||| most `uses` times in one run: as Idris bound it, unless the scope uses
||| a linear value more than once (a trusted library's code reads one and
||| gives it back), when it is used once where it is bound and held plain.
||| The uses are counted only of a linear binder.
export
heldAs : Quantity -> (uses : Lazy Nat) -> Quantity
heldAs One uses = if uses >= 2 then Many else One
heldAs Many _ = Many

||| A bound value held as its scope's uses of it allow (`heldAs`).
export
holdFor : Index -> Loc -> Lazy Nat -> Val -> E Val
holdFor ix l uses v = coerce ix l (heldAs v.use uses) v

||| Operands, left to right, each checked against the type its position
||| expects and held as it binds them; `Nothing` once one never returns.
operands : Index -> Loc -> (Fin nv -> Val) -> List (Sub Em nv) -> List Binder -> E (Maybe (List Val))
operands ix l env [] _ = pure (Just [])
operands ix l env (a :: as) slots = do
  Just v <- a.result env (typeOf <$> head' slots)
    | Nothing => pure Nothing
  v' <- coerce ix l (maybe Many (\b => b.quantity) (head' slots)) !(fit ix l (typeOf <$> head' slots) v)
  map (map (v' ::)) (operands ix l env as (drop 1 slots))

||| A value as a region or a function returns it: as itself, never linear.
export
plain : Index -> Loc -> E (Maybe Val) -> E (Maybe Val)
plain ix l act = act >>= traverse (coerce ix l Many)

mutual
  ||| `v`, with every value named as `before` is, itself or a field of it,
  ||| replaced by `after`.
  renamed : (before, after : Val) -> Val -> Val
  renamed before after (MkVal n t u r) =
    if n == before.name then after else MkVal n t u (renamedIn before after r)

  renamedIn : (before, after : Val) -> Parts -> Parts
  renamedIn before after Whole = Whole
  renamedIn before after (Taken c fs) = Taken c (renamedAll before after fs)

  renamedAll : (before, after : Val) -> List Val -> List Val
  renamedAll before after [] = []
  renamedAll before after (v :: vs) = renamed before after v :: renamedAll before after vs

||| The scope of a match's regions. A match takes a linear scrutinee apart,
||| so inside the regions every variable that named it (a catch-all's, or an
||| outer clause's after a nested match) names what stands for it there:
||| the value the default region gets back, or the constructor rebuilt from
||| the fields a case bound. SSA names are unique within a function, so the
||| name says which variables those are; the fields of a rebuilt
||| constructor are renamed the same way, as an inner match takes them
||| apart in turn.
matched : Val -> Val -> (b -> Val) -> b -> Val
matched before after env y = renamed before after (env y)

||| Is a term a branch Idris proved impossible? It is left out.
excluded : Sub Em nv -> Bool
excluded s = case s.term of
  Unreachable _ => True
  _ => False

||| An arm of a match: the arguments of its region, its operations, and its
||| value, which it yields. A match's op takes its arms' keys apart.
record Arm where
  constructor MkArm
  arguments : List Argument
  result : Maybe Val
  statements : List Statement

||| The yield that ends a region with its value; a region that never
||| returns has ended in `ub.unreachable` already.
yielding : Index -> Loc -> Maybe Val -> E (List Statement)
yielding ix l Nothing = pure []
yielding ix l (Just v) = pure [MkStatement Nothing (Idr.yieldOp [!(operand ix v)]) (At l)]

||| A match, from its arms, with the builder of its op over its regions and
||| results: results when an arm yields, and none, followed by
||| `ub.unreachable`, when no arm returns. The arms join at the type the
||| context expects, else the first arm's; an arm's array of another
||| static shape is cast to it.
match : Index -> Loc -> Maybe Ty -> (List MLIR.Region -> List MlirType -> Op) -> List Arm -> E (Maybe Val)
match ix l expected build arms =
  case expected <|> map (.type) (head' (mapMaybe (.result) arms)) of
    Just t => if all (\a => isNothing a.result) arms then never else do
      regions <- traverse (close t) arms
      Just <$> value ix l t (\r => build regions [r])
    Nothing => never
  where
    close : Ty -> Arm -> E MLIR.Region
    close t a = do
      (v, cast) <- collect (traverse (fit ix l (Just t)) a.result)
      pure (MkRegion a.arguments (a.statements ++ cast ++ !(yielding ix l v)))
    never : E (Maybe Val)
    never = do
      statement l (build (map (\a => MkRegion a.arguments a.statements) arms) [])
      statement l UB.unreachableOp
      pure Nothing

||| A literal as a key of `idr.match_lit`.
key : Lit -> MlirAttr
key (LInt t n) = IntegerAttr (twos (width t) n) (IntegerType (width t))
key (LChar c) = IntegerAttr c (IntegerType 32)
key (LStr s) = StringAttr s
key (LBig n) = idr (BigAttr n)
key (LNat n) = idr (BigAttr (cast n))
key (LDouble d) = FloatAttr d F64Type

||| Starts a function: its own SSA numbers and operations.
export
inFunction : E a -> E (a, List Statement)
inFunction act = do
  st <- get
  put ({ next := 0, ops := [<] } st)
  x <- act
  inner <- gets (.ops)
  modify { next := st.next, ops := st.ops }
  pure (x, inner <>> [])

||| The end of a function's body: its value, returned; a body that never
||| returns has ended in `ub.unreachable` already, as every term that never
||| returns ends.
export
epilogue : Index -> Loc -> Maybe Val -> List Statement -> E (List Statement)
epilogue ix l (Just v) ops = pure (ops ++ [MkStatement Nothing (Idr.returnOp [!(operand ix v)]) (At l)])
epilogue ix l Nothing ops = pure ops

mutual
  ||| A value held plainly, and, if it is a constructor a match took apart,
  ||| rebuilt from plain values into fields none of which is linear.
  plainHeld : Index -> Val -> Bool
  plainHeld ix (MkVal _ t u Whole) = not (linear u t)
  plainHeld ix (MkVal _ t u (Taken c fs)) =
    not (linear u t) && plainFields && allPlain ix fs
    where
      plainFields : Bool
      plainFields = case lookup c ix.cons of
        Just k => all (\f => f.quantity == Many) k.fields
        Nothing => False

  allPlain : Index -> List Val -> Bool
  allPlain ix [] = True
  allPlain ix (v :: vs) = plainHeld ix v && allPlain ix vs

mutual
  ||| Whether a suspended term is a value already, so that forcing it would
  ||| compute nothing: a literal; a variable whose value is not linear, its
  ||| constructor rebuilt, if a match took it apart, from fields none of
  ||| which is linear; or a constructor of such values, none of its fields
  ||| linear. Its ops are then only constants and constructors of plain
  ||| values, and the suspension holds the value itself.
  evaluated : Index -> (Fin n -> Val) -> Term n -> Bool
  evaluated ix env (Var _ x) = plainHeld ix (env x)
  evaluated ix env (Literal _ _) = True
  evaluated ix env (ConApp _ c as) = case lookup c ix.cons of
    Just k => all (\f => f.quantity == Many) k.fields && allEvaluated ix env as
    Nothing => False
  evaluated ix env _ = False

  allEvaluated : Index -> (Fin n -> Val) -> List (Term n) -> Bool
  allEvaluated ix env [] = True
  allEvaluated ix env (t :: ts) = evaluated ix env t && allEvaluated ix env ts

||| A closure or a suspension of a function, made by `build` at type `t`
||| over `captures`. One that holds a linear value is used once, as what it
||| holds: it is entered into its linear type at once.
holding : Index -> Loc -> Ty -> List Value -> (MlirType -> Op) -> E Val
holding ix l t captures build = do
  made <- value ix l t build
  if any linearType captures then coerce ix l One made else pure made
  where
    linearType : Value -> Bool
    linearType v = case v.type of
      Idr (QType One _ _) _ => True
      _ => False

||| A call, a constructor application or a case passes as many values as
||| what it applies or takes apart takes. A count that differs is a
||| position the translator did not drop; nothing is written for it.
saturated : Index -> Loc -> Term n -> String -> (given, taken : Nat) -> E ()
saturated ix l term what given taken =
  unless (given == taken) $
    internal (fastConcat [show l, ": ", what, " passes ", show given, " values; it takes ",
                          show taken, ": ", showBody (names ix) term 0])

||| The algebra: one layer of `Term` to its emitter.
export
alg : {0 nv : Nat} -> Index -> TermF (Sub Em) nv -> Em nv
alg ix (VarF l x) env _ = Just <$> force ix l (env x)
alg ix (LiteralF l x) env _ = Just <$> literal ix l x
-- A trusted library's crash of a string ends the program and does not
-- return. The string is the cause the runtime prints.
alg ix (PrimAppF l (Op CrashStr) _ as) env _ = do
  Just [s] <- operands ix l env as [MkBinder Many StrT]
    | _ => pure Nothing
  statement l (Idr.crashStrOp !(operand ix s))
  statement l UB.unreachableOp
  pure Nothing
alg ix (PrimAppF l p _ as) env _ = do
  Just vs <- operands ix l env as (map (MkBinder Many) (primArgs p))
    | Nothing => pure Nothing
  Just <$> prim ix l p vs
-- An IO primitive takes its operands at their own types, and its op is
-- at the types its call fixes.
alg ix (EffectF l p tys as res) env _ = do
  Just vs <- operands ix l env as []
    | Nothing => pure Nothing
  effect ix l p tys vs res
alg ix (CallF l fn stands as) env expected = do
  Just f <- pure (lookup fn ix.fns)
    | Nothing => internal ("a call of " ++ show fn ++ ", which is not in the program")
  sym <- fnSymbol ix fn
  saturated ix l (Call l fn stands (map (.term) as)) ("a call of " ++ sym) (length as) f.arity
  Just vs <- operands ix l env as (map snd (toList f.params))
    | Nothing => pure Nothing
  args <- traverse (operand ix) vs
  Just <$> fit ix l expected !(value ix l f.result (\r => Idr.callOp sym args [r]))
alg ix (ConAppF l c as) env _ = do
  Just k <- pure (lookup c ix.cons)
    | Nothing => internal ("the constructor " ++ show c ++ " of " ++ show c.dataId ++ ", which is not declared")
  saturated ix l (ConApp l c (map (.term) as)) ("an application of " ++ k.name) (length as) (length k.fields)
  Just vs <- operands ix l env as k.fields
    | Nothing => pure Nothing
  Just <$> con ix l k vs
-- A `let` binds an SSA value; its type is its value's, and its location
-- the variable's name.
alg ix (LetF l name q v b) env expected = do
  before <- newest
  Just x <- v.result env Nothing
    | Nothing => pure Nothing
  x' <- coerce ix l (heldAs q (mostUses FZ b.term)) x
  atBinder name before x'
  b.result (bind [x'] env) expected
-- A match takes its scrutinee at its grade: a linear one is used by the
-- match, whose cases bind the fields as the constructor holds them and
-- whose default gets the value back; a plain one is read, its fields plain
-- (the product of the quantities, as Idris binds pattern variables).
alg ix (CaseF l x alts def) env expected = do
  let before = env x
  scrut <- force ix l before
  DataT d <- pure scrut.type
    | t => internal ("a match on a value of type " ++ show t)
  Just decl <- pure (lookup d ix.datas)
    | Nothing => internal ("a match on " ++ show d ++ ", which is not declared")
  let takenApart = linear scrut.use scrut.type
  cases <- traverse (alternative before scrut) (filter (\(MkAltF _ _ b) => not (excluded b)) alts)
  dflt <- case def of
    Just e => if excluded e then pure [] else do
      (args, inner) <- the (E (List Argument, Fin nv -> Val)) $ if takenApart
        then do
          back <- (\r => val r scrut.type One) <$> fresh
          arg <- operand ix back
          pure ([MkArgument arg (At l)], matched before back env)
        else pure ([], env)
      (res, ops) <- collect (plain ix l (e.result inner expected))
      pure [MkArm args res ops]
    Nothing => pure []
  case map snd cases ++ dflt of
    [] => do
      statement l UB.unreachableOp
      pure Nothing
    arms => match ix l expected (Idr.matchOp !(operand ix scrut) (map fst cases)) arms
  where
    -- A case is its constructor's tag, each field a block argument at its
    -- pattern variable's name.
    alternative : Val -> Val -> AltF (Sub Em) nv -> E (Nat, Arm)
    alternative before scrut (MkAltF {k} c fs body) = do
      Just ctor <- pure (lookup c ix.cons)
        | Nothing => internal ("a case of " ++ show c ++ ", which is not declared")
      saturated ix l body.term ("a case of " ++ ctor.name) k (length ctor.fields)
      let takenApart = linear scrut.use scrut.type
      let use = if takenApart then (\b : Binder => b.quantity) else const Many
      bound <- traverse (\(_, f) => freshVal ix (typeOf f) (use f)) fs
      let args = map (\((field, _), (_, o)) => MkArgument o (Named field l)) (toList (zip fs bound))
      (res, ops) <- collect $ do
        vals <- traverse (\(i, (v, _)) => holdFor ix l (mostUses (Bound {n = nv} i) body.term) v)
                         (zip range bound)
        -- Inside a case of a linear scrutinee, the scrutinee is the
        -- constructor of the fields the case bound.
        inner <- if takenApart
          then (\r => matched before (MkVal r scrut.type Many (Taken c (toList vals))) env) <$> fresh
          else pure env
        plain ix l (body.result (bind vals inner) expected)
      pure (ctor.tag, MkArm args res ops)
alg ix (CaseLitF l x alts def) env expected = do
  let live = filter (not . excluded . snd) alts
  -- A default Idris proved impossible is left out: the last possible
  -- alternative stands for it.
  let (cases, final) = if excluded def
                          then case reverse live of
                                 ((_, e) :: rest) => (reverse rest, Just e)
                                 [] => ([], Nothing)
                          else (live, Just def)
  case (cases, final) of
    (_, Nothing) => do
      statement l UB.unreachableOp
      pure Nothing
    ([], Just e) => e.result env expected
    (_, Just e) => do
      scrut <- coerce ix l Many !(force ix l (env x))
      let inner = matched (env x) scrut env
      arms <- traverse (\(_, c) => do
                          (res, ops) <- collect (plain ix l (c.result inner expected))
                          pure (MkArm [] res ops)) cases
      (res, ops) <- collect (plain ix l (e.result inner expected))
      match ix l expected (Idr.matchLitOp !(operand ix scrut) (map (key . fst) cases))
            (arms ++ [MkArm [] res ops])
-- The predecessor exists only where the value is not zero: the successor's
-- region computes it, and only it binds it.
alg ix (CaseNatF l x z predName s) env expected =
  case (excluded z, excluded s) of
    (True, True) => do
      statement l UB.unreachableOp
      pure Nothing
    (False, True) => z.result env expected
    (True, False) => successor !(coerce ix l Many !(force ix l (env x)))
    (False, False) => do
      n <- coerce ix l Many !(force ix l (env x))
      (zr, zops) <- collect (plain ix l (z.result env expected))
      (sr, sops) <- collect (plain ix l (successor n))
      match ix l expected (Idr.matchLitOp !(operand ix n) [key (LNat 0)])
            [MkArm [] zr zops, MkArm [] sr sops]
  where
    successor : Val -> E (Maybe Val)
    successor n = do
      before <- newest
      p <- value ix l NatT (Idr.bigPredOp !(operand ix n))
      atBinder predName before p
      s.result (bind [p] env) expected
-- A lambda is a closure of a function of its own, and a `Delay` a
-- suspension of one, each over the values its body uses from where it is
-- written: the body is written first, as a region, and the function made
-- of it. A suspension of a value is that value held, `idr.delay %v`. A
-- lambda's parameter and result are at the types the context expects of
-- them, the parameter cast inside to its binder's own: a closure's type
-- holds the extents its values are made at dynamic.
alg ix (LamF l name b body) env expected = do
  let (param, result) = case expected of
                          Just (FunT a r) => (typeOf a, Just r)
                          _ => (typeOf b, Nothing)
  (p, arg) <- freshVal ix param b.quantity
  (r, ops) <- collect $ do
    inner <- coerce ix l (heldAs b.quantity (mostUses FZ body.term)) !(fit ix l (Just (typeOf b)) p)
    plain ix l (body.result (bind [inner] env) result) >>= traverse (fit ix l result)
  Just t <- pure (result <|> map (.type) r)
    | Nothing => internal "the result type of a lambda whose body never returns"
  rt <- mlirType ix t
  ops' <- epilogue ix l r ops
  (sym, captures) <- lift l LiftedLambda [MkArgument arg (Named name l)] ops' [rt]
  Just <$> holding ix l (FunT (MkBinder b.quantity param) t) captures (Idr.closureOp sym captures)
alg ix (AppF l f x) env expected = do
  Just fv <- plain ix l (f.result env Nothing)
    | Nothing => pure Nothing
  FunT a r <- pure fv.type
    | t => internal ("an application of a value of type " ++ show t)
  Just v <- x.result env (Just (typeOf a))
    | Nothing => pure Nothing
  xv <- coerce ix l a.quantity !(fit ix l (Just (typeOf a)) v)
  callee <- operand ix fv
  arg <- operand ix xv
  Just <$> fit ix l expected !(value ix l r (\t => Idr.applyOp callee [arg] [t]))
alg ix (SuspendF l body) env expected = do
  let result = case expected of
                 Just (LazyT r) => Just r
                 _ => Nothing
  if evaluated ix env body.term
    then do
      Just v <- plain ix l (body.result env result)
        | Nothing => internal "a suspended value that never returns"
      Just <$> value ix l (LazyT v.type) (Idr.delayOp !(operand ix v))
    else do
      (r, ops) <- collect (plain ix l (body.result env result) >>= traverse (fit ix l result))
      Just t <- pure (result <|> map (.type) r)
        | Nothing => internal "the result type of a Delay whose body never returns"
      rt <- mlirType ix t
      ops' <- epilogue ix l r ops
      (sym, captures) <- lift l LiftedDelay [] ops' [rt]
      Just <$> holding ix l (LazyT t) captures (Idr.suspendOp sym captures)
alg ix (ResumeF l e) env expected = do
  Just ev <- plain ix l (e.result env Nothing)
    | Nothing => pure Nothing
  LazyT r <- pure ev.type
    | t => internal ("a force of a value of type " ++ show t)
  callee <- operand ix ev
  Just <$> fit ix l expected !(value ix l r (Idr.forceOp callee))
-- The array language: each operand bound once, in order, by the frontend;
-- each body a region of the array op Emit.Tensors writes.
alg ix (TensorF l op rt as) env _ = do
  Just vs <- operands ix l env as []
    | Nothing => pure Nothing
  Just <$> tensorOp ix l op rt vs
alg ix (TabulateF {k} l rt es body) env _ = do
  Just extents <- operands ix l env (toList es) []
    | Nothing => pure Nothing
  Just ev <- pure (toVect k extents)
    | Nothing => internal "a tabulation of fewer extents than it binds"
  tabulate ix l rt ev (\coords => plain ix l (body.result (bind coords env) Nothing))
alg ix (ReduceF l r acc el rt z x body) env _ = do
  Just [zv, xv] <- operands ix l env [z, x] []
    | Nothing => pure Nothing
    | Just _ => internal "a reduction of other than its accumulators and its array"
  reduce ix l r acc el rt zv xv (\a, e => plain ix l (body.result (bind [a, e] env) (Just acc)))
alg ix (TieF l x ds) env _ = do
  Just xv <- plain ix l (x.result env Nothing)
    | Nothing => pure Nothing
  Just dims <- statedAll ds
    | Nothing => pure Nothing
  Just <$> tie ix l xv dims
  where
    -- A size an array's extent gives is exact; any other natural is
    -- converted as an extent.
    stated : Sub Em nv -> E (Maybe Stated)
    stated d = do
      Just v <- plain ix l (d.result env (Just NatT))
        | Nothing => pure Nothing
      pure (Just (case d.term of
                    Tensor _ (Extent _) _ _ => OfArray v
                    _ => OfNatural v))
    statedAll : List (Maybe (Sub Em nv)) -> E (Maybe (List (Maybe Stated)))
    statedAll [] = pure (Just [])
    statedAll (Nothing :: rest) = map (Nothing ::) <$> statedAll rest
    statedAll (Just d :: rest) = do
      Just s <- stated d
        | Nothing => pure Nothing
      map (Just s ::) <$> statedAll rest
alg ix (TabulateIOF {k} l rt es w body step done) env _ = do
  Just extents <- operands ix l env (toList es) []
    | Nothing => pure Nothing
  Just ev <- pure (toVect k extents)
    | Nothing => internal "a tabulation of fewer extents than it binds"
  Just world <- w.result env (Just WorldT)
    | Nothing => pure Nothing
  tabulateIO ix l rt ev world
             (\coords, wv => plain ix l (body.result (bind (snoc coords wv) env) Nothing)) step done
alg ix (UnreachableF l) env _ = do
  statement l UB.unreachableOp
  pure Nothing
-- A crash reports its message and never returns.
alg ix (CrashF l msg) env _ = do
  statement l (Idr.crashOp msg)
  statement l UB.unreachableOp
  pure Nothing
alg ix (NewWorldF l) env _ = Just <$> value ix l WorldT Idr.worldNewOp
alg ix (SystemOsF l) env _ = Just <$> value ix l StrT Idr.osOp
