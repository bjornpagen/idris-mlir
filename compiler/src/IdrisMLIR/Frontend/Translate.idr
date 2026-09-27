||| Checked TT to full Core (docs/architecture/04-frontend.md). Reads compile-time
||| case trees (`treeCT`) and types; monomorphises on demand (ELIM-MONO-*), with
||| Idris's own normalizer doing all type-level computation.
|||
||| Scopes carry over from TT: a TT term in scope `vars` becomes a `Term n`,
||| with an environment saying what each TT variable stands for. A TT index
||| is a position in that environment; type arguments have no Core variable.
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

import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Rule
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.Fin
import Data.Fin.Split
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
record ConInfo where
  constructor MkConInfo
  params : List ClosedTerm   -- the data instance's type arguments
  con : Con

export
data TState : Type where

export
record TS where
  constructor MkTS
  nextLabel : Nat
  datas : SortedMap DataId Data
  dataOrder : SnocList DataId
  building : SortedSet DataId
  cons : SortedMap ConId ConInfo
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

||| A fresh program point for a lambda or `Delay` (ELIM-G-3).
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

||| What a TT variable stands for: a Core variable (with its type, when a
||| match may need it), a type argument's value, or an implementation's value.
||| Types and implementations are compile-time values, closed TT terms: types
||| are erased at runtime, and an implementation is used by translating it
||| where it is needed (FE-TR-6).
data VarInfo : Nat -> Type where
  Bound : Fin n -> Maybe Ty -> VarInfo n
  TypeValue : ClosedTerm -> VarInfo n
  Static : ClosedTerm -> VarInfo n

weakenInfo : (k : Nat) -> VarInfo n -> VarInfo (k + n)
weakenInfo k (Bound i t) = Bound (shift k i) t
weakenInfo k (TypeValue t) = TypeValue t
weakenInfo k (Static t) = Static t

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
                 FC -> List (VarInfo n) -> TT vars -> Core ClosedTerm
closeNormalise fc env tm = do
  let closed = foldl (App fc) (wrapLams fc tm) (reverse (map value env))
  defs <- get Ctxt
  normalise defs [] closed
  where
    value : VarInfo n -> ClosedTerm
    value (TypeValue t) = t
    value (Static t) = t
    value (Bound _ _) = Erased fc Placeholder

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
closeWritten : {vars : Scope} -> FC -> List (VarInfo n) -> TT vars -> ClosedTerm
closeWritten fc env tm = zeta (betaAll (wrapLams fc tm) (reverse (map value env)))
  where
    value : VarInfo n -> ClosedTerm
    value (TypeValue t) = t
    value (Static t) = t
    value (Bound _ _) = Erased fc Impossible

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

quantity : RigCount -> Quantity
quantity rig = if isErased rig then Q0 else if isLinear rig then Q1 else QW

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

||| Static data holds a function or `Lazy` value, directly or through other
||| static data (ELIM-G-2, ELIM-G-5).
isStatic : Ty -> Bool
isStatic (V _) = False
isStatic _ = True

mutual
  ||| The Core type of a closed, normalised type (FE-TR-1). A type that has
  ||| no runtime representation is reported under `rule`: PROF-TYPE-4, or
  ||| PROF-DATA-2 for a constructor field.
  export
  coreType : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             FC -> String -> Rule -> ClosedTerm -> Core Ty
  coreType fc owner rule (PrimVal _ (PrT t)) = case intTy t of
    Just it => pure (V (IntT it))
    Nothing => case t of
      CharType => pure (V CharT)
      DoubleType => pure (V DoubleT)
      StringType => pure (V StrT)
      WorldType => pure (V WorldT)
      -- SEM-BIG-1: an Integer exists only at compile time.
      IntegerType => pure BigT
      _ => reject fc owner rule (show t ++ " in a runtime position")
  coreType fc owner rule (Bind bfc x (Pi _ rig _ a) sc) = do
    at <- if isErased rig then pure (V ErasedT) else coreType fc owner rule a
    let rest = subst (Erased bfc Placeholder) sc
    when (anyErased rest && not (isErased rig)) $
      reject fc owner rule "a function type that depends on its argument"
    rt <- coreType fc owner rule !(normaliseClosed rest)
    pure (FunT (quantity rig) at rt)
  -- SEM-REC-2: `Inf` is a suspension like `Lazy`; codata built from it is
  -- recursive, so it is a compile-time value (SEM-REC-1).
  coreType fc owner rule (TDelayed _ _ t) = LazyT <$> coreType fc owner rule t
  coreType fc owner rule tm = case spine tm [] of
    (Ref rfc (TyCon _) n, args) => do
      d <- dataInstance fc owner n !(traverse normaliseClosed args)
      st <- get TState
      -- A data type that is being registered is recursive: static (SEM-REC-1).
      pure (if maybe False (.static) (lookup d st.datas) || contains d st.building
               then StaticT d else V (DataT d))
    (TType _ _, _) => reject fc owner rule "Type in a runtime position"
    (Erased _ _, _) => reject fc owner rule "a type that depends on a runtime or erased value"
    _ => reject fc owner rule ("unsupported runtime type " ++ showTT tm)

  ||| Registers a monomorphic data instance (PROF-DATA-*, ELIM-MONO-1).
  export
  dataInstance : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 FC -> String -> Name -> List ClosedTerm -> Core DataId
  dataInstance fc owner tcon args = do
    def <- lookupDef fc owner tcon
    let tname = show (fullname def)
    inst <- MkDataId <$> instanceName (fullname def) (map Just args)
    st <- get TState
    -- SEM-REC-1: a recursive occurrence is a compile-time value.
    if isJust (lookup inst st.datas) || contains inst st.building then pure inst else do
      TCon arity params _ _ _ datacons _ <- pure (definition def)
        | _ => reject fc owner ProfType4 (tname ++ " is not a data type")
      let Just datacons = datacons
        | Nothing => reject fc owner ProfData5 (tname ++ " has no known constructors")
      when (any (\i => not (elem i params)) [0 .. minus arity 1] && arity > 0) $
        reject (location def) tname ProfData5 "a data type with indices at runtime"
      put TState ({ building $= insert inst } st)
      loc <- toLoc (location def)
      conList <- traverse (constructor inst args) datacons
      let sorted = sortBy (\a, b => compare a.tag b.tag) conList
      let static = any (any (isStatic . (.type)) . (.fields)) sorted
      update TState { building $= delete inst
                    , datas $= insert inst (MkData inst tname sorted loc static)
                    , dataOrder $= (:< inst) }
      pure inst
    where
      ||| Parameters first, then the fields.
      walk : String -> FC -> List ClosedTerm -> ClosedTerm -> Core (List Field)
      walk cname dfc (p :: ps) (Bind _ _ (Pi {}) sc) = walk cname dfc ps (subst p sc)
      walk cname dfc [] (Bind bfc _ (Pi _ rig _ a) sc) = do
        t <- if isErased rig then pure (V ErasedT) else do
               a' <- normaliseClosed a
               when (anyErased a') $
                 reject dfc cname ProfData2 "a field type that depends on another field"
               coreType dfc cname ProfData2 a'
        rest <- walk cname dfc [] (subst (Erased bfc Placeholder) sc)
        pure (MkField (quantity rig) t :: rest)
      walk _ _ _ _ = pure []

      constructor : DataId -> List ClosedTerm -> Name -> Core Con
      constructor inst targs dcon = do
        def <- lookupDef fc owner dcon
        let cname = show (fullname def)
        DCon tag arity _ <- pure (definition def)
          | _ => reject fc owner FeTtc1 (cname ++ " is not a constructor")
        loc <- toLoc (location def)
        fields <- walk cname (location def) targs (type def)
        let con = MkCon (MkConId inst cname) (cast tag) fields loc
        update TState { cons $= insert con.id (MkConInfo targs con) }
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

||| PROF-DATA-5: a type constructor with indices, found before its instance
||| is needed (a runtime type mentioning an index).
indexedHead : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              String -> ClosedTerm -> Core ()
indexedHead owner tm = case spine tm [] of
  (Ref _ (TyCon _) n, _) => do
    def <- lookupDef EmptyFC owner n
    case definition def of
      TCon arity params _ _ _ _ _ =>
        when (arity > 0 && any (\i => not (elem i params)) [0 .. minus arity 1]) $
          reject (location def) (show (fullname def)) ProfData5 "a data type with indices at runtime"
      _ => pure ()
  _ => pure ()

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
         indexedHead owner a'
         when (anyErased a') $
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

||| The IO primitives of `IdrisMLIR.IO` (PROF-IO-2), and from v3 the
||| Prelude's output primitives (PROF-IO-4), by their full names.
ioPrim : Name -> Maybe IOOp
ioPrim (NS ns (UN (Basic n))) = case unsafeUnfoldNamespace ns of
  ["IO", "IdrisMLIR"] => Data.List.lookup n [ ("prim__idrPutStr", PutStr), ("prim__idrPutChar", PutChar)
                                            , ("prim__idrGetChar", GetChar), ("prim__idrExit", Exit) ]
  ["IO", "Prelude"] => Data.List.lookup n [ ("prim__putStr", PutStr), ("prim__putChar", PutChar)
                                          , ("prim__getChar", GetByte) ]
  _ => Nothing
ioPrim _ = Nothing

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

||| Integer primitives, evaluated at compile time (SEM-BIG-1).
integer : PrimFn k -> Maybe BigOp
integer (Neg IntegerType) = Just BigNegate
integer (Cast IntegerType StringType) = Just BigShow
integer (Cast StringType IntegerType) = Just BigRead
integer (Cast IntegerType to) = FromBig <$> scalar to
integer (Cast from IntegerType) = ToBig <$> scalar from
integer p = case (arith p, comparison p) of
  (Just (op, IntegerType), _) => Just (BigArith op)
  (_, Just (op, IntegerType)) => Just (BigCompare op)
  _ => Nothing

primOp : PrimFn k -> Maybe PrimOp
primOp p = case (integer p, double p, arith p, comparison p, p) of
  (Just b, _, _, _, _) => Just (Big b)
  (_, Just d, _, _, _) => Just (Run d)
  (_, _, Just (op, t), _, _) => Run . IntOp op <$> intTy t
  (_, _, _, Just (op, StringType), _) => Just (Str (StrCompare op))
  (_, _, _, Just (op, t), _) => Run . Compare op <$> scalar t
  (_, _, _, _, Cast StringType to) => Str . FromStr <$> scalar to
  (_, _, _, _, Cast from StringType) => Str . ToStr <$> scalar from
  (_, _, _, _, Cast from to) => Run <$> (join (runtimeCast <$> scalar from <*> scalar to))
  (_, _, _, _, StrLength) => Just (Str Length)
  (_, _, _, _, StrHead) => Just (Str Head)
  (_, _, _, _, StrTail) => Just (Str Tail)
  (_, _, _, _, StrIndex) => Just (Str Index)
  (_, _, _, _, StrCons) => Just (Str Cons)
  (_, _, _, _, StrAppend) => Just (Str Append)
  (_, _, _, _, StrReverse) => Just (Str Reverse)
  (_, _, _, _, StrSubstr) => Just (Str Substr)
  _ => Nothing

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
closure : {auto s : Ref TState TS} -> {n : Nat} -> FC -> Loc -> Binder -> Term (S n) -> Core (Term n)
closure fc loc b body = do
  lbl <- label
  maybe (internal fc "a lambda body that is not well scoped") pure (lam loc lbl b body)

||| Eta-expands a known head applied to too few arguments:
||| `\x.. => head(args ++ xs)`.
etaExpand : {auto s : Ref TState TS} -> {n : Nat} -> FC -> Loc -> List (Quantity, Ty) ->
            ({m : Nat} -> List (Term m) -> Term m) -> List (Term n) -> Core (Term n)
etaExpand fc loc [] mk given = pure (mk given)
etaExpand fc loc ((q, t) :: rest) mk given = do
  let x = if q == Q0 then Erased loc else Var loc FZ
  body <- etaExpand fc loc rest mk (map weaken given ++ [x])
  closure fc loc (MkBinder q (if q == Q0 then V ErasedT else t)) body

mutual
  export
  term : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> {n : Nat} ->
         Ctx -> List (VarInfo n) -> TT vars -> Core (Term n)
  term ctx env (Local fc _ idx _) = do
    loc <- toLoc (bestFC ctx fc)
    case getAt idx env of
      Just (Bound i _) => pure (Var loc i)
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
    -- TTC does not keep the types of lets (Core.TTC, `Let` binders), and
    -- nothing needs them: `Simplify` knows a value's type when it has it.
    loc <- toLoc (bestFC ctx fc)
    let env' = Bound FZ Nothing :: map (weakenInfo 1) env
    if isErased rig
       then Let loc Q0 (Erased loc) <$> term ctx env' sc
       else Let loc (quantity rig) <$> term ctx env val <*> term ctx env' sc
  term ctx env (Bind fc x (Lam lfc rig _ ty) sc) = do
    loc <- toLoc (bestFC ctx fc)
    t <- if isErased rig then pure (V ErasedT)
         else coreType (bestFC ctx fc) ctx.owner ProfType4 !(closeNormalise fc env ty)
    body <- term ctx (Bound FZ (Just t) :: map (weakenInfo 1) env) sc
    closure fc loc (MkBinder (quantity rig) t) body
  term ctx env (TDelay fc _ _ arg) = suspend ctx env fc arg
  term ctx env (TForce fc _ arg) = Resume <$> toLoc (bestFC ctx fc) <*> term ctx env arg
  term ctx env (TDelayed fc _ _) = Erased <$> toLoc (bestFC ctx fc)
  term ctx env (Meta fc n _ _) = reject (bestFC ctx fc) ctx.owner ProfTerm2 ("hole or metavariable " ++ show n)
  term ctx env (As fc _ _ pat) = term ctx env pat
  term ctx env tm@(App fc _ _) = let (fn, args) = spine tm [] in application ctx env fc fn args
  term ctx env tm@(Ref fc _ _) = application ctx env fc tm []
  term ctx env (Bind fc _ _ _) = internal (bestFC ctx fc) "a binder in a runtime position (FE-TR-3)"

  suspend : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> {n : Nat} ->
            Ctx -> List (VarInfo n) -> FC -> TT vars -> Core (Term n)
  suspend ctx env fc arg = do
    loc <- toLoc (bestFC ctx fc)
    body <- term ctx env arg
    lbl <- label
    maybe (internal fc "a delayed term that is not well scoped") pure (delay loc lbl body)

  application : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> {n : Nat} ->
                Ctx -> List (VarInfo n) -> FC -> TT vars -> List (TT vars) -> Core (Term n)
  application ctx env afc (Ref rfc nt name) args = do
    let fc = bestFC ctx rfc
    loc <- toLoc fc
    def <- lookupDef fc ctx.owner name
    let full = fullname def
    case definition def of
      PMDef _ params _ _ _ => call fc loc full (length params) (type def) args
      DCon tag arity _ => constructor fc loc def arity args
      TCon {} => pure (Erased loc)
      Builtin {arity} op => primitive fc loc full arity op args
      ForeignDef arity _ => case ioPrim full of
        Just op => ioCall fc loc arity op (type def) args
        Nothing => reject fc ctx.owner ProfEsc1 ("foreign function " ++ show full)
      ExternDef arity => case ioPrim full of
        Just op => ioCall fc loc arity op (type def) args
        Nothing => reject fc ctx.owner ProfEsc1 ("extern function " ++ show full)
      Hole {} => reject fc ctx.owner ProfTerm2 ("hole " ++ show full)
      _ => internal fc ("a reference to " ++ show full ++ " (FE-TR-3)")
    where
      -- Arguments: values of type parameters, erased ones, runtime ones.
      arguments : Loc -> List (Quantity, PKind) -> List (TT vars) -> Core (List (Term n))
      arguments loc kinds as = traverse arg (zip kinds as)
        where
          arg : ((Quantity, PKind), TT vars) -> Core (Term n)
          arg ((_, RuntimeParam _), a) = term ctx env a
          arg _ = pure (Erased loc)

      isImplementation : TT vars -> Bool
      isImplementation (Local _ _ idx _) = case getAt idx env of
        Just (Static _) => True
        _ => False
      isImplementation _ = False

      argValue : TT vars -> Maybe ArgValue
      argValue a = Just (MkArgValue (closeNormalise afc env a) (solved (closeWritten afc env a)) (isImplementation a))

      argValues : List (TT vars) -> ArgValues
      argValues = map argValue

      applyRest : Loc -> Term n -> List (TT vars) -> Core (Term n)
      applyRest loc f [] = pure f
      applyRest loc f (a :: as) = applyRest loc (App loc f !(term ctx env a)) as

      finish : Loc -> List (Quantity, PKind) -> List (Term n) ->
               ({m : Nat} -> List (Term m) -> Term m) -> List (TT vars) -> Core (Term n)
      finish loc kinds given mk extra = do
        let missing = drop (length given) kinds
        if null missing
           then applyRest loc (mk given) extra
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
          kindTy (q, _) = (Q0, V ErasedT)

      call : FC -> Loc -> Name -> Nat -> ClosedTerm -> List (TT vars) -> Core (Term n)
      call fc loc name arity ty as = do
        (kinds, _) <- classify fc ctx.owner arity ty (argValues (take arity as))
        let statics = map (\k => case k of
                                    (_, TypeParam t) => Just t
                                    (_, DictParam t) => Just t
                                    _ => Nothing) kinds
        inst <- request fc ctx.owner name statics
        given <- arguments loc kinds (take arity as)
        finish loc kinds given (Call loc inst) (drop arity as)

      constructor : FC -> Loc -> GlobalDef -> Nat -> List (TT vars) -> Core (Term n)
      constructor fc loc def arity as = do
        (kinds, resTy) <- classify fc ctx.owner arity (type def) (argValues (take arity as))
        Just inst <- dataOf <$> coreType fc ctx.owner ProfType4 !(normaliseClosed resTy)
          | Nothing => internal fc "a constructor of a type that is not data (FE-TR-3)"
        given <- arguments loc kinds (take arity as)
        -- The data type's parameters come first and are not fields; a type
        -- argument after them is an erased field.
        st <- get TState
        let cid = MkConId inst (show (fullname def))
        let nparams = maybe 0 (length . (.params)) (lookup cid st.cons)
        finish loc (drop nparams kinds) (drop nparams given) (ConApp loc cid) (drop arity as)

      primitive : FC -> Loc -> Name -> Nat -> PrimFn ar -> List (TT vars) -> Core (Term n)
      primitive fc loc name arity op as = case op of
        BelieveMe => reject fc ctx.owner ProfEsc1 "believe_me"
        Crash => reject fc ctx.owner ProfEsc1 "idris_crash"
        Neg DoubleType => supported
        Neg IntegerType => supported
        Neg _ => reject fc ctx.owner ProfPrim2 "negate (SEM-EXCL-1)"
        ShiftL _ => reject fc ctx.owner ProfPrim2 "shift left (SEM-EXCL-1)"
        ShiftR _ => reject fc ctx.owner ProfPrim2 "shift right (SEM-EXCL-1)"
        _ => supported
        where
          supported : Core (Term n)
          supported = case primOp op of
            Nothing => reject fc ctx.owner ProfPrim2 ("primitive " ++ show name)
            Just p => do
              args' <- traverse (term ctx env) (take arity as)
              let kinds = map (\t => (QW, RuntimeParam t)) (opArgs p)
              finish loc kinds args' (PrimApp loc p) (drop arity as)

      ioCall : FC -> Loc -> Nat -> IOOp -> ClosedTerm -> List (TT vars) -> Core (Term n)
      ioCall fc loc arity op ty as = do
        (kinds, resTy) <- classify fc ctx.owner arity ty []
        Just res <- dataOf <$> coreType fc ctx.owner ProfType4 !(normaliseClosed resTy)
          | Nothing => internal fc "an IO primitive with an unexpected type (FE-TR-3)"
        given <- arguments loc kinds (take arity as)
        finish loc kinds given (\xs => Effect loc op xs res) (drop arity as)
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


      applyAll : Loc -> Term n -> List (TT vars) -> Core (Term n)
      applyAll loc f [] = pure f
      applyAll loc f (a :: as) = applyAll loc (App loc f !(term ctx env a)) as

------------------------------------------------------------------------------
-- Case trees (FE-TR-4)
------------------------------------------------------------------------------

||| The variables a constructor alternative binds for its fields, in the
||| alternative's scope: the first field innermost.
fieldInfos : {n : Nat} -> (bs : List Binder) -> List (VarInfo (length bs + n))
fieldInfos bs = zipWith (\i, b => Bound (weakenN n i) (Just b.type)) (Data.Fin.List.allFins (length bs)) bs

toBinder : Field -> Binder
toBinder f = MkBinder f.quantity f.type

mutual
  tree : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> {n : Nat} ->
         Ctx -> List (VarInfo n) -> CaseTree vars -> Core (Term n)
  tree ctx env (STerm _ tm) = term ctx env tm
  -- FE-TR-4, SEM-DATA-2: Idris proved it cannot be reached. An `Unmatched`
  -- leaf of a covering definition (PROF-FN-5) is one too: a definition whose
  -- clauses are all impossible has only that leaf. In a definition with
  -- missing cases it is one of them, and crashes (SEM-CRASH-2).
  tree ctx env (Unmatched msg) =
    if ctx.complete then Unreachable <$> toLoc ctx.fc
    else (\l => Crash l ("unhandled input for " ++ ctx.owner)) <$> toLoc ctx.fc
  tree ctx env Impossible = Unreachable <$> toLoc ctx.fc
  tree ctx env (Case idx _ scTy alts) = do
    loc <- toLoc ctx.fc
    case getAt idx env of
      Just (Bound i (Just (V WorldT))) => case alts of
        [ConstCase WorldVal rhs] => tree ctx env rhs
        _ => internal ctx.fc "an unexpected match on the world (FE-TR-4)"
      Just (Bound i (Just t)) => case dataOf t of
        Just inst => do
          (conAlts, def) <- conAlternatives ctx env inst alts
          st <- get TState
          -- Constructors the tree leaves out are impossible: the definition
          -- is covering (PROF-FN-5), so they become `Unreachable`.
          let missing = case (def, lookup inst st.datas) of
                          (Nothing, Just dt) => filter (\c => not (any (\(MkAlt k _ _) => k == c.id) conAlts)) dt.cons
                          _ => []
          -- Missing constructors are impossible in a covering definition,
          -- and crash otherwise (SEM-CRASH-2).
          let absurd = map (\c => MkAlt c.id (map toBinder c.fields)
                                   (if ctx.complete then Unreachable loc
                                    else Crash loc ("unhandled input for " ++ ctx.owner))) missing
          pure (Case loc i (conAlts ++ absurd) def)
        Nothing => do
          (litAlts, def) <- litAlternatives ctx env alts
          let Just def = def <|> (if ctx.complete then Nothing
                                  else Just (Crash loc ("unhandled input for " ++ ctx.owner)))
            | Nothing => reject ctx.fc ctx.owner ProfFn5 "a literal match without a default"
          pure (CaseLit loc i litAlts def)
      -- A match on an implementation selects its alternative now (FE-TR-6).
      Just (Static t) => staticCase ctx env t alts
      _ => internal ctx.fc "a match on a compile-time value (FE-TR-4)"

  ||| A match on a compile-time value: the implementation is reduced to its
  ||| constructor, and the alternative's variables stand for its arguments.
  staticCase : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> {n : Nat} ->
               Ctx -> List (VarInfo n) -> ClosedTerm -> List (CaseAlt vars) -> Core (Term n)
  staticCase ctx env t alts = do
    Just (cn, cargs) <- whnf 64 t
      | Nothing => reject ctx.fc ctx.owner ProfHeap1
                     ("an implementation that does not reduce to its constructor: " ++ showTT t ++ " (FE-TR-6)")
    cn <- toFullNames cn
    erased <- erasedArgs cn
    pick cn (zipWith info (erased ++ replicate (length cargs) False) cargs) alts
    where
      info : Bool -> ClosedTerm -> VarInfo n
      info True v = TypeValue v
      info False v = Static v
      pick : Name -> List (VarInfo n) -> List (CaseAlt vars) -> Core (Term n)
      pick cn infos (ConCase k _ args rhs :: rest) = do
        k <- toFullNames k
        if k /= cn then pick cn infos rest else do
          when (length args /= length infos) $
            internal ctx.fc ("constructor " ++ show cn ++ " binds an unexpected number of arguments")
          tree ctx (infos ++ env) rhs
      pick cn infos (DefaultCase rhs :: _) = tree ctx env rhs
      pick cn infos (_ :: rest) = pick cn infos rest
      pick cn infos [] = internal ctx.fc ("no alternative for " ++ show cn ++ " (FE-TR-6)")

  conAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> {n : Nat} ->
                    Ctx -> List (VarInfo n) -> DataId -> List (CaseAlt vars) ->
                    Core (List (Alt n), Maybe (Term n))
  conAlternatives ctx env inst [] = pure ([], Nothing)
  conAlternatives ctx env inst (ConCase cn _ args rhs :: rest) = do
    def <- lookupDef ctx.fc ctx.owner cn
    let cid = MkConId inst (show (fullname def))
    st <- get TState
    let Just info = lookup cid st.cons
      | Nothing => internal ctx.fc ("unknown constructor " ++ cid.name ++ " of " ++ inst.name)
    let bs = map toBinder info.con.fields
    let bound = map TypeValue info.params ++ fieldInfos {n} bs ++ map (weakenInfo (length bs)) env
    when (length info.params + length bs /= length args) $
      reject ctx.fc ctx.owner FeTtc1 ("constructor " ++ cid.name ++ " binds an unexpected number of arguments")
    body <- tree ctx bound rhs
    (alts, def') <- conAlternatives ctx env inst rest
    pure (MkAlt cid bs body :: alts, def')
  conAlternatives ctx env inst (DefaultCase rhs :: _) = pure ([], Just !(tree ctx env rhs))
  conAlternatives ctx env inst (DelayCase {} :: _) =
    reject ctx.fc ctx.owner ProfTerm2 "a match on a lazy value"
  conAlternatives ctx env inst (ConstCase {} :: _) =
    internal ctx.fc "a constant alternative in a constructor match (FE-TR-4)"

  litAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> {n : Nat} ->
                    Ctx -> List (VarInfo n) -> List (CaseAlt vars) ->
                    Core (List (Lit, Term n), Maybe (Term n))
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

isTotal : {auto c : Ref Ctxt Defs} -> FC -> Name -> Core Bool
isTotal fc n = do
  t <- catch (checkTotal fc n) (\_ => pure Unchecked)
  pure (case t of
          IsTerminating => True
          _ => False)

||| A definition of a library module, whose `%inline` is its author's hint
||| (ELIM-G-13). Idris also marks small user definitions `Inline` on its own.
library : String -> Bool
library n = any (`isPrefixOf` n) (the (List String) ["Builtin.", "PrimIO.", "Prelude.", "IdrisMLIR.IO."])

||| A case or with block that Idris made from part of a definition.
isBlock : Name -> Bool
isBlock (NS _ n) = isBlock n
isBlock (CaseBlock _ _) = True
isBlock (WithBlock _ _) = True
isBlock _ = False

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
  update TState { fns $= insert p.inst (MkTFn p.inst owner (length kinds) (map binder (fromList kinds)) result body loc tot
                                              (isBlock p.name) (any (== Inline) (flags def) && library owner))
                , fnOrder $= (:< p.inst) }
  where
    binder : (Quantity, PKind) -> Binder
    binder (q, RuntimeParam t) = MkBinder q t
    binder _ = MkBinder Q0 (V ErasedT)
    info : Fin k -> (Quantity, PKind) -> VarInfo k
    info i (_, TypeParam t) = TypeValue t
    info i (_, DictParam t) = Static t
    info i (_, RuntimeParam t) = Bound i (Just t)
    info i _ = Bound i (Just (V ErasedT))

drain : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Core ()
drain = do
  st <- get TState
  case st.queue of
    [] => pure ()
    (p :: rest) => do
      put TState ({ queue := rest, current := p.path } st)
      translateInstance p
      drain

assemble : {auto s : Ref TState TS} -> FnId -> EntryKind -> Core Source
assemble root entry = do
  st <- get TState
  let datas = mapMaybe (\n => lookup n st.datas) (st.dataOrder <>> [])
  let fns = mapMaybe (\n => lookup n st.fns) (st.fnOrder <>> [])
  pure (MkSource datas fns root entry)

||| A `main : Int` program (FE-ENTRY-2): the root is `main` itself.
export
translateIntProgram : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Name -> Core Source
translateIntProgram main = do
  root <- request EmptyFC (show main) main []
  drain
  assemble root IntEntry

||| An IO program (FE-ENTRY-4). The root is `unsafePerformIO main` written
||| directly as world-passing code, which is what `unsafePerformIO`,
||| `unsafeCreateWorld` and `unsafeDestroyWorld` mean:
|||   root w = case main of MkIO f => case f w of MkIORes res w' => res
||| So `%MkWorld` never appears (PROF-IO-3).
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
  let Just ioInst = dataOf mainFn.result
    | Nothing => notIO
  let Just [mkIO] = (.cons) <$> lookup ioInst st.datas
    | _ => notIO
  let [MkField _ (FunT _ (V WorldT) (V (DataT resInst)))] = mkIO.fields
    | _ => notIO
  let Just [mkRes] = (.cons) <$> lookup resInst st.datas
    | _ => notIO
  let [MkField qx resTy, MkField qw (V WorldT)] = mkRes.fields
    | _ => notIO
  loc <- toLoc (location !(lookupDef fc owner main))
  -- w is variable 0; each binder below adds one innermost variable.
  let body : Term 1
      body = Let loc QW (Call loc inst [])                                   -- m
               (Case loc 0
                  [MkAlt mkIO.id [MkBinder QW (FunT Q1 (V WorldT) (V (DataT resInst)))]  -- f
                     (Let loc QW (App loc (Var loc 0) (Var loc 2))           -- r = f w
                        (Case loc 0
                           [MkAlt mkRes.id [MkBinder qx resTy, MkBinder qw (V WorldT)]  -- x, w'
                              (Var loc 0)]
                           Nothing))]
                  Nothing)
  let rootId = MkFnId "$idris-mlir.root"
  src <- assemble rootId IOEntry
  pure ({ fns $= (++ [MkTFn rootId rootId.name 1 [MkBinder Q1 (V WorldT)] resTy body loc True False False]) } src)
