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
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Registry
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.Fin
import Data.List
import Data.Maybe

%default total

------------------------------------------------------------------------------
-- Spines and forms
------------------------------------------------------------------------------

||| The extents of a normalised shape, outermost first. The value-array
||| entries pin the shape type to base's snoc list, whose constructors are
||| told apart by their tags, the order the declaration gives them: `Lin`
||| (tag 0), of the element type alone, and `:<` (tag 1), of the element
||| type, the rest and the last. Nothing when the shape is no such value,
||| a variable or a computation that is stuck.
export
shapeSpine : ClosedTerm -> Maybe (List ClosedTerm)
shapeSpine (App _ (Ref _ (DataCon 0 _) _) _) = Just []
shapeSpine (App _ (App _ (App _ (Ref _ (DataCon 1 _) _) _) rest) n) = (++ [n]) <$> shapeSpine rest
shapeSpine _ = Nothing

||| A shape's form: its spine with every extent erased, what keys an
||| instance whose types need the rank and not the sizes.
export
shapeForm : ClosedTerm -> Maybe ClosedTerm
shapeForm (App _ lin@(Ref _ (DataCon 0 _) _) a) = Just (App EmptyFC lin a)
shapeForm (App _ (App _ (App _ snoc@(Ref _ (DataCon 1 _) _) a) rest) _) =
  (\r => App EmptyFC (App EmptyFC (App EmptyFC snoc a) r) (Erased EmptyFC Placeholder)) <$> shapeForm rest
shapeForm _ = Nothing

||| Whether a type constructor is a value array's.
valueArray : {auto c : Ref Ctxt Defs} -> Name -> Core Bool
valueArray n = (\full => (hooksOf full).valueArray) <$> toFullNames n

||| The shape of a value array, when the term is one applied to its shape
||| and element: `Array s a` or `LArray s a`.
export
arrayShape : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core (Maybe (ClosedTerm, ClosedTerm))
arrayShape (App _ (App _ (Ref _ (TyCon _) n) s) a) =
  pure (if !(valueArray n) then Just (s, a) else Nothing)
arrayShape _ = pure Nothing

||| A parameter put in a type to see whether a value array's shape mentions
||| it: a reference to a definition that does not exist, at which reduction
||| stops, as `Closed.unknownPart` is.
formProbe : ClosedTerm
formProbe = Ref EmptyFC Func (MN "idris-mlir-form" 0)

isFormProbe : TT vs -> Bool
isFormProbe (Ref _ _ (MN "idris-mlir-form" _)) = True
isFormProbe _ = False

||| Does the rest of a type need a parameter's form: does a value array's
||| shape in it mention the parameter (the rest with `formProbe` for it)?
||| A shape the rest of the type does not put in a value array keys
||| nothing, as any erased value does.
export
formNeeded : {auto c : Ref Ctxt Defs} -> (ClosedTerm -> ClosedTerm) -> Core Bool
formNeeded rest = do
  ty <- toFullNames !(normaliseClosed (rest formProbe))
  pure (mentions inShape ty)
  where
    inShape : TT vs -> Bool
    inShape tm = case getFnArgs tm of
      (Ref _ (TyCon _) n, [s, _]) => (hooksOf n).valueArray && mentions isFormProbe s
      _ => False

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
||| its source: a reference to a definition that does not exist, at which
||| reduction stops, numbered by the parameter, and for an axis applied to
||| another such reference numbered by the axis, so that every parameter
||| and every axis has its own.
sourceRef : SizeVar -> ClosedTerm
sourceRef (Axis i j) =
  App EmptyFC (Ref EmptyFC Func (MN "idris-mlir-axis" (cast i))) (Ref EmptyFC Func (MN "idris-mlir-axis-at" (cast j)))
sourceRef (Size i) = Ref EmptyFC Func (MN "idris-mlir-size" (cast i))

sourceOf : ClosedTerm -> Maybe SizeVar
sourceOf (App _ (Ref _ _ (MN "idris-mlir-axis" i)) (Ref _ _ (MN "idris-mlir-axis-at" j))) = Just (Axis (cast i) (cast j))
sourceOf (Ref _ _ (MN "idris-mlir-size" k)) = Just (Size (cast k))
sourceOf _ = Nothing

||| A form with its axis `j` standing for itself, the shape parameter at
||| `i`'s.
axes : Nat -> ClosedTerm -> ClosedTerm
axes i (App _ (App _ (App _ snoc@(Ref _ (DataCon 1 _) _) a) rest) _) =
  -- The axes are numbered outermost first, so the last is the count of
  -- those before it.
  let before = maybe 0 length (shapeSpine rest) in
  App EmptyFC (App EmptyFC (App EmptyFC snoc a) (axes i rest)) (sourceRef (Axis i before))
axes i tm = tm

||| The sources of an array type's dimensions, outermost first, the
||| element's after the shape's when it is an array too; `Nothing` for a
||| dimension no size variable fixes (a literal, a computed size).
export
dimensionSources : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core (List (Maybe SizeVar))
dimensionSources (App _ (App _ (Ref _ (TyCon _) n) s) a) =
  if !(valueArray n)
    then (map sourceOf (fromMaybe [] (shapeSpine s)) ++) <$> dimensionSources a
    else pure []
dimensionSources _ = pure []

||| A definition's parameters as an instance has them, each with its
||| position, kind and Idris type with every size variable standing for
||| itself (`sourceRef`), and the result type likewise: a type parameter or
||| an implementation is its value, a form parameter its form with its
||| axes standing for themselves, a runtime value its shape where the
||| instance is keyed by it, and any other parameter itself, which only an
||| extent, a natural, can show.
export
sizedTelescope : {auto c : Ref Ctxt Defs} ->
                 Nat -> ClosedTerm -> List PKind -> Core (List (Nat, PKind, ClosedTerm), ClosedTerm)
sizedTelescope arity ty kinds = go 0 arity ty kinds
  where
    value : Nat -> PKind -> ClosedTerm
    value i (TypeParam t) = t
    value i (DictParam t _) = t
    value i (FormParam f) = axes i f
    value i (ValueParam _ (Just s) _) = s
    value i _ = sourceRef (Size i)

    -- A binder that is not yet a pi may become one once normalised: the
    -- type is read through definitions that compute it.
    go : Nat -> Nat -> ClosedTerm -> List PKind -> Core (List (Nat, PKind, ClosedTerm), ClosedTerm)
    go i Z t _ = pure ([], !(normaliseClosed t))
    go i (S k) t ks = do
      t' <- case t of
              Bind _ _ (Pi {}) _ => pure t
              _ => normaliseClosed t
      case (t', ks) of
        (Bind _ _ (Pi _ _ _ a) sc, kind :: ks') => do
          a' <- normaliseClosed a
          (rest, res) <- go (S i) k (subst (value i kind) sc) ks'
          pure ((i, kind, a') :: rest, res)
        _ => pure ([], t')

||| The dimensions a tie can state of a value of this type: a value array's.
export
valueDims : Ty -> Maybe (List Dim)
valueDims (TensorT ds _) = Just ds
valueDims _ = Nothing

||| The runtime parameter a position is, counting only the parameters that
||| exist at runtime.
export
runtimeIndex : List PKind -> Nat -> Maybe Nat
runtimeIndex kinds i =
  if isJust (join (map runtimeBinder (getAt i kinds)))
     then Just (length (mapMaybe runtimeBinder (take i kinds)))
     else Nothing

||| The runtime parameter a position is, when Idris lets it be used any
||| number of times: only such a value can also witness a dimension, since
||| a value used once is used by the call or the body it is given to.
unrestricted : List PKind -> Nat -> Maybe Nat
unrestricted kinds i = case getAt i kinds >>= runtimeBinder of
  Just (MkBinder Many _) => runtimeIndex kinds i
  _ => Nothing

||| How a dimension's value is had from the runtime parameters: the
||| natural at runtime parameter `r`, or axis `k` of the array at runtime
||| parameter `r`.
public export
data Witness = NatAt Nat | AxisAt Nat Nat

||| For each runtime parameter of quantity many whose type is a tensor, the
||| witness of each of its dimensions that another parameter of quantity
||| many fixes first: a runtime natural that is the size, or the earliest
||| array dimension of the same source, in parameter then axis order (which
||| is itself left unstated). A static dimension, one no size variable
||| fixes and one only a parameter used once fixes have none.
export
entryWitnesses : {auto c : Ref Ctxt Defs} ->
                 List PKind -> List (Nat, PKind, ClosedTerm) -> Core (List (Nat, List (Maybe Witness)))
entryWitnesses kinds params = do
  arrays <- traverse sourced params
  let sourcesSeen = concatMap firsts (catMaybes arrays)
  pure (mapMaybe (tieOf sourcesSeen) (catMaybes arrays))
  where
    -- A parameter that a tie can state: runtime, of quantity many, a tensor.
    sourced : (Nat, PKind, ClosedTerm) -> Core (Maybe (Nat, List Dim, List (Maybe SizeVar)))
    sourced (i, ValueParam (MkBinder Many t) _ _, a) = case valueDims t of
      Just ds => do
        Just r <- pure (runtimeIndex kinds i)
          | Nothing => pure Nothing
        srcs <- dimensionSources a
        pure (Just (r, ds, srcs))
      Nothing => pure Nothing
    sourced _ = pure Nothing

    -- Every (source, runtime parameter, axis) of a dynamic dimension.
    firsts : (Nat, List Dim, List (Maybe SizeVar)) -> List (SizeVar, Nat, Nat)
    firsts (r, ds, srcs) =
      mapMaybe (\(k, d, src) => case (d, src) of
                                  (Dynamic, Just s) => Just (s, r, k)
                                  _ => Nothing)
               (zip3 [0 .. length ds] ds srcs)

    witness : List (SizeVar, Nat, Nat) -> Nat -> Nat -> Dim -> Maybe SizeVar -> Maybe Witness
    witness seen r k Dynamic (Just s) = case s of
      Size i => case unrestricted kinds i of
        Just n => Just (NatAt n)
        Nothing => earliest
      _ => earliest
      where
        earliest : Maybe Witness
        earliest = case find (\(s', _, _) => s' == s) seen of
          Just (_, r', k') => if r' == r && k' == k then Nothing else Just (AxisAt r' k')
          Nothing => Nothing
    witness _ _ _ _ _ = Nothing

    tieOf : List (SizeVar, Nat, Nat) -> (Nat, List Dim, List (Maybe SizeVar)) -> Maybe (Nat, List (Maybe Witness))
    tieOf seen (r, ds, srcs) =
      let ws = zipWith3 (witness seen r) [0 .. length ds] ds (srcs ++ replicate (length ds) Nothing) in
      if any isJust ws then Just (r, ws) else Nothing

||| The witnesses of a call's result: each dynamic dimension of the result
||| type whose source one of the call's runtime arguments of quantity many
||| has, a natural argument or a dimension of an array argument. An argument
||| used once is the call's, and witnesses nothing after it.
export
resultWitnesses : {auto c : Ref Ctxt Defs} ->
                  List PKind -> List (Nat, PKind, ClosedTerm) -> ClosedTerm -> Ty -> Core (List (Maybe Witness))
resultWitnesses kinds params res rt = case valueDims rt of
  Nothing => pure []
  Just ds => do
    srcs <- dimensionSources res
    arrays <- traverse sourced params
    let seen = concat (catMaybes arrays)
    pure (zipWith (witness seen) ds (srcs ++ replicate (length ds) Nothing))
  where
    sourced : (Nat, PKind, ClosedTerm) -> Core (Maybe (List (SizeVar, Nat, Nat)))
    sourced (i, ValueParam (MkBinder Many t) _ _, a) = case valueDims t of
      Just pds => do
        Just r <- pure (runtimeIndex kinds i)
          | Nothing => pure Nothing
        psrcs <- dimensionSources a
        pure (Just (mapMaybe (\(k, d, src) => case (d, src) of
                                                (_, Just s) => Just (s, r, k)
                                                _ => Nothing)
                             (zip3 [0 .. length pds] pds psrcs)))
      Nothing => pure Nothing
    sourced _ = pure Nothing

    witness : List (SizeVar, Nat, Nat) -> Dim -> Maybe SizeVar -> Maybe Witness
    witness seen Dynamic (Just s) = case s of
      Size i => case unrestricted kinds i of
        Just n => Just (NatAt n)
        Nothing => fromArray
      _ => fromArray
      where
        fromArray : Maybe Witness
        fromArray = (\(_, r, k) => AxisAt r k) <$> find (\(s', _, _) => s' == s) seen
    witness _ _ _ = Nothing

||| The term of a witness, over the variables that hold the runtime
||| arguments.
export
witnessTerm : Loc -> List (Fin n) -> Witness -> Maybe (Term n)
witnessTerm loc vs (NatAt r) = Var loc <$> getAt r vs
witnessTerm loc vs (AxisAt r k) = (\v => Tensor loc (Extent k) NatT [Var loc v]) <$> getAt r vs

------------------------------------------------------------------------------
-- Binding
------------------------------------------------------------------------------

||| Each term bound by a `let` at the quantity of the parameter it is given
||| for, left to right, and the body built over the variables that hold
||| them, in the same order, with the renaming of the scope outside. A value
||| used more than once, or in an order of its own, is evaluated once, where
||| the call put it; one Idris lets the callee use once stays used once.
export
bindAll : {0 m : Nat} -> Loc -> List (Quantity, Term m) ->
          ({0 p : Nat} -> (Fin m -> Fin p) -> List (Fin p) -> Term p) -> Term m
bindAll loc ts k = go id ts k
  where
    -- Under the binders already made: `ren` takes the outer scope into the
    -- current one, and each term is renamed once, where it is bound.
    go : {0 p : Nat} -> (Fin m -> Fin p) -> List (Quantity, Term m) ->
         ({0 r : Nat} -> (Fin p -> Fin r) -> List (Fin r) -> Term r) -> Term p
    go ren [] k' = k' id []
    go ren ((q, t) :: rest) k' =
      Let loc (shown "argument") q (rename ren t)
          (go (FS . ren) rest (\ren', vs => k' (ren' . FS) (ren' FZ :: vs)))
