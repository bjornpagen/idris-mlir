||| Function bodies: the algebra of the fold that writes a term, its
||| matches, lambdas, delays and loops as regions.
module IdrisMLIR.Emit.Bodies

import IdrisMLIR.Dialect.Func as Func
import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Dialect.UB as UB
import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Emit.Operations
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

||| Operands, left to right, each checked against the type its position
||| expects and held as it binds them; `Nothing` once one never returns.
operands : Index -> Loc -> (Fin nv -> Val) -> List (Sub Em nv) -> List Binder -> E (Maybe (List Val))
operands ix l env [] _ = pure (Just [])
operands ix l env (a :: as) slots = do
  Just v <- a.result env (typeOf <$> head' slots)
    | Nothing => pure Nothing
  v' <- coerce ix l (maybe Many binderUse (head' slots)) v
  map (map (v' ::)) (operands ix l env as (drop 1 slots))

||| A value as a region or a function returns it: as itself, never linear.
export
plain : Index -> Loc -> E (Maybe Val) -> E (Maybe Val)
plain ix l act = act >>= traverse (coerce ix l Many)

mutual
  ||| `v`, with every value named as `before` is, itself or a field of a
  ||| rebuilt constructor, replaced by `after`.
  renamed : (before, after : Val) -> Val -> Val
  renamed before after (MkVal n t u r) =
    if n == before.name then after else MkVal n t u (renamedIn before after r)

  renamedIn : (before, after : Val) -> Maybe (ConId, List Val) -> Maybe (ConId, List Val)
  renamedIn before after Nothing = Nothing
  renamedIn before after (Just (c, fs)) = Just (c, renamedAll before after fs)

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

||| An arm of a match: its key (none for the default), the arguments of its
||| region, its operations, and its value, which it yields.
record Arm where
  constructor MkArm
  key : Maybe MlirAttr
  arguments : List Value
  result : Maybe Val
  statements : List Statement

||| The yield that ends a region with its value; a region that never
||| returns has ended in `ub.unreachable` already.
yielding : Index -> Loc -> Maybe Val -> E (List Statement)
yielding ix l Nothing = pure []
yielding ix l (Just v) = pure [MkStatement Nothing (Idr.yieldOp [!(operand ix v)]) (At l)]

||| A match, from its arms, with the builder of its op over its keys,
||| regions and results: results when an arm yields, and none, followed by
||| `ub.unreachable`, when no arm returns.
match : Index -> Loc -> (List MlirAttr -> List MLIR.Region -> List MlirType -> Op) -> List Arm -> E (Maybe Val)
match ix l build arms = do
  regions <- traverse close arms
  let keys = mapMaybe (.key) arms
  case map (.type) (head' (mapMaybe (.result) arms)) of
    Just t => do
      r <- fresh
      append (MkStatement (Just r) (build keys regions [!(mlirType ix t)]) (At l))
      pure (Just (val r t Many))
    Nothing => do
      statement l (build keys regions [])
      statement l UB.unreachableOp
      pure Nothing
  where
    close : Arm -> E MLIR.Region
    close a = pure (MkRegion a.arguments (a.statements ++ !(yielding ix l a.result)))

||| A literal as a key of `idr.match_lit`.
key : Lit -> MlirAttr
key (LInt t n) = IntegerAttr (twos (width t) n) (IntegerType (width t))
key (LChar c) = IntegerAttr c (IntegerType 32)
key (LStr s) = StringAttr s
key (LBig n) = Idr (BigAttr (show n))
key (LNat n) = Idr (BigAttr (show n))
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

||| The end of a function's body, of result type `rt`: its value, returned,
||| or, for a body that never returns, `ub.unreachable`, once.
export
epilogue : Index -> Loc -> MlirType -> Maybe Val -> List Statement -> E (List Statement)
epilogue ix l rt (Just v) ops = pure (ops ++ [MkStatement Nothing (Func.returnOp [!(operand ix v)]) (At l)])
epilogue ix l rt Nothing ops =
  pure (if endsUnreachable (reverse ops) then ops
        else ops ++ [MkStatement Nothing UB.unreachableOp (At l)])
  where
    endsUnreachable : List Statement -> Bool
    endsUnreachable (s :: _) = s.op.name == UB.unreachableOp.name
    endsUnreachable [] = False

||| The region of a lambda's or a `Delay`'s body, whose block takes
||| `params`, and the type of the body's value: its operations, ending in
||| the yield of that value, or, for a body that never returns, in
||| `ub.unreachable`, the type then being the one the context expects.
deferred : Index -> Loc -> String -> List Val -> Maybe Ty -> E (Maybe Val) -> E (MLIR.Region, Ty)
deferred ix l what params expected body = do
  (r, ops) <- collect (plain ix l body)
  Just t <- pure (map (.type) r <|> expected)
    | Nothing => internal ("the result type of " ++ what ++ " whose body never returns")
  yields <- yielding ix l r
  pure (MkRegion !(traverse (operand ix) params) (ops ++ yields), t)

||| What a region primitive takes and gives at the types its call fixes:
||| its operands' types, its block arguments' (a generated array's index;
||| a fold's accumulator, element and index), the type its body yields,
||| and its result's besides the next world.
regionSignature : IdrRegionPrim -> List Ty -> Maybe (List Ty, List Ty, Ty, Ty)
regionSignature ArrayGenerate [e] = Just ([IntT IdrisInt, e, WorldT], [IntT IdrisInt], e, ArrayT Rank1 e)
regionSignature ArrayFold [e, t] = Just ([ArrayT Rank1 e, t, WorldT], [t, e, IntT IdrisInt], t, t)
regionSignature _ _ = Nothing

||| The algebra: one layer of `Term` to its emitter.
export
alg : {0 nv : Nat} -> Index -> TermF (Sub Em) nv -> Em nv
alg ix (VarF l x) env _ = Just <$> force ix l (env x)
alg ix (LiteralF l x) env _ = Just <$> literal ix l x
alg ix (ErasedF l) env _ = Just <$> erasedValue ix l
-- A trusted library's crash of a string ends the program and does not
-- return. The string is the cause the runtime prints.
alg ix (PrimAppF l (Op CrashStr) _ as) env _ = do
  Just [s] <- operands ix l env as [Held Many StrT]
    | _ => pure Nothing
  statement l (Idr.crashStrOp !(operand ix s))
  statement l UB.unreachableOp
  pure Nothing
alg ix (PrimAppF l p _ as) env _ = do
  Just vs <- operands ix l env as (map (Held Many) (primArgs p))
    | Nothing => pure Nothing
  Just <$> prim ix l p vs
-- An IO primitive takes its operands at their own types, and its op is
-- at the types its call fixes.
alg ix (EffectF l p tys as res) env _ = do
  Just vs <- operands ix l env as []
    | Nothing => pure Nothing
  effect ix l p tys vs res
alg ix (CallF l fn _ as) env _ = do
  Just f <- pure (lookup fn ix.fns)
    | Nothing => internal ("a call of " ++ show fn ++ ", which is not in the program")
  Just vs <- operands ix l env as (toList f.params)
    | Nothing => pure Nothing
  args <- traverse (operand ix) vs
  Just <$> value ix l f.result (\rt => Func.callOp (mangle fn.name) args [rt])
alg ix (ConAppF l c as) env _ = do
  Just k <- pure (lookup c ix.cons)
    | Nothing => internal ("the constructor " ++ show c ++ " of " ++ show c.dataId ++ ", which is not declared")
  Just vs <- operands ix l env as k.fields
    | Nothing => pure Nothing
  Just <$> con ix l k vs
-- A `let` binds an SSA value; its type is its value's.
alg ix (LetF l u v b) env expected = do
  Just x <- v.result env Nothing
    | Nothing => pure Nothing
  x' <- coerce ix l u x
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
      (args, inner) <- the (E (List Value, Fin nv -> Val)) $ if takenApart
        then do
          back <- (\r => val r scrut.type Once) <$> fresh
          arg <- operand ix back
          pure ([arg], matched before back env)
        else pure ([], env)
      (res, ops) <- collect (plain ix l (e.result inner expected))
      pure [MkArm Nothing args res ops]
    Nothing => pure []
  case cases ++ dflt of
    [] => do
      statement l UB.unreachableOp
      pure Nothing
    arms => match ix l (Idr.matchOp !(operand ix scrut)) arms
  where
    alternative : Val -> Val -> AltF (Sub Em) nv -> E Arm
    alternative before scrut (MkAltF c fs body) = do
      let takenApart = linear scrut.use scrut.type
      let use = if takenApart then binderUse else const Many
      vals <- traverse (\f => (\n => val n (typeOf f) (use f)) <$> fresh) fs
      args <- traverse (operand ix) (toList vals)
      -- Inside a case of a linear scrutinee, the scrutinee is the
      -- constructor of the fields the case bound.
      inner <- if takenApart
        then (\k => matched before (MkVal k scrut.type Many (Just (c, toList vals))) env) <$> fresh
        else pure env
      (res, ops) <- collect (plain ix l (body.result (bind vals inner) expected))
      pure (MkArm (Just (SymbolRefAttr (MkSymbolRef (mangle c.name) []))) args res ops)
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
      arms <- traverse (\(k, c) => do
                          (res, ops) <- collect (plain ix l (c.result inner expected))
                          pure (MkArm (Just (key k)) [] res ops)) cases
      (res, ops) <- collect (plain ix l (e.result inner expected))
      match ix l (Idr.matchLitOp !(operand ix scrut)) (arms ++ [MkArm Nothing [] res ops])
-- The predecessor exists only where the value is not zero: the successor's
-- region computes it, and only it binds it.
alg ix (CaseNatF l x z s) env expected =
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
      match ix l (Idr.matchLitOp !(operand ix n))
            [MkArm (Just (key (LNat 0))) [] zr zops, MkArm Nothing [] sr sops]
  where
    successor : Val -> E (Maybe Val)
    successor n = do
      p <- value ix l NatT (Idr.bigPredOp !(operand ix n))
      s.result (bind [p] env) expected
-- A lambda and a `Delay` are regions whose bodies use the values of their
-- scope where they are, and run only when the closure is applied or the
-- suspension forced.
alg ix (LamF l b body) env expected = do
  let result = case expected of
                 Just (FunT _ r) => Just r
                 _ => Nothing
  p <- val <$> fresh <*> pure (typeOf b) <*> pure (binderUse b)
  (region, t) <- deferred ix l "a lambda" [p] result (body.result (bind [p] env) result)
  Just <$> value ix l (FunT b t) (Idr.lambdaOp region)
alg ix (AppF l f x) env expected = do
  Just fv <- plain ix l (f.result env Nothing)
    | Nothing => pure Nothing
  FunT a r <- pure fv.type
    | t => internal ("an application of a value of type " ++ show t)
  Just xv <- x.result env (Just (typeOf a))
    | Nothing => pure Nothing
  xv <- coerce ix l (binderUse a) xv
  callee <- operand ix fv
  arg <- operand ix xv
  Just <$> value ix l r (\rt => Idr.applyOp callee [arg] [rt])
alg ix (SuspendF l body) env expected = do
  let result = case expected of
                 Just (LazyT r) => Just r
                 _ => Nothing
  (region, t) <- deferred ix l "a Delay" [] result (body.result env result)
  Just <$> value ix l (LazyT t) (Idr.delayOp region)
alg ix (ResumeF l e) env expected = do
  Just ev <- plain ix l (e.result env Nothing)
    | Nothing => pure Nothing
  LazyT r <- pure ev.type
    | t => internal ("a force of a value of type " ++ show t)
  callee <- operand ix ev
  Just <$> value ix l r (Idr.forceOp callee)
-- A region primitive's body is a region taking the block arguments the
-- primitive declares, which yields its value; a body that never returns
-- ends in ub.unreachable, as a match region does. IO: the world is the
-- last operand, and the next world the last result.
alg ix (RegionF {k} l p tys as body res) env _ = do
  Just (takes, binds, yielded, gives) <- pure (regionSignature p tys)
    | Nothing => internal ("a region primitive at the types " ++ show tys)
  Just argTys <- pure (toVect k binds)
    | Nothing => internal ("a region primitive whose body binds " ++ show k ++ " values")
  Just vs <- operands ix l env as (map (Held Many) takes)
    | Nothing => pure Nothing
  args <- traverse (\t => val <$> fresh <*> pure t <*> pure Many) argTys
  (r, ops) <- collect (plain ix l (body.result (bind args env) (Just yielded)))
  yields <- yielding ix l r
  let region = MkRegion !(traverse (operand ix) (toList args)) (ops ++ yields)
  out <- fresh
  append (MkStatement (Just out)
           (Idr.regionOp p !(traverse (operand ix) vs) region [!(mlirType ix gives), !(mlirType ix WorldT)])
           (At l))
  Just <$> ioResult ix l res (val (out ++ "#0") gives Many) (val (out ++ "#1") WorldT Many)
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
