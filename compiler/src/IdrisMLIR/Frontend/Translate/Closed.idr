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
import Libraries.Data.List.SizeOf

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
||| match may need it, and with the shape of its value when that is known),
||| a type argument's value, or an implementation's value. Types and
||| implementations are compile-time values, closed TT terms: types are
||| erased at runtime, and an implementation is used by translating it where
||| it is needed.
public export
data VarInfo : Type -> Type where
  Runtime : a -> Maybe Ty -> VarInfo a
  ||| A runtime value whose shape is known: the constructors every call of
  ||| the instance built its argument with (`Instances.classify`), or a
  ||| constructor's field of such a value. The shape stands for the value
  ||| in types, and a match on the value takes only the alternatives a
  ||| value of that shape can.
  Shaped : a -> Ty -> ClosedTerm -> VarInfo a
  TypeValue : ClosedTerm -> VarInfo a
  Static : ClosedTerm -> VarInfo a

export
Functor VarInfo where
  map f (Runtime x t) = Runtime (f x) t
  map f (Shaped x t s) = Shaped (f x) t s
  map f (TypeValue t) = TypeValue t
  map f (Static t) = Static t

||| An environment under a binder of `k` variables, which come first.
export
under : List (VarInfo (Under k a)) -> List (VarInfo a) -> List (VarInfo (Under k a))
under bound env = bound ++ map (map Free) env

export
spine : TT vars -> List (TT vars) -> (TT vars, List (TT vars))
spine (App _ fn arg) args = spine fn (arg :: args)
spine fn args = (fn, args)

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
||| their known values and every other variable by `Erased`. Every
||| definition unfolds, whatever its visibility (`normaliseAll`): Idris's
||| plain `normalise` keeps a `private` function of another module as it is
||| (a type-level function such as Data.SortedMap's `delType`), which is a
||| module boundary, not a value.
export
closeNormalise : {auto c : Ref Ctxt Defs} -> {vars : Scope} ->
                 FC -> List (VarInfo a) -> TT vars -> Core ClosedTerm
closeNormalise fc env tm = do
  let closed = foldl (App fc) (wrapLams fc tm) (reverse (map value env))
  defs <- get Ctxt
  normaliseAll defs [] closed
  where
    value : VarInfo a -> ClosedTerm
    value (TypeValue t) = t
    value (Static t) = t
    value (Shaped _ _ s) = s
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
    -- A shape is what is known of the value at compile time; its holes
    -- are the runtime parts (`skeleton`).
    value (Shaped _ _ s) = s
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

||| A metavariable applied to its arguments, as the solution the type checker
||| gave it, which Idris's evaluator and its compilers follow too. Idris
||| leaves a solved one in a checked term when it solved it after the term
||| was elaborated (a lambda postponed until its type was known). The
||| solution is a closed term: lambdas over the scope the metavariable was
||| made in, the arguments, and `let`s for that scope's `let`s; both are
||| substituted. `Nothing` for a metavariable without a solution, a hole.
export
solution : {auto c : Ref Ctxt Defs} -> {vars : Scope} ->
           FC -> Name -> List (TT vars) -> Core (Maybe (TT vars))
solution fc n args = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => internal fc ("the metavariable " ++ show n ++ " is not in the context")
  case definition def of
    PMDef _ [] (STerm _ tm) _ _ => pure (Just (apply (embedClosed tm) args zero Subst.empty))
    PMDef {} => internal fc ("the solution of " ++ show n ++ " is not a term")
    _ => pure Nothing
  where
    apply : {drop, vs : Scope} -> TT (drop ++ vs) -> List (TT vs) -> SizeOf drop -> SubstEnv drop vs -> TT vs
    apply (Bind _ _ (Lam {}) sc) (a :: as) drop env = apply sc as (suc drop) (a :: env)
    apply (Bind _ _ (Let _ _ val _) sc) as drop env = apply (subst val sc) as drop env
    apply tm as drop env = foldl (App fc) (substs drop env tm) as

||| The quantities of a definition's parameters, as its type binds them.
quantities : {auto c : Ref Ctxt Defs} -> Name -> Core (List RigCount)
quantities n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => pure []
  pure (go (type def))
  where
    go : TT vs -> List RigCount
    go (Bind _ _ (Pi _ rig _ _) sc) = rig :: go sc
    go _ = []

||| Does a written implementation depend on a runtime value: does a part
||| that stands for one (`Erased` with reason `Impossible`: a runtime
||| variable, or a part of a runtime value its shape does not say) stand
||| where a value exists at runtime? A type does not (a binder's type, a
||| type constructor's arguments), nor does an argument a definition or a
||| constructor takes with quantity 0, which Idris has checked is never
||| used at runtime: `Foldable (Vect n)` does not depend on the length
||| `n`, while `MkBox {v = n}` holds `n` itself.
export
runtimeDependent : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core Bool
runtimeDependent = go
  where
    anyM : List (TT vs) -> (TT vs -> Core Bool) -> Core Bool
    anyM [] f = pure False
    anyM (x :: xs) f = if !(f x) then pure True else anyM xs f

    mutual
      go : TT vs -> Core Bool
      go (Erased _ Impossible) = pure True
      go (Erased _ (Dotted t)) = go t
      go (Bind _ _ (Pi {}) _) = pure False
      go (Bind _ _ (Let _ _ v _) sc) = if !(go v) then pure True else go sc
      go (Bind _ _ (PLet _ _ v _) sc) = if !(go v) then pure True else go sc
      go (Bind _ _ _ sc) = go sc
      go (TDelay _ _ _ arg) = go arg
      go (TForce _ _ t) = go t
      go (As _ _ _ p) = go p
      go (Meta _ _ _ args) = anyM args go
      go tm@(App {}) = applied (spine tm [])
      go _ = pure False

      applied : (TT vs, List (TT vs)) -> Core Bool
      applied (Ref _ (TyCon _) _, _) = pure False
      applied (Ref _ _ n, args) = do
        qs <- quantities n
        arguments (map isErased qs) args
      applied (f, args) = anyM (f :: args) go

      -- An argument past the parameters the type shows is taken as runtime.
      arguments : List Bool -> List (TT vs) -> Core Bool
      arguments _ [] = pure False
      arguments (True :: es) (_ :: as) = arguments es as
      arguments es (a :: as) = if !(go a) then pure True else arguments (drop 1 es) as

||| The normal form of a closed term, every definition unfolded as in
||| `closeNormalise`.
export
normaliseClosed : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core ClosedTerm
normaliseClosed tm = do
  defs <- get Ctxt
  normaliseAll defs [] tm

||| A projection: a definition that matches one of its parameters against
||| one constructor and returns one of that constructor's arguments, as
||| `fst` and an interface's parents and methods do. Its arity, the
||| position of the parameter, the constructor, and the position of the
||| argument.
projection : {auto c : Ref Ctxt Defs} -> Name -> Core (Maybe (Nat, Nat, Name, Nat))
projection n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => pure Nothing
  pure (case definition def of
          PMDef _ pargs (Case idx _ _ [ConCase cn _ cargs (STerm _ (Local _ _ k _))]) _ _ =>
            if k < length cargs then Just (length pargs, idx, cn, k) else Nothing
          _ => Nothing)

mutual
  ||| The constructor a compile-time value reduces to, with its arguments.
  ||| An implementation is a definition with one right-hand side, so it is
  ||| unfolded by substituting its arguments, keeping the rest as written,
  ||| whatever its visibility: one its module exports without its
  ||| definition is a module boundary, not a value. Anything else goes to
  ||| Idris's normaliser, which stops at such an implementation: a
  ||| projection it leaves takes its field from the constructor the record
  ||| reduces to here.
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
        _ => do
          Nothing <- normalised
            | found => pure found
          Just field <- projected fuel n args
            | Nothing => pure Nothing
          whnf fuel field
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

  ||| A projection applied to arguments, when it applies to all of them: the
  ||| field it takes from the constructor its record reduces to, applied to
  ||| the arguments past the projection's own.
  projected : {auto c : Ref Ctxt Defs} -> Nat -> Name -> List ClosedTerm -> Core (Maybe ClosedTerm)
  projected fuel n args = do
    Just (arity, idx, cn, k) <- projection n
      | Nothing => pure Nothing
    let True = length args >= arity
      | False => pure Nothing
    let Just whole = getAt idx args
      | Nothing => pure Nothing
    Just (built, fields) <- whnf fuel whole
      | Nothing => pure Nothing
    let Just field = getAt k fields
      | Nothing => pure Nothing
    if !(toFullNames built) /= !(toFullNames cn)
       then pure Nothing
       else pure (Just (foldl (App EmptyFC) field (drop arity args)))

||| The implementation a written one stands for, so that two are compared
||| by what they are: the name of an implementation applied to its
||| arguments, each of them an implementation reduced in turn, once what
||| leads to it is reduced: a projection of a constructor's argument (an
||| implementation's constraints, which Idris passes as one tuple, taken
||| apart with `fst` and `snd`; a parent taken from an implementation), a
||| `let`, an applied lambda. The implementation itself is not unfolded.
export
implementationOf : {auto c : Ref Ctxt Defs} -> Nat -> ClosedTerm -> Core ClosedTerm
implementationOf Z tm = pure tm
implementationOf (S fuel) tm = case spine tm [] of
  (Bind _ _ (Lam {}) sc, a :: as) => implementationOf fuel (betaAll (subst a sc) as)
  (Bind fc _ (Let _ _ v _) sc, as) => implementationOf fuel (foldl (App fc) (subst v sc) as)
  (f@(Ref fc _ n), args) => do
    Just field <- projected fuel n args
      | Nothing => foldl (App fc) f <$> traverse (implementationOf fuel) args
    implementationOf fuel field
  _ => pure tm

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

||| A term as a message shows it, every name full: a name Idris has
||| resolved to its place in the context prints as `$resolved359`, which
||| says nothing to the reader.
export
showTT : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core String
showTT tm = show <$> toFullNames tm

||| What a shape says a value was built with: a constructor, with the
||| shapes of its arguments. A shape that is no constructor application (an
||| erased part) says nothing of the value.
export
shapeHead : ClosedTerm -> Maybe (Name, List ClosedTerm)
shapeHead tm = case spine tm [] of
  (Ref _ (DataCon _ _) n, args) => Just (n, args)
  _ => Nothing

||| The shape of a term as written: the constructors it is built with,
||| everything else erased, and nothing when its head is no constructor.
||| Nothing is evaluated: a constant, a variable or a call says nothing.
||| What the shape does not say is a part of a runtime value, so a hole
||| has the reason `Impossible`, as a runtime variable has in the written
||| form: `runtimeDependent` refuses it wherever a value is needed.
export
skeleton : ClosedTerm -> Maybe ClosedTerm
skeleton tm = case spine tm [] of
  (con@(Ref fc (DataCon _ _) _), args) =>
    Just (foldl (App fc) con (map (\a => fromMaybe (Erased fc Impossible) (skeleton a)) args))
  _ => Nothing

||| A runtime value of a type with what its shape says, if anything.
export
shaped : a -> Ty -> ClosedTerm -> VarInfo a
shaped x t s = if isJust (shapeHead s) then Shaped x t s else Runtime x (Just t)

||| How many constructors deep a shape says what the value was built with.
export
shapeDepth : ClosedTerm -> Nat
shapeDepth tm = case shapeHead tm of
  Just (_, args) => S (foldl (\d, a => max d (shapeDepth a)) 0 args)
  Nothing => Z

||| A shape cut at a depth: every part below it, and every part the shape
||| does not say, is `hole`.
export
cutShape : ClosedTerm -> Nat -> ClosedTerm -> ClosedTerm
cutShape hole Z _ = hole
cutShape hole (S d) tm = case spine tm [] of
  (con@(Ref fc (DataCon _ _) _), args) => foldl (App fc) con (map (cutShape hole d) args)
  _ => hole

||| What a shape leaves unknown of a runtime value, where a type is asked
||| whether it needs it: a reference to a definition that does not exist,
||| at which reduction stops exactly where it would need the value. Idris's
||| quotation gives such a function back as it was, where it would take a
||| bound machine name for one of the binders it makes, by its number.
export
unknownPart : ClosedTerm
unknownPart = Ref EmptyFC Func (MN "idris-mlir-unknown" 0)

||| Does a term mention `unknownPart`?
export
mentionsUnknown : TT vars -> Bool
mentionsUnknown (Ref _ _ (MN "idris-mlir-unknown" _)) = True
mentionsUnknown (Bind _ _ b sc) = mentionsUnknown (binderType b) || binderVal b || mentionsUnknown sc
  where
    binderVal : TTBinder (TT vs) -> Bool
    binderVal (Let _ _ v _) = mentionsUnknown v
    binderVal (PLet _ _ v _) = mentionsUnknown v
    binderVal _ = False
mentionsUnknown (App _ f a) = mentionsUnknown f || mentionsUnknown a
mentionsUnknown (As _ _ a p) = mentionsUnknown p
mentionsUnknown (TDelayed _ _ t) = mentionsUnknown t
mentionsUnknown (TDelay _ _ t a) = mentionsUnknown t || mentionsUnknown a
mentionsUnknown (TForce _ _ t) = mentionsUnknown t
mentionsUnknown (Meta _ _ _ args) = any mentionsUnknown args
mentionsUnknown _ = False

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
