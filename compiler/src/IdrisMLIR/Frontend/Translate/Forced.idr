-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Which constructor a scrutinee's type can still be when its indices are
||| only partly known. A variable index matches no constructor; an erased
||| index matches any.
module IdrisMLIR.Frontend.Translate.Forced

import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Frontend.Translate.Closed

import Data.List

%default covering

||| A value known to be one constructor, with the environment positions of
||| the arguments it was built from. Positions are into the environment
||| the match sees, new arguments at the front.
public export
data Known : Type where
  KnownCon : Name -> List Nat -> Known

||| The part of a scrutinee's type a match can see. `VLocal` is an
||| environment position. `VSkip` is a part that decides nothing: erased,
||| a universe, or a local this type does not map to an environment
||| position.
public export
data View : Type where
  VLocal : Nat -> View
  VRef : Name -> List View -> View
  VLit : Constant -> View
  VSkip : View

||| No position is known yet. `n` is the length of the environment.
export
emptyKnown : Nat -> List (Maybe Known)
emptyKnown n = replicate n Nothing

||| `0 .. k-1`, the pattern arguments just bound at the front.
argPositions : Nat -> List Nat
argPositions n = go Z n
  where
    go : Nat -> Nat -> List Nat
    go _ Z = []
    go i (S k) = i :: go (S i) k

||| A recorded position, moved back by the `k` arguments now in front.
shiftKnown : Nat -> Maybe Known -> Maybe Known
shiftKnown _ Nothing = Nothing
shiftKnown k (Just (KnownCon n ps)) = Just (KnownCon n (map (+ k) ps))

||| Write `v` at index `i`. A scrutinee past the end of the list extends
||| it with unknown positions until that index exists.
place : Nat -> Maybe Known -> List (Maybe Known) -> List (Maybe Known)
place Z v [] = [v]
place Z v (_ :: xs) = v :: xs
place (S i) v [] = Nothing :: place i v []
place (S i) v (x :: xs) = x :: place i v xs

||| The known-list after a constructor alternative binds `k` pattern
||| arguments in front. The scrutinee was at `idx`; it is this constructor
||| applied to those new arguments, which occupy positions `0 .. k-1`.
export
underKnown : Nat -> Nat -> Name -> List (Maybe Known) -> List (Maybe Known)
underKnown k idx cn known =
  place (k + idx)
        (Just (KnownCon cn (argPositions k)))
        (replicate k Nothing ++ map (shiftKnown k) known)

||| The known-list after `k` variables are bound in front, none of them
||| known.
export
underBinders : Nat -> List (Maybe Known) -> List (Maybe Known)
underBinders k known = replicate k Nothing ++ map (shiftKnown k) known

||| The constructors of a type name. A name that is not such a type has
||| none, as does a type whose constructors are not recorded.
export
dataConstructors : {auto c : Ref Ctxt Defs} -> Name -> Core (List Name)
dataConstructors n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => pure []
  case definition def of
    TCon _ _ _ _ _ (Just cons) _ => pure cons
    _ => pure []

||| A constructor type's result, still under every pi binder.
data ConRet : Type where
  MkConRet : {0 vars : Scope} -> TT vars -> ConRet

||| The result, and how many pi binders wrap it. Every binder counts,
||| implicit and erased included: the result's locals are indices into
||| that whole telescope, so local `i` (innermost zero) is pattern
||| argument `arity - 1 - i`. Dropping a binder would name the wrong one.
pis : TT vars -> (Nat, ConRet)
pis (Bind _ _ (Pi {}) sc) = case pis sc of
  (n, ret) => (S n, ret)
pis tm = (Z, MkConRet tm)

||| An erased subterm decides nothing.
erased : TT vars -> Bool
erased (Erased _ _) = True
erased _ = False

||| A skipped part of the view decides nothing. A universe is one: the
||| view has no separate form for it.
decidesNothing : View -> Bool
decidesNothing VSkip = True
decidesNothing _ = False

||| Local `i`, innermost zero, is pattern argument `arity - 1 - i`. Against
||| an environment variable it is an equation. Against a constructor, a
||| literal or a skip the argument is bound to the whole of it, so there
||| is no environment position to record. One argument can be equated more
||| than once: `First` is `IsVar n Z (n :: ns)`, so the name and the list
||| head are both the outer argument.
localEq : Nat -> Nat -> View -> List (Nat, Nat)
localEq arity i (VLocal p) =
  if i < arity then [(p, minus arity (S i))] else []
localEq _ _ _ = []

mutual
  ||| One subterm that does not fit rejects the constructor. `Later`'s `S`
  ||| therefore does not fit a `Z` index, and a `Z` or `S` on the left does
  ||| not fit an index that is still an environment variable.
  fit : {auto c : Ref Ctxt Defs} -> {0 vars : Scope} ->
        Nat -> TT vars -> View -> Core (Maybe (List (Nat, Nat)))
  fit arity tm view =
    if erased tm || decidesNothing view then pure (Just [])
    else case tm of
      Local _ _ i _ => pure (Just (localEq arity i view))
      _ => case (getFnArgs tm, view) of
        ((Ref _ _ n, as), VRef m bs) => do
          same <- (==) <$> toFullNames n <*> toFullNames m
          if same && length as == length bs
            then fitArgs arity as bs
            else pure Nothing
        ((PrimVal _ c, []), VLit d) =>
          pure (if c == d then Just [] else Nothing)
        _ => pure Nothing

  fitArgs : {auto c : Ref Ctxt Defs} -> {0 vars : Scope} ->
            Nat -> List (TT vars) -> List View -> Core (Maybe (List (Nat, Nat)))
  fitArgs _ [] [] = pure (Just [])
  fitArgs arity (a :: as) (b :: bs) = do
    Just eqs <- fit arity a b
      | Nothing => pure Nothing
    Just rest <- fitArgs arity as bs
      | Nothing => pure Nothing
    pure (Just (eqs ++ rest))
  fitArgs _ _ _ = pure Nothing

||| Just (arity, equations). Equations are (env position, pattern-arg position).
||| Nothing if this constructor does not fit the view.
export
matchConstructor : {auto c : Ref Ctxt Defs} -> Name -> View -> Core (Maybe (Nat, List (Nat, Nat)))
matchConstructor cn view = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact cn (gamma defs)
    | Nothing => pure Nothing
  case pis (type def) of
    (arity, MkConRet ret) => do
      eqs <- fit arity ret view
      pure (map (\es => (arity, es)) eqs)
