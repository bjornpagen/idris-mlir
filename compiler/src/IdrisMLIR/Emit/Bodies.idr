||| Function bodies: the algebra of the fold that writes a term, its
||| matches as regions and its lambdas as lifted functions.
module IdrisMLIR.Emit.Bodies

import IdrisMLIR.Emit.Attributes
import IdrisMLIR.Emit.Breakers
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
  v' <- coerce ix l (maybe Plain binderMode (head' slots)) v
  map (map (v' ::)) (operands ix l env as (drop 1 slots))

||| A value as a region or a function returns it: as itself, never linear.
export
plain : Index -> Loc -> E (Maybe Val) -> E (Maybe Val)
plain ix l act = act >>= traverse (coerce ix l Plain)

mutual
  ||| `v`, with every value named as `before` is, itself or a field of a
  ||| rebuilt constructor, replaced by `after`.
  renamed : (before, after : Val) -> Val -> Val
  renamed before after (MkVal n t m r) =
    if n == before.name then after else MkVal n t m (renamedIn before after r)

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

||| A region of a match: its header, its operations, and its value, which
||| it yields.
record Region where
  constructor MkRegion
  header : String
  result : Maybe Val
  ops : List Op

||| A match, from its regions: results when a region yields, and none,
||| followed by `ub.unreachable`, when no region returns.
match : Index -> Loc -> String -> List Region -> E (Maybe Val)
match ix l head regions =
  case map (.type) (head' (mapMaybe (.result) regions)) of
    Just t => do
      rt <- typeText ix t
      body <- traverse (close rt) regions
      r <- fresh
      append (Nest (r ++ " = " ++ head ++ " -> (" ++ rt ++ ") {") body "}" (Just (At l)))
      pure (Just (val r t Plain))
    Nothing => do
      body <- traverse (close "") regions
      append (Nest (head ++ " -> () {") body "}" (Just (At l)))
      statement l "ub.unreachable"
      pure Nothing
  where
    close : String -> Region -> E Op
    close rt reg = case reg.result of
      Just v => pure (Nest reg.header (reg.ops ++ [Line ("idr.yield " ++ v.name ++ " : " ++ !(typeText ix v.type)) (At l)]) "}" Nothing)
      Nothing => pure (Nest reg.header reg.ops "}" Nothing)

||| A literal as a key of `idr.match_lit`.
key : Lit -> String
key (LInt t n) = show (twos (width t) n)
key (LChar c) = show c
key (LStr s) = utf8 s
key (LBig n) = "#idr.big<" ++ quoted (show n) ++ ">"
key (LNat n) = "#idr.big<" ++ quoted (show n) ++ ">"
key (LDouble d) = floatLiteral d

||| Starts a function: its own SSA numbers and operations, the owner's
||| lifted functions kept.
export
inFunction : E a -> E (a, List Op)
inFunction act = do
  st <- get
  put ({ next := 0, ops := [<] } st)
  x <- act
  inner <- gets (.ops)
  modify { next := st.next, ops := st.ops }
  pure (x, inner <>> [])

||| The end of a function's body, of result type `rt`: its value, returned.
||| A body that never returns ends in `ub.unreachable` inside its regions
||| only; at the top level a poison value is returned in its place, because
||| the pinned inliner cannot inline a body that ends in `ub.unreachable`
||| (PINS.md: inline-unreachable).
export
epilogue : Loc -> String -> Maybe Val -> List Op -> List Op
epilogue l rt (Just v) ops = ops ++ [Line ("func.return " ++ v.name ++ " : " ++ rt) (At l)]
epilogue l rt Nothing ops =
  reverse (dropEnd (reverse ops)) ++
    [ Line ("%never = ub.poison : " ++ rt) (At l)
    , Line ("func.return %never : " ++ rt) (At l) ]
  where
    dropEnd : List Op -> List Op
    dropEnd (Line "ub.unreachable" _ :: rest) = rest
    dropEnd rest = rest

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
  rt <- typeText ix t
  header <- traverse (param ix) params
  let fn = Nest ("func.func private " ++ symbol sym ++ "(" ++ joinBy ", " header ++ ") -> " ++ rt ++
                 attributes (own.inherited ++ [Total | contains (LamNode lbl) ix.terminating] ++
                             [NoInline | contains (LamNode lbl) ix.breakers]) ++ " {")
                (epilogue l rt res ops) "}" (Just (Named own.idrisName l))
  modify { lifted $= (:< fn) }
  pure (sym, t)
  where
    renamed : Val -> E Val
    renamed v = (\n => { name := n } v) <$> fresh

||| The algebra: one layer of `Term` to its emitter.
export
alg : {0 b : Type} -> Index -> Owner -> TermF (Sub Em) b -> Em b
alg ix own (VarF l x) env _ = Just <$> force ix l (env x)
alg ix own (LiteralF l x) env _ = Just <$> literal l x
alg ix own (ErasedF l) env _ = Just <$> erased l
alg ix own (PrimAppF l p as) env _ = do
  Just vs <- operands ix l env as (map (Held Many) (primArgs p))
    | Nothing => pure Nothing
  Just <$> prim l p vs
alg ix own (EffectF l op as res) env _ = do
  Just vs <- operands ix l env as (map (Held Many) (ioArgs op ++ [WorldT]))
    | Nothing => pure Nothing
  Just <$> io ix l op vs res
alg ix own (CallF l fn as) env _ = do
  Just f <- pure (lookup fn ix.fns)
    | Nothing => internal ("a call of " ++ show fn ++ ", which is not in the program")
  Just vs <- operands ix l env as (toList f.params)
    | Nothing => pure Nothing
  rt <- typeText ix f.result
  Just <$> value l f.result ("func.call " ++ symbol (mangle fn.name) ++ "(" ++ names vs ++ ") : (" ++
                             !(types ix vs) ++ ") -> " ++ rt)
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
  x' <- coerce ix l (modeOf u x.type) x
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
  st <- valText ix scrut
  cases <- traverse (alternative before scrut) (filter (\(MkAltF _ _ b) => not (excluded b)) alts)
  dflt <- case def of
    Just e => if excluded e then pure [] else do
      (header, inner) <- case scrut.mode of
        Linear => do
          back <- (\r => val r scrut.type Linear) <$> fresh
          pure ("default(" ++ !(param ix back) ++ ") {", matched before back env)
        Plain => pure ("default {", env)
      (res, ops) <- collect (plain ix l (e.result inner expected))
      pure [MkRegion header res ops]
    Nothing => pure []
  case cases ++ dflt of
    [] => do
      statement l "ub.unreachable"
      pure Nothing
    regions => match ix l ("idr.match " ++ scrut.name ++ " : " ++ st) regions
  where
    alternative : Val -> Val -> AltF (Sub Em) b -> E Region
    alternative before scrut (MkAltF c fs body) = do
      let held = case scrut.mode of
                   Linear => binderMode
                   Plain => const Plain
      vals <- traverse (\f => (\n => val n (typeOf f) (held f)) <$> fresh) fs
      args <- traverse (param ix) (toList vals)
      -- Inside a case of a linear scrutinee, the scrutinee is the
      -- constructor of the fields the case bound.
      inner <- case scrut.mode of
        Linear => (\key => matched before (MkVal key scrut.type Plain (Just (c, toList vals))) env) <$> fresh
        Plain => pure env
      (res, ops) <- collect (plain ix l (body.result (bind vals inner) expected))
      pure (MkRegion ("case " ++ symbol (mangle c.name) ++ "(" ++ joinBy ", " args ++ ") {") res ops)
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
      statement l "ub.unreachable"
      pure Nothing
    ([], Just e) => e.result env expected
    (_, Just e) => do
      scrut <- coerce ix l Plain !(force ix l (env x))
      let inner = matched (env x) scrut env
      st <- typeText ix scrut.type
      regions <- traverse (\(k, c) => do
                             (res, ops) <- collect (plain ix l (c.result inner expected))
                             pure (MkRegion ("case " ++ key k ++ " {") res ops)) cases
      (res, ops) <- collect (plain ix l (e.result inner expected))
      match ix l ("idr.match_lit " ++ scrut.name ++ " : " ++ st) (regions ++ [MkRegion "default {" res ops])
-- The predecessor exists only where the value is not zero: the successor's
-- region computes it, and only it binds it.
alg ix own (CaseNatF l x z s) env expected =
  case (excluded z, excluded s) of
    (True, True) => do
      statement l "ub.unreachable"
      pure Nothing
    (False, True) => z.result env expected
    (True, False) => successor !(coerce ix l Plain !(force ix l (env x)))
    (False, False) => do
      n <- coerce ix l Plain !(force ix l (env x))
      (zr, zops) <- collect (plain ix l (z.result env expected))
      (sr, sops) <- collect (plain ix l (successor n))
      match ix l ("idr.match_lit " ++ n.name ++ " : !idr.nat")
            [MkRegion ("case " ++ key (LNat 0) ++ " {") zr zops, MkRegion "default {" sr sops]
  where
    successor : Val -> E (Maybe Val)
    successor n = do
      p <- value l NatT ("idr.big.pred " ++ n.name)
      s.result (bind [p] env) expected
alg ix own (LamF l lbl caps b body) env expected = do
  capVals <- traverse (force ix l . env) caps
  let result = case expected of
                 Just (FunT _ r) => Just r
                 _ => Nothing
  (sym, rt) <- lifted ix own l lbl capVals [val "" (typeOf b) (binderMode b)] result
                 (\cs, [p] => body.result (bind [p] (\i => index i cs)) result)
  let t = FunT b rt
  Just <$> closure sym (toList capVals) t
  where
    closure : String -> List Val -> Ty -> E Val
    closure sym cs t = value l t ("idr.closure " ++ symbol sym ++ "(" ++ names cs ++ ") : (" ++
                                  !(types ix cs) ++ ") -> " ++ !(typeText ix t))
alg ix own (AppF l f x) env expected = do
  Just fv <- plain ix l (f.result env Nothing)
    | Nothing => pure Nothing
  FunT a r <- pure fv.type
    | t => internal ("an application of a value of type " ++ show t)
  Just xv <- x.result env (Just (typeOf a))
    | Nothing => pure Nothing
  xv <- coerce ix l (binderMode a) xv
  Just <$> value l r ("idr.apply " ++ fv.name ++ "(" ++ xv.name ++ ") : " ++ !(typeText ix fv.type))
alg ix own (SuspendF l lbl caps body) env expected = do
  capVals <- traverse (force ix l . env) caps
  let result = case expected of
                 Just (LazyT r) => Just r
                 _ => Nothing
  (sym, rt) <- lifted ix own l lbl capVals [] result (\cs, _ => body.result (\i => index i cs) result)
  let t = LazyT rt
  Just <$> value l t ("idr.closure " ++ symbol sym ++ "(" ++ names (toList capVals) ++ ") : (" ++
                      !(types ix (toList capVals)) ++ ") -> " ++ !(typeText ix t))
alg ix own (ResumeF l e) env expected = do
  Just ev <- plain ix l (e.result env Nothing)
    | Nothing => pure Nothing
  LazyT r <- pure ev.type
    | t => internal ("a force of a value of type " ++ show t)
  Just <$> value l r ("idr.apply " ++ ev.name ++ "() : " ++ !(typeText ix ev.type))
alg ix own (UnreachableF l) env _ = do
  statement l "ub.unreachable"
  pure Nothing
-- A crash reports its message and never returns.
alg ix own (CrashF l msg) env _ = do
  statement l ("idr.crash " ++ utf8 msg)
  statement l "ub.unreachable"
  pure Nothing
