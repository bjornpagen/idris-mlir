||| The guaranteed eliminations (docs/architecture/06-elimination.md, ELIM-G-*):
||| full Core to first-order Core.
|||
||| A two-level evaluator. `eval` is Futhark's judgment `E ⊢ e ⇝ ⟨e′, sv⟩`
||| (Hovgaard et al. TFP 2018) written in Kovács's `Gen` monad: it returns
||| the static value of a term and emits the residual first-order code of its
||| runtime parts. Values of a type that is not a value type (functions,
||| `Lazy`, static data such as `IO`) exist only here, as `SVal`s. Every use
||| of one is resolved by beta reduction (G1), known-constructor selection
||| (G2), specialization on static arguments (G3), static lets (G4), arity
||| raising (G5: a call whose result is static is specialized together with
||| the eliminations applied to it), compile-time primitives (G6), output
||| fusion (G7) and Force of Delay (G8). `reify` turns a value that must
||| exist at runtime into an atom, or reports why it cannot (PROF-HEAP-*).
||| Residual code keeps the evaluation order of the input (SEM-EVAL-*).
module IdrisMLIR.Simplify

import IdrisMLIR.Code
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Rule
import IdrisMLIR.Simplify.Fold
import IdrisMLIR.Simplify.Gen
import IdrisMLIR.Simplify.Safety
import IdrisMLIR.Simplify.Value
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

%default covering

V : Type
V = SVal Atom

------------------------------------------------------------------------------
-- The program
------------------------------------------------------------------------------

fnDef : Loc -> FnId -> M TFn
fnDef l f = do
  st <- get
  maybe (fail CoreCheck1 l ("unknown function " ++ show f)) pure (lookup f st.src.fns)

dataDef : Loc -> DataId -> M Data
dataDef l d = do
  st <- get
  maybe (fail CoreCheck1 l ("unknown data " ++ show d)) pure (lookup d st.src.datas)

conDef : Loc -> ConId -> M Con
conDef l c = do
  st <- get
  maybe (fail CoreCheck1 l ("unknown constructor " ++ show c)) pure (lookup c st.src.cons)

||| Why data is static, as the rule that a runtime choice of its constructor
||| breaks and what the data holds: a function (PROF-HEAP-1), a `Lazy` value
||| (PROF-HEAP-2), itself (SEM-REC-1) or an Integer (SEM-BIG-1), in that
||| order of precedence.
staticReason : SourceIndex -> DataId -> (Rule, String)
staticReason src d =
  case sortBy (\a, b => compare (fst a) (fst b)) (go (length (keys src.datas)) [d] d) of
    ((_, r) :: _) => r
    [] => (ProfHeap1, "a function")
  where
    reasons : Nat -> List DataId -> Ty -> List (Nat, (Rule, String))
    go : Nat -> List DataId -> DataId -> List (Nat, (Rule, String))
    go Z _ _ = []
    go (S k) seen n = case lookup n src.datas of
      Just dt => concatMap (reasons k seen . (.type)) (concatMap (.fields) dt.cons)
      Nothing => []
    reasons k seen (FunT {}) = [(0, (ProfHeap1, "a function"))]
    reasons k seen (LazyT _) = [(1, (ProfHeap2, "a Lazy value"))]
    reasons k seen (StaticT m) =
      if elem m seen then [(2, (ProfData3, "a value of its own type"))] else go k (m :: seen) m
    reasons k seen BigT = [(3, (ProfType4, "an Integer"))]
    reasons k seen (V _) = []

||| The type of a value after eliminations.
elimTy : Loc -> Ty -> List (Elim a) -> M Ty
elimTy l t [] = pure t
elimTy l (FunT _ _ r) (Apply _ :: es) = elimTy l r es
elimTy l (LazyT t) (ForceIt :: es) = elimTy l t es
elimTy l t (Proj c i :: es) = case dataOf t of
  Just _ => do
    con <- conDef l c
    maybe (fail CoreCheck1 l "a projection of a missing field") (\f => elimTy l f.type es) (getAt i con.fields)
  Nothing => fail CoreCheck1 l ("a projection from a value of type " ++ show t)
elimTy l t _ = fail CoreCheck1 l ("cannot eliminate a value of type " ++ show t)

||| The value type of a result that must exist at runtime.
runtimeTy : Loc -> Ty -> M VTy
runtimeTy l BigT = fail ProfType4 l "an Integer would exist at runtime here (SEM-BIG-1)"
runtimeTy l t = maybe (fail CoreCheck1 l ("a runtime value of type " ++ show t)) pure (value t)

||| Is a static string known not to be empty (ELIM-G-15)?
nonEmpty : SStr a -> Bool
nonEmpty (SLit s) = s /= ""
nonEmpty (SShow _ _) = True
nonEmpty (SChr _) = True
nonEmpty (SCons _ _) = True
nonEmpty (SAppend a b) = nonEmpty a || nonEmpty b
nonEmpty _ = False

isStr : Lit -> Bool
isStr (LStr _) = True
isStr _ = False

||| The value of a literal; an Integer is static (SEM-BIG-1).
litVal : Lit -> V
litVal (LInt t n) = Dyn (IntT t) (ALit (LInt t n))
litVal (LChar c) = Dyn CharT (ALit (LChar c))
litVal (LStr s) = Dyn StrT (ALit (LStr s))
litVal (LDouble d) = Dyn DoubleT (ALit (LDouble d))
litVal (LBig n) = SBig n

------------------------------------------------------------------------------
-- Strings (ELIM-G-6, ELIM-G-7)
------------------------------------------------------------------------------

||| A string value as a static string.
asStr : V -> Maybe (SStr Atom)
asStr (SString s) = Just s
asStr (Dyn StrT (ALit (LStr s))) = Just (SLit s)
asStr (Dyn StrT a) = Just (SRun a)
asStr _ = Nothing

||| A static string that is fully known.
strLit : SStr Atom -> Maybe String
strLit (SLit s) = Just s
strLit (SAppend a b) = (++) <$> strLit a <*> strLit b
strLit (SCons (ALit (LChar c)) s) = strCons (chr (cast c)) <$> strLit s
strLit (SChr (ALit (LChar c))) = Just (singleton (chr (cast c)))
strLit (SShow _ (ALit (LInt _ n))) = Just (show n)
strLit (SShow _ (ALit (LDouble d))) = Just (prim__cast_DoubleString d)
strLit _ = Nothing

||| A value known entirely at compile time: no runtime variable occurs in it,
||| directly or in what it captures (ELIM-G-12). Literals, Integers, known
||| strings, and constructors, closures and deferred calls over known values.
constant : V -> Bool
constant v = all known (atoms [v] [])
  where
    known : (VTy, Atom) -> Bool
    known (_, AVar _) = False
    known _ = True

constants : List V -> Bool
constants = all constant

||| Arguments worth unfolding a call for (ELIM-G-12): all known, or one a
||| known constructor, which the callee's match can then decide (GHC's
||| "interesting" constructor arguments).
interesting : List V -> Bool
interesting vs = constants vs || any isCon vs
  where
    isCon : V -> Bool
    isCon (SCon _ _) = True
    isCon _ = False

||| The values an elimination sequence applies.
applied : List (Elim Atom) -> List V
applied [] = []
applied (Apply v :: es) = v :: applied es
applied (_ :: es) = applied es

||| Does a value hold a string join point (ELIM-G-14)? Its alternatives' code
||| refers to the variables in scope where it was made, so it can only be
||| used there: a call that receives one is unfolded.
joinIn : V -> Bool
joinIn (SString s) = joinS s
  where
    joinS : SStr Atom -> Bool
    joinS (SCase {}) = True
    joinS (SAppend a b) = joinS a || joinS b
    joinS (SCons _ s) = joinS s
    joinS _ = False
joinIn (SCon _ fs) = assert_total (any joinIn fs)
joinIn (SLam _ caps _ _) = assert_total (any joinIn (toList caps))
joinIn (SDelay _ caps _) = assert_total (any joinIn (toList caps))
joinIn (SCall _ _ as es) = assert_total (any joinIn (as ++ applied es))
joinIn _ = False


------------------------------------------------------------------------------
-- Reification (Futhark's residualization, Kovács's `down`)
------------------------------------------------------------------------------

||| A value that must exist at runtime, as an atom (PROF-HEAP-1..3).
reify : Loc -> V -> M (Atom, VTy)
reify l (Dyn t a) = pure (a, t)
reify l (SString (SRun a)) = pure (a, StrT)
reify l (SString s) = case strLit s of
  Just lit => pure (ALit (LStr lit), StrT)
  -- Only literals and strings passed around exist at runtime.
  Nothing => fail ProfHeap3 l
               ("a string is built at runtime here and is not written directly by putStr, " ++
                "so it would need the heap")
reify l (SDelay {}) = fail ProfHeap2 l "a Lazy value would exist at runtime here"
reify l (SBig _) = fail ProfType4 l "an Integer would exist at runtime here (SEM-BIG-1)"
-- G2: a known constructor of runtime data is built where it must exist.
reify l v@(SCon c fs) = do
  dt <- dataDef l c.dataId
  case (dt.static, dt.cons) of
    (False, _) => do
      as <- assert_total (traverse (reify l) fs)
      x <- bind l (DataT c.dataId) (OCon c (map fst as))
      pure (x, DataT c.dataId)
    (True, [_]) => fail ProfHeap1 l ("a function or IO action would exist at runtime here (" ++
                                     showShape (shape v) ++ "); it must be applied, run or passed " ++
                                     "to a known function")
    -- Which constructor a value of static data has is chosen at runtime.
    (True, _) => do
      st <- get
      let (rule, what) = staticReason st.src c.dataId
      fail rule l ("a value of type " ++ dt.idrisName ++ " holds " ++ what ++ ", and it would " ++
                   "exist at runtime here, where which constructor it has is chosen, so it " ++
                   "would need the heap")
reify l v = fail ProfHeap1 l
              ("a function or IO action would exist at runtime here (" ++ showShape (shape v) ++
               "); it must be applied, run or passed to a known function")

||| A variable or field of a runtime type; an erased one is the value
||| `Erased`, so it only ever reaches quantity-0 positions (CORE-INV-3).
dynVar : VarId -> VTy -> V
dynVar x ErasedT = Dyn ErasedT AErased
dynVar x t = Dyn t (AVar x)

||| The literal an atom is, if it is one (ELIM-G-17).
literalAtom : Atom -> Maybe Lit
literalAtom (ALit lit) = Just lit
literalAtom _ = Nothing

||| A literal string argument is static, so that string primitives on it fold
||| (ELIM-G-6): `putStrLn "hi"` writes one literal, "hi\n".
literalStr : V -> V
literalStr (SString s) = maybe (SString s) (SString . SLit) (strLit s)
literalStr (Dyn StrT (ALit (LStr lit))) = SString (SLit lit)
literalStr v = v

||| Extends an environment with the fields of an alternative, the first field
||| innermost.
extend : (fs : List b) -> List V -> Vect n V -> Maybe (Vect (length fs + n) V)
extend [] [] env = Just env
extend (_ :: fs) (v :: vs) env = (v ::) <$> extend fs vs env
extend _ _ _ = Nothing

bindAlt : Loc -> (fs : List b) -> List V -> Vect n V -> M (Vect (length fs + n) V)
bindAlt l fs vs env =
  maybe (fail CoreCheck1 l "an alternative binds the wrong number of fields") pure (extend fs vs env)

||| The type of a match from its alternatives: absurd if none can return.
matchTy : Loc -> List (Maybe VTy) -> M VTy
matchTy l ts = case catMaybes ts of
  (t :: _) => pure t
  [] => dead l

------------------------------------------------------------------------------
-- The evaluator
------------------------------------------------------------------------------

mutual
  ||| Evaluates a term and applies eliminations to its value.
  evalK : Vect n V -> Term n -> List (Elim Atom) -> M V
  -- G1: the lambda's body is the action it describes, not prefix code.
  evalK env (Lam _ _ caps _ body) (Apply a :: es) =
    leavePrefix (evalK (a :: map (`index` env) caps) body es)
  evalK env (Lam _ lbl caps b body) [] = pure (SLam lbl (map (`index` env) caps) b body)
  evalK env (Suspend _ _ caps body) (ForceIt :: es) =                              -- G8
    leavePrefix (evalK (map (`index` env) caps) body es)
  evalK env (Suspend _ lbl caps body) [] = pure (SDelay lbl (map (`index` env) caps) body)
  -- Arguments are evaluated left to right, as written, across a curried
  -- application too: `f (g x) (h y)` computes `g x` first (SEM-EVAL-2).
  -- This is also the order LLVM's tail recursion elimination expects: in
  -- `fib (n - 1) + fib (n - 2)` it loops on the second call.
  evalK env t@(App _ _ _) es = do
    let (h, as) = spine t []
    vs <- traverse (\a => evalK env a []) as
    evalK env h (map Apply vs ++ es)
    where
      spine : Term n -> List (Term n) -> (Term n, List (Term n))
      spine (App _ f a) acc = spine f (a :: acc)
      spine f acc = (f, acc)
  evalK env (Resume _ e) es = evalK env e (ForceIt :: es)
  evalK env (Let l q v b) es = do                                                  -- G4
    v' <- if q == Q0 then pure (Dyn ErasedT AErased) else evalK env v []
    evalK (v' :: env) b es
  evalK env (Case l x alts def) es = matchCon env l (index x env) alts def es
  evalK env (CaseLit l x alts def) es = matchLit env l (index x env) alts def es
  evalK env (Unreachable l) es = dead l
  evalK env (Crash l m) es = crash l m
  evalK env e es = do
    v <- eval env e
    consume (locOf e) v es

  ||| Evaluates a term that is not an elimination context.
  eval : Vect n V -> Term n -> M V
  eval env (Var _ i) = pure (index i env)
  eval env (Literal _ lit) = pure (litVal lit)
  eval env (Erased _) = pure (Dyn ErasedT AErased)
  eval env (PrimApp l op args) = traverse (\a => evalK env a []) args >>= prim l op
  eval env (Effect l op args res) = traverse (\a => evalK env a []) args >>= io l op res
  eval env (Call l f args) = do
    vs <- traverse (\a => evalK env a []) args
    fn <- fnDef l f
    case value fn.result of
      -- An Integer is computed at compile time (SEM-BIG-1).
      -- So is a value of recursive data (SEM-REC-1), strictly, as Idris
      -- builds it: its constructors are known where it is used.
      -- A call that is passed the world and returns a static result has
      -- run: it is unfolded where it is, in order.
      Nothing => if fn.result == BigT || !(chooses l fn.result) || !(staticRun l fn.result)
                   then known fn vs [] (unfold l fn vs [])                       -- G16
                   else pure (SCall f !(gets effects) vs [])                     -- G5
      Just StrT => known fn vs [] (unfold l fn vs [])                              -- G16, G10
      Just _ => known fn vs [] $                                                    -- G16
                if fn.block || fn.inline || interesting vs || any joinIn vs          -- G11-G14
                   then unfold l fn vs []
                else call l Nothing f vs []
  eval env (ConApp l c args) = do
    vs <- traverse (\a => evalK env a []) args
    dt <- dataDef l c.dataId
    -- G2: a constructor of constants stays known until it must exist.
    if dt.static || constants vs
       then pure (SCon c vs)
       else do
         as <- traverse (reify l) vs
         Dyn (DataT c.dataId) <$> bind l (DataT c.dataId) (OCon c (map fst as))
  eval env e = evalK env e []

  ||| A literal match: selected at compile time on a literal, otherwise
  ||| residual, each alternative in its own block.
  matchLit : Vect n V -> Loc -> V -> List (Lit, Term n) -> Term n -> List (Elim Atom) -> M V
  matchLit env l (Dyn _ (ALit lit)) alts def es =
    evalK env (maybe def snd (find ((== lit) . fst) alts)) es
  matchLit env l (SBig n) alts def es =
    evalK env (maybe def snd (find ((== LBig n) . fst) alts)) es
  -- PROF-PRIM-4: a match on a string is decided at compile time.
  matchLit env l (SString s) alts def es = case strLit s of
    Just str => evalK env (maybe def snd (find ((== LStr str) . fst) alts)) es
    -- G15: a string that is known not to be empty is not "".
    Nothing => if all ((== LStr "") . fst) alts && nonEmpty s
                  then evalK env def es
                  else fail ProfPrim4 l "a match on a string built at runtime"
  matchLit env l scrut alts def es = do
    when (any (isStr . fst) alts) $ fail ProfPrim4 l "a match on a string at runtime"
    (x, _) <- reify l scrut
    alts' <- traverse (\(k, e) => (k,) <$> branch env e es) alts
    def' <- branch env def es
    t <- matchTy l (map (fst . snd) alts' ++ [fst def'])
    Dyn t <$> bind l t (OCaseLit x (map (\(k, (_, c)) => (k, c)) alts') (snd def'))

  ||| One alternative of a residual match, in its own block; its value must
  ||| exist at runtime.
  branch : Vect n V -> Term n -> List (Elim Atom) -> M (Maybe VTy, Code)
  branch env e es = block (locOf e) (evalK env e es >>= reify (locOf e))

  ||| A constructor match.
  matchCon : Vect n V -> Loc -> V -> List (Alt n) -> Maybe (Term n) -> List (Elim Atom) -> M V
  -- G2: a known constructor selects its alternative.
  matchCon env l (SCon c fs) alts def es = case find (\(MkAlt k _ _) => k == c) alts of
    Just (MkAlt _ bs body) => do
      env' <- bindAlt l bs fs env
      evalK env' body es
    Nothing => maybe (fail CoreCheck1 l "no alternative for a known constructor") (\d => evalK env d es) def
  -- A static value of single-constructor data: its fields are projections (G5).
  matchCon env l (SCall f e as ms) alts def es = do
    fn <- fnDef l f
    t <- elimTy l fn.result ms
    Just d <- pure (dataOf t)
      | Nothing => fail ProfHeap1 l "a match on a static value that is not data"
    dt <- dataDef l d
    case dt.cons of
      -- A result that carries the world (an `IORes` of a function) is one
      -- run of the action: it is evaluated once, not once per field.
      [con] => if any ((== V WorldT) . (.type)) con.fields && count (== f) !(gets unfolding) == 0
        then do
          v <- once (the Nat 64) fn as ms
          case v of
            SCon _ _ => matchCon env l v alts def es
            _ => fail ProfHeap1 l ("an IO action whose result holds a function would run more " ++
                                   "than once here (" ++ showShape (shape v) ++ ")")
        else case find (\(MkAlt k _ _) => k == con.id) alts of
        Just (MkAlt _ bs body) => do
          -- A field of a value type is read here, where the value is first
          -- used; a static field stays a projection. An erased field is
          -- the erased value.
          fields <- for (zip [0 .. length con.fields] con.fields) $ \(i, fd) =>
            if fd.quantity == Q0 then pure (Dyn ErasedT AErased)
            else consume l (SCall f e as ms) [Proj con.id i]
          env' <- bindAlt l bs (take (length bs) fields) env
          evalK env' body es
        Nothing => maybe (fail CoreCheck1 l "no alternative") (\e => evalK env e es) def
      -- G16: a known value built by a call is evaluated to its constructor;
      -- otherwise the call is unfolded here, where its constructor is
      -- needed (a list whose elements are computed at runtime).
      _ => do
        v <- force (the Nat 1000) fn as ms
        case v of
          SCon _ _ => matchCon env l v alts def es
          _ => do
            st <- get
            let (rule, what) = staticReason st.src d
            fail rule l
                 ("a value of type " ++ dt.idrisName ++ " holds " ++ what ++ ", and which " ++
                  "constructor it has would be chosen at runtime, so it would need the heap")
    where
      -- An action's run, unfolded until it is a constructor; a function
      -- already being unfolded is not entered again.
      once : Nat -> TFn -> List V -> List (Elim Atom) -> M V
      once Z fn as ms = pure (SCall fn.id e as ms)
      once (S k) fn as ms = do
        v <- leavePrefix (unfold l fn as ms)
        case v of
          SCall g e' as' ms' => if count (== g) !(gets unfolding) > 0 then pure v else do
            gn <- fnDef l g
            once k gn as' ms'
          _ => pure v
      -- The deferred call is evaluated until it is a constructor: a method
      -- may unfold to a call of its implementation.
      force : Nat -> TFn -> List V -> List (Elim Atom) -> M V
      force Z fn as ms = pure (SCall fn.id e as ms)
      force (S k) fn as ms = do
        v <- knownData fn as ms (leavePrefix (unfold l fn as ms))
        case v of
          SCall g e' as' ms' => do
            gn <- fnDef l g
            force k gn as' ms'
          _ => pure v
  -- A runtime match: residual, with fresh binders in each alternative, since
  -- one alternative may be residualized more than once (CORE-INV-1).
  matchCon env l (Dyn (DataT d) x@(AVar _)) alts def es = do
    alts' <- for alts $ \(MkAlt c bs body) => do
      con <- conDef l c
      tys <- traverse (\f => runtimeTy l f.type) con.fields
      ys <- traverse (const freshVar) tys
      env' <- bindAlt l bs (zipWith dynVar ys tys) env
      r <- blockV (locOf body) (evalK env' body es)
      pure (c, ys, locOf body, r)
    def' <- traverse (\e => (locOf e,) <$> blockV (locOf e) (evalK env e es)) def
    let results = mapMaybe (\(_, _, _, r) => value r) alts' ++ maybe [] (toList . value . snd) def'
    -- A single constructor is not a choice: when its alternative yields a
    -- static value (an `IORes` of a function), its fields are read and the
    -- value is used where the match is, not returned from a residual match.
    dt <- dataDef l d
    case (alts', def', dt.cons) of
      ([(c, ys, _, Right (p, v))], Nothing, [con]) =>
        if reifiable v then joinOrResidual alts' def' results else do
          tys <- traverse (\f => runtimeTy l f.type) con.fields
          for_ (zip [0 .. length ys] (zip ys tys)) $ \(i, y, t) =>
            modify { lets $= (:< MkStmt l y (defaultQuantity t) t (OField x c i)) }
          replay p
          pure v
      _ => joinOrResidual alts' def' results
    where
      reifiable : V -> Bool
      reifiable (Dyn _ _) = True
      reifiable (SString _) = True
      reifiable _ = False
      residual : Loc -> Either Code (Prefix, V) -> M (Maybe VTy, Code)
      residual bl (Left code) = pure (Nothing, code)
      residual bl (Right (p, v)) = block bl (replay p *> reify bl v)
      arm : Either Code (Prefix, V) -> Arm Atom
      arm (Left code) = Stops code
      arm (Right (p, v)) = maybe (Stops (Absurd l)) (Returns p) (asStr v)
      value : Either Code (Prefix, V) -> Maybe V
      value (Right (_, v)) = Just v
      value (Left _) = Nothing
      isString : V -> Bool
      isString v = isJust (asStr v)
      needsJoin : V -> Bool
      needsJoin (SString (SRun _)) = False
      needsJoin (SString s) = isNothing (strLit s)
      needsJoin _ = False
      -- G14: alternatives that build strings make a string join point.
      joinOrResidual : List (ConId, List VarId, Loc, Either Code (Prefix, V)) ->
                       Maybe (Loc, Either Code (Prefix, V)) -> List V -> M V
      joinOrResidual alts' def' results =
        if any needsJoin results && all isString results
          then pure (SString (SCase (DataT d) x (map (\(c, ys, _, r) => MkJoin c ys (arm r)) alts')
                                                 (map (arm . snd) def')))
          else do
            branches <- for alts' $ \(c, ys, bl, r) => map (MkBranch c ys) <$> residual bl r
            defs <- traverse (\(bl, r) => residual bl r) def'
            t <- matchTy l (map fst branches ++ maybe [] (pure . fst) defs)
            Dyn t <$> bind l t (OCase x (map snd branches) (map snd defs))
  matchCon env l v alts def es = fail ProfHeap1 l ("a match on " ++ showShape (shape v))

  ||| Applies eliminations to a value.
  consume : Loc -> V -> List (Elim Atom) -> M V
  consume l v [] = pure v
  consume l (SLam _ caps _ body) (Apply a :: es) = leavePrefix (evalK (a :: caps) body es)
  consume l (SDelay _ caps body) (ForceIt :: es) = leavePrefix (evalK caps body es)
  consume l (SCon c fs) (Proj _ i :: es) =
    maybe (fail CoreCheck1 l "a projection of a missing field") (\f => consume l f es) (getAt i fs)
  consume l (SCall f e as ms) es = do
    fn <- fnDef l f
    t <- elimTy l fn.result (ms ++ es)
    now <- gets effects
    case value t of
      -- An Integer is computed at compile time (SEM-BIG-1).
      Nothing => if t == BigT || !(chooses l t) || !(staticRun l t)
                   then leavePrefix (unfold l fn as (ms ++ es))
                 else pure (SCall f e as (ms ++ es))
      -- Running the deferred call is the action, not prefix code; the
      -- callee's own prefix is recorded where it is specialized. G10 and
      -- G11 unfold it instead when no effect separates building the call
      -- from running it.
      Just r => (if e == now then known fn as (ms ++ es) else id) $               -- G16
                if (r == StrT || fn.block || fn.inline || interesting (as ++ applied (ms ++ es))
                    || any joinIn (as ++ applied (ms ++ es))) && e == now
                   then leavePrefix (unfold l fn as (ms ++ es))
                   else leavePrefix (call l (Just e) f as (ms ++ es))
  consume l v es = fail ProfHeap1 l ("cannot apply or project " ++ showShape (shape v))

  ||| G10: a function that returns a String is evaluated where it is called,
  ||| so that the string it builds can still be folded or fused into output.
  ||| G11: so is an Idris case or with block, which is part of its parent's
  ||| body; the parent is then the only function on a recursive cycle.
  ||| A call of a function that is already being unfolded is specialized.
  unfold : Loc -> TFn -> List V -> List (Elim Atom) -> M V
  unfold l fn vs es = atSite l $ do
    st <- get
    case st.fuel of
      Just Z => abandon
      Just (S k) => do
        Just env <- pure (toVect fn.arity vs)
          | Nothing => fail CoreCheck1 l ("a call of " ++ show fn.id ++ " with the wrong arity")
        put ({ fuel := Just k } st)
        evalK env fn.body es
      Nothing => unfoldOnce l fn vs es

  ||| G16: a call whose arguments are all known is evaluated at compile time,
  ||| recursion included, when it finishes within a bound and leaves no code
  ||| behind: its value is then known. Otherwise it is unfolded or
  ||| specialized as usual.
  known : TFn -> List V -> List (Elim Atom) -> M V -> M V
  known fn vs es otherwise =
    if not (constants (vs ++ applied es)) then otherwise
    else if isJust !(gets fuel) then unfold fn.loc fn vs es
    else maybe otherwise pure !(evaluate 20000 constant (unfold fn.loc fn vs es))

  ||| Is a type data whose constructor is a choice? A value of a single
  ||| constructor type (an IO action) is used through its fields instead.
  chooses : Loc -> Ty -> M Bool
  chooses l t = case dataOf t of
    Just d => (\dt => length dt.cons > 1) <$> dataDef l d
    Nothing => pure False

  ||| Is one of the values a known constructor of recursive data?
  recursiveArg : Loc -> List V -> M Bool
  recursiveArg l [] = pure False
  recursiveArg l (SCon c _ :: vs) = do
    dt <- dataDef l c.dataId
    if dt.static && length dt.cons > 1 then pure True else recursiveArg l vs
  recursiveArg l (_ :: vs) = recursiveArg l vs

  ||| Is a type the result of running an action whose value is static (an
  ||| `IORes` of a function, as `(*>)` for IO makes)? Such a result cannot
  ||| cross a specialization, so its function is re-entered a bounded number
  ||| of times, as for a string join point (ELIM-G-14).
  staticRun : Loc -> Ty -> M Bool
  staticRun l t = case dataOf t of
    Just d => do
      dt <- dataDef l d
      pure (dt.static && any (any ((== V WorldT) . (.type)) . (.fields)) dt.cons)
    Nothing => pure False

  ||| G16 for a call whose result has no runtime representation: kept only
  ||| when it evaluates to a known constructor (a `Nat` built from a literal).
  knownData : TFn -> List V -> List (Elim Atom) -> M V -> M V
  knownData fn vs es otherwise =
    if not (constants (vs ++ applied es)) then otherwise
    else if isJust !(gets fuel) then unfold fn.loc fn vs es
    else maybe otherwise pure !(evaluate 20000 conValue (unfold fn.loc fn vs es))
    where
      conValue : V -> Bool
      conValue v@(SCon _ _) = constant v
      conValue _ = False

  unfoldOnce : Loc -> TFn -> List V -> List (Elim Atom) -> M V
  unfoldOnce l fn vs es = do
    st <- get
    -- An Integer or a value of recursive data is built at compile time,
    -- recursion included, up to a bound (SEM-BIG-1, SEM-REC-1); anything
    -- else unfolds once.
    -- A string join point cannot cross a specialization (ELIM-G-14), so a
    -- call that carries one may re-enter a function a bounded number of times.
    t <- elimTy l fn.result es
    isData <- chooses l t
    carries <- staticRun l t
    -- Recursion on a value of recursive data (a list being shown) follows
    -- it, and ends where it ends (SEM-REC-2).
    structural <- recursiveArg l (vs ++ applied es)
    let bound = the Nat (if t == BigT || isData || structural then 10000
                         else if any joinIn (vs ++ applied es) || carries then 64 else 1)
    if count (== fn.id) st.unfolding >= bound then call l Nothing fn.id vs es else do
      Just env <- pure (toVect fn.arity vs)
        | Nothing => fail CoreCheck1 l ("a call of " ++ show fn.id ++ " with the wrong arity")
      put ({ unfolding $= (fn.id ::) } st)
      v <- evalK env fn.body es
      modify { unfolding $= drop 1 }
      pure v

  ||| A call of `f` with arguments and eliminations: a call of the
  ||| specialization for their shapes (G3, G5). A deferred call knows how
  ||| many effects had happened when its action was built.
  call : Loc -> Maybe Nat -> FnId -> List V -> List (Elim Atom) -> M V
  call l built f args0 es = atSite l $ do
    when (isJust !(gets fuel)) abandon
    fn <- fnDef l f
    let args = map literalStr args0
    when (any joinIn (args ++ applied es)) $
      fail ProfHeap3 l ("a string built in a runtime branch is passed to " ++ fn.idrisName ++
                        ", which calls itself, so it would need the heap (ELIM-G-14)")
    t <- elimTy l fn.result es >>= runtimeTy l
    let generic = MkKey f (map shape args) (shapeElims es) []
    let lits = map (literalAtom . snd) (atoms args es)
    -- ELIM-G-17: a specialization that cannot be built for any value of
    -- its atoms is built for the literals among them, if there are any.
    (name, isLiteral) <- if all isNothing lits then (, False) <$> specialize l fn generic args es t else do
      Right name <- attempt (specialize l fn generic args es t)
        | Left _ => (, True) <$> specialize l fn ({ lits := lits } generic) args es t
      pure (name, False)
    now <- gets effects
    when (not (null es)) $
      modify { runs $= (:< (name, l, maybe False (< now) built)) }
    let as = the (List (VTy, Atom)) (if isLiteral then filter (isNothing . literalAtom . snd) (atoms args es)
                                     else atoms args es)
    when (any ((== WorldT) . fst) as) effect
    Dyn t <$> bind l t (OCall name (map snd as))

  ||| The specialization of a function for a key, made on first use.
  specialize : Loc -> TFn -> Key -> List V -> List (Elim Atom) -> VTy -> M FnId
  specialize l fn key args es t = do
    st <- get
    case lookup key st.memo of
      Just name => pure name
      Nothing => do
        -- PROF-HEAP-4: while `f` is specialized, `f` is needed again with
        -- static arguments (functions, actions, Lazy values) that embed the
        -- ones it received and differ from them. They grow with each
        -- recursive call, so specialization would not terminate. The count
        -- and size limits are a backstop.
        when (any (\k => k.fn == key.fn && k /= key && grows k key) st.stack) $
          fail ProfHeap4 l
               (fn.idrisName ++ " passes itself a function, IO action or Lazy value that " ++
                "grows with each call, so it cannot be specialized away")
        let n = fromMaybe 0 (lookup fn.id st.made)
        when (n >= 256 || sum (map size key.args) > 4096) $
          fail ProfHeap4 l
               ("specializing " ++ fn.idrisName ++ " does not terminate: a recursive function " ++
                "passes itself a different function or IO action on each call")
        let name = if trivial key then fn.id else MkFnId (fn.id.name ++ "#" ++ show (S n))
        put ({ memo $= insert key name, made $= insert fn.id (S n), stack $= (key ::) } st)
        -- Parameters: the atoms of the arguments and eliminations, but for
        -- the literals a literal key fixes (ELIM-G-17).
        let all = the (List (VTy, Atom)) (atoms args es)
        let fixed = the (List (Maybe Lit)) (if null key.lits then map (const Nothing) all else key.lits)
        let free = the (List ((VTy, Atom), Maybe Lit)) (filter (\(_, f) => isNothing f) (zip all fixed))
        let types = map (\((t, _), _) => t) free
        params <- traverse (const freshVar) types
        let (args', es') = refill (supply (zipWith dynAtom params types) (zip all fixed)) AErased args es
        Just env <- pure (toVect fn.arity args')
          | Nothing => fail CoreCheck1 l ("a call of " ++ show fn.id ++ " with the wrong arity")
        -- G5: the body before the eliminations apply runs where the action
        -- is used.
        -- Effects are counted within one function's code.
        outer <- gets effects
        (_, body) <- withPrefix (if null es then Nothing else Just name) $
                       block fn.loc (evalK env fn.body es' >>= reify fn.loc)
        modify { effects := outer }
        modify { stack $= drop 1 }
        -- CORE-INV-4: a runtime argument keeps the quantity of its
        -- parameter; the atoms of a static value are unrestricted.
        let qs0 = concat (zipWith quantities (toList fn.params) args) ++
                  map (defaultQuantity . fst) (atoms [] es)
        let qs = the (List Quantity) (map (\(q, _) => q) (filter (\(_, f) => isNothing f) (zip qs0 fixed)))
        let spec = if trivial key then Nothing else Just ("specialization of " ++ showKey key)
        modify { done $= (:< MkCFn name fn.idrisName (zipWith3 MkParam params qs types)
                                   t body fn.loc fn.terminating spec) }
        pure name
    where
      dynAtom : VarId -> VTy -> Atom
      dynAtom x ErasedT = AErased
      dynAtom x _ = AVar x
      -- The atoms in order: a fixed literal, or the next parameter.
      supply : List Atom -> List ((VTy, Atom), Maybe Lit) -> List Atom
      supply ps [] = []
      supply ps ((_, Just lit) :: rest) = ALit lit :: supply ps rest
      supply (p :: ps) ((_, Nothing) :: rest) = p :: supply ps rest
      supply [] ((_, Nothing) :: rest) = AErased :: supply [] rest
      grows : Key -> Key -> Bool
      applied : Elim () -> Maybe (SVal ())
      applied (Apply v) = Just v
      applied _ = Nothing
      grows old new = pairs old.args new.args &&
                      pairs (mapMaybe applied old.elims) (mapMaybe applied new.elims) &&
                      length old.elims == length new.elims
      quantities : Binder -> V -> List Quantity
      quantities b (Dyn ErasedT _) = [Q0]
      quantities b (Dyn _ _) = [b.quantity]
      quantities b v = map (defaultQuantity . fst) (atoms [v] [])

  ||| Primitives: compile-time evaluation (G6) and deferred strings (G7).
  prim : Loc -> PrimOp -> List V -> M V
  prim l op vs = case (op, vs, map asStr vs) of
    (Str Append, _, [Just s, Just t]) => pure (SString (SAppend s t))
    (Str Cons, [c, _], [_, Just t]) => (\(a, _) => SString (SCons a t)) <$> reify l c
    (Str (ToStr SChar), [c], _) => (\(a, _) => SString (SChr a)) <$> reify l c
    (Str (ToStr (SInt t)), [n], _) => (\(a, _) => SString (SShow (IntT t) a)) <$> reify l n
    (Str (ToStr SDouble), [n], _) => (\(a, _) => SString (SShow DoubleT a)) <$> reify l n
    -- G15: the first character of a string whose first piece is known.
    (Str Head, [_], [Just s]) => case strLit s of
      Just _ => general l op vs
      Nothing => maybe (general l op vs) (map (Dyn CharT)) (headOf s)
    (Big b, _, _) => big b
    _ => general l op vs
    where
      known : V -> Maybe Lit
      known (SBig n) = Just (LBig n)
      known (Dyn _ (ALit x)) = Just x
      known v = LStr <$> (asStr v >>= strLit)
      -- SEM-BIG-1: every Integer operation is evaluated here.
      big : BigOp -> M V
      big b = case the (Maybe (List Lit)) (traverse known vs) of
        Just lits => maybe (fail ProfType4 l ("the Integer operation " ++ show b ++ " has no " ++
                                               "value at compile time here (SEM-BIG-1)"))
                           (pure . litVal) (foldBig b lits)
        Nothing => fail ProfType4 l ("an Integer computed from a runtime value (" ++ show b ++
                                     "), which would exist at runtime (SEM-BIG-1)")

  ||| The first character of a static string, when its first piece gives it
  ||| (ELIM-G-15): a literal or runtime character, or the sign or leading
  ||| digit of an integer shown at runtime.
  headOf : SStr Atom -> Maybe (M Atom)
  headOf (SLit s) = case unpack s of
    (c :: _) => Just (pure (ALit (LChar (cast (ord c)))))
    [] => Nothing
  headOf (SCons c _) = Just (pure c)
  headOf (SChr c) = Just (pure c)
  headOf (SShow (IntT t) a) = Just (leadingChar t a)
  headOf (SShow DoubleT a) = Just (bind noLoc CharT (OPrim DoubleHead [a]))
  headOf (SAppend (SLit "") b) = headOf b
  headOf (SAppend a _) = headOf a
  headOf _ = Nothing

  ||| `-` for a negative number, else its leading decimal digit, found by
  ||| comparing with the powers of ten that fit the type.
  leadingChar : IntTy -> Atom -> M Atom
  leadingChar t a = do
    let loc = noLoc
    let lit = \n => ALit (LInt t n)
    digit <- if signed t
      then do
        neg <- bind loc (IntT IdrisInt) (OPrim (Compare CLt (SInt t)) [a, lit 0])
        (_, minus) <- block loc (pure (ALit (LChar 45), CharT))
        (_, plus) <- block loc (digitChar (powers t))
        bind loc CharT (OCaseLit neg [(LInt IdrisInt 1, minus)] plus)
      else fst <$> digitChar (powers t)
    pure digit
    where
      raise : Integer -> Nat -> Integer
      raise b Z = 1
      raise b (S k) = b * raise b k
      powers : IntTy -> List Integer
      powers t = reverse (takeWhile (<= maxOf) [raise 10 k | k <- [1 .. 19]])
        where
          maxOf : Integer
          maxOf = if signed t then raise 2 (minus (width t) 1) - 1 else raise 2 (width t) - 1
      -- The digit is a divided by the largest power of ten not above it.
      digitChar : List Integer -> M (Atom, VTy)
      digitChar [] = do
        c <- bind noLoc (IntT t) (OPrim (IntOp Add t) [a, ALit (LInt t 48)])
        ch <- bind noLoc CharT (OPrim (Cast (SInt t) SChar) [c])
        pure (ch, CharT)
      digitChar (p :: ps) = do
        ge <- bind noLoc (IntT IdrisInt) (OPrim (Compare CGte (SInt t)) [a, ALit (LInt t p)])
        (_, big) <- block noLoc $ do
          d <- bind noLoc (IntT t) (OPrim (IntOp Div t) [a, ALit (LInt t p)])
          c <- bind noLoc (IntT t) (OPrim (IntOp Add t) [d, ALit (LInt t 48)])
          ch <- bind noLoc CharT (OPrim (Cast (SInt t) SChar) [c])
          pure (ch, CharT)
        (_, small) <- block noLoc (digitChar ps)
        ch <- bind noLoc CharT (OCaseLit ge [(LInt IdrisInt 1, big)] small)
        pure (ch, CharT)

  general : Loc -> PrimOp -> List V -> M V
  general l op vs = do
    as <- traverse (reify l) vs
    case (traverse literal (map fst as), op) of
      (Just lits, Run p) => maybe (residual p as) (pure . lit) (foldPrim p lits)
      (Just lits, Str s) => maybe (runtimeString s) (pure . lit) (foldStr s lits)
      (Nothing, Run p) => residual p as
      (Nothing, Str s) => runtimeString s
      (_, Big b) => fail CoreCheck1 l ("the Integer operation " ++ show b ++ " reached runtime")
    where
      literal : Atom -> Maybe Lit
      literal (ALit x) = Just x
      literal _ = Nothing
      lit : Lit -> V
      lit = litVal
      residual : Prim -> List (Atom, VTy) -> M V
      residual p as = Dyn (primResult p) <$> bind l (primResult p) (OPrim p (map fst as))
      runtimeString : StrOp -> M V
      runtimeString s = fail ProfPrim4 l ("the string operation " ++ show s ++ " is not supported at runtime")

  ||| IO primitives, with output fusion for putStr (G7).
  io : Loc -> IOOp -> DataId -> List V -> M V
  io l PutStr res [s, w] = case asStr s of
    Just str => do
      (w', _) <- reify l w
      putStr l res str w'
    Nothing => fail CoreCheck1 l "putStr of a value that is not a string"
  io l op res vs = do
    as <- traverse (reify l) vs
    effect
    Dyn (DataT res) <$> bind l (DataT res) (OIO op (map fst as) res)

  ||| Writes a static string: literal and runtime pieces in order, threading
  ||| the world (G7). Returns the last `IORes` value.
  putStr : Loc -> DataId -> SStr Atom -> Atom -> M V
  putStr l res s w = case (strLit s, s) of
    (Just lit, _) => write PutStr (ALit (LStr lit))
    (_, SRun a) => write PutStr a
    (_, SChr c) => write PutChar c
    (_, SShow (IntT t) n) => write (PutInt t) n
    (_, SShow _ n) => write PutDouble n
    (_, SCons c rest) => do
      r <- write PutChar c
      putStr l res rest !(nextWorld r)
    (_, SAppend a b) => do
      r <- putStr l res a w
      putStr l res b !(nextWorld r)
    (_, SLit lit) => write PutStr (ALit (LStr lit))
    -- G14: the match, with the rest of the output in each alternative.
    (_, SCase t x js d) => do
      branches <- for js $ \(MkJoin c ys a) => map (MkBranch c ys) <$> writeArm a
      defs <- traverse writeArm d
      rt <- matchTy l (map fst branches ++ maybe [] (pure . fst) defs)
      Dyn rt <$> bind l rt (OCase x (map snd branches) (map snd defs))
    where
      write : IOOp -> Atom -> M V
      write op a = effect *> (Dyn (DataT res) <$> bind l (DataT res) (OIO op [a, w] res))
      writeArm : Arm Atom -> M (Maybe VTy, Code)
      writeArm (Stops code) = pure (Nothing, code)
      writeArm (Returns p s) = block l (replay p *> (assert_total (putStr l res s w) >>= reify l))
      ||| The world inside an `IORes` value.
      nextWorld : V -> M Atom
      nextWorld (Dyn _ r) = do
        dt <- dataDef l res
        [mk] <- pure dt.cons
          | _ => fail CoreCheck1 l (show res ++ " is not an IO result")
        bind l WorldT (OField r mk.id 1)
      nextWorld _ = fail CoreCheck1 l "an IO result that is not a runtime value"

------------------------------------------------------------------------------
-- Entry
------------------------------------------------------------------------------

||| A data instance of full Core at runtime.
runtimeData : Data -> Maybe CData
runtimeData d = do
  cons <- traverse (\c => (\fs => MkCCon c.id c.tag fs c.loc) <$>
                            traverse (\f => MkCField f.quantity <$> value f.type) c.fields) d.cons
  pure (MkCData d.id d.idrisName cons d.loc)

||| The data instances a program uses: those its code and signatures
||| mention, and those their fields contain.
usedDatas : SortedMap DataId Data -> List CFn -> SortedSet DataId
usedDatas datas fns = close (length (keys datas)) (fromList (concatMap mentioned fns))
  where
    ty : VTy -> List DataId
    ty (DataT d) = [d]
    ty _ = []
    mentioned : CFn -> List DataId
    mentioned f = ty f.result ++ concatMap (ty . (.type)) f.params ++ datasOf f.body
    fieldsOf : DataId -> List DataId
    fieldsOf d = maybe [] (\dt => mapMaybe (dataOf . (.type)) (concatMap (.fields) dt.cons)) (lookup d datas)
    close : Nat -> SortedSet DataId -> SortedSet DataId
    close Z s = s
    close (S k) s = let s' = union s (fromList (concatMap fieldsOf (Prelude.toList s))) in
                    if length (Prelude.toList s') == length (Prelude.toList s) then s else close k s'

||| Runs the guaranteed eliminations from the root (CORE-PASS-1).
export
simplify : Source -> Either Diag Target
simplify src = do
  let ix = MkSourceIndex (fromList [(f.id, f) | f <- src.fns])
                         (fromList [(d.id, d) | d <- src.datas])
                         (fromList [(c.id, c) | d <- src.datas, c <- d.cons])
  let Just root = lookup src.root ix.fns
    | Nothing => Left (MkDiag CoreCheck1 "Simplify" noLoc "the root is missing")
  let run = do
        ps <- for (toList root.params) $ \b => do
          t <- runtimeTy root.loc b.type
          x <- freshVar
          pure (dynVar x t)
        call root.loc Nothing root.id ps []
  case runStateT (initial ix) run of
    Left (Fail d) => Left d
    Left (Dead l) => Left (MkDiag CoreCheck1 "Simplify" l "the root cannot return")
    Left (Crashed l _) => Left (MkDiag CoreCheck1 "Simplify" l "a crash outside any function")
    Left Abandoned => Left (MkDiag CoreCheck1 "Simplify" noLoc "a compile-time evaluation escaped")
    Right (st, _) => do
      let fns = st.done <>> []
      checkMoved fns (st.moved <>> []) (st.runs <>> [])
      let used = usedDatas ix.datas fns
      let Just datas = traverse runtimeData [d | d <- src.datas, contains d.id used]
        | Nothing => Left (MkDiag CoreCheck1 "Simplify" noLoc "static data at runtime")
      pure (MkTarget datas (filter ((== src.root) . (.id)) fns ++ filter ((/= src.root) . (.id)) fns)
                     src.root src.entry)
