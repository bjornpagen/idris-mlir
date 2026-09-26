||| The guaranteed eliminations (docs/architecture/06-elimination.md, ELIM-G-*).
|||
||| An online specializer over full Core. Values whose type is not first order
||| (functions, `Lazy`, data holding them such as `IO`) are *static*: they exist
||| only at compile time as `SVal`s. Every use of a static value is resolved
||| here, by beta reduction (G1), known-constructor selection (G2),
||| specialization on static arguments (G3), static lets (G4), arity raising
||| (G5, calls whose result is static are specialized together with the
||| eliminations applied to them), compile-time primitives (G6), output fusion
||| (G7) and Force of Delay (G8). Residual code is first order, in A-normal
||| form, and keeps the evaluation order of the input (SEM-EVAL-*).
module IdrisMLIR.Simplify

import IdrisMLIR.Core

import Control.Monad.State
import Data.List
import Data.Maybe
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.String

%default covering

------------------------------------------------------------------------------
-- Static values
------------------------------------------------------------------------------

||| A string known at compile time up to runtime characters and numbers.
data SStr = SLit String | SVarStr Expr | SAppend SStr SStr | SConsChar Expr SStr
          | SShowInt IntTy Expr | SChar Expr

mutual
  data SVal : Type where
    ||| A first-order runtime value: an atom (variable, literal or erased).
    Dyn : Expr -> Ty -> SVal
    SLam : Env -> Var -> Quantity -> Ty -> Expr -> SVal
    SDelay : Env -> Expr -> SVal
    SCon : String -> String -> List SVal -> SVal
    ||| A deferred call of a function whose result is static, with the
    ||| eliminations applied to it so far (G5).
    SCall : String -> List SVal -> List Elim -> SVal
    SString : SStr -> SVal

  data Elim = EApply SVal | EProj String Nat | EForceIt

  Env : Type
  Env = List (Var, SVal)

------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------

data Binding = BLet Var Quantity Ty Expr
             | BUnpack Var String (List Var)   -- scrutinee, constructor, fields

record St where
  constructor MkSt
  prog : Program
  next : Nat
  scopes : List (SnocList Binding)
  memo : SortedMap String String
  counts : SortedMap String Nat
  done : SnocList Fn
  staticData : SortedSet String
  safe : SortedSet String      -- functions and specializations that cannot crash or loop
  active : SortedSet String    -- specializations being built
  pending : SortedMap String (List String)  -- safe if these callees are (recursion)
  assumed : SortedSet String   -- specializations relied on as safe before that was known
  inPrefix : Maybe Loc          -- inside the prefix of a raised function (G5)

M : Type -> Type
M = StateT St (Either Diag)

fail : String -> Loc -> String -> M a
fail rule l msg = lift (Left (diag rule "Simplify" l msg))

freshVar : M Var
freshVar = do
  st <- get
  put ({ next $= S } st)
  pure st.next

||| Emits a residual binding in the current scope. In the prefix of a raised
||| function, only code that cannot crash or loop may run (PROF-HEAP-5).
emit : Binding -> M ()
emit b = do
  st <- get
  case (st.inPrefix, b) of
    (Just at, BLet _ _ _ e) => do
      let (ok, relied) = safeExpr st e
      unless ok $
        fail "PROF-HEAP-5" (locOf e)
             ("arity raising is blocked: this computation may crash or not terminate, " ++
              "and would move from where an IO action or function is built to where it runs")
      modify { assumed $= union (fromList relied) }
    _ => pure ()
  st <- get
  case st.scopes of
    (s :: ss) => put ({ scopes := (s :< b) :: ss } st)
    [] => put ({ scopes := [[<b]] } st)
  where
    ||| Branches of matches were checked as they were emitted.
    safeExpr : St -> Expr -> (Bool, List String)
    safeExpr st (EPrim _ (Div _) [_, ELit _ (LInt _ n)]) = (n /= 0, [])
    safeExpr st (EPrim _ (Mod _) [_, ELit _ (LInt _ n)]) = (n /= 0, [])
    safeExpr st (EPrim _ (Div _) _) = (False, [])
    safeExpr st (EPrim _ (Mod _) _) = (False, [])
    safeExpr st (ECall _ f _) =
      if contains f st.safe then (True, [])
      else if contains f st.active || isJust (lookup f st.pending) then (True, [f])
      else (False, [])
    safeExpr st (EIO {}) = (False, [])
    safeExpr st _ = (True, [])

||| Runs `act` in a fresh scope and wraps its bindings around the result.
scoped : M Expr -> M Expr
scoped act = do
  modify { scopes $= ([<] ::) }
  e <- act
  st <- get
  case st.scopes of
    (s :: ss) => do
      put ({ scopes := ss } st)
      pure (wrap (s <>> []) e)
    [] => pure e
  where
    wrap : List Binding -> Expr -> Expr
    wrap [] e = e
    wrap (BLet x q t v :: bs) e = ELet (locOf v) x q t v (wrap bs e)
    wrap (BUnpack x c xs :: bs) e = EMatchCon (locOf e) x [MkConAlt c xs (wrap bs e)] Nothing

||| Like `scoped`, for an atom with its type.
scopedTyped : M (Expr, Ty) -> M (Expr, Ty)
scopedTyped act = do
  tyCell <- pure ()
  modify { scopes $= ([<] ::) }
  (e, t) <- act
  st <- get
  case st.scopes of
    (s :: ss) => do
      put ({ scopes := ss } st)
      pure (wrapAll (s <>> []) e, t)
    [] => pure (e, t)
  where
    wrapAll : List Binding -> Expr -> Expr
    wrapAll [] e = e
    wrapAll (BLet x q ty v :: bs) e = ELet (locOf v) x q ty v (wrapAll bs e)
    wrapAll (BUnpack x c xs :: bs) e = EMatchCon (locOf e) x [MkConAlt c xs (wrapAll bs e)] Nothing

||| A variable of a runtime type; an erased one is the value `Erased`, so it
||| only ever reaches quantity-0 positions as `Erased` (CORE-INV-3).
dynVar : Loc -> Var -> Ty -> SVal
dynVar l x ErasedT = Dyn (EErased l) ErasedT
dynVar l x t = Dyn (EVar l x) t

bindDyn : Loc -> Ty -> Expr -> M SVal
bindDyn l t e = do
  x <- freshVar
  emit (BLet x QW t e)
  pure (Dyn (EVar l x) t)

------------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------------

isStaticTy : St -> Ty -> Bool
isStaticTy st (FunT {}) = True
isStaticTy st (LazyT _) = True
isStaticTy st (DataT d) = contains d st.staticData
isStaticTy st _ = False

||| Data instances that hold static values, directly or through other data.
staticDatas : Program -> SortedSet String
staticDatas prog = go (fromList [d.name | d <- prog.datas, any (direct . (.type)) (fields d)])
  where
    fields : Data -> List Field
    fields d = concatMap (.fields) d.cons
    direct : Ty -> Bool
    direct (FunT {}) = True
    direct (LazyT _) = True
    direct _ = False
    go : SortedSet String -> SortedSet String
    go s = let s' = foldl (\acc, d => if any (holds acc . (.type)) (fields d) then insert d.name acc else acc) s prog.datas
           in if Prelude.toList s' == Prelude.toList s then s else go s'
      where
        holds : SortedSet String -> Ty -> Bool
        holds acc (DataT n) = contains n acc
        holds acc _ = False

||| Code that cannot crash, given which callees cannot crash or loop: no
||| possibly-crashing primitive and no IO.
safeCode : (String -> Bool) -> Expr -> Bool
safeCode s (EPrim _ (Div _) [a, ELit _ (LInt _ n)]) = n /= 0 && safeCode s a
safeCode s (EPrim _ (Mod _) [a, ELit _ (LInt _ n)]) = n /= 0 && safeCode s a
safeCode s (EPrim _ (Div _) _) = False
safeCode s (EPrim _ (Mod _) _) = False
safeCode s (EPrim _ _ as) = all (safeCode s) as
safeCode s (EIO {}) = False
safeCode s (ECall _ f as) = s f && all (safeCode s) as
safeCode s (ECon _ _ _ as) = all (safeCode s) as
safeCode s (ELet _ _ _ _ v b) = safeCode s v && safeCode s b
safeCode s (EMatchCon _ _ alts d) = all (\(MkConAlt _ _ e) => safeCode s e) alts && maybe True (safeCode s) d
safeCode s (EMatchLit _ _ alts d) = all (safeCode s . snd) alts && safeCode s d
safeCode s (ELam _ _ _ _ b) = safeCode s b
safeCode s (EApp _ f a) = safeCode s f && safeCode s a
safeCode s (EDelay _ e) = safeCode s e
safeCode s (EForce _ e) = safeCode s e
safeCode s _ = True

||| Calls in residual code.
callees : Expr -> List String
callees (ECall _ f as) = f :: concatMap callees as
callees (EPrim _ _ as) = concatMap callees as
callees (EIO _ _ as _) = concatMap callees as
callees (ECon _ _ _ as) = concatMap callees as
callees (ELet _ _ _ _ v b) = callees v ++ callees b
callees (EMatchCon _ _ alts d) = concatMap (\(MkConAlt _ _ e) => callees e) alts ++ maybe [] callees d
callees (EMatchLit _ _ alts d) = concatMap (callees . snd) alts ++ callees d
callees _ = []

||| Functions that cannot crash and terminate: total, no possibly-crashing
||| primitive, no IO, only safe callees (ELIM-G-5).
safeFns : Program -> SortedSet String
safeFns prog = go (fromList [f.name | f <- prog.fns, f.terminating])
  where
    go : SortedSet String -> SortedSet String
    go s = let s' = fromList [f.name | f <- prog.fns, contains f.name s, safeCode (`contains` s) f.body]
           in if Prelude.toList s' == Prelude.toList s then s else go s'

------------------------------------------------------------------------------
-- Shapes and flattening (G3)
------------------------------------------------------------------------------

||| A polynomial hash, for compact keys of expressions.
fnv : String -> Integer
fnv s = foldl (\h, c => (h * 131 + cast (ord c)) `mod` 2305843009213693951) 7 (unpack s)

strShape : SStr -> String
strShape (SLit s) = show s
strShape (SVarStr _) = "_"
strShape (SAppend a b) = "(" ++ strShape a ++ "++" ++ strShape b ++ ")"
strShape (SConsChar _ s) = "(c:" ++ strShape s ++ ")"
strShape (SShowInt t _) = "show_" ++ show t
strShape (SChar _) = "chr"

strAtoms : SStr -> List (Expr, Ty)
strAtoms (SVarStr e) = [(e, StrT)]
strAtoms (SAppend a b) = strAtoms a ++ strAtoms b
strAtoms (SConsChar c s) = (c, CharT) :: strAtoms s
strAtoms (SShowInt t n) = [(n, IntT t)]
strAtoms (SChar c) = [(c, CharT)]
strAtoms (SLit _) = []

strRebuild : SStr -> List Expr -> (SStr, List Expr)
strRebuild (SVarStr _) (e :: es) = (SVarStr e, es)
strRebuild (SAppend a b) es = let (a', es1) = strRebuild a es
                                  (b', es2) = strRebuild b es1
                              in (SAppend a' b', es2)
strRebuild (SConsChar _ s) (c :: es) = let (s', es') = strRebuild s es in (SConsChar c s', es')
strRebuild (SShowInt t _) (n :: es) = (SShowInt t n, es)
strRebuild (SChar _) (c :: es) = (SChar c, es)
strRebuild s es = (s, es)

mutual
  ||| The static structure of a value; the key of a specialization.
  shape : SVal -> String
  shape (Dyn _ t) = "_:" ++ show t
  shape (SLam env x _ _ _) = "\\" ++ show x ++ "[" ++ joinBy "," (map (\(y, v) => show y ++ "=" ++ shape v) env) ++ "]"
  shape (SDelay env e) = "delay" ++ show (fnv (showExpr 0 e)) ++
                         "[" ++ joinBy "," (map (\(x, v) => show x ++ "=" ++ shape v) env) ++ "]"
  shape (SCon d c fs) = c ++ "(" ++ joinBy "," (map shape fs) ++ ")"
  shape (SCall f as es) = f ++ "(" ++ joinBy "," (map shape as) ++ ")" ++ concatMap elimShape es
  shape (SString s) = "str" ++ strShape s

  elimShape : Elim -> String
  elimShape (EApply a) = "@(" ++ shape a ++ ")"
  elimShape (EProj c i) = "." ++ c ++ "#" ++ show i
  elimShape EForceIt = "!"

mutual
  ||| The runtime atoms inside a static value, in a fixed order.
  flatten : SVal -> List (Expr, Ty)
  flatten (Dyn e t) = [(e, t)]
  flatten (SLam env _ _ _ _) = concatMap (flatten . snd) env
  flatten (SDelay env _) = concatMap (flatten . snd) env
  flatten (SCon _ _ fs) = concatMap flatten fs
  flatten (SCall _ as es) = concatMap flatten as ++ concatMap flattenElim es
  flatten (SString s) = strAtoms s

  flattenElim : Elim -> List (Expr, Ty)
  flattenElim (EApply a) = flatten a
  flattenElim _ = []

mutual
  ||| Rebuilds a static value with its atoms replaced, in `flatten` order.
  rebuild : SVal -> List Expr -> (SVal, List Expr)
  rebuild (Dyn _ t) (e :: es) = (Dyn e t, es)
  rebuild (Dyn e t) [] = (Dyn e t, [])
  rebuild (SLam env x q t b) es = let (env', es') = rebuildEnv env es in (SLam env' x q t b, es')
  rebuild (SDelay env b) es = let (env', es') = rebuildEnv env es in (SDelay env' b, es')
  rebuild (SCon d c fs) es = let (fs', es') = rebuildList fs es in (SCon d c fs', es')
  rebuild (SCall f as ms) es =
    let (as', es1) = rebuildList as es
        (ms', es2) = rebuildElims ms es1
    in (SCall f as' ms', es2)
  rebuild (SString s) es = let (s', es') = strRebuild s es in (SString s', es')

  rebuildList : List SVal -> List Expr -> (List SVal, List Expr)
  rebuildList [] es = ([], es)
  rebuildList (v :: vs) es = let (v', es1) = rebuild v es
                                 (vs', es2) = rebuildList vs es1
                             in (v' :: vs', es2)

  rebuildEnv : Env -> List Expr -> (Env, List Expr)
  rebuildEnv [] es = ([], es)
  rebuildEnv ((x, v) :: rest) es = let (v', es1) = rebuild v es
                                       (rest', es2) = rebuildEnv rest es1
                                   in ((x, v') :: rest', es2)

  rebuildElims : List Elim -> List Expr -> (List Elim, List Expr)
  rebuildElims [] es = ([], es)
  rebuildElims (EApply a :: ms) es = let (a', es1) = rebuild a es
                                         (ms', es2) = rebuildElims ms es1
                                     in (EApply a' :: ms', es2)
  rebuildElims (m :: ms) es = let (ms', es') = rebuildElims ms es in (m :: ms', es')

------------------------------------------------------------------------------
-- Free variables (closures capture only what they use)
------------------------------------------------------------------------------

mutual
  freeVars : Expr -> SortedSet Var
  freeVars (EVar _ x) = singleton x
  freeVars (EPrim _ _ as) = unions (map freeVars as)
  freeVars (EIO _ _ as _) = unions (map freeVars as)
  freeVars (ECall _ _ as) = unions (map freeVars as)
  freeVars (EPartial _ _ as) = unions (map freeVars as)
  freeVars (ECon _ _ _ as) = unions (map freeVars as)
  freeVars (ELet _ x _ _ v b) = union (freeVars v) (delete x (freeVars b))
  freeVars (EMatchCon _ x alts d) =
    insert x (unions (maybe empty freeVars d :: map altVars alts))
  freeVars (EMatchLit _ x alts d) = insert x (unions (freeVars d :: map (freeVars . snd) alts))
  freeVars (ELam _ x _ _ b) = delete x (freeVars b)
  freeVars (EApp _ f a) = union (freeVars f) (freeVars a)
  freeVars (EDelay _ e) = freeVars e
  freeVars (EForce _ e) = freeVars e
  freeVars _ = empty

  altVars : ConAlt -> SortedSet Var
  altVars (MkConAlt _ xs e) = foldr delete (freeVars e) xs

  unions : List (SortedSet Var) -> SortedSet Var
  unions = foldl union empty

capture : Env -> SortedSet Var -> Env
capture env fvs = sortBy (\a, b => compare (fst a) (fst b))
                    (nubBy (\a, b => fst a == fst b) (filter (\(x, _) => contains x fvs) env))

------------------------------------------------------------------------------
-- Compile-time primitives (G6)
------------------------------------------------------------------------------

pow2 : Nat -> Integer
pow2 Z = 1
pow2 (S k) = 2 * pow2 k

wrap : IntTy -> Integer -> Integer
wrap t n =
  let m = pow2 (width t)
      r = n `mod` m
      r' = if r < 0 then r + m else r
  in if signed t && r' >= m `div` 2 then r' - m else r'

||| Euclidean division and remainder (SEM-INT-3), b /= 0.
euclid : Integer -> Integer -> (Integer, Integer)
euclid a b =
  let q = if (a < 0) == (b < 0) then abs a `div` abs b else negate (abs a `div` abs b)
      r = a - b * q
  in if r < 0 then (if b > 0 then (q - 1, r + b) else (q + 1, r - b)) else (q, r)

isScalar : Integer -> Bool
isScalar c = (c >= 0 && c <= 0xD7FF) || (c >= 0xE000 && c <= 0x10FFFF)

cmpLit : String -> Integer -> Integer -> Lit
cmpLit op a b = LInt IdrisInt (if res then 1 else 0)
  where
    res : Bool
    res = case op of
      "lt" => a < b
      "lte" => a <= b
      "eq" => a == b
      "gte" => a >= b
      _ => a > b

litInt : Lit -> Maybe Integer
litInt (LInt _ n) = Just n
litInt (LChar c) = Just c
litInt _ = Nothing

||| A primitive on literal arguments, when it cannot crash.
foldPrim : PrimOp -> List Lit -> Maybe Lit
foldPrim (Add t) [LInt _ a, LInt _ b] = Just (LInt t (wrap t (a + b)))
foldPrim (Sub t) [LInt _ a, LInt _ b] = Just (LInt t (wrap t (a - b)))
foldPrim (Mul t) [LInt _ a, LInt _ b] = Just (LInt t (wrap t (a * b)))
foldPrim (Div t) [LInt _ a, LInt _ b] =
  if b == 0 then Nothing
  else if signed t then Just (LInt t (wrap t (fst (euclid a b)))) else Just (LInt t (a `div` b))
foldPrim (Mod t) [LInt _ a, LInt _ b] =
  if b == 0 then Nothing
  else if signed t then Just (LInt t (wrap t (snd (euclid a b)))) else Just (LInt t (a `mod` b))
foldPrim (Lt _) [x, y] = cmpLit "lt" <$> litInt x <*> litInt y
foldPrim (Lte _) [x, y] = cmpLit "lte" <$> litInt x <*> litInt y
foldPrim (Eq _) [x, y] = cmpLit "eq" <$> litInt x <*> litInt y
foldPrim (Gte _) [x, y] = cmpLit "gte" <$> litInt x <*> litInt y
foldPrim (Gt _) [x, y] = cmpLit "gt" <$> litInt x <*> litInt y
foldPrim (Cast _ (IntT t)) [x] = LInt t . wrap t <$> litInt x
foldPrim (Cast _ CharT) [x] = (\n => LChar (if isScalar n then n else 0)) <$> litInt x
foldPrim (Cast CharT StrT) [LChar c] = Just (LStr (singleton (chr (cast c))))
foldPrim (Cast (IntT _) StrT) [LInt _ n] = Just (LStr (show n))
foldPrim StrAppend [LStr a, LStr b] = Just (LStr (a ++ b))
foldPrim StrCons [LChar c, LStr s] = Just (LStr (strCons (chr (cast c)) s))
foldPrim StrLength [LStr s] = Just (LInt IdrisInt (cast (length s)))
foldPrim StrReverse [LStr s] = Just (LStr (reverse s))
foldPrim (StrCompare op) [LStr a, LStr b] =
  Just (LInt IdrisInt (if cmp op a b then 1 else 0))
  where
    cmp : String -> String -> String -> Bool
    cmp "lt" x y = x < y
    cmp "lte" x y = x <= y
    cmp "eq" x y = x == y
    cmp "gte" x y = x >= y
    cmp _ x y = x > y
foldPrim (And t) [LInt _ a, LInt _ b] = Nothing   -- left to MLIR
foldPrim _ _ = Nothing

------------------------------------------------------------------------------
-- The specializer
------------------------------------------------------------------------------

atomLit : SVal -> Maybe Lit
atomLit (Dyn (ELit _ l) _) = Just l
atomLit _ = Nothing

||| A string value as a static string description.
asStr : SVal -> Maybe SStr
asStr (SString s) = Just s
asStr (Dyn (ELit _ (LStr s)) _) = Just (SLit s)
asStr (Dyn e StrT) = Just (SVarStr e)
asStr _ = Nothing

||| A fully literal static string.
strLit : SStr -> Maybe String
strLit (SLit s) = Just s
strLit (SAppend a b) = [| strLit a ++ strLit b |]
strLit (SConsChar (ELit _ (LChar c)) s) = strCons (chr (cast c)) <$> strLit s
strLit (SChar (ELit _ (LChar c))) = Just (singleton (chr (cast c)))
strLit (SShowInt _ (ELit _ (LInt _ n))) = Just (show n)
strLit _ = Nothing

||| A string that must exist at runtime: only literals and runtime string
||| values (which are literals passed around) qualify (PROF-HEAP-3).
materializeStr : Loc -> SStr -> M SVal
materializeStr l (SVarStr e) = pure (Dyn e StrT)
materializeStr l s = case strLit s of
  Just lit => pure (Dyn (ELit l (LStr lit)) StrT)
  Nothing => fail "PROF-HEAP-3" l
               ("a string is built at runtime here and is not written directly by putStr, " ++
                "so it would need the heap")

||| A value that must exist at runtime (PROF-HEAP-1, PROF-HEAP-2).
toDyn : Loc -> SVal -> M (Expr, Ty)
toDyn l (Dyn e t) = pure (e, t)
toDyn l (SString s) = do
  Dyn e t <- materializeStr l s
    | _ => fail "PROF-HEAP-3" l "a string"
  pure (e, t)
toDyn l (SDelay _ _) = fail "PROF-HEAP-2" l "a Lazy value would exist at runtime here"
toDyn l v = fail "PROF-HEAP-1" l
              ("a function or IO action would exist at runtime here (" ++ shape v ++ "); " ++
               "it must be applied, run or passed to a known function")

fnOf : Loc -> String -> M Fn
fnOf l f = do
  st <- get
  maybe (fail "CORE-CHECK-1" l ("unknown function " ++ f)) pure (lookupFn f st.prog)

conFieldTypes : Loc -> String -> String -> M (List Ty)
conFieldTypes l d c = do
  st <- get
  case lookupCon d c st.prog of
    Just con => pure (map (.type) con.fields)
    Nothing => fail "CORE-CHECK-1" l ("unknown constructor " ++ c ++ " of " ++ d)

||| The type of a value after eliminations.
elimTy : Loc -> Ty -> List Elim -> M Ty
elimTy l t [] = pure t
elimTy l (FunT _ _ r) (EApply _ :: es) = elimTy l r es
elimTy l (LazyT t) (EForceIt :: es) = elimTy l t es
elimTy l (DataT d) (EProj c i :: es) = do
  tys <- conFieldTypes l d c
  maybe (fail "CORE-CHECK-1" l "bad projection") (\t => elimTy l t es) (getAt i tys)
elimTy l t _ = fail "CORE-CHECK-1" l ("cannot eliminate a value of type " ++ show t)

mutual
  ||| Evaluates an expression and applies the eliminations to its value.
  evalK : Env -> Expr -> List Elim -> M SVal
  -- G1: the lambda's body is the action it describes, not prefix code.
  evalK env (ELam _ x q t b) (EApply a :: es) = leavePrefix (evalK ((x, a) :: env) b es)
  evalK env (ELam l x q t b) [] = pure (SLam (capture env (delete x (freeVars b))) x q t b)
  evalK env (EDelay _ e) (EForceIt :: es) = leavePrefix (evalK env e es)          -- G8
  evalK env (EDelay l e) [] = pure (SDelay (capture env (freeVars e)) e)
  evalK env (EApp l f a) es = do
    a' <- evalK env a []
    evalK env f (EApply a' :: es)
  evalK env (EForce l e) es = evalK env e (EForceIt :: es)
  evalK env (ELet l x q t v b) es = do                                               -- G4
    v' <- if q == Q0 then pure (Dyn (EErased l) ErasedT) else evalK env v []
    evalK ((x, v') :: env) b es
  evalK env (EMatchCon l x alts def) es = do
    scrut <- lookupVar l env x
    matchCon env l scrut alts def es
  evalK env (EMatchLit l x alts def) es = do
    scrut <- lookupVar l env x
    case atomLit scrut of
      Just lit => case find (\(k, _) => sameLit k lit) alts of
                    Just (_, e) => evalK env e es
                    Nothing => evalK env def es
      Nothing => do
        (se, st) <- toDyn l scrut
        sv <- atomVar l se st
        alts' <- traverse (\(k, e) => (k,) <$> branch env e es) alts
        def' <- branch env def es
        resTy <- branchType l (map (snd . snd) alts' ++ [snd def'])
        bindDyn l resTy (EMatchLit l sv (map (\(k, (e, _)) => (k, e)) alts') (fst def'))
  evalK env e es = do
    v <- eval env e
    consume (locOf e) v es

  ||| Evaluates an expression that is not an elimination context.
  eval : Env -> Expr -> M SVal
  eval env (EVar l x) = lookupVar l env x
  eval env (ELit l lit) = pure (Dyn (ELit l lit) (litTy lit))
  eval env (EErased l) = pure (Dyn (EErased l) ErasedT)
  eval env (EWorld l) = fail "PROF-IO-3" l "%MkWorld outside the root"
  eval env (EPrim l op args) = do
    vs <- traverse (\a => evalK env a []) args
    prim l op vs
  eval env (EIO l op args res) = do
    vs <- traverse (\a => evalK env a []) args
    io l op vs res
  eval env (ECall l f args) = do
    vs <- traverse (\a => evalK env a []) args
    fn <- fnOf l f
    st <- get
    if isStaticTy st fn.result
       then pure (SCall f vs [])                                                  -- G5
       else call l f vs []
  eval env (ECon l d c args) = do
    vs <- traverse (\a => evalK env a []) args
    st <- get
    if contains d st.staticData
       then pure (SCon d c vs)
       else do
         atoms <- traverse (toDyn l) vs
         bindDyn l (DataT d) (ECon l d c (map fst atoms))
  eval env (EPartial l f args) = fail "CORE-CHECK-1" l "partial applications are eta-expanded"
  eval env e = evalK env e []

  lookupVar : Loc -> Env -> Var -> M SVal
  lookupVar l env x = maybe (fail "CORE-CHECK-1" l ("unbound variable %" ++ show x)) pure (lookup x env)

  sameLit : Lit -> Lit -> Bool
  sameLit (LInt _ a) (LInt _ b) = a == b
  sameLit (LChar a) (LChar b) = a == b
  sameLit (LStr a) (LStr b) = a == b
  sameLit _ _ = False

  atomVar : Loc -> Expr -> Ty -> M Var
  atomVar l (EVar _ x) t = pure x
  atomVar l e t = do
    x <- freshVar
    emit (BLet x QW t e)
    pure x

  ||| One branch of a residual match, in its own scope; its value must be
  ||| first order.
  branch : Env -> Expr -> List Elim -> M (Expr, Ty)
  branch env e es = scopedTyped $ do
    v <- evalK env e es
    toDyn (locOf e) v

  branchType : Loc -> List Ty -> M Ty
  branchType l [] = fail "CORE-CHECK-1" l "a match without alternatives"
  branchType l (t :: _) = pure t

  matchCon : Env -> Loc -> SVal -> List ConAlt -> Maybe Expr -> List Elim -> M SVal
  matchCon env l (SCon d c fs) alts def es = case find (\(MkConAlt k _ _) => k == c) alts of  -- G2
    Just (MkConAlt _ xs e) => evalK (zip xs fs ++ env) e es
    Nothing => maybe (fail "CORE-CHECK-1" l "no alternative for a known constructor")
                     (\d => evalK env d es) def
  matchCon env l v@(SCall f as ms) alts def es = do
    -- A static single-constructor value: its fields are projections (G5).
    st <- get
    fn <- fnOf l f
    DataT d <- elimTy l fn.result ms
      | _ => fail "PROF-HEAP-1" l "a match on a static value that is not data"
    case lookupData d st.prog of
      Just dt => case dt.cons of
        [con] => case find (\(MkConAlt k _ _) => k == con.name) alts of
          Just (MkConAlt _ xs e) =>
            let fields = map (\i => SCall f as (ms ++ [EProj con.name i])) [0 .. length xs `minus` 1]
            in evalK (zip xs (take (length xs) fields) ++ env) e es
          Nothing => maybe (fail "CORE-CHECK-1" l "no alternative") (\dd => evalK env dd es) def
        _ => fail "PROF-HEAP-1" l
               ("the constructor of a static value of type " ++ d ++ " would be chosen at runtime")
      Nothing => fail "CORE-CHECK-1" l ("unknown data " ++ d)
  matchCon env l (Dyn (EVar _ x) (DataT d)) alts def es = do
    st <- get
    tys <- traverse (\(MkConAlt c _ _) => conFieldTypes l d c) alts
    alts' <- traverse (altBranch st) (zip alts tys)
    def' <- traverse (\e => branch env e es) def
    resTy <- branchType l (map snd alts' ++ maybe [] (pure . snd) def')
    bindDyn l resTy (EMatchCon l x (map fst alts') (map fst def'))
    where
      altBranch : St -> (ConAlt, List Ty) -> M (ConAlt, Ty)
      -- Fresh binders: the same alternative may be residualized more than
      -- once in one function (CORE-INV-1).
      altBranch st (MkConAlt c xs e, tys) = do
        ys <- traverse (\_ => freshVar) xs
        (body, t) <- branch (zipWith3 (\x, y, t => (x, dynVar l y t)) xs ys tys ++ env) e es
        pure (MkConAlt c ys body, t)
  matchCon env l v alts def es = fail "PROF-HEAP-1" l ("a match on " ++ shape v)

  ||| Applies eliminations to a value.
  consume : Loc -> SVal -> List Elim -> M SVal
  consume l v [] = pure v
  consume l (SLam env x q t b) (EApply a :: es) = leavePrefix (evalK ((x, a) :: env) b es)
  consume l (SDelay env e) (EForceIt :: es) = leavePrefix (evalK env e es)
  consume l (SCon d c fs) (EProj c' i :: es) = case getAt i fs of
    Just f => consume l f es
    Nothing => fail "CORE-CHECK-1" l "bad projection"
  consume l (SCall f as ms) es = do
    fn <- fnOf l f
    st <- get
    t <- elimTy l fn.result (ms ++ es)
    if isStaticTy st t
       then pure (SCall f as (ms ++ es))
       -- Running the deferred call is the action, not prefix code; the
       -- callee's own prefix is checked where it is specialized.
       else leavePrefix (call l f as (ms ++ es))
  consume l v es = fail "PROF-HEAP-1" l ("cannot apply or project " ++ shape v)

  ||| Consuming a static value runs the action it describes: not a prefix.
  leavePrefix : M a -> M a
  leavePrefix act = do
    saved <- map inPrefix get
    modify { inPrefix := Nothing }
    x <- act
    modify { inPrefix := saved }
    pure x

  ||| A call to `f` with (possibly static) arguments and eliminations: a call
  ||| to the specialization for their shape (G3, G5).
  call : Loc -> String -> List SVal -> List Elim -> M SVal
  call l f args0 es = do
    fn <- fnOf l f
    -- A fully literal string is runtime static data, not a static value.
    let args = map literalStr args0
    resTy <- elimTy l fn.result es
    let atoms = concatMap flatten args ++ concatMap flattenElim es
    let allDyn = all isDyn args && null es
    let key = if allDyn then f else f ++ "{" ++ joinBy ";" (map shape args) ++ concatMap elimShape es ++ "}"
    name <- specialize l fn key args es resTy
    bindDyn l resTy (ECall l name (map fst atoms))
    where
      isDyn : SVal -> Bool
      isDyn (Dyn _ _) = True
      isDyn _ = False
      literalStr : SVal -> SVal
      literalStr (SString s) = maybe (SString s) (\lit => Dyn (ELit l (LStr lit)) StrT) (strLit s)
      literalStr v = v

  specialize : Loc -> Fn -> String -> List SVal -> List Elim -> Ty -> M String
  specialize l fn key args es resTy = do
    st <- get
    case lookup key st.memo of
      Just n => pure n
      Nothing => do
        let count = fromMaybe 0 (lookup fn.name st.counts)
        when (count >= 256 || length key > 4096) $
          fail "PROF-HEAP-4" l
               ("specializing " ++ fn.idrisName ++ " does not terminate: a recursive function " ++
                "passes itself a different function or IO action on each call")
        put ({ memo $= insert key key, counts $= insert fn.name (S count), active $= insert key } st)
        let atoms = concatMap flatten args ++ concatMap flattenElim es
        params <- traverse (\(_, t) => (, t) <$> freshVar) atoms
        let pexprs = map (\(v, t) => if t == ErasedT then EErased l else EVar l v) params
        let (args', rest) = rebuildList args pexprs
        let (es', _) = rebuildElims es rest
        let env = zip (map (.var) fn.params) args'
        saved <- map inPrefix get
        -- G5: the body before the eliminations apply runs where the action is used.
        modify { inPrefix := if null es then Nothing else Just l }
        body <- scoped $ do
          v <- evalK env fn.body es'
          (a, _) <- toDyn fn.loc v
          pure a
        modify { inPrefix := saved }
        -- A specialization is safe when its function terminates and its code
        -- cannot crash. Recursion makes that conditional on specializations
        -- not finished yet; `settle` decides once they are.
        modify { active $= delete key }
        st' <- get
        let unknown = \g => contains g st'.active || isJust (lookup g st'.pending)
        let isSafe = fn.terminating &&
                     safeCode (\g => g == key || contains g st'.safe || unknown g) body
        if isSafe
           then case nub (filter (\g => g /= key && unknown g) (callees body)) of
                  [] => modify { safe $= insert key }
                  deps => modify { pending $= insert key deps }
           else unsafe l key
        settle l
        let newFn = MkFn key fn.idrisName (map (\(v, t) => MkParam v (quantityOf t) t) params)
                         resTy body fn.loc fn.terminating
        modify { done $= (:< newFn) }
        pure key
    where
      quantityOf : Ty -> Quantity
      quantityOf ErasedT = Q0
      quantityOf WorldT = Q1
      quantityOf _ = QW

  ||| A specialization that may crash or loop; fatal if it was relied on.
  unsafe : Loc -> String -> M ()
  unsafe l key = do
    st <- get
    when (contains key st.assumed) $
      fail "PROF-HEAP-5" l
           ("arity raising is blocked: " ++ key ++ " may crash or not terminate, and a " ++
            "call to it would move from where an IO action or function is built to where it runs")

  ||| Decides pending specializations: unsafe if a callee is unsafe; safe once
  ||| no callee is unsafe and none can still reach one being built.
  settle : Loc -> M ()
  settle l = do
    st <- get
    let entries = SortedMap.toList st.pending
    let isBad = \g => not (contains g st.safe || contains g st.active || isJust (lookup g st.pending))
    case find (\(_, deps) => any isBad deps) entries of
      Just (k, _) => do
        modify { pending $= delete k }
        unsafe l k
        settle l
      Nothing => do
        let blocked = reach (fromList [k | (k, deps) <- entries, any (`contains` st.active) deps]) entries
        let free = [k | (k, _) <- entries, not (contains k blocked)]
        modify { pending $= \p => foldl (\m, k => delete k m) p free
               , safe $= union (fromList free) }
    where
      reach : SortedSet String -> List (String, List String) -> SortedSet String
      reach s es = let s' = union s (fromList [k | (k, deps) <- es, any (`contains` s) deps])
                   in if Prelude.toList s' == Prelude.toList s then s else reach s' es

  ||| Primitives: compile-time evaluation (G6) and deferred strings (G7).
  prim : Loc -> PrimOp -> List SVal -> M SVal
  prim l op vs = case (op, map asStr vs) of
    (StrAppend, [Just a, Just b]) => pure (SString (SAppend a b))
    (StrCons, [_, Just s]) => do
      (c, _) <- firstAtom vs
      pure (SString (SConsChar c s))
    (Cast CharT StrT, _) => do
      (c, _) <- firstAtom vs
      pure (SString (SChar c))
    (Cast (IntT t) StrT, _) => do
      (n, _) <- firstAtom vs
      pure (SString (SShowInt t n))
    _ => do
      atoms <- traverse (toDyn l) vs
      case traverse atomLit (map (uncurry Dyn) atoms) of
        Just lits => case foldPrim op lits of
          Just lit => pure (Dyn (ELit l lit) (litTy lit))
          Nothing => residual atoms
        Nothing => residual atoms
    where
      firstAtom : List SVal -> M (Expr, Ty)
      firstAtom (v :: _) = toDyn l v
      firstAtom [] = fail "CORE-CHECK-1" l "a primitive without arguments"
      residual : List (Expr, Ty) -> M SVal
      residual atoms =
        if isStringOp op
           then fail "PROF-PRIM-4" l ("the string operation " ++ show op ++ " is not supported at runtime")
           else bindDyn l (primResult op) (EPrim l op (map fst atoms))

  ||| IO primitives, with output fusion for putStr (G7).
  io : Loc -> IOOp -> List SVal -> String -> M SVal
  io l PutStr [s, w] res = case asStr s of
    Just str => do
      (wExpr, _) <- toDyn l w
      putStr l str wExpr res
    Nothing => fail "CORE-CHECK-1" l "putStr of a non-string"
  io l op vs res = do
    atoms <- traverse (toDyn l) vs
    bindDyn l (DataT res) (EIO l op (map fst atoms) res)

  ||| Writes a static string: literal pieces and runtime pieces in order,
  ||| threading the world (G7). Returns the final `IORes` value.
  putStr : Loc -> SStr -> Expr -> String -> M SVal
  putStr l s w res = case strLit s of
    Just lit => bindDyn l (DataT res) (EIO l PutStr [ELit l (LStr lit), w] res)
    Nothing => case s of
      SVarStr e => bindDyn l (DataT res) (EIO l PutStr [e, w] res)
      SChar c => bindDyn l (DataT res) (EIO l PutChar [c, w] res)
      SShowInt t n => bindDyn l (DataT res) (EIO l (PutInt t) [n, w] res)
      SConsChar c rest => do
        r <- bindDyn l (DataT res) (EIO l PutChar [c, w] res)
        w' <- nextWorld r
        putStr l rest w' res
      SAppend a b => do
        r <- putStr l a w res
        w' <- nextWorld r
        putStr l b w' res
      SLit lit => bindDyn l (DataT res) (EIO l PutStr [ELit l (LStr lit), w] res)
    where
      nextWorld : SVal -> M Expr
      nextWorld (Dyn (EVar _ r) _) = do
        u <- freshVar
        w' <- freshVar
        emit (BUnpack r "PrimIO.MkIORes" [u, w'])
        pure (EVar l w')
      nextWorld _ = fail "CORE-CHECK-1" l "an IO result that is not a variable"

------------------------------------------------------------------------------
-- Entry
------------------------------------------------------------------------------

maxVar : Program -> Nat
maxVar prog = foldl max 0 (concatMap fnVars prog.fns) + 1
  where
    exprVars : Expr -> List Nat
    exprVars e = Prelude.toList (freeVarsAll e)
      where
        freeVarsAll : Expr -> SortedSet Var
        freeVarsAll (ELet _ x _ _ v b) = insert x (union (freeVarsAll v) (freeVarsAll b))
        freeVarsAll (ELam _ x _ _ b) = insert x (freeVarsAll b)
        freeVarsAll (EMatchCon _ x alts d) =
          insert x (foldl union (maybe empty freeVarsAll d)
                          (map (\(MkConAlt _ xs e) => union (fromList xs) (freeVarsAll e)) alts))
        freeVarsAll (EMatchLit _ x alts d) = insert x (foldl union (freeVarsAll d) (map (freeVarsAll . snd) alts))
        freeVarsAll (EPrim _ _ as) = foldl union empty (map freeVarsAll as)
        freeVarsAll (EIO _ _ as _) = foldl union empty (map freeVarsAll as)
        freeVarsAll (ECall _ _ as) = foldl union empty (map freeVarsAll as)
        freeVarsAll (ECon _ _ _ as) = foldl union empty (map freeVarsAll as)
        freeVarsAll (EApp _ f a) = union (freeVarsAll f) (freeVarsAll a)
        freeVarsAll (EDelay _ e) = freeVarsAll e
        freeVarsAll (EForce _ e) = freeVarsAll e
        freeVarsAll (EVar _ x) = singleton x
        freeVarsAll _ = empty
    fnVars : Fn -> List Nat
    fnVars f = map (.var) f.params ++ exprVars f.body

||| Runs the guaranteed eliminations from the root (CORE-PASS-1, step 4).
export
simplify : Program -> Either Diag Program
simplify prog = do
  let st0 = MkSt prog (maxVar prog) [] empty empty [<] (staticDatas prog) (safeFns prog) empty empty empty Nothing
  root <- maybe (Left (diag "CORE-CHECK-1" "Simplify" noLoc "no root")) Right (lookupFn prog.root prog)
  let rootArgs = map (\p => dynVar root.loc p.var p.type) root.params
  (st, body) <- runStateT st0 $ scoped $ do
    v <- evalK (zip (map (.var) root.params) rootArgs) root.body []
    (a, _) <- toDyn root.loc v
    pure a
  let root' = { body := body } root
  let fns = root' :: (st.done <>> [])
  let used = usedDatas fns
  pure ({ fns := fns
        , datas := filter (\d => contains d.name used && not (contains d.name st.staticData)) prog.datas
        } prog)
  where
    tyDatas : Ty -> List String
    tyDatas (DataT d) = [d]
    tyDatas _ = []
    exprDatas : Expr -> List String
    exprDatas (ECon _ d _ as) = d :: concatMap exprDatas as
    exprDatas (EIO _ _ as r) = r :: "Builtin.Unit" :: concatMap exprDatas as
    exprDatas (ELet _ _ _ t v b) = tyDatas t ++ exprDatas v ++ exprDatas b
    exprDatas (EMatchCon _ _ alts d) = concatMap (\(MkConAlt _ _ e) => exprDatas e) alts ++ maybe [] exprDatas d
    exprDatas (EMatchLit _ _ alts d) = concatMap (exprDatas . snd) alts ++ exprDatas d
    exprDatas (EPrim _ _ as) = concatMap exprDatas as
    exprDatas (ECall _ _ as) = concatMap exprDatas as
    exprDatas _ = []
    fnDatas : Fn -> List String
    fnDatas f = tyDatas f.result ++ concatMap (tyDatas . (.type)) f.params ++ exprDatas f.body
    closeData : SortedSet String -> SortedSet String
    closeData s = let s' = foldl (\acc, d => if contains d.name acc
                                               then foldl (\a, n => insert n a) acc
                                                      (concatMap (\c => concatMap (tyDatas . (.type)) c.fields) d.cons)
                                               else acc) s prog.datas
                  in if Prelude.toList s' == Prelude.toList s then s else closeData s'
    usedDatas : List Fn -> SortedSet String
    usedDatas fns = closeData (fromList (concatMap fnDatas fns))
