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
import Data.List1
import Data.Maybe
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.String
import Data.Vect

%default total

||| What the fold makes of a term in scope `nv`: given what its variables
||| stand for and what its context wants (the type it expects, if known,
||| and the variable it binds the value to, if any), it appends the term's
||| operations and returns its value, or `Nothing` when the term never
||| returns (its region then ends in `ub.unreachable`).
public export
Em : Nat -> Type
Em nv = (Fin nv -> InScope) -> Wanted -> E (Maybe Val)

||| What a binder's variables stand for, over those outside.
bind : {k : Nat} -> Vect k InScope -> (Fin nv -> InScope) -> Fin (Under k nv) -> InScope
bind vs env v = case splitUnder {k} v of
  Left i => index i vs
  Right x => env x

mutual
  ||| The most times one run of a term uses the variable `v`: along a path
  ||| the uses add, across a match's arms the most of any counts, a match
  ||| uses its scrutinee once (its regions name what stands for it), and a
  ||| use in a region that runs once per index counts as many.
  export
  mostUses : Fin n -> Term n -> Nat
  mostUses v (Var _ x) = if v == x then 1 else 0
  mostUses v (Literal _ _) = 0
  mostUses v (PrimApp _ _ _ as) = vectUses v as
  mostUses v (Effect _ _ _ as _) = allUses v as
  mostUses v (Call _ _ _ as) = allUses v as
  mostUses v (ConApp _ _ as) = vectUses v as
  mostUses v (Let _ _ _ x b) = mostUses v x + mostUses (FS v) b
  mostUses v (Case _ x arms) = if v == x then 1 else armsUses v arms
  mostUses v (CaseLit _ x arms) = if v == x then 1 else litArmsUses v arms
  mostUses v (CaseNat _ x arms) = (if v == x then 1 else 0) + natArmsUses v arms
  mostUses v (Lam _ _ _ body) = mostUses (FS v) body
  mostUses v (App _ f x) = mostUses v f + mostUses v x
  mostUses v (Suspend _ body) = mostUses v body
  mostUses v (Resume _ e) = mostUses v e
  mostUses v (Unreachable _) = 0
  mostUses v (Crash _ _) = 0
  mostUses v (CrashWith _ m) = mostUses v m
  mostUses v (NewWorld _) = 0
  mostUses v (Tensor _ _ op) = opUses v op
  mostUses v (Tabulate {k} _ _ es body) = vectUses v es + many (mostUses (Free {k} v) body)
  mostUses v (TabulateIO {k} _ _ es w body _ _) =
    vectUses v es + mostUses v w + many (mostUses (Free {k = S k} v) body)
  mostUses v (Reduce _ _ _ _ _ z x body) = mostUses v z + mostUses v x + many (mostUses (Free {k = 2} v) body)
  mostUses v (Tie _ x ds) = mostUses v x + statedUses v ds

  allUses : Fin n -> List (Term n) -> Nat
  allUses v [] = 0
  allUses v (t :: ts) = mostUses v t + allUses v ts

  vectUses : Fin n -> Vect k (Term n) -> Nat
  vectUses v [] = 0
  vectUses v (t :: ts) = mostUses v t + vectUses v ts

  opUses : Fin n -> TensorOp (Term n) -> Nat
  opUses v (Extent _ x) = mostUses v x
  opUses v (Extract x cs) = mostUses v x + allUses v cs
  opUses v (Insert x e cs) = mostUses v x + mostUses v e + allUses v cs
  opUses v (Take _ k x) = mostUses v k + mostUses v x
  opUses v (Drop _ k x) = mostUses v k + mostUses v x
  opUses v (Concat _ x y) = mostUses v x + mostUses v y
  opUses v (Transpose _ x) = mostUses v x
  opUses v (Reshape x es) = mostUses v x + allUses v es

  statedUses : Fin n -> List (Nat, Stated (Term n)) -> Nat
  statedUses v [] = 0
  statedUses v ((_, SameAs t) :: ds) = mostUses v t + statedUses v ds
  statedUses v ((_, Natural t) :: ds) = mostUses v t + statedUses v ds

  altUse : Fin n -> Alt n -> Nat
  altUse v (MkAlt {k} _ _ body) = mostUses (Free {k} v) body

  altUses : Fin n -> List (Alt n) -> Nat
  altUses v [] = 0
  altUses v (alt :: alts) = max (altUse v alt) (altUses v alts)

  armsUses : Fin n -> CaseArms n -> Nat
  armsUses v (Defaulted alts d) = max (altUses v alts) (mostUses v d)
  armsUses v (Exhaustive (alt ::: alts)) = max (altUse v alt) (altUses v alts)

  litUses : Fin n -> List (Lit, Term n) -> Nat
  litUses v [] = 0
  litUses v ((_, t) :: alts) = max (mostUses v t) (litUses v alts)

  litArmsUses : Fin n -> LitArms n -> Nat
  litArmsUses v (LitDefault alts d) = max (litUses v alts) (mostUses v d)
  litArmsUses v (LitNoDefault ((_, t) ::: alts)) = max (mostUses v t) (litUses v alts)

  natArmsUses : Fin n -> NatArms n -> Nat
  natArmsUses v (OnlyZero z) = mostUses v z
  natArmsUses v (OnlySucc _ s) = mostUses (FS v) s
  natArmsUses v (Both z _ s) = max (mostUses v z) (mostUses (FS v) s)

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

||| What a layer's operands give, left to right: the next is written only
||| when the one before it returns, so that nothing follows a value that
||| never does (its region has ended in `ub.unreachable`).
record Operands a where
  constructor MkOperands
  written : E (Maybe a)

Functor Operands where
  map f (MkOperands x) = MkOperands (map (map f) x)

Applicative Operands where
  pure x = MkOperands (pure (Just x))
  MkOperands f <*> MkOperands x = MkOperands $ do
    Just g <- f
      | Nothing => pure Nothing
    map g <$> x

||| A subterm's value where a slot takes it: checked against the type the
||| slot expects, if it says one, and held as the slot binds it, plainly
||| where it says nothing; bound to no variable.
operand1 : Index -> Loc -> (Fin nv -> InScope) -> Maybe Binder -> Sub Em nv -> Operands Val
operand1 ix l env slot a = MkOperands $ do
  Just v <- a.result env (expecting (typeOf <$> slot))
    | Nothing => pure Nothing
  Just <$> coerce ix l (maybe Many (.quantity) slot) !(fit ix l (typeOf <$> slot) v)

||| A layer's operands, each in its slot, left to right; `Nothing` once one
||| never returns.
operands : Traversable t => Index -> Loc -> (Fin nv -> InScope) -> t (Maybe Binder, Sub Em nv) -> E (Maybe (t Val))
operands ix l env xs = (traverse (\(slot, a) => operand1 ix l env slot a) xs).written

||| Operands that no slot types: each at its own type, held plainly.
unslotted : Functor t => t (Sub Em nv) -> t (Maybe Binder, Sub Em nv)
unslotted = map (\a => (Nothing, a))

||| A value as a region or a function returns it: as itself, never linear.
export
plain : Index -> Loc -> E (Maybe Val) -> E (Maybe Val)
plain ix l act = act >>= traverse (coerce ix l Many)

||| What a match renames a variable's value by: an SSA value's name, or the
||| key of a constructor taken apart.
keyOf : InScope -> String
keyOf (Whole v) = v.name
keyOf (Taken _ _ k) = k

mutual
  ||| `s`, with what is keyed `before`, itself or a field of it, replaced by
  ||| `after`.
  renamed : (before : String) -> (after : InScope) -> InScope -> InScope
  renamed before after (Whole v) = if v.name == before then after else Whole v
  renamed before after (Taken c fs k) = if k == before then after else Taken c (renamedAll before after fs) k

  renamedAll : (before : String) -> (after : InScope) -> Vect k InScope -> Vect k InScope
  renamedAll before after [] = []
  renamedAll before after (v :: vs) = renamed before after v :: renamedAll before after vs

||| The scope of a match's regions. A match takes a linear scrutinee apart,
||| so inside the regions every variable that named it (a catch-all's, or an
||| outer clause's after a nested match) names what stands for it there:
||| the value the default region binds, or the constructor rebuilt from the
||| fields a case bound. SSA names and keys are unique within a function,
||| so the key says which variables those are; the fields of a rebuilt
||| constructor are renamed the same way, as an inner match takes them
||| apart in turn.
matched : InScope -> InScope -> (b -> InScope) -> b -> InScope
matched before after env y = renamed (keyOf before) after (env y)

||| An arm of a match: the arguments of its region, its operations, and its
||| value, which it yields.
record Arm where
  constructor MkArm
  arguments : List Argument
  result : Maybe Val
  statements : List Statement

||| The yield that ends a region with its value; a region that never
||| returns has ended in `ub.unreachable` already.
yielding : Index -> Loc -> Maybe Val -> E (List Statement)
yielding ix l Nothing = pure []
yielding ix l (Just v) = pure [MkStatement Nothing (Idr.yieldOp [operand v]) (At l)]

||| A match, from its arms, with the builder of its op over its default
||| region, its case regions and its results: results when an arm yields,
||| and none, followed by `ub.unreachable`, when no arm returns. The default
||| region is empty when the cases are exhaustive. The arms join at the type
||| the context expects, else the first case's, else the default's; an
||| arm's array of another static shape is cast to it.
match : Index -> Loc -> Wanted -> (MLIR.Region -> List MLIR.Region -> List MlirType -> Op)
     -> CaseArmsOf Arm Arm -> E (Maybe Val)
match ix l w build arms =
  case w.type <|> map (.type) (head' (mapMaybe (.result) cases) <|> fallback) of
    Just t => if all (\a => isNothing a.result) cases && isNothing fallback then never else do
      cs <- traverse (close t) cases
      d <- case arms of
        Defaulted _ d => close t d
        Exhaustive _ => pure NoBlocks
      Just <$> value {binder = w.binder} ix l t (\r => build d cs [r])
    Nothing => never
  where
    cases : List Arm
    cases = case arms of
      Defaulted cs _ => cs
      Exhaustive cs => forget cs
    fallback : Maybe Val
    fallback = case arms of
      Defaulted _ d => d.result
      Exhaustive _ => Nothing
    unclosed : Arm -> MLIR.Region
    unclosed a = MkRegion a.arguments a.statements
    close : Ty -> Arm -> E MLIR.Region
    close t a = do
      (v, cast) <- collect (traverse (fit ix l (Just t)) a.result)
      pure (MkRegion a.arguments (a.statements ++ cast ++ !(yielding ix l v)))
    never : E (Maybe Val)
    never = do
      let d = case arms of
                Defaulted _ d => unclosed d
                Exhaustive _ => NoBlocks
      statement l (build d (map unclosed cases) [])
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
epilogue ix l (Just v) ops = pure (ops ++ [MkStatement Nothing (Idr.returnOp [operand v]) (At l)])
epilogue ix l Nothing ops = pure ops

mutual
  ||| A value held plainly, or a constructor a match took apart, rebuilt
  ||| from plain values into fields none of which is linear.
  plainHeld : InScope -> Bool
  plainHeld (Whole v) = not (linear v.use v.type)
  plainHeld (Taken c fs _) = all (\f => f.quantity == Many) c.fields && allPlain fs

  allPlain : Vect k InScope -> Bool
  allPlain [] = True
  allPlain (v :: vs) = plainHeld v && allPlain vs

mutual
  ||| Whether a suspended term is a value already, so that forcing it would
  ||| compute nothing: a literal; a variable whose value is not linear, its
  ||| constructor rebuilt, if a match took it apart, from fields none of
  ||| which is linear; or a constructor of such values, none of its fields
  ||| linear. Its ops are then only constants and constructors of plain
  ||| values, and the suspension holds the value itself.
  evaluated : (Fin n -> InScope) -> Term n -> Bool
  evaluated env (Var _ x) = plainHeld (env x)
  evaluated env (Literal _ _) = True
  evaluated env (ConApp _ c as) = all (\f => f.quantity == Many) c.fields && allEvaluated env as
  evaluated env _ = False

  allEvaluated : (Fin n -> InScope) -> Vect k (Term n) -> Bool
  allEvaluated env [] = True
  allEvaluated env (t :: ts) = evaluated env t && allEvaluated env ts

||| A closure or a suspension of a function, made by `build` at type `t`
||| over `captures`, the variable `binder` bound to it. One that holds a
||| linear value is used once, as what it holds: its op makes it at its
||| linear type.
holding : Index -> Loc -> Maybe Binding -> Ty -> List Value -> (MlirType -> Op) -> E Val
holding ix l binder t captures build =
  -- Essential: the dialect gives the closure's type the quantity of its
  -- captures (a type rule of the op), which the op's result type states.
  if any linearType captures
    then do
      r <- mlirValueAt (madeAt binder l t One) (heldType One t) build
      pure (MkVal r.name t One)
    else value {binder} ix l t build
  where
    linearType : Value -> Bool
    linearType v = case v.type of
      Idr (QType One _ _ _) _ => True
      _ => False

||| A call passes as many values as its callee takes. A count that differs
||| is a position the translator did not drop; nothing is written for it.
saturated : Index -> Loc -> Term n -> String -> (given, taken : Nat) -> E ()
saturated ix l term what given taken =
  unless (given == taken) $
    internal (fastConcat [show l, ": ", what, " passes ", show given, " values; it takes ",
                          show taken, ": ", showBody (names ix) term 0])

||| The algebra: one layer of `Term` to its emitter. A layer whose value is
||| a subterm's (a `let`'s body, a match of one possible arm) passes what
||| its context wants on to it; every other subterm is an operand or a
||| region's, bound to no variable.
export
alg : {0 nv : Nat} -> Index -> TermF (Sub Em) nv -> Em nv
alg ix (VarF l x) env w = Just <$> force {binder = w.binder} ix l (env x)
alg ix (LiteralF l x) env w = Just <$> literal {binder = w.binder} ix l x
alg ix (PrimAppF l p _ as) env w = do
  Just vs <- operands ix l env (zip (map (map (MkBinder Many)) (slots p)) as)
    | Nothing => pure Nothing
  Just <$> prim w.binder ix l p vs
-- An IO primitive takes its operands at their own types.
alg ix (EffectF l p gives as res) env w = do
  Just vs <- operands ix l env (unslotted as)
    | Nothing => pure Nothing
  effect w.binder ix l p gives vs res
alg ix (CallF l fn stands as) env w = do
  Just f <- pure (lookup fn ix.fns)
    | Nothing => internal ("a call of " ++ show fn ++ ", which is not in the program")
  saturated ix l (Call l fn stands (map (.term) as)) ("a call of " ++ fn.name) (length as) f.arity
  Just vs <- operands ix l env (zip (map (Just . snd) (toList f.params)) as)
    | Nothing => pure Nothing
  Just <$> fitted {binder = w.binder} ix l w.type f.result (\r => Idr.callOp fn.name (map operand vs) [r])
alg ix (ConAppF l c as) env w = do
  Just vs <- operands ix l env (zip (map Just c.fields) as)
    | Nothing => pure Nothing
  Just <$> con {binder = w.binder} ix l c vs
-- A `let` binds an SSA value; its type is its value's, and the op that
-- makes it as the variable holds it stands at the variable's name.
alg ix (LetF l name q v b) env w = do
  let held = heldAs q (mostUses FZ b.term)
      binding = Just (MkBinding name held)
  Just x <- v.result env (MkWanted Nothing binding)
    | Nothing => pure Nothing
  x' <- coerce {binder = binding} ix l held x
  b.result (bind [Whole x'] env) w
-- A match takes its scrutinee at its grade: a linear one is used by the
-- match, whose cases bind the fields as the constructor holds them and
-- whose default gets the value back; a plain one is read, its fields plain
-- (the product of the quantities, as Idris binds pattern variables), and
-- its default binds it again. Inside every region the scrutinee is what
-- the region binds.
alg ix (CaseF l x arms) env w = do
  let before = env x
  scrut <- force ix l before
  DataT _ <- pure scrut.type
    | t => internal ("a match on a value of type " ++ show t)
  (tags, shape) <- the (E (List Nat, CaseArmsOf Arm Arm)) $ case arms of
    Defaulted alts d => do
      cs <- traverse (alternative before scrut) alts
      pure (map fst cs, Defaulted (map snd cs) !(defaultArm before scrut d))
    Exhaustive alts => do
      cs <- traverse (alternative before scrut) alts
      pure (forget (map fst cs), Exhaustive (map snd cs))
  match ix l w (\d, cs, ts => Idr.matchOp (operand scrut) tags d cs ts) shape
  where
    -- A case is its constructor's tag, each field a block argument at its
    -- pattern variable's name.
    alternative : InScope -> Val -> AltF (Sub Em) nv -> E (Nat, Arm)
    alternative before scrut (MkAltF {k} c fs body) = do
      let takenApart = linear scrut.use scrut.type
      let use = if takenApart then (\b : Binder => b.quantity) else const Many
      bound <- traverse (\f => freshVal (typeOf f) (use f)) c.fields
      let args = toList (zipWith (\field, (_, o) => MkArgument o (Named field l)) fs bound)
      (res, ops) <- collect $ do
        vals <- traverse (\(i, (v, _)) => Whole <$> holdFor ix l (mostUses (Bound {n = nv} i) body.term) v)
                         (zip range bound)
        -- Inside a case of a linear scrutinee, the scrutinee is the
        -- constructor of the fields the case bound.
        inner <- if takenApart
          then (\r => matched before (Taken c vals r) env) <$> fresh
          else pure env
        plain ix l (body.result (bind vals inner) (expecting w.type))
      pure (c.tag, MkArm args res ops)
    -- The default binds the scrutinee at its held type: a linear one given
    -- back, a plain one again.
    defaultArm : InScope -> Val -> Sub Em nv -> E Arm
    defaultArm before scrut d = do
      (back, arg) <- freshVal scrut.type scrut.use
      (res, ops) <- collect (plain ix l (d.result (matched before (Whole back) env) (expecting w.type)))
      pure (MkArm [MkArgument arg (At l)] res ops)
-- `idr.match_lit` has no exhaustive form: when Idris proved the default
-- impossible, the last possible alternative stands for it, and a match of
-- one is that alternative.
alg ix (CaseLitF l x arms) env w = case arms of
  LitDefault alts d => literals alts d
  LitNoDefault alts => literals (init alts) (snd (last alts))
  where
    literals : List (Lit, Sub Em nv) -> Sub Em nv -> E (Maybe Val)
    literals [] d = d.result env w
    literals cases d = do
      scrut <- coerce ix l Many !(force ix l (env x))
      let inner = matched (env x) (Whole scrut) env
      arms <- traverse (\(_, c) => do
                          (res, ops) <- collect (plain ix l (c.result inner (expecting w.type)))
                          pure (MkArm [] res ops)) cases
      (back, arg) <- freshVal scrut.type Many
      (res, ops) <- collect (plain ix l (d.result (matched (env x) (Whole back) env) (expecting w.type)))
      match ix l w (\dr, cs, ts => Idr.matchLitOp (operand scrut) (map (key . fst) cases) dr cs ts)
            (Defaulted arms (MkArm [MkArgument arg (At l)] res ops))
-- The predecessor exists only where the value is not zero: the successor's
-- arm computes it from the value it binds, and only it binds it.
alg ix (CaseNatF l x arms) env w = case arms of
  OnlyZero z => z.result env w
  OnlySucc p s => successor p s env w !(coerce ix l Many !(force ix l (env x)))
  Both z p s => do
    n <- coerce ix l Many !(force ix l (env x))
    (zr, zops) <- collect (plain ix l (z.result env (expecting w.type)))
    (back, arg) <- freshVal NatT Many
    (sr, sops) <- collect (plain ix l (successor p s (matched (env x) (Whole back) env) (expecting w.type) back))
    match ix l w (\dr, cs, ts => Idr.matchLitOp (operand n) [key (LNat 0)] dr cs ts)
          (Defaulted [MkArm [] zr zops] (MkArm [MkArgument arg (At l)] sr sops))
  where
    successor : Shown -> Sub Em (Under 1 nv) -> (Fin nv -> InScope) -> Wanted -> Val -> E (Maybe Val)
    successor p s scope w' n = do
      pv <- value {binder = Just (MkBinding p Many)} ix l NatT (Idr.bigPredOp (operand n))
      s.result (bind [Whole pv] scope) w'
-- A lambda is a closure of a function of its own, and a `Delay` a
-- suspension of one, each over the values its body uses from where it is
-- written: the body is written first, as a region, and the function made
-- of it. A suspension of a value is that value held, `idr.delay %v`. A
-- lambda's parameter and result are at the types the context expects of
-- them, the parameter cast inside to its binder's own: a closure's type
-- holds the extents its values are made at dynamic.
alg ix (LamF l name b body) env w = do
  let (param, result) = case w.type of
                          Just (FunT a r) => (typeOf a, Just r)
                          _ => (typeOf b, Nothing)
  (p, arg) <- freshVal param b.quantity
  (r, ops) <- collect $ do
    inner <- coerce ix l (heldAs b.quantity (mostUses FZ body.term)) !(fit ix l (Just (typeOf b)) p)
    plain ix l (body.result (bind [Whole inner] env) (expecting result)) >>= traverse (fit ix l result)
  Just t <- pure (result <|> map (.type) r)
    | Nothing => internal "the result type of a lambda whose body never returns"
  let rt = mlirType t
  ops' <- epilogue ix l r ops
  (sym, captures) <- lift l LiftedLambda [MkArgument arg (Named name l)] ops' [rt]
  Just <$> holding ix l w.binder (FunT (MkBinder b.quantity param) t) captures (Idr.closureOp sym captures)
alg ix (AppF l f x) env w = do
  Just fv <- plain ix l (f.result env (expecting Nothing))
    | Nothing => pure Nothing
  FunT a r <- pure fv.type
    | t => internal ("an application of a value of type " ++ show t)
  Just v <- x.result env (expecting (Just (typeOf a)))
    | Nothing => pure Nothing
  xv <- coerce ix l a.quantity !(fit ix l (Just (typeOf a)) v)
  Just <$> fitted {binder = w.binder} ix l w.type r (\t => Idr.applyOp (operand fv) [operand xv] [t])
alg ix (SuspendF l body) env w = do
  let result = case w.type of
                 Just (LazyT r) => Just r
                 _ => Nothing
  if evaluated env body.term
    then do
      Just v <- plain ix l (body.result env (expecting result))
        | Nothing => internal "a suspended value that never returns"
      Just <$> value {binder = w.binder} ix l (LazyT v.type) (Idr.delayOp (operand v))
    else do
      (r, ops) <- collect (plain ix l (body.result env (expecting result)) >>= traverse (fit ix l result))
      Just t <- pure (result <|> map (.type) r)
        | Nothing => internal "the result type of a Delay whose body never returns"
      let rt = mlirType t
      ops' <- epilogue ix l r ops
      (sym, captures) <- lift l LiftedDelay [] ops' [rt]
      Just <$> holding ix l w.binder (LazyT t) captures (Idr.suspendOp sym captures)
alg ix (ResumeF l e) env w = do
  Just ev <- plain ix l (e.result env (expecting Nothing))
    | Nothing => pure Nothing
  LazyT r <- pure ev.type
    | t => internal ("a force of a value of type " ++ show t)
  Just <$> fitted {binder = w.binder} ix l w.type r (Idr.forceOp (operand ev))
-- The array language: each operand bound once, in order, by the frontend;
-- each body a region of the array op Emit.Tensors writes.
alg ix (TensorF l rt op) env w = do
  Just vs <- operands ix l env (unslotted op)
    | Nothing => pure Nothing
  Just <$> tensorOp ix l w.binder rt vs
alg ix (TabulateF {k} l rt es body) env w = do
  Just extents <- operands ix l env (unslotted es)
    | Nothing => pure Nothing
  tabulate ix l w.binder rt extents
           (\coords => plain ix l (body.result (bind (map Whole coords) env) (expecting Nothing)))
alg ix (ReduceF l r acc el rt z x body) env w = do
  Just zv <- (operand1 ix l env Nothing z).written
    | Nothing => pure Nothing
  Just xv <- (operand1 ix l env Nothing x).written
    | Nothing => pure Nothing
  reduce ix l w.binder r acc el rt zv xv
         (\a, e => plain ix l (body.result (bind [Whole a, Whole e] env) (expecting (Just acc))))
alg ix (TieF l x ds) env w = do
  Just xv <- plain ix l (x.result env (expecting Nothing))
    | Nothing => pure Nothing
  Just dims <- statedAll ds
    | Nothing => pure Nothing
  Just <$> tie ix l w.binder xv dims
  where
    -- Each statement a natural.
    natural : Sub Em nv -> E (Maybe Val)
    natural d = plain ix l (d.result env (expecting (Just NatT)))
    statedAll : List (Nat, Stated (Sub Em nv)) -> E (Maybe (List (Nat, Stated Val)))
    statedAll [] = pure (Just [])
    statedAll ((a, SameAs d) :: rest) = do
      Just v <- natural d
        | Nothing => pure Nothing
      map ((a, SameAs v) ::) <$> statedAll rest
    statedAll ((a, Natural d) :: rest) = do
      Just v <- natural d
        | Nothing => pure Nothing
      map ((a, Natural v) ::) <$> statedAll rest
alg ix (TabulateIOF {k} l rt es w body step done) env wanted = do
  Just extents <- operands ix l env (unslotted es)
    | Nothing => pure Nothing
  Just world <- w.result env (expecting (Just WorldT))
    | Nothing => pure Nothing
  tabulateIO ix l wanted.binder rt extents world
             (\coords, wv => plain ix l (body.result (bind (snoc (map Whole coords) (Whole wv)) env) (expecting Nothing)))
             step done
alg ix (UnreachableF l) env _ = do
  statement l UB.unreachableOp
  pure Nothing
-- A crash reports its message and never returns: fixed, or computed (a
-- trusted library's crash of a string, whose string is the cause the
-- runtime prints).
alg ix (CrashF l msg) env _ = do
  statement l (Idr.crashOp msg)
  statement l UB.unreachableOp
  pure Nothing
alg ix (CrashWithF l m) env _ = do
  Just s <- (operand1 ix l env (Just (MkBinder Many StrT)) m).written
    | Nothing => pure Nothing
  statement l (Idr.crashStrOp (operand s))
  statement l UB.unreachableOp
  pure Nothing
alg ix (NewWorldF l) env w = Just <$> value {binder = w.binder} ix l WorldT Idr.worldNewOp
