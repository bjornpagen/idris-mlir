||| Checked TT to full Core (docs/architecture/04-frontend.md). Reads compile-time
||| case trees (`treeCT`) and types; monomorphises on demand (ELIM-MONO-*), with
||| Idris's own normalizer doing all type-level computation.
|||
||| Scopes carry over from TT: a TT term in scope `vars` becomes a `Term a`,
||| with an environment saying what each TT variable stands for. A TT index
||| is a position in that environment; type arguments have no Core variable.
module IdrisMLIR.Frontend.Translate

import Core.Case.CaseTree
import Core.CompileExpr
import Core.Context
import Core.Core
import Core.Directory
import Core.Env
import Core.Normalise
import Core.TT
import Core.Termination
import Libraries.Data.NameMap
import Libraries.Data.NatSet

import IdrisMLIR.Facts
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Graph
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Registry
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Rule
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.Fin
import Data.List
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.String
import Data.Vect

%default covering

||| Idris's terms and binders; `Term` and `Binder` are Core's own.
TT : Scope -> Type
TT = Core.TT.Term.Term

TTBinder : Type -> Type
TTBinder = Core.TT.Binder.Binder

------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------

||| A function instance waiting to be translated (ELIM-MONO-1).
record Pending where
  constructor MkPending
  name : Name
  inst : FnId
  ||| The compile-time arguments, by position (ELIM-MONO-1).
  statics : List (Maybe ClosedTerm)
  ||| The instances that requested this one, innermost first, with the size
  ||| of their keys (ELIM-MONO-3).
  path : List (String, String)

||| What a constructor instance needs for case trees.
record ConLayout where
  constructor MkConLayout
  params : List ClosedTerm   -- the data instance's type arguments
  ||| For each argument of the constructor, in order: the position of the
  ||| data type's parameter it is, or `Nothing` for a field. Idris does not
  ||| put the parameters first (`(::) : {0 len} -> {0 elem} -> ...`).
  layout : List (Maybe Nat)
  con : Con

export
data TState : Type where

||| A data instance as it is registered. Its representation is decided once
||| every instance is known (`assemble`): a box exactly when its
||| containment is recursive.
record Decl where
  constructor MkDecl
  id : DataId
  idrisName : Shown
  cons : List Con
  loc : Loc

export
record TS where
  constructor MkTS
  nextLabel : Nat
  datas : SortedMap DataId Decl
  dataOrder : SnocList DataId
  ||| The instances being registered, which a field may refer to.
  building : SortedSet DataId
  cons : SortedMap ConId ConLayout
  fns : SortedMap FnId TFn
  fnOrder : SnocList FnId
  seen : SortedSet FnId
  queue : List Pending
  moduleFC : FC
  current : List (String, String)     -- the path of the instance being translated
  perName : SortedMap String Nat      -- instances per definition (ELIM-MONO-3)
  ||| Who owns each instance name: names are injective (ELIM-MONO-4), and
  ||| a printed form that two instances share is told apart here.
  owners : SortedMap String (List (Name, List (Maybe ClosedTerm)))
  ||| The instances of each definition by their arguments, up to the names
  ||| of binders: `(x : a) -> b` and `a -> b` are one type (ELIM-MONO-4).
  named : SortedMap String (List (List (Maybe ClosedTerm), String))

export
initState : FC -> TS
initState fc = MkTS 0 empty [<] empty empty empty [<] empty [] fc [] empty empty empty

||| A fresh program point for a lambda or `Delay`.
label : {auto s : Ref TState TS} -> Core Label
label = do
  st <- get TState
  put TState ({ nextLabel $= S } st)
  pure (MkLabel st.nextLabel)

------------------------------------------------------------------------------
-- Errors and locations
------------------------------------------------------------------------------

isEmptyFC : FC -> Bool
isEmptyFC EmptyFC = True
isEmptyFC _ = False

||| DIAG-FMT-1, DIAG-LOC-1: never an empty location.
export
reject : {auto s : Ref TState TS} -> FC -> String -> Rule -> String -> Core a
reject fc owner rule what = do
  st <- get TState
  let fc' = if isEmptyFC fc then st.moduleFC else fc
  throw (GenericMsg fc' ("mlir backend: " ++ owner ++ ": unsupported (" ++ show rule ++ "): " ++ what))

||| DIAG-ICE-1
export
internal : FC -> String -> Core a
internal fc msg = throw (GenericMsg fc ("mlir backend: internal error: " ++ msg))

||| An Idris location as a Core location, with the source file resolved and
||| the origin the registry gives its module. A package file is in no module.
export
toLoc : {auto c : Ref Ctxt Defs} -> FC -> Core Loc
toLoc fc@(MkFC (PhysicalIdrSrc ident) (sl, sc) (el, ec)) = do
  file <- catch (nsToSource fc ident) (\_ => pure "")
  pure (MkLoc (originOf ident) (shown (show ident)) file sl sc el ec)
toLoc (MkFC (PhysicalPkgSrc file) (sl, sc) (el, ec)) = pure (MkLoc Generated (shown "") file sl sc el ec)
toLoc (MkVirtualFC (PhysicalIdrSrc ident) (sl, sc) (el, ec)) =
  toLoc (MkFC (PhysicalIdrSrc ident) (sl, sc) (el, ec))
toLoc _ = pure noLoc

||| A Core location as an Idris location, for errors raised after
||| translation: the module is the one Idris named.
export
fromLoc : Loc -> FC
fromLoc l = case l.origin of
  Generated => if l.file == "" then EmptyFC else MkFC (PhysicalPkgSrc l.file) start end
  _ => MkFC (PhysicalIdrSrc (nsAsModuleIdent (mkNamespace (show l.place)))) start end
  where
    start : FilePos
    start = (l.startLine, l.startCol)
    end : FilePos
    end = (l.endLine, l.endCol)

------------------------------------------------------------------------------
-- Terms as closed values
------------------------------------------------------------------------------

||| What a TT variable stands for: a Core variable (with its type, when a
||| match may need it), a type argument's value, or an implementation's value.
||| Types and implementations are compile-time values, closed TT terms: types
||| are erased at runtime, and an implementation is used by translating it
||| where it is needed (FE-TR-6).
data VarInfo : Type -> Type where
  Runtime : a -> Maybe Ty -> VarInfo a
  TypeValue : ClosedTerm -> VarInfo a
  Static : ClosedTerm -> VarInfo a

Functor VarInfo where
  map f (Runtime x t) = Runtime (f x) t
  map f (TypeValue t) = TypeValue t
  map f (Static t) = Static t

||| An environment under a binder of `k` variables, which come first.
under : List (VarInfo (Under k a)) -> List (VarInfo a) -> List (VarInfo (Under k a))
under bound env = bound ++ map (map Free) env

||| Does the term mention `Erased` for the given reason?
anyErasedAs : (WhyErased (TT vars) -> Bool) -> TT vars -> Bool
anyErasedAs p tm = go tm
  where
    go : TT vs -> Bool
    go (Erased _ w) = case w of
      Placeholder => p Placeholder
      Impossible => p Impossible
      Dotted _ => False
    go (Bind _ _ b sc) = go (binderType b) || binderVal b || go sc
      where
        binderVal : TTBinder (TT ws) -> Bool
        binderVal (Let _ _ v _) = go v
        binderVal (PLet _ _ v _) = go v
        binderVal _ = False
    go (App _ f a) = go f || go a
    go (As _ _ a q) = go q
    go (TDelayed _ _ t) = go t
    go (TDelay _ _ t a) = go t || go a
    go (TForce _ _ t) = go t
    go (Meta _ _ _ args) = any go args
    go _ = False

||| Does the term mention `Erased` (a placeholder for an unknown value)?
anyErased : TT vars -> Bool
anyErased (Erased _ _) = True
anyErased (Bind _ _ b sc) = anyErased (binderType b) || binderVal b || anyErased sc
  where
    binderVal : TTBinder (TT vs) -> Bool
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
wrapLams : {vars : Scope} -> FC -> TT vars -> ClosedTerm
wrapLams {vars = []} fc tm = tm
wrapLams {vars = x :: rest} fc tm =
  wrapLams {vars = rest} fc (Bind fc x (Lam fc top Explicit (Erased fc Placeholder)) tm)

||| The closed normal form of a term in scope, with type variables replaced by
||| their known values and every other variable by `Erased`.
closeNormalise : {auto c : Ref Ctxt Defs} -> {vars : Scope} ->
                 FC -> List (VarInfo a) -> TT vars -> Core ClosedTerm
closeNormalise fc env tm = do
  let closed = foldl (App fc) (wrapLams fc tm) (reverse (map value env))
  defs <- get Ctxt
  normalise defs [] closed
  where
    value : VarInfo a -> ClosedTerm
    value (TypeValue t) = t
    value (Static t) = t
    value (Runtime _ _) = Erased fc Placeholder

||| A closed term in any scope.
embedClosed : {vars : Scope} -> ClosedTerm -> TT vars
embedClosed t = embed {outer = vars} t

||| Beta-reduces a closed lambda with its arguments, by substitution.
betaAll : ClosedTerm -> List ClosedTerm -> ClosedTerm
betaAll (Bind _ _ (Lam _ _ _ _) sc) (v :: vs) = betaAll (subst v sc) vs
betaAll tm vs = foldl (App EmptyFC) tm vs

||| Substitutes the outer `let`s of a closed term. Idris elaborates a record
||| update to a `let` of the record around its fields, so an implementation
||| resolved inside it is written under a `let` it does not use.
zeta : ClosedTerm -> ClosedTerm
zeta (Bind _ _ (Let _ _ v _) sc) = zeta (subst v sc)
zeta tm = tm

||| A term in scope as a closed term, with compile-time values substituted
||| and not normalised, so that an implementation keeps its written form. A
||| runtime variable becomes `Erased` with reason `Impossible`, which
||| `runtimeDependent` detects.
closeWritten : {vars : Scope} -> FC -> List (VarInfo a) -> TT vars -> ClosedTerm
closeWritten fc env tm = zeta (betaAll (wrapLams fc tm) (reverse (map value env)))
  where
    value : VarInfo a -> ClosedTerm
    value (TypeValue t) = t
    value (Static t) = t
    -- A quantity-0 variable (a length, a proof) is not a runtime value: an
    -- implementation that mentions it (`Foldable (Vect n)`) does not
    -- depend on anything at runtime.
    value (Runtime _ (Just ErasedT)) = Erased fc Placeholder
    value (Runtime _ _) = Erased fc Impossible

||| Does a term mention a metavariable? Idris can leave a solved one in an
||| elaborated term (the implementation for the inner pair of a triple).
hasMeta : TT vars -> Bool
hasMeta (Meta {}) = True
hasMeta (Bind _ _ b sc) = hasMeta (binderType b) || binderVal b || hasMeta sc
  where
    binderVal : TTBinder (TT vars) -> Bool
    binderVal (Let _ _ v _) = hasMeta v
    binderVal (PLet _ _ v _) = hasMeta v
    binderVal _ = False
hasMeta (App _ f a) = hasMeta f || hasMeta a
hasMeta (As _ _ a p) = hasMeta p
hasMeta (TDelayed _ _ t) = hasMeta t
hasMeta (TDelay _ _ t a) = hasMeta t || hasMeta a
hasMeta (TForce _ _ t) = hasMeta t
hasMeta _ = False

||| A written form with the solutions of its metavariables filled in, and
||| nothing else evaluated (FE-TR-6).
solved : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core ClosedTerm
solved tm =
  if hasMeta tm
     then do
       defs <- get Ctxt
       normaliseHoles defs [] tm
     else pure tm

runtimeDependent : ClosedTerm -> Bool
runtimeDependent = anyErasedAs (\w => case w of
                                        Impossible => True
                                        _ => False)

normaliseClosed : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core ClosedTerm
normaliseClosed tm = do
  defs <- get Ctxt
  normalise defs [] tm

||| The constructor a compile-time value reduces to, with its arguments. An
||| implementation is a definition with one right-hand side, so it is
||| unfolded by substituting its arguments, keeping the rest as written;
||| anything else goes to Idris's normaliser.
whnf : {auto c : Ref Ctxt Defs} -> Nat -> ClosedTerm -> Core (Maybe (Name, List ClosedTerm))
whnf Z tm = pure Nothing
whnf (S fuel) tm = case spineC tm [] of
  (Ref _ (DataCon _ _) n, args) => pure (Just (n, args))
  (Ref _ _ n, args) => do
    defs <- get Ctxt
    Just def <- lookupCtxtExact n (gamma defs)
      | Nothing => pure Nothing
    case definition def of
      PMDef _ pargs (STerm _ body) _ _ =>
        if length args < length pargs then pure Nothing
        else whnf fuel (betaAll (betaAll (wrapLams EmptyFC body) (reverse (take (length pargs) args)))
                                (drop (length pargs) args))
      _ => normalised
  (Bind _ _ (Lam _ _ _ _) sc, a :: as) => whnf fuel (betaAll (subst a sc) as)
  (Bind _ _ (Let _ _ v _) sc, []) => whnf fuel (subst v sc)
  _ => normalised
  where
    spineC : ClosedTerm -> List ClosedTerm -> (ClosedTerm, List ClosedTerm)
    spineC (App _ f a) as = spineC f (a :: as)
    spineC f as = (f, as)
    normalised : Core (Maybe (Name, List ClosedTerm))
    normalised = do
      defs <- get Ctxt
      tm' <- normalise defs [] tm
      pure (case spineC tm' [] of
              (Ref _ (DataCon _ _) n, args) => Just (n, args)
              _ => Nothing)

||| Which arguments of a constructor are erased, by position.
erasedArgs : {auto c : Ref Ctxt Defs} -> Name -> Core (List Bool)
erasedArgs n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => pure []
  pure (go (type def))
  where
    go : TT vs -> List Bool
    go (Bind _ _ (Pi _ rig _ _) sc) = isErased rig :: go sc
    go _ = []

showTT : ClosedTerm -> String
showTT = show

spine : TT vars -> List (TT vars) -> (TT vars, List (TT vars))
spine (App _ fn arg) args = spine fn (arg :: args)
spine fn args = (fn, args)

||| A type-level parameter: its type is a universe, possibly after Pi binders.
isTypeLike : ClosedTerm -> Bool
isTypeLike (TType _ _) = True
isTypeLike (Bind _ _ (Pi _ _ _ _) sc) = typeLikeScope sc
  where
    typeLikeScope : TT vs -> Bool
    typeLikeScope (TType _ _) = True
    typeLikeScope (Bind _ _ (Pi _ _ _ _) s) = typeLikeScope s
    typeLikeScope _ = False
isTypeLike _ = False

lookupDef : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            FC -> String -> Name -> Core GlobalDef
lookupDef fc owner n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => reject fc owner FeTtc1 ("missing definition " ++ show n)
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

||| A full name, printed so that different names print differently: Idris's
||| `show` prints only the display part of a `DN` and leaves out the index of
||| a case or with block.
nameKey : Name -> String
nameKey (NS ns n) = show (NS ns (UN (Basic (nameKey n))))
nameKey (DN str n) = str ++ "{" ++ nameKey n ++ "}"
nameKey (CaseBlock outer i) = "case block " ++ show i ++ " in " ++ outer
nameKey (WithBlock outer i) = "with block " ++ show i ++ " in " ++ outer
nameKey n = show n

||| ELIM-MONO-4: the definition's full name and its arguments' normal forms.
||| The printed form is made unique by a suffix if a different instance
||| already prints the same way.
instanceName : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               Name -> List (Maybe ClosedTerm) -> Core String
instanceName n args = do
  n' <- toFullNames n
  args' <- traverse (\a => case a of
                             Just t => Just <$> toFullNames t
                             Nothing => pure Nothing) args
  let shown = map showTT (catMaybes args')
  let printed = nameKey n' ++ (if null shown then "" else "[" ++ joinBy ", " shown ++ "]")
  st <- get TState
  let same = fromMaybe [] (lookup (nameKey n') st.named)
  case find ((== args') . fst) same of
    Just (_, name) => pure name
    Nothing => do
      let owners = fromMaybe [] (lookup printed st.owners)
      let name = suffixed printed (length owners)
      put TState ({ owners $= insert printed (owners ++ [(n', args')])
                  , named $= insert (nameKey n') ((args', name) :: same) } st)
      pure name
  where
    suffixed : String -> Nat -> String
    suffixed p Z = p
    suffixed p k = p ++ "'" ++ show k

||| A stand-in for the `i`th binder of a constructor's type.
marker : Nat -> ClosedTerm
marker i = Ref EmptyFC Bound (MN "idris-mlir-binder" (cast i))

||| Which arguments of a constructor are the data type's parameters: each
||| binder of its type is replaced by a marker, and the markers found at the
||| parameter positions of the return type name them.
paramLayout : List Nat -> ClosedTerm -> List (Maybe Nat)
paramLayout params ty =
  let (n, ret) = markAll 0 ty
      args = snd (spine ret [])
      found = mapMaybe (\p => (,p) <$> (getAt p args >>= markerOf)) params
  in map (\i => lookup i found) (upto n)
  where
    upto : Nat -> List Nat
    upto Z = []
    upto (S k) = upto k ++ [k]
    markAll : Nat -> ClosedTerm -> (Nat, ClosedTerm)
    markAll i (Bind _ _ (Pi {}) sc) = markAll (S i) (subst (marker i) sc)
    markAll i t = (i, t)
    markerOf : ClosedTerm -> Maybe Nat
    markerOf (Ref _ _ (MN "idris-mlir-binder" k)) = Just (cast k)
    markerOf _ = Nothing

||| The positions of a type constructor's arguments that are types: its
||| parameters whose kind is a universe. Only they tell instances apart;
||| every other argument (an index, or a value parameter such as `Equal`'s
||| `x`) is compile-time information (SEM-IDX-1).
typeParams : {auto c : Ref Ctxt Defs} -> GlobalDef -> Core (List Nat)
typeParams def = case definition def of
  TCon arity params _ _ _ _ _ => do
    defs <- get Ctxt
    -- A record's parameter kinds may be solved metavariables.
    ty <- normaliseHoles defs [] (type def)
    let values = kinds ty
    pure (filter (\i => elem i params && not (fromMaybe False (getAt i values))) [0 .. minus arity 1])
  _ => pure []
  where
    -- Is a kind certainly the type of values, not a universe: a variable
    -- (`x : a`) or a data type (`n : Nat`)?
    valueKind : TT vs -> Bool
    valueKind (Local {}) = True
    valueKind tm = case spine tm [] of
      (Ref _ (TyCon _) _, _) => True
      (PrimVal _ _, _) => True
      _ => False
    kinds : TT vs -> List Bool
    kinds (Bind _ _ (Pi _ _ _ a) sc) = valueKind a :: kinds sc
    kinds _ = []

||| The type arguments of a type constructor, and its arity.
paramPositions : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 String -> Name -> Core (Maybe (Nat, List Nat))
paramPositions owner n = do
  def <- lookupDef EmptyFC owner n
  case definition def of
    TCon arity _ _ _ _ _ _ => pure (Just (arity, !(typeParams def)))
    _ => pure Nothing

||| Does a type mention an erased value other than as an index of an
||| inductive family? Indices exist at compile time only ("Inductive families
||| need not store their indices", Brady, McBride and McKinna, 2003).
erasedOutsideIndices : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                       String -> ClosedTerm -> Core Bool
erasedOutsideIndices owner (Bind bfc _ (Pi _ _ _ a) sc) = do
  -- The argument is erased in the result: a dependency on it is one on an
  -- erased value, unless it is only an index.
  inA <- erasedOutsideIndices owner a
  inB <- erasedOutsideIndices owner (subst (Erased bfc Placeholder) sc)
  pure (inA || inB)
erasedOutsideIndices owner tm = case spine tm [] of
  (Ref _ (TyCon _) n, args) => do
    Just (_, ps) <- paramPositions owner n
      | Nothing => pure (anyErased tm)
    rs <- traverse (erasedOutsideIndices owner) (mapMaybe (\p => getAt p args) ps)
    pure (any id rs)
  _ => pure (anyErased tm)

||| The arguments of a constructor application that are fields, by layout.
fieldsOnly : List (Maybe Nat) -> List a -> List a
fieldsOnly layout xs = go layout xs
  where
    go : List (Maybe Nat) -> List a -> List a
    go (Just _ :: ls) (_ :: ys) = go ls ys
    go (Nothing :: ls) (y :: ys) = y :: go ls ys
    go [] ys = ys
    go _ [] = []

||| The variables a constructor alternative binds, in argument order:
||| parameters are type values, fields are the alternative's binders.
arrange : List (Maybe Nat) -> List ClosedTerm -> List (VarInfo a) -> List (VarInfo a)
arrange [] ps fs = []
arrange (Just p :: ls) ps fs = TypeValue (fromMaybe (Erased EmptyFC Placeholder) (getAt p ps)) :: arrange ls ps fs
arrange (Nothing :: ls) ps (f :: fs) = f :: arrange ls ps fs
arrange (Nothing :: ls) ps [] = []

||| A type with the indices of every inductive family in it erased, so that
||| `Vect 3 Double` and `Vect n Double` name one instance (SEM-IDX-1).
eraseIndices : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               {vars : _} -> String -> TT vars -> Core (TT vars)
eraseIndices owner tm@(Bind fc x (Pi pfc rig pinfo a) sc) = do
  a' <- eraseIndices owner a
  sc' <- eraseIndices owner sc
  pure (Bind fc x (Pi pfc rig pinfo a') sc')
eraseIndices owner tm = case spine tm [] of
  (h@(Ref _ (TyCon _) n), args) => do
    Just (_, ps) <- paramPositions owner n
      | Nothing => pure tm
    args' <- traverse (\(i, a) => if elem i ps then eraseIndices owner a else pure (Erased EmptyFC Placeholder))
                      (zip [0 .. length args] args)
    pure (foldl (App EmptyFC) h args')
  _ => pure tm

||| A constructor's name within its data type, the symbol of its `idr.ctor`:
||| a data type's constructors share its namespace, so the name without it
||| is unique there. The full name is its location (IDR-DATA-5).
shortName : Name -> String
shortName (NS _ n) = shortName n
shortName n = show n

||| The role Idris gives a constructor of a `Nat`-like type
||| (`TTImp.ProcessData.calcNaty`): the type is `BigT`, zero is `0`, and the
||| successor adds one (docs/cutover.md, section 10.5). Idris counts only
||| runtime arguments, so `Fin` is one too.
data NatRole = Zero | Succ

natRole : GlobalDef -> Maybe NatRole
natRole def = case mapMaybe role (flags def) of
  (r :: _) => Just r
  [] => Nothing
  where
    role : DefFlag -> Maybe NatRole
    role (ConType ZERO) = Just Zero
    role (ConType SUCC) = Just Succ
    role _ = Nothing

||| Is a type constructor `Nat`-like: do its constructors carry Idris's
||| `ZERO` and `SUCC` flags? These are read from Idris's metadata, never
||| from names (docs/architecture/17-registry.md, category 3).
natLike : {auto c : Ref Ctxt Defs} -> GlobalDef -> Core Bool
natLike def = case definition def of
  TCon _ _ _ _ _ (Just cons) _ => do
    defs <- get Ctxt
    roles <- traverse (\n => map (>>= natRole) (lookupCtxtExact n (gamma defs))) cons
    pure (not (null roles) && all isJust roles)
  _ => pure False

mutual
  ||| The Core type of a closed, normalised type (FE-TR-1). A type that has
  ||| no runtime representation is reported under `rule`: PROF-TYPE-4, or
  ||| PROF-DATA-2 for a constructor field.
  export
  coreType : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             FC -> String -> Rule -> ClosedTerm -> Core Ty
  coreType fc owner rule (PrimVal _ (PrT t)) = case intTy t of
    Just it => pure (IntT it)
    Nothing => case t of
      CharType => pure CharT
      DoubleType => pure DoubleT
      StringType => pure StrT
      WorldType => pure WorldT
      IntegerType => pure BigT
      _ => reject fc owner rule (show t ++ " in a runtime position")
  coreType fc owner rule (Bind bfc x (Pi _ rig _ a) sc) = do
    at <- if isErased rig then pure ErasedT else coreType fc owner rule a
    let rest = subst (Erased bfc Placeholder) sc
    when (not (isErased rig) && !(erasedOutsideIndices owner rest)) $
      reject fc owner rule "a function type that depends on its argument"
    rt <- coreType fc owner rule !(normaliseClosed rest)
    pure (FunT (quantity rig) at rt)
  -- SEM-REC-2: `Inf` is a suspension like `Lazy`.
  coreType fc owner rule (TDelayed _ _ t) = LazyT <$> coreType fc owner rule t
  coreType fc owner rule tm = case spine tm [] of
    (Ref rfc (TyCon _) n, args) => do
      def <- lookupDef fc owner n
      if !(natLike def)
         then pure BigT
         else DataT <$> dataInstance fc owner n !(traverse normaliseClosed args)
    (TType _ _, _) => reject fc owner rule "Type in a runtime position"
    (Erased _ _, _) => reject fc owner rule "a type that depends on a runtime or erased value"
    _ => reject fc owner rule ("unsupported runtime type " ++ showTT tm)

  ||| Registers a monomorphic data instance (PROF-DATA-*, ELIM-MONO-1).
  export
  dataInstance : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 FC -> String -> Name -> List ClosedTerm -> Core DataId
  dataInstance fc owner tcon args0 = do
    def <- lookupDef fc owner tcon
    let tname = show (fullname def)
    -- SEM-IDX-1: an index is compile-time information; instances differ by
    -- their parameters only.
    keep <- typeParams def
    args <- traverse (\(i, a) => if elem i keep then eraseIndices owner a
                                  else pure (Erased EmptyFC Placeholder))
                     (zip [0 .. length args0] args0)
    inst <- MkDataId <$> instanceName (fullname def) (map Just args)
    st <- get TState
    -- An instance being registered is referred to by its own fields when
    -- it is recursive; `assemble` makes it a box.
    if isJust (lookup inst st.datas) || contains inst st.building then pure inst else do
      TCon arity params _ _ _ datacons _ <- pure (definition def)
        | _ => reject fc owner ProfType4 (tname ++ " is not a data type")
      let Just datacons = datacons
        | Nothing => reject fc owner ProfData5 (tname ++ " has no known constructors")
      put TState ({ building $= insert inst } st)
      loc <- toLoc (location def)
      let ps = filter (\i => elem i params) [0 .. minus arity 1]
      conList <- traverse (constructor inst args ps) datacons
      let sorted = sortBy (\a, b => compare a.tag b.tag) conList
      update TState { building $= delete inst
                    , datas $= insert inst (MkDecl inst (shown tname) sorted loc)
                    , dataOrder $= (:< inst) }
      pure inst
    where
      ||| The constructor's arguments: a parameter is the instance's, anything
      ||| else is a field.
      walk : String -> FC -> List ClosedTerm -> List (Maybe Nat) -> ClosedTerm -> Core (List Field)
      walk cname dfc targs (Just p :: ls) (Bind bfc _ (Pi {}) sc) =
        walk cname dfc targs ls (subst (fromMaybe (Erased bfc Placeholder) (getAt p targs)) sc)
      walk cname dfc targs (Nothing :: ls) (Bind bfc _ (Pi _ rig _ a) sc) = do
        t <- if isErased rig then pure ErasedT else do
               a' <- normaliseClosed a
               when !(erasedOutsideIndices cname a') $
                 reject dfc cname ProfData2 "a field type that depends on another field"
               coreType dfc cname ProfData2 a'
        rest <- walk cname dfc targs ls (subst (Erased bfc Placeholder) sc)
        pure (MkField (quantity rig) t :: rest)
      walk _ _ _ _ _ = pure []

      constructor : DataId -> List ClosedTerm -> List Nat -> Name -> Core Con
      constructor inst targs ps dcon = do
        def <- lookupDef fc owner dcon
        let cname = show (fullname def)
        DCon tag arity _ <- pure (definition def)
          | _ => reject fc owner FeTtc1 (cname ++ " is not a constructor")
        loc <- toLoc (location def)
        let layout = paramLayout ps (type def)
        fields <- walk cname (location def) targs layout (type def)
        let con = MkCon (MkConId inst (shortName (fullname def))) (shown cname) (cast tag) fields loc
        update TState { cons $= insert con.id (MkConLayout targs layout con) }
        pure con

------------------------------------------------------------------------------
-- Function instances
------------------------------------------------------------------------------

||| Requests a function instance and returns its name. Polymorphic recursion
||| would request ever larger instances of one definition (ELIM-MONO-3).
request : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          FC -> String -> Name -> List (Maybe ClosedTerm) -> Core FnId
request fc owner n statics = do
  inst <- MkFnId <$> instanceName n statics
  base <- nameKey <$> toFullNames n
  st <- get TState
  unless (contains inst st.seen) $ do
    -- Growth is a homeomorphic embedding of the static arguments (here, of
    -- their text): the new instance's contain the old one's and are larger.
    -- Another implementation of the same method is not growth.
    let args = snd (break (== '[') inst.name)
    let strip = \s => pack (filter (\c => c /= '[' && c /= ']') (unpack s))
    when (any (\(b, old) => b == base && length old < length args && isInfixOf (strip old) args) st.current) $
      reject fc owner ProfPoly1
             ("polymorphic recursion: " ++ base ++ " calls itself at a larger type (" ++ inst.name ++ ")")
    let count = fromMaybe 0 (lookup base st.perName)
    when (count >= 64) $
      reject fc owner ProfPoly1 ("more than 64 instances of " ++ base)
    put TState ({ seen $= insert inst
                , perName $= insert base (S count)
                , queue $= (++ [MkPending n inst statics ((base, args) :: st.current)]) } st)
  pure inst

||| Parameter classification after instantiation. A type parameter and an
||| implementation (an auto-implicit argument, such as an interface
||| constraint) are compile-time values: they key the instance (ELIM-MONO-1)
||| and are erased at runtime.
data PKind = TypeParam ClosedTerm | DictParam ClosedTerm | ErasedParam | RuntimeParam Ty

||| A compile-time value of an argument, computed on demand: normalised for a
||| type, as written for an implementation. `dictionary` says the argument is
||| an implementation known at compile time, whatever binds it: Idris passes
||| an enclosing function's constraints to its case and with blocks as
||| explicit arguments.
record ArgValue where
  constructor MkArgValue
  normalised : Core ClosedTerm
  written : Core ClosedTerm
  dictionary : Bool

known : ClosedTerm -> ArgValue
known t = MkArgValue (pure t) (pure t) True

||| The arguments of a call by position: `Nothing` for a runtime argument of
||| an instance.
ArgValues : Type
ArgValues = List (Maybe ArgValue)

nextStatic : ArgValues -> (Maybe ArgValue, ArgValues)
nextStatic (v :: vs) = (v, vs)
nextStatic [] = (Nothing, [])

skip : ArgValues -> ArgValues
skip = Data.List.drop 1

isAuto : PiInfo t -> Bool
isAuto AutoImplicit = True
isAuto _ = False

||| Is a type an interface, whatever binds a value of it? Idris declares an
||| interface's record with unique search (`uniqueAuto`), and passes a
||| function's constraints to its `where` functions and its case and with
||| blocks as explicit arguments (FE-TR-6).
interfaceType : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core Bool
interfaceType ty = case spine ty [] of
  (Ref _ (TyCon _) n, _) => do
    defs <- get Ctxt
    Just def <- lookupCtxtExact n (gamma defs)
      | Nothing => pure False
    case definition def of
      TCon _ _ _ flags _ _ _ => pure flags.uniqueAuto
      _ => pure False
  _ => pure False

||| Walks a callee's type over its arguments: which are type parameters or
||| implementations, which are erased, which are runtime (and their types).
classify : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           FC -> String -> Nat -> ClosedTerm -> ArgValues ->
           Core (List (Quantity, PKind), ClosedTerm)
classify fc owner Z ty _ = pure ([], ty)
classify fc owner (S k) (Bind bfc _ (Pi _ rig pinfo a) sc) vals = do
  a' <- normaliseClosed a
  if isErased rig && isTypeLike a'
     then do
       let (Just v, vals') = nextStatic vals
         | _ => reject fc owner ProfFn7 "a type argument that is not known statically"
       val <- v.normalised
       (rest, res) <- classify fc owner k !(normaliseClosed (subst val sc)) vals'
       pure ((Q0, TypeParam val) :: rest, res)
     else if isErased rig
       then do
         (rest, res) <- classify fc owner k (subst (Erased bfc Placeholder) sc) (skip vals)
         pure ((Q0, ErasedParam) :: rest, res)
     else if isAuto pinfo || maybe False (.dictionary) (fst (nextStatic vals)) || !(interfaceType a')
       then do
         let (Just v, vals') = nextStatic vals
           | _ => reject fc owner ProfFn7 "an implementation that is not known statically"
         val <- v.written
         when (runtimeDependent val) $
           reject fc owner ProfHeap1 ("an implementation chosen at runtime (FE-TR-6): " ++ showTT val)
         (rest, res) <- classify fc owner k !(normaliseClosed (subst val sc)) vals'
         pure ((Q0, DictParam val) :: rest, res)
       else do
         when !(erasedOutsideIndices owner a') $
           reject fc owner ProfType4 "a parameter type that depends on another argument"
         t <- coreType fc owner ProfType4 a'
         (rest, res) <- classify fc owner k (subst (Erased bfc Placeholder) sc) (skip vals)
         pure ((quantity rig, RuntimeParam t) :: rest, res)
classify fc owner (S k) ty vals = do
  ty' <- normaliseClosed ty
  case ty' of
    Bind {} => classify fc owner (S k) ty' vals
    _ => internal fc "more arguments than the type has binders (FE-TR-1)"

------------------------------------------------------------------------------
-- Primitives
------------------------------------------------------------------------------

scalar : PrimType -> Maybe Scalar
scalar CharType = Just SChar
scalar DoubleType = Just SDouble
scalar t = SInt <$> intTy t

||| Double arithmetic and the C library's functions (SEM-DBL-2, SEM-DBL-3).
double : PrimFn k -> Maybe Prim
double (Add DoubleType) = Just (FloatOp FAdd)
double (Sub DoubleType) = Just (FloatOp FSub)
double (Mul DoubleType) = Just (FloatOp FMul)
double (Div DoubleType) = Just (FloatOp FDiv)
double (Neg DoubleType) = Just Negate
double DoubleExp = Just (Math Exp)
double DoubleLog = Just (Math Log)
double DoublePow = Just (Math Pow)
double DoubleSin = Just (Math Sin)
double DoubleCos = Just (Math Cos)
double DoubleTan = Just (Math Tan)
double DoubleASin = Just (Math ASin)
double DoubleACos = Just (Math ACos)
double DoubleATan = Just (Math ATan)
double DoubleSqrt = Just (Math Sqrt)
double DoubleFloor = Just (Math Floor)
double DoubleCeiling = Just (Math Ceiling)
double _ = Nothing

||| A cast between types that exist at runtime; `Char` and `Double` are not
||| cast to each other (PROF-PRIM-2).
runtimeCast : Scalar -> Scalar -> Maybe Prim
runtimeCast SChar SDouble = Nothing
runtimeCast SDouble SChar = Nothing
runtimeCast a b = Just (Cast a b)

arith : PrimFn k -> Maybe (ArithOp, PrimType)
arith (Add t) = Just (Add, t)
arith (Sub t) = Just (Sub, t)
arith (Mul t) = Just (Mul, t)
arith (Div t) = Just (Div, t)
arith (Mod t) = Just (Mod, t)
arith (BAnd t) = Just (And, t)
arith (BOr t) = Just (Or, t)
arith (BXOr t) = Just (Xor, t)
arith _ = Nothing

comparison : PrimFn k -> Maybe (Cmp, PrimType)
comparison (LT t) = Just (CLt, t)
comparison (LTE t) = Just (CLte, t)
comparison (EQ t) = Just (CEq, t)
comparison (GTE t) = Just (CGte, t)
comparison (GT t) = Just (CGt, t)
comparison _ = Nothing

||| Integer primitives (IDR-IN-3: `idr.big.*`).
integer : PrimFn k -> Maybe Prim
integer (Neg IntegerType) = Just BigNegate
integer (Cast IntegerType StringType) = Just BigShow
integer (Cast StringType IntegerType) = Just BigRead
integer (Cast IntegerType to) = FromBig <$> scalar to
integer (Cast from IntegerType) = ToBig <$> scalar from
integer p = case (arith p, comparison p) of
  (Just (op, IntegerType), _) => Just (BigArith op)
  (_, Just (op, IntegerType)) => Just (BigCompare op)
  _ => Nothing

||| A cast from a string: to a number. A string has no `Char` cast.
fromString : PrimType -> Maybe Prim
fromString CharType = Nothing
fromString to = FromStr <$> scalar to

primOp : PrimFn k -> Maybe Prim
primOp p = case (integer p, double p, arith p, comparison p, p) of
  (Just b, _, _, _, _) => Just b
  (_, Just d, _, _, _) => Just d
  (_, _, Just (op, t), _, _) => IntOp op <$> intTy t
  (_, _, _, Just (op, StringType), _) => Just (StrCompare op)
  (_, _, _, Just (op, t), _) => Compare op <$> scalar t
  (_, _, _, _, Cast StringType to) => fromString to
  (_, _, _, _, Cast from StringType) => ToStr <$> scalar from
  (_, _, _, _, Cast from to) => join (runtimeCast <$> scalar from <*> scalar to)
  (_, _, _, _, StrLength) => Just StrLength
  (_, _, _, _, StrHead) => Just StrHead
  (_, _, _, _, StrTail) => Just StrTail
  (_, _, _, _, StrIndex) => Just StrIndex
  (_, _, _, _, StrCons) => Just StrCons
  (_, _, _, _, StrAppend) => Just StrAppend
  (_, _, _, _, StrReverse) => Just StrReverse
  (_, _, _, _, StrSubstr) => Just StrSubstr
  _ => Nothing

------------------------------------------------------------------------------
-- Hooks (docs/architecture/17-registry.md)
------------------------------------------------------------------------------

||| FE-TR-7: is a definition the identity on its last argument?
identityOnLast : List Hook -> Bool
identityOnLast [] = False
identityOnLast (IdentityOnLastArgument :: _) = True
identityOnLast (_ :: hs) = identityOnLast hs

||| PROF-IO-4: the IO operation a definition's calls are.
export
ioCallOf : List Hook -> Maybe IOOp
ioCallOf [] = Nothing
ioCallOf (IOCall op :: _) = Just op
ioCallOf (_ :: hs) = ioCallOf hs

------------------------------------------------------------------------------
-- Terms (FE-TR-3)
------------------------------------------------------------------------------

record Ctx where
  constructor MkCtx
  owner : String
  fc : FC
  complete : Bool     -- Idris found no missing case (PROF-FN-5)

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
constantLit (Db x) = Just (LDouble x)
constantLit (BI x) = Just (LBig x)
constantLit _ = Nothing

bestFC : Ctx -> FC -> FC
bestFC ctx fc = if isEmptyFC fc then ctx.fc else fc

||| A closure-converted lambda (`Term.lam`).
closure : {auto s : Ref TState TS} -> Ord a => FC -> Loc -> Binder -> Term (Under 1 a) -> Core (Term a)
closure fc loc b body = do
  lbl <- label
  maybe (internal fc "a lambda body that is not well scoped") pure (lam loc lbl b body)

||| Eta-expands a known head applied to too few arguments:
||| `\x.. => head(args ++ xs)`.
etaExpand : {auto s : Ref TState TS} -> Ord a => FC -> Loc -> List (Quantity, Ty) ->
            ({0 b : Type} -> List (Term b) -> Term b) -> List (Term a) -> Core (Term a)
etaExpand fc loc [] mk given = pure (mk given)
etaExpand fc loc ((q, t) :: rest) mk given = do
  let x = if q == Q0 then Erased loc else Var loc (Bound FZ)
  body <- etaExpand fc loc rest mk (map (map Free) given ++ [x])
  closure fc loc (MkBinder q (if q == Q0 then ErasedT else t)) body

||| The position of a `Nat`-like successor's argument: its one argument of
||| runtime quantity (the others are erased indices, as `FS`'s).
succArg : List (Quantity, PKind) -> Maybe Nat
succArg kinds = case mapMaybe runtime (zip [0 .. length kinds] kinds) of
  [i] => Just i
  _ => Nothing
  where
    runtime : (Nat, Quantity, PKind) -> Maybe Nat
    runtime (i, Q0, _) = Nothing
    runtime (i, _, RuntimeParam _) = Just i
    runtime _ = Nothing

mutual
  export
  term : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> Ord a =>
         Ctx -> List (VarInfo a) -> TT vars -> Core (Term a)
  term ctx env (Local fc _ idx _) = do
    loc <- toLoc (bestFC ctx fc)
    case getAt idx env of
      Just (Runtime x _) => pure (Var loc x)
      Just (TypeValue _) => pure (Erased loc)
      Just (Static t) => term {vars} ctx env (embedClosed {vars} t)
      Nothing => internal (bestFC ctx fc) "a variable out of scope (FE-TR-3)"
  term ctx env (PrimVal fc c) = do
    loc <- toLoc (bestFC ctx fc)
    case constantLit c of
      Just l => pure (Literal loc l)
      Nothing => case c of
        WorldVal => reject (bestFC ctx fc) ctx.owner ProfIO3 "%MkWorld"
        PrT _ => pure (Erased loc)
        _ => reject (bestFC ctx fc) ctx.owner ProfType4 ("constant " ++ show c)
  term ctx env (TType fc _) = Erased <$> toLoc (bestFC ctx fc)
  term ctx env (Erased fc _) = Erased <$> toLoc (bestFC ctx fc)
  term ctx env (Bind fc _ (Pi {}) _) = Erased <$> toLoc (bestFC ctx fc)
  term ctx env (Bind fc x (Let lfc rig val ty) sc) = do
    -- TTC does not keep the types of lets (Core.TTC, `Let` binders): `Emit`
    -- synthesizes them (FE-TR-1).
    loc <- toLoc (bestFC ctx fc)
    let env' = under [Runtime (Bound FZ) Nothing] env
    if isErased rig
       then Let loc Q0 (Erased loc) <$> term ctx env' sc
       else Let loc (quantity rig) <$> term ctx env val <*> term ctx env' sc
  term ctx env (Bind fc x (Lam lfc rig _ ty) sc) = do
    loc <- toLoc (bestFC ctx fc)
    t <- if isErased rig then pure ErasedT
         else coreType (bestFC ctx fc) ctx.owner ProfType4 !(closeNormalise fc env ty)
    body <- term ctx (under [Runtime (Bound FZ) (Just t)] env) sc
    closure fc loc (MkBinder (quantity rig) t) body
  term ctx env (TDelay fc _ _ arg) = suspend ctx env fc arg
  term ctx env (TForce fc _ arg) = Resume <$> toLoc (bestFC ctx fc) <*> term ctx env arg
  term ctx env (TDelayed fc _ _) = Erased <$> toLoc (bestFC ctx fc)
  term ctx env (Meta fc n _ _) = reject (bestFC ctx fc) ctx.owner ProfTerm2 ("hole or metavariable " ++ show n)
  term ctx env (As fc _ _ pat) = term ctx env pat
  term ctx env tm@(App fc _ _) = let (fn, args) = spine tm [] in application ctx env fc fn args
  term ctx env tm@(Ref fc _ _) = application ctx env fc tm []
  term ctx env (Bind fc _ _ _) = internal (bestFC ctx fc) "a binder in a runtime position (FE-TR-3)"

  suspend : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> Ord a =>
            Ctx -> List (VarInfo a) -> FC -> TT vars -> Core (Term a)
  suspend ctx env fc arg = do
    loc <- toLoc (bestFC ctx fc)
    body <- term ctx env arg
    lbl <- label
    maybe (internal fc "a delayed term that is not well scoped") pure (delay loc lbl body)

  application : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> Ord a =>
                Ctx -> List (VarInfo a) -> FC -> TT vars -> List (TT vars) -> Core (Term a)
  application ctx env afc (Ref rfc nt name) args = do
    let fc = bestFC ctx rfc
    loc <- toLoc fc
    def <- lookupDef fc ctx.owner name
    let full = fullname def
    case definition def of
      -- FE-TR-7: a hook for the identity on the one runtime argument, the
      -- last (`replace`, and `rewrite__impl`, which `rewrite` elaborates
      -- to); the rest are proofs and types.
      PMDef _ params _ _ _ =>
        if identityOnLast (hooksOf full) && length args >= length params
           then do
             let (now, rest) = splitAt (length params) args
             v <- maybe (pure (Erased loc)) (term ctx env) (last' now)
             applyAll loc v rest
           else call fc loc full (length params) (type def) args
      DCon tag arity _ => constructor fc loc def arity args
      TCon {} => pure (Erased loc)
      Builtin {arity} op => primitive fc loc full arity op args
      -- PROF-IO-4: an IO primitive the registry lists, a `%foreign` one by
      -- its spec and an `%extern` one by its name.
      ForeignDef arity specs => case foreignHookOf full specs of
        Just (Right (IOCall op)) => ioCall fc loc arity op (type def) args
        Just (Left wrong) => reject fc (show full) HookShape1 wrong
        _ => reject fc ctx.owner ProfEsc1 ("foreign function " ++ show full)
      ExternDef arity => case ioCallOf (hooksOf full) of
        Just op => ioCall fc loc arity op (type def) args
        Nothing => reject fc ctx.owner ProfEsc1 ("extern function " ++ show full)
      Hole {} => reject fc ctx.owner ProfTerm2 ("hole " ++ show full)
      _ => internal fc ("a reference to " ++ show full ++ " (FE-TR-3)")
    where
      applyAll : Loc -> Term a -> List (TT vars) -> Core (Term a)
      applyAll loc f [] = pure f
      applyAll loc f (x :: xs) = applyAll loc (App loc f !(term ctx env x)) xs

      -- Arguments: values of type parameters, erased ones, runtime ones.
      arguments : Loc -> List (Quantity, PKind) -> List (TT vars) -> Core (List (Term a))
      arguments loc kinds xs = traverse arg (zip kinds xs)
        where
          arg : ((Quantity, PKind), TT vars) -> Core (Term a)
          arg ((_, RuntimeParam _), x) = term ctx env x
          arg _ = pure (Erased loc)

      isImplementation : TT vars -> Bool
      isImplementation (Local _ _ idx _) = case getAt idx env of
        Just (Static _) => True
        _ => False
      isImplementation _ = False

      argValue : TT vars -> Maybe ArgValue
      argValue x = Just (MkArgValue (closeNormalise afc env x) (solved (closeWritten afc env x)) (isImplementation x))

      argValues : List (TT vars) -> ArgValues
      argValues = map argValue

      finish : Loc -> List (Quantity, PKind) -> List (Term a) ->
               ({0 b : Type} -> List (Term b) -> Term b) -> List (TT vars) -> Core (Term a)
      finish loc kinds given mk extra = do
        let missing = drop (length given) kinds
        if null missing
           then applyAll loc (mk given) extra
           else do
             when (any isStatic missing) $
               reject afc ctx.owner ProfFn7 "a partially applied type parameter or implementation"
             etaExpand afc loc (map kindTy missing) mk given
        where
          isStatic : (Quantity, PKind) -> Bool
          isStatic (_, TypeParam _) = True
          isStatic (_, DictParam _) = True
          isStatic _ = False
          kindTy : (Quantity, PKind) -> (Quantity, Ty)
          kindTy (q, RuntimeParam t) = (q, t)
          kindTy (q, _) = (Q0, ErasedT)

      call : FC -> Loc -> Name -> Nat -> ClosedTerm -> List (TT vars) -> Core (Term a)
      call fc loc name arity ty xs = do
        (kinds, _) <- classify fc ctx.owner arity ty (argValues (take arity xs))
        let statics = map (\k => case k of
                                    (_, TypeParam t) => Just t
                                    (_, DictParam t) => Just t
                                    _ => Nothing) kinds
        inst <- request fc ctx.owner name statics
        given <- arguments loc kinds (take arity xs)
        finish loc kinds given (Call loc inst) (drop arity xs)

      -- A constructor of a `Nat`-like type is big arithmetic
      -- (docs/cutover.md, section 10.5): zero is 0, a successor adds 1.
      natConstructor : FC -> Loc -> NatRole -> List (Quantity, PKind) -> List (Term a) ->
                       List (TT vars) -> Core (Term a)
      natConstructor fc loc Zero kinds given extra =
        finish loc kinds given (\_ => Literal loc (LBig 0)) extra
      natConstructor fc loc Succ kinds given extra = do
        let Just i = succArg kinds
          | Nothing => internal fc "a successor without one runtime argument (FE-TR-3)"
        finish loc kinds given
               (\xs => PrimApp loc (BigArith Add) (Data.List.take 1 (drop i xs) ++ [Literal loc (LBig 1)])) extra

      constructor : FC -> Loc -> GlobalDef -> Nat -> List (TT vars) -> Core (Term a)
      constructor fc loc def arity xs = do
        (kinds, resTy) <- classify fc ctx.owner arity (type def) (argValues (take arity xs))
        given <- arguments loc kinds (take arity xs)
        case natRole def of
          Just role => natConstructor fc loc role kinds given (drop arity xs)
          Nothing => do
            DataT inst <- coreType fc ctx.owner ProfType4 !(normaliseClosed resTy)
              | _ => internal fc "a constructor of a type that is not data (FE-TR-3)"
            -- The data type's parameters are not fields, wherever they are
            -- among the constructor's arguments; a type argument that is
            -- not one is an erased field.
            st <- get TState
            let cid = MkConId inst (shortName (fullname def))
            let layout = maybe [] (.layout) (lookup cid st.cons)
            finish loc (fieldsOnly layout kinds) (fieldsOnly layout given) (ConApp loc cid) (drop arity xs)

      primitive : FC -> Loc -> Name -> Nat -> PrimFn ar -> List (TT vars) -> Core (Term a)
      primitive fc loc name arity op xs = case op of
        BelieveMe => reject fc ctx.owner ProfEsc1 "believe_me"
        Crash => reject fc ctx.owner ProfEsc1 "idris_crash"
        Neg DoubleType => supported
        Neg IntegerType => supported
        Neg _ => reject fc ctx.owner ProfPrim2 "negate (SEM-EXCL-1)"
        ShiftL _ => reject fc ctx.owner ProfPrim2 "shift left (SEM-EXCL-1)"
        ShiftR _ => reject fc ctx.owner ProfPrim2 "shift right (SEM-EXCL-1)"
        _ => supported
        where
          supported : Core (Term a)
          supported = case primOp op of
            Nothing => reject fc ctx.owner ProfPrim2 ("primitive " ++ show name)
            Just p => do
              args' <- traverse (term ctx env) (take arity xs)
              let kinds = map (\t => (QW, RuntimeParam t)) (primArgs p)
              finish loc kinds args' (PrimApp loc p) (drop arity xs)

      ioCall : FC -> Loc -> Nat -> IOOp -> ClosedTerm -> List (TT vars) -> Core (Term a)
      ioCall fc loc arity op ty xs = do
        (kinds, resTy) <- classify fc ctx.owner arity ty []
        DataT res <- coreType fc ctx.owner ProfType4 !(normaliseClosed resTy)
          | _ => internal fc "an IO primitive with an unexpected type (FE-TR-3)"
        given <- arguments loc kinds (take arity xs)
        finish loc kinds given (\ys => Effect loc op ys res) (drop arity xs)
  application ctx env afc fn args = case headStep fn args of
    Just (h, as) => let (h', as') = spine h [] in application ctx env afc h' (as' ++ as)
    Nothing => do
      loc <- toLoc (bestFC ctx afc)
      f <- term ctx env fn
      applyAll loc f args
    where
      ||| An implementation applied to arguments is used as written; its type
      ||| arguments are substituted, so its body is translated at the types of
      ||| this use (FE-TR-6).
      staticArg : TT vars -> Bool
      staticArg (Local _ _ idx _) = case getAt idx env of
        Just (Static _) => True
        _ => False
      staticArg _ = False

      headStep : TT vars -> List (TT vars) -> Maybe (TT vars, List (TT vars))
      headStep (Local _ _ idx _) as = case getAt idx env of
        Just (Static t) => Just (embedClosed t, as)
        _ => Nothing
      -- A lambda over an implementation (`\@{m} => ...`, as a dictionary's
      -- polymorphic method field is written) takes it as written, like a
      -- type: it is a compile-time value (FE-TR-6).
      headStep (Bind _ _ (Lam _ rig pinfo _) sc) (a :: as) =
        if isErased rig || isAuto pinfo || staticArg a then Just (subst a sc, as) else Nothing
      headStep _ _ = Nothing

      applyAll : Loc -> Term a -> List (TT vars) -> Core (Term a)
      applyAll loc f [] = pure f
      applyAll loc f (x :: xs) = applyAll loc (App loc f !(term ctx env x)) xs

------------------------------------------------------------------------------
-- Case trees (FE-TR-4)
------------------------------------------------------------------------------

||| The variables a constructor alternative binds for its fields, in field
||| order: field `i` is `Bound i`.
fieldInfos : {k : Nat} -> (bs : Vect k Binder) -> List (VarInfo (Under k a))
fieldInfos bs = toList (zipWith (\i, b => Runtime (Bound i) (Just b.type)) range bs)

toBinder : Field -> Binder
toBinder f = MkBinder f.quantity f.type

||| A leaf no input reaches: `Unreachable` in a covering definition
||| (PROF-FN-5), a crash otherwise (SEM-CRASH-2).
missingCase : {0 a : Type} -> Ctx -> Loc -> IdrisMLIR.Term.Term a
missingCase ctx loc =
  if ctx.complete then Unreachable loc else Crash loc ("unhandled input for " ++ ctx.owner)

mutual
  tree : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> Ord a =>
         Ctx -> List (VarInfo a) -> CaseTree vars -> Core (Term a)
  tree ctx env (STerm _ tm) = term ctx env tm
  -- FE-TR-4, SEM-DATA-2: Idris proved it cannot be reached. An `Unmatched`
  -- leaf of a covering definition (PROF-FN-5) is one too: a definition whose
  -- clauses are all impossible has only that leaf. In a definition with
  -- missing cases it is one of them, and crashes (SEM-CRASH-2).
  tree ctx env (Unmatched msg) = missingCase ctx <$> toLoc ctx.fc
  tree ctx env Impossible = Unreachable <$> toLoc ctx.fc
  tree ctx env (Case idx _ scTy alts) = do
    loc <- toLoc ctx.fc
    case getAt idx env of
      Just (Runtime i (Just WorldT)) => case alts of
        [ConstCase WorldVal rhs] => tree ctx env rhs
        _ => internal ctx.fc "an unexpected match on the world (FE-TR-4)"
      -- FE-TR-7: a match on a quantity-0 value (a proof, an index) is in the
      -- compile-time tree only when its type forces the alternative, as
      -- Idris's erasure check guarantees; its fields are erased too.
      Just (Runtime i (Just ErasedT)) => forced alts
      Just (TypeValue (Erased _ _)) => forced alts
      Just (Runtime i (Just (DataT inst))) => do
        (conAlts, def) <- conAlternatives ctx env inst alts
        st <- get TState
        -- Constructors the tree leaves out are impossible when the
        -- definition is covering (PROF-FN-5), and crash otherwise
        -- (SEM-CRASH-2).
        let missing = case (def, lookup inst st.datas) of
                        (Nothing, Just dt) => filter (\c => not (any (\(MkAlt k _ _) => k == c.id) conAlts)) dt.cons
                        _ => []
        let absurd = map (\c => MkAlt c.id (fromList (map toBinder c.fields)) (missingCase ctx loc)) missing
        pure (Case loc i (conAlts ++ absurd) def)
      -- A `Nat`-like value is a big: a match on its constructors is a
      -- match on zero (docs/cutover.md, section 10.5).
      Just (Runtime i (Just BigT)) =>
        if any isConCase alts then natCase ctx env loc i alts else literals loc i
      Just (Runtime i (Just _)) => literals loc i
      -- A match on an implementation selects its alternative now (FE-TR-6).
      Just (Static t) => staticCase ctx env t alts
      _ => internal ctx.fc "a match on a compile-time value (FE-TR-4)"
    where
      isConCase : CaseAlt vars -> Bool
      isConCase (ConCase {}) = True
      isConCase _ = False

      literals : Loc -> a -> Core (Term a)
      literals loc i = do
        (litAlts, def) <- litAlternatives ctx env alts
        let Just def = def <|> (if ctx.complete then Nothing else Just (missingCase ctx loc))
          | Nothing => reject ctx.fc ctx.owner ProfFn5 "a literal match without a default"
        pure (CaseLit loc i litAlts def)

      forced : List (CaseAlt vars) -> Core (Term a)
      forced [ConCase _ _ args rhs] =
        tree ctx (map (const (TypeValue (Erased ctx.fc Placeholder))) args ++ env) rhs
      forced [DefaultCase rhs] = tree ctx env rhs
      forced _ = reject ctx.fc ctx.owner ProfFn5 "a match on an erased value with more than one alternative"

  ||| A match on a `Nat`-like value: a literal match on zero, whose default
  ||| binds the predecessor. Each alternative is translated once, so every
  ||| label stays unique.
  natCase : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> Ord a =>
            Ctx -> List (VarInfo a) -> Loc -> a -> List (CaseAlt vars) -> Core (Term a)
  natCase ctx env loc x alts = do
    (zero, succ, def) <- natAlternatives ctx env loc x alts
    case (zero, succ, def) of
      (Nothing, Nothing, Just d) => pure d
      (Just z, Just s, _) => pure (CaseLit loc x [(LBig 0, z)] s)
      (Just z, Nothing, d) => pure (CaseLit loc x [(LBig 0, z)] (fromMaybe (missingCase ctx loc) d))
      (Nothing, Just s, d) => pure (CaseLit loc x [(LBig 0, fromMaybe (missingCase ctx loc) d)] s)
      (Nothing, Nothing, Nothing) => pure (missingCase ctx loc)

  ||| The alternatives of a match on a `Nat`-like value: zero's, the
  ||| successor's (the predecessor bound by a `let`, its erased arguments
  ||| compile-time values), and the default.
  natAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> Ord a =>
                    Ctx -> List (VarInfo a) -> Loc -> a -> List (CaseAlt vars) ->
                    Core (Maybe (Term a), Maybe (Term a), Maybe (Term a))
  natAlternatives ctx env loc x [] = pure (Nothing, Nothing, Nothing)
  natAlternatives ctx env loc x (ConCase cn _ args rhs :: rest) = do
    def <- lookupDef ctx.fc ctx.owner cn
    isErased <- erasedArgs cn
    case natRole def of
      Just Zero => do
        z <- tree ctx (map (const (TypeValue (Erased ctx.fc Placeholder))) args ++ env) rhs
        (_, s, d) <- natAlternatives ctx env loc x rest
        pure (Just z, s, d)
      Just Succ => do
        let infos = zipWith (\_, e => if e then TypeValue (Erased ctx.fc Placeholder)
                                          else Runtime (Bound FZ) (Just BigT))
                            args (isErased ++ replicate (length args) False)
        body <- tree ctx (under infos env) rhs
        let pred = PrimApp loc (BigArith Sub) [Var loc x, Literal loc (LBig 1)]
        (z, _, d) <- natAlternatives ctx env loc x rest
        pure (z, Just (Let loc QW pred body), d)
      Nothing => internal ctx.fc ("a constructor of another type in a match on a Nat-like value (FE-TR-4)")
  natAlternatives ctx env loc x (DefaultCase rhs :: _) = pure (Nothing, Nothing, Just !(tree ctx env rhs))
  natAlternatives ctx env loc x (_ :: _) = internal ctx.fc "an unexpected alternative (FE-TR-4)"

  ||| A match on a compile-time value: the implementation is reduced to its
  ||| constructor, and the alternative's variables stand for its arguments.
  staticCase : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> Ord a =>
               Ctx -> List (VarInfo a) -> ClosedTerm -> List (CaseAlt vars) -> Core (Term a)
  staticCase ctx env t alts = do
    Just (cn, cargs) <- whnf 64 t
      | Nothing => reject ctx.fc ctx.owner ProfHeap1
                     ("an implementation that does not reduce to its constructor: " ++ showTT t ++ " (FE-TR-6)")
    cn <- toFullNames cn
    erased <- erasedArgs cn
    pick cn (zipWith info (erased ++ replicate (length cargs) False) cargs) alts
    where
      info : Bool -> ClosedTerm -> VarInfo a
      info True v = TypeValue v
      info False v = Static v
      pick : Name -> List (VarInfo a) -> List (CaseAlt vars) -> Core (Term a)
      pick cn infos (ConCase k _ args rhs :: rest) = do
        k <- toFullNames k
        if k /= cn then pick cn infos rest else do
          when (length args /= length infos) $
            internal ctx.fc ("constructor " ++ show cn ++ " binds an unexpected number of arguments")
          tree ctx (infos ++ env) rhs
      pick cn infos (DefaultCase rhs :: _) = tree ctx env rhs
      pick cn infos (_ :: rest) = pick cn infos rest
      pick cn infos [] = internal ctx.fc ("no alternative for " ++ show cn ++ " (FE-TR-6)")

  conAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> Ord a =>
                    Ctx -> List (VarInfo a) -> DataId -> List (CaseAlt vars) ->
                    Core (List (Alt a), Maybe (Term a))
  conAlternatives ctx env inst [] = pure ([], Nothing)
  conAlternatives ctx env inst (ConCase cn _ args rhs :: rest) = do
    def <- lookupDef ctx.fc ctx.owner cn
    let cid = MkConId inst (shortName (fullname def))
    st <- get TState
    let Just info = lookup cid st.cons
      | Nothing => internal ctx.fc ("unknown constructor " ++ cid.name ++ " of " ++ inst.name)
    let bs = fromList (map toBinder info.con.fields)
    let bound = under (arrange info.layout info.params (fieldInfos bs)) env
    when (length info.layout /= length args) $
      reject ctx.fc ctx.owner FeTtc1 ("constructor " ++ cid.name ++ " binds an unexpected number of arguments")
    body <- tree ctx bound rhs
    (alts, def') <- conAlternatives ctx env inst rest
    pure (MkAlt cid bs body :: alts, def')
  conAlternatives ctx env inst (DefaultCase rhs :: _) = pure ([], Just !(tree ctx env rhs))
  conAlternatives ctx env inst (DelayCase {} :: _) =
    reject ctx.fc ctx.owner ProfTerm2 "a match on a lazy value"
  conAlternatives ctx env inst (ConstCase {} :: _) =
    internal ctx.fc "a constant alternative in a constructor match (FE-TR-4)"

  litAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> Ord a =>
                    Ctx -> List (VarInfo a) -> List (CaseAlt vars) ->
                    Core (List (Lit, Term a), Maybe (Term a))
  litAlternatives ctx env [] = pure ([], Nothing)
  litAlternatives ctx env (ConstCase c rhs :: rest) = do
    Just lit <- pure (constantLit c)
      | Nothing => reject ctx.fc ctx.owner ProfPrim4 ("a match on " ++ show c)
    case lit of
      LDouble _ => reject ctx.fc ctx.owner ProfPrim2 "a match on a Double literal (SEM-DBL-1)"
      _ => pure ()
    body <- tree ctx env rhs
    (alts, def) <- litAlternatives ctx env rest
    pure ((lit, body) :: alts, def)
  litAlternatives ctx env (DefaultCase rhs :: _) = pure ([], Just !(tree ctx env rhs))
  litAlternatives ctx env _ = internal ctx.fc "an unexpected alternative (FE-TR-4)"

------------------------------------------------------------------------------
-- Function instances and programs
------------------------------------------------------------------------------

||| FE-TOT-1: Idris's termination checker reports the definition
||| terminating.
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
    | _ => reject fc owner ProfFn1 "not a pattern-matching definition"
  -- PROF-FN-5: a missing case crashes (SEM-CRASH-2).
  let complete = case isCovering (totality def) of
                   MissingCases _ => False
                   _ => True
  (kinds, resTy) <- classify fc owner (length args) (type def) (map (map known) p.statics)
  result <- coreType fc owner ProfType4 !(normaliseClosed resTy)
  -- Parameter i is variable i, as in the case tree's scope.
  let env = zipWith info (Data.Fin.List.allFins (length kinds)) kinds
  body <- tree (MkCtx owner fc complete) env treeCT
  loc <- toLoc fc
  tot <- isTotal fc p.name
  let facts = MkFacts (MkFact tot FromIdris)
  update TState { fns $= insert p.inst (MkTFn p.inst (shown owner) (length kinds) (map binder (fromList kinds))
                                              result body loc facts)
                , fnOrder $= (:< p.inst) }
  where
    binder : (Quantity, PKind) -> Binder
    binder (q, RuntimeParam t) = MkBinder q t
    binder _ = MkBinder Q0 ErasedT
    info : Fin k -> (Quantity, PKind) -> VarInfo (Fin k)
    info i (_, TypeParam t) = TypeValue t
    info i (_, DictParam t) = Static t
    info i (_, RuntimeParam t) = Runtime i (Just t)
    info i _ = Runtime i (Just ErasedT)

drain : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Core ()
drain = do
  st <- get TState
  case st.queue of
    [] => pure ()
    (p :: rest) => do
      put TState ({ queue := rest, current := p.path } st)
      translateInstance p
      drain

||| The program, with each data instance's representation: a box when it
||| contains itself, through the fields of any data (not through closures,
||| which are values of their own), and an unboxed sum otherwise.
assemble : {auto s : Ref TState TS} -> FnId -> Core Source
assemble root = do
  st <- get TState
  let decls = the (List Decl) (mapMaybe (\n => lookup n st.datas) (st.dataOrder <>> []))
  let contained = \d => maybe [] (\decl => concatMap (mapMaybe dataField . (.fields)) decl.cons)
                                 (lookup d st.datas)
  let boxes = cyclic contained (map (.id) decls)
  let datas = map (\d : Decl => MkData d.id d.idrisName d.cons d.loc (if contains d.id boxes then Box else Sop)) decls
  let fns = mapMaybe (\n => lookup n st.fns) (st.fnOrder <>> [])
  pure (MkSource datas fns root)
  where
    dataField : Field -> Maybe DataId
    dataField (MkField _ (DataT d)) = Just d
    dataField _ = Nothing

||| A `main : Int` program (FE-ENTRY-2): the root is `main` itself.
export
translateIntProgram : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Name -> Core Source
translateIntProgram main = do
  root <- request EmptyFC (show main) main []
  drain
  assemble root

||| An IO program (FE-ENTRY-4). The root is `unsafePerformIO main` written
||| directly as world-passing code, which is what `unsafePerformIO`,
||| `unsafeCreateWorld` and `unsafeDestroyWorld` mean:
|||   root w = case main of MkIO f => f w
||| It returns the `IORes` of `main`'s result and the last world, so the
||| world is used exactly once. `%MkWorld` never appears (PROF-IO-3).
export
translateIOProgram : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                     FC -> Name -> Core Source
translateIOProgram fc main = do
  inst <- request fc (show main) main []
  drain
  st <- get TState
  let owner = show main
  let notIO = reject fc owner ProfProg4 "main must have type IO ()"
  let Just mainFn = lookup inst st.fns
    | Nothing => internal fc "main was not translated (FE-ENTRY-4)"
  let DataT ioInst = mainFn.result
    | _ => notIO
  let Just [mkIO] = (.cons) <$> lookup ioInst st.datas
    | _ => notIO
  let [MkField _ action@(FunT _ WorldT res@(DataT _))] = mkIO.fields
    | _ => notIO
  loc <- toLoc (location !(lookupDef fc owner main))
  -- w is the parameter; `m` is main's value, and `f` its action.
  let body : Term (Fin 1)
      body = Let loc QW (Call loc inst [])                                    -- m
               (Case loc (Bound FZ)
                  [MkAlt mkIO.id [MkBinder QW action]                        -- f
                     (App loc (Var loc (Bound FZ)) (Var loc (Free (Free FZ))))]
                  Nothing)
  let rootId = MkFnId "$idris-mlir.root"
  src <- assemble rootId
  -- The root is the `ProgramRoot` hook's code, `unsafePerformIO main`: its
  -- facts are the registry's, and it terminates when main does.
  let facts = MkFacts (MkFact mainFn.facts.terminating.holds FromRegistry)
  pure ({ fns $= (++ [MkTFn rootId (shown rootId.name) 1 [MkBinder Q1 WorldT] res body loc facts]) } src)
