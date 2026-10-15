-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
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
import Libraries.Data.NatSet

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Keys
import IdrisMLIR.Frontend.Translate.Shapes
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Registry
import IdrisMLIR.Syntax.Idr
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
      args = snd (getFnArgs ret)
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
    occurrence tm = case getFnArgs tm of
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
||| which some constructor holds at runtime or names in the type of an
||| argument it holds at runtime. Only they tell instances apart; every other argument (an
||| index, or a value parameter such as `Equal`'s `x`) is compile-time
||| information. A parameter no constructor names is a phantom (the state
||| thread `s` of base's `ST s a` and `STRef s a`): every type it is given
||| has values of one representation, so one instance serves them all, and
||| a type abstraction over it, `{0 s : Type} -> ST s Int`, is a value of
||| that one instance once applied to whatever type.
typeParams : {auto c : Ref Ctxt Defs} -> GlobalDef -> List Nat -> Core (List Nat)
typeParams def params = case definition def of
  TCon arity _ _ _ _ cons _ => do
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
    case the (Maybe (List ClosedTerm)) (sequence tys) of
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
    -- in the type of an argument it holds at runtime? An erased argument
    -- has no representation, whatever its type names (`Subset`'s
    -- predicate, the type of its erased proof). Anything but a binder
    -- there counts.
    represents : Nat -> ClosedTerm -> Bool
    represents p conTy =
      let (bs, ret) = binders 0 conTy in
      case getAt p (snd (getFnArgs ret)) of
        Just (Ref _ _ (MN "idris-mlir-binder" k)) =>
          maybe True (not . isErased . fst) (getAt (cast k) bs) ||
          any (\(rig, a) => not (isErased rig) && mentionsMarker (cast k) a) bs
        _ => True
    -- Is a kind certainly the type of values, not a universe: a variable
    -- (`x : a`) or a data type (`n : Nat`)?
    valueKind : TT vs -> Bool
    valueKind (Local {}) = True
    valueKind tm = case getFnArgs tm of
      (Ref _ (TyCon _) _, _) => True
      (PrimVal _ _, _) => True
      _ => False
    kinds : TT vs -> List Bool
    kinds (Bind _ _ (Pi _ _ _ a) sc) = valueKind a :: kinds sc
    kinds _ = []

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

||| An extent's dimension: static where its normal form is a literal, a
||| `Nat`-like chain of successors ending at zero (read from Idris's flags,
||| never from names) or a non-negative integer; dynamic otherwise, since
||| an erased extent is the value's own, never a constant it is assumed to
||| be.
extentDim : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core Dim
extentDim = go 0
  where
    go : Nat -> ClosedTerm -> Core Dim
    go k tm = case getFnArgs tm of
      (Ref _ (DataCon _ _) n, args) => do
        defs <- get Ctxt
        Just def <- lookupCtxtExact n (gamma defs)
          | Nothing => pure Dynamic
        case natRole def of
          Just Zero => pure (Static k)
          Just Succ => case last' args of
            Just pred => go (S k) pred
            Nothing => pure Dynamic
          Nothing => pure Dynamic
      (PrimVal _ c, []) => case constantLit c of
        Just (LBig i) => pure (if i >= 0 then Static (k + integerToNat i) else Dynamic)
        _ => pure Dynamic
      _ => pure Dynamic

||| The dimensions of a value array's shape at an instance, one per axis of
||| its form, outermost first. A shape whose form is not known (a variable
||| no instance fixes, a recursion that builds it deeper) has no rank, and
||| a tensor has nothing else.
export
shapeDims : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            FC -> String -> ClosedTerm -> Core (List Dim)
shapeDims fc owner shape = do
  shape' <- normaliseClosed shape
  let Just extents = shapeSpine shape'
    | Nothing => reject fc owner Polymorphism ("a shape whose rank no analysis fixes: " ++ !(showTT shape'))
  traverse extentDim extents

||| What the translation reads of a type constructor's definition: its
||| parameters (`dataParams`), the type parameters among them
||| (`typeParams`), and whether it is `Nat`-like, found once per type
||| constructor (`tyCons`).
tyConFacts : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             GlobalDef -> Core TyConFacts
tyConFacts def = do
  let key = nameKey (fullname def)
  case lookup key (!(get TState)).tyCons of
    Just known => pure known
    Nothing => do
      ps <- dataParams def
      facts <- MkTyConFacts ps <$> typeParams def ps <*> natLike def
      update TState { tyCons $= insert key facts }
      pure facts

||| The type arguments of a type constructor, and its arity.
paramPositions : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 String -> Name -> Core (Maybe (Nat, List Nat))
paramPositions owner n = do
  def <- lookupDef EmptyFC owner n
  case definition def of
    TCon arity _ _ _ _ _ _ => pure (Just (arity, (!(tyConFacts def)).typeParams))
    _ => pure Nothing

||| Does a type mention what the test picks other than as an index of an
||| inductive family? Indices exist at compile time only, so a type that
||| mentions something only there has one representation whatever it is.
export
outsideIndices : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 (ClosedTerm -> Bool) -> String -> ClosedTerm -> Core Bool
outsideIndices picks owner (Bind bfc _ (Pi _ rig _ a) sc) = do
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
  -- An argument taken with quantity 0 is not passed: its type has no
  -- representation, whatever it mentions (`(0 _ : IsConClause p) -> ...`).
  inA <- if isErased rig then pure False else outsideIndices picks owner a
  inB <- outsideIndices picks owner (subst (Erased bfc Placeholder) sc)
  pure (inA || inB)
-- A suspension of a type depends on what the type depends on: `coreType`
-- represents `Lazy t` as a suspension of `t`'s representation.
outsideIndices picks owner (TDelayed _ _ t) = outsideIndices picks owner t
-- A type family, at a type parameter (`DPair a (\x => Vect x Int)`,
-- `SortedDMap k (\_ => v)`): its values have its body's representation,
-- whatever its argument, so the body is what may depend on something, as
-- a function type's result is.
outsideIndices picks owner (Bind bfc _ (Lam {}) sc) =
  outsideIndices picks owner (subst (Erased bfc Placeholder) sc)
outsideIndices picks owner tm = case getFnArgs tm of
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

||| A type with the indices of every inductive family in it erased, so that
||| `Vect 3 Double` and `Vect n Double` name one instance. A type family is
||| a lambda (`SortedDMap k (\_ => v)`, `DPair a (\x => p x)`): the indices
||| inside its body are erased the same way, so two families that differ
||| only there name one instance.
eraseIndices : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               {vars : _} -> String -> TT vars -> Core (TT vars)
eraseIndices owner (Bind fc x b sc) = do
  b' <- traverse (eraseIndices owner) b
  sc' <- eraseIndices owner sc
  pure (Bind fc x b' sc')
eraseIndices owner tm = case getFnArgs tm of
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
implementationType ty = case getFnArgs ty of
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

||| A value array of these dimensions of this element: an array of value
||| arrays is one, the element's dimensions after these. An array of
||| records is a tensor of the record, whatever the record holds: the
||| dialect splits it into one tensor per field.
valueArrayOf : List Dim -> Ty -> Ty
valueArrayOf ds (TensorT cs el) = TensorT (ds ++ cs) el
valueArrayOf ds e = TensorT ds e

mutual
  ||| The Core type of a closed, normalised type. A type that has no runtime
  ||| representation is reported under `rule`: `ValueType`, or `DependentField`
  ||| for a constructor field. An argument of quantity 0 is no argument at
  ||| runtime, so a function type that takes one is the type of its result.
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
    let rest = subst (Erased bfc Placeholder) sc
    if isErased rig
       then normaliseClosed rest >>= coreType fc owner rule
       else do
         arg <- coreBinder fc owner rule rig a
         when !(erasedOutsideIndices owner rest) $
           reject fc owner rule "a function type that depends on its argument"
         rt <- coreType fc owner rule !(normaliseClosed rest)
         -- A closure's type is one for every extent its values are made at.
         pure (FunT ({ type $= dynamicDims } arg) (dynamicDims rt))
  -- `Inf` is a suspension like `Lazy`.
  coreType fc owner rule (TDelayed _ _ t) = LazyT . dynamicDims <$> coreType fc owner rule t
  coreType fc owner rule tm = case getFnArgs tm of
    (Ref rfc (TyCon _) n, args) => do
      def <- lookupDef fc owner n
      -- A word type is a machine word whatever its arguments: what a
      -- `Ptr t` points to names what its handle holds, not its
      -- representation.
      let hs = hooksOf (fullname def)
      if (!(tyConFacts def)).natLike
         then pure NatT
         else if hs.wordType
           then pure (IntT UInt64)
         else case hs.orderedArray of
           Just (ds, Just e) => pure (MemRefT ds e)
           Just (ds, Nothing) => case args of
             [a] => do
               e <- coreType fc owner rule !(normaliseClosed a)
               case e of
                 TensorT _ _ => reject fc owner rule ("an array a world orders holding an array value: " ++ !(showTT tm))
                 _ => pure (MemRefT ds e)
             _ => internal fc "the array type without its one element type"
           Nothing =>
             if hs.valueArray
               then case args of
                 [shape, a] => do
                   ds <- shapeDims fc owner shape
                   e <- coreType fc owner rule !(normaliseClosed a)
                   case e of
                     MemRefT _ _ => reject fc owner rule ("an array value holding an array a world orders: " ++ !(showTT tm))
                     _ => pure (valueArrayOf ds e)
                 _ => internal fc "a value array without its shape and element"
               else snd <$> dataInstance fc owner n !(traverse normaliseClosed args)
    (TType _ _, _) => reject fc owner rule "Type in a runtime position"
    (Erased _ _, _) => reject fc owner rule "a type that depends on a runtime or erased value"
    _ => do reject fc owner rule ("unsupported runtime type " ++ !(showTT tm))

  ||| Registers a monomorphic data instance, once, and gives the type its
  ||| values have. A data type with one constructor and exactly one runtime
  ||| field is no declaration: a value of it is the field's value, so its
  ||| type is the field's. One that a field referred to while it was being
  ||| registered is declared whatever its shape (`data Rose = MkRose (List
  ||| Rose)`), since a value of it contains itself and its type cannot be
  ||| its field's.
  export
  dataInstance : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 FC -> String -> Name -> List ClosedTerm -> Core (DataId, Ty)
  dataInstance fc owner tcon args0 = do
    def <- lookupDef fc owner tcon
    let tname = show (fullname def)
    -- An index is compile-time information; instances differ by
    -- their parameters only.
    facts <- tyConFacts def
    let params = facts.params
    let keep = facts.typeParams
    args <- traverse (\(i, a) => if elem i keep
                                    then eraseIndices owner !(canonicalTypeArg a)
                                    else pure (Erased EmptyFC Placeholder))
                     (zip [0 .. length args0] args0)
    (ident, key) <- instanceKey (fullname def)
                                (map (\(i, a) => if elem i keep then Just a else Nothing) (zip [0 .. length args] args))
    let inst = MkDataId ident
    st <- get TState
    case (lookup inst st.datas, lookup inst st.newtypes) of
      (Just _, _) => pure (inst, DataT inst)
      (_, Just b) => pure (inst, typeOf b)
      _ =>
        -- An instance being registered is referred to by its own fields
        -- when it is recursive: it is declared, whatever its shape.
        if contains inst st.building
          then do
            update TState { reentered $= insert inst }
            pure (inst, DataT inst)
          else do
            TCon arity _ _ _ _ datacons _ <- pure (definition def)
              | _ => reject fc owner ValueType (tname ++ " is not a data type")
            let Just datacons = datacons
              | Nothing => reject fc owner DataType (tname ++ " has no known constructors")
            put TState ({ building $= insert inst } st)
            loc <- toLoc (location def)
            conList <- traverse (constructor inst args params keep) datacons
            let sorted = sortBy (\a, b => compare (fst a).tag (fst b).tag) conList
            again <- contains inst . (.reentered) <$> get TState
            let fields : List Binder = case sorted of
                           [(_, kinds)] => mapMaybe fieldBinder kinds
                           _ => []
            case (again, fields) of
              (False, [b]) => do
                update TState { building $= delete inst, newtypes $= insert inst b }
                pure (inst, typeOf b)
              _ => do
                update TState { building $= delete inst
                              , datas $= insert inst (MkData inst key (map fst sorted) loc
                                                             (fromMaybe SumKind.Plain (hooksOf (fullname def)).sumOf))
                              , dataOrder $= (:< inst) }
                pure (inst, DataT inst)
    where
      ||| The constructor's arguments: a parameter is the instance's, one of
      ||| quantity 0 is none, an implementation is a compile-time value of
      ||| the instance (`Dictionaries`), anything else is the next field.
      walk : String -> FC -> List ClosedTerm -> Nat -> List (Maybe Nat) -> ClosedTerm -> Core (List ArgKind)
      walk cname dfc targs i (Just p :: ls) (Bind bfc _ (Pi {}) sc) = do
        let v = fromMaybe (Erased bfc Placeholder) (getAt p targs)
        (Param v ::) <$> walk cname dfc targs i ls (subst v sc)
      walk cname dfc targs i (Nothing :: ls) (Bind bfc _ (Pi _ rig _ a) sc) = do
        let rest = subst (Erased bfc Placeholder) sc
        if isErased rig then (ErasedArg ::) <$> walk cname dfc targs i ls rest else do
          a' <- normaliseClosed a
          if !(dictionaryBinder rig a') then (DictArg a' ::) <$> walk cname dfc targs i ls rest else do
            when !(erasedOutsideIndices cname a') $ do
              reject dfc cname DependentField ("a field type that depends on another field: " ++ !(showTT a'))
            b <- coreBinder dfc cname DependentField rig a'
            (Field i b a' ::) <$> walk cname dfc targs (S i) ls rest
      walk _ _ _ _ _ _ = pure []

      constructor : DataId -> List ClosedTerm -> List Nat -> List Nat -> Name -> Core (Con, List ArgKind)
      constructor inst targs ps keep dcon = do
        def <- lookupDef fc owner dcon
        let cname = show (fullname def)
        DCon tag arity _ <- pure (definition def)
          | _ => reject fc owner CompiledModule (cname ++ " is not a constructor")
        loc <- toLoc (location def)
        -- The type as written may hide its binders behind a definition
        -- (`a -@ b` is `(1 _ : a) -> b`); its normal form shows each one,
        -- with the quantity that makes a field linear.
        ty <- normaliseClosed (type def)
        let layout = paramLayout ps keep ty
        -- Every match binds `arity` arguments: a layout of another length
        -- would misplace every field after the first difference.
        when (length layout /= arity) $
          internal (location def) (cname ++ " has " ++ show arity ++ " arguments, but its type binds " ++
                                   show (length layout))
        kinds <- walk cname (location def) targs 0 layout ty
        let con = MkCon (MkConId inst (shortName (fullname def))) (shown cname) (cast tag) (mapMaybe fieldBinder kinds) loc
                        (fromMaybe CtorRole.Plain (hooksOf (fullname def)).plays)
        update TState { cons $= insert con.id (MkConLayout kinds (fullname def) con) }
        pure (con, kinds)

  ||| The data instance a closed, normalised type names, when it is a data
  ||| type and not a natural, a machine word or an array of either kind: the
  ||| instance, and
  ||| the type its values have, which is its field's for a type with one
  ||| runtime field.
  export
  dataOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           FC -> String -> ClosedTerm -> Core (Maybe (DataId, Ty))
  dataOf fc owner tm = case getFnArgs tm of
    (Ref _ (TyCon _) n, args) => do
      def <- lookupDef fc owner n
      let hs = hooksOf (fullname def)
      natural <- (.natLike) <$> tyConFacts def
      if natural || hs.wordType || isJust hs.orderedArray || hs.valueArray then pure Nothing else do
        args' <- traverse normaliseClosed args
        Just <$> dataInstance fc owner n args'
    _ => pure Nothing

  ||| The binder of a position of this type at this rig: the Core type at
  ||| the rig's quantity, taken through a type with one runtime field,
  ||| whose value is its field's, so that what the binder binds is the
  ||| field at the product of the rig's quantity and the field's, as
  ||| Idris uses the field of a value bound at the rig. Erasing such a
  ||| type to its field's type alone would give a binder at the rig's
  ||| quantity the field's value at that quantity, and a field Idris
  ||| binds unrestricted (the one field of `!* a`) would be held linear.
  export
  coreBinder : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               FC -> String -> Rule -> RigCount -> ClosedTerm -> Core Binder
  coreBinder fc owner rule rig tm = do
    t <- coreType fc owner rule tm
    inst <- dataOf fc owner tm
    st <- get TState
    let q = case inst of
              Just (i, _) => case lookup i st.newtypes of
                               Just (MkBinder fq _) => quantityTimes (quantityOf rig) fq
                               Nothing => quantityOf rig
              Nothing => quantityOf rig
    pure (MkBinder q t)
