-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Types and data instances: the Core type of a closed Idris type, and the
||| monomorphic data instances it names, registered as they are met.
module IdrisMLIR.Frontend.Translate.Types

import Core.Context
import Core.Core
import Core.Env
import Core.TT
import Core.TT.Traversals
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
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Registry
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Grades.Grade
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

||| A stand-in for level `i` of a scope's telescope of erased binders: the
||| `i`th binder of a constructor's type, or a function's `i`th index
||| parameter (`Instances.classifyCall`).
export
marker : Nat -> ClosedTerm
marker i = probeTerm (ProbeBinder i)

||| The binder a name stands in for (`marker`), by its number.
markerNumber : Name -> Maybe Nat
markerNumber n = case probeOf n of
  Just (ProbeBinder k) => Just k
  _ => Nothing

||| The binder a term stands in for, if it is a stand-in.
markerOf : TT vs -> Maybe Nat
markerOf (Ref _ _ n) = markerNumber n
markerOf _ = Nothing

||| A term read in another scope: each level's stand-in replaced by the
||| closed term given for it there, and erased where none is given, since a
||| level of one scope is never one of another's.
export
atLevels : List (Maybe ClosedTerm) -> {vars : _} -> TT vars -> TT vars
atLevels given = mapTerm at
  where
    at : {vs : _} -> Term vs -> Term vs
    at t = case markerOf t of
      Just j => maybe (Erased EmptyFC Placeholder) embedClosed (join (getAt j given))
      Nothing => t

||| A term with every level's stand-in erased: what a key holds of an
||| argument (a static argument a call gives the instance it keys, a type
||| argument a data instance is keyed by) names no level of the scope it
||| is written in, whose levels are no one else's, so an erased index keys
||| nothing.
export
unmarked : {vars : _} -> TT vars -> TT vars
unmarked = atLevels []

||| Which arguments of a constructor are the data type's parameters, whose
||| values the data instance gives: each binder of its type is replaced by a
||| marker, and the markers found at the parameter positions of the return
||| type name them. An erased binder there is given the instance's argument
||| (an erased one where the key holds none); one the constructor holds at
||| runtime is given it only at a `Keyed` position, a type, and at any
||| other is a field (`MkTag : (n : Nat) -> Tag n`, which Idris finds at
||| the same place in every constructor), whose value a form would not be.
export
paramLayout : (con : GlobalDef) -> List Nat -> List Role -> ClosedTerm -> List (Maybe Nat)
paramLayout con params roles ty =
  let (n ** (ret, taken)) = markAll none 0 ty
      args = snd (getFnArgs ret)
      -- The first parameter a binder's marker is found at.
      found = SortedMap.fromList (reverse (mapMaybe (\p => (,p) <$> (getAt p args >>= markerOf)) params))
  in toList (zipWith (\i, a => lookup (finToNat i) found >>= given a) (allFins n) taken)
  where
    -- What the constructor takes at each binder (`argumentAt`), by
    -- position, and the return type with each binder its marker.
    markAll : Given vs -> Nat -> TT vs -> (n ** (ClosedTerm, Vect n ArgumentAt))
    markAll g i (Bind _ _ (Pi _ rig _ _) sc) =
      let (n ** (ret, taken)) = markAll (give (marker i) g) (S i) sc in (S n ** (ret, argumentAt con i rig :: taken))
    markAll g i t = (0 ** (close g t, []))
    given : ArgumentAt -> Nat -> Maybe Nat
    given (RuntimeValue _) p = if roleAt p roles == Keyed then Just p else Nothing
    given _ p = Just p

||| A constructor as the translation reads it, once: its definition, its
||| type normalised with every name full (a type may hide its binders
||| behind a definition, `a -@ b` is `(1 _ : a) -> b`, and a record's
||| parameter kinds may be solved metavariables), and that type read under
||| its binders, each given its stand-in (`marker`): what the constructor
||| takes at each binder, as Idris decided it (`argumentAt`), with the
||| binder's type, and the type it returns.
record Constructor where
  constructor MkConstructor
  global : GlobalDef
  normal : ClosedTerm
  taking : List (ArgumentAt, ClosedTerm)
  result : ClosedTerm

||| A constructor's type read under its binders, each given its stand-in
||| (`marker`): what the constructor takes at each binder, with the
||| binder's type, and the type it returns.
conBinders : GlobalDef -> Given vs -> Nat -> TT vs -> (List (ArgumentAt, ClosedTerm), ClosedTerm)
conBinders con g i (Bind _ _ (Pi _ rig _ a) sc) =
  let (bs, ret) = conBinders con (give (marker i) g) (S i) sc in ((argumentAt con i rig, close g a) :: bs, ret)
conBinders con g i t = ([], close g t)

||| The constructors of a type constructor, each read once
||| (`Constructor`). Nothing when Idris does not know the constructors (a
||| type declared without them) or the context lacks one. What the
||| translation reads of a type constructor is read from these
||| (`tyConFacts`).
constructorsOf : {auto c : Ref Ctxt Defs} -> GlobalDef -> Front (Maybe (List Constructor))
constructorsOf def = case definition def of
  TCon _ _ _ _ _ (Just cons) _ => do
    defs <- getDefs
    found <- traverse (\n => lookupExact n (gamma defs)) cons
    case the (Maybe (List GlobalDef)) (sequence found) of
      Just cs => Just <$> traverse read cs
      Nothing => pure Nothing
  _ => pure Nothing
  where
    read : GlobalDef -> Front Constructor
    read d = do
      ty <- normaliseClosed (type d) >>= fullNames
      let (bs, ret) = conBinders d none 0 ty
      pure (MkConstructor d ty bs ret)

||| The parameters of a type constructor: Idris's, and those its own
||| reading of the constructors' types misses because a type hides its
||| binders behind a definition (`a -@ LList a -@ LList a`, where Idris sees
||| only an application of `-@`). On the normalised types, as Idris does: a
||| position is a parameter when every occurrence of the type, as a field's
||| result and as the constructor's, has there the same binder of the
||| constructor, and no earlier position has it too. Such an argument is
||| never refined by a match, so reading it as a parameter changes nothing
||| Idris proved. Given the constructors' types (`constructorsOf`).
dataParams : GlobalDef -> Maybe (List Constructor) -> List Nat
dataParams def conTys = case definition def of
  TCon arity params _ _ _ _ _ =>
    let positions : List Nat = iterateN arity S 0
        idris = List.filter (\i => elem i params) positions in
    if length idris == arity then idris else
      let found : List Nat = case conTys of
                    Just ts@(_ :: _) => let sets = map (uniform . (.normal)) ts in
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

-- A constructor's binder held at runtime.
heldBinder : (ArgumentAt, ClosedTerm) -> Bool
heldBinder (RuntimeValue _, _) = True
heldBinder _ = False

-- Is binder `k` of a constructor's held at runtime, or none of its?
binderHeld : Nat -> List (ArgumentAt, ClosedTerm) -> Bool
binderHeld k bs = maybe True heldBinder (getAt k bs)

-- Does a binder held at runtime have a type that names binder `k`?
namedBy : Nat -> (ArgumentAt, ClosedTerm) -> Bool
namedBy k (RuntimeValue _, a) = mentionsMarker k a
namedBy k _ = False

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

||| The `Keyed` positions of a type constructor's arguments: the types a
||| value of it represents, its parameters whose kind is a universe, and
||| which some constructor holds at runtime or names in the type of an
||| argument it holds at runtime. With the `Formed` shapes, they tell
||| instances apart; every other argument (an index, or a value parameter
||| such as `Equal`'s `x`) is compile-time information. A parameter no
||| constructor names is a phantom (the state thread `s` of base's `ST s a`
||| and `STRef s a`): every type it is given has values of one
||| representation, so one instance serves them all, and a type
||| abstraction over it, `{0 s : Type} -> ST s Int`, is a value of that one
||| instance once applied to whatever type. Given its parameters and its
||| constructors' types (`constructorsOf`).
keyedOf : {auto c : Ref Ctxt Defs} -> GlobalDef -> List Nat -> Maybe (List Constructor) -> Front (List Nat)
keyedOf def params conTys = case definition def of
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
    represents : Nat -> Constructor -> Bool
    represents p con = case getAt p (snd (getFnArgs con.result)) >>= markerOf of
      Just k => binderHeld k con.taking || any (namedBy k) con.taking
      Nothing => True

-- A split of candidates that holds one or more leaves fewer out.
0 shorter : (a, b : Nat) -> a + S b = n -> LT a n
shorter a b Refl = rewrite sym (plusSuccRightSucc a b) in LTESucc (lteAddRight a)

||| The `Held` positions of a type constructor's arguments: every argument
||| but a parameter whose kind is a universe and that its values hold. A
||| value holds such an argument when a constructor that has its own binder
||| there holds a runtime argument whose type reaches that binder, through
||| a function type's argument or result, a suspension, or a represented
||| position of a type constructor (this one's, or another's `Keyed`
||| ones). It is the least such set: `L : a -> T a` makes `T`'s `a` a
||| position, and `PCons : P (a, a) -> P a`, whose index no value holds,
||| does not. Such an index is checked by the growth phase, never a key.
||| Given the type constructor's parameters, its `Keyed` positions and its
||| constructors' types (`constructorsOf`).
heldOf : {auto c : Ref Ctxt Defs} -> GlobalDef -> (params, keys : List Nat) -> List Constructor -> Front (List Nat)
heldOf def ps keys conTys = case definition def of
  TCon arity _ _ _ _ _ _ => do
    ty <- normaliseClosed (type def)
    let values = kinds ty
    -- Every argument position: `[0 .. minus arity 1]` would be `[0]` at
    -- arity 0.
    let candidates@(_ :: _) = filter (\i => not (elem i ps) && not (fromMaybe False (getAt i values)))
                                     (iterateN arity S 0)
      | [] => pure []
    least keys conTys [] candidates (wellFounded _)
  _ => pure []
  where
    -- The `Keyed` positions of another type constructor.
    keysOf : Name -> Front (List Nat)
    keysOf d = do
      defs <- getDefs
      Just ddef <- lookupExact d (gamma defs)
        | Nothing => pure []
      conTys <- constructorsOf ddef
      keyedOf ddef (dataParams ddef conTys) conTys

    mutual
      -- Does a type reach the stand-in for binder `k`, at the positions
      -- `own` of this type constructor?
      reaches : List Nat -> Nat -> TT vs -> Front Bool
      reaches own k (Ref _ _ n) = pure (markerNumber n == Just k)
      reaches own k (Bind _ _ (Pi _ rig _ a) sc) = do
        inA <- case use rig of
                 Erased => pure False
                 Used _ => reaches own k a
        if inA then pure True else reaches own k sc
      reaches own k (TDelayed _ _ t) = reaches own k t
      reaches own k tm = case getFnArgs tm of
        (Ref _ (TyCon _) d, args) => do
          ks <- if d == fullname def then pure own else keysOf d
          spine ks own k (length args) tm
        _ => pure False

      -- The arguments at positions `ks` of an application of `j`
      -- arguments, the last first, so that each is a subterm.
      spine : List Nat -> List Nat -> Nat -> Nat -> TT vs -> Front Bool
      spine ks own k (S j) (App _ f a) = do
        here <- if elem j ks then reaches own k a else pure False
        if here then pure True else spine ks own k j f
      spine _ _ _ _ _ = pure False

    -- Does a binder held at runtime have a type that reaches binder `k`?
    reachedBy : List Nat -> Nat -> (ArgumentAt, ClosedTerm) -> Front Bool
    reachedBy own k (RuntimeValue _, a) = reaches own k a
    reachedBy own k _ = pure False

    -- Does a constructor whose return type has its own binder at `p` hold
    -- a runtime argument whose type reaches it?
    holds : List Nat -> Nat -> Constructor -> Front Bool
    holds own p con = case getAt p (snd (getFnArgs con.result)) >>= markerOf of
      Just k => any id <$> traverse (reachedBy own k) con.taking
      Nothing => pure False

    -- The candidates of `out` the set `held` makes held, and the rest, as
    -- many between them as `out` has.
    among : List Nat -> List Constructor -> List Nat -> (out : List Nat) ->
            Front (Subset (List Nat, List Nat) (\s => length (snd s) + length (fst s) = length out))
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
    least : List Nat -> List Constructor -> List Nat -> (out : List Nat) ->
            (0 _ : Accessible LT (length out)) -> Front (List Nat)
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
natnessOf : Maybe (List Constructor) -> Natness
natnessOf (Just cons@(_ :: _)) =
  if not (all (isJust . natRole . (.global)) cons) then NotNat
    else if all (\con => all heldBinder con.taking) cons then Chain
    else Numeral
natnessOf _ = NotNat

||| An extent's dimension: static where its normal form is a literal, a
||| `Nat`-like chain of successors ending at zero (read from Idris's flags,
||| never from names) or a non-negative integer; dynamic otherwise, since
||| an erased extent is the value's own, never a constant it is assumed to
||| be.
extentDim : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Front Dim
extentDim = go 0
  where
    -- The role of the constructor a term is an application of.
    roleOf : ClosedTerm -> Front (Maybe NatRole)
    roleOf tm = case getFn tm of
      Ref _ (DataCon _ _) n => do
        defs <- getDefs
        pure (natRole =<< !(lookupExact n (gamma defs)))
      _ => pure Nothing
    -- A successor's predecessor is its last argument.
    go : Nat -> ClosedTerm -> Front Dim
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
||| its form, outermost first (`spineOf`, which refuses a shape that has
||| none).
shapeDims : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            FC -> String -> ClosedTerm -> Front (List Dim)
shapeDims fc owner shape = traverse extentDim (extents !(spineOf fc owner !(normaliseClosed shape)))

||| The roles of a value array's arguments, its shape and its element, as
||| `Shapes.arrayParts` reads them: the shape is its form, and the element
||| a type. The registry's hook says a type constructor is one; it has no
||| constructors to read anything else off.
valueArrayRoles : List Role
valueArrayRoles = [Formed, Keyed]

mutual
  -- Each application of a type constructor in a term, with whether each of
  -- its arguments, the first first, mentions what the test picks.
  picked : ({0 vs : Scope} -> TT vs -> Bool) -> TT vars -> List (Name, List Bool)
  picked p tm = applied p tm []

  -- A term applied to arguments, the first first.
  applied : ({0 vs : Scope} -> TT vs -> Bool) -> TT vars -> List (TT vars) -> List (Name, List Bool)
  applied p (App _ f a) args = picked p a ++ applied p f (a :: args)
  applied p (Ref _ (TyCon _) n) args = [(n, map (mentions p) args)]
  applied p (Bind _ _ b sc) _ = pickedIn p b ++ picked p sc
  applied p (TDelayed _ _ t) _ = picked p t
  applied p (TDelay _ _ t a) _ = picked p t ++ picked p a
  applied p (TForce _ _ t) _ = picked p t
  applied p (As _ _ _ pat) _ = picked p pat
  applied p _ _ = []

  -- A binder's type, and a `let`'s value.
  pickedIn : ({0 vs : Scope} -> TT vs -> Bool) -> TTBinder (TT vars) -> List (Name, List Bool)
  pickedIn p (Lam _ _ _ ty) = picked p ty
  pickedIn p (Let _ _ v ty) = picked p v ++ picked p ty
  pickedIn p (Pi _ _ _ ty) = picked p ty
  pickedIn p (PVar _ _ _ ty) = picked p ty
  pickedIn p (PLet _ _ v ty) = picked p v ++ picked p ty
  pickedIn p (PVTy _ _ ty) = picked p ty

-- What the `Formed` positions of type constructors are assumed to be
-- while they are found: those of each type constructor whose own are
-- being found on the walk, by its name, as far as they are found so far.
Assumed : Type
Assumed = List (Name, List Nat)

mutual
  ||| Does a binder of this kind stand where terms put it in a form: is its
  ||| kind the shape type, and is it, as the test picks it out, in an
  ||| argument at a `Formed` position of a type constructor applied in one
  ||| of the terms (a value array's shape, or a shape a data type's array
  ||| reads)? A tensor's rank is its type, so such a binder keys what its
  ||| type is. The one rule for a function's erased binder (`formNeeded`)
  ||| and a data type's parameter (`formedIn`).
  formRead : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             (w : Walked) -> (0 _ : SizeAccessible w) -> Assumed ->
             (kind : ClosedTerm) -> ({0 vs : Scope} -> TT vs -> Bool) -> List ClosedTerm -> Front Bool
  formRead w acc assumed kind p ts =
    if isShapeType (shapeOf !(fullNames kind))
       then inForm w acc assumed (ts >>= picked p)
       else pure False

  -- Is one of the arguments picked at a `Formed` position of the type
  -- constructor applied to it?
  inForm : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           (w : Walked) -> (0 _ : SizeAccessible w) -> Assumed -> List (Name, List Bool) -> Front Bool
  inForm w acc assumed [] = pure False
  inForm w acc assumed ((n, ms) :: rest) = do
    fs <- formedAt w acc assumed n
    if any (\j => fromMaybe False (getAt j ms)) fs then pure True else inForm w acc assumed rest

  -- The `Formed` positions of a type constructor, by its name: as assumed
  -- while its own are being found, as found once and kept (`tyConFacts`),
  -- or else found here, the walk entering it. Every type constructor the
  -- walk has entered is assumed, so one it cannot enter is none the
  -- context holds a place for.
  formedAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             (w : Walked) -> (0 _ : SizeAccessible w) -> Assumed -> Name -> Front (List Nat)
  formedAt w (Access rec) assumed n = case lookup n assumed of
    Just fs => pure fs
    Nothing => do
      Just (placement, def) <- core (resolve n)
        | Nothing => pure []
      case lookup (addressOf placement) (!(getState)).tyCons of
        Just known => pure (positionsOf (== Formed) known.roles)
        Nothing => case enter placement w of
          Just (Element w' less) => formedIn w' (rec w' less) assumed def
          Nothing => pure []

  ||| The `Formed` positions of a type constructor: a value array's shape
  ||| (`valueArrayRoles`), and the least set of its parameters of which a
  ||| constructor's runtime field puts the binder at the parameter in a
  ||| form (`formRead`), this type constructor's own positions read as the
  ||| set found so far, and those of every type constructor its fields
  ||| apply found the same way, inside, with this one's assumed. Each round
  ||| adds what the set so far makes formed among the parameters still out,
  ||| and the set is whole at a round that adds none, so the rounds descend
  ||| on the parameters still out, as the walk does on the type
  ||| constructors it has entered. `Grid : Shape -> Type` with `MkGrid :
  ||| Array s Int -> Grid s` has its shape formed, and so does a type whose
  ||| constructor holds a `Grid s`; a phantom shape, which no field puts in
  ||| an array, has not.
  formedIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             (w : Walked) -> (0 _ : SizeAccessible w) -> Assumed -> GlobalDef -> Front (List Nat)
  formedIn w acc assumed def =
    if (hooksOf (fullname def)).valueArray then pure (positionsOf (== Formed) valueArrayRoles) else do
      Just cons <- constructorsOf def
        | Nothing => pure []
      rounds w acc assumed (fullname def) cons [] (dataParams def (Just cons)) (wellFounded _)

  rounds : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           (w : Walked) -> (0 _ : SizeAccessible w) -> Assumed -> Name -> List Constructor ->
           (formed, out : List Nat) -> (0 _ : Accessible LT (length out)) -> Front (List Nat)
  rounds w acc assumed self conTys formed out (Access fewer) = do
    Element (p :: ps, outs) n <- formedAmong w acc ((self, formed) :: assumed) conTys out
      | Element ([], _) _ => pure (sort formed)
    rounds w acc assumed self conTys (formed ++ p :: ps) outs (fewer _ (shorter _ _ n))

  -- The parameters of `out` some constructor puts in a form, and the rest,
  -- as many between them as `out` has.
  formedAmong : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                (w : Walked) -> (0 _ : SizeAccessible w) -> Assumed -> List Constructor -> (out : List Nat) ->
                Front (Subset (List Nat, List Nat) (\s => length (snd s) + length (fst s) = length out))
  formedAmong w acc assumed conTys [] = pure (Element ([], []) Refl)
  formedAmong w acc assumed conTys (p :: ps) = do
    Element (ins, outs) n <- formedAmong w acc assumed conTys ps
    True <- formedBy w acc assumed p conTys
      | False => pure (Element (ins, p :: outs) (cong S n))
    pure (Element (p :: ins, outs) (trans (sym (plusSuccRightSucc _ _)) (cong S n)))

  -- Does a constructor whose return type has its own binder at parameter
  -- `p` put that binder in a form with a runtime field?
  formedBy : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             (w : Walked) -> (0 _ : SizeAccessible w) -> Assumed -> Nat -> List Constructor -> Front Bool
  formedBy w acc assumed p [] = pure False
  formedBy w acc assumed p (con :: cs) = do
    let bs = con.taking
    here <- case getAt p (snd (getFnArgs con.result)) >>= markerOf of
      Just k => case getAt k bs of
        Just (_, kind) => formRead w acc assumed kind (\t => markerOf t == Just k) (map snd (filter heldBinder bs))
        Nothing => pure False
      Nothing => pure False
    if here then pure True else formedBy w acc assumed p cs

||| Does the rest of a function's type need an erased binder's form: is
||| the binder a shape that the rest, with `formProbe` for it, puts in a
||| form (`formRead`)?
export
formNeeded : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             (kind : ClosedTerm) -> (ClosedTerm -> ClosedTerm) -> Front Bool
formNeeded kind rest =
  formRead start (sizeAccessible start) [] kind isFormProbe [!(fullNames !(normaliseClosed (rest formProbe)))]

||| What the translation reads of a type constructor's definition, from its
||| constructors read once (`constructorsOf`): its parameters
||| (`dataParams`), the role of each argument (`keyedOf`, `formedIn`,
||| `heldOf`; a value array's are `valueArrayRoles`), and how it is
||| `Nat`-like (`natnessOf`), found once per type constructor (`tyCons`).
export
tyConFacts : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             GlobalDef -> Front TyConFacts
tyConFacts def = do
  defs <- getDefs
  -- A name the context does not hold has no address to keep its facts by.
  let Just key = definitionAddress (gamma defs) (fullname def)
    | Nothing => facts
  case lookup key (!(getState)).tyCons of
    Just known => pure known
    Nothing => do
      found <- facts
      updateState { tyCons $= insert key found }
      pure found
  where
    roleOf : (keys, forms, held : List Nat) -> Nat -> Role
    roleOf keys forms held j =
      if elem j forms then Formed
        else if elem j keys then Keyed
        else if elem j held then Held
        else Index

    facts : Front TyConFacts
    facts = do
      conTys <- constructorsOf def
      let ps = dataParams def conTys
      roles <- if (hooksOf (fullname def)).valueArray then pure valueArrayRoles else do
                 let TCon arity _ _ _ _ _ _ = definition def
                   | _ => pure []
                 keys <- keyedOf def ps conTys
                 -- The walk starts at this type constructor, entered.
                 forms <- case !(core (resolve (fullname def))) of
                            Just (placement, _) => let w = startAt placement in formedIn w (sizeAccessible w) [] def
                            Nothing => formedIn start (sizeAccessible start) [] def
                 held <- heldOf def ps keys (fromMaybe [] conTys)
                 pure (map (roleOf keys forms held) (iterateN arity S 0))
      pure (MkTyConFacts ps roles (natnessOf conTys))

||| The positions of a type constructor's arguments the growth check
||| watches (`watched`), read once per type constructor with its other
||| facts (`tyConFacts`).
export
represented : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> GlobalDef -> Front (List Nat)
represented def = positionsOf watched . (.roles) <$> tyConFacts def

||| The roles of a type constructor's arguments; nothing for a name that
||| is no type constructor.
rolesOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          String -> Name -> Front (Maybe (List Role))
rolesOf owner n = do
  def <- lookupDef EmptyFC owner n
  case definition def of
    TCon {} => pure (Just (!(tyConFacts def)).roles)
    _ => pure Nothing

||| Does a type mention what the test picks other than as an index of an
||| inductive family? Indices exist at compile time only, so a type that
||| mentions something only there has one representation whatever it is.
export
outsideIndices : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 (ClosedTerm -> Bool) -> String -> ClosedTerm -> Front Bool
outsideIndices picks owner = within none
  where
    mutual
      within : Given vs -> TT vs -> Front Bool
      within g (Bind bfc _ (Pi _ rig _ a) sc) = do
        -- The argument is erased in the result: a dependency on it is one on
        -- an erased value, unless it is only an index. A quantity-0 binder
        -- of kind Type, `{0 s : Type} -> ST s Int` (the argument of base's
        -- runST), is compile-time only: a value of the type is applied to a
        -- type and to nothing at runtime, so it has the representation of
        -- its body with the binder erased (`coreType`), one representation
        -- for whatever type it is applied to. The body may then mention the
        -- binder only where no representation needs it, as an index or a
        -- phantom parameter (`keyedOf`); anywhere else (`{0 s : Type} ->
        -- List s`) the representation would depend on it, and the type is
        -- refused. An argument taken with quantity 0 is not passed: its type
        -- has no representation, whatever it mentions (`(0 _ : IsConClause
        -- p) -> ...`).
        inA <- case use rig of
                 Erased => pure False
                 Used _ => within g a
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
      -- Only a `Keyed` argument is a type a representation is made of: a
      -- `Formed` one is a shape whose extents are indices, and whose rank
      -- the key holds (`spineOf` refuses one with none).
      within g tm = case getFnArgs tm of
        (Ref _ (TyCon _) n, args) => do
          Just rs <- rolesOf owner n
            | Nothing => pure (picks (close g tm))
          params g rs (length args) tm
        _ => pure (picks (close g tm))

      -- The arguments at the `Keyed` positions of an application of `k`
      -- arguments, the last first, so that each is a subterm.
      params : Given vs -> List Role -> Nat -> TT vs -> Front Bool
      params g rs (S k) (App _ f a) = do
        here <- if roleAt k rs == Keyed then within g a else pure False
        before <- params g rs k f
        pure (here || before)
      params g rs _ _ = pure False

||| Does a type mention an erased value other than as an index of an
||| inductive family? Indices exist at compile time only, so a value of the
||| family stores none.
export
erasedOutsideIndices : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                       String -> ClosedTerm -> Front Bool
erasedOutsideIndices = outsideIndices anyErased

mutual
  ||| A type with the indices of every inductive family in it erased, so
  ||| that `Vect 3 Double` and `Vect n Double` name one instance, and every
  ||| shape a value array's type needs cut to its form, so that `Vector 3
  ||| Int` and `Vector n Int` do too. A type family is a lambda
  ||| (`SortedDMap k (\_ => v)`, `DPair a (\x => p x)`): the indices inside
  ||| its body are erased the same way, so two families that differ only
  ||| there name one instance.
  eraseIndices : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 {vars : _} -> FC -> String -> TT vars -> Front (TT vars)
  eraseIndices fc owner (Bind bfc x b sc) = do
    b' <- binder b
    sc' <- eraseIndices fc owner sc
    pure (Bind bfc x b' sc')
    where
      binder : TTBinder (TT vars) -> Front (TTBinder (TT vars))
      binder (Lam lfc rig info ty) = Lam lfc rig info <$> eraseIndices fc owner ty
      binder (Let lfc rig v ty) = Let lfc rig <$> eraseIndices fc owner v <*> eraseIndices fc owner ty
      binder (Pi lfc rig info ty) = Pi lfc rig info <$> eraseIndices fc owner ty
      binder (PVar lfc rig info ty) = PVar lfc rig info <$> eraseIndices fc owner ty
      binder (PLet lfc rig v ty) = PLet lfc rig <$> eraseIndices fc owner v <*> eraseIndices fc owner ty
      binder (PVTy lfc rig ty) = PVTy lfc rig <$> eraseIndices fc owner ty
  eraseIndices fc owner tm = case getFnArgs tm of
    (Ref _ (TyCon _) n, args) => do
      Just rs <- rolesOf owner n
        | Nothing => pure tm
      erase rs (length args) tm
    _ => pure tm
    where
      -- An application of `k` arguments with each one keyed by its role,
      -- the last first, so that each is a subterm.
      erase : List Role -> Nat -> TT vars -> Front (TT vars)
      erase rs (S k) (App _ f a) = App EmptyFC <$> erase rs k f <*> argumentKey fc owner (roleAt k rs) a
      erase rs _ h = pure h

  ||| What a key holds of an argument at a position of a role: a type with
  ||| its indices erased, a shape's form, or nothing. A shape with no form
  ||| makes no key (`spineOf`).
  argumentKey : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                {vars : _} -> FC -> String -> Role -> TT vars -> Front (TT vars)
  argumentKey fc owner Keyed a = unmarked <$> eraseIndices fc owner a
  argumentKey fc owner Formed a = formOf <$> spineOf fc owner a
  argumentKey fc owner Held _ = pure (Erased EmptyFC Placeholder)
  argumentKey fc owner Index _ = pure (Erased EmptyFC Placeholder)

||| A constructor's name within its data type, the symbol of its `idr.ctor`:
||| a data type's constructors share its namespace, so the name without it
||| is unique there. The full name is its location.
export
shortName : Name -> String
shortName (NS _ n) = shortName n
shortName n = show n

||| A constructor's identity in a family instance: its tag as a position
||| among the constructors of the type its result is. Nothing when the
||| definition is no constructor, its type's constructors are not known,
||| or its tag is past them.
export
conIdOf : {auto c : Ref Ctxt Defs} -> FamilyId -> GlobalDef -> Front (Maybe ConId)
conIdOf inst def = do
  let DCon tag _ _ = definition def
    | _ => pure Nothing
  -- The type as written may hide its binders behind a definition (`a -@ b`
  -- is `(1 _ : a) -> b`), so the type constructor is read off its normal
  -- form, as `constructor` reads the layout.
  Just tn <- built <$> normaliseClosed (type def)
    | Nothing => pure Nothing
  defs <- getDefs
  Just tdef <- lookupExact tn (gamma defs)
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
                     TT vars -> Front Bool
implementationType (Bind _ _ (Pi {}) sc) = implementationType sc
implementationType ty = case getFn ty of
  Ref _ (TyCon _) n => do
    defs <- getDefs
    Just def <- lookupExact n (gamma defs)
      | Nothing => pure False
    st <- getState
    if contains (fullname def) st.interfaces then pure True else
      case ty of
        App _ (App _ (Ref _ _ _) a) b => do
          False <- core (isPairType (fullname def))
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
                   RigCount -> TT vars -> Front Bool
dictionaryBinder rig ty = case use rig of
  Erased => pure False
  Used _ => implementationType ty

||| The choice of an implementation type: the closed sum of the
||| implementations of it that the program fixes as runtime values
||| (`Choice`), one constructor each, which the translation adds as it finds
||| them (`Choices.memberOf`). It is keyed as a family of the type
||| constructor at its arguments would be, each argument whole, and
||| registered once, with no constructor yet: a choice no value is ever
||| made of is uninhabited. It is not the interface's record: which
||| implementation a value is, not its methods, is what a dispatch on it
||| reads.
export
choiceFamily : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               FC -> String -> ClosedTerm -> Front Choice
choiceFamily fc owner ty = do
  let (Ref _ _ n, args) = getFnArgs ty
    | _ => internal fc ("a choice of no implementation type: " ++ !(showTT ty))
  def <- lookupDef fc owner n
  keyed <- traverse (\a => Just <$> argumentKey fc owner Keyed !(canonicalTypeArg a)) args
  found <- instanceKey fc owner (fullname def) id keyed
  st <- getState
  case lookup found.link st.choiceIds >>= \fam => lookup fam st.choices of
    Just choice => pure choice
    Nothing => do
      let fam = MkFamilyId st.nextFamily
      let choice = MkChoice fam ty [<]
      loc <- toLoc (location def)
      updateState { choiceIds $= insert found.link fam, nextFamily $= S
                  , choices $= insert fam choice
                  , families $= insert fam (MkFamily fam found.key None [] [] loc)
                  , familyOrder $= (:< fam) }
      pure choice

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

||| Why registering ends: each data instance registered extends the chain
||| by its link, new to it and within the bounds, and the universe of links
||| within the bounds is finite (`Requests.Universe`), so each extension
||| leaves less room in it (`Finite.extensionsEnd`). A link is its own key.
0 Descending : Registering -> Type
Descending reg = Accessible (Extends (Universe forms addresses reg.sizes) id) reg.links

-- A chain of links keyed by themselves is itself.
0 keyedBySelf : (ls : List (Link Form)) -> map Prelude.Basics.id ls = ls
keyedBySelf [] = Refl
keyedBySelf (l :: ls) = cong (l ::) (keyedBySelf ls)

-- The empty chain descends.
0 started : (b : Bounds) -> Descending (MkRegistering b [])
started b = extensionsEnd (Universe forms addresses b) id [] [] [] (wellFounded _)

||| The growth check's bound on each argument a data instance is keyed by,
||| at its type constructor's node (`MkNode t []`), checked where the
||| instance is registered, on the arguments as the key holds them (its
||| `statics`, nothing where it holds none). A position given no bound, or
||| an argument above its bound, is a flow the check missed: the
||| compiler's error, never the program's.
boundsHold : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             FC -> String -> Address -> (statics : List (Maybe ClosedTerm)) -> Front ()
boundsHold fc what t statics = do
  st <- getState
  for_ (mapMaybe (\(j, a) => (j,) <$> a) (zip (iterateN (length statics) S 0) statics)) $ \(j, a) => do
    (h, _) <- closedHeight AType a
    heightWithin fc what st.bounds (MkNode t [], j) h

||| What is known of an erased index, from its normal form: a constructor
||| binder's stand-in (`marker`) is that binder's level; a chain of
||| successors of `Nat` (Idris's `ZERO` and `SUCC` flags, never names) over
||| zero or a stand-in is a number or a level plus one per successor; a
||| non-negative integer literal is a number; anything else is outside the
||| language, refining nothing. Read once, where a type is read, and where
||| a call gives an index parameter its argument.
export
indexTerm : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Front ITerm
indexTerm = go 0
  where
    roleOf : ClosedTerm -> Front (Maybe NatRole)
    roleOf tm = case getFn tm of
      Ref _ (DataCon _ _) n => do
        defs <- getDefs
        pure (natRole =<< !(lookupExact n (gamma defs)))
      _ => pure Nothing
    go : Nat -> ClosedTerm -> Front ITerm
    go k tm = case markerOf tm of
      Just level => pure (succ (IVar level) k)
      Nothing => case tm of
        App _ _ pred => case !(roleOf tm) of
          Just Zero => pure (INat k)
          Just Succ => go (S k) pred
          Nothing => pure IOpaque
        Ref _ (DataCon _ _) _ => case !(roleOf tm) of
          Just Zero => pure (INat k)
          _ => pure IOpaque
        PrimVal _ c => case constantLit c of
          Just (LBig i) => pure (if i >= 0 then INat (k + integerToNat i) else IOpaque)
          _ => pure IOpaque
        _ => pure IOpaque

||| Where an erased binder occurs in the rest of a function's type, given
||| as the binder's stand-in (`marker k`): nowhere a value is passed (in no
||| runtime binder's type, nor in the result), only as an index of an
||| inductive family there, or somewhere a representation would depend on
||| it. Only the second makes the binder an index parameter: one only a
||| proof reads is no binder, and one a representation reads is no index.
public export
data Occurrence = Unpassed | IndexOnly | Represented

export
occurrenceOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               String -> (k : Nat) -> (rest : ClosedTerm) -> Front Occurrence
occurrenceOf owner k rest = do
  represented <- outsideIndices (mentionsMarker k) owner rest
  pure (if represented then Represented else if passed rest then IndexOnly else Unpassed)
  where
    passed : TT vs -> Bool
    passed (Bind _ _ (Pi _ rig _ a) sc) = (case use rig of
                                             Erased => False
                                             Used _ => mentionsMarker k a) || passed sc
    passed t = mentionsMarker k t

||| The sort of an erased binder or index, from its type's normal form: a
||| natural for Idris's `Nat` (a chain), a type for a universe, outside the
||| language for anything else.
export
sortOfType : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> ClosedTerm -> Front Sort
sortOfType (TType _ _) = pure SType
sortOfType tm = case getFn tm of
  Ref _ (TyCon _) n => do
    defs <- getDefs
    Just def <- lookupExact n (gamma defs)
      | Nothing => pure SOpaque
    case (!(tyConFacts def)).natness of
      Chain => pure SNat
      _ => pure SOpaque
  _ => pure SOpaque

||| The levels a term or a type names, each once.
mutual
  levelsOfTerm : ITerm -> List Nat
  levelsOfTerm (IVar k) = [k]
  levelsOfTerm (ISucc t _) = levelsOfTerm t
  levelsOfTerm (ICon _ _ as) = levelsOfTerms as
  levelsOfTerm (IType t) = levelsOfTy t
  levelsOfTerm _ = []

  levelsOfTerms : List ITerm -> List Nat
  levelsOfTerms [] = []
  levelsOfTerms (t :: ts) = levelsOfTerm t ++ levelsOfTerms ts

  levelsOfTy : Ty -> List Nat
  levelsOfTy (DataT _ ts) = levelsOfTerms ts
  levelsOfTy (NatT t) = levelsOfTerm t
  levelsOfTy (FunT (MkBinder _ a) r) = levelsOfTy a ++ levelsOfTy r
  levelsOfTy (LazyT a) = levelsOfTy a
  levelsOfTy (TensorT _ a) = levelsOfTy a
  levelsOfTy (MemRefT _ a) = levelsOfTy a
  levelsOfTy _ = []

||| A term or a type with its levels renamed by `f`: a level `f` drops is
||| outside the language there.
mutual
  relevelTerm : (Nat -> Maybe Nat) -> ITerm -> ITerm
  relevelTerm f (IVar k) = maybe IOpaque IVar (f k)
  relevelTerm f (ISucc t k) = succ (relevelTerm f t) k
  relevelTerm f (ICon g c as) = ICon g c (relevelTerms f as)
  relevelTerm f (IType t) = IType (relevelTy f t)
  relevelTerm f t = t

  relevelTerms : (Nat -> Maybe Nat) -> List ITerm -> List ITerm
  relevelTerms f [] = []
  relevelTerms f (t :: ts) = relevelTerm f t :: relevelTerms f ts

  export
  relevelTy : (Nat -> Maybe Nat) -> Ty -> Ty
  relevelTy f (DataT g ts) = DataT g (relevelTerms f ts)
  relevelTy f (NatT t) = NatT (relevelTerm f t)
  relevelTy f (FunT (MkBinder q a) r) = FunT (MkBinder q (relevelTy f a)) (relevelTy f r)
  relevelTy f (LazyT a) = LazyT (relevelTy f a)
  relevelTy f (TensorT ds a) = TensorT ds (relevelTy f a)
  relevelTy f (MemRefT o a) = MemRefT o (relevelTy f a)
  relevelTy f t = t

||| What the walk of a constructor's type finds: its arguments' kinds, the
||| position and type of each of its quantity-0 arguments in order (its
||| candidate binders, each given its stand-in where it is bound), and the
||| type it returns, under those stand-ins.
record Walked where
  constructor MkWalked
  kinds : List ArgKind
  erasedTypes : List (Nat, ClosedTerm)
  returns : ClosedTerm

mutual
  ||| The Core type of a type, read under binders whose values are given,
  ||| in the registration of the families on `chain`. The type is normalised
  ||| (`coreType` normalises it once), so every part of it is too, and the
  ||| reading is structural. A type that has no runtime representation is
  ||| reported under `rule`: `ValueType`, or `DependentField` for a
  ||| constructor field. An argument of quantity 0 is no argument at
  ||| runtime, so a function type that takes one is the type of its result.
  coreTypeIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               (chain : Registering) -> (0 _ : Descending chain) ->
               {cat : Category} -> Given vars -> FC -> String -> Rule cat -> TT vars -> Front Ty
  coreTypeIn chain acc g fc owner rule (PrimVal _ (PrT t)) = pure (prim (primTy t))
    where
      prim : PrimTy -> Ty
      prim (IntP it) = IntT it
      prim IntegerP = BigT
      prim StringP = StrT
      prim CharP = CharT
      prim DoubleP = DoubleT
      prim WorldP = WorldT
  coreTypeIn chain acc g fc owner rule (Bind bfc x (Pi _ rig _ a) sc) = do
    let g' = give (Erased bfc Placeholder) g
    case use rig of
      Erased => coreTypeIn chain acc g' fc owner rule sc
      Used q => do
        arg <- coreBinderIn chain acc g fc owner rule q a
        when !(erasedOutsideIndices owner (close g' sc)) $
          reject fc owner rule "a function type that depends on its argument"
        rt <- coreTypeIn chain acc g' fc owner rule sc
        -- A closure's type is one for every extent its values are made at.
        pure (FunT ({ type $= dynamicDims } arg) (dynamicDims rt))
  -- `Inf` is a suspension like `Lazy`.
  coreTypeIn chain acc g fc owner rule (TDelayed _ _ t) =
    LazyT . dynamicDims <$> coreTypeIn chain acc g fc owner rule t
  -- An implementation in a runtime position is a value of its type's
  -- choice: which of the implementations the program fixes it is.
  coreTypeIn chain acc g fc owner rule tm = do
    True <- implementationType tm
      | False => dataTypeIn chain acc g fc owner rule tm
    choice <- choiceFamily fc owner !(normaliseClosed (close g tm))
    pure (DataT choice.family [])

  ||| A type that is no implementation's, by its head.
  dataTypeIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               (chain : Registering) -> (0 _ : Descending chain) ->
               {cat : Category} -> Given vars -> FC -> String -> Rule cat -> TT vars -> Front Ty
  dataTypeIn chain acc g fc owner rule tm = case getFnArgs tm of
    (Ref rfc (TyCon _) n, args) => do
      def <- lookupDef fc owner n
      -- A word type is a machine word whatever its arguments: what a
      -- `Ptr t` points to names what its handle holds, not its
      -- representation.
      let hs = hooksOf (fullname def)
      -- Idris's `Nat`, a chain of successors, is a natural. A family of
      -- the same shape whose constructors take an erased index (`Fin`,
      -- `Elem`) is a family: the dialect lays it out as a number.
      case (!(tyConFacts def)).natness of
       Chain => pure (NatT IOpaque)
       _ => if hs.wordType
         then pure (IntT UInt64)
         else case hs.orderedArray of
           Just (o, Just e) => pure (MemRefT o e)
           Just (o, Nothing) => case tm of
             App _ (Ref _ _ _) a => do
               e <- coreTypeIn chain acc g fc owner rule a
               case e of
                 TensorT _ _ => reject fc owner rule ("an array a world orders holding an array value: " ++ !(showTT (close g tm)))
                 _ => pure (MemRefT o e)
             _ => internal fc "the array type without its one element type"
           Nothing =>
             if hs.valueArray
               then case tm of
                 App _ (App _ (Ref _ _ _) shape) a => do
                   ds <- shapeDims fc owner (close g shape)
                   e <- coreTypeIn chain acc g fc owner rule a
                   case e of
                     MemRefT _ _ => reject fc owner rule ("an array value holding an array a world orders: " ++ !(showTT (close g tm)))
                     _ => pure (valueArrayOf ds e)
                 _ => internal fc "a value array without its shape and element"
               else snd <$> familyIn chain acc fc owner n !(traverse (normaliseClosed . close g) args)
    (TType _ _, _) => reject fc owner rule "Type in a runtime position"
    (Erased _ _, _) => reject fc owner rule "a type that depends on a runtime or erased value"
    -- A binder of the type read so far stands for a value of quantity 0 or
    -- a runtime one, as an erased part does.
    (Local {}, _) => reject fc owner rule "a type that depends on a runtime or erased value"
    _ => do reject fc owner rule ("unsupported runtime type " ++ !(showTT (close g tm)))

  ||| Registers a family instance, once, and gives the type of a value of
  ||| it at the index terms its arguments give. A family is the type
  ||| constructor at the arguments its key holds; its indices are the
  ||| positions the key does not hold, each read into an index term
  ||| (`indexTerm`). Its identity is minted before its constructors are
  ||| read, so a field of the family itself finds it: a recursive family
  ||| names itself. Registering descends on the room the chain leaves among
  ||| the links within the growth check's bounds (`Descending`): a new
  ||| instance is checked against those bounds and pushed. A data type
  ||| whose fields need ever larger instances of itself (`data T a = L a |
  ||| N (T (a, a))`) is refused before translation, by the growth phase.
  familyIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             (chain : Registering) -> (0 _ : Descending chain) ->
             FC -> String -> Name -> List ClosedTerm -> Front (FamilyId, Ty)
  familyIn chain (Access rec) fc owner tcon args0 = do
    def <- lookupDef fc owner tcon
    let tname = show (fullname def)
    facts <- tyConFacts def
    let params = facts.params
    let roles = facts.roles
    let positions = [0 .. length args0]
    args <- traverse (\(i, a) => let r = roleAt i roles in
                                 if inKey r then argumentKey fc owner r !(canonicalTypeArg a)
                                            else pure (Erased EmptyFC Placeholder))
                     (zip positions args0)
    let statics = map (\(i, a) => if inKey (roleAt i roles) then Just a else Nothing) (zip positions args)
    indices <- traverse indexTerm (map snd (filter (\(i, _) => not (inKey (roleAt i roles))) (zip positions args0)))
    found <- instanceKey fc owner (fullname def) id statics
    st <- getState
    case lookup found.link st.familyIds of
      Just fam => pure (fam, DataT fam indices)
      Nothing => case elemLink found.link chain.links of
        -- A link on the chain is in the table already: its identity was
        -- minted before its constructors were read.
        Holds _ => internal fc (tname ++ ", registered, is not in the table of families")
        Fails fresh => do
          let fam = MkFamilyId st.nextFamily
          updateState { familyIds $= insert found.link fam, nextFamily $= S }
          let what = keyText found.key ++ ", registered,"
          boundsHold fc what found.link.definition statics
          inside <- sizedWithin fc what chain.sizes found.link
          TCon arity _ _ _ _ datacons _ <- pure (definition def)
            | _ => reject fc owner ValueType (tname ++ " is not a data type")
          let Just datacons = datacons
            | Nothing => reject fc owner DataType (tname ++ " has no known constructors")
          loc <- toLoc (location def)
          sorts <- indexSorts def (filter (\i => not (inKey (roleAt i roles))) (take arity [0 .. arity]))
          conList <- traverse (constructor (MkRegistering chain.sizes (found.link :: chain.links))
                                           (rec (found.link :: chain.links)
                                                (Extend (\e => fresh (replace {p = Elem found.link} (keyedBySelf chain.links) e))
                                                        inside.member))
                                           fc owner fam found.link args params roles)
                              datacons
          let sorted = sortBy (\(a, _), (b, _) => compare (snd a).tag (snd b).tag) conList
          let promise = case (hooksOf (fullname def)).sumShape of
                          Just IsInPlace => InPlace
                          _ => None
          updateState { families $= insert fam (MkFamily fam found.key promise sorts (map fst sorted) loc)
                        , familyOrder $= (:< fam) }
          pure (fam, DataT fam indices)
    where
      -- The sorts of a type constructor's index positions, from its type.
      indexSorts : GlobalDef -> List Nat -> Front (List Sort)
      indexSorts d ps = go none 0 !(normaliseClosed (type d))
        where
          go : Given vs -> Nat -> TT vs -> Front (List Sort)
          go g i (Bind bfc _ (Pi _ _ _ a) sc) = do
            rest <- go (give (Erased bfc Placeholder) g) (S i) sc
            if elem i ps then (:: rest) <$> sortOfType !(normaliseClosed (close g a)) else pure rest
          go g i _ = pure []

  ||| A constructor of a family being registered, with its arguments'
  ||| kinds, registered too: its erased binders (the quantity-0 arguments an
  ||| index of its result or a field's type names, renumbered as levels of
  ||| its own scope in order), its equation (the index terms its result
  ||| type gives) and its fields. The translation holds a field's type with
  ||| the constructor's levels outside the language, since a field read in
  ||| a body is at the scope's levels, which the match gives it.
  constructor : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                (chain : Registering) -> (0 _ : Descending chain) ->
                FC -> String -> FamilyId -> Link Form -> List ClosedTerm -> List Nat -> List Role -> Name ->
                Front ((k ** Con k), List ArgKind)
  constructor chain acc fc owner fam link targs ps roles dcon = do
    def <- lookupDef fc owner dcon
    let cname = show (fullname def)
    DCon _ arity _ <- pure (definition def)
      | _ => reject fc owner CompiledModule (cname ++ " is not a constructor")
    Just cid <- conIdOf fam def
      | Nothing => reject fc owner CompiledModule (cname ++ " is not a constructor")
    loc <- toLoc (location def)
    -- The type as written may hide its binders behind a definition
    -- (`a -@ b` is `(1 _ : a) -> b`); its normal form shows each one,
    -- with the quantity that makes a field linear.
    ty <- normaliseClosed (type def)
    let layout = paramLayout def ps roles ty
    -- Every match binds `arity` arguments: a layout of another length
    -- would misplace every field after the first difference.
    when (length layout /= arity) $
      internal (location def) (cname ++ " has " ++ show arity ++ " arguments, but its type binds " ++
                               show (length layout))
    walked <- walk chain acc def cname (location def) targs 0 0 0 layout none ty
    -- The result's index terms, at the family's index positions.
    let resultArgs = snd (getFnArgs walked.returns)
    equation0 <- traverse indexTerm
                   (map snd (filter (\(i, _) => not (inKey (roleAt i roles))) (zip [0 .. length resultArgs] resultArgs)))
    let fields0 = mapMaybe fieldBinder walked.kinds
    -- A binder no index and no field names is an erased proof: it does
    -- not exist.
    let used = nub (levelsOfTerms equation0 ++ concatMap (levelsOfTy . (.type)) fields0)
        kept = filter (\k => elem k used) (take (length walked.erasedTypes) [0 .. length walked.erasedTypes])
        renumber = \k => findIndex' k kept
    binders <- traverse (\(at, t) => (\sort => MkConBinder sort at) <$> sortOfType !(normaliseClosed t))
                        (map snd (filter (\(k, _) => elem k kept) (zip [0 .. length walked.erasedTypes] walked.erasedTypes)))
    let fields = map (\b => { type $= relevelTy renumber } b) fields0
        equation = relevelTerms renumber equation0
        con = (length fields ** MkCon cid (shortName (fullname def)) binders equation (fromList fields) loc)
        unlinkedKinds = map (\k => case k of
                                     Field i b t => Field i ({ type $= relevelTy (const Nothing) } b) t
                                     other => other) walked.kinds
    updateState { cons $= insert cid (MkConLayout unlinkedKinds (fullname def) con) }
    pure (con, unlinkedKinds)
    where
      findIndex' : Nat -> List Nat -> Maybe Nat
      findIndex' k ks = finToNat <$> findIndex (== k) ks

  ||| The constructor's arguments, read under the binders passed, each
  ||| given its value: a parameter is the instance's, one of quantity 0 is
  ||| no field and is given its stand-in, the next level of the
  ||| constructor's own scope, anything else is the next field, an
  ||| implementation among them a choice (`choiceFamily`).
  walk : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         (chain : Registering) -> (0 _ : Descending chain) -> (con : GlobalDef) ->
         String -> FC -> List ClosedTerm -> (at, i, e : Nat) -> List (Maybe Nat) ->
         Given vs -> TT vs -> Front Walked
  walk chain acc con cname dfc targs at i e (Just p :: ls) g (Bind bfc _ (Pi {}) sc) = do
    let v = fromMaybe (Erased bfc Placeholder) (getAt p targs)
    w <- walk chain acc con cname dfc targs (S at) i e ls (give v g) sc
    pure ({ kinds $= (Param v ::) } w)
  walk chain acc con cname dfc targs at i e (Nothing :: ls) g (Bind bfc _ (Pi _ rig _ a) sc) =
    case argumentAt con at rig of
      RuntimeValue q => do
        let g' = give (Erased bfc Placeholder) g
        a' <- normaliseClosed (close g a)
        when !(erasedOutsideIndices cname a') $ do
          reject dfc cname DependentField ("a field type that depends on another field: " ++ !(showTT a'))
        b <- coreBinderIn chain acc none dfc cname DependentField q a'
        w <- walk chain acc con cname dfc targs (S at) (S i) e ls g' sc
        pure ({ kinds $= (Field i b a' ::) } w)
      _ => do
        w <- walk chain acc con cname dfc targs (S at) i (S e) ls (give (marker e) g) sc
        pure ({ kinds $= (ErasedArg ::), erasedTypes $= ((at, close g a) ::) } w)
  walk _ _ _ _ _ _ _ _ _ _ g t = pure (MkWalked [] [] (close g t))

  ||| The family a type names, when it is a data type and not a natural, a
  ||| machine word or an array of either kind: the family, and the type of
  ||| its values at the type's index terms.
  dataOfIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             (chain : Registering) -> (0 _ : Descending chain) ->
             Given vars -> FC -> String -> TT vars -> Front (Maybe (FamilyId, Ty))
  dataOfIn chain acc g fc owner tm = case getFnArgs tm of
    (Ref _ (TyCon _) n, args) => do
      def <- lookupDef fc owner n
      let hs = hooksOf (fullname def)
      case (!(tyConFacts def)).natness of
        Chain => pure Nothing
        _ => if hs.wordType || isJust hs.orderedArray || hs.valueArray then pure Nothing else do
               args' <- traverse (normaliseClosed . close g) args
               Just <$> familyIn chain acc fc owner n args'
    _ => pure Nothing

  ||| The binder of a position of this type at this quantity: the Core type
  ||| at the quantity Idris gave the position.
  coreBinderIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 (chain : Registering) -> (0 _ : Descending chain) ->
                 {cat : Category} -> Given vars -> FC -> String -> Rule cat -> Uses -> TT vars -> Front Binder
  coreBinderIn chain acc g fc owner rule q tm = MkBinder q <$> coreTypeIn chain acc g fc owner rule tm

||| Reads a type from the start of a registration: its normal form, under
||| no binder, with no family being registered.
outermost : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            ((chain : Registering) -> (0 _ : Descending chain) ->
             Given Scope.empty -> ClosedTerm -> Front a) -> ClosedTerm -> Front a
outermost read tm = do
  b <- (.sizes) <$> getState
  read (MkRegistering b []) (started b) none !(normaliseClosed tm)

||| The Core type of a closed type. A type that has no runtime
||| representation is reported under `rule`: `ValueType`, or
||| `DependentField` for a constructor field.
export
coreType : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           {cat : Category} -> FC -> String -> Rule cat -> ClosedTerm -> Front Ty
coreType fc owner rule = outermost (\chain, acc, g => coreTypeIn chain acc g fc owner rule)

||| The family a closed type names, when it is a data type and not a
||| natural, a machine word or an array of either kind (`dataOfIn`).
export
dataOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         FC -> String -> ClosedTerm -> Front (Maybe (FamilyId, Ty))
dataOf fc owner = outermost (\chain, acc, g => dataOfIn chain acc g fc owner)

||| The binder of a position of a closed type at a rig (`coreBinderIn`). A
||| binder of quantity 0 binds no runtime value, so it has no binder: every
||| caller leaves such a position out first, and one that does not is the
||| compiler's error, never a binder at some quantity.
export
coreBinder : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             {cat : Category} -> FC -> String -> Rule cat -> RigCount -> ClosedTerm -> Front Binder
coreBinder fc owner rule rig tm = case use rig of
  Erased => internal fc (owner ++ ": a binder of quantity 0 given a runtime representation")
  Used q => outermost (\chain, acc, g => coreBinderIn chain acc g fc owner rule q) tm
