||| Terms as closed values: types and implementations are compile-time
||| values, closed TT terms, which the translation substitutes, normalises
||| and reduces to their constructors.
module IdrisMLIR.Frontend.Translate.Closed

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.Env
import Core.Normalise
import Core.TT

import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Rule
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.List

%default covering

||| Idris's terms and binders; `Term` and `Binder` are Core's own.
public export
TT : Scope -> Type
TT = Core.TT.Term.Term

public export
TTBinder : Type -> Type
TTBinder = Core.TT.Binder.Binder

||| What a TT variable stands for: a Core variable (with its type, when a
||| match may need it), a type argument's value, or an implementation's value.
||| Types and implementations are compile-time values, closed TT terms: types
||| are erased at runtime, and an implementation is used by translating it
||| where it is needed.
public export
data VarInfo : Type -> Type where
  Runtime : a -> Maybe Ty -> VarInfo a
  TypeValue : ClosedTerm -> VarInfo a
  Static : ClosedTerm -> VarInfo a

export
Functor VarInfo where
  map f (Runtime x t) = Runtime (f x) t
  map f (TypeValue t) = TypeValue t
  map f (Static t) = Static t

||| An environment under a binder of `k` variables, which come first.
export
under : List (VarInfo (Under k a)) -> List (VarInfo a) -> List (VarInfo (Under k a))
under bound env = bound ++ map (map Free) env

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
export
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
export
closeNormalise : {auto c : Ref Ctxt Defs} -> {vars : Scope} ->
                 FC -> List (VarInfo a) -> TT vars -> Core ClosedTerm
closeNormalise fc env tm = do
  let closed = foldl (App fc) (wrapLams fc tm) (reverse (map value env))
  defs <- get Ctxt
  normalise defs [] closed
  where
    value : VarInfo a -> ClosedTerm
    value (TypeValue t) = t
    value (Static t) = t
    value (Runtime _ _) = Erased fc Placeholder

||| A closed term in any scope.
export
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

||| `let`s around a `Delay`, moved into it: the location of the `Delay` and
||| the `let`s around its argument. Idris elaborates `a; let x = v; b` in a
||| `do` block to `a >> (let x = v in Delay b)`. A `let` of TT has no
||| evaluation time of its own: Idris's evaluator and its inliner substitute
||| it, and the stock backend, which inlines `>>`, computes `v` where `b` is
||| forced, after `a` has run. Computed where the `Delay` is built, `v` would
||| run before `a`'s effects, and a `v` that crashes or never returns would
||| hide them. Every use of `x` is inside the `Delay`, so the `let` can move
||| there.
export
delayedLets : TT vars -> Maybe (FC, TT vars)
delayedLets (TDelay fc _ _ arg) = Just (fc, arg)
delayedLets (Bind fc x b@(Let {}) sc) = map (Bind fc x b) <$> delayedLets sc
delayedLets _ = Nothing

||| A term in scope as a closed term, with compile-time values substituted
||| and not normalised, so that an implementation keeps its written form. A
||| runtime variable becomes `Erased` with reason `Impossible`, which
||| `runtimeDependent` detects.
export
closeWritten : {vars : Scope} -> FC -> List (VarInfo a) -> TT vars -> ClosedTerm
closeWritten fc env tm = zeta (betaAll (wrapLams fc tm) (reverse (map value env)))
  where
    value : VarInfo a -> ClosedTerm
    value (TypeValue t) = t
    value (Static t) = t
    -- A quantity-0 variable (a length, a proof) is not a runtime value: an
    -- implementation that mentions it (`Foldable (Vect n)`) does not
    -- depend on anything at runtime.
    value (Runtime _ (Just ErasedT)) = Erased fc Placeholder
    value (Runtime _ _) = Erased fc Impossible

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
||| nothing else evaluated.
export
solved : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core ClosedTerm
solved tm =
  if hasMeta tm
     then do
       defs <- get Ctxt
       normaliseHoles defs [] tm
     else pure tm

export
runtimeDependent : ClosedTerm -> Bool
runtimeDependent = anyErasedAs (\w => case w of
                                        Impossible => True
                                        _ => False)

export
normaliseClosed : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core ClosedTerm
normaliseClosed tm = do
  defs <- get Ctxt
  normalise defs [] tm

||| The constructor a compile-time value reduces to, with its arguments. An
||| implementation is a definition with one right-hand side, so it is
||| unfolded by substituting its arguments, keeping the rest as written;
||| anything else goes to Idris's normaliser.
export
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
export
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

export
showTT : ClosedTerm -> String
showTT = show

export
spine : TT vars -> List (TT vars) -> (TT vars, List (TT vars))
spine (App _ fn arg) args = spine fn (arg :: args)
spine fn args = (fn, args)

||| A type-level parameter: its type is a universe, possibly after Pi binders.
export
isTypeLike : TT vars -> Bool
isTypeLike (TType _ _) = True
isTypeLike (Bind _ _ (Pi _ _ _ _) sc) = typeLikeScope sc
  where
    typeLikeScope : TT vs -> Bool
    typeLikeScope (TType _ _) = True
    typeLikeScope (Bind _ _ (Pi _ _ _ _) s) = typeLikeScope s
    typeLikeScope _ = False
isTypeLike _ = False

export
lookupDef : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            FC -> String -> Name -> Core GlobalDef
lookupDef fc owner n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => reject fc owner CompiledModule ("missing definition " ++ show n)
  pure def
