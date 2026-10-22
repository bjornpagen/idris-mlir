-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2026 Bjorn Pagen
||| What a program written over Idris's compiler asks of it and the
||| program's totality checker cannot follow, stated once, here.
|||
||| The frontend of idris-mlir is such a program, and total: every
||| recursion of its own is structural or well founded, and Idris checks
||| it. It also calls this compiler, which is covering, and the checker
||| follows each call into it: an operation whose own recursion the checker
||| cannot follow (decoding a definition from its TTC, a traversal through
||| a higher-order map, the elaborator) would make every function of the
||| program that reaches it partial. Each such operation is one field of
||| one value, `host`, the one place such a program trusts this compiler:
||| its theorem is that every operation named here returns. The evaluator
||| and the elaborator are here for good, since Idris's theory is not
||| strongly normalizing and the elaborator runs what types compute, and
||| so is the termination check that normalises as it goes; every other
||| field is here until the function it names is total, and then it is
||| deleted and its callers call the function. An operation the checker
||| can follow is called directly and is never here. A field is one
||| operation at one type, so that each goes on its own.
|||
||| The same value states the one thing such a program trusts of what the
||| evaluator returns, which no proof of the program's can reach: that a
||| normal form it gives is a reduct of the term it was given, by the steps
||| `Reduces` declares, reading the definitions the context holds. That is
||| the trust Idris's own type checker rests on, and a program that proves
||| its readings of terms sound against `Reduces` needs no check, when it
||| runs, that the evaluator agreed with it.
module Idris.Host

import Core.Case.CaseBuilder
import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.Env
import Core.Normalise
import Core.Termination
import Core.TT
import Idris.CommandLine
import Idris.ModTree
import Idris.Package
import Idris.REPL.Common
import Idris.REPL.Opts
import Idris.SetOptions
import Idris.Syntax

import Data.DPair
import Data.List.Elem
import Libraries.Data.List.SizeOf

%default total
%prefix_record_projections off

------------------------------------------------------------------------------
-- The reduction the evaluator performs
------------------------------------------------------------------------------

-- What follows declares, as a relation, every step Idris's evaluator takes
-- on a term, so that a reader can prove a reading of what it returns sound
-- step by step. The static fragment a program reads as values (types and
-- dictionaries) is reduced by four of them: under heads (the congruences),
-- beta of a family (`Beta`), a definition's leaf (`Leaf`, of which a
-- projection is one: its tree takes the record's constructor apart), and a
-- solved unknown (`Solved`). The others (`Zeta`, `Primitive`, `ForceDelay`,
-- `AsPattern`) are the rest of what the evaluator does, declared so that the
-- trust below is true of every term it is given. Every relation is blind to
-- locations: the evaluator gives a node it rebuilds the location of a
-- neighbour, which no step of the language decides.

||| That a context defines a name as a global definition. Only `host`
||| holds one: from its lookup (`definition`) and in what its evaluator
||| returns, so a step that unfolds a name unfolds the definition a reader
||| of the same context finds.
export
data Defines : Defs -> Name -> GlobalDef -> Type where
  InContext : Defines defs n d

||| What a primitive operation computes from its arguments, as the
||| evaluator's table of primitives gives it. Only the evaluator's
||| derivations hold one: a reader learns nothing of a primitive's result
||| from it, and says what it assumes.
export
data Computes : PrimFn arity -> List (Term vars) -> Term vars -> Type where
  Computed : Computes op args v

||| A term as a head applied to arguments, the first argument first,
||| whatever the locations of its applications.
public export
data Spine : Term vars -> (head : Term vars) -> List (Term vars) -> Type where
  Head : Spine h h []
  Applied : Spine f h args -> Spine (App fc f a) h (args ++ [a])

||| The form a scrutinee shows to a match: itself, or what a dotted term
||| stands for, which the evaluator matches through.
public export
data Shows : Term vars -> Term vars -> Type where
  Itself : Shows t t
  ThroughDot : Shows t u -> Shows (Erased fc (Dotted t)) u

||| A definition's arguments as its tree's scope binds them: the first
||| argument applied is the first name of the scope.
public export
0 bindArguments : (args : List (Term vars)) -> (ns : Scope) ->
                  length args = length ns -> SubstEnv ns vars
bindArguments [] [] _ = []
bindArguments (a :: as) (n :: ns) same = a :: bindArguments as ns (cong pred same)
bindArguments [] (_ :: _) Refl impossible
bindArguments (_ :: _) [] Refl impossible

||| A constructor's fields as an alternative's names bind them, in front of
||| the scope the alternative extends.
public export
0 bindFields : (fields : List (Term vars)) -> (ns : List Name) ->
               length fields = length ns -> SubstEnv ds vars ->
               SubstEnv (Scope.addInner ds ns) vars
bindFields [] [] _ env = env
bindFields (f :: fs) (n :: ns) same env = f :: bindFields fs ns (cong pred same) env
bindFields [] (_ :: _) Refl _ impossible
bindFields (_ :: _) [] Refl _ impossible

||| The leaf a case tree chooses for the values of its scope. The
||| scrutinee's form picks an alternative whose pattern it shows, its
||| pattern's variables bound to the scrutinee's parts; the evaluator takes
||| the first such alternative, and this takes any, which every reader that
||| reads a tree by its leaves reads the same.
public export
data Chooses : SubstEnv args vars -> CaseTree args -> Term vars -> Type where
  AtLeaf : Chooses env (STerm i rhs) (substs (mkSizeOf args) env (embed rhs))
  ByConstructor : {0 p : IsVar nm idx args} ->
                  Shows (Var.index env (MkVar p)) s ->
                  Spine s (Ref rfc nt h) fields ->
                  Elem (ConCase cn tag cargs sc) alts ->
                  (0 same : length fields = length cargs) ->
                  Chooses (bindFields fields cargs same env) sc v ->
                  Chooses env (Case idx p ty alts) v
  ||| A primitive type, matched by its name.
  ByPrimitiveType : {0 p : IsVar nm idx args} ->
                    Shows (Var.index env (MkVar p)) (PrimVal fc c) ->
                    Elem (ConCase cn tag [] sc) alts ->
                    Chooses env sc v ->
                    Chooses env (Case idx p ty alts) v
  ||| The type of types, matched by its name.
  ByUniverse : {0 p : IsVar nm idx args} ->
               Shows (Var.index env (MkVar p)) (TType fc u) ->
               Elem (ConCase cn tag [] sc) alts ->
               Chooses env sc v ->
               Chooses env (Case idx p ty alts) v
  ||| A function type, matched as the arrow of its domain and its
  ||| codomain abstracted over the domain.
  ByArrow : {0 p : IsVar nm idx args} ->
            Shows (Var.index env (MkVar p)) (Bind fc x (Pi pfc r e dom) cod) ->
            Elem (ConCase cn tag [dn, cn'] sc) alts ->
            Chooses (dom :: Bind fc x (Lam pfc r e dom) cod :: env) sc v ->
            Chooses env (Case idx p ty alts) v
  ByDelay : {0 p : IsVar nm idx args} ->
            Shows (Var.index env (MkVar p)) (TDelay fc d dty arg) ->
            Elem (DelayCase tyn argn sc) alts ->
            Chooses (dty :: arg :: env) sc v ->
            Chooses env (Case idx p ty alts) v
  ByConstant : {0 p : IsVar nm idx args} ->
               Shows (Var.index env (MkVar p)) (PrimVal fc c) ->
               Elem (ConstCase c sc) alts ->
               Chooses env sc v ->
               Chooses env (Case idx p ty alts) v
  ByDefault : Elem (DefaultCase sc) alts ->
              Chooses env sc v ->
              Chooses env (Case idx p ty alts) v

||| A step of the evaluator at the root of a term.
public export
data Contracts : Defs -> Term vars -> Term vars -> Type where
  ||| A family, a lambda, applied to an argument.
  Beta : Contracts defs (App fc (Bind bfc x (Lam lfc c p ty) sc) a) (subst a sc)
  ||| A `let`, its value substituted.
  Zeta : Contracts defs (Bind fc x (Let lfc c val ty) sc) (subst val sc)
  ||| A name the context defines by a case tree, applied to as many
  ||| arguments as the tree's scope binds: the leaf the tree chooses.
  Leaf : Spine t (Ref rfc Func n) args ->
         (0 _ : Defines defs n d) ->
         (0 _ : definition d = PMDef info ns tree clauses pats) ->
         (0 same : length args = length ns) ->
         Chooses (bindArguments args ns same) tree v ->
         Contracts defs t v
  ||| A solved unknown, applied to its scope and to what follows: its
  ||| solution's leaf, applied to the rest.
  Solved : Spine t (Meta mfc m i scope) more ->
           (0 _ : scope ++ more = args ++ rest) ->
           (0 _ : Defines defs (Resolved i) d) ->
           (0 _ : definition d = PMDef info ns tree clauses pats) ->
           (0 same : length args = length ns) ->
           Chooses (bindArguments args ns same) tree v ->
           Contracts defs t (apply mfc v rest)
  ||| A primitive operation, applied to as many arguments as it takes.
  Primitive : Spine t (Ref rfc Func n) args ->
              (0 _ : Defines defs n d) ->
              (0 _ : definition d = Builtin {arity} op) ->
              (0 _ : length args = arity) ->
              (0 _ : Computes op args v) ->
              Contracts defs t v
  ||| A delay forced.
  ForceDelay : Contracts defs (TForce fc r (TDelay dfc d ty a)) a
  ||| An as pattern, its pattern kept.
  AsPattern : Contracts defs (As fc s n t) t

mutual
  ||| What the evaluator can make of a term: steps at its root and under
  ||| every node, in sequence, each node free to take a new location.
  public export
  data Reduces : Defs -> Term vars -> Term vars -> Type where
    Then : Reduces defs t u -> Reduces defs u v -> Reduces defs t v
    Contract : Contracts defs t u -> Reduces defs t u
    ALocal : Reduces defs (Local fc l idx p) (Local fc' l idx p)
    ARef : Reduces defs (Ref fc nt n) (Ref fc' nt n)
    AMeta : AllReduce defs scope scope' ->
            Reduces defs (Meta fc m i scope) (Meta fc' m i scope')
    ABind : BinderReduces defs b b' -> Reduces defs sc sc' ->
            Reduces defs (Bind fc x b sc) (Bind fc' x b' sc')
    AnApp : Reduces defs f f' -> Reduces defs a a' ->
            Reduces defs (App fc f a) (App fc' f' a')
    AnAs : Reduces defs n n' -> Reduces defs t t' ->
           Reduces defs (As fc s n t) (As fc' s n' t')
    ADelayed : Reduces defs t t' ->
               Reduces defs (TDelayed fc r t) (TDelayed fc' r t')
    ADelay : Reduces defs ty ty' -> Reduces defs a a' ->
             Reduces defs (TDelay fc d ty a) (TDelay fc' d ty' a')
    AForce : Reduces defs t t' ->
             Reduces defs (TForce fc r t) (TForce fc' r t')
    APrimVal : Reduces defs (PrimVal fc c) (PrimVal fc' c)
    AnErased : WhyReduces defs w w' ->
               Reduces defs (Erased fc w) (Erased fc' w')
    AType : Reduces defs (TType fc u) (TType fc' u)

  public export
  data AllReduce : Defs -> List (Term vars) -> List (Term vars) -> Type where
    NoneLeft : AllReduce defs [] []
    Each : Reduces defs t t' -> AllReduce defs ts ts' ->
           AllReduce defs (t :: ts) (t' :: ts')

  public export
  data BinderReduces : Defs -> Binder (Term vars) -> Binder (Term vars) -> Type where
    ALam : PiReduces defs p p' -> Reduces defs ty ty' ->
           BinderReduces defs (Lam fc c p ty) (Lam fc' c p' ty')
    ALet : Reduces defs val val' -> Reduces defs ty ty' ->
           BinderReduces defs (Let fc c val ty) (Let fc' c val' ty')
    APi : PiReduces defs p p' -> Reduces defs ty ty' ->
          BinderReduces defs (Pi fc c p ty) (Pi fc' c p' ty')
    APVar : PiReduces defs p p' -> Reduces defs ty ty' ->
            BinderReduces defs (PVar fc c p ty) (PVar fc' c p' ty')
    APLet : Reduces defs val val' -> Reduces defs ty ty' ->
            BinderReduces defs (PLet fc c val ty) (PLet fc' c val' ty')
    APVTy : Reduces defs ty ty' ->
            BinderReduces defs (PVTy fc c ty) (PVTy fc' c ty')

  public export
  data PiReduces : Defs -> PiInfo (Term vars) -> PiInfo (Term vars) -> Type where
    AnImplicit : PiReduces defs Implicit Implicit
    AnExplicit : PiReduces defs Explicit Explicit
    AnAutoImplicit : PiReduces defs AutoImplicit AutoImplicit
    ADefImplicit : Reduces defs t t' ->
                   PiReduces defs (DefImplicit t) (DefImplicit t')

  public export
  data WhyReduces : Defs -> WhyErased (Term vars) -> WhyErased (Term vars) -> Type where
    APlaceholder : WhyReduces defs Placeholder Placeholder
    AnImpossible : WhyReduces defs Impossible Impossible
    ADotted : Reduces defs t t' -> WhyReduces defs (Dotted t) (Dotted t')

||| A closed term's normal form, as the evaluator gave it, with the steps
||| that reach it from the term, which no reader pays for.
public export
record Reduct (defs : Defs) (t : ClosedTerm) where
  constructor MkReduct
  value : ClosedTerm
  0 steps : Reduces defs t value

-- The trust, at quantity 0, so it costs nothing when a program runs: it is
-- applied to what the evaluator returned, at the four normalisers below, and
-- to two readings of one context.
0 trusted : a
trusted = believe_me ()

||| A context defines a name once: two readings of it agree.
export
0 definedOnce : Defines defs n d -> Defines defs n d' -> d = d'
definedOnce _ _ = trusted

-- An evaluator's normal form of a closed term, with the steps that reach it.
reduct : {auto c : Ref Ctxt Defs} ->
         (Defs -> Env Term [] -> ClosedTerm -> Core ClosedTerm) ->
         (defs : Defs) -> (t : ClosedTerm) -> Core (Reduct defs t)
reduct normaliser defs t
    = do v <- normaliser defs Env.empty t
         pure (MkReduct v trusted)

------------------------------------------------------------------------------
-- The operations
------------------------------------------------------------------------------

||| The operations of Idris's compiler whose termination a program over it
||| takes on trust, each named as this compiler names it.
public export
record Host where
  constructor MkHost

  -- The evaluator: Idris's theory is not strongly normalizing, so a
  -- normal form is trusted to exist; every caller first proves that each
  -- definition its term refers to ends, which is what that trust rests on.
  -- Each gives a closed term's normal form with the steps that reach it.

  ||| `Core.Normalise.normalise`.
  normalise : {auto c : Ref Ctxt Defs} ->
              (defs : Defs) -> (t : ClosedTerm) -> Core (Reduct defs t)
  ||| `Core.Normalise.normaliseTypes`.
  normaliseTypes : {auto c : Ref Ctxt Defs} ->
                   (defs : Defs) -> (t : ClosedTerm) -> Core (Reduct defs t)
  ||| `Core.Normalise.normaliseHoles`.
  normaliseHoles : {auto c : Ref Ctxt Defs} ->
                   (defs : Defs) -> (t : ClosedTerm) -> Core (Reduct defs t)
  ||| `Core.Normalise.normaliseAll`, every definition unfolded whatever its
  ||| visibility.
  normaliseAll : {auto c : Ref Ctxt Defs} ->
                 (defs : Defs) -> (t : ClosedTerm) -> Core (Reduct defs t)
  ||| `Core.Context.lookupCtxtExact`, with the evidence that the context
  ||| defines the name so, for a reader to meet the steps that unfold it.
  definition : (defs : Defs) -> (n : Name) ->
               Core (Maybe (Subset GlobalDef (Defines defs n)))

  -- Termination.

  ||| `Core.Termination.checkTerminating`.
  checkTerminating : {auto c : Ref Ctxt Defs} -> FC -> Name -> Core Terminating

  -- The driver.

  ||| `Idris.ModTree.buildMain`: the elaborator, on a main file and what it
  ||| imports, from a fresh context and fresh elaboration states.
  buildMain : {auto c : Ref Ctxt Defs} -> {auto s : Ref Syn SyntaxInfo} ->
              {auto o : Ref ROpts REPLOpts} -> String -> Core (List Error)
  ||| `Idris.Package.processPackageOpts`: the elaborator, on a package.
  processPackageOpts : {auto c : Ref Ctxt Defs} -> {auto s : Ref Syn SyntaxInfo} ->
                       {auto o : Ref ROpts REPLOpts} -> {auto p : Ref PostS PostSession} ->
                       List CLOpt -> Core ControlFlow

  -- The error printer.

  ||| `Idris.REPL.Common.emitError`: the evaluator again, since an error is
  ||| printed with the holes of its terms normalised (`normaliseHoles`).
  emitError : {auto c : Ref Ctxt Defs} -> {auto o : Ref ROpts REPLOpts} ->
              {auto s : Ref Syn SyntaxInfo} -> Error -> Core ()

||| Idris's compiler, as a program over it calls it where the checker
||| cannot follow it. The one trust of such a program in this compiler,
||| stated once: each of these returns, and what the evaluator returns is a
||| reduct of what it was given.
export
host : Host
host = assert_total (MkHost
  { normalise = reduct normalise
  , normaliseTypes = reduct normaliseTypes
  , normaliseHoles = reduct normaliseHoles
  , normaliseAll = reduct normaliseAll
  , definition = \defs, n =>
      map (\d => Element d InContext) <$> lookupCtxtExact n (gamma defs)
  , checkTerminating
  , buildMain
  , processPackageOpts
  , emitError
  })
