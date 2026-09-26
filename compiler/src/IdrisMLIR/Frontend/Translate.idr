||| Checked TT to full Core (docs/architecture/04-frontend.md). Reads compile-time
||| case trees (`treeCT`) and types; monomorphises on demand (ELIM-MONO-*), with
||| Idris's own normalizer doing all type-level computation.
module IdrisMLIR.Frontend.Translate

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.Directory
import Core.Env
import Core.Normalise
import Core.TT
import Core.Termination
import Libraries.Data.NameMap
import Libraries.Data.NatSet

import IdrisMLIR.Core

import Data.List
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.String

%default covering

------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------

||| A function instance waiting to be translated (ELIM-MONO-1).
record Pending where
  constructor MkPending
  name : Name
  instName : String
  typeArgs : List ClosedTerm

||| What a constructor instance needs for case trees.
record ConInfo where
  constructor MkConInfo
  params : List ClosedTerm   -- the data instance's type arguments
  core : Con

export
data TState : Type where

export
record TS where
  constructor MkTS
  nextVar : Nat
  datas : SortedMap String Data
  dataOrder : SnocList String
  building : SortedSet String
  cons : SortedMap String ConInfo     -- key: instance ++ "::" ++ constructor
  fns : SortedMap String Fn
  fnOrder : SnocList String
  seen : SortedSet String
  queue : List Pending
  moduleFC : FC

export
initState : FC -> TS
initState fc = MkTS 0 empty [<] empty empty empty [<] empty [] fc

fresh : {auto s : Ref TState TS} -> Core Var
fresh = do
  st <- get TState
  put TState ({ nextVar $= S } st)
  pure st.nextVar

------------------------------------------------------------------------------
-- Errors and locations
------------------------------------------------------------------------------

isEmptyFC : FC -> Bool
isEmptyFC EmptyFC = True
isEmptyFC _ = False

||| DIAG-FMT-1, DIAG-LOC-1: never an empty location.
export
reject : {auto s : Ref TState TS} -> FC -> String -> String -> String -> Core a
reject fc owner rule what = do
  st <- get TState
  let fc' = if isEmptyFC fc then st.moduleFC else fc
  throw (GenericMsg fc' ("mlir backend: " ++ owner ++ ": unsupported (" ++ rule ++ "): " ++ what))

||| An Idris location as a Core location, with the source file resolved.
export
toLoc : {auto c : Ref Ctxt Defs} -> FC -> Core Loc
toLoc fc@(MkFC (PhysicalIdrSrc ident) (sl, sc) (el, ec)) = do
  file <- catch (nsToSource fc ident) (\_ => pure "")
  pure (MkLoc (FromModule (unsafeUnfoldModuleIdent ident)) file sl sc el ec)
toLoc (MkFC (PhysicalPkgSrc file) (sl, sc) (el, ec)) = pure (MkLoc (FromPackage file) file sl sc el ec)
toLoc (MkVirtualFC (PhysicalIdrSrc ident) (sl, sc) (el, ec)) =
  toLoc (MkFC (PhysicalIdrSrc ident) (sl, sc) (el, ec))
toLoc _ = pure noLoc

||| A Core location as an Idris location, for errors raised after translation.
export
fromLoc : Loc -> FC
fromLoc l = case l.origin of
  FromModule ident => MkFC (PhysicalIdrSrc (unsafeFoldModuleIdent ident)) (l.startLine, l.startCol) (l.endLine, l.endCol)
  FromPackage file => MkFC (PhysicalPkgSrc file) (l.startLine, l.startCol) (l.endLine, l.endCol)
  Nowhere => EmptyFC

------------------------------------------------------------------------------
-- Terms as closed values
------------------------------------------------------------------------------

||| What a TT variable stands for during translation.
data VarInfo = Bound Var Ty | TypeValue ClosedTerm

||| Does the term mention `Erased` (a placeholder for an unknown value)?
anyErased : Term vars -> Bool
anyErased (Erased _ _) = True
anyErased (Bind _ _ b sc) = anyErased (binderType b) || binderVal b || anyErased sc
  where
    binderVal : Binder (Term vs) -> Bool
    binderVal (Let _ _ v _) = anyErased v
    binderVal (PLet _ _ v _) = anyErased v
    binderVal _ = False
anyErased (App _ f a) = anyErased f || anyErased a
anyErased (As _ _ a p) = anyErased p
anyErased (TDelayed _ _ t) = anyErased t
anyErased (TDelay _ _ t a) = anyErased t || anyErased a
anyErased (TForce _ _ t) = anyErased t
anyErased (Meta _ _ _ args) = any anyErased args
anyErased _ = False

||| Abstracts every variable in scope with a lambda, giving a closed term whose
||| outermost lambda binds the last variable of `vars`.
wrapLams : {vars : Scope} -> FC -> Term vars -> ClosedTerm
wrapLams {vars = []} fc tm = tm
wrapLams {vars = x :: rest} fc tm =
  wrapLams {vars = rest} fc (Bind fc x (Lam fc top Explicit (Erased fc Placeholder)) tm)

||| The closed normal form of a term in scope, with type variables replaced by
||| their known values and every other variable by `Erased`.
closeNormalise : {auto c : Ref Ctxt Defs} -> {vars : Scope} ->
                 FC -> List VarInfo -> Term vars -> Core ClosedTerm
closeNormalise fc env tm = do
  let values = map value env
  let closed = foldl (App fc) (wrapLams fc tm) (reverse values)
  defs <- get Ctxt
  normalise defs [] closed
  where
    value : VarInfo -> ClosedTerm
    value (TypeValue t) = t
    value (Bound _ _) = Erased fc Placeholder

normaliseClosed : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core ClosedTerm
normaliseClosed tm = do
  defs <- get Ctxt
  normalise defs [] tm

showTerm : ClosedTerm -> String
showTerm = show

spine : Term vars -> List (Term vars) -> (Term vars, List (Term vars))
spine (App _ fn arg) args = spine fn (arg :: args)
spine fn args = (fn, args)

||| A type-level parameter: its type is a universe, possibly after Pi binders.
isTypeLike : ClosedTerm -> Bool
isTypeLike (TType _ _) = True
isTypeLike (Bind _ _ (Pi _ _ _ _) sc) = typeLikeScope sc
  where
    typeLikeScope : Term vs -> Bool
    typeLikeScope (TType _ _) = True
    typeLikeScope (Bind _ _ (Pi _ _ _ _) s) = typeLikeScope s
    typeLikeScope _ = False
isTypeLike _ = False

quantity : RigCount -> Quantity
quantity rig = if isErased rig then Q0 else if isLinear rig then Q1 else QW

lookupDef : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            FC -> String -> Name -> Core GlobalDef
lookupDef fc owner n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => reject fc owner "FE-TTC-1" ("missing definition " ++ show n)
  pure def

------------------------------------------------------------------------------
-- Types and data instances
------------------------------------------------------------------------------

intTy : PrimType -> Maybe IntTy
intTy IntType = Just IdrisInt
intTy Int8Type = Just SInt8
intTy Int16Type = Just SInt16
intTy Int32Type = Just SInt32
intTy Int64Type = Just SInt64
intTy Bits8Type = Just UInt8
intTy Bits16Type = Just UInt16
intTy Bits32Type = Just UInt32
intTy Bits64Type = Just UInt64
intTy _ = Nothing

||| ELIM-MONO-4: the definition's full name and its arguments' normal forms.
instanceName : {auto c : Ref Ctxt Defs} -> Name -> List ClosedTerm -> Core String
instanceName n [] = show <$> toFullNames n
instanceName n args = do
  n' <- toFullNames n
  args' <- traverse toFullNames args
  pure (show n' ++ "[" ++ joinBy ", " (map showTerm args') ++ "]")

mutual
  ||| The Core type of a closed, normalised type (FE-TR-1, PROF-TYPE-4).
  export
  coreType : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             FC -> String -> ClosedTerm -> Core Ty
  coreType fc owner (PrimVal _ (PrT t)) = case intTy t of
    Just it => pure (IntT it)
    Nothing => case t of
      CharType => pure CharT
      StringType => pure StrT
      WorldType => pure WorldT
      _ => reject fc owner "PROF-TYPE-4" (show t ++ " in a runtime position")
  coreType fc owner (Bind bfc x (Pi _ rig _ a) sc) = do
    at <- if isErased rig then pure ErasedT else coreType fc owner a
    let rest = subst (Erased bfc Placeholder) sc
    when (anyErased rest && not (isErased rig)) $
      reject fc owner "PROF-TYPE-4" "a function type that depends on its argument"
    rt <- coreType fc owner !(normaliseClosed rest)
    pure (FunT (quantity rig) at rt)
  coreType fc owner (TDelayed _ LLazy t) = LazyT <$> coreType fc owner t
  coreType fc owner (TDelayed _ _ _) = reject fc owner "PROF-TYPE-4" "Inf (codata) in a runtime position"
  coreType fc owner tm = case spine tm [] of
    (Ref rfc (TyCon _) n, args) => DataT <$> dataInstance fc owner n !(traverse normaliseClosed args)
    (TType _ _, _) => reject fc owner "PROF-TYPE-4" "Type in a runtime position"
    (Erased _ _, _) => reject fc owner "PROF-TYPE-4" "a type that depends on a runtime or erased value"
    _ => reject fc owner "PROF-TYPE-4" ("unsupported runtime type " ++ showTerm tm)

  ||| Registers a monomorphic data instance (PROF-DATA-*, ELIM-MONO-1).
  export
  dataInstance : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 FC -> String -> Name -> List ClosedTerm -> Core String
  dataInstance fc owner tcon args = do
    def <- lookupDef fc owner tcon
    let tname = show (fullname def)
    inst <- instanceName (fullname def) args
    st <- get TState
    if isJust (lookup inst st.datas) then pure inst else do
      when (contains inst st.building) $
        reject fc owner "PROF-DATA-3" ("recursive data type " ++ tname ++ " at runtime")
      TCon arity params _ _ _ datacons _ <- pure (definition def)
        | _ => reject fc owner "PROF-TYPE-4" (tname ++ " is not a data type")
      let Just datacons = datacons
        | Nothing => reject fc owner "PROF-DATA-5" (tname ++ " has no known constructors")
      when (any (\i => not (elem i params)) [0 .. minus arity 1] && arity > 0) $
        reject (location def) tname "PROF-DATA-5" "a data type with indices at runtime"
      put TState ({ building $= insert inst } st)
      loc <- toLoc (location def)
      conList <- traverse (constructor inst args) datacons
      let sorted = sortBy (\a, b => compare a.tag b.tag) conList
      update TState { building $= delete inst
                    , datas $= insert inst (MkData inst tname sorted loc)
                    , dataOrder $= (:< inst) }
      pure inst
    where
      ||| Parameters first, then the fields.
      walk : String -> FC -> List ClosedTerm -> ClosedTerm -> Core (List Field)
      walk cname dfc (p :: ps) (Bind _ _ (Pi {}) sc) = walk cname dfc ps (subst p sc)
      walk cname dfc [] (Bind bfc _ (Pi _ rig _ a) sc) = do
        t <- if isErased rig then pure ErasedT else do
               a' <- normaliseClosed a
               when (anyErased a') $
                 reject dfc cname "PROF-TYPE-4" "a field type that depends on another field"
               coreType dfc cname a'
        rest <- walk cname dfc [] (subst (Erased bfc Placeholder) sc)
        pure (MkField (quantity rig) t :: rest)
      walk _ _ _ _ = pure []

      constructor : String -> List ClosedTerm -> Name -> Core Con
      constructor inst targs dcon = do
        def <- lookupDef fc owner dcon
        let cname = show (fullname def)
        DCon tag arity _ <- pure (definition def)
          | _ => reject fc owner "FE-TTC-1" (cname ++ " is not a constructor")
        loc <- toLoc (location def)
        fields <- walk cname (location def) targs (type def)
        let con = MkCon cname cname (cast tag) fields loc
        update TState { cons $= insert (inst ++ "::" ++ cname) (MkConInfo targs con) }
        pure con

------------------------------------------------------------------------------
-- Function instances
------------------------------------------------------------------------------

||| Requests a function instance and returns its name.
request : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Name -> List ClosedTerm -> Core String
request n targs = do
  inst <- instanceName n targs
  st <- get TState
  unless (contains inst st.seen) $
    put TState ({ seen $= insert inst, queue $= (++ [MkPending n inst targs]) } st)
  pure inst

||| Parameter classification after instantiation.
data PKind = TypeParam ClosedTerm | ErasedParam | RuntimeParam Ty

||| Walks a callee's type over its arguments: which are type parameters,
||| which are erased, which are runtime (and their types).
classify : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           FC -> String -> Nat -> ClosedTerm -> List (Maybe ClosedTerm) ->
           Core (List (Quantity, PKind), ClosedTerm)
classify fc owner Z ty _ = pure ([], ty)
classify fc owner (S k) (Bind bfc _ (Pi _ rig _ a) sc) vals = do
  a' <- normaliseClosed a
  let v = fromMaybe Nothing (head' vals)
  let vals' = drop 1 vals
  if isErased rig && isTypeLike a'
     then do
       let Just val = v
         | Nothing => reject fc owner "PROF-FN-7" "a type argument that is not known statically"
       (rest, res) <- classify fc owner k !(normaliseClosed (subst val sc)) vals'
       pure ((Q0, TypeParam val) :: rest, res)
     else if isErased rig
       then do
         (rest, res) <- classify fc owner k (subst (Erased bfc Placeholder) sc) vals'
         pure ((Q0, ErasedParam) :: rest, res)
       else do
         when (anyErased a') $
           reject fc owner "PROF-TYPE-4" "a parameter type that depends on another argument"
         t <- coreType fc owner a'
         (rest, res) <- classify fc owner k (subst (Erased bfc Placeholder) sc) vals'
         pure ((quantity rig, RuntimeParam t) :: rest, res)
classify fc owner (S k) ty _ = do
  ty' <- normaliseClosed ty
  case ty' of
    Bind {} => classify fc owner (S k) ty' []
    _ => reject fc owner "FE-TR-1" "more arguments than the type has binders"

------------------------------------------------------------------------------
-- Primitives
------------------------------------------------------------------------------

ioPrim : Name -> Maybe IOOp
ioPrim n = case show n of
  "IdrisMLIR.IO.prim__idrPutStr" => Just PutStr
  "IdrisMLIR.IO.prim__idrPutChar" => Just PutChar
  "IdrisMLIR.IO.prim__idrGetChar" => Just GetChar
  "IdrisMLIR.IO.prim__idrExit" => Just Exit
  _ => Nothing

scalarTy : PrimType -> Maybe Ty
scalarTy CharType = Just CharT
scalarTy t = IntT <$> intTy t

primOp : PrimFn arity -> Maybe PrimOp
primOp (Add t) = Add <$> intTy t
primOp (Sub t) = Sub <$> intTy t
primOp (Mul t) = Mul <$> intTy t
primOp (Div t) = Div <$> intTy t
primOp (Mod t) = Mod <$> intTy t
primOp (BAnd t) = And <$> intTy t
primOp (BOr t) = Or <$> intTy t
primOp (BXOr t) = Xor <$> intTy t
primOp (LT StringType) = Just (StrCompare "lt")
primOp (LTE StringType) = Just (StrCompare "lte")
primOp (EQ StringType) = Just (StrCompare "eq")
primOp (GTE StringType) = Just (StrCompare "gte")
primOp (GT StringType) = Just (StrCompare "gt")
primOp (LT t) = Lt <$> scalarTy t
primOp (LTE t) = Lte <$> scalarTy t
primOp (EQ t) = Eq <$> scalarTy t
primOp (GTE t) = Gte <$> scalarTy t
primOp (GT t) = Gt <$> scalarTy t
primOp (Cast from to) = [| Cast (castTy from) (castTy to) |]
  where
    castTy : PrimType -> Maybe Ty
    castTy StringType = Just StrT
    castTy t = scalarTy t
primOp StrLength = Just StrLength
primOp StrHead = Just StrHead
primOp StrTail = Just StrTail
primOp StrIndex = Just StrIndex
primOp StrCons = Just StrCons
primOp StrAppend = Just StrAppend
primOp StrReverse = Just StrReverse
primOp StrSubstr = Just StrSubstr
primOp _ = Nothing

------------------------------------------------------------------------------
-- Terms (FE-TR-3)
------------------------------------------------------------------------------

record Ctx where
  constructor MkCtx
  owner : String
  fc : FC

constantLit : Constant -> Maybe Lit
constantLit (I x) = Just (LInt IdrisInt (cast x))
constantLit (I8 x) = Just (LInt SInt8 (cast x))
constantLit (I16 x) = Just (LInt SInt16 (cast x))
constantLit (I32 x) = Just (LInt SInt32 (cast x))
constantLit (I64 x) = Just (LInt SInt64 (cast x))
constantLit (B8 x) = Just (LInt UInt8 (cast x))
constantLit (B16 x) = Just (LInt UInt16 (cast x))
constantLit (B32 x) = Just (LInt UInt32 (cast x))
constantLit (B64 x) = Just (LInt UInt64 (cast x))
constantLit (Ch x) = Just (LChar (cast (ord x)))
constantLit (Str x) = Just (LStr x)
constantLit _ = Nothing

bestFC : Ctx -> FC -> FC
bestFC ctx fc = if isEmptyFC fc then ctx.fc else fc

||| Eta-expands a known head applied to too few arguments: `\x.. => head(args ++ xs)`.
etaExpand : {auto s : Ref TState TS} -> Loc -> List (Quantity, Ty) ->
            (List Expr -> Expr) -> List Expr -> Core Expr
etaExpand loc missing mk args = do
  vars <- traverse (\_ => fresh) missing
  let body = mk (args ++ zipWith (\v, (q, _) => if q == Q0 then EErased loc else EVar loc v) vars missing)
  pure (foldr (\(v, (q, t)), b => ELam loc v q (if q == Q0 then ErasedT else t) b) body (zip vars missing))

mutual
  export
  term : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
         Ctx -> List VarInfo -> Term vars -> Core Expr
  term ctx env (Local fc _ idx _) = do
    loc <- toLoc (bestFC ctx fc)
    case getAt idx env of
      Just (Bound v _) => pure (EVar loc v)
      Just (TypeValue _) => pure (EErased loc)
      Nothing => reject (bestFC ctx fc) ctx.owner "FE-TR-3" "variable out of scope"
  term ctx env (PrimVal fc c) = do
    loc <- toLoc (bestFC ctx fc)
    case constantLit c of
      Just l => pure (ELit loc l)
      Nothing => case c of
        WorldVal => pure (EWorld loc)
        PrT _ => pure (EErased loc)
        _ => reject (bestFC ctx fc) ctx.owner "PROF-TYPE-4" ("constant " ++ show c)
  term ctx env (TType fc _) = EErased <$> toLoc (bestFC ctx fc)
  term ctx env (Erased fc _) = EErased <$> toLoc (bestFC ctx fc)
  term ctx env (Bind fc _ (Pi {}) _) = EErased <$> toLoc (bestFC ctx fc)
  term ctx env (Bind fc x (Let lfc rig val ty) sc) = do
    loc <- toLoc (bestFC ctx fc)
    v <- fresh
    if isErased rig
       then ELet loc v Q0 ErasedT (EErased loc) <$> term ctx (Bound v ErasedT :: env) sc
       else do
         -- TTC does not keep the types of lets (Core.TTC, `Let` binders):
         -- `letTypes` infers them from the values after translation.
         ty' <- closeNormalise fc env ty
         t <- case ty' of
                Erased _ _ => pure ErasedT
                _ => coreType (bestFC ctx fc) ctx.owner ty'
         val' <- term ctx env val
         ELet loc v (quantity rig) t val' <$> term ctx (Bound v t :: env) sc
  term ctx env (Bind fc x (Lam lfc rig _ ty) sc) = do
    loc <- toLoc (bestFC ctx fc)
    v <- fresh
    if isErased rig
       then ELam loc v Q0 ErasedT <$> term ctx (Bound v ErasedT :: env) sc
       else do
         t <- coreType (bestFC ctx fc) ctx.owner !(closeNormalise fc env ty)
         ELam loc v (quantity rig) t <$> term ctx (Bound v t :: env) sc
  term ctx env (TDelay fc LLazy _ arg) = EDelay <$> toLoc (bestFC ctx fc) <*> term ctx env arg
  term ctx env (TForce fc LLazy arg) = EForce <$> toLoc (bestFC ctx fc) <*> term ctx env arg
  term ctx env (TDelay fc LUnknown _ arg) = EDelay <$> toLoc (bestFC ctx fc) <*> term ctx env arg
  term ctx env (TForce fc LUnknown arg) = EForce <$> toLoc (bestFC ctx fc) <*> term ctx env arg
  term ctx env (TDelay fc _ _ _) = reject (bestFC ctx fc) ctx.owner "PROF-TYPE-4" "Inf (codata)"
  term ctx env (TForce fc _ _) = reject (bestFC ctx fc) ctx.owner "PROF-TYPE-4" "Inf (codata)"
  term ctx env (TDelayed fc _ _) = EErased <$> toLoc (bestFC ctx fc)
  term ctx env (Meta fc n _ _) = reject (bestFC ctx fc) ctx.owner "PROF-TERM-2" ("hole or metavariable " ++ show n)
  term ctx env (As fc _ _ pat) = term ctx env pat
  term ctx env tm@(App fc _ _) = let (fn, args) = spine tm [] in application ctx env fc fn args
  term ctx env tm@(Ref fc _ _) = application ctx env fc tm []
  term ctx env (Bind fc _ _ _) = reject (bestFC ctx fc) ctx.owner "FE-TR-3" "binder in a runtime position"

  application : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                Ctx -> List VarInfo -> FC -> Term vars -> List (Term vars) -> Core Expr
  application ctx env afc (Ref rfc nt n) args = do
    let fc = bestFC ctx rfc
    loc <- toLoc fc
    def <- lookupDef fc ctx.owner n
    let name = fullname def
    case definition def of
      PMDef _ params _ _ _ => call fc loc name (length params) (type def) args
      DCon tag arity _ => constructor fc loc def arity args
      TCon {} => pure (EErased loc)
      Builtin {arity} op => primitive fc loc name arity op args
      ForeignDef arity _ => case ioPrim name of
        Just op => ioCall fc loc arity op (type def) args
        Nothing => reject fc ctx.owner "PROF-ESC-1" ("foreign function " ++ show name)
      ExternDef _ => reject fc ctx.owner "PROF-ESC-1" ("extern function " ++ show name)
      Hole {} => reject fc ctx.owner "PROF-TERM-2" ("hole " ++ show name)
      _ => reject fc ctx.owner "FE-TR-3" ("reference to " ++ show name)
    where
      -- Arguments: values of type parameters, erased ones, runtime ones.
      arguments : FC -> Loc -> List (Quantity, PKind) -> List (Term vars) -> Core (List Expr)
      arguments fc loc kinds as = traverse arg (zip kinds as)
        where
          arg : ((Quantity, PKind), Term vars) -> Core Expr
          arg ((_, RuntimeParam _), a) = term ctx env a
          arg _ = pure (EErased loc)

      typeArgValues : List (Term vars) -> Core (List (Maybe ClosedTerm))
      typeArgValues = traverse (\a => Just <$> closeNormalise afc env a)

      applyRest : Loc -> Expr -> List (Term vars) -> Core Expr
      applyRest loc f [] = pure f
      applyRest loc f (a :: as) = applyRest loc (EApp loc f !(term ctx env a)) as

      finish : Loc -> List (Quantity, PKind) -> List Expr -> (List Expr -> Expr) ->
               List (Term vars) -> Core Expr
      finish loc kinds given mk extra = do
        let missing = drop (length given) kinds
        if null missing
           then applyRest loc (mk given) extra
           else do
             when (any isTypeParam missing) $
               reject afc ctx.owner "PROF-FN-7" "a partially applied type parameter"
             etaExpand loc (map kindTy missing) mk given
        where
          isTypeParam : (Quantity, PKind) -> Bool
          isTypeParam (_, TypeParam _) = True
          isTypeParam _ = False
          kindTy : (Quantity, PKind) -> (Quantity, Ty)
          kindTy (q, RuntimeParam t) = (q, t)
          kindTy (q, _) = (Q0, ErasedT)

      call : FC -> Loc -> Name -> Nat -> ClosedTerm -> List (Term vars) -> Core Expr
      call fc loc name arity ty as = do
        vals <- typeArgValues (take arity as)
        (kinds, _) <- classify fc ctx.owner arity ty vals
        let targs = mapMaybe (\k => case k of
                                      (_, TypeParam t) => Just t
                                      _ => Nothing) kinds
        inst <- request name targs
        given <- arguments fc loc kinds (take arity as)
        finish loc kinds given (ECall loc inst) (drop arity as)

      constructor : FC -> Loc -> GlobalDef -> Nat -> List (Term vars) -> Core Expr
      constructor fc loc def arity as = do
        vals <- typeArgValues (take arity as)
        (kinds, resTy) <- classify fc ctx.owner arity (type def) vals
        DataT inst <- coreType fc ctx.owner !(normaliseClosed resTy)
          | _ => reject fc ctx.owner "FE-TR-3" "constructor of a non-data type"
        given <- arguments fc loc kinds (take arity as)
        -- Parameters are not fields: drop the type parameters' positions.
        let fieldArgs = map snd (filter (not . isParam . fst) (zip kinds given))
        finish loc (filter (not . isParam) kinds) fieldArgs
               (ECon loc inst (show (fullname def))) (drop arity as)
        where
          isParam : (Quantity, PKind) -> Bool
          isParam (_, TypeParam _) = True
          isParam _ = False

      primitive : FC -> Loc -> Name -> Nat -> PrimFn ar -> List (Term vars) -> Core Expr
      primitive fc loc name arity op as = case op of
        BelieveMe => reject fc ctx.owner "PROF-ESC-1" "believe_me"
        Crash => reject fc ctx.owner "PROF-ESC-1" "idris_crash"
        Neg _ => reject fc ctx.owner "PROF-PRIM-2" "negate (SEM-EXCL-1)"
        ShiftL _ => reject fc ctx.owner "PROF-PRIM-2" "shift left (SEM-EXCL-1)"
        ShiftR _ => reject fc ctx.owner "PROF-PRIM-2" "shift right (SEM-EXCL-1)"
        _ => case primOp op of
          Nothing => reject fc ctx.owner "PROF-PRIM-2" ("primitive " ++ show name)
          Just p => do
            args' <- traverse (term ctx env) (take arity as)
            let kinds = replicate arity (QW, RuntimeParam (argTy p))
            finish loc kinds args' (EPrim loc p) (drop arity as)
        where
          argTy : PrimOp -> Ty
          argTy (Add t) = IntT t
          argTy (Sub t) = IntT t
          argTy (Mul t) = IntT t
          argTy (Div t) = IntT t
          argTy (Mod t) = IntT t
          argTy (And t) = IntT t
          argTy (Or t) = IntT t
          argTy (Xor t) = IntT t
          argTy (Lt t) = t
          argTy (Lte t) = t
          argTy (Eq t) = t
          argTy (Gte t) = t
          argTy (Gt t) = t
          argTy (Cast f _) = f
          argTy _ = StrT

      ioCall : FC -> Loc -> Nat -> IOOp -> ClosedTerm -> List (Term vars) -> Core Expr
      ioCall fc loc arity op ty as = do
        (kinds, resTy) <- classify fc ctx.owner arity ty []
        DataT res <- coreType fc ctx.owner !(normaliseClosed resTy)
          | _ => reject fc ctx.owner "FE-TR-3" "IO primitive with an unexpected type"
        given <- arguments fc loc kinds (take arity as)
        finish loc kinds given (\xs => EIO loc op xs res) (drop arity as)
  application ctx env afc fn args = do
    loc <- toLoc (bestFC ctx afc)
    f <- term ctx env fn
    applyAll loc f args
    where
      applyAll : Loc -> Expr -> List (Term vars) -> Core Expr
      applyAll loc f [] = pure f
      applyAll loc f (a :: as) = applyAll loc (EApp loc f !(term ctx env a)) as

------------------------------------------------------------------------------
-- Case trees (FE-TR-4)
------------------------------------------------------------------------------

mutual
  tree : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
         Ctx -> List VarInfo -> CaseTree vars -> Core Expr
  tree ctx env (STerm _ tm) = term ctx env tm
  tree ctx env (Unmatched msg) =
    reject ctx.fc ctx.owner "PROF-TERM-2" ("a partial match (" ++ msg ++ ")")
  tree ctx env Impossible = reject ctx.fc ctx.owner "FE-TR-4" "an impossible case in a runtime position"
  tree ctx env (Case idx _ scTy alts) = do
    loc <- toLoc ctx.fc
    case getAt idx env of
      Just (Bound v (DataT inst)) => do
        (conAlts, def) <- conAlternatives ctx env inst alts
        pure (EMatchCon loc v conAlts def)
      Just (Bound v WorldT) => case alts of
        [ConstCase WorldVal rhs] => tree ctx env rhs
        _ => reject ctx.fc ctx.owner "FE-TR-4" "an unexpected match on the world"
      Just (Bound v t) => do
        (litAlts, def) <- litAlternatives ctx env t alts
        let Just def = def
          | Nothing => reject ctx.fc ctx.owner "PROF-FN-5" "a literal match without a default"
        pure (EMatchLit loc v litAlts def)
      _ => reject ctx.fc ctx.owner "FE-TR-4" "a match on a compile-time value"

  conAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                    Ctx -> List VarInfo -> String -> List (CaseAlt vars) ->
                    Core (List ConAlt, Maybe Expr)
  conAlternatives ctx env inst [] = pure ([], Nothing)
  conAlternatives ctx env inst (ConCase n _ args Impossible :: rest) =
    conAlternatives ctx env inst rest
  conAlternatives ctx env inst (ConCase n _ args rhs :: rest) = do
    def <- lookupDef ctx.fc ctx.owner n
    let cname = show (fullname def)
    st <- get TState
    let Just info = lookup (inst ++ "::" ++ cname) st.cons
      | Nothing => reject ctx.fc ctx.owner "FE-TR-4" ("unknown constructor " ++ cname ++ " of " ++ inst)
    let nparams = length info.params
    fieldVars <- traverse (\_ => fresh) info.core.fields
    let paramInfo = map TypeValue info.params
    let fieldInfo = zipWith (\v, f => Bound v f.type) fieldVars info.core.fields
    let bound = paramInfo ++ fieldInfo
    when (length bound /= length args) $
      reject ctx.fc ctx.owner "FE-TTC-1" ("constructor " ++ cname ++ " binds an unexpected number of arguments")
    body <- tree ctx (bound ++ env) rhs
    (alts, def') <- conAlternatives ctx env inst rest
    pure (MkConAlt cname fieldVars body :: alts, def')
  conAlternatives ctx env inst (DefaultCase rhs :: _) = pure ([], Just !(tree ctx env rhs))
  conAlternatives ctx env inst (DelayCase {} :: _) =
    reject ctx.fc ctx.owner "PROF-TERM-2" "a match on a lazy value"
  conAlternatives ctx env inst (ConstCase {} :: _) =
    reject ctx.fc ctx.owner "FE-TR-4" "a constant alternative in a constructor match"

  litAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                    Ctx -> List VarInfo -> Ty -> List (CaseAlt vars) ->
                    Core (List (Lit, Expr), Maybe Expr)
  litAlternatives ctx env t [] = pure ([], Nothing)
  litAlternatives ctx env t (ConstCase c rhs :: rest) = do
    Just lit <- pure (constantLit c)
      | Nothing => reject ctx.fc ctx.owner "PROF-PRIM-4" ("a match on " ++ show c)
    case lit of
      LStr _ => reject ctx.fc ctx.owner "PROF-PRIM-4" "a match on a string"
      _ => pure ()
    body <- tree ctx env rhs
    (alts, def) <- litAlternatives ctx env t rest
    pure ((lit, body) :: alts, def)
  litAlternatives ctx env t (DefaultCase rhs :: _) = pure ([], Just !(tree ctx env rhs))
  litAlternatives ctx env t _ = reject ctx.fc ctx.owner "FE-TR-4" "an unexpected alternative"

------------------------------------------------------------------------------
-- Function instances and programs
------------------------------------------------------------------------------

isTotal : {auto c : Ref Ctxt Defs} -> FC -> Name -> Core Bool
isTotal fc n = do
  t <- catch (checkTotal fc n) (\_ => pure Unchecked)
  pure (case t of
          IsTerminating => True
          _ => False)

||| Translates one function instance (FE-TR-*).
translateInstance : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Pending -> Core ()
translateInstance p = do
  def <- lookupDef EmptyFC (show p.name) p.name
  let owner = show (fullname def)
  let fc = location def
  PMDef _ args treeCT _ _ <- pure (definition def)
    | _ => reject fc owner "PROF-FN-1" "not a pattern-matching definition"
  -- PROF-FN-5: the definition's own patterns are covering. Calls to partial
  -- functions are allowed: dividing by zero is a defined crash (SEM-INT-4),
  -- and a callee with missing cases is rejected on its own.
  case isCovering (totality def) of
    MissingCases _ => reject fc owner "PROF-FN-5" "a definition with missing cases"
    _ => pure ()
  (kinds, resTy) <- classify fc owner (length args) (type def) (map Just p.typeArgs)
  result <- coreType fc owner !(normaliseClosed resTy)
  vars <- traverse (\_ => fresh) kinds
  let params = zipWith param vars kinds
  let env = zipWith info vars kinds
  body <- tree (MkCtx owner fc) env treeCT
  loc <- toLoc fc
  tot <- isTotal fc p.name
  update TState { fns $= insert p.instName (MkFn p.instName owner params result body loc tot)
                , fnOrder $= (:< p.instName) }
  where
    param : Var -> (Quantity, PKind) -> Param
    param v (q, RuntimeParam t) = MkParam v q t
    param v _ = MkParam v Q0 ErasedT
    info : Var -> (Quantity, PKind) -> VarInfo
    info v (_, TypeParam t) = TypeValue t
    info v (_, RuntimeParam t) = Bound v t
    info v _ = Bound v ErasedT

drain : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Core ()
drain = do
  st <- get TState
  case st.queue of
    [] => pure ()
    (p :: rest) => do
      put TState ({ queue := rest } st)
      translateInstance p
      drain

||| The types of runtime lets that TTC did not keep (marked `ErasedT` at a
||| runtime quantity, which no runtime let has otherwise), from their values.
letTypes : Program -> Fn -> Maybe Fn
letTypes prog fn = do
  body <- go (map (\p => (p.var, p.type)) fn.params) fn.body
  pure ({ body := body } fn)
  where
    go : List (Var, Ty) -> Expr -> Maybe Expr
    go env (ELet l x q t v b) = do
      v' <- go env v
      t' <- if q /= Q0 && t == ErasedT then typeOf prog env v' else Just t
      ELet l x q t' v' <$> go ((x, t') :: env) b
    go env (EMatchCon l x alts d) = do
      alts' <- traverse alt alts
      EMatchCon l x alts' <$> traverse (go env) d
      where
        alt : ConAlt -> Maybe ConAlt
        alt (MkConAlt c xs e) = do
          DataT dn <- lookup x env
            | _ => Nothing
          con <- lookupCon dn c prog
          MkConAlt c xs <$> go (zip xs (map (.type) con.fields) ++ env) e
    go env (EMatchLit l x alts d) =
      EMatchLit l x <$> traverse (\(k, e) => (k,) <$> go env e) alts <*> go env d
    go env (ELam l x q t b) = ELam l x q t <$> go ((x, t) :: env) b
    go env (EApp l f a) = EApp l <$> go env f <*> go env a
    go env (EDelay l e) = EDelay l <$> go env e
    go env (EForce l e) = EForce l <$> go env e
    go env (EPrim l op as) = EPrim l op <$> traverse (go env) as
    go env (EIO l op as r) = (\as' => EIO l op as' r) <$> traverse (go env) as
    go env (ECall l f as) = ECall l f <$> traverse (go env) as
    go env (ECon l d c as) = ECon l d c <$> traverse (go env) as
    go env e = Just e

assemble : {auto s : Ref TState TS} -> String -> EntryKind -> Core Program
assemble root entry = do
  st <- get TState
  let datas = mapMaybe (\n => lookup n st.datas) (st.dataOrder <>> [])
  let fns = mapMaybe (\n => lookup n st.fns) (st.fnOrder <>> [])
  let prog = MkProgram datas fns root entry 0
  case the (Maybe (List Fn)) (traverse (letTypes prog) fns) of
    Just fns' => pure ({ fns := fns' } prog)
    Nothing => throw (GenericMsg EmptyFC "mlir backend: internal error: the type of a let could not be inferred")

||| A `main : Int` program (FE-ENTRY-2): the root is `main` itself.
export
translateIntProgram : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Name -> Core Program
translateIntProgram main = do
  root <- request main []
  drain
  assemble root IntEntry

||| An IO program (FE-ENTRY-4). The root is `unsafePerformIO main` written
||| directly as world-passing code, which is what `unsafePerformIO`,
||| `unsafeCreateWorld` and `unsafeDestroyWorld` mean:
|||   root w = case main of MkIO f => case f w of MkIORes res w' => res
||| So `%MkWorld` never appears (PROF-IO-3).
export
translateIOProgram : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                     FC -> Name -> Core Program
translateIOProgram fc main = do
  inst <- request main []
  drain
  st <- get TState
  let owner = show main
  let Just mainFn = lookup inst st.fns
    | Nothing => reject fc owner "FE-ENTRY-4" "main was not translated"
  let DataT ioInst = mainFn.result
    | _ => reject fc owner "PROF-PROG-4" "main must have type IO ()"
  let Just ioData = lookup ioInst st.datas
    | Nothing => reject fc owner "PROF-PROG-4" "main must have type IO ()"
  let [mkIO] = ioData.cons
    | _ => reject fc owner "PROF-PROG-4" "main must have type IO ()"
  let [MkField _ (FunT _ WorldT (DataT resInst))] = mkIO.fields
    | _ => reject fc owner "PROF-PROG-4" "main must have type IO ()"
  let Just resData = lookup resInst st.datas
    | Nothing => reject fc owner "PROF-PROG-4" "main must have type IO ()"
  let [mkRes] = resData.cons
    | _ => reject fc owner "PROF-PROG-4" "main must have type IO ()"
  let [MkField _ resTy, MkField _ WorldT] = mkRes.fields
    | _ => reject fc owner "PROF-PROG-4" "main must have type IO ()"
  loc <- toLoc (location !(lookupDef fc owner main))
  w <- fresh
  m <- fresh
  f <- fresh
  r <- fresh
  x <- fresh
  w2 <- fresh
  let body = ELet loc m QW (DataT ioInst) (ECall loc inst [])
               (EMatchCon loc m
                 [MkConAlt mkIO.name [f]
                    (ELet loc r QW (DataT resInst) (EApp loc (EVar loc f) (EVar loc w))
                       (EMatchCon loc r [MkConAlt mkRes.name [x, w2] (EVar loc x)] Nothing))]
                 Nothing)
  let rootName = "$idris-mlir.root"
  prog <- assemble rootName IOEntry
  pure ({ fns $= (++ [MkFn rootName rootName [MkParam w Q1 WorldT] resTy body loc True]) } prog)
