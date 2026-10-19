-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Shapes of the array language: a value array's rank is the form of its
||| shape, a snoc list of naturals, and its extents are the naturals in it.
||| Here the form is read off a normal form, an erased shape is keyed by its
||| form where a value array's type needs it, and the dimensions that one
||| size variable fixes are found, so that a function's entry and a call's
||| result state them equal (`idr.tie_shape`).
module IdrisMLIR.Frontend.Translate.Shapes

import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Registry
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.Fin
import Data.List
import Data.Maybe
import Data.SnocList
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Spines and forms
------------------------------------------------------------------------------

||| A normalised shape as base's snoc list builds it, which the value-array
||| entries pin the shape type to: its constructors are told apart by their
||| tags, the order the declaration gives them, `Lin` (tag 0) of the
||| element type alone, and `:<` (tag 1) of the element type, the rest and
||| the last. Anything else (a variable, a computation that is stuck) is
||| no such value. A shape may stand under binders: a family's body holds
||| one over the family's variable (`\n => Vector n Int`).
public export
data ShapeView : TT vs -> Type where
  ||| `Lin` applied to the element type.
  SLin : {0 f : FC} -> (lin, e : TT vs) -> ShapeView (App f lin e)
  ||| `:<` applied to the element type, the rest and the last.
  SSnoc : {0 f, f', f'' : FC} -> (snoc, e, rest, n : TT vs) -> ShapeView (App f (App f' (App f'' snoc e) rest) n)
  SOther : ShapeView t

||| The one reading of a shape's constructors.
export
shapeView : (t : TT vs) -> ShapeView t
shapeView (App _ lin@(Ref _ (DataCon 0 _) _) e) = SLin lin e
shapeView (App _ (App _ (App _ snoc@(Ref _ (DataCon 1 _) _) e) rest) n) = SSnoc snoc e rest n
shapeView _ = SOther

||| A shape read as a snoc list of extents down to `Lin`: `Lin` applied to
||| the element type, and each axis, outermost first, as `:<` applied to
||| the element type, with the axis's extent. Its rank, the number of its
||| axes, is its form; its extents are the sizes.
public export
record Spine (vs : Scope) where
  constructor MkSpine
  base : TT vs
  axes : List (TT vs, TT vs)

||| A normalised shape's spine; nothing when the shape is no snoc list of
||| extents down to `Lin`.
export
readSpine : TT vs -> Maybe (Spine vs)
readSpine t = (\(b, sx) => MkSpine b (sx <>> [])) <$> go t
  where
    go : TT vs -> Maybe (TT vs, SnocList (TT vs, TT vs))
    go t with (shapeView t)
      go _ | SLin lin e = Just (App EmptyFC lin e, [<])
      go _ | SSnoc snoc e rest n = (\(b, sx) => (b, sx :< (App EmptyFC snoc e, n))) <$> go rest
      go _ | SOther = Nothing

||| The spine of a shape a value array's type or a data instance's key
||| needs: the one place such a shape is read. A shape that is no snoc list
||| of extents (a variable no instance fixes, a recursion that builds it
||| deeper) has no rank, and a tensor has nothing else, so the program is
||| refused here, before any type or key is made of it.
export
spineOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
          FC -> String -> TT vs -> Core (Spine vs)
spineOf fc owner t = case readSpine t of
  Just sp => pure sp
  Nothing => reject fc owner Polymorphism ("a shape whose rank no analysis fixes: " ++ show !(toFullNames t))

||| A spine's extents, outermost first.
export
extents : Spine vs -> List (TT vs)
extents sp = map snd sp.axes

||| A spine's form: its constructors with every extent erased, what keys an
||| instance whose types need the rank and not the sizes.
export
formOf : Spine vs -> TT vs
formOf sp = foldl (\r, (snoc, _) => App EmptyFC (App EmptyFC snoc r) (Erased EmptyFC Placeholder)) sp.base sp.axes

||| Whether a type constructor is a value array's.
valueArray : {auto c : Ref Ctxt Defs} -> Name -> Core Bool
valueArray n = (\full => (hooksOf full).valueArray) <$> toFullNames n

||| A type constructor applied to two arguments, as a value array's type is
||| to its shape and element (`Array s a`, `LArray s a`), or anything else.
public export
data ArrayParts : TT vs -> Type where
  ArrayOf : {0 f, f', f'' : FC} -> {0 ar : Nat} -> (n : Name) -> (s, a : TT vs) ->
            ArrayParts (App f (App f' (Ref f'' (TyCon ar) n) s) a)
  NoArray : ArrayParts t

||| The one reading of an array type's application.
export
arrayParts : (t : TT vs) -> ArrayParts t
arrayParts (App _ (App _ (Ref _ (TyCon _) n) s) a) = ArrayOf n s a
arrayParts _ = NoArray

||| The shape and the element of a value array's type, when the term is
||| one.
export
arrayView : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core (Maybe (ClosedTerm, ClosedTerm))
arrayView t with (arrayParts t)
  arrayView _ | ArrayOf n s a = pure (if !(valueArray n) then Just (s, a) else Nothing)
  arrayView _ | NoArray = pure Nothing

||| A parameter put in a type to see whether the type puts it in a form
||| (`Types.formNeeded`): a name no definition has, at which reduction
||| stops.
export
formProbe : ClosedTerm
formProbe = probeTerm ProbeForm

export
isFormProbe : TT vs -> Bool
isFormProbe t = case probeOfTerm t of
  Just ProbeForm => True
  _ => False

------------------------------------------------------------------------------
-- Runtime parameters
------------------------------------------------------------------------------

||| What a parameter binds at run time, if it is a parameter at run time:
||| a value, or the values an implementation closes over, held as one.
public export
boundAtRuntime : PKind -> Maybe Binder
boundAtRuntime (ValueParam b _ _) = Just b
boundAtRuntime (DictParam _ (Just h)) = Just h.binder
boundAtRuntime _ = Nothing

||| One more for what exists at run time.
public export
counted : Maybe a -> Nat -> Nat
counted (Just _) n = S n
counted Nothing n = n

||| How many of a call's parameters exist at run time.
public export
Runtimes : List PKind -> Nat
Runtimes [] = Z
Runtimes (k :: ks) = counted (boundAtRuntime k) (Runtimes ks)

||| A position among the parameters after one that exists at run time or
||| not: one further, or the same.
export
after : (m : Maybe a) -> Fin n -> Fin (counted m n)
after (Just _) i = FS i
after Nothing i = i

||| The binders of a call's parameters that exist at run time, in order.
export
runtimeBinders : (kinds : List PKind) -> Vect (Runtimes kinds) Binder
runtimeBinders [] = []
runtimeBinders (k :: ks) = before (boundAtRuntime k) (runtimeBinders ks)
  where
    before : (m : Maybe Binder) -> Vect n Binder -> Vect (counted m n) Binder
    before (Just b) bs = b :: bs
    before Nothing bs = bs

------------------------------------------------------------------------------
-- Size variables and ties
------------------------------------------------------------------------------

||| What fixes a dimension of an array in a definition's type: axis `j` of
||| the shape parameter at position `i`, or the natural parameter at `i`.
||| Two dimensions with one source are equal at every call.
public export
data SizeVar = Axis Nat Nat | Size Nat

export
Eq SizeVar where
  Axis i j == Axis i' j' = i == i' && j == j'
  Size i == Size i' = i == i'
  _ == _ = False

||| A stand-in for a size variable while a definition's type is read, by
||| its source: a probe, at which reduction stops, of the parameter, and
||| for an axis of the axis too, so that every parameter and every axis has
||| its own.
sourceRef : SizeVar -> ClosedTerm
sourceRef (Axis i j) = probeTerm (ProbeAxis i j)
sourceRef (Size i) = probeTerm (ProbeSize i)

sourceOf : ClosedTerm -> Maybe SizeVar
sourceOf t = case probeOfTerm t of
  Just (ProbeAxis i j) => Just (Axis i j)
  Just (ProbeSize i) => Just (Size i)
  _ => Nothing

||| A form with each axis standing for itself, of the shape parameter at
||| `i`, and how many axes it has. The axes are numbered outermost first,
||| so each is the count of those before it.
axes : Nat -> ClosedTerm -> (ClosedTerm, Nat)
axes i t with (shapeView t)
  axes i _ | SSnoc snoc e rest _ =
    let (rest', before) = axes i rest in
    (App EmptyFC (App EmptyFC (App EmptyFC snoc e) rest') (sourceRef (Axis i before)), S before)
  axes i t | _ = (t, 0)

||| The sources of an array type's dimensions, outermost first, the
||| element's after the shape's when it is an array too; `Nothing` for a
||| dimension no size variable fixes (a literal, a computed size).
export
dimensionSources : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core (List (Maybe SizeVar))
dimensionSources t with (arrayParts t)
  dimensionSources _ | ArrayOf n s a =
    if !(valueArray n)
      then (map sourceOf (maybe [] extents (readSpine s)) ++) <$> dimensionSources a
      else pure []
  dimensionSources _ | NoArray = pure []

||| The dimensions a tie can state of a value of this type: a value array's.
export
valueDims : Ty -> Maybe (List Dim)
valueDims (TensorT ds _) = Just ds
valueDims _ = Nothing

||| Each dimension of a Core type with its source in the Idris type, read
||| together: a dimension the Idris type gives no source has none.
pairDims : List Dim -> List (Maybe SizeVar) -> List (Dim, Maybe SizeVar)
pairDims [] _ = []
pairDims (d :: ds) [] = (d, Nothing) :: pairDims ds []
pairDims (d :: ds) (s :: ss) = (d, s) :: pairDims ds ss

||| A parameter of a definition's type as an instance has it: its kind, its
||| Idris type with every size variable standing for itself (`sourceRef`),
||| its place among the `r` parameters that exist at run time with its
||| binder there, and, for a runtime value array, each dimension with its
||| source.
public export
record SizedParam (r : Nat) where
  constructor MkSizedParam
  kind : PKind
  type : ClosedTerm
  runtime : Maybe (Fin r, Binder)
  dims : List (Dim, Maybe SizeVar)

||| A definition's parameters as an instance has them, in order.
public export
Telescope : Nat -> Type
Telescope r = List (SizedParam r)

||| A definition's parameters as an instance has them (`SizedParam`), one
||| per kind, and the result type likewise: a type parameter or an
||| implementation is its value, a form parameter its form with its axes
||| standing for themselves, a runtime value its shape where the instance
||| is keyed by it, and any other parameter itself, which only an extent, a
||| natural, can show. A binder that is not yet a pi may become one once
||| normalised: the type is read through definitions that compute it.
export
sizedTelescope : {auto c : Ref Ctxt Defs} ->
                 Nat -> ClosedTerm -> (kinds : List PKind) -> Core (Telescope (Runtimes kinds), ClosedTerm)
sizedTelescope arity ty kinds = go 0 arity ty kinds
  where
    value : Nat -> PKind -> ClosedTerm
    value i (TypeParam t) = t
    value i (DictParam t _) = t
    value i (FormParam f) = fst (axes i f)
    value i (ValueParam _ (Just s) _) = s
    value i _ = sourceRef (Size i)

    -- A parameter after one that exists at run time or not.
    later : (m : Maybe Binder) -> SizedParam n -> SizedParam (counted m n)
    later m (MkSizedParam k t rt ds) = MkSizedParam k t (mapFst (after m) <$> rt) ds

    -- Its place and binder at run time, the first of the parameters that
    -- exist there from here on.
    here : (m : Maybe Binder) -> Maybe (Fin (counted m n), Binder)
    here (Just b) = Just (FZ, b)
    here Nothing = Nothing

    go : Nat -> Nat -> ClosedTerm -> (ks : List PKind) -> Core (Telescope (Runtimes ks), ClosedTerm)
    go i Z t [] = pure ([], !(normaliseClosed t))
    go i (S j) t (k :: ks) = do
      t' <- case t of
              Bind _ _ (Pi {}) _ => pure t
              _ => normaliseClosed t
      let Bind _ _ (Pi _ _ _ a) sc = t'
        | _ => internal EmptyFC ("a parameter past the binders of " ++ show t')
      a' <- normaliseClosed a
      dims <- case typeOf <$> boundAtRuntime k of
                Just (TensorT ds _) => pairDims ds <$> dimensionSources a'
                _ => pure []
      (rest, res) <- go (S i) j (subst (value i k) sc) ks
      pure (MkSizedParam k a' (here (boundAtRuntime k)) dims :: map (later (boundAtRuntime k)) rest, res)
    go i _ t _ = internal EmptyFC ("parameter kinds other than the arity of " ++ show t)

||| How a dimension's value is had from the runtime parameters: the
||| natural at runtime parameter `i`, or axis `k` of the array there.
public export
data Witness : Nat -> Type where
  NatAt : Fin r -> Witness r
  AxisAt : Fin r -> Nat -> Witness r

export
Eq (Witness r) where
  NatAt i == NatAt i' = i == i'
  AxisAt i k == AxisAt i' k' = i == i' && k == k'
  _ == _ = False

||| What witnesses each size variable, among the parameters Idris lets be
||| used any number of times (a value used once is used by the call or the
||| body it is given to, and witnesses nothing): a runtime natural that is
||| the size first, then every dimension of an array of that source, in
||| parameter then axis order, static ones too.
export
witnesses : Telescope r -> List (SizeVar, Witness r)
witnesses tel = go 0 [<] [<] tel
  where
    -- Each dimension of the array at `x` that has a source, by axis.
    axesOf : Fin r -> Nat -> SnocList (SizeVar, Witness r) -> List (Dim, Maybe SizeVar) ->
             SnocList (SizeVar, Witness r)
    axesOf x k found [] = found
    axesOf x k found ((_, Just s) :: ds) = axesOf x (S k) (found :< (s, AxisAt x k)) ds
    axesOf x k found ((_, Nothing) :: ds) = axesOf x (S k) found ds

    go : Nat -> SnocList (SizeVar, Witness r) -> SnocList (SizeVar, Witness r) ->
         Telescope r -> List (SizeVar, Witness r)
    go i naturals arrays [] = naturals <>> (arrays <>> [])
    go i naturals arrays (p :: ps) = case p.runtime of
      Just (x, MkBinder Many _) =>
        go (S i) (naturals :< (Size i, NatAt x)) (axesOf x 0 arrays p.dims) ps
      _ => go (S i) naturals arrays ps

||| For each runtime parameter of quantity many that is an array, each of
||| its dynamic dimensions that another parameter witnesses first (the
||| first witness of its source, when that is not the dimension itself),
||| by axis.
export
entryTies : Telescope r -> List (Fin r, List (Nat, Witness r))
entryTies tel = mapMaybe arrayTies tel
  where
    ws : List (SizeVar, Witness r)
    ws = witnesses tel

    stated : Fin r -> Nat -> List (Dim, Maybe SizeVar) -> List (Nat, Witness r)
    stated x k [] = []
    stated x k ((Dynamic, Just s) :: ds) = case lookup s ws of
      Just w => if w == AxisAt x k then stated x (S k) ds else (k, w) :: stated x (S k) ds
      Nothing => stated x (S k) ds
    stated x k (_ :: ds) = stated x (S k) ds

    arrayTies : SizedParam r -> Maybe (Fin r, List (Nat, Witness r))
    arrayTies p = case p.runtime of
      Just (x, MkBinder Many _) => case stated x 0 p.dims of
        [] => Nothing
        ts => Just (x, ts)
      _ => Nothing

||| The witnesses of a call's result, by axis: each dynamic dimension of the
||| result type whose source one of the call's runtime arguments of
||| quantity many has, a natural argument or a dimension of an array
||| argument.
export
resultTies : {auto c : Ref Ctxt Defs} -> Telescope r -> ClosedTerm -> Ty -> Core (List (Nat, Witness r))
resultTies tel res rt = case valueDims rt of
  Nothing => pure []
  Just ds => (stated 0 . pairDims ds) <$> dimensionSources res
  where
    ws : List (SizeVar, Witness r)
    ws = witnesses tel

    stated : Nat -> List (Dim, Maybe SizeVar) -> List (Nat, Witness r)
    stated k [] = []
    stated k ((Dynamic, Just s) :: ds) = case lookup s ws of
      Just w => (k, w) :: stated (S k) ds
      Nothing => stated (S k) ds
    stated k (_ :: ds) = stated (S k) ds

||| The term of a witness, over the variables that hold the runtime
||| arguments: a natural, converted, or an array's extent, exact.
export
witnessTerm : Loc -> Vect r (Fin n) -> Witness r -> Stated (Term n)
witnessTerm loc vs (NatAt i) = Natural (Var loc (Data.Vect.index i vs))
witnessTerm loc vs (AxisAt i k) = SameAs (Tensor loc NatT (Extent k (Var loc (Data.Vect.index i vs))))
