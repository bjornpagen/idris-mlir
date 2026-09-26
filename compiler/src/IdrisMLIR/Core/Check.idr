||| The invariants of Core (docs/architecture/05-middle-ir.md, CORE-INV-*,
||| CORE-CHECK-1). A failure is an internal compiler error: every user error
||| is reported earlier, by the frontend, `Simplify` or `HeapCheck`.
module IdrisMLIR.Core.Check

import IdrisMLIR.Core

import Data.List
import Data.Maybe
import Data.SortedMap
import Data.SortedSet
import Data.String

%default covering

Scope : Type
Scope = List (Var, (Quantity, Ty))

M : Type -> Type
M = Either String

||| The failure message names the function and the rule.
err : Fn -> String -> String -> M a
err fn rule msg = Left (rule ++ " in " ++ fn.name ++ ": " ++ msg)

------------------------------------------------------------------------------
-- Full Core (after Translate): closed, references resolve, arities match
------------------------------------------------------------------------------

mutual
  fullExpr : Program -> Fn -> Scope -> Expr -> M ()
  fullExpr prog fn sc (EVar _ x) =
    unless (isJust (lookup x sc)) $ err fn "CORE-INV-1" ("unbound variable %" ++ show x)
  fullExpr prog fn sc (EPrim _ _ as) = traverse_ (fullExpr prog fn sc) as
  fullExpr prog fn sc (EIO _ _ as r) = do
    unless (isJust (lookupData r prog)) $ err fn "CORE-INV-3" ("unknown IO result " ++ r)
    traverse_ (fullExpr prog fn sc) as
  fullExpr prog fn sc (ECall _ f as) = do
    Just g <- pure (lookupFn f prog)
      | Nothing => err fn "CORE-INV-2" ("call of unknown function " ++ f)
    unless (length as == length g.params) $
      err fn "CORE-INV-2" ("call of " ++ f ++ " with " ++ show (length as) ++ " arguments")
    traverse_ (fullExpr prog fn sc) as
  fullExpr prog fn sc (EPartial _ f as) = do
    unless (isJust (lookupFn f prog)) $ err fn "CORE-INV-2" ("unknown function " ++ f)
    traverse_ (fullExpr prog fn sc) as
  fullExpr prog fn sc (ECon _ d c as) = do
    Just con <- pure (lookupCon d c prog)
      | Nothing => err fn "CORE-INV-2" ("unknown constructor " ++ c ++ " of " ++ d)
    unless (length as == length con.fields) $
      err fn "CORE-INV-2" ("constructor " ++ c ++ " with " ++ show (length as) ++ " arguments")
    traverse_ (fullExpr prog fn sc) as
  fullExpr prog fn sc (ELet _ x q t v b) = do
    fullExpr prog fn sc v
    fullExpr prog fn ((x, (q, t)) :: sc) b
  fullExpr prog fn sc (EMatchCon _ x alts d) = do
    fullExpr prog fn sc (EVar noLoc x)
    Just (_, DataT dn) <- pure (lookup x sc)
      | _ => err fn "CORE-INV-6" ("constructor match on %" ++ show x ++ ", which is not data")
    for_ alts $ \(MkConAlt c xs e) => do
      Just con <- pure (lookupCon dn c prog)
        | Nothing => err fn "CORE-INV-6" (c ++ " is not a constructor of " ++ dn)
      unless (length xs == length con.fields) $
        err fn "CORE-INV-6" ("alternative " ++ c ++ " binds the wrong number of fields")
      fullExpr prog fn (zip xs (map (\f => (f.quantity, f.type)) con.fields) ++ sc) e
    traverse_ (fullExpr prog fn sc) d
  fullExpr prog fn sc (EMatchLit _ x alts d) = do
    fullExpr prog fn sc (EVar noLoc x)
    traverse_ (fullExpr prog fn sc . snd) alts
    fullExpr prog fn sc d
  fullExpr prog fn sc (ELam _ x q t b) = fullExpr prog fn ((x, (q, t)) :: sc) b
  fullExpr prog fn sc (EApp _ f a) = fullExpr prog fn sc f >> fullExpr prog fn sc a
  fullExpr prog fn sc (EDelay _ e) = fullExpr prog fn sc e
  fullExpr prog fn sc (EForce _ e) = fullExpr prog fn sc e
  fullExpr prog fn sc _ = pure ()

||| The full-Core subset of the checks (CORE-CHECK-1), after `Translate`.
export
checkFull : Program -> Either String ()
checkFull prog = do
  unless (isJust (lookupFn prog.root prog)) $ Left "CORE-INV-8: the root is missing"
  for_ prog.fns $ \fn =>
    fullExpr prog fn (map (\p => (p.var, (p.quantity, p.type))) fn.params) fn.body

------------------------------------------------------------------------------
-- First-order Core (before Emit)
------------------------------------------------------------------------------

checkTy : Program -> Fn -> Ty -> M ()
checkTy prog fn (FunT {}) = err fn "CORE-INV-3" "a function type"
checkTy prog fn (LazyT _) = err fn "CORE-INV-3" "a Lazy type"
checkTy prog fn (DataT d) =
  unless (isJust (lookupData d prog)) $ err fn "CORE-INV-3" ("unknown data " ++ d)
checkTy _ _ _ = pure ()

||| Integer and character types can be scrutinized by literal matches.
litMatches : Ty -> Lit -> Bool
litMatches (IntT t) (LInt t' _) = t == t'
litMatches CharT (LChar _) = True
litMatches _ _ = False

||| Every binder of a function, in order (CORE-INV-1: unique).
binders : Expr -> List Var
binders (ELet _ x _ _ v b) = x :: binders v ++ binders b
binders (EMatchCon _ _ alts d) =
  concatMap (\(MkConAlt _ xs e) => xs ++ binders e) alts ++ maybe [] binders d
binders (EMatchLit _ _ alts d) = concatMap (binders . snd) alts ++ binders d
binders (EPrim _ _ as) = concatMap binders as
binders (EIO _ _ as _) = concatMap binders as
binders (ECall _ _ as) = concatMap binders as
binders (ECon _ _ _ as) = concatMap binders as
binders _ = []

||| The argument types and result value type of an IO operation.
ioSig : IOOp -> (List Ty, Ty)
ioSig PutStr = ([StrT, WorldT], DataT "Builtin.Unit")
ioSig PutChar = ([CharT, WorldT], DataT "Builtin.Unit")
ioSig (PutInt t) = ([IntT t, WorldT], DataT "Builtin.Unit")
ioSig GetChar = ([WorldT], CharT)
ioSig Exit = ([IntT IdrisInt, WorldT], DataT "Builtin.Unit")

mutual
  ||| An argument in a position of the given quantity and type.
  arg : Program -> Fn -> Scope -> (Quantity, Ty) -> Expr -> M ()
  arg prog fn sc (Q0, t) e = case e of
    EErased _ => unless (t == ErasedT) $ err fn "CORE-INV-3" "a quantity-0 position whose type is not Erased"
    _ => err fn "CORE-INV-3" "a quantity-0 position whose argument is not Erased"
  arg prog fn sc (_, t) e = do
    t' <- infer prog fn sc e
    unless (t == t') $ err fn "CORE-INV-3" ("expected " ++ show t ++ ", got " ++ show t')

  ||| The type of a first-order expression.
  infer : Program -> Fn -> Scope -> Expr -> M Ty
  infer prog fn sc (EVar _ x) = case lookup x sc of
    Just (Q0, _) => err fn "CORE-INV-5" ("quantity-0 variable %" ++ show x ++ " used at runtime")
    Just (_, t) => pure t
    Nothing => err fn "CORE-INV-1" ("unbound variable %" ++ show x)
  infer prog fn sc (ELit _ l) = pure (litTy l)
  infer prog fn sc (EErased _) = pure ErasedT
  infer prog fn sc (EWorld _) = err fn "CORE-INV-9" "%MkWorld"
  infer prog fn sc (EPrim _ op as) = do
    when (isStringOp op) $ err fn "CORE-INV-10" ("the string operation " ++ show op)
    ts <- traverse (infer prog fn sc) as
    let ok = case (op, ts) of
               (Cast a _, [t]) => a == t
               (Lt t, [a, b]) => a == t && b == t
               (Lte t, [a, b]) => a == t && b == t
               (Eq t, [a, b]) => a == t && b == t
               (Gte t, [a, b]) => a == t && b == t
               (Gt t, [a, b]) => a == t && b == t
               (_, [a, b]) => a == primResult op && b == primResult op
               _ => False
    unless ok $ err fn "CORE-INV-3" ("ill-typed primitive " ++ show op)
    pure (primResult op)
  infer prog fn sc (EIO _ op as r) = do
    Just dt <- pure (lookupData r prog)
      | Nothing => err fn "CORE-INV-3" ("unknown IO result " ++ r)
    let [MkCon _ _ _ [MkField _ val, MkField _ WorldT] _] = dt.cons
      | _ => err fn "CORE-INV-3" (r ++ " is not an IO result")
    ts <- traverse (infer prog fn sc) as
    let (args, res) = ioSig op
    unless (ts == args && val == res) $
      err fn "CORE-INV-3" ("ill-typed IO operation " ++ show op)
    pure (DataT r)
  infer prog fn sc (ECall _ f as) = do
    Just g <- pure (lookupFn f prog)
      | Nothing => err fn "CORE-INV-2" ("call of unknown function " ++ f)
    unless (length as == length g.params) $ err fn "CORE-INV-2" ("call of " ++ f ++ " with the wrong arity")
    traverse_ (\(p, a) => arg prog fn sc (p.quantity, p.type) a) (zip g.params as)
    pure g.result
  infer prog fn sc (ECon _ d c as) = do
    Just con <- pure (lookupCon d c prog)
      | Nothing => err fn "CORE-INV-2" ("unknown constructor " ++ c ++ " of " ++ d)
    unless (length as == length con.fields) $ err fn "CORE-INV-2" ("constructor " ++ c ++ " with the wrong arity")
    traverse_ (\(f, a) => arg prog fn sc (f.quantity, f.type) a) (zip con.fields as)
    pure (DataT d)
  infer prog fn sc (ELet _ x q t v b) = do
    checkTy prog fn t
    arg prog fn sc (q, t) v
    infer prog fn ((x, (q, t)) :: sc) b
  infer prog fn sc (EMatchCon _ x alts d) = do
    Just (q, DataT dn) <- pure (lookup x sc)
      | _ => err fn "CORE-INV-6" ("constructor match on %" ++ show x ++ ", which is not data")
    when (q == Q0) $ err fn "CORE-INV-5" ("match on quantity-0 variable %" ++ show x)
    Just dt <- pure (lookupData dn prog)
      | Nothing => err fn "CORE-INV-3" ("unknown data " ++ dn)
    let names = map (\(MkConAlt c _ _) => c) alts
    unless (length (nub names) == length names) $ err fn "CORE-INV-6" "duplicate alternatives"
    when (isNothing d && any (\c => not (elem c.name names)) dt.cons) $
      err fn "CORE-INV-6" ("a match on " ++ dn ++ " that does not cover every constructor")
    ts <- for alts $ \(MkConAlt c xs e) => do
      Just con <- pure (find (\k => k.name == c) dt.cons)
        | Nothing => err fn "CORE-INV-6" (c ++ " is not a constructor of " ++ dn)
      unless (length xs == length con.fields) $ err fn "CORE-INV-6" ("alternative " ++ c ++ " binds the wrong number of fields")
      infer prog fn (zip xs (map (\f => (f.quantity, f.type)) con.fields) ++ sc) e
    td <- traverse (infer prog fn sc) d
    same fn (ts ++ toList td)
  infer prog fn sc (EMatchLit _ x alts d) = do
    t <- infer prog fn sc (EVar noLoc x)
    unless (all (litMatches t . fst) alts) $ err fn "CORE-INV-6" "a literal of the wrong type"
    let ks = map (show . fst) alts
    unless (length (nub ks) == length ks) $ err fn "CORE-INV-6" "duplicate literals"
    ts <- traverse (infer prog fn sc . snd) alts
    td <- infer prog fn sc d
    same fn (ts ++ [td])
  infer prog fn sc (ELam {}) = err fn "CORE-INV-2" "a lambda"
  infer prog fn sc (EApp {}) = err fn "CORE-INV-2" "an application of an unknown function"
  infer prog fn sc (EPartial {}) = err fn "CORE-INV-2" "a partial application"
  infer prog fn sc (EDelay {}) = err fn "CORE-INV-2" "Delay"
  infer prog fn sc (EForce {}) = err fn "CORE-INV-2" "Force"

  same : Fn -> List Ty -> M Ty
  same fn [] = err fn "CORE-INV-6" "a match without alternatives"
  same fn (t :: ts) = if all (== t) ts then pure t else err fn "CORE-INV-3" "alternatives of different types"

sums : List (SortedMap Var Nat) -> SortedMap Var Nat
sums = foldl (mergeWith (+)) empty

maxes : List (SortedMap Var Nat) -> SortedMap Var Nat
maxes = foldl (mergeWith max) empty

||| Uses of each world variable, taking the maximum over alternatives.
worldUses : Expr -> SortedMap Var Nat
worldUses (EVar _ x) = singleton x 1
worldUses (EPrim _ _ as) = sums (map worldUses as)
worldUses (EIO _ _ as _) = sums (map worldUses as)
worldUses (ECall _ _ as) = sums (map worldUses as)
worldUses (ECon _ _ _ as) = sums (map worldUses as)
worldUses (ELet _ _ _ _ v b) = sums [worldUses v, worldUses b]
worldUses (EMatchCon _ _ alts d) =
  maxes (maybe [] (pure . worldUses) d ++ map (\(MkConAlt _ _ e) => worldUses e) alts)
worldUses (EMatchLit _ _ alts d) = maxes (worldUses d :: map (worldUses . snd) alts)
worldUses _ = empty

||| World variables: parameters and fields of type %World.
worldVars : Program -> Fn -> List Var
worldVars prog fn = [p.var | p <- fn.params, p.type == WorldT] ++ go fn.body
  where
    go : Expr -> List Var
    go (ELet _ x _ t v b) = (if t == WorldT then [x] else []) ++ go v ++ go b
    go (EMatchCon _ _ alts d) = concatMap alt alts ++ maybe [] go d
      where
        alt : ConAlt -> List Var
        alt (MkConAlt c xs e) =
          let tys = fromMaybe [] (map (map (.type) . (.fields)) (find (\k => k.name == c) (concatMap (.cons) prog.datas)))
          in [x | (x, t) <- zip xs tys, t == WorldT] ++ go e
    go (EMatchLit _ _ alts d) = concatMap (go . snd) alts ++ go d
    go _ = []

checkData : Program -> Data -> M ()
checkData prog d = do
  unless (map (.tag) d.cons == [0 .. length d.cons `minus` 1] || null d.cons) $
    Left ("CORE-INV-7: the tags of " ++ d.name ++ " are not 0..n-1")
  for_ d.cons $ \c => for_ c.fields $ \f => case f.type of
    FunT {} => Left ("CORE-INV-3: a function field in " ++ d.name)
    LazyT _ => Left ("CORE-INV-3: a Lazy field in " ++ d.name)
    DataT n => unless (isJust (lookupData n prog)) $ Left ("CORE-INV-3: unknown data " ++ n)
    ErasedT => unless (f.quantity == Q0) $ Left ("CORE-INV-3: an erased runtime field in " ++ d.name)
    _ => pure ()

||| Runtime containment is acyclic (CORE-INV-7).
acyclic : Program -> M ()
acyclic prog = for_ prog.datas $ \d => go [d.name] d
  where
    go : List String -> Data -> M ()
    go path d = for_ d.cons $ \c => for_ c.fields $ \f => case f.type of
      DataT n => if elem n path
                    then Left ("CORE-INV-7: " ++ n ++ " contains itself")
                    else maybe (pure ()) (go (n :: path)) (lookupData n prog)
      _ => pure ()

||| Functions reachable from the root (CORE-INV-8).
reachable : Program -> SortedSet String
reachable prog = go empty [prog.root]
  where
    calls : Expr -> List String
    calls (ECall _ f as) = f :: concatMap calls as
    calls (EPrim _ _ as) = concatMap calls as
    calls (EIO _ _ as _) = concatMap calls as
    calls (ECon _ _ _ as) = concatMap calls as
    calls (ELet _ _ _ _ v b) = calls v ++ calls b
    calls (EMatchCon _ _ alts d) = concatMap (\(MkConAlt _ _ e) => calls e) alts ++ maybe [] calls d
    calls (EMatchLit _ _ alts d) = concatMap (calls . snd) alts ++ calls d
    calls _ = []
    go : SortedSet String -> List String -> SortedSet String
    go seen [] = seen
    go seen (f :: rest) =
      if contains f seen then go seen rest
      else go (insert f seen) (rest ++ maybe [] (calls . (.body)) (lookupFn f prog))

||| Every invariant of first-order Core (CORE-CHECK-1), before `Emit`.
export
checkFirstOrder : Program -> Either String ()
checkFirstOrder prog = do
  checkFull prog
  traverse_ (checkData prog) prog.datas
  acyclic prog
  let live = reachable prog
  for_ prog.fns $ \fn => do
    unless (contains fn.name live) $ err fn "CORE-INV-8" "unreachable from the root"
    checkTy prog fn fn.result
    for_ fn.params $ \p => do
      checkTy prog fn p.type
      when (p.quantity == Q0 && p.type /= ErasedT) $ err fn "CORE-INV-3" "a quantity-0 parameter whose type is not Erased"
    let vars = map (.var) fn.params ++ binders fn.body
    unless (length (nub vars) == length vars) $ err fn "CORE-INV-1" "a variable is bound twice"
    t <- infer prog fn (map (\p => (p.var, (p.quantity, p.type))) fn.params) fn.body
    unless (t == fn.result) $ err fn "CORE-INV-3" ("the body has type " ++ show t ++ ", not " ++ show fn.result)
    let uses = worldUses fn.body
    for_ (worldVars prog fn) $ \w =>
      when (fromMaybe 0 (lookup w uses) > 1) $
        err fn "CORE-INV-9" ("the world %" ++ show w ++ " is used more than once on a path")
