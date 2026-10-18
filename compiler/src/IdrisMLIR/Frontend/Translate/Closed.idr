-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Terms as closed values: types and implementations are compile-time
||| values, closed TT terms, which the translation substitutes, normalises
||| and reduces to their constructors.
module IdrisMLIR.Frontend.Translate.Closed

import Core.Case.CaseTree
import Core.CompileExpr
import Core.Context
import Core.Core
import Core.Env
import Core.Options
import Core.TT
import Idris.Host
import Libraries.Data.List.SizeOf

import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Syntax.Idr
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.WellFounded
import Data.DPair
import Data.Fin
import Data.List
import Data.List1
import Data.Nat
import Data.Vect

%default total

||| Idris's terms and binders; `Term` and `Binder` are Core's own.
public export
TT : Scope -> Type
TT = Core.TT.Term.Term

public export
TTBinder : Type -> Type
TTBinder = Core.TT.Binder.Binder

||| What a TT variable stands for: a Core variable (with its Core type, when a
||| match may need it, its closed Idris type where it is known, which says
||| which arguments a function-typed value takes at runtime, and the shape
||| of its value when that is known), a compile-time value, or an
||| implementation's value. Types and implementations are compile-time
||| values, closed TT terms, and so is a variable of quantity 0, which is
||| `TypeValue` of `Erased`: none is a Core variable. An implementation is
||| used by translating it where it is needed. An implementation that
||| closes over runtime values holds markers for them (`holeMarker`), with
||| the variable that holds them and what it holds (`Holes`).
public export
data VarInfo : Type -> Type where
  Runtime : a -> Maybe Ty -> Maybe ClosedTerm -> VarInfo a
  ||| A runtime value whose shape is known: the constructors every call of
  ||| the instance built its argument with (`Instances.classify`), or a
  ||| constructor's field of such a value. The shape stands for the value
  ||| in types, and a match on the value takes only the alternatives a
  ||| value of that shape can. Its Idris type is the one before the shape.
  Shaped : a -> Ty -> ClosedTerm -> ClosedTerm -> VarInfo a
  TypeValue : ClosedTerm -> VarInfo a
  Static : ClosedTerm -> Maybe (a, Holes) -> VarInfo a

export
Functor VarInfo where
  map f (Runtime x t i) = Runtime (f x) t i
  map f (Shaped x t i s) = Shaped (f x) t i s
  map f (TypeValue t) = TypeValue t
  map f (Static t h) = Static t (map (\(x, hs) => (f x, hs)) h)

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

||| An environment under a binder of `k` variables, which come first.
export
under : {k : Nat} -> List (VarInfo (Fin (Under k n))) -> List (VarInfo (Fin n)) ->
        List (VarInfo (Fin (Under k n)))
under bound env = bound ++ map (map (Free {k})) env

||| Does a subterm satisfy the test: the term, its binders' types and
||| values, an application's parts, a pattern's value, what a delay holds,
||| a metavariable's arguments?
export
mentions : ({0 vs : Scope} -> TT vs -> Bool) -> TT vars -> Bool
mentions p tm = p tm || case tm of
  Bind _ _ b sc => binder b || mentions p sc
  App _ f a => mentions p f || mentions p a
  As _ _ _ pat => mentions p pat
  TDelayed _ _ t => mentions p t
  TDelay _ _ t a => mentions p t || mentions p a
  TForce _ _ t => mentions p t
  Meta _ _ _ args => anyOf args
  _ => False
  where
    anyOf : List (TT vs) -> Bool
    anyOf [] = False
    anyOf (t :: ts) = mentions p t || anyOf ts

    binder : TTBinder (TT vs) -> Bool
    binder (Lam _ _ _ ty) = mentions p ty
    binder (Let _ _ v ty) = mentions p ty || mentions p v
    binder (Pi _ _ _ ty) = mentions p ty
    binder (PVar _ _ _ ty) = mentions p ty
    binder (PLet _ _ v ty) = mentions p ty || mentions p v
    binder (PVTy _ _ ty) = mentions p ty

||| Does the term mention `Erased` (a placeholder for an unknown value)?
export
anyErased : TT vars -> Bool
anyErased = mentions erasedTerm
  where
    erasedTerm : TT vs -> Bool
    erasedTerm (Erased _ _) = True
    erasedTerm _ = False

||| An Idris constant as the middle end's literal, one to one: the one place
||| the translation reads Idris's constants. A primitive type or the world
||| is no literal.
export
constantLit : Constant -> Maybe Lit
constantLit (I x) = Just (LInt IdrisInt (cast x))
constantLit (I8 x) = Just (LInt SInt8 (cast x))
constantLit (I16 x) = Just (LInt SInt16 (cast x))
constantLit (I32 x) = Just (LInt SInt32 (cast x))
constantLit (I64 x) = Just (LInt SInt64 (cast x))
constantLit (B8 x) = Just (LInt UInt8 (cast x))
constantLit (B16 x) = Just (LInt UInt16 (cast x))
constantLit (B32 x) = Just (LInt UInt32 (cast x))
constantLit (B64 x) = Just (LInt UInt64 (cast x))
constantLit (Ch x) = Just (LChar (cast (ord x)))
constantLit (Str x) = Just (LStr x)
constantLit (Db x) = Just (LDouble x)
constantLit (BI x) = Just (LBig x)
constantLit _ = Nothing

||| Abstracts every variable in scope with a lambda, giving a closed term whose
||| outermost lambda binds the last variable of `vars`.
wrapLams : {vars : Scope} -> FC -> TT vars -> ClosedTerm
wrapLams {vars = []} fc tm = tm
wrapLams {vars = x :: rest} fc tm =
  wrapLams {vars = rest} fc (Bind fc x (Lam fc top Explicit (Erased fc Placeholder)) tm)

||| A closed term in any scope.
export
embedClosed : {0 vars : Scope} -> ClosedTerm -> TT vars
embedClosed t = embed {outer = vars} t

||| Beta-reduces a closed lambda with its arguments, by substitution.
betaAll : ClosedTerm -> List ClosedTerm -> ClosedTerm
betaAll (Bind _ _ (Lam _ _ _ _) sc) (v :: vs) = betaAll (subst v sc) vs
betaAll tm vs = foldl (App EmptyFC) tm vs

||| Substitutes the outer `let`s of a term. Idris elaborates a record update
||| to a `let` of the record around its fields, so an implementation
||| resolved inside it is written under a `let` it does not use. The `let`s
||| of the body come off first; a body that is then the variable a `let`
||| binds is that `let`'s value, with its own outer `let`s substituted.
zeta : TT vars -> TT vars
zeta (Bind _ _ (Let _ _ v _) sc) = case zeta sc of
  Local _ _ Z _ => zeta v
  body => subst v body
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
    value (Static t _) = t
    -- A shape is what is known of the value at compile time; its holes
    -- are the runtime parts (`skeleton`).
    value (Shaped _ _ _ s) = s
    value (Runtime {}) = Erased fc Impossible

||| Does a term mention a metavariable? Idris can leave a solved one in an
||| elaborated term (the implementation for the inner pair of a triple).
hasMeta : TT vars -> Bool
hasMeta = mentions metaTerm
  where
    metaTerm : TT vs -> Bool
    metaTerm (Meta {}) = True
    metaTerm _ = False

||| The name of marker `i` (`holeMarker`'s): a name of the frontend's own,
||| which no context holds, nested around a user name no Idris identifier
||| spells. It is no machine name: Idris's quotation takes a bound machine
||| name for the binder it made with that number
||| (`Core.Normalise.Quote.quoteHead`), so a marker under a lambda Idris's
||| normaliser gives back would become that lambda's variable. This one
||| passes through every normaliser, under every binder, as itself. It and
||| `markerOf` are the one spelling of it.
export
markerName : Nat -> Name
markerName i = Nested (cast i, 0) (UN (Basic "idris-mlir-hole"))

||| The number of the marker a name is, if it is one (`markerName`'s).
export
markerOf : Name -> Maybe Nat
markerOf (Nested (i, 0) (UN (Basic "idris-mlir-hole"))) = Just (cast i)
markerOf _ = Nothing

||| Does a term mention a part that stands for a runtime value, wherever
||| it stands (`runtimeDependent`'s two markers)?
export
hasRuntimePart : TT vars -> Bool
hasRuntimePart = mentions part
  where
    part : TT vs -> Bool
    part (Erased _ Impossible) = True
    part (Ref _ _ n) = isJust (markerOf n)
    part _ = False

||| A closed term with its lambdas applied and the solutions of its
||| metavariables filled in, by the normaliser of Idris's that evaluates
||| nothing else: it unfolds no definition, so it runs none. Its markers
||| come back as themselves (`markerName`).
export
lambdasApplied : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core ClosedTerm
lambdasApplied tm = do
  defs <- get Ctxt
  host.normaliseHoles defs [] tm

||| A written form with the solutions of its metavariables filled in, and
||| nothing else evaluated when it has none.
export
solved : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core ClosedTerm
solved tm = if hasMeta tm then lambdasApplied tm else pure tm

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
    apply (Bind _ _ (Let _ _ val _) sc) as drop env = apply sc as (suc drop) (substs drop env val :: env)
    apply tm as drop env = foldl (App fc) (substs drop env tm) as

||| Which parameters of a definition are erased, by position, as its type
||| binds them.
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

||| What `runtimeDependent` has read of an application, its head and
||| arguments from the left: a type, whose arguments are types; a part that
||| stands for a runtime value where one exists, after which nothing else
||| matters; or the erasure of each argument still to come, as the head's
||| definition takes it.
data Applied = OfType | Depends | Taking (List Bool)

||| Does a written implementation depend on a runtime value: does a part
||| that stands for one (`Erased` with reason `Impossible`: a runtime
||| variable, or a part of a runtime value its shape does not say; or
||| `holeMarker`, the value an implementation closes over) stand
||| where a value exists at runtime? A type does not (a binder's type, a
||| type constructor's arguments), nor does an argument a definition or a
||| constructor takes with quantity 0, which Idris has checked is never
||| used at runtime: `Foldable (Vect n)` does not depend on the length
||| `n`, while `MkBox {v = n}` holds `n` itself. An argument past the
||| parameters the type shows is taken as runtime.
export
runtimeDependent : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core Bool
runtimeDependent = go
  where
    mutual
      go : TT vs -> Core Bool
      go (Erased _ Impossible) = pure True
      go (Ref _ _ n) = pure (isJust (markerOf n))
      go (Erased _ (Dotted t)) = go t
      go (Bind _ _ (Pi {}) _) = pure False
      go (Bind _ _ (Let _ _ v _) sc) = if !(go v) then pure True else go sc
      go (Bind _ _ (PLet _ _ v _) sc) = if !(go v) then pure True else go sc
      go (Bind _ _ _ sc) = go sc
      go (TDelay _ _ _ arg) = go arg
      go (TForce _ _ t) = go t
      go (As _ _ _ p) = go p
      go (Meta _ _ _ args) = anyOf args
      go (App _ f a) = do
        Depends <- appliedTo f a
          | _ => pure False
        pure True
      go _ = pure False

      anyOf : List (TT vs) -> Core Bool
      anyOf [] = pure False
      anyOf (t :: ts) = if !(go t) then pure True else anyOf ts

      -- An application's function applied to one more argument.
      appliedTo : TT vs -> TT vs -> Core Applied
      appliedTo f a = case !(applied f) of
        OfType => pure OfType
        Depends => pure Depends
        Taking (True :: es) => pure (Taking es)
        Taking es => pure (if !(go a) then Depends else Taking (drop 1 es))

      applied : TT vs -> Core Applied
      applied (App _ f a) = appliedTo f a
      applied (Ref _ (TyCon _) _) = pure OfType
      applied (Ref _ _ n) = Taking <$> erasedArgs n
      applied f = pure (if !(go f) then Depends else Taking [])

||| The normal form of a closed term, its definitions unfolded as in
||| `closeNormalise`.
export
normaliseClosed : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core ClosedTerm
normaliseClosed tm = do
  defs <- get Ctxt
  host.normaliseTypes defs [] tm

||| A runtime value an implementation closes over, where its compile-time
||| form stands, by its number among the values (`holeMarker`, below with
||| the values it stands among).
export
holeMarker : Nat -> ClosedTerm

||| One of Idris's normalisers, at any scope.
Normaliser : Type
Normaliser = {free : _} -> Defs -> Env Term free -> Term free -> Core (Term free)

||| A projection: a definition that matches one of its parameters against
||| one constructor and returns one of that constructor's arguments, as
||| `fst` and an interface's parents and methods do. Its parameters, the
||| first first, the one it matches, which its case tree says is one of
||| them, the constructor, and the position of the argument it returns.
public export
record Projection where
  constructor MkProjection
  params : Scope
  matched : Nat
  0 param : Name
  0 isParam : IsVar param matched params
  con : Name
  field : Nat

||| The projection a definition is, if it is one.
projectionOf : GlobalDef -> Maybe Projection
projectionOf def = case definition def of
  PMDef _ pargs (Case idx v _ [ConCase cn _ cargs (STerm _ (Local _ _ k _))]) _ _ =>
    if k < length cargs then Just (MkProjection pargs idx _ v cn k) else Nothing
  _ => Nothing

||| The projection a definition is, if it is one.
export
projection : {auto c : Ref Ctxt Defs} -> Name -> Core (Maybe Projection)
projection n = do
  defs <- get Ctxt
  pure (projectionOf =<< !(lookupCtxtExact n (gamma defs)))

||| The outermost definition named in the string Idris gives a case or with
||| block for its parent: `case block in f`, `with block in f`, or `f,go`
||| for a block of `f`'s nested `go`. A prefix comes off as the part of the
||| string it stands before, so that each is one fewer.
outermost : String -> String
outermost s = pack (takeWhile (/= ',') (blocks (unpack s)))
  where
    blocks : List Char -> List Char
    blocks ('c' :: 'a' :: 's' :: 'e' :: ' ' :: 'b' :: 'l' :: 'o' :: 'c' :: 'k' :: ' ' :: 'i' :: 'n' :: ' ' :: rest) =
      blocks rest
    blocks ('w' :: 'i' :: 't' :: 'h' :: ' ' :: 'b' :: 'l' :: 'o' :: 'c' :: 'k' :: ' ' :: 'i' :: 'n' :: ' ' :: rest) =
      blocks rest
    blocks cs = cs

||| The definition a case, with or nested block belongs to, through every
||| block between: a case or with block's parent is a string, in the
||| block's namespace; a nested function's parent is its place in the
||| context. Idris's numbers in a nested name are those of the session that
||| elaborated it, so the parents of a loaded one can lead anywhere, even
||| back to a name passed already: the walk enters each parent once
||| (`Walk`), and stops at a name whose parent it has entered.
export
rootOf : {auto c : Ref Ctxt Defs} -> Name -> Core Name
rootOf n = climb start (sizeAccessible start) n
  where
    -- The accessibility proof is erased, and every clause matches its one
    -- constructor: no alternative is chosen by it.
    climb : (w : Walked) -> (0 _ : SizeAccessible w) -> Name -> Core Name
    climb w (Access _) (NS ns (CaseBlock outer _)) = pure (NS ns (UN (Basic (outermost outer))))
    climb w (Access _) (NS ns (WithBlock outer _)) = pure (NS ns (UN (Basic (outermost outer))))
    climb w (Access rec) m@(NS _ (Nested (outer, _) _)) = do
      defs <- get Ctxt
      case enter (gamma defs) (Resolved outer) w of
        Nothing => pure m
        Just (Element w' less) => climb w' (rec w' less) !(toFullNames (Resolved outer))
    climb w (Access _) m = pure m

||| Did Idris prove that every call of a definition ends? Idris's own
||| termination check, which follows everything the definition calls, so
||| a reduction through such a definition ends by Idris's proof. Idris
||| checks a block as part of the definition it belongs to, whose calls
||| the block's are, so a block ends when that definition does too.
terminates : {auto c : Ref Ctxt Defs} -> Name -> Core Bool
terminates n = do
  root <- rootOf !(toFullNames n)
  defs <- get Ctxt
  owner <- lookupCtxtExact root (gamma defs)
  if not !(ends n) then pure False else maybe (pure True) (const (ends root)) owner
  where
    ends : Name -> Core Bool
    ends m = do
      verdict <- host.checkTerminating EmptyFC m
      pure (case verdict of
              IsTerminating => True
              _ => False)

||| The definitions a term refers to.
functionsIn : TT vars -> List Name
functionsIn tm = nub (go tm)
  where
    mutual
      go : TT vs -> List Name
      go (Ref _ Func n) = [n]
      go (Bind _ _ b sc) = binder b ++ go sc
      go (App _ f a) = go f ++ go a
      go (As _ _ _ p) = go p
      go (TDelayed _ _ t) = go t
      go (TDelay _ _ t a) = go t ++ go a
      go (TForce _ _ t) = go t
      go (Meta _ _ _ args) = each args
      go (Erased _ (Dotted t)) = go t
      go _ = []

      each : List (TT vs) -> List Name
      each [] = []
      each (t :: ts) = go t ++ each ts

      -- A binder's type, then the value of a `let`.
      binder : TTBinder (TT vs) -> List Name
      binder (Lam _ _ _ ty) = go ty
      binder (Let _ _ v ty) = go ty ++ go v
      binder (Pi _ _ _ ty) = go ty
      binder (PVar _ _ _ ty) = go ty
      binder (PLet _ _ v ty) = go ty ++ go v
      binder (PVTy _ _ ty) = go ty

||| The first definition a term refers to that Idris does not prove ends,
||| if any. Idris's normaliser runs a term only when there is none: it
||| normalises the whole term, so a definition anywhere in it is run.
partialIn : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core (Maybe Name)
partialIn tm = firstOf (functionsIn tm)
  where
    firstOf : List Name -> Core (Maybe Name)
    firstOf [] = pure Nothing
    firstOf (n :: ns) = do
      defs <- get Ctxt
      Just def <- lookupCtxtExact n (gamma defs)
        | Nothing => firstOf ns
      if !(terminates n) then firstOf ns else pure (Just (fullname def))

||| A closed term as written, its metavariables filled in, normalised by
||| one of Idris's normalisers: when the term refers to a definition Idris
||| does not prove ends, which the normaliser would run, that definition
||| instead. Every call of a normaliser that unfolds definitions on a term
||| the translation reduces goes through here, so none runs what Idris does
||| not prove ends; the one that applies lambdas (`lambdasApplied`) runs
||| none.
normalisedBy : {auto c : Ref Ctxt Defs} -> Normaliser -> ClosedTerm -> Core (Either Name ClosedTerm)
normalisedBy normaliser tm = do
  filled <- solved tm
  Nothing <- partialIn filled
    | Just n => pure (Left n)
  defs <- get Ctxt
  Right <$> normaliser defs [] filled

||| A closed term expanded by Idris's normaliser, implementations unfolded
||| to their constructors: the form a projection's field is taken from,
||| in which an argument an implementation took erased can stand where its
||| own blocks take it at runtime. Nothing when the term refers to a
||| definition Idris does not prove ends.
export
expandClosed : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core (Maybe ClosedTerm)
expandClosed tm = either (const Nothing) Just <$> normalisedBy host.normalise tm

------------------------------------------------------------------------------
-- Reduction to a head
------------------------------------------------------------------------------

||| What a reduction is stuck on.
public export
data StuckOn
  = ||| A runtime value: one an implementation closes over, a part of one
    ||| its shape does not say, or a runtime variable.
    OnRuntime ClosedTerm
  | ||| A definition Idris does not prove ends, which Idris's normaliser
    ||| would run.
    OnPartial Name
  | ||| A value that is no constructor application: a literal, a type, a
    ||| function, a definition applied to fewer arguments than it takes.
    OnValue ClosedTerm

||| What a compile-time value is at its head: a constructor applied to its
||| arguments, or the part its reduction is stuck on.
public export
data Head : Type -> Type where
  Built : Name -> List a -> Head a
  Stuck : StuckOn -> Head a

export
Functor Head where
  map f (Built n args) = Built n (map f args)
  map f (Stuck on) = Stuck on

||| Which of Idris's normalisers a term on the way to the next unfolding
||| is a normal form of, so that none is asked of it again: a term as
||| written, of none; what the normaliser that evaluates only lambdas
||| applied and metavariables gives (`lambdasApplied`), of that one; what
||| the normaliser that keeps to the program's visibility gives, of both.
||| What is left in a normal form of that one is kept from it by its
||| visibility, and goes to the one that unfolds every definition, whose
||| normal form is the head (`again`). A phase holds the phases after it,
||| so that asking a normaliser is a step to a part of the phase.
data Phase : Type
data IsNormal : Phase -> Type
data IsBeta : Phase -> Type

data Phase : Type where
  Normal : Phase
  Beta : (normalised : Phase) -> (0 _ : IsNormal normalised) -> Phase
  Written : (beta : Phase) -> (0 _ : IsBeta beta) -> Phase

data IsNormal : Phase -> Type where
  ItIs : IsNormal Normal

data IsBeta : Phase -> Type where
  ItIsBeta : IsBeta (Beta Normal ItIs)

asWritten : Phase
asWritten = Written (Beta Normal ItIs) ItIsBeta

||| A part of a term a reduction meets (an argument, or the value a lambda
||| or a `let` binds), from where it meets it: as written, to its head
||| (`value`), and to the implementation it stands for (`implemented`),
||| each computed when it is needed, on the head path where the part was
||| met. A projection's field continues the path its record was reduced on.
record Part where
  constructor MkPart
  written : Lazy ClosedTerm
  value : Lazy (Core (Head Part))
  implemented : Lazy (Core ClosedTerm)

||| What each variable of a scope stands for.
data Parts : Scope -> Type where
  Nil : Parts []
  (::) : Part -> Parts vs -> Parts (v :: vs)

||| The part a variable stands for, which its scope says is there.
partAt : Parts vs -> (idx : Nat) -> (0 _ : IsVar n idx vs) -> Part
partAt (p :: _) Z _ = p
partAt (_ :: ps) (S i) v = partAt ps i (dropLater v)
partAt [] _ First impossible
partAt [] _ (Later _) impossible

sizeOfParts : Parts vs -> SizeOf vs
sizeOfParts [] = zero
sizeOfParts (_ :: ps) = suc (sizeOfParts ps)

substEnv : Parts vs -> SubstEnv vs []
substEnv [] = []
substEnv (p :: ps) = p.written :: substEnv ps

||| A term with what each of its variables stands for, as written.
close : Parts vs -> TT vs -> ClosedTerm
close {vs} env tm = substs (sizeOfParts env) (substEnv env) (rewrite appendNilRightNeutral vs in tm)

||| A term applied to parts, as written.
whole : Parts vs -> TT vs -> List Part -> ClosedTerm
whole env tm args = applyAll (close env tm) args
  where
    applyAll : ClosedTerm -> List Part -> ClosedTerm
    applyAll f [] = f
    applyAll f (a :: as) = applyAll (App EmptyFC f a.written) as

||| The parameters of a definition, the first argument first, from the
||| parts it is applied to, and the parts past them: nothing when it is
||| applied to fewer.
params : (vs : Scope) -> List Part -> Maybe (Parts vs, List Part)
params [] args = Just ([], args)
params (_ :: vs) (a :: args) = map (\(env, rest) => (a :: env, rest)) (params vs args)
params (_ :: _) [] = Nothing

||| A projection applied to parts, when it applies to all of them: the
||| field it takes from the constructor its record reduces to, and the
||| parts past the projection's own.
project : {auto c : Ref Ctxt Defs} -> Projection -> List Part -> Core (Maybe (Part, List Part))
project pr args = case params pr.params args of
  Nothing => pure Nothing
  Just (env, extras) => do
    Built built fields <- (partAt env pr.matched pr.isParam).value
      | Stuck _ => pure Nothing
    let Just field = getAt pr.field fields
      | Nothing => pure Nothing
    if !(toFullNames built) /= !(toFullNames pr.con)
       then pure Nothing
       else pure (Just (field, extras))

||| The head of a normal form, every part of it a normal form too, which
||| nothing is left to reduce. A reference to a name the context does not
||| have stands for what is not known of a runtime value, as it does where
||| a reduction unfolds it (`unfolded`).
normalHead : Context -> ClosedTerm -> Head Part
normalHead ctxt tm = spine tm []
  where
    normalPart : ClosedTerm -> Part
    normalPart t = MkPart t (pure (normalHead ctxt t)) (pure t)

    spine : ClosedTerm -> List Part -> Head Part
    spine (App _ f a) args = spine f (normalPart a :: args)
    spine (Ref _ (DataCon _ _) n) args = Built n args
    spine (Ref _ Bound _) _ = Stuck (OnRuntime tm)
    spine (Ref _ Func n) _ = Stuck (maybe (OnRuntime tm) (const (OnValue tm)) (getNameID n ctxt))
    spine (Erased _ Impossible) _ = Stuck (OnRuntime tm)
    spine _ _ = Stuck (OnValue tm)

||| A definition the reduction meets again on its head path: unfolding it
||| came back to it, so what ends its recursion is a match on the way,
||| which is Idris's to evaluate. The term goes to Idris's normaliser with
||| every definition unfolded whatever its visibility, when every
||| definition it refers to ends, and its normal form is the head. A
||| definition does not come back to itself through unfoldings and
||| projections alone unless it does not end, so the normaliser is asked
||| only where a match recurses.
again : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core (Head Part)
again tm = do
  defs <- get Ctxt
  either (Stuck . OnPartial) (normalHead (gamma defs)) <$> normalisedBy host.normaliseAll tm

mutual
  ||| A term, with what each of its variables stands for, applied to parts,
  ||| reduced to its head on a head path. An implementation is a definition
  ||| with one right-hand side, so it is unfolded by binding its parameters
  ||| to its arguments, keeping the rest as written, whatever its
  ||| visibility: one its module exports without its definition is a module
  ||| boundary, not a value. Anything else goes to Idris's normaliser, when
  ||| every definition the term refers to ends, which stops at such an
  ||| implementation: a projection it leaves takes its field from the
  ||| constructor the record reduces to here. A lambda applied to parts and
  ||| a `let` bind their variable to the part, so no term is substituted on
  ||| the way.
  |||
  ||| It ends, lexicographically in the definitions not yet unfolded on the
  ||| path, the phase, and the term: an unfolding puts a definition on the
  ||| path, which it unfolds only while it is not there (`enter`), and one
  ||| met again goes to the normaliser (`again`); asking a normaliser
  ||| moves to the phase of its normal form, of which neither it nor one
  ||| before it is asked again; every other step goes to a part of the
  ||| term. A part's own reductions are suspended where the part is met, a
  ||| part of the term there or of a body on a longer path, so forcing one
  ||| later is no step of the reduction that forces it. What is not bounded
  ||| so, a recursion through a match, the evaluation of a definition that
  ||| matches, and a lambda that reaches the head as a value applied to
  ||| parts, is Idris's normaliser's, the one reduction the frontend takes
  ||| on trust (`Host`): Idris's theory is not strongly normalising, so no
  ||| measure of the term bounds it.
  reduce : {auto c : Ref Ctxt Defs} -> Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           Parts vs -> TT vs -> List Part -> Core (Head Part)
  reduce ph w acc env (App _ f a) args = reduce ph w acc env f (partOf ph w acc env a :: args)
  reduce ph w acc env (Bind _ _ (Lam {}) sc) (a :: args) = reduce ph w acc (a :: env) sc args
  reduce ph w acc env tm@(Bind _ _ (Lam {}) _) [] = pure (Stuck (OnValue (close env tm)))
  reduce ph w acc env (Bind _ _ (Let _ _ v _) sc) args = reduce ph w acc (partOf ph w acc env v :: env) sc args
  reduce ph w acc env (Local _ _ idx v) args = applied ph w acc (partAt env idx v) args
  reduce ph w acc env (Ref _ (DataCon _ _) n) args = pure (Built n args)
  reduce ph w acc env tm@(Ref _ (TyCon _) _) args = pure (Stuck (OnValue (whole env tm args)))
  reduce ph w acc env tm@(Ref _ Bound _) args = pure (Stuck (OnRuntime (whole env tm args)))
  reduce ph w acc env tm@(Ref _ Func n) args = unfolded ph w acc n (whole env tm args) args
  reduce ph w acc env tm@(Meta _ _ i _) args = filledIn ph w acc i (whole env tm args)
  reduce ph w acc env tm@(Erased _ Impossible) args = pure (Stuck (OnRuntime (whole env tm args)))
  reduce ph w acc env tm args = normalised ph w acc (whole env tm args)

  ||| A part met on the path.
  partOf : {auto c : Ref Ctxt Defs} -> Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           Parts vs -> TT vs -> Part
  partOf ph w acc env a = MkPart (close env a) (reduce ph w acc env a []) (implementing ph w acc env a [])

  ||| A definition applied to parts. A reference to a definition that does
  ||| not exist stands for what is not known of a runtime value
  ||| (`unknownPart`).
  unfolded : {auto c : Ref Ctxt Defs} -> Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
             Name -> Lazy ClosedTerm -> List Part -> Core (Head Part)
  unfolded ph w acc@(Access rec) n tm args = do
    defs <- get Ctxt
    let Just i = getNameID n (gamma defs)
      | Nothing => pure (Stuck (OnRuntime tm))
    Just def <- lookupCtxtExact (Resolved i) (gamma defs)
      | Nothing => pure (Stuck (OnRuntime tm))
    case definition def of
      PMDef _ pargs (STerm _ body) _ _ => case params pargs args of
        Nothing => pure (Stuck (OnValue tm))
        Just (env, rest) => case enter (gamma defs) (Resolved i) w of
          Nothing => again tm
          Just (Element w' less) => reduce asWritten w' (rec w' less) env body rest
      _ => case projectionOf def of
        Nothing => normalised ph w acc tm
        -- A projection: the field it takes from the constructor its record
        -- reduces to here, its arguments as written, so that an
        -- implementation in it stays the implementation it names. A
        -- normal form of the record unfolds every implementation inside
        -- its fields too, so taken first it would give one implementation
        -- a second written form. A record that reduces to no constructor
        -- here is stuck in the normal form of the normaliser that unfolds
        -- every definition, which no other normaliser goes past, so the
        -- projection is what that normaliser makes of it.
        Just pr => do
          Just (field, extras) <- project pr args
            | Nothing => again tm
          applied ph w acc field extras

  ||| A metavariable applied, as the solution Idris gave it: unfolded as a
  ||| definition is, once on a path.
  filledIn : {auto c : Ref Ctxt Defs} -> Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
             Int -> Lazy ClosedTerm -> Core (Head Part)
  filledIn ph w acc@(Access rec) i tm = do
    defs <- get Ctxt
    case enter (gamma defs) (Resolved i) w of
      Nothing => again tm
      Just (Element w' less) => do
        filled <- solved tm
        if hasMeta filled then pure (Stuck (OnValue tm)) else reduce asWritten w' (rec w' less) [] filled []

  ||| A part applied to parts. A constructor takes them as its arguments; a
  ||| runtime value applied is one. Anything else, a lambda or a function
  ||| applied to fewer arguments than it takes, is applied as written
  ||| (`betaReduced`).
  applied : {auto c : Ref Ctxt Defs} -> Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            Part -> List Part -> Core (Head Part)
  applied ph w acc part [] = part.value
  applied ph w acc part args@(_ :: _) = do
    Built n fields <- part.value
      | Stuck (OnRuntime _) => pure (Stuck (OnRuntime (whole [] part.written args)))
      | Stuck _ => betaReduced ph w acc (whole [] part.written args)
    pure (Built n (fields ++ args))

  ||| A term as written that applies what is no constructor, its lambdas
  ||| applied by the normaliser that unfolds no definition
  ||| (`lambdasApplied`), and reduced on in that normaliser's phase, so
  ||| that a definition the lambdas lead to is unfolded as any other is.
  ||| Applying a lambda is bounded by no measure of the term, since Idris's
  ||| theory is not strongly normalising, so it is Idris's normaliser's. In
  ||| a term that normaliser gave, what applies a function is a projection
  ||| or a `let`, and goes to the normaliser of the phase (`normalised`).
  betaReduced : {auto c : Ref Ctxt Defs} -> Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                Lazy ClosedTerm -> Core (Head Part)
  betaReduced (Written beta _) w acc tm = reduce beta w acc [] !(lambdasApplied tm) []
  betaReduced ph w acc tm = normalised ph w acc tm

  ||| A term given to Idris's normaliser that keeps to the program's
  ||| visibility, when every definition it refers to ends, and its normal
  ||| form reduced on the same path. In the normal form, what is still not
  ||| reduced is kept from the normaliser by its visibility, and goes to it
  ||| again with every definition unfolded (`again`).
  normalised : {auto c : Ref Ctxt Defs} -> Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
               Lazy ClosedTerm -> Core (Head Part)
  normalised Normal w acc tm = again tm
  normalised (Beta next _) w acc tm = normalisedTo next w acc tm
  normalised (Written (Beta next _) _) w acc tm = normalisedTo next w acc tm
  normalised (Written Normal ItIsBeta) _ _ _ impossible
  normalised (Written (Written _ _) ItIsBeta) _ _ _ impossible

  normalisedTo : {auto c : Ref Ctxt Defs} -> Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                 Lazy ClosedTerm -> Core (Head Part)
  normalisedTo next w acc tm = case !(normalisedBy host.normalise tm) of
    Left n => pure (Stuck (OnPartial n))
    Right nf => reduce next w acc [] nf []

  ||| The implementation a term stands for (`implementationOf`), with what
  ||| each of its variables stands for, applied to parts.
  implementing : {auto c : Ref Ctxt Defs} -> Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                 Parts vs -> TT vs -> List Part -> Core ClosedTerm
  implementing ph w acc env (App _ f a) args = implementing ph w acc env f (partOf ph w acc env a :: args)
  implementing ph w acc env (Bind _ _ (Lam {}) sc) (a :: args) = implementing ph w acc (a :: env) sc args
  implementing ph w acc env (Bind _ _ (Let _ _ v _) sc) args =
    implementing ph w acc (partOf ph w acc env v :: env) sc args
  implementing ph w acc env (Local _ _ idx v) args = implementationApplied ph w acc (partAt env idx v) args
  implementing ph w acc env tm@(Ref fc _ n) args = do
    Just (field, extras) <- projectedPart n args
      | Nothing => foldl (App fc) (close env tm) <$> implementations args
    implementationApplied ph w acc field extras
  implementing ph w acc env tm args = pure (whole env tm args)

  ||| A projection's field, when the name is a projection that applies.
  projectedPart : {auto c : Ref Ctxt Defs} -> Name -> List Part -> Core (Maybe (Part, List Part))
  projectedPart n args = do
    Just pr <- projection n
      | Nothing => pure Nothing
    project pr args

  ||| The implementation a part applied to parts stands for: of the part as
  ||| written applied to them, its lambdas applied as `betaReduced` applies
  ||| them, so that a field a projection takes past its own arguments, or a
  ||| function an implementation is given, is applied to its arguments. In
  ||| a term that normaliser gave, a part is applied by a projection or a
  ||| `let`, and its implementation stays applied to theirs.
  implementationApplied : {auto c : Ref Ctxt Defs} -> Phase -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                          Part -> List Part -> Core ClosedTerm
  implementationApplied ph w acc part [] = part.implemented
  implementationApplied (Written beta _) w acc part args@(_ :: _) =
    implementing beta w acc [] !(lambdasApplied (whole [] part.written args)) []
  implementationApplied ph w acc part args@(_ :: _) = do
    f <- part.implemented
    foldl (App EmptyFC) f <$> implementations args

  implementations : {auto c : Ref Ctxt Defs} -> List Part -> Core (List ClosedTerm)
  implementations [] = pure []
  implementations (a :: as) = do
    t <- a.implemented
    (t ::) <$> implementations as

||| What a compile-time value reduces to at its head (`reduce`), from a
||| head path that has unfolded nothing.
export
whnf : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core (Head ClosedTerm)
whnf tm = map (\a => Force a.written) <$> reduce asWritten start (sizeAccessible start) [] tm []

||| A projection applied to arguments, when it applies to all of them: the
||| field it takes from the constructor its record reduces to, applied to
||| the arguments past the projection's own.
export
projected : {auto c : Ref Ctxt Defs} -> Name -> List ClosedTerm -> Core (Maybe ClosedTerm)
projected n args = do
  Just (field, extras) <- projectedPart n (map (partOf asWritten start (sizeAccessible start) []) args)
    | Nothing => pure Nothing
  pure (Just (whole [] field.written extras))

||| The implementation a written one stands for, so that two are compared
||| by what they are: the name of an implementation applied to its
||| arguments, each of them an implementation reduced in turn, once what
||| leads to it is reduced: a projection of a constructor's argument (an
||| implementation's constraints, which Idris passes as one tuple, taken
||| apart with `fst` and `snd`; a parent taken from an implementation), a
||| `let`, an applied lambda. The implementation itself is not unfolded. A
||| projection's field continues the head path its record was reduced on,
||| so a field that leads back to a definition already unfolded there is
||| the one Idris's normaliser reduces (`again`).
export
implementationOf : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core ClosedTerm
implementationOf tm = implementing asWritten start (sizeAccessible start) [] tm []

||| A term as a message shows it, every name full: a name Idris has
||| resolved to its place in the context prints as `$resolved359`, which
||| says nothing to the reader.
export
showTT : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core String
showTT tm = show <$> toFullNames tm

||| What a message says a reduction is stuck on: the value or the
||| definition it names.
export
stuckText : {auto c : Ref Ctxt Defs} -> StuckOn -> Core String
stuckText (OnRuntime tm) = ("the runtime value " ++) <$> showTT tm
stuckText (OnPartial n) = pure (show !(toFullNames n) ++ ", which Idris does not prove ends")
stuckText (OnValue tm) = ("the value " ++) <$> showTT tm

||| What a shape says a value was built with: a constructor, with the
||| shapes of its arguments. A shape that is no constructor application (an
||| erased part) says nothing of the value.
export
shapeHead : ClosedTerm -> Maybe (Name, List ClosedTerm)
shapeHead tm = case getFnArgs tm of
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
skeleton con@(Ref _ (DataCon _ _) _) = Just con
skeleton (App fc f a) = (\f' => App fc f' (fromMaybe (Erased fc Impossible) (skeleton a))) <$> skeleton f
skeleton _ = Nothing

||| A runtime value of a type with what its shape says, if anything.
export
shaped : a -> Ty -> ClosedTerm -> ClosedTerm -> VarInfo a
shaped x t ity s = if isJust (shapeHead s) then Shaped x t ity s else Runtime x (Just t) (Just ity)

||| How many constructors deep a shape says what the value was built with.
export
shapeDepth : ClosedTerm -> Nat
shapeDepth tm = maybe Z S (deepest tm)
  where
    -- The depth of the deepest argument of a constructor application.
    deepest : ClosedTerm -> Maybe Nat
    deepest (Ref _ (DataCon _ _) _) = Just Z
    deepest (App _ f a) = (\d => max d (shapeDepth a)) <$> deepest f
    deepest _ = Nothing

||| A shape cut at a depth: every part below it, and every part the shape
||| does not say, is `hole`.
export
cutShape : ClosedTerm -> Nat -> ClosedTerm -> ClosedTerm
cutShape hole Z _ = hole
cutShape hole (S d) tm = case getFnArgs tm of
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

-- The marker itself (declared above): a bound name that no binder binds,
-- which a translation of the implementation replaces with the value
-- (`Terms.term`, by `refToLocal`, which takes bound names).
holeMarker i = Ref EmptyFC Bound (markerName i)

||| Replaces each marker of the values an implementation closes over with
||| the term for its value, by number.
export
fillHoles : List ClosedTerm -> ClosedTerm -> ClosedTerm
fillHoles values tm = foldl fill tm (zip [0 .. length values] values)
  where
    fill : ClosedTerm -> (Nat, ClosedTerm) -> ClosedTerm
    fill t (i, v) = substName (markerName i) v t

||| A reference to a definition, as Idris writes one: with its kind.
export
refTo : {auto c : Ref Ctxt Defs} -> FC -> Name -> Core ClosedTerm
refTo fc n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => throw (InternalError ("no definition of " ++ show n))
  pure (Ref fc (kind (definition def)) (fullname def))
  where
    kind : Def -> NameType
    kind (DCon tag arity _) = DataCon tag arity
    kind (TCon arity _ _ _ _ _ _) = TyCon arity
    kind _ = Func

||| The pair Idris's `%pair` names: its type, its projections.
export
pairNames : {auto c : Ref Ctxt Defs} -> Core (Name, Name, Name)
pairNames = do
  defs <- get Ctxt
  let Just ns = pairnames (options defs)
    | Nothing => throw (InternalError "no pair type")
  pure (pairType ns, fstName ns, sndName ns)

||| The type of the one value that holds the values an implementation closes
||| over: the one type, or a pair of the first and the rest.
export
packedType : {auto c : Ref Ctxt Defs} -> List1 ClosedTerm -> Core ClosedTerm
packedType (t ::: ts) = packed t ts
  where
    packed : ClosedTerm -> List ClosedTerm -> Core ClosedTerm
    packed t [] = pure t
    packed t (u :: us) = do
      (pair, _, _) <- pairNames
      p <- refTo EmptyFC pair
      pure (App EmptyFC (App EmptyFC p t) !(packed u us))

||| The values the one value holds (`packedType`), as projections of it.
export
unpacked : {auto c : Ref Ctxt Defs} -> List1 ClosedTerm -> ClosedTerm -> Core (List ClosedTerm)
unpacked (t ::: ts) v = projections t ts v
  where
    projections : ClosedTerm -> List ClosedTerm -> ClosedTerm -> Core (List ClosedTerm)
    projections _ [] v = pure [v]
    projections t (u :: us) v = do
      (_, first, second) <- pairNames
      f <- refTo EmptyFC first
      s <- refTo EmptyFC second
      rest <- packedType (u ::: us)
      let proj = \p => App EmptyFC (App EmptyFC (App EmptyFC p t) rest) v
      (proj f ::) <$> projections u us (proj s)

||| Does a term mention `holeMarker`?
export
mentionsHole : TT vars -> Bool
mentionsHole = mentions hole
  where
    hole : TT vs -> Bool
    hole (Ref _ _ n) = isJust (markerOf n)
    hole _ = False

||| Does a term mention `unknownPart`?
export
mentionsUnknown : TT vars -> Bool
mentionsUnknown = mentions unknownRef
  where
    unknownRef : TT vs -> Bool
    unknownRef (Ref _ _ (MN "idris-mlir-unknown" _)) = True
    unknownRef _ = False

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

||| Does a definition compute a type: is its type, normalised, a universe
||| after its arguments? Normalised, since a type may be written with a
||| name for one: `VarSet : Scoped` is `Scope -> Type`.
export
computesType : {auto c : Ref Ctxt Defs} -> GlobalDef -> Core Bool
computesType def = isTypeLike <$> normaliseClosed (type def)

mutual
  ||| A term with every eta-redex in it contracted, the innermost first:
  ||| `\y => f y`, where `f` does not mention `y`, is `f`, and so `\x, y =>
  ||| g x y` is `g`. A normal form keeps them: Idris passes a method's
  ||| argument of a type that binds implicits so (`fork`'s thread, `\{e'},
  ||| {c} => thread e' c`), and a family as a lambda that applies it (`\x
  ||| => g x`: an implementation's superclass over `f . g`, a recursion
  ||| over `Cells p`, the predicate of `(c ** as ** Positive g c as)`).
  ||| A type argument is compared contracted (`canonicalTypeArg`), and every
  ||| reading of the growth check takes a term contracted, a site's and a
  ||| request's alike, so that a family is read as itself whatever stands
  ||| for it: a marker, or the type constructor at its head.
  export
  contracted : TT vs -> TT vs
  contracted (Bind fc x (Lam lfc rig info ty) sc) = case contracted sc of
    app@(App _ f (Local _ _ Z _)) => fromMaybe (Bind fc x (Lam lfc rig info (contracted ty)) app) (shrink f (Drop Refl))
    sc' => Bind fc x (Lam lfc rig info (contracted ty)) sc'
  contracted (Bind fc x b sc) = Bind fc x (binderContracted b) (contracted sc)
  contracted (App fc f a) = App fc (contracted f) (contracted a)
  contracted (As fc side a p) = As fc side (contracted a) (contracted p)
  contracted (TDelayed fc r t) = TDelayed fc r (contracted t)
  contracted (TDelay fc r t a) = TDelay fc r (contracted t) (contracted a)
  contracted (TForce fc r t) = TForce fc r (contracted t)
  contracted (Erased fc (Dotted t)) = Erased fc (Dotted (contracted t))
  contracted t = t

  -- A binder's type, and a `let`'s value. What a binder's implicitness
  -- holds is no part any reading takes.
  binderContracted : TTBinder (TT vs) -> TTBinder (TT vs)
  binderContracted (Lam fc rig info ty) = Lam fc rig info (contracted ty)
  binderContracted (Let fc rig v ty) = Let fc rig (contracted v) (contracted ty)
  binderContracted (Pi fc rig info ty) = Pi fc rig info (contracted ty)
  binderContracted (PVar fc rig info ty) = PVar fc rig info (contracted ty)
  binderContracted (PLet fc rig v ty) = PLet fc rig (contracted v) (contracted ty)
  binderContracted (PVTy fc rig ty) = PVTy fc rig (contracted ty)

||| A type argument as data instances compare them: up to eta, and with
||| a type-level function and the lambda of its one clause as one
||| argument. Elaboration writes a family as `f` in one type and as `\x =>
||| f x` in another, at any depth (`(c ** as ** Positive g c as)` holds
||| `\as => Positive g c as` under the lambda over `c`), so the argument
||| is contracted (`contracted`) before anything else reads it: the
||| contracted form is the one each of them has without knowing a
||| family's arity, which expanding would need, and it is taken before
||| the indices are erased (`Types.eraseIndices`), which would leave
||| `\as => Positive _ _ _`, no longer a redex. A lambda's domain is no
||| part of the comparison (`Keys.write`). Elaboration also leaves a
||| type-level function's name in one type and its clause in another
||| (`Printed`, and `\n => (Fin n -> Nat) -> Nat -> String`), including
||| where the name is an argument of another type (`List (AltF Printed
||| _)`): the clause is inlined where the name stands, when that clause is
||| a function type, and is contracted too. An applied name is left to
||| normalisation, and so is an alias of a data type: normalisation has
||| already made those one type.
export
canonicalTypeArg : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core ClosedTerm
canonicalTypeArg tm = contracted <$> walk False (contracted tm)
  where
    -- Reduced to a name, rather than staying a lambda over its clause.
    etaContracted : TT vars -> Bool
    etaContracted (Bind _ _ (Lam {}) sc) = etaContracted sc
    etaContracted (Ref _ Func _) = True
    etaContracted _ = False

    -- A function type, under the lambdas of the clause. `Printed n` is
    -- `(Fin n -> Nat) -> Nat -> String`. An alias of a data type
    -- (`Scopeable a = List a`) is already that data type once normalised.
    hasPi : TT vars -> Bool
    hasPi (Bind _ _ (Pi {}) _) = True
    hasPi (Bind _ _ (Lam {}) sc) = hasPi sc
    hasPi (App _ f a) = hasPi f || hasPi a
    hasPi _ = False

    normaliseClause : {vs : _} -> FC -> TT vs -> Core (Maybe ClosedTerm)
    normaliseClause fc body = do
      let written = wrapLams fc body
      -- A name with no argument (`Scope = List Name`) is already reduced
      -- by ordinary normalisation wherever it is applied. Inlining it
      -- here turns a parameter into a value at one site only.
      case written of
        Bind _ _ (Lam {}) _ => do
          nf <- normaliseClosed written
          -- Quoting can put the name back; the clause is kept as written.
          let chosen = if etaContracted nf then written else nf
          pure (if hasPi chosen then Just chosen else Nothing)
        _ => pure Nothing

    -- The lambda of a type-level function's one clause, or nothing when
    -- the name is not such a function.
    clause : FC -> Name -> Core (Maybe ClosedTerm)
    clause fc n = do
      defs <- get Ctxt
      Just gdef <- lookupCtxtExact n (gamma defs)
        | Nothing => pure Nothing
      -- The type as written is enough for `Nat -> Type`. A name for one
      -- (`VarSet : Scoped`) needs the normalised type, and that lookup is
      -- the uncommon case.
      yes <- if isTypeLike (type gdef) then pure True else computesType gdef
      if yes then case definition gdef of
             PMDef _ _ _ _ [(_ ** (_, _, body))] => normaliseClause fc body
             PMDef _ _ (STerm _ body) _ _ => normaliseClause fc body
             _ => pure Nothing
        else pure Nothing

    -- `head` is the function of an application: that name is left to
    -- normalisation, and only its arguments are inlined. Replacing an
    -- applied name with its clause and not reducing the application is
    -- a different type than the reduced one. The clause inlined is not
    -- walked: it is already the form elaboration uses, and walking it
    -- would inline the names it mentions into types that were left as
    -- names, so that a call would no longer match its function.
    walk : Bool -> TT vars -> Core (TT vars)
    walk head (Ref fc Func n) =
      if head then pure (Ref fc Func n) else do
        Nothing <- clause fc n
          | Just lam => pure (embedClosed lam)
        pure (Ref fc Func n)
    walk _ (App fc f a) = App fc <$> walk True f <*> walk False a
    walk _ (Meta fc n i args) = Meta fc n i <$> each args
      where
        each : List (TT vars) -> Core (List (TT vars))
        each [] = pure []
        each (t :: ts) = (::) <$> walk False t <*> each ts
    walk _ (TDelayed fc r t) = TDelayed fc r <$> walk False t
    walk _ (TDelay fc r ty a) = TDelay fc r <$> walk False ty <*> walk False a
    walk _ (TForce fc r t) = TForce fc r <$> walk False t
    walk _ (As fc s p q) = As fc s <$> walk False p <*> walk False q
    walk _ tm = pure tm

------------------------------------------------------------------------------
-- Computations on runtime values, cut
------------------------------------------------------------------------------

||| A runtime variable in a term closed for normalisation: a reference to a
||| definition that does not exist, which no reduction looks into.
runtimeVariable : ClosedTerm
runtimeVariable = Ref EmptyFC Func (MN "idris-mlir-runtime" 0)

isRuntimeVariable : TT vs -> Bool
isRuntimeVariable (Ref _ _ (MN "idris-mlir-runtime" _)) = True
isRuntimeVariable _ = False

||| An argument a lambda applied to it binds, in the scope of the cut term:
||| as written, whether it mentions a runtime variable, and as cut where it
||| is written.
record Arg (ws : Scope) where
  constructor MkArg
  written : TT ws
  runtime : Bool
  cutForm : Lazy (Core (TT ws))

weakenArg : Arg ws -> Arg (x :: ws)
weakenArg a = MkArg (weaken a.written) a.runtime (weaken <$> a.cutForm)

||| What each variable of a term being cut (`vs`) stands for in the cut
||| term (`ws`): a variable of a binder the cut keeps, or of the scope it
||| started in; or the argument a lambda applied to it binds.
data CutEnv : Scope -> Scope -> Type where
  ||| A closed term's, in any scope.
  Closed : CutEnv [] ws
  ||| Every variable stands for itself.
  Same : CutEnv vs vs
  ||| A binder kept.
  Keep : CutEnv vs ws -> CutEnv (x :: vs) (x :: ws)
  ||| A lambda applied, its variable bound to the argument.
  Apply : Arg ws -> CutEnv vs ws -> CutEnv (x :: vs) ws

||| A binder kept: where every variable stands for itself, it does too.
keep : CutEnv vs ws -> CutEnv (x :: vs) (x :: ws)
keep Same = Same
keep env = Keep env

||| What a variable stands for in the cut term.
data Bound : Scope -> Type where
  AVar : TT ws -> Bound ws
  AnArg : Arg ws -> Bound ws

weakenBound : Bound ws -> Bound (x :: ws)
weakenBound (AVar t) = AVar (weaken t)
weakenBound (AnArg a) = AnArg (weakenArg a)

boundAt : CutEnv vs ws -> FC -> (idx : Nat) -> (0 _ : IsVar n idx vs) -> Bound ws
boundAt Same fc idx v = AVar (Local fc Nothing idx v)
boundAt Closed _ _ First impossible
boundAt Closed _ _ (Later _) impossible
boundAt (Keep env) fc Z _ = AVar (Local fc Nothing Z First)
boundAt (Keep env) fc (S i) v = weakenBound (boundAt env fc i (dropLater v))
boundAt (Apply a env) fc Z _ = AnArg a
boundAt (Apply a env) fc (S i) v = boundAt env fc i (dropLater v)

mutual
  ||| A term in the scope of the cut term, as written.
  rename : CutEnv vs ws -> TT vs -> TT ws
  rename Same tm = tm
  rename Closed tm = embed tm
  rename env (Local fc _ idx v) = case boundAt env fc idx v of
    AVar t => t
    AnArg a => a.written
  rename env (Ref fc nt n) = Ref fc nt n
  rename env (Meta fc n i args) = Meta fc n i (renameAll env args)
  rename env (Bind fc x b sc) = Bind fc x (renameBinder env b) (rename (keep env) sc)
  rename env (App fc f a) = App fc (rename env f) (rename env a)
  rename env (As fc s a p) = As fc s (rename env a) (rename env p)
  rename env (TDelayed fc r t) = TDelayed fc r (rename env t)
  rename env (TDelay fc r t a) = TDelay fc r (rename env t) (rename env a)
  rename env (TForce fc r t) = TForce fc r (rename env t)
  rename env (PrimVal fc c) = PrimVal fc c
  rename env (Erased fc Placeholder) = Erased fc Placeholder
  rename env (Erased fc Impossible) = Erased fc Impossible
  rename env (Erased fc (Dotted t)) = Erased fc (Dotted (rename env t))
  rename env (TType fc u) = TType fc u

  renameAll : CutEnv vs ws -> List (TT vs) -> List (TT ws)
  renameAll env [] = []
  renameAll env (t :: ts) = rename env t :: renameAll env ts

  renamePi : CutEnv vs ws -> PiInfo (TT vs) -> PiInfo (TT ws)
  renamePi env Implicit = Implicit
  renamePi env Explicit = Explicit
  renamePi env AutoImplicit = AutoImplicit
  renamePi env (DefImplicit t) = DefImplicit (rename env t)

  renameBinder : CutEnv vs ws -> TTBinder (TT vs) -> TTBinder (TT ws)
  renameBinder env (Lam fc r i ty) = Lam fc r (renamePi env i) (rename env ty)
  renameBinder env (Let fc r v ty) = Let fc r (rename env v) (rename env ty)
  renameBinder env (Pi fc r i ty) = Pi fc r (renamePi env i) (rename env ty)
  renameBinder env (PVar fc r i ty) = PVar fc r (renamePi env i) (rename env ty)
  renameBinder env (PLet fc r v ty) = PLet fc r (rename env v) (rename env ty)
  renameBinder env (PVTy fc r ty) = PVTy fc r (rename env ty)

mutual
  ||| Does a term mention a runtime variable, itself or through an argument
  ||| a lambda binds?
  dependsOn : CutEnv vs ws -> TT vs -> Bool
  dependsOn Same tm = mentions isRuntimeVariable tm
  dependsOn env (Local fc _ idx v) = case boundAt env fc idx v of
    AVar _ => False
    AnArg a => a.runtime
  dependsOn env tm@(Ref _ _ _) = isRuntimeVariable tm
  dependsOn env (Meta _ _ _ args) = dependsOnAny env args
  dependsOn env (Bind _ _ b sc) = binderDependsOn env b || dependsOn (keep env) sc
  dependsOn env (App _ f a) = dependsOn env f || dependsOn env a
  dependsOn env (As _ _ _ p) = dependsOn env p
  dependsOn env (TDelayed _ _ t) = dependsOn env t
  dependsOn env (TDelay _ _ t a) = dependsOn env t || dependsOn env a
  dependsOn env (TForce _ _ t) = dependsOn env t
  dependsOn env _ = False

  dependsOnAny : CutEnv vs ws -> List (TT vs) -> Bool
  dependsOnAny env [] = False
  dependsOnAny env (t :: ts) = dependsOn env t || dependsOnAny env ts

  binderDependsOn : CutEnv vs ws -> TTBinder (TT vs) -> Bool
  binderDependsOn env (Lam _ _ _ ty) = dependsOn env ty
  binderDependsOn env (Let _ _ v ty) = dependsOn env ty || dependsOn env v
  binderDependsOn env (Pi _ _ _ ty) = dependsOn env ty
  binderDependsOn env (PVar _ _ _ ty) = dependsOn env ty
  binderDependsOn env (PLet _ _ v ty) = dependsOn env ty || dependsOn env v
  binderDependsOn env (PVTy _ _ ty) = dependsOn env ty

||| A function that does not match on its arguments: its parameters, the
||| first first, its body, and its number in the context.
plain : {auto c : Ref Ctxt Defs} -> Name -> Core (Maybe (vs ** (TT vs, Int)))
plain n = do
  defs <- get Ctxt
  let Just i = getNameID n (gamma defs)
    | Nothing => pure Nothing
  Just def <- lookupCtxtExact (Resolved i) (gamma defs)
    | Nothing => pure Nothing
  case definition def of
    PMDef _ pargs (STerm _ body) _ _ => pure (Just (pargs ** (body, i)))
    _ => pure Nothing

||| Does a definition compute a type?
typeFunction : {auto c : Ref Ctxt Defs} -> Name -> Core Bool
typeFunction n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => pure False
  computesType def

||| Whether a term with this head is cut by cutting its arguments, keeping
||| the head, so that it is cut applied to more arguments as its cut
||| applied to theirs: a constructor, a type constructor, a function that
||| computes a type.
keepsHead : {auto c : Ref Ctxt Defs} -> TT ws -> Core Bool
keepsHead (Ref _ (DataCon _ _) _) = pure True
keepsHead (Ref _ (TyCon _) _) = pure True
keepsHead (Ref _ Func n) = typeFunction n
keepsHead _ = pure False

||| The parameters of a plain function, bound to the arguments it is
||| applied to, cut where they are written, and the arguments past them.
boundParams : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 acc : SizeAccessible w) -> (vs : Scope) ->
              List (TT ws) -> Maybe (CutEnv vs ws, List (Arg ws))

mutual
  ||| A computation on a runtime variable in a term, cut (`cutRuntime`),
  ||| with what each of its variables stands for, on the path of plain
  ||| functions unfolded on the way to the term. It ends, lexicographically
  ||| in the functions not yet unfolded on the path and the term: an
  ||| unfolding puts a function on the path, and every other step goes to a
  ||| part of the term, an argument's cut suspended where it is written.
  cut : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 acc : SizeAccessible w) ->
        CutEnv vs ws -> TT vs -> Core (TT ws)
  cut w acc env tm = cutApplied w acc env tm []

  ||| A term applied to arguments, cut: as written, unless it or an
  ||| argument mentions a runtime variable.
  cutApplied : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 acc : SizeAccessible w) ->
               CutEnv vs ws -> TT vs -> List (Arg ws) -> Core (TT ws)
  cutApplied w acc env tm args =
    if dependsOn env tm || any (.runtime) args
       then spine w acc env tm args
       else pure (foldl (App EmptyFC) (rename env tm) (map (.written) args))

  argOf : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          CutEnv vs ws -> TT vs -> Arg ws
  argOf w acc env a = MkArg (rename env a) (dependsOn env a) (cut w acc env a)

  ||| The head of an application, with its arguments, cut. The
  ||| accessibility proof is erased, and every clause matches its one
  ||| constructor: no alternative is chosen by it.
  spine : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          CutEnv vs ws -> TT vs -> List (Arg ws) -> Core (TT ws)
  spine w acc@(Access _) env (App _ f a) args = spine w acc env f (argOf w acc env a :: args)
  spine w acc@(Access _) env (Bind _ _ (Lam {}) sc) (a :: args) = cutApplied w acc (Apply a env) sc args
  spine w acc@(Access _) env (Bind fc x b sc) [] = Bind fc x <$> binder w acc env b <*> cut w acc (keep env) sc
  spine w acc@(Access _) env (TDelayed fc r t) [] = TDelayed fc r <$> cut w acc env t
  spine w (Access _) env (Local fc _ idx v) [] = case boundAt env fc idx v of
    AVar t => pure t
    AnArg a => a.cutForm
  spine w (Access _) env (Local fc _ idx v) args@(_ :: _) = case boundAt env fc idx v of
    AVar _ => pure (Erased fc Placeholder)
    AnArg a => appliedArg a args
  spine w (Access _) env tm@(Ref fc (DataCon _ _) _) args = foldl (App fc) (rename env tm) <$> cutArgs args
  spine w (Access _) env tm@(Ref fc (TyCon _) _) args = foldl (App fc) (rename env tm) <$> cutArgs args
  spine w acc@(Access rec) env tm@(Ref fc Func n) args =
    if !(typeFunction n)
       then foldl (App fc) (rename env tm) <$> cutArgs args
       -- A function that does not match on its arguments runs nothing on
       -- the value (`(.)` in `(PiInfo . Term) vars`): it is unfolded, and
       -- what it calls is cut in turn.
       else do
         Just (pargs ** (body, i)) <- plain n
           | Nothing => pure (Erased fc Placeholder)
         defs <- get Ctxt
         let Just (Element w' less) = enter (gamma defs) (Resolved i) w
           | Nothing => pure (Erased fc Placeholder)
         given <- cutArgs args
         let Just (env', rest) = boundParams w' (rec w' less) pargs given
           | Nothing => pure (Erased fc Placeholder)
         cutApplied w' (rec w' less) env' body rest
  spine w (Access _) env _ _ = pure (Erased EmptyFC Placeholder)

  ||| An argument a lambda or a plain function binds, applied in turn: the
  ||| argument's cut applied to theirs, when it keeps its head
  ||| (`keepsHead`); otherwise a computation through a value, and cut.
  appliedArg : {auto c : Ref Ctxt Defs} -> Arg ws -> List (Arg ws) -> Core (TT ws)
  appliedArg a args = do
    True <- keepsHead (getFn a.written)
      | False => pure (Erased EmptyFC Placeholder)
    f <- a.cutForm
    foldl (App EmptyFC) f <$> cutArgs args

  cutArgs : List (Arg ws) -> Core (List (TT ws))
  cutArgs [] = pure []
  cutArgs (a :: as) = do
    t <- a.cutForm
    (t ::) <$> cutArgs as

  binder : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           CutEnv vs ws -> TTBinder (TT vs) -> Core (TTBinder (TT ws))
  binder w acc env (Lam fc r i ty) = Lam fc r (renamePi env i) <$> cut w acc env ty
  binder w acc env (Let fc r val ty) = Let fc r <$> cut w acc env val <*> cut w acc env ty
  binder w acc env (Pi fc r i ty) = Pi fc r (renamePi env i) <$> cut w acc env ty
  binder w acc env (PVar fc r i ty) = PVar fc r (renamePi env i) <$> cut w acc env ty
  binder w acc env (PLet fc r val ty) = PLet fc r <$> cut w acc env val <*> cut w acc env ty
  binder w acc env (PVTy fc r ty) = PVTy fc r <$> cut w acc env ty

-- Each parameter is the argument as cut, which the body cuts again where
-- it stands, on the path that has unfolded the function.
boundParams w acc [] given = Just (Closed, map (\t => MkArg t (mentions isRuntimeVariable t) (cut w acc Same t)) given)
boundParams w acc (_ :: vs) (t :: given) =
  map (\(env, rest) => (Apply (MkArg t (mentions isRuntimeVariable t) (cut w acc Same t)) env, rest))
      (boundParams w acc vs given)
boundParams w acc (_ :: _) [] = Nothing

||| A type in which no computation is run on a runtime variable: what is
||| known of one is its constructors, as written, so a constructor or a type
||| constructor applied to one stays, and any other call to one, a
||| computation of a value, is unknown (`Erased`), as a runtime argument's
||| shape is read (`skeleton`). A computation on a value nothing is known of
||| can only be stuck, or never end: a parser's, built of closures that call
||| one another, unfolds without end once normalised under them. A function
||| that does not match on its arguments runs nothing on the value
||| (`(PiInfo . Term) vars`): it is unfolded, and what it calls is cut in
||| turn, except a function already unfolded on the way to it, whose
||| unfolding again would be a recursion that matches on nothing: that is
||| cut, so that the functions left to unfold are fewer at each unfolding.
||| The arguments are cut where they are written, before they are
||| substituted, so a function they apply is not counted as the unfolded
||| one's own. A function whose result is a type (`IsNothing m = m =
||| Nothing`) is no such computation: the type it gives is needed whatever
||| the value, and is cut inside instead. Nor is a lambda applied to one, a
||| type family at a value (`(\m => Vect m Int) n`), which binds its
||| variable to the value. A variable bound so that is applied in turn is
||| cut as what it is bound to is: a constructor's, a type's or a type
||| function's applied to more arguments, as those; a lambda's or a
||| function's that does not match, a computation through a value. A value
||| whose constructors are known (`Shaped`) is no runtime variable, and a
||| type still reduces on it.
cutRuntime : {auto c : Ref Ctxt Defs} -> TT vars -> Core (TT vars)
cutRuntime tm = cut start (sizeAccessible start) Same tm

||| The closed normal form of a term in scope, with type variables replaced by
||| their known values and every runtime variable by `Erased`, once every
||| computation on one is cut (`cutRuntime`). A solved metavariable is
||| filled in first: it stands applied to every variable in scope where it
||| was made, runtime ones too, which its solution need not use. A
||| definition that computes a type unfolds whatever its visibility
||| (`normaliseTypes`): Idris's plain `normalise` keeps a `private` function
||| of another module as it is (a type-level function such as
||| Data.SortedMap's `delType`), which is a module boundary, not a value.
||| Any other unfolds as Idris's own normalisation unfolds it: a value whose
||| definition its module keeps to itself stays as it is (a parser's, whose
||| closures, normalised, would unfold without end).
export
closeNormalise : {auto c : Ref Ctxt Defs} -> {vars : Scope} ->
                 FC -> List (VarInfo a) -> TT vars -> Core ClosedTerm
closeNormalise fc env tm = do
  closed <- solved (betaAll (wrapLams fc tm) (reverse (map value env)))
  normaliseClosed !(cutRuntime closed)
  where
    value : VarInfo a -> ClosedTerm
    value (TypeValue t) = t
    value (Static t _) = t
    value (Shaped _ _ _ s) = s
    value (Runtime {}) = runtimeVariable
