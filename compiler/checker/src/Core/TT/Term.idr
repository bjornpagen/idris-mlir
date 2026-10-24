-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.TT.Term

import Algebra

import Core.FC

import Core.Name.Scoped
import Core.TT.Binder
import Core.TT.Primitive
import Core.TT.Var

import Data.DPair
import Data.List
import Data.Nat

import Libraries.Data.List.SizeOf

%default total

------------------------------------------------------------------------
-- Name types
-- This information is cached in Refs (global variables) so as to avoid
-- too many lookups

public export
data NameType : Type where
     Bound   : NameType
     Func    : NameType
     DataCon : (tag : Int) -> (arity : Nat) -> NameType
     TyCon   : (arity : Nat) -> NameType

%name NameType nt

export
covering
Show NameType where
  showPrec d Bound = "Bound"
  showPrec d Func = "Func"
  showPrec d (DataCon tag ar) = showCon d "DataCon" $ showArg tag ++ showArg ar
  showPrec d (TyCon ar) = showCon d "TyCon" $ showArg ar

export
isCon : NameType -> Maybe Nat
isCon (DataCon t a) = Just a
isCon (TyCon a) = Just a
isCon _ = Nothing

-- Typechecked terms
-- These are guaranteed to be well-scoped wrt local variables, because they are
-- indexed by the names of local variables in scope
public export
data LazyReason = LInf | LLazy | LUnknown

%name LazyReason lz

||| Where a `Delay` came from. One in the source is the source's `Delay e`,
||| and delays only its argument. One by the elaborator is inserted
||| around a term it checked against a `Lazy` or `Inf` type: it stands
||| for the whole expression the expected type delays, so the `let`s the
||| elaborator placed around it (a `do` block's `let`, checked against the
||| delayed type, holds the `Delay` inside it) are part of what the
||| language leaves unevaluated. Nothing but this fact tells the two apart
||| in the checked term, and a reader with eager evaluation needs it.
public export
data DelayOrigin = InSource | ByElaborator

||| What a `Delay` node knows of itself: the laziness it makes, which
||| conversion and unification compare, and where it came from, which they
||| never compare.
public export
record Delaying where
  constructor MkDelaying
  reason : LazyReason
  origin : DelayOrigin

-- For as patterns matching linear arguments, select which side is
-- consumed
public export
data UseSide = UseLeft | UseRight

%name UseSide side

public export
data WhyErased a
  = Placeholder
  | Impossible
  | Dotted a

export
Show a => Show (WhyErased a) where
  show Placeholder = "placeholder"
  show Impossible = "impossible"
  show (Dotted x) = "dotted \{show x}"

%name WhyErased why

export
Functor WhyErased where
  map f Placeholder = Placeholder
  map f Impossible = Impossible
  map f (Dotted x) = Dotted (f x)

export
Foldable WhyErased where
  foldr c n (Dotted x) = c x n
  foldr c n _ = n

export
Traversable WhyErased where
  traverse f Placeholder = pure Placeholder
  traverse f Impossible = pure Impossible
  traverse f (Dotted x) = Dotted <$> f x


------------------------------------------------------------------------
-- Core Terms

public export
data Term : Scoped where
     Local : FC -> (isLet : Maybe Bool) ->
             (idx : Nat) -> (0 p : IsVar name idx vars) -> Term vars
     Ref : FC -> NameType -> (name : Name) -> Term vars
     -- Metavariables and the scope they are applied to
     Meta : FC -> Name -> Int -> List (Term vars) -> Term vars
     Bind : FC -> (x : Name) ->
            (b : Binder (Term vars)) ->
            (scope : Term (Scope.bind vars x)) -> Term vars
     App : FC -> (fn : Term vars) -> (arg : Term vars) -> Term vars
     -- as patterns; since we check LHS patterns as terms before turning
     -- them into patterns, this helps us get it right. When normalising,
     -- we just reduce the inner term and ignore the 'as' part
     -- The 'as' part should really be a Name rather than a Term, but it's
     -- easier this way since it gives us the ability to work with unresolved
     -- names (Ref) and resolved names (Local) without having to define a
     -- special purpose thing. (But it'd be nice to tidy that up, nevertheless)
     As : FC -> UseSide -> (as : Term vars) -> (pat : Term vars) -> Term vars
     -- Typed laziness annotations
     TDelayed : FC -> LazyReason -> Term vars -> Term vars
     TDelay : FC -> Delaying -> (ty : Term vars) -> (arg : Term vars) -> Term vars
     TForce : FC -> LazyReason -> Term vars -> Term vars
     PrimVal : FC -> (c : Constant) -> Term vars
     Erased : FC -> WhyErased (Term vars) -> Term vars
     TType : FC -> Name -> -- universe variable
             Term vars

%name Term t, u

public export
ClosedTerm : Type
ClosedTerm = Term []

------------------------------------------------------------------------
-- Locals

||| The local at a named variable's index, as weakening and putting
||| variables in for names rebuild one.
public export
localAt : FC -> Maybe Bool -> NVar nm vars -> Term vars
localAt fc r (MkNVar p) = Local fc r _ p

||| The local at a variable's index, as substitution rebuilds one.
public export
localOf : FC -> Maybe Bool -> Var vars -> Term vars
localOf fc r (MkVar p) = Local fc r _ p

------------------------------------------------------------------------
-- Weakening

-- Each kind of node a term holds terms in is traversed by a function of
-- its own, so that every recursive call is on a part of its argument; each
-- public, so that a proof over a weakened term reads off what weakening
-- makes of every node.
mutual
  public export
  insertNamesPi : {0 outer, ns, local : Scope} ->
                  SizeOf local -> SizeOf ns ->
                  PiInfo (Term (local ++ outer)) -> PiInfo (Term (local ++ (ns ++ outer)))
  insertNamesPi out ns Implicit = Implicit
  insertNamesPi out ns Explicit = Explicit
  insertNamesPi out ns AutoImplicit = AutoImplicit
  insertNamesPi out ns (DefImplicit t) = DefImplicit (insertNames out ns t)

  public export
  insertNamesBinder : {0 outer, ns, local : Scope} ->
                      SizeOf local -> SizeOf ns ->
                      Binder (Term (local ++ outer)) -> Binder (Term (local ++ (ns ++ outer)))
  insertNamesBinder out ns (Lam fc c p ty)
      = Lam fc c (insertNamesPi out ns p) (insertNames out ns ty)
  insertNamesBinder out ns (Let fc c val ty)
      = Let fc c (insertNames out ns val) (insertNames out ns ty)
  insertNamesBinder out ns (Pi fc c p ty)
      = Pi fc c (insertNamesPi out ns p) (insertNames out ns ty)
  insertNamesBinder out ns (PVar fc c p ty)
      = PVar fc c (insertNamesPi out ns p) (insertNames out ns ty)
  insertNamesBinder out ns (PLet fc c val ty)
      = PLet fc c (insertNames out ns val) (insertNames out ns ty)
  insertNamesBinder out ns (PVTy fc c ty) = PVTy fc c (insertNames out ns ty)

  public export
  insertNamesTerms : {0 outer, ns, local : Scope} ->
                     SizeOf local -> SizeOf ns ->
                     List (Term (local ++ outer)) -> List (Term (local ++ (ns ++ outer)))
  insertNamesTerms out ns [] = []
  insertNamesTerms out ns (t :: ts) = insertNames out ns t :: insertNamesTerms out ns ts

  public export
  insertNames : GenWeakenable Term
  insertNames out ns (Local fc r idx prf)
     = localAt fc r (insertNVarNames out ns (MkNVar prf))
  insertNames out ns (Ref fc nt name) = Ref fc nt name
  insertNames out ns (Meta fc name idx args)
      = Meta fc name idx (insertNamesTerms out ns args)
  insertNames out ns (Bind fc x b scope)
      = Bind fc x (insertNamesBinder out ns b)
             (insertNames (suc out) ns scope)
  insertNames out ns (App fc fn arg)
      = App fc (insertNames out ns fn) (insertNames out ns arg)
  insertNames out ns (As fc s as tm)
      = As fc s (insertNames out ns as) (insertNames out ns tm)
  insertNames out ns (TDelayed fc r ty) = TDelayed fc r (insertNames out ns ty)
  insertNames out ns (TDelay fc r ty tm)
      = TDelay fc r (insertNames out ns ty) (insertNames out ns tm)
  insertNames out ns (TForce fc r tm) = TForce fc r (insertNames out ns tm)
  insertNames out ns (PrimVal fc c) = PrimVal fc c
  insertNames out ns (Erased fc Impossible) = Erased fc Impossible
  insertNames out ns (Erased fc Placeholder) = Erased fc Placeholder
  insertNames out ns (Erased fc (Dotted t)) = Erased fc (Dotted (insertNames out ns t))
  insertNames out ns (TType fc u) = TType fc u

-- Embedding a term in a larger scope adds the new variables at the far
-- end, where no de Bruijn index reaches, so every node is rebuilt from the
-- same fields: once the scope proofs are erased, an identity. Public, so
-- that a proof over an embedded term reads off that it is rebuilt.
mutual
  public export
  embedPi : PiInfo (Term vars) -> PiInfo (Term (vars ++ outer))
  embedPi Implicit = Implicit
  embedPi Explicit = Explicit
  embedPi AutoImplicit = AutoImplicit
  embedPi (DefImplicit t) = DefImplicit (embedTerm t)

  public export
  embedBinder : Binder (Term vars) -> Binder (Term (vars ++ outer))
  embedBinder (Lam fc c p ty) = Lam fc c (embedPi p) (embedTerm ty)
  embedBinder (Let fc c val ty) = Let fc c (embedTerm val) (embedTerm ty)
  embedBinder (Pi fc c p ty) = Pi fc c (embedPi p) (embedTerm ty)
  embedBinder (PVar fc c p ty) = PVar fc c (embedPi p) (embedTerm ty)
  embedBinder (PLet fc c val ty) = PLet fc c (embedTerm val) (embedTerm ty)
  embedBinder (PVTy fc c ty) = PVTy fc c (embedTerm ty)

  public export
  embedTerms : List (Term vars) -> List (Term (vars ++ outer))
  embedTerms [] = []
  embedTerms (t :: ts) = embedTerm t :: embedTerms ts

  public export
  embedTerm : Term vars -> Term (vars ++ outer)
  embedTerm (Local fc r idx p) = Local fc r idx (embedIsVar p)
  embedTerm (Ref fc nt name) = Ref fc nt name
  embedTerm (Meta fc name i args) = Meta fc name i (embedTerms args)
  embedTerm (Bind fc x b scope) = Bind fc x (embedBinder b) (embedTerm scope)
  embedTerm (App fc fn arg) = App fc (embedTerm fn) (embedTerm arg)
  embedTerm (As fc s as pat) = As fc s (embedTerm as) (embedTerm pat)
  embedTerm (TDelayed fc r ty) = TDelayed fc r (embedTerm ty)
  embedTerm (TDelay fc r ty arg) = TDelay fc r (embedTerm ty) (embedTerm arg)
  embedTerm (TForce fc r tm) = TForce fc r (embedTerm tm)
  embedTerm (PrimVal fc c) = PrimVal fc c
  embedTerm (Erased fc Placeholder) = Erased fc Placeholder
  embedTerm (Erased fc Impossible) = Erased fc Impossible
  embedTerm (Erased fc (Dotted t)) = Erased fc (Dotted (embedTerm t))
  embedTerm (TType fc u) = TType fc u

-- Renaming the variables of a scope keeps every de Bruijn index, so, as
-- embedding does, it rebuilds every node from the same fields; the
-- compatibility proof only retypes the variables, and is erased.
mutual
  compatPi : (0 _ : CompatibleVars xs ys) -> PiInfo (Term xs) -> PiInfo (Term ys)
  compatPi prf Implicit = Implicit
  compatPi prf Explicit = Explicit
  compatPi prf AutoImplicit = AutoImplicit
  compatPi prf (DefImplicit t) = DefImplicit (compatTerm prf t)

  compatBinder : (0 _ : CompatibleVars xs ys) -> Binder (Term xs) -> Binder (Term ys)
  compatBinder prf (Lam fc c p ty) = Lam fc c (compatPi prf p) (compatTerm prf ty)
  compatBinder prf (Let fc c val ty) = Let fc c (compatTerm prf val) (compatTerm prf ty)
  compatBinder prf (Pi fc c p ty) = Pi fc c (compatPi prf p) (compatTerm prf ty)
  compatBinder prf (PVar fc c p ty) = PVar fc c (compatPi prf p) (compatTerm prf ty)
  compatBinder prf (PLet fc c val ty) = PLet fc c (compatTerm prf val) (compatTerm prf ty)
  compatBinder prf (PVTy fc c ty) = PVTy fc c (compatTerm prf ty)

  compatTerms : (0 _ : CompatibleVars xs ys) -> List (Term xs) -> List (Term ys)
  compatTerms prf [] = []
  compatTerms prf (t :: ts) = compatTerm prf t :: compatTerms prf ts

  export
  compatTerm : (0 _ : CompatibleVars xs ys) -> Term xs -> Term ys
  compatTerm prf (Local fc r idx p) = Local fc r idx (renamedIsVar prf p).snd
  compatTerm prf (Ref fc nt name) = Ref fc nt name
  compatTerm prf (Meta fc name i args) = Meta fc name i (compatTerms prf args)
  compatTerm prf (Bind fc x b scope)
      = Bind fc x (compatBinder prf b) (compatTerm (Ext prf) scope)
  compatTerm prf (App fc fn arg) = App fc (compatTerm prf fn) (compatTerm prf arg)
  compatTerm prf (As fc s as pat) = As fc s (compatTerm prf as) (compatTerm prf pat)
  compatTerm prf (TDelayed fc r ty) = TDelayed fc r (compatTerm prf ty)
  compatTerm prf (TDelay fc r ty arg)
      = TDelay fc r (compatTerm prf ty) (compatTerm prf arg)
  compatTerm prf (TForce fc r tm) = TForce fc r (compatTerm prf tm)
  compatTerm prf (PrimVal fc c) = PrimVal fc c
  compatTerm prf (Erased fc Placeholder) = Erased fc Placeholder
  compatTerm prf (Erased fc Impossible) = Erased fc Impossible
  compatTerm prf (Erased fc (Dotted t)) = Erased fc (Dotted (compatTerm prf t))
  compatTerm prf (TType fc u) = TType fc u

mutual
  export
  shrinkPi : Shrinkable (PiInfo . Term)
  shrinkPi Implicit th = Just Implicit
  shrinkPi Explicit th = Just Explicit
  shrinkPi AutoImplicit th = Just AutoImplicit
  shrinkPi (DefImplicit t) th = DefImplicit <$> shrinkTerm t th

  export
  shrinkBinder : Shrinkable (Binder . Term)
  shrinkBinder (Lam fc c p ty) th
      = Just (Lam fc c !(shrinkPi p th) !(shrinkTerm ty th))
  shrinkBinder (Let fc c val ty) th
      = Just (Let fc c !(shrinkTerm val th) !(shrinkTerm ty th))
  shrinkBinder (Pi fc c p ty) th
      = Just (Pi fc c !(shrinkPi p th) !(shrinkTerm ty th))
  shrinkBinder (PVar fc c p ty) th
      = Just (PVar fc c !(shrinkPi p th) !(shrinkTerm ty th))
  shrinkBinder (PLet fc c val ty) th
      = Just (PLet fc c !(shrinkTerm val th) !(shrinkTerm ty th))
  shrinkBinder (PVTy fc c ty) th = PVTy fc c <$> shrinkTerm ty th

  export
  shrinkTerms : Shrinkable (List . Term)
  shrinkTerms [] th = Just []
  shrinkTerms (t :: ts) th = Just (!(shrinkTerm t th) :: !(shrinkTerms ts th))

  shrinkTerm : Shrinkable Term
  shrinkTerm (Local fc r idx loc) prf
    = do MkVar loc' <- shrinkIsVar loc prf
         pure (Local fc r _ loc')
  shrinkTerm (Ref fc x name) prf = Just (Ref fc x name)
  shrinkTerm (Meta fc x y xs) prf
     = do Just (Meta fc x y !(shrinkTerms xs prf))
  shrinkTerm (Bind fc x b scope) prf
     = Just (Bind fc x !(shrinkBinder b prf) !(shrinkTerm scope (Keep prf)))
  shrinkTerm (App fc fn arg) prf
     = Just (App fc !(shrinkTerm fn prf) !(shrinkTerm arg prf))
  shrinkTerm (As fc s as tm) prf
     = Just (As fc s !(shrinkTerm as prf) !(shrinkTerm tm prf))
  shrinkTerm (TDelayed fc x y) prf
     = Just (TDelayed fc x !(shrinkTerm y prf))
  shrinkTerm (TDelay fc x t y) prf
     = Just (TDelay fc x !(shrinkTerm t prf) !(shrinkTerm y prf))
  shrinkTerm (TForce fc r x) prf
     = Just (TForce fc r !(shrinkTerm x prf))
  shrinkTerm (PrimVal fc c) prf = Just (PrimVal fc c)
  shrinkTerm (Erased fc Placeholder) prf = Just (Erased fc Placeholder)
  shrinkTerm (Erased fc Impossible) prf = Just (Erased fc Impossible)
  shrinkTerm (Erased fc (Dotted t)) prf = Erased fc . Dotted <$> shrinkTerm t prf
  shrinkTerm (TType fc u) prf = Just (TType fc u)


mutual
  export
  thinPi : Thinnable (PiInfo . Term)
  thinPi Implicit th = Implicit
  thinPi Explicit th = Explicit
  thinPi AutoImplicit th = AutoImplicit
  thinPi (DefImplicit t) th = DefImplicit (thinTerm t th)

  export
  thinBinder : Thinnable (Binder . Term)
  thinBinder (Lam fc c p ty) th = Lam fc c (thinPi p th) (thinTerm ty th)
  thinBinder (Let fc c val ty) th = Let fc c (thinTerm val th) (thinTerm ty th)
  thinBinder (Pi fc c p ty) th = Pi fc c (thinPi p th) (thinTerm ty th)
  thinBinder (PVar fc c p ty) th = PVar fc c (thinPi p th) (thinTerm ty th)
  thinBinder (PLet fc c val ty) th = PLet fc c (thinTerm val th) (thinTerm ty th)
  thinBinder (PVTy fc c ty) th = PVTy fc c (thinTerm ty th)

  export
  thinTerms : Thinnable (List . Term)
  thinTerms [] th = []
  thinTerms (t :: ts) th = thinTerm t th :: thinTerms ts th

  thinTerm : Thinnable Term
  thinTerm (Local fc x idx y) th
      = let MkVar y' = thinIsVar y th in Local fc x _ y'
  thinTerm (Ref fc x name) th = Ref fc x name
  thinTerm (Meta fc x y xs) th
      = Meta fc x y (thinTerms xs th)
  thinTerm (Bind fc x b scope) th
      = Bind fc x (thinBinder b th) (thinTerm scope (Keep th))
  thinTerm (App fc fn arg) th
      = App fc (thinTerm fn th) (thinTerm arg th)
  thinTerm (As fc s nm pat) th
      = As fc s (thinTerm nm th) (thinTerm pat th)
  thinTerm (TDelayed fc x y) th = TDelayed fc x (thinTerm y th)
  thinTerm (TDelay fc x t y) th
      = TDelay fc x (thinTerm t th) (thinTerm y th)
  thinTerm (TForce fc r x) th = TForce fc r (thinTerm x th)
  thinTerm (PrimVal fc c) th = PrimVal fc c
  thinTerm (Erased fc Impossible) th = Erased fc Impossible
  thinTerm (Erased fc Placeholder) th = Erased fc Placeholder
  thinTerm (Erased fc (Dotted t)) th = Erased fc (Dotted (thinTerm t th))
  thinTerm (TType fc u) th = TType fc u

-- Public, as the traversal is, so that a proof reads off a weakening of a
-- term what `insertNames` makes of it.
public export
GenWeaken Term where
  genWeakenNs = insertNames

public export
%hint
WeakenTerm : Weaken Term
WeakenTerm = GenWeakenWeakens

public export
FreelyEmbeddable Term where
  embed = embedTerm

export
IsScoped Term where
  shrink = shrinkTerm
  thin = thinTerm
  compatNs prf = compatTerm prf

------------------------------------------------------------------------
-- A local by its index

-- A local is its location, its `let` hint and its index: the name and the
-- proof are erased, and two proofs that a name is at an index are one. So
-- a proof over terms reads off an operation which local it makes, by
-- index, and two locals it reads so are one term.

||| A term that is the local at index `i`, whatever its proof.
public export
data LocalAt : FC -> Maybe Bool -> Nat -> Term vars -> Type where
  IsLocalAt : {0 p : IsVar nm i vars} -> LocalAt fc r i (Local fc r i p)

0 localSameName : (0 p : IsVar n i vars) -> (0 q : IsVar m i vars) -> n = m ->
                  Local fc r i p = Local fc r i q
localSameName p q Refl = cong (\x => Local fc r i x) (isVarUnique p q)

||| Two terms that are the local at one index, at one location with one
||| hint, are one term.
export
0 localAtSame : LocalAt fc r i t -> LocalAt fc r i u -> t = u
localAtSame (IsLocalAt {p}) (IsLocalAt {p = q}) = localSameName p q (isVarName p q)

||| The local at a named variable's index is the local at that index.
export
0 localAtIdx : (w : NVar nm vars) -> LocalAt fc r (nvarIdx w) (localAt fc r w)
localAtIdx (MkNVar p) = IsLocalAt

||| The local at a variable's index is the local at that index.
export
0 localOfIdx : (w : Var vars) -> LocalAt fc r (varIdx w) (localOf fc r w)
localOfIdx (MkVar p) = IsLocalAt

||| Weakening a reference leaves it as it is.
export
0 weakenRef : {0 vars : Scope} -> {0 s : SizeOf ns} ->
              weakenNs s (Ref {vars} fc nt n) = Ref {vars = ns ++ vars} fc nt n
weakenRef = Refl

||| Weakening a local past `ns` adds their count to its index.
export
0 weakenLocalAt : (s : SizeOf ns) -> (0 p : IsVar nm idx vars) ->
                  LocalAt fc r (size s + idx) (weakenNs s (Local fc r idx p))
weakenLocalAt s p = case insertNVarNamesIdx {outer = vars} zero s (MkNVar p) of
  Left (lt, _) => absurd lt
  Right (_, same) =>
    replace {p = \k => LocalAt fc r k (weakenNs s (Local fc r idx p))} same
            (localAtIdx (insertNVarNames {outer = vars} zero s (MkNVar p)))

------------------------------------------------------------------------
-- Smart constructors

-- Public, so that a proof reads off the applications it builds.
public export
apply : FC -> Term vars -> List (Term vars) -> Term vars
apply loc fn [] = fn
apply loc fn (a :: args) = apply loc (App loc fn a) args

-- Creates a chain of `App` nodes, each with its own file context
export
applySpineWithFC : Term vars -> SnocList (FC, Term vars) -> Term vars
applySpineWithFC fn [<] = fn
applySpineWithFC fn (args :< (fc, arg)) = App fc (applySpineWithFC fn args) arg

-- Creates a chain of `App` nodes, each with its own file context
export
applyStackWithFC : Term vars -> List (FC, Term vars) -> Term vars
applyStackWithFC fn [] = fn
applyStackWithFC fn ((fc, arg) :: args) = applyStackWithFC (App fc fn arg) args

-- Build a simple function type
export
fnType : FC -> Term vars -> Term vars -> Term vars
fnType fc arg scope = Bind emptyFC (MN (known K_) 0) (Pi fc top Explicit arg) (weaken scope)

export
linFnType : FC -> Term vars -> Term vars -> Term vars
linFnType fc arg scope = Bind emptyFC (MN (known K_) 0) (Pi fc linear Explicit arg) (weaken scope)

export
getFnArgs : Term vars -> (Term vars, List (Term vars))
getFnArgs tm = getFA [] tm
  where
    getFA : List (Term vars) -> Term vars ->
            (Term vars, List (Term vars))
    getFA args (App _ f a) = getFA (a :: args) f
    getFA args tm = (tm, args)

export
getFn : Term vars -> Term vars
getFn (App _ f a) = getFn f
getFn tm = tm

export
getArgs : Term vars -> (List (Term vars))
getArgs = snd . getFnArgs


------------------------------------------------------------------------
-- Namespace manipulations

-- Remove/restore the given namespace from all Refs. This is to allow
-- writing terms and case trees to disk without repeating the same namespace
-- all over the place.
public export
interface StripNamespace a where
  trimNS : Namespace -> a -> a
  restoreNS : Namespace -> a -> a

export
StripNamespace Name where
  trimNS ns nm@(NS tns n)
    = if ns == tns then NS emptyNS n else nm
      -- ^ A blank namespace, rather than a UN, so we don't catch primitive
      -- names which are represented as UN.
  trimNS ns nm = nm

  restoreNS ns nm@(NS tns n)
      = if isNil (unsafeUnfoldNamespace tns)
            then NS ns n
            else nm
  restoreNS ns nm = nm

-- The term with `f` applied to the name of every reference but those in a
-- dotted pattern, each kind of node that holds terms traversed by a
-- function of its own, so that every recursive call is on a part of its
-- argument.
mutual
  onRefsPi : (Name -> Name) -> PiInfo (Term vars) -> PiInfo (Term vars)
  onRefsPi f (DefImplicit t) = DefImplicit (onRefs f t)
  onRefsPi f p = p

  onRefsBinder : (Name -> Name) -> Binder (Term vars) -> Binder (Term vars)
  onRefsBinder f (Lam fc c p ty) = Lam fc c (onRefsPi f p) (onRefs f ty)
  onRefsBinder f (Let fc c val ty) = Let fc c (onRefs f val) (onRefs f ty)
  onRefsBinder f (Pi fc c p ty) = Pi fc c (onRefsPi f p) (onRefs f ty)
  onRefsBinder f (PVar fc c p ty) = PVar fc c (onRefsPi f p) (onRefs f ty)
  onRefsBinder f (PLet fc c val ty) = PLet fc c (onRefs f val) (onRefs f ty)
  onRefsBinder f (PVTy fc c ty) = PVTy fc c (onRefs f ty)

  onRefsTerms : (Name -> Name) -> List (Term vars) -> List (Term vars)
  onRefsTerms f [] = []
  onRefsTerms f (t :: ts) = onRefs f t :: onRefsTerms f ts

  onRefs : (Name -> Name) -> Term vars -> Term vars
  onRefs f (Ref fc x nm) = Ref fc x (f nm)
  onRefs f (Meta fc x y xs) = Meta fc x y (onRefsTerms f xs)
  onRefs f (Bind fc x b scope) = Bind fc x (onRefsBinder f b) (onRefs f scope)
  onRefs f (App fc fn arg) = App fc (onRefs f fn) (onRefs f arg)
  onRefs f (As fc s p tm) = As fc s (onRefs f p) (onRefs f tm)
  onRefs f (TDelayed fc x y) = TDelayed fc x (onRefs f y)
  onRefs f (TDelay fc x t y) = TDelay fc x (onRefs f t) (onRefs f y)
  onRefs f (TForce fc r y) = TForce fc r (onRefs f y)
  onRefs f tm = tm

export
StripNamespace (Term vars) where
  trimNS ns = onRefs (trimNS ns)
  restoreNS ns = onRefs (restoreNS ns)

export
isErased : Term vars -> Bool
isErased (Erased {}) = True
isErased _ = False

export
getLoc : Term vars -> FC
getLoc (Local fc _ _ _) = fc
getLoc (Ref fc _ _) = fc
getLoc (Meta fc _ _ _) = fc
getLoc (Bind fc _ _ _) = fc
getLoc (App fc _ _) = fc
getLoc (As fc _ _ _) = fc
getLoc (TDelayed fc _ _) = fc
getLoc (TDelay fc _ _ _) = fc
getLoc (TForce fc _ _) = fc
getLoc (PrimVal fc _) = fc
getLoc (Erased fc i) = fc
getLoc (TType fc _) = fc

export
Eq LazyReason where
  (==) LInf LInf = True
  (==) LLazy LLazy = True
  (==) LUnknown LUnknown = True
  (==) _ _ = False

export
Show LazyReason where
    show LInf = "Inf"
    show LLazy = "Lazy"
    show LUnknown = "Unkown"

export
Eq DelayOrigin where
  InSource == InSource = True
  ByElaborator == ByElaborator = True
  _ == _ = False

export
Show DelayOrigin where
  show InSource = "in source"
  show ByElaborator = "by elaborator"

export
compatible : LazyReason -> LazyReason -> Bool
compatible LUnknown _ = True
compatible _ LUnknown = True
compatible x y = x == y

export
total
Eq a => Eq (WhyErased a) where
  Placeholder == Placeholder = True
  Impossible == Impossible = True
  Dotted t == Dotted u = t == u
  _ == _ = False

-- Two terms are equal when they have one shape and their parts are equal,
-- two constants when they are one constant (`identicalConstants`), as
-- conversion compares them: the unifier takes two equal terms as
-- convertible without converting them. Each kind of node that holds terms
-- is compared by a function of its own, so that every recursive call is on
-- a part of its arguments.
mutual
  eqPi : PiInfo (Term vs) -> PiInfo (Term vs') -> Bool
  eqPi Implicit Implicit = True
  eqPi Explicit Explicit = True
  eqPi AutoImplicit AutoImplicit = True
  eqPi (DefImplicit t) (DefImplicit t') = eqTerm t t'
  eqPi _ _ = False

  eqBinder : Binder (Term vs) -> Binder (Term vs') -> Bool
  eqBinder (Lam _ c p ty) (Lam _ c' p' ty') = c == c' && eqPi p p' && eqTerm ty ty'
  eqBinder (Let _ c v ty) (Let _ c' v' ty') = c == c' && eqTerm v v' && eqTerm ty ty'
  eqBinder (Pi _ c p ty) (Pi _ c' p' ty') = c == c' && eqPi p p' && eqTerm ty ty'
  eqBinder (PVar _ c p ty) (PVar _ c' p' ty') = c == c' && eqPi p p' && eqTerm ty ty'
  eqBinder (PLet _ c v ty) (PLet _ c' v' ty') = c == c' && eqTerm v v' && eqTerm ty ty'
  eqBinder (PVTy _ c ty) (PVTy _ c' ty') = c == c' && eqTerm ty ty'
  eqBinder _ _ = False

  -- Pairwise, as `zip` pairs: what one list holds past the other's end is
  -- not compared.
  eqTerms : List (Term vs) -> List (Term vs') -> Bool
  eqTerms (t :: ts) (u :: us) = eqTerm t u && eqTerms ts us
  eqTerms _ _ = True

  export
  eqTerm : Term vs -> Term vs' -> Bool
  eqTerm (Local _ _ idx _) (Local _ _ idx' _) = idx == idx'
  eqTerm (Ref _ _ n) (Ref _ _ n') = n == n'
  eqTerm (Meta _ _ i args) (Meta _ _ i' args') = i == i' && eqTerms args args'
  eqTerm (Bind _ _ b sc) (Bind _ _ b' sc') = eqBinder b b' && eqTerm sc sc'
  eqTerm (App _ f a) (App _ f' a') = eqTerm f f' && eqTerm a a'
  eqTerm (As _ _ a p) (As _ _ a' p') = eqTerm a a' && eqTerm p p'
  eqTerm (TDelayed _ _ t) (TDelayed _ _ t') = eqTerm t t'
  eqTerm (TDelay _ _ t x) (TDelay _ _ t' x') = eqTerm t t' && eqTerm x x'
  eqTerm (TForce _ _ t) (TForce _ _ t') = eqTerm t t'
  eqTerm (PrimVal _ c) (PrimVal _ c') = identicalConstants c c'
  eqTerm (Erased _ Impossible) (Erased _ Impossible) = True
  eqTerm (Erased _ Placeholder) (Erased _ Placeholder) = True
  eqTerm (Erased _ (Dotted t)) (Erased _ (Dotted t')) = eqTerm t t'
  eqTerm (TType {}) (TType {}) = True
  eqTerm _ _ = False

export
total
Eq (Term vars) where
  (==) = eqTerm

------------------------------------------------------------------------
-- Scope checking

-- A bound reference to a name of `vars` becomes the local of that name,
-- past the binders of the term it is under (`inner`). A term names its own
-- binders by locals, so a bound reference is always to the scope around
-- it: a binder of the term that has the same name does not take it. Each
-- kind of node that holds terms is traversed by a function of its own, so
-- that every recursive call is on a part of its argument.
mutual
  resolvePi : SizeOf inner -> (vars : Scope) ->
              PiInfo (Term (inner ++ vars)) -> PiInfo (Term (inner ++ vars))
  resolvePi s vars (DefImplicit t) = DefImplicit (resolveUnder s vars t)
  resolvePi s vars p = p

  resolveBinder : SizeOf inner -> (vars : Scope) ->
                  Binder (Term (inner ++ vars)) -> Binder (Term (inner ++ vars))
  resolveBinder s vars (Lam fc c p ty)
      = Lam fc c (resolvePi s vars p) (resolveUnder s vars ty)
  resolveBinder s vars (Let fc c val ty)
      = Let fc c (resolveUnder s vars val) (resolveUnder s vars ty)
  resolveBinder s vars (Pi fc c p ty)
      = Pi fc c (resolvePi s vars p) (resolveUnder s vars ty)
  resolveBinder s vars (PVar fc c p ty)
      = PVar fc c (resolvePi s vars p) (resolveUnder s vars ty)
  resolveBinder s vars (PLet fc c val ty)
      = PLet fc c (resolveUnder s vars val) (resolveUnder s vars ty)
  resolveBinder s vars (PVTy fc c ty) = PVTy fc c (resolveUnder s vars ty)

  resolveTerms : SizeOf inner -> (vars : Scope) ->
                 List (Term (inner ++ vars)) -> List (Term (inner ++ vars))
  resolveTerms s vars [] = []
  resolveTerms s vars (t :: ts) = resolveUnder s vars t :: resolveTerms s vars ts

  resolveUnder : SizeOf inner -> (vars : Scope) -> Term (inner ++ vars) -> Term (inner ++ vars)
  resolveUnder s vars (Ref fc Bound name)
      = case isVar name vars of
             Just (MkVar {varIdx} prf) => Local fc (Just False) (size s + varIdx) (weakenIsVar s prf)
             Nothing => Ref fc Bound name
  resolveUnder s vars (Meta fc n i xs)
      = Meta fc n i (resolveTerms s vars xs)
  resolveUnder s vars (Bind fc x b scope)
      = Bind fc x (resolveBinder s vars b) (resolveUnder (suc s) vars scope)
  resolveUnder s vars (App fc fn arg)
      = App fc (resolveUnder s vars fn) (resolveUnder s vars arg)
  resolveUnder s vars (As fc u as pat)
      = As fc u (resolveUnder s vars as) (resolveUnder s vars pat)
  resolveUnder s vars (TDelayed fc x y)
      = TDelayed fc x (resolveUnder s vars y)
  resolveUnder s vars (TDelay fc x t y)
      = TDelay fc x (resolveUnder s vars t) (resolveUnder s vars y)
  resolveUnder s vars (TForce fc r x)
      = TForce fc r (resolveUnder s vars x)
  resolveUnder s vars tm = tm

||| A term with each bound reference to a name of its scope replaced by
||| that name's local.
export
resolveNames : (vars : Scope) -> Term vars -> Term vars
resolveNames vars = resolveUnder zero vars

------------------------------------------------------------------------
-- Showing

export
withPiInfo : Show t => PiInfo t -> String -> String
withPiInfo Explicit tm = "(" ++ tm ++ ")"
withPiInfo Implicit tm = "{" ++ tm ++ "}"
withPiInfo AutoImplicit tm = "{auto " ++ tm ++ "}"
withPiInfo (DefImplicit t) tm = "{default " ++ show t ++ " " ++ tm ++ "}"

-- A term is shown as an application of its head to its arguments; each
-- kind of node that holds terms is shown by a function of its own, so that
-- every recursive call is on a part of its argument.
mutual
  showPiInfo : {vars : _} -> PiInfo (Term vars) -> String -> String
  showPiInfo Explicit tm = "(" ++ tm ++ ")"
  showPiInfo Implicit tm = "{" ++ tm ++ "}"
  showPiInfo AutoImplicit tm = "{auto " ++ tm ++ "}"
  showPiInfo (DefImplicit t) tm = "{default " ++ showTerm t ++ " " ++ tm ++ "}"

  showTerms : {vars : _} -> List (Term vars) -> List String
  showTerms [] = []
  showTerms (t :: ts) = showTerm t :: showTerms ts

  -- An application but its last argument: its head and the arguments
  -- before, separated by spaces.
  showSpine : {vars : _} -> Term vars -> String
  showSpine (App _ f a) = showSpine f ++ " " ++ showTerm a
  showSpine t = showTerm t

  export
  showTerm : {vars : _} -> Term vars -> String
  showTerm (App _ f a) = "(" ++ showSpine f ++ " " ++ showTerm a ++ ")"
  showTerm (Local _ c idx p) = show (nameAt p) ++ "[" ++ show idx ++ "]"
  showTerm (Ref _ _ n) = show n
  showTerm (Meta _ n _ args)
      = "?" ++ show n ++ "_" ++ "[" ++ concat (intersperse ", " (showTerms args)) ++ "]"
  showTerm (Bind _ x (Lam _ c info ty) sc)
      = "\\" ++ showPiInfo info (showCount c ++ show x ++ " : " ++ showTerm ty) ++
        " => " ++ showTerm sc
  showTerm (Bind _ x (Let _ c val ty) sc)
      = "let " ++ showCount c ++ show x ++ " : " ++ showTerm ty ++
        " = " ++ showTerm val ++ " in " ++ showTerm sc
  showTerm (Bind _ x (Pi _ c info ty) sc)
      = showPiInfo info (showCount c ++ show x ++ " : " ++ showTerm ty) ++
        " -> " ++ showTerm sc
  showTerm (Bind _ x (PVar _ c info ty) sc)
      = showPiInfo info ("pat " ++ showCount c ++ show x ++ " : " ++ showTerm ty) ++
        " => " ++ showTerm sc
  showTerm (Bind _ x (PLet _ c val ty) sc)
      = "plet " ++ showCount c ++ show x ++ " : " ++ showTerm ty ++
        " = " ++ showTerm val ++ " in " ++ showTerm sc
  showTerm (Bind _ x (PVTy _ c ty) sc)
      = "pty " ++ showCount c ++ show x ++ " : " ++ showTerm ty ++
        " => " ++ showTerm sc
  showTerm (As _ _ n tm) = showTerm n ++ "@" ++ showTerm tm
  showTerm (TDelayed _ _ tm) = "%Delayed " ++ showTerm tm
  showTerm (TDelay _ _ _ tm) = "%Delay " ++ showTerm tm
  showTerm (TForce _ _ tm) = "%Force " ++ showTerm tm
  showTerm (PrimVal _ c) = show c
  showTerm (Erased _ (Dotted t)) = ".(" ++ showTerm t ++ ")"
  showTerm (Erased {}) = "[__]"
  showTerm (TType _ u) = "Type"

export
{vars : _} -> Show (Term vars) where
  show = showTerm
