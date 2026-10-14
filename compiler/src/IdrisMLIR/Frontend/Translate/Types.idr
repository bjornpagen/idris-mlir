||| Types and data instances: the Core type of a closed Idris type, and the
||| monomorphic data instances it names, registered as they are met.
module IdrisMLIR.Frontend.Translate.Types

import Core.CompileExpr
import Core.Context
import Core.Core
import Core.Env
import Core.Hash
import Core.Normalise
import Core.TT
import Core.Value
import Libraries.Data.NatSet

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Hooks
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Prof
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Rule
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.List
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.String

%default covering

export
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
export
nameKey : Name -> String
nameKey (NS ns n) = show (NS ns (UN (Basic (nameKey n))))
nameKey (DN str n) = str ++ "{" ++ nameKey n ++ "}"
nameKey (CaseBlock outer i) = "case block " ++ show i ++ " in " ++ outer
nameKey (WithBlock outer i) = "with block " ++ show i ++ " in " ++ outer
nameKey n = show n

||| The definition's full name and its arguments' normal forms.
||| The printed form is made unique by a suffix if a different instance
||| already prints the same way.
export
instanceName : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               Name -> List (Maybe ClosedTerm) -> Core String
instanceName n args = do
  n' <- toFullNames n
  args' <- timedSz "instanceName.toFullNames" (sum (map (maybe 0 ttSize) args)) (traverse (\a => case a of
                             Just t => Just <$> toFullNames t
                             Nothing => pure Nothing) args)
  st <- get TState
  -- Instances are bucketed by a hash of their arguments, so a request
  -- compares its arguments with the few instances in its bucket, not with
  -- every instance of the definition.
  key <- timed "instanceName.hash" (pure () >>= \_ => pure (nameKey n' ++ "#" ++ show (hash args')))
  let same = fromMaybe [] (lookup key st.named)
  count ("instanceName.bucket." ++ show (length same))
  -- An instance already named is found by its arguments; only a new one
  -- is printed, since printing a dictionary's normal form is the costly
  -- part and most requests are repeats.
  found <- timed "instanceName.find" (pure () >>= \_ => pure (find ((== args') . fst) same))
  case found of
    Just (_, name) => pure name
    Nothing => do
      shown <- timed "instanceName.show" (traverse showTT (catMaybes args'))
      let printed = nameKey n' ++ (if null shown then "" else "[" ++ joinBy ", " shown ++ "]")
      let owners = fromMaybe [] (lookup printed st.owners)
      let name = suffixed printed (length owners)
      put TState ({ owners $= insert printed (owners ++ [(n', args')])
                  , named $= insert key ((args', name) :: same) } st)
      pure name
  where
    suffixed : String -> Nat -> String
    suffixed p Z = p
    suffixed p k = p ++ "'" ++ show k

||| A stand-in for the `i`th binder of a constructor's type.
marker : Nat -> ClosedTerm
marker i = Ref EmptyFC Bound (MN "idris-mlir-binder" (cast i))

||| Which arguments of a constructor are the data type's parameters, whose
||| values the data instance gives: each binder of its type is replaced by a
||| marker, and the markers found at the parameter positions of the return
||| type name them. Only a parameter the instance keeps (`kept`, a type)
||| has its value there; at any other, the instance is erased, and an
||| argument the constructor holds at runtime (`MkTag : (n : Nat) -> Tag
||| n`, which Idris finds at the same place in every constructor) is a
||| field.
paramLayout : List Nat -> List Nat -> ClosedTerm -> List (Maybe Nat)
paramLayout params kept ty =
  let (n, ret, rigs) = markAll 0 ty
      args = snd (spine ret [])
      found = mapMaybe (\p => (,p) <$> (getAt p args >>= markerOf)) params
  in map (\i => lookup i found >>= given (getAt i rigs)) (upto n)
  where
    upto : Nat -> List Nat
    upto Z = []
    upto (S k) = upto k ++ [k]
    markAll : Nat -> ClosedTerm -> (Nat, ClosedTerm, List RigCount)
    markAll i (Bind _ _ (Pi _ rig _ _) sc) =
      let (n, ret, rigs) = markAll (S i) (subst (marker i) sc) in (n, ret, rig :: rigs)
    markAll i t = (i, t, [])
    given : Maybe RigCount -> Nat -> Maybe Nat
    given rig p = if elem p kept || maybe True isErased rig then Just p else Nothing
    markerOf : ClosedTerm -> Maybe Nat
    markerOf (Ref _ _ (MN "idris-mlir-binder" k)) = Just (cast k)
    markerOf _ = Nothing

||| The parameters of a type constructor: Idris's, and those its own
||| reading of the constructors' types misses because a type hides its
||| binders behind a definition (`a -@ LList a -@ LList a`, where Idris sees
||| only an application of `-@`). On the normalised types, as Idris does: a
||| position is a parameter when every occurrence of the type, as a field's
||| result and as the constructor's, has there the same binder of the
||| constructor, and no earlier position has it too. Such an argument is
||| never refined by a match, so reading it as a parameter changes nothing
||| Idris proved.
dataParams : {auto c : Ref Ctxt Defs} -> GlobalDef -> Core (List Nat)
dataParams def = case definition def of
  TCon arity params _ _ _ cons _ => do
    let idris = filter (\i => elem i params) [0 .. minus arity 1]
    if length idris == arity then pure idris else do
      defs <- get Ctxt
      tys <- traverse (\n => map (map type) (lookupCtxtExact n (gamma defs))) (fromMaybe [] cons)
      found <- the (Core (List Nat)) $ case the (Maybe (List ClosedTerm)) (sequence tys) of
        Just ts@(_ :: _) => do
          sets <- traverse (\t => uniform <$> (normaliseClosed t >>= toFullNames)) ts
          pure (filter (\i => all (elem i) sets) [0 .. minus arity 1])
        _ => pure []
      pure (filter (\i => elem i idris || elem i found) [0 .. minus arity 1])
  _ => pure []
  where
    markerOf : ClosedTerm -> Maybe Nat
    markerOf (Ref _ _ (MN "idris-mlir-binder" k)) = Just (cast k)
    markerOf _ = Nothing
    -- The arguments of an occurrence of the type, as binders; only a
    -- binder's first position counts.
    binders : List ClosedTerm -> List (Maybe Nat)
    binders = go []
      where
        go : List Nat -> List ClosedTerm -> List (Maybe Nat)
        go seen [] = []
        go seen (a :: as) = case markerOf a of
          Just k => if elem k seen then Nothing :: go seen as else Just k :: go (k :: seen) as
          Nothing => Nothing :: go seen as
    -- The occurrence of the type that a type returns, under its binders.
    occurrence : ClosedTerm -> Maybe (List ClosedTerm)
    occurrence (Bind bfc _ (Pi {}) sc) = occurrence (subst (Erased bfc Placeholder) sc)
    occurrence tm = case spine tm [] of
      (Ref _ _ n, args) => if n == fullname def then Just args else Nothing
      _ => Nothing
    merge : List (Maybe Nat) -> List (Maybe Nat) -> List (Maybe Nat)
    merge = zipWith (\a, b => if a == b then a else Nothing)
    -- The parameter positions one constructor allows.
    uniform : ClosedTerm -> List Nat
    uniform ty = go 0 Nothing ty
      where
        positions : List (Maybe Nat) -> List Nat
        positions ms = mapMaybe (\(i, m) => map (const i) m) (zip [0 .. length ms] ms)
        add : Maybe (List (Maybe Nat)) -> ClosedTerm -> Maybe (List (Maybe Nat))
        add acc t = case occurrence t of
          Just args => Just (maybe (binders args) (\ms => merge ms (binders args)) acc)
          Nothing => acc
        go : Nat -> Maybe (List (Maybe Nat)) -> ClosedTerm -> List Nat
        go i acc (Bind _ _ (Pi _ _ _ a) sc) = go (S i) (add acc a) (subst (marker i) sc)
        go i acc ret = maybe [] positions (add acc ret)

||| Does a term mention the stand-in for the `k`th binder of a constructor's
||| type?
mentionsMarker : Nat -> TT vs -> Bool
mentionsMarker k (Ref _ _ (MN "idris-mlir-binder" i)) = cast i == k
mentionsMarker k (Bind _ _ b sc) = mentionsMarker k (binderType b) || mentionsMarker k sc
mentionsMarker k (App _ f a) = mentionsMarker k f || mentionsMarker k a
mentionsMarker k (As _ _ a p) = mentionsMarker k p
mentionsMarker k (TDelayed _ _ t) = mentionsMarker k t
mentionsMarker k (TDelay _ _ t a) = mentionsMarker k t || mentionsMarker k a
mentionsMarker k (TForce _ _ t) = mentionsMarker k t
mentionsMarker k (Meta _ _ _ args) = any (mentionsMarker k) args
mentionsMarker _ _ = False

||| The positions of a type constructor's arguments that are types and that
||| a value of it represents: its parameters whose kind is a universe, and
||| which some constructor holds at runtime or names in the type of one of
||| its arguments. Only they tell instances apart; every other argument (an
||| index, or a value parameter such as `Equal`'s `x`) is compile-time
||| information. A parameter no constructor names is a phantom (the state
||| thread `s` of base's `ST s a` and `STRef s a`): every type it is given
||| has values of one representation, so one instance serves them all, and
||| a type abstraction over it, `{0 s : Type} -> ST s Int`, is a value of
||| that one instance once applied to whatever type.
typeParamsGo : {auto c : Ref Ctxt Defs} -> GlobalDef -> Core (List Nat)
typeParamsGo def = case definition def of
  TCon arity _ _ _ _ cons _ => do
    params <- dataParams def
    defs <- get Ctxt
    -- A record's parameter kinds may be solved metavariables, and a type
    -- may be declared through a definition of its kind (`data CaseTree :
    -- Scoped`, where `Scoped = Scope -> Type`): its binders are those of
    -- the normal form.
    ty <- normaliseClosed (type def)
    let values = kinds ty
    let types = filter (\i => elem i params && not (fromMaybe False (getAt i values))) [0 .. minus arity 1]
    tys <- traverse (\n => map (map type) (lookupCtxtExact n (gamma defs))) (fromMaybe [] cons)
    -- Without its constructors, every type parameter counts.
    if null types then pure [] else case the (Maybe (List ClosedTerm)) (sequence tys) of
      Just ts@(_ :: _) => do
        conTys <- traverse normaliseClosed ts
        pure (filter (\i => any (represents i) conTys) types)
      _ => pure types
  _ => pure []
  where
    binders : Nat -> ClosedTerm -> (List (RigCount, ClosedTerm), ClosedTerm)
    binders i (Bind _ _ (Pi _ rig _ a) sc) =
      let (bs, ret) = binders (S i) (subst (marker i) sc) in ((rig, a) :: bs, ret)
    binders i t = ([], t)
    -- Does a constructor represent the parameter at position `p` of the
    -- type it returns: does it hold the binder there at runtime, or name it
    -- in the type of any of its arguments? Anything but a binder there
    -- counts.
    represents : Nat -> ClosedTerm -> Bool
    represents p conTy =
      let (bs, ret) = binders 0 conTy in
      case getAt p (snd (spine ret [])) of
        Just (Ref _ _ (MN "idris-mlir-binder" k)) =>
          maybe True (not . isErased . fst) (getAt (cast k) bs) ||
          any (mentionsMarker (cast k) . snd) bs
        _ => True
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

typeParams : {auto c : Ref Ctxt Defs} -> GlobalDef -> Core (List Nat)
typeParams def = if not fixTP then typeParams' def else do
  let k = show (fullname def)
  Nothing <- lookupTP k
    | Just r => pure r
  r <- typeParams' def
  insertTP k r
  pure r
  where
    typeParams' : GlobalDef -> Core (List Nat)
    typeParams' def = timed "typeParams.compute" (typeParamsGo def)

||| The type arguments of a type constructor, and its arity.
paramPositions : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 String -> Name -> Core (Maybe (Nat, List Nat))
paramPositions owner n = timed "paramPositions" $ if not fixTP then compute else do
  Nothing <- lookupPP n
    | Just r => pure r
  r <- compute
  insertPP n r
  pure r
  where
    compute : Core (Maybe (Nat, List Nat))
    compute = do
      def <- lookupDef EmptyFC owner n
      case definition def of
        TCon arity _ _ _ _ _ _ => pure (Just (arity, !(typeParams def)))
        _ => pure Nothing

||| A closed type normalised as far as a representation reads it: to its
||| head, and then, under a function type, the binder's type and the
||| scope; under a suspension, what it suspends; and under a type
||| constructor, its type parameters (`typeParams`), each in turn. Every
||| other argument of a type constructor, an index or a value parameter,
||| is erased: no representation reads it (`dataInstance` erases it too),
||| and it may be any computation on a runtime value (`Tree (parse wdir)`),
||| which the compiler must not run. Anything else is its normal form.
export
normaliseTypeKeeping : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Maybe Name -> ClosedTerm -> Core ClosedTerm
normaliseTypeKeeping own tm = timedSz "normaliseType" (ttSize tm) $ do
  defs <- get Ctxt
  when !tracing $ trace ("normaliseType enter " ++ substr 0 300 (show !(toFullNames tm)))
  r <- go defs 0 True !(nfOpts withAll defs [] tm)
  when !tracing $ trace "normaliseType exit"
  pure r
  where
    under : Defs -> Int -> Bool -> FC -> (x : Name) -> (Defs -> Closure [] -> Core (NF [])) -> Core (Term [x])
    -- `top`: the result type of a constructor's type, whose arguments
    -- (`own`'s, all of them) say where its parameters are.
    go : Defs -> Int -> Bool -> NF [] -> Core ClosedTerm
    go defs k top (NTCon fc n ar args) = do
      mine <- if top && isJust own then (\f => Just f == own) <$> toFullNames n else pure False
      keep <- the (Core (List Nat)) $ if mine then pure [0 .. length args] else do
        Just (_, keep) <- paramPositions "" n
          | Nothing => pure [0 .. length args]
        pure keep
      args' <- traverse (\(i, (afc, cl)) =>
                           if Prelude.Types.elem i keep then (afc,) <$> go defs k False !(evalClosure defs cl)
                                          else pure (afc, Erased afc Placeholder))
                        (zip [0 .. length args] args)
      pure (applyStackWithFC (Ref fc (TyCon ar) n) args')
    go defs k top (NBind fc x (Pi pfc rig pinfo a) sc) = do
      a' <- go defs k False !(evalClosure defs a)
      pinfo' <- traverse (quote defs []) pinfo
      pure (Bind fc x (Pi pfc rig pinfo' a') !(under defs k top fc x sc))
    go defs k top (NBind fc x (Lam pfc rig pinfo a) sc) = do
      a' <- go defs k False !(evalClosure defs a)
      pinfo' <- traverse (quote defs []) pinfo
      pure (Bind fc x (Lam pfc rig pinfo' a') !(under defs k False fc x sc))
    go defs k top (NDelayed fc r t) = TDelayed fc r <$> go defs k False t
    go defs k top nf = do
      when !tracing $ trace "normaliseType quote"
      quote defs [] nf

    under defs k top fc x sc = do
      let var = MN "idris-mlir-pi" k
      body <- go defs (k + 1) top !(sc defs (toClosure defaultOpts [] (Ref fc Bound var)))
      pure (refsToLocals (Add x var None) body)

export
normaliseType : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> ClosedTerm -> Core ClosedTerm
normaliseType = normaliseTypeKeeping Nothing

||| `closeNormalise` as far as a representation reads the term
||| (`normaliseType`).
export
closeNormaliseType : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                     FC -> List (VarInfo a) -> TT vars -> Core ClosedTerm
closeNormaliseType fc env tm = normaliseType (closeApplied fc env tm)

||| The normaliser a representation's consumer uses: the full normal form,
||| or, with the measured fix, `normaliseType`.
export
normaliseRepr : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> ClosedTerm -> Core ClosedTerm
normaliseRepr = if fixRepr then normaliseType else normaliseClosed

export
closeNormaliseRepr : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                     FC -> List (VarInfo a) -> TT vars -> Core ClosedTerm
closeNormaliseRepr fc env tm = if fixRepr then closeNormaliseType fc env tm else closeNormalise fc env tm

||| Does a type mention what the test picks other than as an index of an
||| inductive family? Indices exist at compile time only, so a type that
||| mentions something only there has one representation whatever it is.
export
outsideIndices : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 (ClosedTerm -> Bool) -> String -> ClosedTerm -> Core Bool
outsideIndices picks owner (Bind bfc _ (Pi _ _ _ a) sc) = do
  -- The argument is erased in the result: a dependency on it is one on an
  -- erased value, unless it is only an index. A quantity-0 binder of kind
  -- Type, `{0 s : Type} -> ST s Int` (the argument of base's runST), is
  -- compile-time only: a value of the type is applied to a type and to
  -- nothing at runtime, so it has the representation of its body with the
  -- binder erased (`coreType`), one representation for whatever type it is
  -- applied to. The body may then mention the binder only where no
  -- representation needs it, as an index or a phantom parameter
  -- (`typeParams`); anywhere else (`{0 s : Type} -> List s`) the
  -- representation would depend on it, and the type is refused.
  inA <- outsideIndices picks owner a
  inB <- outsideIndices picks owner (subst (Erased bfc Placeholder) sc)
  pure (inA || inB)
-- A suspension of a type depends on what the type depends on: `coreType`
-- represents `Lazy t` as a suspension of `t`'s representation.
outsideIndices picks owner (TDelayed _ _ t) = outsideIndices picks owner t
-- A type-level function (the second component's type of a dependent pair)
-- as a function type, when the representation normaliser has erased its
-- indices.
outsideIndices picks owner tm@(Bind bfc _ (Lam _ _ _ a) sc) =
  if not fixRepr then pure (picks tm) else do
    inA <- outsideIndices picks owner a
    inB <- outsideIndices picks owner (subst (Erased bfc Placeholder) sc)
    pure (inA || inB)
outsideIndices picks owner tm = case spine tm [] of
  (Ref _ (TyCon _) n, args) => do
    Just (_, ps) <- paramPositions owner n
      | Nothing => pure (picks tm)
    rs <- traverse (outsideIndices picks owner) (mapMaybe (\p => getAt p args) ps)
    pure (any id rs)
  _ => pure (picks tm)

||| Does a type mention an erased value other than as an index of an
||| inductive family? Indices exist at compile time only ("Inductive families
||| need not store their indices", Brady, McBride and McKinna, 2003).
export
erasedOutsideIndices : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                       String -> ClosedTerm -> Core Bool
erasedOutsideIndices = outsideIndices anyErased

||| The arguments of a constructor application that are fields, by layout.
export
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
export
arrange : List (Maybe Nat) -> List ClosedTerm -> List (VarInfo a) -> List (VarInfo a)
arrange [] ps fs = []
arrange (Just p :: ls) ps fs = TypeValue (fromMaybe (Erased EmptyFC Placeholder) (getAt p ps)) :: arrange ls ps fs
arrange (Nothing :: ls) ps (f :: fs) = f :: arrange ls ps fs
arrange (Nothing :: ls) ps [] = []

||| A type with the indices of every inductive family in it erased, so that
||| `Vect 3 Double` and `Vect n Double` name one instance.
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
||| is unique there. The full name is its location.
export
shortName : Name -> String
shortName (NS _ n) = shortName n
shortName n = show n

||| The role Idris gives a constructor of a `Nat`-like type
||| (`TTImp.ProcessData.calcNaty`): the type is `NatT`, zero is `0`, and the
||| successor adds one, as Idris's own backends represent every such type.
||| Idris counts only runtime arguments, so `Fin` is one too.
public export
data NatRole = Zero | Succ

export
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
||| from names.
natLike : {auto c : Ref Ctxt Defs} -> GlobalDef -> Core Bool
natLike def = case definition def of
  TCon _ _ _ _ _ (Just cons) _ => do
    defs <- get Ctxt
    roles <- traverse (\n => map (>>= natRole) (lookupCtxtExact n (gamma defs))) cons
    pure (not (null roles) && all isJust roles)
  _ => pure False

||| Is a type the type of implementations, whatever binds a value of it?
||| Idris passes a function's constraints to its `where` functions and its
||| case and with blocks as explicit arguments, so the binder does not say.
||| An implementation is a value of an interface, which is what Idris
||| declared as one, in its table of interfaces (`TS.interfaces`); of a
||| pair of implementations, which is how Idris gives a tuple of
||| constraints (`(Show a, Show b) => Show (a, b)`), each one found by
||| search: its pair type (`%pair`) is the one Idris's search takes apart;
||| or of a function to an implementation, a constraint over the values of
||| its arguments (`{y : a} -> Show (p y)`, which `Show (DPair a p)` takes).
||| A type whose values Idris finds by search is not an interface for that:
||| an auto-implicit argument of any other type (`{auto c : Ref Ctxt
||| Defs}`, a proof Idris searches for) is an ordinary argument, and any
||| data type may ask for the unique search an interface's record has
||| (`[uniqueSearch]`).
export
implementationType : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                     TT vars -> Core Bool
implementationType (Bind _ _ (Pi {}) sc) = implementationType sc
implementationType ty = case spine ty [] of
  (Ref _ (TyCon _) n, args) => do
    defs <- get Ctxt
    Just def <- lookupCtxtExact n (gamma defs)
      | Nothing => pure False
    st <- get TState
    if contains (fullname def) st.interfaces then pure True else
      case args of
        [a, b] => do
          False <- isPairType (fullname def)
            | True => do
                first <- implementationType a
                if first then implementationType b else pure False
          pure False
        _ => pure False
  _ => pure False

||| Does a binder of this quantity and (normalised) type bind an
||| implementation (`implementationType`)? The same answer classifies a
||| function's parameters (`classify`) and a constructor's fields
||| (`dataInstance`), so that what a construction site passes as a
||| compile-time value, the constructor holds as one.
export
dictionaryBinder : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                   RigCount -> TT vars -> Core Bool
dictionaryBinder rig ty = if isErased rig then pure False else implementationType ty

mutual
  ||| The Core type of a closed, normalised type. A type that has no runtime
  ||| representation is reported under `rule`: `ValueType`, or `DependentField`
  ||| for a constructor field.
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
    arg <- binderOf rig (coreType fc owner rule a)
    let rest = subst (Erased bfc Placeholder) sc
    when (not (isErased rig) && !(erasedOutsideIndices owner rest)) $
      reject fc owner rule "a function type that depends on its argument"
    rt <- coreType fc owner rule !(timed "coreType.normRest" (normaliseRepr rest))
    pure (FunT arg rt)
  -- `Inf` is a suspension like `Lazy`.
  coreType fc owner rule (TDelayed _ _ t) = LazyT <$> coreType fc owner rule t
  coreType fc owner rule tm = case spine tm [] of
    (Ref rfc (TyCon _) n, args) => do
      def <- timed "coreType.lookupDef" (lookupDef fc owner n)
      -- A word type is a machine word whatever its arguments: what a
      -- `Ptr t` points to names what its handle holds, not its
      -- representation.
      nl <- timed "coreType.natLike" (natLike def)
      _ <- timed "coreType.hooks" (pure () >>= \_ => pure (isWordType (hooksOf (fullname def))))
      if nl
         then pure NatT
         else if isWordType (hooksOf (fullname def))
           then pure (IntT UInt64)
         else case arrayElementOf (hooksOf (fullname def)) of
           Just (r, Just e) => pure (ArrayT r e)
           Just (r, Nothing) => case args of
             [a] => ArrayT r <$> coreType fc owner rule !(normaliseRepr a)
             _ => internal fc "the array type without its one element type"
           Nothing => DataT <$> dataInstance fc owner n !(timed "coreType.normArgs"
                                                      (if fixRepr then (\t => snd (spine t [])) <$> normaliseType tm
                                                                  else traverse normaliseClosed args))
    (TType _ _, _) => reject fc owner rule "Type in a runtime position"
    (Erased _ _, _) => reject fc owner rule "a type that depends on a runtime or erased value"
    _ => reject fc owner rule ("unsupported runtime type " ++ !(showTT tm))

  ||| Registers a monomorphic data instance.
  export
  dataInstance : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 FC -> String -> Name -> List ClosedTerm -> Core DataId
  dataInstance fc owner tcon args0 = timed "dataInstance" $ do
    def <- lookupDef fc owner tcon
    let tname = show (fullname def)
    -- An index is compile-time information; instances differ by
    -- their parameters only.
    keep <- timed "dataInstance.typeParams" (typeParams def)
    args <- timed "dataInstance.eraseIndices" $ traverse (\(i, a) => if elem i keep then eraseIndices owner a
                                  else pure (Erased EmptyFC Placeholder))
                     (zip [0 .. length args0] args0)
    inst <- MkDataId <$> timed "dataInstance.instanceName" (instanceName (fullname def) (map Just args))
    st <- get TState
    -- An instance being registered is referred to by its own fields when
    -- it is recursive; `assemble` makes it a box.
    if isJust (lookup inst st.datas) || contains inst st.building then pure inst else do
      TCon arity _ _ _ _ datacons _ <- pure (definition def)
        | _ => reject fc owner ValueType (tname ++ " is not a data type")
      params <- dataParams def
      let Just datacons = datacons
        | Nothing => reject fc owner DataType (tname ++ " has no known constructors")
      put TState ({ building $= insert inst } st)
      loc <- toLoc (location def)
      let ps = params
      count "dataInstance.new"
      conList <- timed "dataInstance.constructors" (traverse (constructor inst args ps keep) datacons)
      let sorted = sortBy (\a, b => compare a.tag b.tag) conList
      update TState { building $= delete inst
                    , datas $= insert inst (MkDecl inst (shown tname) sorted loc)
                    , dataOrder $= (:< inst) }
      pure inst
    where
      ||| The constructor's arguments: a parameter is the instance's, anything
      ||| else is a field, with its type when it holds an implementation.
      walk : String -> FC -> List ClosedTerm -> List (Maybe Nat) -> ClosedTerm ->
             Core (List (Binder, Maybe ClosedTerm))
      walk cname dfc targs (Just p :: ls) (Bind bfc _ (Pi {}) sc) =
        walk cname dfc targs ls (subst (fromMaybe (Erased bfc Placeholder) (getAt p targs)) sc)
      walk cname dfc targs (Nothing :: ls) (Bind bfc _ (Pi _ rig _ a) sc) = do
        field <- if isErased rig then pure (Gone, Nothing) else do
          a' <- normaliseRepr a
          -- An implementation is a compile-time value of the instance, not
          -- a runtime field (`Dictionaries`).
          if !(dictionaryBinder rig a') then pure (Gone, Just a') else do
            when !(erasedOutsideIndices cname a') $ do
              reject dfc cname DependentField ("a field type that depends on another field: " ++ !(showTT a'))
            t <- coreType dfc cname DependentField a'
            pure (Held (useOf rig) t, Nothing)
        rest <- walk cname dfc targs ls (subst (Erased bfc Placeholder) sc)
        pure (field :: rest)
      walk _ _ _ _ _ = pure []

      constructor : DataId -> List ClosedTerm -> List Nat -> List Nat -> Name -> Core Con
      constructor inst targs ps keep dcon = do
        def <- lookupDef fc owner dcon
        let cname = show (fullname def)
        DCon tag arity _ <- pure (definition def)
          | _ => reject fc owner CompiledModule (cname ++ " is not a constructor")
        loc <- toLoc (location def)
        -- The type as written may hide its binders behind a definition
        -- (`a -@ b` is `(1 _ : a) -> b`); its normal form shows each one,
        -- with the quantity that makes a field linear.
        ty <- if fixRepr then normaliseTypeKeeping (Just !(toFullNames tcon)) (type def) else normaliseClosed (type def)
        let layout = paramLayout ps keep ty
        -- Every match binds `arity` arguments: a layout of another length
        -- would misplace every field after the first difference.
        when (length layout /= arity) $
          internal (location def) (cname ++ " has " ++ show arity ++ " arguments, but its type binds " ++
                                   show (length layout))
        fields <- walk cname (location def) targs layout ty
        let con = MkCon (MkConId inst (shortName (fullname def))) (shown cname) (cast tag) (map fst fields) loc
        let dicts = mapMaybe (\(i, (_, d)) => (i,) <$> d) (zip [0 .. length fields] fields)
        update TState { cons $= insert con.id (MkConLayout targs layout dicts con) }
        pure con
