-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.TT.Traversals

import Core.TT

import Data.DPair
import Data.SortedSet
import Libraries.Data.NameMap

%default total

-- The terms a binder or a metavariable's arguments hold are walked by
-- functions of their own rather than by `map`, `traverse` or `concatMap`,
-- so that each recursive call is on a part of the term it was given and
-- each traversal is total by its structure.

export
onPRefs : Monoid m =>
          (Name      -> m) ->
          (Term vars -> m)
onPRefs f = go neutral where

  go  : m -> Term vars' -> m
  gos : m -> List (Term vars') -> m
  inBinder : Binder (Term vars') -> m

  go acc (Local fc isLet idx p) = acc
  go acc (Ref fc x name) = acc <+> f name
  go acc (Meta fc x y xs) = gos acc xs
  go acc (Bind fc x b scope) = go (acc <+> inBinder b) scope
  go acc (App fc fn arg) = go (go acc fn) arg
  go acc (As fc x as pat) = go (go acc as) pat
  go acc (TDelayed fc x y) = go acc y
  go acc (TDelay fc x ty arg) = go (go acc ty) arg
  go acc (TForce fc x y) = go acc y
  go acc (PrimVal fc c) = acc
  go acc (Erased fc imp) = acc
  go acc (TType fc u) = acc

  gos acc [] = acc
  gos acc (x :: xs) = gos (go acc x) xs

  -- A binder's default value, then its type, each folded on its own.
  inBinder (Lam _ _ (DefImplicit t) ty) = go neutral t <+> go neutral ty
  inBinder (Lam _ _ _ ty) = go neutral ty
  inBinder (Let _ _ val ty) = go neutral val <+> go neutral ty
  inBinder (Pi _ _ (DefImplicit t) ty) = go neutral t <+> go neutral ty
  inBinder (Pi _ _ _ ty) = go neutral ty
  inBinder (PVar _ _ (DefImplicit t) ty) = go neutral t <+> go neutral ty
  inBinder (PVar _ _ _ ty) = go neutral ty
  inBinder (PLet _ _ val ty) = go neutral val <+> go neutral ty
  inBinder (PVTy _ _ ty) = go neutral ty

export
onConstants : Monoid m =>
          (Constant  -> m) ->
          (Term vars -> m)
onConstants f = go neutral where

  go  : m -> Term vars' -> m
  gos : m -> List (Term vars') -> m
  inBinder : Binder (Term vars') -> m

  go acc (Local fc isLet idx p) = acc
  go acc (Ref fc x name) = acc
  go acc (Meta fc x y xs) = gos acc xs
  go acc (Bind fc x b scope) = go (acc <+> inBinder b) scope
  go acc (App fc fn arg) = go (go acc fn) arg
  go acc (As fc x as pat) = go (go acc as) pat
  go acc (TDelayed fc x y) = go acc y
  go acc (TDelay fc x ty arg) = go (go acc ty) arg
  go acc (TForce fc x y) = go acc y
  go acc (PrimVal fc c) = acc <+> f c
  go acc (Erased fc imp) = acc
  go acc (TType fc u) = acc

  gos acc [] = acc
  gos acc (x :: xs) = gos (go acc x) xs

  -- A binder's default value, then its type, each folded on its own.
  inBinder (Lam _ _ (DefImplicit t) ty) = go neutral t <+> go neutral ty
  inBinder (Lam _ _ _ ty) = go neutral ty
  inBinder (Let _ _ val ty) = go neutral val <+> go neutral ty
  inBinder (Pi _ _ (DefImplicit t) ty) = go neutral t <+> go neutral ty
  inBinder (Pi _ _ _ ty) = go neutral ty
  inBinder (PVar _ _ (DefImplicit t) ty) = go neutral t <+> go neutral ty
  inBinder (PVar _ _ _ ty) = go neutral ty
  inBinder (PLet _ _ val ty) = go neutral val <+> go neutral ty
  inBinder (PVTy _ _ ty) = go neutral ty

export
mapTermM : Monad m =>
           ({vars : _} -> Term vars -> m (Term vars)) ->
           ({vars : _} -> Term vars -> m (Term vars))
mapTermM f t = act t where

  act : {vars : _} -> Term vars -> m (Term vars)
  go  : {vars : _} -> Term vars -> m (Term vars)
  acts : {vars : _} -> List (Term vars) -> m (List (Term vars))
  actInfo : {vars : _} -> PiInfo (Term vars) -> m (PiInfo (Term vars))
  actBinder : {vars : _} -> Binder (Term vars) -> m (Binder (Term vars))

  act t = f =<< go t

  go t@(Local fc isLet idx p) = pure t
  go t@(Ref fc x name) = pure t
  go t@(Meta fc x y xs) = Meta fc x y <$> acts xs
  go t@(Bind fc x b scope) = Bind fc x <$> actBinder b <*> act scope
  go t@(App fc fn arg) = App fc <$> act fn <*> act arg
  go t@(As fc x as pat) = As fc x <$> act as <*> act pat
  go t@(TDelayed fc x y) = TDelayed fc x <$> act y
  go t@(TDelay fc x ty arg) = TDelay fc x <$> act ty <*> act arg
  go t@(TForce fc x y) = pure t
  go t@(PrimVal fc c) = pure t
  go t@(Erased fc imp) = pure t
  go t@(TType fc u) = pure t

  acts [] = pure []
  acts (t :: ts) = (::) <$> act t <*> acts ts

  actInfo Implicit = pure Implicit
  actInfo Explicit = pure Explicit
  actInfo AutoImplicit = pure AutoImplicit
  actInfo (DefImplicit t) = DefImplicit <$> act t

  actBinder (Lam fc c x ty) = Lam fc c <$> actInfo x <*> act ty
  actBinder (Let fc c val ty) = Let fc c <$> act val <*> act ty
  actBinder (Pi fc c x ty) = Pi fc c <$> actInfo x <*> act ty
  actBinder (PVar fc c p ty) = PVar fc c <$> actInfo p <*> act ty
  actBinder (PLet fc c val ty) = PLet fc c <$> act val <*> act ty
  actBinder (PVTy fc c ty) = PVTy fc c <$> act ty

export
mapTerm : ({vars : _} -> Term vars -> Term vars) ->
          ({vars : _} -> Term vars -> Term vars)
mapTerm f t = act t where

  act : {vars : _} -> Term vars -> Term vars
  go  : {vars : _} -> Term vars -> Term vars
  acts : {vars : _} -> List (Term vars) -> List (Term vars)
  actInfo : {vars : _} -> PiInfo (Term vars) -> PiInfo (Term vars)
  actBinder : {vars : _} -> Binder (Term vars) -> Binder (Term vars)

  act t = f (go t)

  go t@(Local fc isLet idx p) = t
  go t@(Ref fc x name) = t
  go t@(Meta fc x y xs) = Meta fc x y (acts xs)
  go t@(Bind fc x b scope) = Bind fc x (actBinder b) (act scope)
  go t@(App fc fn arg) = App fc (act fn) (act arg)
  go t@(As fc x as pat) = As fc x (act as) (act pat)
  go t@(TDelayed fc x y) = TDelayed fc x (act y)
  go t@(TDelay fc x ty arg) = TDelay fc x (act ty) (act arg)
  go t@(TForce fc x y) = t
  go t@(PrimVal fc c) = t
  go t@(Erased fc imp) = t
  go t@(TType fc u) = t

  acts [] = []
  acts (t :: ts) = act t :: acts ts

  actInfo (DefImplicit t) = DefImplicit (act t)
  actInfo info = info

  actBinder (Lam fc c x ty) = Lam fc c (actInfo x) (act ty)
  actBinder (Let fc c val ty) = Let fc c (act val) (act ty)
  actBinder (Pi fc c x ty) = Pi fc c (actInfo x) (act ty)
  actBinder (PVar fc c p ty) = PVar fc c (actInfo p) (act ty)
  actBinder (PLet fc c val ty) = PLet fc c (act val) (act ty)
  actBinder (PVTy fc c ty) = PVTy fc c (act ty)
