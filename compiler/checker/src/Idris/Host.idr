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
||| The same module states the one thing such a program trusts of what the
||| evaluator gives and reads, which no proof of the program's can reach.
||| Everything is said of one context, frozen once it is complete
||| (`Frozen`): an immutable value of every loaded definition by the entry
||| its name resolves to, so that two readings of a name read one
||| definition, which is proved here (`definedOnce`). What a normaliser
||| gives is a reduct of the term it was given by the steps `Reduces`
||| declares for that normaliser, and normal for them (`Reduct`); a
||| definition's type and case tree, read through the context's
||| accessors, are the ones the evaluator reads, one of each (`typeOnce`,
||| `treeOnce`); every term a term reduces to reduces on to the term's
||| normal form (`reachesNormalForm`); the steps that reduce a term reduce
||| it with values put in for its bound names (`substitutes`); and values
||| put in for names that stand for a scope's variables are put in for the
||| variables (`substitutesMarkers`). That is the trust
||| Idris's own type checker rests on, which decides conversion by
||| comparing normal forms, and a program that proves its readings of terms
||| sound against `Reduces` needs no check, when it runs, that the
||| evaluator agreed with it. Beside it stand a fact of the context, that it
||| makes one entry for each full name and records no resolved name as one,
||| so that two resolved names name one entry exactly when their full names
||| agree (`fullNameSameEntry`); and a fact of the hosts that run this
||| compiler, that what the evaluator's table of primitives computes stays
||| within a bound that grows with its arguments' sizes (`computedWithin`).
module Idris.Host

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.Env
import Core.Normalise
import Core.Primitives
import Core.Termination
import Core.TT
import Core.TT.Stored
import Core.Value
import Idris.CommandLine
import Idris.ModTree
import Idris.Package
import Idris.REPL.Common
import Idris.REPL.Opts
import Idris.SetOptions
import Idris.Syntax

import Data.DPair
import Data.Nat
import Data.Vect
import Decidable.Equality

import Libraries.Data.IntMap
import Libraries.Data.List.SizeOf
import Libraries.Data.WithDefault

%default total
%prefix_record_projections off

------------------------------------------------------------------------------
-- The trust
------------------------------------------------------------------------------

-- The trust, at quantity 0, so it costs nothing when a program runs. It is
-- applied only where a statement is a fact of Idris's compiler that no
-- proof follows: of the evaluator, which runs in `Core`, to what the
-- normalisers give (`reduct`), to a term's reducts and its normal form
-- (`reachesNormalForm`) and to reduction with values put in
-- (`substitutes`); of the accessors it reads definitions through, to the
-- terms they read (`typeOnce`, `treeOnce`); of the substitution no proof
-- reaches, to putting values in for names (`substitutesMarkers`); of the
-- context, to the full names its entries hold (`oneEntryPerName`,
-- `fullNameUnresolved`); and of the hosts' primitives, to what the table
-- of primitives computes (`computedWithin`).
0 trusted : a
trusted = believe_me ()

0 justSame : Just x = Just y -> x = y
justSame Refl = Refl

0 nothingIsJust : Nothing = Just x -> Void
nothingIsJust Refl impossible

------------------------------------------------------------------------------
-- The frozen context
------------------------------------------------------------------------------

||| The context the evaluator reads, frozen once it is complete: every
||| definition Idris's lookup gives for an entry the context has made, each
||| decoded once and stored as a definition read from a TTC is, in an
||| immutable map by entry, beside the definitions record the normalisers
||| run on. Every statement below speaks of one such value, so it speaks of
||| one context. Only `host` makes one, once the program and everything it
||| imports are loaded; nothing changes the context after, so what the
||| evaluator reads from the record is what the map holds.
|||
||| The normalisers run on this value alone, so a program that holds it
||| never holds the live context. Idris's evaluator unfolds what the record
||| it is given defines, and reads only its session's options (what it
||| logs) through a reference to a context; that reference is made here,
||| once, holding the record, and nothing the normalisers run writes it.
export
record Frozen where
  constructor MkFrozen
  defs : Defs
  entries : IntMap GlobalDef
  reference : Ref Ctxt Defs

||| The definitions record a frozen context was made from, which the
||| normalisers run on.
export
defsOf : Frozen -> Defs
defsOf ctx = ctx.defs

||| A frozen context's definitions, by entry.
export
entriesOf : Frozen -> IntMap GlobalDef
entriesOf ctx = ctx.entries

||| A name resolves to an entry: the one Idris's lookup turns it into
||| (`getNameID`), a resolved name its own.
export
data Resolves : Frozen -> Name -> Int -> Type where
  ResolvedAs : (0 _ : getNameID n (gamma (defsOf ctx)) = Just i) -> Resolves ctx n i

||| A name resolves to one entry.
export
0 resolvesOnce : Resolves ctx n i -> Resolves ctx n j -> i = j
resolvesOnce (ResolvedAs found) (ResolvedAs found') = justSame (trans (sym found) found')

||| A resolved name resolves to its own entry.
export
0 resolvedItself : Resolves ctx (Resolved i) i
resolvedItself = ResolvedAs Refl

||| The entry a name resolves to, or the evidence that it resolves to none.
public export
data Resolution : Frozen -> Name -> Type where
  ResolvedTo : (i : Int) -> (0 _ : Resolves ctx n i) -> Resolution ctx n
  NotInContext : (0 _ : (i : Int) -> Not (Resolves ctx n i)) -> Resolution ctx n

0 unresolvable : getNameID n (gamma (defsOf ctx)) = Nothing ->
                 (i : Int) -> Not (Resolves ctx n i)
unresolvable none i (ResolvedAs found) = nothingIsJust (trans (sym none) found)

||| The entry a name resolves to, as the evaluator's lookup finds it.
export
resolveIn : (ctx : Frozen) -> (n : Name) -> Resolution ctx n
resolveIn ctx n with (getNameID n (gamma (defsOf ctx))) proof found
  _ | Just i = ResolvedTo i (ResolvedAs found)
  _ | Nothing = NotInContext (unresolvable found)

||| That a frozen context defines a name as a global definition: the one at
||| the entry the name resolves to. Only this module makes one, by reading
||| the context (`definitionIn`), so a step that unfolds a name unfolds the
||| definition a reader of the same context finds.
export
data Defines : Frozen -> Name -> GlobalDef -> Type where
  AtEntry : (0 _ : Resolves ctx n i) ->
            (0 _ : IntMap.lookup i (entriesOf ctx) = Just d) ->
            Defines ctx n d

-- What one entry holds, read through another name of the entry.
0 atEntry : Resolves ctx n i -> Resolves ctx n j ->
            IntMap.lookup j (entriesOf ctx) = Just d ->
            IntMap.lookup i (entriesOf ctx) = Just d
atEntry r r' held = trans (cong (\k => IntMap.lookup k (entriesOf ctx)) (resolvesOnce r r')) held

||| A context defines a name once: two definitions of it are the one at the
||| entry the name resolves to.
export
0 definedOnce : Defines ctx n d -> Defines ctx n d' -> d = d'
definedOnce (AtEntry r held) (AtEntry r' held') = justSame (trans (sym held) (atEntry r r' held'))

||| The entry a definition of a name is at.
export
0 entryOf : Defines ctx n d -> (i : Int ** Resolves ctx n i)
entryOf (AtEntry {i} r _) = (i ** r)

||| What a frozen context defines a name as, at the entry the name resolves
||| to, so that a reader that also needs the entry resolves the name once;
||| or the evidence that it defines it as nothing: a name it does not
||| resolve, or an entry no definition is at.
public export
data Definition : Frozen -> Name -> Type where
  DefinedAs : (i : Int) -> (0 _ : Resolves ctx n i) ->
              (d : GlobalDef) -> (0 _ : Defines ctx n d) -> Definition ctx n
  NotDefined : (0 _ : (d : GlobalDef) -> Not (Defines ctx n d)) -> Definition ctx n

0 undefinedWhere : ((i : Int) -> Not (Resolves ctx n i)) ->
                   (d : GlobalDef) -> Not (Defines ctx n d)
undefinedWhere none d (AtEntry r _) = none _ r

0 emptyEntry : Resolves ctx n i -> IntMap.lookup i (entriesOf ctx) = Nothing ->
               (d : GlobalDef) -> Not (Defines ctx n d)
emptyEntry r none d (AtEntry r' held) = nothingIsJust (trans (sym none) (atEntry r r' held))

definedAt : (ctx : Frozen) -> (i : Int) -> (0 _ : Resolves ctx n i) -> Definition ctx n
definedAt ctx i r with (IntMap.lookup i (entriesOf ctx)) proof held
  _ | Just d = DefinedAs i r d (AtEntry r held)
  _ | Nothing = NotDefined (emptyEntry r held)

||| The definition a frozen context gives a name, with the entry it is at:
||| one resolution of the name and one pure read of an immutable value.
export
definitionIn : (ctx : Frozen) -> (n : Name) -> Definition ctx n
definitionIn ctx n = case resolveIn ctx n of
  ResolvedTo i r => definedAt ctx i r
  NotInContext none => NotDefined (undefinedWhere none)

||| Two names resolve to one entry: they name one definition, whichever
||| spelling each has (a full name, a resolved one).
public export
data SameEntry : Frozen -> Name -> Name -> Type where
  OneEntry : (0 _ : Resolves ctx m i) -> (0 _ : Resolves ctx n i) -> SameEntry ctx m n

||| Whether two names name one entry, with the evidence either way.
public export
data Compared : Frozen -> Name -> Name -> Type where
  BothAt : (0 _ : SameEntry ctx m n) -> Compared ctx m n
  Apart : (0 _ : Not (SameEntry ctx m n)) -> Compared ctx m n

0 apart : Resolves ctx m i -> Resolves ctx n j -> Not (i = j) -> Not (SameEntry ctx m n)
apart r r' differ (OneEntry s s') = differ (trans (resolvesOnce r s) (sym (resolvesOnce r' s')))

0 unresolvedLeft : ((i : Int) -> Not (Resolves ctx m i)) -> Not (SameEntry ctx m n)
unresolvedLeft none (OneEntry s _) = none _ s

0 unresolvedRight : ((i : Int) -> Not (Resolves ctx n i)) -> Not (SameEntry ctx m n)
unresolvedRight none (OneEntry _ s) = none _ s

||| Whether two names name one entry of a frozen context.
export
compareEntries : (ctx : Frozen) -> (m, n : Name) -> Compared ctx m n
compareEntries ctx m n = case resolveIn ctx m of
  NotInContext none => Apart (unresolvedLeft none)
  ResolvedTo i r => case resolveIn ctx n of
    NotInContext none => Apart (unresolvedRight none)
    ResolvedTo j r' => case decEq i j of
      Yes same => BothAt (OneEntry r (rewrite same in r'))
      No differ => Apart (apart r r' differ)

------------------------------------------------------------------------------
-- A definition's terms, as the accessors read them
------------------------------------------------------------------------------

||| A definition's type, as the context's accessor reads it, live or
||| stored alike. Only `host` makes one, by reading the type (`typeOf`).
export
data TypeOf : GlobalDef -> ClosedTerm -> Type where
  ReadType : TypeOf d ty

||| A pattern-matching definition's case tree, as the context's accessor
||| reads it from the definition's body, live or stored alike. Only `host`
||| makes one, by reading the tree (`treeOf`).
export
data TreeOf : Body args -> CaseTree args -> Type where
  ReadTree : TreeOf body tree

-- The accessors run in `Core`, so no proof follows them to the terms they
-- give; they read a definition's terms as the evaluator reads them, a
-- stored term decoded from the definition's frozen arena, so each reads
-- one term of a definition.

||| A definition has one type.
export
0 typeOnce : TypeOf d ty -> TypeOf d ty' -> ty = ty'
typeOnce _ _ = trusted

||| A body has one case tree.
export
0 treeOnce : TreeOf body tree -> TreeOf body tree' -> tree = tree'
treeOnce _ _ = trusted

------------------------------------------------------------------------------
-- What each normaliser evaluates
------------------------------------------------------------------------------

-- The evaluator's options, as each of the four normalisers sets them and as
-- a delay changes them, are three choices, each a type, so that a step
-- states the choice it needs and a normal form the steps it has none of.

||| Which definitions an evaluation unfolds by name (`evalAll`,
||| `evalTypes`): those the program's visibility lets it see; those, and
||| every definition whose type is a type, an implementation kept folded;
||| or every one.
public export
data Unfolding = ByVisibility | ForTypes | Unrestricted

||| Whether an evaluation runs every definition it unfolds, or only holes'
||| solutions and the definitions that always reduce, keeping a `let` and
||| computing no primitive but `believe_me` (`holesOnly`), as every
||| normaliser does under a delay.
public export
data Running = RunsAll | RunsHoles

||| Whether an evaluation removes an as pattern or keeps it (`removeAs`).
public export
data AsPatterns = RemovesAs | KeepsAs

||| What one evaluation does.
public export
record Evaluation where
  constructor MkEvaluation
  unfolding : Unfolding
  running : Running
  asPatterns : AsPatterns

||| The evaluation of a delay's parts, which a normaliser quotes running
||| only holes.
public export
delayed : Evaluation -> Evaluation
delayed (MkEvaluation u r a) = MkEvaluation u RunsHoles a

||| The four normalisers, by what each one's result is a normal form of.
||| None is a head normal form: each quotes under every binder and
||| argument, and under a delay runs only holes.
public export
data NormalForm
  = ||| `normalise`: every reduction the program's visibility allows.
    OfNormalise
  | ||| `normaliseTypes`: those, and every definition whose type is a type,
    ||| an implementation kept folded but where a match takes it apart.
    OfNormaliseTypes
  | ||| `normaliseHoles`: holes' solutions and definitions that always
    ||| reduce, lambdas applied, a `let` and an as pattern kept.
    OfNormaliseHoles
  | ||| `normaliseAll`: every definition, whatever its visibility.
    OfNormaliseAll

||| The evaluation a normaliser runs.
public export
evaluationOf : NormalForm -> Evaluation
evaluationOf OfNormalise = MkEvaluation ByVisibility RunsAll RemovesAs
evaluationOf OfNormaliseTypes = MkEvaluation ForTypes RunsAll RemovesAs
evaluationOf OfNormaliseHoles = MkEvaluation ByVisibility RunsHoles KeepsAs
evaluationOf OfNormaliseAll = MkEvaluation Unrestricted RunsAll RemovesAs

||| A definition the program's visibility lets the evaluator unfold, from
||| the namespaces the context was frozen in (`reducibleInAny`).
public export
data Visible : Frozen -> GlobalDef -> Type where
  InView : (0 _ : reducibleInAny (currentNS (defsOf ctx) :: nestedNS (defsOf ctx))
                                 (fullname d) (collapseDefault (visibility d)) = True) ->
           Visible ctx d

||| An implementation: a definition whose type, past its arguments, is an
||| interface's, the record type declared with a unique search.
public export
data Implementation : Frozen -> GlobalDef -> Type where
  IsImplementation : (0 _ : TypeOf d ty) ->
                     (0 _ : resultHead ty = HeadFamily tn) ->
                     (0 _ : Defines ctx tn td) ->
                     (0 _ : definition td = TCon tarity tps tds tflags tms tcs tdet) ->
                     (0 _ : uniqueAuto tflags = True) ->
                     Implementation ctx d

||| A type's head that computes a type: a universe, or a definition of no
||| arguments whose one leaf computes one. The evaluator follows each alias
||| once; an alias that leads back to itself computes no type, and no
||| derivation goes round it.
public export
data ComputesType : Frozen -> ResultHead -> Type where
  IsUniverse : ComputesType ctx HeadUniverse
  ThroughAlias : (0 _ : Defines ctx n a) ->
                 (0 _ : definition a = PMDef info [] body) ->
                 (0 _ : TreeOf body (STerm i leaf)) ->
                 ComputesType ctx (resultHead leaf) ->
                 ComputesType ctx (HeadAlias n)

||| Whether an evaluation unfolds a definition it meets by name or as a
||| hole's solution (`evalRef`): the program's visibility; that, or a type
||| computed, but never an implementation, when it keeps implementations
||| folded; or any definition.
public export
data Admits : Frozen -> Unfolding -> GlobalDef -> Type where
  AnyDefinition : Admits ctx Unrestricted d
  AVisibleOne : Visible ctx d -> Admits ctx ByVisibility d
  AVisibleType : Visible ctx d -> (0 _ : Not (Implementation ctx d)) -> Admits ctx ForTypes d
  ATypeComputing : (0 _ : TypeOf d ty) -> ComputesType ctx (resultHead ty) ->
                   (0 _ : Not (Implementation ctx d)) -> Admits ctx ForTypes d

||| How an evaluation reached a pattern-matching definition: by its name,
||| or as a hole's solution, applied.
public export
data Reaching = ByName | BySolving

||| Whether an evaluation runs a pattern-matching definition it unfolds
||| (`evalDef`): every one, or, running only holes, a hole's solution and a
||| definition that always reduces.
public export
data Evaluates : Running -> PMDefInfo -> Reaching -> Type where
  RunsEvery : Evaluates RunsAll info via
  AlwaysReduces : (0 _ : alwaysReduce info = True) -> Evaluates RunsHoles info via
  SolvesHole : Evaluates RunsHoles info BySolving

------------------------------------------------------------------------------
-- The forms the evaluator reads
------------------------------------------------------------------------------

||| A term as a head applied to arguments, the first argument first,
||| whatever the locations of its applications.
public export
data Spine : Term vars -> (head : Term vars) -> List (Term vars) -> Type where
  Head : Spine h h []
  Applied : Spine f h args -> Spine (App fc f a) h (args ++ [a])

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

||| What a dotted term stands for, through every dot, which the evaluator
||| matches through.
public export
data Shows : Term vars -> Term vars -> Type where
  Itself : Shows t t
  ThroughDot : Shows t u -> Shows (Erased fc (Dotted t)) u

||| A value a default alternative matches: one the evaluator calls
||| concrete, its head fixed whatever reduces under it.
public export
data Concrete : Term vars -> Type where
  IsConstructor : Spine s (Ref fc (DataCon tag arity) n) args -> Concrete s
  IsFamily : Spine s (Ref fc (TyCon arity) n) args -> Concrete s
  IsConstant : Concrete (PrimVal fc c)
  IsBinder : Concrete (Bind fc x b sc)
  IsUniverseValue : Concrete (TType fc u)
  IsDelay : Concrete (TDelay fc d ty a)

||| An alternative that does not match a scrutinee's form, so that the
||| evaluator tries the next one: a match the scrutinee can never meet
||| whatever reduces under it. Any other pair is stuck, and the evaluator
||| tries no alternative after it.
public export
data Misses : Frozen -> Term vars -> CaseAlt args -> Type where
  ||| A constructor of another tag.
  OtherTag : Spine s (Ref rfc (DataCon tag' arity) h) fields ->
             (0 _ : Not (tag = tag')) ->
             Misses ctx s (ConCase cn tag cargs sc)
  ||| A type constructor at another entry.
  OtherFamily : Spine s (Ref rfc (TyCon arity) h) fields ->
                (0 _ : Not (SameEntry ctx h cn)) ->
                Misses ctx s (ConCase cn tag cargs sc)
  ||| A constant, which a primitive type's name of another type does not
  ||| match, nor an alternative that binds fields.
  OtherPrimitiveType : (0 _ : Not (map PrT (isConstantType (dropNS cn)) = Just c)) ->
                       Misses ctx (PrimVal fc c) (ConCase cn tag [] sc)
  PrimitiveFields : Misses ctx (PrimVal fc c) (ConCase cn tag (f :: fs) sc)
  ||| The type of types, which an alternative of another name does not
  ||| match, nor one that binds fields.
  NotTheUniverse : (0 _ : Not (knownRoot cn = Just KType)) ->
                   Misses ctx (TType fc u) (ConCase cn tag [] sc)
  UniverseFields : Misses ctx (TType fc u) (ConCase cn tag (f :: fs) sc)
  ||| A function type, which an alternative of another name does not match,
  ||| nor one that binds other than its domain and codomain.
  NotTheArrow : (0 _ : Not (knownRoot cn = Just KArrow)) ->
                Misses ctx (Bind fc x (Pi pfc r e dom) cod) (ConCase cn tag [dn, cn'] sc)
  ArrowFields : (0 _ : Not (length cargs = 2)) ->
                Misses ctx (Bind fc x (Pi pfc r e dom) cod) (ConCase cn tag cargs sc)
  ||| Another constant.
  OtherConstant : (0 _ : Not (c = c')) -> Misses ctx (PrimVal fc c') (ConstCase c sc)

||| A value `believe_me` gives another type unchanged: a constructor
||| applied, a type constructor applied, a constant, or a universe.
public export
data Coercible : Term vars -> Type where
  CoercesConstructor : Spine v (Ref fc (DataCon tag arity) n) args -> Coercible v
  CoercesFamily : Spine v (Ref fc (TyCon arity) n) args -> Coercible v
  CoercesConstant : Coercible (PrimVal fc c)
  CoercesUniverse : Coercible (TType fc u)

||| The constants of a primitive's arguments, when there are as many as it
||| takes and each is one.
public export
constantsOf : (n : Nat) -> List (Term vars) -> Maybe (Vect n Constant)
constantsOf Z [] = Just []
constantsOf (S k) (PrimVal _ c :: ts) = map (c ::) (constantsOf k ts)
constantsOf _ _ = Nothing

||| What the evaluator's table of primitives (`getOp`) gives an operation
||| on constants, when it gives a constant: the table itself, so that a
||| primitive's result here is the one the evaluator computes.
export covering
0 tableOf : {arity : Nat} -> PrimFn arity -> Vect arity Constant -> Maybe Constant
tableOf op cs = case getOp {vars = []} op (map (NPrimVal EmptyFC) cs) of
                     Just (NPrimVal _ c) => Just c
                     _ => Nothing

||| What a primitive operation computes from its arguments: a function of
||| the operation and the arguments. An operation on constants gives the
||| constant the evaluator's table gives them, where an evaluation runs
||| everything; `believe_me` gives its value unchanged, wherever it runs.
public export
data Computes : Running -> PrimFn arity -> List (Term vars) -> Term vars -> Type where
  OnConstants : (0 _ : constantsOf arity args = Just cs) ->
                (0 _ : tableOf op cs = Just c) ->
                Computes RunsAll op args (PrimVal fc c)
  BelievedMe : Coercible v -> Computes running BelieveMe [a, b, v] v

||| A head the evaluator applies to nothing: the arguments it is given are
||| dropped.
public export
data DropsArguments : Term vars -> Type where
  DropsAtPlaceholder : DropsArguments (Erased fc Placeholder)
  DropsAtImpossible : DropsArguments (Erased fc Impossible)
  DropsAtConstant : DropsArguments (PrimVal fc c)
  DropsAtUniverse : DropsArguments (TType fc u)
  DropsAtDelay : DropsArguments (TDelay fc d ty a)

||| A binder the evaluator does not apply but evaluates its scope with the
||| arguments it is given: every binder but a lambda, and a `let` only where
||| it is kept.
public export
data Floats : Evaluation -> Binder (Term vars) -> Type where
  PiFloats : Floats ev (Pi fc c p ty)
  PVarFloats : Floats ev (PVar fc c p ty)
  PLetFloats : Floats ev (PLet fc c val ty)
  PVTyFloats : Floats ev (PVTy fc c ty)
  LetFloats : (0 _ : ev.running = RunsHoles) -> Floats ev (Let fc c val ty)

------------------------------------------------------------------------------
-- The reduction the evaluator performs
------------------------------------------------------------------------------

-- What follows declares, as a relation, every step Idris's evaluator takes
-- on a term under each evaluation, so that a reader can prove a reading of
-- what it returns sound step by step, and that what it returns is normal
-- for exactly those steps. The static fragment a program reads as values
-- (types and dictionaries) is reduced by four of them: under heads (the
-- congruences), beta of a family (`Beta`), a definition's leaf (`Unfold`,
-- of which a projection is one: its tree takes the record's constructor
-- apart), and a solved unknown (`Solve`). The others are the rest of what
-- the evaluator does, declared so that the trust is true of every term it
-- is given. Every relation is blind to locations, and to a variable's hint
-- that it is a `let`: the evaluator gives a node it rebuilds the location
-- of a neighbour, which no step of the language decides.

mutual
  ||| The form a case's scrutinee shows its alternatives: itself, through
  ||| its dots; or, where an evaluation keeps implementations folded and
  ||| the scrutinee is one applied, the implementation unfolded once and
  ||| reduced, through its dots. That is the one place such an evaluation
  ||| unfolds an implementation, and it does not unfold another the first
  ||| gives.
  public export
  data Scrutinised : Evaluation -> Frozen -> Term vars -> Term vars -> Type where
    AsItIs : Shows t s -> Scrutinised ev ctx t s
    ImplementationUnfolded : Spine t (Ref rfc Func n) args ->
                             (0 _ : Defines ctx n d) ->
                             (0 _ : ev.unfolding = ForTypes) ->
                             (0 _ : Implementation ctx d) ->
                             (0 _ : Visible ctx d) ->
                             (0 _ : definition d = PMDef info ns body) ->
                             (0 _ : Evaluates ev.running info ByName) ->
                             (0 _ : TreeOf body tree) ->
                             (0 same : length args = length ns) ->
                             Chooses ev ctx (bindArguments args ns same) tree u ->
                             Reduces ev ctx u w ->
                             Shows w s ->
                             Scrutinised ev ctx t s

  ||| The leaf a case tree chooses for the values of its scope, as the
  ||| evaluator walks it: at each case, the alternative it picks for the
  ||| form the scrutinee shows, its pattern's variables bound to the
  ||| scrutinee's parts.
  public export
  data Chooses : Evaluation -> Frozen -> SubstEnv args vars -> CaseTree args -> Term vars -> Type where
    ToLeaf : Chooses ev ctx env (STerm i rhs) (substs (mkSizeOf args) env (embed rhs))
    ByCase : {0 p : IsVar nm idx args} ->
             Scrutinised ev ctx (Var.index env (MkVar p)) s ->
             Picks ev ctx env s alts v ->
             Chooses ev ctx env (Case idx p ty alts) v

  ||| The first alternative that matches, as the evaluator tries them in
  ||| order: every alternative before the one taken misses the scrutinee,
  ||| so one form picks one alternative, a default among them.
  public export
  data Picks : Evaluation -> Frozen -> SubstEnv args vars -> Term vars ->
               List (CaseAlt args) -> Term vars -> Type where
    Takes : Matches ev ctx env s alt v -> Picks ev ctx env s (alt :: alts) v
    Skips : Misses ctx s alt -> Picks ev ctx env s alts v -> Picks ev ctx env s (alt :: alts) v

  ||| An alternative that matches a scrutinee's form, and the leaf its
  ||| subtree chooses.
  public export
  data Matches : Evaluation -> Frozen -> SubstEnv args vars -> Term vars ->
                 CaseAlt args -> Term vars -> Type where
    ||| A constructor applied: the alternative's name is the scrutinee's
    ||| head, by the entry both resolve to.
    ByConstructor : Spine s (Ref rfc (DataCon tag arity) h) fields ->
                    (0 _ : SameEntry ctx h cn) ->
                    (0 same : length fields = length cargs) ->
                    Chooses ev ctx (bindFields fields cargs same env) sc v ->
                    Matches ev ctx env s (ConCase cn tag cargs sc) v
    ||| A type constructor applied, matched by its entry.
    ByFamily : Spine s (Ref rfc (TyCon arity) h) fields ->
               (0 _ : SameEntry ctx h cn) ->
               (0 same : length fields = length cargs) ->
               Chooses ev ctx (bindFields fields cargs same env) sc v ->
               Matches ev ctx env s (ConCase cn tag cargs sc) v
    ||| A primitive type, matched by its name.
    ByPrimitiveType : (0 _ : map PrT (isConstantType (dropNS cn)) = Just c) ->
                      Chooses ev ctx env sc v ->
                      Matches ev ctx env (PrimVal fc c) (ConCase cn tag [] sc) v
    ||| The type of types, matched by its name.
    ByUniverse : (0 _ : knownRoot cn = Just KType) ->
                 Chooses ev ctx env sc v ->
                 Matches ev ctx env (TType fc u) (ConCase cn tag [] sc) v
    ||| A function type, matched as the arrow of its domain and its
    ||| codomain abstracted over the domain.
    ByArrow : (0 _ : knownRoot cn = Just KArrow) ->
              Chooses ev ctx (dom :: Bind fc x (Lam pfc r e dom) cod :: env) sc v ->
              Matches ev ctx env (Bind fc x (Pi pfc r e dom) cod) (ConCase cn tag [dn, cn'] sc) v
    ByDelay : Chooses ev ctx (dty :: arg :: env) sc v ->
              Matches ev ctx env (TDelay fc d dty arg) (DelayCase tyn argn sc) v
    ByConstant : Chooses ev ctx env sc v ->
                 Matches ev ctx env (PrimVal fc c) (ConstCase c sc) v
    ||| A default, of a concrete value: every alternative before it missed
    ||| (`Skips`).
    ByDefaultCase : Concrete s -> Chooses ev ctx env sc v ->
                    Matches ev ctx env s (DefaultCase sc) v

  ||| A step of the evaluator at the root of a term.
  public export
  data Contracts : Evaluation -> Frozen -> Term vars -> Term vars -> Type where
    ||| A family, a lambda, applied to an argument.
    Beta : Contracts ev ctx (App fc (Bind bfc x (Lam lfc c p ty) sc) a) (subst a sc)
    ||| A `let`, its value substituted, where an evaluation runs everything.
    Zeta : (0 _ : ev.running = RunsAll) ->
           Contracts ev ctx (Bind fc x (Let lfc c val ty) sc) (subst val sc)
    ||| A name the context defines by a case tree, applied to as many
    ||| arguments as the tree's scope binds, where the evaluation unfolds
    ||| and runs it: the leaf the tree chooses.
    Unfold : Spine t (Ref rfc Func n) args ->
             (0 _ : Defines ctx n d) ->
             (0 _ : Admits ctx ev.unfolding d) ->
             (0 _ : definition d = PMDef info ns body) ->
             (0 _ : Evaluates ev.running info ByName) ->
             (0 _ : TreeOf body tree) ->
             (0 same : length args = length ns) ->
             Chooses ev ctx (bindArguments args ns same) tree v ->
             Contracts ev ctx t v
    ||| A solved unknown, applied to its scope and to what follows: its
    ||| solution's leaf, applied to the rest.
    Solve : Spine t (Meta mfc m i scope) more ->
            (0 _ : scope ++ more = args ++ rest) ->
            (0 _ : Defines ctx (Resolved i) d) ->
            (0 _ : Admits ctx ev.unfolding d) ->
            (0 _ : definition d = PMDef info ns body) ->
            (0 _ : Evaluates ev.running info BySolving) ->
            (0 _ : TreeOf body tree) ->
            (0 same : length args = length ns) ->
            Chooses ev ctx (bindArguments args ns same) tree v ->
            Contracts ev ctx t (apply mfc v rest)
    ||| A primitive operation, applied to as many arguments as it takes.
    Primitive : Spine t (Ref rfc Func n) args ->
                (0 _ : Defines ctx n d) ->
                (0 _ : Admits ctx ev.unfolding d) ->
                (0 _ : definition d = Builtin {arity} op) ->
                (0 _ : length args = arity) ->
                Computes ev.running op args v ->
                Contracts ev ctx t v
    ||| A delay forced.
    ForceDelay : Contracts ev ctx (TForce fc r (TDelay dfc d ty a)) a
    ||| An as pattern, its pattern kept, where as patterns are removed.
    RemoveAs : (0 _ : ev.asPatterns = RemovesAs) -> Contracts ev ctx (As fc s n t) t
    ||| A kept as pattern applied: both its sides applied.
    FloatAs : (0 _ : ev.asPatterns = KeepsAs) ->
              Contracts ev ctx (App fc (As afc s n t) a) (As afc s (App fc n a) (App fc t a))
    ||| A binder the evaluator does not apply, applied: its scope applied.
    FloatBinder : Floats ev b ->
                  Contracts ev ctx (App fc (Bind bfc x b sc) a) (Bind bfc x b (App fc sc (weaken a)))
    ||| A lazy type applied: what it is lazy in applied.
    FloatDelayed : Contracts ev ctx (App fc (TDelayed dfc r t) a) (TDelayed dfc r (App fc t a))
    ||| A dotted term applied: what it stands for applied.
    FloatDot : Contracts ev ctx (App fc (Erased efc (Dotted t)) a) (Erased efc (Dotted (App fc t a)))
    ||| A head that drops what it is applied to, applied.
    DropApplied : DropsArguments f -> Contracts ev ctx (App fc f a) f
    ||| The type of types by its name, alone.
    TypeName : (0 _ : knownRoot n = Just KType) ->
               Contracts ev ctx (Ref fc (TyCon Z) n) (TType fc (MN (known Ktop) 0))
    ||| A primitive type by its name, alone: the constant that names it.
    ConstantTypeName : (0 _ : isConstantType n = Just pt) ->
                       Contracts ev ctx (Ref fc (TyCon Z) n) (PrimVal fc (PrT pt))

  ||| What an evaluation can make of a term: steps at its root and under
  ||| every node it evaluates under, in sequence, each node free to take a
  ||| new location; under a delay, only what an evaluation running holes
  ||| does.
  public export
  data Reduces : Evaluation -> Frozen -> Term vars -> Term vars -> Type where
    Then : Reduces ev ctx t u -> Reduces ev ctx u v -> Reduces ev ctx t v
    Contract : Contracts ev ctx t u -> Reduces ev ctx t u
    ALocal : Reduces ev ctx (Local fc l idx p) (Local fc' l' idx p)
    ARef : Reduces ev ctx (Ref fc nt n) (Ref fc' nt n)
    AMeta : AllReduce ev ctx scope scope' ->
            Reduces ev ctx (Meta fc m i scope) (Meta fc' m i scope')
    ABind : BinderReduces ev ctx b b' -> Reduces ev ctx sc sc' ->
            Reduces ev ctx (Bind fc x b sc) (Bind fc' x b' sc')
    AnApp : Reduces ev ctx f f' -> Reduces ev ctx a a' ->
            Reduces ev ctx (App fc f a) (App fc' f' a')
    AnAs : Reduces ev ctx n n' -> Reduces ev ctx t t' ->
           Reduces ev ctx (As fc s n t) (As fc' s n' t')
    ADelayed : Reduces ev ctx t t' ->
               Reduces ev ctx (TDelayed fc r t) (TDelayed fc' r t')
    ADelay : Reduces (delayed ev) ctx ty ty' -> Reduces (delayed ev) ctx a a' ->
             Reduces ev ctx (TDelay fc d ty a) (TDelay fc' d ty' a')
    AForce : Reduces ev ctx t t' ->
             Reduces ev ctx (TForce fc r t) (TForce fc' r t')
    APrimVal : Reduces ev ctx (PrimVal fc c) (PrimVal fc' c)
    AnErased : WhyReduces ev ctx w w' ->
               Reduces ev ctx (Erased fc w) (Erased fc' w')
    AType : Reduces ev ctx (TType fc u) (TType fc' u)

  public export
  data AllReduce : Evaluation -> Frozen -> List (Term vars) -> List (Term vars) -> Type where
    NoneLeft : AllReduce ev ctx [] []
    Each : Reduces ev ctx t t' -> AllReduce ev ctx ts ts' ->
           AllReduce ev ctx (t :: ts) (t' :: ts')

  public export
  data BinderReduces : Evaluation -> Frozen -> Binder (Term vars) -> Binder (Term vars) -> Type where
    ALam : PiReduces ev ctx p p' -> Reduces ev ctx ty ty' ->
           BinderReduces ev ctx (Lam fc c p ty) (Lam fc' c p' ty')
    ALet : Reduces ev ctx val val' -> Reduces ev ctx ty ty' ->
           BinderReduces ev ctx (Let fc c val ty) (Let fc' c val' ty')
    APi : PiReduces ev ctx p p' -> Reduces ev ctx ty ty' ->
          BinderReduces ev ctx (Pi fc c p ty) (Pi fc' c p' ty')
    APVar : PiReduces ev ctx p p' -> Reduces ev ctx ty ty' ->
            BinderReduces ev ctx (PVar fc c p ty) (PVar fc' c p' ty')
    APLet : Reduces ev ctx val val' -> Reduces ev ctx ty ty' ->
            BinderReduces ev ctx (PLet fc c val ty) (PLet fc' c val' ty')
    APVTy : Reduces ev ctx ty ty' ->
            BinderReduces ev ctx (PVTy fc c ty) (PVTy fc' c ty')

  public export
  data PiReduces : Evaluation -> Frozen -> PiInfo (Term vars) -> PiInfo (Term vars) -> Type where
    AnImplicit : PiReduces ev ctx Implicit Implicit
    AnExplicit : PiReduces ev ctx Explicit Explicit
    AnAutoImplicit : PiReduces ev ctx AutoImplicit AutoImplicit
    ADefImplicit : Reduces ev ctx t t' ->
                   PiReduces ev ctx (DefImplicit t) (DefImplicit t')

  public export
  data WhyReduces : Evaluation -> Frozen -> WhyErased (Term vars) -> WhyErased (Term vars) -> Type where
    APlaceholder : WhyReduces ev ctx Placeholder Placeholder
    AnImpossible : WhyReduces ev ctx Impossible Impossible
    ADotted : Reduces ev ctx t t' -> WhyReduces ev ctx (Dotted t) (Dotted t')

------------------------------------------------------------------------------
-- Normal forms
------------------------------------------------------------------------------

mutual
  ||| A step of an evaluation somewhere in a term: at its root, or under one
  ||| of the nodes `Reduces` steps under, where it steps.
  public export
  data Redex : Evaluation -> Frozen -> Term vars -> Type where
    AtRoot : Contracts ev ctx t u -> Redex ev ctx t
    InMeta : SomeRedex ev ctx scope -> Redex ev ctx (Meta fc m i scope)
    InBinder : BinderRedex ev ctx b -> Redex ev ctx (Bind fc x b sc)
    InBody : Redex ev ctx sc -> Redex ev ctx (Bind fc x b sc)
    InFunction : Redex ev ctx f -> Redex ev ctx (App fc f a)
    InArgument : Redex ev ctx a -> Redex ev ctx (App fc f a)
    InAsName : Redex ev ctx n -> Redex ev ctx (As fc s n t)
    InAsPattern : Redex ev ctx t -> Redex ev ctx (As fc s n t)
    InDelayed : Redex ev ctx t -> Redex ev ctx (TDelayed fc r t)
    InDelayType : Redex (delayed ev) ctx ty -> Redex ev ctx (TDelay fc d ty a)
    InDelayValue : Redex (delayed ev) ctx a -> Redex ev ctx (TDelay fc d ty a)
    InForce : Redex ev ctx t -> Redex ev ctx (TForce fc r t)
    InDot : Redex ev ctx t -> Redex ev ctx (Erased fc (Dotted t))

  public export
  data SomeRedex : Evaluation -> Frozen -> List (Term vars) -> Type where
    InFirst : Redex ev ctx t -> SomeRedex ev ctx (t :: ts)
    InRest : SomeRedex ev ctx ts -> SomeRedex ev ctx (t :: ts)

  public export
  data BinderRedex : Evaluation -> Frozen -> Binder (Term vars) -> Type where
    InLamImplicit : PiRedex ev ctx p -> BinderRedex ev ctx (Lam fc c p ty)
    InLamType : Redex ev ctx ty -> BinderRedex ev ctx (Lam fc c p ty)
    InLetValue : Redex ev ctx val -> BinderRedex ev ctx (Let fc c val ty)
    InLetType : Redex ev ctx ty -> BinderRedex ev ctx (Let fc c val ty)
    InPiImplicit : PiRedex ev ctx p -> BinderRedex ev ctx (Pi fc c p ty)
    InPiType : Redex ev ctx ty -> BinderRedex ev ctx (Pi fc c p ty)
    InPVarImplicit : PiRedex ev ctx p -> BinderRedex ev ctx (PVar fc c p ty)
    InPVarType : Redex ev ctx ty -> BinderRedex ev ctx (PVar fc c p ty)
    InPLetValue : Redex ev ctx val -> BinderRedex ev ctx (PLet fc c val ty)
    InPLetType : Redex ev ctx ty -> BinderRedex ev ctx (PLet fc c val ty)
    InPVTyType : Redex ev ctx ty -> BinderRedex ev ctx (PVTy fc c ty)

  public export
  data PiRedex : Evaluation -> Frozen -> PiInfo (Term vars) -> Type where
    InDefault : Redex ev ctx t -> PiRedex ev ctx (DefImplicit t)

||| A term an evaluation takes no step in: a normal form of it.
public export
0 Irreducible : Evaluation -> Frozen -> Term vars -> Type
Irreducible ev ctx t = Not (Redex ev ctx t)

||| A closed term's normal form, as a normaliser gave it, with the steps of
||| that normaliser's evaluation that reach it from the term and the
||| evidence that it takes none further, which no reader pays for.
public export
record Reduct (form : NormalForm) (ctx : Frozen) (t : ClosedTerm) where
  constructor MkReduct
  value : ClosedTerm
  0 steps : Reduces (evaluationOf form) ctx t value
  0 normal : Irreducible (evaluationOf form) ctx value

||| Every term a term reduces to reduces on to the term's normal form, by
||| the same normaliser's steps. That is the confluence of Idris's
||| evaluation of the terms its type checker accepts, in the form the type
||| checker rests on when it decides conversion by comparing normal forms:
||| a term and a term it reduces to are convertible, so they reach one
||| normal form. No proof of this module's reaches it.
export
0 reachesNormalForm : (r : Reduct form ctx t) -> Reduces (evaluationOf form) ctx t u ->
                      Reduces (evaluationOf form) ctx u r.value
reachesNormalForm _ _ = trusted

||| Reduction is closed under putting values in for bound names. No step
||| reads a reference to a bound name: each reads a function, a constructor
||| or a family through its kind and the entry it resolves to, or a form.
||| So the steps that take `t` to `u` take `t`, with the values put in for
||| those names, to `u` with them put in. That is the substitution lemma
||| of Idris's evaluation, which its type checker rests on whenever it
||| checks a definition used at its arguments. It is stated over this
||| compiler's `refsToLocals` and `substs`, whose definitions no proof of a
||| program over this compiler reaches.
export
0 substitutes : {ns : Scope} -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) ->
                Reduces ev ctx t u ->
                Reduces ev ctx (substs (mkSizeOf ns) vs (refsToLocals bs t))
                               (substs (mkSizeOf ns) vs (refsToLocals bs u))
substitutes _ _ _ = trusted

||| Normalising commutes with putting closed values in for bound names:
||| the normal form of a term with the values put in is the normal form of
||| its normal form with them put in. The steps to the term's normal form,
||| with the values put in, lead from the term with them put in to that
||| normal form with them put in, a reduct of the term with the values put
||| in, which so reduces on to its normal form (`reachesNormalForm`). With
||| that normal form's evidence that it is normal, the steps are a reduct
||| of the normal form with the values put in, which no normaliser runs to
||| give: `MkReduct s.value (normalisesThrough bs vs r s) s.normal`.
export
0 normalisesThrough : {ns : Scope} -> (bs : Bounds ns) -> (vs : SubstEnv ns []) ->
                      (r : Reduct form ctx t) ->
                      (s : Reduct form ctx (substs (mkSizeOf ns) vs (refsToLocals bs t))) ->
                      Reduces (evaluationOf form) ctx
                              (substs (mkSizeOf ns) vs (refsToLocals bs r.value)) s.value
normalisesThrough bs vs r s = reachesNormalForm s (substitutes bs vs r.steps)

||| Whether a set of bounds puts a local in for a name: whether the name is
||| equal to one it replaces, by Idris's equality of names, as
||| `refsToLocals` compares them.
public export
replaces : Bounds ns -> Name -> Bool
replaces None n = False
replaces (Add _ old bs) n = n == old || replaces bs n

||| Whether the names a set of bounds replaces are apart: each equal to none
||| after it, so that `refsToLocals` puts in for each name the local of its
||| own place.
public export
namesApart : Bounds ns -> Bool
namesApart None = True
namesApart (Add _ old bs) = not (replaces bs old) && namesApart bs

mutual
  ||| Whether a term names one of the names a set of bounds replaces where
  ||| `refsToLocals` would put a local in for it: in a bound reference or an
  ||| unknown.
  public export
  namesAny : Bounds ns -> Term vars -> Bool
  namesAny bs (Local fc l idx p) = False
  namesAny bs (Ref fc Bound n) = replaces bs n
  namesAny bs (Ref fc nt n) = False
  namesAny bs (Meta fc m i args) = replaces bs m || namesAnyIn bs args
  namesAny bs (Bind fc x b sc) = namesAnyInBinder bs b || namesAny bs sc
  namesAny bs (App fc f a) = namesAny bs f || namesAny bs a
  namesAny bs (As fc s n t) = namesAny bs n || namesAny bs t
  namesAny bs (TDelayed fc r t) = namesAny bs t
  namesAny bs (TDelay fc d ty a) = namesAny bs ty || namesAny bs a
  namesAny bs (TForce fc r t) = namesAny bs t
  namesAny bs (PrimVal fc c) = False
  namesAny bs (Erased fc (Dotted t)) = namesAny bs t
  namesAny bs (Erased fc _) = False
  namesAny bs (TType fc u) = False

  public export
  namesAnyIn : Bounds ns -> List (Term vars) -> Bool
  namesAnyIn bs [] = False
  namesAnyIn bs (t :: ts) = namesAny bs t || namesAnyIn bs ts

  public export
  namesAnyInBinder : Bounds ns -> Binder (Term vars) -> Bool
  namesAnyInBinder bs (Lam fc c p ty) = namesAnyInPi bs p || namesAny bs ty
  namesAnyInBinder bs (Let fc c val ty) = namesAny bs val || namesAny bs ty
  namesAnyInBinder bs (Pi fc c p ty) = namesAnyInPi bs p || namesAny bs ty
  namesAnyInBinder bs (PVar fc c p ty) = namesAnyInPi bs p || namesAny bs ty
  namesAnyInBinder bs (PLet fc c val ty) = namesAny bs val || namesAny bs ty
  namesAnyInBinder bs (PVTy fc c ty) = namesAny bs ty

  public export
  namesAnyInPi : Bounds ns -> PiInfo (Term vars) -> Bool
  namesAnyInPi bs (DefImplicit t) = namesAny bs t
  namesAnyInPi bs _ = False

||| A bound reference to each name a set of bounds replaces, the first
||| first: what stands for each variable of a scope, by the name of its
||| place, while a term over the scope is closed.
public export
markersOf : FC -> Bounds ns -> SubstEnv ns vars
markersOf fc None = []
markersOf fc (Add _ old bs) = Ref fc Bound old :: markersOf fc bs

||| Putting values in for names that stand for a scope's variables is
||| putting them in for the variables. A term over the scope, closed with a
||| reference to each name in for its variables (`markersOf`), those
||| references turned back into the variables (`refsToLocals`) and the
||| values put in for them, is the term with the values put in for its
||| variables, where the names are apart (`namesApart`) and the term names
||| none of them (`namesAny`): each reference finds its own name first,
||| since Idris's equality of names is reflexive and symmetric, and every
||| reference and unknown the term held stays as it was. That is the
||| substitution lemma of Idris's terms, which its type checker rests on
||| whenever it checks a definition used at its arguments, stated over this
||| compiler's `substs` and `refsToLocals`, whose definitions no proof of a
||| program over this compiler reaches.
export
0 substitutesMarkers : {ns : Scope} -> (bs : Bounds ns) -> (vs : SubstEnv ns vars) -> (t : Term ns) ->
                       namesApart bs = True -> namesAny bs t = False ->
                       substs (mkSizeOf ns) vs
                              (refsToLocals bs (substs (mkSizeOf ns) (markersOf {vars} fc bs) (embed t)))
                         = substs (mkSizeOf ns) vs (embed t)
substitutesMarkers _ _ _ _ _ = trusted

-- A normaliser's normal form of a closed term, on the frozen context
-- alone: its definitions record, and its own reference as the context the
-- evaluator reads its options through. With the steps that reach it and
-- the evidence that it is normal: what the evaluator gives, which is the
-- trust.
reduct : ({auto c : Ref Ctxt Defs} -> Defs -> Env Term [] -> ClosedTerm -> Core ClosedTerm) ->
         (ctx : Frozen) -> (t : ClosedTerm) -> Core (Reduct form ctx t)
reduct normaliser ctx t
    = do v <- normaliser {c = ctx.reference} (defsOf ctx) Env.empty t
         pure (MkReduct v trusted trusted)

------------------------------------------------------------------------------
-- How large a primitive's result is
------------------------------------------------------------------------------

||| An integer's magnitude.
public export
magnitudeOf : Integer -> Nat
magnitudeOf v = integerToNat (abs v)

||| How much a constant holds, by the measure that can grow: an integer's
||| magnitude, whatever its width; a string's characters; a double's text,
||| which is what tells doubles apart. A character, a primitive type and
||| the world hold nothing that grows.
public export
constantSize : Constant -> Nat
constantSize (I x) = magnitudeOf (cast x)
constantSize (I8 x) = magnitudeOf (cast x)
constantSize (I16 x) = magnitudeOf (cast x)
constantSize (I32 x) = magnitudeOf (cast x)
constantSize (I64 x) = magnitudeOf (cast x)
constantSize (BI x) = magnitudeOf x
constantSize (B8 x) = magnitudeOf (cast x)
constantSize (B16 x) = magnitudeOf (cast x)
constantSize (B32 x) = magnitudeOf (cast x)
constantSize (B64 x) = magnitudeOf (cast x)
constantSize (Str x) = length (unpack x)
constantSize (Ch _) = 0
constantSize (Db x) = length (unpack (show x))
constantSize (PrT _) = 0
constantSize WorldVal = 0

||| A bound on the size of a primitive's result over the sizes of its
||| arguments: a number, an argument's size, a sum, a product, or two to a
||| power. Each grows with the sizes (`resultBoundMonotone`), so what bounds
||| the arguments bounds the result.
public export
data SizeBound : Nat -> Type where
  AtMost : Nat -> SizeBound arity
  ArgumentSize : Fin arity -> SizeBound arity
  Summed : SizeBound arity -> SizeBound arity -> SizeBound arity
  Multiplied : SizeBound arity -> SizeBound arity -> SizeBound arity
  TwoToThe : SizeBound arity -> SizeBound arity

||| What a bound comes to at its arguments' sizes. Two to a size is past
||| what any machine holds, so a bound is read in proofs and never computed.
public export
0 atSizes : SizeBound arity -> Vect arity Nat -> Nat
atSizes (AtMost k) ss = k
atSizes (ArgumentSize i) ss = Vect.index i ss
atSizes (Summed a b) ss = atSizes a ss + atSizes b ss
atSizes (Multiplied a b) ss = atSizes a ss * atSizes b ss
atSizes (TwoToThe a) ss = power 2 (atSizes a ss)

||| 2^64: no fixed-width integer, whose widest width is 64 bits, wraps to
||| a value past it, and no double's text is that long.
public export
fixedWidth : SizeBound arity
fixedWidth = TwoToThe (AtMost 64)

||| The longest text of a double on the hosts that run this compiler: a
||| sign, 17 digits, a point and an exponent such as `e-308`, 24 characters
||| on each; and on the stock host, whose cast from String can read a
||| complex number into a Double, a real and an imaginary part that long
||| and an `i`.
public export
doubleText : Nat
doubleText = 49

||| A bound on each primitive's result as the evaluator's table (`tableOf`)
||| computes it. The table chooses by the constants it is given, not by the
||| type the primitive names, so each bound holds whatever constants the
||| operation meets:
||| - a sum, difference, product, quotient, remainder or negation of
|||   integers, or their bitwise and, or or xor, is no larger in magnitude
|||   than the sum or the product of theirs, a remainder than its divisor;
|||   a fixed-width result wrapped to its width is below 2^64, and so is a
|||   double's text;
||| - a shift moves a value by its amount, and by a negative amount the
|||   other way, as the stock host does at every width (`ash`), so it gives
|||   at most 2^amount times the value, or a wrapped value below 2^64;
||| - a comparison gives 0 or 1;
||| - a string operation gives a string of at most the characters it was
|||   given (one more for `strCons`), their count, or a character;
||| - a double's operation gives a double;
||| - a cast to Integer gives an integer's own value; a character's code or
|||   a finite double's integer part, each below 2^1024; or what a string
|||   reads: a literal in a base of at most 16, below 16^length, or on the
|||   stock host a decimal with a point or an exponent, a finite double;
||| - a cast to String gives an integer's sign and digits, at most its
|||   magnitude and one more, a character, or a double's own text;
||| - a cast to a fixed-width type gives the value, or wraps it below 2^64;
||| - `believe_me` gives its value unchanged;
||| - `crash` and a cast to the world compute nothing.
public export
boundOf : PrimFn arity -> SizeBound arity
boundOf (Add _) = Summed (Summed (ArgumentSize FZ) (ArgumentSize (FS FZ))) fixedWidth
boundOf (Sub _) = Summed (Summed (ArgumentSize FZ) (ArgumentSize (FS FZ))) fixedWidth
boundOf (Mul _) = Summed (Multiplied (ArgumentSize FZ) (ArgumentSize (FS FZ))) fixedWidth
boundOf (Div _) = Summed (ArgumentSize FZ) fixedWidth
boundOf (Mod _) = Summed (ArgumentSize (FS FZ)) fixedWidth
boundOf (Neg _) = Summed (ArgumentSize FZ) fixedWidth
boundOf (ShiftL _) = Summed (Multiplied (ArgumentSize FZ) (TwoToThe (ArgumentSize (FS FZ)))) fixedWidth
boundOf (ShiftR _) = Summed (Multiplied (ArgumentSize FZ) (TwoToThe (ArgumentSize (FS FZ)))) fixedWidth
boundOf (BAnd _) = Summed (Summed (ArgumentSize FZ) (ArgumentSize (FS FZ))) fixedWidth
boundOf (BOr _) = Summed (Summed (ArgumentSize FZ) (ArgumentSize (FS FZ))) fixedWidth
boundOf (BXOr _) = Summed (Summed (ArgumentSize FZ) (ArgumentSize (FS FZ))) fixedWidth
boundOf (Primitive.LT _) = AtMost 1
boundOf (Primitive.LTE _) = AtMost 1
boundOf (Primitive.EQ _) = AtMost 1
boundOf (Primitive.GTE _) = AtMost 1
boundOf (Primitive.GT _) = AtMost 1
boundOf StrLength = ArgumentSize FZ
boundOf StrHead = AtMost 0
boundOf StrTail = ArgumentSize FZ
boundOf StrIndex = AtMost 0
boundOf StrCons = Summed (AtMost 1) (ArgumentSize (FS FZ))
boundOf StrAppend = Summed (ArgumentSize FZ) (ArgumentSize (FS FZ))
boundOf StrReverse = ArgumentSize FZ
boundOf StrSubstr = ArgumentSize (FS (FS FZ))
boundOf DoubleExp = AtMost doubleText
boundOf DoubleLog = AtMost doubleText
boundOf DoublePow = AtMost doubleText
boundOf DoubleSin = AtMost doubleText
boundOf DoubleCos = AtMost doubleText
boundOf DoubleTan = AtMost doubleText
boundOf DoubleASin = AtMost doubleText
boundOf DoubleACos = AtMost doubleText
boundOf DoubleATan = AtMost doubleText
boundOf DoubleSqrt = AtMost doubleText
boundOf DoubleFloor = AtMost doubleText
boundOf DoubleCeiling = AtMost doubleText
boundOf (Cast _ IntegerType) =
  Summed (TwoToThe (Multiplied (AtMost 4) (ArgumentSize FZ))) (TwoToThe (AtMost 1024))
boundOf (Cast _ StringType) = Summed (ArgumentSize FZ) (AtMost 1)
boundOf (Cast _ CharType) = AtMost 0
boundOf (Cast _ DoubleType) = AtMost doubleText
boundOf (Cast _ WorldType) = AtMost 0
boundOf (Cast _ _) = Summed (ArgumentSize FZ) fixedWidth
boundOf BelieveMe = ArgumentSize (FS (FS FZ))
boundOf Crash = AtMost 0

||| The bound on a primitive's result at its arguments' sizes.
public export
0 resultBound : PrimFn arity -> Vect arity Nat -> Nat
resultBound op ss = atSizes (boundOf op) ss

||| Each size of one list is at most the one at its place in the other.
public export
data SizesWithin : Vect n Nat -> Vect n Nat -> Type where
  NoSizes : SizesWithin [] []
  SizeWithin : Nat.LTE s t -> SizesWithin ss ts -> SizesWithin (s :: ss) (t :: ts)

0 withinAt : (i : Fin n) -> SizesWithin ss ts -> Nat.LTE (Vect.index i ss) (Vect.index i ts)
withinAt FZ (SizeWithin le _) = le
withinAt (FS i) (SizeWithin _ rest) = withinAt i rest

0 timesMonotone : Nat.LTE a b -> Nat.LTE c d -> Nat.LTE (a * c) (b * d)
timesMonotone LTEZero _ = LTEZero
timesMonotone (LTESucc ab) cd = plusLteMonotone cd (timesMonotone ab cd)

0 twoToPositive : (n : Nat) -> Nat.LTE 1 (power 2 n)
twoToPositive Z = reflexive
twoToPositive (S k) = transitive (twoToPositive k) (lteAddRight {m = power 2 k + 0} (power 2 k))

0 twoToMonotone : Nat.LTE m n -> Nat.LTE (power 2 m) (power 2 n)
twoToMonotone {n} LTEZero = twoToPositive n
twoToMonotone (LTESucc le) = timesMonotone (reflexive {x = 2}) (twoToMonotone le)

0 atSizesMonotone : (b : SizeBound n) -> SizesWithin ss ts -> Nat.LTE (atSizes b ss) (atSizes b ts)
atSizesMonotone (AtMost k) _ = reflexive
atSizesMonotone (ArgumentSize i) within = withinAt i within
atSizesMonotone (Summed a b) within = plusLteMonotone (atSizesMonotone a within) (atSizesMonotone b within)
atSizesMonotone (Multiplied a b) within = timesMonotone (atSizesMonotone a within) (atSizesMonotone b within)
atSizesMonotone (TwoToThe a) within = twoToMonotone (atSizesMonotone a within)

||| A primitive's bound grows with its arguments' sizes, so a bound on what
||| its arguments can be bounds what it computes.
export
0 resultBoundMonotone : (op : PrimFn arity) -> SizesWithin ss ts ->
                        Nat.LTE (resultBound op ss) (resultBound op ts)
resultBoundMonotone op within = atSizesMonotone (boundOf op) within

||| What the evaluator's table computes from constants stays within the
||| primitive's bound at their sizes (`boundOf`). The table applies the
||| primitive of the host that runs this compiler, so this is a fact of
||| each host: of idris-mlir's runtime, whose fixed-width results are of
||| their width and whose shift of an integer by a negative amount moves it
||| the other way; and of Chez Scheme, under the stock host, whose integers
||| are exact, whose fixed-width arithmetic wraps, whose shift right of any
||| width does not, and whose cast from String reads what Scheme reads. No
||| operation of the table reads anything but its arguments (none reads the
||| clock or the world), so none is left out.
export
0 computedWithin : {arity : Nat} -> (op : PrimFn arity) -> (cs : Vect arity Constant) ->
                   tableOf op cs = Just c -> Nat.LTE (constantSize c) (resultBound op (map constantSize cs))
computedWithin _ _ _ = trusted

------------------------------------------------------------------------------
-- Full names
------------------------------------------------------------------------------

||| A name as `toFullNames` makes it full: a resolved name is the full name
||| of the definition at its entry, where there is one; any other name
||| stays. Over the frozen context it is a function, so the statement that
||| making names full only renames is this definition.
public export
fullNameIn : Frozen -> Name -> Name
fullNameIn ctx (Resolved i) = maybe (Resolved i) fullname (IntMap.lookup i (entriesOf ctx))
fullNameIn ctx n = n

||| An unknown's name as `toFullNames` makes it full: the full name of the
||| definition at its index, where there is one.
public export
metaNameIn : Frozen -> Name -> Int -> Name
metaNameIn ctx m i = maybe m fullname (IntMap.lookup i (entriesOf ctx))

mutual
  ||| A term with every name full, as `toFullNames` makes it: each name a
  ||| reference, an unknown or a universe holds renamed, nothing else
  ||| changed.
  public export
  fullNamesIn : Frozen -> Term vars -> Term vars
  fullNamesIn ctx (Local fc l idx p) = Local fc l idx p
  fullNamesIn ctx (Ref fc nt n) = Ref fc nt (fullNameIn ctx n)
  fullNamesIn ctx (Meta fc m i args) = Meta fc (metaNameIn ctx m i) i (fullNamesAllIn ctx args)
  fullNamesIn ctx (Bind fc x b sc) = Bind fc x (fullNamesBinderIn ctx b) (fullNamesIn ctx sc)
  fullNamesIn ctx (App fc f a) = App fc (fullNamesIn ctx f) (fullNamesIn ctx a)
  fullNamesIn ctx (As fc s n t) = As fc s (fullNamesIn ctx n) (fullNamesIn ctx t)
  fullNamesIn ctx (TDelayed fc r t) = TDelayed fc r (fullNamesIn ctx t)
  fullNamesIn ctx (TDelay fc d ty a) = TDelay fc d (fullNamesIn ctx ty) (fullNamesIn ctx a)
  fullNamesIn ctx (TForce fc r t) = TForce fc r (fullNamesIn ctx t)
  fullNamesIn ctx (PrimVal fc c) = PrimVal fc c
  fullNamesIn ctx (Erased fc Placeholder) = Erased fc Placeholder
  fullNamesIn ctx (Erased fc Impossible) = Erased fc Impossible
  fullNamesIn ctx (Erased fc (Dotted t)) = Erased fc (Dotted (fullNamesIn ctx t))
  fullNamesIn ctx (TType fc u) = TType fc (fullNameIn ctx u)

  public export
  fullNamesAllIn : Frozen -> List (Term vars) -> List (Term vars)
  fullNamesAllIn ctx [] = []
  fullNamesAllIn ctx (t :: ts) = fullNamesIn ctx t :: fullNamesAllIn ctx ts

  public export
  fullNamesBinderIn : Frozen -> Binder (Term vars) -> Binder (Term vars)
  fullNamesBinderIn ctx (Lam fc c p ty) = Lam fc c (fullNamesPiIn ctx p) (fullNamesIn ctx ty)
  fullNamesBinderIn ctx (Let fc c val ty) = Let fc c (fullNamesIn ctx val) (fullNamesIn ctx ty)
  fullNamesBinderIn ctx (Pi fc c p ty) = Pi fc c (fullNamesPiIn ctx p) (fullNamesIn ctx ty)
  fullNamesBinderIn ctx (PVar fc c p ty) = PVar fc c (fullNamesPiIn ctx p) (fullNamesIn ctx ty)
  fullNamesBinderIn ctx (PLet fc c val ty) = PLet fc c (fullNamesIn ctx val) (fullNamesIn ctx ty)
  fullNamesBinderIn ctx (PVTy fc c ty) = PVTy fc c (fullNamesIn ctx ty)

  public export
  fullNamesPiIn : Frozen -> PiInfo (Term vars) -> PiInfo (Term vars)
  fullNamesPiIn ctx Implicit = Implicit
  fullNamesPiIn ctx Explicit = Explicit
  fullNamesPiIn ctx AutoImplicit = AutoImplicit
  fullNamesPiIn ctx (DefImplicit t) = DefImplicit (fullNamesIn ctx t)

------------------------------------------------------------------------------
-- Full names tell entries apart
------------------------------------------------------------------------------

-- Idris makes each definition under the full name it records (`newDef`,
-- `addBuiltin`) and gives a name one entry, the one made for it first
-- (`getPosition`), and a definition decoded from a TTC keeps the full name
-- it was saved under: so two entries hold definitions of two full names,
-- and no definition records a resolved name as its full name.
0 oneEntryPerName : {0 ctx : Frozen} -> {0 i, j : Int} ->
                    IntMap.lookup i (entriesOf ctx) = Just d -> IntMap.lookup j (entriesOf ctx) = Just d' ->
                    fullname d = fullname d' -> i = j
oneEntryPerName _ _ _ = trusted

0 fullNameUnresolved : {0 ctx : Frozen} -> {0 i : Int} ->
                       IntMap.lookup i (entriesOf ctx) = Just d -> Not (fullname d = Resolved k)
fullNameUnresolved _ _ = trusted

0 resolvedInjective : Resolved i = Resolved j -> i = j
resolvedInjective Refl = Refl

-- Two resolved names whose full names agree, read through what their
-- entries hold: two definitions, one, or none.
0 sameByFullName : {0 ctx : Frozen} -> {0 i, j : Int} -> (m, m' : Maybe GlobalDef) ->
                   IntMap.lookup i (entriesOf ctx) = m -> IntMap.lookup j (entriesOf ctx) = m' ->
                   maybe (Resolved i) fullname m = maybe (Resolved j) fullname m' -> i = j
sameByFullName (Just d) (Just d') found found' same = oneEntryPerName {ctx} {i} {j} found found' same
sameByFullName (Just d) Nothing found _ same = void (fullNameUnresolved {ctx} {i} found same)
sameByFullName Nothing (Just d') _ found' same = void (fullNameUnresolved {ctx} {i = j} found' (sym same))
sameByFullName Nothing Nothing _ _ same = resolvedInjective same

||| Two resolved names that name one entry have one full name: a resolved
||| name resolves to its own entry, so two that share an entry are one.
export
0 sameEntryFullName : SameEntry ctx (Resolved i) (Resolved j) ->
                      fullNameIn ctx (Resolved i) = fullNameIn ctx (Resolved j)
sameEntryFullName (OneEntry r r') =
  cong (\k => fullNameIn ctx (Resolved k))
       (trans (resolvesOnce resolvedItself r) (sym (resolvesOnce resolvedItself r')))

||| Two resolved names whose full names agree name one entry, since the
||| context makes one entry for each full name and records no resolved name
||| as one.
export
0 fullNameSameEntry : fullNameIn ctx (Resolved i) = fullNameIn ctx (Resolved j) ->
                      SameEntry ctx (Resolved i) (Resolved j)
fullNameSameEntry same =
  rewrite sameByFullName {ctx} {i} {j} _ _ Refl Refl same in OneEntry resolvedItself resolvedItself

------------------------------------------------------------------------------
-- The operations
------------------------------------------------------------------------------

-- Every entry from `i` on, `left` of them, as Idris's lookup reads each:
-- the evaluator's own lookup, so the frozen definitions are the ones it
-- reads. An entry still coded is decoded here, once, and the table keeps
-- it decoded, so the evaluator reads the definition frozen.
covering
entriesFrom : Context -> (left : Nat) -> Int -> IntMap GlobalDef -> Core (IntMap GlobalDef)
entriesFrom gam Z i acc = pure acc
entriesFrom gam (S left) i acc
    = do Just d <- lookupCtxtExact (Resolved i) gam
           | Nothing => entriesFrom gam left (i + 1) acc
         entriesFrom gam left (i + 1) (IntMap.insert i d acc)

-- The context as it is, frozen: every entry it has made, and the
-- reference the normalisers run the evaluator with, the live context read
-- here once and never again.
covering
frozenContext : {auto c : Ref Ctxt Defs} -> Core Frozen
frozenContext
    = do defs <- get Ctxt
         let gam = gamma defs
         entries <- entriesFrom gam (integerToNat (cast (nextEntry gam))) 0 IntMap.empty
         MkFrozen defs entries <$> newRef Ctxt defs

||| The operations of Idris's compiler whose termination a program over it
||| takes on trust, each named as this compiler names it.
public export
record Host where
  constructor MkHost

  -- The context, frozen once it is complete.

  ||| Every entry of the context, as `Core.Context.lookupCtxtExact` reads
  ||| it, with the definitions record: called once, after the program and
  ||| everything it imports are loaded, the context changed no more.
  freezeContext : {auto c : Ref Ctxt Defs} -> Core Frozen

  -- The evaluator: Idris's theory is not strongly normalizing, so a
  -- normal form is trusted to exist; every caller first proves that each
  -- definition its term refers to ends, which is what that trust rests on.
  -- Each gives a closed term's normal form in the frozen context, and runs
  -- on it alone, with the steps that reach it and the evidence that it is
  -- normal.

  ||| `Core.Normalise.normalise`.
  normalise : (ctx : Frozen) -> (t : ClosedTerm) -> Core (Reduct OfNormalise ctx t)
  ||| `Core.Normalise.normaliseTypes`.
  normaliseTypes : (ctx : Frozen) -> (t : ClosedTerm) -> Core (Reduct OfNormaliseTypes ctx t)
  ||| `Core.Normalise.normaliseHoles`.
  normaliseHoles : (ctx : Frozen) -> (t : ClosedTerm) -> Core (Reduct OfNormaliseHoles ctx t)
  ||| `Core.Normalise.normaliseAll`, every definition unfolded whatever its
  ||| visibility.
  normaliseAll : (ctx : Frozen) -> (t : ClosedTerm) -> Core (Reduct OfNormaliseAll ctx t)

  -- A definition's terms, through the context's accessors, each here
  -- until the accessor is total.

  ||| `Core.Context.typeOf`, with the evidence a step that reads the type
  ||| holds.
  typeOf : (d : GlobalDef) -> Core (Subset ClosedTerm (TypeOf d))
  ||| `Core.Context.treeOf`, with the evidence a step that walks the tree
  ||| holds.
  treeOf : {args : Scope} -> (body : Body args) -> Core (Subset (CaseTree args) (TreeOf body))

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
||| stated once: each of these returns, and what the evaluator gives and
||| the accessors read is what the module's statements say.
export
host : Host
host = assert_total (MkHost
  { freezeContext = frozenContext
  , normalise = reduct normalise
  , normaliseTypes = reduct normaliseTypes
  , normaliseHoles = reduct normaliseHoles
  , normaliseAll = reduct normaliseAll
  , typeOf = \d => (\ty => Element ty ReadType) <$> typeOf d
  , treeOf = \body => (\tree => Element tree ReadTree) <$> treeOf body
  , checkTerminating
  , buildMain
  , processPackageOpts
  , emitError
  })
