-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Types and data instances: the Core type of a closed Idris type, and the
||| monomorphic data instances it names, registered as they are met.
module IdrisMLIR.Frontend.Translate.Types

import Core.Context
import Core.Core
import Core.Env
import Core.TT
import Libraries.Data.List.Finite
import Libraries.Data.NatSet

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Finite
import IdrisMLIR.Frontend.Growth.Template
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Given
import IdrisMLIR.Frontend.Translate.Keys
import IdrisMLIR.Frontend.Translate.Shapes
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Registry
import IdrisMLIR.Syntax.Idr
import IdrisMLIR.Term
import IdrisMLIR.Proof.Forms
import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Types

import Control.WellFounded
import Data.DPair
import Data.Fin
import Data.List
import Data.List.Elem
import Data.List.Quantifiers
import Decidable.Equality
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.String

%default total

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

||| The binder a name stands in for (`marker`), by its number. It and
||| `marker` are the one spelling of the stand-in.
markerNumber : Name -> Maybe Nat
markerNumber (MN "idris-mlir-binder" k) = Just (cast k)
markerNumber _ = Nothing

||| The binder a term stands in for, if it is a stand-in.
markerOf : TT vs -> Maybe Nat
markerOf (Ref _ _ n) = markerNumber n
markerOf _ = Nothing

||| Which arguments of a constructor are the data type's parameters, whose
||| values the data instance gives: each binder of its type is replaced by a
||| marker, and the markers found at the parameter positions of the return
||| type name them. Only a parameter the instance keeps (`kept`, a type)
||| has its value there; at any other, the instance is erased, and an
||| argument the constructor holds at runtime (`MkTag : (n : Nat) -> Tag
||| n`, which Idris finds at the same place in every constructor) is a
||| field.
export
paramLayout : List Nat -> List Nat -> ClosedTerm -> List (Maybe Nat)
paramLayout params kept ty =
  let (n, ret, rigs) = markAll none 0 ty
      args = snd (getFnArgs ret)
      found = mapMaybe (\p => (,p) <$> (getAt p args >>= markerOf)) params
  in map (\i => lookup i found >>= given (getAt i rigs)) (iterateN n S 0)
  where
    markAll : Given vs -> Nat -> TT vs -> (Nat, ClosedTerm, List RigCount)
    markAll g i (Bind _ _ (Pi _ rig _ _) sc) =
      let (n, ret, rigs) = markAll (give (marker i) g) (S i) sc in (n, ret, rig :: rigs)
    markAll g i t = (i, close g t, [])
    given : Maybe RigCount -> Nat -> Maybe Nat
    given rig p = if elem p kept || maybe True isErased rig then Just p else Nothing

||| The constructors of a type constructor, each with its type normalised,
||| every name full: a type may hide its binders behind a definition (`a -@
||| b` is `(1 _ : a) -> b`), and a record's parameter kinds may be solved
||| metavariables. Nothing when Idris does not know the constructors (a
||| type declared without them) or the context lacks one. What the
||| translation reads of a type constructor is read from these
||| (`tyConFacts`).
constructorsOf : {auto c : Ref Ctxt Defs} -> GlobalDef -> Core (Maybe (List (GlobalDef, ClosedTerm)))
constructorsOf def = case definition def of
  TCon _ _ _ _ _ (Just cons) _ => do
    defs <- get Ctxt
    found <- traverse (\n => lookupCtxtExact n (gamma defs)) cons
    case the (Maybe (List GlobalDef)) (sequence found) of
      Just cs => Just <$> traverse (\d => (d,) <$> (normaliseClosed (type d) >>= toFullNames)) cs
      Nothing => pure Nothing
  _ => pure Nothing

||| The parameters of a type constructor: Idris's, and those its own
||| reading of the constructors' types misses because a type hides its
||| binders behind a definition (`a -@ LList a -@ LList a`, where Idris sees
||| only an application of `-@`). On the normalised types, as Idris does: a
||| position is a parameter when every occurrence of the type, as a field's
||| result and as the constructor's, has there the same binder of the
||| constructor, and no earlier position has it too. Such an argument is
||| never refined by a match, so reading it as a parameter changes nothing
||| Idris proved. Given the constructors' types (`constructorsOf`).
dataParams : GlobalDef -> Maybe (List ClosedTerm) -> List Nat
dataParams def conTys = case definition def of
  TCon arity params _ _ _ _ _ =>
    let positions : List Nat = iterateN arity S 0
        idris = List.filter (\i => elem i params) positions in
    if length idris == arity then idris else
      let found : List Nat = case conTys of
                    Just ts@(_ :: _) => let sets = map uniform ts in
                                        List.filter (\i => all (elem i) sets) positions
                    _ => [] in
      List.filter (\i => elem i idris || elem i found) positions
  _ => []
  where
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
    occurrence : Given vs -> TT vs -> Maybe (List ClosedTerm)
    occurrence g (Bind bfc _ (Pi {}) sc) = occurrence (give (Erased bfc Placeholder) g) sc
    occurrence g tm = case getFnArgs tm of
      (Ref _ _ n, args) => if n == fullname def then Just (map (close g) args) else Nothing
      _ => Nothing
    merge : List (Maybe Nat) -> List (Maybe Nat) -> List (Maybe Nat)
    merge = zipWith (\a, b => if a == b then a else Nothing)
    -- The parameter positions one constructor allows.
    uniform : ClosedTerm -> List Nat
    uniform ty = go none 0 Nothing ty
      where
        positions : List (Maybe Nat) -> List Nat
        positions ms = mapMaybe (\(i, m) => map (const i) m) (zip [0 .. length ms] ms)
        add : Maybe (List (Maybe Nat)) -> ClosedTerm -> Maybe (List (Maybe Nat))
        add acc t = case occurrence none t of
          Just args => Just (maybe (binders args) (\ms => merge ms (binders args)) acc)
          Nothing => acc
        go : Given vs -> Nat -> Maybe (List (Maybe Nat)) -> TT vs -> List Nat
        go g i acc (Bind _ _ (Pi _ _ _ a) sc) = go (give (marker i) g) (S i) (add acc (close g a)) sc
        go g i acc ret = maybe [] positions (add acc (close g ret))

||| Does a term mention the stand-in for the `k`th binder of a constructor's
||| type?
mentionsMarker : Nat -> TT vs -> Bool
mentionsMarker k = mentions (\t => markerOf t == Just k)

||| A constructor's type read under its binders, each given its stand-in
||| (`marker`): each binder's quantity and type, and the type it returns.
conBinders : Given vs -> Nat -> TT vs -> (List (RigCount, ClosedTerm), ClosedTerm)
conBinders g i (Bind _ _ (Pi _ rig _ a) sc) =
  let (bs, ret) = conBinders (give (marker i) g) (S i) sc in ((rig, close g a) :: bs, ret)
conBinders g i t = ([], close g t)

||| Is a kind certainly the type of values, not a universe: a variable
||| (`x : a`) or a data type (`n : Nat`)?
valueKind : TT vs -> Bool
valueKind (Local {}) = True
valueKind tm = case getFnArgs tm of
  (Ref _ (TyCon _) _, _) => True
  (PrimVal _ _, _) => True
  _ => False

||| Whether each argument of a type constructor's kind is certainly a value
||| (`valueKind`), in order.
kinds : TT vs -> List Bool
kinds (Bind _ _ (Pi _ _ _ a) sc) = valueKind a :: kinds sc
kinds _ = []

||| The positions of a type constructor's arguments that are types and that
||| a value of it represents: its parameters whose kind is a universe, and
||| which some constructor holds at runtime or names in the type of an
||| argument it holds at runtime. Only they tell instances apart; every other argument (an
||| index, or a value parameter such as `Equal`'s `x`) is compile-time
||| information. A parameter no constructor names is a phantom (the state
||| thread `s` of base's `ST s a` and `STRef s a`): every type it is given
||| has values of one representation, so one instance serves them all, and
||| a type abstraction over it, `{0 s : Type} -> ST s Int`, is a value of
||| that one instance once applied to whatever type. Given its parameters
||| and its constructors' types (`constructorsOf`).
typeParams : {auto c : Ref Ctxt Defs} -> GlobalDef -> List Nat -> Maybe (List ClosedTerm) -> Core (List Nat)
typeParams def params conTys = case definition def of
  TCon arity _ _ _ _ _ _ => do
    -- A record's parameter kinds may be solved metavariables, and a type
    -- may be declared through a definition of its kind (`data CaseTree :
    -- Scoped`, where `Scoped = Scope -> Type`): its binders are those of
    -- the normal form.
    ty <- normaliseClosed (type def)
    let values = kinds ty
    let types = filter (\i => elem i params && not (fromMaybe False (getAt i values))) (iterateN arity S 0)
    -- Without its constructors, every type parameter counts.
    pure (case conTys of
            Just ts@(_ :: _) => filter (\i => any (represents i) ts) types
            _ => types)
  _ => pure []
  where
    -- Does a constructor represent the parameter at position `p` of the
    -- type it returns: does it hold the binder there at runtime, or name it
    -- in the type of an argument it holds at runtime? An erased argument
    -- has no representation, whatever its type names (`Subset`'s
    -- predicate, the type of its erased proof). Anything but a binder
    -- there counts.
    represents : Nat -> ClosedTerm -> Bool
    represents p conTy =
      let (bs, ret) = conBinders none 0 conTy in
      case getAt p (snd (getFnArgs ret)) >>= markerOf of
        Just k =>
          maybe True (not . isErased . fst) (getAt k bs) ||
          any (\(rig, a) => not (isErased rig) && mentionsMarker k a) bs
        Nothing => True

-- A split of candidates that holds one or more leaves fewer out.
0 shorter : (a, b : Nat) -> a + S b = n -> LT a n
shorter a b Refl = rewrite sym (plusSuccRightSucc a b) in LTESucc (lteAddRight a)

||| The positions of a type constructor's arguments the growth check
||| watches: its type parameters (`typeParams`, the keys), and every other
||| argument whose kind is a universe and that its values hold. A value
||| holds such an argument when a constructor that has its own binder there
||| holds a runtime argument whose type reaches that binder, through a
||| function type's argument or result, a suspension, or a represented
||| position of a type constructor (this one's, or another's type
||| parameters). It is the least such set: `L : a -> T a` makes `T`'s `a` a
||| position, and `PCons : P (a, a) -> P a`, whose index no value holds,
||| does not. An index is checked by the growth phase, never a key. Given
||| the type constructor's parameters, its type parameters and its
||| constructors' types (`constructorsOf`).
representedOf : {auto c : Ref Ctxt Defs} -> GlobalDef -> (params, keys : List Nat) -> List ClosedTerm -> Core (List Nat)
representedOf def ps keys conTys = case definition def of
  TCon arity _ _ _ _ _ _ => do
    ty <- normaliseClosed (type def)
    let values = kinds ty
    -- Every argument position: `[0 .. minus arity 1]` would be `[0]` at
    -- arity 0.
    let candidates@(_ :: _) = filter (\i => not (elem i ps) && not (fromMaybe False (getAt i values)))
                                     (iterateN arity S 0)
      | [] => pure (sort keys)
    held <- least keys conTys [] candidates (wellFounded _)
    pure (sort (keys ++ held))
  _ => pure []
  where
    -- The type parameters of another type constructor.
    keysOf : Name -> Core (List Nat)
    keysOf d = do
      defs <- get Ctxt
      Just ddef <- lookupCtxtExact d (gamma defs)
        | Nothing => pure []
      conTys <- map (map snd) <$> constructorsOf ddef
      typeParams ddef (dataParams ddef conTys) conTys

    mutual
      -- Does a type reach the stand-in for binder `k`, at the positions
      -- `own` of this type constructor?
      reaches : List Nat -> Nat -> TT vs -> Core Bool
      reaches own k (Ref _ _ n) = pure (markerNumber n == Just k)
      reaches own k (Bind _ _ (Pi _ rig _ a) sc) = do
        inA <- if isErased rig then pure False else reaches own k a
        if inA then pure True else reaches own k sc
      reaches own k (TDelayed _ _ t) = reaches own k t
      reaches own k tm = case getFnArgs tm of
        (Ref _ (TyCon _) d, args) => do
          ks <- if d == fullname def then pure own else keysOf d
          spine ks own k (length args) tm
        _ => pure False

      -- The arguments at positions `ks` of an application of `j`
      -- arguments, the last first, so that each is a subterm.
      spine : List Nat -> List Nat -> Nat -> Nat -> TT vs -> Core Bool
      spine ks own k (S j) (App _ f a) = do
        here <- if elem j ks then reaches own k a else pure False
        if here then pure True else spine ks own k j f
      spine _ _ _ _ _ = pure False

    -- Does a constructor whose return type has its own binder at `p` hold
    -- a runtime argument whose type reaches it?
    holds : List Nat -> Nat -> ClosedTerm -> Core Bool
    holds own p conTy =
      let (bs, ret) = conBinders none 0 conTy in
      case getAt p (snd (getFnArgs ret)) >>= markerOf of
        Just k => any id <$> traverse (\(rig, a) => if isErased rig then pure False else reaches own k a) bs
        Nothing => pure False

    -- The candidates of `out` the set `held` makes held, and the rest, as
    -- many between them as `out` has.
    among : List Nat -> List ClosedTerm -> List Nat -> (out : List Nat) ->
            Core (Subset (List Nat, List Nat) (\s => length (snd s) + length (fst s) = length out))
    among keys conTys held [] = pure (Element ([], []) Refl)
    among keys conTys held (p :: ps) = do
      Element (ins, outs) n <- among keys conTys held ps
      True <- any id <$> traverse (holds (keys ++ held) p) conTys
        | False => pure (Element (ins, p :: outs) (cong S n))
      pure (Element (p :: ins, outs) (trans (sym (plusSuccRightSucc _ _)) (cong S n)))

    -- The least set, from none: each round holds what the set so far makes
    -- held among the candidates still out, and the set is whole at a round
    -- that holds none. A round that holds one or more leaves fewer out, so
    -- the rounds descend on the candidates still out.
    least : List Nat -> List ClosedTerm -> List Nat -> (out : List Nat) ->
            (0 _ : Accessible LT (length out)) -> Core (List Nat)
    least keys conTys held out (Access fewer) = do
      Element (p :: ps, outs) n <- among keys conTys held out
        | Element ([], _) _ => pure held
      least keys conTys (held ++ p :: ps) outs (fewer _ (shorter _ _ n))

||| What a type constructor's values are as numbers, from its constructors
||| (`constructorsOf`): `Nat`-like when they carry Idris's `ZERO` and
||| `SUCC` flags, read from Idris's metadata, never from names; a `Chain`
||| when each also takes every argument at runtime, none at quantity 0. A
||| key keeps what a constructor takes at quantity 0 (`FS`'s index), so a
||| chain's values' keys are only their successors: `Nat`, but neither
||| `Fin` nor `Elem`, which are `Numeral`s.
natnessOf : Maybe (List (GlobalDef, ClosedTerm)) -> Natness
natnessOf (Just cons@(_ :: _)) =
  if not (all (isJust . natRole . fst) cons) then NotNat
    else if all (\(_, t) => all (not . isErased . fst) (fst (conBinders none 0 t))) cons then Chain
    else Numeral
natnessOf _ = NotNat

||| An extent's dimension: static where its normal form is a literal, a
||| `Nat`-like chain of successors ending at zero (read from Idris's flags,
||| never from names) or a non-negative integer; dynamic otherwise, since
||| an erased extent is the value's own, never a constant it is assumed to
||| be.
extentDim : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core Dim
extentDim = go 0
  where
    -- The role of the constructor a term is an application of.
    roleOf : ClosedTerm -> Core (Maybe NatRole)
    roleOf tm = case getFn tm of
      Ref _ (DataCon _ _) n => do
        defs <- get Ctxt
        pure (natRole =<< !(lookupCtxtExact n (gamma defs)))
      _ => pure Nothing
    -- A successor's predecessor is its last argument.
    go : Nat -> ClosedTerm -> Core Dim
    go k tm@(App _ _ pred) = case !(roleOf tm) of
      Just Zero => pure (Static k)
      Just Succ => go (S k) pred
      Nothing => pure Dynamic
    go k tm@(Ref _ (DataCon _ _) _) = case !(roleOf tm) of
      Just Zero => pure (Static k)
      _ => pure Dynamic
    go k (PrimVal _ c) = case constantLit c of
      Just (LBig i) => pure (if i >= 0 then Static (k + integerToNat i) else Dynamic)
      _ => pure Dynamic
    go k _ = pure Dynamic

||| The dimensions of a value array's shape at an instance, one per axis of
||| its form, outermost first. A shape whose form is not known (a variable
||| no instance fixes, a recursion that builds it deeper) has no rank, and
||| a tensor has nothing else.
shapeDims : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            FC -> String -> ClosedTerm -> Core (List Dim)
shapeDims fc owner shape = do
  shape' <- normaliseClosed shape
  let Just extents = shapeSpine shape'
    | Nothing => reject fc owner Polymorphism ("a shape whose rank no analysis fixes: " ++ !(showTT shape'))
  traverse extentDim extents

||| What the translation reads of a type constructor's definition, from its
||| constructors read once (`constructorsOf`): its parameters
||| (`dataParams`), the type parameters among them (`typeParams`), how it is
||| `Nat`-like (`natnessOf`), and the arguments its values hold
||| (`representedOf`), found once per type constructor (`tyCons`).
export
tyConFacts : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             GlobalDef -> Core TyConFacts
tyConFacts def = do
  defs <- get Ctxt
  -- A name the context does not hold has no address to keep its facts by.
  let Just key = definitionAddress (gamma defs) (fullname def)
    | Nothing => facts
  case lookup key (!(get TState)).tyCons of
    Just known => pure known
    Nothing => do
      found <- facts
      update TState { tyCons $= insert key found }
      pure found
  where
    facts : Core TyConFacts
    facts = do
      cons <- constructorsOf def
      let conTys = map (map snd) cons
      let ps = dataParams def conTys
      keys <- typeParams def ps conTys
      MkTyConFacts ps keys (natnessOf cons) <$> representedOf def ps keys (fromMaybe [] conTys)

||| The positions of a type constructor's arguments the growth check
||| watches (`representedOf`), read once per type constructor with its other
||| facts (`tyConFacts`).
export
represented : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> GlobalDef -> Core (List Nat)
represented def = (.represented) <$> tyConFacts def

||| The type arguments of a type constructor; nothing for a name that is
||| no type constructor.
paramPositions : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 String -> Name -> Core (Maybe (List Nat))
paramPositions owner n = do
  def <- lookupDef EmptyFC owner n
  case definition def of
    TCon {} => pure (Just (!(tyConFacts def)).typeParams)
    _ => pure Nothing

||| Does a type mention what the test picks other than as an index of an
||| inductive family? Indices exist at compile time only, so a type that
||| mentions something only there has one representation whatever it is.
export
outsideIndices : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 (ClosedTerm -> Bool) -> String -> ClosedTerm -> Core Bool
outsideIndices picks owner = within none
  where
    mutual
      within : Given vs -> TT vs -> Core Bool
      within g (Bind bfc _ (Pi _ rig _ a) sc) = do
        -- The argument is erased in the result: a dependency on it is one on
        -- an erased value, unless it is only an index. A quantity-0 binder
        -- of kind Type, `{0 s : Type} -> ST s Int` (the argument of base's
        -- runST), is compile-time only: a value of the type is applied to a
        -- type and to nothing at runtime, so it has the representation of
        -- its body with the binder erased (`coreType`), one representation
        -- for whatever type it is applied to. The body may then mention the
        -- binder only where no representation needs it, as an index or a
        -- phantom parameter (`typeParams`); anywhere else (`{0 s : Type} ->
        -- List s`) the representation would depend on it, and the type is
        -- refused. An argument taken with quantity 0 is not passed: its type
        -- has no representation, whatever it mentions (`(0 _ : IsConClause
        -- p) -> ...`).
        inA <- if isErased rig then pure False else within g a
        inB <- within (give (Erased bfc Placeholder) g) sc
        pure (inA || inB)
      -- A suspension of a type depends on what the type depends on:
      -- `coreType` represents `Lazy t` as a suspension of `t`'s
      -- representation.
      within g (TDelayed _ _ t) = within g t
      -- A type family, at a type parameter (`DPair a (\x => Vect x Int)`,
      -- `SortedDMap k (\_ => v)`): its values have its body's
      -- representation, whatever its argument, so the body is what may
      -- depend on something, as a function type's result is.
      within g (Bind bfc _ (Lam {}) sc) = within (give (Erased bfc Placeholder) g) sc
      within g tm = case getFnArgs tm of
        (Ref _ (TyCon _) n, args) => do
          Just ps <- paramPositions owner n
            | Nothing => pure (picks (close g tm))
          params g ps (length args) tm
        _ => pure (picks (close g tm))

      -- The arguments at the type parameters `ps` of an application of `k`
      -- arguments, the last first, so that each is a subterm.
      params : Given vs -> List Nat -> Nat -> TT vs -> Core Bool
      params g ps (S k) (App _ f a) = do
        here <- if elem k ps then within g a else pure False
        before <- params g ps k f
        pure (here || before)
      params g ps _ _ = pure False

||| Does a type mention an erased value other than as an index of an
||| inductive family? Indices exist at compile time only, so a value of the
||| family stores none.
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
  b' <- binder b
  sc' <- eraseIndices owner sc
  pure (Bind fc x b' sc')
  where
    binder : TTBinder (TT vars) -> Core (TTBinder (TT vars))
    binder (Lam bfc rig info ty) = Lam bfc rig info <$> eraseIndices owner ty
    binder (Let bfc rig v ty) = Let bfc rig <$> eraseIndices owner v <*> eraseIndices owner ty
    binder (Pi bfc rig info ty) = Pi bfc rig info <$> eraseIndices owner ty
    binder (PVar bfc rig info ty) = PVar bfc rig info <$> eraseIndices owner ty
    binder (PLet bfc rig v ty) = PLet bfc rig <$> eraseIndices owner v <*> eraseIndices owner ty
    binder (PVTy bfc rig ty) = PVTy bfc rig <$> eraseIndices owner ty
eraseIndices owner tm = case getFnArgs tm of
  (Ref _ (TyCon _) n, args) => do
    Just ps <- paramPositions owner n
      | Nothing => pure tm
    erase ps (length args) tm
  _ => pure tm
  where
    -- An application of `k` arguments with each one at a position not in
    -- `ps` erased, the last first, so that each is a subterm.
    erase : List Nat -> Nat -> TT vars -> Core (TT vars)
    erase ps (S k) (App _ f a) =
      App EmptyFC <$> erase ps k f <*> (if elem k ps then eraseIndices owner a else pure (Erased EmptyFC Placeholder))
    erase ps _ h = pure h

||| A constructor's name within its data type, the symbol of its `idr.ctor`:
||| a data type's constructors share its namespace, so the name without it
||| is unique there. The full name is its location.
export
shortName : Name -> String
shortName (NS _ n) = shortName n
shortName n = show n

||| A constructor's identity in a data instance: its tag as a position
||| among the constructors of the type its result is. Nothing when the
||| definition is no constructor, its type's constructors are not known,
||| or its tag is past them.
export
conIdOf : {auto c : Ref Ctxt Defs} -> DataId -> GlobalDef -> Core (Maybe ConId)
conIdOf inst def = do
  let DCon tag _ _ = definition def
    | _ => pure Nothing
  -- The type as written may hide its binders behind a definition (`a -@ b`
  -- is `(1 _ : a) -> b`), so the type constructor is read off its normal
  -- form, as `constructor` reads the layout.
  Just tn <- built <$> normaliseClosed (type def)
    | Nothing => pure Nothing
  defs <- get Ctxt
  Just tdef <- lookupCtxtExact tn (gamma defs)
    | Nothing => pure Nothing
  let TCon _ _ _ _ _ (Just cons) _ = definition tdef
    | _ => pure Nothing
  pure (MkConId inst <$> integerToFin (cast tag) (length cons))
  where
    -- The type constructor a constructor's type ends in, under its binders.
    built : TT vs -> Maybe Name
    built (Bind _ _ (Pi {}) sc) = built sc
    built tm = case getFnArgs tm of
      (Ref _ (TyCon _) tn, _) => Just tn
      _ => Nothing

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
implementationType ty = case getFn ty of
  Ref _ (TyCon _) n => do
    defs <- get Ctxt
    Just def <- lookupCtxtExact n (gamma defs)
      | Nothing => pure False
    st <- get TState
    if contains (fullname def) st.interfaces then pure True else
      case ty of
        App _ (App _ (Ref _ _ _) a) b => do
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

||| The registrations in progress: the bounds the growth check gave
||| (`TS.sizes`, which nothing changes while the translation runs), and the
||| links of the data instances being registered, the innermost first.
record Registering where
  constructor MkRegistering
  sizes : Bounds
  links : List (Link Form)

||| One list of links is another with one more in front: a link new to it,
||| and in the universe of links within the bounds.
data Pushed : List (Link Form) -> List (Link Form) -> List (Link Form) -> Type where
  Push : (0 _ : Not (Elem l ls)) -> (0 _ : Elem l u) -> Pushed u (l :: ls) ls

||| Why registering ends: each data instance registered pushes its link,
||| new to the chain and within the bounds, and the universe of links
||| within the bounds is finite (`Requests.Universe`), so each push leaves
||| less room in it (`Finite.room`).
0 Descending : Registering -> Type
Descending reg = Accessible (Pushed (Universe forms addresses reg.sizes)) reg.links

-- A chain of distinct links of the universe descends: each push leaves
-- room for fewer.
0 pushes : (u, ls : List (Link Form)) -> NoDup ls -> All (\l => Elem l u) ls ->
           Accessible LT (minus (length u) (length ls)) -> Accessible (Pushed u) ls
pushes u ls distinct inside (Access less) =
  Access (\ls', pushed => case pushed of
    Push {l} fresh member =>
      pushes u (l :: ls) (fresh :: distinct) (member :: inside)
             (less _ (room (fresh :: distinct) (member :: inside))))

-- The empty chain descends.
0 started : (b : Bounds) -> Descending (MkRegistering b [])
started b = pushes (Universe forms addresses b) [] [] [] (wellFounded _)

||| The growth check's bound on each argument a data instance is keyed by,
||| at its type constructor's node (`MkNode t []`), checked where the
||| instance is registered, on the arguments as the key holds them (its
||| `statics`, nothing where it holds none). A position given no bound, or
||| an argument above its bound, is a flow the check missed: the
||| compiler's error, never the program's.
boundsHold : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             FC -> String -> Address -> (statics : List (Maybe ClosedTerm)) -> Core ()
boundsHold fc what t statics = do
  st <- get TState
  for_ (mapMaybe (\(j, a) => (j,) <$> a) (zip (iterateN (length statics) S 0) statics)) $ \(j, a) => do
    (h, _) <- closedHeight AType a
    heightWithin fc what st.bounds (MkNode t [], j) h

mutual
  ||| The Core type of a type, read under binders whose values are given,
  ||| in the registration of the data instances on `chain` (`heldTypeIn`).
  coreTypeIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               (chain : Registering) -> (0 _ : Descending chain) ->
               Given vars -> FC -> String -> Rule -> TT vars -> Core Ty
  coreTypeIn chain acc g fc owner rule tm = fst <$> heldTypeIn chain acc g fc owner rule tm

  ||| The Core type of a type, read under binders whose values are given,
  ||| in the registration of the data instances on `chain`, and, for a data
  ||| instance that is no declaration, the binder of its one runtime field,
  ||| whose value its values are (`newtypes`). The type is normalised
  ||| (`coreType` normalises it once), so every part of it is too, and the
  ||| reading is structural. A type that has no runtime representation is
  ||| reported under `rule`: `ValueType`, or `DependentField` for a
  ||| constructor field. An argument of quantity 0 is no argument at
  ||| runtime, so a function type that takes one is the type of its result.
  heldTypeIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               (chain : Registering) -> (0 _ : Descending chain) ->
               Given vars -> FC -> String -> Rule -> TT vars -> Core (Ty, Maybe Binder)
  heldTypeIn chain acc g fc owner rule (PrimVal _ (PrT t)) = (, Nothing) <$> case intTy t of
    Just it => pure (IntT it)
    Nothing => case t of
      CharType => pure CharT
      DoubleType => pure DoubleT
      StringType => pure StrT
      WorldType => pure WorldT
      IntegerType => pure BigT
      _ => reject fc owner rule (show t ++ " in a runtime position")
  heldTypeIn chain acc g fc owner rule (Bind bfc x (Pi _ rig _ a) sc) = do
    let g' = give (Erased bfc Placeholder) g
    if isErased rig
       then (, Nothing) <$> coreTypeIn chain acc g' fc owner rule sc
       else do
         arg <- coreBinderIn chain acc g fc owner rule rig a
         when !(erasedOutsideIndices owner (close g' sc)) $
           reject fc owner rule "a function type that depends on its argument"
         rt <- coreTypeIn chain acc g' fc owner rule sc
         -- A closure's type is one for every extent its values are made at.
         pure (FunT ({ type $= dynamicDims } arg) (dynamicDims rt), Nothing)
  -- `Inf` is a suspension like `Lazy`.
  heldTypeIn chain acc g fc owner rule (TDelayed _ _ t) =
    (, Nothing) . LazyT . dynamicDims <$> coreTypeIn chain acc g fc owner rule t
  heldTypeIn chain acc g fc owner rule tm = case getFnArgs tm of
    (Ref rfc (TyCon _) n, args) => do
      def <- lookupDef fc owner n
      -- A word type is a machine word whatever its arguments: what a
      -- `Ptr t` points to names what its handle holds, not its
      -- representation.
      let hs = hooksOf (fullname def)
      -- A Nat-like type, a numeral or a chain, is a natural.
      let NotNat = (!(tyConFacts def)).natness
        | _ => pure (NatT, Nothing)
      if hs.wordType
         then pure (IntT UInt64, Nothing)
         else case hs.orderedArray of
           Just (ds, Just e) => pure (MemRefT ds e, Nothing)
           Just (ds, Nothing) => case tm of
             App _ (Ref _ _ _) a => do
               e <- coreTypeIn chain acc g fc owner rule a
               case e of
                 TensorT _ _ => reject fc owner rule ("an array a world orders holding an array value: " ++ !(showTT (close g tm)))
                 _ => pure (MemRefT ds e, Nothing)
             _ => internal fc "the array type without its one element type"
           Nothing =>
             if hs.valueArray
               then case tm of
                 App _ (App _ (Ref _ _ _) shape) a => do
                   ds <- shapeDims fc owner (close g shape)
                   e <- coreTypeIn chain acc g fc owner rule a
                   case e of
                     MemRefT _ _ => reject fc owner rule ("an array value holding an array a world orders: " ++ !(showTT (close g tm)))
                     _ => pure (valueArrayOf ds e, Nothing)
                 _ => internal fc "a value array without its shape and element"
               else do
                 (inst, t) <- dataInstanceIn chain acc fc owner n !(traverse (normaliseClosed . close g) args)
                 pure (t, lookup inst (!(get TState)).newtypes)
    (TType _ _, _) => reject fc owner rule "Type in a runtime position"
    (Erased _ _, _) => reject fc owner rule "a type that depends on a runtime or erased value"
    -- A binder of the type read so far stands for a value of quantity 0 or
    -- a runtime one, as an erased part does.
    (Local {}, _) => reject fc owner rule "a type that depends on a runtime or erased value"
    _ => do reject fc owner rule ("unsupported runtime type " ++ !(showTT (close g tm)))

  ||| Registers a monomorphic data instance, once, and gives the type its
  ||| values have. A data type with one constructor and exactly one runtime
  ||| field is no declaration: a value of it is the field's value, so its
  ||| type is the field's. One that a field referred to while it was being
  ||| registered is declared whatever its shape (`data Rose = MkRose (List
  ||| Rose)`), since a value of it contains itself and its type cannot be
  ||| its field's. Registering descends on the room the chain leaves among
  ||| the links within the growth check's bounds (`Descending`): a new
  ||| instance is checked against those bounds and pushed. A data type
  ||| whose fields need ever larger instances of itself
  ||| (`data T a = L a | N (T (a, a))`) is refused before translation, by
  ||| the growth phase.
  dataInstanceIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                   (chain : Registering) -> (0 _ : Descending chain) ->
                   FC -> String -> Name -> List ClosedTerm -> Core (DataId, Ty)
  dataInstanceIn chain (Access rec) fc owner tcon args0 = do
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
    let statics = map (\(i, a) => if elem i keep then Just a else Nothing) (zip [0 .. List.length args] args)
    found <- instanceKey fc owner (fullname def) id statics
    let inst = MkDataId found.symbol
    let key = found.key
    st <- get TState
    case (lookup inst st.datas, lookup inst st.newtypes) of
      (Just _, _) => pure (inst, DataT inst)
      (_, Just b) => pure (inst, typeOf b)
      _ => case elemLink found.link chain.links of
        -- A data instance being registered is referred to by its own
        -- fields when it is recursive: it is declared, whatever its shape.
        -- The problem has this case: a value of it contains itself.
        Holds _ => do
          update TState { reentered $= insert inst }
          pure (inst, DataT inst)
        Fails fresh => do
          let what = keyText key ++ ", registered,"
          boundsHold fc what found.link.definition statics
          inside <- sizedWithin fc what chain.sizes found.link
          TCon arity _ _ _ _ datacons _ <- pure (definition def)
            | _ => reject fc owner ValueType (tname ++ " is not a data type")
          let Just datacons = datacons
            | Nothing => reject fc owner DataType (tname ++ " has no known constructors")
          loc <- toLoc (location def)
          conList <- traverse (constructor (MkRegistering chain.sizes (found.link :: chain.links))
                                           (rec (found.link :: chain.links) (Push fresh inside.member))
                                           fc owner inst args params keep)
                              datacons
          let sorted = sortBy (\a, b => compare (fst a).tag (fst b).tag) conList
          again <- contains inst . (.reentered) <$> get TState
          let fields : List Binder = case sorted of
                         [(_, kinds)] => mapMaybe fieldBinder kinds
                         _ => []
          case (again, fields) of
            (False, [b]) => do
              update TState { newtypes $= insert inst b }
              pure (inst, typeOf b)
            _ => do
              update TState { datas $= insert inst (MkData inst key (map fst sorted) loc
                                                           (fromMaybe SumKind.Plain (hooksOf (fullname def)).sumOf))
                            , dataOrder $= (:< inst) }
              pure (inst, DataT inst)

  ||| A constructor of a data instance being registered, with its
  ||| arguments' kinds, registered too.
  constructor : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                (chain : Registering) -> (0 _ : Descending chain) ->
                FC -> String -> DataId -> List ClosedTerm -> List Nat -> List Nat -> Name -> Core (Con, List ArgKind)
  constructor chain acc fc owner inst targs ps keep dcon = do
    def <- lookupDef fc owner dcon
    let cname = show (fullname def)
    DCon _ arity _ <- pure (definition def)
      | _ => reject fc owner CompiledModule (cname ++ " is not a constructor")
    Just cid <- conIdOf inst def
      | Nothing => reject fc owner CompiledModule (cname ++ " is not a constructor")
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
    kinds <- walk chain acc cname (location def) targs 0 layout none ty
    let con = MkCon cid (shortName (fullname def)) (mapMaybe fieldBinder kinds) loc
                    (fromMaybe CtorRole.Plain (hooksOf (fullname def)).plays)
    update TState { cons $= insert con.id (MkConLayout kinds (fullname def) con) }
    pure (con, kinds)

  ||| The constructor's arguments, read under the binders passed, each
  ||| given its value: a parameter is the instance's, one of quantity 0 is
  ||| none, an implementation is a compile-time value of the instance
  ||| (`Dictionaries`), anything else is the next field.
  walk : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         (chain : Registering) -> (0 _ : Descending chain) ->
         String -> FC -> List ClosedTerm -> Nat -> List (Maybe Nat) -> Given vs -> TT vs -> Core (List ArgKind)
  walk chain acc cname dfc targs i (Just p :: ls) g (Bind bfc _ (Pi {}) sc) = do
    let v = fromMaybe (Erased bfc Placeholder) (getAt p targs)
    (Param v ::) <$> walk chain acc cname dfc targs i ls (give v g) sc
  walk chain acc cname dfc targs i (Nothing :: ls) g (Bind bfc _ (Pi _ rig _ a) sc) = do
    let g' = give (Erased bfc Placeholder) g
    if isErased rig then (ErasedArg ::) <$> walk chain acc cname dfc targs i ls g' sc else do
      a' <- normaliseClosed (close g a)
      if !(dictionaryBinder rig a') then (DictArg a' ::) <$> walk chain acc cname dfc targs i ls g' sc else do
        when !(erasedOutsideIndices cname a') $ do
          reject dfc cname DependentField ("a field type that depends on another field: " ++ !(showTT a'))
        b <- coreBinderIn chain acc none dfc cname DependentField rig a'
        (Field i b a' ::) <$> walk chain acc cname dfc targs (S i) ls g' sc
  walk _ _ _ _ _ _ _ _ _ = pure []

  ||| The data instance a type names, when it is a data type and not a
  ||| natural, a machine word or an array of either kind: the instance, and
  ||| the type its values have, which is its field's for a type with one
  ||| runtime field.
  dataOfIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             (chain : Registering) -> (0 _ : Descending chain) ->
             Given vars -> FC -> String -> TT vars -> Core (Maybe (DataId, Ty))
  dataOfIn chain acc g fc owner tm = case getFnArgs tm of
    (Ref _ (TyCon _) n, args) => do
      def <- lookupDef fc owner n
      let hs = hooksOf (fullname def)
      -- A Nat-like type, a numeral or a chain, is a natural.
      let NotNat = (!(tyConFacts def)).natness
        | _ => pure Nothing
      if hs.wordType || isJust hs.orderedArray || hs.valueArray then pure Nothing else do
        args' <- traverse (normaliseClosed . close g) args
        Just <$> dataInstanceIn chain acc fc owner n args'
    _ => pure Nothing

  ||| The binder of a position of this type at this rig: the Core type at
  ||| the rig's quantity, taken through a type with one runtime field,
  ||| whose value is its field's, so that what the binder binds is the
  ||| field at the product of the rig's quantity and the field's, as
  ||| Idris uses the field of a value bound at the rig. Erasing such a
  ||| type to its field's type alone would give a binder at the rig's
  ||| quantity the field's value at that quantity, and a field Idris
  ||| binds unrestricted (the one field of `!* a`) would be held linear.
  coreBinderIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 (chain : Registering) -> (0 _ : Descending chain) ->
                 Given vars -> FC -> String -> Rule -> RigCount -> TT vars -> Core Binder
  coreBinderIn chain acc g fc owner rule rig tm = do
    (t, field) <- heldTypeIn chain acc g fc owner rule tm
    pure (MkBinder (maybe (quantityOf rig) (quantityTimes (quantityOf rig) . (.quantity)) field) t)

||| Reads a type from the start of a registration: its normal form, under
||| no binder, with no data instance being registered.
outermost : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            ((chain : Registering) -> (0 _ : Descending chain) ->
             Given Scope.empty -> ClosedTerm -> Core a) -> ClosedTerm -> Core a
outermost read tm = do
  b <- (.sizes) <$> get TState
  read (MkRegistering b []) (started b) none !(normaliseClosed tm)

||| The Core type of a closed type. A type that has no runtime
||| representation is reported under `rule`: `ValueType`, or
||| `DependentField` for a constructor field.
export
coreType : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           FC -> String -> Rule -> ClosedTerm -> Core Ty
coreType fc owner rule = outermost (\chain, acc, g => coreTypeIn chain acc g fc owner rule)

||| The data instance a closed type names, when it is a data type and not
||| a natural, a machine word or an array of either kind (`dataOfIn`).
export
dataOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         FC -> String -> ClosedTerm -> Core (Maybe (DataId, Ty))
dataOf fc owner = outermost (\chain, acc, g => dataOfIn chain acc g fc owner)

||| The binder of a position of a closed type at a rig (`coreBinderIn`).
export
coreBinder : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             FC -> String -> Rule -> RigCount -> ClosedTerm -> Core Binder
coreBinder fc owner rule rig = outermost (\chain, acc, g => coreBinderIn chain acc g fc owner rule rig)
