||| Function bodies: the algebra of the fold that writes a term, its
||| matches as regions and its lambdas as lifted functions.
module IdrisMLIR.Emit.Bodies

import IdrisMLIR.CustomSyntax as Idr
import IdrisMLIR.Dialect.Func as Func
import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Dialect.UB as UB
import IdrisMLIR.Emit.Attributes
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
import Data.List
import Data.Maybe
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.String
import Data.Vect

%default total

||| What the fold makes of a term in scope `b`: given the values of its
||| variables and the type its context expects, if known, it appends the
||| term's operations and returns its value, or `Nothing` when the term
||| never returns (its region then ends in `ub.unreachable`).
public export
Em : Type -> Type
Em b = (b -> Val) -> Maybe Ty -> E (Maybe Val)

||| The values of a binder's variables, over those outside.
bind : Vect k Val -> (b -> Val) -> Under k b -> Val
bind vs env (Bound i) = index i vs
bind vs env (Free x) = env x

||| Operands, left to right, each checked against the type its position
||| expects and held as it binds them; `Nothing` once one never returns.
operands : Index -> Loc -> (b -> Val) -> List (Sub Em b) -> List Binder -> E (Maybe (List Val))
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
excluded : Sub Em b -> Bool
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
match : Index -> Loc -> (List MlirAttr -> List Region -> List MlirType -> Op) -> List Arm -> E (Maybe Val)
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
    close : Arm -> E Region
    close a = pure (MkRegion a.arguments (a.statements ++ !(yielding ix l a.result)))

||| A literal as a key of `idr.match_lit`.
key : Lit -> MlirAttr
key (LInt t n) = integerAttr (twos (width t) n) (integerType (width t))
key (LChar c) = integerAttr c (integerType 32)
key (LStr s) = stringAttr s
key (LBig n) = Idr.bigAttr (show n)
key (LNat n) = Idr.bigAttr (show n)
key (LDouble d) = floatAttr d f64Type

||| Starts a function: its own SSA numbers and operations, the owner's
||| lifted functions kept.
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

||| A lifted function: private, its captures first, then its parameters.
||| Its body is the closure's, and it is what the closure calls.
lifted : Index -> Owner -> Loc -> Label -> Vect k Val -> Vect m Val -> Maybe Ty ->
         (Vect k Val -> Vect m Val -> E (Maybe Val)) -> E (String, Ty)
lifted ix own l lbl caps ps expected body = do
  let sym = own.symbol ++ "$lam" ++ show lbl.index
  ((params, res), ops) <- inFunction $ do
    cs <- traverse renamed caps
    ps' <- traverse renamed ps
    res <- plain ix l (body cs ps')
    pure (toList cs ++ toList ps', res)
  t <- case map (.type) res <|> expected of
         Just t => pure t
         Nothing => internal ("the result type of " ++ show lbl ++ ", whose body never returns")
  rt <- mlirType ix t
  args <- traverse (operand ix) params
  body <- epilogue ix l rt res ops
  let fnAttrs = own.inherited ++ lifted
  let fn = Func.funcOp {symVisibility = Just "private"} sym
                       (functionType (map (\a => a.type) args) [rt])
                       (MkRegion args body)
  modify { lifted $= (:< MkStatement Nothing ({ attributes := attributes fnAttrs } fn)
                                     (Named own.idrisName l)) }
  pure (sym, t)
  where
    renamed : Val -> E Val
    renamed v = (\n => { name := n } v) <$> fresh

||| The algebra: one layer of `Term` to its emitter.
export
alg : {0 b : Type} -> Index -> Owner -> TermF (Sub Em) b -> Em b
alg ix own (VarF l x) env _ = Just <$> force ix l (env x)
alg ix own (LiteralF l x) env _ = Just <$> literal ix l x
alg ix own (ErasedF l) env _ = Just <$> erasedValue ix l
alg ix own (PrimAppF l p _ as) env _ = do
  Just vs <- operands ix l env as (map (Held Many) (primArgs p))
    | Nothing => pure Nothing
  Just <$> prim ix l p vs
alg ix own (EffectF l op as res) env _ = do
  Just vs <- operands ix l env as (map (Held Many) (ioArgs op ++ [WorldT]))
    | Nothing => pure Nothing
  Just <$> io ix l op vs res
alg ix own (CallF l fn _ as) env _ = do
  Just f <- pure (lookup fn ix.fns)
    | Nothing => internal ("a call of " ++ show fn ++ ", which is not in the program")
  Just vs <- operands ix l env as (toList f.params)
    | Nothing => pure Nothing
  args <- traverse (operand ix) vs
  Just <$> value ix l f.result (\rt => Func.callOp (mangle fn.name) args [rt])
alg ix own (ConAppF l c as) env _ = do
  Just k <- pure (lookup c ix.cons)
    | Nothing => internal ("the constructor " ++ show c ++ " of " ++ show c.dataId ++ ", which is not declared")
  Just vs <- operands ix l env as k.fields
    | Nothing => pure Nothing
  Just <$> con ix l k vs
-- A `let` binds an SSA value; its type is its value's.
alg ix own (LetF l u v b) env expected = do
  Just x <- v.result env Nothing
    | Nothing => pure Nothing
  x' <- coerce ix l u x
  b.result (bind [x'] env) expected
-- A match takes its scrutinee at its grade: a linear one is used by the
-- match, whose cases bind the fields as the constructor holds them and
-- whose default gets the value back; a plain one is read, its fields plain
-- (the product of the quantities, as Idris binds pattern variables).
alg ix own (CaseF l x alts def) env expected = do
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
      (args, inner) <- the (E (List Value, b -> Val)) $ if takenApart
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
    alternative : Val -> Val -> AltF (Sub Em) b -> E Arm
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
      pure (MkArm (Just (flatSymbolRefAttr (mangle c.name))) args res ops)
alg ix own (CaseLitF l x alts def) env expected = do
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
alg ix own (CaseNatF l x z s) env expected =
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
alg ix own (LamF l lbl caps b body) env expected = do
  capVals <- traverse (force ix l . env) caps
  let result = case expected of
                 Just (FunT _ r) => Just r
                 _ => Nothing
  (sym, rt) <- lifted ix own l lbl capVals [val "" (typeOf b) (binderUse b)] result
                 (\cs, [p] => body.result (bind [p] (\i => index i cs)) result)
  Just <$> closure sym (toList capVals) (FunT b rt)
  where
    closure : String -> List Val -> Ty -> E Val
    closure sym cs t = value ix l t (Idr.closureOp sym !(traverse (operand ix) cs))
alg ix own (AppF l f x) env expected = do
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
alg ix own (SuspendF l lbl caps body) env expected = do
  capVals <- traverse (force ix l . env) caps
  let result = case expected of
                 Just (LazyT r) => Just r
                 _ => Nothing
  (sym, rt) <- lifted ix own l lbl capVals [] result (\cs, _ => body.result (\i => index i cs) result)
  captures <- traverse (operand ix) (toList capVals)
  Just <$> value ix l (LazyT rt) (Idr.suspendOp sym captures)
alg ix own (ResumeF l e) env expected = do
  Just ev <- plain ix l (e.result env Nothing)
    | Nothing => pure Nothing
  LazyT r <- pure ev.type
    | t => internal ("a force of a value of type " ++ show t)
  callee <- operand ix ev
  Just <$> value ix l r (Idr.forceOp callee)
-- The two loops over an array's index space: the body is a region taking
-- the index (and for a fold the accumulator and the element), which yields
-- the element (the next accumulator); a body that never returns ends in
-- ub.unreachable, as a match region does.
alg ix own (ArrayGenF l e n x w body res) env _ = do
  Just [nv, xv, wv] <- operands ix l env [n, x, w] [Held Many (IntT IdrisInt), Held Many e, Held Many WorldT]
    | _ => pure Nothing
  i <- val <$> fresh <*> pure (IntT IdrisInt) <*> pure Many
  (r, ops) <- collect (plain ix l (body.result (bind [i] env) (Just e)))
  yields <- yielding ix l r
  let region = MkRegion [!(operand ix i)] (ops ++ yields)
  out <- fresh
  append (MkStatement (Just out)
           (Idr.arrayGenerateOp !(operand ix nv) !(operand ix xv) !(operand ix wv) region
                                !(mlirType ix (ArrayT e)) !(mlirType ix WorldT))
           (At l))
  Just <$> ioResult ix l res (val (out ++ "#0") (ArrayT e) Many) (val (out ++ "#1") WorldT Many)
alg ix own (ArrayFoldF l e t arr z w body res) env _ = do
  Just [av, zv, wv] <- operands ix l env [arr, z, w] [Held Many (ArrayT e), Held Many t, Held Many WorldT]
    | _ => pure Nothing
  acc <- val <$> fresh <*> pure t <*> pure Many
  x <- val <$> fresh <*> pure e <*> pure Many
  i <- val <$> fresh <*> pure (IntT IdrisInt) <*> pure Many
  (r, ops) <- collect (plain ix l (body.result (bind [acc, x, i] env) (Just t)))
  yields <- yielding ix l r
  let region = MkRegion !(traverse (operand ix) [acc, x, i]) (ops ++ yields)
  out <- fresh
  append (MkStatement (Just out)
           (Idr.arrayFoldOp !(operand ix av) !(operand ix zv) !(operand ix wv) region
                            !(mlirType ix t) !(mlirType ix WorldT))
           (At l))
  Just <$> ioResult ix l res (val (out ++ "#0") t Many) (val (out ++ "#1") WorldT Many)
alg ix own (UnreachableF l) env _ = do
  statement l UB.unreachableOp
  pure Nothing
-- A crash reports its message and never returns.
alg ix own (CrashF l msg) env _ = do
  statement l (Idr.crashOp msg)
  statement l UB.unreachableOp
  pure Nothing
alg ix own (NewWorldF l) env _ = Just <$> value ix l WorldT Idr.worldNewOp
